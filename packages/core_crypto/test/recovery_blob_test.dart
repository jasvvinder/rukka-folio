// Suite B — rung 3's sealed blob on the wire, and the verified open
// (ADR 2026-10-06d rulings 1–2 🔒; 04 §7.4, §2, §7.3 step 4).
//
// Ruling 1: `sealed_RK_blob` = 1 byte `suite_version` ‖ 24-byte nonce ‖
// ciphertext+16-byte tag, following `GuardianShare.encode` (shamir.dart).
// `core_crypto` owns both directions; the decode is strict and never guesses.
//
// Ruling 2: a recovered UMK is adopted only after its public halves match the
// account's **published** UMK (06 §3 item 3) — rung 3's authenticator is the
// AEAD under the paper RK, so `expected` is the server-relayed `UmkPublic`
// and the comparison is a currency check, not a trust decision (ADR
// 2026-09-13c §1: "no other rung has this gap"). On a mismatch the derived
// pair is disposed, which the test observes on a pair it holds.
@Tags(['B'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('B-1006d-1 SealedRecoveryBlob.encode is suite_version ‖ nonce(24) ‖ '
      'ciphertext+tag (105 bytes for a 64-byte UMK), decode round-trips it, '
      'the decoded blob opens under RK, and a seeded suite yields the same '
      'bytes run after run', () async {
    final s = await testSuite(seed: 1006);
    final umk = UmkKeyPair.generate(s);
    final rk = RecoveryKey.generate(s);
    addTearDown(umk.dispose);
    addTearDown(rk.dispose);

    final blob = sealUmkUnderRecoveryKey(s, rk, umk);
    final wire = blob.encode();

    // Layout, byte for byte (ADR 2026-10-06d §1; GuardianShare precedent:
    // the suite byte leads).
    final tag = s.sodium.crypto.aeadXChaCha20Poly1305IETF.aBytes;
    expect(tag, 16);
    expect(wire.length, 1 + 24 + 64 + tag);
    expect(wire.length, sealedRecoveryBlobBytes);
    expect(wire[0], suiteVersion);
    expect(wire[0], 0x01);
    expect(Uint8List.sublistView(wire, 1, 25), blob.nonce);
    expect(Uint8List.sublistView(wire, 25), blob.ciphertext);

    // Round trip.
    final back = SealedRecoveryBlob.decode(wire);
    expect(back.suiteVersion, blob.suiteVersion);
    expect(back.nonce, blob.nonce);
    expect(back.ciphertext, blob.ciphertext);
    expect(back.encode(), wire);

    // The decoded blob is the sealed UMK: it opens under RK.
    final recovered = openUmkWithRecoveryKey(s, rk, back);
    addTearDown(recovered.dispose);
    expect(recovered.public, umk.public);

    // decode copies: mutating the wire afterwards changes nothing.
    final copy = Uint8List.fromList(wire);
    final fromCopy = SealedRecoveryBlob.decode(copy);
    copy[30] ^= 0xff;
    expect(fromCopy.ciphertext, blob.ciphertext);

    // Deterministic under the injected RNG (09 §1).
    final s2 = await testSuite(seed: 1006);
    final umk2 = UmkKeyPair.generate(s2);
    final rk2 = RecoveryKey.generate(s2);
    addTearDown(umk2.dispose);
    addTearDown(rk2.dispose);
    expect(sealUmkUnderRecoveryKey(s2, rk2, umk2).encode(), wire);
  });

  test(
    'B-1006d-2 decode is strict: a wrong length (empty, truncated tag, one '
    'byte short or long), an unknown suite byte and a blob whose suite byte '
    'alone was changed are all RecoveryUnsealFailed; it never guesses a '
    'layout, and a future suite byte still encodes (04 §2 agility)',
    () async {
      final s = await testSuite(seed: 1007);
      final umk = UmkKeyPair.generate(s);
      final rk = RecoveryKey.generate(s);
      addTearDown(umk.dispose);
      addTearDown(rk.dispose);
      final wire = sealUmkUnderRecoveryKey(s, rk, umk).encode();

      Matcher failsWith(String reason) => throwsA(
        isA<RecoveryUnsealFailed>().having((e) => e.reason, 'reason', reason),
      );

      // Length.
      expect(
        () => SealedRecoveryBlob.decode(Uint8List(0)),
        failsWith('length'),
      );
      expect(
        () => SealedRecoveryBlob.decode(Uint8List.fromList([suiteVersion])),
        failsWith('length'),
      );
      // Truncated tag: the whole 16-byte tag gone, and just its last byte.
      expect(
        () => SealedRecoveryBlob.decode(
          Uint8List.sublistView(wire, 0, wire.length - 16),
        ),
        failsWith('length'),
      );
      expect(
        () => SealedRecoveryBlob.decode(
          Uint8List.sublistView(wire, 0, wire.length - 1),
        ),
        failsWith('length'),
      );
      // One byte too many — a longer payload is not "a bigger UMK".
      expect(
        () => SealedRecoveryBlob.decode(Bytes.concat([wire, Bytes.u8(0)])),
        failsWith('length'),
      );
      // Nonce alone, no ciphertext at all.
      expect(
        () => SealedRecoveryBlob.decode(Uint8List.sublistView(wire, 0, 25)),
        failsWith('length'),
      );

      // Suite: unknown byte, otherwise a perfect blob.
      final futureSuite = Uint8List.fromList(wire)..[0] = 0x02;
      expect(() => SealedRecoveryBlob.decode(futureSuite), failsWith('suite'));
      final zeroSuite = Uint8List.fromList(wire)..[0] = 0x00;
      expect(() => SealedRecoveryBlob.decode(zeroSuite), failsWith('suite'));
      // An unknown suite is refused even when the length is also wrong — the
      // decoder names the first thing it cannot read, never a guess.
      expect(
        () => SealedRecoveryBlob.decode(Uint8List.fromList([0x02, 1, 2, 3])),
        throwsA(isA<RecoveryUnsealFailed>()),
      );

      // A tampered body still decodes (its shape is right) and then fails
      // the AEAD under RK — strictness at decode is about layout, the tag
      // is what authenticates the bytes.
      final tampered = Uint8List.fromList(wire)..[40] ^= 0x01;
      final decoded = SealedRecoveryBlob.decode(tampered);
      expect(() => openUmkWithRecoveryKey(s, rk, decoded), failsWith('aead'));

      // 04 §2 crypto agility: a later suite bumps the first byte. Encoding a
      // blob that carries one is allowed (it is what a later suite will
      // write); today's decode refuses it typed rather than opening it as
      // suite 1.
      final later = SealedRecoveryBlob(
        nonce: Uint8List(24),
        ciphertext: Uint8List(80),
        suiteVersion: 0x02,
      );
      expect(later.encode()[0], 0x02);
      expect(
        () => SealedRecoveryBlob.decode(later.encode()),
        failsWith('suite'),
      );

      // The constructor refuses a nonce of the wrong size, so no blob with an
      // unencodable layout exists in the first place.
      expect(
        () =>
            SealedRecoveryBlob(nonce: Uint8List(23), ciphertext: Uint8List(80)),
        throwsArgumentError,
      );
    },
  );

  test('B-1006d-3 openUmkWithRecoveryKeyVerified returns the UMK only when its '
      'public halves equal the account\'s published UmkPublic; another user\'s '
      'key as expected is RecoveredUmkMismatch (nothing returned), a wrong RK '
      'is still RecoveryUnsealFailed, the pair verifyRecoveredUmk refuses is '
      'disposed, and neither path draws randomness', () async {
    final s = await testSuite(seed: 1008);
    final umk = UmkKeyPair.generate(s);
    final other = UmkKeyPair.generate(s);
    final rk = RecoveryKey.generate(s);
    final wrongRk = RecoveryKey.generate(s);
    addTearDown(umk.dispose);
    addTearDown(other.dispose);
    addTearDown(rk.dispose);
    addTearDown(wrongRk.dispose);

    final blob = SealedRecoveryBlob.decode(
      sealUmkUnderRecoveryKey(s, rk, umk).encode(),
    );

    // Match: the recovered pair is the account's. `expected` is the published
    // public — what a route relays — not a ceremony product.
    final expected = umk.public;
    final recovered = openUmkWithRecoveryKeyVerified(
      s,
      rk,
      blob,
      expected: expected,
    );
    addTearDown(recovered.dispose);
    expect(recovered.public, umk.public);
    expect(recovered.isDisposed, isFalse);
    final a = umk.exportSecretBytes();
    final b = recovered.exportSecretBytes();
    expect(b, a);
    s.zeroize(a);
    s.zeroize(b);

    // Mismatch: the blob opens (right RK) but is not the key the account
    // published — refused typed, nothing handed back (04 §7.3 step 4;
    // CLAUDE.md rule 5).
    final foreign = other.public;
    expect(
      () => openUmkWithRecoveryKeyVerified(s, rk, blob, expected: foreign),
      throwsA(isA<RecoveredUmkMismatch>()),
    );

    // The pair derived on the mismatch path is disposed, not leaked (ADR
    // 2026-10-06d §2: every buffer is zeroised). Observed directly: the
    // comparison half takes a pair the test holds, and after the refusal
    // that pair's guarded memory is gone — every secret accessor throws. A
    // pair that matches comes back live and untouched.
    final held = openUmkWithRecoveryKey(s, rk, blob);
    expect(held.isDisposed, isFalse);
    expect(
      () => verifyRecoveredUmk(s, held, expected: foreign),
      throwsA(isA<RecoveredUmkMismatch>()),
    );
    expect(held.isDisposed, isTrue);
    expect(held.exportSecretBytes, throwsStateError);
    final kept = openUmkWithRecoveryKey(s, rk, blob);
    addTearDown(kept.dispose);
    expect(
      identical(verifyRecoveredUmk(s, kept, expected: expected), kept),
      isTrue,
    );
    expect(kept.isDisposed, isFalse);

    // A wrong RK never reaches the comparison: the AEAD refuses first and
    // the failure keeps its own type, so R2.4 can tell "didn't open" from
    // "opened to the wrong key" if it ever needs to.
    expect(
      () =>
          openUmkWithRecoveryKeyVerified(s, wrongRk, blob, expected: expected),
      throwsA(
        isA<RecoveryUnsealFailed>().having((e) => e.reason, 'reason', 'aead'),
      ),
    );

    // No fresh key material is minted on either path: the verified open
    // draws nothing from the suite's random source.
    var draws = 0;
    final counting = CryptoSuite(
      s.sodium,
      random: (n) {
        draws++;
        return Uint8List(n);
      },
    );
    expect(
      () =>
          openUmkWithRecoveryKeyVerified(counting, rk, blob, expected: foreign),
      throwsA(isA<RecoveredUmkMismatch>()),
    );
    expect(draws, 0);
    expect(RecoveredUmkMismatch().toString(), contains('does not match'));
  });
}
