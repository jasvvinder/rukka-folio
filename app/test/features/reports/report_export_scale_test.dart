// F1-07-434 — a report at **200 % text scale on 360×800** (07 §1 rule 11;
// 13 §4.3), taken through the export the M12 content rules changed.
//
// The closing block of 07 §14 🔒 (b/d–c/d, the Total line) and the amount in
// words are new rows and a new line of text, and text is what a 200 % layout
// breaks on. This case is the S8.2 viewer pattern — `pumpRk`'s live
// MediaQuery, both the exception check and [expectTextFits], all three
// languages — run at the harder of the two reference phones and then *through*
// the export, so a report that renders at 200 % but cannot be handed over at
// 200 % still fails.
//
// [expectTextFits] is here for the reason the viewer cases give: given less
// room than one of its words a paragraph draws that word past its edge and
// throws nothing, so the tree is measured as well as asked whether it threw.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/screens/s4_account_statement_screen.dart';
import 'package:rukka_folio/features/reports/export/report_export.dart';
import 'package:rukka_folio/features/reports/screens/s8_2_report_viewer_screen.dart';
import 'package:rukka_folio/features/reports/widgets/file_name_message.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';

import '../../shared/test_app.dart';

/// A [ReportSink] that keeps what it was handed instead of writing a file.
/// [where] is what it says it saved to — the file name by default, or a path.
final class _CapturingSink {
  _CapturingSink({this.where});

  final String Function(ReportFile f)? where;
  ReportFile? file;

  Future<ReportDelivery> call(ReportFile f) async {
    file = f;
    return ReportSaved(where?.call(f) ?? f.name);
  }
}

/// The snackbar is up, it names [where] in full, and none of its text is cut.
///
/// The name is read back with the break opportunities taken out — so what is
/// asserted is that every character of it is on the screen, not that a
/// shortened one is — and the paragraph's own lines are checked: more than
/// one proves it wrapped, and [expectTextFits] proves no run is drawn past
/// the edge. No ellipsis, ever (ADR 2026-09-24b §10).
void _expectNamedAndFits(
  WidgetTester tester,
  String where, {
  required String reason,
}) {
  expect(tester.takeException(), isNull, reason: reason);
  final message = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(FileNameMessage),
  );
  expect(message, findsOneWidget, reason: reason);
  final text = tester.widget<Text>(
    find.descendant(of: message, matching: find.byType(Text)),
  );
  final shown = text.data!;
  expect(shown.replaceAll('\u200B', ''), contains(where), reason: reason);
  expect(shown, isNot(contains('…')), reason: reason);
  expect(text.maxLines, isNull, reason: reason);
  expect(text.overflow, isNot(TextOverflow.ellipsis), reason: reason);
  expect(text.semanticsLabel, contains(where), reason: reason);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: message, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse, reason: reason);
  expectTextFits(tester, reason: reason);
}

/// A reading whose token includes `pdf_output` — the plans on which the
/// PDF paths below exist at all (ADR 2026-09-25 §5–§6 🔒, M13-CAT2). Without
/// it the screen reads untokened, which is Free, which has no PDF.
Entitlement _pdfReading() => Entitlement(
  tenantId: 't-synthetic',
  plan: RkPlan.family,
  limits: rkTierFor(RkPlan.family).limits,
  periodEnd: null,
  graceKind: EntitlementGraceKind.none,
  source: EntitlementSourceKind.fresh,
  activeMembers: 1,
  features: [RkFeature.pdfOutput.wire],
);

/// [screen] under a PDF-including entitlement.
Widget _paid(Widget screen) => EntitlementScope(
  source: FakeEntitlementSource(entitlement: _pdfReading()),
  child: screen,
);

/// Taps [action] and lets the export it starts finish.
///
/// A Punjabi or Hindi PDF is shaped by the engine (desk 183 c,
/// `shared/pdf_shaping.dart`): its lines are rasterised through `dart:ui`,
/// whose futures complete on the real event loop — never inside the test's
/// fake-async zone, where a bare `pumpAndSettle` would return with the file
/// still unbuilt. So the export is given real turns ([WidgetTester.runAsync])
/// and a frame after each, until [done] — then settled as before. Nothing is
/// skipped: the same production export runs, only the clock it waits on is
/// real.
Future<void> _tapAndExport(
  WidgetTester tester,
  Finder action,
  bool Function() done,
) async {
  await tester.tap(action);
  await tester.pump();
  for (var turn = 0; turn < 600 && !done(); turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('a report at 200 % on 360×800 (07 §1 rule 11)', () {
    for (final locale in rkLocales) {
      testWidgets('F1-07-434 the report and its export survive 200 % in '
          '${locale.languageCode} on 360×800 — nothing overflows and the file '
          'still reaches the sink (07 §14 🔒 content rules)', (tester) async {
        final seeded = await seedSoloLedger();
        final sink = _CapturingSink();
        await pumpRk(
          tester,
          _paid(ReportViewerScreen(sink: sink.call)),
          ledger: seeded.ledger,
          locale: locale,
          textScale: 2,
          viewport: rkPhone360,
        );

        expect(tester.takeException(), isNull);
        expectTextFits(
          tester,
          reason: 'S8.2 in ${locale.languageCode} at 200% on 360×800',
        );

        // Past 1.3x the primary action is an icon, which is what lets it
        // share the bar at all; it exports the PDF (ADR 2026-09-12d §2 🔒).
        await _tapAndExport(
          tester,
          find.byIcon(Icons.ios_share),
          () => sink.file != null,
        );

        expect(tester.takeException(), isNull);
        final file = sink.file;
        expect(file, isNotNull, reason: 'the report never reached the sink');
        expect(file!.format, ReportFormat.pdf);
        expect(file.bytes, isNotEmpty);

        // The fallback confirmation names the file (07 §1 rule 6) and fits
        // (rule 11): at 200 % "day-book-2026-27.pdf" is wider than the
        // snackbar as one word, so it wraps — at `-`, `/`, `.` first, then
        // any character — and is never ellipsised or clipped
        // (ADR 2026-09-24b §10).
        _expectNamedAndFits(
          tester,
          file.name,
          reason: 'S8.2 saved message in ${locale.languageCode}',
        );

        // Tear down inside the test so the snackbar's four-second timer and
        // drift's cleanup timer fire before the binding's pending-timer
        // invariant runs.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('F1-07-434 S4\'s statement export names a saved *path* in '
          '${locale.languageCode} at 200 % on 360×800 — it wraps at `/`, `-` '
          'and `.` and is never cut (ADR 2026-09-24b §10)', (tester) async {
        final seeded = await seedSoloLedger();
        const path =
            '/data/user/0/com.rukkafolio.app/cache/statement-2026-27.pdf';
        final sink = _CapturingSink(where: (_) => path);
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seeded.partyId, sink: sink.call),
          ledger: seeded.ledger,
          locale: locale,
          textScale: 2,
          viewport: rkPhone360,
        );
        expect(tester.takeException(), isNull);

        await _tapAndExport(
          tester,
          find.byIcon(Icons.ios_share),
          () => sink.file != null,
        );

        expect(sink.file, isNotNull, reason: 'the statement never left S4');
        _expectNamedAndFits(
          tester,
          path,
          reason: 'S4 saved message in ${locale.languageCode}',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets(
        'F1-07-434 a name with no `-`, `/` or `.` narrow enough still '
        'breaks — at any character — in ${locale.languageCode} at 200 % on '
        '360×800 (ADR 2026-09-24b §10)',
        (tester) async {
          // Synthetic: one stretch far wider than the line and no preferred
          // break inside it, so only the any-character level can fit it.
          const name = 'statementofaccountforthefinancialyear202627final.pdf';
          await pumpRk(
            tester,
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      final l10n = AppLocalizations.of(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: FileNameMessage(
                            fileName: name,
                            sentence: l10n.reportsExportSaved,
                          ),
                        ),
                      );
                    },
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          await tester.tap(find.text('go'));
          await tester.pumpAndSettle();

          _expectNamedAndFits(
            tester,
            name,
            reason: 'long unpunctuated name in ${locale.languageCode}',
          );
          // The preferred level alone could not have fitted it: the run before
          // the `.` breaks between characters too.
          final shown = tester
              .widget<Text>(
                find.descendant(
                  of: find.byType(FileNameMessage),
                  matching: find.byType(Text),
                ),
              )
              .data!;
          expect(shown, contains('s\u200Bt\u200Ba'));

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 5));
        },
      );
    }
  });

  group('file-name break levels (ADR 2026-09-24b §10)', () {
    test('F1-07-434 the preferred level breaks after `-`, `/` and `.` only, '
        'and a name that fits is left exactly as the sink gave it', () {
      expect(
        fileNameBreaksPreferred('/tmp/day-book-2026-27.pdf'),
        '/\u200Btmp/\u200Bday-\u200Bbook-\u200B2026-\u200B27.\u200Bpdf',
      );
      // Everything fits → only the preferred breaks, nothing more.
      expect(
        fileNameBreaks('day-book.pdf', (_) => true),
        'day-\u200Bbook.\u200Bpdf',
      );
      // A segment that does not fit breaks at every grapheme; the others stay.
      expect(
        fileNameBreaks('ab-cdef.pdf', (s) => s.length < 4),
        'ab-\u200Bc\u200Bd\u200Be\u200Bf\u200B.\u200Bpdf',
      );
      // Graphemes, not code units: a Gurmukhi cluster is never split.
      expect(fileNameBreaksAnywhere('ਖਾਤਾ'), 'ਖਾ\u200Bਤਾ');
    });
  });
  // RPT2 review, finding 1: the fit was measured in the ambient style while
  // [Text] draws bold under the OS Bold Text setting and applies MediaQuery's
  // spacing overrides — so a piece judged to fit could be drawn wider than the
  // line and clipped. The real Mukta faces are loaded because the test font
  // draws bold at the same width; with Mukta, bold resolves to SemiBold and is
  // measurably wider (the reviewer's probe: 143.2 px vs 148.6 px at 28 px).
  group('file-name fit is measured in the drawn style (ADR 2026-09-24b §10)', () {
    const family = 'RkFitMukta';
    const piece = 'Application/';
    const name = 'Application/Application/day.pdf';
    // A sentence with a space in it, as every ARB sentence has: the engine's
    // min-intrinsic width only honours the zero-width breaks in a paragraph
    // that also contains a space, so a bare name would be misreported as cut.
    String sentence(String n) => 'Saved: $n';

    setUpAll(() async {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/Mukta-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Mukta-SemiBold.ttf'));
      await loader.load();
    });

    const base = TextStyle(fontFamily: family, fontSize: 28);

    double widthOf(String text, TextStyle style) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = p.minIntrinsicWidth;
      p.dispose();
      return w;
    }

    Future<void> pumpAt(
      WidgetTester tester, {
      required double width,
      required MediaQueryData data,
    }) => tester.pumpWidget(
      MediaQuery(
        data: data,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: base,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: FileNameMessage(fileName: name, sentence: sentence),
              ),
            ),
          ),
        ),
      ),
    );

    String shown(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(FileNameMessage),
            matching: find.byType(Text),
          ),
        )
        .data!;

    testWidgets('F1-07-434 under the OS Bold Text setting a piece that fits '
        'only in the regular face is broken, not drawn bold past the edge', (
      tester,
    ) async {
      final regular = widthOf(piece, base);
      final bold = widthOf(
        piece,
        base.merge(const TextStyle(fontWeight: FontWeight.bold)),
      );
      // The precondition the finding rests on: bold really is wider here.
      expect(bold, greaterThan(regular + 2));
      final line = (regular + bold) / 2;

      await pumpAt(
        tester,
        width: line,
        data: const MediaQueryData(size: Size(400, 800), boldText: true),
      );
      expect(tester.takeException(), isNull);
      expectTextFits(tester, reason: 'bold text, line $line px');
      expect(shown(tester).replaceAll('\u200B', ''), sentence(name));
      expect(shown(tester), contains('A\u200Bp\u200Bp'));

      // Control: the same line without Bold Text is left as the plain
      // sentence — the break above is the bold measurement, not a narrow line.
      await pumpAt(
        tester,
        width: line,
        data: const MediaQueryData(size: Size(400, 800)),
      );
      expectTextFits(tester, reason: 'regular text, line $line px');
      expect(shown(tester), sentence(name));
    });

    testWidgets('F1-07-434 a MediaQuery letter-spacing override is measured '
        'too, so the widened piece is broken rather than clipped', (
      tester,
    ) async {
      final regular = widthOf(piece, base);
      // Twelve glyphs at +2 px each: ~24 px wider than the line allows.
      final line = regular + 4;

      await pumpAt(
        tester,
        width: line,
        data: const MediaQueryData(
          size: Size(400, 800),
          letterSpacingOverride: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      expectTextFits(tester, reason: 'letter spacing +2, line $line px');
      expect(shown(tester).replaceAll('\u200B', ''), sentence(name));
      expect(shown(tester), contains('A\u200Bp\u200Bp'));
    });
  });
}
