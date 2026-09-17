// [CloseSource] over the real ledger — S10's source of truth (02 §8 🔒).
//
// It is a **composer**, not a decider. Every judgement on this screen belongs
// somewhere else and is carried here unchanged:
//
//   * what blocks — `LocalLedger.monthClosePreconditions`, which is the
//     engine's `monthLockPreconditions` over the projected state unioned with
//     the mirror's own gaps and `held` rows (02 §8 step 3 🔒, ADR
//     2026-09-05b §3–4, ADR 2026-09-05e §4);
//   * what the lock records — `LocalLedger.lockMonth`, which publishes the
//     projector's own canonical vector and `core_ledger.projectorVersion`
//     (02 §8 step 4 🔒, ADR 2026-09-05c §3). No hash is computed in this
//     file, and none may be;
//   * the figures — `watchAccounts` and `lastCashCount`, the same reads S1,
//     S4 and S5.5 draw from, so the close cannot disagree with the screens
//     the closer just came from (02 §9: balances are derived, never stored
//     twice).
//
// What it adds is only shape: the engine's blockers become [CloseBlockingItem]
// with a human label, the warn-only facts become [CloseWarningItem], and the
// two stay different types all the way to the widget (07 §13 🔒).
//
// Money is [Paise] end to end (CLAUDE.md rule 1).
import 'package:core_ledger/core_ledger.dart';

import '../../shared/ledger/local_ledger.dart';
import 'close_source.dart';

/// The ageing window after which an open advance warns on the close tray.
///
/// ⚠️ SPEC: 02 §7 makes this configurable per book, default 15 days to the
/// holder then 30 to the approver, but `book_config` carries no such field
/// yet and the projector may not read settings (03 §3.3 rule 2). The
/// conservative reading is the **later** of the two published defaults: a
/// warning that appears a fortnight late is a smaller wrong than one that
/// nags every closer about a ten-day advance. Replace this with the book's
/// own window when `book_config` grows one.
const int defaultAdvanceAgeingDays = 30;

/// [CloseSource] backed by [LocalLedger].
final class LedgerCloseSource implements CloseSource {
  /// Creates the source over [ledger].
  const LedgerCloseSource(this.ledger);

  /// The ledger facade. One instance per app, installed by the shell.
  final LocalLedger ledger;

  @override
  Future<CloseView> loadClose(String bookId, YearMonth period) async {
    final chart = await ledger.chartOf(bookId);
    final accounts = await ledger.watchAccounts(bookId).first;
    final bookName = await _bookName(bookId);

    final cash = <CloseCashAccount>[];
    final banks = <CloseBankAccount>[];
    final unverified = <CloseWarningItem>[];

    for (final row in accounts) {
      final a = row.account;
      if (!a.isMoney || row.archived) continue;
      final balance = Paise(row.balancePaise);
      if (a.subtype == MoneySubtype.cash ||
          a.subtype == MoneySubtype.cashCollection) {
        // The row is a door to S5.5, which owns counting (02 §8.2 🔒); this
        // only needs to know whether a count landed inside the month.
        final last = await ledger.lastCashCount(a.id);
        final counted = last != null && period.contains(last.date);
        cash.add(
          CloseCashAccount(
            accountId: a.id,
            name: a.name,
            bookBalance: balance,
            lastCountDate: last?.date,
            countedInPeriod: counted,
          ),
        );
        if (!counted) {
          unverified.add(
            CloseWarningItem(
              kind: CloseWarning.unverifiedCount,
              ref: a.id,
              label: a.name,
            ),
          );
        }
      } else {
        banks.add(
          CloseBankAccount(accountId: a.id, name: a.name, bookBalance: balance),
        );
      }
    }

    final blocks = await _blocks(bookId, period, chart);
    final warns = <CloseWarningItem>[
      ...await _agedAdvances(bookId),
      ...unverified,
    ];

    final saved = await ledger.closeProgress(bookId, period);
    return CloseView(
      bookId: bookId,
      bookName: bookName,
      period: period,
      cashAccounts: cash,
      bankAccounts: banks,
      tray: CloseTray(blocks: blocks, warns: warns),
      progress: _progressOf(saved),
      // ⚠️ SPEC: 13 §2.3.1's read-only member is a *role*, and this app has no
      // book-role source yet (the same gap `LocalLedger.transferBetweenBooks`
      // names). Reporting every reader as a closer would be the dangerous
      // wrong; reporting every reader as read-only would make the wizard
      // unreachable. The conservative reading that keeps 07 §1 rule 6 (no
      // dead ends) is to leave the gate to the ledger: the wizard opens, and
      // `lockMonth` is the thing that can refuse.
      readOnly: false,
    );
  }

  @override
  Future<void> saveProgress(
    String bookId,
    YearMonth period,
    CloseProgress progress,
  ) => ledger.saveCloseProgress(
    bookId,
    period,
    SavedCloseProgress(
      step: progress.step.name,
      confirmedAccountIds: progress.confirmedBankIds,
    ),
  );

  @override
  Future<CloseLockResult> lock({
    required String bookId,
    required YearMonth period,
    required Map<String, Paise> declaredBalances,
  }) async {
    final LockedMonth locked;
    try {
      locked = await ledger.lockMonth(
        bookId,
        period,
        declaredBalances: declaredBalances,
      );
    } on MonthLockRefused catch (e) {
      // The engine's own items, not a message this file invented.
      throw CloseRefused(e.blockers);
    }
    // The wizard is over: a closed month must not resume one.
    await ledger.clearCloseProgress(bookId, period);
    return CloseLockResult(
      lock: locked.lock,
      verification: locked.verification,
    );
  }

  // ── the tray ──────────────────────────────────────────────────────────────

  Future<List<CloseBlockingItem>> _blocks(
    String bookId,
    YearMonth period,
    Chart chart,
  ) async {
    final out = <CloseBlockingItem>[];
    for (final b in await ledger.monthClosePreconditions(bookId, period)) {
      out.add(
        CloseBlockingItem(
          kind: b.kind,
          ref: b.ref,
          label: await _labelFor(b, chart),
          // ⚠️ SPEC: 07 §13 🔒 and 07 §28 want S10.5 to **name the phone**
          // whose entries have not arrived. `author_gaps.author_device` is a
          // device id and no table in `packages/data` carries a device label
          // — `DeviceCert` has none either (04 §3.4). Printing a uuid at a
          // shopkeeper is worse than saying *another phone*, so this stays
          // null until a device-name source exists.
          deviceName: null,
        ),
      );
    }
    return out;
  }

  /// A human label for what a blocker points at, or null — in which case the
  /// screen states the kind alone rather than an id.
  Future<String?> _labelFor(CloseBlockerItem b, Chart chart) async {
    switch (b.kind) {
      case CloseBlocker.reviewFlagOpen:
      case CloseBlocker.advancePending:
      case CloseBlocker.heldEnvelope:
        final entry = await ledger.entry(b.ref);
        return entry?.note;
      case CloseBlocker.suspenseNonZero:
        for (final a in chart.accounts) {
          if (a.id == b.ref) return a.name;
        }
        return null;
      case CloseBlocker.monthOpen:
      case CloseBlocker.authorGapOpen:
        // A month label is the ref itself; a device id has no name to give.
        return null;
    }
  }

  Future<List<CloseWarningItem>> _agedAdvances(String bookId) async => [
    for (final a in await ledger.openAdvances(bookId))
      if (a.ageDays >= defaultAdvanceAgeingDays)
        CloseWarningItem(
          kind: CloseWarning.agedAdvance,
          ref: a.accountId,
          label: a.accountName,
        ),
  ];

  /// The saved step, resolved back to a [CloseStep].
  ///
  /// An unknown name — progress written by a build that named its steps
  /// differently — restarts the wizard rather than crashing it: the figures
  /// are all re-read anyway, so the cost is a few taps (07 §1 rule 6).
  static CloseProgress _progressOf(SavedCloseProgress? saved) {
    if (saved == null) return const CloseProgress();
    for (final step in CloseStep.values) {
      if (step.name == saved.step) {
        return CloseProgress(
          step: step,
          confirmedBankIds: saved.confirmedAccountIds,
        );
      }
    }
    return CloseProgress(confirmedBankIds: saved.confirmedAccountIds);
  }

  Future<String> _bookName(String bookId) async {
    for (final b in await ledger.watchBooks().first) {
      if (b.id == bookId) return b.name;
    }
    // The wizard still opens and still says which month: a missing name is
    // not a dead end (07 §1 rule 6).
    return '';
  }
}
