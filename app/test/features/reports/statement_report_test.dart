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
// The closing block is the M12 half (07 §14 🔒 *b/d–c/d rows on ledgers*,
// 02 §8.1 *Presentation*): b/f · body · **c/d · Total · b/d**, with the amount
// in words under the table. The cases below read the two column totals out of
// each format and check they are equal — a page whose Dr and Cr columns do not
// add up is not the traditional book the rule asks for.
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
import 'package:rukka_folio/features/reports/export/amount_words.dart';
import 'package:rukka_folio/features/reports/statement_report.dart';
import 'package:rukka_folio/l10n/gen/app_localizations_pa.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:xml/xml.dart';

/// Punjabi labels throughout: the hard case for every format at once — the
/// CSV's BOM, the XLSX's UTF-8 parts and the PDF's embedded faces.
final _labels = StatementReportLabels(
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
  closingCarriedDown: 'ਅਗਲੀ ਬਾਕੀ c/d',
  openingBroughtDown: 'ਨਵੀਂ ਸ਼ੁਰੂਆਤੀ ਬਾਕੀ b/d',
  total: 'ਕੁੱਲ',
  closingInWords: 'ਬਾਕੀ ਸ਼ਬਦਾਂ ਵਿੱਚ',
  // The real Punjabi ARB, not a fixture: the words line is the one place an
  // export spells a figure out, and a missing Gurmukhi numeral has to fail
  // here rather than on a printed statement.
  amountWords: AmountWords.of(AppLocalizationsPa()),
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
    test(
      'F1-07-163 the CSV is exactly these bytes: a BOM, the head, Dr/Cr and '
      'Balance columns, b/f first and the c/d · Total · b/d block last, '
      'with the amount in words under it (ADR 2026-09-12e §3 🔒, 07 §14 🔒)',
      () {
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
            // b/f — first row of every view (02 §8.1 *Presentation*). A Dr
            // carry-forward sits in the Dr column too, so the page adds up.
            '2026-04-01,ਪਿਛਲੀ ਬਾਕੀ b/f,5000.00,,5000.00,',
            // A credit line leaves the Dr cell empty, as a paper ledger reads;
            // the note is quoted because it carries a comma (RFC 4180).
            '2026-05-04,ਹੱਥ ਨਕਦ,,2000.00,3000.00,"ਕੁਝ ਵਾਪਸ, & ਬਾਕੀ"',
            '2026-06-11,ਹੱਥ ਨਕਦ,1500.00,,4500.00,',
            // c/f — where the FY view ends (02 §8.1), then c/d: the Dr balance
            // is carried down on the *Cr* side, which squares the account
            // (07 §14 🔒). Both rows are carried — see the ⚠️ SPEC in
            // `statement_report.dart`.
            '2027-03-31,ਅਗਲੀ ਬਾਕੀ c/f,,,4500.00,',
            '2027-03-31,ਅਗਲੀ ਬਾਕੀ c/d,,4500.00,,',
            // …and the two columns are then equal: 5000 + 1500 = 2000 + 4500.
            ',ਕੁੱਲ,6500.00,6500.00,,',
            // b/d — the same figure brought down into the next period, on its
            // own side, dated the day the next period opens.
            '2027-04-01,ਨਵੀਂ ਸ਼ੁਰੂਆਤੀ ਬਾਕੀ b/d,4500.00,,4500.00,',
            '',
            // The amount in words, from the real Punjabi ARB (07 §14 🔒).
            'ਬਾਕੀ ਸ਼ਬਦਾਂ ਵਿੱਚ,ਰੁਪਏ ਚਾਰ ਹਜ਼ਾਰ ਪੰਜ ਸੌ ਪੂਰੇ',
            '',
          ].join('\r\n'),
        );
        // Money is the machine-readable decimal of integer paise — never ₹,
        // never grouped, never a float.
        expect(text, isNot(contains('₹')));
      },
    );

    test('F1-07-164 the XLSX carries money as numbers and dates as dates, the '
        'b/f, c/d, Total and b/d rows emphasised, and exports byte for byte '
        'the same file twice', () {
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
      // …and a Dr carry-forward also stands in the Dr column, so the Total
      // row below can be read off the page. The Cr cell stays blank, not
      // zero — an empty box is how a paper ledger reads (07 §6).
      expect(cells['C7']!.value, '5000.00');
      expect(cells['D7'], isNull);

      // Row 8, the credit line: no Dr cell at all, the Cr figure a number,
      // and the running balance signed the engine's way (+ = Dr, 02 §1.3).
      expect(cells['C8'], isNull);
      expect(cells['D8']!.value, '2000.00');
      expect(cells['D8']!.style, '$xlsxStyleMoney');
      expect(cells['E8']!.value, '3000.00');
      expect(cells['F8']!.value, 'ਕੁਝ ਵਾਪਸ, & ਬਾਕੀ');

      // Row 10 is the c/f — where the FY view ends (02 §8.1).
      expect(cells['B10']!.value, 'ਅਗਲੀ ਬਾਕੀ c/f');
      expect(cells['E10']!.value, '4500.00');
      expect(cells['A10']!.value, '${xlsxSerialDate(_lastDay)}');

      // Row 11 is the c/d: the Dr balance carried down on the Cr side, and
      // no running balance left to carry once the account is squared.
      expect(cells['B11']!.value, 'ਅਗਲੀ ਬਾਕੀ c/d');
      expect(cells['C11'], isNull);
      expect(cells['D11']!.value, '4500.00');
      expect(cells['E11'], isNull);

      // Row 12 is the cross-check: two numbers, equal, and summable — which
      // is the whole reason this format exists beside the CSV.
      expect(cells['B12']!.value, 'ਕੁੱਲ');
      expect(cells['C12']!.type, isNull, reason: 'a total must be a number');
      expect(cells['C12']!.value, '6500.00');
      expect(cells['D12']!.value, '6500.00');

      // Row 13 is the b/d, dated the first day of the next period.
      expect(cells['B13']!.value, 'ਨਵੀਂ ਸ਼ੁਰੂਆਤੀ ਬਾਕੀ b/d');
      expect(cells['C13']!.value, '4500.00');
      expect(cells['E13']!.value, '4500.00');
      expect(cells['A13']!.value, '${xlsxSerialDate(_lastDay.addDays(1))}');

      // Row 14 blank, row 15 the amount in words — text, never a number: a
      // spreadsheet must not try to sum a sentence.
      expect(cells['A14'], isNull);
      expect(cells['A15']!.value, 'ਬਾਕੀ ਸ਼ਬਦਾਂ ਵਿੱਚ');
      expect(cells['B15']!.type, 'inlineStr');
      expect(cells['B15']!.value, 'ਰੁਪਏ ਚਾਰ ਹਜ਼ਾਰ ਪੰਜ ਸੌ ਪੂਰੇ');
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
          _labels.closingCarriedDown,
          _labels.openingBroughtDown,
          _labels.total,
          _labels.closingInWords,
          // The amount in words is the longest Gurmukhi run in the document
          // and the one a reader checks the numerals against; drawn as empty
          // boxes it would be worse than absent.
          table.amountInWords!.value,
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
      'statement — b/f and the c/d · Total · b/d block at nil, never a dead '
      'end (07 §1 rules 2 and 6)',
      (tester) async {
        final empty = Statement(
          accountId: 'acc-ramesh',
          rows: const [],
          openingPaise: 0,
          from: _firstDay,
          to: _lastDay,
        );
        final table = _table(empty);

        // CSV: the head, the columns, and the closing block with a zero
        // balance — a real statement of an untouched account. A nil balance
        // has no side, so the c/d row has nothing to square and both figure
        // cells are blank, never a printed 0.00 (07 §6).
        final csv = utf8.decode(
          reportTableCsvFile(table, fileName: 'x.csv').bytes.sublist(3),
        );
        expect(csv, contains('2026-04-01,ਪਿਛਲੀ ਬਾਕੀ b/f,,,0.00,'));
        expect(csv, contains('2027-03-31,ਅਗਲੀ ਬਾਕੀ c/f,,,0.00,'));
        expect(csv, contains('2027-03-31,ਅਗਲੀ ਬਾਕੀ c/d,,,,'));
        expect(csv, contains(',ਕੁੱਲ,0.00,0.00,,'));
        expect(csv, contains('2027-04-01,ਨਵੀਂ ਸ਼ੁਰੂਆਤੀ ਬਾਕੀ b/d,,,0.00,'));
        // Zero still reads as a sentence, never a blank line.
        expect(csv, contains('ਬਾਕੀ ਸ਼ਬਦਾਂ ਵਿੱਚ,ਰੁਪਏ ਸਿਫ਼ਰ ਪੂਰੇ'));

        // XLSX: the same rows, immediately under the headings.
        final cells = _cells(_parts(reportTableXlsx(table))[xlsxSheetPart]!);
        expect(cells['B7']!.value, 'ਪਿਛਲੀ ਬਾਕੀ b/f');
        expect(cells['B8']!.value, 'ਅਗਲੀ ਬਾਕੀ c/f');
        expect(cells['B9']!.value, 'ਅਗਲੀ ਬਾਕੀ c/d');
        expect(cells['B10']!.value, 'ਕੁੱਲ');
        expect(cells['C10']!.value, '0.00');
        expect(cells['B11']!.value, 'ਨਵੀਂ ਸ਼ੁਰੂਆਤੀ ਬਾਕੀ b/d');
        expect(cells['E11']!.value, '0.00');

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

  group('the closing block squares the page (07 §14 🔒, 02 §8.1)', () {
    test('F1-07-432 a Cr closing balance is carried down on the Dr side and '
        'brought down on the Cr side, and the two column totals are still '
        'equal — the mirror of the Dr case', () {
      final table = _table(_sharma());

      // c/d closes the *lighter* side: a Cr balance is squared with a Dr
      // figure, which is the opposite column to the Dr case above.
      final cd = table.rows[table.rows.length - 3];
      expect((cd.cells[1]! as ReportTextCell).text, _labels.closingCarriedDown);
      expect((cd.cells[2]! as ReportMoneyCell).paise, 2_700_00);
      expect(cd.cells[3], isNull);
      expect(cd.cells[4], isNull, reason: 'a squared account runs no balance');

      // The Total row is the cross-check, and it is read off the page: b/f on
      // its side, every posting line, and the c/d figure.
      final total = table.rows[table.rows.length - 2];
      expect(total.kind, ReportRowKind.total);
      final totalDebit = (total.cells[2]! as ReportMoneyCell).paise;
      final totalCredit = (total.cells[3]! as ReportMoneyCell).paise;
      expect(totalDebit, totalCredit);
      expect(totalDebit, 3_000_00);
      // Stated the long way round too, so the case says *why* they are equal
      // rather than restating one constant twice.
      expect(totalDebit, 300_00 + 2_700_00);
      expect(totalCredit, 1_000_00 + 2_000_00);

      // b/d restates the balance on its own side, and its running-balance
      // cell is the engine's signed closing figure — the statement ties.
      final bd = table.rows.last;
      expect((bd.cells[1]! as ReportTextCell).text, _labels.openingBroughtDown);
      expect(bd.cells[2], isNull);
      expect((bd.cells[3]! as ReportMoneyCell).paise, 2_700_00);
      final carried = bd.cells[4]! as ReportMoneyCell;
      expect(carried.paise, _sharma().closingPaise);
      expect(carried.paise, -2_700_00, reason: '+ = Dr, − = Cr (02 §1.3)');
      expect(carried.side, _labels.columnCredit);
      // The date it opens on is the day after the period closes.
      expect((bd.cells[0]! as ReportDateCell).date, _lastDay.addDays(1));

      // The words under the table are a magnitude — never a minus sign, in
      // words or in numerals (02 §10 🔒, design-system §1 rule 0b 🔒).
      expect(table.amountInWords!.value, 'ਰੁਪਏ ਦੋ ਹਜ਼ਾਰ ਸੱਤ ਸੌ ਪੂਰੇ');
      expect(table.amountInWords!.value, isNot(contains('−')));
      expect(table.amountInWords!.value, isNot(contains('-')));
    });

    test('F1-07-433 the XLSX money format is the Indian #,##,##0.00 — three '
        'digits then twos (07 §14 🔒, 11 §4.4), and it changes the cell\'s '
        'display, never its value', () {
      final parts = _parts(reportTableXlsx(_table(_ramesh())));
      final styles = parts[xlsxStylesPart]!;
      expect(styles, contains('#,##,##0.00'));
      expect(
        styles,
        isNot(contains('"#,##0.00"')),
        reason: 'the neutral grouping must not survive beside the Indian one',
      );

      // The stored number is untouched by the format: a lakh is still the
      // plain decimal of integer paise, which is what lets the column sum.
      final cells = _cells(parts[xlsxSheetPart]!);
      expect(cells['E7']!.value, '5000.00');
      expect(cells['E7']!.value, isNot(contains(',')));
      for (final cell in cells.values) {
        expect(cell.value, isNot(contains('₹')));
      }
    });
  });
}

/// A statement whose balance is **Cr** throughout — the mirror of `_ramesh`.
/// Carried in Cr ₹1,000, one debit of ₹300 and one credit of ₹2,000, closing
/// Cr ₹2,700. Synthetic figures (CLAUDE.md rule 4).
Statement _sharma() => Statement(
  accountId: 'acc-sharma',
  openingPaise: -1_000_00,
  from: _firstDay,
  to: _lastDay,
  rows: [
    StatementRow(
      entryId: 'e1',
      accountId: 'acc-sharma',
      date: LocalDate.parse('2026-05-04'),
      kind: EntryKind.moneyOut,
      status: 'posted',
      reviewState: 'none',
      amountPaise: 300_00,
      runningBalancePaise: -700_00,
      counterAccountIds: const ['acc-cash'],
      hlc: 1,
    ),
    StatementRow(
      entryId: 'e2',
      accountId: 'acc-sharma',
      date: LocalDate.parse('2026-06-11'),
      kind: EntryKind.gaveCredit,
      status: 'posted',
      reviewState: 'none',
      amountPaise: -2_000_00,
      runningBalancePaise: -2_700_00,
      counterAccountIds: const ['acc-cash'],
      hlc: 2,
    ),
  ],
);
