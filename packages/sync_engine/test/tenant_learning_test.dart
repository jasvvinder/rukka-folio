// Suite D — a further device learns its tenant and never mints one (ADR
// 2026-10-10 §1 🔒; PLAN desk 185 (b)). A device that signed in to an
// existing account is registered — its keys exist — but holds no tenant. Its
// source answers `RegisteredAwaitingTenant`, and the engine reads meta only:
// that is how the tenant is learned. It stamps no push, pulls and opens no
// envelope, and hands what a **complete** read showed of its own user's
// memberships to a `TenantLearningSink`; the identity owner (the app's
// ledger) applies the rule. Once the source answers a tenant, the next round
// runs under it with no rebuild.
//
// The adversarial cases are ordering ones: a tenant that is only absent from
// the page read so far must never look like the only one, a read cut short
// hands nothing over, and a verified record outranks a server row.
@Tags(['D'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Records what the engine asked for; can split meta into scripted pages.
final class _Transport implements SyncTransport {
  _Transport(this.inner);

  final FakeTransport inner;

  /// `after` of every meta request, in order.
  final List<String?> metaAfters = [];

  /// Book of every pull request, in order.
  final List<String> pulledBooks = [];

  /// Number of push requests.
  int pushes = 0;

  /// When set, meta is served from here instead: `after` → page, or a
  /// [TransportFailure] to throw.
  Map<String?, Object>? pages;

  @override
  Future<PushResponse> push(PushRequest request) {
    pushes++;
    return inner.push(request);
  }

  @override
  Future<PullResponse> pull(PullRequest request) {
    pulledBooks.add(request.bookId);
    return inner.pull(request);
  }

  @override
  Future<MetaResponse> meta(MetaRequest request) async {
    metaAfters.add(request.after);
    final scripted = pages;
    if (scripted == null) return inner.meta(request);
    final page = scripted[request.after];
    if (page is TransportFailure) throw page;
    return page! as MetaResponse;
  }
}

/// The identity owner's half, as a test: records every read, and — like the
/// ledger — adopts the tenant when the read shows exactly one.
final class _Sink implements TenantLearningSink {
  _Sink(this.identity, {this.learn = true});

  final ManualIdentity identity;
  final bool learn;
  final List<OwnMemberships> reads = [];

  @override
  Future<void> ownMembershipsRead(OwnMemberships read) async {
    reads.add(read);
    final id = identity.identity;
    if (!learn || id is! RegisteredAwaitingTenant) return;
    if (read.userId != id.userId || read.activeTenantIds.length != 1) return;
    identity.identity = RegisteredIdentity(
      deviceId: id.deviceId,
      userId: id.userId,
      tenantId: read.activeTenantIds.single,
    );
  }
}

final class _Phone {
  _Phone(this.db, this.mirror, this.transport, this.identity, this.sink)
    : engine = _engine(db, mirror, transport, identity, sink);

  static SyncEngine _engine(
    LedgerDatabase db,
    Mirror mirror,
    _Transport transport,
    ManualIdentity identity,
    _Sink? sink,
  ) {
    final trust = RecordTrustStore(umks: const MapUmkSource({}));
    return SyncEngine.late(
      db: db,
      mirror: mirror,
      transport: transport,
      clock: ManualClock(1 << 40),
      guard: PlainGuard(trust: trust, trustedDevices: {'admin', 'phone-b'}),
      trust: trust,
      identity: identity,
      tenantSink: sink,
    )..subscribedBooks.add(book1);
  }

  final LedgerDatabase db;
  final Mirror mirror;
  final _Transport transport;
  final ManualIdentity identity;
  final _Sink? sink;
  final SyncEngine engine;
  int _n = 0;

  Future<String> author(String device) async {
    final oid = '$device-${_n++}';
    final seq = await mirror.nextAuthorSeq(book1, device);
    final blob = Uint8List.fromList(
      utf8.encode(jsonEncode({'author_seq': seq, 'id': oid})),
    );
    final rec = EnvelopeRecord(
      envelopeId: 'env-$oid',
      bookId: book1,
      objectId: oid,
      objectType: 'entry',
      keyVersion: 1,
      hlc: 1 << 16,
      authorDevice: device,
      authorSeq: seq,
      blob: blob,
      blobHash: fnv1a32(blob),
      verified: true,
    );
    await mirror.append(rec);
    await mirror.enqueue(
      envelopeId: rec.envelopeId,
      bookId: book1,
      blob: blob,
      createdAt: 1,
    );
    return rec.envelopeId;
  }

  Future<Map<String, String>> outbox() async => {
    for (final r in await mirror.outboxRows()) r.envelopeId: r.pushState,
  };
}

const _awaiting = RegisteredAwaitingTenant(deviceId: 'phone-a', userId: 'u-a');

WireMembership _row(String tenant, String user, String status) =>
    WireMembership(
      id: '$tenant:$user',
      tenantId: tenant,
      userId: user,
      status: status,
    );

void main() {
  late FakeSyncServer server;
  final dbs = <LedgerDatabase>[];

  setUp(() {
    server = FakeSyncServer(
      clock: ManualClock(1 << 40),
      rateLimits: RateLimits.none,
    );
  });

  tearDown(() async {
    for (final d in dbs) {
      await d.close();
    }
    dbs.clear();
  });

  Future<_Phone> phone({
    String session = 'phone-a',
    DeviceIdentity initial = _awaiting,
    bool learn = true,
    bool withSink = true,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final r = await openLedgerDatabase(NativeDatabase.memory());
    final db = (r as Opened).db;
    dbs.add(db);
    final identity = ManualIdentity(initial);
    return _Phone(
      db,
      Mirror(db, hasher: fnv1a32),
      _Transport(server.transportFor(session)),
      identity,
      withSink ? _Sink(identity, learn: learn) : null,
    );
  }

  /// Another phone of the tenant puts an envelope on the server.
  Future<String> otherPhonesEnvelope() async {
    final b = await phone(
      session: 'phone-b',
      initial: const RegisteredIdentity(
        deviceId: 'phone-b',
        userId: 'u-b',
        tenantId: tenant1,
      ),
      withSink: false,
    );
    final id = await b.author('phone-b');
    expect((await b.engine.sync()).acked, 1);
    return id;
  }

  test('C-1010-1 a registered device whose tenant is not known reads meta '
      'from the start every round and nothing else: no push is stamped, no '
      'envelope is pulled or opened, the outbox is untouched, and the round '
      'says why with a typed hold, raised once — never keys lost, corruption '
      'or Synced', () async {
    final theirs = await otherPhonesEnvelope();
    final a = await phone(learn: false);
    final queued = await a.author('phone-a');
    expect(a.engine.hold, SyncHold.tenantNotKnown);

    final r = await a.engine.sync();
    expect(r.held, SyncHold.tenantNotKnown);
    expect((r.pushed, r.acked, r.pulled, r.verified), (0, 0, 0, 0));
    expect(a.transport.pushes, 0, reason: 'no push stamped with a tenant');
    expect(a.transport.pulledBooks, isEmpty, reason: 'nothing pulled');
    expect(a.transport.metaAfters, [null], reason: 'meta, to learn');
    expect(await a.outbox(), {queued: 'queued'});
    expect(server.has(queued), isFalse);
    expect(
      await (a.db.select(
        a.db.envelopesLocal,
      )..where((t) => t.envelopeId.equals(theirs))).getSingleOrNull(),
      isNull,
      reason: 'no envelope opened under a tenant',
    );
    expect(await a.engine.status(), isNot(const Synced()));
    expect(a.engine.mode, EngineMode.active);

    final r2 = await a.engine.sync();
    expect(r2.held, SyncHold.tenantNotKnown);
    expect(a.transport.metaAfters, [
      null,
      null,
    ], reason: 'every awaiting round reads the whole feed, never a delta');
    expect(a.transport.pushes, 0);
    expect(eventsOf<SyncHeld>(a.engine).map((e) => e.reason), [
      SyncHold.tenantNotKnown,
    ]);
    for (final e in a.engine.events) {
      expect(
        e is Quarantined ||
            e is KeyWait ||
            e is Wiped ||
            e is KeysDropped ||
            e is Suspended ||
            e is RecordIgnored,
        isFalse,
        reason: '$e',
      );
    }
  });

  test('C-1010-2 a complete read hands over this user\'s active memberships '
      'only — another user\'s rows, a removed row and a tenant a verified '
      'record contradicts are left out', () async {
    server.memberships
      ..['t-A:u-a'] = _row('t-A', 'u-a', 'active')
      ..['t-B:u-a'] = _row('t-B', 'u-a', 'removed')
      ..['t-C:u-x'] = _row('t-C', 'u-x', 'active')
      ..['t-D:u-a'] = _row('t-D', 'u-a', 'active');
    final payload = Uint8List.fromList(
      utf8.encode(jsonEncode({'user_id': 'u-a', 'status': 'suspended'})),
    );
    server.addSignedRecord(
      WireSignedRecord(
        id: 'ms-1',
        suiteVersion: 1,
        tenantId: 't-D',
        kind: 'membership_status',
        payloadJson: payload,
        authorDeviceId: 'admin',
        authorSig: PlainGuard.sign('admin', payload),
        hlc: 0,
        seq: 0,
      ),
    );
    final a = await phone(learn: false);
    await a.engine.sync();
    expect(a.sink!.reads, hasLength(1));
    expect(a.sink!.reads.single.userId, 'u-a');
    expect(a.sink!.reads.single.activeTenantIds, {'t-A'});
  });

  test('C-1010-2 several pages: the tenants are handed over only once the '
      'whole feed is read, so a second active membership on a later page is '
      'never mistaken for none; a read cut short hands nothing over', () async {
    final a = await phone(learn: false);
    a.transport.pages = {
      null: MetaResponse(
        storeEpoch: server.storeEpoch,
        next: 'p1',
        hasMore: true,
        memberships: [_row('t-A', 'u-a', 'active')],
      ),
      'p1': const TransportOffline('cut'),
    };
    final cut = await a.engine.sync();
    expect(a.sink!.reads, isEmpty, reason: 'half a feed proves nothing');
    expect(cut.held, isNot(SyncHold.bindingChanged));
    expect(a.transport.pushes, 0);
    expect(a.transport.pulledBooks, isEmpty);

    a.transport.pages = {
      null: MetaResponse(
        storeEpoch: server.storeEpoch,
        next: 'p1',
        hasMore: true,
        memberships: [_row('t-A', 'u-a', 'active')],
      ),
      'p1': MetaResponse(
        storeEpoch: server.storeEpoch,
        next: 'p2',
        memberships: [_row('t-B', 'u-a', 'active')],
      ),
    };
    final r = await a.engine.sync();
    expect(a.transport.metaAfters, [null, 'p1', null, 'p1']);
    expect(a.sink!.reads.single.activeTenantIds, {'t-A', 't-B'});
    expect(r.held, SyncHold.tenantNotKnown, reason: 'several: fails closed');
    expect(a.transport.pushes, 0);
  });

  test('C-1010-2 a later page that removes the earlier page\'s membership '
      'wins: the read is the feed\'s last word per tenant', () async {
    final a = await phone(learn: false);
    a.transport.pages = {
      null: MetaResponse(
        storeEpoch: server.storeEpoch,
        next: 'p1',
        hasMore: true,
        memberships: [
          _row('t-A', 'u-a', 'active'),
          _row('t-B', 'u-a', 'active'),
        ],
      ),
      'p1': MetaResponse(
        storeEpoch: server.storeEpoch,
        next: 'p2',
        memberships: [_row('t-B', 'u-a', 'removed')],
      ),
    };
    await a.engine.sync();
    expect(a.sink!.reads.single.activeTenantIds, {'t-A'});
  });

  test('C-1010-2 a learned tenant takes effect without a relaunch: the round '
      'that learned it stops before any push, and the next one re-reads meta '
      'from the start and pushes stamped with the learned tenant', () async {
    final theirs = await otherPhonesEnvelope();
    server.memberships['$tenant1:u-a'] = _row(tenant1, 'u-a', 'active');
    final a = await phone();
    final queued = await a.author('phone-a');

    final r1 = await a.engine.sync();
    expect(r1.held, SyncHold.bindingChanged);
    expect(a.transport.pushes, 0, reason: 'nothing before the next round');
    expect(server.has(queued), isFalse);
    expect(a.engine.hold, isNull, reason: 'the source now answers a tenant');

    final r2 = await a.engine.sync();
    expect(r2.held, isNull);
    expect(r2.acked, 1);
    expect(r2.verified, 1, reason: "phone-b's envelope, now pulled");
    expect(server.stored.last.envelopeId, queued);
    expect(server.stored.last.tenantId, tenant1);
    expect(a.transport.metaAfters.first, isNull);
    expect(a.transport.metaAfters[1], isNull, reason: 're-read under the new');
    expect(a.sink!.reads, hasLength(1), reason: 'no read once it is known');
    expect(eventsOf<IdentityRebound>(a.engine), hasLength(1));
    expect(
      await (a.db.select(
        a.db.envelopesLocal,
      )..where((t) => t.envelopeId.equals(theirs))).getSingleOrNull(),
      isNotNull,
    );
  });

  test('C-1010-2 a device whose tenant is known never reads for it: a first '
      'device is unchanged', () async {
    server.memberships['t-other:u-a'] = _row('t-other', 'u-a', 'active');
    final a = await phone(
      initial: const RegisteredIdentity(
        deviceId: 'phone-a',
        userId: 'u-a',
        tenantId: tenant1,
      ),
    );
    final queued = await a.author('phone-a');
    final r = await a.engine.sync();
    expect(r.held, isNull);
    expect(r.acked, 1);
    expect(server.stored.last.tenantId, tenant1);
    expect(a.sink!.reads, isEmpty);
    expect(a.identity.identity, isA<RegisteredIdentity>());
    expect(server.has(queued), isTrue);
  });
}
