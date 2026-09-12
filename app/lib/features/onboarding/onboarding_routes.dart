// Onboarding feature routes (features/README, router.dart contract). Mounted
// on the root navigator via `featureRoutes` — these screens run before the
// tab shell exists, same posture as features/auth's S0.2 (07 §5 flow F1:
// splash → language → welcome → S0.2 → S0.3 purpose → S0.4 name → S0.8 PIN).
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../shared/app_scope.dart';

import '../auth/auth_paths.dart';
import '../home/home_paths.dart';
import 'onboarding_flow.dart';
import 'onboarding_paths.dart';
import 'screens/s0_0_splash_screen.dart';
import 'screens/s0_05_welcome_screen.dart';
import 'screens/s0_1_language_screen.dart';
import 'screens/s0_3_purpose_screen.dart';
import 'screens/s0_4_name_photo_screen.dart';
import 'screens/s0_5_books_safe_screen.dart';
import 'screens/s0_5b_recovery_sheet_screen.dart';
import 'screens/s0_6a1_business_owners_screen.dart';
import 'screens/s0_6a_business_name_screen.dart';
import 'screens/s0_6d_family_name_screen.dart';
import 'screens/s0_6e_family_members_screen.dart';
import 'screens/s0_6g_trust_name_screen.dart';
import 'screens/s0_6h_trust_members_screen.dart';
import 'screens/s0_8_set_pin_screen.dart';
import 'widgets/business_opening_host.dart';
import 'widgets/family_opening_host.dart';
import 'widgets/trust_opening_host.dart';

export 'onboarding_flow.dart' show OnboardingFlow, OnboardingFlowScope;
export 'onboarding_paths.dart';
export 'screens/s0_3_purpose_screen.dart' show OnboardingPurpose;
export 'screens/s0_6a1_business_owners_screen.dart'
    show BusinessOwnersScreen, OwnerDraft, ShareMode;
export 'screens/s0_6a_business_name_screen.dart'
    show BusinessDraft, BusinessNameScreen, BusinessOwnershipChoice;
export 'screens/s0_5_books_safe_screen.dart'
    show BooksSafeScreen, KeySyncAvailability;
export 'screens/s0_5b_recovery_sheet_screen.dart'
    show RecoverySheetScreen, RecoverySheetStep;
export 'screens/s0_8_set_pin_screen.dart' show SetPinScreen, SetPinStep;
export 'screens/s0_6b_business_opening_balances_screen.dart'
    show BusinessOpeningBalancesScreen, OpeningGroup, OpeningRow;
export 'screens/s0_6d_family_name_screen.dart'
    show FamilyDraft, FamilyNameScreen;
export 'screens/s0_6e_family_members_screen.dart'
    show FamilyMemberDraft, FamilyMembersScreen;
export 'screens/s0_6f_family_accounts_screen.dart'
    show FamilySharedAccountsScreen;
export 'screens/s0_6g_trust_name_screen.dart' show TrustDraft, TrustNameScreen;
export 'screens/s0_6h_trust_members_screen.dart'
    show TrustMemberDraft, TrustMembersScreen, TrustRole;
export 'screens/s0_6i_trust_accounts_screen.dart' show TrustAccountsScreen;
export 'widgets/business_opening_host.dart' show BusinessOpeningHost;
export 'widgets/family_opening_host.dart' show FamilyOpeningHost;
export 'widgets/trust_opening_host.dart' show TrustOpeningHost;

/// S0.0 at [OnboardingPaths.splash]; S0.1 at [OnboardingPaths.language]; S0.05
/// at [OnboardingPaths.welcome]; S0.3 at [OnboardingPaths.purpose]; S0.4 at
/// [OnboardingPaths.namePhoto]. The splash's `onFinished`, the language
/// screen's `onSelected` and S0.3's `onSelected` all push forward; welcome's
/// `onDone` hands off to auth's S0.2 ([AuthPaths.phoneOtp], features/auth),
/// wired by main.dart.
///
/// The answers are carried between steps by [onboardingFlow] — S0.4's name is
/// needed again as the first owner row on S0.6a1 (ADR 2026-09-09 §1) and the
/// S0.6a / S0.6a1 answers are needed together at the committing step, where
/// `createBook` runs ([BusinessOpeningHost]).
///
/// S0.4's Continue records the name and goes to **S0.8 set PIN** (13 §5
/// flow F1). S0.8's Continue now goes to **S0.5 keeping your books safe** and on to
/// **S0.5b the recovery sheet** (07 §3.1 steps 5–6, 13's onboarding flow
/// line), and only then takes the branch the purpose card chose. Both steps
/// are skippable and resumable (07 §3.1.1): S0.5's skip and S0.5b's skip land
/// on the same branch step Continue would, and the verified-storage nag
/// (04 §7.4 🔒) is what brings the sheet back.
///
/// The chosen [OnboardingPurpose] is recorded on the flow: the business
/// branch (O6a/O6a1/O6b), the family branch (O6d/O6e/O6f) and the trust
/// branch (O6g/O6h/O6i) all have screens now (U1e, M5).
final OnboardingFlow onboardingFlow = OnboardingFlow();

final List<RouteBase> onboardingRoutes = [
  GoRoute(
    path: OnboardingPaths.splash,
    builder: (context, state) =>
        SplashScreen(onFinished: () => context.go(OnboardingPaths.language)),
  ),
  GoRoute(
    path: OnboardingPaths.language,
    builder: (context, state) => LanguagePickerScreen(
      onSelected: (locale) => context.go(OnboardingPaths.welcome),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.welcome,
    builder: (context, state) =>
        WelcomeScreen(onDone: () => context.go(AuthPaths.phoneOtp)),
  ),
  GoRoute(
    path: OnboardingPaths.purpose,
    builder: (context, state) => PurposeScreen(
      onSelected: (purpose) {
        onboardingFlow.setPurpose(purpose);
        context.go(OnboardingPaths.namePhoto);
      },
    ),
  ),
  GoRoute(
    path: OnboardingPaths.namePhoto,
    builder: (context, state) => NamePhotoScreen(
      initialName: onboardingFlow.yourName,
      // 07 §3.1 step 4's answer is carried forward, not dropped: S0.6a1 tags
      // the first owner row with it (ADR 2026-09-09 §1).
      onSubmit: (name, photo) {
        onboardingFlow.setYourName(name);
        context.go(OnboardingPaths.setPin);
      },
    ),
  ),
  GoRoute(
    path: OnboardingPaths.setPin,
    builder: (context, state) =>
        SetPinScreen(onDone: () => context.go(OnboardingPaths.booksSafe)),
  ),
  // 07 §3.1 step 5 🔒 — backup is configured here, at signup. Continue and
  // the sheet action both lead to S0.5b; the skip (shown when key sync is
  // unavailable, where the sheet is the primary action) goes to the branch.
  //
  // ⚠️ SPEC: whether iCloud Keychain / Block Store is available is a platform
  // question no seam answers in this build, so no `keySyncAvailable` callback
  // is wired here and the screen takes 04 §7.0's default (on). Same for the
  // destination: naming the wrong cloud would be worse than the generic line.
  GoRoute(
    path: OnboardingPaths.booksSafe,
    builder: (context, state) => BooksSafeScreen(
      onContinue: () => context.go(OnboardingPaths.recoverySheet),
      onSheet: () => context.go(OnboardingPaths.recoverySheet),
      onSkip: () => context.go(afterSetPin(onboardingFlow)),
    ),
  ),
  // 07 §3.1 step 6 / 04 §7.4 🔒. Generation, print/save and the scan-back
  // check are seams with no implementation in this build, so none is wired:
  // the screen shows its intro with the actions disabled rather than
  // pretending a sheet was made. The lane report names the wanted interface.
  GoRoute(
    path: OnboardingPaths.recoverySheet,
    builder: (context, state) => RecoverySheetScreen(
      onVerifiedChanged: onboardingFlow.setRecoverySheetVerified,
      onDone: () => context.go(afterSetPin(onboardingFlow)),
      onSkip: () => context.go(afterSetPin(onboardingFlow)),
    ),
  ),
  // The business branch (07 §3.1.1 O6a → O6b). S0.6a's ownership answer is
  // what forks it: *Shared with others* goes through S0.6a1 first (ADR
  // 2026-09-09 §1), *Just me* straight to S0.6b. The answers live on
  // [onboardingFlow] rather than in `extra`, because the committing step
  // needs S0.6a *and* S0.6a1 together and a resumed step (07 §3.1.1) must not
  // create a second book.
  //
  // ⚠️ SPEC: the S0.6a1 **share weights** are collected and shown but have
  // nowhere to persist — `BookConfig` (packages/data) carries `ownership` but
  // no partner ratio, and `PartnerShare` takes its weight per call at
  // distribution time. They stay on [onboardingFlow] for this build; giving
  // them a home is a `packages/data` change and is in the lane report.
  GoRoute(
    path: OnboardingPaths.business,
    builder: (context, state) => BusinessNameScreen(
      startDate: bookStartDateOf(context),
      initial: onboardingFlow.business,
      onSubmit: (draft) {
        onboardingFlow.setBusiness(draft);
        context.go(
          draft.ownership == BusinessOwnershipChoice.shared
              ? OnboardingPaths.businessOwners
              : OnboardingPaths.businessOpening,
        );
      },
    ),
  ),
  GoRoute(
    path: OnboardingPaths.businessOwners,
    builder: (context, state) => BusinessOwnersScreen(
      yourName: onboardingFlow.yourName,
      initialOwners: onboardingFlow.owners.isEmpty
          ? null
          : onboardingFlow.owners,
      onSubmit: (owners) {
        onboardingFlow.setOwners(owners);
        context.go(OnboardingPaths.businessOpening);
      },
      // ADR 2026-09-09 §3: not a skip — back to S0.6a on the *Just me* branch.
      onJustMeAfterAll: () {
        final draft = onboardingFlow.business;
        if (draft != null) {
          onboardingFlow.setBusiness(
            BusinessDraft(
              name: draft.name,
              ownership: BusinessOwnershipChoice.justMe,
              fyStartMonth: draft.fyStartMonth,
            ),
          );
        }
        context.go(OnboardingPaths.business);
      },
    ),
  ),
  GoRoute(
    path: OnboardingPaths.businessOpening,
    builder: (context, state) => BusinessOpeningHost(
      flow: onboardingFlow,
      startDate: bookStartDateOf(context),
      // Skipped or saved, the next stop is Home — where the S0.7 checklist
      // brings a skipped wizard back (07 §3.1 step 7).
      onDone: () => context.go(HomePaths.home),
    ),
  ),
  // The family branch (07 §3.1.1 O6d → O6e → O6f). Every step is skippable
  // and resumable; S0.6e's *Skip for now* is always visible (🔒) and simply
  // carries an empty (or partial) member list forward rather than blocking.
  GoRoute(
    path: OnboardingPaths.family,
    builder: (context, state) => FamilyNameScreen(
      startDate: bookStartDateOf(context),
      initial: onboardingFlow.family,
      onSubmit: (draft) {
        onboardingFlow.setFamily(draft);
        context.go(OnboardingPaths.familyMembers);
      },
    ),
  ),
  GoRoute(
    path: OnboardingPaths.familyMembers,
    builder: (context, state) => FamilyMembersScreen(
      yourName: onboardingFlow.yourName,
      initialMembers: onboardingFlow.familyMembers.isEmpty
          ? null
          : onboardingFlow.familyMembers,
      onSubmit: (members) {
        onboardingFlow.setFamilyMembers(members);
        context.go(OnboardingPaths.familyAccounts);
      },
      onSkip: () => context.go(OnboardingPaths.familyAccounts),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.familyAccounts,
    builder: (context, state) => FamilyOpeningHost(
      flow: onboardingFlow,
      startDate: bookStartDateOf(context),
      // Skipped or saved, the next stop is Home — where the S0.7 checklist
      // brings a skipped wizard back (07 §3.1 step 7).
      onDone: () => context.go(HomePaths.home),
    ),
  ),
  // The trust branch (07 §3.1.1 O6g → O6h → O6i). Every step is skippable
  // and resumable; S0.6h's *Skip for now* is always visible (🔒) and simply
  // carries an empty (or partial) committee list forward rather than
  // blocking — the same shape as the family branch's S0.6e.
  GoRoute(
    path: OnboardingPaths.trust,
    builder: (context, state) => TrustNameScreen(
      startDate: bookStartDateOf(context),
      initial: onboardingFlow.trust,
      onSubmit: (draft) {
        onboardingFlow.setTrust(draft);
        context.go(OnboardingPaths.trustMembers);
      },
    ),
  ),
  GoRoute(
    path: OnboardingPaths.trustMembers,
    builder: (context, state) => TrustMembersScreen(
      yourName: onboardingFlow.yourName,
      initialMembers: onboardingFlow.trustMembers.isEmpty
          ? null
          : onboardingFlow.trustMembers,
      onSubmit: (members) {
        onboardingFlow.setTrustMembers(members);
        context.go(OnboardingPaths.trustAccounts);
      },
      onSkip: () => context.go(OnboardingPaths.trustAccounts),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.trustAccounts,
    builder: (context, state) => TrustOpeningHost(
      flow: onboardingFlow,
      startDate: bookStartDateOf(context),
      // Skipped or saved, the next stop is Home — where the S0.7 checklist
      // brings a skipped wizard back (07 §3.1 step 7).
      onDone: () => context.go(HomePaths.home),
    ),
  ),
];

/// The day a book created now would begin (ADR 2026-09-09d §4) — read from the
/// app's injected clock, never `DateTime.now()`.
LocalDate bookStartDateOf(BuildContext context) {
  final now = RkScope.of(context).now();
  return LocalDate(now.year, now.month, now.day);
}

/// Where S0.8 goes next: the branch step the purpose card chose (07 §3.1.1).
/// Every branch but *Myself* now has screens; *Myself* lands on Home, whose
/// S0.7 checklist brings the skipped opening-balances step back (07 §3.1
/// step 7 — that step is O6, not built by this lane).
String afterSetPin(OnboardingFlow flow) => switch (flow.purpose) {
  OnboardingPurpose.shop ||
  OnboardingPurpose.businesses => OnboardingPaths.business,
  OnboardingPurpose.family => OnboardingPaths.family,
  OnboardingPurpose.trust => OnboardingPaths.trust,
  _ => HomePaths.home,
};
