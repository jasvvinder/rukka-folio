@Tags(['F1'])
library;

// The Menu tab's *Help* row, driven through a real router (07 §2 🔒 row 8,
// 13 §3.2 rows S8 and S17; 07 §1 rule 6 🔒 no dead ends).
//
// F1-07-382 holds the row itself — live, with a subtitle, in its 07 §2 place —
// but it pumps `MenuScreen` with `onOpenHelp: () => help++` and asserts the
// counter. A counter is reached whatever the callback then does, so that test
// cannot see the one failure that matters to a person holding the phone: the
// row navigating to a path nothing is mounted at. This file taps the row on
// the production `menuRoot` (so `MenuTab` supplies `onOpenHelp`, not the test)
// and requires S17 to actually draw.
//
// It composes the shell itself rather than going through `RukkaFolioApp`, so
// the wire is checked without compiling every other feature.
//
// ⚠️ It builds its own `buildRouter` over `helpRoutes`, because the app's own
// route list lives in `app/lib/bootstrap.dart`, which this lane does not own
// and which does **not** yet mount `helpRoutes` — see the lane report. So this
// test pins `features/menu`'s half of the wire (the path it pushes is the path
// `features/help` declares, and S17 renders there); the composition root's
// half stays an owner item until bootstrap mounts the feature.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/help/help_routes.dart';
import 'package:rukka_folio/features/menu/menu_routes.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

void main() {
  group('S8 Menu → S17 Help', () {
    testWidgets(
      'F1-07-415 tapping the Menu tab\'s Help row reaches S17 through the '
      'real router — the row pushes the path features/help declares, and a '
      'screen is drawn there rather than a router error page',
      (tester) async {
        rkViewport(tester, rkTallViewport);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final db = await openTestDb();
        final router = buildRouter(
          featureRoutes: helpRoutes,
          menu: menuRoot,
          initialLocation: RkPaths.menu,
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

        final help = find.text(l10n.menuHelpRowTitle);
        await tester.ensureVisible(help);
        await tester.pumpAndSettle();
        await tester.tap(help);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), HelpPaths.root);
        expect(find.byType(HelpScreen), findsOneWidget);
        expect(find.text(l10n.helpSectionFaq), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
