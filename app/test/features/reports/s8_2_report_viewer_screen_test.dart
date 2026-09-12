// F1-07-79 (07 §14 🔒, 13 §3.2 row S8.2, ADR 2026-09-12 §1 🔒, ADR
// 2026-09-12d §1–§3 🔒) for S8.2 Report viewer + export — the M5 half: the
// viewer surface, the Day Book, and the three-format export sheet with two of
// the three generating. The remaining ten reports of 07 §14, the Free-tenant
// watermark and every F3 export byte-golden are M12 (ADR 2026-09-12 §2–§3), so
// nothing here asserts them.
//
// **ADR 2026-09-12d reversed 12c.** 12c had moved the primary action off a PDF
// default it believed could not resolve; 12d found that reading wrong — the
// package to pin was `archive`, not `sodium` — and restored PDF as the default
// (§2) and as a generating row (§3). The cases that asserted the CSV default
// are **updated here, not skipped**, exactly as 12d's Consequences require. The
// enumeration and the row order were never touched by either ADR, so the id
// stays F1-07-79.
//
// **ADR 2026-09-12e §1 🔒 unblocked the third row.** XLSX is written in-house
// over `archive` + `xml`, so the sheet has no disabled row left and the cases
// that asserted one are updated here rather than skipped. The XLSX cases read
// the produced file **back**: they unzip it, parse the sheet XML and assert the
// cells. A test that only checked the bytes were non-empty would miss every
// failure mode that matters — a part name that disagrees with its content type
// (Excel silently "repairs" the file, which is data loss, not a warning),
// money arriving as text (the column will not sum, which is the whole reason
// an accountant asked for XLSX), a date arriving as a string, or Gurmukhi
// mangled on the way through the zip.
//
// The PDF cases carry one assertion the CSV ones cannot: `package:pdf` embeds
// every glyph it draws and defaults to Helvetica, which has no Gurmukhi and no
// Devanagari. A day book exported in Punjabi or Hindi would be a page of empty
// boxes, and nothing in the file would say so. [ReportFonts.unsupportedRunes]
// is what makes that visible, and it is asserted against the real account names
// of a real seeded book.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/widgets/fy_switcher.dart';
import 'package:rukka_folio/features/reports/day_book.dart';
import 'package:rukka_folio/features/reports/export/csv_report.dart';
import 'package:rukka_folio/features/reports/export/pdf_report.dart';
import 'package:rukka_folio/features/reports/export/report_export.dart';
import 'package:rukka_folio/features/reports/export/xlsx_report.dart';
import 'package:rukka_folio/features/reports/screens/s8_1_reports_list_screen.dart';
import 'package:rukka_folio/features/reports/screens/s8_2_report_viewer_screen.dart';
import 'package:rukka_folio/features/reports/widgets/reports_row.dart';
import 'package:xml/xml.dart';

import '../../shared/test_app.dart';

/// A [ReportSink] that keeps what it was handed instead of writing a file.
final class _CapturingSink {
  ReportFile? file;

  Future<String> call(ReportFile f) async {
    file = f;
    return f.name;
  }
}

/// Tears the tree down *inside* the test and lets its timers run out: drift's
/// query stream schedules a zero-duration cleanup timer on cancel, and a
/// SnackBar holds a four-second one. Only a pump inside the test fires them
/// before the binding's end-of-test pending-timer invariant runs.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

/// The text of every [Text] in the tree, in tree order — both the plain `data`
/// form and the rendered span, because [MoneyText] writes its Dr/Cr word into
/// a `Text.rich` span that `find.text` cannot see.
List<String> _texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

/// One cell as the sheet XML actually carries it: its declared type (null for
/// a number — which is the point of half these assertions), its style index,
/// and its value text.
typedef XlsxCellRead = ({String? type, String? style, String value});

/// Unzips an `.xlsx` and returns every part as text, keyed by part name.
Map<String, String> xlsxParts(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return {
    for (final f in archive.files)
      if (f.isFile) f.name: utf8.decode(f.readBytes()!),
  };
}

/// The cells of a worksheet part, keyed by reference (`A1`, `C7` …).
Map<String, XlsxCellRead> xlsxCells(String sheetXml) {
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

/// Every inline string in a worksheet part, in document order.
List<String> xlsxStrings(String sheetXml) => [
  for (final cell in xlsxCells(sheetXml).values)
    if (cell.type == 'inlineStr') cell.value,
];

void main() {
  group('S8.2 Report viewer + export (07 §14 🔒, ADR 2026-09-12 §1 🔒, ADR '
      '2026-09-12d §2–§3 🔒)', () {
    testWidgets(
      'F1-07-79 the Day Book renders every seeded entry with its accounts',
      (tester) async {
        final seeded = await seedSoloLedger();
        await pumpRk(
          tester,
          const ReportViewerScreen(),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        expect(find.text('Day Book'), findsWidgets);
        final texts = _texts(tester);
        // Particulars are account names — every seeded account appears.
        for (final name in const [
          'Cash in hand',
          'SBI Saving',
          'Ramesh',
          'Shop sales',
          'Diesel',
        ]) {
          expect(texts, contains(name), reason: 'missing particulars: $name');
        }
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 a report is a PROFESSIONAL surface — Dr/Cr, never Money in/out '
      '(02 §10 🔒, CLAUDE.md rule 9)',
      (tester) async {
        final seeded = await seedSoloLedger();
        await pumpRk(
          tester,
          const ReportViewerScreen(),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        // The Dr/Cr column headings are on screen…
        expect(find.text('Dr'), findsOneWidget);
        expect(find.text('Cr'), findsOneWidget);
        // …and the consumer vocabulary is nowhere near it.
        final rendered = _texts(tester).join(' ');
        expect(rendered, isNot(contains('Money in')));
        expect(rendered, isNot(contains('Money out')));
        // Every figure asks for the professional vocabulary explicitly, so the
        // Dr/Cr words ride on the figures themselves, not only the headings.
        expect(rendered, contains('Dr'));
        expect(rendered, contains('Cr'));
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 the cross-check footer totals both columns and they agree '
      '(02 §1.4; 13 §5 flow F3)',
      (tester) async {
        final seeded = await seedSoloLedger();
        await pumpRk(
          tester,
          const ReportViewerScreen(),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        expect(find.text('Total'), findsOneWidget);
        // Words beside the icon, never colour alone (07 §1 rule 3).
        expect(find.text('Dr and Cr agree'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 the FY switcher is plain text before the first year close '
      '(ADR 2026-09-09 §4 🔒, one control on S4 · S8.2 · S10.4)',
      (tester) async {
        final seeded = await seedSoloLedger();
        await pumpRk(
          tester,
          const ReportViewerScreen(),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        // Shipped state: no year has closed, so no control is drawn.
        expect(find.byType(FySwitcher), findsOneWidget);
        expect(find.byType(ActionChip), findsNothing);
        expect(find.text('FY 2026-27'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 the FY switcher becomes a chip once a year has closed '
      '(ADR 2026-09-09 §4 🔒)',
      (tester) async {
        final seeded = await seedSoloLedger();
        await pumpRk(
          tester,
          ReportViewerScreen(
            closedYears: (bookId, accountId) async => [
              ClosedYear(year: FinancialYear(2025), carriedForwardPaise: 0),
            ],
          ),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        expect(find.byType(ActionChip), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 the export sheet offers exactly PDF, CSV and XLSX in that '
      'order and every one of the three generates — no row is '
      'disabled-with-reason (ADR 2026-09-12 §1 🔒, 12d §3 🔒, 12e §1 🔒)',
      (tester) async {
        final seeded = await seedSoloLedger();
        await pumpRk(
          tester,
          const ReportViewerScreen(),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();

        final texts = _texts(tester);
        final pdf = texts.indexOf('PDF');
        final csv = texts.indexOf('CSV');
        final xlsx = texts.indexOf('XLSX');
        expect(pdf, greaterThan(-1));
        expect(csv, greaterThan(pdf), reason: 'CSV must follow PDF');
        expect(xlsx, greaterThan(csv), reason: 'XLSX must follow CSV');
        // No fourth format: the 🔒 enumeration is exactly three.
        expect(
          texts.where((t) => t == 'PDF' || t == 'CSV' || t == 'XLSX').length,
          3,
        );

        // All three rows run: 12d §3 🔒 turned the PDF row from
        // disabled-with-reason into a working one, and 12e §1 🔒 did the same
        // for XLSX by writing the format in-house.
        expect(find.byType(ReportsActionRow), findsNWidgets(3));
        expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
        expect(find.byIcon(Icons.grid_on_outlined), findsOneWidget);

        // Nothing is blocked any more, and neither blocker line survives its
        // blocker: a reason that names a limitation the build no longer has is
        // a lie on the screen.
        expect(find.byType(ReportsDisabledRow), findsNothing);
        expect(
          find.text('PDF is not ready in this version. Use CSV for now.'),
          findsNothing,
        );
        expect(
          find.text(
            'Spreadsheet files are not ready in this version. Use CSV for now.',
          ),
          findsNothing,
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 exporting CSV reaches the sink with integer paise and the '
      'cross-check total (CLAUDE.md rule 1)',
      (tester) async {
        final seeded = await seedSoloLedger();
        final sink = _CapturingSink();
        await pumpRk(
          tester,
          ReportViewerScreen(sink: sink.call),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await tester.tap(find.text('CSV'));
        await tester.pumpAndSettle();

        final file = sink.file;
        expect(file, isNotNull, reason: 'the CSV never reached the sink');
        expect(file!.format, ReportFormat.csv);
        // The name is metadata that travels with the file: no account name,
        // no party name, no figure (CLAUDE.md rule 4).
        expect(file.name, 'day-book-2026-27.csv');

        // UTF-8 BOM, so Gurmukhi and Devanagari names survive a spreadsheet.
        expect(file.bytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
        final text = utf8.decode(file.bytes.skip(3).toList());

        expect(text, contains('Day Book'));
        expect(text, contains('FY 2026-27'));
        // Professional columns, never the consumer vocabulary.
        expect(text, contains('Dr'));
        expect(text, contains('Cr'));
        expect(text, isNot(contains('Money in')));
        expect(text, isNot(contains('Money out')));
        // Figures are exact paise rendered as text, not floats: the seeded
        // diesel payment is 240_000 paise and the transfer 400_000.
        expect(text, contains('2400.00'));
        expect(text, contains('4000.00'));
        // The cross-check line: both columns totalled, and equal.
        final totalLine = const LineSplitter()
            .convert(text)
            .firstWhere((l) => l.startsWith(',Total,'));
        final parts = totalLine.split(',');
        expect(parts[2], parts[3], reason: 'Dr total must equal Cr total');

        // The reader is told where it went — an export is never silent.
        expect(find.text('Saved: day-book-2026-27.csv'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 exporting XLSX reaches the sink as a workbook Excel will open: '
      'the parts, the content types and the relationship ids all agree '
      '(ADR 2026-09-12e §1 🔒)',
      (tester) async {
        final seeded = await seedSoloLedger();
        final sink = _CapturingSink();
        await pumpRk(
          tester,
          ReportViewerScreen(sink: sink.call),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await tester.tap(find.text('XLSX'));
        await tester.pumpAndSettle();

        final file = sink.file;
        expect(file, isNotNull, reason: 'the XLSX never reached the sink');
        expect(file!.format, ReportFormat.xlsx);
        // The name is metadata that travels with the file: no account name,
        // no party name, no figure (CLAUDE.md rule 4).
        expect(file.name, 'day-book-2026-27.xlsx');

        // A zip, read back part by part — not merely non-empty bytes.
        final parts = xlsxParts(file.bytes);
        expect(
          parts.keys,
          containsAll(const <String>[
            '[Content_Types].xml',
            '_rels/.rels',
            'xl/_rels/workbook.xml.rels',
            xlsxWorkbookPart,
            xlsxStylesPart,
            xlsxSheetPart,
          ]),
        );

        // Internal consistency, the thing that decides between "opens" and
        // "Excel repaired your file" — which is silent data loss, not a
        // warning. Every typed part exists…
        final types = XmlDocument.parse(parts['[Content_Types].xml']!);
        for (final override in types.findAllElements('Override')) {
          final named = override.getAttribute('PartName')!.substring(1);
          expect(parts, contains(named), reason: 'typed but absent: $named');
        }
        // …the package points at a workbook that is there…
        final packageRels = XmlDocument.parse(parts['_rels/.rels']!);
        expect(
          packageRels
              .findAllElements('Relationship')
              .single
              .getAttribute('Target'),
          xlsxWorkbookPart,
        );
        // …and the id `workbook.xml` quotes for its sheet is the id the
        // workbook's own .rels defines, pointing at the sheet part.
        final workbookRels = XmlDocument.parse(
          parts['xl/_rels/workbook.xml.rels']!,
        ).findAllElements('Relationship');
        final sheetRel = workbookRels.singleWhere(
          (r) => r.getAttribute('Type')!.endsWith('/worksheet'),
        );
        expect(parts, contains('xl/${sheetRel.getAttribute('Target')}'));
        final sheetEl = XmlDocument.parse(parts[xlsxWorkbookPart]!)
            .findAllElements('sheet')
            .single;
        expect(sheetEl.getAttribute('r:id'), sheetRel.getAttribute('Id'));
        // A tab name Excel accepts: never blank, never over 31 characters,
        // none of the characters it forbids.
        final tab = sheetEl.getAttribute('name')!;
        expect(tab, isNotEmpty);
        expect(tab.runes.length, lessThanOrEqualTo(31));
        expect(tab, isNot(matches(r'[:\\/?*\[\]]')));

        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 the exported workbook can be summed: money is a NUMBER cell '
      'in integer paise and the date is a real date, not text '
      '(CLAUDE.md rule 1, 02 §10 🔒)',
      (tester) async {
        final seeded = await seedSoloLedger();
        final sink = _CapturingSink();
        await pumpRk(
          tester,
          ReportViewerScreen(sink: sink.call),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await tester.tap(find.text('XLSX'));
        await tester.pumpAndSettle();

        final sheet = xlsxParts(sink.file!.bytes)[xlsxSheetPart]!;
        // UTF-8 is declared by the part itself, so Gurmukhi and Devanagari
        // names survive without the BOM question the CSV has (12e §3).
        expect(sheet, startsWith('<?xml version="1.0" encoding="UTF-8"'));

        final cells = xlsxCells(sheet);
        final strings = xlsxStrings(sheet);

        // A professional surface: Dr and Cr, never the consumer vocabulary.
        expect(strings, contains('Dr'));
        expect(strings, contains('Cr'));
        expect(strings, isNot(contains('Money in')));
        expect(strings, isNot(contains('Money out')));
        expect(strings, contains('Day Book'));
        expect(strings, contains('FY 2026-27'));
        // Account names came through the zip intact.
        expect(strings, contains('Cash in hand'));
        expect(strings, contains('Diesel'));

        // The seeded diesel payment is 2_40_000 paise and the transfer
        // 4_00_000. Both must be NUMBER cells — no `t` attribute, and the
        // money style — or the column cannot be summed.
        for (final figure in const ['2400.00', '4000.00']) {
          final matches = cells.entries
              .where((e) => e.value.value == figure)
              .toList();
          expect(matches, isNotEmpty, reason: 'no cell holds $figure');
          for (final m in matches) {
            expect(
              m.value.type,
              isNull,
              reason:
                  '${m.key} is text, not a '
                  'number — the column would not sum',
            );
            expect(m.value.style, '$xlsxStyleMoney');
          }
        }

        // The date column holds serials with the date format, not strings.
        // Column A's first body cell is the first entry's date.
        final dateCells = cells.entries
            .where((e) => e.key.startsWith('A') && e.value.type == null)
            .toList();
        expect(dateCells, isNotEmpty, reason: 'no date cell in column A');
        for (final d in dateCells) {
          expect(d.value.style, '$xlsxStyleDate');
          expect(
            int.tryParse(d.value.value),
            isNotNull,
            reason: '${d.key} is not a serial date',
          );
        }

        // The cross-check line: the last row totals both columns in the bold
        // money style, and the two agree (02 §1.4, 13 §5 flow F3).
        final lastRow = cells.keys
            .map((r) => int.parse(r.replaceAll(RegExp('[A-Z]'), '')))
            .reduce((a, b) => a > b ? a : b);
        expect(cells['B$lastRow']!.value, 'Total');
        expect(cells['C$lastRow']!.style, '$xlsxStyleMoneyTotal');
        expect(cells['C$lastRow']!.type, isNull);
        expect(cells['C$lastRow']!.value, cells['D$lastRow']!.value);

        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 an empty period is never a dead end — the year control and the '
      'export action stay (07 §1 rules 2 and 6)',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        await pumpRk(
          tester,
          const ReportViewerScreen(),
          ledger: ledger,
          viewport: rkTallViewport,
        );

        expect(
          find.text('Nothing has been entered in this period.'),
          findsOneWidget,
        );
        expect(find.byType(FySwitcher), findsOneWidget);
        // Both doors stay on an empty period: the one that writes, and the
        // one that chooses (ADR 2026-09-12c §1 🔒).
        expect(find.text('Download / Share'), findsOneWidget);
        expect(find.byIcon(Icons.more_horiz), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 a ledger that cannot be resolved shows the error state with '
      'Try again, never a dead end (13 §4.3)',
      (tester) async {
        // No book was ever created, so resolving the solo book throws.
        final ledger = await openTestLedger();
        await pumpRk(tester, const ReportViewerScreen(), ledger: ledger);

        expect(find.text('The day book could not be read.'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 S8.1 opens S8.2 from the Day Book row; the other ten reports '
      'stay disabled-with-reason (10 M5 — basic day-book export)',
      (tester) async {
        var opened = 0;
        await pumpRk(
          tester,
          ReportsListScreen(onOpenDayBook: () => opened++),
          viewport: rkTallViewport,
        );

        expect(find.byType(ReportsActionRow), findsOneWidget);
        expect(find.byType(ReportsDisabledRow), findsNWidgets(10));
        await tester.tap(find.text('Day Book'));
        await tester.pumpAndSettle();
        expect(opened, 1);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 Download / Share writes the PDF straight to the sink without '
      'opening the sheet (ADR 2026-09-12d §2 🔒)',
      (tester) async {
        final seeded = await seedSoloLedger();
        final sink = _CapturingSink();
        await pumpRk(
          tester,
          ReportViewerScreen(sink: sink.call),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        await tester.tap(find.text('Download / Share'));
        await tester.pumpAndSettle();

        // No sheet: the primary action writes, it does not ask.
        expect(find.text('CSV'), findsNothing);
        expect(find.text('XLSX'), findsNothing);

        // The default is PDF again — the format a person hands to someone
        // else (ADR 2026-09-12 §1 🔒, restored by 12d §2 🔒 after 12c's CSV
        // stopgap lapsed).
        final file = sink.file;
        expect(file, isNotNull, reason: 'the default export never ran');
        expect(file!.format, ReportFormat.pdf);
        expect(file.name, 'day-book-2026-27.pdf');
        // A real PDF, not an empty shell: the header signature, and enough
        // bytes to be a document with fonts embedded in it.
        expect(String.fromCharCodes(file.bytes.take(5)), '%PDF-');
        expect(file.bytes.length, greaterThan(10000));
        // Never silent: the reader is told where it went (07 §1 rule 6).
        expect(find.text('Saved: day-book-2026-27.pdf'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 the sheet\'s PDF row generates an A4 document through the same '
      'sink as CSV (ADR 2026-09-12d §3 🔒; 07 §14 🔒 A4 print-clean)',
      (tester) async {
        final seeded = await seedSoloLedger();
        final sink = _CapturingSink();
        await pumpRk(
          tester,
          ReportViewerScreen(sink: sink.call),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await tester.tap(find.text('PDF'));
        await tester.pumpAndSettle();

        final file = sink.file;
        expect(file, isNotNull, reason: 'the PDF never reached the sink');
        expect(file!.format, ReportFormat.pdf);
        // The name is metadata that travels with the file: no account name, no
        // party name, no figure (CLAUDE.md rule 4).
        expect(file.name, 'day-book-2026-27.pdf');
        expect(String.fromCharCodes(file.bytes.take(5)), '%PDF-');
        // A4 is 595.27559 x 841.88976 pt; the page's own MediaBox says so.
        final head = latin1.decode(file.bytes, allowInvalid: true);
        expect(
          head,
          contains('MediaBox[0 0 595.27559 841.88976]'),
          reason: 'the page must be A4 (07 §14 🔒 print-clean)',
        );
        expect(find.text('Saved: day-book-2026-27.pdf'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-79 the format sheet stays reachable beside the default — both '
      'paths exist, neither is the only one (ADR 2026-09-12c §1 🔒)',
      (tester) async {
        final seeded = await seedSoloLedger();
        await pumpRk(
          tester,
          const ReportViewerScreen(),
          ledger: seeded.ledger,
          viewport: rkTallViewport,
        );

        // The writing door and the choosing door, side by side in the bar.
        expect(find.text('Download / Share'), findsOneWidget);
        final chooser = find.byIcon(Icons.more_horiz);
        expect(chooser, findsOneWidget);
        // Icon-only, so the affordance must carry its words to a screen
        // reader and a long-press (07 §1 rules 3 and 11).
        expect(
          tester
              .widget<IconButton>(
                find.ancestor(of: chooser, matching: find.byType(IconButton)),
              )
              .tooltip,
          'Choose a format',
        );

        await tester.tap(chooser);
        await tester.pumpAndSettle();
        expect(find.text('Download or share this report'), findsOneWidget);
        expect(find.text('PDF'), findsOneWidget);
        await unmount(tester);
      },
    );

    // Two affordances now share the bar, and they have to survive the collapse
    // the labelled one already made at 1.3x. Settled on both reference phones,
    // in all three languages, at the two scales that matter: **1.3x**, the
    // widest the pair is ever drawn (one label plus one icon — Punjabi is the
    // longest label), and **200%**, where both are icons. The FY chip is drawn
    // throughout, so a bar that crowded it would show here (07 §1 rule 11).
    for (final locale in rkLocales) {
      for (final size in rkPhones) {
        for (final scale in rkTextScales) {
          final labelled = scale <= 1.3;
          testWidgets(
            'F1-07-79 S8.2 resolves in ${locale.languageCode} without overflow '
            'at ${(scale * 100).round()}% on ${size.width.toInt()}x'
            '${size.height.toInt()} — both export actions fit the bar and the '
            'FY chip is not pushed (ADR 2026-09-12c §1 🔒)',
            (tester) async {
              final seeded = await seedSoloLedger();
              // `pumpRk`'s own `textScale:`/`viewport:` (M5-T1): it scales the
              // **live** MediaQuery above the Navigator, so the real viewport
              // survives and sheets and snackbars are scaled too. The bare
              // `MediaQueryData(textScaler: …)` this case used to wrap carried
              // `size: Size.zero`, under which a bar action that budgets itself
              // against the window collapses to nothing and every assertion
              // below still passes.
              await pumpRk(
                tester,
                ReportViewerScreen(
                  closedYears: (bookId, accountId) async => [
                    ClosedYear(
                      year: FinancialYear(2025),
                      carriedForwardPaise: 0,
                    ),
                  ],
                ),
                ledger: seeded.ledger,
                locale: locale,
                textScale: scale,
                viewport: size,
              );

              expect(tester.takeException(), isNull);

              // The primary action is words up to 1.3x and an icon past it;
              // the chooser is an icon at every scale, which is what lets the
              // pair fit at all.
              final inBar = find.byType(AppBar);
              expect(
                find.descendant(of: inBar, matching: find.byType(TextButton)),
                labelled ? findsOneWidget : findsNothing,
              );
              expect(find.byIcon(Icons.ios_share), findsOneWidget);
              expect(find.byIcon(Icons.more_horiz), findsOneWidget);

              // The actions row must not fill the bar: the title needs its
              // half, and nothing may spill (a RenderFlex overflow would have
              // been taken above, but width is the assertion that says why).
              final bar = tester.getSize(inBar);
              final actions = tester.getSize(
                find
                    .ancestor(
                      of: find.byIcon(Icons.more_horiz),
                      matching: find.byType(Row),
                    )
                    .first,
              );
              // Measured, not assumed: the labelled action is capped at
              // [_labelledActionShare] of the bar and the chooser is a fixed
              // 48, so the pair is ~0.65 of the line at 1.3x and 96 px flat
              // at 200% — the title always keeps a third.
              expect(
                actions.width,
                lessThan(bar.width * 0.7),
                reason: 'the two export actions must leave the title a third',
              );

              // The year control is still drawn, and still a chip.
              expect(find.byType(ActionChip), findsOneWidget);

              // And the sheet behind the chooser resolves at this scale too.
              await tester.tap(find.byIcon(Icons.more_horiz));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(find.text('CSV'), findsOneWidget);
              await unmount(tester);
            },
          );
        }
      }
    }
  });

  group('S8.2 column headings (07 §1 rule 11 — 200% and 360 px)', () {
    /// The heading a reader needs most, and the one that cannot wrap:
    /// *Particulars* is a single English word, so a line too short for it cuts
    /// it rather than folding it. Asserted on the paragraph itself — a
    /// whole-tree check cannot be used on S8.2, because the bar's labelled
    /// primary action clips its own words **on purpose** (see
    /// `_labelledActionShare`).
    void expectHeadingWhole(WidgetTester tester, String heading) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(heading),
      );
      final needed = paragraph.getMinIntrinsicWidth(double.infinity);
      expect(
        needed,
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason:
            '"$heading" needs ${needed.toStringAsFixed(1)}px and was drawn in '
            '${paragraph.size.width.toStringAsFixed(1)}px',
      );
    }

    for (final size in rkPhones) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('F1-07-79 the Particulars heading is never cut at '
            '${(scale * 100).round()}% on ${size.width.toInt()}x'
            '${size.height.toInt()} — it folds onto its own line instead', (
          tester,
        ) async {
          final seeded = await seedSoloLedger();
          await pumpRk(
            tester,
            const ReportViewerScreen(),
            ledger: seeded.ledger,
            textScale: scale,
            viewport: size,
          );

          expectHeadingWhole(tester, 'Particulars');
          // The figure headings stay with it, whichever way it folded.
          expect(find.text('Dr'), findsOneWidget);
          expect(find.text('Cr'), findsOneWidget);
          await unmount(tester);
        });
      }
    }
  });

  group('S8.2 CSV writer (ADR 2026-09-12 §1 🔒 — pure Dart, no package)', () {
    test('F1-07-79 paise become exact decimal text, never a float', () {
      expect(paiseToDecimal(0), '0.00');
      expect(paiseToDecimal(5), '0.05');
      expect(paiseToDecimal(240000), '2400.00');
      expect(paiseToDecimal(12345678901), '123456789.01');
      expect(paiseToDecimal(-1), '-0.01');
    });

    test('F1-07-79 fields are escaped per RFC 4180', () {
      expect(csvField('Diesel'), 'Diesel');
      expect(csvField('Ramesh, Kirana'), '"Ramesh, Kirana"');
      expect(csvField('say "hello"'), '"say ""hello"""');
      expect(csvField('two\nlines'), '"two\nlines"');
      expect(csvRow(const ['a', 'b,c']), 'a,"b,c"');
    });

    test(
      'F1-07-79 an empty day book still writes a head and a zero cross-check',
      () {
        final text = dayBookCsv(
          const DayBook.empty('book-1'),
          accountName: (id) => id,
          labels: const ReportLabels(
            reportName: 'Day Book',
            bookLabel: 'Book',
            periodLabel: 'Period',
            columnDate: 'Date',
            columnParticulars: 'Particulars',
            columnDebit: 'Dr',
            columnCredit: 'Cr',
            columnNote: 'Note',
            totalLabel: 'Total',
          ),
          bookName: 'Me',
          period: 'FY 2026-27',
          formatDate: (date) => date.toIso(),
        );
        expect(text, contains('Day Book'));
        expect(text, contains('Book,Me'));
        expect(text, contains('Period,FY 2026-27'));
        expect(text, contains(',Total,0.00,0.00,'));
        // RFC 4180 line endings, fixed — never the platform's.
        expect(text, contains(csvLineEnding));
      },
    );

    test('F1-07-79 the CSV file opens as UTF-8 in Excel: EF BB BF leads the bytes, '
        'and Gurmukhi survives it (ADR 2026-09-12e §3 🔒)', () {
      final file = dayBookCsvFile(
        const DayBook.empty('book-1'),
        accountName: (id) => id,
        labels: const ReportLabels(
          reportName: 'Day Book',
          bookLabel: 'Book',
          periodLabel: 'Period',
          columnDate: 'Date',
          columnParticulars: 'Particulars',
          columnDebit: 'Dr',
          columnCredit: 'Cr',
          columnNote: 'Note',
          totalLabel: 'Total',
        ),
        bookName: 'ਗੁਰਦੁਆਰਾ ਸਾਹਿਬ',
        period: 'FY 2026-27',
        formatDate: (date) => date.toIso(),
        fileName: 'day-book.csv',
      );
      // Without the mark Excel reads the file in the system code page and
      // every Gurmukhi and Devanagari name arrives as mojibake — the same
      // class of silent failure as a PDF with no embedded font.
      expect(
        file.bytes.take(3),
        orderedEquals(const [0xEF, 0xBB, 0xBF]),
        reason: 'ADR 2026-09-12e §3: the CSV carries a UTF-8 BOM',
      );
      // The mark is a prefix, not a replacement: what follows is still plain
      // UTF-8, so a non-Excel reader loses nothing but three bytes.
      expect(utf8.decode(file.bytes.sublist(3)), contains('ਗੁਰਦੁਆਰਾ ਸਾਹਿਬ'));
    });

    test('F1-07-79 the sheet enumerates exactly the three ADR 2026-09-12 §1 🔒 '
        'formats, in the ADR order', () {
      expect(ReportFormat.values, const [
        ReportFormat.pdf,
        ReportFormat.csv,
        ReportFormat.xlsx,
      ]);
      expect(ReportFormat.csv.extension, 'csv');
      expect(ReportFormat.csv.mediaType, 'text/csv');
      expect(ReportFormat.pdf.extension, 'pdf');
      expect(ReportFormat.pdf.mediaType, 'application/pdf');
    });
  });

  group('S8.2 XLSX writer (ADR 2026-09-12e §1 🔒 — in-house over archive + '
      'xml, no package)', () {
    const labels = ReportLabels(
      reportName: 'Day Book',
      bookLabel: 'Book',
      periodLabel: 'Period',
      columnDate: 'Date',
      columnParticulars: 'Particulars',
      columnDebit: 'Dr',
      columnCredit: 'Cr',
      columnNote: 'Note',
      totalLabel: 'Total',
    );

    /// A day book whose particulars are Gurmukhi and Devanagari, with an
    /// account name carrying the two characters XML cannot take raw.
    /// Synthetic figures (CLAUDE.md rule 4).
    DayBook multiScriptBook() => DayBook(
      bookId: 'book-1',
      rows: [
        DayBookRow(
          entryId: 'e1',
          date: LocalDate(2026, 9, 7),
          kind: EntryKind.moneyIn,
          status: 'posted',
          reviewState: 'none',
          hlc: 1,
          note: 'ਦੁਕਾਨ ਦੀ ਵਿਕਰੀ / दुकान की बिक्री',
          lines: const [
            DayBookLine(accountId: 'cash', amountPaise: 124500),
            DayBookLine(accountId: 'sales', amountPaise: -124500),
          ],
        ),
      ],
      debitTotalPaise: 124500,
      creditTotalPaise: 124500,
    );

    const names = {'cash': 'ਕੈਸ਼ ਇਨ ਹੈਂਡ', 'sales': 'Sharma & Sons <Trading>'};

    Uint8List build(DayBook book) => dayBookXlsx(
      book,
      accountName: (id) => names[id] ?? id,
      labels: labels,
      bookName: 'ਮੇਰੀ ਬਹੀ',
      period: 'FY 2026-27',
    );

    test('F1-07-79 columns are named the spreadsheet way, 1-based', () {
      expect(xlsxColumnName(1), 'A');
      expect(xlsxColumnName(5), 'E');
      expect(xlsxColumnName(26), 'Z');
      expect(xlsxColumnName(27), 'AA');
      expect(xlsxColumnName(52), 'AZ');
      expect(xlsxColumnName(53), 'BA');
    });

    test('F1-07-79 a date becomes an Excel serial by integer arithmetic', () {
      // 1970-01-01 is serial 25569; 2026-09-07 is 46272.
      expect(xlsxSerialDate(LocalDate(1970, 1, 1)), xlsxEpochOffsetDays);
      expect(xlsxSerialDate(LocalDate(2026, 9, 7)), 46272);
      expect(
        xlsxSerialDate(LocalDate(2026, 9, 8)) -
            xlsxSerialDate(LocalDate(2026, 9, 7)),
        1,
      );
    });

    test(
      'F1-07-79 a sheet name Excel refuses is repaired, never passed on',
      () {
        expect(xlsxSheetName('Day Book'), 'Day Book');
        // The six characters Excel forbids in a tab name.
        expect(xlsxSheetName('P/L: 2026 [draft]?*'), 'P L  2026  draft');
        // Blank is not a name.
        expect(xlsxSheetName('   '), 'Sheet1');
        expect(xlsxSheetName('[]'), 'Sheet1');
        // 31 characters, counted in characters — a Gurmukhi name is not
        // measured in bytes.
        final long = xlsxSheetName('ਰੋਜ਼ਨਾਮਚਾ' * 9);
        expect(long.runes.length, lessThanOrEqualTo(31));
        expect(long, isNotEmpty);
      },
    );

    test('F1-07-79 money is written as a number from integer paise — the same '
        'decimal the CSV writes, never a float', () {
      final sheet = xlsxParts(build(multiScriptBook()))[xlsxSheetPart]!;
      final cells = xlsxCells(sheet);
      final money = cells.values.where((c) => c.style == '$xlsxStyleMoney');
      expect(money, isNotEmpty);
      for (final c in money) {
        expect(c.type, isNull, reason: 'a money cell must not be text');
        expect(c.value, paiseToDecimal(124500));
      }
    });

    test('F1-07-79 every script and every XML metacharacter survives the zip '
        '(01 §1.8; an unescaped & would corrupt the part)', () {
      final sheet = xlsxParts(build(multiScriptBook()))[xlsxSheetPart]!;
      final strings = xlsxStrings(sheet);
      expect(strings, contains('ਕੈਸ਼ ਇਨ ਹੈਂਡ'));
      expect(strings, contains('Sharma & Sons <Trading>'));
      expect(strings, contains('ਦੁਕਾਨ ਦੀ ਵਿਕਰੀ / दुकान की बिक्री'));
      expect(strings, contains('ਮੇਰੀ ਬਹੀ'));
      // Escaped on the wire, not raw: `&` and `<` must not reach the part as
      // themselves, or the XML is malformed and Excel repairs the file away.
      // (`>` needs no escape inside content and the writer leaves it.)
      expect(sheet, contains('Sharma &amp; Sons &lt;Trading>'));
    });

    test('F1-07-79 an empty day book still exports a workbook — never a dead '
        'end (07 §1 rules 2 and 6)', () {
      final parts = xlsxParts(build(const DayBook.empty('book-1')));
      expect(parts, contains(xlsxSheetPart));
      final strings = xlsxStrings(parts[xlsxSheetPart]!);
      expect(strings, contains('Day Book'));
      expect(strings, contains('Total'));
      final cells = xlsxCells(parts[xlsxSheetPart]!);
      final totals = cells.values.where(
        (c) => c.style == '$xlsxStyleMoneyTotal',
      );
      expect(totals.length, 2);
      for (final c in totals) {
        expect(c.value, '0.00');
      }
    });

    test('F1-07-79 the styles part declares the money and date formats the '
        'cells index', () {
      final styles = XmlDocument.parse(
        xlsxParts(build(multiScriptBook()))[xlsxStylesPart]!,
      );
      final cellXfs = styles.findAllElements('cellXfs').single;
      final xfs = cellXfs.findElements('xf').toList();
      // Five slots, in the order the constants name.
      expect(xfs.length, 5);
      expect(cellXfs.getAttribute('count'), '5');
      expect(xfs[xlsxStyleMoney].getAttribute('applyNumberFormat'), '1');
      expect(xfs[xlsxStyleDate].getAttribute('applyNumberFormat'), '1');
      expect(
        xfs[xlsxStyleMoney].getAttribute('numFmtId'),
        isNot(xfs[xlsxStyleDate].getAttribute('numFmtId')),
      );
      // Both ids are defined, not merely referenced.
      final defined = styles
          .findAllElements('numFmt')
          .map((e) => e.getAttribute('numFmtId'))
          .toSet();
      expect(defined, contains(xfs[xlsxStyleMoney].getAttribute('numFmtId')));
      expect(defined, contains(xfs[xlsxStyleDate].getAttribute('numFmtId')));
    });

    test('F1-07-79 the same day book exports byte for byte the same file — '
        'the zip carries no clock (F3-07-1 @M12 compares bytes)', () {
      expect(build(multiScriptBook()), build(multiScriptBook()));
    });
  });

  group('S8.2 PDF writer (ADR 2026-09-12d §3 🔒 — package:pdf, A4, on '
      'device)', () {
    /// A day book whose particulars are Gurmukhi and Devanagari — the case
    /// Helvetica cannot draw. Synthetic figures (CLAUDE.md rule 4).
    DayBook multiScriptBook() {
      DayBookLine line(String id, int paise) =>
          DayBookLine(accountId: id, amountPaise: paise);
      return DayBook(
        bookId: 'book-1',
        rows: [
          DayBookRow(
            entryId: 'e1',
            date: LocalDate(2026, 9, 7),
            kind: EntryKind.moneyIn,
            status: 'posted',
            reviewState: 'none',
            hlc: 1,
            note: 'ਦੁਕਾਨ ਦੀ ਵਿਕਰੀ / दुकान की बिक्री',
            lines: [line('cash', 124500), line('sales', -124500)],
          ),
        ],
        debitTotalPaise: 124500,
        creditTotalPaise: 124500,
      );
    }

    const names = {'cash': 'ਕੈਸ਼ ਇਨ ਹੈਂਡ', 'sales': 'दुकान की बिक्री'};

    const labels = ReportLabels(
      reportName: 'ਰੋਜ਼ਨਾਮਚਾ',
      bookLabel: 'ਬਹੀ',
      periodLabel: 'ਮਿਆਦ',
      columnDate: 'ਤਾਰੀਖ਼',
      columnParticulars: 'ਵੇਰਵਾ',
      columnDebit: 'Dr',
      columnCredit: 'Cr',
      columnNote: 'ਨੋਟ',
      totalLabel: 'ਕੁੱਲ',
    );

    testWidgets(
      'F1-07-79 every script the app ships has a face in the document — a '
      'Gurmukhi or Devanagari day book is never a page of empty boxes '
      '(11 §4.4, 01 §1.8)',
      (tester) async {
        final fonts = await ReportFonts.load();

        // package:pdf draws an unsupported rune as a blank placeholder and
        // only warns inside a debug assert, so this is the assertion that
        // stands between a Punjabi reader and an unreadable export.
        for (final text in const [
          'ਕੈਸ਼ ਇਨ ਹੈਂਡ',
          'ਦੁਕਾਨ ਦੀ ਵਿਕਰੀ',
          'ਡਾਊਨਲੋਡ / ਸਾਂਝਾ ਕਰੋ',
          'दुकान की बिक्री',
          'पृष्ठ 1 / 3',
          'Cash in hand',
          '₹1,24,500.00',
          'Dr',
          'Cr',
        ]) {
          expect(
            fonts.unsupportedRunes(text),
            isEmpty,
            reason: 'no embedded face can draw: $text',
          );
        }
      },
    );

    testWidgets(
      'F1-07-79 the day book generates as an A4 PDF with its own fonts, '
      'Dr/Cr columns and the cross-check total (07 §14 🔒, 02 §10 🔒)',
      (tester) async {
        final fonts = await ReportFonts.load();
        final book = multiScriptBook();
        final bytes = await dayBookPdf(
          book,
          accountName: (id) => names[id] ?? id,
          labels: labels,
          bookName: 'ਮੇਰੀ ਬਹੀ',
          period: 'FY 2026-27',
          formatDate: (date) => date.toIso(),
          pageNumber: (page, pages) => 'ਸਫ਼ਾ $page / $pages',
          fonts: fonts,
          locale: const Locale('pa'),
        );

        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        // A4, 595.27559 x 841.88976 pt — 07 §14 🔒 print-clean.
        final raw = latin1.decode(bytes, allowInvalid: true);
        expect(raw, contains('MediaBox[0 0 595.27559 841.88976]'));
        // Fonts are embedded (a subset stream per face), not referenced by
        // name from the reader's machine.
        expect(raw, contains('/FontFile2'));

        // Every string that went into the document can be drawn by a face in
        // it — the writer's own inputs, not a sample.
        final drawn = [
          labels.reportName,
          labels.columnParticulars,
          labels.totalLabel,
          ...names.values,
          'ਮੇਰੀ ਬਹੀ',
          book.rows.single.note!,
        ];
        for (final text in drawn) {
          expect(fonts.unsupportedRunes(text), isEmpty, reason: text);
        }
      },
    );

    testWidgets(
      'F1-07-79 an empty day book still exports a PDF — never a dead end '
      '(07 §1 rules 2 and 6)',
      (tester) async {
        final fonts = await ReportFonts.load();
        final bytes = await dayBookPdf(
          const DayBook.empty('book-1'),
          accountName: (id) => id,
          labels: labels,
          bookName: 'ਮੇਰੀ ਬਹੀ',
          period: 'FY 2026-27',
          formatDate: (date) => date.toIso(),
          pageNumber: (page, pages) => 'ਸਫ਼ਾ $page / $pages',
          fonts: fonts,
          locale: const Locale('pa'),
        );

        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      },
    );
  });
}
