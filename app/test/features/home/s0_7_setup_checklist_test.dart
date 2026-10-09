// ADR 2026-10-07 ruling 3 re-read (F1-07-57 assertions it flips cite it): the
// recovery-sheet row's copy, and the card's exit rule — every row ticked or
// *Not needed*, so the scanned-back sheet now holds it too.
//
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
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/prefs.dart';

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
  group(
    'S0.7 setup checklist (13 §3.2 row S0.7, 07 §4, 07 §3.1 step 7 🔒)',
    () {
      testWidgets(
        'F1-07-57 a new user gets the checklist in place of the position card, '
        'with every step of 07 §4 named',
        (tester) async {
          _tall(tester);
          final (ledger, _) = await _newUser();
          await pumpRk(tester, const HomeScreen(), ledger: ledger);

          expect(find.byType(HomeSetupChecklist), findsOneWidget);
          expect(find.byType(HomePositionCard), findsNothing);
          // Canvas 1 frame O8's copy (desk 172).
          expect(
            find.text('A few minutes now, and your books are live.'),
            findsOneWidget,
          );
          expect(find.text('Opening balances'), findsOneWidget);
          expect(find.text('Write your first entry'), findsOneWidget);
          // ADR 2026-10-07 ruling 3: the sheet row reads *Check your recovery
          // sheet · Not scanned back yet* until the sheet is scanned back.
          expect(find.text('Check your recovery sheet'), findsOneWidget);
          expect(find.text('Not scanned back yet'), findsOneWidget);
          expect(find.text('Add your family'), findsOneWidget);
          // Nothing is done yet, so no step wears the tick.
          expect(find.byIcon(Icons.check_circle), findsNothing);
          await _unmount(tester);
        },
      );

      testWidgets(
        'F1-07-57 tapping the opening-balances step resumes the wizard — that '
        'is what makes skipping it safe (07 §3.1 step 7 🔒)',
        (tester) async {
          _tall(tester);
          final (ledger, _) = await _newUser();
          final steps = <SetupStep>[];
          await pumpRk(
            tester,
            HomeScreen(onSetupStep: steps.add),
            ledger: ledger,
          );

          await tester.tap(find.text('Opening balances'));
          await tester.pump();
          expect(steps, [SetupStep.openingBalances]);
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
          // Step 2 is done: a filled tick and the words struck through —
          // colour is never the only carrier (07 §1 rule 3).
          expect(find.byIcon(Icons.check_circle), findsOneWidget);
          expect(
            tester
                .widget<Text>(find.text('Write your first entry'))
                .style
                ?.decoration,
            TextDecoration.lineThrough,
          );
          await _unmount(tester);
        },
      );

      // Desk 172 (owner-ruled 6 Oct) moved this case: an opening is setup, not
      // the first entry, so with only the balances recorded the checklist stays
      // with its first row ticked (HomeSnapshot.firstRun; P1A review, finding
      // 1). It goes once an ordinary entry follows.
      testWidgets(
        'F1-07-57 with only the opening balances recorded the checklist stays, '
        'its first row ticked; the first entry retires it only once the '
        'recovery sheet is scanned back (ADR 2026-10-07 ruling 3)',
        (tester) async {
          _tall(tester);
          final (ledger, bookId) = await _newUser();
          final cash = await _cashOf(ledger, bookId);
          await ledger.openingBalances(bookId, balances: {cash.id: 1500000});
          await pumpRk(tester, const HomeScreen(), ledger: ledger);

          expect(find.byType(HomeSetupChecklist), findsOneWidget);
          expect(find.byType(HomePositionCard), findsNothing);
          expect(
            tester
                .widget<Text>(find.text('Opening balances'))
                .style
                ?.decoration,
            TextDecoration.lineThrough,
          );
          await _unmount(tester);

          await _firstEntry(ledger, bookId);
          // ADR 2026-10-07 ruling 3 flips the old assertion: the card leaves
          // only when every row is ticked, and *Check your recovery sheet*
          // is not until the printed sheet is scanned back.
          final prefs = MemoryPrefs();
          Future<void> pumpHome() async {
            final settings = AppSettings(prefs: prefs);
            await settings.load();
            await pumpRk(
              tester,
              AppSettingsScope(settings: settings, child: const HomeScreen()),
              ledger: ledger,
            );
            await tester.pumpAndSettle();
          }

          await pumpHome();
          expect(find.byType(HomeSetupChecklist), findsOneWidget);
          expect(find.byType(HomePositionCard), findsOneWidget);
          await _unmount(tester);

          prefs.values[RkPrefKeys.recoverySheetVerified] = '1';
          await pumpHome();
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
                await tester.drag(
                  find.byType(ListView),
                  const Offset(0, -1200),
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                expectTextFits(tester, reason: 'scrolled to the checklist');
                await _unmount(tester);
              },
            );
          }
        }
      }
    },
  );
}
