// The paths the activation ladder lives at (13 §5 flow F11, 13 §3.2 rows
// S11.5 / S11.6 / S11.8, plus S11.2 / S11.3 / S11.7).
//
// All six are **root-navigator** routes: recovery happens before the user
// has books to show, so nothing here may sit inside the tab shell — there is
// no Home to go back to until the ladder finishes. S11.7 is on the root
// navigator for a different reason: it arrives on a *guardian's* phone from
// the loud notification of 13 §3.4 and is a security decision, not a tab.
//
// Aliases of `RkPaths` (features/README: never re-type a path). The three
// rung screens carried literals while `shared/router.dart` belonged to
// another lane; M11/RV5 hoisted them, so every path in this file is now a
// single declaration in the router with a name here.
import '../../shared/router.dart';

abstract final class RecoveryPaths {
  /// S11.5 — silent restore (design R2.0). The screen rung 0 lands on.
  static const silent = RkPaths.recovery;

  /// S11.6 — the fork (design R2.1), after OTP on a new phone.
  static const fork = RkPaths.recoveryFork;

  /// S11.8 — nothing worked yet (design R2.5 🔒). Reached only when every
  /// rung has failed (13 §5 F11: `none → S11.8`).
  static const nothingYet = RkPaths.recoveryNothingYet;

  /// S11.2 — ask your trusted members (design R2.2). Rung 2, 04 §7.3.
  static const askMembers = RkPaths.recoveryAskMembers;

  /// S11.3 — the recovery sheet (design R2.4). Rung 3, 04 §7.4.
  static const sheet = RkPaths.recoverySheet;

  /// S11.7 — the guardian's side (design R2.3), reached from the loud
  /// notification of 13 §3.4 with the request id in the path.
  static const approve = RkPaths.recoveryApprove;

  /// [approve] with [requestId] filled in.
  static String approveOf(String requestId) => '/recovery/approve/$requestId';
}
