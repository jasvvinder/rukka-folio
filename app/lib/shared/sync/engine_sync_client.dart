// The real [SyncClient]: `package:sync_engine`'s [eng.SyncEngine] behind the
// app's seam. Two jobs and no more — map the engine's status onto the five
// states 05 §9 owns, and run a cycle on each 05 §7 trigger. Everything else
// (outbox, cursors, keys, backoff, trust) is the engine's business.
//
// 07 §1.7 🔒: `Offline` is normal, sync failures surface in the Inbox, and a
// sync cycle never stands in front of an entry save — every trigger here is
// fire-and-forget, and `syncNow()` is safe to ignore.
//
// No HTTP lives here: the engine's [eng.SyncTransport] is injected by whoever
// builds the engine (bootstrap).
import 'dart:async';

import 'package:sync_engine/sync_engine.dart' as eng;

import '../seams/sync_client.dart';

/// Resolves an author device id to the member's display name, for the
/// `Waiting for entries from {name}'s phone` state (05 §9). The engine speaks
/// device ids; the status surface speaks names.
typedef MemberNameOf = String Function(String deviceId);

/// How the client arms its backstop poll. Injected so tests fire the tick by
/// hand; production passes [Timer.periodic].
typedef PeriodicTimerFactory = Timer Function(
  Duration period,
  void Function(Timer) onTick,
);

/// The 05 §9 status surface for one engine status. Exhaustive over the
/// engine's sealed status type, so the five states are the only states that
/// can ever reach the UI.
SyncStatus syncStatusFrom(eng.SyncStatus status, MemberNameOf memberName) =>
    switch (status) {
      eng.Synced() => const Synced(),
      // The engine counts queued + in-flight; `N` is that depth.
      eng.SavedWillSync(:final count) => SavedWillSync(count),
      eng.Offline() => const Offline(),
      eng.WaitingFor(:final authorDevice) => WaitingFor(
        memberName(authorDevice),
      ),
      // The reasons stay with the engine: the seam's state is the chip, the
      // Inbox reads the rows (05 §9).
      eng.NeedsAttention() => const NeedsAttention(),
    };

/// The app's [SyncClient] over a live [eng.SyncEngine].
///
/// Triggers (05 §7 🔒): [onAppForeground] (app open), [onScopeSwitch],
/// [onRemoteHint] (content-free FCM — *"book X has news"*), [onEntrySaved],
/// and a backstop poll every [backstopPeriod] on unmetered networks.
class EngineSyncClient implements SyncClient {
  /// Wraps [engine]. [memberName] resolves an author device to a display
  /// name. [unmetered] is the metering signal for the backstop poll: when it
  /// is null the poll is never armed — 05 §7 says *unmetered networks*, and
  /// an app with no metering source must not guess (see the WIRE note).
  EngineSyncClient({
    required this.engine,
    required this.memberName,
    this.unmetered,
    this.backstopPeriod = const Duration(hours: 6),
    PeriodicTimerFactory timerFactory = Timer.periodic,
    SyncStatus initial = const Offline(),
  }) : _timerFactory = timerFactory,
       _current = initial;

  /// The engine this client drives.
  final eng.SyncEngine engine;

  /// Device id → member display name.
  final MemberNameOf memberName;

  /// Whether the current network is unmetered; null = no signal, no poll.
  final bool Function()? unmetered;

  /// Backstop cadence (05 §7: every 6 h).
  final Duration backstopPeriod;

  final PeriodicTimerFactory _timerFactory;

  final _controller = StreamController<SyncStatus>.broadcast();
  SyncStatus _current;
  Timer? _backstop;
  Completer<void>? _cycle;
  bool _again = false;
  bool _disposed = false;
  int _cycles = 0;
  bool _lastCycleFailed = false;

  /// Engine rounds completed by this client.
  int get cycles => _cycles;

  /// Whether the last round ended in an unexpected failure. Failures the
  /// engine understands become Inbox reasons, not this flag (07 §1.7: no
  /// popups); this one exists so a test can see a swallowed throw.
  bool get lastCycleFailed => _lastCycleFailed;

  /// Completes when no cycle is in flight. A trigger registers its cycle
  /// synchronously, so `trigger(); await settled;` is deterministic.
  Future<void> get settled => _cycle?.future ?? Future<void>.value();

  @override
  SyncStatus get current => _current;

  /// Book full, read straight off the engine's own quota stop
  /// ([eng.SyncEngine.quotaStoppedBooks]: added on `rejected:quota`, removed
  /// by [eng.SyncEngine.resumeBook]). [engine] is held by reference and the
  /// set is read on every call, so the answer can never lag the engine.
  @override
  bool isBookFull(String bookId) => engine.quotaStoppedBooks.contains(bookId);

  @override
  Stream<SyncStatus> get status => Stream<SyncStatus>.multi((out) {
    out.add(_current);
    final sub = _controller.stream.listen(out.add, onDone: out.close);
    out.onCancel = sub.cancel;
  });

  /// Reads the first status and arms the backstop poll. Call once, at app
  /// start; the app may then use the client before any cycle has run.
  Future<void> start() async {
    await refresh();
    final metered = unmetered;
    if (metered == null || _disposed) return;
    _backstop = _timerFactory(backstopPeriod, (_) {
      if (metered()) _trigger();
    });
  }

  /// Recomputes [current] from the engine without running a cycle.
  Future<void> refresh() async {
    if (_disposed) return;
    final next = syncStatusFrom(await engine.status(), memberName);
    if (_disposed || _same(_current, next)) return;
    _current = next;
    _controller.add(next);
  }

  // ── 05 §7 triggers ──────────────────────────────────────────────────────

  /// App open / foreground (05 §7).
  void onAppForeground() => _trigger();

  /// Scope switch (05 §7).
  void onScopeSwitch() => _trigger();

  /// A content-free push hint — *"book [bookId] has news"* (05 §7). The
  /// engine's public round covers every subscribed book and is idempotent, so
  /// the hint runs a whole round: a superset of "pull that book", and
  /// correctness comes from the cursors either way ("FCM is a hint, never a
  /// dependency"). The id is taken for symmetry with the spec and for the
  /// day the engine offers a per-book pull.
  void onRemoteHint(String bookId) => _trigger();

  /// An entry was saved (07 §1 🔒). Returns immediately: the save path never
  /// waits for, and never fails on, a sync cycle — and never shows a spinner.
  void onEntrySaved() => _trigger();

  void _trigger() {
    if (_disposed) return;
    unawaited(syncNow());
  }

  @override
  Future<void> syncNow() {
    if (_disposed) return Future<void>.value();
    final running = _cycle;
    if (running != null) {
      // A cycle is in flight. Ask for one more round after it rather than
      // running two at once; every extra ask while it runs folds into that
      // one follow-up.
      _again = true;
      return running.future;
    }
    final done = Completer<void>();
    _cycle = done;
    unawaited(_drive(done));
    return done.future;
  }

  Future<void> _drive(Completer<void> done) async {
    try {
      var more = true;
      while (more && !_disposed) {
        _again = false;
        await _round();
        more = _again;
      }
    } finally {
      _cycle = null;
      if (!done.isCompleted) done.complete();
    }
  }

  Future<void> _round() async {
    try {
      await engine.sync();
      _lastCycleFailed = false;
    } on Object {
      // Nothing reaches the user as a popup (07 §1.7). What the engine
      // understands it has already turned into an Inbox reason; an
      // unexpected throw must not take the save path or the app down.
      _lastCycleFailed = true;
    }
    _cycles++;
    await refresh();
  }

  /// Stops the poll and closes the stream. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _backstop?.cancel();
    _backstop = null;
    await _controller.close();
  }

  // The seam's states carry no `==`, and widening it would touch every UI
  // lane's fake — so equality lives here, where only de-duplication needs it.
  static bool _same(SyncStatus a, SyncStatus b) => switch ((a, b)) {
    (Synced(), Synced()) => true,
    (SavedWillSync(count: final x), SavedWillSync(count: final y)) => x == y,
    (Offline(), Offline()) => true,
    (WaitingFor(name: final x), WaitingFor(name: final y)) => x == y,
    (NeedsAttention(), NeedsAttention()) => true,
    _ => false,
  };
}
