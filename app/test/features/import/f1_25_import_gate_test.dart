// F1-25-14 — S7's statement-import gate reads the token's `features` (ADR
// 2026-09-25 §3, §5 🔒: import is one of the two extras a plan may include;
// §6 🔒: the app's gates read the token, never the plan's name).
//
// Pumped over the feature-local [FakeImportSource], so "no A/C was listed"
// is the source's own count of calls, not a widget's claim.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/import/import_routes.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/subscription_paths.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

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

Future<FakeImportSource> _pump(
  WidgetTester tester, {
  EntitlementSource? entitlement,
  bool viaScope = false,
  VoidCallback? onOpenPlans,
  Locale? locale,
  double textScale = 1,
  Size viewport = rkTallViewport,
}) async {
  final source = FakeImportSource(
    accounts: const [
      ImportAccount(id: 'a1', name: 'Test Bank', bankKey: 'test'),
    ],
  );
  final screen = ImportScreen(
    entitlement: viaScope ? null : entitlement,
    onOpenPlans: onOpenPlans,
    onParsed: (_, _, _) {},
  );
  final scoped = ImportScope(
    source: source,
    filePort: FakeStatementFilePort(),
    bookId: 'book-1',
    child: screen,
  );
  await pumpRk(
    tester,
    viaScope && entitlement != null
        ? EntitlementScope(source: entitlement, child: scoped)
        : scoped,
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
  await tester.pumpAndSettle();
  return source;
}

void main() {
  group('F1-25-14 the statement-import gate (ADR 2026-09-25 §3, §5–§6 🔒)', () {
    testWidgets('F1-25-14 with no token S7 lists no A/C and picks no file: it '
        'says import is not on this plan, that entries by hand still work, '
        'and offers the plans', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      var plans = 0;
      final source = await _pump(tester, onOpenPlans: () => plans++);

      expect(source.pickAccountCalls, 0);
      expect(find.text(l10n.importGateTitle), findsOneWidget);
      expect(find.text(l10n.importGateBody), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text(l10n.importFileChoose), findsNothing);

      await tester.tap(find.text(l10n.importGateSeePlans));
      await tester.pumpAndSettle();
      expect(plans, 1);
    });

    testWidgets('F1-25-14 on the real import routes, with no onOpenPlans '
        'given, See plans lands on S12.1 through the mounted GoRouter', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final source = FakeImportSource(
        accounts: const [
          ImportAccount(id: 'a1', name: 'Test Bank', bankKey: 'test'),
        ],
      );
      final router = GoRouter(
        initialLocation: ImportPaths.root,
        routes: [
          ...importRoutes,
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
          db: await openTestDb(),
          sync: FakeSyncClient(),
          auth: FakeAuthClient(),
          keys: FakeKeyStore(),
          now: testNow,
          child: ImportScope(
            source: source,
            filePort: FakeStatementFilePort(),
            bookId: 'book-1',
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
      expect(source.pickAccountCalls, 0);
      expect(find.text(l10n.importGateTitle), findsOneWidget);
      await tester.tap(find.text(l10n.importGateSeePlans));
      await tester.pumpAndSettle();
      expect(find.text('plans-landed'), findsOneWidget);
    });

    testWidgets('F1-25-14 the gate asks the features, not the name — through '
        'the mounted EntitlementScope as the shell provides it', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // A plan called free whose token carries statement_import imports.
      var source = await _pump(
        tester,
        viaScope: true,
        entitlement: FakeEntitlementSource(
          entitlement: _reading(RkPlan.free, [RkFeature.statementImport.wire]),
        ),
      );
      expect(source.pickAccountCalls, 1);
      expect(find.text(l10n.importGateTitle), findsNothing);
      expect(find.text('Test Bank'), findsOneWidget);

      // A plan called family whose token carries only PDF does not.
      source = await _pump(
        tester,
        viaScope: true,
        entitlement: FakeEntitlementSource(
          entitlement: _reading(RkPlan.family, [RkFeature.pdfOutput.wire]),
        ),
      );
      expect(source.pickAccountCalls, 0);
      expect(find.text(l10n.importGateTitle), findsOneWidget);
    });

    testWidgets('F1-25-14 a reading that cannot be made is the error state '
        'with retry — never a licence to import', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final broken = FakeEntitlementSource(failure: StateError('no store'));
      final source = await _pump(tester, entitlement: broken);
      expect(source.pickAccountCalls, 0);
      expect(find.text(l10n.importError), findsOneWidget);

      broken
        ..failure = null
        ..entitlement = _reading(RkPlan.family, [
          RkFeature.statementImport.wire,
        ]);
      await tester.tap(find.text(l10n.importRetry));
      await tester.pumpAndSettle();
      expect(source.pickAccountCalls, 1);
      expect(broken.reads, 2);
    });

    testWidgets('F1-25-14 the gated state resolves in EN, PA and HI with '
        'nothing cut at 200 % on either phone', (tester) async {
      for (final locale in rkLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        for (final viewport in rkPhones) {
          await _pump(
            tester,
            onOpenPlans: () {},
            locale: locale,
            textScale: 2,
            viewport: viewport,
          );
          expect(find.text(l10n.importGateTitle), findsOneWidget);
          expectTextFits(
            tester,
            reason: '${locale.languageCode} gated S7 on $viewport',
          );
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}
