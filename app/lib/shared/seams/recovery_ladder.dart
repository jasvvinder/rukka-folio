// The recovery-ladder seam (04 §7, 06 §5, 13 §5 flow F11).
//
// It lives here beside `auth_client.dart` / `key_store.dart` / `closed_years.dart`
// because it is a **domain seam**: the activation screens (S11.5 R2.0, S11.6
// R2.1, S11.8 R2.5) ask it two questions and nothing else —
//
//   1. *which rungs can this phone offer right now, and if one cannot, why*
//      ([RecoveryLadder.rungs]); and
//   2. *how far has a rung got* ([RecoveryLadder.progressOf]), as a **count**,
//      because 11 §4.5 🔒 and the pack's loader-rule paragraph forbid a
//      percentage and forbid a spinner.
//
// It deliberately carries **no key material and no cryptography**. 04 §7.4 and
// 07 §5.6 🔒: RK, UMK, shares and device private keys never reach a widget, so
// nothing on this seam can express one — the richest thing that crosses it is
// an integer count and an enum. A screen cannot render a secret it was never
// handed.
//
// **The adapter has landed, and this note is corrected rather than softened.**
// An earlier ⚠️ SPEC here said the real producer was "another lane's files in
// this same round" and that "the adapter lands when those routes exist". The
// routes exist: migration `0011_recovery_sheet.sql`, served as `GET
// /sync-meta/recovery/sheet` (`server/supabase/functions/sync-meta/index.ts`
// :254, with `no_sheet` at :260), beside 0010's `guardian_sets`. The adapter
// is `shared/sync/recovery_ladder_source.dart` — `LiveRecoveryLadder` over
// one probe per rung — and `buildRecoveryLadder` there is what the
// composition root installs (F1-06-89, F1-06-91).
//
// Nothing in *this* file calls a route or names one, and that part still
// holds: the seam is the question, the adapter is the answer, and
// [FakeRecoveryLadder] below stays the double every widget test runs against.
// What changed is only that production no longer runs on it — which is the
// difference between a fork that reports and one that reassures.
import 'dart:async';

import 'package:flutter/widgets.dart';

/// A rung of the ladder, in the order 04 §7 tries them.
///
/// The **display** order of the fork (R2.1 🔒) is not this order — R2.0's rung
/// has already run by the time a fork is drawn, and the remaining three are
/// shown as [forkOrder]. Keeping the two orders apart is deliberate: one is
/// the protocol's, one is the screen's, and neither may be inferred from the
/// other.
enum RecoveryRung {
  /// Rung 0 — platform key sync / Keychain remnant (04 §7.0, §7.1). Runs
  /// before any fork appears; this is the rung S11.5 narrates.
  platformKeySync,

  /// Rung 1 — another of the user's own devices, linked by ceremony
  /// (04 §7.2, §9.1). Instant, and 06 §5 says a user who still has a phone
  /// should link rather than ask anybody.
  anotherDevice,

  /// Rung 2 — trusted members, k-of-n (04 §7.3).
  ///
  /// The user-facing vocabulary is **Trusted member**; "guardian" and "share"
  /// are engineering words and never reach a screen (01 §1.3 tone).
  trustedMembers,

  /// Rung 3 — the recovery sheet, paper or the file the user saved (04 §7.4).
  recoverySheet;

  /// The three rows of the fork, in the pack's 🔒 order: another phone ·
  /// trusted members · recovery sheet. R2.1 fixes this order, so it is stated
  /// once, here, rather than re-typed by the screen.
  static const forkOrder = [
    RecoveryRung.anotherDevice,
    RecoveryRung.trustedMembers,
    RecoveryRung.recoverySheet,
  ];
}

/// Why a rung cannot be taken on this phone right now.
///
/// A rung is never hidden for want of one of these — 13 §4.3 ships
/// *disabled-with-reason*, and 07 §1 rule 6 forbids a dead end, so the reason
/// is always renderable and always sits next to a path that still works.
enum RecoveryRungBlocked {
  /// No other phone of this user is signed in (04 §7.2).
  noOtherDevice,

  /// This user set no trusted members up (04 §7.3 setup never happened).
  noTrustedMembers,

  /// No recovery sheet was ever made, or none that is still current
  /// (04 §7.4: regenerating rotates RK and invalidates the old sheet).
  noRecoverySheet,

  /// The rung exists in the protocol but this build cannot walk it yet.
  ///
  /// S11.2 and S11.3 are not built at M11, and an unbuilt rung is still shown
  /// — a row that vanishes teaches the user their books are unreachable, which
  /// is false. The copy for this reason therefore names a rung that *does*
  /// work rather than apologising.
  notOnThisPhoneYet,
}

/// Whether a rung can be taken — **three** answers, not two.
///
/// The third is the one that matters on this screen. A person reaching S11.6
/// is already locked out, so the two ways to be wrong are not symmetrical:
/// offering a rung that then fails wastes the one attempt they had the nerve
/// to make, and denying a rung they actually have ("you have no recovery
/// sheet" to somebody holding one) can make them stop trying altogether.
/// Neither is an acceptable rendering of *we could not find out*, so
/// [unknown] is its own state and no source is permitted to default into
/// [available].
enum RecoveryRungAvailability {
  /// A real source said yes.
  available,

  /// A real source said no — the reason is on the offer.
  unavailable,

  /// Nothing this phone can reach answered: offline, no session, or no
  /// producer for this rung in this build. Never a synonym for either of the
  /// other two.
  unknown,
}

/// What the ladder offers for one rung: the rung itself, and either nothing
/// (it is available), the reason it is not, or the admission that this phone
/// could not find out.
@immutable
final class RecoveryRungOffer {
  /// An available rung — a real source said so.
  const RecoveryRungOffer.available(this.rung)
    : blocked = null,
      isUnknown = false;

  /// A rung that cannot be taken, with the reason a screen must render.
  const RecoveryRungOffer.blocked(this.rung, RecoveryRungBlocked this.blocked)
    : isUnknown = false;

  /// A rung whose availability could not be established.
  ///
  /// It carries **no** [blocked] reason, because there is nothing true to
  /// say about why it cannot be taken — it may well be takeable. A screen
  /// must not draw it as denied, and must not draw it as confirmed either.
  const RecoveryRungOffer.unknown(this.rung) : blocked = null, isUnknown = true;

  /// Which rung.
  final RecoveryRung rung;

  /// The reason the rung is refused; null when it is available **or**
  /// unknown. Read it with [isBlocked], never as "not available".
  final RecoveryRungBlocked? blocked;

  /// Whether this phone failed to find out. See [RecoveryRungAvailability].
  final bool isUnknown;

  /// Whether the row is live — **a real source said yes**. False for an
  /// unknown rung, which is the whole point of the third state: a caller
  /// that treated `!isBlocked` as available would have re-introduced the
  /// default this type exists to remove.
  bool get isAvailable => blocked == null && !isUnknown;

  /// Whether a real source refused the rung.
  bool get isBlocked => blocked != null;

  /// The three-way answer.
  RecoveryRungAvailability get availability => switch (this) {
    _ when isBlocked => RecoveryRungAvailability.unavailable,
    _ when isUnknown => RecoveryRungAvailability.unknown,
    _ => RecoveryRungAvailability.available,
  };

  @override
  bool operator ==(Object other) =>
      other is RecoveryRungOffer &&
      other.rung == rung &&
      other.blocked == blocked &&
      other.isUnknown == isUnknown;

  @override
  int get hashCode => Object.hash(rung, blocked, isUnknown);

  @override
  String toString() =>
      'RecoveryRungOffer(${rung.name}, ${availability.name}'
      '${blocked == null ? '' : ': ${blocked!.name}'})';
}

/// What a running rung is counting.
///
/// Counts, never percentages (11 §4.5 🔒, pack loader-rule paragraph): the two
/// things the ladder ever counts are whole books (R2.0's *"5 books restored"*)
/// and entry envelopes read back (R2.2's *"1,240 of 3,890 entries restored"*).
enum RecoveryUnit {
  /// Whole books opening again — what S11.5 shows.
  books,

  /// Entry envelopes read back after the key returned.
  entries,
}

/// How far a rung has got: [done] of [total] [unit], plus whether it finished.
@immutable
final class RecoveryProgress {
  /// Creates a reading.
  const RecoveryProgress({
    required this.done,
    required this.total,
    required this.unit,
    this.finished = false,
  });

  /// Done so far.
  final int done;

  /// How many in all. `0` while the total is not known yet.
  final int total;

  /// What is being counted.
  final RecoveryUnit unit;

  /// Whether this reading is the last one — the rung succeeded.
  final bool finished;

  /// 0..1 for the **determinate** rule; `0` while [total] is unknown, so the
  /// rule can never be handed `null` and degrade into an indeterminate sweep.
  double get fraction => total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  @override
  bool operator ==(Object other) =>
      other is RecoveryProgress &&
      other.done == done &&
      other.total == total &&
      other.unit == unit &&
      other.finished == finished;

  @override
  int get hashCode => Object.hash(done, total, unit, finished);

  @override
  String toString() =>
      'RecoveryProgress($done/$total ${unit.name}'
      '${finished ? ', finished' : ''})';
}

/// The seam the recovery screens consume.
abstract interface class RecoveryLadder {
  /// Which rungs this phone can offer, and why not where it cannot.
  ///
  /// Every rung of [RecoveryRung.forkOrder] is always present in the result —
  /// an absent rung would be a hidden row, and 13 §4.3 has no such state. A
  /// rung the caller does not draw (rung 0) may also appear; the fork filters
  /// by [RecoveryRung.forkOrder] rather than by what the list happens to hold.
  ///
  /// 🔒 of this contract: **every offer is backed by a real source, or it is
  /// [RecoveryRungOffer.unknown]**. An implementation may not answer
  /// `available` because it has no producer, because a probe threw, or
  /// because the other rungs looked worse — the person reading the answer is
  /// locked out, and a rung that fails after being offered spends the one
  /// attempt they steeled themselves for.
  Future<List<RecoveryRungOffer>> rungs();

  /// Live progress for [rung]: readings until the rung finishes or the stream
  /// closes. A rung that reports nothing yields an empty stream rather than a
  /// `null` reading, so a screen never has to distinguish *not started* from
  /// *zero done*.
  Stream<RecoveryProgress> progressOf(RecoveryRung rung);
}

/// The in-memory ladder every widget test runs against.
///
/// **It is no longer the only implementation, and this line is corrected
/// rather than softened.** It said "the only implementation in the app until
/// the recovery routes land"; the routes landed (migration
/// `0011_recovery_sheet.sql`, served at `sync-meta/index.ts:254`) and
/// `LiveRecoveryLadder` (`shared/sync/recovery_ladder_source.dart:66`) is
/// what the composition root installs — the same facts this file's own header
/// records twelve lines up. What stays true is the half that names its job:
/// it is the double the S11.5 / S11.6 / S11.8 widget tests drive, and
/// production does not run on it.
///
/// It is a plain scripted double: the offers it was given, and, per rung, the
/// readings it was given, replayed in order. No timers, no clock, no network —
/// a widget test drives it by pumping.
final class FakeRecoveryLadder implements RecoveryLadder {
  /// Creates a fake offering [offers] (every fork rung available by default)
  /// and replaying [progress] per rung.
  FakeRecoveryLadder({
    List<RecoveryRungOffer>? offers,
    Map<RecoveryRung, List<RecoveryProgress>>? progress,
    this.failsWith,
    this.keepRunning = false,
  }) : _offers =
           offers ??
           [
             for (final r in RecoveryRung.forkOrder)
               RecoveryRungOffer.available(r),
           ],
       _progress = progress ?? const {};

  /// A fake whose rungs() throws — the error-with-retry case of 13 §4.3.
  factory FakeRecoveryLadder.failing() =>
      FakeRecoveryLadder(failsWith: Exception('ladder unreachable'));

  /// A fake that found nothing out: every fork rung [RecoveryRungOffer
  /// .unknown]. This is a wholly offline phone, and it is **not** the same
  /// fake as [nothingWorked] — nothing here says a rung is missing.
  factory FakeRecoveryLadder.allUnknown() => FakeRecoveryLadder(
    offers: const [
      RecoveryRungOffer.unknown(RecoveryRung.anotherDevice),
      RecoveryRungOffer.unknown(RecoveryRung.trustedMembers),
      RecoveryRungOffer.unknown(RecoveryRung.recoverySheet),
    ],
  );

  /// A fake where no rung can be taken: every fork row is disabled with its
  /// own reason, which is exactly the state that reaches S11.8.
  factory FakeRecoveryLadder.nothingWorked() => FakeRecoveryLadder(
    offers: const [
      RecoveryRungOffer.blocked(
        RecoveryRung.anotherDevice,
        RecoveryRungBlocked.noOtherDevice,
      ),
      RecoveryRungOffer.blocked(
        RecoveryRung.trustedMembers,
        RecoveryRungBlocked.noTrustedMembers,
      ),
      RecoveryRungOffer.blocked(
        RecoveryRung.recoverySheet,
        RecoveryRungBlocked.noRecoverySheet,
      ),
    ],
  );

  final List<RecoveryRungOffer> _offers;
  final Map<RecoveryRung, List<RecoveryProgress>> _progress;

  /// When set, [rungs] throws it instead of answering.
  final Object? failsWith;

  /// Whether a rung's stream stays **open** after its readings are replayed.
  ///
  /// This is the difference between *still restoring* and *it stopped*: a
  /// rung that finished says so in its last reading, and a rung whose stream
  /// simply closed without one has failed. A test that wants to look at the
  /// running screen keeps the stream open; one that wants the failure lets it
  /// close.
  final bool keepRunning;

  /// How many times [rungs] was asked — a retry is an observable fact.
  int asked = 0;

  @override
  Future<List<RecoveryRungOffer>> rungs() async {
    asked++;
    final failure = failsWith;
    if (failure != null) throw failure;
    return List.unmodifiable(_offers);
  }

  @override
  Stream<RecoveryProgress> progressOf(RecoveryRung rung) {
    final readings = _progress[rung] ?? const <RecoveryProgress>[];
    if (!keepRunning) return Stream.fromIterable(readings);
    // A single-subscription controller buffers what is added before anyone
    // listens, and is never closed — so the screen sees every reading and
    // then keeps waiting, with no timer for the test binding to complain
    // about.
    final c = StreamController<RecoveryProgress>();
    for (final r in readings) {
      c.add(r);
    }
    return c.stream;
  }
}

/// The [RecoveryLadder] in force for the tree below.
///
/// Optional by design, like `ClosedYearsScope`: [maybeOf] returns null when
/// the shell has installed none, and a screen then falls back to what it was
/// constructed with. A missing scope is never an error and never a red screen
/// (07 §1 rule 6).
class RecoveryLadderScope extends InheritedWidget {
  /// Creates the scope.
  const RecoveryLadderScope({
    super.key,
    required this.ladder,
    required super.child,
  });

  /// The ladder in force.
  final RecoveryLadder ladder;

  /// The nearest ladder, or null when none is installed.
  static RecoveryLadder? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RecoveryLadderScope>()?.ladder;

  @override
  bool updateShouldNotify(RecoveryLadderScope old) => ladder != old.ladder;
}

// ===========================================================================
// Rung 2 — asking your trusted members (S11.2, design R2.2; 04 §7.3 🔒)
// ===========================================================================
//
// The server side landed as migration 0010 and its rules are read off that
// file, not re-derived here:
//
//   * `k = ⌈(n+1)/2⌉` for n = 2..5, enforced by the database trigger.
//   * Approvals are **append-only rows, one per guardian**, so the screen can
//     name *which* member approved — R2.2's per-guardian rows are backed by
//     real data and never by a counter.
//   * The 24 h wait of ADR 2026-09-05d §1 is measured from the **k-th**
//     approval; below k, 72 h closes the attempt; three denials close it too.
//   * 03 §2.2's `state` has no `denied`, so a denial-closed attempt is
//     indistinguishable from a timed-out one at the **attempt** level and
//     reads as [RecoveryAttemptState.expired].
//
// **This seam has an HTTP adapter, and that note is corrected rather than
// softened.** An earlier ⚠️ SPEC said it had none "by instruction" and that
// the live producer over the 0010 routes was "the next slice". That slice
// landed: `HttpGuardianRecovery` (`shared/sync/recovery_seams.dart:204`) is
// built and installed by the composition root (`bootstrap.dart:407`), and
// F1-06-44 pins that [GuardianRecoveryScope] hands it down rather than
// [FakeGuardianRecovery].
//
// The fake stays, because it is what the S11.2 widget tests drive, and the
// scope is still how the shell swaps one for the other without a screen
// changing its constructor — that half of the note was right and is kept.

/// Where one trusted member stands on a recovery attempt.
///
/// The first three are DESIGN-PACK R2.2's own three row states. [declined] is
/// the fourth the pack does not draw.
///
/// ⚠️ SPEC: R2.2 draws **approved ✓ · waiting… · not asked** and no more,
/// while 04 §7.3 step 7 🔒 requires that a "guardian denial → requester
/// notified" and migration 0010 stores that decision as its own row. Rendering
/// a declined member as *waiting* or as *not asked* would be a falsehood on a
/// security screen, so the state exists and is drawn — 04 owns recovery and
/// the pack is silent, which is the conservative reading. Reported as an open
/// item against DESIGN-PACK R2.2.
enum TrustedApproverState {
  /// Approved — the row's tick.
  approved,

  /// Asked, no answer yet — the row that carries the inline loader rule.
  waiting,

  /// Not asked yet.
  notAsked,

  /// Answered *no*. See the ⚠️ SPEC above.
  declined,
}

/// One trusted member on the waiting screen.
///
/// Carries a name and, when the book holds one, a phone number — never a key,
/// never a share, never a fingerprint of theirs. What crosses this seam is
/// what R2.2 draws.
@immutable
final class TrustedApprover {
  /// Creates a row.
  const TrustedApprover({
    required this.memberId,
    required this.name,
    this.state = TrustedApproverState.notAsked,
    this.phone,
  });

  /// Stable id — never displayed.
  final String memberId;

  /// Their name, as the book holds it.
  final String name;

  /// Where they stand.
  final TrustedApproverState state;

  /// Their number, when the book has one. R2.2's *Call* link is drawn only
  /// where this exists; where it does not, the row cannot pretend to dial.
  final String? phone;

  @override
  bool operator ==(Object other) =>
      other is TrustedApprover &&
      other.memberId == memberId &&
      other.name == name &&
      other.state == state &&
      other.phone == phone;

  @override
  int get hashCode => Object.hash(memberId, name, state, phone);
}

/// The attempt's state, named exactly as `rf.recovery_derive` (0010) derives
/// it, so nobody has to translate between the screen and the database.
enum RecoveryAttemptState {
  /// Open, fewer than k approvals, and the user has no other active device —
  /// completion will be immediate (ADR 2026-09-05d §1).
  pending,

  /// The user still has an active certified device, so completion waits 24 h
  /// behind a one-tap Cancel on every existing device (ADR 2026-09-05d §1).
  waiting24h,

  /// k approvals in, and any wait has run out: the key can come back.
  approved,

  /// Closed. **Three denials or 72 h — and the two are not distinguishable**
  /// (03 §2.2 has no `denied`), so no copy on S11.2 may claim it was refused.
  expired,

  /// Cancelled from one of the user's existing devices (S11.9).
  cancelled,
}

/// Everything S11.2 draws about one attempt.
@immutable
final class GuardianRecoveryAttempt {
  /// Creates a snapshot.
  const GuardianRecoveryAttempt({
    required this.requestId,
    required this.k,
    required this.n,
    required this.approvers,
    this.state = RecoveryAttemptState.pending,
    this.waitUntil,
    this.expiresAt,
    this.restore,
  });

  /// Server id of the attempt.
  final String requestId;

  /// How many approvals are needed — `⌈(n+1)/2⌉`, enforced server-side.
  final int k;

  /// How many members hold a share.
  final int n;

  /// One row per member, in the order the screen draws them.
  final List<TrustedApprover> approvers;

  /// The derived state.
  final RecoveryAttemptState state;

  /// 24 h from the k-th approval, or null when no wait applies.
  final DateTime? waitUntil;

  /// 72 h from the open — the window members have to answer in.
  final DateTime? expiresAt;

  /// The count of entries coming back, once the key is in hand. Null until
  /// the restore starts; R2.2's completed state draws it over the
  /// determinate loader rule.
  final RecoveryProgress? restore;

  /// How many have approved — counted from the rows, never from a counter.
  int get approvals =>
      approvers.where((a) => a.state == TrustedApproverState.approved).length;

  /// How many have declined. Three closes the attempt (04 §7.3 step 7).
  int get declines =>
      approvers.where((a) => a.state == TrustedApproverState.declined).length;

  /// Whether the attempt is over, either way.
  bool get isClosed =>
      state == RecoveryAttemptState.expired ||
      state == RecoveryAttemptState.cancelled;

  @override
  bool operator ==(Object other) =>
      other is GuardianRecoveryAttempt &&
      other.requestId == requestId &&
      other.k == k &&
      other.n == n &&
      other.state == state &&
      other.waitUntil == waitUntil &&
      other.expiresAt == expiresAt &&
      other.restore == restore &&
      _sameApprovers(other.approvers, approvers);

  @override
  int get hashCode => Object.hash(
    requestId,
    k,
    n,
    state,
    waitUntil,
    expiresAt,
    restore,
    Object.hashAll(approvers),
  );
}

bool _sameApprovers(List<TrustedApprover> a, List<TrustedApprover> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// How a scan ended.
///
/// The scan itself happens **behind the seam**: the camera is opened, the
/// payload is compared, and only this enum comes back. No QR bytes, no public
/// key and no fingerprint ever reach a widget, which is what keeps 04 §7.4 /
/// 07 §5.6 🔒 a property of the contract rather than of one build method.
enum RecoveryScanOutcome {
  /// The scanned payload matched — [RecoveryCeremonyGate] opens.
  verified,

  /// It did not match. ADR 2026-09-13c ruling 1 🔒: hard fail, no override.
  mismatch,

  /// The person backed out of the scanner.
  cancelled,

  /// **This build cannot scan.** No camera package is in the app yet — the
  /// choice is an owner ruling (cf. ADR 2026-09-12e), so the seam names the
  /// state instead of a screen pretending the control works.
  unavailable,
}

/// A failure reading or writing a recovery seam. Plain reason, never a server
/// code (07 §1 rule 12).
final class RecoveryFailure implements Exception {
  /// Creates the failure.
  const RecoveryFailure([this.reason = '']);

  /// For logs only — never rendered raw.
  final String reason;

  @override
  String toString() => 'RecoveryFailure($reason)';
}

/// Thrown when an approval is attempted before the candidate device has been
/// verified by scan.
///
/// ADR 2026-09-13c ruling 3 🔒 turns 04 §7.3 step 2's *"call them before
/// approving"* from advice into a **check**: the guardian's device scans the
/// fresh device's QR and the re-seal accepts only the verified type. Making
/// the seam throw means a screen bug cannot produce an unverified approval —
/// the caution is unskippable in the contract, not merely in the layout.
final class RecoveryCandidateUnverified implements Exception {
  /// Creates the refusal.
  const RecoveryCandidateUnverified();

  @override
  String toString() => 'RecoveryCandidateUnverified()';
}

/// What S11.2 consumes: one live attempt, and the one ceremony that must pass
/// before any key may be reconstructed.
abstract interface class GuardianRecovery {
  /// The attempt as it stands, then every change. May be open for minutes —
  /// R2.2 says the screen must not feel stuck.
  Stream<GuardianRecoveryAttempt> watch();

  /// The latest snapshot, or null before the first arrives.
  GuardianRecoveryAttempt? get current;

  /// Opens (or re-reads) the attempt. Throws [RecoveryFailure].
  Future<void> refresh();

  /// ADR 2026-09-13c ruling 1 🔒 — the **recovery ceremony**: this phone scans
  /// the user's own UMK off an already-verified member's screen and compares
  /// it, behind the seam, with the key the server relayed. Only
  /// [RecoveryScanOutcome.verified] may be followed by a reconstruction.
  ///
  /// Ruling 2 🔒: **QR only**. There is deliberately no typed fallback on this
  /// call, so no screen can offer *Enter code instead* at recovery.
  Future<RecoveryScanOutcome> verifyOwnKeyByScan();
}

/// The scripted [GuardianRecovery] every S11.2 test runs against.
final class FakeGuardianRecovery implements GuardianRecovery {
  /// Creates a fake over [initial].
  FakeGuardianRecovery({
    GuardianRecoveryAttempt? initial,
    this.failRefresh = false,
    this.scan = RecoveryScanOutcome.verified,
  }) : _current = initial;

  /// A 2-of-3 attempt with one approval in — the pack's own example.
  factory FakeGuardianRecovery.waiting() => FakeGuardianRecovery(
    initial: const GuardianRecoveryAttempt(
      requestId: 'req-1',
      k: 2,
      n: 3,
      approvers: [
        TrustedApprover(
          memberId: 'm1',
          name: 'Sunita',
          state: TrustedApproverState.approved,
          phone: '98765 43210',
        ),
        TrustedApprover(
          memberId: 'm2',
          name: 'Harjit',
          state: TrustedApproverState.waiting,
          phone: '98765 43211',
        ),
        TrustedApprover(memberId: 'm3', name: 'Balwinder'),
      ],
    ),
  );

  GuardianRecoveryAttempt? _current;
  final _controller = StreamController<GuardianRecoveryAttempt>.broadcast();

  /// When true, [refresh] throws.
  bool failRefresh;

  /// What [verifyOwnKeyByScan] answers.
  RecoveryScanOutcome scan;

  /// How many times the ceremony was run — a scan is an observable fact.
  int scans = 0;

  @override
  GuardianRecoveryAttempt? get current => _current;

  @override
  Stream<GuardianRecoveryAttempt> watch() => _controller.stream;

  @override
  Future<void> refresh() async {
    if (failRefresh) throw const RecoveryFailure('refresh');
    final a = _current;
    if (a != null) _controller.add(a);
  }

  @override
  Future<RecoveryScanOutcome> verifyOwnKeyByScan() async {
    scans++;
    return scan;
  }

  /// Pushes a new snapshot, as the server would.
  void emit(GuardianRecoveryAttempt a) {
    _current = a;
    _controller.add(a);
  }

  /// Closes the stream.
  void dispose() => _controller.close();
}

/// Hands a [GuardianRecovery] down to S11.2.
class GuardianRecoveryScope extends InheritedWidget {
  /// Installs [recovery] above [child].
  const GuardianRecoveryScope({
    super.key,
    required this.recovery,
    required super.child,
  });

  /// The seam in force.
  final GuardianRecovery recovery;

  /// The nearest one, or null when the shell has installed none.
  static GuardianRecovery? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GuardianRecoveryScope>()
      ?.recovery;

  @override
  bool updateShouldNotify(GuardianRecoveryScope old) =>
      recovery != old.recovery;
}

// ===========================================================================
// Rung 3 — the recovery sheet (S11.3, design R2.4; 04 §7.4 🔒)
// ===========================================================================

/// A typed recovery-sheet code, normalised.
///
/// 04 §7.4 🔒 fixes the typed fallback as **Crockford Base32, groups of 4,
/// 2-char checksum**. Crockford's own decoding rules are what [parse]
/// applies — case-insensitive, `I`/`L` read as `1`, `O` as `0`, hyphens
/// ignored — because they are part of the named encoding and not an invention.
///
/// **The checksum is specified, and it is checked — just not here.** An
/// earlier ⚠️ SPEC on this class said the algorithm was undefined "so nothing
/// here verifies one". That was wrong, and it is corrected rather than
/// softened: `packages/core_crypto/lib/src/recovery.dart:318` defines
/// `_sheetChecksum` as the first two Crockford symbols of
/// `BLAKE2b-256(version ‖ user_id ‖ RK)`, and `recoverySheetFromTyped`
/// (`:344`, `:360`) throws `RecoverySheetChecksumFailed` when the typed final
/// group does not match. 04 §7.4 🔒 says only "2-char checksum"; core_crypto
/// resolved it with the suite's own hash and no new primitive, and that
/// resolution is the one in force.
///
/// This class stays **lexical on purpose**. Verifying the checksum means
/// decoding the payload, and the payload *is* `RK` — so the check can only
/// live where `core_crypto` and a `CryptoSuite` are, never in a value type a
/// widget holds (04 §7.4, 07 §5.6 🔒). What this class can decide alone is
/// the alphabet, and that is all [parse] claims to decide.
///
/// The verdict a well-formed-but-wrong code gets is therefore reached in two
/// places, in this order, and neither of them is the server:
///
///   1. **before any fetch** — `HttpRecoverySheet`'s injected precheck runs
///      `recoverySheetFromTyped`; a length, a foreign symbol or a failed
///      checksum is a mistype, so it is [RecoverySheetRejected] on the spot
///      and the rate-limited `recovery/sheet` route is never spent on it;
///   2. the AEAD open, for a code that is well formed but opens nothing — a
///      sheet reprinted since (regenerating rotates RK, 04 §7.4 🔒).
///
/// Both are R2.4's two stated causes and both are indistinguishable to this
/// device, which is why the copy states both and neither path names one.
@immutable
final class RecoverySheetCode {
  const RecoverySheetCode._(this.value);

  /// Crockford Base32's alphabet: no `I`, `L`, `O` or `U`.
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// The characters of a group in the printed sheet (04 §7.4).
  static const groupSize = 4;

  /// The normalised characters, upper case, no separators.
  final String value;

  /// Normalises [input], or returns null when a character is not Crockford
  /// Base32 — which is the one failure this phone can name by itself, and is
  /// what keeps the *Restore* button disabled-with-reason rather than
  /// bouncing off the server.
  static RecoverySheetCode? parse(String input) {
    final out = StringBuffer();
    for (final rune in input.toUpperCase().runes) {
      final c = String.fromCharCode(rune);
      if (c == ' ' || c == '-' || c == '‐') continue;
      final mapped = switch (c) {
        'I' || 'L' => '1',
        'O' => '0',
        _ => c,
      };
      if (!alphabet.contains(mapped)) return null;
      out.write(mapped);
    }
    final v = out.toString();
    return v.isEmpty ? null : RecoverySheetCode._(v);
  }

  /// The code in the sheet's own groups of four, for the read-back line.
  String get grouped => [
    for (var i = 0; i < value.length; i += groupSize)
      value.substring(i, (i + groupSize).clamp(0, value.length)),
  ].join('-');

  @override
  bool operator ==(Object other) =>
      other is RecoverySheetCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RecoverySheetCode(${value.length} chars)';
}

/// The sheet was not accepted.
///
/// It carries **no reason**: the server cannot tell a mistyped code from one
/// off a sheet that was reprinted (regenerating rotates RK — 04 §7.4 🔒), and
/// R2.4 asks for both causes to be stated plainly anyway.
final class RecoverySheetRejected implements Exception {
  /// Creates the rejection.
  const RecoverySheetRejected();

  @override
  String toString() => 'RecoverySheetRejected()';
}

/// What S11.3 consumes.
abstract interface class RecoverySheetEntry {
  /// R2.4's camera path: scan the QR off the printed sheet. The payload never
  /// surfaces — only the outcome.
  Future<RecoveryScanOutcome> scanSheet();

  /// R2.4's typed path. Throws [RecoverySheetRejected] when the code does not
  /// open the sealed blob, or [RecoveryFailure] when the attempt could not be
  /// made at all.
  Future<void> submit(RecoverySheetCode code);

  /// The count of what is coming back once the key is in hand — a count,
  /// never a percentage (11 §4.5 🔒).
  Stream<RecoveryProgress> restore();
}

/// The scripted sheet every S11.3 test runs against.
final class FakeRecoverySheet implements RecoverySheetEntry {
  /// Creates the fake.
  FakeRecoverySheet({
    this.accepts,
    this.scan = RecoveryScanOutcome.unavailable,
    this.failsWith,
    List<RecoveryProgress>? progress,
  }) : _progress = progress ?? const [];

  /// The one code that works; null accepts any well-formed code.
  final RecoverySheetCode? accepts;

  /// What [scanSheet] answers. Defaults to [RecoveryScanOutcome.unavailable]
  /// because that is this build's truth — no camera package is in the app.
  RecoveryScanOutcome scan;

  /// When set, [submit] throws it instead of deciding.
  final Object? failsWith;

  final List<RecoveryProgress> _progress;

  /// Every code handed to [submit], oldest first.
  final List<RecoverySheetCode> submitted = [];

  @override
  Future<RecoveryScanOutcome> scanSheet() async => scan;

  @override
  Future<void> submit(RecoverySheetCode code) async {
    submitted.add(code);
    final f = failsWith;
    if (f != null) throw f;
    if (accepts != null && accepts != code) throw const RecoverySheetRejected();
  }

  @override
  Stream<RecoveryProgress> restore() => Stream.fromIterable(_progress);
}

/// Hands a [RecoverySheetEntry] down to S11.3.
class RecoverySheetScope extends InheritedWidget {
  /// Installs [sheet] above [child].
  const RecoverySheetScope({
    super.key,
    required this.sheet,
    required super.child,
  });

  /// The seam in force.
  final RecoverySheetEntry sheet;

  /// The nearest one, or null when the shell has installed none.
  static RecoverySheetEntry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RecoverySheetScope>()?.sheet;

  @override
  bool updateShouldNotify(RecoverySheetScope old) => sheet != old.sheet;
}

// ===========================================================================
// The guardian's side (S11.7, design R2.3; 04 §7.3 steps 2–3, 7)
// ===========================================================================

/// What arrives on a trusted member's phone: who is asking, and which phone.
///
/// 04 §4 🔒 — the push itself carries **no financial content**, and neither
/// does this: a name, a device model and the fingerprint the guardian reads
/// back over the call. Nothing about books, balances or entries.
@immutable
final class GuardianRecoveryAsk {
  /// Creates the ask.
  const GuardianRecoveryAsk({
    required this.requestId,
    required this.requesterName,
    required this.newDeviceName,
    required this.newDeviceFingerprint,
    this.requesterPhone,
  });

  /// Server id of the attempt.
  final String requestId;

  /// Who is asking.
  final String requesterName;

  /// The new phone, as its owner would describe it ("iPhone 13").
  final String newDeviceName;

  /// Its fingerprint, drawn small and monospaced so it can be read aloud
  /// (04 §7.3 step 2 🔒).
  final String newDeviceFingerprint;

  /// Their number, when the book has one — R2.3's caution is *call them*, so
  /// the number belongs on the screen where there is one.
  final String? requesterPhone;

  @override
  bool operator ==(Object other) =>
      other is GuardianRecoveryAsk &&
      other.requestId == requestId &&
      other.requesterName == requesterName &&
      other.newDeviceName == newDeviceName &&
      other.newDeviceFingerprint == newDeviceFingerprint &&
      other.requesterPhone == requesterPhone;

  @override
  int get hashCode => Object.hash(
    requestId,
    requesterName,
    newDeviceName,
    newDeviceFingerprint,
    requesterPhone,
  );
}

/// What S11.7 consumes.
abstract interface class GuardianApprovals {
  /// Reads the ask. Throws [RecoveryFailure].
  Future<GuardianRecoveryAsk> load(String requestId);

  /// ADR 2026-09-13c ruling 3 🔒 — scans the fresh device's QR and compares it
  /// with the relayed request, behind the seam.
  Future<RecoveryScanOutcome> verifyCandidateByScan(String requestId);

  /// Re-seals this member's share to the verified candidate (04 §7.3 step 3).
  ///
  /// Throws [RecoveryCandidateUnverified] when
  /// [verifyCandidateByScan] has not returned [RecoveryScanOutcome.verified]
  /// for this request — the check, not the advice.
  Future<void> approve(String requestId);

  /// *Not now* (04 §7.3 step 7). Needs no scan: refusing is always safe.
  Future<void> decline(String requestId);
}

/// The scripted [GuardianApprovals] every S11.7 test runs against.
final class FakeGuardianApprovals implements GuardianApprovals {
  /// Creates the fake over [ask].
  FakeGuardianApprovals({
    GuardianRecoveryAsk? ask,
    this.failLoad = false,
    this.scan = RecoveryScanOutcome.verified,
  }) : _ask =
           ask ??
           const GuardianRecoveryAsk(
             requestId: 'req-1',
             requesterName: 'Gurpreet',
             newDeviceName: 'iPhone 13',
             newDeviceFingerprint: '8F3C 21A9 5B70 D4E1',
             requesterPhone: '98765 43210',
           );

  final GuardianRecoveryAsk _ask;

  /// When true, [load] throws.
  bool failLoad;

  /// What [verifyCandidateByScan] answers.
  RecoveryScanOutcome scan;

  /// Request ids verified so far.
  final Set<String> verified = {};

  /// Request ids approved, oldest first.
  final List<String> approved = [];

  /// Request ids declined, oldest first.
  final List<String> declined = [];

  @override
  Future<GuardianRecoveryAsk> load(String requestId) async {
    if (failLoad) throw const RecoveryFailure('load');
    return _ask;
  }

  @override
  Future<RecoveryScanOutcome> verifyCandidateByScan(String requestId) async {
    if (scan == RecoveryScanOutcome.verified) verified.add(requestId);
    return scan;
  }

  @override
  Future<void> approve(String requestId) async {
    if (!verified.contains(requestId)) {
      throw const RecoveryCandidateUnverified();
    }
    approved.add(requestId);
  }

  @override
  Future<void> decline(String requestId) async => declined.add(requestId);
}

/// Hands a [GuardianApprovals] down to S11.7.
class GuardianApprovalsScope extends InheritedWidget {
  /// Installs [approvals] above [child].
  const GuardianApprovalsScope({
    super.key,
    required this.approvals,
    required super.child,
  });

  /// The seam in force.
  final GuardianApprovals approvals;

  /// The nearest one, or null when the shell has installed none.
  static GuardianApprovals? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GuardianApprovalsScope>()
      ?.approvals;

  @override
  bool updateShouldNotify(GuardianApprovalsScope old) =>
      approvals != old.approvals;
}
