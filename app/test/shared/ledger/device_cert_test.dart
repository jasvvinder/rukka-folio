// 04 §3.4 🔒 — the device certificate, end to end: the ledger self-certifies
// under its own UMK, the auth client uploads it over `devices/certify`
// (06 §3 step 3), and what the chain does about it afterwards.
//
// The server here is not a stub that says yes: it verifies the signature the
// way `auth-challenge/index.ts certifyWith` does — over
// `uuid16(device_id) ‖ pub_ed ‖ pub_x ‖ i64be(issued_at_ms)`, under the UMK
// public key, with the public keys **it** recorded at registration. A byte
// order that drifts on either side fails here rather than in the field.
//
// In-memory SQLite, FakeKeyStore, injected clock, libsodium via the sodium
// build hook. No amounts that are not synthetic (rule 4).
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/auth_transport.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import '../test_app.dart';

/// The activation routes, with a `devices/certify` that checks the signature
/// exactly as the edge function does.
final class CertifyingAuthServer implements AuthTransport {
  CertifyingAuthServer(this.suite);

  final CryptoSuite suite;

  /// Last body seen per sub-route.
  final bodies = <String, Map<String, Object?>>{};

  /// How many times each sub-route was called.
  final calls = <String, int>{};

  /// Bearer tokens seen on `devices/certify`.
  final certifyAuth = <String?>[];

  /// What the server recorded at registration.
  String? deviceId;
  Uint8List? pubEd;
  Uint8List? pubX;

  /// The UMK public key on file (03 §2.2 `umk_pub_ed`), once offered.
  Uint8List? umkPubEd;

  /// `devices.status`.
  String status = 'registered';

  /// Set to refuse: the `error` string the 400 carries.
  String? refuseCertifyWith;

  @override
  Future<AuthHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final b = jsonDecode(body) as Map<String, Object?>;
    final path = url.path.split('/auth-challenge/').last;
    bodies[path] = b;
    calls[path] = (calls[path] ?? 0) + 1;
    switch (path) {
      case 'otp/request':
        return _ok({'ok': true, 'resend_after_s': 30});
      case 'otp/verify':
        return _ok({'ticket': 'tk-1', 'user_id': 'u-1', 'expires_in_s': 600});
      case 'devices':
        deviceId = b['device_id'] as String;
        pubEd = Bytes.fromBase64Url(b['pub_ed'] as String);
        pubX = Bytes.fromBase64Url(b['pub_x'] as String);
        return _ok({'device_id': deviceId, 'user_id': 'u-1', 'status': status});
      case 'challenge':
        return _ok({
          'nonce': Bytes.base64Url(Uint8List.fromList(List.filled(32, 7))),
          'expires_in_s': 60,
        });
      case 'token':
      case 'refresh':
        return _ok({
          'access_token': 'acc-1',
          'expires_in': 900,
          'refresh_token': 'ref-1',
          'refresh_expires_at': 1790000000000,
          'user_id': 'u-1',
          'device_id': deviceId,
          'device_status': status,
        });
      case 'devices/certify':
        certifyAuth.add(headers['Authorization']);
        return _certify(b);
      default:
        return const AuthHttpResponse(404, '');
    }
  }

  AuthHttpResponse _certify(Map<String, Object?> b) {
    if (refuseCertifyWith != null) {
      return AuthHttpResponse(400, jsonEncode({'error': refuseCertifyWith}));
    }
    final cert = b['cert'] as Map<String, Object?>?;
    final sig = cert?['signature'];
    final issuedAt = cert?['issued_at_ms'];
    if (sig is! String || issuedAt is! int) {
      return AuthHttpResponse(400, jsonEncode({'error': 'cert_malformed'}));
    }
    final offered = b['umk_pub_ed'];
    umkPubEd ??= offered is String ? Bytes.fromBase64Url(offered) : null;
    final umk = umkPubEd;
    if (umk == null) {
      return AuthHttpResponse(400, jsonEncode({'error': 'umk_unknown'}));
    }
    // index.ts: msg = uuid16(device) ‖ pub_ed ‖ pub_x ‖ i64be(issued_at_ms),
    // with the keys the server holds for the authenticated device.
    final msg = Bytes.concat([
      Uuid16.toBytes(deviceId!),
      pubEd!,
      pubX!,
      Bytes.i64be(issuedAt),
    ]);
    final ok = suite.sodium.crypto.sign.verifyDetached(
      message: msg,
      signature: Bytes.fromBase64Url(sig),
      publicKey: umk,
    );
    if (!ok) {
      return AuthHttpResponse(400, jsonEncode({'error': 'cert_invalid'}));
    }
    status = 'certified';
    return _ok({'device_id': deviceId, 'status': 'certified'});
  }

  static AuthHttpResponse _ok(Map<String, Object?> body) =>
      AuthHttpResponse(200, jsonEncode(body));
}

void main() {
  late FakeKeyStore keys;
  late CryptoSuite suite;
  late CertifyingAuthServer server;

  setUp(() async {
    keys = FakeKeyStore();
    suite = await testSuite();
    server = CertifyingAuthServer(suite);
  });

  HttpAuthClient authOver(LocalLedger ledger) => HttpAuthClient(
    transport: server,
    suite: suite,
    keys: keys,
    now: testNow,
    baseUrl: Uri.parse('https://api.test/functions/v1/'),
    clientVersion: '1.0.0',
    certifier: ledger,
  );

  Future<AuthSession> activate(HttpAuthClient c) async {
    await c.requestOtp('+919999999999');
    final ticket = await c.verifyOtp('123456');
    return c.activateDevice(ticket);
  }

  /// One envelope this ledger authored, rebuilt from its stored row — what a
  /// reader gets over the wire (03 §3.1; the guard does the same).
  Future<Envelope> anyOwnEnvelope(LocalLedger l) async {
    final row = (await l.db.select(l.db.envelopesLocal).get()).first;
    return Envelope.fromParts(
      suiteVersion: suiteVersion,
      tenantId: l.identity.tenantId,
      bookId: row.bookId,
      objectId: row.objectId,
      objectType: row.objectType,
      keyVersion: row.keyVersion,
      payloadSchema: payloadSchemaCurrent,
      authorDeviceId: row.authorDevice,
      hlc: row.hlc,
      envelopeId: row.envelopeId,
      blob: row.envelopeBlob,
    );
  }

  group('device certificate (04 §3.4 🔒 · 06 §3 step 3)', () {
    test('F1-05-51 the certificate uploaded at activation is '
        'Sign_UMK_ed(uuid16(device_id) ‖ pub_ed ‖ pub_x ‖ i64be(issued_at)) — '
        'that byte order and no other, under this install\'s UMK, over the '
        'public keys the server recorded', () async {
      final l = await openTestLedger(keys: keys);
      final id = await l.bootstrapSolo(firstBookName: 'Me');
      final c = authOver(l);
      await activate(c);

      final sent = server.bodies['devices/certify']!;
      final cert = sent['cert']! as Map<String, Object?>;
      final sig = Bytes.fromBase64Url(cert['signature']! as String);
      final issuedAt = cert['issued_at_ms']! as int;
      expect(sig, hasLength(DeviceCert.deviceCertSigBytes));
      expect(issuedAt, testNow().millisecondsSinceEpoch);

      // The 🔒 order, spelled out here rather than taken from the helper that
      // built it — the point of the test is that both sides agree on it.
      final umkPubEd = l.keyMaterial.umk.public.ed25519;
      bool verifies(Uint8List message) =>
          suite.sodium.crypto.sign.verifyDetached(
            message: message,
            signature: sig,
            publicKey: umkPubEd,
          );
      final device = l.keyMaterial.device.public;
      expect(
        verifies(
          Bytes.concat([
            Uuid16.toBytes(id.deviceId),
            device.ed25519,
            device.x25519,
            Bytes.i64be(issuedAt),
          ]),
        ),
        isTrue,
      );
      // The two 32-byte halves swapped: same length, same bytes, wrong order.
      expect(
        verifies(
          Bytes.concat([
            Uuid16.toBytes(id.deviceId),
            device.x25519,
            device.ed25519,
            Bytes.i64be(issuedAt),
          ]),
        ),
        isFalse,
      );
      // The issue time dropped from the tail.
      expect(
        verifies(
          Bytes.concat([
            Uuid16.toBytes(id.deviceId),
            device.ed25519,
            device.x25519,
          ]),
        ),
        isFalse,
      );

      // And the offer carried what the server needs to check it once.
      expect(sent['umk_pub_ed'], Bytes.base64Url(umkPubEd));
      expect(sent['umk_key_version'], umkKeyVersionFirst);
      expect(cert['issued_by_device'], id.deviceId, reason: 'self-issued');
      expect(server.certifyAuth.single, 'Bearer acc-1');
    });

    test('F1-05-52 the id certified is the ledger\'s (ADR 2026-09-16 §1): the '
        'certificate names the id that authors envelopes, the id registered '
        'and the id the session holds — one id, not four', () async {
      final l = await openTestLedger(keys: keys);
      final id = await l.bootstrapSolo(firstBookName: 'Me');
      final c = authOver(l);
      final session = await activate(c);

      final filed = l.ownDeviceCert!;
      expect(filed.deviceId, id.deviceId);
      expect(filed.device, l.keyMaterial.device.public);
      expect(filed.userId, id.userId);
      expect(session.deviceId, id.deviceId);
      expect(server.deviceId, id.deviceId);
      expect(
        utf8.decode((await keys.read(SessionItems.deviceId))!),
        id.deviceId,
      );
      final row = (await l.db.select(l.db.envelopesLocal).get()).first;
      expect(row.authorDevice, id.deviceId);
      expect((c.current as Active).deviceCertified, isTrue);
    });

    test('F1-05-53 the whole point: before certification ChainVerifier '
        'quarantines this device\'s own envelopes certMissing; after it, the '
        'same envelope verifies — signature ✓ under the certified device key, '
        'certificate ✓ under the ceremony-verified UMK', () async {
      final l = await openTestLedger(keys: keys);
      await l.bootstrapSolo(firstBookName: 'Me');
      final cash = await l.addAccount(
        (await l.mirror.bookIds()).single,
        name: 'Cash in hand',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.cash,
      );
      expect(cash.id, isNotEmpty);

      // The app's own trust store, built exactly as bootstrap.dart builds it.
      final material = l.keyMaterial;
      final trust = eng.RecordTrustStore(umks: material);
      l.onOwnCert = (cert) => trust.certs[cert.deviceId] = cert;
      final verifier = ChainVerifier(suite, trust);
      final envelope = await anyOwnEnvelope(l);

      expect(
        verifier.verifyEnvelope(envelope),
        isA<ChainQuarantine>().having(
          (q) => q.reason,
          'reason',
          QuarantineReason.certMissing,
        ),
      );

      await activate(authOver(l));

      expect(trust.certOf(l.identity.deviceId), isNotNull);
      expect(verifier.verifyEnvelope(envelope), isA<ChainVerified>());
      // Every envelope the book holds, not just the first.
      for (final row in await l.db.select(l.db.envelopesLocal).get()) {
        final env = Envelope.fromParts(
          suiteVersion: suiteVersion,
          tenantId: l.identity.tenantId,
          bookId: row.bookId,
          objectId: row.objectId,
          objectType: row.objectType,
          keyVersion: row.keyVersion,
          payloadSchema: payloadSchemaCurrent,
          authorDeviceId: row.authorDevice,
          hlc: row.hlc,
          envelopeId: row.envelopeId,
          blob: row.envelopeBlob,
        );
        expect(verifier.verifyEnvelope(env), isA<ChainVerified>());
      }
    });

    test('F1-05-54 the certificate is filed once and read back at open: a '
        'second launch over the same store trusts its own chain without '
        'certifying again', () async {
      final l = await openTestLedger(keys: keys);
      final id = await l.bootstrapSolo(firstBookName: 'Me');
      await activate(authOver(l));
      expect(server.calls['devices/certify'], 1);
      final issuedAt = l.ownDeviceCert!.issuedAtMs;
      l.dispose();

      // A second launch: a new facade over the same key store and the same
      // database. The certificate comes back from the store, not the server.
      final again = await openTestLedger(keys: keys, db: l.db);
      final certs = <DeviceCert>[];
      again.onOwnCert = certs.add;
      await again.bootstrapSolo();
      expect(again.identity.deviceId, id.deviceId);
      expect(again.ownDeviceCert, isNotNull);
      expect(again.ownDeviceCert!.issuedAtMs, issuedAt);
      expect(again.ownDeviceCert!.deviceId, id.deviceId);
      // Filed at open is not re-filed: the callback is for what arrives, and
      // bootstrap.dart seeds the store from [ownDeviceCert] directly.
      expect(certs, isEmpty);
      expect(server.calls['devices/certify'], 1);

      // And it is the certificate the chain needs.
      final trust = eng.RecordTrustStore(umks: again.keyMaterial);
      trust.certs[id.deviceId] = again.ownDeviceCert!;
      await again.moneyIn(
        bookId: (await again.mirror.bookIds()).single,
        into: (await again.addAccount(
          (await again.mirror.bookIds()).single,
          name: 'Cash in hand',
          accountClass: AccountClass.money,
          subtype: MoneySubtype.cash,
        )).id,
        from: (await again.addAccount(
          (await again.mirror.bookIds()).single,
          name: 'Shop sales',
          accountClass: AccountClass.categoryIncome,
        )).id,
        paise: 250_00,
        date: again.today(),
      );
      expect(
        ChainVerifier(suite, trust).verifyEnvelope(await anyOwnEnvelope(again)),
        isA<ChainVerified>(),
      );
    });

    test('F1-05-55 a refused certificate fails closed: activation still '
        'succeeds, nothing is filed, the session stays uncertified and the '
        'chain stays quarantined — for cert_invalid, cert_malformed and '
        'umk_unknown alike', () async {
      for (final error in const [
        'cert_invalid',
        'cert_malformed',
        'umk_unknown',
      ]) {
        keys = FakeKeyStore();
        server = CertifyingAuthServer(suite)..refuseCertifyWith = error;
        final l = await openTestLedger(keys: keys);
        await l.bootstrapSolo(firstBookName: 'Me');
        final c = authOver(l);
        final material = l.keyMaterial;
        final trust = eng.RecordTrustStore(umks: material);
        l.onOwnCert = (cert) => trust.certs[cert.deviceId] = cert;

        final session = await activate(c);
        expect(session.deviceId, l.identity.deviceId, reason: error);
        expect((c.current as Active).deviceCertified, isFalse, reason: error);
        expect(l.ownDeviceCert, isNull, reason: error);
        expect(
          await keys.contains(LocalLedgerKeys.deviceCert),
          isFalse,
          reason: error,
        );
        expect(trust.certOf(l.identity.deviceId), isNull, reason: error);
        expect(
          ChainVerifier(suite, trust).verifyEnvelope(await anyOwnEnvelope(l)),
          isA<ChainQuarantine>().having(
            (q) => q.reason,
            'reason',
            QuarantineReason.certMissing,
          ),
          reason: error,
        );
        // Explicitly retried, it surfaces the typed reason rather than a code.
        await expectLater(
          c.certifyDevice(),
          throwsA(isA<CertificationRefused>()),
          reason: error,
        );
        l.dispose();
      }
    });

    test('F1-05-56 the ledger files no certificate it cannot check: one for '
        'another device, or signed by another install\'s UMK, is refused and '
        'the device stays uncertified (04 §8.2 🔒)', () async {
      final mine = await openTestLedger(keys: keys);
      final id = await mine.bootstrapSolo(firstBookName: 'Me');
      final other = await openTestLedger();
      final otherId = await other.bootstrapSolo(firstBookName: 'Theirs');

      // Another device's certificate, correctly signed by its own UMK.
      await expectLater(
        mine.installOwnCert(other.issueOwnCert().cert),
        throwsArgumentError,
      );
      // This device's id and keys, signed by somebody else's UMK.
      final forged = DeviceCert.issue(
        suite,
        issuer: other.keyMaterial.umk,
        userId: id.userId,
        device: mine.keyMaterial.device.public,
        issuedAtMs: testNow().millisecondsSinceEpoch,
      );
      expect(forged.deviceId, id.deviceId);
      expect(forged.deviceId, isNot(otherId.deviceId));
      await expectLater(mine.installOwnCert(forged), throwsArgumentError);

      expect(mine.ownDeviceCert, isNull);
      expect(await keys.contains(LocalLedgerKeys.deviceCert), isFalse);
    });
  });
}
