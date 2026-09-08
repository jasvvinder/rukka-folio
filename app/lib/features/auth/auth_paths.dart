// Paths of this feature — aliases of `RkPaths` (features/README: never re-type
// a path). Kept so screens and tests read `AuthPaths.phoneOtp` at the call site.
import '../../shared/router.dart';

abstract final class AuthPaths {
  /// S0.2 Phone + OTP (13 §3.2, onboarding).
  static const phoneOtp = RkPaths.authPhone;

  /// S19.1 Update required (426 — 06 §4.5). Global, no dismiss.
  static const updateRequired = RkPaths.updateRequired;
}
