// Ceremony feature routes (features/README) — S9.2, S9.3, S9.4, mounted on the
// root navigator: the ceremony covers the tab bar, like entry and detail.
//
// S9.4 is reached only from S9.3, and only by replacing it (`pushReplacement`):
// a mismatch has no way back to the comparison it failed (04 §6.3 🔒).
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/app_scope.dart';
import '../../shared/widgets/placeholder_screen.dart';
import 'camera_scanner.dart';
import 'ceremony_paths.dart';
import 'ceremony_scope.dart';
import 'screens/s9_2_show_my_code_screen.dart';
import 'screens/s9_3_verify_member_screen.dart';
import 'screens/s9_4_mismatch_screen.dart';

export 'camera_scanner.dart';
export 'ceremony_paths.dart';
export 'ceremony_repository.dart';
export 'ceremony_scope.dart';
export 'screens/s9_2_show_my_code_screen.dart';
export 'screens/s9_3_verify_member_screen.dart';
export 'screens/s9_4_mismatch_screen.dart';

final List<RouteBase> ceremonyRoutes = [
  GoRoute(
    path: CeremonyPaths.showMyCode,
    builder: (context, state) {
      final repository = CeremonyScope.maybeOf(context)?.showMyCode;
      if (repository == null) {
        return RkPlaceholderScreen(
          title: AppLocalizations.of(context).ceremonyShowTitle,
          body: AppLocalizations.of(context).ceremonyShowLoading,
        );
      }
      return ShowMyCodeScreen(
        repository: repository,
        now: RkScope.of(context).now,
      );
    },
  ),
  GoRoute(
    path: CeremonyPaths.verifyMember,
    builder: (context, state) {
      final scope = CeremonyScope.maybeOf(context);
      final repository = scope?.verifyMember;
      if (repository == null) {
        return RkPlaceholderScreen(
          title: AppLocalizations.of(context).ceremonyVerifyTitle,
          body: AppLocalizations.of(context).ceremonyVerifyChecking,
        );
      }
      return VerifyMemberScreen(
        repository: repository,
        scanner: scope?.scanner ?? NoCameraScanner(),
        onMismatch: () => context.pushReplacement(CeremonyPaths.mismatch),
        onVerified: () => context.pop(),
      );
    },
  ),
  GoRoute(
    path: CeremonyPaths.mismatch,
    builder: (context, state) => const VerificationMismatchScreen(),
  ),
];
