// Revocation cut-off by server `seq` (ADR 2026-09-05b §5) including the
// guardians' k-of-n counting rule (ADR 2026-09-06 §3, as amended by ADR
// 2026-10-03b §2: a guardian approval counts only where it was filed in the
// tenant of the set version it names, while the subject is not removed
// there). Pure: a function of the record set, the guardian-set history, the
// membership facts and the revoked device's owner — recomputed every time,
// never cached as final, so the cut-off can only move earlier and every
// reader agrees regardless of arrival order *and of which other tenants it
// can see*.
import 'package:meta/meta.dart';

/// A verified `device_revocation` record reduced to what counting needs.
@immutable
final class RevocationRecord {
  /// Creates the record.
  const RevocationRecord({
    required this.recordId,
    required this.seq,
    required this.tenantId,
    required this.authorDeviceId,
    required this.authorUserId,
    required this.revokedDeviceId,
    required this.subjectUserId,
    this.shareSetVersion,
  });

  /// Record id.
  final String recordId;

  /// The tenant the record was filed in — `signed_records.tenant_id`, which
  /// is inside the author's signature (04 §3.3), so it is the author's claim
  /// and not the server's. A guardian record counts only when this is the
  /// tenant of the set version it names (ADR 2026-10-03b §2).
  final String tenantId;

  /// Server `seq` — the candidate cut-off.
  final int seq;

  /// Authoring device (chain-verified).
  final String authorDeviceId;

  /// The author's user (from the device certificate).
  final String authorUserId;

  /// `revoked_device_id`.
  final String revokedDeviceId;

  /// `subject_user_id` — the author's *claim* of the revoked device's owner;
  /// a record counts only when it is that owner
  /// ([IgnoreReason.notSubjectsDevice]).
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
    this.tenantId,
  });

  /// Subject.
  final String subjectUserId;

  /// Version.
  final int shareSetVersion;

  /// Threshold at this version.
  final int k;

  /// Guardians at this version.
  final Set<String> guardianUserIds;

  /// The tenant this version was set up in (`guardian_sets.tenant_id`, ADR
  /// 2026-10-03b §1). Null for a version published before that ADR: it still
  /// recovers (04 §7.3 does not read it) but no approval naming it counts.
  final String? tenantId;
}

/// A verified membership fact reduced to what counting needs: a
/// `membership_status {user_id, status}` record, or a `member_removal
/// {user_id}` (status [removed]), filed in [tenantId] at [seq].
///
/// ⚠️ SPEC: the server applies these only from a tenant admin (`records.ts`
/// `not_admin`), but stores and serves a refused one like any other signed
/// record, and the client cannot judge admin authority. A non-admin's
/// `removed` can therefore keep an approval filed after it from counting
/// here. It can only *withhold* a count, never complete one or wipe, which a
/// server can already do by withholding the approval itself. Reported to the
/// owner (M13-REV89C).
@immutable
final class MembershipFact {
  /// Creates the fact.
  const MembershipFact({
    required this.recordId,
    required this.tenantId,
    required this.userId,
    required this.status,
    required this.seq,
  });

  /// The status a removal leaves (06 §7).
  static const String removed = 'removed';

  /// Record id.
  final String recordId;

  /// The tenant the record was filed in, which is the tenant whose
  /// membership it changes (the server projects it there).
  final String tenantId;

  /// The member.
  final String userId;

  /// The status the record moves the member to.
  final String status;

  /// Server `seq`.
  final int seq;
}

/// Why a record was not counted.
enum IgnoreReason {
  /// `subject_user_id` is not the revoked device's owner as this reader
  /// knows it (its certificate, else its `devices` row; for the reader's own
  /// device, its own user), or the owner is not known yet. Applies to both
  /// paths: without it any member could name itself as subject and revoke
  /// anyone's device as its "owner". The server refuses this shape
  /// (`records.ts` `rejected:shape`; 0026 `rf.revocation_approvals` joins on
  /// the device's owner) but stores and serves it.
  notSubjectsDevice,

  /// The record names no `share_set_version` and is not the owner's.
  noVersion,

  /// No guardian set is known at the version named.
  unknownVersion,

  /// The version named has no tenant — published before ADR 2026-10-03b, so
  /// it can no longer revoke until the next re-split (§1).
  setHasNoTenant,

  /// The record was filed in a tenant other than the one the version it
  /// names belongs to (ADR 2026-10-03b §2).
  wrongTenant,

  /// The author was not a guardian at the version named.
  notGuardian,

  /// At the record's `seq`, the subject's membership in the tenant it was
  /// filed in was `removed` (ADR 2026-10-03b §2).
  subjectRemoved,

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

  /// The k applied — of the *earliest* version any valid guardian record
  /// names, a guardian's later records included; null when no guardian
  /// record counted.
  final int? threshold;

  /// Records that did not count.
  final List<IgnoredRecord> ignored;

  /// Cut-off from the owner's own record, if any.
  final int? ownerSeq;
}

/// Counts the revocation of [revokedDeviceId] from [records] (already
/// chain-verified) against [history] and [memberships].
///
/// - Every record must name the device's owner as its subject:
///   [revokedDeviceOwner] is that owner as the reader knows it, and while it
///   is null (the device is not known yet) nothing counts. The owner path
///   (`authorUserId == subjectUserId`) would otherwise let any member revoke
///   anyone's device by naming itself; the guardian path would let k
///   guardians of one user revoke another's.
/// - An owner's record (any certified device of the subject, 04 §9.2) is
///   effective alone at its `seq`.
/// - Guardian records count when the version they name has a tenant, the
///   record was filed in that tenant, the subject's membership there was not
///   `removed` at the record's `seq` (ADR 2026-10-03b §2), and the author was
///   a guardian at that version; one per author (earliest `seq` among the
///   records that pass those checks, so an invalid record never shadows a
///   valid one); approvals carry across versions, each judged by the tenant
///   of the version it names; the threshold is the k of the earliest version
///   *any* valid record names (a guardian's later records included, as 0026
///   `rf.revocation_tally` takes it); effective at the k-th smallest `seq`
///   among the distinct authors.
/// - The cut-off is the minimum of the two paths — it only moves earlier.
///
/// ⚠️ SPEC: ADR 2026-10-03b §2 counts an approval only if "the subject holds
/// a membership there other than `removed`" and does not say *when*. This
/// reads it at the approval's own `seq` — the moment 0022 §4's WHERE, which
/// the ADR cites, is evaluated, and the moment the server refuses an
/// approval as `not_revoker`. A later removal therefore never un-counts an
/// approval, keeping ADR 2026-09-06 §3's "only moves earlier", and an
/// approval refused while the subject was removed never counts after a
/// re-admission. 0026 `rf.revocation_approvals` instead reads the subject's
/// *current* membership, so the server's tally differs from this one when
/// the subject's membership changes between approvals. Reported to the owner
/// (M13-REV89C). With no fact for the subject in that tenant the membership
/// is taken as held: the set's publisher was `active` there (0026 §1 guard).
/// The owner path is not judged by membership here, though the server's
/// owner arm is (0022 (e)); also reported.
RevocationCount countRevocation({
  required String revokedDeviceId,
  required String? revokedDeviceOwner,
  required Iterable<RevocationRecord> records,
  required Iterable<GuardianSetVersion> history,
  required Iterable<MembershipFact> memberships,
}) {
  final byVersion = <(String, int), GuardianSetVersion>{
    for (final v in history) (v.subjectUserId, v.shareSetVersion): v,
  };
  // The owner's membership facts per tenant, by seq.
  final timeline = <String, List<MembershipFact>>{};
  for (final f in memberships) {
    if (f.userId == revokedDeviceOwner) {
      (timeline[f.tenantId] ??= []).add(f);
    }
  }
  for (final t in timeline.values) {
    t.sort((a, b) => a.seq.compareTo(b.seq));
  }
  bool removedAt(String tenantId, int seq) {
    MembershipFact? latest;
    for (final f in timeline[tenantId] ?? const <MembershipFact>[]) {
      if (f.seq >= seq) break;
      latest = f;
    }
    return latest?.status == MembershipFact.removed;
  }

  int? ownerSeq;
  final ignored = <IgnoredRecord>[];
  final counted = <String, RevocationRecord>{}; // author user → earliest record
  int? earliestVersion; // over every valid guardian record
  final sorted =
      records.where((r) => r.revokedDeviceId == revokedDeviceId).toList()
        ..sort((a, b) => a.seq.compareTo(b.seq));
  for (final r in sorted) {
    if (revokedDeviceOwner == null || r.subjectUserId != revokedDeviceOwner) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.notSubjectsDevice));
      continue;
    }
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
    final setTenant = set.tenantId;
    if (setTenant == null) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.setHasNoTenant));
      continue;
    }
    if (r.tenantId != setTenant) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.wrongTenant));
      continue;
    }
    if (!set.guardianUserIds.contains(r.authorUserId)) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.notGuardian));
      continue;
    }
    if (removedAt(r.tenantId, r.seq)) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.subjectRemoved));
      continue;
    }
    // Valid: its version bears on the threshold even when its author has
    // already counted (0026 rf.revocation_tally's `thr` reads every row).
    if (earliestVersion == null || version < earliestVersion) {
      earliestVersion = version;
    }
    if (counted.containsKey(r.authorUserId)) {
      ignored.add(IgnoredRecord(r.recordId, IgnoreReason.duplicateAuthor));
      continue;
    }
    counted[r.authorUserId] = r;
  }
  int? threshold;
  int? guardianSeq;
  if (earliestVersion != null && revokedDeviceOwner != null) {
    threshold = byVersion[(revokedDeviceOwner, earliestVersion)]!.k;
    final seqs = counted.values.map((r) => r.seq).toList()..sort();
    // A k below 1 is malformed (the server's set guard never publishes one):
    // it completes nothing rather than index out of range.
    if (threshold >= 1 && seqs.length >= threshold) {
      guardianSeq = seqs[threshold - 1];
    }
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
