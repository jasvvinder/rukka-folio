// F1-07-229: the **Menu → per book** door into S10.4, the Year Close ceremony
// (07 §13 last bullet 🔒, ADR 2026-09-03 ruling 1, 13 §3.2 row S10.4).
//
// Two things are pinned here, and they are the two that can silently go wrong:
//
//  · **the path** — `ClosePaths.forYear(bookId, ClosePaths.fyStartOf(fy))`,
//    whose parameter is the financial year's **first month** as `YYYY-MM` and
//    never a bare year, because a book's FY does not have to start in April;
//  · **the year offered** — the earliest financial year that has already ended
//    and is not certified. Years close in order (every month of the year must
//    be locked first, 02 §8.1 🔒), so any later year would be a door into a
//    ceremony that could only refuse (07 §1 rule 6).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/close/close_paths.dart';
import 'package:rukka_folio/features/menu/screens/s8_menu_screen.dart';
import 'package:rukka_folio/features/menu/year_close_books.dart';

import '../../shared/test_app.dart';

/// 10 May 2027 — FY 2026-27 is wholly past for an April book, and FY 2026 is
/// wholly past for a calendar-year one.
DateTime _may2027() => DateTime(2027, 5, 10, 10);

void main() {
  Widget menu({
    List<MenuYearCloseBook> books = const [],
    void Function(MenuYearCloseBook)? onOpenYearClose,
  }) => MenuScreen(
    onOpenReports: () {},
    onOpenBooks: () {},
    onOpenBackup: () {},
    onOpenDevices: () {},
    onOpenSettings: () {},
    yearCloseBooks: books,
    onOpenYearClose: onOpenYearClose,
  );

  testWidgets('F1-07-229 one *Year close* row per book, each naming its book '
      'and its year, and the tap reaches that book (07 §13 🔒)', (
    tester,
  ) async {
    final rows = [
      MenuYearCloseBook(
        bookId: 'b1',
        bookName: 'Me',
        year: FinancialYear(2026, startMonth: 4),
      ),
      MenuYearCloseBook(
        bookId: 'b2',
        bookName: 'Kirana',
        year: FinancialYear(2026, startMonth: 1),
      ),
    ];
    final taken = <String>[];
    await pumpRk(
      tester,
      menu(books: rows, onOpenYearClose: (b) => taken.add(b.bookId)),
    );

    expect(find.text('Year close'), findsNWidgets(2));
    expect(find.textContaining('Me · certify FY 2026-27'), findsOneWidget);
    expect(find.textContaining('Kirana · certify FY 2026'), findsOneWidget);

    await tester.tap(find.textContaining('Kirana · certify'));
    await tester.pumpAndSettle();
    expect(taken, ['b2']);
  });

  testWidgets('F1-07-229 with nothing to certify the row stays, disabled with '
      'its reason — never a door that quietly disappears (07 §1 rule 6)', (
    tester,
  ) async {
    await pumpRk(tester, menu());
    expect(find.text('Year close'), findsOneWidget);
    expect(
      find.text('A financial year can be certified once it has ended.'),
      findsOneWidget,
    );
    // Disabled, so it carries no tap of its own.
    expect(
      tester.widget<MenuScreen>(find.byType(MenuScreen)).yearCloseBooks,
      isEmpty,
    );
  });

  test('F1-07-229 the path is built from the FY\'s FIRST MONTH, so a trust on '
      'the calendar year gets its own door and not April\'s', () {
    expect(
      ClosePaths.forYear(
        'b1',
        ClosePaths.fyStartOf(FinancialYear(2026, startMonth: 4)),
      ),
      '/close/b1/year/2026-04',
    );
    expect(
      ClosePaths.forYear(
        'b2',
        ClosePaths.fyStartOf(FinancialYear(2026, startMonth: 1)),
      ),
      '/close/b2/year/2026-01',
    );
  });

  test(
    'F1-07-229 the year offered is the EARLIEST ended, uncertified one, and '
    'the book drops out of the list once it is certified (02 §8.1 🔒)',
    () async {
      final ledger = await openTestLedger(now: _may2027);
      await ledger.bootstrapSolo(
        firstBookName: 'Me',
        startDate: LocalDate(2025, 4, 1),
      );
      final bookId = (await ledger.mirror.bookIds()).single;
      // Both years hold entries: a financial year with nothing in it locally is
      // *archived* rather than replayed (03 §3.3 rule 3), which is a different
      // story from the one this test is about.
      final cash = (await ledger.addAccount(
        bookId,
        name: 'Cash in hand',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.cash,
      )).id;
      final fuel = (await ledger.addAccount(
        bookId,
        name: 'Diesel',
        accountClass: AccountClass.categoryExpense,
      )).id;
      await ledger.openingBalances(
        bookId,
        balances: {cash: 5_000_000},
        date: LocalDate(2025, 4, 1),
      );
      for (final day in [LocalDate(2025, 7, 4), LocalDate(2026, 7, 4)]) {
        await ledger.moneyOut(
          bookId: bookId,
          from: cash,
          forWhat: fuel,
          paise: 100_000,
          date: day,
          note: 'Diesel',
        );
      }

      // Two ended years behind us (FY 2025-26 and FY 2026-27): the earliest is
      // the only one that can close, because months — and so years — lock in
      // order.
      final rows = await menuYearCloseBooks(ledger);
      expect(rows, hasLength(1));
      expect(rows.single.bookId, bookId);
      expect(rows.single.bookName, 'Me');
      expect(rows.single.year, FinancialYear(2025, startMonth: 4));

      final first = FinancialYear(2025, startMonth: 4);
      for (final m in first.months) {
        await ledger.lockMonth(bookId, m, declaredBalances: const {});
      }
      await ledger.closeYear(bookId, first);
      final next = await menuYearCloseBooks(ledger);
      expect(next.single.year, FinancialYear(2026, startMonth: 4));

      final second = FinancialYear(2026, startMonth: 4);
      for (final m in second.months) {
        await ledger.lockMonth(bookId, m, declaredBalances: const {});
      }
      await ledger.closeYear(bookId, second);
      // Nothing ended is left uncertified, so the Menu says so with its
      // disabled row rather than offering the year still running.
      expect(await menuYearCloseBooks(ledger), isEmpty);
    },
  );
}
