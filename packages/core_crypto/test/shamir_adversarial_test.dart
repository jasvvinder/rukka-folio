// Suite B — adversarial review of shamir.dart and the guardian-share paths
// (04 §7.3, §8; ADR 2026-09-06 §1–2; escalation lane M7-K2, 13 Sep 2026).
//
// Ids B-04-74 … B-04-81. Each test pins a property the review had to *reason*
// about rather than read off the code: an independent field construction,
// degenerate inputs, every below-threshold subset, cross-split replay and
// re-labelling, zeroisation and use-after-dispose, injected randomness with no
// fallback, and the verified-key type boundary as seen from `app/`.
// Test code may use dart:io and dart:math — the purity rule binds lib/.
@Tags(['B'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A fixed, obviously synthetic 64-byte "UMK_priv" (never a real key).
Uint8List _secret64() =>
    Uint8List.fromList(List.generate(64, (i) => (i * 37 + 11) & 0xff));

/// All k-element index subsets of 0..n-1.
Iterable<List<int>> _subsets(int n, int k) sync* {
  if (k == 0) {
    yield const [];
    return;
  }
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

/// Textbook GF(2^8) multiply written as two separate steps — a carry-less
/// schoolbook product to 15 bits, then long division by 0x11b — with plain
/// `if`s. It shares no code and no structure with `Gf256.mul` (interleaved
/// branch-free xtime) or `Gf256.mulTable` (exp/log), so agreement is evidence.
int _refMul(int a, int b) {
  var product = 0;
  for (var i = 0; i < 8; i++) {
    if ((b >> i) & 1 == 1) product ^= a << i;
  }
  for (var bit = 14; bit >= 8; bit--) {
    if ((product >> bit) & 1 == 1) product ^= 0x11b << (bit - 8);
  }
  return product;
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

/// A [GuardianShare] with one header field rewritten — what an attacker who
/// controls the sealed transit could present.
GuardianShare _relabel(
  GuardianShare g, {
  int? shareSetVersion,
  int? index,
  int? suiteVersion,
  Uint8List? bytes,
}) => GuardianShare(
  suiteVersion: suiteVersion ?? g.suiteVersion,
  shareSetVersion: shareSetVersion ?? g.shareSetVersion,
  k: g.k,
  n: g.n,
  index: index ?? g.index,
  bytes: bytes ?? g.bytes,
);

Iterable<File> _dartFilesUnder(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
}

void main() {
  group('field arithmetic (independent construction)', () {
    test('B-04-74 a textbook carry-less-multiply-then-reduce agrees with Gf256.mul and mulTable on all 65 536 pairs; field laws hold; every non-zero element has exactly one inverse', () {
      // Sanity of the reference itself against FIPS-197 §4.2.
      expect(_refMul(0x57, 0x83), 0xc1);
      expect(_refMul(0x57, 0x13), 0xfe);
      for (var a = 0; a < 256; a++) {
        var inverses = 0;
        for (var b = 0; b < 256; b++) {
          final r = _refMul(a, b);
          if (Gf256.mul(a, b) != r || Gf256.mulTable(a, b) != r) {
            fail(
              'mul($a, $b): ref $r, loop ${Gf256.mul(a, b)}, table ${Gf256.mulTable(a, b)}',
            );
          }
          if (r == 1) inverses++;
        }
        expect(inverses, a == 0 ? 0 : 1, reason: 'inverses of $a');
        if (a != 0) expect(Gf256.mul(a, Gf256.inverse(a)), 1);
      }
      // Associativity and distributivity on a stride-7 lattice (37³ triples).
      for (var a = 0; a < 256; a += 7) {
        for (var b = 0; b < 256; b += 7) {
          for (var c = 0; c < 256; c += 7) {
            expect(
              Gf256.mul(a, Gf256.mul(b, c)),
              Gf256.mul(Gf256.mul(a, b), c),
              reason: 'assoc $a $b $c',
            );
            expect(
              Gf256.mul(a, b ^ c),
              Gf256.mul(a, b) ^ Gf256.mul(a, c),
              reason: 'distrib $a $b $c',
            );
          }
        }
      }
      // The exp table is the powers of 3 under the reference multiply too.
      var p = 1;
      for (var i = 0; i < 255; i++) {
        expect(Gf256.exp[i], p, reason: 'exp[$i]');
        p = _refMul(p, 3);
      }
      expect(p, 1, reason: '3^255 = 1: generator has full order');
      // Out-of-range operands are masked, not misread (the only public inputs
      // that reach mulTable/inverse are indices already validated to 1..255).
      expect(Gf256.mul(0x153, 0x183), Gf256.mul(0x53, 0x83));
      expect(
        () => ShamirShare(index: 256, bytes: Uint8List(1)),
        throwsArgumentError,
      );
    });
  });

  group('degenerate inputs and thresholds', () {
    test('B-04-75 zero, all-0xff and one-byte secrets split and reconstruct from every k-subset for every guardian (k, n); k = n = 255 and k = 3, n = 255 hold; shares of a zero secret are not zero', () async {
      final s = await testSuite(seed: 74);
      final secrets = [
        Uint8List(64),
        Uint8List(64)..fillRange(0, 64, 0xff),
        Uint8List.fromList([0x00]),
        Uint8List.fromList([0xff]),
        Uint8List.fromList([0x80]),
      ];
      for (final secret in secrets) {
        for (final (k, n) in _guardianRange) {
          final shares = Shamir.split(s, secret, k: k, n: n);
          if (secret.length == 64) {
            for (final sh in shares) {
              expect(
                sh.bytes.any((b) => b != 0),
                isTrue,
                reason: 'a share of the zero secret is random, not zero',
              );
            }
          }
          for (final idx in _subsets(n, k)) {
            expect(
              Shamir.combine([for (final i in idx) shares[i]]),
              secret,
              reason: 'len ${secret.length} ($k, $n) subset $idx',
            );
          }
          expect(Shamir.combine(shares), secret);
        }
      }
      // The far corner of the parameter space: every share is needed.
      final eight = Uint8List.fromList([0, 1, 2, 3, 0xfc, 0xfd, 0xfe, 0xff]);
      final all = Shamir.split(s, eight, k: 255, n: 255);
      expect(all.length, 255);
      expect(Shamir.combine(all), eight);
      expect(Shamir.combine(all.reversed.toList()), eight);
      expect(() => Shamir.combine(all.sublist(1)), throwsArgumentError);
      // Wide fan-out, small threshold: 200 random 3-subsets of 255.
      final wide = Shamir.split(s, _secret64(), k: 3, n: 255);
      final rng = Random(255);
      for (var t = 0; t < 200; t++) {
        final picked = <int>{};
        while (picked.length < 3) {
          picked.add(rng.nextInt(255));
        }
        expect(
          Shamir.combine([for (final i in picked) wide[i]]),
          _secret64(),
          reason: 'subset $picked',
        );
      }
    });

    test('B-04-76 below threshold never returns bytes: every subset of size 1..k−1 of every guardian (k, n) is refused; a lone share is refused even without a declared threshold; stripped thresholds are the one hole, and the wire form closes it', () async {
      final s = await testSuite(seed: 75);
      final secret = _secret64();
      var refused = 0;
      for (final (k, n) in _guardianRange) {
        final shares = Shamir.split(s, secret, k: k, n: n);
        for (var size = 1; size < k; size++) {
          for (final idx in _subsets(n, size)) {
            expect(
              () => Shamir.combine([for (final i in idx) shares[i]]),
              throwsArgumentError,
              reason: '($k, $n) subset $idx of size $size returned bytes',
            );
            refused++;
          }
        }
      }
      expect(refused, greaterThan(40));

      // Provenance stripped (threshold == null): one share alone is still
      // refused — split() never issues k = 1, so a lone share can only ever
      // "reconstruct" to its own bytes.
      final three = Shamir.split(s, secret, k: 3, n: 5);
      final bare = [
        for (final x in three) ShamirShare(index: x.index, bytes: x.bytes),
      ];
      expect(
        () => Shamir.combine([bare[0]]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('at least 2'),
          ),
        ),
      );
      // Two bare shares of a 3-of-5: Shamir cannot know k and returns *wrong*
      // bytes — this is exactly why the threshold rides on every share and on
      // the guardian wire form (B-04-63), and why reconstructVerified exists.
      final wrong = Shamir.combine([bare[0], bare[1]]);
      expect(wrong.length, 64);
      expect(wrong, isNot(secret));
      // One labelled share is enough to restore the refusal.
      expect(() => Shamir.combine([bare[0], three[1]]), throwsArgumentError);
      expect(Shamir.combine([bare[0], bare[1], bare[2]]), secret);
    });
  });

  group('cross-split replay, re-labelling and truncation', () {
    test('B-04-77 a share replayed from another split, another user, another index, or truncated/extended, never yields the UMK: reconstruct() is wrong or refuses, reconstructVerified() always fails closed and leaves the caller\'s shares intact', () async {
      final s = await testSuite(seed: 76);
      final umk = UmkKeyPair.generate(s);
      final other = UmkKeyPair.generate(s);
      addTearDown(umk.dispose);
      addTearDown(other.dispose);
      final priv = umk.exportSecretBytes();
      final otherPriv = other.exportSecretBytes();
      addTearDown(() => s.zeroize(priv));
      addTearDown(() => s.zeroize(otherPriv));

      // Shamir layer: two splits of the *same* secret do not mix.
      final a = Shamir.split(s, priv, k: 2, n: 3);
      final b = Shamir.split(s, priv, k: 2, n: 3);
      final mixed = Shamir.combine([a[0], b[1]]);
      expect(mixed.length, 64);
      expect(mixed, isNot(priv), reason: 'plausible garbage, not the secret');

      // Guardian layer.
      final v7 = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 7,
      );
      final v8 = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 8,
      );
      final theirs = GuardianShareSet.create(
        s,
        umkSecret: otherPriv,
        n: 3,
        shareSetVersion: 7,
      );
      final snapshot = [for (final g in v7) Uint8List.fromList(g.bytes)];

      void failsClosed(List<GuardianShare> set, String what) {
        expect(
          () => GuardianShareSet.reconstructVerified(
            s,
            set,
            expected: verifiedUmk(s, umk),
          ),
          throwsA(isA<GuardianShareMismatch>()),
          reason: what,
        );
        // The caller still owns intact shares — the UI re-requests, it does
        // not lose what it has.
        for (var i = 0; i < v7.length; i++) {
          expect(v7[i].isDisposed, isFalse);
          expect(
            v7[i].bytes,
            snapshot[i],
            reason: '$what left share ${i + 1} altered',
          );
        }
      }

      // 1. Re-labelled generation: a v8 share wearing a v7 header.
      final relabelled = _relabel(v8[1], shareSetVersion: 7);
      expect(GuardianShareSet.reconstruct([v7[0], relabelled]), isNot(priv));
      failsClosed([v7[0], relabelled], 're-labelled share_set_version');

      // 2. Another user's share with matching (version, k, n).
      expect(GuardianShareSet.reconstruct([v7[0], theirs[1]]), isNot(priv));
      failsClosed([v7[0], theirs[1]], 'cross-user replay');

      // 3. Re-indexed: share 1's bytes presented as share 3.
      final reindexed = _relabel(v7[0], index: 3);
      expect(GuardianShareSet.reconstruct([v7[1], reindexed]), isNot(priv));
      failsClosed([v7[1], reindexed], 're-indexed share');

      // 4. k good shares plus one foreign: extra shares are interpolated, not
      //    ignored, so the intruder poisons the result — and dropping it heals.
      expect(
        GuardianShareSet.reconstruct([v7[0], v7[1], theirs[2]]),
        isNot(priv),
      );
      failsClosed([v7[0], v7[1], theirs[2]], 'k good + 1 foreign');
      final healed = GuardianShareSet.reconstructVerified(s, [
        v7[0],
        v7[1],
      ], expected: verifiedUmk(s, umk));
      expect(healed.public, umk.public);
      healed.dispose();

      // 5. Truncated wire: one short share is a length mismatch; all short is
      //    a 63-byte "secret" that cannot be a UMK.
      final wire0 = v7[0].encode();
      final wire1 = v7[1].encode();
      final short0 = GuardianShare.decode(wire0.sublist(0, wire0.length - 1));
      final short1 = GuardianShare.decode(wire1.sublist(0, wire1.length - 1));
      expect(short0.bytes.length, 63);
      expect(
        () => GuardianShareSet.reconstruct([short0, v7[1]]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('length'),
          ),
        ),
      );
      expect(GuardianShareSet.reconstruct([short0, short1]).length, 63);
      failsClosed([short0, short1], 'all shares truncated');

      // 6. Extended wire: a trailing byte makes a 65-byte non-UMK.
      final long0 = GuardianShare.decode(
        Bytes.concat([
          wire0,
          Uint8List.fromList([0]),
        ]),
      );
      final long1 = GuardianShare.decode(
        Bytes.concat([
          wire1,
          Uint8List.fromList([0]),
        ]),
      );
      expect(GuardianShareSet.reconstruct([long0, long1]).length, 65);
      failsClosed([long0, long1], 'all shares extended');

      // 7. Header only / header + 0 bytes never decode.
      expect(
        () => GuardianShare.decode(wire0.sublist(0, 8)),
        throwsFormatException,
      );

      // The honest set still works after all of the above.
      final ok = GuardianShareSet.reconstructVerified(s, [
        v7[2],
        v7[0],
      ], expected: verifiedUmk(s, umk));
      expect(ok.public, umk.public);
      ok.dispose();
    });
  });

  group('memory hygiene', () {
    test('B-04-78 the coefficient buffer is zeroised after split() and create(); dispose() zeroises the share, is idempotent, and every later read — bytes, encode, toShamirShare, combine, reconstruct — throws StateError instead of interpolating zeros', () async {
      final s = await sodium();
      Uint8List? drawn;
      final recording = CryptoSuite(
        s,
        random: (n) {
          drawn = Uint8List.fromList(
            List.generate(n, (i) => (i * 131 + 17) & 0xff),
          );
          return drawn!;
        },
      );
      final secret = _secret64();
      Shamir.split(recording, secret, k: 3, n: 5);
      expect(drawn, isNotNull);
      expect(drawn!.length, 64 * 2);
      expect(
        drawn,
        everyElement(0),
        reason: 'split() left coefficients in memory',
      );
      drawn = null;
      final set = GuardianShareSet.create(
        recording,
        umkSecret: secret,
        n: 5,
        shareSetVersion: 1,
      );
      expect(
        drawn,
        everyElement(0),
        reason: 'create() left coefficients in memory',
      );

      // Constructor copies: the caller's buffer is not the share's.
      final input = Uint8List.fromList(set[0].bytes);
      final copy = ShamirShare(index: 1, bytes: input, threshold: 3);
      input.fillRange(0, input.length, 0xee);
      expect(copy.bytes, isNot(input));

      // ShamirShare: the getter hands out the live buffer, so a reference
      // taken before dispose() shows the zeroisation.
      final shares = Shamir.split(recording, secret, k: 2, n: 3);
      final live = shares[0].bytes;
      expect(live.any((b) => b != 0), isTrue);
      expect(shares[0].isDisposed, isFalse);
      shares[0].dispose();
      expect(shares[0].isDisposed, isTrue);
      expect(live, everyElement(0));
      shares[0].dispose(); // idempotent
      expect(() => shares[0].bytes, throwsStateError);
      expect(
        () => Shamir.combine([shares[0], shares[1]]),
        throwsStateError,
        reason: 'a zeroised share must not interpolate to garbage',
      );
      expect(Shamir.combine([shares[1], shares[2]]), secret);

      // GuardianShare: same contract, every read path.
      final g = set[0];
      final gLive = g.bytes;
      g.dispose();
      expect(g.isDisposed, isTrue);
      expect(gLive, everyElement(0));
      g.dispose();
      expect(() => g.bytes, throwsStateError);
      expect(() => g.encode(), throwsStateError);
      expect(() => g.toShamirShare(), throwsStateError);
      expect(
        () => GuardianShareSet.reconstruct([g, set[1], set[2]]),
        throwsStateError,
      );
      expect(GuardianShareSet.reconstruct([set[1], set[2], set[3]]), secret);

      // reconstructVerified: the pair is the only holder of the secret, and
      // its dispose() closes every read path (B-04-70 for the pair itself).
      final umk = UmkKeyPair.generate(recording);
      addTearDown(umk.dispose);
      final priv = umk.exportSecretBytes();
      final gs = GuardianShareSet.create(
        recording,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 2,
      );
      s.secureCopy(priv).dispose(); // no-op sanity that priv is 64 bytes
      final pair = GuardianShareSet.reconstructVerified(recording, [
        gs[0],
        gs[2],
      ], expected: verifiedUmk(recording, umk));
      expect(pair.exportSecretBytes(), priv);
      pair.dispose();
      expect(pair.isDisposed, isTrue);
      expect(() => pair.exportSecretBytes(), throwsA(anything));
      recording.zeroize(priv);
    });
  });

  group('determinism and injection', () {
    test('B-04-79 shamir.dart draws randomness only through CryptoSuite.randomBytes — no dart:math, dart:io, Random, DateTime — and an RNG that throws or returns the wrong length yields no shares (no fallback); a seeded suite is byte-identical, the live CSPRNG is not', () async {
      final src = File('lib/src/shamir.dart').readAsLinesSync();
      final code = src.where((l) => !l.trimLeft().startsWith('//')).toList();
      final imports = code.where((l) => l.startsWith('import '));
      expect(
        imports.map((l) => l.trim()).toList(),
        unorderedEquals([
          "import 'dart:typed_data';",
          "import 'bytes.dart';",
          "import 'keys.dart';",
          "import 'suite.dart';",
        ]),
        reason: 'only typed_data and sibling modules',
      );
      for (final banned in [
        'dart:math',
        'dart:io',
        'dart:async',
        'Random',
        'DateTime',
        'Stopwatch',
        'print(',
        'SodiumInit',
      ]) {
        expect(
          code.where((l) => l.contains(banned)).toList(),
          isEmpty,
          reason: '$banned in shamir.dart',
        );
      }
      expect(
        code.where((l) => l.contains('randomBytes(')).length,
        1,
        reason: 'exactly one draw site: Shamir.split',
      );

      final s = await sodium();
      final secret = _secret64();
      // An RNG that fails must surface, not be papered over.
      final failing = CryptoSuite(
        s,
        random: (_) => throw StateError('no entropy'),
      );
      expect(
        () => Shamir.split(failing, secret, k: 3, n: 5),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'no entropy'),
        ),
      );
      // Short or long output is refused by the suite before any share exists.
      final short = CryptoSuite(s, random: (n) => Uint8List(n - 1));
      expect(() => Shamir.split(short, secret, k: 3, n: 5), throwsStateError);
      final long = CryptoSuite(s, random: (n) => Uint8List(n + 1));
      expect(() => Shamir.split(long, secret, k: 3, n: 5), throwsStateError);
      expect(
        () => GuardianShareSet.create(
          short,
          umkSecret: secret,
          n: 3,
          shareSetVersion: 1,
        ),
        throwsStateError,
      );

      // Seeded: identical wire bytes; the stream advances between calls.
      final x = GuardianShareSet.create(
        await testSuite(seed: 77),
        umkSecret: secret,
        n: 5,
        shareSetVersion: 3,
      );
      final y = GuardianShareSet.create(
        await testSuite(seed: 77),
        umkSecret: secret,
        n: 5,
        shareSetVersion: 3,
      );
      for (var i = 0; i < 5; i++) {
        expect(x[i].encode(), y[i].encode());
      }
      final one = await testSuite(seed: 78);
      final p = GuardianShareSet.create(
        one,
        umkSecret: secret,
        n: 3,
        shareSetVersion: 1,
      );
      final q = GuardianShareSet.create(
        one,
        umkSecret: secret,
        n: 3,
        shareSetVersion: 1,
      );
      expect(p[0].bytes, isNot(q[0].bytes), reason: 'second draw differs');
      expect(GuardianShareSet.reconstruct([p[0], p[2]]), secret);
      expect(GuardianShareSet.reconstruct([q[1], q[2]]), secret);
      // Live CSPRNG: two splits differ and both reconstruct.
      final live = await liveSuite();
      final l1 = Shamir.split(live, secret, k: 2, n: 3);
      final l2 = Shamir.split(live, secret, k: 2, n: 3);
      expect(l1[0].bytes, isNot(l2[0].bytes));
      expect(Shamir.combine([l1[0], l1[2]]), secret);
      expect(Shamir.combine([l2[1], l2[0]]), secret);
    });
  });

  group('verified-key boundary (04 §8.2)', () {
    test('B-04-80 VerifiedUmkPublic is constructed only inside ceremony.dart — no other Dart source in app/ or packages/ names its constructor or silences the analyzer — and a guardian share travels only through sealToVerified/openSealed end to end', () async {
      // Static side: the only construction sites in the repository.
      // Production sources only: app/lib, every packages/*/lib, and the
      // harness — never test/ or .dart_tool/ (this file names the literal).
      final roots = [
        '../../app/lib',
        '../../testing',
        for (final d in Directory('../../packages').listSync())
          if (d is Directory) '${d.path}/lib',
      ];
      final constructions = <String>[];
      final silenced = <String>[];
      for (final root in roots) {
        for (final f in _dartFilesUnder(root)) {
          final lines = f.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.trimLeft().startsWith('//')) continue;
            if (line.contains('VerifiedUmkPublic.internal(') ||
                line.contains('VerifiedDevicePublic.internal(')) {
              constructions.add('${f.path}:${i + 1}');
            }
            if (line.contains('invalid_use_of_internal_member')) {
              silenced.add('${f.path}:${i + 1}');
            }
          }
        }
      }
      expect(
        Directory('../../app/lib').existsSync(),
        isTrue,
        reason: 'scan must cover app/',
      );
      expect(
        constructions.map((p) => p.replaceFirst(RegExp(r':\d+$'), '')).toSet(),
        {
          '../../packages/core_crypto/lib/src/keys.dart',
          '../../packages/core_crypto/lib/src/ceremony.dart',
        },
        reason: 'constructions found at: $constructions',
      );
      expect(
        silenced,
        isEmpty,
        reason: 'an ignore would let app/ mint a verified key',
      );
      // Every seal entry point takes the verified type, not UmkPublic.
      final wrapping = File('lib/src/wrapping.dart').readAsStringSync();
      expect(
        wrapping,
        contains(
          'SealedBlob sealToVerified(\n  CryptoSuite suite,\n  VerifiedUmkPublic to,',
        ),
      );
      // Every sealing call site sits inside a function whose recipient
      // parameter is a Verified* type (04 §8.2 — UMK to a verified guardian or
      // member, UMK to a verified device); opening is not the guarded direction.
      final sealSites = RegExp(r'crypto\.box\.seal\(').allMatches(wrapping);
      // Three since M11: the guardian's re-seal of ADR 2026-09-13c §3 takes
      // `VerifiedRecoveryCandidate`, the candidate type that ruling reserved
      // ("or a verified candidate type built the same way, by ceremony.dart
      // alone"); B-04-85 pins the same rule over every file in lib/src.
      expect(
        sealSites.length,
        3,
        reason:
            'sealToVerified, wrapUmkToDevice and resealShareToCandidate '
            '(ADR 2026-09-13c §3)',
      );
      for (final m in sealSites) {
        final declStart = wrapping.lastIndexOf('\n\n', m.start);
        final decl = wrapping.substring(declStart, m.start);
        expect(
          RegExp(r'Verified(UmkPublic|DevicePublic|RecoveryCandidate) \w+,')
              .hasMatch(decl),
          isTrue,
          reason:
              'seal site at offset ${m.start} not behind a Verified* parameter:\n$decl',
        );
      }

      // Dynamic side: the 04 §7.3 transit at the crypto layer. The share is
      // sealed to a guardian obtained through the real ceremony (helpers), the
      // guardian opens it, and only the verified reconstruction is trusted.
      final s = await testSuite(seed: 79);
      final user = UmkKeyPair.generate(s);
      final guardian1 = UmkKeyPair.generate(s);
      final guardian2 = UmkKeyPair.generate(s);
      final stranger = UmkKeyPair.generate(s);
      for (final k in [user, guardian1, guardian2, stranger]) {
        addTearDown(k.dispose);
      }
      final priv = user.exportSecretBytes();
      final shares = GuardianShareSet.create(
        s,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 1,
      );
      final sealed1 = sealToVerified(
        s,
        verifiedUmk(s, guardian1, userId: userA),
        shares[0].encode(),
      );
      final sealed2 = sealToVerified(
        s,
        verifiedUmk(s, guardian2, userId: userB),
        shares[1].encode(),
      );
      for (final g in shares) {
        g.dispose(); // the splitting device keeps nothing (04 §7.3)
      }
      expect(
        () => openSealed(s, stranger, sealed1),
        throwsA(isA<UnsealFailed>()),
      );
      expect(() => openSealed(s, user, sealed1), throwsA(isA<UnsealFailed>()));
      final opened = [
        GuardianShare.decode(openSealed(s, guardian1, sealed1)),
        GuardianShare.decode(openSealed(s, guardian2, sealed2)),
      ];
      final pair = GuardianShareSet.reconstructVerified(
        s,
        opened,
        expected: verifiedUmk(s, user, userId: userA),
      );
      expect(pair.public, user.public);
      expect(pair.exportSecretBytes(), priv);
      pair.dispose();
      // The same two shares against the wrong pinned key fail closed.
      expect(
        () => GuardianShareSet.reconstructVerified(
          s,
          opened,
          expected: verifiedUmk(s, stranger, userId: userB),
        ),
        throwsA(isA<GuardianShareMismatch>()),
      );
      s.zeroize(priv);
      // `expected` is a VerifiedUmkPublic since ADR 2026-09-13c §1: the
      // provenance question this note once deferred (lane report M7-K2) is
      // ruled on there and pinned by B-04-82/B-04-83; here it is obtained
      // through the real ceremony, as the recovery flow must.
    });

    test('B-04-81 reconstruct refuses a hand-built set that create() never issues — n outside 2..5 or an unknown suite_version — even when the shares are self-consistent; a legitimate 3-of-5 still passes the same checks', () async {
      final s = await testSuite(seed: 80);
      final secret = _secret64();
      // Consistent 4-of-6 Shamir shares wearing guardian headers.
      final six = Shamir.split(s, secret, k: 4, n: 6);
      final bigSet = [
        for (final sh in six)
          GuardianShare(
            suiteVersion: 1,
            shareSetVersion: 9,
            k: 4,
            n: 6,
            index: sh.index,
            bytes: sh.bytes,
          ),
      ];
      expect(
        () => GuardianShareSet.reconstruct(bigSet),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('guardian count'),
          ),
        ),
      );
      expect(
        () => GuardianShareSet.reconstruct(bigSet.take(4).toList()),
        throwsArgumentError,
      );
      // The bytes would have reconstructed — the refusal is policy, and it is
      // what keeps a non-issued set from ever reaching the key check.
      expect(Shamir.combine(six.take(4).toList()), secret);

      // A whole set on an unknown suite_version (decode already refuses one
      // on the wire; this closes the constructor path).
      final legit = GuardianShareSet.create(
        s,
        umkSecret: secret,
        n: 5,
        shareSetVersion: 9,
      );
      final future = [for (final g in legit) _relabel(g, suiteVersion: 0x02)];
      expect(
        () => GuardianShareSet.reconstruct(future.take(3).toList()),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('suite_version'),
          ),
        ),
      );
      expect(
        () => GuardianShare.decode(future[0].encode()),
        throwsFormatException,
      );

      // Same shares, honest headers: fine.
      expect(GuardianShareSet.reconstruct(legit.sublist(1, 4)), secret);
      expect(GuardianPolicy.maxGuardians, 5);
    });
  });
}
