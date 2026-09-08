// Suite D — the engine over the in-memory server (05 §3–§5, §9; ADR
// 2026-09-05b §2–§7; ADR 2026-09-05i §9 clock-jump cases). Plaintext devices:
// every trust-boundary rule here is about seqs, cursors, rows and records, not
// ciphertext — the crypto path is `engine_crypto_test.dart`.
@Tags(['D'])
library;

import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _hour = 60 * 60 * 1000;
const _day = 24 * _hour;

void main() {
  late ManualClock clock;
  late FakeSyncServer server;
  final open = <PlainDevice>[];

  Future<PlainDevice> dev(
    String id, {
    String? user,
    Set<String> trusted = const {},
  }) async {
    final d = await PlainDevice.open(
      id,
      server: server,
      clock: clock,
      userId: user ?? 'u-$id',
      trustedDevices: trusted,
    );
    open.add(d);
    return d;
  }

  setUp(() {
    clock = ManualClock(1000 * _day);
    server = FakeSyncServer(clock: clock, rateLimits: RateLimits.none);
  });
  tearDown(() async {
    for (final d in open) {
      await d.close();
    }
    open.clear();
  });

  test('D-05-1 withheld envelope: the server drops one envelope from the pull; '
      'the reader shows the author gap (WaitingFor), Inbox at 24 h + 1 min, not '
      'at 23 h 59; a re-bootstrap after release closes the gap', () async {
    final a = await dev('phone-a');
    final b = await dev('phone-b');
    final recs = [
      for (var i = 0; i < 3; i++) await a.author(physicalMs: clock.nowMs() + i),
    ];
    server.withheld.add(recs[1].envelopeId);
    final ra = await a.engine.sync();
    expect(ra.acked, 3);
    expect(server.stored.length, 3);

    final rb = await b.engine.sync();
    expect(rb.pulled, 2);
    expect(rb.verified, 2);
    expect(await b.engine.status(), WaitingFor(a.id));
    final gaps = await b.mirror.recomputeAuthorGaps(book1);
    expect(gaps.single.expectedSeq, recs[1].authorSeq);

    clock.advance(23 * _hour + 59 * 60 * 1000);
    expect(await b.engine.status(), WaitingFor(a.id));
    clock.advance(2 * 60 * 1000);
    expect(
      await b.engine.status(),
      const NeedsAttention([AttentionReason.authorGapOverdue]),
    );

    // The cursor is past the hole — only a re-bootstrap (05 §8) can fill it.
    server.withheld.clear();
    await b.engine.sync();
    expect((await b.rows()).length, 2, reason: 'seq cursor cannot go back');
    await b.engine.rebootstrapBook(book1);
    final rb2 = await b.engine.sync();
    expect(rb2.pulled, 3);
    expect((await b.rows()).length, 3);
    expect(await b.mirror.recomputeAuthorGaps(book1), isEmpty);
    expect(await b.engine.status(), const Synced());
  });

  test(
    'D-05-8 read-your-writes: acked → observed on the device\'s own pull and '
    'pruned only then; a cursor that passes an acked seq without seeing it '
    're-pushes with write_lost',
    () async {
      final a = await dev('phone-a');
      final r0 = await a.author(physicalMs: clock.nowMs());
      final r1 = await a.author(physicalMs: clock.nowMs() + 1);
      // Pull fails this round: acked, but not yet observed → kept.
      a.transport.beforeCall = (route) {
        if (route == 'pull') throw const TransportOffline('pull dropped');
      };
      final r = await a.engine.sync();
      expect(r.acked, 2);
      expect(await a.outboxStates(), {
        r0.envelopeId: 'acked',
        r1.envelopeId: 'acked',
      });
      expect((await a.row(r0.envelopeId))!.seq, 1, reason: 'seq stored on ack');
      expect(await a.engine.status(), const Offline());

      a.transport.beforeCall = null;
      server.withheld.add(r1.envelopeId); // the server hides our own write
      await a.engine.sync();
      expect((await a.outboxStates())[r0.envelopeId], isNull, reason: 'pruned');
      expect(
        (await a.outboxStates())[r1.envelopeId],
        'queued',
        reason: 're-push',
      );
      expect(eventsOf<WriteLost>(a.engine).map((e) => e.envelopeId), [
        r1.envelopeId,
      ]);
      expect(
        await a.engine.status(),
        const NeedsAttention([AttentionReason.writeLost]),
      );

      server.withheld.clear();
      a.engine.dismiss(AttentionReason.writeLost);
      await a.engine.sync();
      expect(
        server.stored.length,
        2,
        reason: 'duplicate push stored nothing new (same seq)',
      );
      expect(
        (await a.outboxStates())[r1.envelopeId],
        'queued',
        reason:
            'the cursor is past seq 2 for good — only a re-bootstrap sees it',
      );
      a.engine.dismiss(AttentionReason.writeLost);
      await a.engine.rebootstrapBook(book1);
      await a.engine.sync();
      expect(await a.outboxStates(), isEmpty, reason: 'observed on re-pull');
      expect((await a.rows()).length, 2);
      expect((await a.row(r1.envelopeId))!.authorSeq, r1.authorSeq);
      expect(await a.engine.status(), const Synced());
    },
  );

  test('D-05-5 restore from backup: the epoch changes; a reader resets cursors '
      'and re-pulls with zero duplicates; an envelope acked before the restore '
      'but missing after it is re-pushed with write_lost', () async {
    final a = await dev('phone-a');
    final b = await dev('phone-b');
    final recs = [
      for (var i = 0; i < 3; i++) await a.author(physicalMs: clock.nowMs() + i),
    ];
    a.transport.beforeCall = (route) {
      if (route == 'pull') throw const TransportOffline('pull dropped');
    };
    await a.engine.sync(); // acked ×3, none observed
    a.transport.beforeCall = null;
    await b.engine.sync();
    expect((await b.rows()).length, 3);

    final dropped = server.restore(dropLast: 1);
    expect(dropped, [recs[2].envelopeId]);

    final rb = await b.engine.sync();
    expect(rb.epochChanged, isTrue);
    expect(rb.pulled, 2, reason: 'full re-pull from seq 0');
    expect((await b.rows()).length, 3, reason: 'zero duplicates, nothing lost');
    expect(await b.mirror.storeEpoch(), server.storeEpoch);

    final ra = await a.engine.sync();
    expect(ra.epochChanged, isTrue);
    expect(eventsOf<WriteLost>(a.engine).map((e) => e.envelopeId), [
      recs[2].envelopeId,
    ]);
    expect(server.has(recs[2].envelopeId), isTrue, reason: 're-pushed');
    expect(server.stored.length, 3);
    expect(
      await a.outboxStates(),
      isEmpty,
      reason: 'all observed after re-pull',
    );
  });

  test(
    'D-05-6 flood: rate_limited throttles (rows stay queued, no Inbox, no '
    'data loss); quota stops the book with Inbox; the book stays pullable',
    () async {
      server.rateLimits = const RateLimits(perMinute: 20, perHour: null);
      final a = await dev('phone-a');
      final b = await dev('phone-b');
      for (var i = 0; i < 50; i++) {
        await a.author(physicalMs: clock.nowMs() + i);
      }
      var r = await a.engine.sync();
      expect(r.acked, 20);
      expect(eventsOf<Throttled>(a.engine).length, 1);
      expect(await a.engine.status(), const SavedWillSync(30));
      r = await a.engine.sync();
      expect(r.pushed, 0, reason: 'honours retry_after');
      clock.advance(61 * 1000);
      r = await a.engine.sync();
      expect(r.acked, 20);
      expect(await a.engine.status(), const SavedWillSync(10));

      server.quotaPerBook[book1] = 45;
      clock.advance(61 * 1000);
      r = await a.engine.sync();
      expect(r.acked, 5);
      expect(eventsOf<QuotaStopped>(a.engine).single.bookId, book1);
      expect(
        await a.engine.status(),
        const NeedsAttention([AttentionReason.quota]),
      );
      expect(
        (await a.outboxStates()).values.where((s) => s == 'queued').length,
        5,
        reason: 'never lost',
      );
      clock.advance(61 * 1000);
      r = await a.engine.sync();
      expect(r.pushed, 0, reason: 'book stopped until the plan changes');

      final rb = await b.engine.sync();
      expect(rb.pulled, 45, reason: 'book stays readable and pullable');
      expect(
        eventsOf<Throttled>(a.engine).length,
        2,
        reason: 'one per throttled batch, never Inbox',
      );
    },
  );

  test(
    'D-05-3 unsigned revocation: a devices row (or a 401) says revoked with '
    'no signed record → suspended, nothing wiped; resumes when auth succeeds',
    () async {
      final a = await dev('phone-a');
      await a.author(physicalMs: clock.nowMs());
      await a.engine.sync();
      expect(await a.engine.status(), const Synced());

      server.devices[a.id] = deviceRow(a.id, a.userId, status: 'revoked');
      server.touchMeta();
      await a.engine.sync();
      expect(a.engine.mode, EngineMode.suspended);
      expect(eventsOf<Suspended>(a.engine).single.source, 'devices row');
      expect(eventsOf<Wiped>(a.engine), isEmpty);
      expect((await a.rows()).length, 1, reason: 'data stays');
      expect(
        await a.engine.status(),
        const NeedsAttention([AttentionReason.suspended]),
      );
      await a.author(physicalMs: clock.nowMs() + 1);
      final r = await a.engine.sync();
      expect(r.pushed, 0, reason: 'sync stops while suspended');

      server.devices[a.id] = deviceRow(a.id, a.userId);
      server.touchMeta();
      await a.engine.sync();
      expect(a.engine.mode, EngineMode.active);
      expect(eventsOf<Resumed>(a.engine).length, 1);
      expect(await a.engine.status(), const Synced());

      server.authRevoked.add(a.id);
      await a.engine.sync();
      expect(a.engine.mode, EngineMode.suspended);
      expect(eventsOf<Suspended>(a.engine).last.source, '401 device_revoked');
      server.authRevoked.remove(a.id);
      await a.engine.sync();
      expect(a.engine.mode, EngineMode.active);
      expect(eventsOf<Wiped>(a.engine), isEmpty);
    },
  );

  test('D-05-4 stolen-phone backdate: a revoked device pushes an envelope with '
      'last week\'s HLC; its seq is above the signed revocation\'s → quarantined '
      'by the reader; its earlier envelope stays valid; the revoked device '
      'itself wipes only on the verified record', () async {
    const stolen = 'phone-c';
    const otherOwn = 'phone-c2';
    final c = await dev(stolen, user: 'u-c');
    final b = await dev('phone-b', trusted: {otherOwn});
    server.devices[stolen] = deviceRow(stolen, 'u-c');
    server.devices[otherOwn] = deviceRow(otherOwn, 'u-c');

    final before = await c.author(physicalMs: clock.nowMs());
    await c.engine.sync(); // seq 1
    final rev = server.addSignedRecord(
      plainRecord(
        id: 'rev-1',
        kind: 'device_revocation',
        author: otherOwn,
        payload: {'revoked_device_id': stolen, 'subject_user_id': 'u-c'},
      ),
    );
    expect(rev.seq, 2);
    // The stolen phone stamps last week's HLC (author-controlled) and pushes.
    final after = await c.author(
      physicalMs: clock.nowMs(),
      hlcOverride: (clock.nowMs() - 7 * _day) << 16,
    );
    // Its own pull/meta would fetch the record; push first, as a thief would.
    c.transport.beforeCall = (route) {
      if (route != 'push') throw const TransportOffline('thief blocks meta');
    };
    // Meta runs first in a round and fails → round stops; push directly.
    final res = server.push(
      stolen,
      PushRequest(
        envelopes: [
          WireEnvelope(
            envelopeId: after.envelopeId,
            tenantId: tenant1,
            bookId: book1,
            objectId: after.objectId,
            objectType: 'entry',
            keyVersion: 1,
            suiteVersion: 1,
            payloadSchema: 1,
            authorDevice: stolen,
            hlc: after.hlc,
            blobHash: after.blobHash,
            blob: after.blob,
          ),
        ],
      ),
    );
    expect(res.results.single.seq, 3);

    final rb = await b.engine.sync();
    expect(rb.pulled, 2);
    expect((await b.row(before.envelopeId))!.verified, 1);
    final q = (await b.row(after.envelopeId))!;
    expect(q.quarantined, 1);
    expect(q.quarantineReason, 'revoked');
    expect(b.trust.revocationSeqOf(stolen), 2);
    expect(
      await b.engine.status(),
      const NeedsAttention([AttentionReason.quarantine]),
    );

    // The revoked phone: the verified record is what wipes it (05 §5).
    c.transport.beforeCall = null;
    c.trust.deviceOwners[otherOwn] = 'u-c';
    (c.engine.guard as PlainGuard).trustedDevices.add(otherOwn);
    await c.engine.sync();
    expect(c.engine.mode, EngineMode.wiped);
    expect(eventsOf<Wiped>(c.engine).single.recordId, 'rev-1');
    expect(await c.rows(), isEmpty);
  });

  test('D-05-9 offline: pushes back off exponentially and the status is '
      'Offline; a connectivity change resets the schedule', () async {
    final a = await dev('phone-a');
    await a.author(physicalMs: clock.nowMs());
    a.transport.online = false;
    var r = await a.engine.sync();
    expect(r.offline, isTrue);
    expect(await a.engine.status(), const Offline());
    expect(a.engine.backoff.attempt, 0, reason: 'meta failed before any push');
    a.transport.online = true;
    a.transport.beforeCall = (route) {
      if (route == 'push') throw const TransportOffline('push dropped');
    };
    r = await a.engine.sync();
    expect(a.engine.backoff.attempt, 1);
    expect(a.engine.retryPushAtMs, clock.nowMs() + 1000);
    expect((await a.outboxStates()).values.single, 'queued');
    clock.advance(1000);
    await a.engine.sync();
    expect(a.engine.backoff.attempt, 2);
    expect(a.engine.retryPushAtMs, clock.nowMs() + 2000);
    a.transport.beforeCall = null;
    r = await a.engine.sync();
    expect(r.pushed, 0, reason: 'still inside the backoff window');
    a.engine.connectivityChanged();
    r = await a.engine.sync();
    expect(r.acked, 1);
    expect(await a.engine.status(), const Synced());
  });

  test(
    'D-05-10 every 05 §3 result code is handled: hlc_future → clock warning; '
    'membership_not_active/no_role/unknown_book → Inbox + stop the book; '
    'too_large/version → terminal; key_version_stale with no newer key → '
    'Inbox; tenant_frozen → queued + Inbox, lifts; 426 → update required',
    () async {
      final a = await dev('phone-a');
      // hlc_future
      await a.author(
        physicalMs: clock.nowMs(),
        hlcOverride: (clock.nowMs() + 10 * 60 * 1000) << 16,
      );
      await a.engine.sync();
      expect(
        eventsOf<PushRejected>(a.engine).single.result,
        'rejected:hlc_future',
      );
      expect(
        await a.engine.status(),
        const NeedsAttention([
          AttentionReason.rejection,
          AttentionReason.clockWarning,
        ]),
      );
      a.engine.dismiss(AttentionReason.rejection);
      a.engine.dismiss(AttentionReason.clockWarning);

      // membership_not_active stops the book.
      server.inactiveDevices.add(a.id);
      final r1 = await a.author(physicalMs: clock.nowMs() + 1);
      await a.author(physicalMs: clock.nowMs() + 2);
      var r = await a.engine.sync();
      expect(r.pushed, 2);
      expect((await a.outboxStates())[r1.envelopeId], 'rejected');
      expect(a.engine.pushBlockedBooks, {book1});
      server.inactiveDevices.remove(a.id);
      r = await a.engine.sync();
      expect(r.pushed, 0, reason: 'stopped until a record says otherwise');
      a.engine.resumeBook(book1);

      // too_large, version: terminal per envelope, the rest of the batch goes on.
      server.maxEnvelopeBytes = 10;
      await a.author(physicalMs: clock.nowMs() + 3);
      r = await a.engine.sync();
      expect(
        eventsOf<PushRejected>(a.engine).last.result,
        'rejected:too_large',
      );
      server.maxEnvelopeBytes = 256 * 1024;
      server.maxPayloadSchema = 0;
      await a.author(physicalMs: clock.nowMs() + 3);
      await a.engine.sync();
      expect(eventsOf<PushRejected>(a.engine).last.result, 'rejected:version');
      server.maxPayloadSchema = 1;

      // key_version_stale without a newer key → Inbox, no retry loop.
      server.minKeyVersion[book1] = 2;
      final stale = await a.author(physicalMs: clock.nowMs() + 4);
      await a.engine.sync();
      expect(
        eventsOf<PushRejected>(a.engine).last.result,
        'rejected:key_version_stale',
      );
      expect((await a.outboxStates())[stale.envelopeId], 'rejected');
      server.minKeyVersion.remove(book1);

      // tenant_frozen: queued, Inbox, pull continues, lifts.
      server.frozen = true;
      final frozen = await a.author(physicalMs: clock.nowMs() + 5);
      r = await a.engine.sync();
      expect((await a.outboxStates())[frozen.envelopeId], 'queued');
      expect(eventsOf<TenantFrozen>(a.engine).length, 1);
      expect(
        (await a.engine.status() as NeedsAttention).reasons,
        contains(AttentionReason.tenantFrozen),
      );
      expect(a.transport.calls.last, 'pull', reason: 'pull continues');
      server.frozen = false;
      a.engine.freezeLifted();
      r = await a.engine.sync();
      expect(r.acked, 1);

      // no_role / unknown_book
      server.noRoleBooks.add('b2');
      await a.author(physicalMs: clock.nowMs() + 6, bookId: 'b2');
      await a.engine.sync();
      expect(eventsOf<PushRejected>(a.engine).last.result, 'rejected:no_role');
      expect(a.engine.pushBlockedBooks, contains('b2'));
      server.unknownBooks.add('b3');
      await a.author(physicalMs: clock.nowMs() + 7, bookId: 'b3');
      await a.engine.sync();
      expect(
        eventsOf<PushRejected>(a.engine).last.result,
        'rejected:unknown_book',
      );

      // 426
      server.updateRequired = true;
      await a.engine.sync();
      expect(a.engine.mode, EngineMode.updateRequired);
      expect(
        (await a.engine.status() as NeedsAttention).reasons,
        contains(AttentionReason.updateRequired),
      );
    },
  );

  test('D-05b-1 meta_mismatch: the server fabricates a limit change without a '
      'record; the client keeps the record\'s value and logs', () async {
    const admin = 'phone-admin';
    final a = await dev('phone-a', trusted: {admin});
    server.devices[admin] = deviceRow(admin, 'u-admin');
    server.addSignedRecord(
      plainRecord(
        id: 'role-1',
        kind: 'book_role',
        author: admin,
        payload: {
          'book_id': book1,
          'user_id': a.userId,
          'role': 'member',
          'limits': {'per_entry_paise': 500000},
        },
      ),
    );
    server.bookRoles['br-1'] = WireBookRole(
      id: 'br-1',
      bookId: book1,
      userId: a.userId,
      role: 'member',
      limits: const {'per_entry_paise': 5000000},
    );
    server.bookRoles['br-2'] = WireBookRole(
      id: 'br-2',
      bookId: 'b9',
      userId: a.userId,
      role: 'admin',
    );
    await a.engine.sync();
    final mm = eventsOf<MetaMismatch>(a.engine);
    expect(mm.map((m) => m.rowId), ['br-1', 'br-2']);
    expect(mm[0].detail, contains('role-1'));
    expect(mm[1].detail, 'no signed record');
    expect(a.engine.roleOf(book1, a.userId)!.limits, {
      'per_entry_paise': 500000,
    });
    expect(a.engine.roleOf('b9', a.userId), isNull);
    // An unsigned record is ignored and logged.
    final forged = plainRecord(
      id: 'role-forged',
      kind: 'book_role',
      author: 'phone-nobody',
      payload: {'book_id': book1, 'user_id': a.userId, 'role': 'admin'},
    );
    server.addSignedRecord(forged);
    await a.engine.sync();
    expect(eventsOf<RecordIgnored>(a.engine).single.recordId, 'role-forged');
    expect(a.engine.roleOf(book1, a.userId)!.role, 'member');
    final stored = await a.db.select(a.db.signedRecordsLocal).get();
    expect(
      {for (final r in stored) r.id: r.verified},
      {'role-1': 1, 'role-forged': 0},
    );
  });
}
