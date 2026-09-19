@Tags(['B'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A fixed, synthetic server timestamp for the commitment (injected — no
/// clock in lib/).
const int _issued = 1_800_000_000_000;

/// One honest SAS session (04 §6.1, ADR 2026-09-13d §1) run to the point
/// where the verifier's device holds a ready [SasChallenge]: the invitee
/// commits, the verifier draws `r_V` against the commitment and the relayed
/// key, the invitee opens once, the verifier checks the opening.
({
  SasShower shower,
  SasVerifier verifier,
  SasResponse response,
  SasChallenge challenge,
})
_sasSession(CryptoSuite s, UmkKeyPair invitee, {String userId = userA}) {
  final shower = SasShower.open(s, userId: userId, umk: invitee.public);
  final verifier = SasVerifier.begin(
    s,
    relayed: invitee.public,
    relayedUserId: userId,
    commitment: shower.commitment,
    issuedAtMs: _issued,
  );
  final response = shower.respond(s, verifier.verifierRandom);
  final opened = verifier.open(s, response.opening) as SasOpened;
  return (
    shower: shower,
    verifier: verifier,
    response: response,
    challenge: opened.challenge,
  );
}

/// A code that differs from [code] in its first digit.
String _wrongDigit(String code) =>
    code[0] == '9' ? '0${code.substring(1)}' : '9${code.substring(1)}';

void main() {
  // B-04-4, B-04-7, B-04-9 and B-04-10 asserted the 04 §6.1 derivation over a
  // server-issued nonce and its `CodeChallenge`. ADR 2026-09-13d §1 retired
  // that derivation (a substituting relay pre-computes it — B-04-87) and the
  // app switched at U4c; the tests were @Skip'd per ADR 2026-09-05i §4 and
  // re-land here at M11 against the rule 04 §6.1 / §6.3 state today: the
  // same eight zero-padded digits, `code_remote`, three attempts, ten minutes
  // and *Regenerate*, now over the commitment-based SAS. What each one lost
  // is only the retired formula and the nonce that scoped it.
  test('B-04-4 the 8-digit code (04 §6.1, ADR 2026-09-13d §1) = decimal(first4(BLAKE2b-256("rf-sas-code-v1" ‖ FP ‖ user_id ‖ r_S ‖ r_V))) mod 10⁸, zero-padded to 8 digits, deterministic in exactly those inputs — the invite nonce stays in the QR payload and no longer derives any code; contributions of the wrong length are refused', () async {
    // 04 §6.1: "The code is decimal( first4bytes( BLAKE2b-256( FP ‖ user_id ‖
    // r_S ‖ r_V ‖ tag ) ) ) mod 10⁸, zero-padded. The invite nonce stays in
    // the QR payload only and no longer derives any code." (Re-landed at M11:
    // the superseded assertion was the `FP ‖ nonce ‖ "verify-v1"` formula.)
    final s = await testSuite(seed: 11);
    final u = UmkKeyPair.generate(s);
    addTearDown(u.dispose);
    final fp = Fingerprint.of(s, u.public);

    final x = _sasSession(s, u);
    final code = x.response.code;
    expect(code, matches(RegExp(r'^\d{8}$')));

    // Deterministic in (FP, user_id, r_S, r_V) — and a function of nothing
    // else: `sasCode` has no nonce input, so the QR payload's nonce cannot
    // reach it. Two payloads with different nonces show one and the same code.
    final again = sasCode(
      s,
      fp: fp,
      userId: userA,
      showerRandom: x.response.opening,
      verifierRandom: x.verifier.verifierRandom,
    );
    expect(again, code, reason: 'deterministic');
    final qr1 = QrPayload(
      userId: userA,
      umk: u.public,
      nonce: s.randomBytes(16),
    );
    final qr2 = QrPayload(
      userId: userA,
      umk: u.public,
      nonce: s.randomBytes(16),
    );
    expect(qr1.nonce, isNot(qr2.nonce));
    expect(Fingerprint.of(s, qr1.umk), fp);
    expect(
      Fingerprint.of(s, qr2.umk),
      fp,
      reason: 'same key, same FP, same code',
    );

    // The formula, by hand.
    final h = s.blake2b256(
      Bytes.concat([
        Uint8List.fromList(utf8.encode('rf-sas-code-v1')),
        fp.bytes,
        Uuid16.toBytes(userA),
        x.response.opening,
        x.verifier.verifierRandom,
      ]),
    );
    final first4 = ByteData.sublistView(h, 0, 4).getUint32(0);
    expect(code, (first4 % 100000000).toString().padLeft(8, '0'));

    // Find a verifier contribution whose code needs zero-padding and check the
    // padding happens — the search is deterministic under the seeded suite.
    String padded;
    do {
      padded = sasCode(
        s,
        fp: fp,
        userId: userA,
        showerRandom: x.response.opening,
        verifierRandom: s.randomBytes(sasContributionBytes),
      );
    } while (!padded.startsWith('0'));
    expect(padded.length, 8);

    // Another person's id or another key gives another code (the code binds
    // both, as the commitment does — B-04-89).
    expect(
      sasCode(
        s,
        fp: fp,
        userId: userB,
        showerRandom: x.response.opening,
        verifierRandom: x.verifier.verifierRandom,
      ),
      isNot(code),
    );

    // 128-bit contributions, refused otherwise — never guessed.
    expect(
      () => sasCode(
        s,
        fp: fp,
        userId: userA,
        showerRandom: Uint8List(15),
        verifierRandom: x.verifier.verifierRandom,
      ),
      throwsArgumentError,
    );
    expect(
      () => sasCode(
        s,
        fp: fp,
        userId: userA,
        showerRandom: x.response.opening,
        verifierRandom: Uint8List(17),
      ),
      throwsArgumentError,
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

  test('B-04-7 code path (04 §6.3, ADR 2026-09-13d §1): the correct 8 digits verify the relayed key as code_remote; whitespace read in pairs is tolerated; a wrong try costs one attempt, the earlier state is unchanged, and the right code still verifies afterwards; garbage is a wrong attempt', () async {
    // 04 §6.3 code path: the verifier's device "compares the typed digits …
    // 3 attempts per session". 04 §6.4: method `code_remote`. (Re-landed at
    // M11 over `SasChallenge`; the retired `CodeChallenge` assertions were
    // the same, over a server-issued nonce.)
    final s = await testSuite(seed: 14);
    final invitee = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    final x = _sasSession(s, invitee);
    final code = x.response.code;
    final c0 = x.challenge;
    expect(c0.attemptsLeft, 3);

    // Whitespace the invitee read aloud in pairs is tolerated.
    final spaced = '${code.substring(0, 4)} ${code.substring(4)}';
    final r1 = c0.attempt(s, typed: spaced, nowMs: _issued + 1000);
    expect(r1.result, isA<CeremonyVerified>());
    final v = (r1.result as CeremonyVerified).verified;
    expect(v.method, VerificationMethod.codeRemote);
    expect(v.public, invitee.public);
    expect(v.fingerprint, Fingerprint.of(s, invitee.public));
    expect(r1.next.dead, isTrue, reason: 'one verification per session');

    // Wrong once, then right.
    final r2 = c0.attempt(s, typed: _wrongDigit(code), nowMs: _issued + 1000);
    expect(r2.result, isA<CodeWrong>());
    expect((r2.result as CodeWrong).attemptsLeft, 2);
    expect(r2.next.attemptsLeft, 2);
    expect(
      c0.attemptsLeft,
      3,
      reason: 'immutable — the old state is unchanged',
    );
    final r3 = r2.next.attempt(s, typed: code, nowMs: _issued + 2000);
    expect(r3.result, isA<CeremonyVerified>());

    // Garbage counts as a wrong attempt, never as a match.
    final r4 = c0.attempt(s, typed: 'abcdefgh', nowMs: _issued);
    expect(r4.result, isA<CodeWrong>());
    // The shower's device answers once per session (ADR 2026-09-13d §2).
    expect(x.shower.isSpent, isTrue);
    expect(
      () => x.shower.respond(s, x.verifier.verifierRandom),
      throwsStateError,
    );
  });

  test('B-04-9 wrong 8-digit code entered 3× → session dead (CodeExhausted); the correct code no longer verifies on that session; Regenerate — a fresh commitment — yields a different code that verifies the same person', () async {
    // 04 §10: "Given a wrong 8-digit code entered 3×, then the nonce is dead
    // and a new Regenerate is required." 04 §6.3: "3 attempts per session …
    // Regenerate opens a fresh session." (Re-landed at M11: the session
    // replaces the nonce as the unit that dies.)
    final s = await testSuite(seed: 15);
    final invitee = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    final x = _sasSession(s, invitee);
    final code = x.response.code;
    final wrong = _wrongDigit(code);

    var c = x.challenge;
    final r1 = c.attempt(s, typed: wrong, nowMs: _issued);
    expect((r1.result as CodeWrong).attemptsLeft, 2);
    c = r1.next;
    final r2 = c.attempt(s, typed: wrong, nowMs: _issued);
    expect((r2.result as CodeWrong).attemptsLeft, 1);
    c = r2.next;
    final r3 = c.attempt(s, typed: wrong, nowMs: _issued);
    expect(r3.result, isA<CodeExhausted>());
    c = r3.next;
    expect(c.dead, isTrue);
    expect(c.attemptsLeft, 0);

    // The right code on the dead session fails — Regenerate is the only way on.
    final r4 = c.attempt(s, typed: code, nowMs: _issued);
    expect(r4.result, isA<CodeExhausted>());
    expect(identical(r4.next, c), isTrue);

    // Regenerate: a new session is a new r_S, a new commitment, a new code.
    final y = _sasSession(s, invitee);
    expect(y.shower.commitment, isNot(x.shower.commitment));
    expect(y.response.opening, isNot(x.response.opening));
    expect(y.response.code, isNot(code), reason: 'the session scopes the code');
    expect(
      y.challenge.attempt(s, typed: y.response.code, nowMs: _issued).result,
      isA<CeremonyVerified>(),
    );
    // …and the old code is useless on the new session.
    expect(
      y.challenge.attempt(s, typed: code, nowMs: _issued).result,
      isA<CodeWrong>(),
    );
  });

  test('B-04-10 session lifetime 10 minutes from the commitment\'s server timestamp: expired at 10 min + 1 ms, not at 9 min 59 s (nor at exactly 10 min); expiry spends no attempt', () async {
    // 04 §6.3: "lifetime 10 minutes from the commitment's server timestamp;
    // Regenerate opens a fresh session." 09 §2 clock-jump convention: fires
    // at N + 1, not at N − 1. (Re-landed at M11: the clock runs from the
    // commitment's server timestamp, not from a nonce's issue time.)
    final s = await testSuite(seed: 16);
    final invitee = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    final x = _sasSession(s, invitee);
    final code = x.response.code;
    final c = x.challenge;
    const tenMin = 10 * 60 * 1000;
    expect(codeNonceLifetimeMs, tenMin);
    expect(c.issuedAtMs, _issued, reason: 'the commitment\'s server timestamp');

    expect(c.isExpiredAt(_issued + 9 * 60 * 1000 + 59 * 1000), isFalse);
    expect(
      c
          .attempt(s, typed: code, nowMs: _issued + 9 * 60 * 1000 + 59 * 1000)
          .result,
      isA<CeremonyVerified>(),
    );
    expect(c.isExpiredAt(_issued + tenMin), isFalse);
    expect(c.isExpiredAt(_issued + tenMin + 1), isTrue);
    final late = c.attempt(s, typed: code, nowMs: _issued + tenMin + 1);
    expect(late.result, isA<CodeExpired>());
    expect(
      late.next.attemptsLeft,
      3,
      reason: 'expiry does not consume attempts',
    );
    expect(identical(late.next, c), isTrue);
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
