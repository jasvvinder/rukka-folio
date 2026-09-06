@Tags(['B'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('B-04-4 verification code = decimal(first4(BLAKE2b-256(FP ‖ nonce ‖ "verify-v1"))) mod 10⁸, 8 digits zero-padded, deterministic', () async {
    // 04 §6.1: "8-digit code: decimal( first4bytes( BLAKE2b-256( FP ‖ nonce ‖
    // "verify-v1" ) ) ) mod 10⁸, zero-padded."
    final s = await testSuite(seed: 11);
    final u = UmkKeyPair.generate(s);
    addTearDown(u.dispose);
    final fp = Fingerprint.of(s, u.public);
    final nonce = s.randomBytes(16);

    final code = verificationCode(s, fp, nonce);
    expect(code, matches(RegExp(r'^\d{8}$')));
    expect(verificationCode(s, fp, nonce), code, reason: 'deterministic');

    final h = s.blake2b256(
      Bytes.concat([
        fp.bytes,
        nonce,
        Uint8List.fromList('verify-v1'.codeUnits),
      ]),
    );
    final first4 = ByteData.sublistView(h, 0, 4).getUint32(0);
    expect(code, (first4 % 100000000).toString().padLeft(8, '0'));

    // Find a nonce whose code needs zero-padding (leading zero) and check
    // the padding actually happens — the search is deterministic under the
    // seeded suite.
    String padded;
    do {
      padded = verificationCode(s, fp, s.randomBytes(16));
    } while (!padded.startsWith('0'));
    expect(padded.length, 8);

    expect(
      () => verificationCode(s, fp, Uint8List(15)),
      throwsArgumentError,
      reason: 'nonce is 128-bit',
    );
  });

  test('B-04-5 QR payload = base64url(suite ‖ user_id ‖ UMK_pub_ed ‖ UMK_pub_x ‖ nonce) in that order; round-trips; wrong length / unknown suite refused', () async {
    // 04 §6.1: "QR payload: base64url( suite_version ‖ user_id ‖ UMK_pub_ed ‖
    // UMK_pub_x ‖ nonce )".
    final s = await testSuite(seed: 12);
    final u = UmkKeyPair.generate(s);
    addTearDown(u.dispose);
    final nonce = s.randomBytes(16);
    final qr = QrPayload(userId: userA, umk: u.public, nonce: nonce);

    final bytes = qr.toBytes();
    expect(bytes.length, 97);
    expect(bytes[0], suiteVersion);
    expect(bytes.sublist(1, 17), Uuid16.toBytes(userA));
    expect(bytes.sublist(17, 49), u.public.ed25519, reason: 'ed before x');
    expect(bytes.sublist(49, 81), u.public.x25519);
    expect(bytes.sublist(81, 97), nonce);
    expect(qr.encode(), Bytes.base64Url(bytes));
    expect(qr.encode(), isNot(contains('=')));

    final back = QrPayload.decode(qr.encode());
    expect(back.suiteVersion, suiteVersion);
    expect(back.userId, userA);
    expect(back.umk, u.public);
    expect(back.nonce, nonce);

    expect(
      () => QrPayload.decode(Bytes.base64Url(bytes.sublist(0, 96))),
      throwsFormatException,
      reason: 'short payload',
    );
    final wrongSuite = Uint8List.fromList(bytes)..[0] = 0x02;
    expect(
      () => QrPayload.decode(Bytes.base64Url(wrongSuite)),
      throwsFormatException,
      reason: 'unknown suite_version',
    );
    expect(() => QrPayload.decode('!!not base64!!'), throwsFormatException);
  });

  test('B-04-6 QR path: byte-for-byte equal keys + same user → verified (qr_in_person); one flipped key byte or another user id → CeremonyMismatch, no override', () async {
    // 04 §6.3: "compares scanned public keys byte-for-byte against the
    // server-relayed keys for that user. Equal → verified. Unequal → hard-fail
    // ... There is no override." 04 §10: "Given a server that swaps the
    // invitee's public key, when the inviter scans the true QR, then hard-fail
    // mismatch".
    final s = await testSuite(seed: 13);
    final invitee = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    final scanned = QrPayload(
      userId: userA,
      umk: invitee.public,
      nonce: s.randomBytes(16),
    );

    final ok = Ceremony.verifyQr(
      s,
      scanned: scanned,
      relayed: invitee.public,
      relayedUserId: userA,
    );
    expect(ok, isA<CeremonyVerified>());
    final v = (ok as CeremonyVerified).verified;
    expect(v.public, invitee.public);
    expect(v.fingerprint, Fingerprint.of(s, invitee.public));
    expect(v.method, VerificationMethod.qrInPerson);

    // Server swaps one byte of the relayed x25519 key.
    final swappedX = Uint8List.fromList(invitee.public.x25519);
    swappedX[7] ^= 0x01;
    final swapped = UmkPublic(
      x25519: swappedX,
      ed25519: invitee.public.ed25519,
    );
    expect(
      Ceremony.verifyQr(
        s,
        scanned: scanned,
        relayed: swapped,
        relayedUserId: userA,
      ),
      isA<CeremonyMismatch>(),
    );

    // Same for the ed25519 half.
    final swappedEd = Uint8List.fromList(invitee.public.ed25519);
    swappedEd[31] ^= 0x80;
    expect(
      Ceremony.verifyQr(
        s,
        scanned: scanned,
        relayed: UmkPublic(x25519: invitee.public.x25519, ed25519: swappedEd),
        relayedUserId: userA,
      ),
      isA<CeremonyMismatch>(),
    );

    // Right keys but the server says they belong to someone else.
    expect(
      Ceremony.verifyQr(
        s,
        scanned: scanned,
        relayed: invitee.public,
        relayedUserId: userB,
      ),
      isA<CeremonyMismatch>(),
    );
  });

  test('B-04-7 code path: the correct 8 digits verify (code_remote); a wrong try costs one attempt and the right code still verifies afterwards', () async {
    // 04 §6.3: "verifier's device computes the expected code from the
    // server-relayed keys + nonce and compares to the typed digits. 3 attempts
    // per nonce". 04 §6.4: method `code_remote`.
    final s = await testSuite(seed: 14);
    final invitee = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    final nonce = s.randomBytes(16);
    final code = verificationCode(s, Fingerprint.of(s, invitee.public), nonce);
    const issued = 1_800_000_000_000;

    final c0 = CodeChallenge(
      relayed: invitee.public,
      nonce: nonce,
      issuedAtMs: issued,
    );
    expect(c0.attemptsLeft, 3);

    // Whitespace the invitee read aloud in pairs is tolerated.
    final spaced = '${code.substring(0, 4)} ${code.substring(4)}';
    final r1 = c0.attempt(s, typed: spaced, nowMs: issued + 1000);
    expect(r1.result, isA<CeremonyVerified>());
    final v = (r1.result as CeremonyVerified).verified;
    expect(v.method, VerificationMethod.codeRemote);
    expect(v.public, invitee.public);
    expect(r1.next.dead, isTrue, reason: 'one verification per nonce');

    // Wrong once, then right.
    final wrong = code[0] == '9'
        ? '0${code.substring(1)}'
        : '9${code.substring(1)}';
    final r2 = c0.attempt(s, typed: wrong, nowMs: issued + 1000);
    expect(r2.result, isA<CodeWrong>());
    expect((r2.result as CodeWrong).attemptsLeft, 2);
    expect(r2.next.attemptsLeft, 2);
    expect(
      c0.attemptsLeft,
      3,
      reason: 'immutable — the old state is unchanged',
    );
    final r3 = r2.next.attempt(s, typed: code, nowMs: issued + 2000);
    expect(r3.result, isA<CeremonyVerified>());

    // Garbage counts as a wrong attempt, never as a match.
    final r4 = c0.attempt(s, typed: 'abcdefgh', nowMs: issued);
    expect(r4.result, isA<CodeWrong>());
  });

  test('B-04-9 wrong 8-digit code entered 3× → nonce dead (CodeExhausted); the correct code no longer verifies on that nonce', () async {
    // 04 §10: "Given a wrong 8-digit code entered 3×, then the nonce is dead
    // and a new Regenerate is required." 04 §6.3: "3 attempts per nonce".
    final s = await testSuite(seed: 15);
    final invitee = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    final nonce = s.randomBytes(16);
    final code = verificationCode(s, Fingerprint.of(s, invitee.public), nonce);
    const issued = 1_800_000_000_000;
    final wrong = code[0] == '9'
        ? '0${code.substring(1)}'
        : '9${code.substring(1)}';

    var c = CodeChallenge(
      relayed: invitee.public,
      nonce: nonce,
      issuedAtMs: issued,
    );
    final r1 = c.attempt(s, typed: wrong, nowMs: issued);
    expect((r1.result as CodeWrong).attemptsLeft, 2);
    c = r1.next;
    final r2 = c.attempt(s, typed: wrong, nowMs: issued);
    expect((r2.result as CodeWrong).attemptsLeft, 1);
    c = r2.next;
    final r3 = c.attempt(s, typed: wrong, nowMs: issued);
    expect(r3.result, isA<CodeExhausted>());
    c = r3.next;
    expect(c.dead, isTrue);
    expect(c.attemptsLeft, 0);

    // The right code on the dead nonce fails — Regenerate is the only way on.
    final r4 = c.attempt(s, typed: code, nowMs: issued);
    expect(r4.result, isA<CodeExhausted>());
    expect(identical(r4.next, c), isTrue);

    // A fresh nonce (Regenerate) verifies the same person.
    final nonce2 = s.randomBytes(16);
    final code2 = verificationCode(
      s,
      Fingerprint.of(s, invitee.public),
      nonce2,
    );
    expect(code2, isNot(code), reason: 'nonce scopes the code');
    final fresh = CodeChallenge(
      relayed: invitee.public,
      nonce: nonce2,
      issuedAtMs: issued,
    );
    expect(
      fresh.attempt(s, typed: code2, nowMs: issued).result,
      isA<CeremonyVerified>(),
    );
  });

  test('B-04-10 nonce lifetime 10 minutes: expired at 10 min + 1 ms, not at 9 min 59 s (nor at exactly 10 min)', () async {
    // 04 §6.3: "nonce lifetime 10 minutes; Regenerate issues a fresh nonce."
    // 09 §2 clock-jump convention: fires at N + 1, not at N − 1.
    final s = await testSuite(seed: 16);
    final invitee = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    final nonce = s.randomBytes(16);
    final code = verificationCode(s, Fingerprint.of(s, invitee.public), nonce);
    const issued = 1_800_000_000_000;
    const tenMin = 10 * 60 * 1000;
    expect(codeNonceLifetimeMs, tenMin);
    final c = CodeChallenge(
      relayed: invitee.public,
      nonce: nonce,
      issuedAtMs: issued,
    );

    expect(c.isExpiredAt(issued + 9 * 60 * 1000 + 59 * 1000), isFalse);
    expect(
      c
          .attempt(s, typed: code, nowMs: issued + 9 * 60 * 1000 + 59 * 1000)
          .result,
      isA<CeremonyVerified>(),
    );
    expect(c.isExpiredAt(issued + tenMin), isFalse);
    expect(c.isExpiredAt(issued + tenMin + 1), isTrue);
    final late = c.attempt(s, typed: code, nowMs: issued + tenMin + 1);
    expect(late.result, isA<CodeExpired>());
    expect(
      late.next.attemptsLeft,
      3,
      reason: 'expiry does not consume attempts',
    );
  });

  test('B-04-11 device linking: new device\'s QR (suite ‖ device_id ‖ ed ‖ x ‖ nonce) round-trips; matching relayed record → VerifiedDevicePublic; a flipped byte or other id → mismatch; UMK wrapped to the verified device round-trips and no other device opens it', () async {
    // 04 §9.1: "Old device runs Verify member against the new device's Show my
    // code (same ceremony; the QR carries the new device's keys) → old device
    // wraps UMK to the new device's X25519 key".
    final s = await testSuite(seed: 17);
    final umk = UmkKeyPair.generate(s);
    final newDevice = DeviceKeyPair.generate(s, deviceId: deviceB);
    final otherDevice = DeviceKeyPair.generate(s, deviceId: deviceA);
    addTearDown(umk.dispose);
    addTearDown(newDevice.dispose);
    addTearDown(otherDevice.dispose);
    final nonce = s.randomBytes(16);

    final qr = DeviceQrPayload(device: newDevice.public, nonce: nonce);
    final bytes = qr.toBytes();
    expect(bytes.length, 97);
    expect(bytes[0], suiteVersion);
    expect(bytes.sublist(1, 17), Uuid16.toBytes(deviceB));
    expect(bytes.sublist(17, 49), newDevice.public.ed25519);
    expect(bytes.sublist(49, 81), newDevice.public.x25519);
    expect(bytes.sublist(81), nonce);
    final back = DeviceQrPayload.decode(qr.encode());
    expect(back.device, newDevice.public);
    expect(back.nonce, nonce);
    expect(
      () => DeviceQrPayload.decode(Bytes.base64Url(bytes.sublist(1))),
      throwsFormatException,
    );

    final ok = Ceremony.verifyDeviceQr(
      s,
      scanned: back,
      relayed: newDevice.public,
    );
    expect(ok, isA<DeviceVerified>());
    final verified = (ok as DeviceVerified).verified;
    expect(verified.public, newDevice.public);
    expect(verified.method, VerificationMethod.qrInPerson);

    final flipped = Uint8List.fromList(newDevice.public.x25519)..[0] ^= 1;
    expect(
      Ceremony.verifyDeviceQr(
        s,
        scanned: back,
        relayed: DevicePublic(
          deviceId: deviceB,
          ed25519: newDevice.public.ed25519,
          x25519: flipped,
        ),
      ),
      isA<DeviceMismatch>(),
    );
    expect(
      Ceremony.verifyDeviceQr(
        s,
        scanned: back,
        relayed: DevicePublic(
          deviceId: deviceA,
          ed25519: newDevice.public.ed25519,
          x25519: newDevice.public.x25519,
        ),
      ),
      isA<DeviceMismatch>(),
      reason: 'same keys, different device id',
    );

    // Wrap the UMK to the verified device and open it there.
    final wrapped = wrapUmkToDevice(s, umk, verified);
    expect(wrapped.deviceId, deviceB);
    expect(wrapped.suiteVersion, suiteVersion);
    final onNewDevice = unwrapUmk(s, wrapped, newDevice);
    addTearDown(onNewDevice.dispose);
    expect(onNewDevice.public, umk.public);
    final a = umk.exportSecretBytes();
    final b = onNewDevice.exportSecretBytes();
    expect(b, a);
    s.zeroize(a);
    s.zeroize(b);

    expect(
      () => unwrapUmk(s, wrapped, otherDevice),
      throwsA(isA<UnsealFailed>()),
      reason: 'another device cannot open it',
    );
    final forged = WrappedUmk(deviceId: deviceA, bytes: wrapped.bytes);
    expect(
      () => unwrapUmk(s, forged, otherDevice),
      throwsA(isA<UnsealFailed>()),
    );
  });
}
