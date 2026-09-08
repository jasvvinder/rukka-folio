// Devices feature routes (features/README). Mounted on the root navigator;
// the Menu lane may re-home S11 under /menu when RkPaths gains the entries.
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/widgets/placeholder_screen.dart';
import 'devices_paths.dart';
import 'screens/s11_4_backup_screen.dart';
import 'screens/s11_9_10_cancel_window_screen.dart';
import 'screens/s11_devices_screen.dart';
import 'screens/s15_4_suspended_screen.dart';
import 'screens/s19_5_modified_device_screen.dart';

export 'devices_paths.dart';
export 'devices_repository.dart'
    show DevicesRepository, DevicesRepositoryScope, FakeDevicesRepository;

final List<RouteBase> devicesRoutes = [
  GoRoute(
    path: DevicesPaths.devices,
    builder: (context, state) => DevicesScreen(
      onOpenBackup: () => context.push(DevicesPaths.backup),
      onOpenWindow: (id) => context.push(DevicesPaths.windowFor(id)),
      onOpenRow: (row) => context.push('${DevicesPaths.devices}/$row'),
    ),
    routes: [
      GoRoute(
        path: 'backup',
        builder: (context, state) => const BackupScreen(),
      ),
      GoRoute(
        path: 'window/:id',
        builder: (context, state) =>
            CancelWindowScreen(windowId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: ':row',
        builder: (context, state) => RkPlaceholderScreen(
          title: AppLocalizations.of(context).devicesTitle,
          body: AppLocalizations.of(context).devicesPlaceholderBody,
        ),
      ),
    ],
  ),
  GoRoute(
    path: DevicesPaths.suspended,
    builder: (context, state) => SuspendedScreen(
      onOpenDevices: () => context.push(DevicesPaths.devices),
    ),
  ),
  GoRoute(
    path: DevicesPaths.modified,
    builder: (context, state) => ModifiedDeviceScreen(
      onOpenDevices: () => context.go(DevicesPaths.devices),
      onDismiss: () => context.pop(),
    ),
  ),
];
