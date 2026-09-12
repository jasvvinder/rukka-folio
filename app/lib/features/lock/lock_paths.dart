// Paths of the lock family (features/README: never re-type a path elsewhere).
// The lock sits outside the tab shell — it covers everything — so these mount
// on the root navigator, like onboarding's pre-auth steps.
abstract final class LockPaths {
  /// S15 App lock / S15.3 cooldown and disabled — one route, several states
  /// (ADR 2026-09-05f §B, 13 §4.3).
  static const lock = '/lock';
}
