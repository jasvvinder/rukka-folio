// F1 — the sync_engine adapter onto the `SyncClient` seam (05 §7 triggers &
// cadence, 05 §9 status surface, 07 §1.7 and 07 §1 "no spinners on entry save,
// ever"). The engine runs for real over an in-memory ledger database and a
// fake `SyncTransport`: no HTTP anywhere in this lane.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart' show Hlc;
import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/sync/sync.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

const _tenant = 't1';
const _book = 'b1';
const _device = 'phone-a';

/// A [eng.SyncTransport] the test drives: it delegates to the in-memory
/// server, can hold a call open on [gate], and can fail with [failWith].
final class _TestTransport implements eng.SyncTransport {
  _TestTransport(this.inner);

  final eng.FakeTransport inner;

  /// Completed before each call is let through, when set.
  Completer<void>? gate;

  /// Thrown by every call, when set.
  Object? failWith;

  /// Routes called, in order.
  final List<String> calls = [];

  /// Rounds started — one `meta` call opens every engine round (05 §3).
  int get rounds => calls.where((c) => c == 'meta').length;

  Future<T> _call<T>(String route, Future<T> Function() f) async {
    calls.add(route);
    final g = gate;
    if (g != null) await g.future;
    final fail = failWith;
    if (fail != null) throw fail;
    return f();
  }

  @override
  Future<eng.PushResponse> push(eng.PushRequest r) =>
      _call('push', () => inner.push(r));

  @override
  Future<eng.PullResponse> pull(eng.PullRequest r) =>
      _call('pull', () => inner.pull(r));

  @override
  Future<eng.MetaResponse> meta(eng.MetaRequest r) =>
      _call('meta', () => inner.meta(r));
}

/// One device on the in-memory server, with the pieces the adapter needs.
final class _Device {
  _Device(this.db, this.mirror, this.transport, this.engine);

  final LedgerDatabase db;
  final Mirror mirror;
  final _TestTransport transport;
  final eng.SyncEngine engine;
  Hlc _hlc = Hlc.compose(physicalMs: 0, counter: 0);
  int _n = 0;

  /// Appends a synthetic (never real) object to the mirror and the outbox.
  Future<String> author(int physicalMs) async {
    final oid = '$_device-${_n++}';
    _hlc = _hlc.tick(physicalMs: physicalMs);
    final seq = await mirror.nextAuthorSeq(_book, _device);
    final blob = Uint8List.fromList(
      utf8.encode(jsonEncode({'author_seq': seq, 'id': oid})),
    );
    final rec = EnvelopeRecord(
      envelopeId: 'env-$oid',
      bookId: _book,
      objectId: oid,
      objectType: 'entry',
      keyVersion: 1,
      hlc: _hlc.raw,
      authorDevice: _device,
      authorSeq: seq,
      blob: blob,
      blobHash: eng.fnv1a32(blob),
      verified: true,
    );
    await mirror.append(rec);
    await mirror.enqueue(
      envelopeId: rec.envelopeId,
      bookId: _book,
      blob: blob,
      createdAt: physicalMs,
    );
    return rec.envelopeId;
  }
}

Future<_Device> _openDevice(
  eng.FakeSyncServer server,
  eng.ManualClock clock,
) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final r = await openLedgerDatabase(NativeDatabase.memory());
  final db = switch (r) {
    Opened(:final db) => db,
    _ => throw StateError('in-memory ledger did not open: $r'),
  };
  addTearDown(db.close);
  final mirror = Mirror(db, hasher: eng.fnv1a32);
  final transport = _TestTransport(server.transportFor(_device));
  final trust = eng.RecordTrustStore(umks: const eng.MapUmkSource({}));
  final engine = eng.SyncEngine(
    db: db,
    mirror: mirror,
    transport: transport,
    clock: clock,
    guard: eng.PlainGuard(trust: trust),
    trust: trust,
    deviceId: _device,
    userId: 'u-a',
    tenantId: _tenant,
  );
  engine.subscribedBooks.add(_book);
  return _Device(db, mirror, transport, engine);
}

/// A periodic timer the test fires by hand.
final class _FakeTimer implements Timer {
  _FakeTimer(this.period, this.onTick);

  final Duration period;
  final void Function(Timer) onTick;
  bool cancelled = false;

  void fire() => onTick(this);

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late eng.ManualClock clock;
  late eng.FakeSyncServer server;
  late _Device device;

  setUp(() async {
    clock = eng.ManualClock(1000 * 24 * 60 * 60 * 1000);
    server = eng.FakeSyncServer(clock: clock, rateLimits: eng.RateLimits.none);
    device = await _openDevice(server, clock);
  });

  EngineSyncClient client({
    MemberNameOf? memberName,
    bool Function()? unmetered,
    PeriodicTimerFactory? timerFactory,
  }) {
    final c = EngineSyncClient(
      engine: device.engine,
      memberName: memberName ?? (id) => 'Sunita',
      unmetered: unmetered,
      timerFactory: timerFactory ?? (d, f) => _FakeTimer(d, f),
    );
    addTearDown(c.dispose);
    return c;
  }

  group('status surface (05 §9)', () {
    test('F1-05-1 every engine state maps onto one of the seam\'s five, and '
        'the seam declares no others', () {
      String word(SyncStatus s) => switch (s) {
        Synced() => 'synced',
        SavedWillSync() => 'saved',
        Offline() => 'offline',
        WaitingFor() => 'waiting',
        NeedsAttention() => 'attention',
      };
      final mapped = <eng.SyncStatus, SyncStatus>{
        for (final s in <eng.SyncStatus>[
          const eng.Synced(),
          const eng.SavedWillSync(3),
          const eng.Offline(),
          const eng.WaitingFor('phone-b'),
          const eng.NeedsAttention([eng.AttentionReason.rejection]),
        ])
          s: syncStatusFrom(s, (id) => 'Sunita'),
      };
      expect(mapped.values.map(word).toList(), [
        'synced',
        'saved',
        'offline',
        'waiting',
        'attention',
      ]);
      expect(
        mapped[const eng.SavedWillSync(3)],
        isA<SavedWillSync>().having((s) => s.count, 'count', 3),
      );
    });

    test('F1-05-2 WaitingFor carries the member\'s display name, never the '
        'device id (05 §9)', () {
      final s = syncStatusFrom(
        const eng.WaitingFor('phone-b'),
        (id) => id == 'phone-b' ? 'Sunita' : '?',
      );
      expect(s, isA<WaitingFor>().having((w) => w.name, 'name', 'Sunita'));
    });

    test('F1-05-3 NeedsAttention drops the engine\'s reasons — the seam\'s '
        'state carries no payload (the Inbox owns the rows)', () {
      final s = syncStatusFrom(
        const eng.NeedsAttention([
          eng.AttentionReason.rejection,
          eng.AttentionReason.quarantine,
        ]),
        (id) => 'Sunita',
      );
      expect(s, isA<NeedsAttention>());
    });

    test('F1-05-4 outbox depth surfaces as Saved on phone · will sync (N), '
        'and a cycle clears it to Synced', () async {
      await device.author(clock.nowMs());
      final c = client();
      final seen = <SyncStatus>[];
      final sub = c.status.listen(seen.add);
      await c.start();
      expect(c.current, isA<SavedWillSync>().having((s) => s.count, 'N', 1));
      await c.syncNow();
      expect(c.current, isA<Synced>());
      await pumpEventQueue();
      expect(seen.whereType<SavedWillSync>(), isNotEmpty);
      expect(seen.last, isA<Synced>());
      await sub.cancel();
    });

    test('F1-05-5 a dropped transport shows Offline, and connectivity back '
        'returns to Synced', () async {
      final c = client();
      await c.start();
      device.transport.inner.online = false;
      await c.syncNow();
      expect(c.current, isA<Offline>());
      device.transport.inner.online = true;
      await c.syncNow();
      expect(c.current, isA<Synced>());
    });
  });

  group('triggers & cadence (05 §7)', () {
    test('F1-05-6 app open, scope switch and a content-free push hint each run '
        'exactly one cycle', () async {
      final c = client();
      await c.start();
      expect(c.cycles, 0);
      c.onAppForeground();
      await c.settled;
      expect(c.cycles, 1);
      c.onScopeSwitch();
      await c.settled;
      expect(c.cycles, 2);
      c.onRemoteHint(_book);
      await c.settled;
      expect(c.cycles, 3);
      expect(device.transport.rounds, 3);
    });

    test(
      'F1-05-7 the 6 h backstop polls only on an unmetered network',
      () async {
        var unmetered = true;
        _FakeTimer? timer;
        final c = client(
          unmetered: () => unmetered,
          timerFactory: (d, f) => timer = _FakeTimer(d, f),
        );
        await c.start();
        expect(timer, isNotNull);
        expect(timer!.period, const Duration(hours: 6));
        timer!.fire();
        await c.settled;
        expect(c.cycles, 1);
        unmetered = false;
        timer!.fire();
        await c.settled;
        expect(c.cycles, 1, reason: 'metered: the backstop does not poll');
      },
    );

    test('F1-05-8 with no metering signal the backstop timer is not armed at '
        'all (05 §7 says unmetered; the app must not guess)', () async {
      _FakeTimer? timer;
      final c = client(timerFactory: (d, f) => timer = _FakeTimer(d, f));
      await c.start();
      expect(timer, isNull);
    });

    test('F1-05-9 a lifecycle resume is an app-open trigger', () async {
      final c = client();
      await c.start();
      final observer = SyncLifecycleObserver(c);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await c.settled;
      expect(c.cycles, 0);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await c.settled;
      expect(c.cycles, 1);
    });
  });

  group('never in front of an entry save (07 §1)', () {
    test('F1-05-10 onEntrySaved returns before the cycle it starts finishes, '
        'and never throws into the save path', () async {
      final c = client();
      await c.start();
      final gate = Completer<void>();
      device.transport.gate = gate;
      var returned = false;
      c.onEntrySaved();
      returned = true;
      expect(returned, isTrue);
      expect(c.cycles, 0, reason: 'the cycle is still in flight');
      gate.complete();
      device.transport.gate = null;
      await c.settled;
      expect(c.cycles, 1);
    });

    test('F1-05-11 cycles never overlap: calls made while one is in flight '
        'coalesce into a single follow-up round', () async {
      final c = client();
      await c.start();
      final gate = Completer<void>();
      device.transport.gate = gate;
      final first = c.syncNow();
      c.onEntrySaved();
      c.onScopeSwitch();
      c.onRemoteHint(_book);
      gate.complete();
      device.transport.gate = null;
      await first;
      await c.settled;
      expect(c.cycles, 2, reason: 'one in flight + one coalesced follow-up');
    });

    test('F1-05-12 a transport failure never escapes syncNow and never leaves '
        'the surface outside the five states', () async {
      final c = client();
      await c.start();
      device.transport.failWith = StateError('socket exploded');
      await expectLater(c.syncNow(), completes);
      expect(c.lastCycleFailed, isTrue);
      expect(
        c.current,
        anyOf(
          isA<Synced>(),
          isA<SavedWillSync>(),
          isA<Offline>(),
          isA<WaitingFor>(),
          isA<NeedsAttention>(),
        ),
      );
      device.transport.failWith = null;
      await c.syncNow();
      expect(c.lastCycleFailed, isFalse);
    });

    test('F1-05-13 after dispose the timer is cancelled and triggers are '
        'no-ops', () async {
      _FakeTimer? timer;
      final c = client(
        unmetered: () => true,
        timerFactory: (d, f) => timer = _FakeTimer(d, f),
      );
      await c.start();
      await c.dispose();
      expect(timer!.cancelled, isTrue);
      c.onAppForeground();
      await c.settled;
      expect(c.cycles, 0);
    });
  });
}
