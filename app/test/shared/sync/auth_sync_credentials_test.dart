// F1-05-20 … F1-05-23: the session credential the sync transport carries
// (05 §1, 06 §4) and what a 401 is allowed to do about it (ADR 2026-09-05b
// §2 🔒 — a device never wipes on the server's word).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rukka_folio/shared/sync/auth_sync_credentials.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

final _root = Uri.parse('https://api.example.test/functions/v1/');

eng.HttpSyncTransport transport(
  AuthSyncCredentials credentials, {
  required List<http.Request> seen,
  required int Function(int call) status,
}) {
  var calls = 0;
  return eng.HttpSyncTransport(
    client: MockClient((request) async {
      seen.add(request);
      final code = status(calls++);
      return http.Response(
        code == 200
            ? jsonEncode({
                'store_epoch': 'e1',
                'devices': <Object?>[],
                'memberships': <Object?>[],
                'book_roles': <Object?>[],
                'wrapped_keys': <Object?>[],
                'signed_records': <Object?>[],
                'has_more': false,
              })
            : jsonEncode({'error': 'unauthorized'}),
        code,
        headers: {'content-type': 'application/json'},
      );
    }),
    functionsRoot: _root,
    credentials: credentials,
    clientVersion: '0.1.0',
    pins: const eng.SpkiPins.localDev(),
  );
}

void main() {
  test('F1-05-20 the token is asked for per request and is held nowhere but '
      'the identity client', () async {
    var issued = 0;
    final credentials = AuthSyncCredentials(
      accessTokenOf: () async => 'jwt-${++issued}',
    );
    final seen = <http.Request>[];
    final t = transport(credentials, seen: seen, status: (_) => 200);

    await t.meta(const eng.MetaRequest());
    await t.meta(const eng.MetaRequest());

    expect(issued, 2, reason: 'one ask per request, never a cached token');
    expect(seen.map((r) => r.headers['authorization']), [
      'Bearer jwt-1',
      'Bearer jwt-2',
    ]);
  });

  test('F1-05-21 a 401 invalidates the session before the failure surfaces: '
      'the cached token is dropped and the next call carries a fresh one, '
      'with no sign-out', () async {
    var issued = 0;
    var forgotten = 0;
    final credentials = AuthSyncCredentials(
      accessTokenOf: () async => 'jwt-${++issued}',
      forget: () async => forgotten++,
    );
    final seen = <http.Request>[];
    final t = transport(
      credentials,
      seen: seen,
      status: (call) => call == 0 ? 401 : 200,
    );

    await expectLater(
      t.meta(const eng.MetaRequest()),
      throwsA(isA<eng.AuthFailed>()),
    );
    expect(credentials.invalidations, 1);
    expect(forgotten, 1, reason: 'invalidate ran before AuthFailed surfaced');

    await t.meta(const eng.MetaRequest());
    expect(seen.last.headers['authorization'], 'Bearer jwt-2');
  });

  test('F1-05-22 with no cache-buster to call, the rejected token is never '
      'replayed — the round goes offline instead of re-sending a token the '
      'server has already refused', () async {
    final credentials = AuthSyncCredentials(
      accessTokenOf: () async =>
          'stale-jwt', // the client keeps handing it back
    );
    final seen = <http.Request>[];
    final t = transport(
      credentials,
      seen: seen,
      status: (call) => call == 0 ? 401 : 200,
    );

    await expectLater(
      t.meta(const eng.MetaRequest()),
      throwsA(isA<eng.AuthFailed>()),
    );
    await expectLater(
      t.meta(const eng.MetaRequest()),
      throwsA(
        isA<eng.AuthFailed>().having(
          (e) => e.code,
          'code',
          eng.ClientFailureCode.noSession,
        ),
      ),
    );
    expect(seen, hasLength(1), reason: 'the stale token never left again');

    // The identity client refreshes on its own margin; the credential then
    // resumes without anybody having signed out.
    var token = 'stale-jwt';
    final resuming = AuthSyncCredentials(accessTokenOf: () async => token);
    expect(await resuming.accessToken(), 'stale-jwt');
    await resuming.invalidate();
    token = 'fresh-jwt';
    expect(await resuming.accessToken(), 'fresh-jwt');
  });

  test('F1-05-23 no live session is a plain 401-shaped failure, not a fact '
      'about the device: the engine backs off, nothing is wiped', () async {
    final credentials = AuthSyncCredentials(
      accessTokenOf: () async => throw StateError('SessionEnded'),
    );
    final seen = <http.Request>[];
    await expectLater(
      transport(
        credentials,
        seen: seen,
        status: (_) => 200,
      ).meta(const eng.MetaRequest()),
      throwsA(
        isA<eng.AuthFailed>().having(
          (e) => e.code,
          'code',
          eng.ClientFailureCode.noSession,
        ),
      ),
    );
    expect(seen, isEmpty);

    // An empty token is the same thing, and a failing cache-buster never
    // changes the failure the engine sees.
    final empty = AuthSyncCredentials(
      accessTokenOf: () async => '',
      forget: () async => throw StateError('keystore locked'),
    );
    await expectLater(empty.accessToken(), throwsA(isA<StaleAccessToken>()));
    await empty.invalidate();
    expect(empty.invalidations, 1);
  });
}
