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
}
