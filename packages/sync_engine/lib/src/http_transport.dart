// The real [SyncTransport]: HTTPS + JSON over `package:http` against the three
// deployed edge functions (05 §1 transport, §3 push, §4 pull, §5 meta).
//
// `server/supabase/functions/sync-push | sync-pull | sync-meta` ARE the
// contract; this file is the client half of it and `test/http_transport_test
// .dart` is the place wire drift is supposed to fail. Everything it knows
// about the server is pinned to a named line over there:
//
//   * routes          — one edge function per route, `sync-meta` also serving
//                       sub-paths through `_shared/http.ts` `subPath`;
//   * auth            — `Authorization: Bearer <15-min access JWT>` (06 §4
//                       step 2), verified by `_shared/claims.ts`;
//   * version gate    — `x-rukka-client-version` (`_shared/http.ts`
//                       CLIENT_VERSION_HEADER). **Sending it is not optional:**
//                       `belowMinVersion(null, min)` is `true`, so a request
//                       without the header is answered 426 by every sync route;
//   * errors          — `{error, detail?}`, 426 adding `min_client_version`,
//                       mapped by [TransportFailure.fromHttp];
//   * bytes           — base64url, unpadded out of Deno, either alphabet and
//                       any padding accepted back in (`_shared/bytes.ts`
//                       `b64any`); `wire.dart` matches on both directions.
//
// Purity: no `dart:io`, no clock, no RNG. The `http.Client`, the session
// credential and the TLS chain all arrive injected, so `MockClient` drives the
// whole file in `dart test` and nothing here opens a socket by itself.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'spki_pins.dart';
import 'transport.dart';
import 'wire.dart';

/// Route table under the edge-functions root (`…/functions/v1/`). One function
/// per sync route; `sync-meta` also answers the sub-paths `/records` (ADR 05b
/// §1) and `/invites`, `/invites/accept` (06 §7) through `_shared/http.ts`
/// `subPath`.
final class SyncEndpoints {
  /// Creates the table under [functionsRoot], slash-terminating it so
  /// [Uri.resolve] appends a segment rather than replacing the last one.
  SyncEndpoints(Uri functionsRoot)
    : base = functionsRoot.path.endsWith('/')
          ? functionsRoot
          : functionsRoot.replace(path: '${functionsRoot.path}/');

  /// The edge-functions root, always slash-terminated.
  final Uri base;

  /// `POST` — 05 §3.
  Uri get push => base.resolve('sync-push');

  /// `GET` — 05 §4.
  Uri get pull => base.resolve('sync-pull');

  /// `GET` — 05 §5.
  Uri get meta => base.resolve('sync-meta');

  /// `POST` — signed records (ADR 05b §1).
  Uri get records => base.resolve('sync-meta/records');

  /// `POST` to issue, `GET` to list — 06 §7 invites.
  Uri get invites => base.resolve('sync-meta/invites');

  /// `POST` — accept an invite (06 §7).
  Uri get acceptInvite => base.resolve('sync-meta/invites/accept');
}

/// The session credential the transport carries (06 §4): a 15-minute access
/// JWT the identity client mints and refreshes. The transport never mints,
/// stores or inspects it — it asks for one per request and hands back the 401.
abstract interface class SyncCredentials {
  /// The current access token, refreshed by the implementation when it is
  /// close to expiry. Throwing means there is no live session.
  Future<String> accessToken();

  /// Called when the server answered 401, so the next call fetches a fresh
  /// token instead of replaying the rejected one. Never a logout: a plain 401
  /// is a refresh problem, not a fact about the device (ADR 05b §2).
  Future<void> invalidate();
}

/// A fixed token, for tests and local development.
final class StaticSyncCredentials implements SyncCredentials {
  /// Creates the credential.
  StaticSyncCredentials(this.token);

  /// The bearer token handed to every request.
  String token;

  /// How many times [invalidate] was called.
  int invalidations = 0;

  @override
  Future<String> accessToken() async => token;

  @override
  Future<void> invalidate() async => invalidations++;
}

/// The TLS chain the platform presented for a connection, as SHA-256 SPKI
/// digests, leaf → root — the one input [SpkiPins] needs (05 §1, ADR
/// 2026-09-05 §1).
///
/// Pure Dart cannot see a socket, so the host supplies this: the app's
/// `dart:io` client reports the chain of the connection it will use for [url]
/// (`SecurityContext` / `badCertificateCallback` / `connectionFactory`), and
/// the transport asks the pin set. Returning `null` — "I do not know what was
/// presented" — is a **failure**, not a pass: pin failure is a hard fail with
/// no fallback and no override.
abstract interface class TlsChainSource {
  /// The SPKI digests for [url]'s connection, or null when none is known.
  Future<List<Uint8List>?> spkiSha256(Uri url);
}

/// A chain source that always answers with the same digests (tests, and the
/// local-dev build where the pin set is disabled anyway).
final class StaticTlsChainSource implements TlsChainSource {
  /// Creates the source over [chain].
  StaticTlsChainSource(this.chain);

  /// What every connection is said to have presented; null fails the pin.
  List<Uint8List>? chain;

  /// Every url asked about, in order.
  final List<Uri> asked = [];

  @override
  Future<List<Uint8List>?> spkiSha256(Uri url) async {
    asked.add(url);
    return chain;
  }
}

/// Codes this client puts on a [TransportFailure] it raised itself rather than
/// read off the wire. They are never server codes; nothing on the server emits
/// them.
abstract final class ClientFailureCode {
  /// [AuthFailed] — [SyncCredentials.accessToken] threw: no live session.
  /// A plain 401-shaped failure, so the engine backs off and retries rather
  /// than treating it as a fact about the device.
  static const String noSession = 'no_session';

  /// [RouteRefused] — a 2xx whose body was not the JSON this route promises.
  /// Route-level: cursors and outbox rows stay exactly where they were.
  static const String malformedResponse = 'malformed_response';

  /// [PinFailed] detail — the presented chain matched no pin, or no chain was
  /// reported at all.
  static const String pinFailed = 'spki_pin_failed';
}

/// `SyncTransport` over HTTPS (05 §1). See the file comment for the contract.
///
/// A pin failure is 05 §1's "hard fail with no fallback and no override":
/// this build raises [PinFailed] with detail [ClientFailureCode.pinFailed],
/// the round stops, nothing is sent, nothing is believed and no cursor moves.
/// The user sees *Needs attention* → Inbox, never *Offline* — settled by
/// ADR 2026-09-15 §7 🔒, which the M7-Y2 lane report had left to the owner.
///
/// ⚠️ SPEC 05 §1 also asks for gzip on the request body. `package:http` and the
/// platform client negotiate gzip on responses; compressing a request body
/// needs `dart:io`'s `GZipCodec`, which this package may not import. Payloads
/// are ciphertext and incompressible, so the loss is metadata overhead only.
final class HttpSyncTransport implements FullSyncTransport {
  /// Creates the transport.
  ///
  /// Throws [ArgumentError] when [pins] is a live pin set and no
  /// [tlsChainSource] is given — a build that talks to a hosted environment
  /// cannot opt out of pinning (05 §1).
  HttpSyncTransport({
    required this.client,
    required Uri functionsRoot,
    required this.credentials,
    required this.clientVersion,
    required this.pins,
    TlsChainSource? tlsChainSource,
    this.timeout = const Duration(seconds: 30),
    Map<String, String> extraHeaders = const {},
  }) : endpoints = SyncEndpoints(functionsRoot),
       tlsChainSource = tlsChainSource,
       extraHeaders = Map.unmodifiable(extraHeaders) {
    if (!pins.localDevDisabled && tlsChainSource == null) {
      throw ArgumentError.notNull('tlsChainSource');
    }
  }

  /// Request header carrying the build version (`_shared/http.ts`
  /// CLIENT_VERSION_HEADER). Absent ⇒ 426 from every sync route.
  static const String clientVersionHeader = 'x-rukka-client-version';

  /// The injected HTTP client (`MockClient` in tests).
  final http.Client client;

  /// The three routes.
  final SyncEndpoints endpoints;

  /// The session credential (06 §4).
  final SyncCredentials credentials;

  /// This build's version, sent on every request.
  final String clientVersion;

  /// The pin set (05 §1).
  final SpkiPins pins;

  /// Where the presented chain comes from; null only for a local-dev pin set.
  final TlsChainSource? tlsChainSource;

  /// Per-request deadline; expiry is a network condition ⇒ [TransportOffline].
  final Duration timeout;

  /// Static headers the deployment needs (a gateway `apikey`, say). Never a
  /// credential the routes themselves read.
  final Map<String, String> extraHeaders;

  @override
  Future<PushResponse> push(PushRequest request) async {
    final body = await _post(endpoints.push, 'push', request.toJson());
    return _decode('push', () => PushResponse.fromJson(body));
  }

  @override
  Future<PullResponse> pull(PullRequest request) async {
    final url = endpoints.pull.replace(
      queryParameters: <String, String>{
        'book_id': request.bookId,
        'after_seq': '${request.afterSeq}',
        'limit': '${request.limit}',
        if (request.fy != null) 'fy': request.fy!,
        if (request.objectTypes != null && request.objectTypes!.isNotEmpty)
          'object_types': request.objectTypes!.join(','),
      },
    );
    final body = await _get(url, 'pull');
    return _decode('pull', () => PullResponse.fromJson(body));
  }

  @override
  Future<MetaResponse> meta(MetaRequest request) async {
    final after = request.after;
    final url = after == null
        ? endpoints.meta
        : endpoints.meta.replace(
            queryParameters: <String, String>{'after': after},
          );
    final body = await _get(url, 'meta');
    return _decode('meta', () => MetaResponse.fromJson(body));
  }

  // ── the write half of /sync-meta (ADR 05b §1, 06 §7) ──────────────────────

  @override
  Future<PostRecordsResponse> postRecords(PostRecordsRequest request) async {
    // The batch cap is the server's (`RECORDS_BATCH_MAX`), and it refuses the
    // batch WHOLE: raising it here rather than posting keeps a caller that
    // over-filled from believing a partial apply happened. `readJson` also
    // caps the body at 1 MB by `content-length` — a body over it is a plain
    // 400, so the caller splits on count and stays far below it.
    if (request.records.length > PostRecordsRequest.batchMax) {
      throw const BatchTooLarge(
        detail: 'max ${PostRecordsRequest.batchMax} records',
      );
    }
    final body = await _post(endpoints.records, 'records', request.toJson());
    return _decode('records', () => PostRecordsResponse.fromJson(body));
  }

  @override
  Future<InviteIssued> createInvite(CreateInviteRequest request) async {
    // `request.phone` is written into this one body and kept nowhere: no
    // field, no log, no retry buffer (rule 4, ADR 2026-09-05c §4).
    final body = await _post(endpoints.invites, 'invites', request.toJson());
    return _decode('invites', () => InviteIssued.fromJson(body));
  }

  @override
  Future<List<WireInviteOffer>> myInvites() async {
    final body = await _get(endpoints.invites, 'invites');
    return _decode('invites', () {
      final rows = (body['invites'] as List<Object?>? ?? const [])
          .cast<Map<String, Object?>>();
      return [for (final r in rows) WireInviteOffer.fromJson(r)];
    });
  }

  @override
  Future<InviteAcceptance> acceptInvite(String inviteId) async {
    final body = await _post(endpoints.acceptInvite, 'invites/accept', {
      'invite_id': inviteId,
    });
    return _decode('invites/accept', () => InviteAcceptance.fromJson(body));
  }

  // ── the one door ──────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _get(Uri url, String route) =>
      _send(url, route, () async {
        final headers = await _headers();
        await _checkPin(url);
        return client.get(url, headers: headers);
      });

  Future<Map<String, Object?>> _post(
    Uri url,
    String route,
    Map<String, Object?> body,
  ) => _send(url, route, () async {
    final headers = await _headers(json: true);
    await _checkPin(url);
    return client.post(url, headers: headers, body: jsonEncode(body));
  });

  /// Runs [call], maps every network condition and every non-2xx answer onto a
  /// [TransportFailure], and returns the parsed 2xx body.
  Future<Map<String, Object?>> _send(
    Uri url,
    String route,
    Future<http.Response> Function() call,
  ) async {
    final http.Response response;
    try {
      response = await call().timeout(timeout);
    } on TransportFailure {
      rethrow; // the pin verdict and a missing session are already typed
    } on Exception catch (e) {
      // `ClientException` (dropped request, dropped response, malformed
      // framing), `SocketException`, `HandshakeException`, `TimeoutException`:
      // all of them are "no connectivity right now" (05 §3 retry).
      throw TransportOffline('$route: ${e.runtimeType}');
    }

    Map<String, Object?>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) body = decoded;
    } on Exception {
      body = null; // an error body we cannot read is still an error status
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        try {
          await credentials.invalidate();
        } on Exception {
          // The credential store's problem, not the route's; the typed 401
          // below is what the engine acts on either way.
        }
      }
      throw TransportFailure.fromHttp(response.statusCode, body);
    }
    if (body == null) {
      throw RouteRefused(
        status: response.statusCode,
        code: ClientFailureCode.malformedResponse,
        detail: route,
      );
    }
    return body;
  }

  Future<Map<String, String>> _headers({bool json = false}) async {
    final String token;
    try {
      token = await credentials.accessToken();
    } on TransportFailure {
      rethrow;
    } on Object {
      // No live session. Shaped like a plain 401 so the engine backs off and
      // retries next round instead of suspending the device.
      throw const AuthFailed(code: ClientFailureCode.noSession);
    }
    return {
      ...extraHeaders,
      'accept': 'application/json',
      'authorization': 'Bearer $token',
      clientVersionHeader: clientVersion,
      if (json) 'content-type': 'application/json; charset=utf-8',
    };
  }

  /// 05 §1 🔒: the presented chain must match a pin, or the request never
  /// leaves. No fallback, no override — a source that cannot say what was
  /// presented fails exactly like a mismatch.
  ///
  /// [PinFailed], never [TransportOffline]: the engine turns it into *Needs
  /// attention* with `pin_failed` rather than telling the user to wait for a
  /// network they may already have (ADR 2026-09-15 §7 🔒).
  Future<void> _checkPin(Uri url) async {
    if (pins.localDevDisabled) return;
    final List<Uint8List>? chain;
    try {
      chain = await tlsChainSource!.spkiSha256(url);
    } on Object {
      throw const PinFailed(ClientFailureCode.pinFailed);
    }
    if (chain == null || pins.check(chain) != PinVerdict.matched) {
      throw const PinFailed(ClientFailureCode.pinFailed);
    }
  }

  /// Wraps a wire decode. A shape this build cannot read is a route-level
  /// refusal, never a silent empty page: the caller stops the route with its
  /// cursor untouched. Only the exception's *type* travels — never a value off
  /// the wire, which could be plaintext-adjacent (rule 4).
  T _decode<T>(String route, T Function() f) {
    try {
      return f();
    } on Object catch (e) {
      throw RouteRefused(
        status: 200,
        code: ClientFailureCode.malformedResponse,
        detail: '$route: ${e.runtimeType}',
      );
    }
  }
}
