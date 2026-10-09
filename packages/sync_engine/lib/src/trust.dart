// The reader's trust state (04 §3.4) assembled from meta: ceremony-verified
// UMKs (injected — only a human can produce one), device certificates from
// `device_certs` + `devices`, and revocation cut-offs derived live from the
// verified `device_revocation` / `member_removal` records (ADR 05b §5; ADR
// 2026-09-06 §3). `revocationSeqOf` is computed on every call — never cached.
import 'package:core_crypto/core_crypto.dart';

import 'binding.dart';
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

/// The [VerifiedUmkSource] of whatever key material [keys] answers **now**
/// (ADR 2026-10-09 §1 🔒): read at every call, never captured, so a C-04b-3
/// re-mint or the S0.2 mint is believed at the next verification and the
/// discarded user is not. Before the keys exist it believes nobody, and it
/// believes nobody through a pair the holder has disposed — a fail-closed
/// answer, never a guess.
final class BoundUmkSource implements VerifiedUmkSource {
  /// Creates the source over [keys].
  const BoundUmkSource(this.keys);

  /// Where the material is read.
  final KeyMaterialSource keys;

  @override
  VerifiedUmkPublic? verifiedUmkOf(String userId) =>
      switch (keys.currentKeys()) {
        KeysNotRegisteredYet() => null,
        DeviceKeyMaterial(:final device, :final umk)
            when device.isDisposed || (umk?.isDisposed ?? false) =>
          null,
        DeviceKeyMaterial(:final verifiedUmks) => verifiedUmks?.verifiedUmkOf(
          userId,
        ),
      };
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
  /// Creates the store over [umks] — read live on every verification.
  RecordTrustStore({required this.umks});

  /// Creates the store believing the UMKs of whatever material [keys]
  /// answers at each verification ([BoundUmkSource]) — believing nobody
  /// before S0.2 (ADR 2026-10-09 §1 🔒).
  RecordTrustStore.late({required KeyMaterialSource keys})
    : umks = BoundUmkSource(keys);

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

  /// Verified membership facts (`membership_status`, `member_removal`) of
  /// every tenant, each with the tenant it was filed in (ADR 2026-10-03b §2).
  final List<MembershipFact> memberships = [];

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
  /// A record counts only if its subject is the device's owner: [ownerUserId]
  /// when given — the engine passes its own user for its own device, which it
  /// knows without asking the server — else [userOf].
  RevocationCount countFor(String deviceId, {String? ownerUserId}) =>
      countRevocation(
        revokedDeviceId: deviceId,
        revokedDeviceOwner: ownerUserId ?? userOf(deviceId),
        records: revocations,
        history: guardianHistory,
        memberships: memberships,
      );

  @override
  int? revocationSeqOf(String deviceId) => revocationSeqFor(deviceId);

  /// [revocationSeqOf] with the device's owner given, as in [countFor].
  int? revocationSeqFor(String deviceId, {String? ownerUserId}) {
    final user = ownerUserId ?? userOf(deviceId);
    int? cutoff = countFor(deviceId, ownerUserId: user).effectiveSeq;
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
