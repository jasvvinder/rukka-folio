@Tags(['F1'])
library;

// The Menu tab's *Subscription* row and the Settings hub's, both driven
// through a real router (07 §2 🔒 row 6, 07 §16, 13 §3.2 rows S8, S13 and
// S12; 07 §1 rule 6 🔒 no dead ends).
//
// F1-07-77 holds the Menu row itself — live, with a subtitle, in its 07 §2
// place — but it pumps `MenuScreen` with `onOpenSubscription: () => n++` and
// asserts the counter. A counter is reached whatever the callback then does,
// so that test cannot see the one failure that matters to a person holding
// the phone: the row navigating to a path nothing is mounted at. This file
// taps the rows on the production `menuRoot` / `settingsRoutes` (so the
// feature supplies the callback, not the test) and requires S12 to draw.
//
// ⚠️ It builds its own `buildRouter` over `subscriptionRoutes`, because the
// app's own route list lives in `app/lib/bootstrap.dart`, which this lane
// does not own and which does **not** yet mount `subscriptionRoutes` — see
// the lane report. So this test pins each feature's half of the wire; the
// composition root's half stays an owner item.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/menu/menu_routes.dart';
import 'package:rukka_folio/features/settings/settings_routes.dart';
import 'package:rukka_folio/features/subscription/subscription_routes.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

Future<GoRouter> _pumpShell(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  rkViewport(tester, rkTallViewport);
  final db = await openTestDb();
  final router = buildRouter(
    featureRoutes: [...subscriptionRoutes, ...settingsRoutes],
    menu: menuRoot,
    initialLocation: initialLocation,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RkScope(
      db: db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: FakeKeyStore(),
      now: testNow,
      child: MaterialApp.router(
        routerConfig: router,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: rkLocalizationsDelegates,
        theme: rkTheme(Brightness.light),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('S8 Menu / S13 Settings → S12 Subscription', () {
    testWidgets(
      'F1-07-466 tapping the Menu tab\'s Subscription row reaches S12 through '
      'the real router — the row pushes the path features/subscription '
      'declares, and a screen is drawn there rather than a router error page',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final router = await _pumpShell(tester, initialLocation: RkPaths.menu);

        final row = find.text(l10n.menuSubscriptionRowTitle);
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), SubscriptionPaths.root);
        expect(find.byType(SubscriptionScreen), findsOneWidget);
        // With no producer wired, the honest reading is *Free, never locked*
        // (ADR 2026-09-05g §1 🔒) — not an error and not a lock.
        expect(find.text(l10n.subscriptionPlanFree), findsOneWidget);
        expect(find.text(l10n.subscriptionRenewalNone), findsOneWidget);
        expect(find.text(l10n.subscriptionError), findsNothing);
        expect(tester.takeException(), isNull);

        // …and S12.1 is one level below it, not a dead end.
        await tester.tap(find.text(l10n.subscriptionRowPlansTitle));
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), SubscriptionPaths.plans);
        expect(find.byType(PlansScreen), findsOneWidget);
        expect(find.text(l10n.plansNeverLocked), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-467 tapping the Settings hub\'s Subscription row reaches the '
      'same S12 (07 §16)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final router = await _pumpShell(
          tester,
          initialLocation: SettingsPaths.root,
        );

        final row = find.text(l10n.settingsSubscriptionRowTitle);
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), SubscriptionPaths.root);
        expect(find.byType(SubscriptionScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
