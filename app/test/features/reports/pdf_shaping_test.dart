// F1-183-1x — desk 183 (c): the report PDF shapes Punjabi and Hindi.
//
// `package:pdf` embeds Mukta / Mukta Mahee (F1-07-79 proves no rune falls
// through them) but does not *shape* Indic scripts: set as PDF text, a
// Gurmukhi or Devanagari line prints with its pre-base vowel after the
// consonant and its nukta adrift. The report writer therefore hands every such
// run to the engine (`shared/pdf_shaping.dart`, the recovery sheet's helper)
// and places it as an image; Latin runs stay vector text.
//
// Test honesty: each test asserts the **route** — which strings the shaper
// rasterised, and that the document carries image objects — and its control
// (the same table with no shaper, or an English table) shows the opposite, so
// a writer that silently dropped back to text would fail here.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/screens/s4_account_statement_screen.dart';
import 'package:rukka_folio/features/reports/day_book.dart';
import 'package:rukka_folio/features/reports/export/pdf_report.dart';
import 'package:rukka_folio/features/reports/export/report_export.dart';
import 'package:rukka_folio/features/reports/export/report_table.dart';
import 'package:rukka_folio/features/reports/screens/s8_2_report_viewer_screen.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/pdf_shaping.dart';

import '../../shared/design_capture.dart' show rkLoadDesignFonts;
import '../../shared/test_app.dart';

const _pa = 'ਦੁਕਾਨ ਦੀ ਵਿਕਰੀ';
const _hi = 'दुकान की बिक्री';
const _en = 'Cash in hand';

ReportTable _table(List<String> particulars, {String name = 'Day Book'}) =>
    ReportTable(
      name: name,
      meta: const [ReportMetaLine('Period', 'FY 2026-27')],
      columns: const [
        ReportColumn('Particulars'),
        ReportColumn('Dr', align: ReportAlign.end, width: ReportFixedWidth(80)),
      ],
      rows: [
        for (final p in particulars)
          ReportRow([ReportTextCell(p), const ReportMoneyCell(1_250_00)]),
      ],
    );

/// How many drawn images the document carries. A shaped line is a PNG with
/// alpha, which `package:pdf` writes as a colour image plus its soft mask —
/// so the colour images are the ones that name an `/SMask`.
int _images(Uint8List bytes) =>
    RegExp(r'/SMask\s+\d+\s+0\s+R')
        .allMatches(latin1.decode(bytes, allowInvalid: true))
        .length;

/// What each drawn image holds: its soft mask — the shaped line's alpha, one
/// byte a pixel — read back out of the PDF. An `/SMask` is written for every
/// PNG whatever it holds, so [_images] alone would pass a blank image
/// (REP183C review finding 2); this looks at the ink.
typedef _Ink = ({int width, int height, int inked, int left});

List<_Ink> _inks(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final out = <_Ink>[];
  for (final ref in RegExp(r'/SMask\s+(\d+)\s+0\s+R').allMatches(text)) {
    final obj = RegExp('(?<![0-9])${ref.group(1)} 0 obj').firstMatch(text);
    expect(obj, isNotNull, reason: 'soft mask ${ref.group(1)} is not written');
    final streamAt = text.indexOf('stream\n', obj!.end);
    final dict = text.substring(obj.end, streamAt);
    int field(String name) =>
        int.parse(RegExp('/$name\\s+(\\d+)').firstMatch(dict)!.group(1)!);
    final width = field('Width');
    final height = field('Height');
    final start = streamAt + 'stream\n'.length;
    final raw = bytes.sublist(start, start + field('Length'));
    final alpha = dict.contains('/FlateDecode') ? zlib.decode(raw) : raw;
    expect(alpha.length, width * height, reason: 'a soft mask is 8-bit grey');
    var inked = 0;
    var left = width;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (alpha[y * width + x] > 0) {
          inked++;
          if (x < left) left = x;
        }
      }
    }
    out.add((width: width, height: height, inked: inked, left: left));
  }
  return out;
}

/// Every drawn image carries ink, and the ink starts at the image's left
/// edge — the right-aligned route shifts its paragraph back by the line's
/// own left (pdf_shaping.dart); without that shift the ink lands past the
/// image and the image is blank.
void _expectInked(Uint8List bytes, {String reason = ''}) {
  final inks = _inks(bytes);
  for (final ink in inks) {
    expect(
      ink.inked,
      greaterThan(ink.width * ink.height ~/ 50),
      reason: 'a drawn line is blank ($reason ${ink.width}x${ink.height})',
    );
    expect(
      ink.left,
      lessThanOrEqualTo((2 * pdfShapingRasterScale).ceil()),
      reason: "a drawn line's ink starts ${ink.left} px in ($reason)",
    );
  }
}

String _page(int page, int pages) => 'Page $page of $pages';

Future<Uint8List> _pdf(
  WidgetTester tester,
  ReportTable table, {
  PdfLineShaper? shaper,
  String Function(int, int) pageNumber = _page,
}) async {
  final fonts = (await tester.runAsync(ReportFonts.load))!;
  return (await tester.runAsync(
    () => reportTablePdf(
      table,
      pageNumber: pageNumber,
      fonts: fonts,
      locale: const Locale('pa'),
      shaper: shaper,
    ),
  ))!;
}

/// A [ReportSink] that keeps the file it was handed.
final class _CapturingSink {
  ReportFile? file;

  Future<ReportDelivery> call(ReportFile f) async {
    file = f;
    return ReportSaved(f.name);
  }
}

/// [screen] under an entitlement whose token includes `pdf_output` — without
/// it the screens offer no PDF at all (ADR 2026-09-25 §5–§6 🔒).
Widget _paid(Widget screen) => EntitlementScope(
  source: FakeEntitlementSource(
    entitlement: Entitlement(
      tenantId: 't-synthetic',
      plan: RkPlan.family,
      limits: rkTierFor(RkPlan.family).limits,
      periodEnd: null,
      graceKind: EntitlementGraceKind.none,
      source: EntitlementSourceKind.fresh,
      activeMembers: 1,
      features: [RkFeature.pdfOutput.wire],
    ),
  ),
  child: screen,
);

/// Taps [action] on a mounted screen and gives the export real event-loop
/// turns until it reaches [sink] — rasterising never completes inside the
/// fake-async zone (see `report_export_scale_test`'s `_tapAndExport`).
Future<ReportFile> _export(
  WidgetTester tester,
  Finder action,
  _CapturingSink sink,
) async {
  await tester.tap(action);
  await tester.pump();
  for (var turn = 0; turn < 600 && sink.file == null; turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  final file = sink.file;
  expect(file, isNotNull, reason: 'the export never reached the sink');
  expect(file!.format, ReportFormat.pdf);
  // Unmount inside the test so the confirmation's timer and drift's cleanup
  // fire before the binding's pending-timer check.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
  return file;
}

void main() {
  testWidgets('F1-183-11 a Punjabi report line is shaped by the engine and '
      'placed as an image; the English line beside it stays text', (
    tester,
  ) async {
    await rkLoadDesignFonts(tester);
    final shaper = PdfLineShaper();
    final bytes = await _pdf(tester, _table([_pa, _en]), shaper: shaper);

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(shaper.shapedTexts, contains(_pa));
    expect(shaper.shapedTexts, isNot(contains(_en)));
    expect(_images(bytes), shaper.shapeCount);
    expect(_images(bytes), greaterThan(0));

    // Control: the same table with no shaper draws no image at all.
    final unshaped = await _pdf(tester, _table([_pa, _en]));
    expect(_images(unshaped), 0);
  });

  testWidgets('F1-183-12 a Hindi report line is shaped by the engine and '
      'placed as an image', (tester) async {
    await rkLoadDesignFonts(tester);
    final shaper = PdfLineShaper();
    final bytes = await _pdf(tester, _table([_hi, _en]), shaper: shaper);

    expect(shaper.shapedTexts, contains(_hi));
    expect(shaper.shapedTexts, isNot(contains(_en)));
    expect(_images(bytes), greaterThan(0));
  });

  testWidgets('F1-183-13 a string repeated down a long report is shaped '
      'once and embedded once', (tester) async {
    await rkLoadDesignFonts(tester);
    final shaper = PdfLineShaper();
    final bytes = await _pdf(
      tester,
      _table([for (var i = 0; i < 60; i++) i.isEven ? _pa : _hi]),
      shaper: shaper,
    );

    expect(shaper.shapedTexts, {_pa, _hi});
    expect(shaper.shapeCount, 2);
    expect(_images(bytes), 2, reason: 'one image object per distinct line');
  });

  testWidgets('F1-183-14 a Punjabi page footer is shaped for every page, '
      '"p of n" with the real page count', (tester) async {
    await rkLoadDesignFonts(tester);
    final shaper = PdfLineShaper();
    String paPage(int page, int pages) => 'ਸਫ਼ਾ $page / $pages';
    final bytes = await _pdf(
      tester,
      _table([for (var i = 0; i < 120; i++) 'Row $i']),
      shaper: shaper,
      pageNumber: paPage,
    );

    final count = int.parse(
      RegExp(r'/Type\s*/Pages[^>]*/Count\s+(\d+)')
          .firstMatch(latin1.decode(bytes, allowInvalid: true))!
          .group(1)!,
    );
    expect(count, greaterThan(1), reason: 'the table runs onto more pages');
    for (var p = 1; p <= count; p++) {
      expect(shaper.shapedTexts, contains(paPage(p, count)));
    }
    // The probe line laid out the counting pass; nothing else was shaped.
    expect(
      shaper.shapedTexts.difference({
        for (var p = 1; p <= count; p++) paPage(p, count),
      }),
      {paPage(1, 1)},
    );
    // Asked is not drawn: the labels are shaped before the last layout, so
    // the final document must carry them. The rows are English, so the only
    // images are footers — one per page, each its own "p of n" — and the
    // probe, laid out only for the counting pass, is not among them
    // (`pw.MemoryImage` embeds only what a page draws).
    expect(
      _images(bytes),
      count,
      reason: 'every page draws its own shaped footer, and nothing else',
    );
  });

  // The …File writers are what the screens call. Each is driven with the
  // flag the call sites must pass, and its control (flag off) proves the
  // flag — not the table — is what routes the run through the engine.
  Future<ReportFile> dayBookFile(
    WidgetTester tester, {
    bool? shape,
    Locale locale = const Locale('pa'),
  }) async {
    final fonts = (await tester.runAsync(ReportFonts.load))!;
    final pa = lookupAppLocalizations(locale);
    // The book is named in the reader's own script, so a Hindi run proves
    // Devanagari is shaped, not a Gurmukhi name riding along.
    final bookName = locale.languageCode == 'hi' ? 'मेरी बही' : 'ਮੇਰੀ ਵਹੀ';
    Future<ReportFile> run() => shape == null
        ? dayBookPdfFile(
            const DayBook.empty('book-1'),
            accountName: (id) => id,
            labels: ReportLabels.dayBook(pa),
            bookName: bookName,
            period: 'FY 2026-27',
            formatDate: (date) => date.toIso(),
            pageNumber: (page, pages) => pa.reportsExportPage(page, pages),
            fonts: fonts,
            locale: locale,
            fileName: 'day-book.pdf',
          )
        : dayBookPdfFile(
            const DayBook.empty('book-1'),
            accountName: (id) => id,
            labels: ReportLabels.dayBook(pa),
            bookName: bookName,
            period: 'FY 2026-27',
            formatDate: (date) => date.toIso(),
            pageNumber: (page, pages) => pa.reportsExportPage(page, pages),
            fonts: fonts,
            locale: locale,
            fileName: 'day-book.pdf',
            shapeComplexScripts: shape,
          );
    return (await tester.runAsync(run))!;
  }

  Future<ReportFile> statementFile(
    WidgetTester tester, {
    bool? shape,
    String particulars = _pa,
    String name = 'ਖਾਤਾ',
  }) async {
    final fonts = (await tester.runAsync(ReportFonts.load))!;
    Future<ReportFile> run() => shape == null
        ? reportTablePdfFile(
            _table([particulars], name: name),
            pageNumber: _page,
            fonts: fonts,
            locale: const Locale('pa'),
            fileName: 'statement.pdf',
          )
        : reportTablePdfFile(
            _table([particulars], name: name),
            pageNumber: _page,
            fonts: fonts,
            locale: const Locale('pa'),
            fileName: 'statement.pdf',
            shapeComplexScripts: shape,
          );
    return (await tester.runAsync(run))!;
  }

  testWidgets('F1-183-15 the …File writers the screens call shape Punjabi '
      'when asked — the S8.2 day book and the S4 statement', (tester) async {
    await rkLoadDesignFonts(tester);

    expect(
      _images((await dayBookFile(tester, shape: true)).bytes),
      greaterThan(0),
    );
    expect(
      _images((await statementFile(tester, shape: true)).bytes),
      greaterThan(0),
    );
    // Control: the flag off draws no image, so the flag is the route.
    expect(_images((await dayBookFile(tester, shape: false)).bytes), 0);
    expect(_images((await statementFile(tester, shape: false)).bytes), 0);
  });

  // Desk 183 c, production path (REP183C): `shapeComplexScripts` is on by
  // default, so the writers S8.2 and S4 call — with no flag, exactly as their
  // call sites pass it — shape Punjabi and Hindi. Flip the default back to
  // false and this fails (0 images), which is what F1-183-15's control shows.
  testWidgets('F1-183-17 a Punjabi or Hindi PDF from the writers the screens '
      'call is shaped without being asked (desk 183 c production path)', (
    tester,
  ) async {
    await rkLoadDesignFonts(tester);
    final files = [
      await dayBookFile(tester),
      await statementFile(tester),
      await dayBookFile(tester, locale: const Locale('hi')),
      await statementFile(tester, particulars: _hi, name: 'खाता'),
    ];
    for (final file in files) {
      expect(_images(file.bytes), greaterThan(0));
      // What the images hold, not only that they exist (REP183C finding 2).
      _expectInked(file.bytes, reason: file.name);
    }
  });

  testWidgets('F1-183-16 an English report shapes nothing — Latin stays '
      'vector text', (tester) async {
    await rkLoadDesignFonts(tester);
    final shaper = PdfLineShaper();
    final bytes = await _pdf(tester, _table([_en, 'Diesel']), shaper: shaper);

    expect(shaper.shapeCount, 0);
    expect(_images(bytes), 0);
    expect(needsComplexShaping('₹1,24,500.00 Dr'), isFalse);
    expect(needsComplexShaping(_pa), isTrue);
    expect(needsComplexShaping(_hi), isTrue);
  });

  // ── REP183C: the screens themselves (desk 183 c production path) ──────────
  //
  // F1-183-17 drives the writers with default arguments; these drive the
  // screens, so a call site that passed `shapeComplexScripts: false` — or a
  // default flipped back — fails here too. The English run is the control:
  // the same screen, the same export, and no image, so the reader's script —
  // not the screen — is what routes a run through the engine.

  testWidgets('F1-183-21 S8.2 Download / Share hands the sink a Punjabi or '
      'Hindi day book drawn through the engine; the English one stays text', (
    tester,
  ) async {
    await rkLoadDesignFonts(tester);
    for (final locale in rkLocales) {
      final seeded = await seedSoloLedger();
      final sink = _CapturingSink();
      await pumpRk(
        tester,
        _paid(ReportViewerScreen(sink: sink.call)),
        ledger: seeded.ledger,
        locale: locale,
        viewport: rkTallViewport,
      );
      final primary = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(TextButton),
      );
      final file = await _export(tester, primary, sink);
      final images = _images(file.bytes);
      if (locale.languageCode == 'en') {
        expect(images, 0, reason: 'an English day book rasterises nothing');
      } else {
        expect(
          images,
          greaterThan(0),
          reason:
              'the ${locale.languageCode} day book from S8.2 was not shaped',
        );
        _expectInked(file.bytes, reason: 'S8.2 ${locale.languageCode}');
      }
    }
  });

  testWidgets('F1-183-22 S4 Download / Share hands the sink a Punjabi or '
      'Hindi statement drawn through the engine; the English one stays text', (
    tester,
  ) async {
    await rkLoadDesignFonts(tester);
    for (final locale in rkLocales) {
      final seeded = await seedSoloLedger();
      final sink = _CapturingSink();
      await pumpRk(
        tester,
        AccountStatementScreen(accountId: seeded.partyId, sink: sink.call),
        ledger: seeded.ledger,
        locale: locale,
        viewport: rkTallViewport,
      );
      final file = await _export(tester, find.byIcon(Icons.ios_share), sink);
      final images = _images(file.bytes);
      if (locale.languageCode == 'en') {
        expect(images, 0, reason: 'an English statement rasterises nothing');
      } else {
        expect(
          images,
          greaterThan(0),
          reason: 'the ${locale.languageCode} statement from S4 was not shaped',
        );
        _expectInked(file.bytes, reason: 'S4 ${locale.languageCode}');
      }
    }
  });

  testWidgets('F1-183-23 a 200-row Punjabi report shapes each distinct line '
      'once, embeds it once, and a second build is all cache hits', (
    tester,
  ) async {
    await rkLoadDesignFonts(tester);
    const account = 'ਨਕਦ ਖਾਤਾ';
    // Worst case for the cache: every narration distinct, one account name
    // repeated down all 200 rows, English heads and footer.
    final table = ReportTable(
      name: 'Day Book',
      meta: const [ReportMetaLine('Period', 'FY 2026-27')],
      columns: const [
        ReportColumn('Particulars'),
        ReportColumn('Account', width: ReportFixedWidth(110)),
        ReportColumn('Dr', align: ReportAlign.end, width: ReportFixedWidth(80)),
      ],
      rows: [
        for (var i = 0; i < 200; i++)
          ReportRow([
            ReportTextCell('$_pa $i'),
            const ReportTextCell(account),
            ReportMoneyCell(1_250_00 + i),
          ]),
      ],
    );
    final fonts = (await tester.runAsync(ReportFonts.load))!;
    Future<(Uint8List, Duration)> timed(PdfLineShaper? shaper) async {
      final run = await tester.runAsync(() async {
        final clock = Stopwatch()..start();
        final bytes = await reportTablePdf(
          table,
          pageNumber: _page,
          fonts: fonts,
          locale: const Locale('pa'),
          shaper: shaper,
        );
        return (bytes, clock.elapsed);
      });
      return run!;
    }

    final (vector, vectorTime) = await timed(null);
    final shaper = PdfLineShaper();
    final (shaped, shapedTime) = await timed(shaper);

    // 200 distinct narrations + the one repeated account name.
    expect(shaper.shapeCount, 201);
    expect(shaper.shapedTexts, contains(account));
    expect(_images(shaped), 201, reason: 'one image object per distinct line');
    expect(_images(vector), 0);

    // Same shaper, same document: nothing is rasterised again.
    final (_, cachedTime) = await timed(shaper);
    expect(shaper.shapeCount, 201, reason: 'a second build hit the cache');

    debugPrint(
      'F1-183-23 200-row pa report: vector ${vectorTime.inMilliseconds} ms '
      '(${vector.length} B), shaped ${shapedTime.inMilliseconds} ms '
      '(${shaped.length} B), cached rebuild ${cachedTime.inMilliseconds} ms',
    );
    // A loose ceiling, not a benchmark: it catches a lost cache or a
    // per-row re-layout, never a slow machine.
    expect(shapedTime, lessThan(const Duration(seconds: 60)));
  });

  // ── REP183C repair round 2 ───────────────────────────────────────────────

  testWidgets('F1-183-24 a right-aligned shaped run — the Punjabi page '
      'footer and an end-aligned cell — is drawn with its ink, at the image '
      'edge', (tester) async {
    await rkLoadDesignFonts(tester);
    String paPage(int page, int pages) => 'ਸਫ਼ਾ $page / $pages';
    // English rows: the only shaped run is the right-aligned footer.
    final footers = await _pdf(
      tester,
      _table([for (var i = 0; i < 120; i++) 'Row $i']),
      shaper: PdfLineShaper(),
      pageNumber: paPage,
    );
    final footerInks = _inks(footers);
    expect(footerInks, hasLength(greaterThan(1)));
    _expectInked(footers, reason: 'right-aligned footer');

    // A Punjabi word in the end-aligned Dr column, alone on its row.
    final cell = await _pdf(
      tester,
      ReportTable(
        name: 'Day Book',
        meta: const [ReportMetaLine('Period', 'FY 2026-27')],
        columns: const [
          ReportColumn('Particulars'),
          ReportColumn(
            'Dr',
            align: ReportAlign.end,
            width: ReportFixedWidth(80),
          ),
        ],
        rows: const [
          ReportRow([ReportTextCell('Opening'), ReportTextCell('ਨਾਮ')]),
        ],
      ),
      shaper: PdfLineShaper(),
    );
    expect(_inks(cell), hasLength(1));
    _expectInked(cell, reason: 'end-aligned cell');

    // Control: the same footer left-aligned inks as much — the shift moves
    // the ink, it does not lose any of it.
    final probe = (await tester.runAsync(
      () => shapePdfLine(
        paPage(3, 12),
        size: 8,
        color: const Color(0xFF000000),
        maxWidth: 500,
      ),
    ))!;
    final right = (await tester.runAsync(
      () => shapePdfLine(
        paPage(3, 12),
        size: 8,
        color: const Color(0xFF000000),
        maxWidth: 500,
        align: TextAlign.right,
      ),
    ))!;
    expect(right.width, probe.width);
    expect(right.png.length, closeTo(probe.png.length, probe.png.length / 10));
  });

  testWidgets('F1-183-25 the masthead, its meta line, the column headings and '
      'the amount in words are shaped and drawn, not set as text', (
    tester,
  ) async {
    await rkLoadDesignFonts(tester);
    const title = 'ਰੋਜ਼ਨਾਮਚਾ';
    const heads = ['ਵੇਰਵਾ', 'ਨਾਮ'];
    const inWords = ReportMetaLine('ਸ਼ਬਦਾਂ ਵਿੱਚ', 'ਚਾਰ ਹਜ਼ਾਰ ਪੰਜ ਸੌ ਰੁਪਏ');
    final table = ReportTable(
      name: title,
      meta: const [ReportMetaLine('ਮਿਆਦ', 'ਵਿੱਤੀ ਸਾਲ 2026-27')],
      columns: [
        ReportColumn(heads[0]),
        ReportColumn(
          heads[1],
          align: ReportAlign.end,
          width: const ReportFixedWidth(80),
        ),
      ],
      // English body and footer: every image is one of the four routes.
      rows: const [
        ReportRow([ReportTextCell('Opening'), ReportMoneyCell(4_500_00)]),
      ],
      amountInWords: inWords,
    );
    final shaper = PdfLineShaper();
    final bytes = await _pdf(tester, table, shaper: shaper);

    expect(shaper.shapedTexts, {
      title,
      'ਮਿਆਦ: ਵਿੱਤੀ ਸਾਲ 2026-27',
      ...heads,
      '${inWords.label}: ${inWords.value}',
    });
    // One page, so every shaped line is drawn, once.
    expect(_images(bytes), shaper.shapeCount);
    _expectInked(bytes, reason: 'masthead / headings / amount in words');
  });

  testWidgets('F1-183-26 the shaper draws at most four lines at a time and '
      'still shapes every one', (tester) async {
    await rkLoadDesignFonts(tester);
    final shaper = PdfLineShaper();
    final bytes = await _pdf(
      tester,
      _table([for (var i = 0; i < 40; i++) '$_pa $i']),
      shaper: shaper,
    );
    expect(shaper.shapeCount, 40);
    expect(shaper.peakInFlight, inInclusiveRange(1, 4));
    expect(_images(bytes), 40);

    final one = PdfLineShaper(maxConcurrent: 1);
    await _pdf(tester, _table(['$_pa a', '$_pa b', '$_pa c']), shaper: one);
    expect(one.shapeCount, 3);
    expect(one.peakInFlight, 1);
  });
}
