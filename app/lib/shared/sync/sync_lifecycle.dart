// App-open trigger (05 §7): a resume is a foreground pull. Kept apart from
// the client so the client stays a plain object a test can drive.
import 'package:flutter/widgets.dart';

import 'engine_sync_client.dart';

/// Runs [EngineSyncClient.onAppForeground] on every resume. Register it with
/// `WidgetsBinding.instance.addObserver(...)` at app start.
class SyncLifecycleObserver with WidgetsBindingObserver {
  /// Observes for [client].
  SyncLifecycleObserver(this.client);

  /// The client to nudge.
  final EngineSyncClient client;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) client.onAppForeground();
  }
}
