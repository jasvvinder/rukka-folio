@Tags(['F1'])
library;

// PLAN desk 132 — the shipped app mounted S1 through its own inline
// `HomeScreen(...)` in `bootstrap.dart`, and that copy had drifted: no S21
// search button (07 §25 🔒), no reconciliation door (07 §10 🔒), no Close card
// door (07 §13 🔒), no S0.7 setup doors. The fix has two halves, and this file
// pins both, so removing either half goes red:
//
//   1. the composition root mounts S1 through `homeTabRootWith(homeScope)`
//      and builds no S1 of its own (F1-07-35, read from the source the way
//      F1-24b-2 reads the root);
//   2. the doors desk 132 found missing are really on `homeTabRootWith`, driven
//      through the real router: the 07 §10 reconciliation door (F1-07-123)
//      and the 07 §13 Close card door (F1-07-140) here, and the 07 §25 search
//      door in `features/home/s1_search_entry_test.dart` (F1-07-35). Each
//      door's behaviour on a bare `HomeScreen` stays with its own test
//      (s1_in_transit_test.dart, s1_close_card_test.dart); what is asserted
//      here is only that `homeScreenFor` — the one wiring — passes the
//      callback and that it lands on the owning feature's path. Drop
//      `onOpenReconciliation` or `onOpenClose` from `homeScreenFor` and the
//      tap goes nowhere, so these go red.
//
// The destinations are stub routes at the owning features' path constants
// (`ReportsPaths.reconciliationLocation`, `ClosePaths.pattern`): S8.3 and S10
// have tests of their own, and mounting them here would test them, not the
// wiring. Every amount is synthetic (CLAUDE.md rule 4).
import 'dart:io';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/close/close_routes.dart';
import 'package:rukka_folio/features/home/home_routes.dart';
import 'package:rukka_folio/features/home/home_scope.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart'
    show HomeCardKeys;
import 'package:rukka_folio/features/home/widgets/home_close_card.dart';
import 'package:rukka_folio/features/reports/reports_paths.dart';
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

String _bootstrapCode() {
  for (final path in ['lib/bootstrap.dart', 'app/lib/bootstrap.dart']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    expect(text, isNotEmpty, reason: 'the root was really read');
    return [
      for (final line in text.split('\n'))
        line.contains('//') ? line.substring(0, line.indexOf('//')) : line,
    ].join('\n');
  }
  fail('lib/bootstrap.dart not found from ${Directory.current.path}');
}

const _reconciliationStub = Key('stub.s8_3');
const _closeStub = Key('stub.s10');

/// Pumps the shell's router with S1 mounted exactly as `bootstrap.dart`
/// mounts it — `homeTabRootWith(scope)` — and stub destinations at the owning
/// features' paths. [close] installs [CloseScope] above the router, as the
/// root does.
Future<GoRouter> _pumpShell(
  WidgetTester tester,
  SeededLedger seed,
  HomeScopeController scope, {
  CloseSource? close,
}) async {
  final router = buildRouter(
    featureRoutes: [
      GoRoute(
        path: ClosePaths.pattern,
        builder: (_, state) => Scaffold(
          key: _closeStub,
          body: Text(
            '${state.pathParameters[ClosePaths.bookParam]} '
            '${state.pathParameters[ClosePaths.periodParam]}',
          ),
        ),
      ),
    ],
    home: homeTabRootWith(scope),
    menu: RkTabRoot(
      builder: (_) => const SizedBox.shrink(),
      routes: [
        GoRoute(
          path: '${ReportsPaths.root}/${ReportsPaths.reconciliation}',
          builder: (_, _) => const Scaffold(key: _reconciliationStub),
        ),
      ],
    ),
  );
  addTearDown(router.dispose);
  Widget app = MaterialApp.router(
    routerConfig: router,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: rkLocalizationsDelegates,
    theme: rkTheme(Brightness.light),
  );
  if (close != null) app = CloseScope(source: close, child: app);
  await tester.pumpWidget(
    RkScope(
      db: seed.ledger.db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: seed.ledger.keys as FakeKeyStore,
      now: seed.ledger.now,
      child: LedgerScope(ledger: seed.ledger, child: app),
    ),
  );
  await tester.pumpAndSettle();
  expect(router.state.uri.toString(), RkPaths.home);
  expect(find.byType(HomeScreen), findsOneWidget);
  return router;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  test(
    'F1-07-35 bootstrap mounts S1 through homeTabRootWith(homeScope) — the '
    'one wiring tests share — and builds no HomeScreen of its own (desk 132)',
    () {
      final root = _bootstrapCode();
      expect(root, contains('Future<void> bootstrap() async {'));
      expect(
        RegExp(r'homeTabRoot:\s*homeTabRootWith\(\s*homeScope\s*\)')
            .allMatches(root),
        hasLength(1),
        reason: 'S1 is the shared wiring, with the shell\'s scope holder',
      );
      expect(
        RegExp(r'\bHomeScreen\(').hasMatch(root),
        isFalse,
        reason:
            'an inline S1 drops every door homeScreenFor gains (07 §10 and '
            '§13, pinned below; 07 §25, pinned in s1_search_entry_test)',
      );
    },
  );

  testWidgets(
    'F1-07-123 through homeTabRootWith (desk 132): the in-transit label on '
    'the shipped S1 opens S8.3 at ReportsPaths.reconciliationLocation '
    '(07 §10 🔒)',
    (tester) async {
      rkViewport(tester, rkTallViewport);
      final seed = await seedSoloLedger();
      final familyId = await seed.ledger.createBook(
        name: 'Sharma Family',
        type: BookType.family,
        cashName: 'Family Cash',
      );
      final familyCash = (await seed.ledger.chartOf(familyId))
          .byClass(AccountClass.money)
          .firstWhere((a) => a.name == 'Family Cash');
      // 02 §6 🔒: the receiving half carries the review flag, so the pair
      // reads *in transit* and S1 draws the 07 §10 label.
      await seed.ledger.transferBetweenBooks(
        fromBookId: seed.bookId,
        fromAccountId: seed.bankId,
        toBookId: familyId,
        toAccountId: familyCash.id,
        paise: 5_000_00,
        date: seed.ledger.today(),
        reviewRequiredIn: (from: false, to: true),
      );
      final scope = HomeScopeController();
      addTearDown(scope.dispose);
      final router = await _pumpShell(tester, seed, scope);

      expect(find.byKey(HomeCardKeys.inTransitChip), findsOneWidget);
      await tester.tap(find.byKey(HomeCardKeys.inTransitChip));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, ReportsPaths.reconciliationLocation);
      expect(find.byKey(_reconciliationStub), findsOneWidget);

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets(
    'F1-07-140 through homeTabRootWith (desk 132): the shipped S1 draws the '
    'Close card from the root\'s CloseScope and its action opens S10 at '
    'ClosePaths.forBook (07 §13 🔒 bullet 1)',
    (tester) async {
      rkViewport(tester, rkTallViewport);
      final seed = await seedSoloLedger();
      final august = YearMonth(2026, 8);
      final source =
          FakeCloseSource(
              view: CloseView(
                bookId: seed.bookId,
                bookName: 'Kirana',
                period: august,
                cashAccounts: const [],
                bankAccounts: const [],
                tray: const CloseTray(),
              ),
            )
            ..statuses = [
              BookCloseStatus(
                bookId: seed.bookId,
                bookName: 'Kirana',
                period: august,
                state: BookCloseState.notStarted,
              ),
            ];
      final scope = HomeScopeController();
      addTearDown(scope.dispose);
      final router = await _pumpShell(tester, seed, scope, close: source);

      final action = find.byKey(HomeCloseKeys.action(seed.bookId));
      expect(action, findsOneWidget);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, ClosePaths.forBook(seed.bookId, '2026-08'));
      expect(find.byKey(_closeStub), findsOneWidget);

      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );
}
