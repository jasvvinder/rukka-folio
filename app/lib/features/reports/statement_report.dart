// The A/C statement as an exportable report (ADR 2026-09-12e §2 🔒: the trio
// *View · Download/Share · Export (PDF/CSV/XLSX)* is binding on S4, not only
// on S8.2 — owner-confirmed 13 Sep). It sits here, beside `day_book.dart`,
// because a report belongs to the reports feature whichever screen opens it;
// S4 supplies the account and the year and takes the file.
//
// The rows are **not** re-queried: they are the ones S4 already has from
// `LocalLedger.watchStatement(accountId, from:, to:)`, which bounds the
// statement by the FY switcher and sums everything before `from` into
// [Statement.openingPaise] (ADR 2026-09-09 §4 🔒). So the paper and the screen
// are the same statement by construction, not by two queries agreeing.
//
// A PROFESSIONAL surface (02 §10 🔒, CLAUDE.md rule 9): the columns are **Dr**,
// **Cr** and **Balance**, never *Money in / Money out*. The engine's sign is
// what picks the column and tags the balance (+ = Dr, − = Cr, 02 §1.3); the
// display language never bends the posting.
//
// **The exported statement closes like a paper khata** (07 §14 🔒 *b/d–c/d rows
// on ledgers*, 02 §8.1 *Presentation*). It opens with *Opening balance b/f* —
// the certified carry-forward the engine hands over in [Statement.openingPaise],
// never recomputed here — and closes with the classical block: *Closing balance
// c/d* as the balancing figure in the column **opposite** the balance's own
// side, a *Total* line where the Dr and Cr columns are equal by construction,
// and *Opening balance b/d* restating the balance on its own side for the next
// period. The totals square exactly when closing = opening + Dr − Cr, which is
// the engine's own arithmetic, so the line is a real cross-check (13 §5, flow
// F3) and not decoration. All four are ordinary rows, so they reach all three
// formats identically.
//
// ⚠️ SPEC: 02 §8.1 *Presentation* says each FY view "ends with *Closing balance
// c/f*" and, in the same sentence, that "printed/exported ledgers carry the b/d
// and c/d rows so they read exactly like the traditional book". A traditional
// book closes an account **once**, so on paper c/f and c/d are one row under
// two names — but the two readings differ and this file takes the conservative
// one: the export carries **both**, c/f then c/d, adding the block 07 §14 🔒
// asks for without dropping a row 02 §8.1 names and `F1-07-162` already asserts
// (dropping it would supersede a green test, which needs an ADR, not a lane).
// Owner call: if the export should read as one closing row, delete the c/f row
// here and amend `F1-07-162`; nothing else moves.
//
// Under the table sits the **amount in words** (07 §14 🔒): the closing
// balance's magnitude spelled out on the Indian scale by `amount_words.dart`,
// in the reader's own language. Its side is not in the words — that is the
// c/d row's column (02 §10 🔒, design-system §1 rule 0b 🔒).
//
// Money is integer paise the whole way (CLAUDE.md rule 1): the table carries
// paise and each writer renders them.
import 'package:core_ledger/core_ledger.dart' hide StatementRow;

import '../../l10n/gen/app_localizations.dart';
import '../../shared/ledger/local_ledger.dart';
import 'export/amount_words.dart';
import 'export/report_table.dart';

/// The words an exported A/C statement carries, pulled off the locale's
/// strings once so every format says the same thing.
final class StatementReportLabels {
  /// Creates the label set.
  const StatementReportLabels({
    required this.reportName,
    required this.accountLabel,
    required this.bookLabel,
    required this.periodLabel,
    required this.columnDate,
    required this.columnParticulars,
    required this.columnDebit,
    required this.columnCredit,
    required this.columnBalance,
    required this.columnNote,
    required this.opening,
    required this.closing,
    required this.closingCarriedDown,
    required this.openingBroughtDown,
    required this.total,
    required this.closingInWords,
    required this.amountWords,
  });

  /// Reads them from [strings].
  factory StatementReportLabels.of(AppLocalizations strings) =>
      StatementReportLabels(
        reportName: strings.reportsStatementReportTitle,
        accountLabel: strings.reportsStatementAccountLabel,
        bookLabel: strings.reportsViewerBookLabel,
        periodLabel: strings.reportsViewerPeriodLabel,
        columnDate: strings.reportsViewerColumnDate,
        columnParticulars: strings.reportsViewerColumnParticulars,
        // Professional vocabulary (02 §10 🔒) — the same two words the screen
        // heads its columns with.
        columnDebit: strings.moneySideDr,
        columnCredit: strings.moneySideCr,
        columnBalance: strings.ledgerStatementColumnBalance,
        columnNote: strings.reportsViewerColumnNote,
        opening: strings.ledgerStatementOpening,
        closing: strings.ledgerStatementClosing,
        closingCarriedDown: strings.reportsStatementClosingCd,
        openingBroughtDown: strings.reportsStatementOpeningBd,
        total: strings.reportsViewerTotal,
        closingInWords: strings.reportsStatementClosingWordsLabel,
        amountWords: AmountWords.of(strings),
      );

  /// *A/C statement* — the report's own name (07 §14 🔒 row 3).
  final String reportName;

  /// *Account* — heading for the account line of the head.
  final String accountLabel;

  /// *Book*.
  final String bookLabel;

  /// *Period* — the FY or range in force.
  final String periodLabel;

  /// *Date* column.
  final String columnDate;

  /// *Particulars* column — the counter account(s) of each row.
  final String columnParticulars;

  /// *Dr* column.
  final String columnDebit;

  /// *Cr* column.
  final String columnCredit;

  /// *Balance* column — the running balance, signed as the engine signs it.
  final String columnBalance;

  /// *Note* column.
  final String columnNote;

  /// *Opening balance b/f* (02 §8.1) — the period's certified carry-forward.
  final String opening;

  /// *Closing balance c/f* — the row 02 §8.1 ends an FY view with.
  final String closing;

  /// *Closing balance c/d* — the balancing row that closes the account on
  /// paper (07 §14 🔒), under the c/f line (see the ⚠️ SPEC above).
  final String closingCarriedDown;

  /// *Opening balance b/d* — the same figure brought down into the next
  /// period, on its own side (07 §14 🔒).
  final String openingBroughtDown;

  /// *Total* — the cross-check line between c/d and b/d (13 §5, flow F3).
  final String total;

  /// *Closing balance in words* — the label of the amount-in-words line.
  final String closingInWords;

  /// The locale's number words, for that line (07 §14 🔒).
  final AmountWords amountWords;
}

/// Column widths on paper, in points — the statement's own grid.
const ReportColumnWidth _dateWidth = ReportFixedWidth(58);
const ReportColumnWidth _figureWidth = ReportFixedWidth(64);
const ReportColumnWidth _balanceWidth = ReportFixedWidth(78);

/// Builds the statement's [ReportTable].
///
/// [accountName] is the account this is the statement of — it heads the
/// report and never appears in the particulars column, exactly as on screen.
/// [counterNames] resolves the counter account ids of a row; the caller holds
/// the [Chart]. [openingDate] is the first day of the period and [closingDate]
/// the day the c/f falls on — the period's last day, or today while the period
/// is still open (07 §6 🔒, owner rule), decided by the caller because this
/// file reads no clock.
ReportTable statementTable(
  Statement statement, {
  required String accountName,
  required String bookName,
  required String period,
  required StatementReportLabels labels,
  required List<String> Function(StatementRow row) counterNames,
  required String Function(LocalDate date) formatDate,
  required LocalDate openingDate,
  required LocalDate closingDate,
}) {
  /// *Dr* or *Cr* for a balance, or nothing at all when it is zero — a zero
  /// balance has no side (design-system §1 rule 0b 🔒).
  String? side(int paise) => paise == 0
      ? null
      : paise > 0
      ? labels.columnDebit
      : labels.columnCredit;

  final opening = statement.openingPaise;
  final closing = statement.closingPaise;

  // The two column totals. Each is the sum of what the reader can see in that
  // column — the b/f figure on its own side, every posting line, and the c/d
  // balancing figure — so the Total row is a cross-check of the printed page
  // and not a second opinion from the engine (13 §5, flow F3). They are equal
  // exactly when closing = opening + Dr − Cr, which is the engine's own
  // arithmetic; nothing here recomputes a balance.
  var totalDebitPaise = opening > 0 ? opening : 0;
  var totalCreditPaise = opening < 0 ? -opening : 0;
  for (final row in statement) {
    totalDebitPaise += row.debitPaise;
    totalCreditPaise += row.creditPaise;
  }
  // The balancing figure closes the lighter side (07 §14 🔒): a Dr balance is
  // carried down on the Cr side, and the other way about.
  if (closing > 0) {
    totalCreditPaise += closing;
  } else if (closing < 0) {
    totalDebitPaise += -closing;
  }

  final rows = <ReportRow>[
    // b/f — the first row of every view (02 §8.1 *Presentation*). The figure
    // also sits in its own Dr or Cr column, because a page whose columns do
    // not add up is not the traditional book 07 §14 🔒 asks for.
    ReportRow([
      ReportDateCell(openingDate, formatDate(openingDate)),
      ReportTextCell(labels.opening),
      opening > 0 ? ReportMoneyCell(opening) : null,
      opening < 0 ? ReportMoneyCell(-opening) : null,
      ReportMoneyCell(opening, signed: true, side: side(opening)),
      null,
    ], kind: ReportRowKind.boundary),
    for (final row in statement)
      ReportRow([
        ReportDateCell(row.date, formatDate(row.date)),
        ReportTextCell(counterNames(row).join(', ')),
        // Blank, not zero: an empty Dr box on a credit line is how a paper
        // ledger reads (07 §6).
        row.debitPaise == 0 ? null : ReportMoneyCell(row.debitPaise),
        row.creditPaise == 0 ? null : ReportMoneyCell(row.creditPaise),
        ReportMoneyCell(
          row.runningBalancePaise,
          signed: true,
          side: side(row.runningBalancePaise),
        ),
        row.note == null ? null : ReportTextCell(row.note!, muted: true),
      ], kind: ReportRowKind.groupEnd),
    // c/f — where the FY view ends (02 §8.1 *Presentation*): the balance the
    // period closes at, signed as the engine signs it.
    ReportRow([
      ReportDateCell(closingDate, formatDate(closingDate)),
      ReportTextCell(labels.closing),
      null,
      null,
      ReportMoneyCell(closing, signed: true, side: side(closing)),
      null,
    ], kind: ReportRowKind.boundary),
    // c/d — the balancing row that closes the account (07 §14 🔒). No running
    // balance on it: after the account is squared there is nothing left to
    // run, which is exactly what the blank cell says on paper.
    ReportRow([
      ReportDateCell(closingDate, formatDate(closingDate)),
      ReportTextCell(labels.closingCarriedDown),
      closing < 0 ? ReportMoneyCell(-closing) : null,
      closing > 0 ? ReportMoneyCell(closing) : null,
      null,
      null,
    ], kind: ReportRowKind.boundary),
    // The cross-check: the two columns of the page, which are equal.
    ReportRow([
      null,
      ReportTextCell(labels.total),
      ReportMoneyCell(totalDebitPaise),
      ReportMoneyCell(totalCreditPaise),
      null,
      null,
    ], kind: ReportRowKind.total),
    // b/d — the same figure brought down into the next period, on its own
    // side, dated the day the next period opens.
    ReportRow([
      ReportDateCell(
        closingDate.addDays(1),
        formatDate(closingDate.addDays(1)),
      ),
      ReportTextCell(labels.openingBroughtDown),
      closing > 0 ? ReportMoneyCell(closing) : null,
      closing < 0 ? ReportMoneyCell(-closing) : null,
      ReportMoneyCell(closing, signed: true, side: side(closing)),
      null,
    ], kind: ReportRowKind.boundary),
  ];

  return ReportTable(
    name: labels.reportName,
    // Metadata only — a name and a period, never a figure (CLAUDE.md rule 4).
    meta: [
      ReportMetaLine(labels.accountLabel, accountName),
      ReportMetaLine(labels.bookLabel, bookName),
      ReportMetaLine(labels.periodLabel, period),
    ],
    columns: [
      ReportColumn(labels.columnDate, width: _dateWidth),
      ReportColumn(labels.columnParticulars, width: const ReportFlexWidth(3)),
      ReportColumn(
        labels.columnDebit,
        align: ReportAlign.end,
        width: _figureWidth,
      ),
      ReportColumn(
        labels.columnCredit,
        align: ReportAlign.end,
        width: _figureWidth,
      ),
      ReportColumn(
        labels.columnBalance,
        align: ReportAlign.end,
        width: _balanceWidth,
      ),
      ReportColumn(labels.columnNote, width: const ReportFlexWidth(2)),
    ],
    rows: rows,
    // The closing balance in words (07 §14 🔒). A magnitude: the side is on
    // the c/d row, so the words never carry a sign (02 §10 🔒).
    amountInWords: ReportMetaLine(
      labels.closingInWords,
      labels.amountWords(closing.abs()),
    ),
  );
}
