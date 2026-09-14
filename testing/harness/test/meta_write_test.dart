// Suite D — the write half of `/sync-meta` on the two-client harness: one
// device *publishes* a structural fact and the other believes it (ADR
// 2026-09-05b §1 🔒), and 06 §7's invitation machine end to end (ADR
// 2026-09-05d §9 🔒).
//
// Until this round the engine's transport seam had no way to publish at all:
// a device could pull every fact the family authored and contribute none of
// its own. These tests run the real engine over the in-memory server, so the
// seam that the app's HTTPS transport implements is the seam a test exercises.
@Tags(['D'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:harness/harness.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

const _book = 'b1';
const _tenant = 't1';
const _inviteePhone = '+919876500011';
const _otherPhone = '+919876500022';

Uint8List _json(Map<String, Object?> payload) =>
    Uint8List.fromList(utf8.encode(jsonEncode(payload)));

/// A record authored on [device], signed the way [PlainGuard] verifies it.
WireRecordPost _record({
  required String id,
  required String device,
  required String kind,
  required Map<String, Object?> payload,
  int hlc = 1,
}) {
  final bytes = _json(payload);
  return WireRecordPost(
    id: id,
    suiteVersion: 1,
    tenantId: _tenant,
    kind: kind,
    payloadJson: bytes,
    authorDeviceId: device,
    authorSig: PlainGuard.sign(device, bytes),
    hlc: hlc,
  );
}

/// A 128-bit ceremony nonce, deterministic (no `Random()` in a pure package).
String _nonce(int seed) => base64Url
    .encode(Uint8List.fromList(List<int>.generate(16, (i) => seed + i)))
    .replaceAll('=', '');

WireRecordPost _inviteRecord(String id, {int seed = 1}) => _record(
  id: id,
  device: 'phone-a',
  kind: 'invite',
  payload: {
    'roles': [
      {'book_id': _book, 'role': 'member'},
    ],
    'nonce': _nonce(seed),
  },
);

final class _Rig {
  _Rig(this.s, this.server, this.admin, this.joiner);

  final Scheduler s;
  final FakeSyncServer server;

  /// The tenant admin's phone (a certified device, 06 §1.0).
  final SyncedDevice admin;

  /// The second phone — not in the tenant until it accepts an invite.
  final SyncedDevice joiner;

  static Future<_Rig> open() async {
    final s = Scheduler();
    final server = FakeSyncServer(
      clock: SchedulerClock(s),
      rateLimits: RateLimits.none,
    );
    final admin = await SyncedDevice.open(
      'phone-a',
      server: server,
      scheduler: s,
      userId: 'u-a',
      books: {_book},
      trustedDevices: {'phone-a'},
    );
    final joiner = await SyncedDevice.open(
      'phone-b',
      server: server,
      scheduler: s,
      userId: 'u-b',
      books: {_book},
      // 04 §3.4: the joiner believes a record because the author's device is
      // certified, not because the server relayed it.
      trustedDevices: {'phone-a'},
    );
    server
      ..adminDevices.add('phone-a')
      ..devicePhones['phone-b'] = _inviteePhone;
    return _Rig(s, server, admin, joiner);
  }

  Future<void> close() async {
    await admin.close();
    await joiner.close();
  }
}

void main() {
  test('D-05-32 a device publishes a signed record and the other device '
      'believes it: POST /sync-meta/records stamps a seq, the meta pull '
      'carries the record, the reader keeps the RECORD\'s value and the '
      'server row is only its projection', () async {
    final r = await _Rig.open();
    final rec = _record(
      id: 'rec-role-1',
      device: 'phone-a',
      kind: 'book_role',
      payload: {'book_id': _book, 'user_id': 'u-b', 'role': 'member'},
    );

    final res = await r.admin.transport.postRecords(
      PostRecordsRequest(records: [rec]),
    );
    expect(res.storeEpoch, r.server.storeEpoch);
    final ack = res[rec.id]!;
    expect(ack.isAcked, isTrue, reason: ack.result);
    expect(ack.seq, greaterThan(0), reason: 'the server stamps the sequence');
    expect(r.admin.transport.calls, contains('records'));

    // The server projected it onto its own row — the copy, never the source.
    expect(r.server.bookRoles['$_book:u-b']!.role, 'member');

    await r.joiner.sync();
    final fact = r.joiner.engine.roleOf(_book, 'u-b');
    expect(fact, isNotNull, reason: 'the record reached the reader');
    expect(fact!.role, 'member');
    expect(fact.recordId, rec.id, reason: 'believed through the record');
    expect(fact.seq, ack.seq);
    expect(
      r.joiner.engine.events.whereType<MetaMismatch>(),
      isEmpty,
      reason: 'row and record agree',
    );

    // Idempotent: the same record posted twice is one record, one seq.
    final again = await r.admin.transport.postRecords(
      PostRecordsRequest(records: [rec]),
    );
    expect(again[rec.id]!.isAcked, isTrue);
    expect(again[rec.id]!.seq, ack.seq, reason: 'a replay is the same fact');
    expect(r.server.signedRecords.where((x) => x.id == rec.id), hasLength(1));
    await r.close();
  });

  test(
    'D-05-33 a record the author may not write is kept and refused, not '
    'silently dropped: a non-admin\'s book_role is stored with its refusal, '
    'an `invite` record on the generic route is rejected:invite_route, and '
    'a record signed for another device never becomes a record at all',
    () async {
      final r = await _Rig.open();
      // The joiner's own device authors a role grant for itself.
      final grab = _record(
        id: 'rec-grab',
        device: 'phone-b',
        kind: 'book_role',
        payload: {'book_id': _book, 'user_id': 'u-b', 'role': 'admin'},
      );
      final refused = await r.joiner.transport.postRecords(
        PostRecordsRequest(records: [grab]),
      );
      expect(refused[grab.id]!.rejection, 'unauthorized');
      expect(
        refused[grab.id]!.seq,
        isNotNull,
        reason: 'stored anyway: a signed fact is append-only (ADR 05b §1)',
      );
      expect(r.server.bookRoles['$_book:u-b'], isNull, reason: 'not applied');

      // 0008 ⚠️ SPEC / 06 §7: the generic route has no number to HMAC, so it is
      // not a second way to mint an invite.
      final viaRecords = await r.admin.transport.postRecords(
        PostRecordsRequest(records: [_inviteRecord('rec-invite-1')]),
      );
      expect(viaRecords['rec-invite-1']!.result, RecordAck.rejectedInviteRoute);
      expect(r.server.invites, isEmpty, reason: 'no invite without the route');

      // `intakeRecord`: the author_device must be the calling device.
      final forged = _record(
        id: 'rec-forged',
        device: 'phone-a',
        kind: 'book_role',
        payload: {'book_id': _book, 'user_id': 'u-b', 'role': 'admin'},
      );
      final forgery = await r.joiner.transport.postRecords(
        PostRecordsRequest(records: [forged]),
      );
      expect(forgery[forged.id]!.result, RecordAck.rejectedShape);
      expect(forgery[forged.id]!.check, 'author_device_id');
      expect(forgery[forged.id]!.seq, isNull, reason: 'never stored');
      expect(
        r.server.signedRecords.where((x) => x.id == 'rec-forged'),
        isEmpty,
      );
      await r.close();
    },
  );

  test('D-05-34 06 §7 end to end: the admin issues an invite from a signed '
      'record plus the number, the invited phone is offered exactly that '
      'invite and accepts into joined_pending_verification (never active), '
      'and replaying the record mints no second invite', () async {
    final r = await _Rig.open();
    final record = _inviteRecord('rec-invite-1');

    final issued = await r.admin.transport.createInvite(
      CreateInviteRequest(record: record, phone: _inviteePhone),
    );
    expect(issued.recordId, record.id);
    expect(issued.seq, greaterThan(0));
    final row = r.server.invites.single;
    expect(row.id, issued.inviteId);
    expect(row.recordId, record.id, reason: 'the row is the record\'s copy');
    expect(row.createdBy, 'phone-a');
    expect(
      row.expiresAtMs - row.createdAtMs,
      7 * 24 * 3600 * 1000,
      reason: '06 §7: a 7-day window, stamped server-side',
    );

    // rule 4 / ADR 2026-09-05c §4: the plaintext number is in no row and no
    // record — it travelled once, was hashed, and was dropped.
    final dump = jsonEncode([
      for (final i in r.server.invites)
        {
          'id': i.id,
          'hash': i.inviteeHash,
          'roles': i.roles,
          'by': i.createdBy,
        },
      for (final s in r.server.signedRecords) utf8.decode(s.payloadJson),
    ]);
    for (final shape in [_inviteePhone, '9876500011']) {
      expect(dump.contains(shape), isFalse, reason: 'the number leaked');
    }

    final offers = await r.joiner.transport.myInvites();
    expect(offers, hasLength(1));
    expect(offers.single.inviteId, issued.inviteId);
    expect(offers.single.tenantId, _tenant);
    expect(offers.single.roleGrants.single['role'], 'member');
    expect(offers.single.expiresAtMs, row.expiresAtMs);

    final accepted = await r.joiner.transport.acceptInvite(issued.inviteId);
    expect(accepted.status, InviteAcceptance.joinedPendingVerification);
    expect(
      r.server.memberships['$_tenant:phone-b']!.status,
      InviteAcceptance.joinedPendingVerification,
      reason: '06 §7: only the ceremony grants active',
    );
    expect(r.server.invites.single.status, FakeInvite.accepted);
    expect(await r.joiner.transport.myInvites(), isEmpty, reason: 'spent');

    // The record IS the action: a retry of the same signed record must not
    // mint a second invite (which would revoke the first, 06 §7's re-invite).
    await expectLater(
      r.admin.transport.createInvite(
        CreateInviteRequest(record: record, phone: _inviteePhone),
      ),
      throwsA(
        isA<RouteRefused>()
            .having((e) => e.code, 'code', RouteRefused.recordReplayed)
            .having((e) => e.status, 'status', 409),
      ),
    );
    expect(r.server.invites, hasLength(1));
    await r.close();
  });

  test('D-05-35 the link alone admits nobody: a wrong number is refused '
      'byte-identically to an invite id that does not exist, an expired '
      'invite is refused at accept time however stale the sweep, and a '
      'non-admin cannot issue one at all (ADR 2026-09-05d §9)', () async {
    final r = await _Rig.open();
    r.server.devicePhones['phone-a'] = _otherPhone;
    final issued = await r.admin.transport.createInvite(
      CreateInviteRequest(
        record: _inviteRecord('rec-invite-1'),
        phone: _inviteePhone,
      ),
    );

    // The same link on the wrong phone, and an id that never existed: one
    // code, one status — the route is no oracle for who was invited.
    RouteRefused? wrongNumber;
    RouteRefused? unknownId;
    try {
      await r.admin.transport.acceptInvite(issued.inviteId);
    } on RouteRefused catch (e) {
      wrongNumber = e;
    }
    try {
      await r.admin.transport.acceptInvite('invite-does-not-exist');
    } on RouteRefused catch (e) {
      unknownId = e;
    }
    expect(wrongNumber!.code, RouteRefused.inviteNotForYou);
    expect(wrongNumber.status, 403);
    expect(unknownId!.code, wrongNumber.code);
    expect(unknownId.status, wrongNumber.status);
    expect(
      r.server.memberships['$_tenant:phone-a'],
      isNull,
      reason: 'nothing moved',
    );
    expect(
      r.server.invites.single.status,
      FakeInvite.sent,
      reason: 'still live',
    );

    // 06 §7's 7-day window binds lazily, at accept time.
    r.s.run(untilMs: 7 * 24 * 3600 * 1000 + 1000);
    expect(await r.joiner.transport.myInvites(), isEmpty, reason: 'stale');
    await expectLater(
      r.joiner.transport.acceptInvite(issued.inviteId),
      throwsA(
        isA<RouteRefused>()
            .having((e) => e.code, 'code', RouteRefused.inviteExpired)
            .having((e) => e.status, 'status', 410),
      ),
    );
    expect(r.server.invites.single.status, FakeInvite.expired);
    expect(r.server.memberships['$_tenant:phone-b'], isNull);

    // Issuing is an admin power, and a number that is not E.164 never reaches
    // the hash (`_shared/phone.ts` normaliseE164).
    await expectLater(
      r.joiner.transport.createInvite(
        CreateInviteRequest(
          record: _record(
            id: 'rec-invite-2',
            device: 'phone-b',
            kind: 'invite',
            payload: {'roles': <Object?>[], 'nonce': _nonce(9)},
          ),
          phone: _inviteePhone,
        ),
      ),
      throwsA(
        isA<RouteRefused>().having(
          (e) => e.code,
          'code',
          RouteRefused.notAdmin,
        ),
      ),
    );
    await expectLater(
      r.admin.transport.createInvite(
        CreateInviteRequest(
          record: _inviteRecord('rec-invite-3', seed: 3),
          phone: '98765',
        ),
      ),
      throwsA(
        isA<RouteRefused>().having(
          (e) => e.code,
          'code',
          RouteRefused.badPhone,
        ),
      ),
    );
    expect(r.server.invites, hasLength(1), reason: 'no invite was minted');
    await r.close();
  });
}
