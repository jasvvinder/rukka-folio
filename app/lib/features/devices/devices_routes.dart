// Devices feature routes (features/README). Mounted on the root navigator;
// the Menu lane may re-home S11 under /menu when RkPaths gains the entries.
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/router.dart';
import '../../shared/widgets/placeholder_screen.dart';
import '../../shared/seams/guardians.dart';
import '../ceremony/ceremony_paths.dart';
import '../members/members_repository.dart';
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
          // S9.3 is keyed by the subject's **user id** (CeremonyPaths
          // .verifyMemberFor; migration 0007 keys a ceremony session by
          // `subject_user`) — `memberId` is that id (guardians_seams fills it
          // from the roster's `userId`). The candidate carries no invite id:
          // retired by ADR 2026-10-03c §4 (04 §6 — guardian activation runs
          // the ceremony between two members with no invite).
          onMeet: (c) =>
              context.push(CeremonyPaths.verifyMemberFor(c.memberId)),
          meetBlockOf: guardianMeetBlockFrom(
            MembersRepositoryScope.of(context),
          ),
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

/// *Meet them* is offered — and the member may be **chosen** (ADR 2026-10-03c
/// §4) — only for a member the server will open a ceremony for:
/// `joined_pending_verification` or `active` (migration 0007
/// `subject_not_in_tenant`; 06 §7 🔒). An `invited` or `expired` row is keyed
/// by its **invite** id (no user exists yet), and pushing that into S9.3 would
/// ask for a UMK nobody has; a `blocked` member needs an admin and a new
/// invite first (06 §7 🔒, 06 §10).
///
/// Read lazily, per row: the guardian roster is built from the same members
/// snapshot (`bootstrap`'s `GuardianRoster`), so the answer and the row come
/// from one reading.
///
/// ⚠️ SPEC: `TrustedMemberCandidate` carries no membership state, so this
/// joins it to the members snapshot by id. A candidate the snapshot does not
/// hold is treated as *not joined* — the conservative reading, since this
/// device cannot show that the person can be met. Carrying the state on the
/// seam itself is for the owner of `shared/seams/guardians.dart`.
GuardianMeetBlock? Function(TrustedMemberCandidate) guardianMeetBlockFrom(
  MembersRepository members,
) => (candidate) {
  final list = members.current?.members ?? const <Member>[];
  for (final m in list) {
    if (m.id != candidate.memberId) continue;
    return switch (m.state) {
      MembershipState.active ||
      MembershipState.joinedPendingVerification => null,
      MembershipState.invited ||
      MembershipState.expired => GuardianMeetBlock.notJoined,
      MembershipState.blocked => GuardianMeetBlock.blocked,
    };
  }
  return GuardianMeetBlock.notJoined;
};
