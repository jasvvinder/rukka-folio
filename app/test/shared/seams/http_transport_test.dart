// F1-05-28, F1-05-29: one HTTP door for the app. `features/auth` and
// `features/members` each declared their own two-method seam with its own
// response type and its own "never answered" exception; both now run over one
// transport, so there is a single place that calls `package:http`.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rukka_folio/features/auth/auth_transport.dart';
import 'package:rukka_folio/features/members/members_api.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';

void main() {
  test(
    'F1-05-28 both feature seams run over one transport, and a request '
    'that never answered surfaces as each feature\'s own offline failure',
    () async {
      final seen = <http.BaseRequest>[];
      var fail = false;
      final one = HttpClientRkTransport(
        MockClient((request) async {
          seen.add(request);
          if (fail) throw http.ClientException('no route to host');
          return http.Response(
            jsonEncode({'ok': request.method}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final auth = AuthTransportOverRkHttp(one);
      final members = MembersTransportOverRkHttp(one);

      expect(
        (await auth.post(
          Uri.parse('https://x.test/auth-challenge/token'),
          headers: const {'content-type': 'application/json'},
          body: '{}',
        )).body,
        '{"ok":"POST"}',
      );
      expect(
        (await members.get(
          Uri.parse('https://x.test/sync-meta/invites'),
          headers: const {'authorization': 'Bearer t'},
        )).statusCode,
        200,
      );
      expect(
        (await members.post(
          Uri.parse('https://x.test/sync-meta/records'),
          headers: const {'authorization': 'Bearer t'},
          body: '{"records":[]}',
        )).body,
        '{"ok":"POST"}',
      );
      expect(seen.map((r) => r.method), ['POST', 'GET', 'POST']);

      fail = true;
      await expectLater(
        auth.post(Uri.parse('https://x.test/a'), headers: const {}, body: '{}'),
        throwsA(isA<AuthTransportException>()),
      );
      await expectLater(
        members.get(Uri.parse('https://x.test/a'), headers: const {}),
        throwsA(isA<MembersTransportException>()),
      );
      await expectLater(
        members.post(
          Uri.parse('https://x.test/a'),
          headers: const {},
          body: '{}',
        ),
        throwsA(isA<MembersTransportException>()),
      );
    },
  );

  test(
    'F1-05-29 a body is read as UTF-8 even when the server names no '
    'charset — a Punjabi or Hindi member name must not come back mojibake',
    () async {
      const name = 'ਸੁਨੀਤਾ · सुनीता';
      final transport = HttpClientRkTransport(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'display_name': name})),
            200,
            // No charset: `http.Response.body` would decode this as latin-1.
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );
      final decoded = jsonDecode(
        (await transport.get(
          Uri.parse('https://x.test/a'),
          headers: const {},
        )).body,
      ) as Map<String, Object?>;
      expect(decoded['display_name'], name);

      // And the fake used by other lanes' tests speaks the same seam.
      final fake = FakeRkHttpTransport(
        (method, url, headers, body) => RkHttpResponse(200, '$method $body'),
      );
      expect(
        (await fake.post(
          Uri.parse('https://x.test/a'),
          headers: const {},
          body: 'b',
        )).body,
        'POST b',
      );
      expect(fake.calls.single.method, 'POST');
    },
  );
}
