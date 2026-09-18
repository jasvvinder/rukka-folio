// The day book as a [ReportTable] — the one place its layout is decided, now
// that two reports share the three writers (ADR 2026-09-12e §2 🔒).
//
// The layout is unchanged from the one the writers each used to carry: the
// classical journal, one row per posting **line**, the date and the note on
// the entry's first line only, and a cross-check total at the foot (13 §5,
// flow F3). Moving it here is what stopped the three formats being three
// chances to disagree.
//
// A PROFESSIONAL surface (02 §10 🔒, CLAUDE.md rule 9): Dr and Cr, never
// *Money in / Money out*. The columns are chosen from the engine's sign, never
// the other way round (02 §1.3).
import 'package:core_ledger/core_ledger.dart';

import '../day_book.dart';
import 'report_export.dart';
import 'report_table.dart';

/// Column widths on paper, in points — the day book's own grid.
const ReportColumnWidth _dateWidth = ReportFixedWidth(58);
const ReportColumnWidth _figureWidth = ReportFixedWidth(74);

/// Builds the day book's table.
///
/// [accountName] resolves an account id to its display name — the caller holds
/// the [Chart], this file does not reach for one.
ReportTable dayBookTable(
  DayBook book, {
  required String Function(String accountId) accountName,
  required ReportLabels labels,
  required String bookName,
  required String period,
  required String Function(LocalDate date) formatDate,
}) {
  final rows = <ReportRow>[];
  for (final row in book.rows) {
    // The date and the note sit on the entry's first line; every further line
    // of the same entry continues under it.
    final lines = [...row.debits, ...row.credits];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final first = i == 0;
      rows.add(
        ReportRow(
          [
            first ? ReportDateCell(row.date, formatDate(row.date)) : null,
            ReportTextCell(accountName(line.accountId)),
            line.isDebit ? ReportMoneyCell(line.figurePaise) : null,
            line.isCredit ? ReportMoneyCell(line.figurePaise) : null,
            first && row.note != null
                ? ReportTextCell(row.note!, muted: true)
                : null,
          ],
          kind: i == lines.length - 1
              ? ReportRowKind.groupEnd
              : ReportRowKind.body,
        ),
      );
    }
  }

  // The cross-check footer (13 §5, flow F3): the two columns must agree,
  // because every entry balances (02 §1.4).
  rows.add(
    ReportRow([
      null,
      ReportTextCell(labels.totalLabel),
      ReportMoneyCell(book.debitTotalPaise),
      ReportMoneyCell(book.creditTotalPaise),
      null,
    ], kind: ReportRowKind.total),
  );
  return ReportTable(
    name: labels.reportName,
    meta: [
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
      ReportColumn(labels.columnNote, width: const ReportFlexWidth(2)),
    ],
    rows: rows,
  );
}
