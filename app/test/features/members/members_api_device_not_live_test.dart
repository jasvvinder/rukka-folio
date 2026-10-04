@Tags(['F1'])
library;

// Desk 109 — the invite routes refuse a phone that is not a live device of its
// account (ADR 2026-10-03c §3, migration 0028; suspended too, owner ruling
// 4 Oct 2026, desk 108). sync-meta's `inviteError` answers that
// `unknown_candidate_device` as **403 `unknown_request`** — the wire name
// `recoveryError` also gives "no such attempt, or not yours" on the recovery
// routes. So the named refusal is read on the two device-gated invite routes
// ONLY, and the same bytes anywhere else keep their old meaning.
//
// F1-03c-5  the invites GET and the accept map 403 `unknown_request` to
//           [MembersRefusal.deviceNotLive] — through the production
//           `HttpMembersApi` parsing, over a fake transport, and through the
//           S9.2 nonce relay's accept, which passes it on unchanged
// F1-03c-6  controls: the same body on a route 0028 does not gate, the same
//           name on another status, and another name on the invite routes all
//           map exactly as before
//
// Synthetic ids only (CLAUDE.md rule 4).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/invite_nonce_relay.dart';
import 'package:rukka_folio/features/members/members_api.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';

const _invite = '0c0c0c0c-1111-4222-8333-444455556666';

/// sync-meta answering every request with one scripted response.
HttpMembersApi _api(RkHttpResponse Function(String method, Uri url) answer) =>
    HttpMembersApi(
      transport: FakeRkHttpTransport(
        (method, url, _, _) => answer(method, url),
      ),
      functionsRoot: Uri.parse('https://api.test/functions/v1/'),
      accessToken: () async => 'acc-1',
    );

/// The exact body `error(403, "unknown_request")` writes.
final _notLive = RkHttpResponse(403, jsonEncode({'error': 'unknown_request'}));

/// The refusal [call] threw, or fails the test when it threw none.
Future<MembersRefusal> _refusal(Future<Object?> Function() call) async {
  try {
    await call();
  } on MembersFailure catch (f) {
    return f.reason;
  }
  fail('expected a MembersFailure');
}

void main() {
  group('desk 109 — a phone that is not live, on the invite routes', () {
    test(
      'F1-03c-5 the invites GET and the accept read 403 `unknown_request` '
      'as deviceNotLive, and the S9.2 relay passes it on unchanged',
      () async {
        final api = _api((_, _) => _notLive);
        expect(await _refusal(api.myInvites), MembersRefusal.deviceNotLive);
        expect(
          await _refusal(() => api.acceptInviteRelayed(_invite)),
          MembersRefusal.deviceNotLive,
        );
        expect(
          await _refusal(() => api.acceptInvite(_invite)),
          MembersRefusal.deviceNotLive,
        );

        final relay = InviteNonceRelay(
          offers: api.myInvites,
          accept: api.acceptInviteRelayed,
          store: MemoryPrefs(),
        );
        expect(
          await _refusal(() => relay.acceptInvite(_invite)),
          MembersRefusal.deviceNotLive,
        );
        // A refused accept is not remembered as this phone's invite.
        expect(relay.ownInviteId, isNull);
      },
    );

    test('F1-03c-5 the pure mapping: device-gated + 403 + `unknown_request`, '
        'and nothing less', () {
      expect(
        refusalOf('unknown_request', 403, deviceGated: true),
        MembersRefusal.deviceNotLive,
      );
      expect(refusalOf('unknown_request', 403), MembersRefusal.server);
      expect(
        refusalOf('unknown_request', 409, deviceGated: true),
        MembersRefusal.server,
      );
    });

    test('F1-03c-6 controls — the same body off the gated routes, another '
        'status, and other names on the invite routes map as before', () async {
      // The same 403 on the routes 0028 does not gate stays the generic
      // refusal: never misnamed as "this phone is not live".
      final everywhere = _api((_, _) => _notLive);
      expect(
        await _refusal(() => everywhere.postRecords(const [])),
        MembersRefusal.server,
      );
      expect(
        await _refusal(
          () => everywhere.issueInvite(record: const {}, phoneE164: '+910'),
        ),
        MembersRefusal.server,
      );
      expect(
        await _refusal(() => everywhere.pullMeta()),
        MembersRefusal.server,
      );

      // `unknown_request` on another status is off-contract: generic.
      final other = _api(
        (_, _) => RkHttpResponse(409, jsonEncode({'error': 'unknown_request'})),
      );
      expect(await _refusal(other.myInvites), MembersRefusal.server);

      // The invite routes' other refusals keep their own names.
      final notForYou = _api(
        (_, _) =>
            RkHttpResponse(403, jsonEncode({'error': 'invite_not_for_you'})),
      );
      expect(
        await _refusal(() => notForYou.acceptInviteRelayed(_invite)),
        MembersRefusal.inviteNotForYou,
      );
      final forbidden = _api(
        (_, _) => RkHttpResponse(403, jsonEncode({'error': 'forbidden'})),
      );
      expect(await _refusal(forbidden.myInvites), MembersRefusal.unauthorized);
      final broken = _api(
        (_, _) => RkHttpResponse(500, jsonEncode({'error': 'internal'})),
      );
      expect(await _refusal(broken.myInvites), MembersRefusal.server);
    });
  });
}
