// F1 — S1's four verbs pinned above the tab bar (canvas 1 O8 *Setup
// checklist · Home, first run*; canvas 15 S1 *Home · the baseline*; 07 §1
// rules 1–2 🔒, rule 11).
//
//   F1-1006c-10  the phase-1 journey on rf_min (360×800 dp) stopped at
//                'S1-verb': on first-run Home the verbs sat in the list below
//                the checklist, off-screen and unbuilt. They are now in a bar
//                pinned to the bottom of Home's body — hit-testable without a
//                scroll, the list still scrolling beneath, the bar staying put.
//   F1-1006c-11  the same holds on a populated Home (the c15 frame pins them
//                too).
//   F1-1006c-12  at 200 % in EN/PA/HI on 360×800 the bar reflows (2 × 2) and
//                nothing overflows; the verbs are still reachable.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import '../../shared/test_app.dart';

const _verbs = ['Money in', 'Money out', 'Gave on credit', 'Took on credit'];

/// Home as the shell's Home tab — content above the production tab bar, the
/// way the journey on rf_min sees it.
Future<void> _pumpHome(
  WidgetTester tester,
  LocalLedger ledger, {
  void Function(EntryKind kind)? onVerb,
  Locale? locale,
  double textScale = 1,
}) async {
  final settings = AppSettings(prefs: MemoryPrefs());
  await settings.load();
  final home = AppSettingsScope(
    settings: settings,
    child: HomeScreen(
      onVerb: onVerb,
      onSetupStep: (_) {},
      setupDoors: const {0, 1},
    ),
  );
  final router = buildRouter(
    featureRoutes: const [],
    initialLocation: RkPaths.of(RkTab.home),
    home: RkTabRoot(builder: (_) => home),
  );
  addTearDown(router.dispose);
  await pumpRk(
    tester,
    Router.withConfig(config: router),
    ledger: ledger,
    locale: locale,
    textScale: textScale,
    viewport: rkPhone360,
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<LocalLedger> _firstRunBook() async {
  final ledger = await openTestLedger();
  await ledger.bootstrapSolo(firstBookName: 'Journey Tester');
  return ledger;
}

void main() {
  testWidgets(
    'F1-1006c-10 first-run Home at 360×800: the four verbs are hit-testable '
    'without scrolling, the list scrolls beneath, the bar stays put',
    (tester) async {
      final tapped = <EntryKind>[];
      await _pumpHome(tester, await _firstRunBook(), onVerb: tapped.add);

      // First run: the checklist is on screen (S0.7) …
      expect(find.byType(HomeSetupChecklist), findsOneWidget);
      // … and the verbs are in the pinned bar, not the list.
      final bar = find.byKey(HomeVerbBar.barKey);
      expect(bar, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(HomeVerbButtons),
        ),
        findsNothing,
      );
      for (final label in _verbs) {
        expect(
          find.descendant(of: bar, matching: find.text(label)).hitTestable(),
          findsOneWidget,
          reason: '$label must be reachable without a scroll (07 §1 rule 2)',
        );
      }
      // Above the tab bar, never under it.
      final barRect = tester.getRect(bar);
      final tabs = tester.getRect(find.byType(RkTabBar));
      expect(barRect.bottom, lessThanOrEqualTo(tabs.top));

      // The list scrolls beneath; the bar does not move.
      final list = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(list.position.pixels, 0);
      expect(list.position.maxScrollExtent, greaterThan(0));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(list.position.pixels, greaterThan(0));
      expect(tester.getRect(bar), barRect);

      await tester.tap(find.text('Money in'));
      expect(tapped, [EntryKind.moneyIn]);
      await _unmount(tester);
    },
  );

  testWidgets(
    'F1-1006c-11 populated Home at 360×800 pins the verbs the same way',
    (tester) async {
      final seed = await seedSoloLedger();
      await _pumpHome(tester, seed.ledger);
      expect(find.byType(HomePositionCard), findsOneWidget);
      final bar = find.byKey(HomeVerbBar.barKey);
      for (final label in _verbs) {
        expect(
          find.descendant(of: bar, matching: find.text(label)).hitTestable(),
          findsOneWidget,
        );
      }
      await _unmount(tester);
    },
  );

  for (final locale in rkLocales) {
    testWidgets(
      'F1-1006c-12 first-run Home, ${locale.languageCode} at 200 % on '
      '360×800: the bar reflows without overflow, the verbs stay reachable',
      (tester) async {
        await _pumpHome(
          tester,
          await _firstRunBook(),
          locale: locale,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expectTextFits(
          tester,
          reason: 'Home verb bar, ${locale.languageCode} at 200 % on 360×800',
        );
        final bar = find.byKey(HomeVerbBar.barKey);
        final buttons = find.descendant(
          of: bar,
          matching: find.byType(OutlinedButton),
        );
        expect(buttons, findsNWidgets(4));
        // The first verb is always in reach; the bar never takes more than
        // half the body, so the list keeps room above it.
        expect(buttons.first.hitTestable(), findsOneWidget);
        final body = tester.getRect(find.byType(HomeScreen));
        expect(tester.getRect(bar).height, lessThanOrEqualTo(body.height / 2));
        await _unmount(tester);
      },
    );
  }
}
