@Tags(['C'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart' show BookType;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/auth_transport.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart';
import 'package:rukka_folio/shared/ledger/device_certification.dart';
import 'package:rukka_folio/shared/ledger/ledger_identity.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart'
    show IdentityNotConfirmed, LocalLedger;
import 'package:rukka_folio/shared/records/device_added_record.dart';
import 'package:rukka_folio/shared/records/device_record_author.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../../shared/test_app.dart' show openTestDb, testNow;
import '../devices/crypto_helpers.dart';

/// Records every request and answers from a scripted table keyed by the
/// route's trailing path (`/otp/request`, `/token`, …).
final class ScriptedTransport implements AuthTransport {
  final requests =
      <({Uri url, Map<String, String> headers, Map<String, Object?> body})>[];
  final Map<String, List<AuthHttpResponse>> script = {};
  bool offline = false;

  /// Runs as `POST devices` is sent — what had happened by then.
  void Function()? beforeDevices;

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
    if (url.path.endsWith('/devices')) beforeDevices?.call();
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

const phone = '+919999900001'; // reserved test block (ADR 2026-09-05i §7)
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
  String user = ledgerUserId,
}) => keys.write(
  LocalLedgerKeys.identity,
  LedgerIdentity(
    deviceId: device,
    userId: user,
    tenantId: ledgerTenantId,
  ).encode(suiteVersion: 1),
);

final nonce = Uint8List.fromList(List.generate(32, (i) => 255 - i));

/// The id a re-mint hands back (ADR 2026-10-04b §2), and the id of an account
/// the phone already has (§3). Synthetic.
const remintedUserId = '3a4b5c6d-7e8f-4a1b-9c2d-3e4f5a6b7c8d';
const existingUserId = '1f2e3d4c-5b6a-4978-8695-a4b3c2d1e0f9';

/// The ledger as signup sees it (`SignupIdentity`, ADR 2026-10-04b §2). The
/// real one is `LocalLedger` (`test/shared/ledger/provisional_identity_test`);
/// this records what the client asked of it, and re-mints the way the ledger
/// does — by rewriting the identity record the client reads.
final class FakeSignupIdentity implements SignupIdentity {
  FakeSignupIdentity(this.keys);

  final FakeKeyStore keys;
  bool confirmed = false;
  bool refuseRemint = false;
  final confirmedWith = <String>[];
  int reminted = 0;

  /// The SessionItems.userId value at the moment of confirmation: the
  /// identity is confirmed before anything is stored.
  final storedAtConfirm = <bool>[];

  @override
  bool get identityConfirmed => confirmed;

  @override
  Future<void> confirmIdentity(String userId) async {
    storedAtConfirm.add(await keys.contains(SessionItems.userId));
    confirmedWith.add(userId);
    confirmed = true;
  }

  @override
  Future<String> remintProvisionalIdentity() async {
    if (refuseRemint || confirmed) throw const IdentityNotProvisional();
    reminted++;
    await seedLedgerIdentity(keys, user: remintedUserId);
    return remintedUserId;
  }

  /// Ids adopted (ADR 2026-10-04b §3), in order.
  final adopted = <String>[];

  @override
  Future<void> adoptExistingAccount(String userId) async {
    if (confirmed) throw const IdentityNotProvisional();
    adopted.add(userId);
    await seedLedgerIdentity(keys, user: userId);
  }

  /// As the ledger answers it: an adopted account, and (a fake holds none)
  /// no UMK of it.
  @override
  bool get awaitingAccountUmk => adopted.isNotEmpty;
}

/// The ledger's S0.2 key step as the auth client sees it ([DeviceKeyMint],
/// ADR 2026-10-09 §2). The real one is `LocalLedger.mintForRegistration`
/// (`test/shared/ledger/late_bound_keys_test.dart`, and the C-1009-2 tests
/// below over a real ledger); this one writes seeds from the suite the same
/// way — reusing any already held — and counts the asks.
final class FakeKeyMint implements DeviceKeyMint {
  FakeKeyMint(this.keys, this.suite);

  final FakeKeyStore keys;
  final CryptoSuite suite;
  int asked = 0;

  @override
  Future<void> mintForRegistration() async {
    asked++;
    if (await keys.contains(KeyIds.deviceSigningKey) &&
        await keys.contains(KeyIds.deviceAgreementKey)) {
      return;
    }
    await keys.write(KeyIds.deviceSigningKey, suite.randomBytes(32));
    await keys.write(KeyIds.deviceAgreementKey, suite.randomBytes(32));
  }
}

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
      umkPubX: umk.public.x25519,
    );
  }

  @override
  Future<void> installOwnCert(DeviceCert cert) async => filed.add(cert);

  @override
  DeviceCert? get ownDeviceCert => filed.isEmpty ? null : filed.last;

  /// How many times the launch-time re-offer asked for the filed certificate.
  int reoffered = 0;

  /// The offers the client recorded as accepted by the server (owner ruling
  /// 25 Sep, PLAN desk 33). The real ledger persists this and checks the x
  /// half; `umk_reoffer_ledger_test.dart` covers that.
  final accepted = <DeviceCertOffer>[];

  /// Models a device certified by a build before ADR 2026-09-24b §2: it holds
  /// a certificate, but the server never got its x half.
  void forgetAcceptance() => accepted.clear();

  @override
  Future<void> recordUmkPubsAccepted(DeviceCertOffer offer) async =>
      accepted.add(offer);

  @override
  DeviceCertOffer? reofferOwnCert() {
    final cert = ownDeviceCert;
    if (unopenable || cert == null || accepted.isNotEmpty) return null;
    reoffered++;
    return DeviceCertOffer(
      cert: cert,
      umkPubEd: umk.public.ed25519,
      umkPubX: umk.public.x25519,
    );
  }
}

/// Captures the `device_added` records the client files (06 §5 🔒), and can
/// fail the way the record route can. [filedWhenPosted] is how the ordering
/// rule is checked: the certificate must already be installed when the record
/// goes out, or no reader could verify the record's own author (04 §3.4).
final class CapturingPost {
  CapturingPost(this.certifier, {this.throws = false});

  final FakeCertifier certifier;
  final bool throws;
  final posted = <Map<String, Object?>>[];
  final filedWhenPosted = <int>[];

  Future<List<String>> call(List<Map<String, Object?>> records) async {
    filedWhenPosted.add(certifier.filed.length);
    if (throws) throw Exception('no network');
    posted.addAll(records);
    return List.filled(records.length, 'no projection');
  }
}

/// The device key pair the client generated and stored, rebuilt from its
/// seeds — the same replay `DeviceRecordAuthor` does, so a test can verify a
/// record's signature under the key that actually signed it.
Future<DevicePublic> storedDevicePublic(
  CryptoSuite suite,
  FakeKeyStore keys,
) async {
  final queue = <Uint8List>[
    Uint8List.fromList((await keys.read(KeyIds.deviceSigningKey))!),
    Uint8List.fromList((await keys.read(KeyIds.deviceAgreementKey))!),
  ];
  return DeviceKeyPair.generate(
    CryptoSuite(suite.sodium, random: (_) => queue.removeAt(0)),
    deviceId: deviceId,
  ).public;
}

/// An announcer that breaks its own contract, to prove the client does not
/// depend on it keeping it.
final class ThrowingAnnouncer implements DeviceAddedAnnouncer {
  @override
  Future<void> deviceAdded(
    DeviceCert cert, {
    required int umkKeyVersion,
    String? issuedByDevice,
  }) async => throw Exception('announcer is broken');
}

/// The payload bytes exactly as they travel — never re-encoded, so a test
/// checks the bytes that were signed.
Uint8List payloadBytesOf(Map<String, Object?> row) => Uint8List.fromList(
  base64.decode(
    base64.normalize(
      (row['payload_json']! as String)
          .replaceAll('-', '+')
          .replaceAll('_', '/'),
    ),
  ),
);

Map<String, Object?> payloadOf(Map<String, Object?> row) =>
    jsonDecode(utf8.decode(payloadBytesOf(row))) as Map<String, Object?>;

void main() {
  late ScriptedTransport t;
  late FakeKeyStore keys;
  late TestClock clock;
  late List<String> log;
  late FakeKeyMint mint;

  Future<HttpAuthClient> client({
    DeviceCertifier? certifier,
    bool bindMint = true,
  }) async {
    final suite = await liveSuite();
    mint = FakeKeyMint(keys, suite);
    return HttpAuthClient(
      transport: t,
      suite: suite,
      keys: keys,
      now: clock.call,
      baseUrl: Uri.parse('https://api.test/functions/v1/'),
      clientVersion: '1.2.0',
      deviceModel: 'Pixel 8',
      deviceOs: 'Android 15',
      log: log.add,
      certifier: certifier,
      keyMint: bindMint ? mint : null,
    );
  }

  void scriptHappyPath() {
    t.on(
      '/otp/request',
      ScriptedTransport.ok({'ok': true, 'resend_after_s': 30}),
    );
    t.on(
      '/otp/verify',
      ScriptedTransport.ok({
        'ticket': 'tk-1',
        'user_id': ledgerUserId,
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
    test('C-06-7 requestOtp posts the phone once, surfaces the channel as state, moves to OtpSent, and no phone or code ever reaches the log', () async {
      final c = await client();
      t.on(
        '/otp/request',
        ScriptedTransport.ok({'ok': true, 'resend_after_s': 30}),
      );
      await c.requestOtp(phone);
      expect(t.count('/otp/request'), 1);
      // The default channel is SMS (ADR 2026-09-25 §1) — asserted in C-25-1.
      expect(t.last('/otp/request')['phone'], phone);
      expect(t.last('/otp/request')['purpose'], 'signup');
      expect(t.requests.single.headers['x-rukka-client-version'], '1.2.0');
      expect(c.resendAfter.value, const Duration(seconds: 30));
      expect(c.current, isA<OtpSent>().having((s) => s.phone, 'phone', phone));

      // SMS asked for explicitly: the channel travels as `channel` and is
      // the state the client holds (06 §2 as amended by ADR 2026-09-25 §1).
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
          'user_id': ledgerUserId,
          'expires_in_s': 600,
        }),
      );
      await c.verifyOtp(code);
      expect(t.last('/otp/verify'), {
        'phone': phone,
        'purpose': 'device_activation',
        'code': code,
        'user_id': ledgerUserId,
      });
      final joined = log.join('\n');
      expect(joined, isNot(contains(phone.substring(3))));
      expect(joined, isNot(contains(code)));
      expect(joined, isNot(contains('tk')));
      expect(log, isNotEmpty);
    });

    test('C-25-1 OTP is SMS only (ADR 2026-09-25 §1): the client can name no other channel, requests `sms` by default, and a server answer naming any other channel never becomes a WhatsApp state', () async {
      // The client's vocabulary is SMS alone — WhatsApp is not a state it can
      // hold, so no screen can render one.
      expect(OtpChannel.values, [OtpChannel.sms]);
      expect(OtpChannel.sms.wire, 'sms');

      final c = await client();
      expect(c.otpChannel.value, isNull); // nothing sent yet
      // One scripted answer per request: drop the previous one first (the
      // transport queues answers and replays the last).
      void answer(Map<String, Object?> body) {
        t.script.remove('/otp/request');
        t.on('/otp/request', ScriptedTransport.ok(body));
      }

      // Default request: `channel: sms` on the wire, and SMS is the state.
      answer({'ok': true, 'resend_after_s': 30});
      await c.requestOtp(phone);
      expect(t.last('/otp/request'), {
        'phone': phone,
        'purpose': 'signup',
        'channel': 'sms',
      });
      expect(c.otpChannel.value, OtpChannel.sms);

      // A server that names SMS keeps SMS.
      answer({'ok': true, 'resend_after_s': 60, 'channel': 'sms'});
      await c.requestOtp(phone);
      expect(t.last('/otp/request')['channel'], 'sms');
      expect(c.otpChannel.value, OtpChannel.sms);

      // A server that names any other channel — WhatsApp included — is not
      // believed as SMS and is not a WhatsApp state: the channel is unknown.
      // The code was still sent, so the flow moves on to OtpSent.
      for (final other in ['whatsapp', 'WhatsApp', 'rcs', '', 7]) {
        answer({'ok': true, 'resend_after_s': 30, 'channel': other});
        log.clear();
        await c.requestOtp(phone);
        expect(t.last('/otp/request')['channel'], 'sms', reason: '$other');
        expect(c.otpChannel.value, isNull, reason: '$other');
        expect(c.current, isA<OtpSent>(), reason: '$other');
        expect(log, contains('otp_channel_unrecognised'), reason: '$other');
        final joined = log.join('\n');
        expect(joined, isNot(contains(phone.substring(3))));
        expect(joined.toLowerCase(), isNot(contains('whatsapp')));
      }

      // And the answer after that, naming nothing, is SMS again — the unknown
      // does not stick.
      answer({'ok': true, 'resend_after_s': 30});
      await c.requestOtp(phone);
      expect(c.otpChannel.value, OtpChannel.sms);
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
        'user_id': ledgerUserId,
      });
    });
  });

  group('HttpAuthClient — 06 §3 registration, 06 §4 sessions', () {
    test('C-06-9 activateDevice asks the ledger\'s S0.2 step for the Ed25519 + X25519 seeds in KeyIds (ADR 2026-10-09 §2 — re-read: it no longer mints them itself), registers with ticket + public keys + model/os, then signs nonce ‖ device_id ‖ unix_ts with the device key and opens an uncertified Active session', () async {
      final c = await client();
      scriptHappyPath();
      t.beforeDevices = () => expect(mint.asked, 1, reason: 'before POST');
      final s = await activate(c);
      expect(mint.asked, 1);

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
      // Written once, by the ledger's step (ADR 2026-10-09 §2) — never by
      // this client.
      expect(log, isNot(contains('device_keys_generated')));

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
          'user_id': ledgerUserId,
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
          'user_id': ledgerUserId,
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
      // verifyOtp itself refuses with no identity since ADR 2026-10-04b §1
      // (C-04b-1); a ticket from elsewhere still finds activation closed.
      const ticket = ActivationTicket('tk-1');
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

    test('C-06-29 every refusal fails closed: cert_malformed, cert_invalid, umk_unknown, umk_pub_conflict, umk_pub_malformed, 401 and 500 each leave the device registered-but-uncertified with nothing filed, and surface a typed reason on a retry', () async {
      const cases = <(int, String, CertRefusal)>[
        (400, 'cert_malformed', CertRefusal.certMalformed),
        (400, 'cert_invalid', CertRefusal.certInvalid),
        (400, 'umk_unknown', CertRefusal.umkUnknown),
        // Since activation carries `umk_pub_x` (ADR 2026-09-24b §2) the
        // server's x-half check runs before the signature check, so a phone
        // holding a different UMK than the account's hears `umk_pub_conflict`
        // where it used to hear `cert_invalid`: the same fact, the same
        // answer — recovery, not a retry. A malformed half is a known
        // refusal too, never "nothing is known".
        (400, 'umk_pub_conflict', CertRefusal.certInvalid),
        (400, 'umk_pub_malformed', CertRefusal.certMalformed),
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

    test('C-06-31 certification runs once, at activation: a device that already holds its certificate signs no second one, a server that merely says certified does not stop it from holding one, and restore() alone posts nothing (the per-launch umk_pub_x re-offer is F1-24b-2, ADR 2026-09-24b §2)', () async {
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
  group('ADR 2026-09-24b §2 — every device offers umk_pub_x', () {
    // The halves as the request body carried them, decoded.
    (Uint8List, Uint8List) halves(Map<String, Object?> body) => (
      Bytes.fromBase64Url(body['umk_pub_ed']! as String),
      Bytes.fromBase64Url(body['umk_pub_x']! as String),
    );

    test('F1-24b-2 activation sends BOTH UMK public halves on devices/certify: umk_pub_ed and umk_pub_x are the certifier\'s own, 32 bytes each, and distinct', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final certifier = FakeCertifier(await liveSuite());
      final c = await client(certifier: certifier);
      await activate(c);

      final sent = t.last('/devices/certify');
      expect(sent.containsKey('umk_pub_x'), isTrue, reason: '04 §6.3 🔒');
      final (ed, x) = halves(sent);
      expect(ed, certifier.umk.public.ed25519);
      expect(x, certifier.umk.public.x25519);
      expect(x, hasLength(32));
      expect(x, isNot(ed), reason: 'the x half is its own seed, not pub_ed');
    });

    test('F1-24b-2 a later launch re-offers once, with no prompt: the FILED certificate (same signature, same issue time) and both halves, one Bearer call — nothing issued, nothing filed, nothing announced, and a second call in the same launch posts nothing', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final certifier = FakeCertifier(await liveSuite());
      final first = await client(certifier: certifier);
      await activate(first);
      certifier.forgetAcceptance(); // certified by a build before ADR 24b §2
      expect(t.count('/devices/certify'), 1);
      final filed = certifier.filed.single;
      final issued = certifier.issued;

      // A later launch: restore, exactly as C-06-31 — which still posts
      // nothing on its own — then the composition root's one re-offer.
      clock.advance(const Duration(minutes: 20));
      t.on('/refresh', ScriptedTransport.ok(sessionBody('acc-2', 'ref-2')));
      final posted = CapturingPost(certifier);
      final later = await client(certifier: certifier)
        ..announcer = DeviceAddedRecorder(
          author: DeviceRecordAuthor(
            suite: await liveSuite(),
            keys: keys,
            deviceIdOf: () async => deviceId,
            clock: RecordHlcClock(clock.call),
          ),
          tenantId: ledgerTenantId,
          post: posted.call,
        );
      await later.restore();
      expect(t.count('/devices/certify'), 1, reason: 'restore alone is quiet');

      expect(await later.reofferUmkPublic(), UmkReoffer.accepted);
      expect(t.count('/devices/certify'), 2);
      final sent = t.last('/devices/certify');
      final cert = sent['cert']! as Map<String, Object?>;
      expect(
        Bytes.fromBase64Url(cert['signature']! as String),
        filed.signature,
      );
      expect(cert['issued_at_ms'], filed.issuedAtMs);
      expect(cert['issued_by_device'], deviceId);
      expect(sent['umk_key_version'], umkKeyVersionFirst);
      final (ed, x) = halves(sent);
      expect(ed, certifier.umk.public.ed25519);
      expect(x, certifier.umk.public.x25519);
      final req = t.requests.lastWhere(
        (r) => r.url.path.endsWith('/devices/certify'),
      );
      expect(req.headers['Authorization'], 'Bearer acc-2');

      // Harmless: no new certificate, no second filing, no device_added.
      expect(certifier.issued, issued);
      expect(certifier.filed, hasLength(1));
      expect(posted.posted, isEmpty);
      expect(log, contains('umk_pub_reoffered'));
      expect(log.where((e) => e.startsWith('device_certify_refused')), isEmpty);

      // Once per launch.
      expect(await later.reofferUmkPublic(), UmkReoffer.skipped);
      expect(t.count('/devices/certify'), 2);
    });

    test('F1-24b-2 a re-offer the server refuses, or cannot hear, is harmless: it never throws, never un-certifies, files and announces nothing, and files no certification refusal', () async {
      final cases = <(String, AuthHttpResponse?, UmkReoffer)>[
        (
          'umk_pub_conflict',
          ScriptedTransport.ok({'error': 'umk_pub_conflict'}, 400),
          UmkReoffer.refused,
        ),
        (
          'cert_invalid',
          ScriptedTransport.ok({'error': 'cert_invalid'}, 400),
          UmkReoffer.refused,
        ),
        ('500', const AuthHttpResponse(500, ''), UmkReoffer.refused),
        ('offline', null, UmkReoffer.unreachable),
      ];
      for (final (name, answer, outcome) in cases) {
        t = ScriptedTransport();
        keys = FakeKeyStore();
        await seedLedgerIdentity(keys);
        log = [];
        scriptHappyPath();
        t.on(
          '/devices/certify',
          ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
        );
        final certifier = FakeCertifier(await liveSuite());
        final c = await client(certifier: certifier);
        await activate(c);
        certifier.forgetAcceptance(); // certified by a build before ADR 24b §2
        expect((c.current as Active).deviceCertified, isTrue, reason: name);

        t.script['/devices/certify'] = [?answer];
        if (answer == null) t.offline = true;
        final before = t.count('/devices/certify');
        expect(await c.reofferUmkPublic(), outcome, reason: name);
        expect(
          t.count('/devices/certify'),
          answer == null ? before : before + 1,
          reason: name,
        );
        expect((c.current as Active).deviceCertified, isTrue, reason: name);
        expect(certifier.filed, hasLength(1), reason: name);
        expect(
          log.where((e) => e.startsWith('device_certify_refused')),
          isEmpty,
          reason: '$name: a re-offer is not a certification attempt',
        );
        expect(log, isNot(contains('device_uncertified')), reason: name);
        expect(log.any((e) => e.contains(deviceId)), isFalse, reason: name);
        if (name == 'umk_pub_conflict') {
          expect(log, contains('umk_pub_conflict'));
        }
      }
    });

    test('C-06-10 the launch re-offer and another caller that both need a token share ONE refresh: the rotated refresh token is never presented twice, so the server never sees a reuse, never revokes the family, and the device stays signed in', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final certifier = FakeCertifier(await liveSuite());
      await activate(await client(certifier: certifier));
      certifier.forgetAcceptance(); // certified by a build before ADR 24b §2

      // A rotating server: the first presentation of `ref-1` rotates it, a
      // second is a reuse and ends the family (06 §4 step 2 🔒; index.ts
      // `refresh_reused`). A client that let two callers refresh at once
      // would sign itself out here.
      clock.advance(const Duration(minutes: 20));
      t.script['/refresh'] = [
        ScriptedTransport.ok(sessionBody('acc-2', 'ref-2')),
        ScriptedTransport.ok({'error': 'refresh_reused'}, 401),
      ];
      final later = await client(certifier: certifier);
      await later.restore();

      // Cold start: the composition root's unawaited re-offer, and in the
      // same instant a sync cycle asking for its bearer.
      final reoffer = later.reofferUmkPublic();
      final token = later.accessToken();
      expect(await token, 'acc-2');
      expect(await reoffer, UmkReoffer.accepted);

      expect(t.count('/refresh'), 1, reason: 'one refresh, shared');
      expect(t.last('/refresh')['refresh_token'], 'ref-1');
      expect(later.current, isA<Active>());
      expect(log, isNot(contains('signed_out')));
      expect(log, isNot(contains('session_ended')));
      expect(await keys.contains(SessionItems.refreshToken), isTrue);
      final certify = t.requests.lastWhere(
        (r) => r.url.path.endsWith('/devices/certify'),
      );
      expect(certify.headers['Authorization'], 'Bearer acc-2');

      // Once it has landed the next caller reads the cached token and posts
      // nothing; a later expiry refreshes again, with the ROTATED token.
      expect(await later.accessToken(), 'acc-2');
      expect(t.count('/refresh'), 1);
      clock.advance(const Duration(minutes: 20));
      t.script['/refresh'] = [
        ScriptedTransport.ok(sessionBody('acc-3', 'ref-3')),
      ];
      expect(await later.accessToken(), 'acc-3');
      expect(t.last('/refresh')['refresh_token'], 'ref-2');
    });

    test('C-06-10 a shared refresh the server refuses ends the session once: every waiting caller hears SessionEnded, one /refresh was posted, and the re-offer still never throws', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final certifier = FakeCertifier(await liveSuite());
      await activate(await client(certifier: certifier));
      certifier.forgetAcceptance(); // certified by a build before ADR 24b §2

      clock.advance(const Duration(minutes: 20));
      t.script['/refresh'] = [
        ScriptedTransport.ok({'error': 'refresh_invalid'}, 401),
      ];
      final later = await client(certifier: certifier);
      await later.restore();

      final reoffer = later.reofferUmkPublic();
      final a = later.accessToken();
      final b = later.accessToken();
      await expectLater(a, throwsA(isA<SessionEnded>()));
      await expectLater(b, throwsA(isA<SessionEnded>()));
      expect(await reoffer, UmkReoffer.unreachable);
      expect(t.count('/refresh'), 1);
      expect(log.where((e) => e == 'signed_out'), hasLength(1));
      expect(later.current, isA<SignedOut>());
    });

    test('F1-24b-2 an accepted re-offer is recorded, so the next launch posts nothing — the re-offer stops after one success (owner ruling 25 Sep)', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final certifier = FakeCertifier(await liveSuite());
      await activate(await client(certifier: certifier));
      certifier.forgetAcceptance(); // certified by a build before ADR 24b §2

      clock.advance(const Duration(minutes: 20));
      t.on('/refresh', ScriptedTransport.ok(sessionBody('acc-2', 'ref-2')));
      final second = await client(certifier: certifier);
      await second.restore();
      expect(await second.reofferUmkPublic(), UmkReoffer.accepted);
      expect(certifier.accepted, hasLength(1));
      final (_, x) = halves(t.last('/devices/certify'));
      expect(certifier.accepted.single.umkPubX, x);
      final posts = t.count('/devices/certify');

      t.on('/refresh', ScriptedTransport.ok(sessionBody('acc-3', 'ref-3')));
      final third = await client(certifier: certifier);
      await third.restore();
      expect(await third.reofferUmkPublic(), UmkReoffer.skipped);
      expect(t.count('/devices/certify'), posts);
    });

    test('F1-24b-2 a refused or unheard re-offer records nothing, so the next launch tries again', () async {
      for (final answer in [
        ScriptedTransport.ok({'error': 'cert_invalid'}, 400),
        const AuthHttpResponse(500, ''),
        null,
      ]) {
        t = ScriptedTransport();
        keys = FakeKeyStore();
        await seedLedgerIdentity(keys);
        log = [];
        scriptHappyPath();
        t.on(
          '/devices/certify',
          ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
        );
        final certifier = FakeCertifier(await liveSuite());
        final c = await client(certifier: certifier);
        await activate(c);
        certifier.forgetAcceptance(); // certified by a build before ADR 24b §2

        t.script['/devices/certify'] = [?answer];
        if (answer == null) t.offline = true;
        expect(await c.reofferUmkPublic(), isNot(UmkReoffer.accepted));
        expect(certifier.accepted, isEmpty, reason: '$answer');
        t.offline = false;

        t.script['/devices/certify'] = [
          ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
        ];
        t.on('/refresh', ScriptedTransport.ok(sessionBody('acc-2', 'ref-2')));
        final next = await client(certifier: certifier);
        await next.restore();
        final before = t.count('/devices/certify');
        expect(await next.reofferUmkPublic(), UmkReoffer.accepted);
        expect(t.count('/devices/certify'), before + 1);
      }
    });

    test('F1-24b-2 an activation the server certified carried both halves, so it is recorded too: a device activated on this build never re-offers', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final certifier = FakeCertifier(await liveSuite());
      await activate(await client(certifier: certifier));
      expect(certifier.accepted, hasLength(1));
      final (_, x) = halves(t.last('/devices/certify'));
      expect(certifier.accepted.single.umkPubX, x);
      final posts = t.count('/devices/certify');

      clock.advance(const Duration(minutes: 20));
      t.on('/refresh', ScriptedTransport.ok(sessionBody('acc-2', 'ref-2')));
      final later = await client(certifier: certifier);
      await later.restore();
      expect(await later.reofferUmkPublic(), UmkReoffer.skipped);
      expect(t.count('/devices/certify'), posts);
    });

    test('F1-24b-2 a refused activation records nothing', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'error': 'cert_invalid'}, 400),
      );
      final certifier = FakeCertifier(await liveSuite());
      await activate(await client(certifier: certifier));
      expect(certifier.ownDeviceCert, isNull);
      expect(certifier.accepted, isEmpty);
    });

    test('F1-24b-2 nothing to re-offer posts nothing: signed out, no ledger bound, a closed ledger, and a device that holds no certificate yet (its activation carries both halves)', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final signedOut = await client(
        certifier: FakeCertifier(await liveSuite()),
      );
      expect(await signedOut.reofferUmkPublic(), UmkReoffer.skipped);

      final unbound = await client();
      await activate(unbound);
      expect(await unbound.reofferUmkPublic(), UmkReoffer.skipped);

      final shut = FakeCertifier(await liveSuite())..unopenable = true;
      final c2 = await client(certifier: shut);
      await activate(c2);
      expect(await c2.reofferUmkPublic(), UmkReoffer.skipped);

      t.script['/devices/certify'] = [
        ScriptedTransport.ok({'error': 'cert_invalid'}, 400),
      ];
      final uncertified = FakeCertifier(await liveSuite());
      final c3 = await client(certifier: uncertified);
      await activate(c3);
      final after = t.count('/devices/certify');
      expect(uncertified.ownDeviceCert, isNull);
      expect(await c3.reofferUmkPublic(), UmkReoffer.skipped);
      expect(t.count('/devices/certify'), after);
      expect(uncertified.reoffered, 0);
    });
  });
  group('06 §5 🔒 — device_added (ADR 2026-09-05d §6)', () {
    /// A live recorder over the key store the client itself writes its device
    /// seeds into: the record is signed by the device that was certified, not
    /// by a stand-in.
    Future<CapturingPost> announce(
      HttpAuthClient c,
      FakeCertifier certifier, {
      bool throws = false,
    }) async {
      final post = CapturingPost(certifier, throws: throws);
      c.announcer = DeviceAddedRecorder(
        author: DeviceRecordAuthor(
          suite: await liveSuite(),
          keys: keys,
          deviceIdOf: () async => deviceId,
          clock: RecordHlcClock(clock.call),
        ),
        tenantId: ledgerTenantId,
        post: post.call,
        log: log.add,
      );
      return post;
    }

    test('C-06-32 a certified device announces itself exactly once: one device_added record on the record route, its payload the certificate that was just filed, signed under this device key — and filed before it is posted', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final suite = await liveSuite();
      final certifier = FakeCertifier(suite);
      final c = await client(certifier: certifier);
      final post = await announce(c, certifier);

      await activate(c);

      expect((c.current as Active).deviceCertified, isTrue);
      expect(post.posted, hasLength(1));
      final row = post.posted.single;
      expect(row['kind'], SignedRecordKind.deviceAdded);
      expect(row['tenant_id'], ledgerTenantId);
      expect(row['author_device_id'], deviceId);

      // The record IS the certificate the ledger filed (ADR 05d §6).
      final filed = certifier.filed.single;
      expect(payloadOf(row), {
        'device_id': deviceId,
        'signature': Bytes.base64Url(filed.signature),
        'issued_at_ms': filed.issuedAtMs,
        'issued_by_device': deviceId,
        'umk_key_version': umkKeyVersionFirst,
      });

      // Install first, post second — the chain must be able to verify the
      // record's own author.
      expect(post.filedWhenPosted, [1]);

      // Signed by the device this client registered.
      final record = SignedRecord(
        suiteVersion: row['suite_version']! as int,
        tenantId: row['tenant_id']! as String,
        kind: row['kind']! as String,
        payloadJson: payloadBytesOf(row),
        authorDeviceId: row['author_device_id']! as String,
        authorSig: Bytes.fromBase64Url(row['author_sig']! as String),
        hlc: row['hlc']! as int,
      );
      expect(
        record.verifySignature(
          await liveSuite(),
          await storedDevicePublic(suite, keys),
        ),
        isTrue,
      );
      expect(log, contains('device_certified'));
      expect(log, isNot(contains(DeviceAddedRecorder.unfiledEvent)));
    });

    test('C-06-33 a device that was not certified announces nothing: a server refusal and a certificate over another device id each leave the record unauthored and unposted', () async {
      // The server refuses the certificate.
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'error': 'cert_invalid'}, 400),
      );
      final certifier = FakeCertifier(await liveSuite());
      final c = await client(certifier: certifier);
      final post = await announce(c, certifier);
      await activate(c);
      expect((c.current as Active).deviceCertified, isFalse);
      expect(certifier.filed, isEmpty);
      expect(post.posted, isEmpty);
      expect(post.filedWhenPosted, isEmpty);
      expect(log, isNot(contains(DeviceAddedRecorder.unfiledEvent)));

      // Refused before a byte was sent (ADR 2026-09-16 §1): still nothing.
      t = ScriptedTransport();
      keys = FakeKeyStore();
      await seedLedgerIdentity(keys);
      log = [];
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final wrong = FakeCertifier(
        await liveSuite(),
        certDeviceId: otherDeviceId,
      );
      final c2 = await client(certifier: wrong);
      final post2 = await announce(c2, wrong);
      await activate(c2);
      expect(post2.posted, isEmpty);
      expect(log, contains('device_cert_id_mismatch'));
    });

    test('C-06-34 an announcement that fails costs nothing: the device stays certified, certifyDevice returns, the log holds one fixed event name and no id — and a device that already holds a certificate never files a second record', () async {
      scriptHappyPath();
      t.on(
        '/devices/certify',
        ScriptedTransport.ok({'device_id': deviceId, 'status': 'certified'}),
      );
      final certifier = FakeCertifier(await liveSuite());
      final c = await client(certifier: certifier);
      final post = await announce(c, certifier, throws: true);

      // Activation completes normally: the post threw, and it was the
      // recorder's to swallow.
      await activate(c);
      expect((c.current as Active).deviceCertified, isTrue);
      expect(certifier.filed, hasLength(1));
      expect(post.posted, isEmpty);
      expect(log, contains('device_certified'));
      expect(log, contains(DeviceAddedRecorder.unfiledEvent));
      expect(log, isNot(contains('device_uncertified')));
      expect(log.any((e) => e.contains(deviceId)), isFalse);
      expect(log.any((e) => e.contains(ledgerTenantId)), isFalse);

      // An announcer that throws out of the seam itself is caught too — no
      // implementation of it may un-certify a certified device.
      t.on('/refresh', ScriptedTransport.ok(sessionBody('acc-2', 'ref-2')));
      final rude = await client(certifier: FakeCertifier(await liveSuite()));
      rude.announcer = ThrowingAnnouncer();
      await rude.restore();
      await rude.certifyDevice();
      expect((rude.current as Active).deviceCertified, isTrue);

      // 06 §5 says *newly* certified: this install already held a
      // certificate, so an S0.9 retry after a success announces nothing.
      final before = post.filedWhenPosted.length;
      await c.certifyDevice();
      expect(certifier.filed, hasLength(2), reason: 'it did re-certify');
      expect(post.filedWhenPosted, hasLength(before));
      expect(post.posted, isEmpty);
    });
  });

  group('ADR 2026-10-04b — the first device mints user_id', () {
    late FakeSignupIdentity identity;

    Future<HttpAuthClient> signupClient() async {
      final c = await client();
      identity = FakeSignupIdentity(keys);
      c.signupIdentity = identity;
      return c;
    }

    void scriptRequest() => t.on(
      '/otp/request',
      ScriptedTransport.ok({'ok': true, 'resend_after_s': 30}),
    );

    Map<String, Object?> verified(String userId) => {
      'ticket': 'tk-1',
      'user_id': userId,
      'expires_in_s': 600,
    };

    List<Map<String, Object?>> verifyBodies() => [
      for (final r in t.requests)
        if (r.url.path.endsWith('/otp/verify')) r.body,
    ];

    test('C-04b-1 verifyOtp sends the ledger identity\'s user_id and, when the '
        'server echoes it, confirms the identity and only then stores it under '
        'SessionItems.userId — no id reaches the log', () async {
      final c = await signupClient();
      scriptRequest();
      t.on('/otp/verify', ScriptedTransport.ok(verified(ledgerUserId)));
      await c.requestOtp(phone);
      final ticket = await c.verifyOtp(code);

      expect(ticket.value, 'tk-1');
      expect(verifyBodies().single, {
        'phone': phone,
        'purpose': 'signup',
        'code': code,
        'user_id': ledgerUserId,
      });
      expect(identity.confirmedWith, [ledgerUserId]);
      expect(identity.storedAtConfirm, [false]);
      expect(
        utf8.decode((await keys.read(SessionItems.userId))!),
        ledgerUserId,
      );
      expect(log.join('\n'), isNot(contains(ledgerUserId)));
    });

    test('C-04b-1 an echo that is missing or is not a uuid is refused as '
        'unavailable: nothing confirmed, nothing stored', () async {
      for (final echo in <Object?>[null, '', 'u-1', 42]) {
        t = ScriptedTransport();
        final c = await signupClient();
        scriptRequest();
        t.on(
          '/otp/verify',
          ScriptedTransport.ok({'ticket': 'tk-1', 'user_id': echo}),
        );
        await c.requestOtp(phone);
        await expectLater(
          c.verifyOtp(code),
          throwsA(
            isA<AuthFailure>().having(
              (f) => f.kind,
              'kind',
              AuthFailureKind.unavailable,
            ),
          ),
          reason: 'echo $echo',
        );
        expect(identity.confirmedWith, isEmpty);
        expect(await keys.contains(SessionItems.userId), isFalse);
      }
    });

    test(
      'C-04b-1 with no ledger identity verifyOtp throws NoDeviceIdentity '
      'before any request — it never sends a request without the id',
      () async {
        await keys.delete(LocalLedgerKeys.identity);
        final c = await signupClient();
        scriptRequest();
        t.on('/otp/verify', ScriptedTransport.ok(verified(ledgerUserId)));
        await c.requestOtp(phone);
        await expectLater(c.verifyOtp(code), throwsA(isA<NoDeviceIdentity>()));
        expect(t.count('/otp/verify'), 0);
        expect(await keys.contains(SessionItems.userId), isFalse);
      },
    );

    test('C-04b-3 409 user_id_taken re-mints the provisional identity and '
        'retries ONCE with the same code and the fresh id; the fresh id is '
        'what is confirmed and stored', () async {
      final c = await signupClient();
      scriptRequest();
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({'error': 'user_id_taken'}, 409),
      );
      t.on('/otp/verify', ScriptedTransport.ok(verified(remintedUserId)));
      await c.requestOtp(phone);
      await c.verifyOtp(code);

      final bodies = verifyBodies();
      expect(bodies, hasLength(2));
      expect(bodies[0]['user_id'], ledgerUserId);
      expect(bodies[1]['user_id'], remintedUserId);
      expect(bodies[1]['code'], code);
      expect(identity.reminted, 1);
      expect(identity.confirmedWith, [remintedUserId]);
      expect(
        utf8.decode((await keys.read(SessionItems.userId))!),
        remintedUserId,
      );
      expect(log.join('\n'), isNot(contains(remintedUserId)));
    });

    test('C-04b-3 the retry is once: a second 409, a re-mint the ledger '
        'refuses (confirmed or authored) and a client with no ledger bound each '
        'end unavailable with nothing stored', () async {
      // A second 409.
      var c = await signupClient();
      scriptRequest();
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({'error': 'user_id_taken'}, 409),
      );
      await c.requestOtp(phone);
      await expectLater(
        c.verifyOtp(code),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.unavailable,
          ),
        ),
      );
      expect(t.count('/otp/verify'), 2);
      expect(identity.reminted, 1);
      expect(identity.confirmedWith, isEmpty);
      expect(await keys.contains(SessionItems.userId), isFalse);

      // The ledger refuses the re-mint.
      t = ScriptedTransport();
      await seedLedgerIdentity(keys);
      c = await signupClient();
      identity.refuseRemint = true;
      scriptRequest();
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({'error': 'user_id_taken'}, 409),
      );
      await c.requestOtp(phone);
      await expectLater(c.verifyOtp(code), throwsA(isA<AuthFailure>()));
      expect(t.count('/otp/verify'), 1);
      expect(identity.reminted, 0);

      // No ledger bound.
      t = ScriptedTransport();
      c = await client();
      scriptRequest();
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({'error': 'user_id_taken'}, 409),
      );
      await c.requestOtp(phone);
      await expectLater(c.verifyOtp(code), throwsA(isA<AuthFailure>()));
      expect(t.count('/otp/verify'), 1);
      expect(await keys.contains(SessionItems.userId), isFalse);
    });

    test('C-04b-2 C-04b-4 ADR 04b §3: a verify that answers ANOTHER account\'s '
        'user_id surfaces existingAccount — the ledger adopts that id before '
        'anything is authored (C-04b-4), the session stores nothing, the '
        'identity is not confirmed, no device is registered, and the spent '
        'code is forgotten', () async {
      final c = await signupClient();
      scriptRequest();
      t.on('/otp/verify', ScriptedTransport.ok(verified(existingUserId)));
      await c.requestOtp(phone);
      await expectLater(
        c.verifyOtp(code),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.existingAccount,
          ),
        ),
      );
      expect(identity.confirmedWith, isEmpty);
      expect(identity.reminted, 0);
      expect(await keys.contains(SessionItems.userId), isFalse);
      expect(t.count('/devices'), 0);
      expect(identity.adopted, [existingUserId]);
      expect(
        (await readStoredIdentity(keys))!.userId,
        existingUserId,
        reason: 'the account\'s id, adopted through the ledger (C-04b-4)',
      );
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
      expect(log.join('\n'), isNot(contains(existingUserId)));
    });
  });

  group('ADR 2026-10-05c — the sign-in door on the wire (server slice '
      'SIGNIN1B)', () {
    late FakeSignupIdentity identity;

    Future<HttpAuthClient> signupClient() async {
      final c = await client();
      identity = FakeSignupIdentity(keys);
      c.signupIdentity = identity;
      return c;
    }

    void scriptRequest() => t.on(
      '/otp/request',
      ScriptedTransport.ok({'ok': true, 'resend_after_s': 30}),
    );

    Matcher failsWith(AuthFailureKind kind) =>
        throwsA(isA<AuthFailure>().having((f) => f.kind, 'kind', kind));

    test('F1-1005c-2 the door picks the purpose: I\'m new sends signup, '
        'sign in sends device_activation, on both OTP calls; an explicit '
        'purpose still wins', () async {
      final c = await signupClient();
      scriptRequest();
      await c.requestOtp(phone, door: SignInDoor.newBooks);
      expect(t.last('/otp/request')['purpose'], 'signup');
      await c.requestOtp(phone, door: SignInDoor.signIn);
      expect(t.last('/otp/request')['purpose'], 'device_activation');
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({
          'account': 'existing',
          'ticket': 'tk-1',
          'user_id': existingUserId,
        }),
      );
      await c.checkOtp(code);
      expect(t.last('/otp/verify')['purpose'], 'device_activation');
      await c.requestOtp(
        phone,
        door: SignInDoor.signIn,
        purpose: OtpPurpose.phoneChange,
      );
      expect(t.last('/otp/request')['purpose'], 'phone_change');
      // Through the seam's own signature (what S0.2 calls).
      final AuthClient seam = c;
      await seam.requestOtp(phone, door: SignInDoor.signIn);
      expect(t.last('/otp/request')['purpose'], 'device_activation');
    });

    test('F1-1005c-2 account parsing: created + our id → this phone (confirmed '
        'and stored); existing + another id → has books (nothing stored); '
        'existing + our own id → this phone; created + another id is not '
        'believed; an unknown account value is refused', () async {
      Future<(HttpAuthClient, Object)> run(Map<String, Object?> body) async {
        t = ScriptedTransport();
        keys = FakeKeyStore();
        await seedLedgerIdentity(keys);
        final c = await signupClient();
        scriptRequest();
        t.on('/otp/verify', ScriptedTransport.ok(body));
        await c.requestOtp(phone, door: SignInDoor.signIn);
        try {
          return (c, await c.checkOtp(code));
        } on AuthFailure catch (e) {
          return (c, e);
        }
      }

      var (_, out) = await run({
        'account': 'created',
        'ticket': 'tk-1',
        'user_id': ledgerUserId,
      });
      expect(out, isA<OtpThisPhone>());
      expect((out as OtpThisPhone).ticket.value, 'tk-1');
      expect(identity.confirmedWith, [ledgerUserId]);
      expect(await keys.contains(SessionItems.userId), isTrue);

      (_, out) = await run({
        'account': 'existing',
        'ticket': 'tk-1',
        'user_id': existingUserId,
      });
      expect(out, isA<OtpHasBooks>());
      expect(identity.confirmedWith, isEmpty);
      expect(await keys.contains(SessionItems.userId), isFalse);
      expect(log.join('\n'), isNot(contains(existingUserId)));

      (_, out) = await run({
        'account': 'existing',
        'ticket': 'tk-1',
        'user_id': ledgerUserId,
      });
      expect(out, isA<OtpThisPhone>());

      (_, out) = await run({
        'account': 'created',
        'ticket': 'tk-1',
        'user_id': existingUserId,
      });
      expect(
        out,
        isA<AuthFailure>().having(
          (f) => f.kind,
          'kind',
          AuthFailureKind.unavailable,
        ),
      );
      expect(await keys.contains(SessionItems.userId), isFalse);

      (_, out) = await run({
        'account': 'mystery',
        'ticket': 'tk-1',
        'user_id': ledgerUserId,
      });
      expect(out, isA<AuthFailure>());
      expect(await keys.contains(SessionItems.userId), isFalse);

      // No `account` at all: the 04b user_id comparison still decides.
      (_, out) = await run({'ticket': 'tk-1', 'user_id': existingUserId});
      expect(out, isA<OtpHasBooks>());
    });

    test('F1-1005c-2 account none carries a signup ticket and nothing else: '
        'nothing is confirmed or stored, the code is spent, and verifyOtp '
        'refuses it as unavailable (no ticket to activate)', () async {
      final c = await signupClient();
      scriptRequest();
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({
          'account': 'none',
          'signup_ticket': 'st-1',
          'expires_in_s': 600,
        }),
      );
      await c.requestOtp(phone, door: SignInDoor.signIn);
      final out = await c.checkOtp(code);
      expect(out, isA<OtpNoBooks>());
      final signup = (out as OtpNoBooks).signupTicket;
      expect(signup.value, 'st-1');
      expect(signup.expiresIn, const Duration(minutes: 10));
      expect(identity.confirmedWith, isEmpty);
      expect(await keys.contains(SessionItems.userId), isFalse);
      expect(t.count('/devices'), 0);
      await expectLater(
        c.checkOtp(code),
        failsWith(AuthFailureKind.noPendingCode),
      );
      expect(log.join('\n'), isNot(contains('st-1')));

      // A `none` without a ticket is malformed, never a silent signup.
      t = ScriptedTransport();
      final c2 = await signupClient();
      scriptRequest();
      t.on('/otp/verify', ScriptedTransport.ok({'account': 'none'}));
      await c2.requestOtp(phone, door: SignInDoor.signIn);
      await expectLater(
        c2.verifyOtp(code),
        failsWith(AuthFailureKind.unavailable),
      );
    });

    test('F1-1005c-2 adoptSignup posts {signup_ticket, user_id} to '
        'auth-challenge/signup/adopt and, on an echo of our id with account '
        'created, confirms, stores and returns the activation ticket — no '
        'second OTP request', () async {
      final c = await signupClient();
      t.on(
        '/signup/adopt',
        ScriptedTransport.ok({
          'ticket': 'tk-9',
          'user_id': ledgerUserId,
          'account': 'created',
          'expires_in_s': 600,
        }),
      );
      final ticket = await c.adoptSignup(const SignupTicket('st-1'));
      expect(ticket.value, 'tk-9');
      final req = t.requests.single;
      expect(
        req.url.toString(),
        'https://api.test/functions/v1/auth-challenge/signup/adopt',
      );
      expect(req.body, {'signup_ticket': 'st-1', 'user_id': ledgerUserId});
      expect(identity.confirmedWith, [ledgerUserId]);
      expect(identity.storedAtConfirm, [false]);
      expect(
        utf8.decode((await keys.read(SessionItems.userId))!),
        ledgerUserId,
      );
      expect(t.count('/otp/request'), 0);
      expect(t.count('/otp/verify'), 0);
      final joined = log.join('\n');
      expect(joined, isNot(contains('st-1')));
      expect(joined, isNot(contains(ledgerUserId)));
    });

    test('F1-1005c-2 adoptSignup errors: 400 signup_ticket_invalid → '
        'signupTicketInvalid; 409 user_id_taken re-mints once and retries '
        'with the fresh id; another id in the echo, a second 409 and a 500 '
        'are unavailable; nothing stored on any failure; no identity → '
        'NoDeviceIdentity before any request', () async {
      var c = await signupClient();
      t.on(
        '/signup/adopt',
        ScriptedTransport.ok({'error': 'signup_ticket_invalid'}, 400),
      );
      await expectLater(
        c.adoptSignup(const SignupTicket('st-1')),
        failsWith(AuthFailureKind.signupTicketInvalid),
      );
      expect(await keys.contains(SessionItems.userId), isFalse);

      t = ScriptedTransport();
      c = await signupClient();
      t.on(
        '/signup/adopt',
        ScriptedTransport.ok({'error': 'user_id_taken'}, 409),
      );
      t.on(
        '/signup/adopt',
        ScriptedTransport.ok({
          'ticket': 'tk-9',
          'user_id': remintedUserId,
          'account': 'created',
        }),
      );
      expect((await c.adoptSignup(const SignupTicket('st-1'))).value, 'tk-9');
      final bodies = [
        for (final r in t.requests)
          if (r.url.path.endsWith('/signup/adopt')) r.body,
      ];
      expect(bodies.map((b) => b['user_id']), [ledgerUserId, remintedUserId]);
      expect(bodies.map((b) => b['signup_ticket']), ['st-1', 'st-1']);
      expect(identity.reminted, 1);
      expect(identity.confirmedWith, [remintedUserId]);

      for (final answers in [
        [
          ScriptedTransport.ok({
            'ticket': 'tk-9',
            'user_id': existingUserId,
            'account': 'created',
          }),
        ],
        [
          ScriptedTransport.ok({'error': 'user_id_taken'}, 409),
          ScriptedTransport.ok({'error': 'user_id_taken'}, 409),
        ],
        [const AuthHttpResponse(500, '')],
      ]) {
        t = ScriptedTransport();
        keys = FakeKeyStore();
        await seedLedgerIdentity(keys);
        c = await signupClient();
        for (final a in answers) {
          t.on('/signup/adopt', a);
        }
        await expectLater(
          c.adoptSignup(const SignupTicket('st-1')),
          failsWith(AuthFailureKind.unavailable),
        );
        expect(await keys.contains(SessionItems.userId), isFalse);
      }

      t = ScriptedTransport();
      keys = FakeKeyStore();
      c = await signupClient();
      await expectLater(
        c.adoptSignup(const SignupTicket('st-1')),
        throwsA(isA<NoDeviceIdentity>()),
      );
      expect(t.requests, isEmpty);
    });
  });

  group('C-1009-2 S0.2 mints through the ledger, never in the auth client '
      '(ADR 2026-10-09 §2)', () {
    /// The production ledger (guard on) over this suite's key store, opened
    /// the way the composition root opens it: ids only.
    Future<LocalLedger> realLedger() async {
      keys = FakeKeyStore();
      final l = LocalLedger(
        db: await openTestDb(),
        keys: keys,
        suite: await liveSuite(),
        now: testNow,
        requireConfirmedIdentity: true,
      );
      addTearDown(l.dispose);
      await l.openIdentity();
      return l;
    }

    Future<HttpAuthClient> over(LocalLedger l) async {
      final c = await client(certifier: l, bindMint: false);
      c.signupIdentity = l;
      c.keyMint = l;
      return c;
    }

    void scriptFor(LocalLedger l, {String? echo}) {
      final id = l.identity;
      t.on(
        '/otp/request',
        ScriptedTransport.ok({'ok': true, 'resend_after_s': 30}),
      );
      t.on(
        '/otp/verify',
        ScriptedTransport.ok({
          'ticket': 'tk-1',
          'user_id': echo ?? id.userId,
          'expires_in_s': 600,
        }),
      );
      t.on(
        '/devices',
        ScriptedTransport.ok({
          'device_id': id.deviceId,
          'user_id': id.userId,
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

    test('C-1009-2 with no ledger step bound and no seeds held, activation '
        'fails closed before POST devices and the client writes no seed — '
        'it never mints its own', () async {
      final c = await client(bindMint: false);
      scriptHappyPath();
      await c.requestOtp(phone);
      final ticket = await c.verifyOtp(code);
      keys.writes.clear();
      await expectLater(
        c.activateDevice(ticket),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.kind,
            'kind',
            AuthFailureKind.unavailable,
          ),
        ),
      );
      expect(t.count('/devices'), 0);
      expect(keys.writes, isNot(contains(KeyIds.deviceSigningKey)));
      expect(keys.writes, isNot(contains(KeyIds.deviceAgreementKey)));
      expect(log, contains('device_keys_absent'));
    });

    test('C-1009-2 a new account: the ledger mints the seeds and the UMK '
        'exactly when S0.2 activates — none before verify, all before POST '
        'devices — the registered public keys are the ledger device\'s, the '
        'device certifies under that UMK, and a retried POST reuses the '
        'same keys', () async {
      final l = await realLedger();
      final c = await over(l);
      scriptFor(l);
      await c.requestOtp(phone);
      final ticket = await c.verifyOtp(code);
      expect(l.identityConfirmed, isTrue);
      expect(l.keysRegistered, isFalse, reason: 'nothing minted at verify');
      expect(await keys.contains(KeyIds.wrappedUmk), isFalse);

      // The first POST dies on the wire; the retry must send the same keys.
      t.script['/devices']!.insert(0, const AuthHttpResponse(500, ''));
      t.beforeDevices = () => expect(l.keysRegistered, isTrue);
      await expectLater(c.activateDevice(ticket), throwsA(anything));
      final firstEd = t.last('/devices')['pub_ed'];
      final session = await c.activateDevice(ticket);

      expect(session.deviceId, l.identity.deviceId);
      final reg = t.last('/devices');
      expect(reg['pub_ed'], firstEd);
      expect(
        Bytes.fromBase64Url(reg['pub_ed'] as String),
        l.keyMaterial.device.public.ed25519,
      );
      expect(
        Bytes.fromBase64Url(reg['pub_x'] as String),
        l.keyMaterial.device.public.x25519,
      );
      expect(await keys.contains(KeyIds.wrappedUmk), isTrue);
      expect(l.keyMaterial.verifiedUmkOf(l.identity.userId), isNotNull);
      expect(t.count('/devices/certify'), 1);
      expect(log, isNot(contains('device_keys_generated')));
    });

    test(
      'C-04b-4 C-1009-2 a fresh install signing in to an existing account '
      'adopts the account\'s user id before any authoring; a second verify '
      'echoing that id is HAS BOOKS again — never confirmed, never '
      'registered, no key minted, no new-books onboarding — so the UMK can '
      'only come by link or recovery (06 §5; review finding KEY168B-1)',
      () async {
        final l = await realLedger();
        final provisional = l.identity;
        final c = await over(l);
        scriptFor(l, echo: existingUserId);
        await c.requestOtp(phone);
        expect(await c.checkOtp(code), isA<OtpHasBooks>());

        expect(l.identity.userId, existingUserId);
        expect(l.identity.deviceId, provisional.deviceId);
        expect(l.identityConfirmed, isFalse);
        expect(await l.mirror.bookIds(), isEmpty);
        expect(await keys.contains(SessionItems.userId), isFalse);
        expect(t.count('/devices'), 0);

        // The account's own sign-in, later: the echo now names this install.
        t.on(
          '/otp/verify',
          ScriptedTransport.ok({
            'ticket': 'tk-2',
            'user_id': existingUserId,
            'account': 'existing',
            'expires_in_s': 600,
          }),
        );
        t.script['/otp/verify']!.removeAt(0);
        expect(l.awaitingAccountUmk, isTrue);
        await c.requestOtp(phone);
        final out = await c.checkOtp(code);
        expect(out, isA<OtpHasBooks>());
        expect(
          t.last('/otp/verify')['user_id'],
          existingUserId,
          reason: 'the second verify really proposed the adopted id',
        );
        expect(l.identityConfirmed, isFalse);
        expect(l.identity.userId, existingUserId);
        expect(await keys.contains(SessionItems.userId), isFalse);
        expect(t.count('/devices'), 0);
        expect(await keys.contains(KeyIds.deviceSigningKey), isFalse);
        expect(await keys.contains(KeyIds.wrappedUmk), isFalse);
        expect(l.keysRegistered, isFalse);
        // Nothing can be authored: new-books onboarding is never reached, and
        // had it been, the ledger would refuse.
        await expectLater(
          l.createBook(name: 'Ghar', type: BookType.personal),
          throwsA(isA<IdentityNotConfirmed>()),
        );
        // And the door-blind form says the same.
        t.on(
          '/otp/verify',
          ScriptedTransport.ok({
            'ticket': 'tk-3',
            'user_id': existingUserId,
            'account': 'existing',
            'expires_in_s': 600,
          }),
        );
        t.script['/otp/verify']!.removeAt(0);
        await c.requestOtp(phone);
        await expectLater(
          c.verifyOtp(code),
          throwsA(
            isA<AuthFailure>().having(
              (e) => e.kind,
              'kind',
              AuthFailureKind.existingAccount,
            ),
          ),
        );
        expect(l.identityConfirmed, isFalse);
      },
    );
  });
}
