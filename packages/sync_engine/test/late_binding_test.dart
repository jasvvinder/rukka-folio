// Suite D — late-bound identity and key material (ADR 2026-10-09 §1 🔒;
// PLAN desks 126, 168). The device keys are minted at S0.2, after the
// composition root built the engine, and a C-04b-3 re-mint replaces ids in the
// same process. So the engine, the guard and the trust store read a source at
// use. Before the keys exist the source answers an explicit *not registered
// yet* and everything fails closed with a typed reason; once it answers, the
// next round runs under the new values with no rebuild — and nothing verified
// under an earlier identity is re-attributed to the new one.
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

import 'helpers.dart';

// ── plaintext rig ────────────────────────────────────────────────────────

/// Records what the engine asked for, then forwards to the fake server.
final class RecordingTransport implements SyncTransport {
  RecordingTransport(this.inner);

  final FakeTransport inner;

  /// `after` of every meta request, in order.
  final List<String?> metaAfters = [];

  /// Book of every pull request, in order.
  final List<String> pulledBooks = [];

  @override
  Future<PushResponse> push(PushRequest request) => inner.push(request);

  @override
  Future<PullResponse> pull(PullRequest request) {
    pulledBooks.add(request.bookId);
    return inner.pull(request);
  }

  @override
  Future<MetaResponse> meta(MetaRequest request) {
    metaAfters.add(request.after);
    return inner.meta(request);
  }
}

/// One phone whose identity is read through [identity] at every round.
final class LateDevice {
  LateDevice._(
    this.db,
    this.mirror,
    this.fake,
    this.transport,
    this.trust,
    this.guard,
    this.identity,
    this.engine,
  );

  static Future<LateDevice> open({
    required FakeSyncServer server,
    required ManualClock clock,
    required String sessionDevice,
    DeviceIdentity initial = const NotRegisteredYet(),
    Set<String> trustedDevices = const {},
    Set<String> books = const {book1},
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final r = await openLedgerDatabase(NativeDatabase.memory());
    final db = (r as Opened).db;
    final mirror = Mirror(db, hasher: fnv1a32);
    final fake = server.transportFor(sessionDevice);
    final transport = RecordingTransport(fake);
    final trust = RecordTrustStore(umks: const MapUmkSource({}));
    final guard = PlainGuard(trust: trust, trustedDevices: {...trustedDevices});
    final identity = ManualIdentity(initial);
    final engine = SyncEngine.late(
      db: db,
      mirror: mirror,
      transport: transport,
      clock: clock,
      guard: guard,
      trust: trust,
      identity: identity,
    )..subscribedBooks.addAll(books);
    return LateDevice._(
      db,
      mirror,
      fake,
      transport,
      trust,
      guard,
      identity,
      engine,
    );
  }

  final LedgerDatabase db;
  final Mirror mirror;

  /// The session line: its `deviceId` is who the access token names.
  final FakeTransport fake;
  final RecordingTransport transport;
  final RecordTrustStore trust;
  final PlainGuard guard;
  final ManualIdentity identity;
  final SyncEngine engine;
  int _n = 0;

  /// Authors a plaintext object as [author] into the mirror and the outbox.
  Future<EnvelopeRecord> author(
    String author, {
    required int physicalMs,
    String bookId = book1,
  }) async {
    final oid = '$author-${_n++}';
    final seq = await mirror.nextAuthorSeq(bookId, author);
    final blob = Uint8List.fromList(
      utf8.encode(jsonEncode({'author_seq': seq, 'id': oid})),
    );
    final rec = EnvelopeRecord(
      envelopeId: 'env-$oid',
      bookId: bookId,
      objectId: oid,
      objectType: 'entry',
      keyVersion: 1,
      hlc: physicalMs << 16,
      authorDevice: author,
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

  Future<Map<String, String>> outboxStates() async => {
    for (final r in await mirror.outboxRows()) r.envelopeId: r.pushState,
  };

  Future<EnvelopesLocalData?> row(String envelopeId) => (db.select(
    db.envelopesLocal,
  )..where((t) => t.envelopeId.equals(envelopeId))).getSingleOrNull();

  Future<int> cursor(String book) async =>
      (await (db.select(
        db.syncCursors,
      )..where((t) => t.bookId.equals(book))).getSingleOrNull())?.lastSeq ??
      0;

  Future<int> signedRecordsHeld() async =>
      (await db.select(db.signedRecordsLocal).get()).length;

  Future<void> close() => db.close();
}

/// Events that would read as corruption, lost keys or a security event.
List<SyncEvent> alarming(SyncEngine e) => [
  for (final ev in e.events)
    if (ev is Quarantined ||
        ev is BlobCorruptOnPull ||
        ev is RecordIgnored ||
        ev is KeyWait ||
        ev is Wiped ||
        ev is KeysDropped ||
        ev is Suspended ||
        ev is PushRejected)
      ev,
];

const _a = RegisteredIdentity(
  deviceId: 'phone-a',
  userId: 'u-a',
  tenantId: tenant1,
);

// ── crypto rig ───────────────────────────────────────────────────────────

String uuid(int n, [int group = 1]) =>
    '${n.toRadixString(16).padLeft(8, '0')}-000$group-4000-8000-'
    '${n.toRadixString(16).padLeft(12, '0')}';

final cTenant = uuid(1, 0);
final cBook = uuid(2, 0);

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

/// A user with a ceremony-verified UMK and one certified device.
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

  RegisteredIdentity get identity =>
      RegisteredIdentity(deviceId: deviceId, userId: userId, tenantId: cTenant);

  WireSignedRecord record(String id, String kind, Map<String, Object?> body) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
    final r = SignedRecord.sign(
      suite,
      tenantId: cTenant,
      kind: kind,
      payloadJson: bytes,
      hlc: 1,
      author: device,
    );
    return WireSignedRecord(
      id: id,
      suiteVersion: r.suiteVersion,
      tenantId: cTenant,
      kind: kind,
      payloadJson: r.payloadJson,
      authorDeviceId: deviceId,
      authorSig: r.authorSig,
      hlc: 1,
      seq: 1, // as the server stamps it (seq starts at 1)
    );
  }

  WireEnvelope seal(BookKey key, {required int n, required int authorSeq}) {
    final e = EnvelopeBuilder.seal(
      suite,
      tenantId: cTenant,
      bookId: cBook,
      objectId: uuid(n, 5),
      objectType: 'entry',
      envelopeId: uuid(n, 6),
      hlc: 1 << 16,
      authorSeq: authorSeq,
      object: {'kind': 'money_out', 'n': n},
      bookKey: key,
      author: device,
    );
    final blob = e.blob;
    return WireEnvelope(
      envelopeId: e.envelopeId,
      tenantId: cTenant,
      bookId: cBook,
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

  /// This person's material over a fresh book-key store, vouching for [umks].
  DeviceKeyMaterial material(Map<String, VerifiedUmkPublic> umks) =>
      DeviceKeyMaterial(
        device: device,
        umk: umk,
        bookKeys: BookKeyStore(tenantId: cTenant),
        verifiedUmks: MapUmkSource(umks),
      );
}

final class RecordingKeySink implements AcceptedKeySink {
  final List<AcceptedBookKey> accepted = [];

  /// Runs while the key is being persisted — where the app's `key_cache`
  /// write awaits, and the composition root could dispose the material.
  void Function(AcceptedBookKey key)? onAccepted;

  @override
  Future<void> keyAccepted(AcceptedBookKey key) async {
    accepted.add(key);
    onAccepted?.call(key);
  }
}

/// Forwards to [inner], noting every envelope it answered *not registered*.
final class CountingGuard implements EnvelopeGuard {
  CountingGuard(this.inner);

  final EnvelopeGuard inner;

  /// Envelope ids the guard was asked about and answered not registered.
  final List<String> notRegistered = [];

  @override
  Uint8List hash(Uint8List blob) => inner.hash(blob);

  @override
  int get payloadSchema => inner.payloadSchema;

  @override
  EnvelopeVerdict checkEnvelope(WireEnvelope envelope) {
    final v = inner.checkEnvelope(envelope);
    if (v is EnvelopeNotRegistered) notRegistered.add(envelope.envelopeId);
    return v;
  }

  @override
  RecordVerdict checkRecord(WireSignedRecord record) =>
      inner.checkRecord(record);

  @override
  int? highestKeyVersion(String bookId) => inner.highestKeyVersion(bookId);

  @override
  WireEnvelope? reseal(WireEnvelope envelope, {required int toVersion}) =>
      inner.reseal(envelope, toVersion: toVersion);

  @override
  KeyAcceptance acceptWrappedKey(WireWrappedKey key) =>
      inner.acceptWrappedKey(key);

  @override
  DeviceCert? buildCert(WireDeviceCert cert, WireDevice device) =>
      inner.buildCert(cert, device);

  @override
  void dropAllKeys() => inner.dropAllKeys();

  @override
  bool boundTo(String deviceId) => inner.boundTo(deviceId);
}

/// This device's own envelope [w], authored into the mirror and the outbox.
Future<void> enqueueOwn(Mirror mirror, WireEnvelope w, int authorSeq) async {
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
    createdAt: 1,
  );
}

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
  late ManualClock clock;
  late FakeSyncServer server;
  final open = <LateDevice>[];

  setUp(() {
    clock = ManualClock(1 << 40);
    server = FakeSyncServer(clock: clock, rateLimits: RateLimits.none);
  });

  tearDown(() async {
    for (final d in open) {
      await d.close();
    }
    open.clear();
  });

  Future<LateDevice> late({
    String session = 'phone-a',
    DeviceIdentity initial = const NotRegisteredYet(),
    Set<String> trusted = const {},
    Set<String> books = const {book1},
  }) async {
    final d = await LateDevice.open(
      server: server,
      clock: clock,
      sessionDevice: session,
      initial: initial,
      trustedDevices: trusted,
      books: books,
    );
    open.add(d);
    return d;
  }

  group('plaintext engine', () {
    test('D-1009-1 not registered yet: a round makes no call at all — no '
        'meta, no push, no pull, nothing verified — and says why with a typed '
        'hold, raised once, never as keys lost, corruption or an Inbox cause; '
        'the status never claims Synced', () async {
      // Something is waiting on the server: another phone's envelope and a
      // record a trusted device signed.
      final other = await late(session: 'phone-b', initial: _a);
      await other.author('phone-b', physicalMs: clock.nowMs());
      // phone-b's own line: re-point the fake session and push it in.
      other.fake.deviceId = 'phone-b';
      other.identity.identity = const RegisteredIdentity(
        deviceId: 'phone-b',
        userId: 'u-b',
        tenantId: tenant1,
      );
      expect((await other.engine.sync()).acked, 1);
      server.addSignedRecord(
        plainRecord(
          id: 'role-1',
          kind: 'book_role',
          author: 'admin',
          payload: {'book_id': book1, 'user_id': 'u-a', 'role': 'owner'},
        ),
      );

      final a = await late(trusted: {'admin'});
      final queued = await a.author('phone-a', physicalMs: clock.nowMs());
      expect(a.engine.hold, SyncHold.notRegistered);

      final r = await a.engine.sync();
      expect(r.held, SyncHold.notRegistered);
      expect(
        (r.pushed, r.acked, r.pulled, r.verified, r.quarantined),
        (0, 0, 0, 0, 0),
      );
      expect(a.transport.inner.calls, isEmpty, reason: 'not one request');
      expect(await a.outboxStates(), {queued.envelopeId: 'queued'});
      expect(server.has(queued.envelopeId), isFalse);
      expect(await a.signedRecordsHeld(), 0, reason: 'nothing verified');
      expect(await a.cursor(book1), 0);
      expect(a.engine.roleOf(book1, 'u-a'), isNull);
      expect(a.engine.mode, EngineMode.active, reason: 'not wiped/suspended');
      expect(alarming(a.engine), isEmpty);
      expect(eventsOf<SyncHeld>(a.engine).map((e) => e.reason), [
        SyncHold.notRegistered,
      ]);
      // 05 §9 🔒 has five states and no sixth: a queued row reads "saved on
      // phone · will sync", never Synced and never Needs attention.
      expect(await a.engine.status(), const SavedWillSync(1));

      // A second round: still nothing, and the hold is not raised again.
      final r2 = await a.engine.sync();
      expect(r2.held, SyncHold.notRegistered);
      expect(a.transport.inner.calls, isEmpty);
      expect(eventsOf<SyncHeld>(a.engine), hasLength(1));

      // An empty outbox before registration: not Synced either (nothing has
      // been confirmed against a server) — the conservative non-claim.
      final empty = await late(session: 'phone-e');
      await empty.engine.sync();
      expect(await empty.engine.status(), const Offline());
      expect(empty.engine.hold, SyncHold.notRegistered);
    });

    test('D-1009-1 registration: once the source answers, the same engine — '
        'no rebuild, no relaunch — pushes, pulls and verifies on its next '
        'round under the ids it now reads', () async {
      final b = await late(
        session: 'phone-b',
        initial: const RegisteredIdentity(
          deviceId: 'phone-b',
          userId: 'u-b',
          tenantId: tenant1,
        ),
      );
      final fromB = await b.author('phone-b', physicalMs: clock.nowMs());
      await b.engine.sync();
      expect(server.has(fromB.envelopeId), isTrue);

      final a = await late();
      final mine = await a.author('phone-a', physicalMs: clock.nowMs());
      expect((await a.engine.sync()).held, SyncHold.notRegistered);
      final engine = a.engine;

      a.identity.identity = _a; // S0.2 registered the device
      expect(a.engine.hold, isNull);
      final r = await a.engine.sync();
      expect(identical(a.engine, engine), isTrue);
      expect(r.held, isNull);
      expect(r.acked, 1);
      expect(r.verified, 1, reason: "phone-b's envelope, verified");
      expect(server.stored.map((e) => (e.envelopeId, e.authorDevice)), [
        (fromB.envelopeId, 'phone-b'),
        (mine.envelopeId, 'phone-a'),
      ]);
      expect(server.stored.last.tenantId, tenant1);
      expect((await a.row(fromB.envelopeId))!.verified, 1);
      expect(await a.engine.status(), const Synced());
      expect(eventsOf<SyncHeld>(a.engine), hasLength(1), reason: 'not again');
      expect(
        eventsOf<IdentityRebound>(a.engine),
        isEmpty,
        reason:
            'a first '
            'binding is not a re-binding',
      );
      expect(alarming(a.engine), isEmpty);
    });

    test('D-1009-1 re-mint after registration: the next round runs under the '
        'new device, user and tenant ids, re-reads meta from the start, and a '
        'stale unsigned claim about the old device does not follow it; what '
        'was verified under the old identity stays attributed to the old one '
        '— its role, its book, its envelopes', () async {
      // No `devices` row for phone-c: only the rebind can clear a claim that
      // was about phone-a (a row for phone-c would restate it anyway).
      server.devices['phone-a'] = deviceRow('phone-a', 'u-a');
      server.addSignedRecord(
        plainRecord(
          id: 'role-a',
          kind: 'book_role',
          author: 'admin',
          payload: {'book_id': 'b-role', 'user_id': 'u-a', 'role': 'owner'},
        ),
      );
      final x = await late(initial: _a, trusted: {'admin'});
      final a1 = await x.author('phone-a', physicalMs: clock.nowMs());
      await x.engine.sync();
      expect(server.has(a1.envelopeId), isTrue);
      expect(x.engine.roleOf('b-role', 'u-a')!.recordId, 'role-a');
      expect(
        x.transport.pulledBooks,
        contains('b-role'),
        reason: "u-a's role brings its book into the round",
      );

      // The server's unsigned word about phone-a: suspended (ADR 05b §2).
      server.devices['phone-a'] = deviceRow(
        'phone-a',
        'u-a',
        status: 'revoked',
      );
      server.touchMeta();
      await x.engine.sync();
      expect(x.engine.mode, EngineMode.suspended);

      // Re-mint: new ids in the same process; the session now names phone-c.
      const c = RegisteredIdentity(
        deviceId: 'phone-c',
        userId: 'u-c',
        tenantId: 't2',
      );
      x.identity.identity = c;
      x.fake.deviceId = 'phone-c';
      final c1 = await x.author('phone-c', physicalMs: clock.nowMs() + 1);
      x.transport.metaAfters.clear();
      x.transport.pulledBooks.clear();

      final r = await x.engine.sync();
      expect(r.held, isNull);
      final rebound = eventsOf<IdentityRebound>(x.engine).single;
      expect(
        (rebound.previousDeviceId, rebound.deviceId),
        ('phone-a', 'phone-c'),
      );
      expect(
        x.transport.metaAfters.first,
        isNull,
        reason: 'meta is re-read whole under the new session',
      );
      expect(
        x.engine.mode,
        EngineMode.active,
        reason: "the claim was about phone-a; nothing claims phone-c",
      );
      // Pushed as the new device, under the new tenant.
      final stored = server.stored.singleWhere(
        (e) => e.envelopeId == c1.envelopeId,
      );
      expect((stored.authorDevice, stored.tenantId), ('phone-c', 't2'));
      // Nothing re-attributed: the role is u-a's, u-c has none, and u-a's
      // book is not pulled for u-c.
      expect(x.engine.roleOf('b-role', 'u-a')!.recordId, 'role-a');
      expect(x.engine.roleOf('b-role', 'u-c'), isNull);
      expect(x.transport.pulledBooks, isNot(contains('b-role')));
      expect((await x.row(a1.envelopeId))!.authorDevice, 'phone-a');
      expect(eventsOf<Wiped>(x.engine), isEmpty);
    });

    test('D-1009-1 re-mint re-judges this device\'s own fate: a verified '
        'revocation of the new device id, applied while bound to the old one '
        '(when it was somebody else\'s), wipes it before anything is pushed; '
        'a later re-bind never resumes a wiped engine', () async {
      server.devices['phone-c'] = deviceRow('phone-c', 'u-c');
      server.devices['phone-c2'] = deviceRow('phone-c2', 'u-c');
      server.addSignedRecord(
        plainRecord(
          id: 'rev-c',
          kind: 'device_revocation',
          author: 'phone-c2',
          payload: {'revoked_device_id': 'phone-c', 'subject_user_id': 'u-c'},
        ),
      );
      final x = await late(initial: _a, trusted: {'phone-c2'});
      await x.engine.sync();
      expect(x.engine.mode, EngineMode.active, reason: 'not about phone-a');
      expect(x.trust.revocationSeqOf('phone-c'), isNotNull);

      x.identity.identity = const RegisteredIdentity(
        deviceId: 'phone-c',
        userId: 'u-c',
        tenantId: tenant1,
      );
      x.fake.deviceId = 'phone-c';
      final c1 = await x.author('phone-c', physicalMs: clock.nowMs() + 1);
      final calls = x.fake.calls.length;
      final r = await x.engine.sync();
      expect(x.engine.mode, EngineMode.wiped);
      expect(eventsOf<Wiped>(x.engine).single.recordId, 'rev-c');
      expect(r.pushed, 0);
      expect(server.has(c1.envelopeId), isFalse);
      expect(x.fake.calls.length, calls, reason: 'wiped before any request');

      // Fail closed for good: another identity does not un-wipe the engine.
      x.identity.identity = _a;
      x.fake.deviceId = 'phone-a';
      await x.engine.sync();
      expect(x.engine.mode, EngineMode.wiped);
      expect(x.fake.calls.length, calls);
    });

    test('D-1009-1 the binding changes mid-round: the round stops at the next '
        'route boundary with a typed hold — what the server already answered '
        'is kept, nothing is quarantined, no cursor passes an unread row — and '
        'the next round runs under whatever the source answers then', () async {
      final b = await late(
        session: 'phone-b',
        initial: const RegisteredIdentity(
          deviceId: 'phone-b',
          userId: 'u-b',
          tenantId: tenant1,
        ),
      );
      final fromB = await b.author('phone-b', physicalMs: clock.nowMs());
      await b.engine.sync();

      final a = await late(initial: _a);
      final mine = await a.author('phone-a', physicalMs: clock.nowMs());
      // The keys go away while meta is in flight (the root disposed them).
      a.fake.beforeCall = (route) {
        if (route == 'meta') a.identity.identity = const NotRegisteredYet();
      };
      final r = await a.engine.sync();
      expect(r.held, SyncHold.notRegistered);
      expect(a.fake.calls, ['meta'], reason: 'no push, no pull after it');
      expect(await a.outboxStates(), {mine.envelopeId: 'queued'});
      expect(await a.cursor(book1), 0);
      expect(alarming(a.engine), isEmpty);

      // Back, and a different identity mid-round: `bindingChanged`.
      a.fake.beforeCall = (route) {
        if (route == 'meta') {
          a.identity.identity = const RegisteredIdentity(
            deviceId: 'phone-a',
            userId: 'u-a2',
            tenantId: tenant1,
          );
        }
      };
      a.identity.identity = _a;
      final r2 = await a.engine.sync();
      expect(r2.held, SyncHold.bindingChanged);
      expect(server.has(mine.envelopeId), isFalse);
      expect(eventsOf<SyncHeld>(a.engine).map((e) => e.reason), [
        SyncHold.notRegistered,
        SyncHold.bindingChanged,
      ]);

      a.fake.beforeCall = null;
      final r3 = await a.engine.sync();
      expect(r3.held, isNull);
      expect(eventsOf<IdentityRebound>(a.engine).single.deviceId, 'phone-a');
      expect(server.has(mine.envelopeId), isTrue);
      expect((await a.row(fromB.envelopeId))!.verified, 1);
      expect(await a.engine.status(), const Synced());
      expect(alarming(a.engine), isEmpty);
    });

    test('D-1009-1 the binding changes while a pull page is in flight: the '
        'page the server already answered is kept and its cursor moves, but '
        'the next page is never asked for — the round stops with a typed hold '
        '(not registered, then a changed binding) — and a later round reads on '
        'from that cursor without reading a row twice', () async {
      final b = await late(
        session: 'phone-b',
        initial: const RegisteredIdentity(
          deviceId: 'phone-b',
          userId: 'u-b',
          tenantId: tenant1,
        ),
      );
      final b1 = await b.author('phone-b', physicalMs: clock.nowMs());
      final b2 = await b.author('phone-b', physicalMs: clock.nowMs() + 1);
      await b.engine.sync();

      // Nothing queued on phone-a, so the round is meta → pull pages only.
      final a = await late(initial: _a);
      a.fake.beforeCall = (route) {
        if (route == 'pull') a.identity.identity = const NotRegisteredYet();
      };
      final r1 = await a.engine.sync();
      expect(r1.held, SyncHold.notRegistered);
      expect(
        a.fake.calls,
        ['meta', 'pull'],
        reason: 'a non-empty page is followed by another pull — not this time',
      );
      expect(r1.verified, 2, reason: 'the answered page is kept');
      expect((await a.row(b1.envelopeId))!.verified, 1);
      expect((await a.row(b2.envelopeId))!.verified, 1);
      expect(await a.cursor(book1), 2);
      expect(alarming(a.engine), isEmpty);

      // Back, and a different identity while the next page is in flight.
      final b3 = await b.author('phone-b', physicalMs: clock.nowMs() + 2);
      final b4 = await b.author('phone-b', physicalMs: clock.nowMs() + 3);
      await b.engine.sync();
      a.identity.identity = _a;
      a.fake.calls.clear();
      a.fake.beforeCall = (route) {
        if (route == 'pull') {
          a.identity.identity = const RegisteredIdentity(
            deviceId: 'phone-a',
            userId: 'u-a2',
            tenantId: tenant1,
          );
        }
      };
      final r2 = await a.engine.sync();
      expect(r2.held, SyncHold.bindingChanged);
      expect(a.fake.calls, ['meta', 'pull']);
      expect(r2.verified, 2);
      expect(await a.cursor(book1), 4);
      expect(eventsOf<SyncHeld>(a.engine).map((e) => e.reason), [
        SyncHold.notRegistered,
        SyncHold.bindingChanged,
      ]);

      // The binding the round started under is back: it reads on from 4.
      a.fake.beforeCall = null;
      a.identity.identity = _a;
      final r3 = await a.engine.sync();
      expect(r3.held, isNull);
      expect(r3.pulled, 0, reason: 'no row is read twice');
      expect(
        (await a.mirror.envelopesOf(book1)).map((r) => r.envelopeId),
        unorderedEquals([
          b1.envelopeId,
          b2.envelopeId,
          b3.envelopeId,
          b4.envelopeId,
        ]),
      );
      expect(await a.engine.status(), const Synced());
      expect(alarming(a.engine), isEmpty);
    });
  });

  group('crypto guard and trust store', () {
    late CryptoSuite suite;
    late Person me, other, author;
    late Map<String, VerifiedUmkPublic> umks;
    late BookKey bk;

    setUpAll(() async {
      final s = await SodiumInit.init();
      suite = CryptoSuite(s, random: _deterministic(s, 1009));
    });

    setUp(() {
      me = Person(suite, uuid(10), uuid(110));
      other = Person(suite, uuid(11), uuid(111));
      author = Person(suite, uuid(12), uuid(112));
      umks = {
        for (final p in [me, other, author]) p.userId: p.verified,
      };
      bk = BookKey.generate(suite, bookId: cBook, keyVersion: 1);
    });

    test('D-1009-1 before the keys exist the guard verifies nothing, unwraps '
        'nothing and signs nothing — with its own not-registered verdicts, '
        'never a quarantine, a corruption or a key-wait — and the trust store '
        'believes nobody; the moment the source answers, both read the new '
        'material', () async {
      final source = ManualKeyMaterial();
      final trust = RecordTrustStore.late(keys: source);
      final guard = CryptoGuard.late(
        suite: suite,
        trust: trust,
        material: source,
      );
      trust.certs[author.deviceId] = author.cert;
      final env = author.seal(bk, n: 1, authorSeq: 1);
      final rec = author.record('r-1', SignedRecordKind.bookRole, {
        'book_id': cBook,
        'user_id': me.userId,
        'role': 'owner',
      });
      final row = wrapFor(suite, bk, me, 'wk-1');

      expect(guard.boundTo(me.deviceId), isFalse);
      expect(guard.checkEnvelope(env), isA<EnvelopeNotRegistered>());
      expect(guard.checkRecord(rec), isA<RecordNotRegistered>());
      expect(guard.acceptWrappedKey(row), isA<KeyHeldNotRegistered>());
      expect(guard.highestKeyVersion(cBook), isNull);
      expect(guard.reseal(env, toVersion: 2), isNull);
      expect(trust.verifiedUmkOf(me.userId), isNull);
      expect(trust.verifiedUmkOf(author.userId), isNull);
      expect(() => guard.keys, throwsStateError, reason: 'explicit, not null');

      source.keys = me.material(umks);
      expect(guard.boundTo(me.deviceId), isTrue);
      expect(guard.boundTo(other.deviceId), isFalse);
      expect(trust.verifiedUmkOf(author.userId), author.verified);
      expect(guard.checkRecord(rec), isA<RecordVerified>());
      expect(guard.checkEnvelope(env), isA<EnvelopeKeyWait>());
      expect(guard.acceptWrappedKey(row), isA<KeyAccepted>());
      expect(guard.checkEnvelope(env), isA<EnvelopeVerified>());
      expect(guard.highestKeyVersion(cBook), 1);
      expect(
        identical(guard.keys, (source.keys as DeviceKeyMaterial).bookKeys),
        isTrue,
      );
    });

    test('D-1009-1 a re-mint swaps the material under a live guard: the next '
        'use reads the new device, UMK and book-key store — the old user is no '
        'longer believed as this install, a disposed pair is refused rather '
        'than used, and an engine whose identity names a device the guard has '
        'no keys for holds instead of syncing', () async {
      final source = ManualKeyMaterial(me.material({me.userId: me.verified}));
      final trust = RecordTrustStore.late(keys: source);
      final guard = CryptoGuard.late(
        suite: suite,
        trust: trust,
        material: source,
      );
      (source.keys as DeviceKeyMaterial).bookKeys.put(bk);
      expect(guard.highestKeyVersion(cBook), 1);
      expect(trust.verifiedUmkOf(me.userId), me.verified);

      source.keys = other.material({other.userId: other.verified});
      expect(guard.boundTo(other.deviceId), isTrue);
      expect(guard.boundTo(me.deviceId), isFalse);
      expect(guard.highestKeyVersion(cBook), isNull, reason: 'new store');
      expect(trust.verifiedUmkOf(me.userId), isNull, reason: 'not captured');
      expect(trust.verifiedUmkOf(other.userId), other.verified);

      // An engine told it is `me` while the guard holds `other`'s keys.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db =
          ((await openLedgerDatabase(NativeDatabase.memory())) as Opened).db;
      addTearDown(db.close);
      final fake = server.transportFor(me.deviceId);
      final engine = SyncEngine.late(
        db: db,
        mirror: Mirror(db, hasher: blake2bHasher(suite)),
        transport: fake,
        clock: clock,
        guard: guard,
        trust: trust,
        identity: FixedIdentity(me.identity),
      );
      expect((await engine.sync()).held, SyncHold.notRegistered);
      expect(fake.calls, isEmpty);

      // A pair the root disposed (a rebuild) is never used to sign or open.
      final disposable = Person(suite, uuid(13), uuid(113));
      source.keys = disposable.material(const {});
      disposable.device.dispose();
      expect(guard.boundTo(disposable.deviceId), isFalse);
      expect(
        guard.checkEnvelope(author.seal(bk, n: 2, authorSeq: 1)),
        isA<EnvelopeNotRegistered>(),
      );
    });

    test('D-1009-1 identity registered, keys not yet: the engine holds and '
        'makes no request, so the meta cursor cannot pass a wrapped_keys row '
        'it could not open; once the keys arrive the next round accepts the '
        'key, persists it and verifies the envelope it opens', () async {
      server.devices[author.deviceId] = author.row;
      server.deviceCerts[author.deviceId] = author.certRow;
      server.wrappedKeys.add(wrapFor(suite, bk, me, 'wk-1'));
      final env = author.seal(bk, n: 1, authorSeq: 1);
      server.push(author.deviceId, PushRequest(envelopes: [env]));

      final source = ManualKeyMaterial();
      final trust = RecordTrustStore.late(keys: source);
      final guard = CryptoGuard.late(
        suite: suite,
        trust: trust,
        material: source,
      );
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db =
          ((await openLedgerDatabase(NativeDatabase.memory())) as Opened).db;
      addTearDown(db.close);
      final mirror = Mirror(db, hasher: blake2bHasher(suite));
      final fake = server.transportFor(me.deviceId);
      final sink = RecordingKeySink();
      final engine = SyncEngine.late(
        db: db,
        mirror: mirror,
        transport: fake,
        clock: clock,
        guard: guard,
        trust: trust,
        identity: FixedIdentity(me.identity),
        keySink: sink,
      )..subscribedBooks.add(cBook);

      final r = await engine.sync();
      expect(r.held, SyncHold.notRegistered);
      expect(fake.calls, isEmpty);
      expect(sink.accepted, isEmpty);
      expect(await mirror.envelopesOf(cBook), isEmpty);

      source.keys = me.material(umks); // S0.2 minted them
      final r2 = await engine.sync();
      expect(r2.held, isNull);
      expect(sink.accepted.single.ref, bk.ref);
      expect(r2.verified, 1);
      final rows = await mirror.envelopesOf(cBook);
      expect(rows.single.verified, 1);
      expect(rows.single.quarantined, 0);
      expect(engine.events.whereType<Quarantined>(), isEmpty);
    });

    test('D-1009-1 the keys go away mid-page: a wrapped_keys row and a '
        'signed record on that meta page are neither stored nor skipped — the '
        'meta cursor stays before the page — and an envelope on a pull page is '
        'neither stored nor quarantined, its cursor held; once the keys are '
        'back every one of them is read again and verified', () async {
      server.devices[author.deviceId] = author.row;
      server.deviceCerts[author.deviceId] = author.certRow;
      server.wrappedKeys.add(wrapFor(suite, bk, me, 'wk-1'));
      final env = author.seal(bk, n: 1, authorSeq: 1);
      server.push(author.deviceId, PushRequest(envelopes: [env]));

      final material = me.material(umks);
      final source = ManualKeyMaterial(material);
      final trust = RecordTrustStore.late(keys: source);
      final guard = CryptoGuard.late(
        suite: suite,
        trust: trust,
        material: source,
      );
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db =
          ((await openLedgerDatabase(NativeDatabase.memory())) as Opened).db;
      addTearDown(db.close);
      final mirror = Mirror(db, hasher: blake2bHasher(suite));
      final fake = server.transportFor(me.deviceId);
      final sink = RecordingKeySink();
      final engine = SyncEngine.late(
        db: db,
        mirror: mirror,
        transport: fake,
        clock: clock,
        guard: guard,
        trust: trust,
        identity: FixedIdentity(me.identity),
        keySink: sink,
      )..subscribedBooks.add(cBook);
      void goneOn(String route) => fake.beforeCall = (r) {
        if (r == route) source.keys = const KeysNotRegisteredYet();
      };

      // 1. Gone while a page holding only the wrapped key is in flight.
      goneOn('meta');
      final r1 = await engine.sync();
      expect(r1.held, SyncHold.notRegistered);
      expect(fake.calls, ['meta']);
      expect(sink.accepted, isEmpty);

      // 2. Back: the same page comes again (the cursor never passed it) and
      //    the key is accepted. A signed record joins the next page.
      source.keys = material;
      fake.beforeCall = null;
      await engine.sync();
      expect(sink.accepted.single.ref, bk.ref, reason: 'the row was re-read');
      expect((await mirror.envelopesOf(cBook)).single.verified, 1);
      server.addSignedRecord(
        author.record('r-role', SignedRecordKind.bookRole, {
          'book_id': cBook,
          'user_id': me.userId,
          'role': 'owner',
        }),
      );
      goneOn('meta');
      final r2 = await engine.sync();
      expect(r2.held, SyncHold.notRegistered);
      expect(
        await db.select(db.signedRecordsLocal).get(),
        isEmpty,
        reason: 'not stored, not even as unverified',
      );
      expect(engine.events.whereType<RecordIgnored>(), isEmpty);
      expect(engine.roleOf(cBook, me.userId), isNull);

      // 3. Back for meta (the record is read again and believed), gone while
      //    a pull page holding a new envelope is in flight.
      source.keys = material;
      final env2 = author.seal(bk, n: 2, authorSeq: 2);
      server.push(author.deviceId, PushRequest(envelopes: [env2]));
      goneOn('pull');
      final r3 = await engine.sync();
      expect(r3.held, SyncHold.notRegistered);
      expect(engine.roleOf(cBook, me.userId)!.recordId, 'r-role');
      expect(await mirror.envelopesOf(cBook), hasLength(1));
      expect(engine.keyWaiting, isEmpty, reason: 'not a key_wait');
      final cursor = await (db.select(
        db.syncCursors,
      )..where((t) => t.bookId.equals(cBook))).getSingleOrNull();
      expect(
        cursor?.lastSeq ?? 0,
        lessThan(server.stored.last.seq!),
        reason: 'never past the unread row',
      );

      // 4. Back for good.
      source.keys = material;
      fake.beforeCall = null;
      final r4 = await engine.sync();
      expect(r4.held, isNull);
      expect(r4.verified, 1);
      final rows = await mirror.envelopesOf(cBook);
      expect(rows.map((r) => (r.verified, r.quarantined)), [(1, 0), (1, 0)]);
      expect(engine.events.whereType<Quarantined>(), isEmpty);
      expect(engine.events.whereType<BlobCorruptOnPull>(), isEmpty);
      expect(engine.events.whereType<KeyWait>(), isEmpty);
      expect(await engine.status(), const Synced());
    });

    test('D-1009-1 the keys go away while a push is in flight and the server '
        'answers key_version_stale: the row goes back to queued — not '
        'rejected, no Inbox rejection, since a device holding no keys cannot '
        're-seal and that is not the row\'s fault — and once the keys are back '
        'with the newer version it is re-sealed and acked once', () async {
      server.devices[me.deviceId] = me.row;
      server.deviceCerts[me.deviceId] = me.certRow;
      final material = me.material(umks)..bookKeys.put(bk);
      final source = ManualKeyMaterial(material);
      final trust = RecordTrustStore.late(keys: source);
      final guard = CryptoGuard.late(
        suite: suite,
        trust: trust,
        material: source,
      );
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db =
          ((await openLedgerDatabase(NativeDatabase.memory())) as Opened).db;
      addTearDown(db.close);
      final mirror = Mirror(db, hasher: blake2bHasher(suite));
      final fake = server.transportFor(me.deviceId);
      final engine = SyncEngine.late(
        db: db,
        mirror: mirror,
        transport: fake,
        clock: clock,
        guard: guard,
        trust: trust,
        identity: FixedIdentity(me.identity),
      )..subscribedBooks.add(cBook);
      final w = me.seal(bk, n: 1, authorSeq: 1);
      await enqueueOwn(mirror, w, 1);
      server.minKeyVersion[cBook] = 2; // the grace window for v1 closed
      fake.beforeCall = (r) {
        if (r == 'push') source.keys = const KeysNotRegisteredYet();
      };

      final r1 = await engine.sync();
      expect(r1.held, SyncHold.notRegistered);
      expect(fake.calls, ['meta', 'push']);
      expect(
        (await mirror.outboxRows()).single.pushState,
        PushState.queued.name,
      );
      expect(engine.events.whereType<PushRejected>(), isEmpty);
      expect(
        await engine.status(),
        const SavedWillSync(1),
        reason: 'no Inbox rejection',
      );
      expect(server.has(w.envelopeId), isFalse);

      // Back, holding v2 (a restore brought the rotated key with it).
      material.bookKeys.put(
        BookKey.generate(suite, bookId: cBook, keyVersion: 2),
      );
      source.keys = material;
      fake.beforeCall = null;
      final r2 = await engine.sync();
      expect(r2.held, isNull);
      expect(r2.acked, 1);
      expect(
        server.stored.where((e) => e.envelopeId == w.envelopeId).single,
        isA<WireEnvelope>().having((e) => e.keyVersion, 'keyVersion', 2),
      );
      final resealed = engine.events.whereType<Resealed>().single;
      expect((resealed.fromVersion, resealed.toVersion), (1, 2));
      expect(engine.events.whereType<PushRejected>(), isEmpty);
      expect(await engine.status(), const Synced());
    });

    test('D-1009-1 the keys go away while an accepted key is being persisted: '
        'the key_wait drain stops at the guard\'s first not-registered answer '
        '— it asks about no further envelope, stores nothing, quarantines '
        'nothing, every envelope stays waiting with its cursor held — and once '
        'the keys are back each one is verified', () async {
      server.devices[author.deviceId] = author.row;
      server.deviceCerts[author.deviceId] = author.certRow;
      final e1 = author.seal(bk, n: 1, authorSeq: 1);
      final e2 = author.seal(bk, n: 2, authorSeq: 2);
      server.push(author.deviceId, PushRequest(envelopes: [e1, e2]));

      final material = me.material(umks); // no book key yet
      final source = ManualKeyMaterial(material);
      final trust = RecordTrustStore.late(keys: source);
      final guard = CountingGuard(
        CryptoGuard.late(suite: suite, trust: trust, material: source),
      );
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db =
          ((await openLedgerDatabase(NativeDatabase.memory())) as Opened).db;
      addTearDown(db.close);
      final mirror = Mirror(db, hasher: blake2bHasher(suite));
      final fake = server.transportFor(me.deviceId);
      final sink = RecordingKeySink();
      final engine = SyncEngine.late(
        db: db,
        mirror: mirror,
        transport: fake,
        clock: clock,
        guard: guard,
        trust: trust,
        identity: FixedIdentity(me.identity),
        keySink: sink,
      )..subscribedBooks.add(cBook);
      Future<int> cursor() async =>
          (await (db.select(
                db.syncCursors,
              )..where((t) => t.bookId.equals(cBook))).getSingleOrNull())
              ?.lastSeq ??
          0;

      final r1 = await engine.sync();
      expect(r1.keyWait, 2);
      expect(engine.keyWaiting, {e1.envelopeId, e2.envelopeId});

      // The key arrives; the root disposes the material while it is being
      // written to key_cache.
      server.wrappedKeys.add(wrapFor(suite, bk, me, 'wk-1'));
      server.touchMeta();
      sink.onAccepted = (_) => source.keys = const KeysNotRegisteredYet();
      final r2 = await engine.sync();
      expect(r2.held, SyncHold.notRegistered);
      expect(sink.accepted.single.ref, bk.ref);
      expect(
        guard.notRegistered,
        hasLength(1),
        reason: 'one not-registered answer stops the drain',
      );
      expect(engine.keyWaiting, {e1.envelopeId, e2.envelopeId});
      expect(await mirror.envelopesOf(cBook), isEmpty);
      expect(await cursor(), 0, reason: 'never past a waiting envelope');
      expect(
        engine.events.whereType<KeyWait>(),
        hasLength(2),
        reason: 'round 1 only',
      );
      expect(engine.events.whereType<Quarantined>(), isEmpty);
      expect(engine.events.whereType<BlobCorruptOnPull>(), isEmpty);

      // Back: the accepted key is in the store, and the held cursor brings
      // both envelopes again.
      sink.onAccepted = null;
      source.keys = material;
      final r3 = await engine.sync();
      expect(r3.held, isNull);
      expect(r3.verified, 2);
      expect(engine.keyWaiting, isEmpty);
      final rows = await mirror.envelopesOf(cBook);
      expect(rows.map((r) => (r.verified, r.quarantined)), [(1, 0), (1, 0)]);
      expect(engine.events.whereType<Quarantined>(), isEmpty);
      expect(await engine.status(), const Synced());
    });
  });
}
