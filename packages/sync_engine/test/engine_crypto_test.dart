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

/// A second tenant the subject and some guardians also belong to (ADR
/// 2026-10-03b §2: approvals filed here never count for a set of [tenant]).
final otherTenant = uuid(3, 0);

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

  /// A record signed by this device and filed in [tenantId] (default: the
  /// test's [tenant]). The tenant is inside the signed bytes (04 §3.3), so
  /// where a record is filed is the author's claim, not the server's.
  WireSignedRecord record(
    String id,
    String kind,
    Map<String, Object?> payload, {
    int hlc = 1,
    String? tenantId,
  }) {
    final filedIn = tenantId ?? tenant;
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final r = SignedRecord.sign(
      suite,
      tenantId: filedIn,
      kind: kind,
      payloadJson: bytes,
      hlc: hlc,
      author: device,
    );
    return WireSignedRecord(
      id: id,
      suiteVersion: r.suiteVersion,
      tenantId: filedIn,
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
    String? tenantId,
  }) => record(id, SignedRecordKind.deviceRevocation, {
    'revoked_device_id': revokedDevice,
    'subject_user_id': subject,
    'share_set_version': ?version,
  }, tenantId: tenantId);
}

/// Where the app persists a key accepted on the meta channel (03 §3.1
/// `key_cache`; in the app it is `LocalLedger`). Here it only records, so a
/// test can say exactly what the seam was handed and how often.
final class RecordingKeySink implements AcceptedKeySink {
  /// What reached the seam, in order.
  final List<AcceptedBookKey> accepted = [];

  @override
  Future<void> keyAccepted(AcceptedBookKey key) async => accepted.add(key);
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
    this.sink,
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
    final sink = RecordingKeySink();
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
      keySink: sink,
    )..subscribedBooks.add(book);
    return CryptoDevice._(me, db, mirror, store, trust, engine, sink);
  }

  final Person me;
  final LedgerDatabase db;
  final Mirror mirror;
  final BookKeyStore keys;
  final RecordTrustStore trust;
  final SyncEngine engine;

  /// The persistence seam this device's engine hands accepted keys to.
  final RecordingKeySink sink;

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

  /// Publishes a guardian-set version. Every set belongs to the tenant it was
  /// set up in (ADR 2026-10-03b §1) — [tenant] unless [inTenant] says
  /// otherwise; [noTenant] is a set published before that ADR.
  void guardianSet(
    int version,
    int k,
    List<Person> guardians, {
    String? inTenant,
    bool noTenant = false,
  }) {
    server.guardianSets.add(
      WireGuardianSet(
        subjectUserId: subject.userId,
        shareSetVersion: version,
        k: k,
        guardianUserIds: [for (final g in guardians) g.userId],
        tenantId: noTenant ? null : (inTenant ?? tenant),
      ),
    );
  }

  /// Registers [id] as another device of [owner] — a `devices` row only,
  /// which is what a reader binds a revocation's `subject_user_id` to
  /// (`RecordTrustStore.userOf`).
  void extraDevice(String id, Person owner) {
    server.devices[id] = WireDevice(
      id: id,
      userId: owner.userId,
      pubEd: owner.device.public.ed25519,
      pubX: owner.device.public.x25519,
      status: 'active',
    );
  }

  int pushAt(int seq, WireEnvelope e, {Person? by}) {
    server.skipSeqTo(seq);
    final r = server.push(
      (by ?? subject).deviceId,
      PushRequest(envelopes: [e]),
    );
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

  // ── ADR 2026-10-03b §2: a set belongs to a tenant; only approvals filed
  // there count. Everything else in ADR 2026-09-06 §3 is unchanged. ────────

  test('D-03b-1 a guardian approval filed outside the set\'s tenant is '
      'ignored as wrongTenant and does not complete; it does not shadow the '
      'same guardian\'s later approval filed in the set\'s tenant, which '
      'completes at its own seq; a set with no tenant counts nothing; the '
      'owner\'s own-device record is unaffected', () async {
    guardianSet(3, 2, [g1, g2, g3]);
    // The owner's own-device record (04 §9.2) names no set: it is effective
    // alone at its seq wherever the owner filed it — ADR 2026-10-03b leaves
    // that path alone. (Seq 5: the authoring device is itself revoked at 16
    // below, and a revoked device authors nothing after its cut-off.)
    final other = uuid(119); // a second device of the subject
    extraDevice(other, subject);
    recordAt(
      5,
      subject.revoke('r-own', other, subject.userId, tenantId: otherTenant),
    );
    recordAt(
      10,
      g1.revoke('r-g1', subject.deviceId, subject.userId, version: 3),
    );
    recordAt(
      13,
      g2.revoke(
        'r-g2-elsewhere',
        subject.deviceId,
        subject.userId,
        version: 3,
        tenantId: otherTenant,
      ),
    );
    final e14 = subject.seal(bk1, n: 14, authorSeq: 1);
    pushAt(14, e14);

    final r = await readerDevice(reader);
    await r.engine.sync();
    var count = r.trust.countFor(subject.deviceId);
    expect(count.countedGuardians, 1);
    expect(count.effectiveSeq, isNull, reason: '1 of 2 counted — not done');
    expect(r.trust.revocationSeqOf(subject.deviceId), isNull);
    expect(count.ignored.map((i) => (i.recordId, i.reason)), [
      ('r-g2-elsewhere', IgnoreReason.wrongTenant),
    ]);
    final ignored = r.engine.events.whereType<RecordIgnored>().single;
    expect(
      (ignored.recordId, ignored.reason),
      ('r-g2-elsewhere', 'wrongTenant'),
    );
    expect((await r.row(e14.envelopeId))!.verified, 1);
    expect(await r.quarantined(), isEmpty);
    expect(r.trust.countFor(other).ownerSeq, 5);
    expect(r.trust.revocationSeqOf(other), 5);

    // The same guardian files again, in the set's tenant: it counts, and the
    // cut-off is ITS seq (16), never the out-of-tenant one's (13).
    recordAt(
      16,
      g2.revoke('r-g2', subject.deviceId, subject.userId, version: 3),
    );
    final e17 = subject.seal(bk1, n: 17, authorSeq: 2);
    pushAt(17, e17);
    server.touchMeta();
    await r.engine.sync();
    count = r.trust.countFor(subject.deviceId);
    expect(count.countedGuardians, 2);
    expect(count.effectiveSeq, 16);
    expect(await r.quarantined(), {e17.envelopeId});

    // A set published before the ADR (no tenant) recovers but cannot revoke:
    // k approvals naming it, filed where the subject is, count nothing.
    final third = uuid(120); // a third device of the subject
    extraDevice(third, subject);
    guardianSet(5, 2, [g4, g5], noTenant: true);
    recordAt(20, g4.revoke('r-g4', third, subject.userId, version: 5));
    recordAt(21, g5.revoke('r-g5', third, subject.userId, version: 5));
    server.touchMeta();
    await r.engine.sync();
    final none = r.trust.countFor(third);
    expect(none.countedGuardians, 0);
    expect(none.effectiveSeq, isNull);
    expect(none.threshold, isNull);
    expect(none.ignored.map((i) => (i.recordId, i.reason)), [
      ('r-g4', IgnoreReason.setHasNoTenant),
      ('r-g5', IgnoreReason.setHasNoTenant),
    ]);
    expect(
      r.engine.events
          .whereType<RecordIgnored>()
          .where((e) => e.reason == 'setHasNoTenant')
          .map((e) => e.recordId),
      ['r-g4', 'r-g5'],
    );
  });

  test('D-03b-2 a reader active in two tenants reaches the same count as a '
      'reader only in the set\'s tenant: guardians who share two tenants with '
      'the subject and file one approval in each do not complete; k filed in '
      'the set\'s tenant do', () async {
    guardianSet(3, 2, [g1, g2, g3]);
    recordAt(
      10,
      g1.revoke('r-g1', subject.deviceId, subject.userId, version: 3),
    );
    final split = recordAt(
      12,
      g2.revoke(
        'r-g2-elsewhere',
        subject.deviceId,
        subject.userId,
        version: 3,
        tenantId: otherTenant,
      ),
    );
    final e13 = subject.seal(bk1, n: 13, authorSeq: 1);
    pushAt(13, e13);

    // `both` is a member of both tenants and pulls both tenants' records;
    // `one` is only in the set's tenant, so RLS never shows it the other.
    final both = await readerDevice(reader);
    await both.engine.sync();
    server.withheldRecords.add(split.id);
    server.touchMeta();
    final one = await readerDevice(reader2);
    await one.engine.sync();

    for (final d in [both, one]) {
      final c = d.trust.countFor(subject.deviceId);
      expect(c.countedGuardians, 1, reason: d.me.userId);
      expect(c.effectiveSeq, isNull, reason: d.me.userId);
      expect(await d.quarantined(), isEmpty, reason: d.me.userId);
    }
    expect(
      both.trust.countFor(subject.deviceId).ignored.single.reason,
      IgnoreReason.wrongTenant,
    );

    // The second guardian files in the set's tenant: both readers complete,
    // at the same seq, and quarantine the same envelopes.
    recordAt(
      15,
      g2.revoke('r-g2', subject.deviceId, subject.userId, version: 3),
    );
    final e16 = subject.seal(bk1, n: 16, authorSeq: 2);
    pushAt(16, e16);
    server.touchMeta();
    await both.engine.sync();
    await one.engine.sync();
    for (final d in [both, one]) {
      expect(d.trust.revocationSeqOf(subject.deviceId), 15);
      expect(d.trust.countFor(subject.deviceId).countedGuardians, 2);
      expect(await d.quarantined(), {e16.envelopeId});
    }
  });

  test('D-03b-3 a re-split that moves the set to another tenant: an approval '
      'for the earlier version counts only if filed in that version\'s '
      'tenant and carries across; earliest-k holds and the cut-off only '
      'moves earlier', () async {
    guardianSet(3, 2, [g1, g2, g3]); // set up in `tenant`
    guardianSet(4, 3, [g2, g3, g4, g5], inTenant: otherTenant);
    // g1 approves v3 in v4's tenant — wrong for v3 — and again in v3's.
    recordAt(
      9,
      g1.revoke(
        'r-g1-v3-other',
        subject.deviceId,
        subject.userId,
        version: 3,
        tenantId: otherTenant,
      ),
    );
    final g1v3 = recordAt(
      10,
      g1.revoke('r-g1-v3', subject.deviceId, subject.userId, version: 3),
    );
    // g2 approves v4 in v4's tenant (late-arriving, low seq) and in v3's.
    final g2v4 = recordAt(
      11,
      g2.revoke(
        'r-g2-v4',
        subject.deviceId,
        subject.userId,
        version: 4,
        tenantId: otherTenant,
      ),
    );
    final e12 = subject.seal(bk1, n: 12, authorSeq: 1);
    pushAt(12, e12);
    recordAt(
      14,
      g2.revoke('r-g2-v4-here', subject.deviceId, subject.userId, version: 4),
    );
    recordAt(
      16,
      g3.revoke(
        'r-g3-v4',
        subject.deviceId,
        subject.userId,
        version: 4,
        tenantId: otherTenant,
      ),
    );
    final e17 = subject.seal(bk1, n: 17, authorSeq: 2);
    pushAt(17, e17);
    server.withheldRecords.addAll([g1v3.id, g2v4.id]);

    // Only g3's v4 approval counts: the threshold is v4's k (3), not done.
    final a = await readerDevice(reader);
    await a.engine.sync();
    var c = a.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 1);
    expect(c.threshold, 3);
    expect(c.effectiveSeq, isNull);
    expect(c.ignored.map((i) => (i.recordId, i.reason)), [
      ('r-g1-v3-other', IgnoreReason.wrongTenant),
      ('r-g2-v4-here', IgnoreReason.wrongTenant),
    ]);
    expect(await a.quarantined(), isEmpty);

    // g1's v3 approval filed in v3's tenant arrives: it carries across the
    // re-split, earliest-k applies (v3's k = 2) → effective at 16.
    server.withheldRecords.remove(g1v3.id);
    server.touchMeta();
    await a.engine.sync();
    c = a.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 2);
    expect(c.threshold, 2, reason: 'k of the earliest counted version');
    expect(c.effectiveSeq, 16);
    expect(await a.quarantined(), {e17.envelopeId});

    // g2's v4 approval in v4's tenant, seq 11, arrives late: the cut-off
    // moves earlier to 11 and seq 12 is re-quarantined.
    server.withheldRecords.clear();
    server.touchMeta();
    await a.engine.sync();
    c = a.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 3);
    expect(c.threshold, 2);
    expect(c.effectiveSeq, 11);
    expect(await a.quarantined(), {e12.envelopeId, e17.envelopeId});
    final cuts = a.engine.events.whereType<CutoffChanged>().toList();
    expect(cuts.map((x) => (x.previousSeq, x.seq)), [(null, 16), (16, 11)]);

    // A reader that sees everything at once agrees.
    final b = await readerDevice(reader2);
    await b.engine.sync();
    expect(b.trust.revocationSeqOf(subject.deviceId), 11);
    expect(await b.quarantined(), await a.quarantined());
  });

  test('D-03b-4 a device_revocation counts only when its subject owns the '
      'revoked device: a co-member naming itself as subject (the owner '
      'path), and k guardians of that co-member naming another user\'s '
      'device, are ignored as notSubjectsDevice by every reader; the '
      'device\'s own engine does not wipe, even when the server relabels the '
      'device as the author\'s', () async {
    // The server refuses this shape (records.ts rejected:shape; 0026
    // rf.revocation_approvals joins on the device's owner) but stores and
    // serves it to every active member of the tenant.
    final victim = reader2;
    server.guardianSets.add(
      WireGuardianSet(
        subjectUserId: nobody.userId,
        shareSetVersion: 1,
        k: 2,
        guardianUserIds: [g1.userId, g2.userId],
        tenantId: tenant,
      ),
    );
    recordAt(5, nobody.revoke('r-self-claim', victim.deviceId, nobody.userId));
    recordAt(
      6,
      g1.revoke('r-g1-wrong', victim.deviceId, nobody.userId, version: 1),
    );
    recordAt(
      7,
      g2.revoke('r-g2-wrong', victim.deviceId, nobody.userId, version: 1),
    );
    final e8 = victim.seal(bk1, n: 8, authorSeq: 1);
    pushAt(8, e8, by: victim);

    final r = await readerDevice(reader);
    await r.engine.sync();
    final count = r.trust.countFor(victim.deviceId);
    expect(count.ownerSeq, isNull);
    expect(count.countedGuardians, 0);
    expect(count.threshold, isNull);
    expect(count.effectiveSeq, isNull);
    expect(count.ignored.map((i) => (i.recordId, i.reason)), [
      ('r-self-claim', IgnoreReason.notSubjectsDevice),
      ('r-g1-wrong', IgnoreReason.notSubjectsDevice),
      ('r-g2-wrong', IgnoreReason.notSubjectsDevice),
    ]);
    expect(
      r.engine.events.whereType<RecordIgnored>().map(
        (e) => (e.recordId, e.reason),
      ),
      [
        ('r-self-claim', 'notSubjectsDevice'),
        ('r-g1-wrong', 'notSubjectsDevice'),
        ('r-g2-wrong', 'notSubjectsDevice'),
      ],
    );
    expect(r.trust.revocationSeqOf(victim.deviceId), isNull);
    expect((await r.row(e8.envelopeId))!.verified, 1);
    expect(await r.quarantined(), isEmpty);

    // The victim's own engine: not about it, nothing wiped.
    final own = await readerDevice(victim);
    await own.engine.sync();
    expect(own.engine.mode, EngineMode.active);
    expect(own.engine.events.whereType<Wiped>(), isEmpty);

    // A server that relabels the victim's device as the attacker's: a reader
    // believes the row, but the device's own engine binds itself to its own
    // user, never to the server's claim — still no wipe.
    server.devices[victim.deviceId] = WireDevice(
      id: victim.deviceId,
      userId: nobody.userId,
      pubEd: victim.device.public.ed25519,
      pubX: victim.device.public.x25519,
      status: 'active',
    );
    server.touchMeta();
    final relabelled = await readerDevice(victim);
    await relabelled.engine.sync();
    expect(relabelled.trust.userOf(victim.deviceId), nobody.userId);
    expect(relabelled.engine.mode, isNot(EngineMode.wiped));
    expect(relabelled.engine.events.whereType<Wiped>(), isEmpty);
  });

  test('D-03b-5 an approval counts only while the subject holds a membership '
      'other than removed in the tenant it was filed in, judged at the '
      'approval\'s seq: approvals filed while the subject is removed never '
      'count, not after re-admission either, so the subject\'s own device '
      'does not wipe on them; a removal in another tenant changes nothing; '
      'approvals filed after re-admission count; a later removal does not '
      'move the cut-off later', () async {
    guardianSet(3, 2, [g1, g2, g3]);
    // Filed by g4 as the tenant's admin; the client does not judge admin
    // authority (⚠️ SPEC in revocation.dart, MembershipFact).
    WireSignedRecord status(String id, String to, {String? tenantId}) =>
        g4.record(id, SignedRecordKind.membershipStatus, {
          'user_id': subject.userId,
          'status': to,
        }, tenantId: tenantId);
    recordAt(5, status('m-out', 'removed'));
    recordAt(
      10,
      g1.revoke('r-g1-while-out', subject.deviceId, subject.userId, version: 3),
    );
    recordAt(
      11,
      g2.revoke('r-g2-while-out', subject.deviceId, subject.userId, version: 3),
    );
    recordAt(12, status('m-back', 'invited'));
    recordAt(13, status('m-out-elsewhere', 'removed', tenantId: otherTenant));
    final e14 = subject.seal(bk1, n: 14, authorSeq: 1);
    pushAt(14, e14);

    final r = await readerDevice(reader);
    await r.engine.sync();
    var c = r.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 0);
    expect(c.effectiveSeq, isNull);
    expect(c.ignored.map((i) => (i.recordId, i.reason)), [
      ('r-g1-while-out', IgnoreReason.subjectRemoved),
      ('r-g2-while-out', IgnoreReason.subjectRemoved),
    ]);
    expect(await r.quarantined(), isEmpty);

    // The subject's own device pulls the stored approvals past its
    // re-admission: k of them, none counted, nothing wiped.
    final own = await readerDevice(subject);
    await own.engine.sync();
    expect(own.trust.countFor(subject.deviceId).effectiveSeq, isNull);
    expect(own.engine.mode, EngineMode.active);
    expect(own.engine.events.whereType<Wiped>(), isEmpty);

    // After re-admission (the removal at 13 is another tenant's): g3 and g1
    // file again and both count — g1's earlier approval never counted, so it
    // does not shadow its later one. A removal after them does not un-count
    // them: the cut-off only moves earlier (ADR 2026-09-06 §3).
    recordAt(
      15,
      g3.revoke('r-g3', subject.deviceId, subject.userId, version: 3),
    );
    recordAt(
      16,
      g1.revoke('r-g1', subject.deviceId, subject.userId, version: 3),
    );
    final e17 = subject.seal(bk1, n: 17, authorSeq: 2);
    pushAt(17, e17);
    recordAt(18, status('m-out-again', 'removed'));
    server.touchMeta();
    await r.engine.sync();
    c = r.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 2);
    expect(c.threshold, 2);
    expect(c.effectiveSeq, 16);
    expect(r.trust.revocationSeqOf(subject.deviceId), 16);
    expect(await r.quarantined(), {e17.envelopeId});

    await own.engine.sync();
    expect(own.engine.mode, EngineMode.wiped);
    expect(own.engine.events.whereType<Wiped>().single.recordId, 'r-g1');
  });

  test('D-03b-6 the threshold is the k of the earliest version any valid '
      'approval names, not only each guardian\'s first: g1 names v4 (k 3) at '
      '10 and v3 (k 2) at 20, g2 names v4 at 30 → k 2, effective at 30, as '
      'the server\'s tally counts; a reader without g1\'s v3 approval applies '
      'k 3 and completes when it arrives', () async {
    guardianSet(3, 2, [g1, g2, g3]);
    guardianSet(4, 3, [g1, g2, g3, g4]);
    recordAt(
      10,
      g1.revoke('r-g1-v4', subject.deviceId, subject.userId, version: 4),
    );
    final g1v3 = recordAt(
      20,
      g1.revoke('r-g1-v3', subject.deviceId, subject.userId, version: 3),
    );
    final e25 = subject.seal(bk1, n: 25, authorSeq: 1);
    pushAt(25, e25);
    recordAt(
      30,
      g2.revoke('r-g2-v4', subject.deviceId, subject.userId, version: 4),
    );
    final e35 = subject.seal(bk1, n: 35, authorSeq: 2);
    pushAt(35, e35);
    server.withheldRecords.add(g1v3.id);

    final a = await readerDevice(reader);
    await a.engine.sync();
    var c = a.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 2);
    expect(c.threshold, 3);
    expect(c.effectiveSeq, isNull);
    expect(await a.quarantined(), isEmpty);

    server.withheldRecords.clear();
    server.touchMeta();
    await a.engine.sync();
    c = a.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 2);
    expect(c.threshold, 2, reason: 'v3 is the earliest version named');
    expect(c.effectiveSeq, 30);
    expect(c.ignored.map((i) => (i.recordId, i.reason)), [
      ('r-g1-v3', IgnoreReason.duplicateAuthor),
    ]);
    expect(await a.quarantined(), {e35.envelopeId});

    final b = await readerDevice(reader2);
    await b.engine.sync();
    expect(b.trust.revocationSeqOf(subject.deviceId), 30);
    expect(await b.quarantined(), await a.quarantined());
  });

  test('D-03b-7 a membership fact that arrives after the approvals it bears '
      'on is applied to them: the subject\'s re-admission, withheld while k '
      'approvals filed after it arrive, completes the count when it lands, '
      'and the subject\'s own device wipes on it', () async {
    guardianSet(3, 2, [g1, g2, g3]);
    WireSignedRecord status(String id, String to) => g4.record(
      id,
      SignedRecordKind.membershipStatus,
      {'user_id': subject.userId, 'status': to},
    );
    recordAt(5, status('m-out', 'removed'));
    final back = recordAt(8, status('m-back', 'joined_pending_verification'));
    recordAt(
      10,
      g1.revoke('r-g1', subject.deviceId, subject.userId, version: 3),
    );
    recordAt(
      11,
      g2.revoke('r-g2', subject.deviceId, subject.userId, version: 3),
    );
    server.withheldRecords.add(back.id);

    final own = await readerDevice(subject);
    await own.engine.sync();
    var c = own.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 0, reason: 'removed as far as it knows');
    expect(own.engine.mode, EngineMode.active);

    server.withheldRecords.clear();
    server.touchMeta();
    await own.engine.sync();
    c = own.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 2);
    expect(c.effectiveSeq, 11);
    expect(own.engine.mode, EngineMode.wiped);
    expect(own.engine.events.whereType<Wiped>().single.recordId, 'm-back');
  });

  test('D-03b-8 a member_removal is a membership fact too: an approval filed '
      'before the subject\'s removal from the set\'s tenant counts, one filed '
      'after it is ignored as subjectRemoved; the removal stays its own '
      'cut-off (ADR 2026-09-05b §5)', () async {
    guardianSet(3, 2, [g1, g2, g3]);
    recordAt(
      10,
      g1.revoke('r-g1', subject.deviceId, subject.userId, version: 3),
    );
    recordAt(
      12,
      g4.record('rm', SignedRecordKind.memberRemoval, {
        'user_id': subject.userId,
      }),
    );
    recordAt(
      14,
      g2.revoke('r-g2', subject.deviceId, subject.userId, version: 3),
    );

    final r = await readerDevice(reader);
    await r.engine.sync();
    final c = r.trust.countFor(subject.deviceId);
    expect(c.countedGuardians, 1);
    expect(c.effectiveSeq, isNull);
    expect(c.ignored.map((i) => (i.recordId, i.reason)), [
      ('r-g2', IgnoreReason.subjectRemoved),
    ]);
    expect(r.trust.revocationSeqOf(subject.deviceId), 12);
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

  // 05 §5 + 03 §3.1: a key accepted on the meta channel must reach
  // `key_cache`, or the device holds it only until the process dies and the
  // meta cursor has already passed the row — permanent `key_wait` on the
  // second launch (16 Sep finding). The engine writes no key itself: it hands
  // the at-rest material to the sink, which is the ledger in the app.
  test('D-05-40 a wrapped key accepted on the meta channel reaches the '
      'persistence seam exactly once, as the wire blob and its own recipient '
      "— wrapped to this user's UMK, never re-wrapped (04 §8.2 🔒), never "
      'unwrapped at rest (03 §3.1)', () async {
    final bk2 = BookKey.generate(suite, bookId: book, keyVersion: 2);
    final wire = wrapFor(suite, bk2, reader, 'wk-r-2');
    server.wrappedKeys.add(wire);
    final c = await readerDevice(reader); // holds v1 only
    await c.engine.sync();

    final handed = c.sink.accepted.single;
    expect(handed.ref, BookKeyRef(bookId: book, keyVersion: 2));
    expect(handed.sealed, wire.blob, reason: 'the wire blob, byte for byte');
    expect(handed.recipient, Fingerprint.of(suite, reader.umk.public));
    expect(handed.suiteVersion, suiteVersion);
    expect(c.keys.has(book, 2), isTrue, reason: 'and in memory this round');

    // What rests is the key: it unwraps under this user's UMK alone.
    final sealed = SealedBlob(
      suiteVersion: handed.suiteVersion,
      recipient: handed.recipient,
      bytes: handed.sealed,
    );
    final back = unwrapBookKey(
      suite,
      WrappedBookKey(ref: handed.ref, sealed: sealed),
      reader.umk,
    );
    expect(back.ref, handed.ref);
    expect(
      () => unwrapBookKey(
        suite,
        WrappedBookKey(ref: handed.ref, sealed: sealed),
        reader2.umk,
      ),
      throwsA(isA<UnsealFailed>()),
    );

    // The same row on the next meta page is not a second write.
    server.touchMeta();
    await c.engine.sync();
    expect(c.sink.accepted, hasLength(1));
  });

  test('D-05-41 nothing reaches the persistence seam that this device did not '
      'newly unwrap: a key it already holds, one sealed to another member, '
      'and one torn in flight (05 §5)', () async {
    final bk2 = BookKey.generate(suite, bookId: book, keyVersion: 2);
    final bk3 = BookKey.generate(suite, bookId: book, keyVersion: 3);
    final c = await readerDevice(reader); // holds v1
    // (a) the v1 it already holds.
    server.wrappedKeys.add(wrapFor(suite, bk1, reader, 'wk-r-1'));
    // (b) v2, sealed to somebody else — not ours to keep, by fingerprint and
    //     by the seal.
    server.wrappedKeys.add(wrapFor(suite, bk2, reader2, 'wk-r2-2'));
    // (c) v3, addressed to us but corrupt: it does not open, so it is not a
    //     key and nothing may rest under its name.
    final good = wrapFor(suite, bk3, reader, 'wk-r-3');
    final torn = Uint8List.fromList(good.blob);
    torn[0] ^= 0xff;
    server.wrappedKeys.add(
      WireWrappedKey(
        id: good.id,
        kind: good.kind,
        userId: good.userId,
        bookId: book,
        keyVersion: 3,
        blob: torn,
        recipientFingerprint: good.recipientFingerprint,
      ),
    );

    await c.engine.sync();
    expect(c.sink.accepted, isEmpty);
    expect(c.keys.has(book, 1), isTrue, reason: 'what it held it still holds');
    expect(c.keys.has(book, 2), isFalse);
    expect(c.keys.has(book, 3), isFalse);
  });
}
