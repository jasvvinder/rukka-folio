// An in-memory [CashCountSource] for tests and for driving the screen before
// the ledger lane lands (the `shared/seams/` fakes live in lib/ for the same
// reason). It does **not** re-decide anything: it calls the engine's own
// `validateCount` and `resolveCount` (02 §8.2 🔒, A-02-83…92) and hands their
// results back, so a screen that is green against this fake is green against
// the rule, not against a stub's opinion of it.
import 'package:core_ledger/core_ledger.dart';

import 'cash_count_source.dart';

/// A [CashCountSource] over a fixed target, recording what it was asked to save.
final class FakeCashCountSource implements CashCountSource {
  /// Creates the fake.
  FakeCashCountSource({
    required this.target,
    Account? adjustments,
    this.failLoad = false,
    this.failSave = false,
    this.loadDelay,
  }) : adjustments =
           adjustments ??
           Account(
             id: 'adjustments',
             bookId: target.bookId,
             name: 'Adjustments',
             accountClass: AccountClass.equitySystem,
             systemRole: SystemRole.adjustments,
             createdOrder: 0,
           );

  /// What [loadTarget] answers.
  CashCountTarget target;

  /// The book's Adjustments A/C — where a cash difference lands (02 §8.2).
  final Account adjustments;

  /// Makes [loadTarget] throw, for the error state.
  bool failLoad;

  /// Makes [saveCount] throw, for the save-error state.
  bool failSave;

  /// Holds [loadTarget] pending, for the loading state.
  Duration? loadDelay;

  /// Every draft this fake was asked to save, in order.
  final List<CashCountDraft> saved = [];

  /// The lines of the entry each save posted (empty for a verification).
  final List<List<Line>> posted = [];

  @override
  Future<CashCountTarget> loadTarget(String accountId) async {
    if (loadDelay != null) await Future<void>.delayed(loadDelay!);
    if (failLoad) throw StateError('no such account: $accountId');
    return target;
  }

  @override
  Future<CashCountResult> saveCount(CashCountDraft draft) async {
    if (failSave) throw StateError('save failed');
    final count = draft.toEvent(bookId: target.bookId);
    final violations = validateCount(
      count,
      bookType: target.bookType,
      account: target.account,
    );
    if (violations.isNotEmpty) throw CashCountRefused(violations);
    final income = draft.incomeAccountId == null
        ? null
        : target.incomeAccounts.firstWhere(
            (a) => a.id == draft.incomeAccountId,
          );
    final outcome = resolveCount(
      count,
      account: target.account,
      bookBalance: target.bookBalance,
      adjustmentsAccount: adjustments,
      incomeAccount: income,
    );
    saved.add(draft);
    posted.add(outcome.lines);
    return CashCountResult(
      outcome: outcome,
      date: draft.date,
      postedEntryId: outcome.lines.isEmpty ? null : 'entry-${saved.length}',
      incomeAccountName: income?.name,
    );
  }
}
