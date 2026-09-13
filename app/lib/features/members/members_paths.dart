// Paths of this feature. S9 is reached from Menu (S8, 13 §3.2); S9.1 nests
// under it.
//
// Wired 13 Sep 2026: the strings now live in `RkPaths` (features/README
// "Routes") and these two are aliases of them, exactly as `DevicesPaths` is.
import '../../shared/router.dart';

abstract final class MembersPaths {
  /// S9 Members.
  static const members = RkPaths.members;

  /// S9.1 Invite member.
  static const invite = RkPaths.membersInvite;
}
