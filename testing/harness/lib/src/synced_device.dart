// M4: the real sync engine on a SimulatedDevice, talking to the in-memory
// FakeSyncServer through the seeded network (09 §1 "two-client harness").
// Every request is one `Network.decide` (label = route) so drops and offline
// windows replay from the log; the engine's clock is the scheduler's.
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:sync_engine/sync_engine.dart';

import 'device.dart';
import 'network.dart';
import 'scheduler.dart';

/// The scheduler's virtual clock as the engine's [Clock].
final class SchedulerClock implements Clock {
  /// Creates the clock.
  const SchedulerClock(this.scheduler);

  /// The scheduler.
  final Scheduler scheduler;

  @override
  int nowMs() => scheduler.now;
}

/// A [SimulatedDevice] with a [SyncEngine] over a [PlainGuard].
final class SyncedDevice {
  SyncedDevice._(
    this.device,
    this.engine,
    this.transport,
    this.trust,
    this.scheduler,
  );

  /// Opens a device on [server]. Requests route through [network] when given
  /// (a dropped decision → `TransportOffline`; [model]'s offline windows too).
  ///
  /// With [identity] the engine reads who it is from that source at every
  /// round (ADR 2026-10-09 §1) — a phone that registers late, or is re-minted
  /// — and [userId]/[tenantId] are not used; without it the device is
  /// registered from the start as `(id, userId, tenantId)`.
  static Future<SyncedDevice> open(
    String id, {
    required FakeSyncServer server,
    required Scheduler scheduler,
    String? userId,
    DeviceIdentitySource? identity,
    String tenantId = 't1',
    Network? network,
    NetworkModel? model,
    Set<String> books = const {},
    Set<String> trustedDevices = const {},
  }) async {
    if (identity == null && userId == null) {
      throw ArgumentError(
        'a registered device needs a userId, a late one an '
        'identity source',
      );
    }
    final device = await SimulatedDevice.open(id);
    final transport = server.transportFor(id);
    final trust = RecordTrustStore(umks: const MapUmkSource({}));
    final engine = SyncEngine.late(
      db: device.db,
      mirror: device.mirror,
      transport: transport,
      clock: SchedulerClock(scheduler),
      guard: PlainGuard(trust: trust, trustedDevices: {...trustedDevices}),
      trust: trust,
      identity:
          identity ??
          FixedIdentity(
            RegisteredIdentity(
              deviceId: id,
              userId: userId!,
              tenantId: tenantId,
            ),
          ),
      recompute: device.recompute,
    )..subscribedBooks.addAll(books);
    return SyncedDevice._(device, engine, transport, trust, scheduler)
      ..setNetwork(network: network, model: model);
  }

  /// Routes every request through [network] (or [model], whose offline
  /// windows also apply); both null = a lossless line. One `decide` per
  /// request, labelled by route, so a run replays from its log.
  void setNetwork({Network? network, NetworkModel? model}) {
    final net = network ?? model;
    if (net == null) {
      transport.beforeCall = null;
      return;
    }
    transport.beforeCall = (route) {
      if (model != null && model.isOffline(id, scheduler.now)) {
        throw TransportOffline('$id offline window');
      }
      final d = net.decide(
        from: id,
        to: 'server',
        label: route,
        now: scheduler.now,
      );
      if (d.dropped) throw TransportOffline('$id $route dropped');
    };
  }

  /// The data stack.
  final SimulatedDevice device;

  /// The engine.
  final SyncEngine engine;

  /// The line to the server.
  final FakeTransport transport;

  /// Trust state.
  final RecordTrustStore trust;

  /// Virtual clock.
  final Scheduler scheduler;

  /// Device id.
  String get id => device.id;

  Future<void> _enqueue(EnvelopeRecord rec) => device.mirror.enqueue(
    envelopeId: rec.envelopeId,
    bookId: rec.bookId,
    blob: rec.blob,
    createdAt: scheduler.now,
  );

  /// Authors the book's config and chart into the mirror and the outbox.
  Future<List<EnvelopeRecord>> authorSetup(
    BookConfig config,
    Iterable<Account> accounts,
  ) async {
    final recs = await device.authorSetup(
      config,
      accounts,
      physicalMs: scheduler.now,
    );
    for (final r in recs) {
      await _enqueue(r);
    }
    return recs;
  }

  /// Authors a ledger event into the mirror and the outbox.
  Future<EnvelopeRecord> author(LedgerEvent event) async {
    final rec = await device.author(event);
    await _enqueue(rec);
    return rec;
  }

  /// One sync round at the current virtual time.
  Future<SyncReport> sync() => engine.sync();

  /// Closes the database.
  Future<void> close() => device.close();
}
