import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'device_cert.dart';
import 'envelope.dart';
import 'keys.dart';
import 'signed_record.dart';
import 'suite.dart';

/// What a reader already trusts, per tenant (04 §3.4; ADR 2026-09-05b §5).
///
/// One instance is scoped to **one tenant**: [verifiedUmkOf] answers "was
/// this user's fingerprint confirmed by ceremony *for this tenant*".
///
/// ⚠️ SPEC: the store's shape is this package's choice — 04 names the three
/// facts (verified UMK, device cert, revocation) but not where they live;
/// `packages/data` backs them with `verification_events`, `devices` and the
/// `device_revocation` signed records (05b §1, §5).
abstract interface class TrustStore {
  /// The ceremony-verified UMK of [userId] in this tenant, or `null` if no
  /// human has confirmed their fingerprint (04 §6).
  VerifiedUmkPublic? verifiedUmkOf(String userId);

  /// The certificate of [deviceId], or `null` if unknown.
  DeviceCert? certOf(String deviceId);

  /// Server `seq` of [deviceId]'s verified revocation record (or of its
  /// owner's removal), or `null` if the device is not revoked (05b §5).
  int? revocationSeqOf(String deviceId);
}

/// Why an artefact was quarantined (04 §8.3).
enum QuarantineReason {
  /// `suite_version` this build cannot verify (04 §8.5).
  suiteUnsupported,

  /// No certificate for the author device.
  certMissing,

  /// The certificate does not verify under the claimed user's verified UMK
  /// (or names a different device).
  certInvalid,

  /// The certificate's user has no ceremony-verified UMK in this tenant —
  /// nothing roots the chain (04 §3.4 "verified by ceremony").
  authorUnverified,

  /// The author signature does not verify under the certified device key.
  sigInvalid,

  /// Authored at or after the device's revocation `seq` (05b §5; 04 §9.2).
  revoked,
}

/// Outcome of a chain check (04 §3.4, §8.3; ADR 2026-09-05c §2).
@immutable
sealed class ChainVerdict {
  const ChainVerdict();

  /// Whether the reader must raise a security event. Corruption never does
  /// (05c §2 — "corruption is not tampering"); every quarantine does.
  bool get securityEvent;
}

/// Signature chain intact: sig ✓ under device key → cert ✓ under the author's
/// UMK → UMK verified by ceremony → not revoked at this `seq`.
final class ChainVerified extends ChainVerdict {
  /// Creates the verdict.
  const ChainVerified();

  @override
  bool get securityEvent => false;
}

/// `blob_hash` did not match the blob (05c §2): corruption — re-fetch or
/// re-bootstrap, count `blob_corrupt`, **no quarantine, no security event**.
final class ChainCorrupt extends ChainVerdict {
  /// Creates the verdict.
  const ChainCorrupt();

  @override
  bool get securityEvent => false;
}

/// The chain failed: quarantine the artefact and raise a security event
/// (04 §8.3). Never display its content as trusted.
final class ChainQuarantine extends ChainVerdict {
  /// Creates the verdict.
  const ChainQuarantine(this.reason);

  /// Which link failed.
  final QuarantineReason reason;

  @override
  bool get securityEvent => true;

  @override
  String toString() => 'ChainQuarantine(${reason.name})';
}

/// Walks the trust chain of 04 §3.4 for envelopes and signed records.
///
/// Order of checks for an envelope: blob hash → suite → cert present → cert
/// valid under the author's ceremony-verified UMK → author sig → revocation
/// `seq`. A signed record skips the hash (it has no blob) and is otherwise
/// identical (05b §1 "clients verify the record: sig → cert → verified UMK").
final class ChainVerifier {
  /// Creates a verifier over [trust] (one tenant's trust state).
  const ChainVerifier(this.suite, this.trust);

  /// Crypto suite.
  final CryptoSuite suite;

  /// Trust state for the tenant being read.
  final TrustStore trust;

  /// Verifies [envelope].
  ///
  /// [expectedBlobHash] is the stored `blob_hash` column (05c §2); when
  /// given and different from `BLAKE2b-256(blob)` the verdict is
  /// [ChainCorrupt] before anything else is examined. [seq] is the server
  /// sequence of this envelope (`null` for an envelope not yet stored, e.g.
  /// the author's own outbox).
  ///
  /// ⚠️ SPEC (conservative reading of 05b §5): when the author device has a
  /// revocation on file and the envelope's [seq] is unknown, the envelope is
  /// quarantined as [QuarantineReason.revoked] — it cannot be shown to sit
  /// below the cut-off.
  ChainVerdict verifyEnvelope(
    Envelope envelope, {
    int? seq,
    Uint8List? expectedBlobHash,
  }) {
    if (expectedBlobHash != null &&
        !suite.constantTimeEquals(expectedBlobHash, envelope.blobHash(suite))) {
      return const ChainCorrupt();
    }
    return _verifyChain(
      suiteVersion: envelope.suiteVersion,
      authorDeviceId: envelope.authorDeviceId,
      seq: seq,
      sigOk: (device) => envelope.verifyAuthorSig(suite, device),
    );
  }

  /// Verifies [record] (05b §1). The revocation cut-off uses `record.seq`.
  ChainVerdict verifySignedRecord(SignedRecord record) => _verifyChain(
    suiteVersion: record.suiteVersion,
    authorDeviceId: record.authorDeviceId,
    seq: record.seq,
    sigOk: (device) => record.verifySignature(suite, device),
  );

  ChainVerdict _verifyChain({
    required int suiteVersion,
    required String authorDeviceId,
    required int? seq,
    required bool Function(DevicePublic device) sigOk,
  }) {
    if (suiteVersion != _currentSuite) {
      return const ChainQuarantine(QuarantineReason.suiteUnsupported);
    }
    final cert = trust.certOf(authorDeviceId);
    if (cert == null) {
      return const ChainQuarantine(QuarantineReason.certMissing);
    }
    if (cert.deviceId != authorDeviceId) {
      return const ChainQuarantine(QuarantineReason.certInvalid);
    }
    final umk = trust.verifiedUmkOf(cert.userId);
    if (umk == null) {
      return const ChainQuarantine(QuarantineReason.authorUnverified);
    }
    if (cert.suiteVersion != _currentSuite) {
      return const ChainQuarantine(QuarantineReason.suiteUnsupported);
    }
    if (!cert.verify(suite, umk.public)) {
      return const ChainQuarantine(QuarantineReason.certInvalid);
    }
    if (!sigOk(cert.device)) {
      return const ChainQuarantine(QuarantineReason.sigInvalid);
    }
    final revokedAt = trust.revocationSeqOf(authorDeviceId);
    if (revokedAt != null && (seq == null || seq >= revokedAt)) {
      return const ChainQuarantine(QuarantineReason.revoked);
    }
    return const ChainVerified();
  }
}

/// Suites this build can verify (04 §8.5: old suites stay readable ≥ 2 years;
/// only `0x01` exists today).
const int _currentSuite = suiteVersion;
