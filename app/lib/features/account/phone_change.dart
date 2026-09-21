// The seam S16.2 consumes — changing the number on the identity record
// (06 §9.4 🔒, 07 §21 🔒, 13 §3.2 row S16.2, ADR 2026-09-05d §1).
//
// 06 §9.4 🔒 is one sentence and this file is its shape:
//
//   *OTP on old number (or, if lost, guardian approval k-of-n) + OTP on new
//   number → identity record updates; UMK, keys, memberships untouched.*
//
// Two things follow and are enforced here rather than in a build method.
//
//  1. **The new number's code is never optional.** It is required on *both*
//     routes — the guardian branch replaces the *old* number's proof and
//     nothing else. [PhoneChangeStage] therefore has no path from
//     [PhoneChangeStage.oldNumberProved] to [PhoneChangeStage.done] that
//     skips [PhoneChangeStage.codeSentToNew].
//  2. **Nothing here carries key material.** 06 §9.4 says UMK, keys and
//     memberships are untouched: the number was only ever the doorbell. So
//     the richest thing that crosses this seam is a phone number, a count and
//     an enum — a screen cannot leak a key it was never handed (04 §7.4,
//     07 §5.6 🔒).
//
// **One vocabulary, not two.** The k-of-n ask is the same act the recovery
// ladder already performs, so this file imports the ladder's own
// [TrustedApprover], [TrustedApproverState] and [RecoveryAttemptState] rather
// than minting parallel names. The user-facing word stays **trusted member**;
// "guardian" and "share" are engineering words and never reach a screen
// (01 §1.3 tone). What is *not* reused is `GuardianRecoveryAttempt` itself:
// it carries a `restore` progress and the ceremony call
// `verifyOwnKeyByScan()`, and both exist to guard a key coming back together.
// A phone-number change reconstructs nothing, so dragging them in here would
// state something 06 §9.4 explicitly denies.
//
// ⚠️ SPEC: 04 §7.3's guardian approval is defined as a guardian **re-sealing a
// share to a candidate key**, and migration 0010's `recovery_approvals` row is
// shaped that way (`wrapped_key_id`, `sealed_to_pub_x`). A phone-change
// approval has no share to re-seal — 06 §9.4 🔒 says the keys are untouched —
// so the two cannot be the same row. The conservative reading taken here is
// that 06 §9.4's "guardian approval k-of-n" is a **decision-only** k-of-n over
// the same trusted-member set, with the same k, the same 72 h window and the
// same 24 h cancellable delay, and that the server grows its own table for it.
// Nothing in this file names a route or a table; guessing the wire shape would
// be the invention CLAUDE.md forbids. Reported as an open item.
//
// ⚠️ WIRE — the whole interface is this lane's. [FakePhoneChange] is what
// S16.2 is built and tested against; the adapter lands with the auth/server
// lanes that own the phone-change routes.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../shared/seams/recovery_ladder.dart'
    show RecoveryAttemptState, TrustedApprover, TrustedApproverState;

export '../../shared/seams/recovery_ladder.dart'
    show RecoveryAttemptState, TrustedApprover, TrustedApproverState;

/// India's country code — the only one the app registers numbers under
/// (06 §2). Held once so the field's prefix and the seam agree.
const phoneCountryCode = '+91';

/// A ten-digit Indian mobile number: `[6-9]` then nine digits. The same shape
/// S0.2 enforces at first run — a number this app could never have sent an
/// OTP to is not a number it may change *to*.
final phoneNationalShape = RegExp(r'^[6-9][0-9]{9}$');

/// `+91XXXXXXXXXX` from ten typed digits.
String phoneE164(String tenDigits) => '$phoneCountryCode${tenDigits.trim()}';

/// Where a change has got to. The order is 06 §9.4's order, and the only
/// door into [done] is [codeSentToNew] — the new number always proves itself.
enum PhoneChangeStage {
  /// Nothing started. The screen explains what does *not* change, shows the
  /// number on the record, and offers the two ways to prove it.
  start,

  /// A code went to the **old** number and is waiting to be typed.
  codeSentToOld,

  /// The old number is lost: trusted members have been asked, k-of-n is
  /// running, and [PhoneChangeAttempt.request] says where it stands.
  askingTrustedMembers,

  /// The old number is proved — by its code, or by k approvals and any wait
  /// that applied. The new number is asked for next.
  oldNumberProved,

  /// A code went to the **new** number.
  codeSentToNew,

  /// The identity record now holds the new number. Keys, books and
  /// memberships were never touched (06 §9.4 🔒).
  done,
}

/// Why a call failed. Plain causes, never a server code (07 §1 rule 12).
enum PhoneChangeFailureKind {
  /// Wrong code; [PhoneChangeFailure.attemptsLeft] says how many remain.
  invalidCode,

  /// Three wrong codes, or the code aged out — ask for a new one (06 §2).
  codeExpired,

  /// The per-number limit was hit (06 §2: 5/hour, 10/day).
  rateLimited,

  /// The typed number is not a ten-digit Indian mobile number.
  badNumber,

  /// The "new" number is the number already on the record.
  sameNumber,

  /// This user set no trusted members up, so the lost-number route has
  /// nobody to ask (04 §7.3 setup never happened).
  noTrustedMembers,

  /// Transport failed; **nothing changed**. The copy says so, because a
  /// half-done identity change is the one thing a reader will fear.
  network,
}

/// A failed call. Carries a cause and, for a wrong code, the tries left.
final class PhoneChangeFailure implements Exception {
  /// Creates the failure.
  const PhoneChangeFailure(this.kind, {this.attemptsLeft});

  /// What went wrong.
  final PhoneChangeFailureKind kind;

  /// Tries left, for [PhoneChangeFailureKind.invalidCode] only.
  final int? attemptsLeft;

  @override
  String toString() => 'PhoneChangeFailure(${kind.name})';
}

/// The k-of-n ask, as S16.2 draws it.
///
/// Deliberately the *shape* of a recovery attempt minus everything about keys:
/// the rows, the tally, the 72 h window and the 24 h delay of
/// ADR 2026-09-05d §1 🔒. The tally is counted from the rows, never read off a
/// counter, for the same reason S11.2 counts it that way — a screen that says
/// *who* cannot be lying about *how many*.
@immutable
final class TrustedApprovalRequest {
  /// Creates a snapshot.
  const TrustedApprovalRequest({
    required this.requestId,
    required this.k,
    required this.n,
    required this.approvers,
    this.state = RecoveryAttemptState.pending,
    this.waitUntil,
    this.expiresAt,
  });

  /// Server id of the ask — never displayed.
  final String requestId;

  /// How many must say yes — `⌈(n+1)/2⌉`, enforced server-side (04 §7.3).
  final int k;

  /// How many trusted members the user has.
  final int n;

  /// One row per trusted member, in the order the screen draws them.
  final List<TrustedApprover> approvers;

  /// Where the ask stands.
  final RecoveryAttemptState state;

  /// End of the 24 h cancellable window (ADR 2026-09-05d §1 🔒), or null when
  /// no wait applies.
  final DateTime? waitUntil;

  /// End of the 72 h window the members have to answer in.
  final DateTime? expiresAt;

  /// How many have said yes — counted from the rows.
  int get approvals =>
      approvers.where((a) => a.state == TrustedApproverState.approved).length;

  /// How many have said no. Three closes the ask (04 §7.3 step 7).
  int get declines =>
      approvers.where((a) => a.state == TrustedApproverState.declined).length;

  /// Whether the ask is over, either way. 03 §2.2 has no `denied`, so a
  /// refused ask and a lapsed one are the same value and no copy may tell
  /// them apart (the ⚠️ SPEC on `rf.recovery_derive`).
  bool get isClosed =>
      state == RecoveryAttemptState.expired ||
      state == RecoveryAttemptState.cancelled;

  /// Whole hours left of the 24 h wait at [now], floored at zero. A count,
  /// never a percentage (11 §4.5 🔒).
  int hoursLeft(DateTime now) {
    final until = waitUntil;
    if (until == null) return 0;
    final left = until.difference(now).inHours;
    return left < 0 ? 0 : left;
  }

  /// 0..1 for the determinate rule: approvals against [k]. Never null, so the
  /// rule can never degrade into an indeterminate sweep.
  double get fraction => k <= 0 ? 0 : (approvals / k).clamp(0, 1).toDouble();
}

/// Everything S16.2 renders.
@immutable
final class PhoneChangeAttempt {
  /// Creates a snapshot.
  const PhoneChangeAttempt({
    required this.currentNumber,
    this.stage = PhoneChangeStage.start,
    this.newNumber,
    this.request,
    this.trustedMemberCount = 0,
    this.hasOtherActiveDevice = false,
  });

  /// The number on the identity record right now, as it was registered.
  final String currentNumber;

  /// Where the change has got to.
  final PhoneChangeStage stage;

  /// The number being moved to, in E.164, once it has been accepted. Null
  /// before that.
  final String? newNumber;

  /// The k-of-n ask, when the lost-number route is running.
  final TrustedApprovalRequest? request;

  /// How many trusted members this user set up. Zero disables the
  /// lost-number route **with a reason and a way to fix it** — never by
  /// hiding the row (13 §4.3, 07 §1 rule 6).
  final int trustedMemberCount;

  /// Whether the user has another certified device signed in. It decides
  /// whether the 24 h delay of ADR 2026-09-05d §1 🔒 applies at all.
  final bool hasOtherActiveDevice;

  /// Whether the old number has been proved, either way.
  bool get oldNumberProved =>
      stage == PhoneChangeStage.oldNumberProved ||
      stage == PhoneChangeStage.codeSentToNew ||
      stage == PhoneChangeStage.done;

  /// Copy with the named fields replaced. [clearRequest] drops the ask.
  PhoneChangeAttempt copyWith({
    String? currentNumber,
    PhoneChangeStage? stage,
    String? newNumber,
    TrustedApprovalRequest? request,
    bool clearRequest = false,
    int? trustedMemberCount,
    bool? hasOtherActiveDevice,
  }) => PhoneChangeAttempt(
    currentNumber: currentNumber ?? this.currentNumber,
    stage: stage ?? this.stage,
    newNumber: newNumber ?? this.newNumber,
    request: clearRequest ? null : (request ?? this.request),
    trustedMemberCount: trustedMemberCount ?? this.trustedMemberCount,
    hasOtherActiveDevice: hasOtherActiveDevice ?? this.hasOtherActiveDevice,
  );
}

/// What S16.2 asks for and nothing else.
abstract interface class PhoneChange {
  /// The attempt as it stands, then every change. The lost-number route may
  /// be open for days, so this is a stream and not a one-shot read.
  Stream<PhoneChangeAttempt> watch();

  /// The latest snapshot, or null before the first arrives.
  PhoneChangeAttempt? get current;

  /// (Re)reads the attempt. Throws [PhoneChangeFailure].
  Future<void> refresh();

  /// Sends a code to the **old** number (06 §9.4 🔒, first half).
  Future<void> sendCodeToOldNumber();

  /// Checks a code sent to the old number.
  Future<void> verifyOldNumberCode(String code);

  /// Opens the k-of-n ask when the old number is lost (06 §9.4 🔒). The old
  /// number still receives the plain notice that a change was requested — the
  /// server sends it; the screen only promises it.
  Future<void> askTrustedMembers();

  /// One-tap Cancel (ADR 2026-09-05d §1 🔒). Closes the ask, whatever stage
  /// it is at, and changes nothing.
  Future<void> cancel();

  /// Sends a code to the **new** number. [e164] is `+91` + ten digits.
  Future<void> sendCodeToNewNumber(String e164);

  /// Checks the code sent to the new number. On success the identity record
  /// holds the new number and the stage is [PhoneChangeStage.done].
  Future<void> verifyNewNumberCode(String code);
}

/// The scripted [PhoneChange] every S16.2 test runs against, and the only
/// implementation in the app until the phone-change routes exist.
///
/// No timers, no clock, no network: a widget test drives it by pumping and by
/// calling [emit] where the server would have pushed.
final class FakePhoneChange implements PhoneChange {
  /// Creates the fake over [initial].
  FakePhoneChange({PhoneChangeAttempt? initial, this.failRefresh = false})
    : _current =
          initial ?? const PhoneChangeAttempt(currentNumber: '+91 98765 43210');

  /// The pack's own example: three trusted members, 2 of them needed, one
  /// already said yes, and another phone of the user's is signed in — so the
  /// 24 h window applies.
  factory FakePhoneChange.asking({DateTime? waitUntil, DateTime? expiresAt}) =>
      FakePhoneChange(
        initial: PhoneChangeAttempt(
          currentNumber: '+91 98765 43210',
          stage: PhoneChangeStage.askingTrustedMembers,
          trustedMemberCount: 3,
          hasOtherActiveDevice: true,
          request: TrustedApprovalRequest(
            requestId: 'pc-1',
            k: 2,
            n: 3,
            expiresAt: expiresAt,
            waitUntil: waitUntil,
            approvers: const [
              TrustedApprover(
                memberId: 'm1',
                name: 'Sunita',
                state: TrustedApproverState.approved,
                phone: '98765 43211',
              ),
              TrustedApprover(
                memberId: 'm2',
                name: 'Harjit',
                state: TrustedApproverState.waiting,
                phone: '98765 43212',
              ),
              TrustedApprover(memberId: 'm3', name: 'Balwinder'),
            ],
          ),
        ),
      );

  PhoneChangeAttempt? _current;
  final _controller = StreamController<PhoneChangeAttempt>.broadcast();

  /// When true, [refresh] throws.
  bool failRefresh;

  /// Thrown once by the next call that is not [refresh], then cleared.
  PhoneChangeFailure? failNext;

  /// Only this code verifies; null lets any six digits through.
  String? expectedCode;

  /// Wrong codes allowed before a new one is required (06 §2: 3).
  int attemptsLeft = 3;

  /// Codes handed to [verifyOldNumberCode], in order.
  final oldCodes = <String>[];

  /// Codes handed to [verifyNewNumberCode], in order.
  final newCodes = <String>[];

  /// Numbers handed to [sendCodeToNewNumber], in order.
  final newNumbers = <String>[];

  /// Times a code was asked for on the old number.
  int oldSends = 0;

  /// Times the trusted-member ask was opened.
  int asks = 0;

  /// Times [cancel] ran.
  int cancels = 0;

  @override
  PhoneChangeAttempt? get current => _current;

  @override
  Stream<PhoneChangeAttempt> watch() async* {
    final c = _current;
    if (c != null) yield c;
    yield* _controller.stream;
  }

  /// Pushes a snapshot, as the server would.
  void emit(PhoneChangeAttempt a) {
    _current = a;
    _controller.add(a);
  }

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  void _stage(PhoneChangeStage stage) {
    final c = _current;
    if (c != null) emit(c.copyWith(stage: stage));
  }

  @override
  Future<void> refresh() async {
    if (failRefresh) {
      throw const PhoneChangeFailure(PhoneChangeFailureKind.network);
    }
    final c = _current;
    if (c != null) _controller.add(c);
  }

  @override
  Future<void> sendCodeToOldNumber() async {
    _maybeFail();
    oldSends++;
    _stage(PhoneChangeStage.codeSentToOld);
  }

  @override
  Future<void> verifyOldNumberCode(String code) async {
    _maybeFail();
    oldCodes.add(code);
    _check(code);
    _stage(PhoneChangeStage.oldNumberProved);
  }

  @override
  Future<void> askTrustedMembers() async {
    _maybeFail();
    final c = _current;
    if (c != null && c.trustedMemberCount == 0) {
      throw const PhoneChangeFailure(PhoneChangeFailureKind.noTrustedMembers);
    }
    asks++;
    _stage(PhoneChangeStage.askingTrustedMembers);
  }

  @override
  Future<void> cancel() async {
    _maybeFail();
    cancels++;
    final c = _current;
    if (c == null) return;
    final r = c.request;
    emit(
      c.copyWith(
        stage: PhoneChangeStage.start,
        request: r == null
            ? null
            : TrustedApprovalRequest(
                requestId: r.requestId,
                k: r.k,
                n: r.n,
                approvers: r.approvers,
                state: RecoveryAttemptState.cancelled,
                waitUntil: r.waitUntil,
                expiresAt: r.expiresAt,
              ),
      ),
    );
  }

  @override
  Future<void> sendCodeToNewNumber(String e164) async {
    _maybeFail();
    newNumbers.add(e164);
    final c = _current;
    if (c != null) {
      emit(c.copyWith(stage: PhoneChangeStage.codeSentToNew, newNumber: e164));
    }
  }

  @override
  Future<void> verifyNewNumberCode(String code) async {
    _maybeFail();
    newCodes.add(code);
    _check(code);
    final c = _current;
    if (c != null) {
      emit(
        c.copyWith(
          stage: PhoneChangeStage.done,
          currentNumber: c.newNumber ?? c.currentNumber,
        ),
      );
    }
  }

  void _check(String code) {
    final expected = expectedCode;
    if (expected == null || code == expected) return;
    attemptsLeft--;
    if (attemptsLeft <= 0) {
      throw const PhoneChangeFailure(PhoneChangeFailureKind.codeExpired);
    }
    throw PhoneChangeFailure(
      PhoneChangeFailureKind.invalidCode,
      attemptsLeft: attemptsLeft,
    );
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}

/// Hands a [PhoneChange] down to S16.2. Absent, the screen falls back to a
/// shared fake so a shell-only test still renders rather than throwing — the
/// same convention [AccountRepositoryScope] follows.
class PhoneChangeScope extends InheritedWidget {
  /// Installs [phoneChange] above [child].
  const PhoneChangeScope({
    super.key,
    required this.phoneChange,
    required super.child,
  });

  /// The seam in force.
  final PhoneChange phoneChange;

  /// The nearest one, or null when nothing installed one.
  static PhoneChange? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PhoneChangeScope>()
      ?.phoneChange;

  @override
  bool updateShouldNotify(PhoneChangeScope old) =>
      phoneChange != old.phoneChange;
}
