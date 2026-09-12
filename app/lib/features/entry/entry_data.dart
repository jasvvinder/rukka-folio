// What S2 needs from the local projection: the book's accounts (the facade
// already streams those) and how often each money account has been used, so
// the chip row can show "the three most-used money accounts" (07 §5 step 2
// 🔒) rather than an arbitrary three.
//
// The count is read from the same projection tables Home reads (`entries_p`,
// `entry_lines_p`, 03 §3.2) with the projection's own row filter (02 §9):
// heads of accepted amend chains, `pending`/`rejected` excluded. It is a
// *frequency*, never a balance — no posting rule is re-implemented here and
// no figure leaves integer paise.
//
// Deliberately two independent streams rather than one combinator: the screen
// nests two StreamBuilders, so nothing here has to cancel a set of
// subscriptions on dispose (the U2a teardown deadlock — an async onCancel
// never completes inside flutter_test's fake-async zone).
import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart' show Variable;

import '../../shared/ledger/local_ledger.dart';
import 'entry_slots.dart';

/// How many posted lines each money account of [bookId] carries — the
/// chip row's ordering key (07 §5 step 2).
Stream<Map<String, int>> watchMoneyUseCounts(
  LocalLedger ledger,
  String bookId,
) {
  final db = ledger.db;
  final q = db.customSelect(
    'SELECT l.account_id AS id, COUNT(*) AS n '
    'FROM entry_lines_p l '
    'JOIN entries_p e ON e.id = l.entry_id '
    'JOIN accounts_p a ON a.id = l.account_id '
    'WHERE l.book_id = ?1 '
    "AND e.superseded_by IS NULL AND e.status NOT IN ('pending','rejected') "
    "AND a.class = 'money' "
    'GROUP BY l.account_id',
    variables: [Variable.withString(bookId)],
    readsFrom: {db.entriesP, db.entryLinesP, db.accountsP},
  );
  return q.watch().map(
    (rows) => {for (final r in rows) r.read<String>('id'): r.read<int>('n')},
  );
}

/// The chip row: the [take] most-used money accounts of [all], most-used
/// first, ties broken by the chart's own creation order so the row is stable
/// between rebuilds. Archived accounts never appear.
List<AccountBalance> topMoneyAccounts(
  List<AccountBalance> all,
  Map<String, int> counts, {
  int take = 3,
  String? exclude,
}) {
  final money =
      [
        for (final a in all)
          if (a.account.accountClass == AccountClass.money &&
              !a.archived &&
              a.account.id != exclude)
            a,
      ]..sort((x, y) {
        final c = (counts[y.account.id] ?? 0).compareTo(
          counts[x.account.id] ?? 0,
        );
        return c != 0
            ? c
            : x.account.createdOrder.compareTo(y.account.createdOrder);
      });
  return money.take(take).toList();
}

/// The book's Drawings account (`SystemRole.drawings`, 02 §7.1 *Just me*),
/// or null when the chart has none seeded — the ADR 2026-09-09b seeding gap
/// (07 §5 "Owner's drawings" 🔒 paragraph, S2.5).
Account? drawingsAccountOf(List<AccountBalance> all) {
  for (final a in all) {
    if (a.account.accountClass == AccountClass.equitySystem &&
        a.account.systemRole == SystemRole.drawings) {
      return a.account;
    }
  }
  return null;
}

/// Accounts that may answer [spec], matching [query], most-used money first
/// and then the chart's order — recents-and-favourites shaped, which is what
/// 07 §5 step 3 asks the in-place picker to fill itself with.
///
/// [exclude] drops the account already chosen on the other side, so a
/// transfer can never be built from an account to itself (02 §2 verb 5).
List<AccountBalance> slotCandidates(
  List<AccountBalance> all,
  SlotSpec spec, {
  Map<String, int> counts = const {},
  String query = '',
  String? exclude,
}) {
  final q = query.trim().toLowerCase();
  final rows =
      [
        for (final a in all)
          if (spec.classes.contains(a.account.accountClass) &&
              !a.archived &&
              a.account.id != exclude &&
              (q.isEmpty || a.account.name.toLowerCase().contains(q)))
            a,
      ]..sort((x, y) {
        final c = (counts[y.account.id] ?? 0).compareTo(
          counts[x.account.id] ?? 0,
        );
        return c != 0
            ? c
            : x.account.createdOrder.compareTo(y.account.createdOrder);
      });
  return rows;
}
