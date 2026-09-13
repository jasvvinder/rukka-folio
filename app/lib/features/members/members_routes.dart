// Members feature routes (features/README). Mounted on the root navigator —
// S9 is two levels from Menu and S9.1 covers the tab bar.
//
// The ceremony screens (S9.2 Show my code, S9.3 Verify member, S9.4 mismatch)
// are another lane's; nothing here links to them, so no dead route is minted.
import 'package:go_router/go_router.dart';

import 'members_paths.dart';
import 'screens/s9_1_invite_screen.dart';
import 'screens/s9_members_screen.dart';

export 'designations.dart';
export 'members_paths.dart';
export 'members_repository.dart';
export 'screens/s9_1_invite_screen.dart' show InviteScreen;
export 'screens/s9_members_screen.dart' show MembersScreen;

final List<RouteBase> membersRoutes = [
  GoRoute(
    path: MembersPaths.members,
    builder: (context, state) =>
        MembersScreen(onInvite: () => context.push(MembersPaths.invite)),
    routes: [
      GoRoute(
        path: 'invite',
        builder: (context, state) => InviteScreen(onSent: () => context.pop()),
      ),
    ],
  ),
];
