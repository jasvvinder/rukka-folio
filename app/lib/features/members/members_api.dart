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
//     roles, expires_at, created_by, status, nonce}]}` — the caller's own
//     invites: at `sent` and addressed to *my* OTP-verified number, or
//     accepted by me, inside the 7-day window (ADR 2026-09-25b §2, 0015);
//   • POST `sync-meta/invites/accept` `{invite_id}` → `{invite_id, status,
//     nonce}` — `status` here is the MEMBERSHIP's
//     (`joined_pending_verification`), not the invite's;
//   • `nonce` on both is base64url **unpadded**, 16 bytes: the one the
//     inviter's device drew and signed (ADR 2026-09-25b §1). It is decoded with
//     `Bytes.fromBase64Url`, never `base64Url.decode`, which refuses unpadded
//     input (D-05-14);
//   • POST `sync-meta/records` `{records:[…]}` → `{results:[{id, result}]}`;
//   • refusals by name: 403 `invite_not_for_you` · 403 `not_admin` · 403
//     `unauthorized` · 409 `invite_not_live` · 409 `record_replayed` · 409
//     `no_record` · 410 `invite_expired` · 400 `bad_phone` / `bad_record`;
//   • the plan's hard caps (ADR 2026-09-05g §2 / §6 🔒, migration 0019): 409
//     `seat_cap` / `seat_rotation_cap` on `invites` (`inviteError`), and
//     `rejected:seat_cap` / `rejected:seat_rotation_cap` / `rejected:book_cap`
//     as a `records` result (`CAP_REFUSALS`). The names are `sync_engine`'s
//     [PlanCap] — one spelling for both doors, pinned to the server by D-05g-1.
//
// **`invite_not_for_you` is the whole of C-05d-9:** the server answers a
// wrong number and an invite id that does not exist with byte-identical
// bodies, so the route is no oracle for who was invited. This client keeps
// that property — it has exactly one failure for both and never asks a
// second question to tell them apart.
//
// Nothing here logs: bodies carry phone numbers and access tokens (rule 4).
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show Bytes, ceremonyNonceBytes;
import 'package:sync_engine/sync_engine.dart' show MetaResponse, PlanCap;

import '../../shared/seams/http_transport.dart';
import 'members_repository.dart';

export '../../shared/seams/http_transport.dart'
    show
        MembersTransportOverRkHttp,
        RkHttpFailure,
        RkHttpResponse,
        RkHttpTransport;

/// A minimal response: status and UTF-8 body. An alias of the app's one HTTP
/// door (`shared/seams/http_transport.dart`) — this feature declared its own
/// copy until M7; the name stays, the second declaration does not.
typedef MembersHttpResponse = RkHttpResponse;

/// Thrown by a [MembersTransport] when the request never reached a response
/// (no network, DNS, TLS, timeout). The API maps it to
/// [MembersRefusal.offline] — never to a refusal that would claim the server
/// said something.
typedef MembersTransportException = RkHttpFailure;

/// GET/POST JSON with a bearer token: the door itself ([RkHttpTransport]).
/// Implementations must throw [MembersTransportException] on transport
/// failure and never log a body.
typedef MembersTransport = RkHttpTransport;

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

/// An invite offered to *this* phone (06 §7), or the one this phone accepted
/// (ADR 2026-09-25b §2). Carries no `invitee_hmac` and no number — the server
/// hands the joiner only what it must. It does carry the invite's **nonce**
/// since 25b: not secret (04 §6.1), and S9.2's QR needs it.
final class InviteOffer {
  /// Creates an offer.
  const InviteOffer({
    required this.inviteId,
    required this.tenantId,
    required this.roles,
    required this.expiresAt,
    required this.createdBy,
    this.status,
    this.nonce,
    this.extra = const {},
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
    // ⚠️ SPEC (PLAN desk 36, unanswered): whether `status` is part of ADR
    // 2026-09-25b §2 is not ruled — the server added it in the M11-INV1
    // repair. It is decoded and carried, and NOTHING here or in the relay
    // pairs a nonce by it: the pairing is by `invite_id` alone.
    status: j['status'] is String ? j['status']! as String : null,
    nonce: inviteNonceFromWire(j['nonce']),
    extra: {
      for (final e in j.entries)
        if (!_offerFields.contains(e.key)) e.key: e.value,
    },
  );

  static const _offerFields = {
    'invite_id',
    'tenant_id',
    'roles',
    'expires_at',
    'created_by',
    'status',
    'nonce',
  };

  /// The invite's id — what [MembersApi.acceptInvite] takes, and the one key
  /// a relayed nonce is paired by (ADR 2026-09-25b §3).
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

  /// The invite's own status on the wire — `sent` or `accepted` — or null
  /// from a server that predates it. Informational only (⚠️ SPEC desk 36).
  final String? status;

  /// The invite's 16-byte nonce as the inviter signed it, or null when the row
  /// carries none this build can read. Never drawn here.
  final Uint8List? nonce;

  /// Fields this build does not know, kept as they came (CLAUDE.md rule 6).
  final Map<String, Object?> extra;
}

/// What `POST sync-meta/invites/accept` answered (⚠️ WIRE).
final class AcceptedInvite {
  /// Creates the answer.
  const AcceptedInvite({
    required this.inviteId,
    required this.status,
    this.nonce,
    this.extra = const {},
  });

  /// Decodes the accept body.
  factory AcceptedInvite.fromJson(Map<String, Object?> j) => AcceptedInvite(
    inviteId: j['invite_id']! as String,
    status: j['status']! as String,
    nonce: inviteNonceFromWire(j['nonce']),
    extra: {
      for (final e in j.entries)
        if (e.key != 'invite_id' && e.key != 'status' && e.key != 'nonce')
          e.key: e.value,
    },
  );

  /// The invite the server says it accepted.
  final String inviteId;

  /// The **membership** status the server moved to —
  /// `joined_pending_verification`, never `active`.
  final String status;

  /// That invite's nonce (ADR 2026-09-25b §2), or null when absent/unreadable.
  final Uint8List? nonce;

  /// Fields this build does not know (CLAUDE.md rule 6).
  final Map<String, Object?> extra;
}

/// A wire nonce → its 16 bytes, or null. Unpadded base64url (the server's
/// `b64url.enc`), decoded with `Bytes.fromBase64Url` (D-05-14). A value that
/// is missing, malformed or not 16 bytes is **no nonce** — never a throw that
/// would take the whole offer list down with it, and never a value padded or
/// cut to fit.
Uint8List? inviteNonceFromWire(Object? v) {
  if (v is! String || v.isEmpty) return null;
  try {
    final b = Bytes.fromBase64Url(v);
    return b.length == ceremonyNonceBytes ? b : null;
  } on FormatException {
    return null;
  }
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
  Future<String> acceptInvite(String inviteId) async =>
      (await acceptInviteRelayed(inviteId)).status;

  /// [acceptInvite] with the whole answer: the invite id the server accepted
  /// and its relayed nonce (ADR 2026-09-25b §2). Not on [MembersApi], so the
  /// interface every fake implements is unchanged.
  Future<AcceptedInvite> acceptInviteRelayed(String inviteId) async {
    final body = await _send(
      () async => _http.post(
        _endpoints.acceptInvite,
        headers: await _headers(json: true),
        body: jsonEncode({'invite_id': inviteId}),
      ),
    );
    return AcceptedInvite.fromJson(body);
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
///
/// A hard cap is read on **409 only**, the status the contract gives it —
/// the same rule as `sync_engine`'s `TransportFailure.fromHttp`, so the two
/// doors cannot disagree about what is a cap. A cap name on another status is
/// off-contract and stays [MembersRefusal.server].
MembersRefusal refusalOf(String? error, int status) {
  final cap = status == 409 ? planCapRefusal(PlanCap.fromWire(error)) : null;
  return cap ?? _namedRefusal(error, status);
}

/// What one `records` result means for the caller, when it is a refusal:
/// `rejected:<name>` → the named refusal, a cap by its own name
/// (`CAP_REFUSALS`, check = the name, no seq). Anything else keeps the
/// mapping [refusalOf] gives the bare name.
MembersRefusal recordRefusalOf(String result) {
  const prefix = 'rejected:';
  final name = result.startsWith(prefix)
      ? result.substring(prefix.length)
      : result;
  return planCapRefusal(PlanCap.fromWire(name)) ?? _namedRefusal(name, 400);
}

/// The members feature's name for [cap], or null when there is none.
MembersRefusal? planCapRefusal(PlanCap? cap) => switch (cap) {
  PlanCap.seats => MembersRefusal.seatCap,
  PlanCap.seatRotation => MembersRefusal.seatRotationCap,
  PlanCap.businessBooks => MembersRefusal.bookCap,
  null => null,
};

MembersRefusal _namedRefusal(String? error, int status) => switch (error) {
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
