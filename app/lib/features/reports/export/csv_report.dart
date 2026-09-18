// CSV export of a report (ADR 2026-09-12 §1 🔒 — CSV joined PDF and XLSX on
// the report export surface). Pure Dart, no package: a CSV is a handful of
// escaping rules, and a dependency for it would be a dependency to audit.
// Generated **on device**, like every format (07 §14 🔒).
//
// This is a PROFESSIONAL surface (02 §10 🔒, CLAUDE.md rule 9): the columns
// are **Dr** and **Cr**, never *Money in / Money out*. The day book is laid
// out the classical way — one CSV row per posting *line*, the date carried on
// the entry's first line only, the Dr and Cr figures in their own columns, and
// a totals line at the foot that is the cross-check (13 §5, flow F3).
//
// Money never touches a float (CLAUDE.md rule 1): integer paise are split into
// rupees and paise by integer division and printed as text.
//
// ⚠️ SPEC: ADR 2026-09-12 §3 says 07 §14's content rules — b/d–c/d rows,
// amount-in-words, Indian digit grouping — bind all three formats, but the
// same ADR's Open note puts report *content* rules at M12 with the F3 byte
// goldens (`F3-07-1`, `F3-07-2`), not at M5. So the figures here are written
// machine-readable (`1234.56`, two decimals, no ₹, no grouping): a grouped
// `₹12,34,567.00` inside a CSV cell is a string to a spreadsheet, not a
// number, and which of the two a golden freezes is the M12 lane's call, not
// this one's. The PDF writer beside this one prints the same figures through
// the app's own [formatPaise] (₹, Indian grouping) precisely because paper is
// read by a person and a CSV cell by a spreadsheet. Nothing else about the
// layout anticipates that decision.
//
// The column words live in `report_export.dart` as [ReportLabels], shared with
// the PDF writer so the two formats of one report cannot disagree.
import 'dart:convert';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/foundation.dart';

import '../day_book.dart';
import 'day_book_table.dart';
import 'report_export.dart';
import 'report_table.dart';

/// RFC 4180 line ending. Fixed, never the platform's — an export is a file
/// that travels, and a golden compares bytes (ADR 2026-09-12 §3).
const String csvLineEnding = '\r\n';

/// `1234.56` from 123456 paise — integer arithmetic only, never a float
/// (CLAUDE.md rule 1). Negative paise keep a leading `-` (ASCII hyphen: this
/// is a machine-readable cell, not the U+2212 of a screen).
String paiseToDecimal(int paise) {
  final negative = paise < 0;
  final magnitude = paise.abs();
  final rupees = magnitude ~/ 100;
  final rest = (magnitude % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$rupees.$rest';
}

/// One CSV field, escaped per RFC 4180: a field containing a comma, a quote,
/// CR or LF is wrapped in quotes and its own quotes are doubled.
String csvField(String value) {
  final needsQuotes =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// One CSV record.
String csvRow(List<String> fields) => fields.map(csvField).join(',');

/// Any [ReportTable] as CSV text — the one CSV layout, shared by the day book
/// and the A/C statement (ADR 2026-09-12e §2 🔒).
///
/// The head is a short block of metadata so the file says what it is once it
/// has left the app — the report's name and its `(label, value)` lines, no
/// figures — then a blank record, then the column headings and the body.
String reportTableCsv(ReportTable table) {
  final buffer = StringBuffer();
  void write(List<String> fields) {
    buffer
      ..write(csvRow(fields))
      ..write(csvLineEnding);
  }

  write([table.name]);
  for (final line in table.meta) {
    write([line.label, line.value]);
  }
  write(const ['']);
  write([for (final column in table.columns) column.title]);

  for (final row in table.rows) {
    write([
      for (var i = 0; i < table.columns.length; i++)
        csvCellText(i < row.cells.length ? row.cells[i] : null),
    ]);
  }
  return buffer.toString();
}

/// One cell as CSV text. A blank cell is the empty field; money is the
/// machine-readable decimal of [paiseToDecimal] — never grouped, never ₹, and
/// a balance keeps its sign, which is the engine's own (+ = Dr, 02 §1.3).
String csvCellText(ReportCell? cell) => switch (cell) {
  null => '',
  ReportTextCell(:final text) => text,
  ReportMoneyCell(:final paise) => paiseToDecimal(paise),
  ReportDateCell(:final text) => text,
};

/// Any [ReportTable] as a [ReportFile] ready for a [ReportSink].
///
/// UTF-8 with a BOM (ADR 2026-09-12e §3 🔒): the names in this file are
/// Gurmukhi and Devanagari as often as Latin, and without the BOM a
/// spreadsheet on Windows renders them as mojibake — which would make the
/// export useless to the person it is for.
ReportFile reportTableCsvFile(ReportTable table, {required String fileName}) =>
    ReportFile(
      name: fileName,
      format: ReportFormat.csv,
      bytes: Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(reportTableCsv(table)),
      ]),
    );

/// The day book as CSV text.
///
/// [accountName] resolves an account id to its display name — the caller holds
/// the [Chart], this file does not reach for one. [period] is the financial
/// year as the reader sees it, [bookName] the book.
String dayBookCsv(
  DayBook book, {
  required String Function(String accountId) accountName,
  required ReportLabels labels,
  required String bookName,
  required String period,
  required String Function(LocalDate date) formatDate,
}) => reportTableCsv(
  dayBookTable(
    book,
    accountName: accountName,
    labels: labels,
    bookName: bookName,
    period: period,
    formatDate: formatDate,
  ),
);

/// The day book as a [ReportFile] ready for a [ReportSink].
ReportFile dayBookCsvFile(
  DayBook book, {
  required String Function(String accountId) accountName,
  required ReportLabels labels,
  required String bookName,
  required String period,
  required String Function(LocalDate date) formatDate,
  required String fileName,
}) => reportTableCsvFile(
  dayBookTable(
    book,
    accountName: accountName,
    labels: labels,
    bookName: bookName,
    period: period,
    formatDate: formatDate,
  ),
  fileName: fileName,
);
