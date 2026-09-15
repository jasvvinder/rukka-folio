@Tags(['C'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/auth_transport.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart';
import 'package:rukka_folio/shared/ledger/device_certification.dart';
import 'package:rukka_folio/shared/ledger/ledger_identity.dart';
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
// The ledger identity every install has before any screen (ADR 2026-09-16
// §1): the device id above is the LEDGER's; the scripted server echoes it.
const ledgerUserId = '7d2f9c1a-4b6e-4c8d-9e0f-1a2b3c4d5e6f';
const ledgerTenantId = '9e0f1a2b-3c4d-4e5f-8a6b-7c8d9e0f1a2b';
const otherDeviceId = '5c3e1a7f-2b9d-4e6a-8f1c-0d2e4a6b8c1e';

Future<void> seedLedgerIdentity(
  FakeKeyStore keys, {
  String device = deviceId,
}) => keys.write(
  LocalLedgerKeys.identity,
  LedgerIdentity(
    deviceId: device,
    userId: ledgerUserId,
    tenantId: ledgerTenantId,
  ).encode(suiteVersion: 1),
);

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

/// The ledger, as `certifyDevice` sees it (04 §3.4): it issues a real
/// certificate under a real UMK and files what the server accepted. The
/// signing lives here, not in the auth client — the UMK secret never crosses
/// the seam.
final class FakeCertifier implements DeviceCertifier {
  FakeCertifier(this.suite, {this.certDeviceId = deviceId})
    : device = DeviceKeyPair.generate(suite, deviceId: certDeviceId),
      umk = UmkKeyPair.generate(suite);

  final CryptoSuite suite;

  /// The id the issued certificate names — [deviceId] unless a test pins
  /// another to prove the mismatch is caught.
  final String certDeviceId;

  final DeviceKeyPair device;
  final UmkKeyPair umk;

  /// Certificates issued, and the ones the client filed after a 200.
  int issued = 0;
  final filed = <DeviceCert>[];

  /// Set to fail as a closed (or absent) ledger does.
  bool unopenable = false;

  @override
  DeviceCertOffer issueOwnCert() {
    if (unopenable) throw StateError('ledger not open');
    issued++;
    return DeviceCertOffer(
      cert: DeviceCert.issue(
        suite,
        issuer: umk,
        userId: ledgerUserId,
        device: device.public,
        issuedAtMs: 1789000000000,
      ),
      umkPubEd: umk.public.ed25519,
    );
  }

  @override
  Future<void> installOwnCert(DeviceCert cert) async => filed.add(cert);

  @override
  DeviceCert? get ownDeviceCert => filed.isEmpty ? null : filed.last;
}

void main() {
  late ScriptedTransport t;
  late FakeKeyStore keys;
  late TestClock clock;
  late List<String> log;

  Future<HttpAuthClient> client({DeviceCertifier? certifier}) async =>
      HttpAuthClient(
        transport: t,
        suite: await liveSuite(),
        keys: keys,
        now: clock.call,
        baseUrl: Uri.parse('https://api.test/functions/v1/'),
        clientVersion: '1.2.0',
        deviceModel: 'Pixel 8',
        deviceOs: 'Android 15',
        log: log.add,
        certifier: certifier,
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

  setUp(() async {
    t = ScriptedTransport();
    keys = FakeKeyStore();
    await seedLedgerIdentity(keys);
    keys.writes.clear(); // the fixture's write, not the client's
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
      expect(reg['device_id'], deviceId); // the ledger's (ADR 2026-09-16 §2)
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

  group('C-06-19 — an OTP-only device surfaces no tenant metadata', () {
    // ADR 2026-09-05d §2 🔒 + 06 §3 step 3: until the server has verified a
    // certificate under the user's UMK, the device sees only itself. The
    // server half landed in M7, so the client half is testable: even when a
    // server volunteers tenant metadata on the activation responses, the
    // client must surface none of it — not a name, not a count.
    const planted = [
      'Sharma Family',
      'Sharma Trading Co',
      'Personal book',
      'Sunita',
      'owner',
      'tnt-9f2c',
    ];

    void scriptOversharingServer() {
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
          // Not in the contract; a server that leaks it must not be believed.
          'tenant_name': 'Sharma Family',
          'member_count': 4,
        }),
      );
      t.on(
        '/devices',
        ScriptedTransport.ok({
          'device_id': deviceId,
          'user_id': 'u-1',
          'status': 'registered',
          'tenant_id': 'tnt-9f2c',
          'tenant_name': 'Sharma Family',
          'books': [
            {'id': 'b-1', 'name': 'Personal book'},
            {'id': 'b-2', 'name': 'Sharma Trading Co'},
          ],
          'members': [
            {'name': 'Sunita', 'role': 'owner'},
          ],
          'device_count': 3,
        }),
      );
      t.on(
        '/challenge',
        ScriptedTransport.ok({
          'nonce': Bytes.base64Url(nonce),
          'expires_in_s': 60,
        }),
      );
      t.on(
        '/token',
        ScriptedTransport.ok({
          ...sessionBody('acc-1', 'ref-1'),
          'tenant_name': 'Sharma Family',
          'memberships': [
            {'tenant': 'tnt-9f2c', 'role': 'owner'},
          ],
        }),
      );
    }

    test('C-06-19 the client state of an OTP-only session names only this user and this device, and carries no tenant, book or member metadata the server volunteered', () async {
      final c = await client();
      scriptOversharingServer();
      final session = await activate(c);

      final state = c.current;
      expect(
        state,
        isA<Active>().having((a) => a.deviceCertified, 'certified', false),
      );
      expect(session.userId, 'u-1');
      expect(session.deviceId, deviceId);

      // Everything the seam exposes about the session, in one string.
      final surfaced = [
        state.toString(),
        session.userId,
        session.deviceId,
        (state as Active).session.userId,
        state.session.deviceId,
      ].join('|');
      for (final leak in planted) {
        expect(
          surfaced,
          isNot(contains(leak)),
          reason: 'ADR 2026-09-05d §2: an uncertified device sees only itself',
        );
      }
    });

    test('C-06-19 nothing tenant-shaped reaches the key store or the log on the OTP-only path', () async {
      final c = await client();
      scriptOversharingServer();
      await activate(c);

      // Only this device's own keys (04 §3.3) and the three session items
      // 06 §4 needs. No tenant cache, no member list, no book names.
      expect(keys.writes.toSet(), {
        'rk.device.sign',
        'rk.device.agree',
        'rk.device.id',
        'rk.session.user',
        'rk.session.refresh',
      });
      for (final id in keys.writes.toSet()) {
        final bytes = await keys.read(id);
        final text = String.fromCharCodes(bytes!);
        for (final leak in planted) {
          expect(text, isNot(contains(leak)), reason: '$id');
        }
      }
      // Rule 4: fixed event names only — no phone, no tenant, no name.
      for (final line in log) {
        for (final leak in [...planted, phone, code]) {
          expect(line, isNot(contains(leak)));
        }
      }
    });

    test('C-06-19 an OTP-only device asks for no tenant metadata — the five activation routes and nothing else', () async {
      final c = await client();
      scriptOversharingServer();
      await activate(c);
      expect(t.requests.map((r) => r.url.path).toSet(), {
        '/functions/v1/auth-challenge/otp/request',
        '/functions/v1/auth-challenge/otp/verify',
        '/functions/v1/auth-challenge/devices',
        '/functions/v1/auth-challenge/challenge',
        '/functions/v1/auth-challenge/token',
      });
      // No sync-meta, no memberships, no books call before certification.
      expect(t.requests.any((r) => r.url.path.contains('sync-meta')), isFalse);
    });
  });

  group('ADR 2026-09-16 — one device, one id', () {
    test('C-06-24 activateDevice sends the ledger-minted device_id in POST devices and every later artefact carries that same id — session, challenge, token signature and SessionItems.deviceId; the server echo is accepted', () async {
      scriptHappyPath();
      final c = await client();
      final s = await activate(c);

      expect(t.last('/devices')['device_id'], deviceId);
      expect(s.deviceId, deviceId);
      expect(t.last('/challenge')['device_id'], deviceId);
      expect(t.last('/token')['device_id'], deviceId);
      expect(utf8.decode((await keys.read(SessionItems.deviceId))!), deviceId);
      // The device id was read, never minted: the client never writes the
      // identity record — it is the ledger's.
      expect(keys.writes, isNot(contains(LocalLedgerKeys.identity)));
      expect((await readStoredIdentity(keys))!.deviceId, deviceId);
      // The same key pair the ledger holds signs the challenge (one seed pair
      // under KeyIds — 04 §3.3).
      expect(await keys.contains(KeyIds.deviceSigningKey), isTrue);
    });

    test('C-06-25 a server that answers with a different device_id, or 409 device_id_taken, is refused as unavailable — no session, nothing stored under the foreign id, no challenge signed; 409 device_cap keeps DeviceCapReached', () async {
      // Different id echoed.
      scriptHappyPath();
      t.script['/devices'] = [
        ScriptedTransport.ok({
          'device_id': otherDeviceId,
          'user_id': 'u-1',
          'status': 'registered',
        }),
      ];
      final c = await client();
      await expectLater(
        activate(c),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.unavailable,
          ),
        ),
      );
      expect(c.current, isNot(isA<Active>()));
      expect(await keys.contains(SessionItems.deviceId), isFalse);
      expect(await keys.contains(SessionItems.refreshToken), isFalse);
      expect(t.count('/challenge'), 0);
      expect(log, contains('device_id_mismatch'));
      expect(log.any((e) => e.contains(otherDeviceId)), isFalse);

      // 409 device_id_taken: distinct from the cap, also fails closed.
      t.script['/devices'] = [
        ScriptedTransport.ok({'error': 'device_id_taken'}, 409),
      ];
      final c2 = await client();
      await expectLater(
        activate(c2),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.unavailable,
          ),
        ),
      );
      expect(await keys.contains(SessionItems.deviceId), isFalse);
      expect(log, contains('device_id_taken'));

      // 409 device_cap is still the cap.
      t.script['/devices'] = [
        ScriptedTransport.ok({'error': 'device_cap'}, 409),
      ];
      final c3 = await client();
      await expectLater(activate(c3), throwsA(isA<DeviceCapReached>()));
    });

    test('C-06-26 with no ledger identity in the store activateDevice throws NoDeviceIdentity before any request — it never mints an id of its own and writes nothing', () async {
      await keys.delete(LocalLedgerKeys.identity);
      scriptHappyPath();
      final c = await client();
      await c.requestOtp(phone);
      final ticket = await c.verifyOtp(code);
      final writesBefore = keys.writes.length;
      await expectLater(
        c.activateDevice(ticket),
        throwsA(isA<NoDeviceIdentity>()),
      );
      expect(t.count('/devices'), 0);
      expect(keys.writes.length, writesBefore);
      expect(await keys.contains(LocalLedgerKeys.identity), isFalse);
      expect(await keys.contains(SessionItems.deviceId), isFalse);
      expect(c.current, isNot(isA<Active>()));
    });

    test('C-06-27 restore() does not restore a stored session whose device id is not the ledger\'s — it logs device_id_stale, stays SignedOut and deletes nothing; a matching id restores', () async {
      scriptHappyPath();
      final c = await client();
      await activate(c);

      // A pre-ratification install: the session was stored under a server-
      // issued id that is not the ledger's.
      await keys.write(
        SessionItems.deviceId,
        Uint8List.fromList(utf8.encode(otherDeviceId)),
      );
      final stale = await client();
      await stale.restore();
      expect(stale.current, isA<SignedOut>());
      expect(log, contains('device_id_stale'));
      expect(await keys.contains(SessionItems.refreshToken), isTrue);
      expect(await keys.contains(KeyIds.deviceSigningKey), isTrue);

      await keys.write(
        SessionItems.deviceId,
        Uint8List.fromList(utf8.encode(deviceId)),
      );
      final fresh = await client();
      await fresh.restore();
      expect(
        fresh.current,
        isA<Active>().having((a) => a.session.deviceId, 'device', deviceId),
      );
    });
  });

  group('06 §3 step 3 — devices/certify (04 §3.4 🔒)', () {
    Map<String, Object?> certBody() =>
        t.last('/devices/certify')['cert']! as Map<String, Object?>;

    test('C-06-28 activation certifies the device: one Bearer call to devices/certify carrying the signature, the issue time and the UMK public half, then the certificate is filed and the session flips to certified', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final certifier = FakeCertifier(await liveSuite());
      final c = await client(certifier: certifier);
      await activate(c);

      expect(t.count('/devices/certify'), 1);
      final sent = t.last('/devices/certify');
      final cert = certBody();
      expect(
        Bytes.fromBase64Url(cert['signature']! as String),
        hasLength(DeviceCert.deviceCertSigBytes),
      );
      expect(cert['issued_at_ms'], 1789000000000);
      expect(cert['issued_by_device'], deviceId, reason: 'self-issued');
      expect(sent['umk_key_version'], umkKeyVersionFirst);
      expect(
        Bytes.fromBase64Url(sent['umk_pub_ed']! as String),
        certifier.umk.public.ed25519,
      );
      // Bearer, per the route table — the same access token the session holds.
      final req = t.requests.lastWhere(
        (r) => r.url.path.endsWith('/devices/certify'),
      );
      expect(req.headers['Authorization'], 'Bearer acc-1');

      expect(certifier.filed.single.deviceId, deviceId);
      expect((c.current as Active).deviceCertified, isTrue);
      expect(log, contains('device_certified'));
      // Nothing about the certificate reaches the log beyond the event name.
      expect(log.any((e) => e.contains(deviceId)), isFalse);
    });

    test('C-06-29 every refusal fails closed: cert_malformed, cert_invalid, umk_unknown, 401 and 500 each leave the device registered-but-uncertified with nothing filed, and surface a typed reason on a retry', () async {
      const cases = <(int, String, CertRefusal)>[
        (400, 'cert_malformed', CertRefusal.certMalformed),
        (400, 'cert_invalid', CertRefusal.certInvalid),
        (400, 'umk_unknown', CertRefusal.umkUnknown),
        (401, 'unauthenticated', CertRefusal.unavailable),
        (500, '', CertRefusal.unavailable),
      ];
      for (final (status, error, reason) in cases) {
        t = ScriptedTransport();
        keys = FakeKeyStore();
        await seedLedgerIdentity(keys);
        log = [];
        scriptHappyPath();
        t.on(
          '/devices/certify',
          ScriptedTransport.ok({if (error.isNotEmpty) 'error': error}, status),
        );
        final certifier = FakeCertifier(await liveSuite());
        final c = await client(certifier: certifier);

        // Activation itself still succeeds — the device is registered and
        // signed in; it simply sees nothing but itself (ADR 05d §2).
        final session = await activate(c);
        expect(session.deviceId, deviceId, reason: error);
        expect((c.current as Active).deviceCertified, isFalse, reason: error);
        expect(certifier.filed, isEmpty, reason: error);
        expect(log, contains('device_uncertified'), reason: error);
        expect(log, isNot(contains('device_certified')), reason: error);

        // Retried by hand (S0.9), the reason is typed, not a status code.
        await expectLater(
          c.certifyDevice(),
          throwsA(
            isA<CertificationRefused>().having(
              (r) => r.reason,
              'reason',
              reason,
            ),
          ),
          reason: error,
        );
        expect(certifier.filed, isEmpty, reason: error);
        expect((c.current as Active).deviceCertified, isFalse, reason: error);
      }
    });

    test('C-06-30 refusals that never reach the network: no session, no ledger bound, a ledger that cannot issue, and a certificate over another device id — none of them post anything', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );

      // Signed out: there is no device to certify.
      final none = await client();
      await expectLater(none.certifyDevice(), throwsA(isA<SessionEnded>()));

      // Active, but no ledger bound: activation reaches for nothing and the
      // explicit call refuses with the typed reason.
      final unbound = await client();
      await activate(unbound);
      expect(t.count('/devices/certify'), 0);
      await expectLater(
        unbound.certifyDevice(),
        throwsA(
          isA<CertificationRefused>().having(
            (r) => r.reason,
            'reason',
            CertRefusal.noKeyMaterial,
          ),
        ),
      );

      // A ledger that will not open.
      final shut = FakeCertifier(await liveSuite())..unopenable = true;
      final c2 = await client(certifier: shut);
      await activate(c2);
      await expectLater(
        c2.certifyDevice(),
        throwsA(
          isA<CertificationRefused>().having(
            (r) => r.reason,
            'reason',
            CertRefusal.noKeyMaterial,
          ),
        ),
      );

      // ADR 2026-09-16 §1: a certificate over any other id is not this
      // device's, and is refused before a byte is sent.
      final wrong = FakeCertifier(
        await liveSuite(),
        certDeviceId: otherDeviceId,
      );
      final c3 = await client(certifier: wrong);
      await activate(c3);
      await expectLater(
        c3.certifyDevice(),
        throwsA(
          isA<CertificationRefused>().having(
            (r) => r.reason,
            'reason',
            CertRefusal.deviceIdMismatch,
          ),
        ),
      );
      expect(t.count('/devices/certify'), 0);
      expect(log, contains('device_cert_id_mismatch'));
      expect(log.any((e) => e.contains(otherDeviceId)), isFalse);
    });

    test('C-06-31 certification runs once, at activation: a device that already holds its certificate signs no second one, a server that merely says certified does not stop it from holding one, and a later launch posts nothing', () async {
      // A server that calls this device certified while the device has filed
      // no certificate: it certifies anyway, because the chain is rooted in
      // what this install holds, not in a status string.
      scriptHappyPath();
      t.script['/devices'] = [
        ScriptedTransport.ok({
          'device_id': deviceId,
          'user_id': 'u-1',
          'status': 'certified',
        }),
      ];
      t.script['/token'] = [
        ScriptedTransport.ok(
          sessionBody('acc-1', 'ref-1', status: 'certified'),
        ),
      ];
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final certifier = FakeCertifier(await liveSuite());
      final c = await client(certifier: certifier);
      await activate(c);
      expect((c.current as Active).deviceCertified, isTrue);
      expect(t.count('/devices/certify'), 1);
      expect(certifier.filed, hasLength(1));

      // A later launch: restore, then a token refresh past the margin. The
      // certificate is the ledger's to hold, so neither asks the server.
      clock.advance(const Duration(minutes: 20));
      t.on('/refresh', ScriptedTransport.ok(sessionBody('acc-2', 'ref-2')));
      final later = await client(certifier: certifier);
      await later.restore();
      await later.accessToken();
      expect(t.count('/devices/certify'), 1);

      // And a fresh activation on an install that already holds one (06 §5
      // Keychain remnant) signs nothing new.
      final before = certifier.issued;
      final again = await client(certifier: certifier);
      await activate(again);
      expect(certifier.issued, before);
      expect(t.count('/devices/certify'), 1);
    });
  });
}
