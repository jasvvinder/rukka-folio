@Tags(['C'])
library;

// C-06-35, C-06-36: the `device_added` record is the certificate itself
// (06 §5 🔒 final paragraph; ADR 2026-09-05d §6), authored on the device that
// was just certified and carried by the one record route (05 §5, ADR
// 2026-09-05b §1).
//
// Real libsodium, a fake key store, an injected clock, no network. Nothing
// here is financial data (rule 4): a certificate is a signature over public
// keys.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/server_members_repository.dart';
import 'package:rukka_folio/shared/ledger/device_certification.dart'
    show umkKeyVersionFirst;
import 'package:rukka_folio/shared/records/device_added_record.dart';
import 'package:rukka_folio/shared/records/device_record_author.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../test_app.dart';

const deviceId = '11111111-2222-4333-8444-555555555555';
const tenantId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const userId = '99999999-8888-4777-8666-555555555555';
const issuedAtMs = 1789000000000;

/// The same seed replay [DeviceRecordAuthor] uses, so the test can hold the
/// public half of the key the author signs with.
DeviceKeyPair deviceFrom(CryptoSuite suite, Uint8List ed, Uint8List x) {
  final queue = <Uint8List>[Uint8List.fromList(ed), Uint8List.fromList(x)];
  return DeviceKeyPair.generate(
    CryptoSuite(suite.sodium, random: (_) => queue.removeAt(0)),
    deviceId: deviceId,
  );
}

Uint8List b64any(String s) => base64.decode(
  base64.normalize(s.replaceAll('-', '+').replaceAll('_', '/')),
);

/// Everything one test needs: the key store the author reads, the device the
/// author signs as, and a certificate over it.
final class Fixture {
  Fixture._(this.suite, this.keys, this.device, this.umk, this.cert);

  static Future<Fixture> create() async {
    final suite = await testSuite();
    final keys = FakeKeyStore();
    final ed = suite.randomBytes(32);
    final x = suite.randomBytes(32);
    await keys.write(KeyIds.deviceSigningKey, ed);
    await keys.write(KeyIds.deviceAgreementKey, x);
    final device = deviceFrom(suite, ed, x);
    final umk = UmkKeyPair.generate(suite);
    final cert = DeviceCert.issue(
      suite,
      issuer: umk,
      userId: userId,
      device: device.public,
      issuedAtMs: issuedAtMs,
    );
    return Fixture._(suite, keys, device, umk, cert);
  }

  final CryptoSuite suite;
  final FakeKeyStore keys;
  final DeviceKeyPair device;
  final UmkKeyPair umk;
  final DeviceCert cert;

  DeviceRecordAuthor author() => DeviceRecordAuthor(
    suite: suite,
    keys: keys,
    deviceIdOf: () async => deviceId,
    clock: RecordHlcClock(() => DateTime.utc(2026, 9, 17, 6, 30)),
  );
}

/// Captures what was posted; optionally fails the way the route can.
final class CapturingPost {
  CapturingPost({this.throws = false, this.note = 'no projection'});

  final posted = <List<Map<String, Object?>>>[];
  final bool throws;
  final String note;

  Future<List<String>> call(List<Map<String, Object?>> records) async {
    if (throws) throw const MembersFailure('offline', MembersRefusal.offline);
    posted.add(records);
    return List.filled(records.length, note);
  }
}

void main() {
  test(
    'C-06-35 the device_added record is the certificate itself: the wire row '
    'passes every shape check records.ts makes, the payload carries the '
    'signature, issue time, issuer and UMK version of the certificate that '
    'was filed, and the signature verifies under this device key',
    () async {
      final f = await Fixture.create();
      final post = CapturingPost();
      final recorder = DeviceAddedRecorder(
        author: f.author(),
        tenantId: tenantId,
        post: post.call,
      );

      await recorder.deviceAdded(f.cert, umkKeyVersion: umkKeyVersionFirst);

      // Exactly one record, in one batch.
      expect(post.posted, hasLength(1));
      expect(post.posted.single, hasLength(1));
      final row = post.posted.single.single;

      // ⚠️ WIRE `_shared/records.ts` parseRecord: uuids, a known kind, an
      // integer suite version, a bigint hlc, base64 payload and a 64-byte
      // base64 signature. `seq` is the server's and is never sent.
      expect(Uuid16.isCanonical(row['id']! as String), isTrue);
      expect(row['tenant_id'], tenantId);
      expect(row['author_device_id'], deviceId);
      expect(row['kind'], SignedRecordKind.deviceAdded);
      expect(row['suite_version'], isA<int>());
      expect(row['hlc'], isA<int>());
      expect(row.containsKey('seq'), isFalse);
      final sig = b64any(row['author_sig']! as String);
      expect(sig, hasLength(SignedRecord.signedRecordSigBytes));

      // The payload IS the certificate (ADR 2026-09-05d §6) — the same five
      // fields `devices/certify` sends, and nothing else.
      final payloadBytes = b64any(row['payload_json']! as String);
      final payload =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, Object?>;
      expect(payload, {
        'device_id': deviceId,
        'signature': Bytes.base64Url(f.cert.signature),
        'issued_at_ms': issuedAtMs,
        'issued_by_device': deviceId,
        'umk_key_version': umkKeyVersionFirst,
      });

      // A reader with the payload rebuilds the certificate and it verifies
      // under the issuing UMK (04 §3.4) — the record needs no second source.
      final rebuilt = DeviceCert(
        suiteVersion: f.cert.suiteVersion,
        userId: userId,
        device: f.device.public,
        issuedAtMs: payload['issued_at_ms']! as int,
        signature: Bytes.fromBase64Url(payload['signature']! as String),
      );
      expect(rebuilt.verify(f.suite, f.umk.public), isTrue);

      // And the record itself is signed by the device it announces.
      final record = SignedRecord(
        suiteVersion: row['suite_version']! as int,
        tenantId: row['tenant_id']! as String,
        kind: row['kind']! as String,
        payloadJson: payloadBytes,
        authorDeviceId: row['author_device_id']! as String,
        authorSig: sig,
        hlc: row['hlc']! as int,
      );
      expect(record.verifySignature(f.suite, f.device.public), isTrue);

      // A linked device's certificate names its issuer (04 §9.1, M8).
      final post2 = CapturingPost();
      await DeviceAddedRecorder(
        author: f.author(),
        tenantId: tenantId,
        post: post2.call,
      ).deviceAdded(
        f.cert,
        umkKeyVersion: 7,
        issuedByDevice: 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff',
      );
      final p2 = jsonDecode(
        utf8.decode(
          b64any(post2.posted.single.single['payload_json']! as String),
        ),
      ) as Map<String, Object?>;
      expect(p2['issued_by_device'], 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff');
      expect(p2['umk_key_version'], 7);
    },
  );

  test('C-06-36 an announcement that does not land changes nothing: a device '
      'that cannot sign, a post that never reaches the server and a record the '
      'server refuses each return normally and log one fixed event name — no '
      'exception, no retry, nothing about the device in the log', () async {
    final f = await Fixture.create();

    // (1) The post never reached the server.
    final log = <String>[];
    final offline = CapturingPost(throws: true);
    await DeviceAddedRecorder(
      author: f.author(),
      tenantId: tenantId,
      post: offline.call,
      log: log.add,
    ).deviceAdded(f.cert, umkKeyVersion: umkKeyVersionFirst);
    expect(log, [DeviceAddedRecorder.unfiledEvent]);
    expect(offline.posted, isEmpty);

    // (2) The server stored it and then refused it: `records.ts` rolls the
    // row back and answers a note, not an error.
    log.clear();
    final refused = CapturingPost(note: 'rejected:shape');
    await DeviceAddedRecorder(
      author: f.author(),
      tenantId: tenantId,
      post: refused.call,
      log: log.add,
    ).deviceAdded(f.cert, umkKeyVersion: umkKeyVersionFirst);
    expect(log, [DeviceAddedRecorder.unfiledEvent]);

    // (3) This device holds no signing key: the author throws
    // `unauthorized` and the recorder still returns.
    log.clear();
    final unsignable = CapturingPost();
    final mute = DeviceRecordAuthor(
      suite: f.suite,
      keys: FakeKeyStore(),
      deviceIdOf: () async => deviceId,
      clock: RecordHlcClock(() => DateTime.utc(2026, 9, 17, 6, 30)),
    );
    await DeviceAddedRecorder(
      author: mute,
      tenantId: tenantId,
      post: unsignable.call,
      log: log.add,
    ).deviceAdded(f.cert, umkKeyVersion: umkKeyVersionFirst);
    expect(log, [DeviceAddedRecorder.unfiledEvent]);
    expect(unsignable.posted, isEmpty);

    // Rule 4: the event name is all that is ever written.
    expect(log.any((e) => e.contains(deviceId)), isFalse);
    expect(log.any((e) => e.contains(tenantId)), isFalse);
  });
}
