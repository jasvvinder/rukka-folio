// Suite B — the recovery candidate is its own X25519 pair, one per attempt
// (ADR 2026-09-24b §1 🔒, desk 12; 04 §7.3 steps 1–4).
//
// Id B-24b-1. 04 §7.3 step 1's *candidate X25519 pair* is not the fresh
// device's `pub_x`: the device mints a dedicated pair when it opens an attempt
// and holds it in the platform key store until the attempt closes. The key
// store holds bytes, so the pair must survive a round trip through them —
// minted, exported once, rebuilt on a later launch — without the rebuilt pair
// being a different key (the guardians' shares are sealed to the first one)
// and without a plaintext seed outliving the call that used it.
//
// Test code may read files and use dart:io — the purity rule binds lib/.
@Tags(['B'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
    'B-24b-1 the candidate pair restores from its secret: the rebuilt pair '
    'is the minted key (same public half, opens what was sealed to it), the '
    'seed drawn to mint it is zeroised, a wrong-length secret is refused, '
    'and nothing in core_crypto but openResealedShare accepts the pair',
    () async {
      final s0 = await sodium();

      // A random source that remembers every buffer it handed out, so the test
      // can look at the seed *after* generate returned.
      final drawn = <Uint8List>[];
      final base = deterministicRandom(s0, 241);
      final suite = CryptoSuite(
        s0,
        random: (n) {
          final b = base(n);
          drawn.add(b);
          return b;
        },
      );

      final minted = RecoveryCandidateKeyPair.generate(suite);
      addTearDown(minted.dispose);
      expect(minted.x25519.length, 32);

      // The seed is zeroised after use: the only bytes generate drew were the
      // 32-byte seed, and they are all zero now.
      expect(drawn, hasLength(1));
      expect(drawn.single.length, 32);
      expect(
        drawn.single,
        everyElement(0),
        reason: 'the plaintext seed must not outlive generate()',
      );

      // Deterministic under the injected RNG — never a hidden random source.
      final again = RecoveryCandidateKeyPair.generate(
        CryptoSuite(s0, random: deterministicRandom(s0, 241)),
      );
      addTearDown(again.dispose);
      expect(again.x25519, minted.x25519);
      final other = RecoveryCandidateKeyPair.generate(
        CryptoSuite(s0, random: deterministicRandom(s0, 242)),
      );
      addTearDown(other.dispose);
      expect(other.x25519, isNot(minted.x25519));

      // Round trip through the bytes the key store holds.
      final secret = minted.exportSecretBytes();
      expect(secret.length, 32);
      expect(secret.any((b) => b != 0), isTrue);
      final rebuilt = RecoveryCandidateKeyPair.fromSecretBytes(suite, secret);
      addTearDown(rebuilt.dispose);
      // The caller's buffer is copied, not kept: zeroising it changes nothing.
      suite.zeroize(secret);
      expect(secret, everyElement(0));
      expect(rebuilt.x25519, minted.x25519);

      // …and it is the same KEY, not merely the same public bytes: a box sealed
      // to the minted public half (what a guardian re-seals to, step 3) opens
      // under the rebuilt secret (step 4).
      final message = Uint8List.fromList(List<int>.generate(40, (i) => i));
      final box = s0.crypto.box.seal(
        message: message,
        publicKey: minted.x25519,
      );
      final opened = s0.crypto.box.sealOpen(
        cipherText: box,
        publicKey: rebuilt.x25519,
        secretKey: rebuilt.x25519Secret,
      );
      expect(opened, message);
      // A different candidate cannot open it.
      expect(
        () => s0.crypto.box.sealOpen(
          cipherText: box,
          publicKey: other.x25519,
          secretKey: other.x25519Secret,
        ),
        throwsA(anything),
      );

      // Every export is a fresh copy the caller owns.
      final e1 = rebuilt.exportSecretBytes();
      final e2 = rebuilt.exportSecretBytes();
      suite.zeroize(e1);
      expect(e2.any((b) => b != 0), isTrue);
      suite.zeroize(e2);

      // A wrong-length secret is refused, never padded or truncated into a key.
      for (final n in const [0, 31, 33, 64]) {
        expect(
          () => RecoveryCandidateKeyPair.fromSecretBytes(suite, Uint8List(n)),
          throwsA(isA<ArgumentError>()),
          reason: '$n bytes is not a candidate secret',
        );
      }

      // Disposed means gone: no read path remains, and dispose is idempotent.
      final spent = RecoveryCandidateKeyPair.fromSecretBytes(
        suite,
        minted.exportSecretBytes(),
      );
      spent.dispose();
      spent.dispose();
      expect(spent.isDisposed, isTrue);
      expect(spent.exportSecretBytes, throwsStateError);
      expect(() => spent.x25519Secret, throwsStateError);
      expect(spent.toString(), isNot(contains(Bytes.hex(minted.x25519))));

      // Never wraps a BK and is never a device key (ADR 2026-09-24b §1): the
      // one function in core_crypto that takes the pair is the step-4 opener.
      final takers = <String>[];
      final param = RegExp(r'RecoveryCandidateKeyPair\s+[a-z]\w*\s*[,)]');
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trimLeft().startsWith('//')) continue;
          if (param.hasMatch(lines[i])) takers.add('${f.path}:${i + 1}');
        }
      }
      expect(takers, hasLength(1), reason: takers.join('\n'));
      expect(takers.single, contains('wrapping.dart'));
      final wrapping = File('lib/src/wrapping.dart').readAsLinesSync();
      final at = int.parse(takers.single.split(':').last) - 1;
      expect(
        wrapping.sublist(at - 4, at + 1).join('\n'),
        contains('GuardianShare openResealedShare('),
      );
    },
  );
}
