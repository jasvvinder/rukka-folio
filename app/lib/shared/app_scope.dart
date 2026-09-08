// The app's dependency scope: one InheritedWidget carrying the database, the
// sync and auth seams and an injected clock. Features read `RkScope.of(context)`
// and never construct these themselves, so tests swap fakes in one place.
import 'package:data/data.dart';
import 'package:flutter/widgets.dart';

import 'seams/auth_client.dart';
import 'seams/key_store.dart';
import 'seams/sync_client.dart';

/// Dependencies for the widget tree below.
class RkScope extends InheritedWidget {
  const RkScope({
    super.key,
    required this.db,
    required this.sync,
    required this.auth,
    required this.keys,
    required this.now,
    required super.child,
  });

  /// The open local ledger (03).
  final LedgerDatabase db;

  /// Sync seam (05).
  final SyncClient sync;

  /// Identity seam (06).
  final AuthClient auth;

  /// Secrets at rest (04 §3.3) — device keys, wrapped UMK, database key.
  final KeyStore keys;

  /// Injected clock — widgets never call `DateTime.now()` directly, so tests
  /// pin time (09 §1).
  final DateTime Function() now;

  /// The nearest scope; throws if none — every screen runs under one.
  static RkScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RkScope>();
    assert(scope != null, 'RkScope missing above this widget (see pumpRk)');
    return scope!;
  }

  @override
  bool updateShouldNotify(RkScope old) =>
      db != old.db ||
      sync != old.sync ||
      auth != old.auth ||
      keys != old.keys ||
      now != old.now;
}
