// F1 tests for desk 193 (c): S1's books-balanced verification card is a door
// to the trial balance (07 §4 🔒 "tapping through to the full trial balance
// (S8.2 report viewer)").
//
// Driven through the PRODUCTION composition — [homeTabRootWith], the tab root
// `bootstrap.dart` mounts, inside the real router with the Menu tab root
// (`menuRoot`, which carries the reports routes) — never a hand-injected
// callback, so the test fails if the shipped wiring drops the door
// (test-honesty, desk 193 (c)).
//
// ⚠️ SPEC: the app has no trial-balance surface yet (S8.2 shows the Day Book;
// S8.1 keeps *Trial Balance* disabled-with-reason until M12, ADR 2026-09-12
// Consequences), so the door opens S8.1 Reports, where that row stands with
// its reason. When the trial balance gets its own location, these
// assertions move with it.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/home/home_routes.dart';
import 'package:rukka_folio/features/home/home_scope.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/features/ledger/ledger_routes.dart';
import 'package:rukka_folio/features/menu/menu_routes.dart';
import 'package:rukka_folio/features/reports/screens/s8_1_reports_list_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/tokens.dart';

import '../../shared/test_app.dart';

/// The shipped shell: S1 through [homeTabRootWith], the Menu tab through
/// [menuRoot], past setup so the position card (and its verification card)
/// stands rather than the S0.7 checklist.
Future<GoRouter> _pumpShell(WidgetTester tester, SeededLedger seed) async {
  final scope = HomeScopeController();
  addTearDown(scope.dispose);
  final prefs = MemoryPrefs()..values[RkPrefKeys.recoverySheetVerified] = '1';
  for (final id in await seed.ledger.mirror.bookIds()) {
    prefs.values[RkPrefKeys.openingBalancesOf(id)] = '1';
  }
  final settings = AppSettings(prefs: prefs);
  await settings.load();
  final router = buildRouter(
    featureRoutes: [...homeRoutes, ...ledgerRoutes],
    home: homeTabRootWith(scope),
    ledger: ledgerRoot,
    menu: menuRoot,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RkScope(
      db: seed.ledger.db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: seed.ledger.keys as FakeKeyStore,
      now: seed.ledger.now,
      child: LedgerScope(
        ledger: seed.ledger,
        child: AppSettingsScope(
          settings: settings,
          child: MaterialApp.router(
            routerConfig: router,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: rkLocalizationsDelegates,
            theme: rkTheme(Brightness.light),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Finder get _card => find.byType(HomeVerificationCard);

void main() {
  testWidgets('F1-193-1 the shipped S1 verification card is a door: tapping '
      'it leaves Home for the reports where the trial balance stands '
      '(07 §4 🔒)', (tester) async {
    rkViewport(tester, rkTallViewport);
    final seed = await seedSoloLedger();
    final router = await _pumpShell(tester, seed);
    expect(router.state.uri.toString(), RkPaths.home);
    expect(_card, findsOneWidget);

    await tester.tap(_card);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '${RkPaths.menu}/reports');
    expect(find.byType(ReportsListScreen), findsOneWidget);
    expect(find.text('Trial Balance'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('F1-193-2 the door carries the frame\'s chevron and is announced '
      'as a button named by its action (07 §1, 13 §8)', (tester) async {
    rkViewport(tester, rkTallViewport);
    final handle = tester.ensureSemantics();
    final seed = await seedSoloLedger();
    await _pumpShell(tester, seed);

    expect(
      find.descendant(of: _card, matching: find.byIcon(Icons.chevron_right)),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(
        find.descendant(of: _card, matching: find.byType(InkWell)),
      ),
      containsSemantics(isButton: true, hasTapAction: true),
    );
    // Named by the action first; the card's own words follow it.
    expect(
      tester
          .getSemantics(
            find.descendant(of: _card, matching: find.byType(InkWell)),
          )
          .label,
      startsWith('See the full check'),
    );
    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('F1-193-2 the card is laid out as the frame draws it: the '
      'chevron in the title row, the line under it small, muted and '
      'indented under the title text (canvas c7/c15/c2 S1)', (tester) async {
    rkViewport(tester, rkTallViewport);
    final seed = await seedSoloLedger();
    await _pumpShell(tester, seed);

    final title = find.descendant(of: _card, matching: find.text('Balanced'));
    final line = find.descendant(
      of: _card,
      matching: find.text('Books balanced · difference nil'),
    );
    final chevron = find.descendant(
      of: _card,
      matching: find.byIcon(Icons.chevron_right),
    );
    // The chevron centres on the title row, above the line.
    expect(
      (tester.getCenter(chevron).dy - tester.getCenter(title).dy).abs(),
      lessThan(2),
    );
    expect(tester.getCenter(chevron).dy, lessThan(tester.getTopLeft(line).dy));
    // The line starts under the title text, not at the card's edge.
    expect(
      (tester.getTopLeft(line).dx - tester.getTopLeft(title).dx).abs(),
      lessThan(1),
    );
    final status = RkStatusColors.of(tester.element(_card));
    final style = tester.widget<Text>(line).style!;
    expect(style.color, status.muted);
    expect(style.fontSize, RkType.caption.fontSize);
    await _unmount(tester);
  });

  testWidgets('F1-193-2 without a door (a preview with no callback) the card '
      'draws no chevron and no button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: rkLocalizationsDelegates,
        theme: rkTheme(Brightness.light),
        home: const Scaffold(
          body: HomeVerificationCard(balanced: true, differencePaise: 0),
        ),
      ),
    );
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.text('Books balanced · difference nil'), findsOneWidget);
  });
}
