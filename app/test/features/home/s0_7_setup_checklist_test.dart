// F1 widget test for S0.7 — the setup checklist Home shows a new user (13 §3.2
// row S0.7, 07 §4 empty state) and, crucially, the way back to a **skipped**
// opening-balances wizard: 07 §3.1 step 7 🔒 makes that wizard *"skippable,
// resumable from Home's setup card"*, so the card cannot vanish the moment the
// first entry is posted or the wizard would have no door left (07 §1 rule 6,
// no dead ends).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

const _locales = [Locale('en'), Locale('pa'), Locale('hi')];

void _tall(WidgetTester tester, {double width = 400, double height = 3000}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Tears the tree down inside the test: cancelling drift's query stream
/// schedules a zero-duration timer, and only a pump inside the test fires it
/// before the binding's pending-timer invariant runs.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// A bootstrapped personal book: the seeded chart of ADR 2026-09-09c §1 and
/// nothing else — the 07 §4 "new user".
Future<(LocalLedger, String)> _newUser() async {
  final ledger = await openTestLedger();
  await ledger.bootstrapSolo(
    firstBookName: 'Me',
    startDate: ledger.today().addDays(-7),
  );
  final bookId = (await ledger.mirror.bookIds()).single;
  return (ledger, bookId);
}

Future<Account> _cashOf(LocalLedger l, String bookId) async =>
    (await l.chartOf(bookId)).byClass(AccountClass.money).first;

/// The user skipped the balances and just posted something.
Future<void> _firstEntry(LocalLedger l, String bookId) async {
  final cash = await _cashOf(l, bookId);
  final diesel = await l.addAccount(
    bookId,
    name: 'Diesel',
    accountClass: AccountClass.categoryExpense,
  );
  await l.moneyOut(
    bookId: bookId,
    from: cash.id,
    forWhat: diesel.id,
    paise: 40000,
    date: l.today(),
  );
}

void main() {
  group('S0.7 setup checklist (13 §3.2 row S0.7, 07 §4, 07 §3.1 step 7 🔒)', () {
    testWidgets(
      'F1-07-57 a new user gets the checklist in place of the position card, '
      'with every step of 07 §4 named',
      (tester) async {
        _tall(tester);
        final (ledger, _) = await _newUser();
        await pumpRk(tester, const HomeScreen(), ledger: ledger);

        expect(find.byType(HomeSetupChecklist), findsOneWidget);
        expect(find.byType(HomePositionCard), findsNothing);
        expect(find.text('Get your book going'), findsOneWidget);
        expect(find.text('Add your opening balances'), findsOneWidget);
        expect(find.text('Record your first entry'), findsOneWidget);
        expect(find.text('Print your recovery sheet'), findsOneWidget);
        expect(find.text('Add your family'), findsOneWidget);
        // Nothing is done yet, so no step wears the word.
        expect(find.text('Done'), findsNothing);
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-07-57 tapping the opening-balances step resumes the wizard — that '
      'is what makes skipping it safe (07 §3.1 step 7 🔒)',
      (tester) async {
        _tall(tester);
        final (ledger, _) = await _newUser();
        final steps = <int>[];
        await pumpRk(
          tester,
          HomeScreen(onSetupStep: steps.add),
          ledger: ledger,
        );

        await tester.tap(find.text('Add your opening balances'));
        await tester.pump();
        expect(steps, [0]);
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-07-57 the card survives the first entry: the position card returns '
      'and the checklist stays, because the balances are still missing',
      (tester) async {
        _tall(tester);
        final (ledger, bookId) = await _newUser();
        await _firstEntry(ledger, bookId);
        await pumpRk(tester, const HomeScreen(), ledger: ledger);

        expect(find.byType(HomePositionCard), findsOneWidget);
        expect(find.byType(HomeSetupChecklist), findsOneWidget);
        // Step 2 is done, and the word says so beside the tick — colour is
        // never the only carrier (07 §1 rule 3).
        expect(find.text('Done'), findsOneWidget);
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-07-57 once the opening balances are recorded the checklist goes and '
      'the position card stands alone',
      (tester) async {
        _tall(tester);
        final (ledger, bookId) = await _newUser();
        final cash = await _cashOf(ledger, bookId);
        await ledger.openingBalances(bookId, balances: {cash.id: 1500000});
        await pumpRk(tester, const HomeScreen(), ledger: ledger);

        expect(find.byType(HomeSetupChecklist), findsNothing);
        expect(find.byType(HomePositionCard), findsOneWidget);
        await _unmount(tester);
      },
    );

    testWidgets('F1-07-57 strings resolve in EN, PA and HI', (tester) async {
      _tall(tester);
      for (final locale in _locales) {
        final (ledger, _) = await _newUser();
        await pumpRk(
          tester,
          const HomeScreen(),
          ledger: ledger,
          locale: locale,
        );
        final card = find.byType(HomeSetupChecklist);
        expect(
          card,
          findsOneWidget,
          reason: 'no checklist in ${locale.languageCode}',
        );
        final labels = tester
            .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)),
            )
            .map((t) => t.data ?? '')
            .where((s) => s.isNotEmpty);
        expect(labels, hasLength(greaterThanOrEqualTo(5)));
        for (final s in labels) {
          expect(s, isNot(contains('home.setup')), reason: 'unresolved key');
          // Consumer surface (02 §10 🔒, CLAUDE.md rule 9).
          expect(s.contains('Dr '), isFalse);
          expect(s.contains('Cr '), isFalse);
        }
        await _unmount(tester);
      }
    });

    // Layout sweep (09 suite F, ADR 2026-09-05f §H): both phone viewports,
    // 1.3 as well as 200 %, all three languages. The scale rides on
    // `pumpRk(textScale:)` so the viewport survives it — a bare
    // `MediaQueryData` hands the screen `Size.zero`, where nothing can
    // overflow and the assertion means nothing.
    for (final locale in _locales) {
      for (final size in rkPhones) {
        for (final scale in rkTextScales) {
          testWidgets(
            'F1-07-57 the checklist holds in ${locale.languageCode} at '
            '${(scale * 100).round()}% on ${size.width.toInt()}x'
            '${size.height.toInt()}',
            (tester) async {
              final (ledger, _) = await _newUser();
              await pumpRk(
                tester,
                const HomeScreen(),
                ledger: ledger,
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              expect(tester.takeException(), isNull);
              expectTextFits(tester, reason: 'above the fold');
              // Reachable, not clipped: the list scrolls to the checklist.
              await tester.drag(find.byType(ListView), const Offset(0, -1200));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expectTextFits(tester, reason: 'scrolled to the checklist');
              await _unmount(tester);
            },
          );
        }
      }
    }
  });
}
