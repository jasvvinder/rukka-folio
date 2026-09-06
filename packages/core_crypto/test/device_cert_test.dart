@Tags(['B'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const int issuedAt = 1757100000000;

void main() {
  test('B-04-34 self-certification (04 §3.4): the first device\'s cert verifies under its own UMK and under no other', () async {
    final s = await testSuite(seed: 34);
    final umk = UmkKeyPair.generate(s);
    final other = UmkKeyPair.generate(s);
    final dev = DeviceKeyPair.generate(s, deviceId: deviceA);
    addTearDown(umk.dispose);
    addTearDown(other.dispose);
    addTearDown(dev.dispose);

    final cert = DeviceCert.issue(
      s,
      issuer: umk,
      userId: userA,
      device: dev.public,
      issuedAtMs: issuedAt,
    );
    expect(cert.suiteVersion, suiteVersion);
    expect(cert.userId, userA);
    expect(cert.deviceId, deviceA);
    expect(cert.signature.length, 64);
    expect(cert.verify(s, umk.public), isTrue);
    expect(cert.verify(s, other.public), isFalse);

    // A flipped signature byte fails.
    final flipped = Uint8List.fromList(cert.signature)..[3] ^= 0x01;
    final bad = DeviceCert(
      suiteVersion: cert.suiteVersion,
      userId: cert.userId,
      device: cert.device,
      issuedAtMs: cert.issuedAtMs,
      signature: flipped,
    );
    expect(bad.verify(s, umk.public), isFalse);
  });

  test('B-04-35 signed bytes are device_id ‖ pub_ed ‖ pub_x ‖ issued_at (04 §3.4 🔒 order); changing any of them breaks the cert', () async {
    final s = await testSuite(seed: 35);
    final umk = UmkKeyPair.generate(s);
    final dev = DeviceKeyPair.generate(s, deviceId: deviceA);
    final imposter = DeviceKeyPair.generate(s, deviceId: deviceB);
    addTearDown(umk.dispose);
    addTearDown(dev.dispose);
    addTearDown(imposter.dispose);

    final bytes = DeviceCert.signedBytes(
      device: dev.public,
      issuedAtMs: issuedAt,
    );
    expect(bytes.length, 16 + 32 + 32 + 8);
    expect(bytes.sublist(0, 16), Uuid16.toBytes(deviceA));
    expect(bytes.sublist(16, 48), dev.public.ed25519);
    expect(bytes.sublist(48, 80), dev.public.x25519);
    expect(bytes.sublist(80), Bytes.i64be(issuedAt));

    final cert = DeviceCert.issue(
      s,
      issuer: umk,
      userId: userA,
      device: dev.public,
      issuedAtMs: issuedAt,
    );
    // Same signature, different issued_at → invalid.
    expect(
      DeviceCert(
        suiteVersion: cert.suiteVersion,
        userId: userA,
        device: dev.public,
        issuedAtMs: issuedAt + 1,
        signature: cert.signature,
      ).verify(s, umk.public),
      isFalse,
    );
    // Same signature, another device's keys → invalid.
    expect(
      DeviceCert(
        suiteVersion: cert.suiteVersion,
        userId: userA,
        device: imposter.public,
        issuedAtMs: issuedAt,
        signature: cert.signature,
      ).verify(s, umk.public),
      isFalse,
    );
    // Same signature, the same keys under a different device id → invalid.
    expect(
      DeviceCert(
        suiteVersion: cert.suiteVersion,
        userId: userA,
        device: DevicePublic(
          deviceId: deviceB,
          ed25519: dev.public.ed25519,
          x25519: dev.public.x25519,
        ),
        issuedAtMs: issuedAt,
        signature: cert.signature,
      ).verify(s, umk.public),
      isFalse,
    );
  });

  test('B-04-36 linking (04 §9.1) and recovery (04 §7.3 step 6) issue the same cert: a second device certified by the user\'s UMK verifies; a seeded suite reproduces it byte-for-byte', () async {
    final s1 = await testSuite(seed: 36);
    final s2 = await testSuite(seed: 36);
    final umk1 = UmkKeyPair.generate(s1);
    final umk2 = UmkKeyPair.generate(s2);
    final devB1 = DeviceKeyPair.generate(s1, deviceId: deviceB);
    final devB2 = DeviceKeyPair.generate(s2, deviceId: deviceB);
    addTearDown(umk1.dispose);
    addTearDown(umk2.dispose);
    addTearDown(devB1.dispose);
    addTearDown(devB2.dispose);

    final c1 = DeviceCert.issue(
      s1,
      issuer: umk1,
      userId: userA,
      device: devB1.public,
      issuedAtMs: issuedAt,
    );
    final c2 = DeviceCert.issue(
      s2,
      issuer: umk2,
      userId: userA,
      device: devB2.public,
      issuedAtMs: issuedAt,
    );
    expect(c1.verify(s1, umk1.public), isTrue);
    expect(c1.signature, c2.signature);
    expect(c1.device, c2.device);

    // The recovered-UMK path: rebuild the UMK from its secret bytes and issue.
    final secret = umk1.exportSecretBytes();
    final recovered = UmkKeyPair.fromSecretBytes(s1, secret);
    s1.zeroize(secret);
    addTearDown(recovered.dispose);
    final c3 = DeviceCert.issue(
      s1,
      issuer: recovered,
      userId: userA,
      device: devB1.public,
      issuedAtMs: issuedAt,
    );
    expect(c3.signature, c1.signature);
    expect(
      () => DeviceCert(
        suiteVersion: 1,
        userId: 'nope',
        device: devB1.public,
        issuedAtMs: 0,
        signature: Uint8List(64),
      ),
      throwsFormatException,
    );
  });
}
