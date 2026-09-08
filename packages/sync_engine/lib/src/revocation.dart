// Revocation cut-off by server `seq` (ADR 2026-09-05b §5) including the
// guardians' k-of-n counting rule (ADR 2026-09-06 §3). Pure: a function of
// the record set and the guardian-set history — recomputed every time, never
// cached as final, so the cut-off can only move earlier and every reader agrees
// regardless of arrival order.
import 'package:meta/meta.dart';

/// A verified `device_revocation` record reduced to what counting needs.
@immutable
final class RevocationRecord {
  /// Creates the record.
  const RevocationRecord({
    required this.recordId,
    required this.seq,
    required this.authorDeviceId,
    required this.authorUserId,
    required this.revokedDeviceId,
    required this.subjectUserId,
    this.shareSetVersion,
  });

  /// Record id.
  final String recordId;

  /// Server `seq` — the candidate cut-off.
  final int seq;

  /// Authoring device (chain-verified).
  final String authorDeviceId;

  /// The author's user (from the device certificate).
  final String authorUserId;

  /// `revoked_device_id`.
  final String revokedDeviceId;

  /// `subject_user_id` — the revoked device's owner.
  final String subjectUserId;

  /// `share_set_version` a guardian record names; null on an owner's record.
  final int? shareSetVersion;

  /// Authored by a certified device of the subject (04 §9.2 own-device path).
  bool get byOwner => authorUserId == subjectUserId;
}

/// One version of a subject's guardian set.
@immutable
final class GuardianSetVersion {
  /// Creates the version.
  const GuardianSetVersion({
    required this.subjectUserId,
    required this.shareSetVersion,
    required this.k,
    required this.guardianUserIds,
  });

  /// Subject.
  final String subjectUserId;

  /// Version.
  final int shareSetVersion;

  /// Threshold at this version.
  final int k;

  /// Guardians at this version.
  final Set<String> guardianUserIds;
}

/// Why a record was not counted.
enum IgnoreReason {
  /// The record names no `share_set_version` and is not the owner's.
  noVersion,

  /// No guardian set is known at the version named.
  unknownVersion,

  /// The author was not a guardian at the version named.
  notGuardian,

  /// The same author already counted (earliest `seq` kept).
  duplicateAuthor,
}

/// A record that did not count, with the reason (logged, ADR 2026-09-06 §3).
@immutable
final class IgnoredRecord {
  /// Creates the entry.
  const IgnoredRecord(this.recordId, this.reason);

  /// Record.
  final String recordId;

  /// Why.
  final IgnoreReason reason;
}

/// The result of counting for one revoked device.
@immutable
final class RevocationCount {
  /// Creates the result.
  const RevocationCount({
    required this.effectiveSeq,
    required this.countedGuardians,
    required this.threshold,
    required this.ignored,
    required this.ownerSeq,
  });

  /// The cut-off, or null while the revocation is not effective.
  final int? effectiveSeq;

  /// Distinct guardian authors counted.
  final int countedGuardians;

  /// The k applied — of the *earliest* version among counted records; null
  /// when no guardian record counted.
  final int? threshold;

  /// Records that did not count.
  final List<IgnoredRecord> ignored;

  /// Cut-off from the owner's own record, if any.
  final int? ownerSeq;
}

/// Counts the revocation of [revokedDeviceId] from [records] (already
/// chain-verified) against [history].
///
/// - An owner's record (any certified device of the subject, 04 §9.2) is
///   effective alone at its `seq`.
/// - Guardian records count when the author was a guardian at the version the
///   record names; one per author (earliest `seq`); approvals carry across
///   versions; the threshold is the k of the earliest version among counted
///   records; effective at the k-th smallest `seq`.
/// - The cut-off is the minimum of the two paths — it only moves earlier.
RevocationCount countRevocation({
  required String revokedDeviceId,
  required Iterable<RevocationRecord> records,
  required Iterable<GuardianSetVersion> history,
}) {
  final byVersion = <(String, int), GuardianSetVersion>{
    for (final v in history) (v.subjectUserId, v.shareSetVersion): v,
  };
  int? ownerSeq;
  final ignored = <IgnoredRecord>[];
  final counted = <String, RevocationRecord>{}; // author user → earliest record
  final sorted =
      records.where((r) => r.revokedDeviceId == revokedDeviceId).toList()
        ..sort((a, b) => a.seq.compareTo(b.seq));
  for (final r in sorted) {
    if (r.byOwner) {
      if (ownerSeq == null || r.seq < ownerSeq) ownerSeq = r.seq;
      continue;
    }
    final version = r.shareSetVersion;
    if (version == null) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.noVersion));
      continue;
    }
    final set = byVersion[(r.subjectUserId, version)];
    if (set == null) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.unknownVersion));
      continue;
    }
    if (!set.guardianUserIds.contains(r.authorUserId)) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.notGuardian));
      continue;
    }
    if (counted.containsKey(r.authorUserId)) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.duplicateAuthor));
      continue;
    }
    counted[r.authorUserId] = r;
  }
  int? threshold;
  int? guardianSeq;
  if (counted.isNotEmpty) {
    final earliestVersion = counted.values
        .map((r) => r.shareSetVersion!)
        .reduce((a, b) => a < b ? a : b);
    final subject = counted.values.first.subjectUserId;
    threshold = byVersion[(subject, earliestVersion)]!.k;
    final seqs = counted.values.map((r) => r.seq).toList()..sort();
    if (seqs.length >= threshold) guardianSeq = seqs[threshold - 1];
  }
  int? effective = ownerSeq;
  if (guardianSeq != null && (effective == null || guardianSeq < effective)) {
    effective = guardianSeq;
  }
  return RevocationCount(
    effectiveSeq: effective,
    countedGuardians: counted.length,
    threshold: threshold,
    ignored: ignored,
    ownerSeq: ownerSeq,
  );
}
