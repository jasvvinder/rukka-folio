// Shared helpers for suite D at the engine level: a plaintext device on the
// real data stack (in-memory SQLite) behind a FakeTransport. Test code may use
// non-canonical ids; the crypto tests have their own helpers.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart' show Hlc;
import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:sync_engine/sync_engine.dart';

/// Synthetic ids (never real).
const tenant1 = 't1';
const book1 = 'b1';

/// A plaintext device: data stack + engine over [PlainGuard].
final class PlainDevice {
  PlainDevice._(
    this.id,
    this.userId,
    this.db,
    this.mirror,
    this.transport,
    this.trust,
    this.engine,
  );

  /// Opens a device on [server] as [userId].
  static Future<PlainDevice> open(
    String id, {
    required FakeSyncServer server,
    required ManualClock clock,
    required String userId,
    Set<String> trustedDevices = const {},
    Set<String> books = const {book1},
    Jitter? jitter,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final r = await openLedgerDatabase(NativeDatabase.memory());
    if (r is! Opened) throw StateError('device $id could not open: $r');
    final db = r.db;
    final mirror = Mirror(db, hasher: fnv1a32);
    final transport = server.transportFor(id);
    final trust = RecordTrustStore(umks: const MapUmkSource({}));
    final guard = PlainGuard(trust: trust, trustedDevices: {...trustedDevices});
    final engine = SyncEngine(
      db: db,
      mirror: mirror,
      transport: transport,
      clock: clock,
      guard: guard,
      trust: trust,
      deviceId: id,
      userId: userId,
      tenantId: tenant1,
      jitter: jitter,
    );
    engine.subscribedBooks.addAll(books);
    return PlainDevice._(id, userId, db, mirror, transport, trust, engine);
  }

  final String id;
  final String userId;
  final LedgerDatabase db;
  final Mirror mirror;
  final FakeTransport transport;
  final RecordTrustStore trust;
  final SyncEngine engine;
  Hlc _clock = Hlc.compose(physicalMs: 0, counter: 0);
  int _n = 0;

  /// Authors a plaintext object into the mirror and the outbox.
  Future<EnvelopeRecord> author({
    required int physicalMs,
    String bookId = book1,
    String? objectId,
    String objectType = 'entry',
    Map<String, Object?> object = const {},
    int? hlcOverride,
  }) async {
    final oid = objectId ?? '$id-${_n++}';
    _clock = _clock.tick(physicalMs: physicalMs);
    final seq = await mirror.nextAuthorSeq(bookId, id);
    final blob = Uint8List.fromList(
      utf8.encode(jsonEncode({...object, 'author_seq': seq, 'id': oid})),
    );
    final rec = EnvelopeRecord(
      envelopeId: 'env-$oid',
      bookId: bookId,
      objectId: oid,
      objectType: objectType,
      keyVersion: 1,
      hlc: hlcOverride ?? _clock.raw,
      authorDevice: id,
      authorSeq: seq,
      blob: blob,
      blobHash: fnv1a32(blob),
      verified: true,
    );
    await mirror.append(rec);
    await mirror.enqueue(
      envelopeId: rec.envelopeId,
      bookId: bookId,
      blob: blob,
      createdAt: physicalMs,
    );
    return rec;
  }

  Future<List<EnvelopesLocalData>> rows([String bookId = book1]) =>
      mirror.envelopesOf(bookId);

  Future<EnvelopesLocalData?> row(String envelopeId) => (db.select(
    db.envelopesLocal,
  )..where((t) => t.envelopeId.equals(envelopeId))).getSingleOrNull();

  Future<Map<String, String>> outboxStates() async => {
    for (final r in await mirror.outboxRows()) r.envelopeId: r.pushState,
  };

  Future<void> close() => db.close();
}

/// A record "signed" the PlainGuard way.
WireSignedRecord plainRecord({
  required String id,
  required String kind,
  required String author,
  required Map<String, Object?> payload,
  int hlc = 0,
}) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  return WireSignedRecord(
    id: id,
    suiteVersion: 1,
    tenantId: tenant1,
    kind: kind,
    payloadJson: bytes,
    authorDeviceId: author,
    authorSig: PlainGuard.sign(author, bytes),
    hlc: hlc,
    seq: 0,
  );
}

/// A `devices` row with dummy keys.
WireDevice deviceRow(String id, String userId, {String status = 'active'}) =>
    WireDevice(
      id: id,
      userId: userId,
      pubEd: Uint8List(32),
      pubX: Uint8List(32),
      status: status,
    );

/// Events of type [T].
List<T> eventsOf<T extends SyncEvent>(SyncEngine e) =>
    e.events.whereType<T>().toList();
