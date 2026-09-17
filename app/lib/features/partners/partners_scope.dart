// The mount seam for [PartnersPort]. The shell (or a test) puts one of these
// above the router; S14 reads it in `build`.
//
// It is an InheritedWidget rather than a constructor argument because S14 is a
// **root-navigator route** reached from S8.1 by path (13 §3.2 row S14), so the
// route builder has no object to hand it.
import 'package:flutter/widgets.dart';

import 'partners_port.dart';

/// Carries the [PartnersPort] down the tree.
class PartnersScope extends InheritedWidget {
  /// Creates the scope.
  const PartnersScope({super.key, required this.port, required super.child});

  /// The implementation S14 reads and posts through.
  final PartnersPort port;

  /// The nearest port, or null when none is mounted.
  static PartnersPort? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PartnersScope>()?.port;

  /// The nearest port; throws when the shell forgot to mount one.
  static PartnersPort of(BuildContext context) {
    final port = maybeOf(context);
    if (port == null) {
      throw FlutterError(
        'No PartnersScope above this widget. S14 reads the ledger through '
        'PartnersPort; mount PartnersScope(port: …) above the router.',
      );
    }
    return port;
  }

  @override
  bool updateShouldNotify(PartnersScope oldWidget) => oldWidget.port != port;
}
