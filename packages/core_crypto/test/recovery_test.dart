@Tags(['B'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Raw RK bytes, for equality assertions only (test code).
Uint8List rkBytes(RecoveryKey rk) => rk.key.extractBytes();

void main() {
  test('B-04-15 sealed_RK_blob = XChaCha20-Poly1305(RK, UMK_priv) with a fresh 24-byte nonce: opens to the same UMK under RK; a wrong RK or a tampered byte fails typed', () async {
    // 04 §7.4: "RK = random 256-bit ... Server stores sealed_RK_blob =
    // XChaCha20(RK, UMK_priv)" and "Recovery: scan/type RK → fetch blob →
    // decrypt UMK". 04 §2: XChaCha20-Poly1305 with a 24-byte random nonce.
    final s = await testSuite(seed: 31);
    final umk = UmkKeyPair.generate(s);
    final rk = RecoveryKey.generate(s);
    final wrongRk = RecoveryKey.generate(s);
    addTearDown(umk.dispose);
    addTearDown(rk.dispose);
    addTearDown(wrongRk.dispose);
    expect(rk.key.length, 32);

    final blob = sealUmkUnderRecoveryKey(s, rk, umk);
    expect(blob.suiteVersion, suiteVersion);
    expect(blob.nonce.length, 24);
    expect(
      blob.ciphertext.length,
      64 + s.sodium.crypto.aeadXChaCha20Poly1305IETF.aBytes,
    );

    final recovered = openUmkWithRecoveryKey(s, rk, blob);
    addTearDown(recovered.dispose);
    expect(recovered.public, umk.public);
    final a = umk.exportSecretBytes();
    final b = recovered.exportSecretBytes();
    expect(b, a);
    s.zeroize(a);
    s.zeroize(b);

    expect(
      () => openUmkWithRecoveryKey(s, wrongRk, blob),
      throwsA(
        isA<RecoveryUnsealFailed>().having((e) => e.reason, 'reason', 'aead'),
      ),
    );
    final tampered = Uint8List.fromList(blob.ciphertext)..[5] ^= 0x10;
    expect(
      () => openUmkWithRecoveryKey(
        s,
        rk,
        SealedRecoveryBlob(nonce: blob.nonce, ciphertext: tampered),
      ),
      throwsA(isA<RecoveryUnsealFailed>()),
    );
    expect(
      () => openUmkWithRecoveryKey(
        s,
        rk,
        SealedRecoveryBlob(
          nonce: blob.nonce,
          ciphertext: blob.ciphertext,
          suiteVersion: 0x02,
        ),
      ),
      throwsA(
        isA<RecoveryUnsealFailed>().having((e) => e.reason, 'reason', 'suite'),
      ),
    );

    // Two seals of the same UMK use different nonces (fresh per seal).
    final again = sealUmkUnderRecoveryKey(s, rk, umk);
    expect(again.nonce, isNot(blob.nonce));
  });

  test('B-04-16 sheet QR = base64url(version ‖ user_id ‖ RK) round-trips; wrong length or unknown version refused', () async {
    // 04 §7.4: "Sheet = one-page PDF: QR base64url(version ‖ user_id ‖ RK)".
    final s = await testSuite(seed: 32);
    final rk = RecoveryKey.generate(s);
    addTearDown(rk.dispose);

    final qr = recoverySheetQr(userA, rk);
    final raw = Bytes.fromBase64Url(qr);
    expect(raw.length, 49);
    expect(raw[0], recoverySheetVersion);
    expect(raw.sublist(1, 17), Uuid16.toBytes(userA));
    expect(raw.sublist(17), rkBytes(rk));

    final sheet = recoverySheetFromQr(s, qr);
    addTearDown(sheet.dispose);
    expect(sheet.version, recoverySheetVersion);
    expect(sheet.userId, userA);
    expect(rkBytes(sheet.rk), rkBytes(rk));

    expect(
      () => recoverySheetFromQr(s, Bytes.base64Url(raw.sublist(0, 48))),
      throwsFormatException,
    );
    final badVersion = Uint8List.fromList(raw)..[0] = 0x09;
    expect(
      () => recoverySheetFromQr(s, Bytes.base64Url(badVersion)),
      throwsFormatException,
    );
    expect(() => recoverySheetFromQr(s, '***'), throwsFormatException);
  });

  test('B-04-17 typed fallback: Crockford Base32 in groups of 4 with a 2-char checksum group; round-trips; decoder accepts lowercase, O/I/L aliases, dropped hyphens and stray spaces', () async {
    // 04 §7.4: "typed fallback (Crockford Base32, groups of 4, 2-char
    // checksum)". Crockford's alphabet excludes I, L, O, U and decodes
    // O→0, I/L→1 so a reader's confusion is harmless.
    final s = await testSuite(seed: 33);
    final rk = RecoveryKey.generate(s);
    addTearDown(rk.dispose);

    final typed = recoverySheetTyped(s, userA, rk);
    final groups = typed.split('-');
    // 49 bytes = 392 bits → 79 symbols → 19 groups of 4 + one of 3, then the
    // 2-symbol checksum group.
    expect(groups.length, 21);
    expect(groups.sublist(0, 19).every((g) => g.length == 4), isTrue);
    expect(groups[19].length, 3);
    expect(groups[20].length, 2);
    expect(typed, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z-]+$')));
    expect(typed, isNot(matches(RegExp('[ILOU]'))));

    final sheet = recoverySheetFromTyped(s, typed);
    addTearDown(sheet.dispose);
    expect(sheet.userId, userA);
    expect(rkBytes(sheet.rk), rkBytes(rk));

    // Same bytes as the QR payload.
    expect(
      rkBytes(recoverySheetFromQr(s, recoverySheetQr(userA, rk)).rk),
      rkBytes(rk),
    );

    // Tolerances: lowercase, aliases, hyphens dropped, spaces inserted.
    final sloppy = typed
        .toLowerCase()
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('-', ' ')
        .replaceAllMapped(RegExp('.{9}'), (m) => '${m[0]} ');
    final decoded = recoverySheetFromTyped(s, sloppy);
    addTearDown(decoded.dispose);
    expect(rkBytes(decoded.rk), rkBytes(rk));
    final withL = typed.replaceAll('1', 'L').replaceAll('-', '');
    final decodedL = recoverySheetFromTyped(s, withL);
    addTearDown(decodedL.dispose);
    expect(rkBytes(decodedL.rk), rkBytes(rk));
  });

  test('B-04-18 typed fallback refuses a bad checksum (typo in the body or in the checksum group) with a typed error; a foreign symbol (U) and a wrong length are FormatExceptions', () async {
    // 04 §7.4 "2-char checksum" — the checksum exists to catch typing errors,
    // so a mistyped sheet must be refused, never decoded to a wrong key.
    // ⚠️ SPEC: the checksum function is this slice's interpretation (first 2
    // Crockford symbols of BLAKE2b-256 over the payload) — see recovery.dart.
    final s = await testSuite(seed: 34);
    final rk = RecoveryKey.generate(s);
    addTearDown(rk.dispose);
    final typed = recoverySheetTyped(s, userA, rk);

    // Typo in the body: swap one symbol for a different valid one.
    String flip(String t, int i) {
      const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
      final c = t[i];
      final r = alphabet[(alphabet.indexOf(c) + 1) % alphabet.length];
      return t.substring(0, i) + r + t.substring(i + 1);
    }

    expect(
      () => recoverySheetFromTyped(s, flip(typed, 0)),
      throwsA(isA<RecoverySheetChecksumFailed>()),
    );
    expect(
      () => recoverySheetFromTyped(s, flip(typed, 22)),
      throwsA(isA<RecoverySheetChecksumFailed>()),
    );
    // Typo in the checksum group itself.
    expect(
      () => recoverySheetFromTyped(s, flip(typed, typed.length - 1)),
      throwsA(isA<RecoverySheetChecksumFailed>()),
    );
    // Not in the alphabet at all.
    expect(
      () => recoverySheetFromTyped(s, 'U${typed.substring(1)}'),
      throwsFormatException,
    );
    // Wrong length.
    expect(
      () => recoverySheetFromTyped(s, typed.substring(5)),
      throwsFormatException,
    );
    expect(() => recoverySheetFromTyped(s, '${typed}A'), throwsFormatException);
  });

  test('B-04-19 a seeded suite is deterministic: RK, UMK, sheet text and the RK-sealed blob (nonce and ciphertext) are byte-identical run after run', () async {
    // 09 §1: "Injected clock and injected RNG everywhere ... required for
    // deterministic crypto tests." 09 §2 B: "pure, deterministic via injected
    // RNG". Note: `crypto_box_seal` draws its ephemeral key pair from
    // libsodium's own CSPRNG, so sealed boxes are NOT reproducible under the
    // injected RNG (asserted below); the AEAD path, whose nonce comes from
    // the suite, is.
    final s1 = await testSuite(seed: 35);
    final s2 = await testSuite(seed: 35);
    final u1 = UmkKeyPair.generate(s1);
    final u2 = UmkKeyPair.generate(s2);
    final rk1 = RecoveryKey.generate(s1);
    final rk2 = RecoveryKey.generate(s2);
    addTearDown(u1.dispose);
    addTearDown(u2.dispose);
    addTearDown(rk1.dispose);
    addTearDown(rk2.dispose);

    expect(u1.public, u2.public);
    expect(rkBytes(rk1), rkBytes(rk2));
    expect(recoverySheetQr(userA, rk1), recoverySheetQr(userA, rk2));
    expect(
      recoverySheetTyped(s1, userA, rk1),
      recoverySheetTyped(s2, userA, rk2),
    );

    final b1 = sealUmkUnderRecoveryKey(s1, rk1, u1);
    final b2 = sealUmkUnderRecoveryKey(s2, rk2, u2);
    expect(b1.nonce, b2.nonce);
    expect(b1.ciphertext, b2.ciphertext);

    // A different seed changes everything.
    final s3 = await testSuite(seed: 36);
    final rk3 = RecoveryKey.generate(s3);
    addTearDown(rk3.dispose);
    expect(rkBytes(rk3), isNot(rkBytes(rk1)));

    // Sealed boxes: libsodium's internal ephemeral randomness — not injected.
    final r1 = Ceremony.verifyQr(
      s1,
      scanned: QrPayload(
        userId: userA,
        umk: u1.public,
        nonce: s1.randomBytes(16),
      ),
      relayed: u1.public,
      relayedUserId: userA,
    ) as CeremonyVerified;
    final r2 = Ceremony.verifyQr(
      s2,
      scanned: QrPayload(
        userId: userA,
        umk: u2.public,
        nonce: s2.randomBytes(16),
      ),
      relayed: u2.public,
      relayedUserId: userA,
    ) as CeremonyVerified;
    final plain = Uint8List.fromList([1, 2, 3, 4]);
    final box1 = sealToVerified(s1, r1.verified, plain);
    final box2 = sealToVerified(s2, r2.verified, plain);
    expect(box1.recipient, box2.recipient);
    expect(
      box1.bytes,
      isNot(box2.bytes),
      reason:
          'crypto_box_seal ephemeral key comes from libsodium, not the suite',
    );
  });
}
