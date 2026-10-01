// D-05g-1 … D-05g-8 — the client half of ADR 2026-09-05g §2 / §6 🔒: the
// server's three hard-cap refusals (`0019_seat_and_book_caps.sql`, M13-CAP1)
// reach the caller as ONE typed, terminal refusal it can switch on — never a
// generic route failure, never a retry.
//
// The contract lines over there:
//   * `sync-meta/index.ts` `CAP_REFUSALS` = {seat_cap, seat_rotation_cap,
//     book_cap} — the database's P0001 names, passed through by name;
//   * `inviteError`: `POST /sync-meta/invites` answers `409 {error: <name>}`;
//   * `/records`: a record the cap refuses is `{id, result: "rejected:<name>",
//     check: <name>}` inside a 200 — no `seq` (`_tests/seat_caps_route.test.ts`
//     E-05g-14).
//
// Why "terminal" is load-bearing and not tidiness: on BOTH routes the signed
// record is stored before the cap answers (append-only, savepoint per write,
// `_shared/store_pg.ts`). Re-sending the SAME record therefore never re-asks
// the cap — `/invites` answers `409 record_replayed` ("the first one stands",
// which is false here) and `/records` answers `acked` for the duplicate
// although nothing was applied. A caller that retried a cap refusal would be
// told it had succeeded. After an upgrade the only honest retry is a NEW
// signed record.
@Tags(['D'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _root = 'https://rukka.example/functions/v1/';
const _tenant = 't1';
const _admin = 'dev-admin';
const _stranger = 'dev-stranger';

/// Synthetic numbers only (check_purity: +91 99999 xxxxx).
const _phone = '+919999900011';

Uint8List _json(Object o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));

WireRecordPost _record(
  String id,
  String kind,
  Map<String, Object?> payload, {
  String device = _admin,
}) => WireRecordPost(
  id: id,
  suiteVersion: 1,
  tenantId: _tenant,
  kind: kind,
  payloadJson: _json(payload),
  authorDeviceId: device,
  authorSig: Uint8List(64),
  hlc: 1 << 16,
);

WireRecordPost _invite(String id, {String device = _admin}) =>
    _record(id, 'invite', {
      'roles': [
        {'book_id': 'b1', 'role': 'member'},
      ],
      'nonce': base64Url.encode(Uint8List(16)),
    }, device: device);

/// An [HttpSyncTransport] whose every answer is [status] + [body], counting
/// the requests that actually left.
({HttpSyncTransport transport, List<http.Request> sent}) _http(
  int status,
  Object body,
) {
  final sent = <http.Request>[];
  final t = HttpSyncTransport(
    client: MockClient((req) async {
      sent.add(req);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
    functionsRoot: Uri.parse(_root),
    credentials: StaticSyncCredentials('jwt-token'),
    clientVersion: '1.4.0',
    pins: const SpkiPins.localDev(),
  );
  return (transport: t, sent: sent);
}

/// What a caller does with the typed refusal: an exhaustive switch — no
/// default arm, so a fourth cap would not compile past this line.
String _nextStep(PlanCap cap) => switch (cap) {
  PlanCap.seats => 'plans:seats',
  PlanCap.seatRotation => 'plans:rotation',
  PlanCap.businessBooks => 'plans:books',
};

void main() {
  group('D-05g-1 the three names are the server’s own', () {
    test('D-05g-1 PlanCap spells exactly sync-meta’s CAP_REFUSALS, and the '
        'record-route results are those names behind `rejected:`', () {
      // Read the contract itself, not a copy of it: a rename on either side
      // fails here, in `dart test`, instead of as a generic error on a phone.
      final src = File('../../server/supabase/functions/sync-meta/index.ts')
          .readAsStringSync();
      final decl = RegExp(r'CAP_REFUSALS[^=]*=\s*new Set\(\[([^\]]*)\]\)')
          .firstMatch(src);
      expect(decl, isNotNull, reason: 'CAP_REFUSALS moved or was renamed');
      final server = {
        for (final m in RegExp(r'"([a-z_]+)"').allMatches(decl![1]!)) m[1]!,
      };
      expect({for (final c in PlanCap.values) c.wire}, server);

      expect(PlanCap.seats.wire, 'seat_cap');
      expect(PlanCap.seatRotation.wire, 'seat_rotation_cap');
      expect(PlanCap.businessBooks.wire, 'book_cap');
      expect(RecordAck.rejectedSeatCap, 'rejected:seat_cap');
      expect(RecordAck.rejectedSeatRotationCap, 'rejected:seat_rotation_cap');
      expect(RecordAck.rejectedBookCap, 'rejected:book_cap');
      for (final c in PlanCap.values) {
        expect(PlanCap.fromWire(c.wire), c);
      }
      // Never guessed: a near-miss, an empty name and null are not caps.
      for (final other in ['seat', 'seats_cap', 'quota', '', null]) {
        expect(PlanCap.fromWire(other), isNull, reason: '$other');
      }
    });
  });

  group('D-05g-2 409 on /sync-meta/invites is a typed, terminal refusal', () {
    test('D-05g-2 seat_cap and seat_rotation_cap come back as PlanCapRefused '
        'naming the cap — not a RouteRefused, not Offline — after exactly one '
        'request', () async {
      for (final (name, cap) in [
        ('seat_cap', PlanCap.seats),
        ('seat_rotation_cap', PlanCap.seatRotation),
      ]) {
        final rig = _http(409, {'error': name});
        Object? thrown;
        try {
          await rig.transport.createInvite(
            CreateInviteRequest(record: _invite('rec-1'), phone: _phone),
          );
        } on Object catch (e) {
          thrown = e;
        }
        expect(thrown, isA<PlanCapRefused>(), reason: name);
        final refused = thrown! as PlanCapRefused;
        expect(refused.cap, cap);
        expect(refused.status, 409);
        expect(refused.code, name);
        expect(thrown, isNot(isA<RouteRefused>()));
        expect(thrown, isNot(isA<TransportOffline>()));
        expect(_nextStep(refused.cap), startsWith('plans:'));
        expect(
          rig.sent,
          hasLength(1),
          reason: 'the transport never re-sends a cap refusal on its own',
        );
      }
    });

    test('D-05g-2 the one mapping every door shares types all three names — '
        'book_cap included, for the book-create route CAP1 left to come', () {
      for (final cap in PlanCap.values) {
        final f = TransportFailure.fromHttp(409, {'error': cap.wire});
        expect(f, isA<PlanCapRefused>().having((e) => e.cap, 'cap', cap));
      }
    });
  });

  group('D-05g-3 nothing else is mistaken for a cap', () {
    test('D-05g-3 the other 409s keep their own names, and a cap name on a '
        'status the contract does not use is not claimed as one', () {
      for (final code in [
        RouteRefused.recordReplayed,
        RouteRefused.inviteNotLive,
        'no_record',
      ]) {
        final f = TransportFailure.fromHttp(409, {'error': code});
        expect(f, isA<RouteRefused>().having((e) => e.code, 'code', code));
      }
      // ⚠️ WIRE: the contract is 409 (`inviteError`). `inviteError`'s default
      // arm would answer a stray `book_cap` as 403 — that is the server's to
      // fix, and the client does not paper over it by guessing.
      final off = TransportFailure.fromHttp(403, {'error': 'book_cap'});
      expect(off, isA<RouteRefused>().having((e) => e.status, 'status', 403));
      // The status rules stay first: 401 is still auth, 413 still batch.
      expect(
        TransportFailure.fromHttp(401, {'error': 'seat_cap'}),
        isA<AuthFailed>(),
      );
      expect(
        TransportFailure.fromHttp(413, {'error': 'seat_cap'}),
        isA<BatchTooLarge>(),
      );
    });
  });

  group('D-05g-4 rejected:<cap> on /sync-meta/records', () {
    test('D-05g-4 a refused record in E-05g-14’s exact shape (check = name, no '
        'seq) reads as its cap; unauthorized, acked and unknown names read as '
        'no cap', () async {
      final rig = _http(200, {
        'store_epoch': 'e1',
        'results': [
          {'id': 'r1', 'result': 'rejected:seat_cap', 'check': 'seat_cap'},
          {
            'id': 'r2',
            'result': 'rejected:seat_rotation_cap',
            'check': 'seat_rotation_cap',
          },
          {'id': 'r3', 'result': 'rejected:book_cap', 'check': 'book_cap'},
          {'id': 'r4', 'result': 'rejected:unauthorized', 'check': 'rls'},
          {'id': 'r5', 'result': 'acked', 'seq': '12'},
          {'id': 'r6', 'result': 'rejected:seat_capacity'},
        ],
      });
      final res = await rig.transport.postRecords(
        PostRecordsRequest(
          records: [
            for (var i = 1; i <= 6; i++)
              _record('r$i', 'membership_status', {'user_id': 'u$i'}),
          ],
        ),
      );
      expect(res['r1']!.planCap, PlanCap.seats);
      expect(res['r2']!.planCap, PlanCap.seatRotation);
      expect(res['r3']!.planCap, PlanCap.businessBooks);
      for (final id in ['r1', 'r2', 'r3']) {
        expect(res[id]!.isAcked, isFalse, reason: id);
        expect(res[id]!.seq, isNull, reason: 'the catch arm sends no seq');
        expect(res[id]!.check, res[id]!.planCap!.wire);
      }
      expect(res['r1']!.result, RecordAck.rejectedSeatCap);
      expect(res['r4']!.planCap, isNull);
      expect(res['r5']!.planCap, isNull);
      expect(res['r6']!.planCap, isNull, reason: 'never guessed from a prefix');
    });
  });

  group('D-05g-5 the fake server refuses invites by cap, after admission', () {
    late FakeSyncServer server;
    setUp(() {
      server = FakeSyncServer(clock: ManualClock(1000))
        ..adminDevices.add(_admin);
    });

    test('D-05g-5 each seat cap is producible: typed through FakeTransport, '
        'no invite row minted, the signed record kept (append-only)', () async {
      for (final cap in [PlanCap.seats, PlanCap.seatRotation]) {
        server.inviteCap = cap;
        final id = 'rec-${cap.wire}';
        await expectLater(
          server
              .transportFor(_admin)
              .createInvite(
                CreateInviteRequest(record: _invite(id), phone: _phone),
              ),
          throwsA(
            isA<PlanCapRefused>()
                .having((e) => e.cap, 'cap', cap)
                .having((e) => e.status, 'status', 409),
          ),
        );
        expect(server.invites, isEmpty);
        expect(server.signedRecords.map((r) => r.id), contains(id));
      }
    });

    test('D-05g-5 re-sending the refused record is a replay, never a second '
        'ask and never an invite — so a retry after an upgrade must be a new '
        'record', () async {
      server.inviteCap = PlanCap.seats;
      final t = server.transportFor(_admin);
      final refused = _invite('rec-1');
      await expectLater(
        t.createInvite(CreateInviteRequest(record: refused, phone: _phone)),
        throwsA(isA<PlanCapRefused>()),
      );
      server.inviteCap = null; // the plan was upgraded
      await expectLater(
        t.createInvite(CreateInviteRequest(record: refused, phone: _phone)),
        throwsA(
          isA<RouteRefused>().having(
            (e) => e.code,
            'code',
            RouteRefused.recordReplayed,
          ),
        ),
      );
      expect(server.invites, isEmpty, reason: 'the replay minted nothing');
      final issued = await t.createInvite(
        CreateInviteRequest(record: _invite('rec-2'), phone: _phone),
      );
      expect(issued.recordId, 'rec-2');
      expect(server.invites, hasLength(1));
    });

    test('D-05g-5 a stranger on a full plan hears not_admin, never the cap — '
        'the cap answers only after admission, so it is no oracle', () async {
      server.inviteCap = PlanCap.seats;
      await expectLater(
        server
            .transportFor(_stranger)
            .createInvite(
              CreateInviteRequest(
                record: _invite('rec-s', device: _stranger),
                phone: _phone,
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
    });
  });

  group('D-05g-6 the fake server refuses records by cap, after admission', () {
    late FakeSyncServer server;
    setUp(() {
      server = FakeSyncServer(clock: ManualClock(1000))
        ..adminDevices.add(_admin);
    });

    test(
      'D-05g-6 every cap is producible on /records: rejected:<name> with '
      'check = name and no seq, nothing projected, the record kept',
      () async {
        for (final cap in PlanCap.values) {
          server.recordCaps['membership_status'] = cap;
          final id = 'rec-${cap.wire}';
          final res = await server
              .transportFor(_admin)
              .postRecords(
                PostRecordsRequest(
                  records: [
                    _record(id, 'membership_status', {
                      'user_id': 'u-joiner',
                      'status': 'joined_pending_verification',
                    }),
                  ],
                ),
              );
          final ack = res[id]!;
          expect(ack.planCap, cap);
          expect(ack.result, 'rejected:${cap.wire}');
          expect(ack.check, cap.wire);
          expect(ack.seq, isNull);
          expect(server.memberships, isEmpty, reason: 'nothing projected');
          expect(server.signedRecords.map((r) => r.id), contains(id));
        }
      },
    );

    test('D-05g-6 a stranger’s record is unauthorized, never the cap; a kind '
        'without a cap is untouched', () async {
      server.recordCaps['membership_status'] = PlanCap.seats;
      final res = await server
          .transportFor(_stranger)
          .postRecords(
            PostRecordsRequest(
              records: [
                _record('rec-s', 'membership_status', {
                  'user_id': 'u-x',
                  'status': 'active',
                }, device: _stranger),
              ],
            ),
          );
      expect(res['rec-s']!.result, RecordAck.rejectedUnauthorized);
      expect(res['rec-s']!.planCap, isNull);

      final ok = await server
          .transportFor(_admin)
          .postRecords(
            PostRecordsRequest(
              records: [
                _record('rec-r', 'book_role', {
                  'user_id': 'u-y',
                  'book_id': 'b1',
                  'role': 'viewer',
                }),
              ],
            ),
          );
      expect(ok['rec-r']!.isAcked, isTrue);
    });
  });

  group('D-05g-7 the engine treats a cap as terminal, never as backoff', () {
    late ManualClock clock;
    late FakeSyncServer server;
    final open = <PlainDevice>[];
    setUp(() {
      clock = ManualClock(1000 * 24 * 3600 * 1000);
      server = FakeSyncServer(clock: clock, rateLimits: RateLimits.none);
    });
    tearDown(() async {
      for (final d in open) {
        await d.close();
      }
      open.clear();
    });

    test('D-05g-7 a cap refusal on the push route stops that book with the '
        'rows kept — no backoff step, no retry window, no re-send next round, '
        'no exception out of sync()', () async {
      final a = await PlainDevice.open(
        'phone-a',
        server: server,
        clock: clock,
        userId: 'u-a',
      );
      open.add(a);
      await a.author(physicalMs: clock.nowMs());
      var pushes = 0;
      a.transport.beforeCall = (route) {
        if (route == 'push') {
          pushes++;
          throw const PlanCapRefused(PlanCap.seats);
        }
      };
      await a.engine.sync();
      expect(pushes, 1);
      expect(a.engine.backoff.attempt, 0, reason: 'a cap is not a network');
      expect(a.engine.retryPushAtMs, 0);
      expect((await a.outboxStates()).values.single, 'queued');
      expect(a.engine.pushBlockedBooks, {book1});
      expect(
        eventsOf<PullRefused>(a.engine).single,
        isA<PullRefused>()
            .having((e) => e.code, 'code', 'seat_cap')
            .having((e) => e.route, 'route', 'push'),
      );
      expect(
        await a.engine.status(),
        const NeedsAttention([AttentionReason.bookUnavailable]),
      );

      clock.advance(60 * 60 * 1000);
      await a.engine.sync();
      expect(pushes, 1, reason: 'terminal: nothing re-sends it');
    });

    test('D-05g-7 a cap refusal on the meta route ends the round cleanly, '
        'with no backoff', () async {
      final a = await PlainDevice.open(
        'phone-a',
        server: server,
        clock: clock,
        userId: 'u-a',
      );
      open.add(a);
      a.transport.beforeCall = (route) {
        if (route == 'meta') throw const PlanCapRefused(PlanCap.businessBooks);
      };
      final r = await a.engine.sync();
      expect(r.offline, isFalse);
      expect(a.engine.backoff.attempt, 0);
    });
  });

  group('D-05g-8 a cap refusal carries no plaintext', () {
    test('D-05g-8 its string form is the cap name and status only — no body, '
        'no number (rule 4)', () {
      const f = PlanCapRefused(PlanCap.seatRotation);
      expect(f.toString(), 'PlanCapRefused(409 seat_rotation_cap)');
    });
  });
}
