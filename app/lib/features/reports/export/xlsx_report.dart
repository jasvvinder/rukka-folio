// XLSX export of a report — written **in-house** over `archive` (zip) and
// `xml` (markup), no XLSX package (ADR 2026-09-12e §1 🔒). The free writers
// need `archive` 3.x and sodium needs 4.x, and an override cannot bridge a
// deleted method; the one compatible package is proprietary. An `.xlsx` is a
// zip of XML parts, so this is serialization, not the typesetting engine that
// made hand-rolling PDF the wrong call. Generated **on device**, like every
// format (07 §14 🔒).
//
// This is a PROFESSIONAL surface (02 §10 🔒, CLAUDE.md rule 9): the columns
// are **Dr** and **Cr**, never *Money in / Money out*. The layout is the same
// classical day book the CSV writer lays out — one sheet row per posting
// *line*, the date and note on the entry's first line only, and a cross-check
// total at the foot (13 §5, flow F3) — so the two machine-readable formats of
// one report can never disagree.
//
// **What makes this file worth having over the CSV**, and therefore what must
// not regress:
//
//   • **Money lands as a number, not text.** A ledger that arrives as strings
//     cannot be summed, which is the whole reason an accountant asked for
//     XLSX. The cell is numeric with a money number-format in `styles.xml`.
//     Money is still integer paise end to end (CLAUDE.md rule 1): the decimal
//     that goes into `<v>` is built by [paiseToDecimal]'s integer arithmetic
//     — the shared one the CSV writer uses — and no double is ever
//     constructed. XLSX stores a number as its decimal *text*, so writing the
//     text is writing the number.
//   • **Dates land as real dates**, an integer serial with a date
//     number-format, for the same reason: a date column of strings cannot be
//     sorted or filtered.
//   • **Internal consistency.** Part names, content types and relationship
//     ids have to agree exactly or Excel "repairs" the file — which is silent
//     data loss, not a warning. Every one of them is named once here, as a
//     constant, and used from that constant in each part.
//   • **UTF-8 throughout.** Gurmukhi and Devanagari account names survive
//     because each part declares `encoding="UTF-8"` in its XML prolog — the
//     BOM question the CSV has (ADR 2026-09-12e §3) does not arise here.
//
// Inline strings (`t="inlineStr"`) by ADR 2026-09-12e §1 🔒: a shared-string
// table is a second index to keep consistent with the sheet, and a day book
// has no repetition worth the risk.
//
// ⚠️ SPEC: 07 §14's content rules — b/d–c/d rows, amount-in-words, Indian
// digit grouping — are M12 with the F3 byte-goldens (ADR 2026-09-12 §3 and
// its Open note), not M5. So the money format code here is the neutral
// `#,##0.00` rather than the Indian `#,##,##0.00`, and which of the two a
// golden freezes is the M12 lane's call. It changes only the *display* of a
// cell, never its value: the number in the file is the same either way, which
// is why this is a safe conservative reading rather than a guess. The same
// note stands over `csv_report.dart`.
//
// Not this milestone: the Free-tenant watermark (`F3-07-3 @M12`) and the
// byte-goldens (`F3-07-1/2 @M12`) that will freeze these bytes.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../day_book.dart';
import 'csv_report.dart' show paiseToDecimal;
import 'report_export.dart';

// ---------------------------------------------------------------------------
// Package shape. Every name below appears in more than one part; naming each
// once is what keeps the package internally consistent (see the header).
// ---------------------------------------------------------------------------

/// The workbook part.
const String xlsxWorkbookPart = 'xl/workbook.xml';

/// The one worksheet part. Only the day book exists at M5 (ADR 2026-09-12e
/// §2), so the workbook has exactly one sheet.
const String xlsxSheetPart = 'xl/worksheets/sheet1.xml';

/// The styles part — money and date number-formats live here.
const String xlsxStylesPart = 'xl/styles.xml';

const String _contentTypesPart = '[Content_Types].xml';
const String _packageRelsPart = '_rels/.rels';
const String _workbookRelsPart = 'xl/_rels/workbook.xml.rels';

/// Relationship id of the worksheet inside the workbook's `.rels` — quoted by
/// `workbook.xml` as `r:id`, so it is a constant rather than a literal typed
/// twice.
const String xlsxSheetRelId = 'rId1';
const String _stylesRelId = 'rId2';
const String _workbookRelId = 'rId1';

const String _nsContentTypes =
    'http://schemas.openxmlformats.org/package/2006/content-types';
const String _nsPackageRels =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _nsSpreadsheet =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _nsDocRels =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

const String _relTypeOfficeDocument = '$_nsDocRels/officeDocument';
const String _relTypeWorksheet = '$_nsDocRels/worksheet';
const String _relTypeStyles = '$_nsDocRels/styles';

const String _typeWorkbook =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';
const String _typeWorksheet =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml';
const String _typeStyles =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml';

/// Fixed modification time stamped on every zip entry.
///
/// `archive` otherwise stamps `DateTime.now()`, which would make two exports
/// of the same report differ byte for byte — and the F3 byte-goldens
/// (`F3-07-1/2 @M12`) compare bytes. 1980-01-01 is the zero of the DOS date
/// field a zip carries, so it is the one timestamp that encodes exactly.
final DateTime xlsxZipTimestamp = DateTime.utc(1980, 1, 1);

// ---------------------------------------------------------------------------
// Style slots of `styles.xml`, by index into its `cellXfs` list. A cell's
// `s="n"` is that index; getting it wrong silently formats a figure as a date.
// ---------------------------------------------------------------------------

/// Plain text, general format.
const int xlsxStyleDefault = 0;

/// Bold text — the report name and the column headings.
const int xlsxStyleBold = 1;

/// A money figure: numeric, two decimals.
const int xlsxStyleMoney = 2;

/// A calendar date: numeric serial, shown as a date.
const int xlsxStyleDate = 3;

/// A money figure on the cross-check line: numeric, two decimals, bold.
const int xlsxStyleMoneyTotal = 4;

/// Number-format id of the money format, above Excel's built-in range.
const int _numFmtMoney = 164;

/// Number-format id of the date format.
const int _numFmtDate = 165;

/// Days between the Unix epoch and Excel's day zero (1899-12-30) — the offset
/// that turns [LocalDate.toEpochDays] into an Excel serial date.
const int xlsxEpochOffsetDays = 25569;

// ---------------------------------------------------------------------------
// Cells
// ---------------------------------------------------------------------------

/// One cell of the sheet. A row is a list of these with `null` for a gap —
/// an empty cell is written by not writing it, which is what a spreadsheet
/// means by blank (as against a cell holding the empty string).
@immutable
sealed class XlsxCell {
  const XlsxCell();

  /// Index into `styles.xml`'s `cellXfs`.
  int get style;
}

/// Text, written inline (`t="inlineStr"` — ADR 2026-09-12e §1 🔒).
@immutable
final class XlsxText extends XlsxCell {
  /// Creates a text cell.
  const XlsxText(this.value, {this.style = xlsxStyleDefault});

  /// The text. Escaped by the XML writer, so `&`, `<` and quotes in an
  /// account name are safe.
  final String value;

  @override
  final int style;
}

/// A money figure in **integer paise** (CLAUDE.md rule 1), written as a
/// *number* so a spreadsheet can sum the column.
@immutable
final class XlsxMoney extends XlsxCell {
  /// Creates a money cell.
  const XlsxMoney(this.paise, {this.style = xlsxStyleMoney});

  /// Integer paise. Never divided in Dart — [paiseToDecimal] renders the
  /// decimal with integer arithmetic and the spreadsheet parses it.
  final int paise;

  @override
  final int style;
}

/// A calendar date, written as a real date (numeric serial + date format) so
/// the column sorts and filters.
@immutable
final class XlsxDate extends XlsxCell {
  /// Creates a date cell.
  const XlsxDate(this.date, {this.style = xlsxStyleDate});

  /// The day.
  final LocalDate date;

  @override
  final int style;
}

/// Excel's serial day number for [date] — integer arithmetic only.
///
/// Excel's day zero is 1899-12-30, and its 1900 date system famously counts a
/// 29 February 1900 that never existed; that phantom only affects serials at
/// or below 60 (dates before 1 March 1900), which no accounting date reaches.
int xlsxSerialDate(LocalDate date) => date.toEpochDays() + xlsxEpochOffsetDays;

/// `A`, `B`, … `Z`, `AA` … for a **1-based** column index.
String xlsxColumnName(int index) {
  assert(index >= 1, 'columns are 1-based');
  final letters = <int>[];
  var n = index;
  while (n > 0) {
    final remainder = (n - 1) % 26;
    letters.insert(0, 0x41 + remainder);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(letters);
}

/// A sheet-tab name Excel will accept: at most 31 characters, none of
/// `: \ / ? * [ ]`, not blank, no leading or trailing apostrophe.
///
/// The proposed name is the localised report name, so it may be Gurmukhi or
/// Devanagari — the length limit counts characters, not bytes, which is why
/// it is measured in runes.
String xlsxSheetName(String proposed) {
  var name = proposed.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
  final runes = name.runes.toList();
  if (runes.length > 31) name = String.fromCharCodes(runes.take(31));
  name = name.replaceAll(RegExp("^'+|'+\$"), '').trim();
  return name.isEmpty ? 'Sheet1' : name;
}

// ---------------------------------------------------------------------------
// The parts
// ---------------------------------------------------------------------------

String _document(void Function(XmlBuilder b) build) {
  final b = XmlBuilder();
  // The prolog is what declares UTF-8: Gurmukhi and Devanagari names survive
  // because every consumer is told the encoding before it reads a byte.
  b.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  build(b);
  return b.buildDocument().toXmlString();
}

/// `[Content_Types].xml` — every part in the package has a declared type, by
/// extension or by name. A part Excel cannot type is a part it repairs away.
String xlsxContentTypes() => _document((b) {
  b.element(
    'Types',
    attributes: {'xmlns': _nsContentTypes},
    nest: () {
      b.element(
        'Default',
        attributes: {
          'Extension': 'rels',
          'ContentType':
              'application/vnd.openxmlformats-package.relationships+xml',
        },
      );
      b.element(
        'Default',
        attributes: {'Extension': 'xml', 'ContentType': 'application/xml'},
      );
      for (final part in const {
        xlsxWorkbookPart: _typeWorkbook,
        xlsxSheetPart: _typeWorksheet,
        xlsxStylesPart: _typeStyles,
      }.entries) {
        b.element(
          'Override',
          attributes: {'PartName': '/${part.key}', 'ContentType': part.value},
        );
      }
    },
  );
});

/// `_rels/.rels` — the package root points at the workbook.
String xlsxPackageRels() => _document((b) {
  b.element(
    'Relationships',
    attributes: {'xmlns': _nsPackageRels},
    nest: () {
      b.element(
        'Relationship',
        attributes: {
          'Id': _workbookRelId,
          'Type': _relTypeOfficeDocument,
          'Target': xlsxWorkbookPart,
        },
      );
    },
  );
});

/// `xl/_rels/workbook.xml.rels` — the workbook points at its sheet and its
/// styles. Targets are relative to `xl/`, which is why they carry no prefix.
String xlsxWorkbookRels() => _document((b) {
  b.element(
    'Relationships',
    attributes: {'xmlns': _nsPackageRels},
    nest: () {
      b.element(
        'Relationship',
        attributes: {
          'Id': xlsxSheetRelId,
          'Type': _relTypeWorksheet,
          'Target': 'worksheets/sheet1.xml',
        },
      );
      b.element(
        'Relationship',
        attributes: {
          'Id': _stylesRelId,
          'Type': _relTypeStyles,
          'Target': 'styles.xml',
        },
      );
    },
  );
});

/// `xl/workbook.xml` — one sheet, named [sheetName], bound to the worksheet
/// part by [xlsxSheetRelId].
String xlsxWorkbook(String sheetName) => _document((b) {
  b.element(
    'workbook',
    attributes: {'xmlns': _nsSpreadsheet, 'xmlns:r': _nsDocRels},
    nest: () {
      b.element(
        'sheets',
        nest: () {
          b.element(
            'sheet',
            attributes: {
              'name': xlsxSheetName(sheetName),
              'sheetId': '1',
              'r:id': xlsxSheetRelId,
            },
          );
        },
      );
    },
  );
});

/// `xl/styles.xml` — minimal, but carrying the two formats that make this
/// file more than a CSV: money and dates.
///
/// The counts and the order are load-bearing: a cell's `s="n"` indexes
/// `cellXfs`, and Excel wants the two default fills present even when nothing
/// uses them.
String xlsxStyles() => _document((b) {
  void xf(Map<String, String> attributes) =>
      b.element('xf', attributes: attributes);

  b.element(
    'styleSheet',
    attributes: {'xmlns': _nsSpreadsheet},
    nest: () {
      b.element(
        'numFmts',
        attributes: {'count': '2'},
        nest: () {
          b.element(
            'numFmt',
            attributes: {
              'numFmtId': '$_numFmtMoney',
              // See the ⚠️ SPEC note at the head: display only, M12 may swap
              // this for the Indian grouping. The value never changes.
              'formatCode': '#,##0.00',
            },
          );
          b.element(
            'numFmt',
            attributes: {
              'numFmtId': '$_numFmtDate',
              // Locale-independent: an `.xlsx` travels, and `dd-mm-yyyy` is
              // read the same way wherever it lands.
              'formatCode': 'dd-mm-yyyy',
            },
          );
        },
      );
      b.element(
        'fonts',
        attributes: {'count': '2'},
        nest: () {
          b.element(
            'font',
            nest: () {
              b.element('sz', attributes: {'val': '11'});
              b.element('name', attributes: {'val': 'Calibri'});
            },
          );
          b.element(
            'font',
            nest: () {
              b.element('b');
              b.element('sz', attributes: {'val': '11'});
              b.element('name', attributes: {'val': 'Calibri'});
            },
          );
        },
      );
      b.element(
        'fills',
        attributes: {'count': '2'},
        nest: () {
          for (final pattern in const ['none', 'gray125']) {
            b.element(
              'fill',
              nest: () => b.element(
                'patternFill',
                attributes: {'patternType': pattern},
              ),
            );
          }
        },
      );
      b.element(
        'borders',
        attributes: {'count': '1'},
        nest: () {
          b.element(
            'border',
            nest: () {
              for (final side in const [
                'left',
                'right',
                'top',
                'bottom',
                'diagonal',
              ]) {
                b.element(side);
              }
            },
          );
        },
      );
      b.element(
        'cellStyleXfs',
        attributes: {'count': '1'},
        nest: () => xf(const {
          'numFmtId': '0',
          'fontId': '0',
          'fillId': '0',
          'borderId': '0',
        }),
      );
      // Order is the contract: these five are xlsxStyleDefault … Total.
      b.element(
        'cellXfs',
        attributes: {'count': '5'},
        nest: () {
          xf(const {
            'numFmtId': '0',
            'fontId': '0',
            'fillId': '0',
            'borderId': '0',
            'xfId': '0',
          });
          xf(const {
            'numFmtId': '0',
            'fontId': '1',
            'fillId': '0',
            'borderId': '0',
            'xfId': '0',
            'applyFont': '1',
          });
          xf({
            'numFmtId': '$_numFmtMoney',
            'fontId': '0',
            'fillId': '0',
            'borderId': '0',
            'xfId': '0',
            'applyNumberFormat': '1',
          });
          xf({
            'numFmtId': '$_numFmtDate',
            'fontId': '0',
            'fillId': '0',
            'borderId': '0',
            'xfId': '0',
            'applyNumberFormat': '1',
          });
          xf({
            'numFmtId': '$_numFmtMoney',
            'fontId': '1',
            'fillId': '0',
            'borderId': '0',
            'xfId': '0',
            'applyNumberFormat': '1',
            'applyFont': '1',
          });
        },
      );
      b.element(
        'cellStyles',
        attributes: {'count': '1'},
        nest: () => b.element(
          'cellStyle',
          attributes: {'name': 'Normal', 'xfId': '0', 'builtinId': '0'},
        ),
      );
    },
  );
});

/// `xl/worksheets/sheet1.xml` from [rows] — row 1 is `rows.first`.
String xlsxSheet(List<List<XlsxCell?>> rows) => _document((b) {
  b.element(
    'worksheet',
    attributes: {'xmlns': _nsSpreadsheet, 'xmlns:r': _nsDocRels},
    nest: () {
      b.element(
        'sheetData',
        nest: () {
          for (var r = 0; r < rows.length; r++) {
            final cells = rows[r];
            if (cells.every((c) => c == null)) continue;
            final rowNumber = r + 1;
            b.element(
              'row',
              attributes: {'r': '$rowNumber'},
              nest: () {
                for (var c = 0; c < cells.length; c++) {
                  final cell = cells[c];
                  if (cell == null) continue;
                  _writeCell(b, '${xlsxColumnName(c + 1)}$rowNumber', cell);
                }
              },
            );
          }
        },
      );
    },
  );
});

void _writeCell(XmlBuilder b, String ref, XlsxCell cell) {
  switch (cell) {
    case XlsxText():
      b.element(
        'c',
        attributes: {'r': ref, 's': '${cell.style}', 't': 'inlineStr'},
        nest: () => b.element(
          'is',
          nest: () => b.element(
            't',
            // Preserved, so a name that ends in a space is not silently
            // trimmed by the reader.
            attributes: {'xml:space': 'preserve'},
            nest: () => b.text(cell.value),
          ),
        ),
      );
    case XlsxMoney():
      // No `t` attribute: a cell with no type is a number, which is the point
      // — the column sums. The text is the integer-paise decimal.
      b.element(
        'c',
        attributes: {'r': ref, 's': '${cell.style}'},
        nest: () =>
            b.element('v', nest: () => b.text(paiseToDecimal(cell.paise))),
      );
    case XlsxDate():
      b.element(
        'c',
        attributes: {'r': ref, 's': '${cell.style}'},
        nest: () =>
            b.element('v', nest: () => b.text('${xlsxSerialDate(cell.date)}')),
      );
  }
}

// ---------------------------------------------------------------------------
// The report
// ---------------------------------------------------------------------------

/// The day book's sheet rows — the classical layout, shared with the CSV.
///
/// [accountName] resolves an account id to its display name; the caller holds
/// the chart, this file does not reach for one.
List<List<XlsxCell?>> dayBookSheetRows(
  DayBook book, {
  required String Function(String accountId) accountName,
  required ReportLabels labels,
  required String bookName,
  required String period,
}) {
  final rows = <List<XlsxCell?>>[
    // A short head, so the file says what it is once it has left the app. No
    // figures here — the head is metadata, the body is the report.
    [XlsxText(labels.reportName, style: xlsxStyleBold)],
    [XlsxText(labels.bookLabel), XlsxText(bookName)],
    [XlsxText(labels.periodLabel), XlsxText(period)],
    const [null],
    [
      XlsxText(labels.columnDate, style: xlsxStyleBold),
      XlsxText(labels.columnParticulars, style: xlsxStyleBold),
      // Professional vocabulary (02 §10 🔒): Dr and Cr, never Money in/out.
      XlsxText(labels.columnDebit, style: xlsxStyleBold),
      XlsxText(labels.columnCredit, style: xlsxStyleBold),
      XlsxText(labels.columnNote, style: xlsxStyleBold),
    ],
  ];

  for (final row in book.rows) {
    // The date and the note sit on the entry's first line; every further line
    // of the same entry continues under it.
    var first = true;
    for (final line in [...row.debits, ...row.credits]) {
      rows.add([
        first ? XlsxDate(row.date) : null,
        XlsxText(accountName(line.accountId)),
        line.isDebit ? XlsxMoney(line.figurePaise) : null,
        line.isCredit ? XlsxMoney(line.figurePaise) : null,
        first && row.note != null ? XlsxText(row.note!) : null,
      ]);
      first = false;
    }
  }

  // The cross-check footer (13 §5, flow F3): the two columns must agree,
  // because every entry balances (02 §1.4).
  rows.add([
    null,
    XlsxText(labels.totalLabel, style: xlsxStyleBold),
    XlsxMoney(book.debitTotalPaise, style: xlsxStyleMoneyTotal),
    XlsxMoney(book.creditTotalPaise, style: xlsxStyleMoneyTotal),
  ]);
  return rows;
}

/// The day book as the bytes of an `.xlsx` — a zip of the five parts.
Uint8List dayBookXlsx(
  DayBook book, {
  required String Function(String accountId) accountName,
  required ReportLabels labels,
  required String bookName,
  required String period,
}) {
  final sheet = xlsxSheet(
    dayBookSheetRows(
      book,
      accountName: accountName,
      labels: labels,
      bookName: bookName,
      period: period,
    ),
  );

  final archive = Archive();
  for (final part in <String, String>{
    _contentTypesPart: xlsxContentTypes(),
    _packageRelsPart: xlsxPackageRels(),
    _workbookRelsPart: xlsxWorkbookRels(),
    xlsxWorkbookPart: xlsxWorkbook(labels.reportName),
    xlsxStylesPart: xlsxStyles(),
    xlsxSheetPart: sheet,
  }.entries) {
    // Explicit UTF-8 bytes rather than ArchiveFile.string, so the encoding in
    // the zip is the one each part's prolog declares.
    archive.add(ArchiveFile.bytes(part.key, utf8.encode(part.value)));
  }

  return ZipEncoder().encodeBytes(archive, modified: xlsxZipTimestamp);
}

/// The day book as a [ReportFile] ready for a [ReportSink].
ReportFile dayBookXlsxFile(
  DayBook book, {
  required String Function(String accountId) accountName,
  required ReportLabels labels,
  required String bookName,
  required String period,
  required String fileName,
}) => ReportFile(
  name: fileName,
  format: ReportFormat.xlsx,
  bytes: dayBookXlsx(
    book,
    accountName: accountName,
    labels: labels,
    bookName: bookName,
    period: period,
  ),
);
