// F1-25-13 — the PDF gate reads the token's `features` (ADR 2026-09-25 §5 🔒:
// no PDF output on Free, CSV/XLSX never restricted; §6 🔒: the app's gates
// read the token, never the plan's name).
//
// Every case drives the real S8.2 viewer over a seeded in-memory ledger and a
// capturing sink, so "nothing was written" is the sink's own record, not a
// widget's claim.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/reports/export/pdf_gate.dart';
import 'package:rukka_folio/features/reports/export/report_export.dart';
import 'package:rukka_folio/features/reports/screens/s8_2_report_viewer_screen.dart';
import 'package:rukka_folio/features/reports/widgets/reports_row.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/subscription_paths.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

final class _Sink {
  final files = <ReportFile>[];

  Future<ReportDelivery> call(ReportFile f) async {
    files.add(f);
    return ReportSaved(f.name);
  }
}

Entitlement _reading(RkPlan plan, List<String> features) => Entitlement(
  tenantId: 't-synthetic',
  plan: plan,
  limits: rkTierFor(RkPlan.family).limits,
  periodEnd: null,
  graceKind: EntitlementGraceKind.none,
  source: EntitlementSourceKind.fresh,
  activeMembers: 1,
  features: features,
);

Future<void> _pump(
  WidgetTester tester,
  _Sink sink, {
  Entitlement? reading,
  Locale? locale,
  double textScale = 1,
  Size viewport = rkTallViewport,
}) async {
  final seeded = await seedSoloLedger();
  final screen = ReportViewerScreen(sink: sink.call);
  await pumpRk(
    tester,
    reading == null
        ? screen
        : EntitlementScope(
            source: FakeEntitlementSource(entitlement: reading),
            child: screen,
          ),
    ledger: seeded.ledger,
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  group('F1-25-13 the PDF gate (ADR 2026-09-25 §5–§6 🔒)', () {
    testWidgets('F1-25-13 with no token the default writes nothing: the format '
        'sheet opens, PDF is shut with its reason, and CSV still writes', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final sink = _Sink();
      await _pump(tester, sink);

      await tester.tap(find.text('Download / Share'));
      await tester.pumpAndSettle();
      expect(sink.files, isEmpty, reason: 'no PDF may be written on Free');
      // The sheet is open: all three rows (the 🔒 enumeration is intact),
      // PDF carrying the lock and the sentence.
      expect(find.byType(ReportsActionRow), findsNWidgets(3));
      expect(find.text(l10n.reportsExportPdfNotOnPlan), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);

      // Tapping the shut row writes nothing and keeps the reason on screen.
      await tester.tap(find.text(l10n.reportsExportPdf));
      await tester.pumpAndSettle();
      expect(sink.files, isEmpty);
      expect(find.text(l10n.reportsExportPdfNotOnPlan), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // CSV is never gated (ADR 25 §5: *Export everything*).
      await tester.tap(find.byTooltip('Choose a format'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reportsExportCsv));
      await tester.pumpAndSettle();
      expect(sink.files.single.format, ReportFormat.csv);
      await _unmount(tester);
    });

    testWidgets('F1-25-13 the gate asks the features, not the name: a plan '
        'called free whose token carries pdf_output writes the PDF, a plan '
        'called family whose token does not, does not', (tester) async {
      final freeWithPdf = _Sink();
      await _pump(
        tester,
        freeWithPdf,
        reading: _reading(RkPlan.free, [RkFeature.pdfOutput.wire]),
      );
      await tester.tap(find.text('Download / Share'));
      await tester.pumpAndSettle();
      expect(freeWithPdf.files.single.format, ReportFormat.pdf);
      await _unmount(tester);

      final familyWithout = _Sink();
      await _pump(
        tester,
        familyWithout,
        reading: _reading(RkPlan.family, [RkFeature.statementImport.wire]),
      );
      await tester.tap(find.text('Download / Share'));
      await tester.pumpAndSettle();
      expect(familyWithout.files, isEmpty);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('F1-25-13 the "Choose a format" sheet reads the entitlement '
        'itself: with no token its PDF row is shut and writes nothing; under '
        'a pdf_output token the same row writes the PDF', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final free = _Sink();
      await _pump(tester, free);
      await tester.tap(find.byTooltip('Choose a format'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportsActionRow), findsNWidgets(3));
      expect(find.text(l10n.reportsExportPdfNotOnPlan), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await tester.tap(find.text(l10n.reportsExportPdf));
      await tester.pumpAndSettle();
      expect(free.files, isEmpty, reason: 'no PDF may be written on Free');
      expect(find.byType(SnackBar), findsOneWidget);
      await _unmount(tester);

      final paid = _Sink();
      await _pump(
        tester,
        paid,
        reading: _reading(RkPlan.family, [RkFeature.pdfOutput.wire]),
      );
      await tester.tap(find.byTooltip('Choose a format'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reportsExportPdfNotOnPlan), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      await tester.tap(find.text(l10n.reportsExportPdf));
      await tester.pumpAndSettle();
      expect(paid.files.single.format, ReportFormat.pdf);
      await _unmount(tester);
    });

    testWidgets('F1-25-13 the shut PDF row\'s See plans lands on S12.1 '
        'through the mounted GoRouter', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final sink = _Sink();
      final seeded = await seedSoloLedger();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ReportViewerScreen(sink: sink.call),
          ),
          GoRoute(
            path: SubscriptionPaths.plans,
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('plans-landed'))),
          ),
        ],
      );
      rkViewport(tester, rkTallViewport);
      await tester.pumpWidget(
        RkScope(
          db: seeded.ledger.db,
          sync: FakeSyncClient(),
          auth: FakeAuthClient(),
          keys: seeded.ledger.keys,
          now: seeded.ledger.now,
          child: LedgerScope(
            ledger: seeded.ledger,
            child: MaterialApp.router(
              routerConfig: router,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: rkLocalizationsDelegates,
              theme: rkTheme(Brightness.light),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download / Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reportsExportPdf));
      await tester.pumpAndSettle();
      expect(sink.files, isEmpty);
      await tester.tap(find.text(l10n.reportsExportPdfSeePlans));
      await tester.pumpAndSettle();
      expect(find.text('plans-landed'), findsOneWidget);
      await _unmount(tester);
    });

    test(
      'F1-25-13 a reading that cannot be made is not a PDF licence',
      () async {
        final broken = FakeEntitlementSource(failure: StateError('no store'));
        expect(await reportPdfIncluded(broken), isFalse);
        expect(
          await reportPdfIncluded(
            FakeEntitlementSource(
              entitlement: _reading(RkPlan.family, [RkFeature.pdfOutput.wire]),
            ),
          ),
          isTrue,
        );
        expect(
          await reportPdfIncluded(const UntokenedEntitlementSource()),
          isFalse,
        );
      },
    );

    testWidgets('F1-25-13 the shut PDF row resolves in EN, PA and HI with '
        'nothing cut at 200 % on 360×800', (tester) async {
      for (final locale in rkLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        final sink = _Sink();
        await _pump(
          tester,
          sink,
          locale: locale,
          textScale: 2,
          viewport: rkPhone360,
        );
        await tester.tap(find.byIcon(Icons.ios_share));
        await tester.pumpAndSettle();
        expect(find.text(l10n.reportsExportPdfNotOnPlan), findsOneWidget);
        expectTextFits(tester, reason: '${locale.languageCode} gated sheet');
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      }
    });
  });
}
