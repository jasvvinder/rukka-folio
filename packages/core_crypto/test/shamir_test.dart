// Suite B — Shamir over GF(256) and the guardian share set (04 §2, §7.3; 09 §1).
//
// Ids B-04-50 … B-04-69. Deterministic through the injected RNG; the property
// test (B-04-69) uses kiri_check (ADR 2026-09-05i §5) seeded from PROPTEST_SEED
// like core_ledger's A-05i-1 — the helper is three lines, so it is repeated here
// rather than importing core_ledger into a crypto test.
@Tags(['B'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'helpers.dart';

int? get _propSeed => int.tryParse(Platform.environment['PROPTEST_SEED'] ?? '');

/// A fixed, obviously synthetic 64-byte "UMK_priv" (never a real key).
Uint8List _secret64() =>
    Uint8List.fromList(List.generate(64, (i) => (i * 37 + 11) & 0xff));

/// All k-element index subsets of 0..n-1.
Iterable<List<int>> _subsets(int n, int k) sync* {
  final idx = List<int>.generate(k, (i) => i);
  while (true) {
    yield List<int>.of(idx);
    var i = k - 1;
    while (i >= 0 && idx[i] == n - k + i) {
      i--;
    }
    if (i < 0) return;
    idx[i]++;
    for (var j = i + 1; j < k; j++) {
      idx[j] = idx[j - 1] + 1;
    }
  }
}

/// Lagrange evaluation at [x] of the polynomial through [points] (GF(256)),
/// written independently of the library's combine (which only evaluates at 0).
int _lagrangeAt(List<(int, int)> points, int x) {
  var acc = 0;
  for (var i = 0; i < points.length; i++) {
    final (xi, yi) = points[i];
    var num = 1;
    var den = 1;
    for (var j = 0; j < points.length; j++) {
      if (j == i) continue;
      final xj = points[j].$1;
      num = Gf256.mul(num, x ^ xj);
      den = Gf256.mul(den, xi ^ xj);
    }
    acc ^= Gf256.mul(yi, Gf256.mul(num, Gf256.inverse(den)));
  }
  return acc;
}

/// The guardian range of 04 §7.3: every (k, n) with 2 ≤ k ≤ n ≤ 5.
const List<(int, int)> _guardianRange = [
  (2, 2),
  (2, 3),
  (3, 3),
  (2, 4),
  (3, 4),
  (4, 4),
  (2, 5),
  (3, 5),
  (4, 5),
  (5, 5),
];

void main() {
  group('GF(256)', () {
    test('B-04-50 known answers under 0x11b: 0x53·0xCA = 0x01, 0x57·0x83 = 0xC1, 0x57·0x13 = 0xFE; 0 and 1 behave', () {
      expect(Gf256.polynomial, 0x11b);
      expect(Gf256.mul(0x53, 0xca), 0x01);
      expect(Gf256.mul(0xca, 0x53), 0x01);
      expect(Gf256.mul(0x57, 0x83), 0xc1); // FIPS-197 §4.2 worked example
      expect(Gf256.mul(0x57, 0x13), 0xfe); // FIPS-197 §4.2.1
      expect(Gf256.mul(0x02, 0x80), 0x1b); // the reduction step itself
      for (var a = 0; a < 256; a++) {
        expect(Gf256.mul(a, 0), 0);
        expect(Gf256.mul(0, a), 0);
        expect(Gf256.mul(a, 1), a);
        expect(Gf256.add(a, a), 0, reason: 'characteristic 2');
      }
      expect(Gf256.add(0x53, 0xca), 0x53 ^ 0xca);
    });

    test('B-04-51 a·inv(a) = 1 for every a ≠ 0; inverse(0) is refused', () {
      for (var a = 1; a < 256; a++) {
        final inv = Gf256.inverse(a);
        expect(Gf256.mul(a, inv), 1, reason: 'a = $a, inv = $inv');
        expect(Gf256.mulTable(a, inv), 1);
      }
      expect(Gf256.inverse(0x53), 0xca);
      expect(() => Gf256.inverse(0), throwsArgumentError);
    });

    test('B-04-52 exp/log tables (generator 3) cover all 255 non-zero elements once and agree with the branch-free mul on all 65 536 pairs', () {
      expect(Gf256.exp.length, 255);
      expect(Gf256.exp.toSet().length, 255, reason: 'a permutation of 1..255');
      expect(Gf256.exp.contains(0), isFalse);
      expect(Gf256.exp[0], 1);
      expect(Gf256.exp[1], 3);
      for (var i = 0; i < 255; i++) {
        expect(Gf256.log[Gf256.exp[i]], i);
      }
      for (var a = 0; a < 256; a++) {
        for (var b = 0; b < 256; b++) {
          if (Gf256.mulTable(a, b) != Gf256.mul(a, b)) {
            fail(
              'mul($a, $b): loop ${Gf256.mul(a, b)} ≠ table ${Gf256.mulTable(a, b)}',
            );
          }
        }
      }
    });
  });

  group('Shamir split/combine', () {
    test('B-04-53 round-trip for every (k, n) in the guardian range and 3-of-5 over a real 64-byte UMK_priv', () async {
      final s = await testSuite(seed: 5);
      final secret = _secret64();
      for (final (k, n) in _guardianRange) {
        final shares = Shamir.split(s, secret, k: k, n: n);
        expect(shares.length, n);
        expect(shares.map((x) => x.index), List.generate(n, (i) => i + 1));
        for (final sh in shares) {
          expect(sh.bytes.length, 64);
          expect(sh.threshold, k);
          expect(
            sh.bytes,
            isNot(secret),
            reason: 'a share is never the secret',
          );
        }
        expect(
          Shamir.combine(shares.take(k).toList()),
          secret,
          reason: '($k, $n) first k',
        );
        expect(Shamir.combine(shares), secret, reason: '($k, $n) all n');
      }
      final umk = UmkKeyPair.generate(s);
      addTearDown(umk.dispose);
      final priv = umk.exportSecretBytes();
      final shares = Shamir.split(s, priv, k: 3, n: 5);
      final back = Shamir.combine([shares[4], shares[1], shares[2]]);
      expect(back, priv);
      final again = UmkKeyPair.fromSecretBytes(s, back);
      addTearDown(again.dispose);
      expect(again.public, umk.public);
    });

    test('B-04-54 any k-subset of n reconstructs — every subset enumerated for n ≤ 5, in any order', () async {
      final s = await testSuite(seed: 6);
      final secret = Uint8List.fromList([
        0x00,
        0x01,
        0x7f,
        0x80,
        0xfe,
        0xff,
        0x42,
        0xa5,
      ]);
      var subsets = 0;
      for (final (k, n) in _guardianRange) {
        final shares = Shamir.split(s, secret, k: k, n: n);
        for (final idx in _subsets(n, k)) {
          final chosen = [for (final i in idx) shares[i]];
          expect(
            Shamir.combine(chosen),
            secret,
            reason: '($k, $n) subset $idx',
          );
          expect(Shamir.combine(chosen.reversed.toList()), secret);
          subsets++;
        }
      }
      expect(
        subsets,
        1 + 3 + 1 + 6 + 4 + 1 + 10 + 10 + 5 + 1,
      ); // Σ C(n, k) = 42
    });

    test('B-04-55 k − 1 shares carry no information: for every candidate byte v in 0..255 a consistent k-th share exists (2-of-3 and 3-of-5)', () async {
      final s = await testSuite(seed: 8);
      final secret = Uint8List.fromList([0x9c, 0x00, 0xff, 0x31]);
      for (final (k, n) in [(2, 3), (3, 5), (5, 5)]) {
        final shares = Shamir.split(s, secret, k: k, n: n);
        final partial = shares
            .take(k - 1)
            .toList(); // what an under-threshold coalition holds
        final missingX = shares[k - 1].index; // the index they would need
        for (var b = 0; b < secret.length; b++) {
          for (var v = 0; v < 256; v++) {
            // The unique degree ≤ k−1 polynomial through the k−1 held points
            // and (0, v) — evaluate it at the missing index to forge that share.
            final points = [
              for (final p in partial) (p.index, p.bytes[b]),
              (0, v),
            ];
            final forgedY = _lagrangeAt(points, missingX);
            final forged = Uint8List.fromList(shares[k - 1].bytes)
              ..[b] = forgedY;
            final out = Shamir.combine([
              ...partial,
              ShamirShare(index: missingX, bytes: forged, threshold: k),
            ]);
            expect(
              out[b],
              v,
              reason: '($k, $n) byte $b: v=$v has no consistent k-th share',
            );
          }
        }
        // And the real k-th share is just one of those 256 possibilities.
        expect(Shamir.combine(shares.take(k).toList()), secret);
      }
    });

    test('B-04-56 seeded suite → byte-identical shares run after run; a different seed → different shares for the same secret (09 §1)', () async {
      final secret = _secret64();
      final a = Shamir.split(await testSuite(seed: 42), secret, k: 3, n: 5);
      final b = Shamir.split(await testSuite(seed: 42), secret, k: 3, n: 5);
      final c = Shamir.split(await testSuite(seed: 43), secret, k: 3, n: 5);
      for (var i = 0; i < 5; i++) {
        expect(a[i].bytes, b[i].bytes, reason: 'share ${i + 1} same seed');
        expect(
          a[i].bytes,
          isNot(c[i].bytes),
          reason: 'share ${i + 1} other seed',
        );
      }
      expect(Shamir.combine(c.sublist(2)), secret);
      // Consumption is fixed: exactly len·(k−1) bytes per split, one call.
      var calls = 0;
      var drawn = 0;
      final s = await sodium();
      final counting = CryptoSuite(
        s,
        random: (n) {
          calls++;
          drawn += n;
          return Uint8List(n)..fillRange(0, n, 0x5a);
        },
      );
      Shamir.split(counting, secret, k: 3, n: 5);
      expect(calls, 1);
      expect(drawn, 64 * 2);
    });

    test('B-04-57 a tampered share byte yields a wrong secret — silently (integrity is the sealed transit of 04 §7.3 step 3, not this layer)', () async {
      final s = await testSuite(seed: 9);
      final secret = _secret64();
      final shares = Shamir.split(s, secret, k: 2, n: 3);
      final tampered = Uint8List.fromList(shares[0].bytes)..[10] ^= 0x01;
      final out = Shamir.combine([
        ShamirShare(index: 1, bytes: tampered, threshold: 2),
        shares[1],
      ]);
      expect(out, isNot(secret));
      expect(out.length, 64);
      // Only the tampered position differs — every byte is its own polynomial.
      for (var i = 0; i < 64; i++) {
        expect(out[i] == secret[i], i != 10, reason: 'byte $i');
      }
    });

    test('B-04-58 duplicate index refused', () async {
      final s = await testSuite(seed: 10);
      final shares = Shamir.split(s, _secret64(), k: 2, n: 3);
      expect(
        () => Shamir.combine([shares[0], shares[0]]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('duplicate'),
          ),
        ),
      );
      // Same index, different bytes — still a duplicate, not a second share.
      final other = ShamirShare(index: 1, bytes: shares[1].bytes, threshold: 2);
      expect(() => Shamir.combine([shares[0], other]), throwsArgumentError);
      expect(
        () => Shamir.combine([shares[0], shares[1], shares[1]]),
        throwsArgumentError,
      );
    });

    test('B-04-59 malformed inputs refused: empty list, mismatched lengths, index 0 or > 255, empty bytes, disagreeing thresholds', () async {
      final s = await testSuite(seed: 11);
      final shares = Shamir.split(s, _secret64(), k: 2, n: 3);
      expect(() => Shamir.combine([]), throwsArgumentError);
      final short = ShamirShare(index: 2, bytes: Uint8List(63), threshold: 2);
      expect(
        () => Shamir.combine([shares[0], short]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('length'),
          ),
        ),
      );
      expect(
        () => ShamirShare(index: 0, bytes: Uint8List(1)),
        throwsArgumentError,
      );
      expect(
        () => ShamirShare(index: 256, bytes: Uint8List(1)),
        throwsArgumentError,
      );
      expect(
        () => ShamirShare(index: 1, bytes: Uint8List(0)),
        throwsArgumentError,
      );
      expect(
        () => ShamirShare(index: 1, bytes: Uint8List(1), threshold: 1),
        throwsArgumentError,
      );
      final k3 = ShamirShare(index: 2, bytes: shares[1].bytes, threshold: 3);
      expect(
        () => Shamir.combine([shares[0], k3]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('threshold'),
          ),
        ),
      );
      // Shares of unknown provenance (threshold null) combine on trust.
      final bare = [
        for (final x in shares.take(2))
          ShamirShare(index: x.index, bytes: x.bytes),
      ];
      expect(Shamir.combine(bare), _secret64());
    });

    test('B-04-60 fewer shares than the declared threshold are refused rather than yielding garbage', () async {
      final s = await testSuite(seed: 12);
      final shares = Shamir.split(s, _secret64(), k: 3, n: 5);
      expect(
        () => Shamir.combine([shares[0], shares[4]]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('need 3'),
          ),
        ),
      );
      expect(() => Shamir.combine([shares[2]]), throwsArgumentError);
      expect(Shamir.combine([shares[0], shares[2], shares[4]]), _secret64());
    });

    test('B-04-61 split validation: k = 1 refused (no threshold), k > n, n > 255, empty secret; k = 2, n = 255 is the edge that works', () async {
      final s = await testSuite(seed: 13);
      final secret = Uint8List.fromList([1, 2, 3]);
      expect(() => Shamir.split(s, secret, k: 1, n: 3), throwsArgumentError);
      expect(() => Shamir.split(s, secret, k: 0, n: 3), throwsArgumentError);
      expect(() => Shamir.split(s, secret, k: 4, n: 3), throwsArgumentError);
      expect(() => Shamir.split(s, secret, k: 2, n: 256), throwsArgumentError);
      expect(
        () => Shamir.split(s, Uint8List(0), k: 2, n: 3),
        throwsArgumentError,
      );
      final wide = Shamir.split(s, secret, k: 2, n: 255);
      expect(wide.length, 255);
      expect(wide.last.index, 255);
      expect(Shamir.combine([wide[0], wide[254]]), secret);
      expect(Shamir.combine([wide[100], wide[7]]), secret);
      // A 1-byte secret is fine.
      final one = Shamir.split(s, Uint8List.fromList([0xab]), k: 2, n: 2);
      expect(Shamir.combine(one), [0xab]);
    });
  });

  group('Guardian policy and share set (04 §7.3)', () {
    test('B-04-62 default threshold k = ⌈(n + 1) / 2⌉: 2→2, 3→2, 4→3, 5→3; n outside 2..5 refused', () {
      expect(GuardianPolicy.defaultThreshold(2), 2);
      expect(GuardianPolicy.defaultThreshold(3), 2);
      expect(GuardianPolicy.defaultThreshold(4), 3);
      expect(GuardianPolicy.defaultThreshold(5), 3);
      for (final n in [-1, 0, 1, 6, 7, 255]) {
        expect(
          () => GuardianPolicy.defaultThreshold(n),
          throwsArgumentError,
          reason: 'n = $n',
        );
      }
      expect(GuardianPolicy.minGuardians, 2);
      expect(GuardianPolicy.maxGuardians, 5);
    });

    test('B-04-63 GuardianShare wire form = u8(suite) ‖ u32be(share_set_version) ‖ u8(k) ‖ u8(n) ‖ u8(index) ‖ bytes; decode inverts encode', () async {
      final s = await testSuite(seed: 14);
      final priv = _secret64();
      final shares = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 0x01020304,
      );
      expect(shares.length, 3);
      for (var i = 0; i < 3; i++) {
        final g = shares[i];
        expect(g.suiteVersion, 0x01);
        expect(g.shareSetVersion, 0x01020304);
        expect(g.k, 2, reason: 'default 2-of-3');
        expect(g.n, 3);
        expect(g.index, i + 1);
        expect(g.bytes.length, 64);
        final wire = g.encode();
        expect(wire.length, GuardianShare.headerLength + 64);
        expect(wire.sublist(0, 8), [0x01, 0x01, 0x02, 0x03, 0x04, 2, 3, i + 1]);
        expect(wire.sublist(8), g.bytes);
        final back = GuardianShare.decode(wire);
        expect(back.suiteVersion, g.suiteVersion);
        expect(back.shareSetVersion, g.shareSetVersion);
        expect(back.k, g.k);
        expect(back.n, g.n);
        expect(back.index, g.index);
        expect(back.bytes, g.bytes);
        expect(back.encode(), wire);
      }
      // Decode works on a view into a larger buffer (offset ≠ 0).
      final padded = Bytes.concat([
        Uint8List.fromList([9, 9, 9]),
        shares[1].encode(),
      ]);
      final view = Uint8List.sublistView(padded, 3);
      expect(GuardianShare.decode(view).encode(), shares[1].encode());
      // Same suite + seed → same wire bytes (deterministic, 09 §1).
      final again = GuardianShareSet.create(
        await testSuite(seed: 14),
        umkSecret: priv,
        n: 3,
        shareSetVersion: 0x01020304,
      );
      expect(again[2].encode(), shares[2].encode());
    });

    test('B-04-64 k of n guardian shares reconstruct UMK_priv exactly and the pair re-derives the same public keys (04 §7.3 step 4–5)', () async {
      final s = await testSuite(seed: 15);
      final umk = UmkKeyPair.generate(s);
      addTearDown(umk.dispose);
      final priv = umk.exportSecretBytes();
      for (final n in [2, 3, 4, 5]) {
        final k = GuardianPolicy.defaultThreshold(n);
        final shares = GuardianShareSet.create(
          s,
          umkSecret: priv,
          n: n,
          shareSetVersion: 1,
        );
        // Decode-from-wire path, as a recovering device would see them.
        final wire = [for (final g in shares) GuardianShare.decode(g.encode())];
        for (final idx in _subsets(n, k)) {
          final back = GuardianShareSet.reconstruct([
            for (final i in idx) wire[i],
          ]);
          expect(back, priv, reason: '$k-of-$n subset $idx');
          final pair = UmkKeyPair.fromSecretBytes(s, back);
          expect(pair.public, umk.public);
          pair.dispose();
          s.zeroize(back); // 04 §7.3 step 4 — the caller's duty
        }
        // More than k also works.
        expect(GuardianShareSet.reconstruct(wire), priv);
      }
    });

    test('B-04-65 shares from different share_set_versions are refused — a re-split after a guardian change never mixes with the old set (04 §7.3)', () async {
      final s = await testSuite(seed: 16);
      final priv = _secret64();
      final v1 = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 1,
      );
      final v2 = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 2,
      );
      expect(
        () => GuardianShareSet.reconstruct([v1[0], v2[1]]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('share_set_version'),
          ),
        ),
      );
      expect(
        () => GuardianShareSet.reconstruct([v1[0], v1[1], v2[2]]),
        throwsArgumentError,
      );
      // Each generation on its own is fine, and they differ on the wire.
      expect(GuardianShareSet.reconstruct([v1[0], v1[2]]), priv);
      expect(GuardianShareSet.reconstruct([v2[1], v2[2]]), priv);
      expect(v1[0].bytes, isNot(v2[0].bytes));
      // Tampered share bytes at the same version → wrong secret, not an error
      // (no integrity at this layer; the sealed box on transit carries it).
      final bad = GuardianShare(
        suiteVersion: v1[0].suiteVersion,
        shareSetVersion: 1,
        k: 2,
        n: 3,
        index: 1,
        bytes: Uint8List.fromList(v1[0].bytes)..[0] ^= 0x80,
      );
      expect(GuardianShareSet.reconstruct([bad, v1[1]]), isNot(priv));
    });

    test('B-04-66 reconstruct refuses fewer than k, empty, k/n/suite metadata mismatch and duplicate indices', () async {
      final s = await testSuite(seed: 17);
      final priv = _secret64();
      final shares = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 5,
        shareSetVersion: 7,
      );
      expect(shares.first.k, 3);
      expect(
        () => GuardianShareSet.reconstruct([shares[0], shares[4]]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('need 3'),
          ),
        ),
      );
      expect(() => GuardianShareSet.reconstruct([]), throwsArgumentError);
      expect(
        () => GuardianShareSet.reconstruct([shares[0], shares[1], shares[1]]),
        throwsArgumentError,
      );
      final otherN = GuardianShare(
        suiteVersion: 1,
        shareSetVersion: 7,
        k: 3,
        n: 4,
        index: 3,
        bytes: shares[2].bytes,
      );
      expect(
        () => GuardianShareSet.reconstruct([shares[0], shares[1], otherN]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('metadata'),
          ),
        ),
      );
      final otherK = GuardianShare(
        suiteVersion: 1,
        shareSetVersion: 7,
        k: 2,
        n: 5,
        index: 3,
        bytes: shares[2].bytes,
      );
      expect(
        () => GuardianShareSet.reconstruct([shares[0], shares[1], otherK]),
        throwsArgumentError,
      );
      final otherSuite = GuardianShare(
        suiteVersion: 2,
        shareSetVersion: 7,
        k: 3,
        n: 5,
        index: 3,
        bytes: shares[2].bytes,
      );
      expect(
        () => GuardianShareSet.reconstruct([shares[0], shares[1], otherSuite]),
        throwsArgumentError,
      );
      expect(
        GuardianShareSet.reconstruct([shares[3], shares[0], shares[2]]),
        priv,
      );
    });

    test('B-04-67 2-of-2 is permitted (the data-loss warning is UI); both shares needed, either alone refused', () async {
      final s = await testSuite(seed: 18);
      final priv = _secret64();
      final shares = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 2,
        shareSetVersion: 1,
      );
      expect(shares.length, 2);
      expect(shares.first.k, 2);
      expect(GuardianShareSet.reconstruct(shares), priv);
      expect(GuardianShareSet.reconstruct(shares.reversed.toList()), priv);
      expect(
        () => GuardianShareSet.reconstruct([shares[0]]),
        throwsArgumentError,
      );
      expect(
        () => GuardianShareSet.reconstruct([shares[1]]),
        throwsArgumentError,
      );
    });

    test('B-04-68 create/decode validation: n outside 2..5, explicit k outside 2..n, short buffer, unknown suite_version, k > n, index 0 or > n', () async {
      final s = await testSuite(seed: 19);
      final priv = _secret64();
      expect(
        () => GuardianShareSet.create(
          s,
          umkSecret: priv,
          n: 1,
          shareSetVersion: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => GuardianShareSet.create(
          s,
          umkSecret: priv,
          n: 6,
          shareSetVersion: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => GuardianShareSet.create(
          s,
          umkSecret: priv,
          n: 3,
          k: 1,
          shareSetVersion: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => GuardianShareSet.create(
          s,
          umkSecret: priv,
          n: 3,
          k: 4,
          shareSetVersion: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => GuardianShareSet.create(
          s,
          umkSecret: priv,
          n: 3,
          shareSetVersion: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => GuardianShareSet.create(
          s,
          umkSecret: priv,
          n: 3,
          shareSetVersion: 1 << 32,
        ),
        throwsArgumentError,
      );
      expect(
        () => GuardianShareSet.create(
          s,
          umkSecret: Uint8List(0),
          n: 3,
          shareSetVersion: 1,
        ),
        throwsArgumentError,
      );
      // Explicit k = n and k = 2 within range are accepted (3-of-3, 2-of-5).
      expect(
        GuardianShareSet.create(
          s,
          umkSecret: priv,
          n: 3,
          k: 3,
          shareSetVersion: 1,
        ).first.k,
        3,
      );
      expect(
        GuardianShareSet.create(
          s,
          umkSecret: priv,
          n: 5,
          k: 2,
          shareSetVersion: 1,
        ).first.k,
        2,
      );

      final good = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 5,
      )[0].encode();
      expect(() => GuardianShare.decode(Uint8List(0)), throwsFormatException);
      expect(
        () => GuardianShare.decode(good.sublist(0, 8)),
        throwsFormatException,
        reason: 'header only',
      );
      expect(
        () => GuardianShare.decode(Uint8List.fromList(good)..[0] = 0x02),
        throwsFormatException,
      );
      expect(
        () => GuardianShare.decode(Uint8List.fromList(good)..[5] = 4),
        throwsArgumentError,
        reason: 'k 4 > n 3',
      );
      expect(
        () => GuardianShare.decode(Uint8List.fromList(good)..[5] = 1),
        throwsArgumentError,
        reason: 'k = 1',
      );
      expect(
        () => GuardianShare.decode(Uint8List.fromList(good)..[7] = 0),
        throwsArgumentError,
        reason: 'index 0',
      );
      expect(
        () => GuardianShare.decode(Uint8List.fromList(good)..[7] = 4),
        throwsArgumentError,
        reason: 'index > n',
      );
      // Header fields can be read straight off the wire without touching the secret.
      final view = GuardianShare.decode(good);
      expect(view.shareSetVersion, 5);
      expect(view.index, 1);
    });
    test('B-04-72 reconstructVerified: k good shares yield a pair re-deriving the known UMK public key; one tampered share, or another user\'s key, → GuardianShareMismatch with the bytes zeroised (04 §7.3 step 4–5, ADR 2026-09-06 §2)', () async {
      final s = await testSuite(seed: 21);
      final umk = UmkKeyPair.generate(s);
      final other = UmkKeyPair.generate(s);
      addTearDown(umk.dispose);
      addTearDown(other.dispose);
      final priv = umk.exportSecretBytes();
      final shares = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 7,
      );
      final wire = [for (final g in shares) GuardianShare.decode(g.encode())];

      // Every k-subset verifies against the public key the device already has.
      for (final idx in _subsets(3, 2)) {
        final pair = GuardianShareSet.reconstructVerified(s, [
          for (final i in idx) wire[i],
        ], expected: umk.public);
        expect(pair.public, umk.public, reason: 'subset $idx');
        expect(pair.exportSecretBytes(), priv);
        pair.dispose();
      }

      // A single flipped bit in one share — undetectable by reconstruct()
      // (B-04-57) — is caught here.
      final tampered = GuardianShare(
        suiteVersion: wire[0].suiteVersion,
        shareSetVersion: 7,
        k: 2,
        n: 3,
        index: 1,
        bytes: Uint8List.fromList(wire[0].bytes)..[5] ^= 0x01,
      );
      expect(GuardianShareSet.reconstruct([tampered, wire[1]]), isNot(priv));
      expect(
        () => GuardianShareSet.reconstructVerified(s, [
          tampered,
          wire[1],
        ], expected: umk.public),
        throwsA(isA<GuardianShareMismatch>()),
      );

      // Good shares of the wrong account are refused too.
      expect(
        () => GuardianShareSet.reconstructVerified(s, [
          wire[1],
          wire[2],
        ], expected: other.public),
        throwsA(isA<GuardianShareMismatch>()),
      );

      // Structural refusals still surface as ArgumentError, not as mismatch.
      expect(
        () => GuardianShareSet.reconstructVerified(s, [
          wire[0],
        ], expected: umk.public),
        throwsArgumentError,
      );
      s.zeroize(priv);
    });

    test('B-04-73 known-answer vector from an independent GF(256) reference (table-free Russian-peasant multiply, brute-force inverse; scratch Python, 6 Sep 2026): fixed 3-of-5 shares combine to the fixed secret from every 3-subset, and split() under a scripted RNG reproduces the shares byte for byte', () async {
      // Secret and shares as printed by the reference. The reference fixed the
      // coefficients of x¹ and x² for secret byte j at (j·29 + 7) and
      // (j·113 + 91) mod 256, so the split side can be replayed by scripting
      // the suite's random source with exactly that buffer (layout of
      // Shamir.split: coefficients[j·(k−1) + t] = coefficient of x^(t+1)).
      final secret = Uint8List.fromList([
        0x00, 0x01, 0x7f, 0x80, 0xff, 0x11, 0x22, 0x33, //
        0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb,
      ]);
      const vectors = <int, List<int>>{
        1: [
          0x5c,
          0xe9,
          0x03,
          0x70,
          0x9b,
          0x19,
          0x96,
          0x93,
          0x48,
          0x0d,
          0x8a,
          0x07,
          0x4c,
          0x01,
          0xbe,
          0xfb,
        ],
        2: [
          0x79,
          0x54,
          0x09,
          0xb2,
          0x75,
          0x4c,
          0x57,
          0x5f,
          0x20,
          0x06,
          0x0d,
          0x23,
          0xe4,
          0xe2,
          0x99,
          0x11,
        ],
        3: [
          0x25,
          0xbc,
          0x75,
          0x42,
          0x11,
          0x44,
          0xe3,
          0xff,
          0x2c,
          0x5e,
          0xe1,
          0x53,
          0x20,
          0x7a,
          0x8d,
          0x51,
        ],
        4: [
          0xdb,
          0xe5,
          0x9d,
          0xed,
          0xe3,
          0x84,
          0xd0,
          0x37,
          0x67,
          0x52,
          0x26,
          0x39,
          0x81,
          0x34,
          0xa0,
          0x5c,
        ],
        5: [
          0x87,
          0x0d,
          0xe1,
          0x1d,
          0x87,
          0x8c,
          0x64,
          0x97,
          0x6b,
          0x0a,
          0xca,
          0x49,
          0x45,
          0xac,
          0xb4,
          0x1c,
        ],
      };
      final shares = [
        for (final e in vectors.entries)
          ShamirShare(
            index: e.key,
            bytes: Uint8List.fromList(e.value),
            threshold: 3,
          ),
      ];

      // Combine side: every 3-subset, in reverse order too.
      for (final idx in _subsets(5, 3)) {
        final picked = [for (final i in idx) shares[i]];
        expect(Shamir.combine(picked), secret, reason: 'subset $idx');
        expect(Shamir.combine(picked.reversed.toList()), secret);
      }
      expect(Shamir.combine(shares), secret);

      // Split side: script the RNG with the reference's coefficient buffer.
      final coefficients = Uint8List(secret.length * 2);
      for (var j = 0; j < secret.length; j++) {
        coefficients[j * 2] = (j * 29 + 7) & 0xff;
        coefficients[j * 2 + 1] = (j * 113 + 91) & 0xff;
      }
      var draws = 0;
      final scripted = CryptoSuite(
        await sodium(),
        random: (n) {
          draws++;
          expect(n, coefficients.length, reason: 'one draw of len·(k−1)');
          return Uint8List.fromList(coefficients);
        },
      );
      final produced = Shamir.split(scripted, secret, k: 3, n: 5);
      expect(draws, 1);
      for (final p in produced) {
        expect(p.bytes, vectors[p.index], reason: 'share ${p.index}');
      }
    });
  });

  group('property', () {
    late CryptoSuite suite;
    setUpAll(() async {
      suite = await testSuite(seed: 20260906);
    });

    property('B-04-69 split → combine is the identity for random secrets, 2 ≤ k ≤ n ≤ 8, over a random k-subset in random order (kiri_check, shrinking)', () {
      forAll(
        combine3(
          binary(minLength: 1, maxLength: 80),
          integer(min: 2, max: 8),
          integer(min: 0, max: 1 << 30),
        ),
        (input) {
          final (secretList, n, pick) = input;
          final secret = Uint8List.fromList(secretList);
          final k = 2 + pick % (n - 1);
          final shares = Shamir.split(suite, secret, k: k, n: n);
          expect(shares.length, n);
          // A random k-subset in random order, driven by the generated seed.
          final order = List<int>.generate(n, (i) => i)..shuffle(Random(pick));
          final chosen = [for (final i in order.take(k)) shares[i]];
          expect(
            Shamir.combine(chosen),
            secret,
            reason: 'k=$k n=$n subset=${order.take(k)}',
          );
          expect(Shamir.combine(shares), secret, reason: 'all n');
          // k − 1 of them are refused, never wrong.
          expect(() => Shamir.combine(chosen.sublist(1)), throwsArgumentError);
          // No share equals the secret unless a coefficient vector happens to
          // be all zero — probability 256^-(len·(k−1)); assert it for len ≥ 4.
          if (secret.length >= 4) {
            for (final sh in shares) {
              expect(sh.bytes, isNot(secret));
            }
          }
        },
        maxExamples: 300,
        seed: _propSeed,
      );
    }, tags: 'property');
  });
}
