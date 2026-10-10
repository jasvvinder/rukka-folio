// F1 tests for desk 193 (i): S1.1's total header, balance order and ageing
// chips (07 §7 🔒 — "party list sorted by balance, ageing chips (`> 30 days`
// amber, `> 90 days` red — localised per 01 §2.0, never abbreviated in
// ਪੰਜਾਬੀ/हिन्दी), total header"; 07 §1 rule 3 — colour never alone).
//
// Ageing: no doc defines how a *party* balance is aged (02 §7 ages advances
// only), and neither packages/data nor core_ledger exposes a per-party age, so
// the screen takes ages through a seam ([PositionDrilldownScreen.ageDaysOf])
// that production leaves null — no chip is drawn until the rule exists
// (⚠️ SPEC, lane report open). These tests drive the seam with a fake to pin
// what a chip looks like, and pin that the default draws none.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/home/home_routes.dart';
import 'package:rukka_folio/features/home/home_scope.dart';
import 'package:rukka_folio/features/home/screens/s1_1_position_drilldown_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/features/home/widgets/home_scope_switcher.dart';
import 'package:rukka_folio/features/ledger/ledger_routes.dart';
import 'package:rukka_folio/features/menu/menu_routes.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart'
    show AccountBalance;
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Finder _money(String s) => find.text(s, findRichText: true);

/// Synthetic suppliers (CLAUDE.md rule 4), created out of balance order.
const _suppliers = [
  ('Vardhman Dairy', 360_000),
  ('Tuglaq Yarn Company', 17_000_000),
  ('Avtar Transport Co.', 1_120_000),
];

Future<SeededLedger> _seedSuppliers() async {
  final seed = await seedSoloLedger();
  for (final (name, paise) in _suppliers) {
    final party = await seed.ledger.addAccount(
      seed.bookId,
      name: name,
      accountClass: AccountClass.party,
    );
    await seed.ledger.tookCredit(
      bookId: seed.bookId,
      fromWhom: party.id,
      took: seed.fuelId,
      paise: paise,
      date: seed.ledger.today().addDays(-3),
    );
  }
  return seed;
}

/// The shipped shell — S1 through [homeTabRootWith] and S1.1 through
/// [homeRoutes], the compositions `bootstrap.dart` mounts — past setup so
/// every book's position card stands. Never a hand-built screen: a test of
/// what production does must go through what production wires.
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

/// Taps the Home position row labelled [label].
Future<void> _tapPositionRow(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(HomePositionCard),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

/// A fake age source: days by party name.
int? Function(AccountBalance) _agesByName(Map<String, int> days) =>
    (row) => days[row.account.name];

const _ages = {
  'Tuglaq Yarn Company': 95,
  'Avtar Transport Co.': 45,
  'Vardhman Dairy': 10,
};

void main() {
  testWidgets('F1-193-3 S1.1 opens with a total header — caption, the line '
      'total, how many parties — and no foot total row (07 §7 🔒)', (
    tester,
  ) async {
    _tall(tester);
    final seed = await _seedSuppliers();
    await pumpRk(
      tester,
      PositionDrilldownScreen(
        line: PositionLine.youWillGive,
        onOpenAccount: (_) {},
      ),
      ledger: seed.ledger,
    );
    // ₹3,600 + ₹1,70,000 + ₹11,200, in integer paise all the way.
    expect(find.text('YOU OWE, IN ALL'), findsOneWidget);
    expect(_money('−₹1,84,800'), findsOneWidget);
    expect(find.text('3 people and suppliers'), findsOneWidget);
    expect(find.text('Total'), findsNothing);
    // The header sits above every row.
    final header = tester.getTopLeft(_money('−₹1,84,800')).dy;
    for (final (name, _) in _suppliers) {
      expect(header < tester.getTopLeft(find.text(name)).dy, isTrue);
    }
    await _unmount(tester);
  });

  testWidgets('F1-193-4 S1.1 lists parties by balance, largest first — not '
      'by creation order (07 §7 🔒)', (tester) async {
    _tall(tester);
    final seed = await _seedSuppliers();
    await pumpRk(
      tester,
      PositionDrilldownScreen(
        line: PositionLine.youWillGive,
        onOpenAccount: (_) {},
      ),
      ledger: seed.ledger,
    );
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('Tuglaq Yarn Company'), lessThan(top('Avtar Transport Co.')));
    expect(top('Avtar Transport Co.'), lessThan(top('Vardhman Dairy')));
    await _unmount(tester);
  });

  testWidgets('F1-193-5 with ages known, a party over 90 days carries a red '
      '"> 90 days" chip, over 30 an amber "> 30 days" chip, and a newer one '
      'none; the header names the oldest (07 §7 🔒, 01 §2.0 🔒)', (
    tester,
  ) async {
    _tall(tester);
    final seed = await _seedSuppliers();
    await pumpRk(
      tester,
      PositionDrilldownScreen(
        line: PositionLine.youWillGive,
        onOpenAccount: (_) {},
        ageDaysOf: _agesByName(_ages),
      ),
      ledger: seed.ledger,
    );
    final status = RkStatusColors.of(
      tester.element(find.byType(PositionDrilldownScreen)),
    );
    // Text, not colour alone (07 §1 rule 3).
    final red = find.text('> 90 days');
    final amber = find.text('> 30 days');
    expect(red, findsOneWidget);
    expect(amber, findsOneWidget);
    expect(tester.widget<Text>(red).style?.color, status.danger);
    expect(tester.widget<Text>(amber).style?.color, status.warning);
    // The frame's tag is square-cornered (canvas c7 S1.1): no radius.
    final tag = tester.widget<DecoratedBox>(
      find.ancestor(of: red, matching: find.byType(DecoratedBox)).first,
    );
    expect((tag.decoration as BoxDecoration).borderRadius, isNull);
    // Each chip sits under its own party.
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(red), greaterThan(top(find.text('Tuglaq Yarn Company'))));
    expect(top(red), lessThan(top(find.text('Avtar Transport Co.'))));
    expect(top(amber), greaterThan(top(find.text('Avtar Transport Co.'))));
    expect(top(amber), lessThan(top(find.text('Vardhman Dairy'))));
    expect(
      find.text('3 people and suppliers · oldest 95 days'),
      findsOneWidget,
    );
    expect(find.textContaining('Ageing is on the chip'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('F1-193-5 the chips are the 01 §2.0 🔒 words in ਪੰਜਾਬੀ and '
      'हिन्दी — never abbreviated', (tester) async {
    _tall(tester);
    for (final (locale, over90, over30) in const [
      (Locale('pa'), '90 ਦਿਨਾਂ ਤੋਂ ਵੱਧ', '30 ਦਿਨਾਂ ਤੋਂ ਵੱਧ'),
      (Locale('hi'), '90 दिन से ज़्यादा', '30 दिन से ज़्यादा'),
    ]) {
      final seed = await _seedSuppliers();
      await pumpRk(
        tester,
        PositionDrilldownScreen(
          line: PositionLine.youWillGive,
          ageDaysOf: _agesByName(_ages),
        ),
        ledger: seed.ledger,
        locale: locale,
      );
      expect(find.text(over90), findsOneWidget, reason: '$locale');
      expect(find.text(over30), findsOneWidget, reason: '$locale');
      expect(find.textContaining('>'), findsNothing, reason: '$locale');
      await _unmount(tester);
    }
  });

  testWidgets('F1-193-6 with no age known — the shipped default, since no doc '
      'yet says how a party balance is aged — the S1.1 the production route '
      'opens from Home draws no chip, no "oldest", no footnote, and the '
      'total header still stands', (tester) async {
    rkViewport(tester, rkTallViewport);
    final seed = await _seedSuppliers();
    await _pumpShell(tester, seed);
    await _tapPositionRow(tester, 'You will give');

    expect(find.byType(PositionDrilldownScreen), findsOneWidget);
    expect(find.text('YOU OWE, IN ALL'), findsOneWidget);
    expect(_money('−₹1,84,800'), findsOneWidget);
    expect(find.text('3 people and suppliers'), findsOneWidget);
    expect(find.text('> 90 days'), findsNothing);
    expect(find.text('> 30 days'), findsNothing);
    expect(find.textContaining('oldest'), findsNothing);
    expect(find.textContaining('Ageing is on the chip'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('F1-193-8 S1.1 opens over the book Home has in scope: with two '
      'books and the second chosen, the drill-down total is that book\'s — '
      'the same figure as the row tapped (02 §9 per selected scope; 13 §2.2)', (
    tester,
  ) async {
    rkViewport(tester, rkTallViewport);
    final seed = await seedSoloLedger();
    final me = seed.bookId;
    // Me owes a supplier ₹3,000; the Shop owes another ₹7,700.
    final fuels = await seed.ledger.addAccount(
      me,
      name: 'Bharat Fuels',
      accountClass: AccountClass.party,
    );
    await seed.ledger.tookCredit(
      bookId: me,
      fromWhom: fuels.id,
      took: seed.fuelId,
      paise: 300_000,
      date: seed.ledger.today().addDays(-1),
    );
    final shop = await seed.ledger.createBook(
      name: 'Shop',
      type: BookType.business,
      startDate: seed.ledger.today().addDays(-7),
    );
    final kirpal = await seed.ledger.addAccount(
      shop,
      name: 'Kirpal Traders',
      accountClass: AccountClass.party,
    );
    final stock = await seed.ledger.addAccount(
      shop,
      name: 'Stock',
      accountClass: AccountClass.categoryExpense,
    );
    await seed.ledger.tookCredit(
      bookId: shop,
      fromWhom: kirpal.id,
      took: stock.id,
      paise: 770_000,
      date: seed.ledger.today().addDays(-1),
    );

    final router = await _pumpShell(tester, seed);
    // Both books are drilled, so whichever one a fallback would pick (the
    // mirror's first id), the other exposes it.
    Future<void> drill(String book, String party, String figure) async {
      // The Home row reads this book's figure…
      expect(
        find.descendant(
          of: find.byType(HomePositionCard),
          matching: _money(figure),
        ),
        findsOneWidget,
        reason: party,
      );
      await _tapPositionRow(tester, 'You will give');
      // …and so does the drill-down it opens.
      expect(router.state.uri.queryParameters['book'], book);
      expect(find.byType(PositionDrilldownScreen), findsOneWidget);
      expect(find.text(party), findsOneWidget);
      expect(_money(figure), findsNWidgets(2)); // header + the one row
      router.pop();
      await tester.pumpAndSettle();
    }

    await drill(me, 'Bharat Fuels', '−₹3,000');
    expect(find.text('Kirpal Traders'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(HomeScopeToggle),
        matching: find.text('Shop'),
      ),
    );
    await tester.pumpAndSettle();
    await drill(shop, 'Kirpal Traders', '−₹7,700');
    expect(find.text('Bharat Fuels'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('F1-193-9 the You will get header counts those who owe you as '
      'people and customers — debtors, never suppliers (01 §2)', (
    tester,
  ) async {
    _tall(tester);
    final seed = await seedSoloLedger(); // Ramesh owes ₹5,000.
    await pumpRk(
      tester,
      PositionDrilldownScreen(
        line: PositionLine.youWillGet,
        bookId: seed.bookId,
        onOpenAccount: (_) {},
      ),
      ledger: seed.ledger,
    );
    expect(find.text('OWED TO YOU, IN ALL'), findsOneWidget);
    expect(find.text('1 person or customer'), findsOneWidget);
    expect(find.textContaining('supplier'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('F1-193-9 the You will get count is the 01 §2 debtor word in '
      'ਪੰਜਾਬੀ and हिन्दी', (tester) async {
    _tall(tester);
    for (final (locale, word) in const [
      (Locale('pa'), '1 ਦੇਣਦਾਰ'),
      (Locale('hi'), '1 देनदार'),
    ]) {
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        PositionDrilldownScreen(
          line: PositionLine.youWillGet,
          bookId: seed.bookId,
        ),
        ledger: seed.ledger,
        locale: locale,
      );
      expect(find.text(word), findsOneWidget, reason: '$locale');
      await _unmount(tester);
    }
  });

  testWidgets('F1-193-3 a non-party line keeps the plain "Total" caption and '
      'counts accounts', (tester) async {
    _tall(tester);
    final seed = await seedSoloLedger();
    await pumpRk(
      tester,
      const PositionDrilldownScreen(line: PositionLine.cash),
      ledger: seed.ledger,
    );
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('2 accounts'), findsOneWidget);
    await _unmount(tester);
  });

  test('F1-193-5 ageing buckets: strictly over 30 is amber, strictly over 90 '
      'is red, unknown or 30 and under is none', () {
    expect(ageingBucketOf(null), AgeingBucket.none);
    expect(ageingBucketOf(30), AgeingBucket.none);
    expect(ageingBucketOf(31), AgeingBucket.over30);
    expect(ageingBucketOf(90), AgeingBucket.over30);
    expect(ageingBucketOf(91), AgeingBucket.over90);
  });
}
