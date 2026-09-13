// Paths of the ceremony feature (S9.2–S9.4, 13 §3.2).
//
// Wired 13 Sep 2026: features/README says paths come from `RkPaths`, and these
// three now do — the constants below are aliases.
import '../../shared/router.dart';

abstract final class CeremonyPaths {
  /// S9.2 Show my code — the invitee's side (04 §6.2).
  static const showMyCode = RkPaths.ceremonyShowMyCode;

  /// S9.3 Verify member — the verifier's side; `:invite` is the invite id.
  static const verifyMember = RkPaths.ceremonyVerifyMember;

  /// S9.3 for one invite.
  static String verifyMemberFor(String inviteId) =>
      '/ceremony/verify/$inviteId';

  /// S9.4 Verification mismatch — hard fail, no override (04 §6.3 🔒).
  static const mismatch = RkPaths.ceremonyMismatch;
}
