// Which financial year the Menu offers to certify, per book — the *Menu → per
// book* door 07 §13 🔒's last bullet gives the Year Close ceremony, and the
// second of S10.4's two doors (the first is the prompt the moment the year's
// last month locks, wired on S10.2).
//
// The path is always built with `ClosePaths.forYear(bookId,
// ClosePaths.fyStartOf(fy))`: the FY parameter is the year's **first month** as
// `YYYY-MM`, because a book's financial year does not have to start in April
// (a trust may run the calendar year), so a bare year cannot name it.
//
// ⚠️ SPEC: 07 §13 🔒 says *Menu → per book* and ADR 2026-09-03 ruling 1 says the
// year close is reached after March, but neither says **which** year a book
// with two uncertified years behind it should be offered. Certifying the wrong
// year is the one mistake 02 §8.1 🔒 makes permanent, so the conservative
// reading is taken here: the **earliest financial year that has already ended
// and is not certified**. Years close in order (months lock in order, and every
// month of the year must be locked), so the earliest uncertified year is the
// only one that can actually close — offering a later one would be offering a
// ceremony that must refuse.
import 'package:core_ledger/core_ledger.dart';

import '../../shared/ledger/local_ledger.dart';

/// One *Year close* row on S8: a book, and the year it is being offered.
final class MenuYearCloseBook {
  /// Creates the row's data.
  const MenuYearCloseBook({
    required this.bookId,
    required this.bookName,
    required this.year,
  });

  /// The book whose year would be certified.
  final String bookId;

  /// Its name, as the user wrote it.
  final String bookName;

  /// The year offered — the earliest ended, uncertified one.
  final FinancialYear year;
}

/// The *Year close* rows for every book on this device, in book order.
///
/// A book still inside its first financial year, and a book whose every ended
/// year is already certified, contribute **no row**: there is nothing to
/// certify, and a row that could only refuse is worse than none (07 §1 rule 6).
/// The screen states that case once, rather than dropping the door silently.
Future<List<MenuYearCloseBook>> menuYearCloseBooks(LocalLedger ledger) async {
  final today = ledger.today();
  final out = <MenuYearCloseBook>[];
  for (final b in await ledger.watchBooks().first) {
    final startMonth = await ledger.fyStartMonthOf(b.id);
    final certified = {
      for (final y in await ledger.certifiedYears(b.id))
        if (y.status == YearStatus.closed) y.year,
    };
    final current = FinancialYear.of(today, startMonth: startMonth);
    final startDate = b.startDate;
    var fy = FinancialYear.of(
      startDate == null ? today : LocalDate.parse(startDate),
      startMonth: startMonth,
    );
    while (fy.firstDay.isBefore(current.firstDay)) {
      if (!certified.contains(fy)) {
        out.add(MenuYearCloseBook(bookId: b.id, bookName: b.name, year: fy));
        break;
      }
      fy = FinancialYear(fy.startYear + 1, startMonth: fy.startMonth);
    }
  }
  return List.unmodifiable(out);
}
