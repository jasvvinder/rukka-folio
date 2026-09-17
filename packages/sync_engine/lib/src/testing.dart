// Test doubles the two-client harness and suite D drive: an in-memory
// [FakeSyncServer] that speaks the three routes of 05 §3–§5 exactly as
// `wire.dart` spells them — plus the write half of `/sync-meta`, signed
// records (ADR 05b §1) and 06 §7's invites — a per-device [FakeTransport]
// with an on/off switch,
// and a [PlainGuard] for devices that author plaintext JSON blobs (the harness's
// `SimulatedDevice`). Pure Dart: the server clock is injected, nothing here
// reads the wall clock or `Random()`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show DeviceCert;

import 'guard.dart';
import 'transport.dart';
import 'trust.dart';
import 'wire.dart';

/// Per-device push rate limits (05 §3, ADR 2026-09-05g §3).
final class RateLimits {
  /// Creates limits; null disables a dimension.
  const RateLimits({this.perMinute = 600, this.perHour = 5000});

  /// Envelopes per minute per device.
  final int? perMinute;

  /// Envelopes per hour per device.
  final int? perHour;

  /// No limits.
  static const RateLimits none = RateLimits(perMinute: null, perHour: null);
}

final class _Stored {
  _Stored(this.envelope, this.receivedAtMs);
  final WireEnvelope envelope;
  final int receivedAtMs;
}

final class _Window {
  int minuteStart = 0;
  int inMinute = 0;
  int hourStart = 0;
  int inHour = 0;
}

/// The server, in memory. One `seq` sequence shared by envelopes and signed
/// records (ADR 05b §5); a `store_epoch` that changes only on [restore].
/// Every hostile behaviour a suite-D test needs is a knob, never a code path
/// the engine could observe.
final class FakeSyncServer {
  /// Creates a server at [storeEpoch] over an injected [clock].
  FakeSyncServer({
    required this.clock,
    String storeEpoch = 'epoch-1',
    this.rateLimits = const RateLimits(),
  }) : _epoch = storeEpoch;

  /// Server clock (for `hlc_future` and rate windows).
  final Clock clock;

  /// Rate limits applied to pushes.
  RateLimits rateLimits;

  String _epoch;
  int _seq = 0;
  final List<_Stored> _envelopes = [];
  final Map<String, _Stored> _byId = {};
  final Map<String, _Window> _windows = {};

  // ── knobs ────────────────────────────────────────────────────────────────

  /// Envelope ids removed from every pull (the "withheld envelope" case).
  final Set<String> withheld = {};

  /// Signed-record ids hidden from `meta` (a record that arrives late).
  final Set<String> withheldRecords = {};

  /// Books whose pushes answer `rejected:no_role`.
  final Set<String> noRoleBooks = {};

  /// Devices whose pushes answer `membership_not_active`.
  final Set<String> inactiveDevices = {};

  /// Books whose pushes answer `rejected:unknown_book`.
  final Set<String> unknownBooks = {};

  /// Per-book envelope cap → `rejected:quota` beyond it.
  final Map<String, int> quotaPerBook = {};

  /// Book → lowest `key_version` still accepted (grace window closed below it).
  final Map<String, int> minKeyVersion = {};

  /// `rejected:tenant_frozen` on every push.
  bool frozen = false;

  /// Every route answers 426.
  bool updateRequired = false;

  /// Devices that get `401 device_revoked` on every route (unsigned word).
  final Set<String> authRevoked = {};

  /// Devices whose posted records are refused `rejected:unauthorized`
  /// (`intakeRecord`: the author's device row must be `certified`).
  final Set<String> uncertifiedDevices = {};

  /// Devices whose user is a tenant admin (06 §1.0): the only ones whose
  /// membership/role records apply and the only ones who may issue an invite.
  final Set<String> adminDevices = {};

  /// Device → the OTP-verified E.164 number behind it. The server hashes it to
  /// match invites; a device with no number here is offered none.
  final Map<String, String> devicePhones = {};

  /// 06 §7's invite window.
  int inviteTtlMs = 7 * 24 * 3600 * 1000;

  /// The `invites` table (06 §7).
  final List<FakeInvite> invites = [];

  /// Per-envelope size cap (05 §3 ⚠️ 256 KB).
  int maxEnvelopeBytes = 256 * 1024;

  /// Highest `payload_schema` the registry knows.
  int maxPayloadSchema = 1;

  /// `hlc_future` window (05 §2: 5 min).
  int hlcFutureMs = 5 * 60 * 1000;

  /// Meta tables, all mutable by the test (the server's *rows*).
  final List<WireSignedRecord> signedRecords = [];

  /// `wrapped_keys`.
  final List<WireWrappedKey> wrappedKeys = [];

  /// `devices`.
  final Map<String, WireDevice> devices = {};

  /// `device_certs`.
  final Map<String, WireDeviceCert> deviceCerts = {};

  /// `memberships`.
  final Map<String, WireMembership> memberships = {};

  /// `book_roles`.
  final Map<String, WireBookRole> bookRoles = {};

  /// `guardian_sets`.
  final List<WireGuardianSet> guardianSets = [];

  int _metaVersion = 0;

  /// Bumps the meta cursor so the next `meta` returns everything again.
  void touchMeta() => _metaVersion++;

  /// Current epoch.
  String get storeEpoch => _epoch;

  /// Highest `seq` handed out.
  int get lastSeq => _seq;

  /// Stored envelopes, in `seq` order.
  List<WireEnvelope> get stored => [for (final s in _envelopes) s.envelope];

  /// Whether [envelopeId] is stored.
  bool has(String envelopeId) => _byId.containsKey(envelopeId);

  /// Advances the sequence so the next stored row gets `seq` [next].
  void skipSeqTo(int next) {
    if (next - 1 < _seq) {
      throw ArgumentError.value(next, 'next', 'seq is already past it');
    }
    _seq = next - 1;
  }

  /// Stores a signed record, stamping the next `seq`; returns it stamped.
  WireSignedRecord addSignedRecord(WireSignedRecord record) {
    final stamped = WireSignedRecord(
      id: record.id,
      suiteVersion: record.suiteVersion,
      tenantId: record.tenantId,
      kind: record.kind,
      payloadJson: record.payloadJson,
      authorDeviceId: record.authorDeviceId,
      authorSig: record.authorSig,
      hlc: record.hlc,
      seq: ++_seq,
    );
    signedRecords.add(stamped);
    _metaVersion++;
    return stamped;
  }

  /// Simulates a restore from backup (ADR 05b §6): the epoch changes and the
  /// last [dropLast] envelopes by `seq` are gone. Returns the dropped ids.
  List<String> restore({int dropLast = 0, String? newEpoch}) {
    _epoch = newEpoch ?? '$_epoch+';
    final dropped = <String>[];
    for (var i = 0; i < dropLast && _envelopes.isNotEmpty; i++) {
      final s = _envelopes.removeLast();
      _byId.remove(s.envelope.envelopeId);
      dropped.add(s.envelope.envelopeId);
    }
    _metaVersion++;
    return dropped;
  }

  // ── routes ───────────────────────────────────────────────────────────────

  void _gate(String deviceId) {
    if (updateRequired) throw const UpdateRequired();
    if (authRevoked.contains(deviceId)) {
      throw const AuthFailed(code: AuthFailed.deviceRevoked);
    }
  }

  bool _rateLimited(String deviceId) {
    final w = _windows.putIfAbsent(deviceId, _Window.new);
    final now = clock.nowMs();
    if (now - w.minuteStart >= 60 * 1000) {
      w.minuteStart = now;
      w.inMinute = 0;
    }
    if (now - w.hourStart >= 3600 * 1000) {
      w.hourStart = now;
      w.inHour = 0;
    }
    final m = rateLimits.perMinute;
    final h = rateLimits.perHour;
    if ((m != null && w.inMinute >= m) || (h != null && w.inHour >= h)) {
      return true;
    }
    w.inMinute++;
    w.inHour++;
    return false;
  }

  /// `POST /sync/push` as [deviceId].
  PushResponse push(String deviceId, PushRequest request) {
    _gate(deviceId);
    final results = <PushResult>[];
    for (final e in request.envelopes) {
      results.add(_pushOne(deviceId, e));
    }
    return PushResponse(storeEpoch: _epoch, results: results);
  }

  PushResult _pushOne(String deviceId, WireEnvelope e) {
    PushResult reject(String result, {String? check, int? retryAfterMs}) =>
        PushResult(
          envelopeId: e.envelopeId,
          result: result,
          check: check,
          retryAfterMs: retryAfterMs,
        );
    final existing = _byId[e.envelopeId];
    if (existing != null) {
      // Duplicate: same thing as stored (05 §3).
      return PushResult(
        envelopeId: e.envelopeId,
        result: PushOutcome.acked,
        seq: existing.envelope.seq,
      );
    }
    if (frozen) return reject(PushOutcome.rejectedTenantFrozen);
    if (inactiveDevices.contains(deviceId)) {
      return reject(PushOutcome.membershipNotActive);
    }
    if (noRoleBooks.contains(e.bookId)) {
      return reject(PushOutcome.rejectedNoRole);
    }
    if (unknownBooks.contains(e.bookId)) {
      return reject(PushOutcome.rejectedUnknownBook);
    }
    if (e.authorDevice != deviceId) {
      return reject(PushOutcome.rejectedShape, check: 'author_device');
    }
    if (e.size > maxEnvelopeBytes) return reject(PushOutcome.rejectedTooLarge);
    if (e.payloadSchema > maxPayloadSchema) {
      return reject(PushOutcome.rejectedVersion);
    }
    if ((e.hlc >> 16) > clock.nowMs() + hlcFutureMs) {
      return reject(PushOutcome.rejectedHlcFuture);
    }
    final minV = minKeyVersion[e.bookId];
    if (minV != null && e.keyVersion < minV) {
      return reject(PushOutcome.rejectedKeyVersionStale);
    }
    if (_rateLimited(deviceId)) {
      return reject(PushOutcome.rejectedRateLimited, retryAfterMs: 60 * 1000);
    }
    final cap = quotaPerBook[e.bookId];
    if (cap != null &&
        _envelopes.where((s) => s.envelope.bookId == e.bookId).length >= cap) {
      return reject(PushOutcome.rejectedQuota);
    }
    final stored = _Stored(e.withSeq(++_seq), clock.nowMs());
    _envelopes.add(stored);
    _byId[e.envelopeId] = stored;
    return PushResult(
      envelopeId: e.envelopeId,
      result: PushOutcome.acked,
      seq: stored.envelope.seq,
    );
  }

  /// `GET /sync/pull` as [deviceId].
  PullResponse pull(String deviceId, PullRequest request) {
    _gate(deviceId);
    final page = <WireEnvelope>[];
    var next = request.afterSeq;
    for (final s in _envelopes) {
      final e = s.envelope;
      if (e.seq! <= request.afterSeq) continue;
      if (e.bookId != request.bookId) continue;
      if (withheld.contains(e.envelopeId)) continue;
      page.add(e);
      next = e.seq!;
      if (page.length >= request.limit) break;
    }
    // An empty page reports the highest seq seen for the book so the cursor
    // moves past withheld rows (that is exactly what read-your-writes and the
    // author-gap rule are there to catch).
    if (page.isEmpty) next = _seq;
    return PullResponse(storeEpoch: _epoch, envelopes: page, nextSeq: next);
  }

  /// `GET /sync/meta` as [deviceId]. The cursor is the meta version: a client
  /// at the current version gets an empty page.
  MetaResponse meta(String deviceId, MetaRequest request) {
    _gate(deviceId);
    final cursor = '$_metaVersion';
    if (request.after == cursor) {
      return MetaResponse(storeEpoch: _epoch, next: cursor);
    }
    return MetaResponse(
      storeEpoch: _epoch,
      next: cursor,
      signedRecords: [
        for (final r in signedRecords)
          if (!withheldRecords.contains(r.id)) r,
      ],
      wrappedKeys: List.of(wrappedKeys),
      devices: devices.values.toList(),
      deviceCerts: deviceCerts.values.toList(),
      memberships: memberships.values.toList(),
      bookRoles: bookRoles.values.toList(),
      guardianSets: List.of(guardianSets),
    );
  }

  // ── the write half of /sync-meta (ADR 05b §1, 06 §7) ──────────────────────
  // The order of the checks below is `sync-meta/index.ts`'s, deliberately: a
  // record is stored FIRST (it is a signed fact — append-only, even when it is
  // refused) and judged after, so a test that asserts "refused but kept" is
  // asserting the server's real shape and not this file's convenience.

  /// `POST /sync-meta/records` as [deviceId].
  PostRecordsResponse postRecords(String deviceId, PostRecordsRequest request) {
    _gate(deviceId);
    if (request.records.length > PostRecordsRequest.batchMax) {
      throw const BatchTooLarge(detail: 'max 50 records');
    }
    final results = <RecordAck>[];
    for (final p in request.records) {
      final taken = _intake(deviceId, p);
      final refusal = taken.refusal;
      if (refusal != null) {
        results.add(refusal);
        continue;
      }
      final stored = taken.record!;
      if (taken.duplicate) {
        results.add(
          RecordAck(id: p.id, result: RecordAck.acked, seq: stored.seq),
        );
        continue;
      }
      results.add(_apply(deviceId, stored));
    }
    return PostRecordsResponse(storeEpoch: _epoch, results: results);
  }

  /// `POST /sync-meta/invites` as [deviceId] (06 §7). The number is hashed and
  /// dropped: [FakeInvite] keeps [FakeInvite.inviteeHash] and nothing else, so
  /// a test that greps the server for the plaintext finds none.
  InviteIssued createInvite(String deviceId, CreateInviteRequest request) {
    _gate(deviceId);
    final phone = normaliseE164(request.phone);
    if (phone == null) {
      throw const RouteRefused(status: 400, code: RouteRefused.badPhone);
    }
    final taken = _intake(deviceId, request.record);
    final refusal = taken.refusal;
    if (refusal != null) {
      // `unauthorized` is a 403; a shape refusal is `400 bad_record` naming
      // the field (`sync-meta/index.ts` invites).
      if (refusal.result == RecordAck.rejectedUnauthorized) {
        throw const RouteRefused(status: 403, code: 'unauthorized');
      }
      throw RouteRefused(
        status: 400,
        code: RouteRefused.badRecord,
        detail: refusal.check,
      );
    }
    final record = taken.record!;
    if (record.kind != 'invite') {
      throw const RouteRefused(
        status: 400,
        code: RouteRefused.badRecord,
        detail: 'kind',
      );
    }
    final payload = _payloadOf(record);
    final nonce = payload?['nonce'];
    if (payload == null ||
        payload['roles'] is! List ||
        nonce is! String ||
        base64.decode(base64.normalize(nonce)).length != 16) {
      throw const RouteRefused(
        status: 400,
        code: RouteRefused.badRecord,
        detail: 'payload_json',
      );
    }
    if (taken.duplicate) {
      // The record IS the action: replaying it must not mint a second invite
      // (the first stands, found by `source_record_id` in the meta pull).
      throw const RouteRefused(status: 409, code: RouteRefused.recordReplayed);
    }
    if (!adminDevices.contains(deviceId)) {
      throw const RouteRefused(status: 403, code: RouteRefused.notAdmin);
    }
    final invite = FakeInvite(
      id: 'invite-${invites.length + 1}',
      tenantId: record.tenantId,
      recordId: record.id,
      inviteeHash: inviteeHashOf(phone),
      roles: payload['roles'],
      createdBy: userOf(deviceId),
      createdAtMs: clock.nowMs(),
      expiresAtMs: clock.nowMs() + inviteTtlMs,
    );
    invites.add(invite);
    _metaVersion++;
    return InviteIssued(
      inviteId: invite.id,
      recordId: record.id,
      seq: record.seq,
    );
  }

  /// `GET /sync-meta/invites` as [deviceId]: the live invites addressed to
  /// **this** device's own number, and nothing about anyone else's.
  List<WireInviteOffer> myInvites(String deviceId) {
    _gate(deviceId);
    final hash = inviteeHashOf(devicePhones[deviceId] ?? '');
    return [
      for (final i in invites)
        if (i.inviteeHash == hash &&
            i.status == FakeInvite.sent &&
            clock.nowMs() <= i.expiresAtMs)
          WireInviteOffer(
            inviteId: i.id,
            tenantId: i.tenantId,
            createdBy: i.createdBy,
            expiresAtMs: i.expiresAtMs,
            roles: i.roles,
          ),
    ];
  }

  /// `POST /sync-meta/invites/accept` as [deviceId]. Expiry binds here, lazily,
  /// so a missed sweep never admits anyone (06 §7's 7-day window).
  InviteAcceptance acceptInvite(String deviceId, String inviteId) {
    _gate(deviceId);
    final hash = inviteeHashOf(devicePhones[deviceId] ?? '');
    FakeInvite? row;
    for (final i in invites) {
      if (i.id == inviteId) row = i;
    }
    // ADR 2026-09-05d §9 🔒: a wrong number and an unknown id refuse
    // IDENTICALLY — the route is no oracle for who was invited.
    if (row == null || row.inviteeHash != hash) {
      throw const RouteRefused(status: 403, code: RouteRefused.inviteNotForYou);
    }
    if (clock.nowMs() > row.expiresAtMs) {
      row.status = FakeInvite.expired;
      throw const RouteRefused(status: 410, code: RouteRefused.inviteExpired);
    }
    if (row.status != FakeInvite.sent) {
      throw const RouteRefused(status: 409, code: RouteRefused.inviteNotLive);
    }
    final user = userOf(deviceId);
    row
      ..status = FakeInvite.accepted
      ..acceptedBy = user;
    // Never `active`: 06 §7 gives that edge to the ceremony alone.
    memberships['${row.tenantId}:$user'] = WireMembership(
      id: '${row.tenantId}:$user',
      tenantId: row.tenantId,
      userId: user,
      status: InviteAcceptance.joinedPendingVerification,
    );
    _metaVersion++;
    return InviteAcceptance(
      inviteId: inviteId,
      status: InviteAcceptance.joinedPendingVerification,
    );
  }

  /// The user behind [deviceId] — the `devices` row when the test seeded one,
  /// else the device id itself (the harness's one-device-per-user case).
  String userOf(String deviceId) => devices[deviceId]?.userId ?? deviceId;

  /// The fake's stand-in for the server-keyed `invitee_hmac`: a one-way tag
  /// over the number. Like the real HMAC, the client cannot compute it —
  /// nothing outside this server ever sees the number again.
  static String inviteeHashOf(String e164) =>
      base64Url.encode(fnv1a32(Uint8List.fromList(utf8.encode(e164))));

  /// `_shared/phone.ts` `normaliseE164`: `+`, a non-zero digit, then 7–14 more,
  /// with spaces and dashes stripped. Anything else never reaches the hash.
  static String? normaliseE164(String s) {
    final t = s.replaceAll(RegExp(r'[\s-]'), '');
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(t) ? t : null;
  }

  /// Verifies, stores and stamps one posted record. Mirrors `intakeRecord`:
  /// the record is stored even when the *application* is later refused.
  ({WireSignedRecord? record, RecordAck? refusal, bool duplicate}) _intake(
    String deviceId,
    WireRecordPost p,
  ) {
    RecordAck reject(String result, String check) =>
        RecordAck(id: p.id, result: result, check: check);
    if (p.authorDeviceId != deviceId) {
      return (
        record: null,
        refusal: reject(RecordAck.rejectedShape, 'author_device_id'),
        duplicate: false,
      );
    }
    if (p.authorSig.length != 64) {
      return (
        record: null,
        refusal: reject(RecordAck.rejectedShape, 'author_sig'),
        duplicate: false,
      );
    }
    if (uncertifiedDevices.contains(deviceId)) {
      return (
        record: null,
        refusal: reject(RecordAck.rejectedUnauthorized, 'device_status'),
        duplicate: false,
      );
    }
    for (final existing in signedRecords) {
      if (existing.id == p.id) {
        return (record: existing, refusal: null, duplicate: true);
      }
    }
    return (
      record: addSignedRecord(p.stamped(0)),
      refusal: null,
      duplicate: false,
    );
  }

  /// Projects a stored record onto the server's rows, or says why it did not.
  RecordAck _apply(String deviceId, WireSignedRecord r) {
    RecordAck ack(String result) =>
        RecordAck(id: r.id, result: result, seq: r.seq);
    final p = _payloadOf(r) ?? const <String, Object?>{};
    switch (r.kind) {
      case 'invite':
        // The generic route is not a second way in: it has no number to hash
        // (`_shared/records.ts` applyRecord).
        return ack(RecordAck.rejectedInviteRoute);
      case 'membership_status':
        if (!adminDevices.contains(deviceId)) {
          return ack(RecordAck.rejectedUnauthorized);
        }
        final user = p['user_id'];
        final status = p['status'];
        if (user is! String || status is! String) {
          return ack(RecordAck.rejectedShape);
        }
        memberships['${r.tenantId}:$user'] = WireMembership(
          id: '${r.tenantId}:$user',
          tenantId: r.tenantId,
          userId: user,
          status: status,
        );
      case 'book_role':
        if (!adminDevices.contains(deviceId)) {
          return ack(RecordAck.rejectedUnauthorized);
        }
        final user = p['user_id'];
        final book = p['book_id'];
        if (user is! String || book is! String) {
          return ack(RecordAck.rejectedShape);
        }
        bookRoles['$book:$user'] = WireBookRole(
          id: '$book:$user',
          bookId: book,
          userId: user,
          role: p['role'] as String?,
          limits: p['limits'] as Map<String, Object?>?,
        );
      default:
        // Every other kind is kept and relayed; the clients judge it. A kind
        // this fake does not project is NOT a refusal (rule 6).
        break;
    }
    _metaVersion++;
    return ack(RecordAck.acked);
  }

  Map<String, Object?>? _payloadOf(WireSignedRecord r) {
    try {
      final v = jsonDecode(utf8.decode(r.payloadJson));
      return v is Map<String, Object?> ? v : null;
    } on Object {
      return null;
    }
  }

  /// The transport one device uses.
  FakeTransport transportFor(String deviceId) => FakeTransport(this, deviceId);
}

/// An `invites` row as 06 §7's machine holds it. The invitee is present only
/// as [inviteeHash]; the plaintext number reached this server once, in the
/// issuing request, and was never written down (ADR 2026-09-05c §4).
final class FakeInvite {
  /// Creates a row.
  FakeInvite({
    required this.id,
    required this.tenantId,
    required this.recordId,
    required this.inviteeHash,
    required this.roles,
    required this.createdBy,
    required this.createdAtMs,
    required this.expiresAtMs,
    this.status = sent,
    this.acceptedBy,
  });

  /// Live and unspent.
  static const String sent = 'sent';

  /// Spent — an invite admits exactly one join.
  static const String accepted = 'accepted';

  /// Past its 7-day window (bound lazily, at accept time).
  static const String expired = 'expired';

  /// Row id.
  final String id;

  /// Tenant the invite is into.
  final String tenantId;

  /// `source_record_id` — the admin's signed `invite` record.
  final String recordId;

  /// One-way tag over the invitee's number.
  final String inviteeHash;

  /// The grants offered, as the record spelled them.
  final Object? roles;

  /// The admin's user id.
  final String createdBy;

  /// When it was issued (server clock).
  final int createdAtMs;

  /// When it stops admitting anyone.
  final int expiresAtMs;

  /// `sent` / `accepted` / `expired`.
  String status;

  /// Who accepted it.
  String? acceptedBy;
}

/// A device's line to the [FakeSyncServer]: on/off switch, call log, and an
/// optional per-call hook the harness uses to route each request through the
/// seeded network (drops → [TransportOffline]).
final class FakeTransport implements FullSyncTransport {
  /// Creates the transport.
  FakeTransport(this.server, this.deviceId);

  /// The server.
  final FakeSyncServer server;

  /// The device.
  final String deviceId;

  /// Connectivity switch.
  bool online = true;

  /// Runs before every call; throw [TransportOffline] to drop it.
  void Function(String route)? beforeCall;

  /// Routes called, in order.
  final List<String> calls = [];

  Future<T> _call<T>(String route, T Function() f) async {
    calls.add(route);
    if (!online) throw TransportOffline('$deviceId offline');
    beforeCall?.call(route);
    return f();
  }

  @override
  Future<PushResponse> push(PushRequest request) =>
      _call('push', () => server.push(deviceId, request));

  @override
  Future<PullResponse> pull(PullRequest request) =>
      _call('pull', () => server.pull(deviceId, request));

  @override
  Future<MetaResponse> meta(MetaRequest request) =>
      _call('meta', () => server.meta(deviceId, request));

  @override
  Future<PostRecordsResponse> postRecords(PostRecordsRequest request) =>
      _call('records', () => server.postRecords(deviceId, request));

  @override
  Future<InviteIssued> createInvite(CreateInviteRequest request) =>
      _call('invites', () => server.createInvite(deviceId, request));

  @override
  Future<List<WireInviteOffer>> myInvites() =>
      _call('invites', () => server.myInvites(deviceId));

  @override
  Future<InviteAcceptance> acceptInvite(String inviteId) =>
      _call('invites/accept', () => server.acceptInvite(deviceId, inviteId));
}

/// A deterministic 32-bit FNV-1a — the harness's blob hash.
Uint8List fnv1a32(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return Uint8List.fromList([
    h >> 24 & 0xff,
    h >> 16 & 0xff,
    h >> 8 & 0xff,
    h & 0xff,
  ]);
}

/// The guard for plaintext devices (the harness). Envelopes are JSON blobs;
/// a record is "signed" when its `author_sig` is [sign]'s tag under a device
/// in [trustedDevices] — so an unsigned or foreign record is still refused,
/// which is what the trust-boundary tests exercise. Revocation cut-offs come
/// from the same [RecordTrustStore] the real guard uses.
final class PlainGuard implements EnvelopeGuard {
  /// Creates the guard.
  PlainGuard({required this.trust, Set<String>? trustedDevices})
    : trustedDevices = trustedDevices ?? {};

  /// Trust state (revocation records, device owners).
  final RecordTrustStore trust;

  /// Devices whose records count as certified.
  final Set<String> trustedDevices;

  @override
  int get payloadSchema => 1;

  @override
  Uint8List hash(Uint8List blob) => fnv1a32(blob);

  /// The 64-byte tag [checkRecord] accepts for [payloadJson] by [deviceId].
  static Uint8List sign(String deviceId, Uint8List payloadJson) {
    final tag = fnv1a32(
      Uint8List.fromList([...payloadJson, ...utf8.encode(deviceId)]),
    );
    final out = Uint8List(64);
    out.setRange(0, 4, tag);
    return out;
  }

  @override
  EnvelopeVerdict checkEnvelope(WireEnvelope envelope) {
    final cut = trust.revocationSeqOf(envelope.authorDevice);
    if (cut != null && (envelope.seq == null || envelope.seq! >= cut)) {
      return const EnvelopeQuarantine('revoked');
    }
    try {
      final decoded = jsonDecode(utf8.decode(envelope.blob));
      if (decoded is! Map<String, Object?>) {
        return const EnvelopeQuarantine('payload: payloadMalformed');
      }
      final seq = decoded['author_seq'];
      if (seq is! int || seq < 1) {
        return const EnvelopeQuarantine('payload: payloadMalformed');
      }
      return EnvelopeVerified(seq);
    } on FormatException {
      return const EnvelopeQuarantine('payload: payloadMalformed');
    }
  }

  @override
  RecordVerdict checkRecord(WireSignedRecord record) {
    if (!trustedDevices.contains(record.authorDeviceId)) {
      return const RecordRejected('certMissing');
    }
    final expected = sign(record.authorDeviceId, record.payloadJson);
    if (record.authorSig.length != 64) {
      return const RecordRejected('sigInvalid');
    }
    for (var i = 0; i < 64; i++) {
      if (record.authorSig[i] != expected[i]) {
        return const RecordRejected('sigInvalid');
      }
    }
    final cut = trust.revocationSeqOf(record.authorDeviceId);
    if (cut != null && record.seq >= cut) {
      return const RecordRejected('revoked');
    }
    return const RecordVerified();
  }

  @override
  int? highestKeyVersion(String bookId) => null;

  @override
  WireEnvelope? reseal(WireEnvelope envelope, {required int toVersion}) => null;

  @override
  KeyAcceptance acceptWrappedKey(WireWrappedKey key) =>
      const KeyNotAccepted('plaintext harness holds no wrapped keys');

  @override
  DeviceCert? buildCert(WireDeviceCert cert, WireDevice device) => null;

  @override
  void dropAllKeys() {}
}
