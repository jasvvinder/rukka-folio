// Wire types for the three sync routes (05 §3 push, §4 pull, §5 meta).
//
// Field names are the ones 05 §3–§5 and 03 §2.2/§2.3 spell — `envelope_id`,
// `seq`, `store_epoch`, `after_seq`, `next_seq`, `key_version`, `blob_hash` … —
// so `server/functions` (lane S) and this package meet on the same JSON. Bytes
// travel base64url-encoded. Anything this file had to invent is marked
// `⚠️ WIRE:` and listed in the lane's notes.
//
// Reconciled against the server's actual output (M4/M6 Phase A stage 2a;
// `server/supabase/functions/sync-meta|sync-pull|sync-push`, `_shared/
// records.ts`): 03 wins over this file. Rows may carry more columns than the
// types below read (`source_record_id`, `updated_at`, `created_at`, `model`,
// `os`, `guardians[]`, `min_client_version`, `umk_public_keys`) — decoders
// ignore what they do not read; the meta response keeps whole unknown tables
// in [MetaResponse.extra] (rule 6).
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

String _b64(Uint8List b) => base64Url.encode(b);
Uint8List _bytes(Object? v) =>
    Uint8List.fromList(base64Url.decode(v! as String));
List<Map<String, Object?>> _list(Object? v) =>
    v == null ? const [] : (v as List<Object?>).cast<Map<String, Object?>>();

/// One envelope on the wire (03 §2.3 `envelopes` columns). `seq` is absent on
/// push (the server stamps it) and present on pull.
@immutable
final class WireEnvelope {
  /// Creates a wire envelope.
  const WireEnvelope({
    required this.envelopeId,
    required this.tenantId,
    required this.bookId,
    required this.objectId,
    required this.objectType,
    required this.keyVersion,
    required this.suiteVersion,
    required this.payloadSchema,
    required this.authorDevice,
    required this.hlc,
    required this.blobHash,
    required this.blob,
    this.seq,
    this.blobRef,
  });

  /// Decodes the JSON form. A pulled row whose blob lives in object storage
  /// carries `blob_ref` instead of `blob` (03 §2.3 `blob_ref`); the blob is
  /// then empty here and [blobRef] says where it is.
  factory WireEnvelope.fromJson(Map<String, Object?> j) => WireEnvelope(
    envelopeId: j['envelope_id']! as String,
    seq: j['seq'] as int?,
    tenantId: j['tenant_id']! as String,
    bookId: j['book_id']! as String,
    objectId: j['object_id']! as String,
    objectType: j['object_type']! as String,
    keyVersion: j['key_version']! as int,
    suiteVersion: j['suite_version']! as int,
    payloadSchema: j['payload_schema']! as int,
    authorDevice: j['author_device']! as String,
    hlc: j['hlc']! as int,
    blobHash: _bytes(j['blob_hash']),
    blob: j['blob'] == null ? Uint8List(0) : _bytes(j['blob']),
    blobRef: j['blob_ref'] as String?,
  );

  /// `envelope_id` — client-minted idempotency key.
  final String envelopeId;

  /// `seq` — server receipt order; null until stored.
  final int? seq;

  /// `tenant_id`.
  final String tenantId;

  /// `book_id`.
  final String bookId;

  /// `object_id`.
  final String objectId;

  /// `object_type`.
  final String objectType;

  /// `key_version`.
  final int keyVersion;

  /// `suite_version`.
  final int suiteVersion;

  /// `payload_schema`.
  final int payloadSchema;

  /// `author_device`.
  final String authorDevice;

  /// `hlc`.
  final int hlc;

  /// `blob_hash` — BLAKE2b-256(blob).
  final Uint8List blobHash;

  /// `blob` — `nonce ‖ author_sig ‖ ciphertext`. Empty when the server sent
  /// [blobRef] instead.
  final Uint8List blob;

  /// `blob_ref` — object-storage reference the server sends in place of
  /// `blob` for large envelopes (03 §2.3). ⚠️ WIRE: this build does not fetch
  /// it; such a row fails the hash check and stops the cursor (see notes).
  final String? blobRef;

  /// `size` — blob length (03 §2.3).
  int get size => blob.length;

  /// The same envelope with the server `seq` attached.
  WireEnvelope withSeq(int seq) => WireEnvelope(
    envelopeId: envelopeId,
    seq: seq,
    tenantId: tenantId,
    bookId: bookId,
    objectId: objectId,
    objectType: objectType,
    keyVersion: keyVersion,
    suiteVersion: suiteVersion,
    payloadSchema: payloadSchema,
    authorDevice: authorDevice,
    hlc: hlc,
    blobHash: blobHash,
    blob: blob,
    blobRef: blobRef,
  );

  /// Encodes the JSON form.
  Map<String, Object?> toJson() => {
    'envelope_id': envelopeId,
    if (seq != null) 'seq': seq,
    'tenant_id': tenantId,
    'book_id': bookId,
    'object_id': objectId,
    'object_type': objectType,
    'key_version': keyVersion,
    'suite_version': suiteVersion,
    'payload_schema': payloadSchema,
    'author_device': authorDevice,
    'hlc': hlc,
    'blob_hash': _b64(blobHash),
    'size': size,
    'blob': _b64(blob),
    if (blobRef != null) 'blob_ref': blobRef,
  };
}

/// `POST /sync/push {envelopes[]}` (05 §3). Batch ≤ 100 envelopes or 1 MB of
/// blob bytes; a larger batch is refused whole with HTTP 413
/// `{error:"batch_too_large"}` ([BatchTooLarge]), never per envelope.
@immutable
final class PushRequest {
  /// Creates a push.
  const PushRequest({required this.envelopes});

  /// Decodes.
  factory PushRequest.fromJson(Map<String, Object?> j) => PushRequest(
    envelopes: [
      for (final e in _list(j['envelopes'])) WireEnvelope.fromJson(e),
    ],
  );

  /// Batch cap, envelopes (05 §3).
  static const int maxEnvelopes = 100;

  /// Batch cap, bytes (05 §3).
  static const int maxBytes = 1 << 20;

  /// `envelopes`.
  final List<WireEnvelope> envelopes;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'envelopes': [for (final e in envelopes) e.toJson()],
  };
}

/// Per-envelope push outcomes — the `result` column of 05 §3's table.
abstract final class PushOutcome {
  /// Stored, or a duplicate (same thing).
  static const String acked = 'acked';

  /// Not authorised for this book now.
  static const String rejectedNoRole = 'rejected:no_role';

  /// Membership not active (or `blocked`, ADR 05b §7).
  static const String membershipNotActive = 'membership_not_active';

  /// Book archived / deleted.
  static const String rejectedUnknownBook = 'rejected:unknown_book';

  /// HLC beyond `server_now + 5 min` (05 §2).
  static const String rejectedHlcFuture = 'rejected:hlc_future';

  /// Above the per-envelope cap.
  static const String rejectedTooLarge = 'rejected:too_large';

  /// Sealed under a `BK` superseded > 48 h ago — one re-seal retry allowed.
  static const String rejectedKeyVersionStale = 'rejected:key_version_stale';

  /// `payload_schema` above the registry.
  static const String rejectedVersion = 'rejected:version';

  /// A 03 §2.3 shape check failed; [PushResult.check] names it.
  static const String rejectedShape = 'rejected:shape';

  /// Per-device rate exceeded — back off, never Inbox.
  static const String rejectedRateLimited = 'rejected:rate_limited';

  /// Book over plan quota — Inbox; book stays readable and pullable.
  static const String rejectedQuota = 'rejected:quota';

  /// Tenant frozen by support — pushes only.
  static const String rejectedTenantFrozen = 'rejected:tenant_frozen';
}

/// One row of a push response.
@immutable
final class PushResult {
  /// Creates a result.
  const PushResult({
    required this.envelopeId,
    required this.result,
    this.seq,
    this.retryAfterMs,
    this.check,
  });

  /// Decodes.
  factory PushResult.fromJson(Map<String, Object?> j) => PushResult(
    envelopeId: j['envelope_id']! as String,
    result: j['result']! as String,
    seq: j['seq'] as int?,
    retryAfterMs: j['retry_after_ms'] as int?,
    check: j['check'] as String?,
  );

  /// `envelope_id`.
  final String envelopeId;

  /// `result` — one of [PushOutcome].
  final String result;

  /// `seq` — present when [result] is `acked`.
  final int? seq;

  /// `retry_after_ms` — ⚠️ WIRE: invented; present on `rejected:rate_limited`
  /// so the client can honour the server's window instead of guessing.
  final int? retryAfterMs;

  /// `check` — the named shape check on `rejected:shape` (05 §3 "log with
  /// the named check").
  final String? check;

  /// Whether the envelope is stored.
  bool get isAcked => result == PushOutcome.acked;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'envelope_id': envelopeId,
    'result': result,
    if (seq != null) 'seq': seq,
    if (retryAfterMs != null) 'retry_after_ms': retryAfterMs,
    if (check != null) 'check': check,
  };
}

/// Push response: `store_epoch` (05 §1) + one [PushResult] per envelope.
@immutable
final class PushResponse {
  /// Creates a response.
  const PushResponse({required this.storeEpoch, required this.results});

  /// Decodes.
  factory PushResponse.fromJson(Map<String, Object?> j) => PushResponse(
    storeEpoch: j['store_epoch']! as String,
    results: [for (final r in _list(j['results'])) PushResult.fromJson(r)],
  );

  /// `store_epoch`.
  final String storeEpoch;

  /// `results`.
  final List<PushResult> results;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'store_epoch': storeEpoch,
    'results': [for (final r in results) r.toJson()],
  };
}

/// `GET /sync/pull?book_id=&after_seq=&limit=500[&fy=][&object_types=a,b]`
/// (05 §4); `fy` selects a closed year on demand and `object_types` narrows
/// a page to the bootstrap hot set (05 §8). Errors: 404 `unknown_book` (also
/// for a non-member's tenant and an uncertified device), 403 `no_role`, 401,
/// 426 — see [RouteRefused].
@immutable
final class PullRequest {
  /// Creates a pull.
  const PullRequest({
    required this.bookId,
    required this.afterSeq,
    this.limit = defaultLimit,
    this.fy,
    this.objectTypes,
  });

  /// Decodes.
  factory PullRequest.fromJson(Map<String, Object?> j) => PullRequest(
    bookId: j['book_id']! as String,
    afterSeq: j['after_seq']! as int,
    limit: (j['limit'] as int?) ?? defaultLimit,
    fy: j['fy'] as String?,
    objectTypes: switch (j['object_types']) {
      final String s => s.split(',').where((t) => t.isNotEmpty).toList(),
      final List<Object?> l => l.cast<String>(),
      _ => null,
    },
  );

  /// Page size 05 §4 names.
  static const int defaultLimit = 500;

  /// `book_id`.
  final String bookId;

  /// `after_seq` — the cursor; 0 pulls from the beginning.
  final int afterSeq;

  /// `limit`.
  final int limit;

  /// `fy` — e.g. `2024-25`; null = the hot set.
  final String? fy;

  /// `object_types` — comma-joined on the query string; null = every type.
  final List<String>? objectTypes;

  /// Encodes (query-string values as the server reads them).
  Map<String, Object?> toJson() => {
    'book_id': bookId,
    'after_seq': afterSeq,
    'limit': limit,
    if (fy != null) 'fy': fy,
    if (objectTypes != null) 'object_types': objectTypes!.join(','),
  };
}

/// Pull response: ordered page + `next_seq` (05 §4) + `store_epoch`.
@immutable
final class PullResponse {
  /// Creates a response.
  const PullResponse({
    required this.storeEpoch,
    required this.envelopes,
    required this.nextSeq,
  });

  /// Decodes.
  factory PullResponse.fromJson(Map<String, Object?> j) => PullResponse(
    storeEpoch: j['store_epoch']! as String,
    envelopes: [
      for (final e in _list(j['envelopes'])) WireEnvelope.fromJson(e),
    ],
    nextSeq: j['next_seq']! as int,
  );

  /// `store_epoch`.
  final String storeEpoch;

  /// `envelopes` — ascending `seq`, every one carrying its `seq`.
  final List<WireEnvelope> envelopes;

  /// `next_seq` — the cursor to store; equals `after_seq` on an empty page.
  final int nextSeq;

  /// Whether another page may follow.
  bool get hasMore => envelopes.isNotEmpty;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'store_epoch': storeEpoch,
    'envelopes': [for (final e in envelopes) e.toJson()],
    'next_seq': nextSeq,
  };
}

/// `GET /sync/meta?after=cursor` (05 §5). The cursor is opaque to the client
/// (the server encodes per-table `updated_at,id` positions inside it).
@immutable
final class MetaRequest {
  /// Creates a meta pull.
  const MetaRequest({this.after});

  /// Decodes.
  factory MetaRequest.fromJson(Map<String, Object?> j) =>
      MetaRequest(after: j['after'] as String?);

  /// `after` — null on bootstrap.
  final String? after;

  /// Encodes.
  Map<String, Object?> toJson() => {if (after != null) 'after': after};
}

/// A signed record on the wire (ADR 05b §1 `SignedRecord{…}`), stamped with
/// the server `seq` it shares with envelopes (ADR 05b §5).
@immutable
final class WireSignedRecord {
  /// Creates a wire record.
  const WireSignedRecord({
    required this.id,
    required this.suiteVersion,
    required this.tenantId,
    required this.kind,
    required this.payloadJson,
    required this.authorDeviceId,
    required this.authorSig,
    required this.hlc,
    required this.seq,
  });

  /// Decodes.
  factory WireSignedRecord.fromJson(Map<String, Object?> j) => WireSignedRecord(
    id: j['id']! as String,
    suiteVersion: j['suite_version']! as int,
    tenantId: j['tenant_id']! as String,
    kind: j['kind']! as String,
    payloadJson: _bytes(j['payload_json']),
    authorDeviceId: j['author_device_id']! as String,
    authorSig: _bytes(j['author_sig']),
    hlc: j['hlc']! as int,
    seq: j['seq']! as int,
  );

  /// `id` — ⚠️ WIRE: the record's row id (ADR 05b §1 names no id; the
  /// client's `signed_records_local.id` needs one).
  final String id;

  /// `suite_version`.
  final int suiteVersion;

  /// `tenant_id`.
  final String tenantId;

  /// `kind`.
  final String kind;

  /// `payload_json` — the exact signed bytes, base64url on the wire.
  final Uint8List payloadJson;

  /// `author_device_id`.
  final String authorDeviceId;

  /// `author_sig`.
  final Uint8List authorSig;

  /// `hlc`.
  final int hlc;

  /// `seq` — shares the envelope sequence (ADR 05b §5).
  final int seq;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'id': id,
    'suite_version': suiteVersion,
    'tenant_id': tenantId,
    'kind': kind,
    'payload_json': _b64(payloadJson),
    'author_device_id': authorDeviceId,
    'author_sig': _b64(authorSig),
    'hlc': hlc,
    'seq': seq,
  };
}

/// A `wrapped_keys` row (03 §2.2).
@immutable
final class WireWrappedKey {
  /// Creates a row.
  const WireWrappedKey({
    required this.id,
    required this.kind,
    required this.userId,
    required this.blob,
    this.recipientFingerprint,
    this.deviceId,
    this.bookId,
    this.keyVersion,
    this.shareSetVersion,
    this.revokedAt,
  });

  /// Decodes. `created_at` / `updated_at` (epoch ms) are not read.
  factory WireWrappedKey.fromJson(Map<String, Object?> j) => WireWrappedKey(
    id: j['id']! as String,
    kind: j['kind']! as String,
    userId: j['user_id']! as String,
    deviceId: j['device_id'] as String?,
    bookId: j['book_id'] as String?,
    keyVersion: j['key_version'] as int?,
    shareSetVersion: j['share_set_version'] as int?,
    blob: _bytes(j['blob']),
    recipientFingerprint: j['recipient_fingerprint'] == null
        ? null
        : _bytes(j['recipient_fingerprint']),
    revokedAt: j['revoked_at'] as int?,
  );

  /// Book key sealed to a member's UMK.
  static const String kindBkForUser = 'bk_for_user';

  /// `id`.
  final String id;

  /// `kind` — `umk_for_device | bk_for_user | guardian_share | recovery_blob | escrow_blob`.
  final String kind;

  /// `user_id` — the recipient user.
  final String userId;

  /// `device_id`.
  final String? deviceId;

  /// `book_id`.
  final String? bookId;

  /// `key_version`.
  final int? keyVersion;

  /// `share_set_version`.
  final int? shareSetVersion;

  /// `blob` — `crypto_box_seal` ciphertext.
  final Uint8List blob;

  /// `recipient_fingerprint` — optional. 03 §2.2 has no such column and the
  /// server sends none: the engine selects its own copies by `user_id` and
  /// the unseal itself proves the recipient (04 §8.2). When a sender does
  /// include it, the guard checks it too.
  final Uint8List? recipientFingerprint;

  /// `revoked_at` (epoch ms).
  final int? revokedAt;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'user_id': userId,
    if (deviceId != null) 'device_id': deviceId,
    if (bookId != null) 'book_id': bookId,
    if (keyVersion != null) 'key_version': keyVersion,
    if (shareSetVersion != null) 'share_set_version': shareSetVersion,
    'blob': _b64(blob),
    if (recipientFingerprint != null)
      'recipient_fingerprint': _b64(recipientFingerprint!),
    if (revokedAt != null) 'revoked_at': revokedAt,
  };
}

/// A `devices` row (03 §2.2) — the server's projection of device state.
/// `model`, `os`, `updated_at` also arrive and are not read.
@immutable
final class WireDevice {
  /// Creates a row.
  const WireDevice({
    required this.id,
    required this.userId,
    required this.pubEd,
    required this.pubX,
    required this.status,
    this.revokedAt,
  });

  /// Decodes.
  factory WireDevice.fromJson(Map<String, Object?> j) => WireDevice(
    id: j['id']! as String,
    userId: j['user_id']! as String,
    pubEd: _bytes(j['pub_ed']),
    pubX: _bytes(j['pub_x']),
    status: j['status']! as String,
    revokedAt: j['revoked_at'] as int?,
  );

  /// `status` — OTP-only, no certificate yet (ADR 05d §2).
  static const String statusRegistered = 'registered';

  /// `status` — certified by the user's UMK; the normal state.
  static const String statusCertified = 'certified';

  /// `status` — suspended by support / pending.
  static const String statusSuspended = 'suspended';

  /// `status` value for a revoked device.
  static const String statusRevoked = 'revoked';

  /// `id`.
  final String id;

  /// `user_id`.
  final String userId;

  /// `pub_ed`.
  final Uint8List pubEd;

  /// `pub_x`.
  final Uint8List pubX;

  /// `status` — `registered | certified | suspended | revoked` (03 §2.2).
  final String status;

  /// `revoked_at` (epoch ms).
  final int? revokedAt;

  /// Whether the row claims revocation (a claim until a record proves it).
  bool get claimsRevoked => status == statusRevoked || revokedAt != null;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'id': id,
    'user_id': userId,
    'pub_ed': _b64(pubEd),
    'pub_x': _b64(pubX),
    'status': status,
    if (revokedAt != null) 'revoked_at': revokedAt,
  };
}

/// A `device_certs` row (03 §2.2). `cert` is the 64-byte UMK signature in 03;
/// the server ships it as `cert:{suite_version, issued_at_ms, signature}`.
/// There is **no** `cert.user_id`: the signed message is
/// `uuid16(device) ‖ pub_ed ‖ pub_x ‖ i64be(issued_at_ms)` (core_crypto
/// `DeviceCert.signedBytes`), so the user and the public keys both come from
/// the `devices` row with the same `device_id` in the same response.
@immutable
final class WireDeviceCert {
  /// Creates a row.
  const WireDeviceCert({
    required this.deviceId,
    required this.suiteVersion,
    required this.issuedAtMs,
    required this.signature,
    required this.issuedByDevice,
    this.umkKeyVersion,
  });

  /// Decodes. `updated_at` (epoch ms) is not read.
  factory WireDeviceCert.fromJson(Map<String, Object?> j) {
    final cert = j['cert']! as Map<String, Object?>;
    return WireDeviceCert(
      deviceId: j['device_id']! as String,
      issuedByDevice: j['issued_by_device'] as String?,
      umkKeyVersion: j['umk_key_version'] as int?,
      suiteVersion: cert['suite_version']! as int,
      issuedAtMs: cert['issued_at_ms'] as int?,
      signature: _bytes(cert['signature']),
    );
  }

  /// `device_id`.
  final String deviceId;

  /// `cert.suite_version`.
  final int suiteVersion;

  /// `cert.issued_at_ms` — null when the server has no issue time; such a
  /// certificate cannot be verified and is skipped.
  final int? issuedAtMs;

  /// `cert.signature` — Ed25519 under the user's UMK.
  final Uint8List signature;

  /// `issued_by_device`.
  final String? issuedByDevice;

  /// `umk_key_version` — the UMK version that signed (03 §2.2).
  final int? umkKeyVersion;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'device_id': deviceId,
    'issued_by_device': issuedByDevice,
    if (umkKeyVersion != null) 'umk_key_version': umkKeyVersion,
    'cert': {
      'suite_version': suiteVersion,
      'issued_at_ms': issuedAtMs,
      'signature': _b64(signature),
    },
  };
}

/// A `memberships` row (03 §2.1) — the server's projection. `id` is
/// `"tenant_id:user_id"`; `source_record_id` and `updated_at` also arrive and
/// are not read.
@immutable
final class WireMembership {
  /// Creates a row.
  const WireMembership({
    required this.id,
    required this.tenantId,
    required this.userId,
    required this.status,
  });

  /// Decodes.
  factory WireMembership.fromJson(Map<String, Object?> j) => WireMembership(
    id: j['id']! as String,
    tenantId: j['tenant_id']! as String,
    userId: j['user_id']! as String,
    status: j['status']! as String,
  );

  /// `id`.
  final String id;

  /// `tenant_id`.
  final String tenantId;

  /// `user_id`.
  final String userId;

  /// `status`.
  final String status;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'id': id,
    'tenant_id': tenantId,
    'user_id': userId,
    'status': status,
  };
}

/// A `book_roles` row (03 §2.1) — the server's projection of a `book_role`
/// signed record. `id` is `"book_id:user_id"`; `limits` is
/// `{auto_post_limit_paise: int}` and present only when a limit is set;
/// `source_record_id` and `updated_at` also arrive and are not read.
@immutable
final class WireBookRole {
  /// Creates a row.
  const WireBookRole({
    required this.id,
    required this.bookId,
    required this.userId,
    required this.role,
    this.limits,
  });

  /// Decodes.
  factory WireBookRole.fromJson(Map<String, Object?> j) => WireBookRole(
    id: j['id']! as String,
    bookId: j['book_id']! as String,
    userId: j['user_id']! as String,
    role: j['role'] as String?,
    limits: j['limits'] as Map<String, Object?>?,
  );

  /// The `limits` key for the per-entry auto-post cap, integer paise.
  static const String autoPostLimitPaise = 'auto_post_limit_paise';

  /// `id`.
  final String id;

  /// `book_id`.
  final String bookId;

  /// `user_id`.
  final String userId;

  /// `role` — null when the record removed the role (server `role ?? null`).
  final String? role;

  /// `limits` — plaintext limits JSON (03 §4): `{auto_post_limit_paise}`.
  final Map<String, Object?>? limits;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'id': id,
    'book_id': bookId,
    'user_id': userId,
    'role': role,
    if (limits != null) 'limits': limits,
  };
}

/// Guardian-set history by `share_set_version` (PLAN M4 lane S; ADR
/// 2026-09-06 §3 needs "who was a guardian at the version the record names").
/// Shape: `subject_user_id`, `share_set_version`, `k`, `n`,
/// `guardian_user_ids[]`; the server adds `guardians:[{guardian_user_id,
/// umk_pub_ed}]`, not read here.
@immutable
final class WireGuardianSet {
  /// Creates a row.
  const WireGuardianSet({
    required this.subjectUserId,
    required this.shareSetVersion,
    required this.k,
    required this.guardianUserIds,
  });

  /// Decodes.
  factory WireGuardianSet.fromJson(Map<String, Object?> j) => WireGuardianSet(
    subjectUserId: j['subject_user_id']! as String,
    shareSetVersion: j['share_set_version']! as int,
    k: j['k']! as int,
    guardianUserIds: (j['guardian_user_ids']! as List<Object?>).cast<String>(),
  );

  /// `subject_user_id`.
  final String subjectUserId;

  /// `share_set_version`.
  final int shareSetVersion;

  /// `k`.
  final int k;

  /// `guardian_user_ids`.
  final List<String> guardianUserIds;

  /// `n`.
  int get n => guardianUserIds.length;

  /// Encodes.
  Map<String, Object?> toJson() => {
    'subject_user_id': subjectUserId,
    'share_set_version': shareSetVersion,
    'k': k,
    'n': n,
    'guardian_user_ids': guardianUserIds,
  };
}

/// Meta response (05 §5): every table the engine consumes, plus `next`,
/// `has_more` and `store_epoch`. Tables and fields this package does not read
/// yet (invites, verification_events, subscriptions, entitlement tokens,
/// escrow states, tombstones, `umk_public_keys`, `min_client_version`) are
/// carried through in [extra] untouched (rule 6).
@immutable
final class MetaResponse {
  /// Creates a response.
  const MetaResponse({
    required this.storeEpoch,
    required this.next,
    this.hasMore = false,
    this.signedRecords = const [],
    this.wrappedKeys = const [],
    this.devices = const [],
    this.deviceCerts = const [],
    this.memberships = const [],
    this.bookRoles = const [],
    this.guardianSets = const [],
    this.extra = const {},
  });

  /// Decodes.
  factory MetaResponse.fromJson(Map<String, Object?> j) => MetaResponse(
    storeEpoch: j['store_epoch']! as String,
    next: j['next'] as String?,
    hasMore: (j['has_more'] as bool?) ?? false,
    signedRecords: [
      for (final r in _list(j['signed_records'])) WireSignedRecord.fromJson(r),
    ],
    wrappedKeys: [
      for (final r in _list(j['wrapped_keys'])) WireWrappedKey.fromJson(r),
    ],
    devices: [for (final r in _list(j['devices'])) WireDevice.fromJson(r)],
    deviceCerts: [
      for (final r in _list(j['device_certs'])) WireDeviceCert.fromJson(r),
    ],
    memberships: [
      for (final r in _list(j['memberships'])) WireMembership.fromJson(r),
    ],
    bookRoles: [
      for (final r in _list(j['book_roles'])) WireBookRole.fromJson(r),
    ],
    guardianSets: [
      for (final r in _list(j['guardian_sets'])) WireGuardianSet.fromJson(r),
    ],
    extra: {
      for (final e in j.entries)
        if (!_known.contains(e.key)) e.key: e.value,
    },
  );

  static const _known = {
    'store_epoch',
    'next',
    'has_more',
    'signed_records',
    'wrapped_keys',
    'devices',
    'device_certs',
    'memberships',
    'book_roles',
    'guardian_sets',
  };

  /// `store_epoch`.
  final String storeEpoch;

  /// `next` — the opaque cursor to send on the next request: always the
  /// position after this page (the server sends it on every response), so a
  /// client at the head keeps receiving it unchanged.
  final String? next;

  /// `has_more` — true when another page is available right now (the client
  /// keeps paging), false when this page is the head. Always sent.
  final bool hasMore;

  /// `min_client_version` — `{sync, auth}` if the server sent it (kept in
  /// [extra]; typed access for the update screen).
  Map<String, Object?>? get minClientVersion =>
      extra['min_client_version'] as Map<String, Object?>?;

  /// `signed_records`.
  final List<WireSignedRecord> signedRecords;

  /// `wrapped_keys`.
  final List<WireWrappedKey> wrappedKeys;

  /// `devices`.
  final List<WireDevice> devices;

  /// `device_certs`.
  final List<WireDeviceCert> deviceCerts;

  /// `memberships`.
  final List<WireMembership> memberships;

  /// `book_roles`.
  final List<WireBookRole> bookRoles;

  /// `guardian_sets`.
  final List<WireGuardianSet> guardianSets;

  /// Tables not consumed here, preserved as received.
  final Map<String, Object?> extra;

  /// Whether any table carried rows.
  bool get isEmpty =>
      signedRecords.isEmpty &&
      wrappedKeys.isEmpty &&
      devices.isEmpty &&
      deviceCerts.isEmpty &&
      memberships.isEmpty &&
      bookRoles.isEmpty &&
      guardianSets.isEmpty;

  /// Encodes.
  Map<String, Object?> toJson() => {
    ...extra,
    'store_epoch': storeEpoch,
    if (next != null) 'next': next,
    'has_more': hasMore,
    'signed_records': [for (final r in signedRecords) r.toJson()],
    'wrapped_keys': [for (final r in wrappedKeys) r.toJson()],
    'devices': [for (final r in devices) r.toJson()],
    'device_certs': [for (final r in deviceCerts) r.toJson()],
    'memberships': [for (final r in memberships) r.toJson()],
    'book_roles': [for (final r in bookRoles) r.toJson()],
    'guardian_sets': [for (final r in guardianSets) r.toJson()],
  };
}
