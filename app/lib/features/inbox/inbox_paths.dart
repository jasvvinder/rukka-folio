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

  /// S6.3 structural review surface — a root-navigator route for the same
  /// reason S6.2 is one: it is the full statement of one request, and the
  /// owner decides on it without the tab bar competing for the thumb.
  static const structural = '${RkPaths.inbox}/structural/:requestId';

  /// The location to push for [requestId].
  static String structuralFor(String requestId) =>
      '${RkPaths.inbox}/structural/$requestId';

  /// S10.3 Late Arrivals tray — a root-navigator route for the same reason
  /// S6.2 and S6.3 are: it is a closer's decision surface, and the actions on
  /// it (re-date, re-open) deserve the thumb without the tab bar competing.
  /// One level below the tab root, inside the 13 §3.1 depth rule.
  static const lateArrivals = '${RkPaths.inbox}/late';
}
