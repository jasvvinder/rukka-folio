// F1 widget tests for **S9.5 Add a business** (07 §5.7 🔒, 13 §3.2 row S9.5)
// and the S9 Books surface that carries it (Menu → Books).
//
// S9.5 is the onboarding business flow reached a second time, not a second
// implementation of it: these tests drive `booksRoutes` on a bare router and
// assert that the screens that come up are S0.6a / S0.6a1 / S0.6b themselves
// (ADR 2026-09-09 §1–§3, ADR 2026-09-09c §1, §3), that the book is really
// created (02 §7.1 — weights keyed on Partner Current A/c ids, an absent map
// meaning *not recorded*), and that the new book lands on the right side of
// 07 §5.7's 🔒 scope-switcher count rule: two books → the inline toggle,
// three → the grouped sheet, never the sheet at two.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/books/books_routes.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_scope_switcher.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a1_business_owners_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a_business_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6b_business_opening_balances_screen.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

/// A viewport tall enough that every row of S9 and of S0.6b is laid out.
void tallViewport(
  WidgetTester tester, {
  double width = 400,
  double height = 3000,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Tears the tree down inside the test: cancelling drift's query stream
/// schedules a zero-duration timer that only an in-test pump can fire.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// The books on the device, by name.
Future<List<String>> _bookNames(LocalLedger l) async => [
  for (final b in await l.db.select(l.db.booksP).get()) b.name,
];

/// Pumps `features/books`'s own routes on a bare router — the wiring this
/// lane owns; composing them into the app is the orchestrator's job.
Future<GoRouter> _pumpBooks(
  WidgetTester tester,
  LocalLedger ledger, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  final router = GoRouter(
    routes: booksRoutes,
    initialLocation: BooksPaths.root,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RkScope(
      db: ledger.db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: ledger.keys as FakeKeyStore,
      now: ledger.now,
      child: LedgerScope(
        ledger: ledger,
        child: MaterialApp.router(
          routerConfig: router,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: rkLocalizationsDelegates,
          theme: rkTheme(Brightness.light),
          builder: textScale == 1
              ? null
              : (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Walks S9 → S9.5 for a *Just me* business called [name], ending on S9.
Future<void> _addJustMeBusiness(WidgetTester tester, String name) async {
  await tester.tap(find.text('Add a business'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, name);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  // S0.6b: the balances are optional (07 §3.1.1 — every branch step is
  // skippable), so *Skip for now* is the shortest honest path back.
  await tester.tap(find.text('Skip for now'));
  await tester.pumpAndSettle();
}

void main() {
  group('S9 Books — the Menu → Books surface (07 §5.7 🔒)', () {
    testWidgets(
      'F1-07-20 the books on the device are listed, with the S9.5 entry '
      'point on the screen and no dead-end row',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await _pumpBooks(tester, seed.ledger);

        expect(find.text('Books'), findsWidgets);
        expect(find.text('Your books'), findsOneWidget);
        // The seeded personal book, named and typed.
        expect(find.text('Me'), findsOneWidget);
        expect(find.text('Personal'), findsOneWidget);
        // S9.5's entry point (07 §5.7 🔒).
        expect(find.text('Add a business'), findsOneWidget);
        // 13 §3.2's other half of S9 is not built: it says so rather than
        // vanishing or sitting silently inert (07 §1 rule 6).
        expect(find.text('Roles, limits and members'), findsOneWidget);
        expect(find.textContaining('have not been built yet'), findsOneWidget);
        await unmount(tester);
      },
    );

    for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
      testWidgets(
        'F1-07-20 S9 and its S9.5 row render in ${locale.languageCode} at '
        '200% without overflow',
        (tester) async {
          tallViewport(tester, width: 360, height: 3200);
          final seed = await seedSoloLedger();
          await _pumpBooks(tester, seed.ledger, locale: locale, textScale: 2);

          final l10n = await AppLocalizations.delegate.load(locale);
          expect(find.text(l10n.booksAddBusinessRowTitle), findsOneWidget);
          expect(find.text(l10n.booksListHeading), findsOneWidget);
          expect(tester.takeException(), isNull);
          await unmount(tester);
        },
      );
    }
  });

  group('S9.5 Add a business — the onboarding flow, reached again', () {
    testWidgets(
      'F1-07-20 four fields and nothing else: S9 → S0.6a → S0.6b creates the '
      'second book and returns to S9 with it listed',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final router = await _pumpBooks(tester, seed.ledger);

        await tester.tap(find.text('Add a business'));
        await tester.pumpAndSettle();
        // The screen that comes up *is* S0.6a — not a second implementation
        // of it (07 §5.7 🔒, this lane's brief).
        expect(find.byType(BusinessNameScreen), findsOneWidget);
        expect(router.state.uri.path, BooksPaths.addBusiness);
        // A fresh pass: the field is blank, never a re-edit of book one.
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          '',
        );

        await tester.enterText(find.byType(TextField).first, 'Sharma Traders');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // *Just me* skips S0.6a1 (ADR 2026-09-09 §1) and lands on S0.6b,
        // which is review-and-fill over a chart that already exists (ADR
        // 2026-09-09c §3) — so the book has been created by now.
        expect(find.byType(BusinessOwnersScreen), findsNothing);
        expect(find.byType(BusinessOpeningBalancesScreen), findsOneWidget);
        expect(await _bookNames(seed.ledger), contains('Sharma Traders'));
        expect(find.text('Business Cash A/c'), findsOneWidget);

        await tester.tap(find.text('Skip for now'));
        await tester.pumpAndSettle();

        // Back on S9, with the new book on it — no dead end (07 §1).
        expect(router.state.uri.path, BooksPaths.root);
        expect(find.text('Sharma Traders'), findsOneWidget);
        expect(find.text('Business'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-20 *Shared with others* goes through S0.6a1 — weights, not '
      'percentages, and the step is not skippable (ADR 2026-09-09 §1, §3)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await _pumpBooks(tester, seed.ledger);

        await tester.tap(find.text('Add a business'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Sharma Traders');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shared with others'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.byType(BusinessOwnersScreen), findsOneWidget);
        // Not skippable: its secondary returns to *Just me* (§3), and no
        // book has been created yet.
        expect(find.text('Skip for now'), findsNothing);
        expect(find.text('Just me after all'), findsOneWidget);
        expect(
          await _bookNames(seed.ledger),
          isNot(contains('Sharma Traders')),
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-20 a second pass through S9.5 creates a *third* book, never a '
      'second edit of the first (07 §3.1.1 — resumable, never duplicated)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await _pumpBooks(tester, seed.ledger);

        await _addJustMeBusiness(tester, 'Sharma Traders');
        await _addJustMeBusiness(tester, 'Sharma Agri');

        final names = await _bookNames(seed.ledger);
        expect(names, containsAll(['Me', 'Sharma Traders', 'Sharma Agri']));
        expect(names.length, 3);
        await unmount(tester);
      },
    );
  });

  group('S9.5 lands on the right scope control (07 §5.7 🔒)', () {
    testWidgets(
      'F1-07-87 the second book gives Home the two-chip toggle and never the '
      'grouped sheet; the third book is what brings the sheet',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await _pumpBooks(tester, seed.ledger);
        await _addJustMeBusiness(tester, 'Sharma Traders');
        await unmount(tester);

        // Two books: the inline toggle of S1.2, and no sheet anywhere.
        await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);
        expect(find.byType(HomeScopeToggle), findsOneWidget);
        expect(find.byType(HomeScopeSheetButton), findsNothing);
        expect(find.text('Sharma Traders'), findsWidgets);
        await unmount(tester);

        // A third book flips the control to the grouped sheet of S1.3.
        await _pumpBooks(tester, seed.ledger);
        await _addJustMeBusiness(tester, 'Sharma Agri');
        await unmount(tester);

        await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);
        expect(find.byType(HomeScopeSheetButton), findsOneWidget);
        expect(find.byType(HomeScopeToggle), findsNothing);
        await unmount(tester);
      },
    );
  });
}
