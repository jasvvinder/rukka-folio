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

  /// S0.3 Purpose — five-card branch, after S0.2 phone+OTP (07 §3.1 step 3,
  /// 13 §3.2). Owned here (not aliased off `RkPaths`, same posture as the
  /// three paths above) because S0.2 lives in features/auth and this lane
  /// does not touch router.dart.
  static const purpose = '/onboarding/purpose';

  /// S0.4 Name & photo — after S0.3 (07 §3.1 step 4, 13 §3.2).
  static const namePhoto = '/onboarding/name-photo';

  /// S0.6a Name the business — the O6a branch step (07 §3.1.1, 13 §3.2).
  static const business = '/onboarding/business';

  /// S0.6a1 Who owns this business? — the *Shared with others* branch only
  /// (ADR 2026-09-09 §1); a *Just me* business never reaches this path.
  static const businessOwners = '/onboarding/business/owners';

  /// S0.6b The business's opening balances — one grouped review-and-fill
  /// screen over the seeded accounts (ADR 2026-09-09c §3).
  static const businessOpening = '/onboarding/business/opening';
}
