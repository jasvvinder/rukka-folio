// Onboarding feature routes (features/README, router.dart contract). Mounted
// on the root navigator via `featureRoutes` — these screens run before the
// tab shell exists, same posture as features/auth's S0.2 (07 §5 flow F1:
// splash → language → welcome → S0.2 → S0.3 purpose → S0.4 name → S0.8 PIN).
import 'package:go_router/go_router.dart';

import '../auth/auth_paths.dart';
import 'onboarding_paths.dart';
import 'screens/s0_0_splash_screen.dart';
import 'screens/s0_05_welcome_screen.dart';
import 'screens/s0_1_language_screen.dart';
import 'screens/s0_3_purpose_screen.dart';
import 'screens/s0_4_name_photo_screen.dart';

export 'onboarding_paths.dart';
export 'screens/s0_3_purpose_screen.dart' show OnboardingPurpose;

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
];
