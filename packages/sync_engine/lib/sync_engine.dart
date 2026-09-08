/// Sync engine: push/pull with seq cursors, meta/key channel, outbox,
/// signed-record application, revocation cut-off (05; ADR 2026-09-05b,
/// ADR 2026-09-06 §3). M4.
///
/// Spec owner: `docs/05-sync-protocol.md`. Pure Dart — no Flutter, no
/// `DateTime.now()`, no `Random()`, no `dart:io`: the clock is a [Clock] and
/// the network a [SyncTransport], both injected (09 §1), so the two-client
/// harness runs the real engine deterministically.
///
/// Entry points: [SyncEngine] (one device, one tenant), [CryptoGuard] over a
/// [BookKeyStore] + [RecordTrustStore], the wire types of `wire.dart`, the
/// five-state [SyncStatus], typed [SyncEvent]s, and — for tests and the
/// harness — [FakeSyncServer], [FakeTransport], [PlainGuard].
library;

export 'src/backoff.dart';
export 'src/engine.dart';
export 'src/events.dart';
export 'src/guard.dart';
export 'src/key_store.dart';
export 'src/revocation.dart';
export 'src/spki_pins.dart';
export 'src/status.dart';
export 'src/testing.dart';
export 'src/transport.dart';
export 'src/trust.dart';
export 'src/wire.dart';

/// Package identity used by the M0 hello-world gate.
const String packageName = 'sync_engine';
