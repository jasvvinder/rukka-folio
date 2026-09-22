// Subscription routes (features/README "Routes"). Mounted on the **root**
// navigator: S12 is reached by pushing [SubscriptionPaths.root] from the
// *Subscription* row of S8 Menu (07 §2 🔒) and of S13 Settings (07 §16), and
// S12.1 Plans sits one level under it (13 §3.1).
//
// The screens own no navigation: every door is a callback the route fills in
// (the `legalRoutes`/`helpRoutes` convention), so each page is pumpable in a
// widget test with no router.
//
// **The source.** With an [EntitlementScope] above, the routes use it. With
// none — which is every build today, because the meta channel that delivers
// the token is not wired (05 §5) — they use [UntokenedEntitlementSource].
// That is not a stub: ADR 2026-09-05g §1 🔒 says an app with no valid token
// reads *Free, never locked*, and that is exactly what it returns.
//
// **The channel** is read from the ambient platform, not from a build flag:
// 08 §3.2 🔒 / ADR 2026-09-05g §8 rule In-App Purchase on iOS and the gateway
// on Android and web, and macOS ships through the App Store on the same
// terms, so both Apple platforms take the IAP reading. Everything else takes
// the gateway. ⚠️ SPEC — 08 §3.2 names iOS and "Android and web" only; macOS
// is the conservative reading of the same merchant-of-record rule rather than
// a new decision, and no coupon field exists on either path today.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/app_scope.dart';
import 'entitlement_source.dart';
import 'invoice_source.dart';
import 'screens/s12_1_plans_screen.dart';
import 'screens/s12_3_manage_screen.dart';
import 'screens/s12_4_payment_problem_screen.dart';
import 'screens/s12_6_invoices_screen.dart';
import 'screens/s12_subscription_screen.dart';
import 'subscription_commands.dart';
import 'subscription_paths.dart';
import 'subscription_seam_scope.dart';
import 'tier_catalogue.dart';

export 'dunning_grace.dart';
export 'entitlement_source.dart';
export 'invoice_source.dart';
export 'screens/s12_1_plans_screen.dart';
export 'screens/s12_3_manage_screen.dart';
export 'screens/s12_4_payment_problem_screen.dart';
export 'screens/s12_6_invoices_screen.dart';
export 'screens/s12_subscription_screen.dart';
export 'subscription_commands.dart';
export 'subscription_copy.dart';
export 'subscription_paths.dart';
export 'subscription_seam_scope.dart';
export 'tier_catalogue.dart';

/// The subscription feature's routes.
final List<RouteBase> subscriptionRoutes = [
  GoRoute(
    path: SubscriptionPaths.root,
    builder: (context, state) => SubscriptionScreen(
      source: entitlementSourceOf(context),
      onOpenPlans: () => context.push(SubscriptionPaths.plans),
      onOpenManage: () => context.push(SubscriptionPaths.manage),
      onOpenPayment: () => context.push(SubscriptionPaths.payment),
      onOpenInvoices: () => context.push(SubscriptionPaths.invoices),
    ),
    routes: [
      GoRoute(
        path: 'plans',
        builder: (context, state) => PlansScreen(
          source: entitlementSourceOf(context),
          channel: rkCheckoutChannelOf(context),
        ),
      ),
      GoRoute(
        path: 'manage',
        builder: (context, state) => ManageSubscriptionScreen(
          source: entitlementSourceOf(context),
          commands: subscriptionCommandsOf(context),
          channel: rkCheckoutChannelOf(context),
          onOpenPlans: () => context.push(SubscriptionPaths.plans),
        ),
      ),
      GoRoute(
        path: 'payment',
        builder: (context, state) => PaymentProblemScreen(
          source: entitlementSourceOf(context),
          commands: subscriptionCommandsOf(context),
          // 🔒 The clock is the app's injected one (CLAUDE.md rule 3's
          // spirit in the UI layer): no screen reads the wall clock.
          now: RkScope.of(context).now,
          onOpenPlans: () => context.push(SubscriptionPaths.plans),
        ),
      ),
      GoRoute(
        path: 'invoices',
        builder: (context, state) =>
            InvoicesScreen(source: invoiceSourceOf(context)),
      ),
    ],
  ),
];

/// The scoped source, or the untokened reading (ADR 2026-09-05g §1 🔒).
EntitlementSource entitlementSourceOf(BuildContext context) =>
    EntitlementScope.maybeOf(context)?.source ??
    const UntokenedEntitlementSource();

/// The scoped commands, or the unwired implementation — which answers
/// [RkCommandUnavailable] because no payment channel is in the app (PLAN desk
/// item 11), never a silent success.
SubscriptionCommands subscriptionCommandsOf(BuildContext context) =>
    SubscriptionSeamScope.maybeOf(context)?.commands ??
    const UnwiredSubscriptionCommands();

/// The scoped invoice source, or the unwired one — which reads empty, because
/// nothing in the app issues an invoice (ADR 2026-09-05g §8 🔒).
InvoiceSource invoiceSourceOf(BuildContext context) =>
    SubscriptionSeamScope.maybeOf(context)?.invoices ??
    const UnwiredInvoiceSource();

/// Which checkout channel this platform uses (08 §3.2 🔒).
RkCheckoutChannel rkCheckoutChannelOf(BuildContext context) => switch (Theme.of(
  context,
).platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => RkCheckoutChannel.inAppPurchase,
  _ => RkCheckoutChannel.gateway,
};
