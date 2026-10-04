// Paths owned by this feature. `RkPaths.ledger` is the tab root (S3, shared
// router); everything nested here is pushed on the root navigator so it
// covers the tab bar (13 §3.2 depth rule: S4/S4.1/S21 are one level below a
// root, S3.1 is a sheet, not a route).
import '../../shared/router.dart';

/// Paths under the Ledger tab (S3 root) plus the two global sheets/screens
/// this feature also owns (You-will-get/give, read-only mode is a widget,
/// not a route).
abstract final class LedgerPaths {
  /// S3 Ledger index — the tab root.
  static const index = RkPaths.ledger;

  /// S4 A/C statement of one account.
  static const statement = '${RkPaths.ledger}/account/:id';
  static String statementOf(String accountId) =>
      '${RkPaths.ledger}/account/$accountId';

  /// S4.1 Entry detail.
  static const entry = '${RkPaths.ledger}/entry/:id';
  static String entryOf(String entryId) => '${RkPaths.ledger}/entry/$entryId';

  /// 07 §7 You-will-get / You-will-give party lists; `:direction` is `get`
  /// or `give`.
  static const parties = '${RkPaths.ledger}/parties/:direction';
  static String partiesFor({required bool get}) =>
      '${RkPaths.ledger}/parties/${get ? 'get' : 'give'}';

  /// S21 Search. Bare, it searches the one book S3 resolves for itself.
  static const search = '${RkPaths.ledger}/search';

  /// S21 Search over [bookId] — the door a scoped surface (S1) uses, so the
  /// search covers the book on screen and not whichever the mirror lists
  /// first (07 §25 🔒 "in scope"; 13 §2.2 scope persists per tab).
  static String searchIn(String bookId) =>
      '$search?book=${Uri.encodeQueryComponent(bookId)}';
}
