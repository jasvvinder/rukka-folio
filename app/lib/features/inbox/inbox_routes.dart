// Inbox feature routes (features/README "Routes").
//
// [inboxRoot] is the Inbox tab's root (S6, tab bar visible); [inboxRoutes] are
// the root-navigator routes it pushes (S6.2, covering the tab bar). Integration
// composes them in `main.dart`:
//
//   buildRouter(featureRoutes: [...inboxRoutes], inbox: inboxRoot(...))
import 'package:flutter/widgets.dart';

import '../../shared/router.dart';
import 'inbox_paths.dart';
import 'screens/s6_2_review_stepper_screen.dart';
import 'screens/s6_3_structural_review_screen.dart';
import 'screens/s6_inbox_screen.dart';

export 'inbox_paths.dart';

/// The Inbox tab root (S6). [onOpenLedger] is the empty state's one next
/// action — integration points it at the Ledger tab (07 §1 rule 6).
RkTabRoot inboxRoot({VoidCallback? onOpenLedger}) => RkTabRoot(
  builder: (context) => InboxScreen(
    onOpenLedger: onOpenLedger ?? () => GoRouter.of(context).go(RkPaths.ledger),
    onReviewGroup: (groupId) =>
        GoRouter.of(context).push(InboxPaths.stepperFor(groupId)),
    onOpenStructural: (requestId) =>
        GoRouter.of(context).push(InboxPaths.structuralFor(requestId)),
  ),
);

/// Root-navigator routes: S6.2 (07 §9) and S6.3 (07 §26), each full-screen
/// over the tab bar.
final List<RouteBase> inboxRoutes = [
  GoRoute(
    path: InboxPaths.stepper,
    builder: (context, state) =>
        ReviewStepperScreen(groupId: state.pathParameters['groupId'] ?? ''),
  ),
  GoRoute(
    path: InboxPaths.structural,
    builder: (context, state) => StructuralReviewScreen(
      requestId: state.pathParameters['requestId'] ?? '',
      onDone: () => GoRouter.of(context).go(RkPaths.inbox),
    ),
  ),
];
