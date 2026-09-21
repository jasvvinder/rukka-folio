// Account feature routes (features/README "Routes"). Mounted on the **root**
// navigator; reached by pushing [AccountPaths.root] from Menu (S8) — the
// orchestrator wires the router and that row.
//
// S16.2 Change phone number (06 §9.4 🔒) is mounted here as of M11/A2. The row
// on S16 was drawn disabled-with-reason while the route did not exist; now
// that it does, `onChangePhone` is passed and the same row is a door. Both
// halves stay asserted (F1-07-318) — a screen that only ever sees the wired
// case cannot prove it degrades honestly.
import 'package:go_router/go_router.dart';

import '../../shared/router.dart';
import '../settings/settings_paths.dart';
import 'account_paths.dart';
import 'screens/s16_1_edit_profile_screen.dart';
import 'screens/s16_2_change_phone_screen.dart';
import 'screens/s16_3_delete_account_screen.dart';
import 'screens/s16_my_account_screen.dart';

export 'account_paths.dart';
export 'account_repository.dart'
    show
        AccountFailure,
        AccountProfile,
        AccountRepository,
        AccountRepositoryScope,
        AccountSnapshot,
        FakeAccountRepository,
        accountInitialsOf,
        accountPhotoSupported;
export 'deletion_window.dart';
export 'phone_change.dart';
export 'screens/s16_1_edit_profile_screen.dart';
export 'screens/s16_2_change_phone_screen.dart';
export 'screens/s16_3_delete_account_screen.dart';
export 'screens/s16_my_account_screen.dart';

/// The account feature's routes: S16, S16.1, S16.2, S16.3.
final List<RouteBase> accountRoutes = [
  GoRoute(
    path: AccountPaths.root,
    builder: (context, state) => MyAccountScreen(
      onEditProfile: () => context.push(AccountPaths.editProfile),
      onChangePhone: () => context.push(AccountPaths.changePhone),
      onOpenLanguage: () => context.push(SettingsPaths.root),
      onOpenDelete: () => context.push(AccountPaths.delete),
    ),
    routes: [
      GoRoute(
        path: 'edit',
        builder: (context, state) => EditProfileScreen(
          onDone: () {
            if (context.canPop()) context.pop();
          },
        ),
      ),
      GoRoute(
        path: 'phone',
        builder: (context, state) => ChangePhoneScreen(
          onDone: () {
            if (context.canPop()) context.pop();
          },
          // → S11.1 Trusted members (04 §7.3 🔒): the way out of the
          // lost-number route's disabled-with-reason state, so a user with no
          // trusted members is never told "no" without being told "here".
          onSetUpTrustedMembers: () => context.push(RkPaths.devicesGuardians),
        ),
      ),
      GoRoute(
        path: 'delete',
        builder: (context, state) => const DeleteAccountScreen(),
      ),
    ],
  ),
];
