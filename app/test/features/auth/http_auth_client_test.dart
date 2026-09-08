@Tags(['C'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/auth_transport.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../devices/crypto_helpers.dart';

/// Records every request and answers from a scripted table keyed by the
/// route's trailing path (`/otp/request`, `/token`, …).
final class ScriptedTransport implements AuthTransport {
  final requests =
      <({Uri url, Map<String, String> headers, Map<String, Object?> body})>[];
  final Map<String, List<AuthHttpResponse>> script = {};
  bool offline = false;

  void on(String path, AuthHttpResponse r) => (script[path] ??= []).add(r);

  static AuthHttpResponse ok(Map<String, Object?> body, [int status = 200]) =>
      AuthHttpResponse(status, jsonEncode(body));

  Map<String, Object?> last(String path) =>
      requests.lastWhere((r) => r.url.path.endsWith(path)).body;

  int count(String path) =>
      requests.where((r) => r.url.path.endsWith(path)).length;

  @override
  Future<AuthHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    if (offline) throw const AuthTransportException();
    requests.add((
      url: url,
      headers: headers,
      body: jsonDecode(body) as Map<String, Object?>,
    ));
    // Scripts are keyed by the sub-route under `auth-challenge/`.
    final key = script.keys
        .where(url.path.endsWith)
        .fold<String?>(
          null,
          (best, k) => best == null || k.length > best.length ? k : best,
        );
    final q = key == null ? null : script[key];
    if (q == null || q.isEmpty) return const AuthHttpResponse(500, '');
    return q.length == 1 ? q.first : q.removeAt(0);
  }
}

const phone = '+919876543210';
const code = '482913';
const deviceId = '0b7a4c2e-9d41-4f3a-8e6b-2f1c9a7d5e30';

final nonce = Uint8List.fromList(List.generate(32, (i) => 255 - i));

/// The `/token` and `/refresh` 200 body (index.ts issueTokens).
Map<String, Object?> sessionBody(
  String access,
  String refresh, {
  String userId = 'u-1',
  String status = 'registered',
}) => {
  'access_token': access,
  'expires_in': 900,
  'refresh_token': refresh,
  'refresh_expires_at': 1790000000000,
  'user_id': userId,
  'device_id': deviceId,
  'device_status': status,
};

void main() {
  late ScriptedTransport t;
  late FakeKeyStore keys;
  late TestClock clock;
  late List<String> log;

  Future<HttpAuthClient> client() async => HttpAuthClient(
    transport: t,
    suite: await liveSuite(),
    keys: keys,
    now: clock.call,
    baseUrl: Uri.parse('https://api.test/functions/v1/'),
    clientVersion: '1.2.0',
    deviceModel: 'Pixel 8',
    deviceOs: 'Android 15',
    log: log.add,
  );

  void scriptHappyPath() {
    t.on(
      '/otp/request',
      ScriptedTransport.ok({'ok': true, 'resend_after_s': 30}),
    );
    t.on(
      '/otp/verify',
      ScriptedTransport.ok({
        'ticket': 'tk-1',
        'user_id': 'u-1',
        'expires_in_s': 600,
      }),
    );
    t.on(
      '/devices',
      ScriptedTransport.ok({
        'device_id': deviceId,
        'user_id': 'u-1',
        'status': 'registered',
      }),
    );
    t.on(
      '/challenge',
      ScriptedTransport.ok({
        'nonce': Bytes.base64Url(nonce),
        'expires_in_s': 60,
      }),
    );
    t.on('/token', ScriptedTransport.ok(sessionBody('acc-1', 'ref-1')));
  }

  Future<AuthSession> activate(HttpAuthClient c) async {
    await c.requestOtp(phone);
    final ticket = await c.verifyOtp(code);
    return c.activateDevice(ticket);
  }

  setUp(() {
    t = ScriptedTransport();
    keys = FakeKeyStore();
    clock = TestClock(DateTime.utc(2026, 9, 7, 4, 30));
    log = [];
  });

  group('HttpAuthClient — 06 §2 OTP', () {
    test('C-06-7 requestOtp posts the phone once, surfaces WhatsApp then SMS fallback as state, moves to OtpSent, and no phone or code ever reaches the log', () async {
      final c = await client();
      t.on(
        '/otp/request',
        ScriptedTransport.ok({'ok': true, 'resend_after_s': 30}),
      );
      await c.requestOtp(phone);
      expect(t.count('/otp/request'), 1);
      expect(t.last('/otp/request'), {
        'phone': phone,
        'purpose': 'signup',
        'channel': 'whatsapp',
      });
      expect(t.requests.single.headers['x-rukka-client-version'], '1.2.0');
      expect(c.otpChannel.value, OtpChannel.whatsapp);
      expect(c.resendAfter.value, const Duration(seconds: 30));
      expect(c.current, isA<OtpSent>().having((s) => s.phone, 'phone', phone));

      // SMS asked for explicitly (or as the fallback the screen offers): the
      // preference travels as `channel` and is what the screen reports.
      // ⚠️ WIRE the 200 body never says which channel carried the code.
      await c.requestOtp(
        phone,
        purpose: OtpPurpose.deviceActivation,
        channel: OtpChannel.sms,
      );
      expect(c.otpChannel.value, OtpChannel.sms);
      expect(t.last('/otp/request'), {
        'phone': phone,
        'purpose': 'device_activation',
        'channel': 'sms',
      });

      t.on(
        '/otp/verify',
        ScriptedTransport.ok({
          'ticket': 'tk',
          'user_id': 'u-1',
          'expires_in_s': 600,
        }),
      );
      await c.verifyOtp(code);
      expect(t.last('/otp/verify'), {
        'phone': phone,
        'purpose': 'device_activation',
        'code': code,
      });
      final joined = log.join('\n');
      expect(joined, isNot(contains('9876543210')));
      expect(joined, isNot(contains(code)));
      expect(joined, isNot(contains('tk')));
      expect(log, isNotEmpty);
    });

    test('C-06-8 verifyOtp maps wrong code (attempts left), expired, rate-limited and transport failure to generic AuthFailure kinds; no code pending is refused locally', () async {
      final c = await client();
      await expectLater(
        c.verifyOtp(code),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.noPendingCode,
          ),
        ),
      );
      t.on(
        '/otp/request',
        ScriptedTransport.ok({'ok': true, 'resend_after_s': 30}),
      );
      await c.requestOtp(phone);

      t.on(
        '/otp/verify',
        ScriptedTransport.ok({'error': 'otp_invalid', 'attempts_left': 2}, 400),
      );
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({'error': 'otp_invalid', 'attempts_left': 1}, 400),
      );
      t.on(
        '/otp/verify',
        // Expired / consumed / third strike: `otp_invalid` with no attempts_left.
        ScriptedTransport.ok({'error': 'otp_invalid'}, 400),
      );
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({'error': 'too_many_requests'}, 429),
      );
      await expectLater(
        c.verifyOtp('000000'),
        throwsA(
          isA<AuthFailure>()
              .having((f) => f.kind, 'kind', AuthFailureKind.invalidCode)
              .having((f) => f.attemptsLeft, 'left', 2),
        ),
      );
      await expectLater(
        c.verifyOtp('000001'),
        throwsA(isA<AuthFailure>().having((f) => f.attemptsLeft, 'left', 1)),
      );
      await expectLater(
        c.verifyOtp('000002'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.codeExpired,
          ),
        ),
      );
      // Expired → a new code is required: the client refuses locally now.
      await expectLater(
        c.verifyOtp('000003'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.noPendingCode,
          ),
        ),
      );
      await c.requestOtp(phone);
      await expectLater(
        c.verifyOtp('000004'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.rateLimited,
          ),
        ),
      );
      t.offline = true;
      await expectLater(
        c.verifyOtp('000005'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.unavailable,
          ),
        ),
      );
      expect(t.last('/otp/verify'), {
        'phone': phone,
        'purpose': 'signup',
        'code': '000004',
      });
    });
  });

  group('HttpAuthClient — 06 §3 registration, 06 §4 sessions', () {
    test('C-06-9 activateDevice generates Ed25519 + X25519 seeds via the suite into KeyIds, registers with ticket + public keys + model/os, then signs nonce ‖ device_id ‖ unix_ts with the device key and opens an uncertified Active session', () async {
      final c = await client();
      scriptHappyPath();
      final s = await activate(c);

      expect(s.deviceId, deviceId);
      expect(s.userId, 'u-1');
      expect(
        c.current,
        isA<Active>().having((a) => a.deviceCertified, 'certified', false),
      );
      expect(
        keys.writes,
        containsAll([KeyIds.deviceSigningKey, KeyIds.deviceAgreementKey]),
      );

      final sodiumLib = await sodium();
      final edSeed = (await keys.read(KeyIds.deviceSigningKey))!;
      final xSeed = (await keys.read(KeyIds.deviceAgreementKey))!;
      expect(edSeed, hasLength(32));
      expect(xSeed, hasLength(32));
      final ed = sodiumLib.crypto.sign.seedKeyPair(
        sodiumLib.secureCopy(edSeed),
      );
      final x = sodiumLib.crypto.box.seedKeyPair(sodiumLib.secureCopy(xSeed));

      final reg = t.last('/devices');
      expect(reg['ticket'], 'tk-1');
      expect(Bytes.fromBase64Url(reg['pub_ed'] as String), ed.publicKey);
      expect(Bytes.fromBase64Url(reg['pub_x'] as String), x.publicKey);
      expect(reg['pub_ed'], isNot(contains('=')));
      expect(reg['model'], 'Pixel 8');
      expect(reg['os'], 'Android 15');
      expect(reg.containsKey('attestation'), isTrue);

      expect(t.last('/challenge'), {'device_id': deviceId});
      final sess = t.last('/token');
      expect(sess.keys.toSet(), {'device_id', 'nonce', 'unix_ts', 'signature'});
      expect(sess['device_id'], deviceId);
      expect(sess['nonce'], Bytes.base64Url(nonce));
      expect(sess['unix_ts'], clock.now.millisecondsSinceEpoch ~/ 1000);
      // Byte-identical to index.ts verifyChallenge:
      // concat([nonce, uuid16(device_id), i64be(ts)]).
      final msg = HttpAuthClient.challengeMessage(
        nonce,
        deviceId,
        sess['unix_ts'] as int,
      );
      expect(msg, hasLength(32 + 16 + 8));
      expect(msg.sublist(0, 32), nonce);
      expect(msg.sublist(32, 48), Uuid16.toBytes(deviceId));
      expect(msg.sublist(48), Bytes.i64be(sess['unix_ts'] as int));
      final ok = sodiumLib.crypto.sign.verifyDetached(
        message: msg,
        signature: HttpAuthClient.decodeBase64Any(sess['signature'] as String),
        publicKey: ed.publicKey,
      );
      expect(ok, isTrue);
      // The server accepts either alphabet; the client decodes either too.
      expect(HttpAuthClient.decodeBase64Any(base64Encode(nonce)), nonce);
      expect(await keys.contains(SessionItems.refreshToken), isTrue);
    });

    test('C-06-10 access token is cached for 15 min against the injected clock; past the margin a refresh signs a fresh challenge and rotates the refresh token; a refused refresh ends the session without touching device keys', () async {
      final c = await client();
      scriptHappyPath();
      await activate(c);
      expect(await c.accessToken(), 'acc-1');
      expect(t.count('/refresh'), 0);

      clock.advance(const Duration(minutes: 13));
      expect(await c.accessToken(), 'acc-1');
      expect(t.count('/refresh'), 0);

      clock.advance(const Duration(minutes: 1, seconds: 30));
      t.on('/refresh', ScriptedTransport.ok(sessionBody('acc-2', 'ref-2')));
      expect(await c.accessToken(), 'acc-2');
      final ref = t.last('/refresh');
      expect(ref.keys.toSet(), {
        'device_id',
        'refresh_token',
        'nonce',
        'unix_ts',
        'signature',
      });
      expect(ref['refresh_token'], 'ref-1');
      expect(ref['device_id'], deviceId);
      expect(ref['nonce'], Bytes.base64Url(nonce));
      expect(ref['signature'], isA<String>());
      expect(t.count('/challenge'), 2);
      expect(
        utf8.decode((await keys.read(SessionItems.refreshToken))!),
        'ref-2',
      );

      clock.advance(const Duration(minutes: 15));
      t.script['/refresh'] = [
        ScriptedTransport.ok({'error': 'refresh_reused'}, 401),
      ];
      await expectLater(c.accessToken(), throwsA(isA<SessionEnded>()));
      expect(c.current, isA<SignedOut>());
      expect(await keys.contains(SessionItems.refreshToken), isFalse);
      expect(await keys.contains(KeyIds.deviceSigningKey), isTrue);
      expect(await keys.contains(KeyIds.deviceAgreementKey), isTrue);
    });

    test('C-06-11 a 426 from any route sets the min-version gate with current and required versions and surfaces as UpdateRequired', () async {
      final c = await client();
      t.on(
        '/otp/request',
        ScriptedTransport.ok({
          'error': 'upgrade_required',
          'min_client_version': '1.3.0',
        }, 426),
      );
      expect(c.updateRequired.value, isNull);
      await expectLater(
        c.requestOtp(phone),
        throwsA(
          isA<UpdateRequired>()
              .having((u) => u.currentVersion, 'current', '1.2.0')
              .having((u) => u.requiredVersion, 'required', '1.3.0'),
        ),
      );
      expect(c.updateRequired.value?.requiredVersion, '1.3.0');
      expect(c.current, isA<SignedOut>());
    });

    test('C-06-12 existing device seeds are reused, never regenerated (Keychain remnant = same device, 04 §3.3, 06 §5); sign-out keeps them and restore() brings the session back', () async {
      scriptHappyPath();
      final c = await client();
      await activate(c);
      final edBefore = await keys.read(KeyIds.deviceSigningKey);
      final writesBefore = keys.writes
          .where((w) => w == KeyIds.deviceSigningKey)
          .length;
      expect(writesBefore, 1);

      await c.signOut();
      expect(c.current, isA<SignedOut>());
      expect(await keys.read(KeyIds.deviceSigningKey), edBefore);

      final c2 = await client();
      await activate(c2);
      expect(await keys.read(KeyIds.deviceSigningKey), edBefore);
      expect(keys.writes.where((w) => w == KeyIds.deviceSigningKey).length, 1);
      expect(log.where((e) => e == 'device_keys_generated').length, 1);

      final c3 = await client();
      expect(c3.current, isA<SignedOut>());
      await c3.restore();
      expect(
        c3.current,
        isA<Active>().having((a) => a.session.deviceId, 'device', deviceId),
      );
    });

    test('C-06-13 invalid or consumed ticket is refused as invalidTicket and no session opens; markCertified flips the one flag only', () async {
      final c = await client();
      t.on(
        '/otp/request',
        ScriptedTransport.ok({'ok': true, 'resend_after_s': 30}),
      );
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({
          'ticket': 'tk-x',
          'user_id': 'u',
          'expires_in_s': 600,
        }),
      );
      t.on('/devices', ScriptedTransport.ok({'error': 'ticket_invalid'}, 401));
      await c.requestOtp(phone);
      final ticket = await c.verifyOtp(code);
      await expectLater(
        c.activateDevice(ticket),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.invalidTicket,
          ),
        ),
      );
      expect(t.count('/challenge'), 0);
      expect(c.current, isA<OtpSent>());

      // 409 device_cap: the ticket is spent, the user must drop a device.
      t.script['/devices'] = [
        ScriptedTransport.ok({'error': 'device_cap'}, 409),
      ];
      await expectLater(
        c.activateDevice(ticket),
        throwsA(isA<DeviceCapReached>()),
      );
      expect(c.current, isA<OtpSent>());

      t.script['/devices'] = [
        ScriptedTransport.ok({
          'device_id': deviceId,
          'user_id': 'u',
          'status': 'registered',
        }),
      ];
      t.on(
        '/challenge',
        ScriptedTransport.ok({
          'nonce': Bytes.base64Url(nonce),
          'expires_in_s': 60,
        }),
      );
      t.on('/token', ScriptedTransport.ok(sessionBody('a', 'r', userId: 'u')));
      await c.activateDevice(ticket);
      expect(
        c.current,
        isA<Active>().having((a) => a.deviceCertified, 'certified', false),
      );
      c.markCertified();
      expect(
        c.current,
        isA<Active>().having((a) => a.deviceCertified, 'certified', true),
      );
    });
  });

  group('ADR 2026-09-05d §2 — an OTP-only device sees nothing but itself', () {
    test('C-05d-6 after activation the client reports the device uncertified, requests no tenant data, and the state stream replays the current value to a late listener', () async {
      final c = await client();
      scriptHappyPath();
      await activate(c);
      final paths = t.requests.map((r) => r.url.path).toSet();
      expect(paths, {
        '/functions/v1/auth-challenge/otp/request',
        '/functions/v1/auth-challenge/otp/verify',
        '/functions/v1/auth-challenge/devices',
        '/functions/v1/auth-challenge/challenge',
        '/functions/v1/auth-challenge/token',
      });
      final first = await c.state.first;
      expect(
        first,
        isA<Active>().having((a) => a.deviceCertified, 'certified', false),
      );
    });
  });
}
