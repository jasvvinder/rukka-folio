// The Day Book read model (07 §14 🔒 row 1 of 11; 10's M5 row — *"basic
// day-book export"*). A day book is the chronological journal: every posted
// entry of one book in date order, each with the account(s) it debited, the
// account(s) it credited, and the one figure that sits on both sides.
//
// This is a PROFESSIONAL surface (02 §10 🔒, CLAUDE.md rule 9): Dr and Cr,
// never *Money in / Money out*. The engine's sign convention (+ = Dr, − = Cr,
// 02 §1.3) is read straight out of `entry_lines_p` and never bent — this file
// only sorts the lines into two columns.
//
// ⚠️ SPEC: the natural home for this query is `LocalLedger.watchDayBook`,
// beside `watchStatement` — `shared/ledger/` owns the app's one door to the
// ledger. That file belongs to another lane's directories, so the query lives
// here, against `data`'s own `LedgerDatabase` (the package API, reached
// through `LocalLedger.db`, which the facade publishes for exactly this).
// Fold it into `LocalLedger` when `shared/ledger` next opens: nothing outside
// this file would change but the import. The shape is already the one the
// projection was indexed for — `entries_p_daybook ON entries_p(book_id,
// accounting_date DESC)` (packages/data tables.dart).
//
// Filters match `watchStatement` exactly, so the two surfaces can never
// disagree about what is in the books: heads of accepted amend chains only
// (`superseded_by IS NULL`), advance requests still pending excluded, and
// reversals plus their mirrors both present (02 §9).
import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart';

import '../../shared/ledger/local_ledger.dart';

/// One posting line of an entry, as the projection holds it (02 §1.4).
final class DayBookLine {
  /// Creates the line.
  const DayBookLine({required this.accountId, required this.amountPaise});

  /// The account this line posts to.
  final String accountId;

  /// **Signed** paise, the engine's convention: + = Dr, − = Cr (02 §1.3).
  /// Never bent — the two columns are chosen from the sign, not the other way
  /// round (02 §10 🔒).
  final int amountPaise;

  /// True when the line sits in the Dr column.
  bool get isDebit => amountPaise > 0;

  /// True when the line sits in the Cr column.
  bool get isCredit => amountPaise < 0;

  /// The figure for its column — absolute, because a column has no sign
  /// (design-system §1 rule 0b 🔒).
  int get figurePaise => amountPaise.abs();
}

/// One entry as the day book lists it: the date, the note, and every line it
/// posted, Dr lines and Cr lines in the entry's own order.
final class DayBookRow {
  /// Creates the row.
  const DayBookRow({
    required this.entryId,
    required this.date,
    required this.kind,
    required this.status,
    required this.reviewState,
    required this.lines,
    required this.hlc,
    this.note,
    this.channel,
  });

  /// Entry id — the row's door to S4.1 entry detail.
  final String entryId;

  /// `accounting_date`.
  final LocalDate date;

  /// Verb (02 §1.3).
  final EntryKind kind;

  /// Effective status as projected (`posted`, `void`, `in_tray` …).
  final String status;

  /// `none | open | approved | rejected` (03 §3.3.5).
  final String reviewState;

  /// Every posting line, in `line_index` order (03 — the order is projected
  /// so it is stable across rebuilds).
  final List<DayBookLine> lines;

  /// Entry HLC — part of the `(date, hlc, id)` order of 02 §9.
  final int hlc;

  /// Note.
  final String? note;

  /// `upi | card | netbanking | cash` (02 §1.3).
  final String? channel;

  /// The Dr lines, in order.
  Iterable<DayBookLine> get debits => lines.where((l) => l.isDebit);

  /// The Cr lines, in order.
  Iterable<DayBookLine> get credits => lines.where((l) => l.isCredit);

  /// The entry's figure, absolute paise — the sum of its Dr lines, which for
  /// a balanced entry is also the sum of its Cr lines (02 §1.4).
  int get amountPaise => debits.fold(0, (sum, l) => sum + l.figurePaise);
}

/// A day book over a period: the rows plus the cross-check totals 13 §5's
/// F3 flow line calls the *cross-check footer*.
final class DayBook {
  /// Creates the day book.
  const DayBook({
    required this.bookId,
    required this.rows,
    required this.debitTotalPaise,
    required this.creditTotalPaise,
    this.from,
    this.to,
  });

  /// An empty day book for [bookId] — the state before anything is posted.
  const DayBook.empty(this.bookId, {this.from, this.to})
    : rows = const [],
      debitTotalPaise = 0,
      creditTotalPaise = 0;

  /// The book.
  final String bookId;

  /// Entries in `(accounting_date, hlc, entry_id)` order (02 §9), oldest
  /// first — a journal reads forwards.
  final List<DayBookRow> rows;

  /// Sum of every Dr line in the period, absolute paise.
  final int debitTotalPaise;

  /// Sum of every Cr line in the period, absolute paise.
  final int creditTotalPaise;

  /// First day of the period, or null for the whole history.
  final LocalDate? from;

  /// Last day of the period, or null for *up to the latest entry*.
  final LocalDate? to;

  /// Nothing in the period.
  bool get isEmpty => rows.isEmpty;

  /// The cross-check: every entry balances (02 §1.4), so the two columns must
  /// agree. It is asserted on screen rather than assumed — a day book whose
  /// columns disagree is the first place a reader would see it.
  bool get balances => debitTotalPaise == creditTotalPaise;
}

/// The heading a report carries: the book's name and its financial-year
/// calendar (02 §1.1). A one-shot read, deliberately not a stream — a report
/// header does not change under the reader while they look at it.
final class ReportHeading {
  /// Creates the heading.
  const ReportHeading({required this.bookName, required this.fyStartMonth});

  /// Display name of the book.
  final String bookName;

  /// Month the financial year begins (02 §1.1); 4 when the book predates it.
  final int fyStartMonth;
}

/// Reads [bookId]'s name and FY calendar in one query.
Future<ReportHeading> reportHeading(LocalLedger ledger, String bookId) async {
  final db = ledger.db;
  final row = await (db.select(
    db.booksP,
  )..where((b) => b.id.equals(bookId))).getSingleOrNull();
  return ReportHeading(
    bookName: row?.name ?? '',
    fyStartMonth: row?.fyStartMonth ?? 4,
  );
}

/// Watches the day book of [bookId] between [from] and [to] (both inclusive;
/// null = unbounded).
///
/// Rebuilt whenever the projection changes, like every other ledger stream.
Stream<DayBook> watchDayBook(
  LocalLedger ledger,
  String bookId, {
  LocalDate? from,
  LocalDate? to,
}) {
  final db = ledger.db;
  final lines = db.entryLinesP;
  final entries = db.entriesP;
  final q = db.customSelect(
    'SELECT l.entry_id, l.account_id, l.amount_paise, l.line_index, '
    'e.accounting_date, e.kind, e.status, e.review_state, e.note, '
    'e.channel, e.hlc '
    'FROM entry_lines_p l JOIN entries_p e ON e.id = l.entry_id '
    'WHERE l.book_id = ? '
    "AND e.superseded_by IS NULL AND e.status NOT IN ('pending','rejected') "
    '${from == null ? '' : 'AND l.accounting_date >= ? '}'
    '${to == null ? '' : 'AND l.accounting_date <= ? '}'
    'ORDER BY e.accounting_date, e.hlc, e.id, l.line_index',
    variables: [
      Variable.withString(bookId),
      if (from != null) Variable.withString(from.toIso()),
      if (to != null) Variable.withString(to.toIso()),
    ],
    readsFrom: {lines, entries},
  );
  return q.watch().map((rows) => _assemble(bookId, rows, from: from, to: to));
}

DayBook _assemble(
  String bookId,
  List<QueryRow> rows, {
  LocalDate? from,
  LocalDate? to,
}) {
  // The query returns one row per *line*; a day book lists one row per
  // *entry*, so the lines are folded back together in the order they arrive
  // (which is already `(date, hlc, id, line_index)`).
  final order = <String>[];
  final lines = <String, List<DayBookLine>>{};
  final head = <String, QueryRow>{};
  var debitTotal = 0;
  var creditTotal = 0;

  for (final r in rows) {
    final entryId = r.read<String>('entry_id');
    if (head[entryId] == null) {
      order.add(entryId);
      lines[entryId] = [];
      head[entryId] = r;
    }
    final amount = r.read<int>('amount_paise');
    lines[entryId]!.add(
      DayBookLine(accountId: r.read<String>('account_id'), amountPaise: amount),
    );
    if (amount > 0) {
      debitTotal += amount;
    } else {
      // A zero line adds nothing to either column; a negative one is Cr.
      creditTotal += -amount;
    }
  }

  final out = <DayBookRow>[
    for (final entryId in order)
      DayBookRow(
        entryId: entryId,
        date: LocalDate.parse(head[entryId]!.read<String>('accounting_date')),
        kind: EntryKind.parse(head[entryId]!.read<String>('kind')),
        status: head[entryId]!.read<String>('status'),
        reviewState: head[entryId]!.read<String>('review_state'),
        lines: List.unmodifiable(lines[entryId]!),
        hlc: head[entryId]!.read<int>('hlc'),
        note: head[entryId]!.readNullable<String>('note'),
        channel: head[entryId]!.readNullable<String>('channel'),
      ),
  ];

  return DayBook(
    bookId: bookId,
    rows: List.unmodifiable(out),
    debitTotalPaise: debitTotal,
    creditTotalPaise: creditTotal,
    from: from,
    to: to,
  );
}
