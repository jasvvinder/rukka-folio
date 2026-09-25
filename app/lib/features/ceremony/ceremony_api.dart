// The app's door to the **ceremony session relay** — the three opaque values
// of ADR 2026-09-13d ruling 4 🔒 and the two [ShowerSessionRelay] /
// [VerifierSessionRelay] implementations that ride them.
//
// ⚠️ WIRE — the contract is migration
// `server/supabase/migrations/0007_ceremony_sessions.sql` and the `ceremony`
// block of `server/supabase/functions/sync-meta/index.ts`, pinned by
// `server/supabase/functions/_tests/ceremony_relay.test.ts`:
//
//   POST `sync-meta/ceremony`           `{tenant_id, commitment}`       → session
//   POST `sync-meta/ceremony/verifier`  `{session_id, verifier_random}` → session
//   POST `sync-meta/ceremony/opening`   `{session_id, opening}`         → session
//   GET  `sync-meta/ceremony?session_id=…`                              → session
//   GET  `sync-meta/ceremony?subject_user_id=…&tenant_id=…`             → session
//        — the newest UNEXPIRED session for that subject, else 404
//        `no_live_session` (04 §6.4 *delegated*: a verifier holds a user id,
//        never a session id).
//
// A session on the wire is
// `{session_id, tenant_id, subject_user_id, commitment, committed_at,
//   expires_at, verifier_user_id, verifier_random, verifier_random_at,
//   opening, opened_at}` — byte fields unpadded base64url, times ISO-8601.
//
// **Three things this client must never do.**
//
//   1. It never derives, compares or validates a code. The server computes
//      nothing with these bytes (04 §8.6) and neither does this file: grep it
//      for a hash and you will not find one. Every check lives in
//      `core_crypto`'s `SasShower` / `SasVerifier`, which this only carries
//      bytes between.
//   2. It never lets a value out of order. The ordering *is* the security
//      property (0007's header): the opening is written only after `r_V` has
//      arrived, and `r_V` is drawn only once the commitment is in hand. Both
//      relays below expose exactly the ordered interface `ceremony_repository
//      .dart` declares, and the server's guard refuses an out-of-order write
//      anyway — this client cannot loosen it.
//   3. It never measures the lifetime against this phone's clock. The ten
//      minutes of 04 §6.3 run from `committed_at`, the **server's** timestamp,
//      which is what both devices agree on; the injected clock here is used
//      only to decide when to stop polling, never to extend a session.
//
// **Delivery is short polling** (ADR 2026-09-13d Open 2, decided in 0007's
// footer): the two devices GET the session while a ceremony screen is open.
// The poll interval and the sleep are injected so a widget test runs the whole
// exchange without a real delay.
//
// Nothing here logs: a body carries a bearer token, and a session row names
// two people (CLAUDE.md rule 4).
import 'dart:convert';
import 'dart:typed_data';

import '../../shared/seams/http_transport.dart';
import 'ceremony_repository.dart';

/// Route table under the edge-functions root (⚠️ WIRE sync-meta/index.ts).
final class CeremonyEndpoints {
  /// Creates the table from the functions root (`…/functions/v1/`).
  CeremonyEndpoints(Uri functionsRoot)
    : base = functionsRoot.path.endsWith('/')
          ? functionsRoot
          : functionsRoot.replace(path: '${functionsRoot.path}/');

  /// Slash-terminated root, so `resolve` appends rather than replaces.
  final Uri base;

  /// The function every ceremony route lives under.
  static const String function = 'sync-meta';

  /// `POST sync-meta/ceremony` — the invitee opens a session.
  Uri get commit => base.resolve('$function/ceremony');

  /// `POST sync-meta/ceremony/verifier` — the verifier writes `r_V`.
  Uri get verifier => base.resolve('$function/ceremony/verifier');

  /// `POST sync-meta/ceremony/opening` — the invitee reveals `r_S`.
  Uri get opening => base.resolve('$function/ceremony/opening');

  /// `GET sync-meta/ceremony?session_id=…` — either side polls.
  Uri session(String sessionId) =>
      commit.replace(queryParameters: {'session_id': sessionId});

  /// `GET sync-meta/ceremony?subject_user_id=…&tenant_id=…` — the verifier
  /// finds the subject's live session.
  Uri liveSession({required String tenantId, required String subjectUserId}) =>
      commit.replace(
        queryParameters: {
          'subject_user_id': subjectUserId,
          'tenant_id': tenantId,
        },
      );
}

/// One `ceremony_sessions` row as the server shapes it (⚠️ WIRE
/// `sessionToWire`).
///
/// Every field is a *claim*: the server stores and forwards, so nothing here
/// is trusted beyond being the bytes the other device wrote. What makes them
/// safe is the commitment `core_crypto` checks them against, not this class.
final class CeremonySessionWire {
  /// Creates the row.
  CeremonySessionWire({
    required this.sessionId,
    required this.tenantId,
    required this.subjectUserId,
    required Uint8List commitment,
    required this.committedAt,
    required this.expiresAt,
    this.verifierUserId,
    Uint8List? verifierRandom,
    Uint8List? opening,
  }) : commitment = Uint8List.fromList(commitment),
       verifierRandom = verifierRandom == null
           ? null
           : Uint8List.fromList(verifierRandom),
       opening = opening == null ? null : Uint8List.fromList(opening);

  /// Decodes one wire row. Throws [FormatException] on a shape this build
  /// does not understand — a malformed session is not a session.
  factory CeremonySessionWire.fromJson(Map<String, Object?> j) {
    final commitment = _bytes(j['commitment']);
    if (commitment == null) {
      throw const FormatException('ceremony session without a commitment');
    }
    return CeremonySessionWire(
      sessionId: _string(j['session_id'], 'session_id'),
      tenantId: _string(j['tenant_id'], 'tenant_id'),
      subjectUserId: _string(j['subject_user_id'], 'subject_user_id'),
      commitment: commitment,
      committedAt: _time(j['committed_at'], 'committed_at'),
      expiresAt: _time(j['expires_at'], 'expires_at'),
      verifierUserId: j['verifier_user_id'] as String?,
      verifierRandom: _bytes(j['verifier_random']),
      opening: _bytes(j['opening']),
    );
  }

  /// The session's id — what the other three routes take.
  final String sessionId;

  /// The tenant the ceremony belongs to.
  final String tenantId;

  /// Who is being verified (0007: the subject's own certified device wrote
  /// the commitment).
  final String subjectUserId;

  /// The 32 committed bytes.
  final Uint8List commitment;

  /// The server's timestamp on the commitment — 04 §6.3's ten minutes run
  /// from here.
  final DateTime committedAt;

  /// `committed_at + 10 minutes`, stamped by 0007's guard.
  final DateTime expiresAt;

  /// The active member who contributed `r_V`, once one has.
  final String? verifierUserId;

  /// `r_V`, 16 bytes, once the verifier's device has written it.
  final Uint8List? verifierRandom;

  /// `r_S`, 16 bytes, once the invitee's device has revealed it.
  final Uint8List? opening;

  static String _string(Object? v, String field) =>
      v is String ? v : throw FormatException('ceremony session field $field');

  static DateTime _time(Object? v, String field) {
    if (v is String) {
      final t = DateTime.tryParse(v);
      if (t != null) return t.toUtc();
    }
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    }
    throw FormatException('ceremony session field $field');
  }

  static Uint8List? _bytes(Object? v) {
    if (v is! String || v.isEmpty) return null;
    try {
      return base64Url.decode(v.padRight((v.length + 3) & ~3, '='));
    } on FormatException {
      return null;
    }
  }
}

/// The ceremony session relay, as the app calls it.
abstract class CeremonyApi {
  /// `POST sync-meta/ceremony` — opens a session with [commitment].
  Future<CeremonySessionWire> commit({
    required String tenantId,
    required Uint8List commitment,
  });

  /// `POST sync-meta/ceremony/verifier` — writes `r_V`.
  Future<CeremonySessionWire> contribute({
    required String sessionId,
    required Uint8List verifierRandom,
  });

  /// `POST sync-meta/ceremony/opening` — writes `r_S`.
  Future<CeremonySessionWire> reveal({
    required String sessionId,
    required Uint8List opening,
  });

  /// `GET sync-meta/ceremony?session_id=…`; null when the server says 404.
  Future<CeremonySessionWire?> session(String sessionId);

  /// `GET sync-meta/ceremony?subject_user_id=…&tenant_id=…`; null when the
  /// server says `no_live_session` — which it also says for a session this
  /// caller may not see, so null never tells anyone whose ceremony is live.
  Future<CeremonySessionWire?> liveSessionFor({
    required String tenantId,
    required String subjectUserId,
  });
}

/// The production client.
final class HttpCeremonyApi implements CeremonyApi {
  /// Creates the client. [accessToken] yields the 15-minute JWT of 06 §4;
  /// [clientVersion] rides `x-rukka-client-version` (06 §4.5).
  HttpCeremonyApi({
    required RkHttpTransport transport,
    required Uri functionsRoot,
    required Future<String?> Function() accessToken,
    String? clientVersion,
  }) : _http = transport,
       _endpoints = CeremonyEndpoints(functionsRoot),
       _token = accessToken,
       _version = clientVersion;

  /// The header 06 §4.5 names.
  static const String clientVersionHeader = 'x-rukka-client-version';

  final RkHttpTransport _http;
  final CeremonyEndpoints _endpoints;
  final Future<String?> Function() _token;
  final String? _version;

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      // No session is not "the relay refused"; it is this device having
      // nothing to speak with. Offline is false: the server said nothing.
      throw const CeremonyFailure(message: 'unauthorized');
    }
    return {
      'authorization': 'Bearer $token',
      if (json) 'content-type': 'application/json',
      if (_version != null) clientVersionHeader: _version,
    };
  }

  @override
  Future<CeremonySessionWire> commit({
    required String tenantId,
    required Uint8List commitment,
  }) async => CeremonySessionWire.fromJson(
    await _send(
      () async => _http.post(
        _endpoints.commit,
        headers: await _headers(json: true),
        body: jsonEncode({
          'tenant_id': tenantId,
          'commitment': _b64(commitment),
        }),
      ),
    ),
  );

  @override
  Future<CeremonySessionWire> contribute({
    required String sessionId,
    required Uint8List verifierRandom,
  }) async => CeremonySessionWire.fromJson(
    await _send(
      () async => _http.post(
        _endpoints.verifier,
        headers: await _headers(json: true),
        body: jsonEncode({
          'session_id': sessionId,
          'verifier_random': _b64(verifierRandom),
        }),
      ),
    ),
  );

  @override
  Future<CeremonySessionWire> reveal({
    required String sessionId,
    required Uint8List opening,
  }) async => CeremonySessionWire.fromJson(
    await _send(
      () async => _http.post(
        _endpoints.opening,
        headers: await _headers(json: true),
        body: jsonEncode({'session_id': sessionId, 'opening': _b64(opening)}),
      ),
    ),
  );

  @override
  Future<CeremonySessionWire?> session(String sessionId) async {
    try {
      return CeremonySessionWire.fromJson(
        await _send(
          () async => _http.get(
            _endpoints.session(sessionId),
            headers: await _headers(),
          ),
        ),
      );
    } on CeremonyFailure catch (e) {
      if (e.message == 'not_found') return null;
      rethrow;
    }
  }

  @override
  Future<CeremonySessionWire?> liveSessionFor({
    required String tenantId,
    required String subjectUserId,
  }) async {
    try {
      return CeremonySessionWire.fromJson(
        await _send(
          () async => _http.get(
            _endpoints.liveSession(
              tenantId: tenantId,
              subjectUserId: subjectUserId,
            ),
            headers: await _headers(),
          ),
        ),
      );
    } on CeremonyFailure catch (e) {
      if (e.message == 'no_live_session') return null;
      rethrow;
    }
  }

  Future<Map<String, Object?>> _send(
    Future<RkHttpResponse> Function() call,
  ) async {
    final RkHttpResponse r;
    try {
      r = await call();
    } on RkHttpFailure {
      // The request never reached a response: offline, never "the server
      // refused". The screens read `offline` to keep the countdown honest.
      throw const CeremonyFailure(offline: true, message: 'offline');
    }
    final Object? decoded;
    try {
      decoded = r.body.isEmpty ? null : jsonDecode(r.body);
    } on FormatException {
      throw const CeremonyFailure(message: 'malformed');
    }
    final body = decoded is Map
        ? decoded.cast<String, Object?>()
        : const <String, Object?>{};
    if (r.statusCode == 200) return body;
    // The database named the refusal and the edge passed it through unchanged
    // (05c: never a silent drop); this passes it on the same way rather than
    // collapsing `self_verification` and `ceremony_flood` into one word.
    final reason = body['error'] ?? body['reason'];
    throw CeremonyFailure(
      message: reason is String && reason.isNotEmpty
          ? reason
          : 'http_${r.statusCode}',
    );
  }

  static String _b64(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}

/// How often a waiting device re-reads the session, and how it sleeps.
///
/// Injected as a pair so a widget test drives the whole exchange without a
/// real delay, and so the interval is one named number rather than a literal
/// buried in two loops.
final class CeremonyPolling {
  /// Creates the policy.
  const CeremonyPolling({
    this.interval = const Duration(seconds: 2),
    this.sleep = Future.delayed,
  });

  /// Gap between reads of the session row.
  final Duration interval;

  /// How the gap is taken; `Future.delayed` in production.
  final Future<void> Function(Duration) sleep;
}

/// The invitee device's half, over the wire (04 §6.2, ADR 2026-09-13d §4).
///
/// [open] is what mints the session, so this object is single-use per
/// session: *Regenerate* opens a new one, exactly as 0007 requires (nothing
/// ever mutates an old session).
final class ServerShowerSessionRelay implements ShowerSessionRelay {
  /// Creates the relay. [now] is the injected clock (CLAUDE.md rule 3) and is
  /// used only to stop polling once the **server's** `expires_at` has passed.
  ServerShowerSessionRelay({
    required this.api,
    required this.tenantId,
    required this.now,
    this.polling = const CeremonyPolling(),
  });

  /// The wire.
  final CeremonyApi api;

  /// Which tenant's ceremony this is.
  final String tenantId;

  /// Injected clock.
  final DateTime Function() now;

  /// Poll interval and sleep.
  final CeremonyPolling polling;

  String? _sessionId;
  DateTime? _expiresAt;

  /// The session this relay opened, or null before [open].
  String? get sessionId => _sessionId;

  @override
  Future<DateTime> open(Uint8List commitment) async {
    final s = await api.commit(tenantId: tenantId, commitment: commitment);
    _sessionId = s.sessionId;
    _expiresAt = s.expiresAt;
    return s.committedAt;
  }

  @override
  Future<Uint8List> verifierRandom() => _poll(
    (s) => s.verifierRandom,
    'no session is open: open() before verifierRandom()',
  );

  @override
  Future<void> reveal(Uint8List opening) async {
    final id = _sessionId;
    if (id == null) {
      throw StateError('no session is open: open() before reveal()');
    }
    await api.reveal(sessionId: id, opening: opening);
  }

  Future<Uint8List> _poll(
    Uint8List? Function(CeremonySessionWire) field,
    String unopened,
  ) => _pollSession(
    api: api,
    sessionId: _sessionId,
    expiresAt: _expiresAt,
    now: now,
    polling: polling,
    field: field,
    unopened: unopened,
  );
}

/// The verifier device's half, over the wire (04 §6.2, §6.3).
///
/// It is constructed **against a session id that already exists** — this side
/// never opens one. 0007 makes the subject's own device the only writer of a
/// commitment, so a verifier that minted a session would be inventing the
/// thing the ceremony exists to check.
final class ServerVerifierSessionRelay implements VerifierSessionRelay {
  /// Creates the relay over the invitee's live [sessionId].
  ServerVerifierSessionRelay({
    required this.api,
    required this.sessionId,
    required this.now,
    this.polling = const CeremonyPolling(),
  });

  /// The wire.
  final CeremonyApi api;

  /// The invitee's live session.
  final String sessionId;

  /// Injected clock.
  final DateTime Function() now;

  /// Poll interval and sleep.
  final CeremonyPolling polling;

  DateTime? _expiresAt;

  @override
  Future<RelayedCommitment> commitment() async {
    final s = await _read();
    _expiresAt = s.expiresAt;
    // `committed_at` and not this phone's clock: 04 §6.3's lifetime is the
    // server's, so both devices die at the same instant.
    return RelayedCommitment(bytes: s.commitment, issuedAt: s.committedAt);
  }

  @override
  Future<void> contribute(Uint8List verifierRandom) async {
    await api.contribute(sessionId: sessionId, verifierRandom: verifierRandom);
  }

  @override
  Future<Uint8List> opening() => _pollSession(
    api: api,
    sessionId: sessionId,
    expiresAt: _expiresAt,
    now: now,
    polling: polling,
    field: (s) => s.opening,
    unopened: 'no session',
  );

  Future<CeremonySessionWire> _read() async {
    final s = await api.session(sessionId);
    if (s == null) throw const CeremonyFailure(message: 'unknown_session');
    return s;
  }
}

/// One waiting loop, shared by both sides: re-read the session until [field]
/// is there, or until the **server's** `expires_at` has passed.
///
/// A relay that simply never answers is denial of service, accepted in 04
/// §1.2 bullet 1 — so this ends in a refusal the screen can show, never in a
/// verified state and never in an unbounded wait.
Future<Uint8List> _pollSession({
  required CeremonyApi api,
  required String? sessionId,
  required DateTime? expiresAt,
  required DateTime Function() now,
  required CeremonyPolling polling,
  required Uint8List? Function(CeremonySessionWire) field,
  required String unopened,
}) async {
  final id = sessionId;
  if (id == null) throw StateError(unopened);
  var deadline = expiresAt;
  while (true) {
    final s = await api.session(id);
    if (s == null) throw const CeremonyFailure(message: 'unknown_session');
    deadline = s.expiresAt;
    final value = field(s);
    if (value != null) return value;
    if (!deadline.isAfter(now().toUtc())) {
      throw const CeremonyFailure(message: 'expired');
    }
    await polling.sleep(polling.interval);
  }
}
