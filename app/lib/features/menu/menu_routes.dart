// Menu feature routes (features/README "Routes", 13 §3.1/§3.2). Menu (S8) is
// a bottom-bar root — `menuRoot` is the [RkTabRoot] the app passes to
// `buildRouter(menu: menuRoot, ...)` / `RukkaFolioApp(menuTabRoot: menuRoot)`
// (the orchestrator wires the latter; not done in this lane). S8.1 Reports
// nests *under* the root as `menuRoot.routes` (13 §3.2 depth rule) rather
// than covering the tab bar, per this lane's brief — `features/menu`
// composes the routes it imports from `features/reports`.
//
// Devices & security (S11), Backup (S11.4) and Settings (S13) are
// root-navigator routes already wired into the app's `featureRoutes`
// (`devicesRoutes`/`settingsRoutes` in main.dart, built by earlier lanes) —
// Menu just pushes their absolute path, exactly as Home pushes
// `LedgerPaths.statementOf`.
import 'package:go_router/go_router.dart';

import '../../shared/router.dart';
import '../devices/devices_paths.dart';
import '../reports/reports_routes.dart';
import '../settings/settings_paths.dart';
import 'menu_paths.dart';
import 'screens/s8_menu_screen.dart';

export 'menu_paths.dart';

/// S8 Menu — the Menu tab's root screen. Row taps push a nested route
/// (Reports) or an existing feature's root-navigator screen (Backup,
/// Devices & security, Settings).
final RkTabRoot menuRoot = RkTabRoot(
  builder: (context) => MenuScreen(
    onOpenReports: () => context.push(MenuPaths.reports),
    onOpenBackup: () => context.push(DevicesPaths.backup),
    onOpenDevices: () => context.push(DevicesPaths.devices),
    onOpenSettings: () => context.push(SettingsPaths.root),
  ),
  routes: reportsRoutes,
);
