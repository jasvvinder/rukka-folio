// The path S10 lives at. The wizard is reached from the Home *Close card*
// (07 §13 bullet 1) and from the family close status (S10.1, not this slice),
// and in both cases it covers the tab bar until the closer leaves it — so it
// is a **root-navigator** route, like the entry flow and the cash count sheet.
//
// Two parameters, because a close is always *this book's* *this month*: a
// joint family closes several books in the same month and the karta is often
// part-way through two of them (07 §13 *The family's state, not just yours*).
//
// ⚠️ SPEC: `shared/router.dart`'s `RkPaths` has no month-close constant and is
// another lane's file, so the literal lives here (the same arrangement
// `CashCountPaths` and `AdvancesPaths` made). When the shell adopts the route,
// move the string to `RkPaths.close` and point this at it.
import 'package:core_ledger/core_ledger.dart';

abstract final class ClosePaths {
  /// The route pattern, with the book and the month as its parameters.
  static const pattern = '/close/:bookId/:period';

  /// The book parameter in [pattern].
  static const bookParam = 'bookId';

  /// The month parameter in [pattern], as `YYYY-MM` — `YearMonth.toString()`'s
  /// own form, so the path and the engine agree by construction.
  static const periodParam = 'period';

  /// The wizard for one book's month. [period] is `YYYY-MM`.
  static String forBook(String bookId, String period) =>
      '/close/$bookId/$period';

  /// S10.2 on its own, for a month that is **already** locked — the door the
  /// Home close card gives way to once the book has closed (07 §13 🔒). The
  /// wizard shows the same card inline the moment the lock lands; this is how
  /// the closer reaches it again a week later.
  static const summaryPattern = '/close/:bookId/:period/summary';

  /// The month summary card for one book's month. [period] is `YYYY-MM`.
  static String summaryFor(String bookId, String period) =>
      '/close/$bookId/$period/summary';

  /// S10.4 — the Year Close ceremony for one book's financial year (02 §8.1
  /// 🔒, 13 §3.2 row S10.4). Root-navigator, like the wizard: certifying a
  /// year covers the tab bar until the closer leaves it.
  ///
  /// The parameter is the FY's **first month** in `YearMonth.toString()`'s own
  /// form — `2026-04` for FY 2026-27 — rather than a bare start year. A book's
  /// financial year does not have to start in April (`FinancialYear.startMonth`
  /// is 1–12 and a trust may run the calendar year), so a year alone cannot
  /// name the period; the first month always can, and it reuses the parser the
  /// month route already has rather than inventing a second calendar.
  static const yearPattern = '/close/:bookId/year/:fyStart';

  /// The FY parameter in [yearPattern], as `YYYY-MM` — the FY's first month.
  static const yearParam = 'fyStart';

  /// The Year Close ceremony for [bookId]. [fyStart] is `YYYY-MM`; build it
  /// with [fyStartOf] rather than by hand.
  static String forYear(String bookId, String fyStart) =>
      '/close/$bookId/year/$fyStart';

  /// The [yearPattern] parameter for [fy] — its first month, `YYYY-MM`.
  static String fyStartOf(FinancialYear fy) =>
      YearMonth(fy.startYear, fy.startMonth).toString();
}
