// `features/books` routes (features/README "Routes", 13 §3.1/§3.2). S9 and
// its S9.5 chain are **root-navigator** routes: Menu pushes `BooksPaths.root`
// exactly as it pushes Devices and Settings, and the orchestrator mounts
// [booksRoutes] in the app's `featureRoutes`.
//
// 🔒 07 §5.7 — S9.5 is *the onboarding business flow reached again*, not a
// second implementation of it: the three screens below are S0.6a, S0.6a1 and
// S0.6b, imported from `features/onboarding`, with the same answers holder
// ([onboardingFlow]) and the same committing host ([BusinessOpeningHost]).
// Only the locations and the destination differ — S9.5 returns to S9 where
// onboarding went on to S0.6c / Home. Four fields and nothing else: name ·
// who owns it · financial-year start · opening balances.
//
// Entering S9.5 calls `addAnotherBusiness()`, the O6c loop's own move
// (07 §3.1.1): the flow's cursor steps past every business already collected,
// so S0.6a opens blank and the committing step creates a **new** book instead
// of re-editing the first one. A resumed step still never creates a second
// book for the same answers — that is [OnboardingFlow.businessBookId]'s job,
// unchanged.
//
// ⚠️ SPEC: S0.6a1 tags the first owner row with the creating user's name,
// which onboarding took from S0.4. After onboarding is over there is no
// persisted profile name any screen can read (`LocalLedger` carries
// [LedgerIdentity] — ids, no display name), so S9.5 passes whatever the
// in-process [onboardingFlow] still holds and the row is simply blank on a
// cold start rather than inventing a name. Naming a home for the user's own
// display name is a `packages/data` / `shared/` change; it is in the lane
// report.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../onboarding/onboarding_routes.dart';
import 'books_paths.dart';
import 'screens/s9_books_screen.dart';

export 'books_paths.dart';
export 'screens/s9_books_screen.dart' show BookRow, BooksScreen;

/// The answers holder S9.5 shares with onboarding — one flow, two entry
/// points (07 §5.7 🔒).
final OnboardingFlow addBusinessFlow = onboardingFlow;

/// S9 at [BooksPaths.root] and the S9.5 chain beneath it.
final List<RouteBase> booksRoutes = [
  GoRoute(
    path: BooksPaths.root,
    builder: (context, state) =>
        BooksScreen(onAddBusiness: () => startAddBusiness(context)),
  ),
  GoRoute(
    path: BooksPaths.addBusiness,
    builder: (context, state) => BusinessNameScreen(
      startDate: bookStartDateOf(context),
      initial: addBusinessFlow.business,
      onSubmit: (draft) {
        addBusinessFlow.setBusiness(draft);
        context.push(
          draft.ownership == BusinessOwnershipChoice.shared
              ? BooksPaths.addBusinessOwners
              : BooksPaths.addBusinessOpening,
        );
      },
    ),
  ),
  GoRoute(
    path: BooksPaths.addBusinessOwners,
    builder: (context, state) => BusinessOwnersScreen(
      yourName: addBusinessFlow.yourName,
      initialOwners: addBusinessFlow.owners.isEmpty
          ? null
          : addBusinessFlow.owners,
      onSubmit: (owners) {
        addBusinessFlow.setOwners(owners);
        context.push(BooksPaths.addBusinessOpening);
      },
      // ADR 2026-09-09 §3: not a skip — back to S0.6a on the *Just me*
      // branch, with the answers already given kept.
      onJustMeAfterAll: () {
        final draft = addBusinessFlow.business;
        if (draft != null) {
          addBusinessFlow.setBusiness(
            BusinessDraft(
              name: draft.name,
              ownership: BusinessOwnershipChoice.justMe,
              fyStartMonth: draft.fyStartMonth,
            ),
          );
        }
        context.go(BooksPaths.addBusiness);
      },
    ),
  ),
  GoRoute(
    path: BooksPaths.addBusinessOpening,
    builder: (context, state) => BusinessOpeningHost(
      flow: addBusinessFlow,
      startDate: bookStartDateOf(context),
      // Saved or skipped, S9.5 lands back on S9 — where the new book is now
      // in the list (07 §1: no dead ends). `go`, not `pop`: the chain behind
      // is finished and must not be walked back into a second creation.
      onDone: () => context.go(BooksPaths.root),
    ),
  ),
];

/// Opens S9.5 from S9 (07 §5.7 🔒). Steps the flow's cursor past every
/// business already collected first, so this pass names a *new* business.
void startAddBusiness(BuildContext context) {
  addBusinessFlow.addAnotherBusiness();
  context.push(BooksPaths.addBusiness);
}
