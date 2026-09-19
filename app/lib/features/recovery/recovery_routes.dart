// Recovery feature routes (features/README). All on the **root** navigator:
// the activation ladder runs before there are books to show, so none of these
// screens may sit inside the tab shell.
//
// The flow is 13 §5 F11: `S11.5 → (rung 0 found nothing) → S11.6 → (no rung
// open) → S11.8`. Each hop is a `push`, so a person who reached the fork can
// still see what the silent attempt said; the last hop `go`es, because S11.8
// is where the ladder ends and there is nothing behind it worth returning to.
//
// S11.2 and S11.3 landed in the same milestone, so `onRung` now pushes the
// screen that walks the rung the person picked. S11.7 is not on this path at
// all — it arrives on a *different* person's phone from the loud notification
// of 13 §3.4 — but it lives on the root navigator beside the others for the
// same reason: it is a security decision, not a tab.
//
// ⚠️ SPEC: what still has no producer is the **server side**. Every screen
// below runs on the seam's fakes; the adapter over migration 0010's routes is
// the next slice, and `RecoveryLadderScope` / `GuardianRecoveryScope` /
// `RecoverySheetScope` / `GuardianApprovalsScope` are how the shell installs
// it without a screen changing its constructor.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../shared/seams/recovery_ladder.dart';
import 'recovery_paths.dart';
import 'screens/s11_2_ask_members_screen.dart';
import 'screens/s11_3_sheet_screen.dart';
import 'screens/s11_5_silent_restore_screen.dart';
import 'screens/s11_6_fork_screen.dart';
import 'screens/s11_7_guardian_approval_screen.dart';
import 'screens/s11_8_nothing_yet_screen.dart';

export 'recovery_paths.dart';
export 'screens/s11_2_ask_members_screen.dart' show AskTrustedMembersScreen;
export 'screens/s11_3_sheet_screen.dart' show RecoverySheetScreen;
export 'screens/s11_5_silent_restore_screen.dart' show SilentRestoreScreen;
export 'screens/s11_6_fork_screen.dart' show RecoveryForkScreen;
export 'screens/s11_7_guardian_approval_screen.dart'
    show GuardianApprovalScreen;
export 'screens/s11_8_nothing_yet_screen.dart' show NothingWorkedYetScreen;

/// The three activation screens.
///
/// [onRestored] is where a finished silent restore lands — Home in the shell,
/// injected because `features/recovery` does not own that path.
List<RouteBase> recoveryRoutes({
  required void Function(BuildContext context) onRestored,
}) => [
  GoRoute(
    path: RecoveryPaths.silent,
    builder: (context, state) => SilentRestoreScreen(
      onDone: () => onRestored(context),
      onNeedsFork: () => context.push(RecoveryPaths.fork),
    ),
  ),
  GoRoute(
    path: RecoveryPaths.fork,
    builder: (context, state) => RecoveryForkScreen(
      onRung: (rung) => switch (rung) {
        // Rung 1 is the link ceremony, which is the devices feature's screen
        // and its route — not this one's to name.
        RecoveryRung.anotherDevice || RecoveryRung.platformKeySync => null,
        RecoveryRung.trustedMembers => context.push(RecoveryPaths.askMembers),
        RecoveryRung.recoverySheet => context.push(RecoveryPaths.sheet),
      },
      onNothingWorked: () => context.go(RecoveryPaths.nothingYet),
    ),
  ),
  GoRoute(
    path: RecoveryPaths.askMembers,
    builder: (context, state) =>
        AskTrustedMembersScreen(onBack: () => context.pop()),
  ),
  GoRoute(
    path: RecoveryPaths.sheet,
    builder: (context, state) => RecoverySheetScreen(
      onBack: () => context.pop(),
      onRestored: () => onRestored(context),
    ),
  ),
  GoRoute(
    path: RecoveryPaths.approve,
    builder: (context, state) => GuardianApprovalScreen(
      requestId: state.pathParameters['requestId'] ?? '',
      onDone: () => context.pop(),
    ),
  ),
  GoRoute(
    path: RecoveryPaths.nothingYet,
    builder: (context, state) => NothingWorkedYetScreen(
      // Setting this phone up is the shell's business — the same callback the
      // silent path lands on, because both end with a usable phone.
      onContinue: () => onRestored(context),
    ),
  ),
];
