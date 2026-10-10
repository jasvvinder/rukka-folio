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

  /// Whether the server refused [bookId]'s pushes with `rejected:quota` —
  /// **book full** (ADR 2026-09-05b §7). The entry Save path asks this before
  /// posting and raises the S12.5 sheet instead (07 §5, ADR 2026-09-05f §B).
  ///
  /// A per-book question, not a sixth [SyncStatus]: the status surface stays
  /// the five states 05 §9 owns, and the quota row itself reaches the user as
  /// an Inbox card through `NeedsAttention`. A predicate rather than a set
  /// getter so no caller can hold (or mutate) a snapshot that goes stale when
  /// the plan is upgraded and the book resumes. Reads are never blocked by it.
  bool isBookFull(String bookId);

  /// Whether the engine is held *not registered yet* (ADR 2026-10-09 §1 🔒):
  /// before S0.2 mints this phone's keys there is nobody to sync as, and the
  /// engine sends nothing. Not a sixth [SyncStatus] — 05 §9 🔒 keeps five,
  /// and while held [current] still reads one of them (`Offline` when nothing
  /// is queued). A screen tells the two apart through this signal: while
  /// held it shows **no** sync chip, and no control is disabled because of
  /// it (ADR 2026-10-10 §2 🔒). Read it through [SyncChip] rather than by hand.
  ///
  /// [held] and [current] are one pair: an implementation answers both from
  /// the same read of its engine, never a fresh hold beside a status read
  /// under the other one — the `Offline` a held engine reports, paired with
  /// a registered hold, would draw a chip the engine does not report.
  bool get held;

  /// [held] now, then every change. Emits the current value on listen.
  Stream<bool> get heldChanges;
}

/// What a screen's sync chip shows (ADR 2026-10-10 §2 🔒): the client's
/// [SyncStatus] once the engine is registered, and `null` — no chip at all,
/// not `Offline`, and nothing disabled — while it is [SyncClient.held]. Once
/// not held, 05 §9 and 07 §1 rule 7 apply unchanged. Showing nothing is not a
/// sixth state; the seam's states stay the five.
extension SyncChip on SyncClient {
  /// The chip's status now; `null` while held.
  SyncStatus? get chipCurrent => held ? null : current;

  /// The chip's status now, then on every status or [SyncClient.held]
  /// change; `null` while held. Emits the current value on listen.
  Stream<SyncStatus?> get chipStatus => Stream<SyncStatus?>.multi((out) {
    var isHeld = held;
    var last = current;
    void emit() => out.add(isHeld ? null : last);
    final statuses = status.listen((s) {
      last = s;
      emit();
    }, onDone: out.close);
    final holds = heldChanges.listen((h) {
      isHeld = h;
      emit();
    });
    out.onCancel = () async {
      await statuses.cancel();
      await holds.cancel();
    };
  });
}

/// In-memory fake for UI lanes and tests: set [current], count [syncNowCalls].
class FakeSyncClient implements SyncClient {
  FakeSyncClient({SyncStatus initial = const Synced(), bool held = false})
    : _current = initial,
      _held = held;

  final _controller = StreamController<SyncStatus>.broadcast();
  final _heldController = StreamController<bool>.broadcast();
  SyncStatus _current;
  bool _held;

  /// Not held unless a test says so — the registered phone every screen test
  /// before ADR 2026-10-10 assumed.
  @override
  bool get held => _held;

  /// Emits [value] to every [heldChanges] listener.
  set held(bool value) {
    _held = value;
    _heldController.add(value);
  }

  @override
  Stream<bool> get heldChanges async* {
    yield _held;
    yield* _heldController.stream;
  }

  /// Number of times [syncNow] ran.
  int syncNowCalls = 0;

  /// What [syncNow] moves the status to, if anything.
  SyncStatus? afterSync;

  /// Books [isBookFull] answers true for — empty until a test says so.
  final Set<String> fullBooks = {};

  @override
  bool isBookFull(String bookId) => fullBooks.contains(bookId);

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

  /// Closes the streams.
  Future<void> dispose() async {
    await _controller.close();
    await _heldController.close();
  }
}
