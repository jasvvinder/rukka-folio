// The shape every exported report has in common — the abstraction the second
// report forced (ADR 2026-09-12e §2 🔒: the trio *View · Download/Share ·
// Export (PDF/CSV/XLSX)* is binding on S4 as well as S8.2, so the writers must
// serve two reports, not one).
//
// A [ReportTable] is **already localised**: every string in it is the word the
// reader sees, chosen by the surface that built it. The writers therefore need
// no [ReportLabels] and no vocabulary of their own — which is what keeps the
// professional wording of 02 §10 🔒 a decision of the report, made once, and
// not a thing three file formats could each get differently wrong.
//
// Money never leaves integer paise (CLAUDE.md rule 1): a [ReportMoneyCell]
// carries paise, and each writer renders them its own way — `paiseToDecimal`
// for the machine-readable formats, the app's `formatPaise` for paper. No
// double is constructed anywhere on the path.
//
// Generalised **only as far as the statement needed** (ADR 2026-09-12e §2):
// column widths, alignment, a running-balance column, the boundary and total
// rows a ledger closes with (02 §8.1 *Presentation*, 07 §14 🔒 b/d–c/d) and the
// amount-in-words line under them (07 §14 🔒). Anything the day book and the
// statement do not both need is still the report's own business.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/foundation.dart';

/// Which edge a column's cells sit against. Figures go [ReportAlign.end],
/// words [ReportAlign.start] — the paper-ledger habit, and the only way a
/// column of amounts reads down the page.
enum ReportAlign {
  /// Left in an LTR document.
  start,

  /// Right in an LTR document.
  end,
}

/// How wide a column is on paper. Neutral of `package:pdf` on purpose: the
/// CSV and XLSX writers must not drag a PDF dependency behind them.
@immutable
sealed class ReportColumnWidth {
  const ReportColumnWidth();
}

/// A column of exactly [points] PDF points.
@immutable
final class ReportFixedWidth extends ReportColumnWidth {
  /// Creates the width.
  const ReportFixedWidth(this.points);

  /// Width in points.
  final double points;
}

/// A column that takes [factor] shares of what the fixed columns leave.
@immutable
final class ReportFlexWidth extends ReportColumnWidth {
  /// Creates the width.
  const ReportFlexWidth(this.factor);

  /// Relative share.
  final double factor;
}

/// One column: its heading (already localised) and how it is drawn.
@immutable
final class ReportColumn {
  /// Creates the column.
  const ReportColumn(
    this.title, {
    this.align = ReportAlign.start,
    this.width = const ReportFlexWidth(1),
  });

  /// The heading as the reader sees it.
  final String title;

  /// Which edge the cells sit against.
  final ReportAlign align;

  /// Width on paper.
  final ReportColumnWidth width;
}

/// One cell. A **null** cell is blank — which is not the same as the empty
/// string: a spreadsheet distinguishes a cell holding nothing from a cell
/// holding `""`, and a paper ledger's empty Dr box is the classical way to
/// read a credit line (07 §6).
@immutable
sealed class ReportCell {
  const ReportCell();
}

/// Text.
@immutable
final class ReportTextCell extends ReportCell {
  /// Creates the cell.
  const ReportTextCell(this.text, {this.muted = false});

  /// The words, already localised.
  final String text;

  /// Drawn in the muted ink on paper (notes). Ignored by the machine formats,
  /// where emphasis is not data.
  final bool muted;
}

/// A money figure in **integer paise** (CLAUDE.md rule 1).
///
/// [paise] is the engine's signed value when [signed] is true — the running
/// balance, where + = Dr and − = Cr (02 §1.3) — and an absolute column figure
/// otherwise. The machine formats write the number so the column sums; paper
/// prints it through the app's own money formatter and, for a signed cell,
/// tags the side in words ([drWord] / [crWord]) rather than by a sign, because
/// a statement is a professional surface (02 §10 🔒).
@immutable
final class ReportMoneyCell extends ReportCell {
  /// Creates the cell.
  const ReportMoneyCell(this.paise, {this.signed = false, this.side});

  /// Integer paise.
  final int paise;

  /// True for a balance: keep the sign as data, tag the side on paper.
  final bool signed;

  /// The *Dr* / *Cr* word for this figure on paper — supplied by the report,
  /// null when the figure carries no side (a zero balance).
  final String? side;
}

/// A calendar date. [text] is the formatted form the paper and CSV use;
/// [date] is what the spreadsheet gets, as a real date it can sort.
@immutable
final class ReportDateCell extends ReportCell {
  /// Creates the cell.
  const ReportDateCell(this.date, this.text);

  /// The day.
  final LocalDate date;

  /// Its formatted form (07 §1 rule 5 — formatted by the caller, in the
  /// reader's locale).
  final String text;
}

/// What a row is for. The writers give each kind its emphasis; nothing else
/// about a row's meaning reaches them.
enum ReportRowKind {
  /// An ordinary line of the report.
  body,

  /// The last line of a group — one entry's final posting line. Drawn with a
  /// hairline under it on paper; no effect elsewhere.
  groupEnd,

  /// *Opening balance b/f* or *Closing balance c/f* (02 §8.1 *Presentation*)
  /// — emphasised, and boxed off from the body.
  boundary,

  /// The cross-check total at the foot (13 §5, flow F3).
  total,
}

/// One row of the body.
@immutable
final class ReportRow {
  /// Creates the row.
  const ReportRow(this.cells, {this.kind = ReportRowKind.body});

  /// Its cells, one per column; null is blank, and a short row is blank to
  /// the right.
  final List<ReportCell?> cells;

  /// What the row is for.
  final ReportRowKind kind;
}

/// A whole report, ready for any of the three writers.
@immutable
final class ReportTable {
  /// Creates the table.
  const ReportTable({
    required this.name,
    required this.meta,
    required this.columns,
    required this.rows,
    this.amountInWords,
  });

  /// The report's own name — the document title, the sheet tab and the first
  /// line of the head.
  final String name;

  /// The head: `(label, value)` pairs, e.g. *Account: Ramesh*, *Book: Me*,
  /// *Period: FY 2026-27*. Metadata only — never a figure, because the head
  /// travels in the file name and the document title (CLAUDE.md rule 4).
  final List<ReportMetaLine> meta;

  /// The columns, left to right.
  final List<ReportColumn> columns;

  /// The body.
  final List<ReportRow> rows;

  /// The amount-in-words line under the table (07 §14 🔒), or null where the
  /// report has no single figure to say in words — a day book has none, a
  /// ledger's closing balance is one.
  ///
  /// A `(label, value)` pair rather than a bare sentence so the three writers
  /// need no wording of their own, and **not** a [meta] line: the head is
  /// metadata and carries no figure (see [meta]), while this is the figure
  /// itself and belongs at the foot, where a paper ledger puts it.
  final ReportMetaLine? amountInWords;
}

/// One `(label, value)` line of a report's head.
@immutable
final class ReportMetaLine {
  /// Creates the line.
  const ReportMetaLine(this.label, this.value);

  /// *Book*, *Period*, *Account* — already localised.
  final String label;

  /// Its value.
  final String value;
}
