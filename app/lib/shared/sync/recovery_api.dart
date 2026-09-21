// The app's door to the guardian-recovery routes (04 §7.3 🔒, 06 §5).
//
// ⚠️ WIRE — the contract is migration
// `server/supabase/migrations/0010_recovery_guardian_write_side.sql` and the
// `recovery` block of `server/supabase/functions/sync-meta/index.ts`, pinned
// by `server/supabase/functions/_tests/recovery_meta.test.ts` and
// `server/supabase/tests/rls/recovery.test.ts` (E-06-43…56). Everything below
// mirrors those files and must change in step with them:
//
//   • GET  `sync-meta/recovery`                     → `{requests:[…]}` — the
//     caller's own attempts (`requestToWire`);
//   • GET  `sync-meta/recovery?request_id=<uuid>`   → the **derived** state
//     (`progressToWire`): `k n approvals denials opened_state state
//     kth_approval_at wait_until expires_at cancelled_at`;
//   • GET  `sync-meta/recovery/asks`                → `{asks:[…]}` — the
//     attempts addressed to the caller **as a guardian**, and no others;
//   • POST `sync-meta/recovery` `{candidate_pub_x}` → one new attempt;
//   • POST `sync-meta/recovery/approve` `{request_id, blob, sealed_to_pub_x}`
//     → `{request_id, decision, wrapped_key_id}`;
//   • POST `sync-meta/recovery/deny` `{request_id}`;
//   • POST `sync-meta/recovery/cancel` `{request_id}` (ADR 2026-09-05d §1);
//   • GET  `sync-meta/recovery/sheet`               → `{user_id,
//     sheet_version, sealed_rk_blob, created_at}`, or 404 `no_sheet`
//     (04 §7.4 🔒 rung 3, migration 0011, E-06-58/60/61);
//   • POST `sync-meta/recovery/sheet` `{blob}`      → `{sheet_version}`.
//
// **Three things this client must never do**, because they are the server's
// and doing them here would be a client that can shorten the ladder:
//
//   1. It never derives a state. `state` is read verbatim from the body; the
//      24 h wait of ADR 2026-09-05d §1 is measured by the database from the
//      k-th approval (0010 `rf.recovery_derive`, E-06-56), so a phone whose
//      clock says the wait is over learns nothing from that. `wait_until` and
//      `expires_at` are carried for display only and are never compared with
//      a local clock to decide anything.
//   2. It never counts a quorum. `k`, `n`, `approvals` and `denials` come off
//      the append-only decision rows in the database (0010 THE DECISION 🔒);
//      no arithmetic here may reach the conclusion the server withheld.
//   3. It never opens, hashes or re-seals a share. `blob` is opaque bytes in
//      and an id out (04 §8.6).
//
// Nothing here logs: bodies carry access tokens and sealed shares (rule 4).
import 'dart:convert';
import 'dart:typed_data';

import '../seams/http_transport.dart';

/// Route table under the edge-functions root (⚠️ WIRE sync-meta/index.ts).
final class RecoveryEndpoints {
  /// Creates the table from the functions root (`…/functions/v1/`).
  RecoveryEndpoints(Uri functionsRoot)
    : base = functionsRoot.path.endsWith('/')
          ? functionsRoot
          : functionsRoot.replace(path: '${functionsRoot.path}/');

  /// Slash-terminated root, so `resolve` appends rather than replaces.
  final Uri base;

  /// The function every recovery route lives under.
  static const String function = 'sync-meta';

  Uri _sub(String path) => base.resolve('$function/$path');

  /// `GET` my attempts / `POST` a new one (04 §7.3 step 1).
  Uri get recovery => _sub('recovery');

  /// The derived state of one attempt.
  Uri progress(String requestId) =>
      _sub('recovery').replace(queryParameters: {'request_id': requestId});

  /// The attempts addressed to me as a guardian (04 §7.3 step 2).
  Uri get asks => _sub('recovery/asks');

  /// 04 §7.3 step 3 — approve, carrying the re-sealed share.
  Uri get approve => _sub('recovery/approve');

  /// 04 §7.3 step 7 — *not now*.
  Uri get deny => _sub('recovery/deny');

  /// ADR 2026-09-05d §1 — the one-tap Cancel.
  Uri get cancel => _sub('recovery/cancel');

  /// 04 §7.4 🔒 rung 3 — `GET` the caller's **own current** sealed sheet
  /// blob, `POST` the next one (migration 0011).
  ///
  /// The route takes no parameter in either direction that could name a
  /// *code*: the server holds one blob per user and hands over that one. RK
  /// never reaches this file, this package or the wire.
  Uri get sheet => _sub('recovery/sheet');
}

/// Why a recovery call was refused, named exactly as the route names it
/// (⚠️ WIRE `recoveryError` in sync-meta/index.ts). Never a status code and
/// never a raw server string (07 §1 rule 12).
enum RecoveryRefusal {
  /// The request never reached a response. The one refusal that does not
  /// claim the server said anything.
  offline,

  /// 403 `unknown_request` — **and this is one answer for two questions**:
  /// an attempt that does not exist and one the caller is not a guardian of
  /// answer identically, so the route is no oracle for whose recovery is in
  /// flight (0010, ADR 2026-09-05d §2). Never asked a second time to tell
  /// them apart.
  unknownRequest,

  /// 401 / 403 — no live session, or a device that may not be here.
  unauthorized,

  /// 409 `no_guardian_set` — rung 2 does not exist for this user; the ladder
  /// falls through to 04 §7.4's paper sheet.
  noGuardianSet,

  /// 409 `guardian_set_incomplete` — the published set holds fewer than n.
  guardianSetIncomplete,

  /// 409 `recovery_closed` — cancelled, expired or already approved.
  recoveryClosed,

  /// 409 `already_decided` — this guardian decided once already. Idempotent
  /// by the primary key, so it is a *state*, not a fault.
  alreadyDecided,

  /// 409 `candidate_key_mismatch` — the share was sealed to another
  /// attempt's candidate key (ADR 2026-09-13c §3).
  candidateKeyMismatch,

  /// 429 `recovery_flood` — too many live attempts (ADR 2026-09-05b §7).
  flood,

  /// 400 — the body was not the shape the route takes.
  badRequest,

  /// 404 — no such attempt for this caller.
  notFound,

  /// 404 `no_sheet` — this user never published a recovery sheet, or this
  /// caller may not read one.
  ///
  /// **It is not a rejected code.** 04 §7.4 🔒's rung 3 fails here before any
  /// decryption is attempted, so nothing about the code the human typed has
  /// been learned — and a screen that said *"that code didn't work"* on this
  /// refusal would be telling somebody their correctly copied sheet is wrong.
  /// The verdict on a code is the client's AEAD open and only that.
  noSheet,

  /// 409 `sheet_version_out_of_order` / `append_only` — a sheet at that
  /// version is already filed. 0011 is write-once and versioned (04 §7.4 🔒:
  /// regenerating rotates RK), so this is the refusal a second publisher
  /// meets, never a licence to overwrite.
  sheetConflict,

  /// 426 — this build is below the floor (06 §4.5).
  upgradeRequired,

  /// Anything else. Never guessed into something friendlier.
  server,
}

/// A recovery call was refused. Carries the refusal, never a server string.
final class RecoveryApiFailure implements Exception {
  /// Creates the failure.
  const RecoveryApiFailure(this.refusal, [this.detail = '']);

  /// What the server (or the transport) said.
  final RecoveryRefusal refusal;

  /// For this device's own handling only — never rendered, never logged.
  final String detail;

  @override
  String toString() => 'RecoveryApiFailure(${refusal.name})';
}

/// Maps a server `error` name onto a refusal (⚠️ WIRE `recoveryError`).
RecoveryRefusal recoveryRefusalOf(String? error, int status) => switch (error) {
  'unknown_request' ||
  'unknown_candidate_device' => RecoveryRefusal.unknownRequest,
  'no_guardian_set' => RecoveryRefusal.noGuardianSet,
  'guardian_set_incomplete' => RecoveryRefusal.guardianSetIncomplete,
  'recovery_closed' => RecoveryRefusal.recoveryClosed,
  'already_decided' => RecoveryRefusal.alreadyDecided,
  'candidate_key_mismatch' => RecoveryRefusal.candidateKeyMismatch,
  'recovery_flood' || 'sheet_flood' => RecoveryRefusal.flood,
  'no_sheet' => RecoveryRefusal.noSheet,
  'sheet_version_out_of_order' ||
  'append_only' => RecoveryRefusal.sheetConflict,
  'upgrade_required' => RecoveryRefusal.upgradeRequired,
  'unauthorized' || 'forbidden' => RecoveryRefusal.unauthorized,
  'not_found' => RecoveryRefusal.notFound,
  'recovery_shape' ||
  'guardian_quorum' ||
  'guardian_set_size' ||
  'guardian_is_subject' ||
  'share_set_version_out_of_order' ||
  'check' ||
  'bad_request' => RecoveryRefusal.badRequest,
  _ => switch (status) {
    401 || 403 => RecoveryRefusal.unauthorized,
    404 => RecoveryRefusal.notFound,
    426 => RecoveryRefusal.upgradeRequired,
    429 => RecoveryRefusal.flood,
    _ => RecoveryRefusal.server,
  },
};

/// One attempt as the route opens it (⚠️ WIRE `requestToWire`).
final class RecoveryRequestWire {
  /// Creates the row.
  const RecoveryRequestWire({
    required this.requestId,
    required this.candidateDevice,
    required this.candidatePubX,
    required this.shareSetVersion,
    required this.openedState,
    required this.createdAtMs,
    required this.expiresAtMs,
  });

  /// Decodes one wire row.
  factory RecoveryRequestWire.fromJson(Map<String, Object?> j) =>
      RecoveryRequestWire(
        requestId: j['request_id']! as String,
        candidateDevice: j['candidate_device'] as String? ?? '',
        candidatePubX: decodeB64Url(j['candidate_pub_x'] as String?),
        shareSetVersion: (j['share_set_version'] as num?)?.toInt() ?? 0,
        // The LADDER it opened on, never the live state — 0010's comment on
        // `recovery_requests.state`. `GET …?request_id=` carries the live one.
        openedState: j['opened_state'] as String? ?? '',
        createdAtMs: (j['created_at'] as num?)?.toInt() ?? 0,
        expiresAtMs: (j['expires_at'] as num?)?.toInt() ?? 0,
      );

  /// Server id of the attempt.
  final String requestId;

  /// The fresh phone this attempt belongs to.
  final String candidateDevice;

  /// Its candidate X25519 public key — 32 opaque bytes, the key every
  /// guardian re-seals to (04 §7.3 step 1).
  final Uint8List candidatePubX;

  /// The guardian set the attempt is pinned to (0010: pinned at open, so a
  /// re-split mid-attempt cannot move the quorum).
  final int shareSetVersion;

  /// `waiting_24h` or `pending` — the ladder, not the live state.
  final String openedState;

  /// Epoch milliseconds.
  final int createdAtMs;

  /// Epoch milliseconds — 72 h from the open (04 §7.3 step 7).
  final int expiresAtMs;
}

/// One guardian's decision, as it would arrive from the append-only rows.
///
/// `progressToWire` sends these (M11 RV7, ⚠️ WIRE sync-meta/index.ts):
/// `decisions: [{guardian_user_id, decision, created_at}]`, beside the
/// `approvals` / `denials` integers it always sent. The rows are why 0010
/// stores one append-only decision per guardian (ADR 2026-09-06 §
/// Consequences; ADR 2026-09-05d §1's cancel "notifies the guardians who
/// approved") — they are what lets the requester's screen say *which* member
/// acted.
///
/// **A missing array still attributes nothing.** The integers never stand in
/// for names: ticking "the first `approvals` members" would mark somebody who
/// did not act, on the one screen whose job is to say who did, and a denial
/// is a row while silence is the absence of one. So an older server, a body
/// this build cannot parse and a genuinely undecided attempt all read the
/// same way — every roster row *waiting*, which under-reports and never
/// misattributes.
final class RecoveryDecisionWire {
  /// Creates the row.
  const RecoveryDecisionWire({
    required this.guardianUserId,
    required this.decision,
    this.decidedAtMs,
  });

  /// Decodes one wire row.
  factory RecoveryDecisionWire.fromJson(Map<String, Object?> j) =>
      RecoveryDecisionWire(
        guardianUserId: j['guardian_user_id']! as String,
        decision: j['decision'] as String? ?? '',
        decidedAtMs: (j['created_at'] as num?)?.toInt(),
      );

  /// Which guardian decided.
  final String guardianUserId;

  /// `approved` or `denied` (0010 `recovery_approvals.decision`).
  final String decision;

  /// When, in epoch milliseconds. Display only.
  final int? decidedAtMs;
}

/// The **derived** state of one attempt (⚠️ WIRE `progressToWire`).
///
/// Every field here is the database's answer. Nothing in this class is
/// computed, and nothing in it may be recomputed by a caller: `state` is the
/// one word that decides whether a key may be reconstructed, and 0010 derives
/// it inside `rf.recovery_derive` for exactly that reason (E-06-56).
final class RecoveryProgressWire {
  /// Creates the reading.
  const RecoveryProgressWire({
    required this.requestId,
    required this.shareSetVersion,
    required this.k,
    required this.n,
    required this.approvals,
    required this.denials,
    required this.openedState,
    required this.state,
    this.kthApprovalAtMs,
    this.waitUntilMs,
    this.expiresAtMs,
    this.cancelledAtMs,
    this.decisions = const [],
  });

  /// Decodes the body.
  factory RecoveryProgressWire.fromJson(Map<String, Object?> j) =>
      RecoveryProgressWire(
        requestId: j['request_id'] as String? ?? '',
        shareSetVersion: (j['share_set_version'] as num?)?.toInt() ?? 0,
        k: (j['k'] as num?)?.toInt() ?? 0,
        n: (j['n'] as num?)?.toInt() ?? 0,
        approvals: (j['approvals'] as num?)?.toInt() ?? 0,
        denials: (j['denials'] as num?)?.toInt() ?? 0,
        openedState: j['opened_state'] as String? ?? '',
        state: j['state'] as String? ?? '',
        kthApprovalAtMs: (j['kth_approval_at'] as num?)?.toInt(),
        waitUntilMs: (j['wait_until'] as num?)?.toInt(),
        expiresAtMs: (j['expires_at'] as num?)?.toInt(),
        cancelledAtMs: (j['cancelled_at'] as num?)?.toInt(),
        decisions: [
          for (final d in (j['decisions'] as List<Object?>? ?? const []))
            if (d is Map)
              RecoveryDecisionWire.fromJson(d.cast<String, Object?>()),
        ],
      );

  /// Server id of the attempt.
  final String requestId;

  /// The set this attempt is pinned to.
  final int shareSetVersion;

  /// The quorum the database enforces — `⌈(n+1)/2⌉`, never computed here.
  final int k;

  /// How many members hold a share.
  final int n;

  /// Counted from the append-only rows (0010), never from the vestigial
  /// `recovery_requests.approvals` column.
  final int approvals;

  /// Denials so far; three closes the attempt (04 §7.3 step 7).
  final int denials;

  /// The ladder the attempt opened on.
  final String openedState;

  /// The live state: `pending` · `waiting_24h` · `approved` · `expired` ·
  /// `cancelled`. **The server's word, taken verbatim.**
  final String state;

  /// When the k-th approval landed; the 24 h wait runs from here.
  final int? kthApprovalAtMs;

  /// When the wait ends, for display. Never compared with a local clock to
  /// decide anything — that decision is `state`'s and the server's.
  final int? waitUntilMs;

  /// 72 h from the open.
  final int? expiresAtMs;

  /// When it was cancelled, or null.
  final int? cancelledAtMs;

  /// Who decided, as the route names them. Empty when the body carried no
  /// rows — which is *nobody named*, never "the first [approvals] of them".
  final List<RecoveryDecisionWire> decisions;
}

/// The caller's own current sealed recovery sheet (⚠️ WIRE the
/// `GET /recovery/sheet` block of sync-meta/index.ts; migration 0011).
///
/// 04 §7.4 🔒: the server holds `sealed_RK_blob = XChaCha20(RK, UMK_priv)`
/// and **cannot open it** — RK exists on a sheet of paper and nowhere else.
/// So every field here is either public (a user id, a version, a timestamp)
/// or opaque ciphertext. Nothing in this class is a secret, and nothing in it
/// is evidence about a code: the server hands over the same bytes whatever
/// the human typed.
final class RecoverySheetWire {
  /// Creates the row.
  const RecoverySheetWire({
    required this.userId,
    required this.sheetVersion,
    required this.blob,
    this.createdAtMs = 0,
  });

  /// Decodes the body.
  factory RecoverySheetWire.fromJson(Map<String, Object?> j) =>
      RecoverySheetWire(
        userId: j['user_id'] as String? ?? '',
        sheetVersion: (j['sheet_version'] as num?)?.toInt() ?? 0,
        blob: decodeB64Url(j['sealed_rk_blob'] as String?),
        createdAtMs: (j['created_at'] as num?)?.toInt() ?? 0,
      );

  /// Whose sheet it is — the caller's own; 0011 serves no other user's.
  final String userId;

  /// Its generation. A regenerated sheet rotates RK and invalidates the old
  /// one (04 §7.4 🔒), so an old paper sheet legitimately fails to open the
  /// current blob — and that failure is still an AEAD failure, not a
  /// server verdict.
  final int sheetVersion;

  /// The sealed bytes, exactly as the server stored them. Opaque here: this
  /// file does not frame, parse, hash or compare them.
  final Uint8List blob;

  /// Epoch milliseconds the sheet was filed. Display only.
  final int createdAtMs;
}

/// What a guardian is asked (⚠️ WIRE the `/recovery/asks` block).
///
/// Nothing financial: a user, a device, a public key and two timestamps.
/// There is no book, tenant, amount or envelope anywhere in this shape
/// (04 §4 🔒).
final class RecoveryAskWire {
  /// Creates the ask.
  const RecoveryAskWire({
    required this.requestId,
    required this.subjectUserId,
    required this.candidateDevice,
    required this.candidatePubX,
    required this.shareSetVersion,
    required this.createdAtMs,
    required this.expiresAtMs,
    this.myDecision,
  });

  /// Decodes one wire row.
  factory RecoveryAskWire.fromJson(Map<String, Object?> j) => RecoveryAskWire(
    requestId: j['request_id']! as String,
    subjectUserId: j['subject_user_id'] as String? ?? '',
    candidateDevice: j['candidate_device'] as String? ?? '',
    candidatePubX: decodeB64Url(j['candidate_pub_x'] as String?),
    shareSetVersion: (j['share_set_version'] as num?)?.toInt() ?? 0,
    createdAtMs: (j['created_at'] as num?)?.toInt() ?? 0,
    expiresAtMs: (j['expires_at'] as num?)?.toInt() ?? 0,
    myDecision: j['my_decision'] as String?,
  );

  /// Server id of the attempt.
  final String requestId;

  /// Whose books are being recovered.
  final String subjectUserId;

  /// The fresh phone asking.
  final String candidateDevice;

  /// The candidate X25519 public key — 32 bytes the guardian's device
  /// compares, byte-for-byte, against the `DeviceQrPayload` it scans
  /// (ADR 2026-09-13c §3 🔒). Opaque here: this file neither hashes it nor
  /// seals to it.
  final Uint8List candidatePubX;

  /// The set the attempt is pinned to.
  final int shareSetVersion;

  /// Epoch milliseconds.
  final int createdAtMs;

  /// Epoch milliseconds — the 72 h window.
  final int expiresAtMs;

  /// **This** guardian's own decision, or null while the ask is open. Never
  /// another guardian's: the route does not answer for anybody else.
  final String? myDecision;
}

/// Decodes base64url with or without padding; empty for null or malformed.
Uint8List decodeB64Url(String? s) {
  if (s == null || s.isEmpty) return Uint8List(0);
  try {
    return Uint8List.fromList(base64Url.decode(base64.normalize(s)));
  } on FormatException {
    return Uint8List(0);
  }
}

/// Encodes bytes as unpadded base64url — the form every route takes.
String encodeB64Url(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

/// The server's side of the guardian-recovery ladder.
abstract interface class RecoveryApi {
  /// The caller's own attempts, newest last as the route returns them.
  Future<List<RecoveryRequestWire>> myRequests();

  /// The derived state of one attempt.
  Future<RecoveryProgressWire> progress(String requestId);

  /// 04 §7.3 step 1: open an attempt for this device, carrying its candidate
  /// X25519 public key. The key is generated elsewhere and passed through.
  Future<RecoveryRequestWire> open(Uint8List candidatePubX);

  /// The attempts addressed to this device's user **as a guardian**.
  Future<List<RecoveryAskWire>> asks();

  /// 04 §7.3 step 3: file this guardian's approval with the re-sealed share.
  /// Returns the sealed row's id — never the blob.
  Future<String?> approve({
    required String requestId,
    required Uint8List blob,
    required Uint8List sealedToPubX,
  });

  /// 04 §7.3 step 7: *not now*.
  Future<void> deny(String requestId);

  /// ADR 2026-09-05d §1: the one-tap Cancel, from an existing certified
  /// device of the user.
  Future<void> cancel(String requestId);

  /// 04 §7.4 🔒 rung 3: the caller's own current sealed sheet blob, or
  /// **null** when the server says `no_sheet`.
  ///
  /// Null is *"this user has no sheet"*. It is deliberately not an exception
  /// and deliberately not a rejection: the caller has learned nothing about
  /// any code, because no code was sent. Every other refusal still throws.
  Future<RecoverySheetWire?> sheet();

  /// 04 §7.4 🔒: files the next sealed sheet, returning the version the
  /// server filed. [blob] is `XChaCha20(RK, UMK_priv)` as the caller sealed
  /// it — opaque bytes in, an integer out. **RK itself is never sent**: it
  /// belongs on paper, and a server that held it could open every book.
  Future<int> publishSheet(Uint8List blob);
}

/// [RecoveryApi] over the edge functions.
final class HttpRecoveryApi implements RecoveryApi {
  /// Creates the client. [accessToken] yields the 15-minute JWT of 06 §4;
  /// [clientVersion] rides `x-rukka-client-version` so a build below the
  /// floor is told to upgrade rather than failing obscurely (06 §4.5).
  HttpRecoveryApi({
    required RkHttpTransport transport,
    required Uri functionsRoot,
    required Future<String?> Function() accessToken,
    String? clientVersion,
  }) : _http = transport,
       _endpoints = RecoveryEndpoints(functionsRoot),
       _token = accessToken,
       _version = clientVersion;

  final RkHttpTransport _http;
  final RecoveryEndpoints _endpoints;
  final Future<String?> Function() _token;
  final String? _version;

  /// ⚠️ WIRE `_shared/http.ts` CLIENT_VERSION_HEADER.
  static const String clientVersionHeader = 'x-rukka-client-version';

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const RecoveryApiFailure(
        RecoveryRefusal.unauthorized,
        'no session',
      );
    }
    return {
      'authorization': 'Bearer $token',
      if (json) 'content-type': 'application/json',
      if (_version != null) clientVersionHeader: _version,
    };
  }

  @override
  Future<List<RecoveryRequestWire>> myRequests() async {
    final body = await _send(
      () async => _http.get(_endpoints.recovery, headers: await _headers()),
    );
    return [
      for (final r in (body['requests'] as List<Object?>? ?? const []))
        if (r is Map) RecoveryRequestWire.fromJson(r.cast<String, Object?>()),
    ];
  }

  @override
  Future<RecoveryProgressWire> progress(String requestId) async {
    final body = await _send(
      () async =>
          _http.get(_endpoints.progress(requestId), headers: await _headers()),
    );
    return RecoveryProgressWire.fromJson(body);
  }

  @override
  Future<RecoveryRequestWire> open(Uint8List candidatePubX) async {
    final body = await _send(
      () async => _http.post(
        _endpoints.recovery,
        headers: await _headers(json: true),
        body: jsonEncode({'candidate_pub_x': encodeB64Url(candidatePubX)}),
      ),
    );
    return RecoveryRequestWire.fromJson(body);
  }

  @override
  Future<List<RecoveryAskWire>> asks() async {
    final body = await _send(
      () async => _http.get(_endpoints.asks, headers: await _headers()),
    );
    return [
      for (final a in (body['asks'] as List<Object?>? ?? const []))
        if (a is Map) RecoveryAskWire.fromJson(a.cast<String, Object?>()),
    ];
  }

  @override
  Future<String?> approve({
    required String requestId,
    required Uint8List blob,
    required Uint8List sealedToPubX,
  }) async {
    final body = await _send(
      () async => _http.post(
        _endpoints.approve,
        headers: await _headers(json: true),
        // Opaque in, an id out: this client does not open, hash or re-seal
        // the share, and the server does not either (04 §8.6).
        body: jsonEncode({
          'request_id': requestId,
          'blob': encodeB64Url(blob),
          'sealed_to_pub_x': encodeB64Url(sealedToPubX),
        }),
      ),
    );
    return body['wrapped_key_id'] as String?;
  }

  @override
  Future<void> deny(String requestId) async {
    await _send(
      () async => _http.post(
        _endpoints.deny,
        headers: await _headers(json: true),
        body: jsonEncode({'request_id': requestId}),
      ),
    );
  }

  @override
  Future<void> cancel(String requestId) async {
    await _send(
      () async => _http.post(
        _endpoints.cancel,
        headers: await _headers(json: true),
        body: jsonEncode({'request_id': requestId}),
      ),
    );
  }

  @override
  Future<RecoverySheetWire?> sheet() async {
    try {
      final body = await _send(
        () async => _http.get(_endpoints.sheet, headers: await _headers()),
      );
      return RecoverySheetWire.fromJson(body);
    } on RecoveryApiFailure catch (e) {
      // `no_sheet` is an answer, not a fault — and it is the *only* refusal
      // that becomes null. A 401, a 429 or a dead socket must never read as
      // "no sheet exists", because that is a different sentence on S11.3.
      if (e.refusal == RecoveryRefusal.noSheet) return null;
      rethrow;
    }
  }

  @override
  Future<int> publishSheet(Uint8List blob) async {
    final body = await _send(
      () async => _http.post(
        _endpoints.sheet,
        headers: await _headers(json: true),
        // The sealed blob and nothing else. There is no field on this route
        // for RK, for the sheet's text or for a checksum, by construction.
        body: jsonEncode({'blob': encodeB64Url(blob)}),
      ),
    );
    return (body['sheet_version'] as num?)?.toInt() ?? 0;
  }

  /// Runs one request and turns anything but 2xx into a named failure. A
  /// transport that never answered is [RecoveryRefusal.offline] — the one
  /// refusal that does not claim the server spoke.
  Future<Map<String, Object?>> _send(
    Future<RkHttpResponse> Function() run,
  ) async {
    final RkHttpResponse res;
    try {
      res = await run();
    } on RecoveryApiFailure {
      rethrow;
    } on Exception catch (_) {
      throw const RecoveryApiFailure(RecoveryRefusal.offline);
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
    throw RecoveryApiFailure(
      recoveryRefusalOf(body['error'] as String?, res.statusCode),
    );
  }
}
