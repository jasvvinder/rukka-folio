// F1-07-160 … F1-07-162 and F1-07-167 … F1-07-169 — the export trio on S4
// (ADR 2026-09-12e §2 🔒, owner-confirmed 13 Sep: *View · Download/Share ·
// Export (PDF/CSV/XLSX)* binds the A/C statement as well as S8.2).
//
// **View** is S4 itself, so the cases that assert the statement renders are
// F1-07-44's and are not repeated here. What is asserted here is the other two
// thirds and what they must never do:
//
//   • *Download / Share* writes a **PDF** with no sheet in between
//     (ADR 2026-09-12d §2 🔒), and a successful share gets **no sentence** from
//     us — the share sheet is its own confirmation (ADR 2026-09-13 §1 🔒).
//   • A share that could not be raised names the file it wrote instead, so the
//     path is never a dead end (07 §1 rules 2 and 6).
//   • The wait is the 2 px loader **rule**, never a spinner (11 §4.5 🔒).
//   • The bar holds both actions at 200 % on a 360 px phone in all three
//     languages — the defect the S8.2 pair was hardened against, which S4 now
//     inherits rather than re-invents.
//
// The bytes of each format are F1-07-163 … F1-07-166, in
// `test/features/reports/statement_report_test.dart`, where they can be
// asserted against a hand-written statement instead of a seeded clock.
@Tags(['F1'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/screens/s4_account_statement_screen.dart';
import 'package:rukka_folio/features/reports/export/report_export.dart';
import 'package:rukka_folio/features/reports/widgets/reports_row.dart';

import '../../shared/test_app.dart';

/// A [ReportSink] that keeps what it was handed instead of writing a file.
///
/// [delivery] is what it reports back: [ReportSaved] (the fallback, which puts
/// a sentence on the screen) or [ReportShared] (the shipped path, which must
/// not). [gate] holds the delivery open so a test can look at the screen while
/// the export is still running.
final class _CapturingSink {
  _CapturingSink({this.delivery, this.gate});

  final ReportDelivery? delivery;
  final Completer<void>? gate;
  ReportFile? file;

  Future<ReportDelivery> call(ReportFile f) async {
    file = f;
    if (gate != null) await gate!.future;
    return delivery ?? ReportSaved(f.name);
  }
}

/// Tears the tree down *inside* the test and lets its timers run out: drift's
/// query stream schedules a zero-duration cleanup timer on cancel, and a
/// SnackBar holds a four-second one.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

/// The text of every [Text] in the tree, in tree order — both the plain `data`
/// form and the rendered span, because `MoneyText` writes its Dr/Cr word into
/// a `Text.rich` span that `find.text` cannot see.
List<String> _texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

void main() {
  group('S4 export trio (ADR 2026-09-12e §2 🔒, 07 §6, 13 §3.2 row S4)', () {
    testWidgets(
      'F1-07-160 the statement is the View, and its bar carries the other two '
      'thirds — Download / Share and Export',
      (tester) async {
        final seed = await seedSoloLedger();
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seed.partyId),
          ledger: seed.ledger,
          viewport: rkTallViewport,
        );

        // View: the statement itself, b/f first and c/f last.
        expect(find.textContaining('Opening balance b/f'), findsOneWidget);
        expect(find.textContaining('Closing balance c/f'), findsOneWidget);

        // Download / Share — labelled at normal scale, and never carried by
        // the glyph alone (07 §1 rule 3).
        expect(find.byIcon(Icons.ios_share), findsOneWidget);
        expect(find.byTooltip('Download / Share'), findsOneWidget);
        // Export — the door to the three formats.
        expect(find.byIcon(Icons.more_horiz), findsOneWidget);
        expect(find.byTooltip('Choose a format'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-161 Download / Share writes a PDF with no sheet in between, and '
      'a successful share gets no sentence from us (ADR 2026-09-12d §2 🔒, '
      'ADR 2026-09-13 §1 🔒)',
      (tester) async {
        final seed = await seedSoloLedger();
        final sink = _CapturingSink(delivery: const ReportShared());
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seed.partyId, sink: sink.call),
          ledger: seed.ledger,
          viewport: rkTallViewport,
        );

        await tester.tap(find.byIcon(Icons.ios_share));
        await tester.pumpAndSettle();

        // No sheet was opened — the default writes straight away.
        expect(find.byType(ReportsActionRow), findsNothing);

        final file = sink.file;
        expect(file, isNotNull, reason: 'the report never reached the sink');
        expect(file!.format, ReportFormat.pdf);
        // The name is metadata that travels with the file: the year and the
        // extension, never an account name or a figure (CLAUDE.md rule 4).
        expect(file.name, 'statement-2026-27.pdf');
        expect(file.name, isNot(contains('Ramesh')));
        expect(String.fromCharCodes(file.bytes.take(5)), '%PDF-');

        // The share sheet is the confirmation; a snackbar would cover the very
        // screen it appeared on and would be a guess about what the reader did.
        expect(find.byType(SnackBar), findsNothing);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-162 Export offers exactly PDF · CSV · XLSX, and the CSV it '
      'writes is this account\'s statement in professional Dr/Cr',
      (tester) async {
        final seed = await seedSoloLedger();
        final sink = _CapturingSink();
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seed.partyId, sink: sink.call),
          ledger: seed.ledger,
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
        // The 🔒 enumeration is exactly three — no fourth row, none missing.
        expect(find.byType(ReportsActionRow), findsNWidgets(3));

        await tester.tap(find.text('CSV'));
        await tester.pumpAndSettle();

        final file = sink.file;
        expect(file, isNotNull, reason: 'the CSV never reached the sink');
        expect(file!.format, ReportFormat.csv);
        expect(file.name, 'statement-2026-27.csv');
        expect(file.bytes.take(3), [0xEF, 0xBB, 0xBF]);

        final text = utf8.decode(file.bytes.sublist(3));
        expect(text, contains('A/C statement'));
        expect(text, contains('Account,Ramesh'));
        // A professional surface: Dr and Cr head the columns, and the consumer
        // vocabulary never reaches the file (02 §10 🔒, CLAUDE.md rule 9).
        expect(text, contains('Dr,Cr,Balance'));
        expect(text, isNot(contains('Money in')));
        expect(text, isNot(contains('Money out')));
        // b/f first, c/f last (02 §8.1 *Presentation*).
        final lines = text.split('\r\n')..removeWhere((l) => l.isEmpty);
        expect(lines.where((l) => l.contains('Opening balance b/f')).length, 1);
        expect(lines.last, contains('Closing balance c/f'));
        // Ramesh owes ₹5,000 after the seeded part repayment — integer paise
        // all the way to the file (CLAUDE.md rule 1).
        expect(lines.last, contains('5000.00'));
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-167 when no share sheet can be raised the file is written and '
      'named — never a silent no-op (07 §1 rules 2 and 6)',
      (tester) async {
        final seed = await seedSoloLedger();
        final sink = _CapturingSink(
          delivery: const ReportSaved('/tmp/statement-2026-27.pdf'),
        );
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seed.partyId, sink: sink.call),
          ledger: seed.ledger,
          viewport: rkTallViewport,
        );

        await tester.tap(find.byIcon(Icons.ios_share));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.textContaining('/tmp/statement-2026-27.pdf'),
          findsOneWidget,
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-168 the wait is the 2 px loader rule with words beside it, never '
      'a spinner (11 §4.5 🔒, 13 §4.3)',
      (tester) async {
        final seed = await seedSoloLedger();
        final gate = Completer<void>();
        final sink = _CapturingSink(delivery: const ReportShared(), gate: gate);
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seed.partyId, sink: sink.call),
          ledger: seed.ledger,
          viewport: rkTallViewport,
        );

        await tester.tap(find.byIcon(Icons.ios_share));
        // Long enough for the fonts to load and the sink to be reached, but
        // the gate holds the delivery open.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(sink.file, isNotNull, reason: 'the export never started');
        final loader = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(loader.minHeight, 2.0);
        // Never a spinner — anywhere (11 §4.5 🔒).
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // The rule alone says nothing: the words beside it are what carry the
        // state (07 §1 rule 3).
        expect(find.text('Preparing your file'), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Preparing your file'), findsNothing);
        await unmount(tester);
      },
    );

    testWidgets('F1-07-169 the bar holds both actions at 1.3x and 200% on both phones, '
        'in EN, PA and HI (07 §1 rule 11)', (tester) async {
      for (final viewport in rkPhones) {
        for (final scale in rkTextScales) {
          for (final locale in rkLocales) {
            final seed = await seedSoloLedger();
            await pumpRk(
              tester,
              AccountStatementScreen(accountId: seed.partyId),
              ledger: seed.ledger,
              locale: locale,
              viewport: viewport,
              textScale: scale,
            );

            final where = '$locale at ${scale}x on $viewport';
            expect(
              tester.takeException(),
              isNull,
              reason: 'the statement bar overflowed — $where',
            );
            // Both thirds of the trio survive every combination: at 200 %
            // the labelled action has become an icon, but neither vanishes.
            expect(
              find.byIcon(Icons.ios_share),
              findsOneWidget,
              reason: 'Download / Share is missing — $where',
            );
            expect(
              find.byIcon(Icons.more_horiz),
              findsOneWidget,
              reason: 'Export is missing — $where',
            );
            // The whole screen, not only the bar: the statement grid it sits
            // over folds its columns rather than cut a figure now (F1-07-171),
            // so there is nothing left for this case to scope around.
            expectTextFits(tester, reason: where);
            await unmount(tester);
          }
        }
      }
    });
  });
}
