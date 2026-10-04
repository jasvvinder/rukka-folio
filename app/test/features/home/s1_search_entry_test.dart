// F1-07-35 (entry point): S21 Search is reached from S1 as well as S3
// (13 §3.2 row S21; 07 §25 🔒; desk 81), over the book S1 has in scope.
//
// Driven through [homeTabRootWith] — the tab root the shipped app is meant to
// mount with the shell's scope holder — and the real router, with
// ledgerRoutes mounting S21 at LedgerPaths.search. [homeRoot] builds through
// the same [homeScreenFor], so there is one wiring to test.
//
// Not covered here: `bootstrap.dart` still builds its own HomeScreen inline
// rather than passing `homeTabRootWith(homeScope)` (a file this lane does not
// own — lane report open item). Until it does, the shipped S1 has no search
// door, whatever this test says.
//
// Scope (finding 2): each test searches a note only the Me book carries, from
// both scopes. S21 used to open on the mirror's first book id, so whichever
// way the random book ids sort, one of the two scopes would search the wrong
// book and the assertion for that scope would go red.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/home/home_routes.dart';
import 'package:rukka_folio/features/home/home_scope.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_scope_switcher.dart';
import 'package:rukka_folio/features/ledger/ledger_routes.dart';
import 'package:rukka_folio/features/ledger/screens/s21_search_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

/// Pumps the app shell's router with S1 mounted as the shipped app mounts it.
Future<GoRouter> _pumpShell(
  WidgetTester tester,
  SeededLedger seed,
  HomeScopeController scope,
) async {
  final router = buildRouter(
    featureRoutes: [...homeRoutes, ...ledgerRoutes],
    home: homeTabRootWith(scope),
    ledger: ledgerRoot,
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
  return router;
}

Finder get _searchButton => find.descendant(
  of: find.byType(AppBar),
  matching: find.byTooltip('Search'),
);

/// Opens S21 from S1's app bar and searches the seeded Me book's note.
Future<void> _openAndSearch(WidgetTester tester) async {
  expect(_searchButton, findsOneWidget);
  await tester.tap(_searchButton);
  await tester.pumpAndSettle();
  expect(find.byType(LedgerSearchScreen), findsOneWidget);
  await tester.enterText(find.byType(TextField), 'saturday');
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('F1-07-35 S1 opens S21 from its app bar through the real router '
      '(13 §3.2: S3/S1), on the book in scope, and finds its notes', (
    tester,
  ) async {
    rkViewport(tester, rkTallViewport);
    final seed = await seedSoloLedger();
    final scope = HomeScopeController();
    addTearDown(scope.dispose);
    final router = await _pumpShell(tester, seed, scope);
    expect(router.state.uri.toString(), RkPaths.home);
    expect(find.byType(HomeScreen), findsOneWidget);

    await _openAndSearch(tester);
    expect(router.state.uri.path, LedgerPaths.search);
    expect(router.state.uri.queryParameters['book'], seed.bookId);
    expect(
      tester.widget<LedgerSearchScreen>(find.byType(LedgerSearchScreen)).bookId,
      seed.bookId,
    );
    expect(find.textContaining('Saturday sales'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('F1-07-35 two books: S21 searches the book S1 is showing — Me '
      'by default, the other book once switched (07 §25 🔒 "in scope")', (
    tester,
  ) async {
    rkViewport(tester, rkTallViewport);
    final seed = await seedSoloLedger();
    final shopId = await seed.ledger.createBook(
      name: 'Shop',
      type: BookType.business,
      startDate: seed.ledger.today().addDays(-7),
    );
    final scope = HomeScopeController();
    addTearDown(scope.dispose);
    final router = await _pumpShell(tester, seed, scope);

    // Default scope is Me (13 §2.2), whatever the mirror lists first.
    await _openAndSearch(tester);
    expect(router.state.uri.queryParameters['book'], seed.bookId);
    expect(find.textContaining('Saturday sales'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(HomeScopeToggle),
        matching: find.text('Shop'),
      ),
    );
    await tester.pumpAndSettle();

    // Shop has no such note: a search over Me here would be the bug.
    await _openAndSearch(tester);
    expect(router.state.uri.queryParameters['book'], shopId);
    expect(
      tester.widget<LedgerSearchScreen>(find.byType(LedgerSearchScreen)).bookId,
      shopId,
    );
    expect(find.textContaining('Saturday sales'), findsNothing);
    expect(find.text('Nothing matches "saturday"'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('F1-07-35 Everything: no search door — S21 searches one book, '
      'never one book passed off as the aggregate (⚠️ SPEC, conservative)', (
    tester,
  ) async {
    rkViewport(tester, rkTallViewport);
    final seed = await seedSoloLedger();
    for (final (name, type) in [
      ('Shop', BookType.business),
      ('Ghar', BookType.family),
    ]) {
      await seed.ledger.createBook(
        name: name,
        type: type,
        startDate: seed.ledger.today().addDays(-7),
      );
    }
    final scope = HomeScopeController();
    addTearDown(scope.dispose);
    await _pumpShell(tester, seed, scope);
    expect(_searchButton, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(HomeScopeSheetButton),
        matching: find.byType(ActionChip),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(HomeScopeSheet),
        matching: find.text('Everything'),
      ),
    );
    await tester.pumpAndSettle();
    expect(scope.selected, const HomeScope.everything());
    expect(_searchButton, findsNothing);

    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('F1-07-35 the S1 search button is named in EN, PA and HI', (
    tester,
  ) async {
    final seed = await seedSoloLedger();
    for (final locale in AppLocalizations.supportedLocales) {
      final opened = <String>[];
      await pumpRk(
        tester,
        HomeScreen(onOpenSearch: opened.add),
        ledger: seed.ledger,
        locale: locale,
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      final button = find.byTooltip(l10n.ledgerSearchTitle);
      expect(button, findsOneWidget, reason: locale.languageCode);
      await tester.tap(button);
      expect(opened, [seed.bookId], reason: locale.languageCode);
      expect(tester.takeException(), isNull);
    }
    await _unmount(tester);
  });
}
