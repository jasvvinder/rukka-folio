// Paths owned by this feature (features/README "Routes"). S8.1 sits one
// level below S8 Menu (13 §3.2 depth rule) and is not a root-navigator
// route: it nests inside the Menu tab's [RkTabRoot.routes] (features/menu
// composes this feature's routes), so the segment here is *relative* — a
// bare path segment, never a leading slash. The absolute spellings a caller
// pushes are offered beside them.
import '../../shared/router.dart';

abstract final class ReportsPaths {
  /// S8.1 Reports list — relative segment under the Menu tab root.
  static const root = 'reports';

  /// S8.2 Report viewer + export — relative segment under [root], so the
  /// location is `/menu/reports/day-book`.
  ///
  /// ⚠️ SPEC: 13 §3.2's depth rule would put a *detail viewer* like S8.2 on
  /// the root navigator, covering the tab bar (S4/S4.1 do). Mounting it there
  /// means adding it to `main.dart`'s `featureRoutes`, or reaching the root
  /// navigator key `shared/router.dart` keeps private — neither of which is
  /// this lane's to change. It therefore nests under S8.1 inside the Menu tab
  /// for now; moving it is a one-line change here plus one in `main.dart`.
  static const dayBook = 'day-book';

  /// S8.2 as a full location for `context.push`. Spelled out rather than
  /// composed from `features/menu`'s [MenuPaths] — menu imports this feature,
  /// so importing it back would close a cycle.
  static const dayBookLocation = '${RkPaths.menu}/$root/$dayBook';
}
