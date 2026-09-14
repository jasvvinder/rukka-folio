// F1-13-17 — the layout base (ADR 2026-09-13b §2 🔒, ratified 14 Sep 2026):
// breakpoints, the two-tier width rule, and the rail threshold.
//
// Three things are asserted and they are not interchangeable:
//   1. the numbers match `design/tokens/tokens.json` — the sole token source;
//   2. the shell applies the width rule, so no screen has to know about it;
//   3. the rail appears at `expanded` and nowhere below it, with exactly the
//      bar's destinations.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:io';

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

/// `scripts/gen_tokens.dart` has no `layout` emitter, so `RkLayout` mirrors
/// tokens.json by hand. This reads the source of truth and the mirror is
/// checked against it — tokens and code cannot drift silently.
Map<String, dynamic> layoutTokens() {
  for (final path in [
    '../design/tokens/tokens.json',
    'design/tokens/tokens.json',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json['layout'] as Map<String, dynamic>;
  }
  fail('design/tokens/tokens.json not found from ${Directory.current.path}');
}

/// A tab root that reports the width it was actually given.
class _Measured extends StatelessWidget {
  const _Measured({required this.name, this.wide = false});

  final String name;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final body = Scaffold(key: ValueKey(name), body: const SizedBox.expand());
    return wide ? RkWideSurface(child: body) : body;
  }
}

Future<GoRouter> pumpShell(
  WidgetTester tester, {
  required Size viewport,
  RkTabRoot? home,
}) async {
  rkViewport(tester, viewport);
  final db = await openTestDb();
  final router = buildRouter(featureRoutes: const [], home: home);
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

void main() {
  test('F1-13-17 breakpoints and the measure come from tokens.json', () {
    final layout = layoutTokens();
    final bp = layout['breakpoint'] as Map<String, dynamic>;
    expect(
      (bp['compact'] as num).toDouble(),
      0,
      reason: 'compact is the floor — there is no narrower class',
    );
    expect((bp['medium'] as num).toDouble(), RkLayout.mediumMin);
    expect((bp['expanded'] as num).toDouble(), RkLayout.expandedMin);
    expect(
      (layout['readableMeasure'] as num).toDouble(),
      RkLayout.readableMeasure,
    );
    expect((layout['railMinWidth'] as num).toDouble(), RkLayout.railMinWidth);
    // Material 3's canonical set, which Flutter aligns to (ADR §2).
    expect([RkLayout.mediumMin, RkLayout.expandedMin], [600.0, 840.0]);
  });

  test(
    'F1-13-17 the three window classes, at and either side of every edge',
    () {
      expect(RkLayout.forWidth(0), RkBreakpoint.compact);
      expect(RkLayout.forWidth(320), RkBreakpoint.compact);
      expect(RkLayout.forWidth(360), RkBreakpoint.compact);
      expect(RkLayout.forWidth(599.99), RkBreakpoint.compact);
      expect(RkLayout.forWidth(600), RkBreakpoint.medium);
      // Portrait iPads measure roughly 744–834pt and are therefore medium.
      expect(RkLayout.forWidth(744), RkBreakpoint.medium);
      expect(RkLayout.forWidth(834), RkBreakpoint.medium);
      expect(RkLayout.forWidth(839.99), RkBreakpoint.medium);
      expect(RkLayout.forWidth(840), RkBreakpoint.expanded);
      // Landscape iPads are expanded.
      expect(RkLayout.forWidth(1194), RkBreakpoint.expanded);
      expect(RkLayout.forWidth(1366), RkBreakpoint.expanded);

      // The rail threshold is `expanded` and nothing else.
      expect(RkLayout.railAt(RkBreakpoint.compact), isFalse);
      expect(RkLayout.railAt(RkBreakpoint.medium), isFalse);
      expect(RkLayout.railAt(RkBreakpoint.expanded), isTrue);
    },
  );

  testWidgets(
    'F1-13-17 a phone is never capped — the rule cannot engage below 600',
    (tester) async {
      for (final viewport in rkPhones) {
        await pumpShell(
          tester,
          viewport: viewport,
          home: RkTabRoot(builder: (c) => const _Measured(name: 'reading')),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('reading'))).width,
          viewport.width,
          reason: 'no cap at ${viewport.width}',
        );
      }
    },
  );

  testWidgets(
    'F1-13-17 the shell caps a reading surface to the readable measure and centres it',
    (tester) async {
      await pumpShell(
        tester,
        viewport: rkTabletPortrait,
        home: RkTabRoot(builder: (c) => const _Measured(name: 'reading')),
      );
      final pane = find.byKey(const ValueKey('reading'));
      expect(tester.getSize(pane).width, RkLayout.readableMeasure);
      // Centred: equal slack either side of the content region.
      expect(
        tester.getCenter(pane).dx,
        moreOrLessEquals(rkTabletPortrait.width / 2, epsilon: 0.5),
      );
      // Full height: a capped surface is still a whole screen.
      expect(
        tester.getSize(pane).height,
        greaterThan(rkTabletPortrait.height * 0.8),
      );
    },
  );

  testWidgets(
    'F1-13-17 a professional surface is NOT capped — it takes the width it is given',
    (tester) async {
      // The statement, trial balance and reports opt out with RkWideSurface:
      // `ਨਾਮੇ | ਜਮ੍ਹਾਂ | ਬਾਕੀ` is a real data table (design-system §3.1 rule 8)
      // and capping it would waste the tablet a bookkeeper bought.
      await pumpShell(
        tester,
        viewport: rkTabletPortrait,
        home: RkTabRoot(
          builder: (c) => const _Measured(name: 'statement', wide: true),
        ),
      );
      final wide = find.byKey(const ValueKey('statement'));
      expect(tester.getSize(wide).width, rkTabletPortrait.width);
      expect(
        tester.getCenter(wide).dx,
        moreOrLessEquals(rkTabletPortrait.width / 2, epsilon: 0.5),
      );
    },
  );

  testWidgets('F1-13-17 RkWideSurface outside a shell is a no-op', (
    tester,
  ) async {
    // Screen tests pump screens directly and always will (ADR §3): a
    // professional screen must render identically with no shell above it.
    await pumpRk(
      tester,
      const RkWideSurface(child: SizedBox.expand(key: ValueKey('bare'))),
      viewport: rkPhone360,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('bare'))).width,
      rkPhone360.width,
    );
  });

  testWidgets(
    'F1-13-17 the shell swaps the bar for a rail at expanded and nowhere below it',
    (tester) async {
      await pumpShell(tester, viewport: rkTabletPortrait);
      expect(
        find.byType(RkTabBar),
        findsOneWidget,
        reason: 'medium keeps the bar',
      );
      expect(find.byType(RkNavRail), findsNothing);

      await pumpShell(tester, viewport: rkTabletLandscape);
      expect(find.byType(RkNavRail), findsOneWidget);
      expect(find.byType(RkTabBar), findsNothing);
    },
  );

  testWidgets(
    'F1-13-17 the rail is a presentation switch, not a second information architecture',
    (tester) async {
      // The bar's own labels are asserted at medium by F1-13-1..5; here the
      // rail must carry the same four, in the same order, from the same keys.
      const labels = ['Home', 'Ledger', 'Inbox', 'Menu'];
      final router = await pumpShell(tester, viewport: rkTabletLandscape);
      // Same four destinations, same ARB-sourced labels, same order.
      for (final l in labels) {
        expect(find.text(l), findsOneWidget, reason: 'rail label $l');
      }
      final xs = labels.map((l) => tester.getCenter(find.text(l)).dy).toList();
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i], greaterThan(xs[i - 1]), reason: 'rail order');
      }
      // Same centre ( + ), still an action and never a destination.
      expect(find.byType(RkCentreAction), findsOneWidget);

      // It navigates the same branches.
      await tester.tap(find.text('Inbox'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, RkPaths.inbox);
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, RkPaths.menu);
    },
  );

  testWidgets('F1-13-17 the rail survives 200 % text scale without overflow', (
    tester,
  ) async {
    for (final scale in rkTextScales) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpShell(tester, viewport: rkTabletLandscape);
      expect(
        tester.takeException(),
        isNull,
        reason: 'no overflow at ${scale}x',
      );
      final rail = tester.getSize(find.byType(RkNavRail));
      expect(rail.width, greaterThanOrEqualTo(RkLayout.railMinWidth));
      expect(rail.width, lessThan(rkTabletLandscape.width * 0.3));
      expectTextFits(tester, reason: 'rail at ${scale}x');
    }
  });
}
