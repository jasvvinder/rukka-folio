// Where screens find the ledger facade. `RkScope` (shared/app_scope.dart)
// carries the raw database and the seams; this scope sits beneath it and
// carries the one `LocalLedger` built over them, so a screen reads
// `LedgerScope.of(context)` and never composes core_ledger / core_crypto /
// data itself. Tests pass a seeded facade through `pumpRk(ledger: …)`.
import 'package:flutter/widgets.dart';

import 'local_ledger.dart';

/// The app's [LocalLedger] for the widget tree below.
class LedgerScope extends InheritedWidget {
  /// Creates the scope.
  const LedgerScope({super.key, required this.ledger, required super.child});

  /// The open facade (bootstrapped by the shell before any screen shows).
  final LocalLedger ledger;

  /// The nearest facade, or null when no [LedgerScope] is above [context]
  /// (a screen pumped without data shows its empty state).
  static LocalLedger? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LedgerScope>()?.ledger;

  /// The nearest facade; throws when none — every data screen runs under one.
  static LocalLedger of(BuildContext context) {
    final l = maybeOf(context);
    assert(l != null, 'LedgerScope missing above this widget (see pumpRk)');
    return l!;
  }

  @override
  bool updateShouldNotify(LedgerScope old) => ledger != old.ledger;
}
