// Devices feature routes (features/README). Mounted on the root navigator;
// the Menu lane may re-home S11 under /menu when RkPaths gains the entries.
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/router.dart';
import '../../shared/widgets/placeholder_screen.dart';
import '../ceremony/ceremony_paths.dart';
import 'devices_paths.dart';
import 'screens/s11_1_guardian_setup_screen.dart';
import 'screens/s11_4_backup_screen.dart';
import 'screens/s11_9_10_cancel_window_screen.dart';
import 'screens/s11_devices_screen.dart';
import 'screens/s15_4_suspended_screen.dart';
import 'screens/s19_5_modified_device_screen.dart';

export 'devices_paths.dart';
export 'screens/s11_1_guardian_setup_screen.dart';
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
      // Declared before ':row' so the literal wins the match: the S11 row
      // pushes `/devices/guardians`, and only the rows still unbuilt fall
      // through to the placeholder.
      GoRoute(
        path: 'guardians',
        builder: (context, state) => GuardianSetupScreen(
          onMeet: (c) =>
              context.push(CeremonyPaths.verifyMemberFor(c.inviteId ?? '')),
          onAddMember: () => context.push(RkPaths.members),
          onDone: () {
            if (context.canPop()) context.pop();
          },
        ),
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
