// Onboarding feature routes (features/README, router.dart contract). Mounted
// on the root navigator via `featureRoutes` — these screens run before the
// tab shell exists, same posture as features/auth's S0.2 (07 §5 flow F1:
// splash → language → welcome → S0.2 → S0.3 purpose → S0.4 name → S0.8 PIN).
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../shared/app_scope.dart';

import '../auth/auth_paths.dart';
import 'onboarding_paths.dart';
import 'screens/s0_0_splash_screen.dart';
import 'screens/s0_05_welcome_screen.dart';
import 'screens/s0_1_language_screen.dart';
import 'screens/s0_3_purpose_screen.dart';
import 'screens/s0_4_name_photo_screen.dart';
import 'screens/s0_6a1_business_owners_screen.dart';
import 'screens/s0_6a_business_name_screen.dart';
import 'screens/s0_6b_business_opening_balances_screen.dart';

export 'onboarding_paths.dart';
export 'screens/s0_3_purpose_screen.dart' show OnboardingPurpose;
export 'screens/s0_6a1_business_owners_screen.dart'
    show BusinessOwnersScreen, OwnerDraft, ShareMode;
export 'screens/s0_6a_business_name_screen.dart'
    show BusinessDraft, BusinessNameScreen, BusinessOwnershipChoice;
export 'screens/s0_6b_business_opening_balances_screen.dart'
    show BusinessOpeningBalancesScreen, OpeningGroup, OpeningRow;

/// S0.0 at [OnboardingPaths.splash]; S0.1 at [OnboardingPaths.language]; S0.05
/// at [OnboardingPaths.welcome]; S0.3 at [OnboardingPaths.purpose]; S0.4 at
/// [OnboardingPaths.namePhoto]. The splash's `onFinished`, the language
/// screen's `onSelected` and S0.3's `onSelected` all push forward; welcome's
/// `onDone` hands off to auth's S0.2 ([AuthPaths.phoneOtp], features/auth),
/// wired by main.dart.
///
/// ⚠️ SPEC: S0.4's Continue has nowhere to hand off to yet — 07 §3.1 step 5
/// (`S0.8` set PIN, 13 §3.2's flow) has no screen in this build. `onSubmit`
/// is left unwired here rather than invented; see the lane report's open
/// items. The chosen [OnboardingPurpose] (S0.3) is likewise not yet carried
/// past S0.4 — the O6* branch wizard that reads it (07 §3.1.1) is a later
/// lane's job, out of scope for U1b.
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
      onSelected: (purpose) => context.go(OnboardingPaths.namePhoto),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.namePhoto,
    builder: (context, state) => const NamePhotoScreen(),
  ),
  // The business branch (07 §3.1.1 O6a → O6b). S0.6a's ownership answer is
  // what forks it: *Shared with others* goes through S0.6a1 first (ADR
  // 2026-09-09 §1), *Just me* straight to S0.6b. ⚠️ SPEC: the book is not
  // created here — `createBook` needs the S0.6a1 owners, and the checklist
  // step that commits the branch (07 §3.1 step 8, S0.7) has no screen in this
  // build; the routes carry the drafts through `extra` and the committing
  // caller is wired by a later lane. See the lane report's open items.
  GoRoute(
    path: OnboardingPaths.business,
    builder: (context, state) => BusinessNameScreen(
      startDate: bookStartDateOf(context),
      initial: state.extra is BusinessDraft
          ? state.extra! as BusinessDraft
          : null,
      onSubmit: (draft) => context.go(
        draft.ownership == BusinessOwnershipChoice.shared
            ? OnboardingPaths.businessOwners
            : OnboardingPaths.businessOpening,
        extra: draft,
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.businessOwners,
    builder: (context, state) => BusinessOwnersScreen(
      yourName: '',
      onSubmit: (owners) =>
          context.go(OnboardingPaths.businessOpening, extra: owners),
      // ADR 2026-09-09 §3: not a skip — back to S0.6a on the *Just me* branch.
      onJustMeAfterAll: () => context.go(
        OnboardingPaths.business,
        extra: state.extra is BusinessDraft
            ? BusinessDraft(
                name: (state.extra! as BusinessDraft).name,
                ownership: BusinessOwnershipChoice.justMe,
                fyStartMonth: (state.extra! as BusinessDraft).fyStartMonth,
              )
            : null,
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.businessOpening,
    builder: (context, state) => BusinessOpeningBalancesScreen(
      rows: const [],
      startDate: bookStartDateOf(context),
    ),
  ),
];

/// The day a book created now would begin (ADR 2026-09-09d §4) — read from the
/// app's injected clock, never `DateTime.now()`.
LocalDate bookStartDateOf(BuildContext context) {
  final now = RkScope.of(context).now();
  return LocalDate(now.year, now.month, now.day);
}
