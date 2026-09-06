@Tags(['B'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Runs the QR ceremony against [u]'s own keys — the only way to obtain a
/// [VerifiedUmkPublic] (04 §8.2 is structural: there is no other constructor).
VerifiedUmkPublic verify(CryptoSuite s, UmkKeyPair u, {String userId = userA}) {
  final r = Ceremony.verifyQr(
    s,
    scanned: QrPayload(userId: userId, umk: u.public, nonce: s.randomBytes(16)),
    relayed: u.public,
    relayedUserId: userId,
  );
  return (r as CeremonyVerified).verified;
}

/// The raw key bytes, for equality assertions only (test code).
Uint8List keyBytes(BookKey bk) => bk.key.extractBytes();

void main() {
  test('B-04-12 sealed box to a verified UMK: opens for the recipient, UnsealFailed for another UMK, for a tampered box and for an unknown suite', () async {
    // 04 §2: "Key wrapping to a person: X25519 sealed box (crypto_box_seal)".
    // 04 §5.1: seal to the "ceremony-verified UMK public key".
    final s = await testSuite(seed: 21);
    final alice = UmkKeyPair.generate(s);
    final bob = UmkKeyPair.generate(s);
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);

    final plain = Uint8List.fromList(List.generate(40, (i) => i * 3 & 0xff));
    final blob = sealToVerified(s, verify(s, alice), plain);
    expect(blob.suiteVersion, suiteVersion);
    expect(blob.recipient, Fingerprint.of(s, alice.public));
    expect(blob.bytes.length, plain.length + s.sodium.crypto.box.sealBytes);

    expect(openSealed(s, alice, blob), plain);
    expect(
      () => openSealed(s, bob, blob),
      throwsA(
        isA<UnsealFailed>().having((e) => e.reason, 'reason', 'recipient'),
      ),
    );
    final tampered = Uint8List.fromList(blob.bytes)
      ..[blob.bytes.length - 1] ^= 1;
    expect(
      () => openSealed(
        s,
        alice,
        SealedBlob(recipient: blob.recipient, bytes: tampered),
      ),
      throwsA(isA<UnsealFailed>().having((e) => e.reason, 'reason', 'box')),
    );
    // Recipient label forged onto Bob's fingerprint: the box still will not open.
    expect(
      () => openSealed(
        s,
        bob,
        SealedBlob(recipient: Fingerprint.of(s, bob.public), bytes: blob.bytes),
      ),
      throwsA(isA<UnsealFailed>().having((e) => e.reason, 'reason', 'box')),
    );
    expect(
      () => openSealed(
        s,
        alice,
        SealedBlob(
          recipient: blob.recipient,
          bytes: blob.bytes,
          suiteVersion: 0x7f,
        ),
      ),
      throwsA(isA<UnsealFailed>().having((e) => e.reason, 'reason', 'suite')),
    );
  });

  test('B-04-13 wrapped book key unwraps to the same 32 bytes for the intended UMK and fails for another UMK; head escrow is that same wrap of the Personal-Book BK', () async {
    // 04 §5.1: "seal BK ... to the new member's ceremony-verified UMK public
    // key". 04 §10: "Given a removed member's device, when it pulls
    // post-rotation envelopes, then decryption fails for all of them."
    // 04 §7.5: head escrow scope is "the member's Personal-Book BK only".
    final s = await testSuite(seed: 22);
    final member = UmkKeyPair.generate(s);
    final outsider = UmkKeyPair.generate(s);
    final head = UmkKeyPair.generate(s);
    addTearDown(member.dispose);
    addTearDown(outsider.dispose);
    addTearDown(head.dispose);
    final bk = BookKey.generate(s, bookId: bookA, keyVersion: 1);
    addTearDown(bk.dispose);

    // Compile-time guarantee (rule 5 / 04 §8.2): `wrapBookKey(s, bk,
    // member.public)` does not type-check — UmkPublic is not VerifiedUmkPublic.
    final wrapped = wrapBookKey(s, bk, verify(s, member));
    expect(wrapped.ref, const BookKeyRef(bookId: bookA, keyVersion: 1));
    expect(wrapped.recipient, Fingerprint.of(s, member.public));
    expect(wrapped.suiteVersion, suiteVersion);
    expect(wrapped.blob.length, 32 + s.sodium.crypto.box.sealBytes);

    final opened = unwrapBookKey(s, wrapped, member);
    addTearDown(opened.dispose);
    expect(opened.ref, bk.ref);
    expect(keyBytes(opened), keyBytes(bk));

    expect(
      () => unwrapBookKey(s, wrapped, outsider),
      throwsA(isA<UnsealFailed>()),
    );

    // Head escrow: a BK wrap to the head, opened only by the head.
    final personal = BookKey.generate(s, bookId: bookA, keyVersion: 3);
    addTearDown(personal.dispose);
    final escrow = sealPersonalBookKeyForHead(
      s,
      personal,
      verify(s, head, userId: userB),
    );
    expect(escrow.ref.keyVersion, 3);
    expect(escrow.recipient, Fingerprint.of(s, head.public));
    final atHead = unwrapBookKey(s, escrow, head);
    addTearDown(atHead.dispose);
    expect(keyBytes(atHead), keyBytes(personal));
    expect(
      () => unwrapBookKey(s, escrow, member),
      throwsA(isA<UnsealFailed>()),
    );
  });

  test('B-04-14 rotation after removal: BK(v+1) is generated fresh and wrapped to every remaining member, never to the leaver; the leaver still opens v', () async {
    // 04 §5.3 step 2: "Any remaining member's device generates BK(v+1) for
    // every book the leaver could read, seals to all remaining members,
    // uploads." 04 §5.3 step 5: "Removed members keep entries they already
    // had; everything new is sealed from them."
    final s = await testSuite(seed: 23);
    final a = UmkKeyPair.generate(s);
    final b = UmkKeyPair.generate(s);
    final leaver = UmkKeyPair.generate(s);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(leaver.dispose);
    final v1 = BookKey.generate(s, bookId: bookA, keyVersion: 1);
    addTearDown(v1.dispose);
    final leaverV1 = wrapBookKey(s, v1, verify(s, leaver, userId: userB));

    final rotated = rotateBookKey(s, v1, [verify(s, a), verify(s, b)]);
    addTearDown(rotated.next.dispose);
    expect(rotated.next.ref, const BookKeyRef(bookId: bookA, keyVersion: 2));
    expect(
      keyBytes(rotated.next),
      isNot(keyBytes(v1)),
      reason: 'a fresh key, not a re-wrap',
    );
    expect(rotated.wrapped, hasLength(2));
    expect(
      rotated.wrapped.map((w) => w.recipient),
      unorderedEquals([
        Fingerprint.of(s, a.public),
        Fingerprint.of(s, b.public),
      ]),
    );
    expect(rotated.wrapped.every((w) => w.ref.keyVersion == 2), isTrue);
    expect(
      rotated.wrapped.map((w) => w.recipient),
      isNot(contains(Fingerprint.of(s, leaver.public))),
    );

    // Each remaining member opens v2 with the same bytes; the leaver cannot.
    for (final (me, w) in [(a, rotated.wrapped[0]), (b, rotated.wrapped[1])]) {
      final mine = unwrapBookKey(s, w, me);
      addTearDown(mine.dispose);
      expect(keyBytes(mine), keyBytes(rotated.next));
      expect(() => unwrapBookKey(s, w, leaver), throwsA(isA<UnsealFailed>()));
    }
    // The leaver keeps what they already had.
    final still = unwrapBookKey(s, leaverV1, leaver);
    addTearDown(still.dispose);
    expect(still.ref.keyVersion, 1);
  });
}
