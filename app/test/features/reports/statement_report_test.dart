// F1-07-163 … F1-07-166 — the exported A/C statement, one case per format
// (ADR 2026-09-12e §2 🔒: the trio *View · Download/Share · Export
// (PDF/CSV/XLSX)* is binding on S4; 07 §14 🔒 b/d–c/d rows on ledgers; 02 §8.1
// *Presentation*; 02 §10 🔒 professional Dr/Cr).
//
// These are **byte-level** cases, and deliberately not driven through a
// database: the statement is built from a hand-written [Statement], so the
// figures, the dates and therefore the bytes are the same on every machine and
// every day. What they assert is what a file that has left the app has to get
// right —
//
//   • the CSV's leading bytes are the UTF-8 BOM and its records are exactly
//     the text below, CRLF-terminated (ADR 2026-09-12e §3 🔒);
//   • the XLSX carries money as **numbers** and dates as **dates**, and the
//     same statement exported twice is the same file byte for byte (the F3
//     goldens of M12 depend on that);
//   • the PDF is an A4 document with the app's own faces embedded, so a
//     Gurmukhi or Devanagari statement is never a page of empty boxes.
//
// Amount-in-words is **M12** (07 §14) and is not asserted here.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:archive/archive.dart';
import 'package:core_ledger/core_ledger.dart' hide StatementRow;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/reports/export/csv_report.dart';
import 'package:rukka_folio/features/reports/export/pdf_report.dart';
import 'package:rukka_folio/features/reports/export/report_export.dart';
import 'package:rukka_folio/features/reports/export/report_table.dart';
import 'package:rukka_folio/features/reports/export/xlsx_report.dart';
import 'package:rukka_folio/features/reports/statement_report.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:xml/xml.dart';

/// Punjabi labels throughout: the hard case for every format at once — the
/// CSV's BOM, the XLSX's UTF-8 parts and the PDF's embedded faces.
const _labels = StatementReportLabels(
  reportName: 'ਖਾਤਾ ਸਟੇਟਮੈਂਟ',
  accountLabel: 'ਖਾਤਾ',
  bookLabel: 'ਕਿਤਾਬ',
  periodLabel: 'ਮਿਆਦ',
  columnDate: 'ਤਾਰੀਖ਼',
  columnParticulars: 'ਵੇਰਵਾ',
  columnDebit: 'ਨਾਮੇ',
  columnCredit: 'ਜਮ੍ਹਾਂ',
  columnBalance: 'ਬਾਕੀ',
  columnNote: 'ਨੋਟ',
  opening: 'ਪਿਛਲੀ ਬਾਕੀ b/f',
  closing: 'ਅਗਲੀ ਬਾਕੀ c/f',
);

final _firstDay = LocalDate.parse('2026-04-01');
final _lastDay = LocalDate.parse('2027-03-31');

/// A statement of *Ramesh*: carried in Dr ₹5,000, one credit of ₹2,000 and one
/// debit of ₹1,500 — so the running balance moves in both directions and the
/// c/f is a Dr figure. Synthetic figures (CLAUDE.md rule 4).
Statement _ramesh() => Statement(
  accountId: 'acc-ramesh',
  openingPaise: 5_000_00,
  from: _firstDay,
  to: _lastDay,
  rows: [
    StatementRow(
      entryId: 'e1',
      accountId: 'acc-ramesh',
      date: LocalDate.parse('2026-05-04'),
      kind: EntryKind.moneyIn,
      status: 'posted',
      reviewState: 'none',
      amountPaise: -2_000_00,
      runningBalancePaise: 3_000_00,
      counterAccountIds: const ['acc-cash'],
      hlc: 1,
      note: 'ਕੁਝ ਵਾਪਸ, & ਬਾਕੀ',
    ),
    StatementRow(
      entryId: 'e2',
      accountId: 'acc-ramesh',
      date: LocalDate.parse('2026-06-11'),
      kind: EntryKind.gaveCredit,
      status: 'posted',
      reviewState: 'none',
      amountPaise: 1_500_00,
      runningBalancePaise: 4_500_00,
      counterAccountIds: const ['acc-cash'],
      hlc: 2,
    ),
  ],
);

ReportTable _table(Statement statement) => statementTable(
  statement,
  accountName: 'ਰਮੇਸ਼',
  bookName: 'ਮੇਰੀ ਬਹੀ',
  period: 'FY 2026-27',
  labels: _labels,
  counterNames: (row) => [
    for (final id in row.counterAccountIds) id == 'acc-cash' ? 'ਹੱਥ ਨਕਦ' : id,
  ],
  formatDate: (date) => date.toIso(),
  openingDate: _firstDay,
  closingDate: _lastDay,
);

/// Unzips an `.xlsx` and returns every part as text, keyed by part name.
Map<String, String> _parts(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return {
    for (final f in archive.files)
      if (f.isFile) f.name: utf8.decode(f.readBytes()!),
  };
}

/// One cell as the sheet XML actually carries it.
typedef _Cell = ({String? type, String? style, String value});

Map<String, _Cell> _cells(String sheetXml) {
  final doc = XmlDocument.parse(sheetXml);
  return {
    for (final c in doc.findAllElements('c'))
      c.getAttribute('r')!: (
        type: c.getAttribute('t'),
        style: c.getAttribute('s'),
        value: c.getAttribute('t') == 'inlineStr'
            ? c.findAllElements('t').map((e) => e.innerText).join()
            : c.findElements('v').map((e) => e.innerText).join(),
      ),
  };
}

void main() {
  group('A/C statement export (ADR 2026-09-12e §2 🔒, 07 §14 🔒, 02 §8.1)', () {
    test('F1-07-163 the CSV is exactly these bytes: a BOM, the head, Dr/Cr and '
        'Balance columns, b/f first and c/f last (ADR 2026-09-12e §3 🔒)', () {
      final file = reportTableCsvFile(
        _table(_ramesh()),
        fileName: 'statement-2026-27.csv',
      );

      // The BOM, byte for byte — without it a spreadsheet on Windows reads
      // every Gurmukhi name as mojibake.
      expect(file.bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(file.format, ReportFormat.csv);

      final text = utf8.decode(file.bytes.sublist(3));
      expect(
        text,
        [
          'ਖਾਤਾ ਸਟੇਟਮੈਂਟ',
          'ਖਾਤਾ,ਰਮੇਸ਼',
          'ਕਿਤਾਬ,ਮੇਰੀ ਬਹੀ',
          'ਮਿਆਦ,FY 2026-27',
          '',
          'ਤਾਰੀਖ਼,ਵੇਰਵਾ,ਨਾਮੇ,ਜਮ੍ਹਾਂ,ਬਾਕੀ,ਨੋਟ',
          // b/f — first row of every view (02 §8.1 *Presentation*).
          '2026-04-01,ਪਿਛਲੀ ਬਾਕੀ b/f,,,5000.00,',
          // A credit line leaves the Dr cell empty, as a paper ledger reads;
          // the note is quoted because it carries a comma (RFC 4180).
          '2026-05-04,ਹੱਥ ਨਕਦ,,2000.00,3000.00,"ਕੁਝ ਵਾਪਸ, & ਬਾਕੀ"',
          '2026-06-11,ਹੱਥ ਨਕਦ,1500.00,,4500.00,',
          // c/f — last row of every view.
          '2027-03-31,ਅਗਲੀ ਬਾਕੀ c/f,,,4500.00,',
          '',
        ].join('\r\n'),
      );
      // Money is the machine-readable decimal of integer paise — never ₹,
      // never grouped, never a float.
      expect(text, isNot(contains('₹')));
    });

    test('F1-07-164 the XLSX carries money as numbers and dates as dates, the '
        'b/f and c/f rows emphasised, and exports byte for byte the same file '
        'twice', () {
      final table = _table(_ramesh());
      final first = reportTableXlsx(table);
      final second = reportTableXlsx(table);
      // The zip carries no clock: the F3 byte goldens (M12) depend on it.
      expect(first, orderedEquals(second));

      final parts = _parts(first);
      expect(parts.keys, contains(xlsxSheetPart));
      final cells = _cells(parts[xlsxSheetPart]!);

      // Row 1 the report name, rows 2–4 the head, row 5 blank, row 6 the
      // column headings — professional words, never Money in / Money out.
      expect(cells['A1']!.value, 'ਖਾਤਾ ਸਟੇਟਮੈਂਟ');
      expect(cells['B2']!.value, 'ਰਮੇਸ਼');
      expect(cells['A6']!.value, 'ਤਾਰੀਖ਼');
      expect(cells['C6']!.value, 'ਨਾਮੇ');
      expect(cells['D6']!.value, 'ਜਮ੍ਹਾਂ');
      expect(cells['E6']!.value, 'ਬਾਕੀ');
      for (final cell in cells.values) {
        expect(cell.value, isNot(contains('Money in')));
      }

      // Row 7 is the b/f: a real date, the label in bold, and the carried
      // balance as a *number* the column can sum.
      expect(cells['A7']!.type, isNull);
      expect(cells['A7']!.value, '${xlsxSerialDate(_firstDay)}');
      expect(cells['A7']!.style, '$xlsxStyleDate');
      expect(cells['B7']!.value, 'ਪਿਛਲੀ ਬਾਕੀ b/f');
      expect(cells['B7']!.style, '$xlsxStyleBold');
      expect(cells['E7']!.type, isNull, reason: 'a balance must be a number');
      expect(cells['E7']!.value, '5000.00');
      expect(cells['E7']!.style, '$xlsxStyleMoneyTotal');
      // …and the Dr and Cr cells of a b/f row are blank, not zero.
      expect(cells['C7'], isNull);
      expect(cells['D7'], isNull);

      // Row 8, the credit line: no Dr cell at all, the Cr figure a number,
      // and the running balance signed the engine's way (+ = Dr, 02 §1.3).
      expect(cells['C8'], isNull);
      expect(cells['D8']!.value, '2000.00');
      expect(cells['D8']!.style, '$xlsxStyleMoney');
      expect(cells['E8']!.value, '3000.00');
      expect(cells['F8']!.value, 'ਕੁਝ ਵਾਪਸ, & ਬਾਕੀ');

      // Row 10 is the c/f — the last row of the view.
      expect(cells['B10']!.value, 'ਅਗਲੀ ਬਾਕੀ c/f');
      expect(cells['E10']!.value, '4500.00');
      expect(cells['A10']!.value, '${xlsxSerialDate(_lastDay)}');
    });

    testWidgets(
      'F1-07-165 the PDF is A4 with the app\'s own faces embedded, so a '
      'Gurmukhi statement is never a page of empty boxes (11 §4.4, 01 §1.8)',
      (tester) async {
        final fonts = await ReportFonts.load();
        final table = _table(_ramesh());
        final bytes = await reportTablePdf(
          table,
          pageNumber: (page, pages) => 'ਸਫ਼ਾ $page / $pages',
          fonts: fonts,
          locale: const Locale('pa'),
        );

        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        final raw = latin1.decode(bytes, allowInvalid: true);
        // A4, 595.27559 x 841.88976 pt — 07 §14 🔒 print-clean.
        expect(raw, contains('MediaBox[0 0 595.27559 841.88976]'));
        // Faces are embedded (a subset stream per face), never referenced by
        // name from the reader's machine.
        expect(raw, contains('/FontFile2'));

        // Every string the writer was handed can be drawn by a face in the
        // document — its own inputs, not a sample.
        for (final text in [
          _labels.reportName,
          _labels.opening,
          _labels.closing,
          _labels.columnBalance,
          'ਰਮੇਸ਼',
          'ਹੱਥ ਨਕਦ',
          'ਕੁਝ ਵਾਪਸ, & ਬਾਕੀ',
        ]) {
          expect(fonts.unsupportedRunes(text), isEmpty, reason: text);
        }
      },
    );

    testWidgets(
      'F1-07-166 an account with nothing in the period still exports a '
      'statement — b/f and c/f, never a dead end (07 §1 rules 2 and 6)',
      (tester) async {
        final empty = Statement(
          accountId: 'acc-ramesh',
          rows: const [],
          openingPaise: 0,
          from: _firstDay,
          to: _lastDay,
        );
        final table = _table(empty);

        // CSV: the head, the columns, and the two boundary rows with a zero
        // balance — a real statement of an untouched account.
        final csv = utf8.decode(
          reportTableCsvFile(table, fileName: 'x.csv').bytes.sublist(3),
        );
        expect(csv, contains('2026-04-01,ਪਿਛਲੀ ਬਾਕੀ b/f,,,0.00,'));
        expect(csv, contains('2027-03-31,ਅਗਲੀ ਬਾਕੀ c/f,,,0.00,'));

        // XLSX: the same two rows, immediately under the headings.
        final cells = _cells(_parts(reportTableXlsx(table))[xlsxSheetPart]!);
        expect(cells['B7']!.value, 'ਪਿਛਲੀ ਬਾਕੀ b/f');
        expect(cells['B8']!.value, 'ਅਗਲੀ ਬਾਕੀ c/f');
        expect(cells['E8']!.value, '0.00');

        // PDF: still a document.
        final fonts = await ReportFonts.load();
        final bytes = await reportTablePdf(
          table,
          pageNumber: (page, pages) => 'ਸਫ਼ਾ $page / $pages',
          fonts: fonts,
          locale: const Locale('pa'),
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      },
    );
  });
}
