@Tags(['B'])
library;

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('B-10-1 package identifies itself', () {
    expect(suiteVersion, 0x01);
  });

  test('B-04-1 fingerprint = BLAKE2b-256(x25519 ‖ ed25519), deterministic under a seeded suite', () async {
    final s1 = await testSuite(seed: 7);
    final s2 = await testSuite(seed: 7);
    final u1 = UmkKeyPair.generate(s1);
    final u2 = UmkKeyPair.generate(s2);
    addTearDown(u1.dispose);
    addTearDown(u2.dispose);
    expect(u1.public, u2.public);
    final fp = Fingerprint.of(s1, u1.public);
    expect(
      fp.bytes,
      s1.blake2b256(Bytes.concat([u1.public.x25519, u1.public.ed25519])),
    );
    expect(Fingerprint.of(s2, u2.public), fp);
    final other = UmkKeyPair.generate(s1);
    addTearDown(other.dispose);
    expect(Fingerprint.of(s1, other.public), isNot(fp));
  });

  test('B-04-2 UMK secret bytes round-trip: export → fromSecretBytes yields the same public keys', () async {
    final s = await testSuite(seed: 3);
    final u = UmkKeyPair.generate(s);
    addTearDown(u.dispose);
    final secret = u.exportSecretBytes();
    expect(secret.length, 64);
    final again = UmkKeyPair.fromSecretBytes(s, secret);
    addTearDown(again.dispose);
    s.zeroize(secret);
    expect(again.public, u.public);
  });

  test('B-04-3 uuid ↔ 16 bytes round-trip; non-canonical forms refused', () {
    final b = Uuid16.toBytes(bookA);
    expect(b.length, 16);
    expect(Uuid16.fromBytes(b), bookA);
    expect(
      () => Uuid16.toBytes('ABCDEF00-1111-4111-8111-111111111111'),
      throwsFormatException,
    );
    expect(
      Uuid16.fromBytes(Uuid16.toBytes('abcdef00-1111-4111-8111-111111111111')),
      'abcdef00-1111-4111-8111-111111111111',
    );
    expect(() => Uuid16.toBytes('not-a-uuid'), throwsFormatException);
  });
}
