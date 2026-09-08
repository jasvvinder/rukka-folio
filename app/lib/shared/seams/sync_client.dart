// The app's seam to the sync engine (05). UI lanes depend on this interface
// and the in-memory fake; the real client (sync_engine over the server) plugs
// in at integration. No network here.
import 'dart:async';

/// The status surface — exactly the five states 05 §9 owns (feeds 07 §1.7).
/// No other states; no spinners on entry save, ever. (The determinate loader
/// while a book rebuilds is a screen state, S1.4, not a sync status.)
sealed class SyncStatus {
  const SyncStatus();
}

/// `Synced ✓` — outbox empty, cursors fresh, no author gaps.
final class Synced extends SyncStatus {
  const Synced();
}

/// `Saved on phone · will sync (N)` — N envelopes waiting in the outbox.
final class SavedWillSync extends SyncStatus {
  const SavedWillSync(this.count);

  /// Outbox depth; ≥ 1.
  final int count;
}

/// `Offline`.
final class Offline extends SyncStatus {
  const Offline();
}

/// `Waiting for entries from {name}'s phone` — author gap < 24 h
/// (ADR 2026-09-05b §3); the projection is provisional.
final class WaitingFor extends SyncStatus {
  const WaitingFor(this.name);

  /// Display name of the member whose entries are missing.
  final String name;
}

/// `Needs attention` → Inbox: rejections, quarantines, key_wait > 24 h,
/// author gap > 24 h, write_lost, clock warning.
final class NeedsAttention extends SyncStatus {
  const NeedsAttention();
}

/// What the app needs from sync. Everything else (outbox, cursors, keys) is
/// the engine's business (05 §3–§5).
abstract class SyncClient {
  /// Current status, then every change. Emits the current value on listen.
  Stream<SyncStatus> get status;

  /// The latest status without subscribing.
  SyncStatus get current;

  /// Runs one push/pull cycle now (05 §7 triggers: foreground, save, pull-down).
  Future<void> syncNow();
}

/// In-memory fake for UI lanes and tests: set [current], count [syncNowCalls].
class FakeSyncClient implements SyncClient {
  FakeSyncClient({SyncStatus initial = const Synced()}) : _current = initial;

  final _controller = StreamController<SyncStatus>.broadcast();
  SyncStatus _current;

  /// Number of times [syncNow] ran.
  int syncNowCalls = 0;

  /// What [syncNow] moves the status to, if anything.
  SyncStatus? afterSync;

  @override
  SyncStatus get current => _current;

  /// Emits [value] to every listener.
  set current(SyncStatus value) {
    _current = value;
    _controller.add(value);
  }

  @override
  Stream<SyncStatus> get status async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> syncNow() async {
    syncNowCalls++;
    final next = afterSync;
    if (next != null) current = next;
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}
