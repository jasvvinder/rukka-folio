// F1 widget tests for S21 Search (07 §25 🔒 ⟦tests: F1-07-35⟧, 13 §3.2 row
// S21, §4.1 P1, §4.3 states).
//
// Every result here comes from the real in-memory ledger's projection — the
// seeded solo book of `test_app.dart` — so a search seam that returned an
// empty index would fail every "finds" case below, not pass it.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/ledger_routes.dart';
import 'package:rukka_folio/features/ledger/screens/s21_search_screen.dart';
import 'package:rukka_folio/features/ledger/screens/s3_1_quick_add_sheet.dart';
import 'package:rukka_folio/features/ledger/screens/s3_ledger_index_screen.dart';
import 'package:rukka_folio/features/ledger/screens/s4_1_entry_detail_screen.dart';
import 'package:rukka_folio/features/ledger/screens/s4_account_statement_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/format/money_format.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/widgets/rk_ruled_card.dart';

import '../../shared/test_app.dart';

/// Tears the tree down inside the test so drift's stream-cancel timers fire
/// before the pending-timer invariant runs.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

/// The [MoneyText] inside the first (topmost) result row that shows
/// [label] — a name can be both an account hit and a note hit's counter
/// account.
Finder amountIn(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label).first,
    matching: find.byType(RkLabelAmountRow),
  ),
  matching: find.byType(MoneyText),
);

int paiseOf(WidgetTester tester, Finder f) => tester.widget<MoneyText>(f).paise;

/// What the [MoneyText] at [f] actually draws — figure *and* side word. The
/// paise alone cannot show a balance whose direction is only a tint.
String drawnOf(WidgetTester tester, Finder f) => tester
    .widget<RichText>(find.descendant(of: f, matching: find.byType(RichText)))
    .text
    .toPlainText();

/// The result list's own scrollable (the field has one too).
Finder resultList() => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

String entryWithNote(SeededLedger seed, String note) =>
    seed.entries.firstWhere((e) => e.note == note).id;

void main() {
  group('S21 Search (07 §25, 13 §3.2)', () {
    testWidgets('F1-07-35 empty query: the next action, and no results', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const LedgerSearchScreen(),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Type a name, or a few words from a note.'), findsOne);
      expect(find.byType(MoneyText), findsNothing);
      // Autofocused: the 8-second rule starts at the field (07 §1).
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofocus,
        isTrue,
      );
      await unmount(tester);
    });

    testWidgets('F1-07-35 a name finds parties and accounts, grouped by type, '
        'drawn with the live balance', (tester) async {
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const LedgerSearchScreen(),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );

      await type(tester, 'RAMESH');
      expect(find.text('Parties'), findsOneWidget);
      expect(find.text('Accounts'), findsNothing);
      expect(find.text('Ramesh'), findsOneWidget);
      // Ramesh owes +₹5,000 after seeding (test_app.dart).
      expect(paiseOf(tester, amountIn('Ramesh')), 500000);
      // …and the row says so in a word, not only a tint (07 §1 rule 3 🔒,
      // 13 §8): he owes us, so his khata is Dr.
      expect(drawnOf(tester, amountIn('Ramesh')), '₹5,000 Dr');

      await type(tester, 'sa');
      // "SBI Saving" and "Shop sales" match by name; Saturday's note too.
      expect(find.text('Parties'), findsNothing);
      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('In notes'), findsOneWidget);
      expect(paiseOf(tester, amountIn('SBI Saving')), 11460000);
      expect(paiseOf(tester, amountIn('Shop sales')), -1860000);
      expect(drawnOf(tester, amountIn('SBI Saving')), '₹1,14,600 Dr');
      expect(drawnOf(tester, amountIn('Shop sales')), '₹18,600 Cr');
      // The note row's label is its counter account: Saturday's UPI sale
      // into SBI, drawn from the bank's side (+ = money came in).
      expect(find.text('Shop sales'), findsNWidgets(2));
      final saturday = find.ancestor(
        of: find.textContaining('Saturday sales'),
        matching: find.byType(RkLabelAmountRow),
      );
      expect(
        paiseOf(
          tester,
          find.descendant(of: saturday, matching: find.byType(MoneyText)),
        ),
        1860000,
      );
      // Group order: Accounts above In notes, names A-Z inside a group.
      double y(String t) => tester.getTopLeft(find.text(t).first).dy;
      expect(y('Accounts'), lessThan(y('SBI Saving')));
      expect(y('SBI Saving'), lessThan(y('Shop sales')));
      expect(y('Shop sales'), lessThan(y('In notes')));
      await unmount(tester);
    });

    testWidgets('F1-07-35 a note hit is a P1 row: counter account, the words '
        'with the date, the amount from the money side', (tester) async {
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const LedgerSearchScreen(),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );

      await type(tester, 'repay');
      expect(find.text('Parties'), findsNothing);
      expect(find.text('In notes'), findsOneWidget);
      // Cash in from Ramesh, yesterday: the label is the counter account,
      // the figure is the cash line, + = money came in.
      expect(find.text('Yesterday · part repayment'), findsOneWidget);
      expect(paiseOf(tester, amountIn('Ramesh')), 500000);
      final money = tester.widget<MoneyText>(amountIn('Ramesh'));
      expect(money.showDirection, isTrue, reason: 'colour is never alone');

      await type(tester, 'diesel');
      // The category by name, and the entry by its note "Diesel A/C".
      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('In notes'), findsOneWidget);
      final notes = find.textContaining('· Diesel A/C');
      expect(notes, findsOneWidget);
      final noteRow = find.ancestor(
        of: notes,
        matching: find.byType(RkLabelAmountRow),
      );
      final noteAmount = find.descendant(
        of: noteRow,
        matching: find.byType(MoneyText),
      );
      expect(paiseOf(tester, noteAmount), -240000);
      await unmount(tester);
    });

    testWidgets('F1-07-35 rows open S4 (account, party) and S4.1 (note)', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      String? account;
      String? entry;
      await pumpRk(
        tester,
        LedgerSearchScreen(
          onOpenAccount: (id) => account = id,
          onOpenEntry: (id) => entry = id,
        ),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );

      await type(tester, 'ramesh');
      // The merged row announces name, amount *and* side (13 §8: screen
      // readers hear amount and direction).
      final handle = tester.ensureSemantics();
      final row = find.ancestor(
        of: find.text('Ramesh'),
        matching: find.byType(RkLabelAmountRow),
      );
      expect(tester.getSemantics(row).label, contains('₹5,000 Dr'));
      handle.dispose();
      await tester.tap(find.text('Ramesh'));
      expect(account, seed.partyId);

      await type(tester, 'saturday');
      await tester.tap(find.textContaining('Saturday sales'));
      expect(entry, entryWithNote(seed, 'Saturday sales'));
      await unmount(tester);
    });

    testWidgets('F1-07-35 no results offers the create row (07 §6, no dead '
        'end)', (tester) async {
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const LedgerSearchScreen(),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );

      await type(tester, '  Langar  ');
      expect(find.text('Nothing matches "Langar"'), findsOneWidget);
      expect(find.byType(MoneyText), findsNothing);
      await tester.tap(find.text('New A/C'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickAddSheet), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('F1-07-35 results are live: a new note appears while S21 is '
        'open', (tester) async {
      final seed = await seedSoloLedger();
      await pumpRk(
        tester,
        const LedgerSearchScreen(),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );
      await type(tester, 'tea stall');
      expect(find.text('Nothing matches "tea stall"'), findsOneWidget);

      await tester.runAsync(
        () => seed.ledger.moneyOut(
          bookId: seed.bookId,
          from: seed.cashId,
          forWhat: seed.fuelId,
          paise: 12_000,
          date: seed.ledger.today(),
          note: 'Tea stall',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Today · Tea stall'), findsOneWidget);
      expect(paiseOf(tester, amountIn('Diesel')), -12_000);
      await unmount(tester);
    });

    testWidgets('F1-07-35 search is scoped to the book in scope', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      final shop = await seed.ledger.createBook(
        name: 'Shop',
        type: BookType.family,
      );
      await seed.ledger.addAccount(
        shop,
        name: 'Ramesh Traders',
        accountClass: AccountClass.party,
      );

      await pumpRk(
        tester,
        LedgerSearchScreen(bookId: seed.bookId),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );
      await type(tester, 'ramesh');
      expect(find.text('Ramesh'), findsOneWidget);
      expect(find.text('Ramesh Traders'), findsNothing);
      await unmount(tester);

      await pumpRk(
        tester,
        LedgerSearchScreen(bookId: shop),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );
      await type(tester, 'ramesh');
      expect(find.text('Ramesh Traders'), findsOneWidget);
      expect(find.text('Ramesh'), findsNothing);
      await unmount(tester);
    });

    testWidgets('F1-07-35 error state names the cause and offers Try again', (
      tester,
    ) async {
      // A ledger with no book: the scope cannot resolve.
      final ledger = await openTestLedger();
      await pumpRk(tester, const LedgerSearchScreen(), ledger: ledger);
      expect(find.text("Couldn't search your books"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('F1-07-35 S3 opens S21 from its app bar (13 §3.2: S3/S1)', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      var opened = 0;
      await pumpRk(
        tester,
        LedgerIndexScreen(onOpenSearch: () => opened++),
        ledger: seed.ledger,
        viewport: rkTallViewport,
      );
      await tester.tap(find.byTooltip('Search'));
      expect(opened, 1);
      await unmount(tester);
    });

    testWidgets('F1-07-35 through the real router: S3 → S21 → S4 and S21 → '
        'S4.1 (ledgerRoot + ledgerRoutes, not test callbacks)', (tester) async {
      // The counter test above is reached whatever the callback does (the
      // s8_help_door_test pattern). This one drives the production wiring:
      // ledgerRoot supplies onOpenSearch, ledgerRoutes mounts S21 at
      // LedgerPaths.search and supplies its row callbacks. Drop any of them
      // and S21 is unreachable or its rows go dead — and this goes red.
      rkViewport(tester, rkTallViewport);
      final seed = await seedSoloLedger();
      final router = buildRouter(
        featureRoutes: ledgerRoutes,
        ledger: ledgerRoot,
        initialLocation: RkPaths.ledger,
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
      expect(find.byType(LedgerIndexScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), LedgerPaths.search);
      expect(find.byType(LedgerSearchScreen), findsOneWidget);

      await type(tester, 'ramesh');
      await tester.tap(find.text('Ramesh'));
      await tester.pumpAndSettle();
      expect(
        router.state.uri.toString(),
        LedgerPaths.statementOf(seed.partyId),
      );
      expect(find.byType(AccountStatementScreen), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), LedgerPaths.search);
      await type(tester, 'saturday');
      await tester.tap(find.textContaining('Saturday sales'));
      await tester.pumpAndSettle();
      expect(
        router.state.uri.toString(),
        LedgerPaths.entryOf(entryWithNote(seed, 'Saturday sales')),
      );
      expect(find.byType(EntryDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('F1-07-35 every state resolves in EN/PA/HI with no overflow at '
        '1.3x and 200% on both phones', (tester) async {
      // Each state at the harness's own `viewport:`/`textScale:` — the
      // results state with all three groups ('a': parties, accounts, notes),
      // the empty-query state with the field's hint, and the miss with its
      // create row. The results list is lazy: at 200 % the In-notes rows sit
      // below the fold and are never built, so the list is scrolled to its
      // end and checked at every stop, and at least one note row must have
      // been on screen — otherwise the new P1 row was never measured.
      for (final locale in rkLocales) {
        for (final phone in rkPhones) {
          for (final scale in rkTextScales) {
            for (final query in ['', 'a', 'zzz']) {
              final seed = await seedSoloLedger();
              await pumpRk(
                tester,
                LedgerSearchScreen(initialQuery: query),
                ledger: seed.ledger,
                locale: locale,
                textScale: scale,
                viewport: phone,
              );
              final where =
                  'S21 "$query" at ${scale}x on $phone in '
                  '${locale.languageCode}';
              expect(tester.takeException(), isNull, reason: where);
              expectTextFits(tester, reason: where);
              if (query == '') {
                // 13 §8: 200 % without truncation. The hint must not be cut
                // to a word and an ellipsis (expectTextFits skips ellipsised
                // text), and the field must grow to hold all of it.
                final hint = find.text(
                  lookupAppLocalizations(locale).ledgerSearchFieldHint,
                );
                expect(hint, findsOneWidget, reason: where);
                final para = tester.renderObject<RenderParagraph>(hint);
                expect(para.didExceedMaxLines, isFalse, reason: where);
                expect(para.overflow, TextOverflow.clip, reason: where);
                expect(
                  tester.getRect(hint).bottom,
                  lessThanOrEqualTo(
                    tester.getRect(find.byType(InputDecorator)).bottom,
                  ),
                  reason: where,
                );
              }
              if (query == 'a') {
                expect(find.byType(MoneyText), findsWidgets, reason: where);
                final notes = find.byIcon(Icons.notes_outlined);
                var sawNote = notes.evaluate().isNotEmpty;
                final position = tester
                    .state<ScrollableState>(resultList())
                    .position;
                while (position.extentAfter > 0) {
                  await tester.drag(
                    resultList(),
                    Offset(0, -position.viewportDimension * 0.8),
                  );
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull, reason: where);
                  expectTextFits(tester, reason: where);
                  sawNote = sawNote || notes.evaluate().isNotEmpty;
                }
                expect(sawNote, isTrue, reason: '$where: no note row built');
              }
              await unmount(tester);
            }
          }
        }
      }
    });
  });
}
