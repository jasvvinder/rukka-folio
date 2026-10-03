// Whether this user's trusted-member set can still switch off a lost phone
// together — the S11 guardians row of ADR 2026-10-03b §4 🔒 (07 §15
// Devices & security, F1-03b-1).
//
// A guardian set belongs to the tenant it was set up in (§1), and a guardian's
// revocation approval counts only when it is filed there while the subject
// still holds a membership there (§2). So a set can keep **recovering** (04
// §7.3 does not read the tenant) and still have lost the power to **revoke**:
//
//   • it has no tenant — published before the ADR (§1);
//   • the subject no longer holds a membership in that tenant;
//   • fewer than k guardians of the current version still do.
//
// This file states that condition and nothing more. The facts are
// `sync_engine`'s — [GuardianSetVersion] (with its `tenantId`) and the
// verified [MembershipFact]s the engine files in its `RecordTrustStore` — and
// the rule reads them exactly as `countRevocation` (revocation.dart) does:
// a person's standing in a tenant is their latest fact there by `seq`, and
// with no fact at all the membership is taken as **held**, because the set's
// publisher was active there and every guardian not removed there when the
// set was filed (0026 §1 guard, ADR §1). Only `removed` ends a membership
// (§2: "a membership there other than `removed`").
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sync_engine/sync_engine.dart'
    show GuardianSetVersion, MembershipFact, RecordTrustStore;

import '../../shared/sync/guardians_seams.dart'
    show GuardianSetWire, ServerGuardians;

/// Why the set in force can no longer switch off a lost phone (ADR
/// 2026-10-03b §4). All three read the same on screen; the reason is kept for
/// tests and for whoever wants to say more later.
enum GuardianRevokeGap {
  /// The set in force was published before ADR 2026-10-03b and names no
  /// tenant (§1).
  noTenant,

  /// The subject no longer holds a membership in the set's tenant.
  subjectLeft,

  /// Fewer than k guardians of the current version still hold a membership
  /// in the set's tenant.
  belowThreshold,
}

/// The gap for [subjectUserId]'s set in force, or null when there is nothing
/// to say: no set at all (S11.1 is reached the ordinary way), or a set that
/// can still revoke.
///
/// The set in force is the highest `share_set_version` of [subjectUserId]'s
/// [history] — a set is never rewritten (0010 `rf.guardian_set_guard`).
GuardianRevokeGap? guardianRevokeGapOf({
  required String subjectUserId,
  required Iterable<GuardianSetVersion> history,
  required Iterable<MembershipFact> memberships,
}) {
  GuardianSetVersion? live;
  for (final v in history) {
    if (v.subjectUserId != subjectUserId) continue;
    if (live == null || v.shareSetVersion > live.shareSetVersion) live = v;
  }
  if (live == null) return null;

  final tenant = live.tenantId;
  if (tenant == null || tenant.isEmpty) return GuardianRevokeGap.noTenant;

  // Latest fact per member in the set's tenant, by seq.
  final latest = <String, MembershipFact>{};
  for (final f in memberships) {
    if (f.tenantId != tenant) continue;
    final seen = latest[f.userId];
    if (seen == null || f.seq > seen.seq) latest[f.userId] = f;
  }
  bool holds(String userId) => latest[userId]?.status != MembershipFact.removed;

  if (!holds(subjectUserId)) return GuardianRevokeGap.subjectLeft;
  final still = live.guardianUserIds.where(holds).length;
  if (still < live.k) return GuardianRevokeGap.belowThreshold;
  return null;
}

/// One reading of the gap for the signed-in user. Pure and cheap — two
/// in-memory lists — so it is safe to call on every build.
typedef GuardianStandingRead = GuardianRevokeGap? Function();

/// How often a [GuardianStanding] that S11 is listening to re-reads on its
/// own.
///
/// ⚠️ SPEC (M13-REV89U): a **backstop**, not the design. The sync engine
/// files `guardian_sets` rows and membership facts on a meta pull and raises
/// no event when it does (`SyncEngine.onEvent` carries none; the app's
/// `SyncStatus` is de-duplicated, so Synced → Synced emits nothing), so there
/// is no signal for a removal filed while S11 is open. Until `sync_engine`
/// raises one — reported in the lane's `open` — this re-reads the two
/// in-memory lists while, and only while, S11 is on screen.
const Duration guardianStandingPoll = Duration(seconds: 5);

/// The S11 guardians row's reading, kept **live** (ADR 2026-10-03b §4 🔒).
///
/// [gap] reads afresh on every call, so a build never shows an answer older
/// than itself. Between builds the standing re-reads when any of [changes]
/// emits, every [pollEvery] while it has listeners, or on [recheck], and
/// notifies its listeners only when the answer moved — so S11 flips in either
/// direction the moment a reading changes, without anything rebuilding it
/// from outside.
class GuardianStanding extends ChangeNotifier {
  /// Creates the standing over [read].
  ///
  /// [changes] must be broadcast streams (each is listened to afresh whenever
  /// S11 starts listening again). With no [pollEvery] the standing re-reads
  /// only on [changes] and [recheck].
  GuardianStanding(
    GuardianStandingRead read, {
    Iterable<Stream<Object?>> changes = const [],
    this.pollEvery,
  }) : _read = read,
       _changes = List.unmodifiable(changes);

  final GuardianStandingRead _read;
  final List<Stream<Object?>> _changes;

  /// The backstop re-read period while listened to, or null for none.
  final Duration? pollEvery;

  final _subs = <StreamSubscription<Object?>>[];
  Timer? _timer;
  GuardianRevokeGap? _last;
  bool _armed = false;
  bool _disposed = false;

  /// The gap as of this call.
  GuardianRevokeGap? get gap => _last = _read();

  /// Re-reads, and notifies listeners when the answer differs from the last
  /// one read.
  void recheck() {
    if (_disposed) return;
    final before = _last;
    final now = _last = _read();
    if (now != before) notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (!_armed) _arm();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _disarm();
  }

  void _arm() {
    if (_disposed) return;
    _armed = true;
    for (final c in _changes) {
      _subs.add(c.listen((_) => recheck()));
    }
    final every = pollEvery;
    if (every != null) _timer = Timer.periodic(every, (_) => recheck());
  }

  void _disarm() {
    _armed = false;
    _timer?.cancel();
    _timer = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _disarm();
    _disposed = true;
    super.dispose();
  }
}

/// The engine's guardian-set history, plus every generation [published]
/// holds that the engine has not filed yet.
///
/// Both are readings of the same server rows (`guardian_sets`, unsigned on
/// either path): the engine's arrives with the meta pull, [published] with
/// S11.1's own read-back after a re-split. Where both hold a generation the
/// engine's row is kept — it is the one the revocation count reads.
Iterable<GuardianSetVersion> mergedGuardianHistory(
  Iterable<GuardianSetVersion> engine,
  Iterable<GuardianSetWire> published,
) {
  final seen = <(String, int)>{};
  final out = <GuardianSetVersion>[];
  for (final v in engine) {
    seen.add((v.subjectUserId, v.shareSetVersion));
    out.add(v);
  }
  for (final w in published) {
    if (!seen.add((w.subjectUserId, w.shareSetVersion))) continue;
    out.add(
      GuardianSetVersion(
        subjectUserId: w.subjectUserId,
        shareSetVersion: w.shareSetVersion,
        k: w.k,
        guardianUserIds: w.guardianUserIds.toSet(),
        tenantId: w.tenantId,
      ),
    );
  }
  return out;
}

/// The production [GuardianStanding]: the facts the sync engine itself counts
/// revocations with ([RecordTrustStore.guardianHistory] and
/// [RecordTrustStore.memberships]), so the row and the count read the same
/// set and the same memberships.
///
/// [guardians] is S11.1's repository — the one door to `guardian_sets` the
/// screens read through. Its read-back joins the engine's history
/// ([mergedGuardianHistory]) and its [ServerGuardians.watch] is a change
/// signal, so a set chosen again in S11.1 clears the warning when S11.1 reads
/// it back, not at the next meta pull. Memberships come from the trust store
/// alone: they are signed records, and only the engine has verified them.
///
/// [subjectUserId] must be the user id the engine counts this device's own
/// revocations under (`SyncEngine.userId`).
GuardianStanding trustStoreGuardianStanding(
  RecordTrustStore trust, {
  required String subjectUserId,
  ServerGuardians? guardians,
  Duration? pollEvery = guardianStandingPoll,
}) => GuardianStanding(
  () => guardianRevokeGapOf(
    subjectUserId: subjectUserId,
    history: mergedGuardianHistory(
      trust.guardianHistory,
      guardians?.history ?? const <GuardianSetWire>[],
    ),
    memberships: trust.memberships,
  ),
  changes: [?guardians?.watch()],
  pollEvery: pollEvery,
);

/// Hands a [GuardianStanding] down to S11.
///
/// With no scope S11 says nothing about revoking: the row keeps its ordinary
/// line. Silence is not a claim that the set can revoke — it is the absence
/// of a reading — and the row still opens S11.1 either way.
class GuardianStandingScope extends InheritedWidget {
  /// Installs [standing] above [child].
  const GuardianStandingScope({
    super.key,
    required this.standing,
    required super.child,
  });

  /// The reading in force. S11 listens to it, so it is installed once and
  /// kept; a new object is a new reading.
  final GuardianStanding standing;

  /// The nearest standing, or null when none is installed.
  static GuardianStanding? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GuardianStandingScope>()
      ?.standing;

  @override
  bool updateShouldNotify(GuardianStandingScope old) =>
      standing != old.standing;
}
