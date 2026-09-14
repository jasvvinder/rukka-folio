// F1-13-19 — the shell is tested through, not around (ADR 2026-09-13b §3 🔒).
//
// Every tab root is mounted inside the **real** RkShell and asserted to have a
// content region with a non-zero height and its content on stage. No such test
// existed, which is why RkTabBar — taking the full screen height as
// `bottomNavigationBar` and leaving every tab's body at zero — shipped in M5
// and survived two green gates.
//
// Measured before the fix, at 800x600 with no feature code at all:
//   RkTabBar                 800.0 x 600.0
//   StatefulNavigationShell  800.0 x   0.0
//
// So the assertions here are on **height**, never on `findsOneWidget` alone:
// a `Text` in a zero-height viewport still has an element and `find.text`
// still passes, which is exactly what failed to catch this for a milestone.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/layout.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_nav_rail.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import 'test_app.dart';

/// A tab root that is honest about its viewport: a lazy list, which builds no
/// rows at all when the shell hands it zero height.
class _RowsRoot extends StatelessWidget {
  const _RowsRoot(this.tab);

  final RkTab tab;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: ValueKey('root-${tab.name}'),
    body: ListView.builder(
      itemCount: 40,
      itemExtent: 56,
      itemBuilder: (context, i) => Text('${tab.name} row $i'),
    ),
  );
}

Future<GoRouter> pumpShell(
  WidgetTester tester, {
  Size viewport = rkPhone360,
  RkTabRoot? home,
  RkTabRoot? ledger,
  RkTabRoot? inbox,
  RkTabRoot? menu,
  String initialLocation = RkPaths.home,
}) async {
  rkViewport(tester, viewport);
  final db = await openTestDb();
  final router = buildRouter(
    featureRoutes: const [],
    home: home,
    ledger: ledger,
    inbox: inbox,
    menu: menu,
    initialLocation: initialLocation,
  );
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

/// Size of the branch content region the shell handed the current tab.
Size contentSize(WidgetTester tester) =>
    tester.getSize(find.byType(StatefulNavigationShell));

void main() {
  // One test per viewport: each re-pumps the whole app, and a fresh GoRouter
  // in a re-used widget tree does not always re-attach, so the viewports are
  // registered rather than looped.
  for (final viewport in [...rkPhones, ...rkTablets]) {
    final at = '${viewport.width.toInt()}x${viewport.height.toInt()}';
    testWidgets(
      'F1-13-19 at $at every tab root gets a content region with real height inside the real shell',
      (tester) async {
        final router = await pumpShell(
          tester,
          viewport: viewport,
          home: RkTabRoot(builder: (c) => const _RowsRoot(RkTab.home)),
          ledger: RkTabRoot(builder: (c) => const _RowsRoot(RkTab.ledger)),
          inbox: RkTabRoot(builder: (c) => const _RowsRoot(RkTab.inbox)),
          menu: RkTabRoot(builder: (c) => const _RowsRoot(RkTab.menu)),
        );
        for (final tab in RkTab.values) {
          // Drive the branch through the router, not the bar: at `expanded`
          // there is no bar, and the assertion must hold on both form factors.
          router.go(RkPaths.of(tab));
          await tester.pumpAndSettle();

          final content = contentSize(tester);
          final root = tester.getSize(find.byKey(ValueKey('root-${tab.name}')));
          final where = '${tab.name} at $at';

          // The whole point: a content region, not a sliver of nothing.
          expect(content.height, greaterThan(0), reason: 'content h, $where');
          expect(content.width, greaterThan(0), reason: 'content w, $where');
          expect(root.height, greaterThan(0), reason: 'root height, $where');

          // …and enough of it that the screen is usable: the navigation may
          // take a bar or a rail, never the body. Before the fix this was 0 %.
          expect(
            content.height,
            greaterThan(viewport.height * 0.6),
            reason: 'content should keep most of the screen, $where',
          );

          // Content actually on stage, and a lazy list really building rows —
          // the failure mode `find.text` alone cannot see.
          expect(find.text('${tab.name} row 0'), findsOneWidget, reason: where);
          expect(find.text('${tab.name} row 3'), findsOneWidget, reason: where);
        }
      },
    );

    testWidgets(
      'F1-13-19 at $at the navigation bounds its own height instead of filling the screen',
      (tester) async {
        for (final scale in [1.0, ...rkTextScales]) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpShell(tester, viewport: viewport);

          if (RkLayout.forWidth(viewport.width) == RkBreakpoint.expanded) {
            expect(find.byType(RkTabBar), findsNothing);
            expect(
              tester.getSize(find.byType(RkNavRail)).width,
              lessThan(viewport.width * 0.3),
              reason: 'rail must not eat the screen, $at @ ${scale}x',
            );
            expect(
              contentSize(tester).height,
              greaterThan(viewport.height - 1),
            );
            continue;
          }

          final bar = tester.getSize(find.byType(RkTabBar));
          final where = '$at @ ${scale}x';
          expect(
            bar.height,
            greaterThanOrEqualTo(RkTabBarSpec.minHeight),
            reason: 'bar keeps its locked min-height, $where',
          );
          // Bounded by its content, never by what it was offered. Before the
          // fix this measured the full screen height at every scale.
          expect(
            bar.height,
            lessThan(viewport.height * 0.3),
            reason: 'bar must not eat the screen, $where',
          );
          expect(
            contentSize(tester).height,
            greaterThan(viewport.height - bar.height - 1),
            reason: 'everything the bar does not take is content, $where',
          );
        }
      },
    );
  }

  testWidgets(
    'F1-13-19 the shell renders the real placeholder roots with their text visible, not merely present',
    (tester) async {
      await pumpShell(tester, viewport: rkPhone375);
      // Default roots (no feature routes) — the tree M5 shipped.
      for (final label in ['Ledger', 'Inbox', 'Menu']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(contentSize(tester).height, greaterThan(0));
        // On stage means inside the content region, with area of its own.
        final body = find.descendant(
          of: find.byType(StatefulNavigationShell),
          matching: find.byType(Text),
        );
        expect(body, findsWidgets);
        expect(tester.getSize(body.first).height, greaterThan(0));
      }
    },
  );

  testWidgets('F1-13-19 the rail shell gives its content real height too', (
    tester,
  ) async {
    await pumpShell(
      tester,
      viewport: rkTabletLandscape,
      home: RkTabRoot(builder: (c) => const _RowsRoot(RkTab.home)),
    );
    expect(find.byType(RkNavRail), findsOneWidget);
    expect(find.byType(RkTabBar), findsNothing);
    final content = contentSize(tester);
    expect(content.height, greaterThan(rkTabletLandscape.height * 0.9));
    expect(
      content.width,
      lessThan(rkTabletLandscape.width - RkLayout.railMinWidth + 1),
    );
    expect(find.text('home row 0'), findsOneWidget);
  });
}
