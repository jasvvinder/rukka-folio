// Paths of the ceremony feature (S9.2–S9.4, 13 §3.2).
//
// Wired 13 Sep 2026: features/README says paths come from `RkPaths`, and these
// three now do — the constants below are aliases.
import '../../shared/router.dart';

abstract final class CeremonyPaths {
  /// S9.2 Show my code — the invitee's side (04 §6.2).
  static const showMyCode = RkPaths.ceremonyShowMyCode;

  /// S9.3 Verify member. The one path parameter carries the **subject's user
  /// id** — see [subjectParameter].
  static const verifyMember = RkPaths.ceremonyVerifyMember;

  /// The name `shared/router.dart` gives S9.3's path parameter.
  ///
  /// ⚠️ SPEC — it is spelled `invite`, from the days when the ceremony was
  /// read as the member-invite flow alone. A ceremony session is keyed by
  /// `subject_user` (migration 0007 🔒), and 04 §6 says "one component, four
  /// uses": guardian activation, device linking and trustee handover all run
  /// the same ceremony between two **active** members, with no invite in
  /// sight. So the value carried is a user id and the segment's name is
  /// stale. Renaming it touches `shared/router.dart`, which this feature does
  /// not own; the constant keeps callers from spelling the old name by hand.
  static const subjectParameter = 'invite';

  /// S9.3 for one subject — [subjectUserId] is the user id of the person
  /// being verified, never an invite id (see [subjectParameter]).
  static String verifyMemberFor(String subjectUserId) =>
      '/ceremony/verify/$subjectUserId';

  /// S9.4 Verification mismatch — hard fail, no override (04 §6.3 🔒).
  static const mismatch = RkPaths.ceremonyMismatch;
}
