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

  /// S0.8 Set your PIN — after S0.4 (07 §3.1's chain via 13 §5 flow F1,
  /// 06 §4.4 🔒 six digits). Also the landing after a forgot-PIN
  /// reverification (07 §5.6: OTP + biometric, then set a new one).
  static const setPin = '/onboarding/set-pin';

  /// S0.5 Keeping your books safe — after S0.8, before the branch step
  /// (07 §3.1 step 5 🔒, 13 §3.2 row S0.5, 13's onboarding flow line).
  static const booksSafe = '/onboarding/books-safe';

  /// S0.5b Recovery sheet — after S0.5 (07 §3.1 step 6, 04 §7.4 🔒,
  /// 13 §3.2 row S0.5b).
  static const recoverySheet = '/onboarding/recovery-sheet';

  /// S0.6a Name the business — the O6a branch step (07 §3.1.1, 13 §3.2).
  static const business = '/onboarding/business';

  /// S0.6a1 Who owns this business? — the *Shared with others* branch only
  /// (ADR 2026-09-09 §1); a *Just me* business never reaches this path.
  static const businessOwners = '/onboarding/business/owners';

  /// S0.6b The business's opening balances — one grouped review-and-fill
  /// screen over the seeded accounts (ADR 2026-09-09c §3).
  static const businessOpening = '/onboarding/business/opening';

  /// S0.6d Name the family — the O6d branch step (07 §3.1.1, 13 §3.2).
  static const family = '/onboarding/family';

  /// S0.6e Who else is in the family — invite heads by phone, Skip for now
  /// always visible (07 §3.1.1, 13 §3.2).
  static const familyMembers = '/onboarding/family/members';

  /// S0.6f The family's shared accounts — one grouped review-and-fill screen
  /// over the pool's seeded chart (07 §3.1.1, ADR 2026-09-09c §3).
  static const familyAccounts = '/onboarding/family/accounts';

  /// S0.6g Name the trust and its type — the O6g branch step (07 §3.1.1,
  /// 13 §3.2).
  static const trust = '/onboarding/trust';

  /// S0.6h Who runs the trust — invite the committee by phone, Skip for now
  /// always visible (07 §3.1.1, 13 §3.2).
  static const trustMembers = '/onboarding/trust/members';

  /// S0.6i The trust's accounts — one grouped review-and-fill screen over the
  /// trust's seeded chart (07 §3.1.1, ADR 2026-09-09c §3, ADR 2026-09-09d §2).
  static const trustAccounts = '/onboarding/trust/accounts';
}
