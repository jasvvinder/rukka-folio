// Where a cold-started chain picks up a branch whose book was already made
// (review finding SETUP174-1).
//
// ADR 2026-10-07 ruling 3 keeps S0.3's purpose on the device, so S0.5 / S0.5b
// restore it and re-enter the branch. The branch's book ids, though, live on
// the in-memory [OnboardingFlow]; re-entering at the naming step (S0.6a /
// S0.6d / S0.6g) after S0.6b / S0.6f / S0.6i had already run `createBook`
// would ask the name again and make a second book. ADR 2026-10-06b ruling 2 🔒
// resumes at **the first step not yet completed**, and 07 §3.1.1 says a branch
// step is resumable and never duplicated — so the committing steps record
// each book they make ([SetupProgress.recordBranchBook]) and this puts them
// back:
//
// - the book's openings not saved yet → its committing step, over that book
//   (S0.6b / S0.6f / S0.6i: `flow.<x>BookId ?? createBook` then makes
//   nothing);
// - saved ([OpeningSetupRecord], kept on the device) → the step after it:
//   S0.6c for a business (its recap rebuilt from the books), S0.6 for a
//   family or trust.
//
// The steps before the committing step (S0.6a1 owners, S0.6e / S0.6h
// invites) were answered before the book existed and are fixed into it
// (ADR 2026-09-09 §2), so they are not asked again. A recorded book the
// ledger no longer holds is ignored — the chain then asks the name, which is
// the behaviour before this file.
import '../../shared/ledger/local_ledger.dart';
import '../../shared/prefs.dart';
import 'onboarding_flow.dart';
import 'onboarding_paths.dart';
import 'opening_setup_record.dart';
import 'screens/s0_3_purpose_screen.dart' show OnboardingPurpose;
import 'screens/s0_6a_business_name_screen.dart';
import 'setup_progress.dart';

/// Restores onto [flow] the branch books a cold start lost and returns the
/// step to resume at; null when there is nothing to restore (no branch book
/// made yet, or this process already holds it) — the caller then takes
/// `afterSetPin` as before.
Future<String?> resumeBranchBooks(
  OnboardingFlow flow,
  RkPrefs? prefs,
  LocalLedger ledger,
) async {
  final purpose = flow.purpose;
  if (purpose == null || purpose == OnboardingPurpose.myself) return null;
  final alreadyHeld = switch (purpose) {
    OnboardingPurpose.businesses => flow.businesses.isNotEmpty,
    OnboardingPurpose.family => flow.familyBookId != null,
    OnboardingPurpose.trust => flow.trustBookId != null,
    OnboardingPurpose.myself => true,
  };
  if (alreadyHeld) return null;
  final recorded = [
    for (final b in await SetupProgress.branchBooks(prefs))
      if (b.purpose == purpose) b,
  ];
  if (recorded.isEmpty) return null;
  final books = {
    for (final b in await ledger.db.select(ledger.db.booksP).get()) b.id: b,
  };
  final live = [
    for (final r in recorded)
      if (books.containsKey(r.bookId)) r,
  ];
  if (live.isEmpty) return null;

  switch (purpose) {
    case OnboardingPurpose.businesses:
      final entries = <BusinessEntry>[
        for (final r in live)
          BusinessEntry(
            draft: BusinessDraft(
              name: books[r.bookId]!.name,
              ownership: r.shared
                  ? BusinessOwnershipChoice.shared
                  : BusinessOwnershipChoice.justMe,
              fyStartMonth: books[r.bookId]!.fyStartMonth,
            ),
            bookId: r.bookId,
            openingPosted: await OpeningSetupRecord.isFinished(prefs, r.bookId),
          ),
      ];
      flow.restoreBusinesses(entries);
      return entries.last.openingPosted
          ? OnboardingPaths.businessAnother
          : OnboardingPaths.businessOpening;
    case OnboardingPurpose.family:
      final id = live.last.bookId;
      flow.familyBookId = id; // clears familyOpeningPosted; set it after
      flow.familyOpeningPosted = await OpeningSetupRecord.isFinished(prefs, id);
      return flow.familyOpeningPosted
          ? OnboardingPaths.openingBalances
          : OnboardingPaths.familyAccounts;
    case OnboardingPurpose.trust:
      final id = live.last.bookId;
      flow.trustBookId = id; // clears trustOpeningPosted; set it after
      flow.trustOpeningPosted = await OpeningSetupRecord.isFinished(prefs, id);
      return flow.trustOpeningPosted
          ? OnboardingPaths.openingBalances
          : OnboardingPaths.trustAccounts;
    case OnboardingPurpose.myself:
      return null;
  }
}
