// Paths owned by this feature (features/README "Routes"). S8.1 sits one
// level below S8 Menu (13 §3.2 depth rule) and is not a root-navigator
// route: it nests inside the Menu tab's [RkTabRoot.routes] (features/menu
// composes this feature's routes), so the segment here is *relative* — a
// bare path segment, never a leading slash.
abstract final class ReportsPaths {
  /// S8.1 Reports list — relative segment under the Menu tab root.
  static const root = 'reports';
}
