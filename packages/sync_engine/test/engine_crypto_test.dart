// Suite D — the engine on the real crypto path (04 §8.3, §9.2; ADR 2026-09-06
// §3; 05 §3 re-seal; 05 §4 key_wait). Real libsodium through a seeded
// CryptoSuite; every id is a synthetic canonical uuid.
@Tags(['D'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:sodium/sodium.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

String uuid(int n, [int group = 1]) =>
    '${n.toRadixString(16).padLeft(8, '0')}-000$group-4000-8000-'
    '${n.toRadixString(16).padLeft(12, '0')}';

final tenant = uuid(1, 0);
final book = uuid(2, 0);

RandomBytes _deterministic(Sodium s, int seed) {
  var counter = 0;
  return (int length) {
    final out = Uint8List(length);
    var o = 0;
    while (o < length) {
      final block = s.crypto.genericHash(
        message: Bytes.concat([Bytes.i64be(seed), Bytes.i64be(counter++)]),
        outLen: 32,
      );
      final n = length - o < 32 ? length - o : 32;
      out.setRange(o, o + n, block);
      o += n;
    }
    return out;
  };
}

/// A user with a verified UMK and one device (certified by that UMK).
final class Person {
  Person(this.suite, this.userId, this.deviceId)
    : umk = UmkKeyPair.generate(suite),
      device = DeviceKeyPair.generate(suite, deviceId: deviceId) {
    final r = Ceremony.verifyQr(
      suite,
      scanned: QrPayload(
        userId: userId,
        umk: umk.public,
        nonce: suite.randomBytes(16),
      ),
      relayed: umk.public,
      relayedUserId: userId,
    );
    verified = (r as CeremonyVerified).verified;
    cert = DeviceCert.issue(
      suite,
      issuer: umk,
      userId: userId,
      device: device.public,
      issuedAtMs: 1,
    );
  }
  final CryptoSuite suite;
  final String userId;
  final String deviceId;
  final UmkKeyPair umk;
  final DeviceKeyPair device;
  late final VerifiedUmkPublic verified;
  late final DeviceCert cert;

  WireDevice get row => WireDevice(
    id: deviceId,
    userId: userId,
    pubEd: device.public.ed25519,
    pubX: device.public.x25519,
    status: 'active',
  );

  WireDeviceCert get certRow => WireDeviceCert(
    deviceId: deviceId,
    suiteVersion: cert.suiteVersion,
    issuedAtMs: cert.issuedAtMs,
    signature: cert.signature,
    issuedByDevice: deviceId,
  );

  WireSignedRecord record(
    String id,
    String kind,
    Map<String, Object?> payload, {
    int hlc = 1,
  }) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final r = SignedRecord.sign(
      suite,
      tenantId: tenant,
      kind: kind,
      payloadJson: bytes,
      hlc: hlc,
      author: device,
    );
    return WireSignedRecord(
      id: id,
      suiteVersion: r.suiteVersion,
      tenantId: tenant,
      kind: kind,
      payloadJson: r.payloadJson,
      authorDeviceId: deviceId,
      authorSig: r.authorSig,
      hlc: hlc,
      seq: 0,
    );
  }

  WireEnvelope seal(
    BookKey key, {
    required int n,
    required int authorSeq,
    int hlc = 1 << 16,
  }) {
    final e = EnvelopeBuilder.seal(
      suite,
      tenantId: tenant,
      bookId: book,
      objectId: uuid(n, 5),
      objectType: 'entry',
      envelopeId: uuid(n, 6),
      hlc: hlc,
      authorSeq: authorSeq,
      object: {'kind': 'money_out', 'n': n},
      bookKey: key,
      author: device,
    );
    final blob = e.blob;
    return WireEnvelope(
      envelopeId: e.envelopeId,
      tenantId: tenant,
      bookId: book,
      objectId: e.objectId,
      objectType: e.objectType,
      keyVersion: e.keyVersion,
      suiteVersion: e.suiteVersion,
      payloadSchema: e.payloadSchema,
      authorDevice: deviceId,
      hlc: e.hlc,
      blobHash: suite.blake2b256(blob),
      blob: blob,
    );
  }

  WireSignedRecord revoke(
    String id,
    String revokedDevice,
    String subject, {
    int? version,
  }) => record(id, SignedRecordKind.deviceRevocation, {
    'revoked_device_id': revokedDevice,
    'subject_user_id': subject,
    'share_set_version': ?version,
  });
}

/// A device running the real engine over [CryptoGuard].
final class CryptoDevice {
  CryptoDevice._(
    this.me,
    this.db,
    this.mirror,
    this.keys,
    this.trust,
    this.engine,
  );

  static Future<CryptoDevice> open(
    Person me, {
    required CryptoSuite suite,
    required FakeSyncServer server,
    required Clock clock,
    required Map<String, VerifiedUmkPublic> umks,
    Iterable<BookKey> keys = const [],
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final r = await openLedgerDatabase(NativeDatabase.memory());
    final db = (r as Opened).db;
    final mirror = Mirror(db, hasher: blake2bHasher(suite));
    final store = BookKeyStore(tenantId: tenant);
    for (final k in keys) {
      store.put(k);
    }
    final trust = RecordTrustStore(umks: MapUmkSource(umks));
    final guard = CryptoGuard(
      suite: suite,
      keys: store,
      trust: trust,
      me: me.device,
      umk: me.umk,
    );
    final engine = SyncEngine(
      db: db,
      mirror: mirror,
      transport: server.transportFor(me.deviceId),
      clock: clock,
      guard: guard,
      trust: trust,
      deviceId: me.deviceId,
      userId: me.userId,
      tenantId: tenant,
    )..subscribedBooks.add(book);
    return CryptoDevice._(me, db, mirror, store, trust, engine);
  }

  final Person me;
  final LedgerDatabase db;
  final Mirror mirror;
  final BookKeyStore keys;
  final RecordTrustStore trust;
  final SyncEngine engine;

  Future<EnvelopesLocalData?> row(String id) => (db.select(
    db.envelopesLocal,
  )..where((t) => t.envelopeId.equals(id))).getSingleOrNull();

  Future<Set<String>> quarantined() async => {
    for (final r in await mirror.envelopesOf(book))
      if (r.quarantined == 1) r.envelopeId,
  };

  /// Authors [w] into the mirror (verified) and the outbox.
  Future<void> enqueue(WireEnvelope w, int authorSeq, int createdAt) async {
    await mirror.append(
      EnvelopeRecord(
        envelopeId: w.envelopeId,
        bookId: w.bookId,
        objectId: w.objectId,
        objectType: w.objectType,
        keyVersion: w.keyVersion,
        hlc: w.hlc,
        authorDevice: w.authorDevice,
        authorSeq: authorSeq,
        blob: w.blob,
        blobHash: w.blobHash,
        verified: true,
      ),
    );
    await mirror.enqueue(
      envelopeId: w.envelopeId,
      bookId: w.bookId,
      blob: w.blob,
      createdAt: createdAt,
    );
  }

  Future<void> close() => db.close();
}

BookKey clone(CryptoSuite suite, BookKey k) =>
    BookKey(k.ref, k.key.runUnlockedSync((b) => suite.sodium.secureCopy(b)));

WireWrappedKey wrapFor(CryptoSuite suite, BookKey bk, Person p, String id) {
  final w = wrapBookKey(suite, bk, p.verified);
  return WireWrappedKey(
    id: id,
    kind: WireWrappedKey.kindBkForUser,
    userId: p.userId,
    bookId: bk.ref.bookId,
    keyVersion: bk.ref.keyVersion,
    blob: w.blob,
    recipientFingerprint: w.recipient.bytes,
  );
}

void main() {
  late CryptoSuite suite;
  late ManualClock clock;
  late FakeSyncServer server;
  late Person subject, g1, g2, g3, g4, g5, nobody, reader, reader2;
  late Map<String, VerifiedUmkPublic> umks;
  late BookKey bk1;
  final open = <CryptoDevice>[];

  setUpAll(() async {
    final s = await SodiumInit.init();
    suite = CryptoSuite(s, random: _deterministic(s, 42));
  });

  setUp(() {
    clock = ManualClock(1 << 40);
    server = FakeSyncServer(clock: clock, rateLimits: RateLimits.none);
    subject = Person(suite, uuid(10), uuid(110));
    g1 = Person(suite, uuid(11), uuid(111));
    g2 = Person(suite, uuid(12), uuid(112));
    g3 = Person(suite, uuid(13), uuid(113));
    g4 = Person(suite, uuid(14), uuid(114));
    g5 = Person(suite, uuid(15), uuid(115));
    nobody = Person(suite, uuid(16), uuid(116));
    reader = Person(suite, uuid(17), uuid(117));
    reader2 = Person(suite, uuid(18), uuid(118));
    final all = [subject, g1, g2, g3, g4, g5, nobody, reader, reader2];
    umks = {for (final p in all) p.userId: p.verified};
    for (final p in all) {
      server.devices[p.deviceId] = p.row;
      server.deviceCerts[p.deviceId] = p.certRow;
    }
    bk1 = BookKey.generate(suite, bookId: book, keyVersion: 1);
  });
  tearDown(() async {
    for (final d in open) {
      await d.close();
    }
    open.clear();
  });

  Future<CryptoDevice> readerDevice(Person p, {Iterable<BookKey>? keys}) async {
    final d = await CryptoDevice.open(
      p,
      suite: suite,
      server: server,
      clock: clock,
      umks: umks,
      keys: keys ?? [clone(suite, bk1)],
    );
    open.add(d);
    return d;
  }

  void guardianSet(int version, int k, List<Person> guardians) {
    server.guardianSets.add(
      WireGuardianSet(
        subjectUserId: subject.userId,
        shareSetVersion: version,
        k: k,
        guardianUserIds: [for (final g in guardians) g.userId],
      ),
    );
  }

  int pushAt(int seq, WireEnvelope e) {
    server.skipSeqTo(seq);
    final r = server.push(subject.deviceId, PushRequest(envelopes: [e]));
    expect(r.results.single.result, PushOutcome.acked);
    expect(r.results.single.seq, seq);
    return seq;
  }

  WireSignedRecord recordAt(int seq, WireSignedRecord r) {
    server.skipSeqTo(seq);
    final stamped = server.addSignedRecord(r);
    expect(stamped.seq, seq);
    return stamped;
  }

  test(
    'D-06a-1 k-th record\'s seq is the cut-off: 2-of-3, approvals at seq 10 '
    'and 14 → the device\'s envelope at seq 12 is valid, seq 15 quarantined',
    () async {
      guardianSet(3, 2, [g1, g2, g3]);
      recordAt(
        10,
        g1.revoke('r-g1', subject.deviceId, subject.userId, version: 3),
      );
      final e12 = subject.seal(bk1, n: 12, authorSeq: 1);
      pushAt(12, e12);
      recordAt(
        14,
        g2.revoke('r-g2', subject.deviceId, subject.userId, version: 3),
      );
      final e15 = subject.seal(bk1, n: 15, authorSeq: 2);
      pushAt(15, e15);

      final r = await readerDevice(reader);
      final rep = await r.engine.sync();
      expect(rep.pulled, 2);
      expect(r.trust.revocationSeqOf(subject.deviceId), 14);
      expect(r.trust.countFor(subject.deviceId).countedGuardians, 2);
      expect((await r.row(e12.envelopeId))!.verified, 1);
      expect((await r.row(e12.envelopeId))!.authorSeq, 1);
      final q = (await r.row(e15.envelopeId))!;
      expect(q.quarantined, 1);
      expect(q.quarantineReason, 'revoked');
      final cut = r.engine.events.whereType<CutoffChanged>().single;
      expect((cut.previousSeq, cut.seq), (null, 14));
    },
  );

  test('D-06a-2 cut-off moves earlier, never later: a third approval arrives '
      'with seq 8 → cut-off 10; seq 12 is quarantined on Recompute; a client '
      'with the opposite arrival order agrees', () async {
    guardianSet(3, 2, [g1, g2, g3]);
    final late = recordAt(
      8,
      g3.revoke('r-g3', subject.deviceId, subject.userId, version: 3),
    );
    server.withheldRecords.add(late.id);
    recordAt(
      10,
      g1.revoke('r-g1', subject.deviceId, subject.userId, version: 3),
    );
    final e12 = subject.seal(bk1, n: 12, authorSeq: 1);
    pushAt(12, e12);
    recordAt(
      14,
      g2.revoke('r-g2', subject.deviceId, subject.userId, version: 3),
    );
    final e15 = subject.seal(bk1, n: 15, authorSeq: 2);
    pushAt(15, e15);

    final a = await readerDevice(reader);
    await a.engine.sync();
    expect(a.trust.revocationSeqOf(subject.deviceId), 14);
    expect(await a.quarantined(), {e15.envelopeId});

    server.withheldRecords.clear();
    server.touchMeta();
    await a.engine.sync();
    expect(a.trust.revocationSeqOf(subject.deviceId), 10);
    expect(await a.quarantined(), {e12.envelopeId, e15.envelopeId});
    final cuts = a.engine.events.whereType<CutoffChanged>().toList();
    expect(cuts.map((c) => (c.previousSeq, c.seq)), [(null, 14), (14, 10)]);

    final b = await readerDevice(reader2);
    await b.engine.sync();
    expect(b.trust.revocationSeqOf(subject.deviceId), 10);
    expect(await b.quarantined(), await a.quarantined());
  });

  test('D-06a-3 re-split does not reset: one approval at version 3; the device '
      'bumps to version 4 (k raised to 3); a second approval naming 4 counts '
      'and the earliest version\'s k applies → revocation effective', () async {
    guardianSet(3, 2, [g1, g2, g3]);
    guardianSet(4, 3, [g2, g3, g4, g5]);
    recordAt(
      10,
      g1.revoke('r-g1', subject.deviceId, subject.userId, version: 3),
    );
    final eMid = subject.seal(bk1, n: 12, authorSeq: 1);
    pushAt(12, eMid);
    recordAt(
      14,
      g2.revoke('r-g2', subject.deviceId, subject.userId, version: 4),
    );
    final eAfter = subject.seal(bk1, n: 15, authorSeq: 2);
    pushAt(15, eAfter);

    final r = await readerDevice(reader);
    await r.engine.sync();
    final count = r.trust.countFor(subject.deviceId);
    expect(count.countedGuardians, 2);
    expect(count.threshold, 2, reason: 'k of the earliest counted version');
    expect(count.effectiveSeq, 14);
    expect(await r.quarantined(), {eAfter.envelopeId});
  });

  test('D-06a-4 a removed guardian\'s approval stands; a non-guardian\'s does '
      'not: a guardian dropped in the bump still counts; a record from a '
      'never-guardian UMK is ignored and logged', () async {
    guardianSet(3, 2, [g1, g2, g3]);
    guardianSet(4, 2, [g2, g3, g4]);
    recordAt(
      10,
      nobody.revoke('r-nobody', subject.deviceId, subject.userId, version: 4),
    );
    recordAt(
      11,
      g1.revoke('r-g1', subject.deviceId, subject.userId, version: 3),
    );
    final e12 = subject.seal(bk1, n: 12, authorSeq: 1);
    pushAt(12, e12);

    final r = await readerDevice(reader);
    await r.engine.sync();
    var count = r.trust.countFor(subject.deviceId);
    expect(count.effectiveSeq, isNull, reason: '1 of 2 — not effective');
    expect(count.countedGuardians, 1);
    expect(count.ignored.map((i) => (i.recordId, i.reason)), [
      ('r-nobody', IgnoreReason.notGuardian),
    ]);
    final ignored = r.engine.events.whereType<RecordIgnored>().single;
    expect((ignored.recordId, ignored.reason), ('r-nobody', 'notGuardian'));
    expect((await r.row(e12.envelopeId))!.verified, 1);

    recordAt(
      14,
      g2.revoke('r-g2', subject.deviceId, subject.userId, version: 4),
    );
    final e15 = subject.seal(bk1, n: 15, authorSeq: 2);
    pushAt(15, e15);
    server.touchMeta();
    await r.engine.sync();
    count = r.trust.countFor(subject.deviceId);
    expect(count.effectiveSeq, 14);
    expect(count.countedGuardians, 2);
    expect(await r.quarantined(), {e15.envelopeId});
  });

  test('D-05-11 rotation across the offline window: key sync completes first, '
      'the queued envelope is re-sealed under BK(v+1) with envelope_id/object_id/'
      'hlc byte-identical, acked once, read by a v2 reader, and unreadable '
      'under BK(v)', () async {
    final author = await readerDevice(subject);
    final w1 = subject.seal(bk1, n: 1, authorSeq: 1, hlc: 777 << 16);
    await author.enqueue(w1, 1, clock.nowMs());
    final bk2 = BookKey.generate(suite, bookId: book, keyVersion: 2);
    server.wrappedKeys.add(wrapFor(suite, bk2, subject, 'wk-s-2'));
    server.addSignedRecord(
      g1.record('rot-2', SignedRecordKind.keyRotation, {
        'book_id': book,
        'key_version': 2,
      }),
    );

    final rep = await author.engine.sync();
    expect(rep.acked, 1);
    expect(author.engine.announcedKeyVersion(book), 2);
    final resealed = author.engine.events.whereType<Resealed>().single;
    expect((resealed.fromVersion, resealed.toVersion), (1, 2));
    final stored = server.stored.single;
    expect(stored.keyVersion, 2);
    expect(stored.envelopeId, w1.envelopeId);
    expect(stored.objectId, w1.objectId);
    expect(stored.hlc, w1.hlc);
    expect(stored.blob, isNot(w1.blob));
    expect(await author.mirror.outboxRows(), isEmpty, reason: 'observed');

    // A reader holding v2 only verifies and reads it.
    final r2 = await readerDevice(reader, keys: [clone(suite, bk2)]);
    final rr = await r2.engine.sync();
    expect(rr.verified, 1);
    expect((await r2.row(w1.envelopeId))!.authorSeq, 1);

    // Zero envelopes readable under BK(v): the stored copy refuses v1.
    final env = Envelope.fromParts(
      suiteVersion: stored.suiteVersion,
      tenantId: tenant,
      bookId: book,
      objectId: stored.objectId,
      objectType: stored.objectType,
      keyVersion: stored.keyVersion,
      payloadSchema: stored.payloadSchema,
      authorDeviceId: stored.authorDevice,
      hlc: stored.hlc,
      envelopeId: stored.envelopeId,
      blob: stored.blob,
    );
    expect(() => env.open(suite, bk1), throwsA(isA<EnvelopeOpenFailed>()));
    expect(env.open(suite, bk2).authorSeq, 1);
  });

  test(
    'D-05-12 key-later: an envelope pulled before its key sits in key_wait '
    '(cursor held back, nothing surfaced under 24 h); the wrapped key '
    'arrives via meta → verified; a key_version_stale rejection re-seals on '
    'the single permitted retry once the new key lands, yielding one row',
    () async {
      final bk2 = BookKey.generate(suite, bookId: book, keyVersion: 2);
      pushAt(5, subject.seal(bk2, n: 5, authorSeq: 1));
      final c = await readerDevice(reader); // holds v1 only
      var rep = await c.engine.sync();
      expect(rep.keyWait, 1);
      expect(c.engine.keyWaiting, {uuid(5, 6)});
      expect(await c.row(uuid(5, 6)), isNull, reason: 'not in the mirror yet');
      expect(await c.engine.status(), const Synced(), reason: 'no user noise');
      clock.advance(24 * 60 * 60 * 1000 + 60 * 1000);
      expect(
        await c.engine.status(),
        const NeedsAttention([AttentionReason.keyWaitOverdue]),
      );
      server.wrappedKeys.add(wrapFor(suite, bk2, reader, 'wk-r-2'));
      server.touchMeta();
      rep = await c.engine.sync();
      expect(rep.keyWait, 0);
      expect((await c.row(uuid(5, 6)))!.verified, 1);
      expect(await c.engine.status(), const Synced());

      // Grace window closed: the author still on v1 gets key_version_stale.
      final author = await readerDevice(subject);
      final w = subject.seal(bk1, n: 7, authorSeq: 1);
      await author.enqueue(w, 1, clock.nowMs());
      server.minKeyVersion[book] = 2;
      rep = await author.engine.sync();
      expect(rep.acked, 0);
      expect(
        author.engine.events.whereType<PushRejected>().single.result,
        PushOutcome.rejectedKeyVersionStale,
      );
      expect(
        (await author.mirror.outboxRows()).single.pushState,
        PushState.rejected.name,
      );
      server.wrappedKeys.add(wrapFor(suite, bk2, subject, 'wk-s-2'));
      server.touchMeta();
      rep = await author.engine.sync();
      expect(rep.acked, 1);
      expect(
        server.stored.where((e) => e.envelopeId == w.envelopeId).length,
        1,
      );
      expect(server.stored.last.keyVersion, 2);
      expect(await author.mirror.outboxRows(), isEmpty);
    },
  );
}
