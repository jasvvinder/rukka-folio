// The members feature's door to the server: the meta pull of 05 §5 and the
// three invite routes 06 §7 needs (ADR 2026-09-05d §9 🔒).
//
// ⚠️ WIRE — the contract is `server/supabase/functions/sync-meta/index.ts`
// (route table in its `invites` block) and the suite that pins it,
// `server/functions/_tests/invites_route.test.ts`. Everything marked ⚠️ WIRE
// mirrors that file and must change in step with it:
//   • GET  `sync-meta/`                 → the meta pull; every table the
//     reader may see, `signed_records`, `next`, `has_more` (parsed by
//     `sync_engine`'s [MetaResponse]; `invites` and `verification_events`
//     ride in its `extra`, untouched — rule 6);
//   • POST `sync-meta/invites` `{record, phone}` → `{invite_id, record_id,
//     seq}`; the plaintext number travels **once** and is stored nowhere
//     (ADR 2026-09-05c §4);
//   • GET  `sync-meta/invites`          → `{invites:[{invite_id, tenant_id,
//     roles, expires_at, created_by}]}` — only those addressed to *my*
//     OTP-verified number;
//   • POST `sync-meta/invites/accept` `{invite_id}` → `{invite_id, status}`;
//   • POST `sync-meta/records` `{records:[…]}` → `{results:[{id, result}]}`;
//   • refusals by name: 403 `invite_not_for_you` · 403 `not_admin` · 403
//     `unauthorized` · 409 `invite_not_live` · 409 `record_replayed` · 409
//     `no_record` · 410 `invite_expired` · 400 `bad_phone` / `bad_record`.
//
// **`invite_not_for_you` is the whole of C-05d-9:** the server answers a
// wrong number and an invite id that does not exist with byte-identical
// bodies, so the route is no oracle for who was invited. This client keeps
// that property — it has exactly one failure for both and never asks a
// second question to tell them apart.
//
// Nothing here logs: bodies carry phone numbers and access tokens (rule 4).
import 'dart:convert';

import 'package:sync_engine/sync_engine.dart' show MetaResponse;

import 'members_repository.dart';

/// A minimal response: status and UTF-8 body — the same two-field shape
/// `features/auth`'s [AuthHttpResponse] uses, for the same reason (the HTTP
/// package is wired at integration, not here).
final class MembersHttpResponse {
  /// Creates a response.
  const MembersHttpResponse(this.statusCode, this.body);

  /// HTTP status.
  final int statusCode;

  /// UTF-8 body, possibly empty.
  final String body;
}

/// Thrown by a [MembersTransport] when the request never reached a response
/// (no network, DNS, TLS, timeout). The API maps it to
/// [MembersRefusal.offline] — never to a refusal that would claim the server
/// said something.
final class MembersTransportException implements Exception {
  /// Creates the exception.
  const MembersTransportException([this.cause]);

  /// What went wrong, for the caller's own handling. Never logged.
  final Object? cause;

  @override
  String toString() => 'MembersTransportException';
}

/// GET/POST JSON with a bearer token. Implementations must throw
/// [MembersTransportException] on transport failure and never log a body.
abstract class MembersTransport {
  /// GET [url].
  Future<MembersHttpResponse> get(
    Uri url, {
    required Map<String, String> headers,
  });

  /// POST [body] (already JSON) to [url].
  Future<MembersHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  });
}

/// Route table under the edge-functions root (⚠️ WIRE sync-meta/index.ts).
final class MembersEndpoints {
  /// Creates the table from the functions root (`…/functions/v1/`).
  MembersEndpoints(Uri functionsRoot)
    : base = functionsRoot.path.endsWith('/')
          ? functionsRoot
          : functionsRoot.replace(path: '${functionsRoot.path}/');

  /// Slash-terminated root, so `resolve` appends rather than replaces.
  final Uri base;

  /// The function every members route lives under.
  static const String function = 'sync-meta';

  Uri _sub(String path) => base.resolve('$function/$path');

  /// The meta pull (05 §5); `after` is the opaque cursor.
  Uri meta(String? after) => after == null
      ? _sub('')
      : _sub('').replace(queryParameters: {'after': after});

  /// `POST` issue / `GET` my offers (06 §7).
  Uri get invites => _sub('invites');

  /// Accept one offer (ADR 2026-09-05d §9).
  Uri get acceptInvite => _sub('invites/accept');

  /// The generic signed-record route (ADR 2026-09-05b §1).
  Uri get records => _sub('records');
}

/// An invite offered to *this* phone (06 §7). Carries no `invitee_hmac`, no
/// nonce and no number — the server hands the joiner only what it must.
final class InviteOffer {
  /// Creates an offer.
  const InviteOffer({
    required this.inviteId,
    required this.tenantId,
    required this.roles,
    required this.expiresAt,
    required this.createdBy,
  });

  /// Decodes one wire row (⚠️ WIRE sync-meta `invites` GET).
  factory InviteOffer.fromJson(Map<String, Object?> j) => InviteOffer(
    inviteId: j['invite_id']! as String,
    tenantId: j['tenant_id']! as String,
    roles: [
      for (final r in (j['roles'] as List<Object?>? ?? const []))
        if (r is Map) r.cast<String, Object?>(),
    ],
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      (j['expires_at']! as num).toInt(),
    ),
    createdBy: j['created_by'] as String?,
  );

  /// The invite's id — what [MembersApi.acceptInvite] takes.
  final String inviteId;

  /// Which tenant is offering.
  final String tenantId;

  /// `[{book_id, role, auto_post_limit_paise?}]` as the admin signed it.
  final List<Map<String, Object?>> roles;

  /// When the 7-day window closes (06 §7).
  final DateTime expiresAt;

  /// The admin who sent it, by user id. Their *name* is not the server's to
  /// know (ADR 2026-09-05c §4).
  final String? createdBy;
}

/// What issuing an invite returns.
final class IssuedInvite {
  /// Creates the result.
  const IssuedInvite({required this.inviteId, required this.recordId});

  /// The new invite row.
  final String inviteId;

  /// The signed `invite` record it projects (06 §7, ADR 2026-09-05b §1).
  final String recordId;
}

/// The server's side of the members feature.
abstract class MembersApi {
  /// One page of the meta pull; `after` continues a previous page.
  Future<MetaResponse> pullMeta({String? after});

  /// Issues an invite: the admin's signed `invite` record plus the invitee's
  /// number, which travels once and is kept nowhere (ADR 2026-09-05c §4).
  Future<IssuedInvite> issueInvite({
    required Map<String, Object?> record,
    required String phoneE164,
  });

  /// The invites addressed to this device's OTP-verified number.
  Future<List<InviteOffer>> myInvites();

  /// Accepts one. Returns the membership status the server moved to —
  /// `joined_pending_verification`, never `active`: the ceremony grants that.
  Future<String> acceptInvite(String inviteId);

  /// Posts signed records (role, limit, designation changes) and returns the
  /// apply note per record, in order.
  Future<List<String>> postRecords(List<Map<String, Object?>> records);
}

/// [MembersApi] over the edge functions.
final class HttpMembersApi implements MembersApi {
  /// Creates the client. [accessToken] yields the 15-minute JWT of 06 §4;
  /// [clientVersion] rides the `x-rukka-client-version` header so a build
  /// below the floor is told to upgrade rather than failing obscurely.
  HttpMembersApi({
    required MembersTransport transport,
    required Uri functionsRoot,
    required Future<String?> Function() accessToken,
    String? clientVersion,
  }) : _http = transport,
       _endpoints = MembersEndpoints(functionsRoot),
       _token = accessToken,
       _version = clientVersion;

  final MembersTransport _http;
  final MembersEndpoints _endpoints;
  final Future<String?> Function() _token;
  final String? _version;

  /// ⚠️ WIRE `_shared/http.ts` CLIENT_VERSION_HEADER.
  static const String clientVersionHeader = 'x-rukka-client-version';

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const MembersFailure('no session', MembersRefusal.unauthorized);
    }
    return {
      'authorization': 'Bearer $token',
      if (json) 'content-type': 'application/json',
      if (_version != null) clientVersionHeader: _version,
    };
  }

  @override
  Future<MetaResponse> pullMeta({String? after}) async {
    final body = await _send(
      () async => _http.get(_endpoints.meta(after), headers: await _headers()),
    );
    return MetaResponse.fromJson(body);
  }

  @override
  Future<IssuedInvite> issueInvite({
    required Map<String, Object?> record,
    required String phoneE164,
  }) async {
    final body = await _send(
      () async => _http.post(
        _endpoints.invites,
        headers: await _headers(json: true),
        // The number is in this body and nowhere else on this device's side
        // of the wire: it is not stored, not retried from a queue, not logged.
        body: jsonEncode({'record': record, 'phone': phoneE164}),
      ),
    );
    return IssuedInvite(
      inviteId: body['invite_id']! as String,
      recordId: body['record_id']! as String,
    );
  }

  @override
  Future<List<InviteOffer>> myInvites() async {
    final body = await _send(
      () async => _http.get(_endpoints.invites, headers: await _headers()),
    );
    return [
      for (final r in (body['invites'] as List<Object?>? ?? const []))
        InviteOffer.fromJson((r! as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<String> acceptInvite(String inviteId) async {
    final body = await _send(
      () async => _http.post(
        _endpoints.acceptInvite,
        headers: await _headers(json: true),
        body: jsonEncode({'invite_id': inviteId}),
      ),
    );
    return body['status']! as String;
  }

  @override
  Future<List<String>> postRecords(List<Map<String, Object?>> records) async {
    final body = await _send(
      () async => _http.post(
        _endpoints.records,
        headers: await _headers(json: true),
        body: jsonEncode({'records': records}),
      ),
    );
    return [
      for (final r in (body['results'] as List<Object?>? ?? const []))
        ((r! as Map).cast<String, Object?>()['result'] as String?) ?? '',
    ];
  }

  /// Runs one request and turns anything but 2xx into a named
  /// [MembersFailure]. A transport that never answered is
  /// [MembersRefusal.offline] — the one refusal that does not claim the
  /// server spoke.
  Future<Map<String, Object?>> _send(
    Future<MembersHttpResponse> Function() run,
  ) async {
    final MembersHttpResponse res;
    try {
      res = await run();
    } on MembersFailure {
      rethrow;
    } on Exception catch (_) {
      throw const MembersFailure('offline', MembersRefusal.offline);
    }
    Map<String, Object?> body = const {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) body = decoded.cast<String, Object?>();
      } on FormatException {
        body = const {};
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    throw MembersFailure(
      'http ${res.statusCode}',
      refusalOf(body['error'] as String?, res.statusCode),
    );
  }
}

/// Maps a server `error` name onto the client's refusal (⚠️ WIRE
/// `inviteError` in sync-meta/index.ts). An unknown name is
/// [MembersRefusal.server] — never guessed into something friendlier.
MembersRefusal refusalOf(String? error, int status) => switch (error) {
  // ADR 2026-09-05d §9 🔒 — one refusal for "not your number" and "no such
  // invite", exactly as the server answers both identically.
  'invite_not_for_you' => MembersRefusal.inviteNotForYou,
  'invite_expired' => MembersRefusal.inviteExpired,
  'invite_not_live' => MembersRefusal.inviteNotLive,
  'not_admin' => MembersRefusal.notAdmin,
  'unauthorized' || 'forbidden' => MembersRefusal.unauthorized,
  'record_replayed' => MembersRefusal.recordReplayed,
  'no_record' => MembersRefusal.noRecord,
  'bad_phone' => MembersRefusal.badPhone,
  'bad_record' || 'bad_request' => MembersRefusal.badRecord,
  'unknown_tenant' => MembersRefusal.unknownTenant,
  'upgrade_required' => MembersRefusal.upgradeRequired,
  'tenant_frozen' || 'rejected:tenant_frozen' => MembersRefusal.tenantFrozen,
  _ => status == 401 ? MembersRefusal.unauthorized : MembersRefusal.server,
};
