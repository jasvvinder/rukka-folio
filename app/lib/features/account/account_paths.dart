// Paths of the account feature (features/README: never re-type a path).
// S16 is a root-navigator screen reached from Menu (S8, 13 §3.2 row S16).
//
// Aliases of `RkPaths` — the single declaration lives in `shared/router.dart`
// (the `RecoveryPaths` convention). The four carried literals while the
// router belonged to the shell; the orchestrator hoisted them when it wired
// the routes and the S8 row.
import '../../shared/router.dart';

abstract final class AccountPaths {
  /// S16 My account.
  static const root = RkPaths.account;

  /// S16.1 Edit profile (name and photo only — 13 §3.2 row S16.1).
  static const editProfile = RkPaths.accountEditProfile;

  /// S16.3 Delete account (06 §9.3 🔒).
  static const delete = RkPaths.accountDelete;

  /// S16.2 Change phone number (06 §9.4 🔒) — OTP on the old number **and**
  /// the new one, or, when the old number is lost, a k-of-n ask of the user's
  /// trusted members. Mounted by [accountRoutes] as of M11/A2; S16 draws its
  /// phone row as a live door now that it is, and disabled-with-reason when
  /// no destination is supplied.
  static const changePhone = RkPaths.accountChangePhone;
}
