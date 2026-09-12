// Paths owned by this feature. `RkPaths.menu` is the tab root (S8, shared
// router); S8.1 Reports nests one level below it (13 §3.2 depth rule),
// composed from `features/reports`'s own relative route.
import '../../shared/router.dart';
import '../reports/reports_paths.dart';

abstract final class MenuPaths {
  /// S8 Menu — the tab root.
  static const root = RkPaths.menu;

  /// S8.1 Reports list (composed from `features/reports`), as a full
  /// location for `context.push`.
  static const reports = '${RkPaths.menu}/${ReportsPaths.root}';
}
