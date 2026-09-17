// [CashCountSource] over the real ledger (02 §8.2 🔒).
//
// It decides nothing. `LocalLedger.cashCountReading` and
// `LocalLedger.recordCashCount` carry the engine's own `countPolicy`,
// `validateCount` and `resolveCount` (A-02-83…92); this file only translates
// between their types and the ones S5.5 holds, and turns the ledger's typed
// refusal into the screen's. `FakeCashCountSource` stays the contract: the
// same expectations run against both (F1-02-36…39).
import 'package:core_ledger/core_ledger.dart';

import '../../shared/ledger/local_ledger.dart';
import 'cash_count_source.dart';

/// The [CashCountSource] the app mounts above S5.5.
final class LedgerCashCountSource implements CashCountSource {
  /// Reads and writes through [ledger].
  const LedgerCashCountSource(this.ledger);

  /// The one door to the ledger.
  final LocalLedger ledger;

  @override
  Future<CashCountTarget> loadTarget(String accountId) async {
    final reading = await ledger.cashCountReading(accountId);
    final last = reading.lastCount;
    return CashCountTarget(
      bookId: reading.bookId,
      bookType: reading.bookType,
      account: reading.account,
      bookBalance: reading.bookBalance,
      lastCount: last == null
          ? null
          : LastCashCount(
              date: last.date,
              counted: last.counted,
              sheet: last.sheet,
            ),
      incomeAccounts: reading.incomeAccounts,
    );
  }

  @override
  Future<CashCountResult> saveCount(CashCountDraft draft) async {
    final RecordedCashCount recorded;
    try {
      recorded = await ledger.recordCashCount(
        accountId: draft.accountId,
        counted: draft.counted,
        date: draft.date,
        sheet: draft.sheet,
        countedBy: draft.countedBy,
        witness: draft.witness,
        incomeAccountId: draft.incomeAccountId,
      );
    } on CountRejected catch (e) {
      // The engine's own violations, never a message this layer invented
      // (07 §1 rule 6).
      throw CashCountRefused(e.violations);
    }
    final incomeAccountId = draft.incomeAccountId;
    return CashCountResult(
      outcome: recorded.outcome,
      date: recorded.count.date,
      postedEntryId: recorded.entry?.id,
      incomeAccountName: incomeAccountId == null
          ? null
          : (await ledger.chartOf(recorded.count.bookId))
                .maybeAccount(incomeAccountId)
                ?.name,
    );
  }
}
