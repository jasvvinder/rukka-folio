// F1 widget tests for the S4 → S5.5 door (02 §8.2 🔒 *Where it appears*, 07
// §5.5, 13 §3.2 rows S4/S5.5): the A/C statement header of a `cash` or
// `cash_collection` account carries the last count — *Last counted 27 Aug ·
// 20×500, 15×200, 25×100* — and the button that opens the count sheet,
// *Count again* for cash and *Open and count* for a collection box.
//
// 07 §1 rule 6: no dead doors. With no [CashCountScope] mounted, or with an
// account that has never been counted, the door still opens the sheet and the
// header line is simply absent — never a crash, never an inert tap.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart' hide StatementRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/cash_count/cash_count_fake.dart';
import 'package:rukka_folio/features/cash_count/cash_count_paths.dart';
import 'package:rukka_folio/features/cash_count/cash_count_source.dart';
import 'package:rukka_folio/features/ledger/screens/s4_account_statement_screen.dart';

import '../../shared/test_app.dart';

/// A viewport tall enough that the statement's `ListView` builds every row.
void tallViewport(WidgetTester tester, {double width = 500}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Tears the tree down inside the test so drift's cleanup timer fires.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

CashCountTarget targetFor(
  SeededLedger seed,
  String accountId, {
  required String name,
  required MoneySubtype subtype,
  LastCashCount? lastCount,
}) => CashCountTarget(
  bookId: seed.bookId,
  bookType: BookType.personal,
  account: Account(
    id: accountId,
    bookId: seed.bookId,
    name: name,
    accountClass: AccountClass.money,
    subtype: subtype,
    createdOrder: 1,
  ),
  bookBalance: const Paise(2160000),
  lastCount: lastCount,
);

void main() {
  group('S4 A/C statement → S5.5 cash count (02 §8.2, 07 §5.5)', () {
    testWidgets(
      'F1-07-124 a cash A/C statement header shows the last count with its '
      'breakdown and a Count again door to S5.5 (02 §8.2 🔒)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final fake = FakeCashCountSource(
          target: targetFor(
            seed,
            seed.cashId,
            name: 'Cash in hand',
            subtype: MoneySubtype.cash,
            lastCount: LastCashCount(
              date: seed.ledger.today().addDays(-11),
              counted: const Paise(1750000),
              sheet: const DenominationSheet(
                notes: {500: 20, 200: 15, 100: 25},
                coinsPaise: Paise(5000),
              ),
            ),
          ),
        );
        String? opened;
        await pumpRk(
          tester,
          CashCountScope(
            source: fake,
            child: AccountStatementScreen(
              accountId: seed.cashId,
              onCountCash: (id) => opened = CashCountPaths.forAccount(id),
            ),
          ),
          ledger: seed.ledger,
        );
        await tester.pumpAndSettle();

        // 02 §8.2 🔒 form: date first, then the sheet's groups, biggest note
        // first.
        expect(find.textContaining('20×500'), findsOneWidget);
        expect(find.textContaining('15×200'), findsOneWidget);
        expect(find.textContaining('25×100'), findsOneWidget);
        expect(find.textContaining('Last counted'), findsOneWidget);

        // The door, and it really opens S5.5 for *this* account.
        expect(find.text('Count again'), findsOneWidget);
        await tester.tap(find.text('Count again'));
        await tester.pump();
        expect(opened, '/cash-count/${seed.cashId}');
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-125 a cash_collection A/C says Open and count, and an account '
      'never counted shows the door alone with no header line (07 §1 rule 6)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final gollak = await seed.ledger.addAccount(
          seed.bookId,
          name: 'Gollak Cash',
          accountClass: AccountClass.money,
          subtype: MoneySubtype.cashCollection,
        );
        final fake = FakeCashCountSource(
          target: targetFor(
            seed,
            gollak.id,
            name: 'Gollak Cash',
            subtype: MoneySubtype.cashCollection,
          ),
        );
        String? opened;
        await pumpRk(
          tester,
          CashCountScope(
            source: fake,
            child: AccountStatementScreen(
              accountId: gollak.id,
              onCountCash: (id) => opened = CashCountPaths.forAccount(id),
            ),
          ),
          ledger: seed.ledger,
        );
        await tester.pumpAndSettle();

        expect(find.text('Open and count'), findsOneWidget);
        expect(find.text('Count again'), findsNothing);
        // Never counted: no header line at all, and nothing half-written.
        expect(find.textContaining('Last counted'), findsNothing);
        expect(find.textContaining('×'), findsNothing);

        await tester.tap(find.text('Open and count'));
        await tester.pump();
        expect(opened, '/cash-count/${gollak.id}');
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-126 with no CashCountScope mounted the door still opens the '
      'sheet and nothing throws; a non-cash A/C gets no door at all',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        String? opened;
        await pumpRk(
          tester,
          AccountStatementScreen(
            accountId: seed.cashId,
            onCountCash: (id) => opened = CashCountPaths.forAccount(id),
          ),
          ledger: seed.ledger,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Last counted'), findsNothing);
        expect(find.text('Count again'), findsOneWidget);
        await tester.tap(find.text('Count again'));
        await tester.pump();
        expect(opened, '/cash-count/${seed.cashId}');
        await unmount(tester);

        // A party A/C is not countable: no door, no header line (02 §8.2 —
        // cash and cash_collection only).
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seed.partyId, onCountCash: (_) {}),
          ledger: seed.ledger,
        );
        await tester.pumpAndSettle();
        expect(find.text('Count again'), findsNothing);
        expect(find.text('Open and count'), findsNothing);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-127 the header holds in EN, PA and HI at both scales on both '
      'phones, cutting no word (07 §1 rule 11, 09 F1 viewports)',
      (tester) async {
        for (final (locale, phone, scale) in [
          for (final locale in rkLocales)
            for (final phone in rkPhones)
              for (final scale in rkTextScales) (locale, phone, scale),
        ]) {
          final seed = await seedSoloLedger();
          final fake = FakeCashCountSource(
            target: targetFor(
              seed,
              seed.cashId,
              name: 'Cash in hand',
              subtype: MoneySubtype.cash,
              lastCount: LastCashCount(
                date: seed.ledger.today().addDays(-11),
                counted: const Paise(1750000),
                sheet: const DenominationSheet(
                  notes: {500: 20, 200: 15, 100: 25},
                  coinsPaise: Paise(5000),
                ),
              ),
            ),
          );
          await pumpRk(
            tester,
            CashCountScope(
              source: fake,
              child: AccountStatementScreen(
                accountId: seed.cashId,
                onCountCash: (_) {},
              ),
            ),
            ledger: seed.ledger,
            locale: locale,
            textScale: scale,
            viewport: phone,
          );
          await tester.pumpAndSettle();

          final where = '${locale.languageCode} at ${scale}x on $phone';
          expect(
            tester.takeException(),
            isNull,
            reason: 'S4 cash-count header overflowed — $where',
          );
          // Measured, not merely un-thrown: a squeezed word is drawn past the
          // edge in silence, so the header's own words are checked too.
          expectTextFits(tester, reason: 'S4 cash-count header — $where');
          // The breakdown is Latin numerals in every locale (11 §4.4).
          expect(find.textContaining('20×500'), findsOneWidget);
          await unmount(tester);
        }
      },
    );
  });
}
