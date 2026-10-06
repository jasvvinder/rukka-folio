// Each account's **opening** figure — what S0.6 shows on a row whose opening
// is already in the book (P1A review, finding 2).
//
// Not the running balance. S0.6 can be reopened from the S0.7 checklist after
// entries have moved money (02 §4: guided setup is re-runnable until first
// lock; 07 §3.1 step 7 🔒: resumable from Home's setup card), so an account's
// balance is no longer its opening: a Cash A/c with no opening and one
// ₹200 spend reads −₹200, and treating that as "the opening is in" would show
// it as one, lock the row, and leave *Finish* nothing to post.
//
// An opening is what `LocalLedger.openingBalances` posts (02 §4): an
// `adjustment` with a line on the book's *Opening Balance* system account
// (S3.1's balance-in-the-same-breath posts the same verb). The figure is the
// sum of the account's own lines in those entries, so a reversed opening nets
// back to nil and the row takes a figure again. Read-side only, on the
// projection's own row filter (02 §9, as `home_data.dart` reads it); no
// posting rule here, integer paise throughout.
import 'package:drift/drift.dart' show Variable;

import '../../shared/ledger/local_ledger.dart';

/// Account id → signed opening paise (+ = Dr) for every account of [bookId]
/// that has a non-nil opening. An account absent from the map has none.
Stream<Map<String, int>> watchOpeningFigures(
  LocalLedger ledger,
  String bookId,
) {
  final db = ledger.db;
  final q = db.customSelect(
    'SELECT l.account_id, SUM(l.amount_paise) AS p '
    'FROM entry_lines_p l JOIN entries_p e ON e.id = l.entry_id '
    "WHERE e.book_id = ?1 AND e.kind = 'adjustment' "
    "AND e.superseded_by IS NULL AND e.status NOT IN ('pending','rejected') "
    'AND EXISTS (SELECT 1 FROM entry_lines_p o '
    'JOIN accounts_p a ON a.id = o.account_id '
    "WHERE o.entry_id = e.id AND a.system_role = 'opening_balance') "
    'GROUP BY l.account_id',
    variables: [Variable.withString(bookId)],
    readsFrom: {db.entriesP, db.entryLinesP, db.accountsP},
  );
  return q.watch().map(
    (rows) => {
      for (final r in rows)
        if (r.read<int>('p') != 0)
          r.read<String>('account_id'): r.read<int>('p'),
    },
  );
}
