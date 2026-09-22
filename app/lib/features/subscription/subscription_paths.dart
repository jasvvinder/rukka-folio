// Paths of the subscription feature (features/README "Routes": a path is
// declared once and never re-typed).
//
// S12 is a root-navigator screen reached from the *Subscription* rows of S8
// Menu (07 §2 🔒) and S13 Settings (07 §16), and S12.1 Plans sits one level
// under it (13 §3.1: never more than two levels from a bottom-bar root).
//
// ⚠️ SPEC — these are literals, not `RkPaths` aliases. Every other feature
// aliases the single declaration in `shared/router.dart`, but that file
// belongs to the shell lane and no lane may edit another's directory this
// round; `features/help` and `features/account` carried their own literals
// for exactly the same reason until the orchestrator hoisted them. The lane
// report names the `RkPaths` block to add.
library;

abstract final class SubscriptionPaths {
  /// S12 Subscription.
  static const root = '/subscription';

  /// S12.1 Plans.
  static const plans = '/subscription/plans';

  /// S12.3 Manage subscription.
  static const manage = '/subscription/manage';

  /// S12.4 Payment problem — the dunning grace (08 §3 🔒).
  static const payment = '/subscription/payment';

  /// S12.6 Invoices.
  static const invoices = '/subscription/invoices';
}
