// The path S5.5 lives at. The sheet is reached from a cash A/C's statement
// (*Count again* / *Open and count*), from month close step 1, and from the
// account screen (07 §5.5, 13 §3.2 row S5.5) — three doors, one destination,
// so it is a **root-navigator** route that covers the tab bar, like the entry
// flow.
//
// ⚠️ SPEC: `shared/router.dart`'s `RkPaths` has no cash-count constant and is
// another lane's file, so the literal lives here (the same arrangement
// `AdvancesPaths` made). When the shell adopts the route, move the string to
// `RkPaths.cashCount` and point this at it.
abstract final class CashCountPaths {
  /// The route pattern, with the account id as its one parameter.
  static const pattern = '/cash-count/:accountId';

  /// The parameter name in [pattern].
  static const accountParam = 'accountId';

  /// The sheet for one cash or collection A/C.
  static String forAccount(String accountId) => '/cash-count/$accountId';
}
