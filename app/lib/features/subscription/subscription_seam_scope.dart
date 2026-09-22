// Hands the two command/read seams of S12.3, S12.4 and S12.6 down the tree,
// the way [EntitlementScope] already hands down the entitlement reading.
//
// Absent — which is every build today — the routes fall back to
// [UnwiredSubscriptionCommands] and [UnwiredInvoiceSource]. Neither is a
// placeholder pretending to work: with no payment channel in the app (PLAN
// desk item 11) there is no command to send and no document to list, and both
// say exactly that. When a channel lands, the shell mounts one of these and
// nothing below changes.
import 'package:flutter/widgets.dart';

import 'invoice_source.dart';
import 'subscription_commands.dart';

/// Carries [SubscriptionCommands] and [InvoiceSource] for the feature.
class SubscriptionSeamScope extends InheritedWidget {
  /// Creates the scope.
  const SubscriptionSeamScope({
    super.key,
    required this.commands,
    required this.invoices,
    required super.child,
  });

  /// The command seam S12.3 and S12.4 use.
  final SubscriptionCommands commands;

  /// The document seam S12.6 reads.
  final InvoiceSource invoices;

  /// The nearest scope, or null.
  static SubscriptionSeamScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SubscriptionSeamScope>();

  @override
  bool updateShouldNotify(SubscriptionSeamScope oldWidget) =>
      oldWidget.commands != commands || oldWidget.invoices != invoices;
}
