// Paths owned by `features/books` (features/README: never re-type a path
// elsewhere). S9 is reached from Menu → Books (07 §5.7 🔒) and S9.5 hangs
// under it, one level down (13 §3.1 depth rule).
//
// The S9.5 chain is deliberately *not* `OnboardingPaths.business…`: those
// locations belong to first-run onboarding and their steps lead on to S0.6c
// and Home. S9.5 is the same three screens reached later, so it has its own
// locations and its own destination — back to S9 — while the screens
// themselves are imported from `features/onboarding` (07 §5.7: one flow, two
// entry points, never two implementations).
abstract final class BooksPaths {
  /// S9 Books — the list, with the S9.5 entry point on it.
  static const root = '/books';

  /// S9.5 step 1 — S0.6a *Name the business* (07 §5.7 🔒: name · who owns it
  /// · financial year start · opening balances, and nothing else).
  static const addBusiness = '/books/add-business';

  /// S9.5 step 2 — S0.6a1 *Who owns this business?*, on the *Shared with
  /// others* branch only (ADR 2026-09-09 §1; the step is not skippable, its
  /// secondary returns to *Just me*).
  static const addBusinessOwners = '/books/add-business/owners';

  /// S9.5 step 3 — S0.6b, the grouped review-and-fill over the seeded chart
  /// (ADR 2026-09-09c §3). The book is created here, as in onboarding.
  static const addBusinessOpening = '/books/add-business/opening';
}
