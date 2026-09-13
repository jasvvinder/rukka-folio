// Paths owned by the Inbox feature (features/README "Routes"). S6 is the
// Inbox tab root (`/inbox`, from [RkPaths]); S6.2 is a full-screen detail
// stepper, so it mounts on the ROOT navigator and covers the tab bar — the
// same treatment S4/S4.1 get, and what 07 §9 asks for ("each entry
// full-screen"). It is one level below the tab root, inside the 13 §3.1
// depth rule.
import '../../shared/router.dart';

abstract final class InboxPaths {
  /// S6.2 review stepper — a root-navigator route, so the path is absolute.
  static const stepper = '${RkPaths.inbox}/review/:groupId';

  /// The location to push for [groupId].
  static String stepperFor(String groupId) =>
      '${RkPaths.inbox}/review/$groupId';
}
