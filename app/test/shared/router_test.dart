@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import 'test_app.dart';

void main() {
  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    List<RouteBase> featureRoutes = const [],
  }) async {
    final db = await openTestDb();
    final router = buildRouter(featureRoutes: featureRoutes);
    await tester.pumpWidget(
      RukkaFolioApp(
        db: db,
        sync: FakeSyncClient(),
        auth: FakeAuthClient(),
        now: testNow,
        locale: const Locale('en'),
        router: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  // `state` resolves the topmost match — a pushed screen, not only the last `go`.
  String location(GoRouter r) => r.state.uri.path;

  testWidgets(
    'F1-13-6 shell opens on /home; tabs switch branches; ( + ) pushes /entry over the bar',
    (tester) async {
      final router = await pumpApp(tester);
      expect(location(router), RkPaths.home);
      expect(find.byType(RkTabBar), findsOneWidget);

      await tester.tap(find.text('Ledger'));
      await tester.pumpAndSettle();
      expect(location(router), RkPaths.ledger);
      expect(
        find.text('Every account, A to Z, will be listed here.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();
      expect(location(router), RkPaths.inbox);
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(location(router), RkPaths.menu);

      // The centre action is a push, not a tab: /entry covers the shell.
      await tester.tap(find.byType(RkCentreAction));
      await tester.pumpAndSettle();
      expect(location(router), RkPaths.entry);
      expect(find.byType(RkTabBar), findsNothing);
      expect(find.text('The entry keypad will appear here.'), findsOneWidget);

      // Back returns to the tab that was active — nothing was "selected".
      router.pop();
      await tester.pumpAndSettle();
      expect(location(router), RkPaths.menu);
      expect(find.byType(RkTabBar), findsOneWidget);
    },
  );

  testWidgets('F1-13-7 feature routes compose onto the root navigator', (
    tester,
  ) async {
    final router = await pumpApp(
      tester,
      featureRoutes: [
        GoRoute(
          path: '/probe',
          builder: (_, _) => const Scaffold(body: Text('probe screen')),
        ),
      ],
    );
    router.push('/probe');
    await tester.pumpAndSettle();
    expect(location(router), '/probe');
    expect(find.text('probe screen'), findsOneWidget);
  });
}
