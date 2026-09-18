// Paths this feature owns. S14 is reached from S8.1 (13 §3.2 row S14) — the
// business's own settings surface — so it is a root-navigator destination,
// not a tab root, and it carries the book id: partner positions only exist
// per business book (02 §7.1).
//
// ⚠️ SPEC: `shared/router.dart`'s `RkPaths` has no `partners` constant and
// belongs to another lane, so the literal lives here. When the shell adopts
// this route, move the string to `RkPaths.partners` and point this at it —
// noted in the lane report rather than edited across a directory boundary.
abstract final class PartnersPaths {
  /// S14 Partner positions, for one book.
  static const pattern = '/books/:bookId/partners';

  /// The concrete path for [bookId].
  static String of(String bookId) => '/books/$bookId/partners';

  /// S14.1 Profit distribution wizard, reached from S14 (13 §3.2).
  static const distributePattern = '/books/:bookId/partners/distribute';

  /// The concrete S14.1 path for [bookId].
  static String distributeOf(String bookId) =>
      '/books/$bookId/partners/distribute';
}
