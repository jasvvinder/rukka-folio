@Tags(['F1'])
library;

// ADR 2026-09-25b §2–§3 — the invitee is handed its own invite's nonce, and
// the app pairs it by `invite_id`.
//
// Driven through the production client (`HttpMembersApi` over the app's one
// HTTP door, faked at the transport) and the production relay
// (`InviteNonceRelay`). The wire rows are shaped exactly as
// `server/supabase/functions/sync-meta/index.ts` emits them: the nonce is
// base64url **unpadded** (Deno `b64url.enc`), which `base64Url.decode` refuses
// (the D-05-14 lesson), and GET rows carry the invite's `status`.
//
// Test honesty: every positive case is paired with the state that must stay
// closed — no accept this launch, an accept answer for another invite, a GET
// row that is not ours listed first — so a relay that answered the first
// row, or any row, fails here.
//
// Synthetic ids and bytes only (CLAUDE.md rule 4).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/invite_nonce_relay.dart';
import 'package:rukka_folio/features/members/members_api.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';

const _inviteA = '0a0a0a0a-1111-4222-8333-444455556666';
const _inviteB = '0b0b0b0b-1111-4222-8333-444455556666';
const _tenantA = '9e0f1a2b-3c4d-4e5f-8a6b-7c8d9e0f1a2b';
const _tenantB = '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

Uint8List _nonce(int seed) =>
    Uint8List.fromList(List<int>.generate(16, (i) => (seed + i * 11) % 256));

/// Unpadded base64url, as `b64url.enc` writes it on the server.
String _wire(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

Map<String, Object?> _row({
  required String id,
  String tenant = _tenantA,
  String status = 'sent',
  Object? nonce,
  Map<String, Object?> more = const {},
}) => {
  'invite_id': id,
  'tenant_id': tenant,
  'roles': [
    {'book_id': 'b1', 'role': 'viewer'},
  ],
  'expires_at': 1789000000000,
  'created_by': 'u-admin',
  'status': status,
  'nonce': nonce,
  ...more,
};

/// sync-meta's invite routes, scripted.
final class _Server {
  List<Map<String, Object?>> rows = [];
  Map<String, Object?> Function(String inviteId)? acceptAnswer;
  bool offline = false;

  /// When set, what the invites GET answers instead of [rows] (desk 113).
  RkHttpResponse? getRefusal;
  late final transport = FakeRkHttpTransport(_answer);

  int get gets => [
    for (final c in transport.calls)
      if (c.method == 'GET' && c.url.path.endsWith('sync-meta/invites')) c,
  ].length;

  int get posts => [
    for (final c in transport.calls)
      if (c.method == 'POST' && c.url.path.endsWith('invites/accept')) c,
  ].length;

  RkHttpResponse _answer(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) {
    if (offline) throw const RkHttpFailure();
    if (method == 'GET' && url.path.endsWith('sync-meta/invites')) {
      final refusal = getRefusal;
      if (refusal != null) return refusal;
      return RkHttpResponse(200, jsonEncode({'invites': rows}));
    }
    if (method == 'POST' && url.path.endsWith('sync-meta/invites/accept')) {
      final id =
          (jsonDecode(body!) as Map<String, Object?>)['invite_id']! as String;
      final a = acceptAnswer;
      return RkHttpResponse(
        200,
        jsonEncode(
          a == null
              ? {
                  'invite_id': id,
                  'status': 'joined_pending_verification',
                  'nonce': _wire(_nonce(id == _inviteA ? 1 : 2)),
                }
              : a(id),
        ),
      );
    }
    return RkHttpResponse(404, jsonEncode({'error': 'not_found'}));
  }

  HttpMembersApi get api => HttpMembersApi(
    transport: transport,
    functionsRoot: Uri.parse('https://api.test/functions/v1/'),
    accessToken: () async => 'acc-1',
  );
}

void main() {
  group('the wire rows (ADR 2026-09-25b §2)', () {
    test('F1-25b-1 an invites GET row decodes its UNPADDED base64url nonce to '
        '16 bytes, tolerates status, and keeps fields it does not know', () {
      final n = _nonce(3);
      final encoded = _wire(n);
      // The D-05-14 trap is real for this shape: 16 bytes is 22 chars.
      expect(encoded.length % 4, isNot(0));
      expect(() => base64Url.decode(encoded), throwsFormatException);

      final offer = InviteOffer.fromJson(
        _row(
          id: _inviteA,
          status: 'accepted',
          nonce: encoded,
          more: {'future_field': 7},
        ),
      );
      expect(offer.nonce, n);
      expect(offer.status, 'accepted');
      expect(offer.inviteId, _inviteA);
      // CLAUDE.md rule 6: a field this build does not know survives.
      expect(offer.extra, {'future_field': 7});
    });

    test('F1-25b-1 a missing, malformed or wrong-length nonce is no nonce — '
        'the offer itself still decodes (S0.9 must keep working)', () {
      for (final bad in <Object?>[
        null,
        '',
        '!!not-base64!!',
        _wire(_nonce(1)).substring(0, 10),
      ]) {
        final offer = InviteOffer.fromJson(_row(id: _inviteA, nonce: bad));
        expect(offer.nonce, isNull, reason: 'nonce $bad');
        expect(offer.inviteId, _inviteA);
      }
      // A row from a server that predates 25b: no status, no nonce.
      final old = InviteOffer.fromJson({
        'invite_id': _inviteA,
        'tenant_id': _tenantA,
        'roles': const [],
        'expires_at': 1789000000000,
        'created_by': null,
      });
      expect(old.status, isNull);
      expect(old.nonce, isNull);
      expect(old.extra, isEmpty);
    });

    test(
      'F1-25b-1 HttpMembersApi reads nonce and status off GET invites, and '
      'the accept answer carries the nonce beside invite_id and status',
      () async {
        final server = _Server()
          ..rows = [
            _row(id: _inviteA, nonce: _wire(_nonce(1))),
            _row(
              id: _inviteB,
              tenant: _tenantB,
              status: 'accepted',
              nonce: _wire(_nonce(2)),
            ),
          ];
        final offers = await server.api.myInvites();
        expect([for (final o in offers) o.inviteId], [_inviteA, _inviteB]);
        expect(offers[0].nonce, _nonce(1));
        expect(offers[1].status, 'accepted');
        expect(offers[1].nonce, _nonce(2));

        final accepted = await server.api.acceptInviteRelayed(_inviteB);
        expect(accepted.inviteId, _inviteB);
        expect(accepted.status, 'joined_pending_verification');
        expect(accepted.nonce, _nonce(2));
        // The one-string answer every existing caller reads is unchanged.
        expect(
          await server.api.acceptInvite(_inviteA),
          'joined_pending_verification',
        );
      },
    );
  });

  group('InviteNonceRelay — paired by invite_id (ADR 2026-09-25b §3)', () {
    test('F1-25b-1 before this device accepted an invite there is no nonce, '
        'however many rows the server lists — never the first row', () async {
      final server = _Server()
        ..rows = [
          _row(id: _inviteA, status: 'accepted', nonce: _wire(_nonce(1))),
        ];
      final relay = InviteNonceRelay(
        offers: server.api.myInvites,
        accept: server.api.acceptInviteRelayed,
        store: MemoryPrefs(),
      );
      expect(relay.ownInviteId, isNull);
      expect(await relay.nonce(), isNull);
    });

    test('F1-25b-1 after accepting B the relay answers B’s nonce, byte for '
        'byte, and the accept still returns the membership status', () async {
      final server = _Server();
      final relay = InviteNonceRelay(
        offers: server.api.myInvites,
        accept: server.api.acceptInviteRelayed,
        store: MemoryPrefs(),
      );
      expect(await relay.acceptInvite(_inviteB), 'joined_pending_verification');
      expect(relay.ownInviteId, _inviteB);
      expect(await relay.nonce(), _nonce(2));
    });

    test(
      'F1-25b-1 an accept answer without a nonce is paired on the GET row '
      'with the SAME invite_id — not the first row, not the live one',
      () async {
        final server = _Server()
          ..acceptAnswer = ((id) => {
            'invite_id': id,
            'status': 'joined_pending_verification',
          })
          ..rows = [
            // Listed first, live, another tenant: a positional or status-led
            // pick lands here.
            _row(id: _inviteA, tenant: _tenantB, nonce: _wire(_nonce(1))),
            _row(id: _inviteB, status: 'accepted', nonce: _wire(_nonce(2))),
          ];
        final relay = InviteNonceRelay(
          offers: server.api.myInvites,
          accept: server.api.acceptInviteRelayed,
          store: MemoryPrefs(),
        );
        await relay.acceptInvite(_inviteB);
        expect(await relay.nonce(), _nonce(2));

        // Our row gone from the list: nothing — never A's nonce instead.
        server.rows = [server.rows.first];
        expect(await relay.nonce(), isNull);
      },
    );

    test(
      'F1-25b-1 an accept answer naming ANOTHER invite pairs nothing; a '
      'failed accept pairs nothing; offline answers null, not a throw',
      () async {
        final server = _Server()
          ..acceptAnswer = (id) => {
            'invite_id': _inviteA,
            'status': 'joined_pending_verification',
            'nonce': _wire(_nonce(1)),
          };
        final relay = InviteNonceRelay(
          offers: server.api.myInvites,
          accept: server.api.acceptInviteRelayed,
          store: MemoryPrefs(),
        );
        await relay.acceptInvite(_inviteB);
        expect(relay.ownInviteId, isNull);
        expect(await relay.nonce(), isNull);

        server.offline = true;
        await expectLater(
          relay.acceptInvite(_inviteB),
          throwsA(
            isA<MembersFailure>().having(
              (f) => f.reason,
              'reason',
              MembersRefusal.offline,
            ),
          ),
        );
        expect(relay.ownInviteId, isNull);

        // Accepted online, then the GET fails: the accept's own nonce stands.
        server
          ..offline = false
          ..acceptAnswer = null;
        await relay.acceptInvite(_inviteA);
        server.offline = true;
        expect(await relay.nonce(), _nonce(1));
        expect(server.gets, 0, reason: 'the accept answer was enough');
      },
    );
  });

  group('InviteNonceRelay — after a restart (ADR 2026-09-25b §2)', () {
    InviteNonceRelay launch(_Server server, RkPrefs store) => InviteNonceRelay(
      offers: server.api.myInvites,
      accept: server.api.acceptInviteRelayed,
      store: store,
    );

    test('F1-25b-1 a second launch over the same store, with no accept, '
        'answers the accepted invite’s nonce from GET — paired by the kept '
        'id, not by the first row and not by status; only the id is kept, '
        'never the nonce', () async {
      final store = MemoryPrefs();
      final server = _Server();
      await launch(server, store).acceptInvite(_inviteB);
      expect(store.values, {InviteNonceRelay.acceptedInviteKey: _inviteB});
      expect(
        store.values.values.any((v) => v.contains(_wire(_nonce(2)))),
        isFalse,
        reason: 'the device keeps no copy of the nonce',
      );

      final postsBefore = server.posts;
      server.rows = [
        // Listed first and `accepted`: a positional or status-led pick
        // lands here.
        _row(id: _inviteA, status: 'accepted', nonce: _wire(_nonce(1))),
        _row(id: _inviteB, status: 'accepted', nonce: _wire(_nonce(2))),
      ];
      final restarted = launch(server, store);
      expect(await restarted.nonce(), _nonce(2));
      expect(restarted.ownInviteId, _inviteB);
      expect(server.posts, postsBefore, reason: 'no accept this launch');
      expect(server.gets, greaterThan(0), reason: 'read from the relay');
    });

    test('F1-25b-1 after a restart, Check again recovers: offline answers '
        'null, the same relay answers the nonce once GET is back, and a row '
        'that is gone answers null — never another invite’s', () async {
      final store = MemoryPrefs();
      final server = _Server();
      await launch(server, store).acceptInvite(_inviteB);

      server
        ..rows = [
          _row(id: _inviteB, status: 'accepted', nonce: _wire(_nonce(2))),
        ]
        ..offline = true;
      final restarted = launch(server, store);
      expect(await restarted.nonce(), isNull);

      server.offline = false;
      expect(await restarted.nonce(), _nonce(2), reason: 'Check again');

      server.rows = [_row(id: _inviteA, nonce: _wire(_nonce(1)))];
      expect(await restarted.nonce(), isNull);
    });

    test('F1-25b-1 an accept answer naming another invite, or a refused '
        'accept, keeps nothing — a later launch still has no nonce', () async {
      final store = MemoryPrefs();
      final server = _Server()
        ..rows = [
          _row(id: _inviteA, status: 'accepted', nonce: _wire(_nonce(1))),
        ]
        ..acceptAnswer = (id) => {
          'invite_id': _inviteA,
          'status': 'joined_pending_verification',
          'nonce': _wire(_nonce(1)),
        };
      await launch(server, store).acceptInvite(_inviteB);
      server.offline = true;
      await expectLater(
        launch(server, store).acceptInvite(_inviteB),
        throwsA(isA<MembersFailure>()),
      );
      expect(store.values, isEmpty);

      server.offline = false;
      expect(await launch(server, store).nonce(), isNull);
    });

    test('F1-25b-1 a store that cannot be written or read never fails the '
        'accept or throws from nonce()', () async {
      final server = _Server();
      final broken = _BrokenPrefs();
      final relay = launch(server, broken);
      expect(await relay.acceptInvite(_inviteB), 'joined_pending_verification');
      expect(await relay.nonce(), _nonce(2), reason: 'this launch still pairs');
      expect(await launch(server, broken).nonce(), isNull);
    });
  });

  // PLAN desk 113: the one relay failure that is NOT swallowed. A removed or
  // paused phone is refused on the invites GET with 403 `unknown_request`
  // (ADR 2026-10-03c §3, ADR 2026-10-04-suspended-invites §1); S9.2 must be
  // able to name it, as S0.9 does (F1-03c-5…8). Every other failure keeps
  // answering null — S9.2's *no code yet* — exactly as before.
  group(
    'InviteNonceRelay — not live is named, the rest is null (desk 113)',
    () {
      InviteNonceRelay launch(_Server server, RkPrefs store) =>
          InviteNonceRelay(
            offers: server.api.myInvites,
            accept: server.api.acceptInviteRelayed,
            store: store,
          );

      Future<RkPrefs> kept() async {
        final store = MemoryPrefs();
        await store.write(InviteNonceRelay.acceptedInviteKey, _inviteB);
        return store;
      }

      test('F1-03c-9 after a restart, a 403 unknown_request on the invites GET '
          'propagates from nonce() as MembersFailure(deviceNotLive) — not '
          'null — and Check again recovers once the phone is live', () async {
        final server = _Server()
          ..rows = [
            _row(id: _inviteB, status: 'accepted', nonce: _wire(_nonce(2))),
          ]
          ..getRefusal = RkHttpResponse(
            403,
            jsonEncode({'error': 'unknown_request'}),
          );
        final relay = launch(server, await kept());
        await expectLater(
          relay.nonce(),
          throwsA(
            isA<MembersFailure>().having(
              (f) => f.reason,
              'reason',
              MembersRefusal.deviceNotLive,
            ),
          ),
        );
        expect(server.gets, 1);

        server.getRefusal = null;
        expect(await relay.nonce(), _nonce(2), reason: 'Check again');
      });

      test('F1-03c-10 control: offline, 403 forbidden, 401, 500, and no invite '
          'accepted on this device still answer null from nonce(), never '
          'a throw', () async {
        for (final refusal in <RkHttpResponse?>[
          null, // offline, below
          RkHttpResponse(403, jsonEncode({'error': 'forbidden'})),
          RkHttpResponse(401, jsonEncode({'error': 'unauthorized'})),
          RkHttpResponse(500, jsonEncode({'error': 'internal'})),
        ]) {
          final server = _Server()
            ..rows = [
              _row(id: _inviteB, status: 'accepted', nonce: _wire(_nonce(2))),
            ]
            ..offline = refusal == null
            ..getRefusal = refusal;
          expect(await launch(server, await kept()).nonce(), isNull);
        }

        // Not live, but this device never accepted an invite: there is no
        // invite of its own to read, so nothing is asked and nothing named.
        final fresh = _Server()
          ..getRefusal = RkHttpResponse(
            403,
            jsonEncode({'error': 'unknown_request'}),
          );
        expect(await launch(fresh, MemoryPrefs()).nonce(), isNull);
        expect(fresh.gets, 0);
      });
    },
  );
}

/// A protected item store that refuses every call.
final class _BrokenPrefs implements RkPrefs {
  @override
  Future<String?> read(String key) async => throw StateError('locked');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('locked');

  @override
  Future<void> remove(String key) async => throw StateError('locked');
}
