@Tags(['B'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const int hlc0 = 1757100000000 << 16;

Uint8List json(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('B-05b-1 SignedRecord = {suite, tenant, kind, payload, author_device, sig = Ed25519(BLAKE2b(payload ‖ header)), hlc, seq} (ADR 05b §1) signs and verifies under the author device', () async {
    final s = await testSuite(seed: 51);
    final dev = DeviceKeyPair.generate(s, deviceId: deviceA);
    final other = DeviceKeyPair.generate(s, deviceId: deviceB);
    addTearDown(dev.dispose);
    addTearDown(other.dispose);
    final payload = json(
      '{"user_id":"$userB","role":"member","auto_post_limit_paise":500000}',
    );
    final r = SignedRecord.sign(
      s,
      tenantId: tenantA,
      kind: SignedRecordKind.bookRole,
      payloadJson: payload,
      hlc: hlc0,
      author: dev,
    );
    expect(r.suiteVersion, suiteVersion);
    expect(r.seq, isNull);
    expect(r.authorDeviceId, deviceA);
    expect(r.verifySignature(s, dev.public), isTrue);
    expect(r.verifySignature(s, other.public), isFalse);
    // The digest is BLAKE2b-256(payload ‖ header).
    expect(r.signedDigest(s), s.blake2b256(Bytes.concat([payload, r.header])));
    expect(
      s.sodium.crypto.sign.verifyDetached(
        message: r.signedDigest(s),
        signature: r.authorSig,
        publicKey: dev.public.ed25519,
      ),
      isTrue,
    );
    expect(SignedRecordKind.all, contains(SignedRecordKind.deviceRevocation));
    expect(SignedRecordKind.all.length, 8);
  });

  test('B-05b-2 header binding: kind, tenant, hlc and author device are signed — changing any one invalidates the record; payload tamper too', () async {
    final s = await testSuite(seed: 52);
    final dev = DeviceKeyPair.generate(s, deviceId: deviceA);
    addTearDown(dev.dispose);
    final payload = json('{"device_id":"$deviceB"}');
    final r = SignedRecord.sign(
      s,
      tenantId: tenantA,
      kind: SignedRecordKind.deviceRevocation,
      payloadJson: payload,
      hlc: hlc0,
      author: dev,
    );
    SignedRecord mutate({
      String? tenantId,
      String? kind,
      Uint8List? payloadJson,
      String? authorDeviceId,
      int? hlc,
    }) => SignedRecord(
      suiteVersion: r.suiteVersion,
      tenantId: tenantId ?? r.tenantId,
      kind: kind ?? r.kind,
      payloadJson: payloadJson ?? r.payloadJson,
      authorDeviceId: authorDeviceId ?? r.authorDeviceId,
      authorSig: r.authorSig,
      hlc: hlc ?? r.hlc,
    );
    expect(mutate().verifySignature(s, dev.public), isTrue);
    expect(
      mutate(kind: SignedRecordKind.deviceAdded).verifySignature(s, dev.public),
      isFalse,
    );
    expect(mutate(tenantId: bookA).verifySignature(s, dev.public), isFalse);
    expect(mutate(hlc: hlc0 + 1).verifySignature(s, dev.public), isFalse);
    // Re-pointing the author is caught twice: the device id check and the key.
    final otherDev = DeviceKeyPair.generate(s, deviceId: deviceB);
    addTearDown(otherDev.dispose);
    expect(
      mutate(authorDeviceId: deviceB).verifySignature(s, otherDev.public),
      isFalse,
    );
    expect(
      mutate(authorDeviceId: deviceB).verifySignature(s, dev.public),
      isFalse,
    );
    // Payload tamper (same length, one byte).
    final t = Uint8List.fromList(payload)..[payload.length - 3] ^= 0x01;
    expect(mutate(payloadJson: t).verifySignature(s, dev.public), isFalse);
    // Header bytes in the ⚠️ SPEC order.
    expect(
      r.header,
      Bytes.concat([
        Bytes.u8(suiteVersion),
        Uuid16.toBytes(tenantA),
        Bytes.lengthPrefixedUtf8(SignedRecordKind.deviceRevocation),
        Uuid16.toBytes(deviceA),
        Bytes.i64be(hlc0),
      ]),
    );
  });

  test('B-05b-3 seq is server-stamped (ADR 05b §5) and excluded from the signature: withSeq() still verifies and carries the seq', () async {
    final s = await testSuite(seed: 53);
    final dev = DeviceKeyPair.generate(s, deviceId: deviceA);
    addTearDown(dev.dispose);
    final r = SignedRecord.sign(
      s,
      tenantId: tenantA,
      kind: SignedRecordKind.membershipStatus,
      payloadJson: json('{"user_id":"$userB","status":"active"}'),
      hlc: hlc0,
      author: dev,
    );
    final stored = r.withSeq(4711);
    expect(stored.seq, 4711);
    expect(stored.authorSig, r.authorSig);
    expect(stored.verifySignature(s, dev.public), isTrue);
    expect(() => r.withSeq(0), throwsArgumentError);
  });

  test('B-05b-4 payload bytes are kept exactly as signed (rule 6): unknown fields, key order and whitespace survive; payload decodes with them present', () async {
    final s = await testSuite(seed: 54);
    final dev = DeviceKeyPair.generate(s, deviceId: deviceA);
    addTearDown(dev.dispose);
    const text =
        '{ "user_id": "$userB",  "status": "active", "future_field": {"x": [1, 2]} , "zeta": 1 }';
    final r = SignedRecord.sign(
      s,
      tenantId: tenantA,
      kind: SignedRecordKind.membershipStatus,
      payloadJson: json(text),
      hlc: hlc0,
      author: dev,
    );
    expect(utf8.decode(r.payloadJson), text);
    expect(r.payload['future_field'], {
      'x': [1, 2],
    });
    expect(r.payload.keys.toList(), [
      'user_id',
      'status',
      'future_field',
      'zeta',
    ]);
    // A re-serialised payload would be different bytes and must NOT verify —
    // which is exactly why the bytes are kept.
    final reserialised = json(jsonEncode(r.payload));
    expect(reserialised, isNot(r.payloadJson));
    expect(
      SignedRecord(
        suiteVersion: r.suiteVersion,
        tenantId: r.tenantId,
        kind: r.kind,
        payloadJson: reserialised,
        authorDeviceId: r.authorDeviceId,
        authorSig: r.authorSig,
        hlc: r.hlc,
      ).verifySignature(s, dev.public),
      isFalse,
    );
  });

  test('B-05b-5 a payload that is not a JSON object is refused at signing and at decoding; malformed ids are refused', () async {
    final s = await testSuite(seed: 55);
    final dev = DeviceKeyPair.generate(s, deviceId: deviceA);
    addTearDown(dev.dispose);
    for (final bad in ['[1,2]', '"str"', '42', 'not json']) {
      expect(
        () => SignedRecord.sign(
          s,
          tenantId: tenantA,
          kind: SignedRecordKind.designation,
          payloadJson: json(bad),
          hlc: hlc0,
          author: dev,
        ),
        throwsFormatException,
        reason: bad,
      );
    }
    expect(
      () => SignedRecord(
        suiteVersion: 1,
        tenantId: 'tenant',
        kind: 'x',
        payloadJson: json('{}'),
        authorDeviceId: deviceA,
        authorSig: Uint8List(64),
        hlc: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => SignedRecord(
        suiteVersion: 1,
        tenantId: tenantA,
        kind: '',
        payloadJson: json('{}'),
        authorDeviceId: deviceA,
        authorSig: Uint8List(64),
        hlc: 1,
      ),
      throwsArgumentError,
    );
  });
}
