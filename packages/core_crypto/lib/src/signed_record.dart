import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'bytes.dart';
import 'keys.dart';
import 'suite.dart';

// The class field `suiteVersion` shadows the library constant inside the
// class body; this alias resolves at file scope.
const int _currentSuite = suiteVersion;

/// Signed-record kinds (ADR 2026-09-05b §1; ADR 2026-09-05d §7). Plain
/// strings, not an enum: the server stores `kind text` and a reader must keep
/// an unknown kind's bytes rather than fail on it (rule 6).
abstract final class SignedRecordKind {
  /// Membership status change (05b §1).
  static const String membershipStatus = 'membership_status';

  /// Per-book role or limit (05b §1).
  static const String bookRole = 'book_role';

  /// Member removal (05b §1; 04 §5.3).
  static const String memberRemoval = 'member_removal';

  /// Device revocation (05b §1, §5; 04 §9.2).
  static const String deviceRevocation = 'device_revocation';

  /// A new certified device announcing itself (05d §6–§7).
  static const String deviceAdded = 'device_added';

  /// Book-key rotation notice (05b §1; 04 §5.3).
  // Record kind label, not key material (check_purity.sh excludes `kind`).
  static const String keyRotation = 'key_rotation'; // record kind

  /// Ceremony verification event — who verified whom, how (05d §7).
  static const String verificationEvent = 'verification_event';

  /// Designation (05b §1).
  static const String designation = 'designation';

  /// Every kind this build knows.
  static const Set<String> all = {
    membershipStatus,
    bookRole,
    memberRemoval,
    deviceRevocation,
    deviceAdded,
    keyRotation,
    verificationEvent,
    designation,
  };
}

/// A structural fact authored on a certified device (ADR 2026-09-05b §1 🔒):
///
/// ```
/// SignedRecord { suite_version, tenant_id, kind, payload_json (plaintext),
///                author_device_id, author_sig = Ed25519(BLAKE2b(payload ‖ header)),
///                hlc, seq }
/// ```
///
/// [payloadJson] is kept as the exact bytes that were signed and is never
/// re-serialised, so unknown payload fields survive storage and relay
/// (rule 6). The payload is plaintext by design — the server applies it to
/// its rows — so it must never carry financial content.
///
/// ⚠️ SPEC: the ADR fixes the digest as `BLAKE2b(payload ‖ header)` but not
/// the header's byte order. Chosen here: `u8(suite_version) ‖ uuid16(tenant)
/// ‖ lenPrefixedUtf8(kind) ‖ uuid16(author_device) ‖ i64be(hlc)`.
///
/// ⚠️ SPEC: `seq` is stamped by the server at receipt (05b §5) so it cannot
/// be part of the author's signature; it is excluded from the signed bytes
/// and is `null` until the record has been stored.
@immutable
final class SignedRecord {
  /// Assembles a record from stored parts (validates shape only).
  SignedRecord({
    required this.suiteVersion,
    required this.tenantId,
    required this.kind,
    required Uint8List payloadJson,
    required this.authorDeviceId,
    required Uint8List authorSig,
    required this.hlc,
    this.seq,
  }) : payloadJson = Uint8List.fromList(payloadJson),
       authorSig = Uint8List.fromList(authorSig) {
    if (!Uuid16.isCanonical(tenantId)) {
      throw FormatException('tenant_id must be a canonical uuid', tenantId);
    }
    if (!Uuid16.isCanonical(authorDeviceId)) {
      throw FormatException(
        'author_device_id must be a canonical uuid',
        authorDeviceId,
      );
    }
    if (kind.isEmpty) throw ArgumentError.value(kind, 'kind', 'empty');
    if (authorSig.length != signedRecordSigBytes) {
      throw ArgumentError.value(authorSig.length, 'authorSig', '64 bytes');
    }
    if (seq != null && seq! < 1) {
      throw ArgumentError.value(seq, 'seq', 'server seq starts at 1');
    }
  }

  /// Signs [payloadJson] (which must be a UTF-8 JSON object — decoded once
  /// to check, then kept byte-for-byte) as [author]. [hlc] is injected.
  factory SignedRecord.sign(
    CryptoSuite suite, {
    required String tenantId,
    required String kind,
    required Uint8List payloadJson,
    required int hlc,
    required DeviceKeyPair author,
  }) {
    _requireJsonObject(payloadJson);
    final header = headerBytes(
      suiteVersion: _currentSuite,
      tenantId: tenantId,
      kind: kind,
      authorDeviceId: author.deviceId,
      hlc: hlc,
    );
    final sig = suite.sodium.crypto.sign.detached(
      message: suite.blake2b256(Bytes.concat([payloadJson, header])),
      secretKey: author.ed25519Secret,
    );
    return SignedRecord(
      suiteVersion: _currentSuite,
      tenantId: tenantId,
      kind: kind,
      payloadJson: payloadJson,
      authorDeviceId: author.deviceId,
      authorSig: sig,
      hlc: hlc,
    );
  }

  /// Ed25519 detached signature length.
  static const int signedRecordSigBytes = 64;

  /// The signed header:
  /// `u8(suite) ‖ uuid16(tenant) ‖ lenPrefixedUtf8(kind) ‖ uuid16(author_device) ‖ i64be(hlc)`.
  static Uint8List headerBytes({
    required int suiteVersion,
    required String tenantId,
    required String kind,
    required String authorDeviceId,
    required int hlc,
  }) => Bytes.concat([
    Bytes.u8(suiteVersion),
    Uuid16.toBytes(tenantId),
    Bytes.lengthPrefixedUtf8(kind),
    Uuid16.toBytes(authorDeviceId),
    Bytes.i64be(hlc),
  ]);

  /// `suite_version` (04 §2).
  final int suiteVersion;

  /// Tenant the fact belongs to.
  final String tenantId;

  /// One of [SignedRecordKind] (or a kind a newer build introduced).
  final String kind;

  /// The exact signed payload bytes — UTF-8 JSON object, plaintext.
  final Uint8List payloadJson;

  /// Authoring device.
  final String authorDeviceId;

  /// `Ed25519(BLAKE2b-256(payload ‖ header))` under the author device key.
  final Uint8List authorSig;

  /// Author's hybrid logical clock (05 §2).
  final int hlc;

  /// Server receipt sequence — shares the envelope sequence space (05b §5).
  /// `null` until stored; never signed.
  final int? seq;

  /// This record's header bytes.
  Uint8List get header => headerBytes(
    suiteVersion: suiteVersion,
    tenantId: tenantId,
    kind: kind,
    authorDeviceId: authorDeviceId,
    hlc: hlc,
  );

  /// The bytes the author signed: `BLAKE2b-256(payload ‖ header)`.
  Uint8List signedDigest(CryptoSuite suite) =>
      suite.blake2b256(Bytes.concat([payloadJson, header]));

  /// Decodes [payloadJson]. Unknown fields are present because the bytes
  /// were never rewritten. Throws [FormatException] if the bytes are not a
  /// JSON object.
  Map<String, Object?> get payload => _requireJsonObject(payloadJson);

  /// Checks [authorSig] under [author]'s Ed25519 key (and that [author] is
  /// the claimed device). Does **not** walk the certificate chain — use
  /// `ChainVerifier.verifySignedRecord` (04 §3.4, 05b §1).
  bool verifySignature(CryptoSuite suite, DevicePublic author) {
    if (author.deviceId != authorDeviceId) return false;
    return suite.sodium.crypto.sign.verifyDetached(
      message: signedDigest(suite),
      signature: authorSig,
      publicKey: author.ed25519,
    );
  }

  /// The same record with the server-assigned [seq] attached.
  SignedRecord withSeq(int seq) => SignedRecord(
    suiteVersion: suiteVersion,
    tenantId: tenantId,
    kind: kind,
    payloadJson: payloadJson,
    authorDeviceId: authorDeviceId,
    authorSig: authorSig,
    hlc: hlc,
    seq: seq,
  );

  static Map<String, Object?> _requireJsonObject(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('signed-record payload is not a JSON object');
    }
    return Map<String, Object?>.from(decoded);
  }
}
