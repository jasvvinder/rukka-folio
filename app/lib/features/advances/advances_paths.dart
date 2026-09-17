// Paths this feature owns. S5 is reached from S1 (the Home advances position
// row) and from S6 (an advance card in the Inbox) — 13 §3.2 row S5 — so it is
// a root-navigator destination, not a tab root.
//
// ⚠️ SPEC: `shared/router.dart`'s `RkPaths` has no `advances` constant yet and
// belongs to another lane, so the literal lives here. When the shell adopts
// this route, move the string to `RkPaths.advances` and point this at it —
// noted in the lane report rather than edited across a directory boundary.
abstract final class AdvancesPaths {
  /// S5 Advances — *Advance with you* + *Advance out*.
  static const index = '/advances';

  /// S5.1 Advance request (amount + purpose → approver). **Not built here** —
  /// the next lane owns it. Reserved so that nothing else takes the path; no
  /// route declares it and no screen links to it, because 07 §1 rule 6
  /// forbids a door that leads nowhere.
  static const request = '/advances/request';
}
