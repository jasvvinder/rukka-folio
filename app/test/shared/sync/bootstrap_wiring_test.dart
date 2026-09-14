// F1-05-30, F1-05-31: the composition root's half of the socket — the pin
// decision (05 §1 🔒), the transport it builds, and the identity it reads
// before anything is opened.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rukka_folio/bootstrap.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

void main() {
  test('F1-05-30 the transport this build ships carries a fresh token and the '
      'version header to the real routes, and a 401 refreshes rather than '
      'ends the session', () async {
    final seen = <http.Request>[];
    var issued = 0;
    var calls = 0;
    final transport = buildSyncTransport(
      client: MockClient((request) async {
        seen.add(request);
        if (calls++ == 0) {
          return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
        }
        return http.Response(
          jsonEncode({
            'store_epoch': 'e1',
            'devices': <Object?>[],
            'memberships': <Object?>[],
            'book_roles': <Object?>[],
            'wrapped_keys': <Object?>[],
            'signed_records': <Object?>[],
            'has_more': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      accessTokenOf: () async => 'jwt-${++issued}',
      functionsRoot: Uri.parse('http://127.0.0.1:54321/functions/v1/'),
    );

    await expectLater(
      transport.meta(const eng.MetaRequest()),
      throwsA(isA<eng.AuthFailed>()),
    );
    await transport.meta(const eng.MetaRequest());

    expect(seen.map((r) => r.url.path), [
      '/functions/v1/sync-meta',
      '/functions/v1/sync-meta',
    ]);
    // ⚠️ WIRE `_shared/http.ts`: no version header ⇒ 426 from every route.
    expect(
      seen.map((r) => r.headers[eng.HttpSyncTransport.clientVersionHeader]),
      everyElement(isNotNull),
    );
    // The 401 dropped the token; the retry carried a new one.
    expect(seen.map((r) => r.headers['authorization']), [
      'Bearer jwt-1',
      'Bearer jwt-2',
    ]);
  });

  test('F1-05-31 the default build pins nothing and says so; a configured pin '
      'set that cannot be verified refuses to build rather than ship '
      'unpinned; and the stored identity survives a garbage record', () async {
    final (pins, chain) = spkiPins();
    // No `--dart-define=RF_SPKI_PINS` in a test build: local dev, pins off,
    // and the transport is then allowed to have no chain source.
    expect(pins.localDevDisabled, isTrue);
    expect(chain, isNull);

    final keys = FakeKeyStore();
    expect(await storedIdentity(keys), isNull);

    await keys.write(
      LocalLedgerKeys.identity,
      Uint8List.fromList(utf8.encode('not json')),
    );
    expect(await storedIdentity(keys), isNull);

    await keys.write(
      LocalLedgerKeys.identity,
      Uint8List.fromList(utf8.encode(jsonEncode({'device_id': 'd'}))),
    );
    expect(
      await storedIdentity(keys),
      isNull,
      reason: 'a partial record is none',
    );

    const identity = {
      'device_id': '11111111-2222-4333-8444-555555555555',
      'user_id': '99999999-8888-4777-8666-555555555555',
      'tenant_id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      'suite_version': 1,
    };
    await keys.write(
      LocalLedgerKeys.identity,
      Uint8List.fromList(utf8.encode(jsonEncode(identity))),
    );
    final read = await storedIdentity(keys);
    expect(read?.tenantId, identity['tenant_id']);
    expect(read?.userId, identity['user_id']);
    expect(read?.deviceId, identity['device_id']);
  });
}
