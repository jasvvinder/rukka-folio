// What S10 needs from the ledger, and nothing more.
//
// `app/lib/shared/ledger/` belongs to another lane this round, so the wizard
// talks to this **feature-local interface** instead of to `LocalLedger`. The
// next lane implements [CloseSource] over `LocalLedger` and installs it above
// the route with [CloseScope]; nothing in this folder imports the facade.
//
// What a close *means* is the engine's to say, not this file's:
//
//   * **what blocks** is `core_ledger`'s own [CloseBlocker] — the enum
//     `monthLockPreconditions` returns (02 §8 step 3 🔒, ADR 2026-09-05b §3–4,
//     ADR 2026-09-05e §4, pinned by A-02-48…52). A blocking tray item carries
//     one, so the screen cannot invent a blocker and an implementation cannot
//     quietly demote one to a warning.
//   * **what warns** is the closed set [CloseWarning] — aged advances and
//     unverified cash counts, the two 02 §8 and 07 §13 🔒 name as warn-only.
//     It is a *different type*, so "blocks" and "warns" can never arrive as
//     one undifferentiated list (07 §13 🔒).
//   * **what a lock is** is [PeriodLock]: a signed envelope recording the
//     declared balances, the balance-vector hash and the `projector_version`
//     (02 §8 step 4 🔒, ADR 2026-09-05c §3). This seam carries the engine's
//     event back unchanged rather than a summary of it.
//
// Money is [Paise] end to end — integer paise, never a double (CLAUDE.md
// rule 1).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/widgets.dart';

/// The four steps of the month-close wizard, in the order 02 §8 🔒 states
/// them. One screen each (07 §13 🔒).
///
/// The order is the enum's own `index`, and [CloseProgress] saves it — the
/// *Resumable* rule (07 §13 🔒) is about this value and nothing else.
enum CloseStep {
  /// 1 — *Count your cash*: a door per cash A/C to the S5.5 sheet.
  countCash,

  /// 2 — *Confirm each bank balance* against the bank's own app.
  confirmBanks,

  /// 3 — *Clear the tray*: the blocks, then the warnings, stated apart.
  clearTray,

  /// 4 — *Confirm & lock*: the declared balances, then the one lock action.
  confirmAndLock;

  /// The step before this one, or null at the first.
  CloseStep? get previous => index == 0 ? null : values[index - 1];

  /// The step after this one, or null at the last.
  CloseStep? get next => index == values.length - 1 ? null : values[index + 1];
}

/// One cash A/C of the book as step 1 needs it.
///
/// The count itself is **not** taken here: the row is a door to S5.5, the one
/// screen that owns counting (02 §8.2 🔒). This carries only what the row
/// shows and what decides its state.
final class CloseCashAccount {
  /// Creates the row.
  const CloseCashAccount({
    required this.accountId,
    required this.name,
    required this.bookBalance,
    this.lastCountDate,
    this.countedInPeriod = false,
  });

  /// The A/C being counted — the id the S5.5 path is built from.
  final String accountId;

  /// Its name, as the user wrote it.
  final String name;

  /// What the entries say is in it (engine sign, 02 §9).
  final Paise bookBalance;

  /// When it was last counted, or null if it never has been.
  final LocalDate? lastCountDate;

  /// True when a count falling **inside the month being closed** exists.
  ///
  /// False is a **warning**, never a block (02 §8 🔒: unverified counts warn).
  /// The screen says *Not counted yet* and still lets the closer go on.
  final bool countedInPeriod;
}

/// One bank (or other non-cash money) A/C of the book as step 2 needs it.
final class CloseBankAccount {
  /// Creates the row.
  const CloseBankAccount({
    required this.accountId,
    required this.name,
    required this.bookBalance,
  });

  /// The A/C.
  final String accountId;

  /// Its name.
  final String name;

  /// The balance to confirm against the bank's app or statement (02 §8 step 2).
  final Paise bookBalance;
}

/// A warn-only tray item — the two 02 §8 🔒 and 07 §13 🔒 name.
///
/// Deliberately a *separate* enum from [CloseBlocker]: a warning can never be
/// mistaken for a blocker by a widget, a fake or an implementation, because
/// the two never share a type.
enum CloseWarning {
  /// An advance older than the book's ageing window (02 §7). Warns, never
  /// blocks — 02 §8.1 says so of the year close and 02 §8 of the month.
  agedAdvance,

  /// A cash A/C with no count in the month being closed (02 §8 step 1).
  unverifiedCount,
}

/// One thing standing between the closer and the lock — an engine blocker,
/// with the words the screen needs.
final class CloseBlockingItem {
  /// Creates the item.
  const CloseBlockingItem({
    required this.kind,
    required this.ref,
    this.label,
    this.deviceName,
  });

  /// The engine's own reason (`monthLockPreconditions`, 02 §8 step 3 🔒).
  final CloseBlocker kind;

  /// The entry, account, envelope or device id it points at.
  final String ref;

  /// A human label for [ref] — an A/C name, a narration. Null is fine: the
  /// screen then states the kind alone rather than an id.
  final String? label;

  /// For [CloseBlocker.authorGapOpen] and [CloseBlocker.heldEnvelope]: the
  /// **name of the phone** whose entries have not arrived. S10.5 names it
  /// (07 §28 🔒); with no name the screen says *another phone* rather than
  /// printing a device id at a shopkeeper.
  final String? deviceName;

  /// True when this item is the kind that raises S10.5 — a missing-envelope
  /// blocker rather than something the closer can clear here (ADR
  /// 2026-09-05b §3–4, ADR 2026-09-05e §4).
  bool get isGap =>
      kind == CloseBlocker.authorGapOpen || kind == CloseBlocker.heldEnvelope;
}

/// One thing the closer should know about but that does not stop the lock.
final class CloseWarningItem {
  /// Creates the item.
  const CloseWarningItem({required this.kind, required this.ref, this.label});

  /// Which warning.
  final CloseWarning kind;

  /// The advance or A/C it points at.
  final String ref;

  /// A human label for [ref] — a party or A/C name.
  final String? label;
}

/// Step 3's contents: two lists, held apart by type (07 §13 🔒).
final class CloseTray {
  /// Creates the tray.
  const CloseTray({this.blocks = const [], this.warns = const []});

  /// Everything that **blocks** the lock, in the engine's terms.
  final List<CloseBlockingItem> blocks;

  /// Everything that **warns** only.
  final List<CloseWarningItem> warns;

  /// True when nothing blocks — the only condition under which step 4's lock
  /// action is enabled (02 §8 step 3 🔒).
  bool get canLock => blocks.isEmpty;

  /// The missing-envelope blockers, which render S10.5 in place of step 4's
  /// action (07 §28 🔒, 13 §3.2 row S10.5).
  List<CloseBlockingItem> get gaps =>
      blocks.where((b) => b.isGap).toList(growable: false);

  /// Blockers the closer can act on here — everything that is not a gap.
  List<CloseBlockingItem> get clearable =>
      blocks.where((b) => !b.isGap).toList(growable: false);

  /// True when the tray is wholly empty — step 3's empty state, which still
  /// says so rather than showing two blank headings (13 §4.3).
  bool get isEmpty => blocks.isEmpty && warns.isEmpty;
}

/// Where the closer had got to — the whole of *Resumable* 🔒 (07 §13).
///
/// A shopkeeper will not finish a close in one sitting, so this is written at
/// **every** step change and read back on return. The confirmed banks belong
/// here too: re-confirming eight accounts because the phone rang is the same
/// loss of work the rule exists to prevent.
final class CloseProgress {
  /// Creates the saved progress.
  const CloseProgress({
    this.step = CloseStep.countCash,
    this.confirmedBankIds = const {},
  });

  /// The step the closer had reached.
  final CloseStep step;

  /// The bank A/Cs already confirmed as *Matches ✓* (step 2).
  final Set<String> confirmedBankIds;

  /// This progress with [step] reached.
  CloseProgress at(CloseStep step) =>
      CloseProgress(step: step, confirmedBankIds: confirmedBankIds);

  /// This progress with [accountId] confirmed or unconfirmed.
  CloseProgress withBank(String accountId, {required bool confirmed}) =>
      CloseProgress(
        step: step,
        confirmedBankIds: {
          ...confirmedBankIds.where((id) => id != accountId),
          if (confirmed) accountId,
        },
      );

  @override
  bool operator ==(Object other) =>
      other is CloseProgress &&
      other.step == step &&
      other.confirmedBankIds.length == confirmedBankIds.length &&
      other.confirmedBankIds.containsAll(confirmedBankIds);

  @override
  int get hashCode =>
      Object.hash(step, Object.hashAllUnordered(confirmedBankIds));

  @override
  String toString() => 'CloseProgress(${step.name}, $confirmedBankIds)';
}

/// Everything the wizard draws, in one load.
///
/// One load, one object: the wizard never asks the ledger a second question
/// while the closer is working, so the figures across the four steps cannot
/// drift apart mid-close.
final class CloseView {
  /// Creates the view.
  const CloseView({
    required this.bookId,
    required this.bookName,
    required this.period,
    required this.cashAccounts,
    required this.bankAccounts,
    required this.tray,
    this.progress = const CloseProgress(),
    this.readOnly = false,
  });

  /// The book being closed.
  final String bookId;

  /// Its name, for the wizard's title line.
  final String bookName;

  /// The month being closed (02 §8: periods are calendar months).
  final YearMonth period;

  /// Cash A/Cs — step 1, one row each.
  final List<CloseCashAccount> cashAccounts;

  /// Bank and other non-cash money A/Cs — step 2, one row each.
  final List<CloseBankAccount> bankAccounts;

  /// Step 3's blocks and warns.
  final CloseTray tray;

  /// Where the closer had got to (07 §13 *Resumable* 🔒).
  final CloseProgress progress;

  /// True when this member may read the book but not close it (13 §2.3.1).
  /// The wizard stays legible; the lock says why it is off.
  final bool readOnly;

  /// The declared balances the lock envelope records (02 §8 step 4 🔒): every
  /// money A/C of the book, cash and bank alike, at the figure the closer has
  /// just been shown. Integer paise, keyed by account id.
  Map<String, Paise> get declaredBalances => {
    for (final a in cashAccounts) a.accountId: a.bookBalance,
    for (final a in bankAccounts) a.accountId: a.bookBalance,
  };
}

/// What locking the month came to — the engine's own [PeriodLock], carried
/// back unchanged.
final class CloseLockResult {
  /// Creates the result.
  const CloseLockResult({required this.lock, this.verification});

  /// The signed close envelope: the declared balances, the canonical balance
  /// vector and the `projectorVersion` that computed it (02 §8 step 4 🔒).
  final PeriodLock lock;

  /// This device's own verification of that vector, when it has one — the
  /// third outcome ([CloseVerification.readerOutdated], *update to verify*)
  /// is a state, not an error (ADR 2026-09-05c §3).
  final CloseVerification? verification;
}

/// A lock the engine refused: `monthLockPreconditions` was not empty.
///
/// The wizard keeps the lock disabled for every blocker it can see, so this is
/// the backstop — and it carries the engine's own [CloseBlockerItem]s rather
/// than a message the widget invented.
final class CloseRefused implements Exception {
  /// Creates the refusal.
  const CloseRefused(this.blockers);

  /// What the engine objected to (02 §8 step 3 🔒).
  final List<CloseBlockerItem> blockers;

  @override
  String toString() => 'CloseRefused($blockers)';
}

/// The ledger, as S10 needs it.
///
/// Three reads and one write: load the close, save the progress, take the
/// lock. Nothing here decides *whether* a month may be locked — that is
/// `monthLockPreconditions`, and an implementation calls it rather than
/// re-stating it.
abstract interface class CloseSource {
  /// Everything the wizard draws for [bookId]'s [period].
  ///
  /// Throws when the book or period is unknown — the screen shows its error
  /// state with a retry (13 §4.3), never a red screen.
  Future<CloseView> loadClose(String bookId, YearMonth period);

  /// Records that the closer has reached [progress].
  ///
  /// Called at **every** step change (07 §13 *Resumable* 🔒). It must be
  /// cheap and it must survive the app being killed; the screen does not wait
  /// on it before drawing the next step.
  Future<void> saveProgress(
    String bookId,
    YearMonth period,
    CloseProgress progress,
  );

  /// Locks [period], recording [declaredBalances] on the close envelope.
  ///
  /// Implementations call `monthLockPreconditions` first and throw
  /// [CloseRefused] when it is not empty — a refusal is an exception, not a
  /// silent no-op — then publish the signed [PeriodLock] with the balance
  /// vector hash and the `projectorVersion` (02 §8 step 4 🔒).
  Future<CloseLockResult> lock({
    required String bookId,
    required YearMonth period,
    required Map<String, Paise> declaredBalances,
  });
}

/// The [CloseSource] for the tree below — installed by the shell above the
/// router, so `closeRoutes` can build the wizard from a path alone.
class CloseScope extends InheritedWidget {
  /// Creates the scope.
  const CloseScope({super.key, required this.source, required super.child});

  /// The implementation in force.
  final CloseSource source;

  /// The nearest scope, or null when the shell has not installed one yet —
  /// the screen then shows its error state rather than throwing (07 §1 rule
  /// 6: no dead ends, and no red screen either).
  static CloseSource? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CloseScope>()?.source;

  @override
  bool updateShouldNotify(CloseScope old) => source != old.source;
}
