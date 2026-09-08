// Paths of this feature (features/README: never re-type a path elsewhere).
// These three screens sit before auth, so — unlike auth/devices — there is
// no existing `RkPaths` entry to alias; router.dart is frozen for this lane,
// so the paths live here and the orchestrator mounts [onboardingRoutes] on
// the root navigator (features/onboarding_routes.dart).
abstract final class OnboardingPaths {
  /// S0.0 Splash — launch, mark animation only (13 §3.2, ADR 2026-09-03d).
  static const splash = '/onboarding/splash';

  /// S0.1 Language picker — first screen ever shown after splash (07 §3.1 step 1).
  static const language = '/onboarding/language';

  /// S0.05 Welcome — 3 skippable slides, after language (13 §3.2).
  static const welcome = '/onboarding/welcome';
}
