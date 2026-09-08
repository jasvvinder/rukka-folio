// The reader's trust state (04 §3.4) assembled from meta: ceremony-verified
// UMKs (injected — only a human can produce one), device certificates from
// `device_certs` + `devices`, and revocation cut-offs derived live from the
// verified `device_revocation` / `member_removal` records (ADR 05b §5; ADR
// 2026-09-06 §3). `revocationSeqOf` is computed on every call — never cached.
import 'package:core_crypto/core_crypto.dart';

import 'revocation.dart';

/// Where ceremony-verified UMKs come from (the app's `verification_events`).
abstract interface class VerifiedUmkSource {
  /// The verified UMK of [userId] in this tenant, or null.
  VerifiedUmkPublic? verifiedUmkOf(String userId);
}

/// A map-backed [VerifiedUmkSource].
final class MapUmkSource implements VerifiedUmkSource {
  /// Creates the source over [umks] (user id → verified UMK), read live.
  const MapUmkSource(this.umks);

  /// Backing map (the caller may keep adding to it).
  final Map<String, VerifiedUmkPublic> umks;

  @override
  VerifiedUmkPublic? verifiedUmkOf(String userId) => umks[userId];
}

/// A verified `member_removal` record reduced to what the cut-off needs.
final class RemovalRecord {
  /// Creates the record.
  const RemovalRecord({
    required this.recordId,
    required this.seq,
    required this.removedUserId,
  });

  /// Record id.
  final String recordId;

  /// Server `seq`.
  final int seq;

  /// `removed_user_id`.
  final String removedUserId;
}

/// Trust state for one tenant.
final class RecordTrustStore implements TrustStore {
  /// Creates the store.
  RecordTrustStore({required this.umks});

  /// Ceremony-verified UMKs.
  final VerifiedUmkSource umks;

  /// device id → certificate (from meta).
  final Map<String, DeviceCert> certs = {};

  /// Verified revocation records.
  final List<RevocationRecord> revocations = [];

  /// Verified removal records.
  final List<RemovalRecord> removals = [];

  /// Guardian-set history.
  final List<GuardianSetVersion> guardianHistory = [];

  /// device id → user id as the server's `devices` rows say. Only a
  /// fallback for [userOf] when no certificate is held (the two-client
  /// harness runs without certificates); a certificate always wins.
  final Map<String, String> deviceOwners = {};

  @override
  VerifiedUmkPublic? verifiedUmkOf(String userId) => umks.verifiedUmkOf(userId);

  @override
  DeviceCert? certOf(String deviceId) => certs[deviceId];

  /// The user a device belongs to (from its certificate, else the server's
  /// row), or null.
  String? userOf(String deviceId) =>
      certs[deviceId]?.userId ?? deviceOwners[deviceId];

  /// Full counting result for [deviceId] (tests and the Inbox read this).
  RevocationCount countFor(String deviceId) => countRevocation(
    revokedDeviceId: deviceId,
    records: revocations,
    history: guardianHistory,
  );

  @override
  int? revocationSeqOf(String deviceId) {
    int? cutoff = countFor(deviceId).effectiveSeq;
    final user = userOf(deviceId);
    if (user != null) {
      for (final r in removals) {
        if (r.removedUserId == user && (cutoff == null || r.seq < cutoff)) {
          cutoff = r.seq;
        }
      }
    }
    return cutoff;
  }
}
