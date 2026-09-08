// Onboarding feature routes (features/README, router.dart contract). Mounted
// on the root navigator via `featureRoutes` — these three screens (splash,
// language, welcome) run before the tab shell exists, same posture as
// features/auth's S0.2 (07 §5 flow F1: splash → language → welcome → S0.2).
import 'package:go_router/go_router.dart';

import '../auth/auth_paths.dart';
import 'onboarding_paths.dart';
import 'screens/s0_0_splash_screen.dart';
import 'screens/s0_05_welcome_screen.dart';
import 'screens/s0_1_language_screen.dart';

export 'onboarding_paths.dart';

/// S0.0 at [OnboardingPaths.splash]; S0.1 at [OnboardingPaths.language]; S0.05
/// at [OnboardingPaths.welcome]. The splash's `onFinished` and the language
/// screen's `onSelected` both push forward; welcome's `onDone` hands off to
/// auth's S0.2 ([AuthPaths.phoneOtp], features/auth), wired by main.dart.
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
];
