// F1-24b-8 … F1-24b-10, F1-24b-13 … F1-24b-15 — the entitlement and the plan
// catalogue reach the whole app, and the shell says so when it is read-only (ADR 2026-09-24b §13, §14; ADR 2026-09-05g §5
// *lapsed ≠ locked*; 13 §3.2 row S12.5 scope = global; 07 §1 rules 3 and 6).
//
// The bug these tests pin: `EntitlementScope` was mounted by nobody in
// production, and a screen-level mount is invisible to a modal sheet — the
// sheet's route is a *sibling* of the Home route under the root navigator,
// not a child of it. So the scope must sit above `MaterialApp.router`, which
// is where `RukkaFolioApp` now puts it. The negative control proves the test
// can tell the two mounts apart.
@Tags(['F1'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/entry_restriction.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/plan_catalogue_source.dart';
import 'package:rukka_folio/features/subscription/subscription_paths.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_entitlement_banner.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import 'test_app.dart';

/// A reading of [grace] from a token this phone holds, [source] fresh unless
/// said otherwise. Synthetic tenant id (CLAUDE.md rule 4).
Entitlement reading(
  EntitlementGraceKind grace, {
  EntitlementSourceKind source = EntitlementSourceKind.fresh,
}) => Entitlement.fromToken(
  tenantId: 'tenant-test',
  plan: RkPlan.family,
  limits: rkTierFor(RkPlan.family).limits,
  graceKind: grace,
  times: const EntitlementTokenTimes(),
  source: source,
  activeMembers: 1,
);

FakeEntitlementSource lapsed() =>
    FakeEntitlementSource(entitlement: reading(EntitlementGraceKind.lapsed));

const _homeKey = ValueKey('home-root');
const _plansMarker = 'plans-route-marker';

/// A Home root with one button that opens a bottom sheet on the **root**
/// navigator — the way every S12.5-raising sheet in the app is shown.
class _SheetOpener extends StatelessWidget {
  const _SheetOpener({required this.onSheet});

  final void Function(BuildContext sheetContext) onSheet;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _homeKey,
    body: Center(
      child: TextButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          builder: (sheetContext) {
            onSheet(sheetContext);
            return const SizedBox(height: 120, child: Text('sheet'));
          },
        ),
        child: const Text('open sheet'),
      ),
    ),
  );
}

Future<void> pumpApp(
  WidgetTester tester, {
  EntitlementSource? entitlement,
  PlanCatalogueSource? planCatalogue,
  RkTabRoot? home,
  Locale locale = const Locale('en'),
  Size viewport = rkPhone360,
  double textScale = 1,
  double keyboard = 0,
}) async {
  rkViewport(tester, viewport);
  if (keyboard > 0) {
    // Logical == physical here: `rkViewport` sets a ratio of 1.
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
  }
  final db = await openTestDb();
  final router = buildRouter(
    featureRoutes: [
      GoRoute(
        path: SubscriptionPaths.plans,
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text(_plansMarker))),
      ),
    ],
    home:
        home ??
        RkTabRoot(
          builder: (_) => const Scaffold(
            key: _homeKey,
            body: Center(child: Text('home body')),
          ),
        ),
  );
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    RukkaFolioApp(
      db: db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      now: testNow,
      locale: locale,
      router: router,
      entitlement: entitlement,
      planCatalogue: planCatalogue,
    ),
  );
  await tester.pumpAndSettle();
}

Finder get banner => find.byType(RkRestrictionBanner);

/// The shell banner as a whole — its rect is the part actually drawn.
Finder get shellBanner => find.byType(RkEntitlementBanner);

/// The banner's one way forward.
Finder get renew =>
    find.descendant(of: shellBanner, matching: find.byType(TextButton));

/// Fails unless *Renew* is drawn whole inside the visible banner, above
/// [bottom] (the keyboard's top edge, or the screen's), **and** a tap at its
/// centre lands on it. `find.descendant` alone also finds a button scrolled
/// out of its viewport, which is how F1-24b-10 once stayed green over a
/// banner whose only action could not be seen (SH1 review, 1 Oct 2026).
void expectRenewInView(WidgetTester tester, {required double bottom}) {
  expect(renew, findsOneWidget);
  final r = tester.getRect(renew);
  final b = tester.getRect(shellBanner);
  expect(
    r.top >= b.top - 0.5 && r.bottom <= b.bottom + 0.5,
    isTrue,
    reason: 'Renew $r lies outside the drawn banner $b',
  );
  expect(r.bottom, lessThanOrEqualTo(bottom + 0.5), reason: 'Renew $r');
  final hit = tester.hitTestOnBinding(r.center);
  final target = tester.renderObject(renew);
  expect(
    hit.path.any((e) => identical(e.target, target)),
    isTrue,
    reason: 'a tap at the centre of Renew $r misses it',
  );
}

/// Fails unless the banner's words can all be scrolled into view, and says
/// so with a scrollbar whenever there is more to read than is drawn.
Future<void> expectWordsReachable(WidgetTester tester) async {
  final viewport = find.descendant(
    of: shellBanner,
    matching: find.byType(Scrollable),
  );
  expect(viewport, findsOneWidget);
  final position = tester.state<ScrollableState>(viewport).position;
  if (position.maxScrollExtent > 0) {
    final bar = tester.widget<Scrollbar>(
      find.descendant(of: shellBanner, matching: find.byType(Scrollbar)),
    );
    expect(bar.thumbVisibility, isTrue, reason: 'hidden overflow');
  }
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
  final last = find.descendant(of: banner, matching: find.byType(Text)).last;
  expect(
    tester.getRect(last).bottom,
    lessThanOrEqualTo(tester.getRect(viewport).bottom + 0.5),
    reason: 'the banner\'s last line cannot be scrolled into view',
  );
}

void main() {
  group('F1-24b-8 EntitlementScope sits above the router', () {
    testWidgets('F1-24b-8 a sheet opened from Home reads the app\'s source', (
      tester,
    ) async {
      final source = lapsed();
      EntitlementScope? seen;
      RkRestrictionKind? kind;
      await pumpApp(
        tester,
        entitlement: source,
        home: RkTabRoot(
          builder: (_) => _SheetOpener(
            onSheet: (c) {
              seen = EntitlementScope.maybeOf(c);
              kind = null;
              entryRestrictionFor(
                entryRestrictionSourcesOf(c),
                const [],
              ).then((k) => kind = k);
            },
          ),
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      expect(find.text('sheet'), findsOneWidget);
      expect(seen, isNotNull, reason: 'the sheet cannot see the scope');
      expect(identical(seen!.source, source), isTrue);
      // The public gate, asked from the sheet's own context, answers from
      // that source — not from the untokened fallback.
      expect(kind, RkRestrictionKind.readOnly);
      expect(source.reads, greaterThan(0));
    });

    testWidgets(
      'F1-24b-8 with no source given, production binds the untokened one',
      (tester) async {
        EntitlementScope? seen;
        await pumpApp(
          tester,
          home: RkTabRoot(
            builder: (_) => _SheetOpener(
              onSheet: (c) => seen = EntitlementScope.maybeOf(c),
            ),
          ),
        );
        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();
        expect(seen, isNotNull);
        expect(seen!.source, isA<UntokenedEntitlementSource>());
        // Free and never locked (ADR 2026-09-05g §1): no banner.
        expect(banner, findsNothing);
      },
    );

    testWidgets(
      'F1-24b-8 negative control: a screen-level mount is invisible to the sheet',
      (tester) async {
        EntitlementScope? seen;
        var opened = false;
        await pumpApp(
          tester,
          home: RkTabRoot(
            builder: (_) => EntitlementScope(
              source: lapsed(),
              child: _SheetOpener(
                onSheet: (c) {
                  opened = true;
                  seen = EntitlementScope.maybeOf(c);
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();
        expect(opened, isTrue);
        // The nearest scope is the app's untokened one — never the lapsed
        // source mounted around the Home screen.
        expect(seen?.source, isA<UntokenedEntitlementSource>());
      },
    );
  });

  group('F1-24b-9 the global read-only banner', () {
    testWidgets('F1-24b-9 read-only: words, icon, and one way forward', (
      tester,
    ) async {
      await pumpApp(tester, entitlement: lapsed());

      expect(banner, findsOneWidget);
      expect(find.byType(RkEntitlementBanner), findsOneWidget);
      final b = tester.widget<RkRestrictionBanner>(banner);
      expect(b.kind, RkRestrictionKind.readOnly);
      // Colour never alone (07 §1 rule 3): the words and the icon travel
      // with the tint.
      expect(
        find.descendant(
          of: banner,
          matching: find.text('Your books are read-only'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: banner, matching: find.byIcon(Icons.lock_outline)),
        findsOneWidget,
      );
      // ADR 2026-09-24b §14: no dead *Export everything* button until the
      // whole-tenant export route exists.
      expect(find.text('Export everything'), findsNothing);
      // The shell's content region still has a real height under it.
      expect(tester.getSize(find.byKey(_homeKey)).height, greaterThan(0));

      expect(
        find.descendant(of: renew, matching: find.text('Renew')),
        findsOneWidget,
      );
      expectRenewInView(tester, bottom: rkPhone360.height);
      await tester.tap(renew);
      await tester.pumpAndSettle();
      expect(find.text(_plansMarker), findsOneWidget);
    });

    testWidgets('F1-24b-9 the banner stays on every tab', (tester) async {
      await pumpApp(tester, entitlement: lapsed());
      expect(banner, findsOneWidget);
      await tester.tap(find.text('Ledger'));
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);
    });

    final quiet = <String, EntitlementSource>{
      'active': FakeEntitlementSource(
        entitlement: reading(EntitlementGraceKind.none),
      ),
      'dunning grace (the grace itself)': FakeEntitlementSource(
        entitlement: reading(EntitlementGraceKind.dunning),
      ),
      // Offline grace is device-local and never says lapsed (ADR
      // 2026-09-05g §4 🔒): a stale lapsed token shows no read-only banner.
      'stale lapsed token (offline grace)': FakeEntitlementSource(
        entitlement: reading(
          EntitlementGraceKind.lapsed,
          source: EntitlementSourceKind.stale,
        ),
      ),
      'untokened': const UntokenedEntitlementSource(),
      // ADR 2026-09-24b §14: a failed read is untokened — never locked.
      'failed read': FakeEntitlementSource(failure: StateError('unreadable')),
    };
    for (final e in quiet.entries) {
      testWidgets('F1-24b-9 no banner when ${e.key}', (tester) async {
        await pumpApp(tester, entitlement: e.value);
        expect(banner, findsNothing);
        expect(find.text('Your books are read-only'), findsNothing);
      });
    }

    testWidgets('F1-24b-9 a lapse learned while backgrounded shows on resume', (
      tester,
    ) async {
      final source = FakeEntitlementSource(
        entitlement: reading(EntitlementGraceKind.none),
      );
      await pumpApp(tester, entitlement: source);
      expect(banner, findsNothing);

      source.entitlement = reading(EntitlementGraceKind.lapsed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);
    });
  });

  group('F1-24b-10 the banner at 200 % in EN/PA/HI', () {
    const titles = {
      'en': 'Your books are read-only',
      'pa': 'ਤੁਹਾਡੀਆਂ ਬਹੀਆਂ ਸਿਰਫ਼ ਪੜ੍ਹਨ ਲਈ ਹਨ',
      'hi': 'आपकी बहियाँ अभी सिर्फ़ पढ़ने के लिए हैं',
    };
    for (final locale in rkLocales) {
      for (final phone in rkPhones) {
        testWidgets('F1-24b-10 ${locale.languageCode} at 200 % on '
            '${phone.width.toInt()}x${phone.height.toInt()}', (tester) async {
          await pumpApp(
            tester,
            entitlement: lapsed(),
            locale: locale,
            viewport: phone,
            textScale: 2,
          );
          expect(tester.takeException(), isNull);
          expect(
            find.descendant(
              of: banner,
              matching: find.text(titles[locale.languageCode]!),
            ),
            findsOneWidget,
          );
          expectTextFits(tester);
          // Capped: past its share the banner scrolls inside itself.
          expect(
            tester.getSize(find.byType(RkEntitlementBanner)).height,
            lessThanOrEqualTo(phone.height * RkEntitlementBanner.maxShare),
          );
          // The tab's content keeps a real height under the banner.
          expect(tester.getSize(find.byKey(_homeKey)).height, greaterThan(0));
          // Capped, but never at the cost of the way forward (07 §1 rule 6;
          // 13 §8): Renew is in view and takes the tap, and every word
          // scrolls into view behind a visible scrollbar.
          expectRenewInView(tester, bottom: phone.height);
          await expectWordsReachable(tester);
          await tester.tap(renew);
          await tester.pumpAndSettle();
          expect(find.text(_plansMarker), findsOneWidget);
        });
      }
    }
  });

  group('F1-24b-13 Renew stays in view wherever the banner is capped', () {
    // The cap is a share of the shell's content height, which shrinks with
    // the keyboard (router.dart): the action must survive that too.
    final cases = <({double scale, double keyboard})>[
      (scale: 1.3, keyboard: 0),
      (scale: 1.5, keyboard: 0),
      (scale: 1, keyboard: 300),
      (scale: 2, keyboard: 300),
    ];
    for (final c in cases) {
      for (final locale in rkLocales) {
        for (final phone in rkPhones) {
          testWidgets('F1-24b-13 ${locale.languageCode} at ${c.scale}x, '
              'keyboard ${c.keyboard.toInt()} px, on '
              '${phone.width.toInt()}x${phone.height.toInt()}', (tester) async {
            await pumpApp(
              tester,
              entitlement: lapsed(),
              locale: locale,
              viewport: phone,
              textScale: c.scale,
              keyboard: c.keyboard,
            );
            expect(tester.takeException(), isNull);
            expectTextFits(tester);
            expectRenewInView(tester, bottom: phone.height - c.keyboard);
            await expectWordsReachable(tester);
            await tester.tap(renew);
            await tester.pumpAndSettle();
            expect(find.text(_plansMarker), findsOneWidget);
          });
        }
      }
    }

    for (final tablet in rkTablets) {
      testWidgets('F1-24b-13 en at 200 % on '
          '${tablet.width.toInt()}x${tablet.height.toInt()}', (tester) async {
        await pumpApp(
          tester,
          entitlement: lapsed(),
          viewport: tablet,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expectRenewInView(tester, bottom: tablet.height);
      });
    }
  });

  group('F1-24b-14 the plan catalogue sits above the router', () {
    testWidgets(
      'F1-24b-14 a sheet opened from Home reads the app\'s catalogue',
      (tester) async {
        final source = FakePlanCatalogueSource();
        PlanCatalogueSource? seen;
        await pumpApp(
          tester,
          planCatalogue: source,
          home: RkTabRoot(
            builder: (_) =>
                _SheetOpener(onSheet: (c) => seen = planCatalogueSourceOf(c)),
          ),
        );
        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();
        expect(identical(seen, source), isTrue, reason: 'got $seen');
      },
    );

    testWidgets(
      'F1-24b-14 negative control: none given is the offline mirror',
      (tester) async {
        PlanCatalogueSource? seen;
        await pumpApp(
          tester,
          home: RkTabRoot(
            builder: (_) =>
                _SheetOpener(onSheet: (c) => seen = planCatalogueSourceOf(c)),
          ),
        );
        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();
        expect(seen, isA<OfflinePlanCatalogueSource>());
      },
    );
  });

  test('F1-24b-15 bootstrap hands RukkaFolioApp the server plan catalogue', () {
    // Read like F1-24b-2 (`launch_reoffer_wiring_test`): comments stripped,
    // so prose naming the binding cannot stand in for it.
    String? code;
    for (final path in ['lib/bootstrap.dart', 'app/lib/bootstrap.dart']) {
      final file = File(path);
      if (!file.existsSync()) continue;
      code = [
        for (final line in file.readAsStringSync().split('\n'))
          line.contains('//') ? line.substring(0, line.indexOf('//')) : line,
      ].join('\n');
      break;
    }
    if (code == null) fail('lib/bootstrap.dart not found');
    final app = code.indexOf('RukkaFolioApp(');
    expect(app, greaterThanOrEqualTo(0));
    final bound = RegExp(r'planCatalogue:\s*HttpPlanCatalogueSource\(')
        .allMatches(code)
        .toList();
    expect(bound, hasLength(1), reason: 'one binding, to the server source');
    expect(
      bound.single.start,
      greaterThan(app),
      reason: 'the binding is an argument of RukkaFolioApp',
    );
    // With no catalogue bound, S12.1 silently shows the offline mirror
    // (`planCatalogueSourceOf`); that is the regression this pins.
    expect(code, isNot(contains('OfflinePlanCatalogueSource')));
    final call = code.substring(bound.single.start);
    expect(call, contains('functionsRoot: Uri.parse(apiBase)'));
    expect(call, contains('auth.accessToken()'));
  });
}
