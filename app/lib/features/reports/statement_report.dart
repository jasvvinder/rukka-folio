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
// Each view opens with *Opening balance b/f* and closes with *Closing balance
// c/f* (02 §8.1 *Presentation*, 07 §14 🔒 — b/d–c/d rows on ledgers). Both are
// real rows of the table, so they reach all three formats identically.
// Amount-in-words is **M12** and is deliberately not built (07 §14).
//
// Money is integer paise the whole way (CLAUDE.md rule 1): the table carries
// paise and each writer renders them.
import 'package:core_ledger/core_ledger.dart' hide StatementRow;

import '../../l10n/gen/app_localizations.dart';
import '../../shared/ledger/local_ledger.dart';
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

  /// *Opening balance b/f* (02 §8.1).
  final String opening;

  /// *Closing balance c/f* (02 §8.1).
  final String closing;
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

  final rows = <ReportRow>[
    // b/f — the first row of every view (02 §8.1 *Presentation*).
    ReportRow([
      ReportDateCell(openingDate, formatDate(openingDate)),
      ReportTextCell(labels.opening),
      null,
      null,
      ReportMoneyCell(
        statement.openingPaise,
        signed: true,
        side: side(statement.openingPaise),
      ),
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
    // c/f — the last row of every view.
    ReportRow([
      ReportDateCell(closingDate, formatDate(closingDate)),
      ReportTextCell(labels.closing),
      null,
      null,
      ReportMoneyCell(
        statement.closingPaise,
        signed: true,
        side: side(statement.closingPaise),
      ),
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
  );
}
