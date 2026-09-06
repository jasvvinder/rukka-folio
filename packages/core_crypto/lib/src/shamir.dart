// Shamir secret sharing over GF(256) and the guardian share set (04 §2, §7.3).
//
// Owner: docs/04-crypto.md. This module produces and consumes share *bytes*
// only; sealing a share to a guardian's verified UMK (04 §7.3 "seal share_i to
// guardian i's UMK public key") is the ceremony/wrapping module's job.
import 'dart:typed_data';

import 'bytes.dart';
import 'keys.dart';
import 'suite.dart';

/// The library-level [suiteVersion], reachable from inside [GuardianShare]
/// where the field of the same name shadows it.
const int _currentSuiteVersion = suiteVersion;

/// Arithmetic in GF(2^8) with the AES reduction polynomial
/// x^8 + x^4 + x^3 + x + 1 (`0x11b`), as used by every GF(256) Shamir scheme
/// in the wild (SLIP-39, HashiCorp Vault, `libgfshare`), so shares produced
/// here are interoperable with any of them given the same encoding.
///
/// Two multiplication paths, chosen deliberately:
///
/// * [mul] is a **branch-free shift-and-reduce loop** (8 rounds, masks instead
///   of `if`s, no data-dependent memory access). It is the one that touches
///   secret operands — polynomial coefficients on split, share bytes on
///   combine — so it must not leak them through cache timing. Constant-time in
///   the Dart VM is best effort (the JIT may still specialise), but a
///   table-free loop is the strongest we can do in pure Dart, and the cost is
///   irrelevant here: a 64-byte UMK split into ≤ 5 shares is a few thousand
///   multiplications.
/// * [exp] / [log] tables (generator 3, built once at library init) back
///   [inverse] and [mulTable], which are only ever applied to **public** values —
///   share indices `x` — when forming the Lagrange basis at `x = 0`. They also
///   serve as an independent cross-check of [mul] in the test vectors.
abstract final class Gf256 {
  /// The reduction polynomial, `x^8 + x^4 + x^3 + x + 1`.
  static const int polynomial = 0x11b;

  /// `exp[i] = 3^i` for `i` in `0..254` — every non-zero element once.
  static final Uint8List exp = _tables.$1;

  /// `log[a]` such that `exp[log[a]] = a` for `a ≠ 0`; `log[0]` is unused (0).
  static final Uint8List log = _tables.$2;

  static final (Uint8List, Uint8List) _tables = _buildTables();

  static (Uint8List, Uint8List) _buildTables() {
    final e = Uint8List(255);
    final l = Uint8List(256);
    var x = 1;
    for (var i = 0; i < 255; i++) {
      e[i] = x;
      l[x] = i;
      // x *= 3  ==  x ^ (x·2), with x·2 reduced by 0x11b when bit 7 is set.
      x = x ^ _xtime(x);
    }
    return (e, l);
  }

  /// `a · x` in GF(2^8), branch-free: the reduction term is selected by a mask
  /// derived from bit 7 rather than by a conditional.
  static int _xtime(int a) {
    final shifted = a << 1;
    final mask = -((shifted >> 8) & 1); // 0 or -1 (all ones)
    return (shifted ^ (polynomial & mask)) & 0xff;
  }

  /// Addition (and subtraction) in GF(2^8) is XOR.
  static int add(int a, int b) => a ^ b;

  /// Product of [a] and [b], branch-free (see the class comment for why).
  static int mul(int a, int b) {
    var result = 0;
    var x = a & 0xff;
    var y = b & 0xff;
    for (var i = 0; i < 8; i++) {
      // Add x to the result iff the low bit of y is set, via a mask.
      result ^= x & -(y & 1);
      x = _xtime(x);
      y >>= 1;
    }
    return result;
  }

  /// Multiplicative inverse of a **public**, non-zero [a] (table lookup —
  /// never call this with secret data). Throws [ArgumentError] on zero.
  static int inverse(int a) {
    if (a == 0) throw ArgumentError.value(a, 'a', 'zero has no inverse');
    return exp[(255 - log[a & 0xff]) % 255];
  }

  /// Product via the tables — public operands only. Exposed so tests can
  /// cross-check [mul] against an independent construction.
  static int mulTable(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return exp[(log[a & 0xff] + log[b & 0xff]) % 255];
  }
}

/// One Shamir share: the point `(index, bytes)` — `bytes[j]` is the evaluation
/// at `x = index` of the polynomial whose constant term is secret byte `j`.
///
/// [threshold] is carried when the producer knows it ([Shamir.split] sets it)
/// so [Shamir.combine] can refuse an under-threshold attempt instead of
/// returning a wrong secret; it is `null` for shares of unknown provenance.
final class ShamirShare {
  /// Creates a share; [bytes] are copied.
  ShamirShare({required this.index, required Uint8List bytes, this.threshold})
    : bytes = Uint8List.fromList(bytes) {
    if (index < 1 || index > 255) {
      throw ArgumentError.value(index, 'index', 'must be in 1..255');
    }
    if (bytes.isEmpty) throw ArgumentError.value(bytes, 'bytes', 'empty');
    if (threshold != null && (threshold! < 2 || threshold! > 255)) {
      throw ArgumentError.value(threshold, 'threshold', 'must be in 2..255');
    }
  }

  /// The x-coordinate, `1 ≤ index ≤ 255`. `x = 0` is the secret itself and is
  /// never a share.
  final int index;

  /// One y byte per secret byte.
  final Uint8List bytes;

  /// The `k` this share was produced under, when known.
  final int? threshold;

  /// Overwrites [bytes] with zeros (04 §7.3 step 4, 04 §8.1).
  void dispose() => bytes.fillRange(0, bytes.length, 0);
}

/// Shamir's scheme over GF(256): split a byte string into `n` shares any `k`
/// of which reconstruct it, while any `k − 1` reveal nothing (04 §2).
///
/// No `dart:math`, no `Random()`: every coefficient comes from
/// [CryptoSuite.randomBytes] (rule 7, 04 §8.4), so a seeded suite yields
/// byte-identical shares run after run (09 §1).
abstract final class Shamir {
  /// Splits [secret] into [n] shares with threshold [k].
  ///
  /// One random polynomial of degree `k − 1` per secret byte, with the secret
  /// byte as its constant term; share `i` (`x = i`, `1 ≤ i ≤ n`) holds one
  /// evaluation per byte. **All coefficients are drawn in a single
  /// `randomBytes(secret.length · (k − 1))` call** — one draw per split — so
  /// the mapping from the injected stream to shares is fixed and deterministic
  /// under a seeded suite. The coefficient buffer is zeroised in `finally`.
  ///
  /// Requires `2 ≤ k ≤ n ≤ 255` and a non-empty secret. `k = 1` is refused:
  /// it is no threshold at all — every share *is* the secret.
  static List<ShamirShare> split(
    CryptoSuite suite,
    Uint8List secret, {
    required int k,
    required int n,
  }) {
    if (secret.isEmpty) {
      throw ArgumentError.value(secret, 'secret', 'must not be empty');
    }
    if (k < 2) {
      throw ArgumentError.value(
        k,
        'k',
        'threshold must be ≥ 2 (k = 1 is no threshold)',
      );
    }
    if (n > 255) throw ArgumentError.value(n, 'n', 'at most 255 shares');
    if (k > n) {
      throw ArgumentError.value(k, 'k', 'threshold exceeds share count $n');
    }

    final degree = k - 1;
    final len = secret.length;
    // coefficients[j * degree + t] = coefficient of x^(t+1) for secret byte j.
    final coefficients = suite.randomBytes(len * degree);
    final ys = List<Uint8List>.generate(n, (_) => Uint8List(len));
    try {
      for (var j = 0; j < len; j++) {
        final base = j * degree;
        for (var i = 1; i <= n; i++) {
          // Horner: start from the top coefficient, multiply by x, add next.
          var y = coefficients[base + degree - 1];
          for (var t = degree - 2; t >= 0; t--) {
            y = Gf256.mul(y, i) ^ coefficients[base + t];
          }
          y = Gf256.mul(y, i) ^ secret[j];
          ys[i - 1][j] = y;
        }
      }
      return List<ShamirShare>.generate(
        n,
        (i) => ShamirShare(index: i + 1, bytes: ys[i], threshold: k),
      );
    } finally {
      suite.zeroize(coefficients);
      for (final y in ys) {
        suite.zeroize(y); // ShamirShare copied them
      }
    }
  }

  /// Reconstructs the secret from [shares] by Lagrange interpolation at `x = 0`.
  ///
  /// Refuses an empty list, duplicate indices, mismatched lengths, and — when
  /// any share carries a [ShamirShare.threshold] — disagreeing thresholds or
  /// fewer shares than that threshold. Every share given is used: with `m ≥ k`
  /// consistent shares the interpolation is exact, and with an inconsistent
  /// (tampered) share the result is wrong either way — this layer has no
  /// integrity check; the sealed transit of 04 §7.3 step 3 provides it.
  /// The caller owns and must zeroise the returned bytes.
  static Uint8List combine(List<ShamirShare> shares) {
    if (shares.isEmpty) throw ArgumentError.value(shares, 'shares', 'empty');
    final len = shares.first.bytes.length;
    int? threshold;
    final seen = <int>{};
    for (final s in shares) {
      if (s.bytes.length != len) {
        throw ArgumentError.value(shares, 'shares', 'mismatched share lengths');
      }
      if (!seen.add(s.index)) {
        throw ArgumentError.value(
          shares,
          'shares',
          'duplicate index ${s.index}',
        );
      }
      if (s.threshold != null) {
        if (threshold != null && threshold != s.threshold) {
          throw ArgumentError.value(
            shares,
            'shares',
            'shares declare different thresholds',
          );
        }
        threshold = s.threshold;
      }
    }
    if (threshold != null && shares.length < threshold) {
      throw ArgumentError.value(
        shares,
        'shares',
        'need $threshold shares to reconstruct, got ${shares.length}',
      );
    }

    // Lagrange basis at x = 0 over the (public) indices:
    //   L_i(0) = Π_{j≠i} x_j / (x_j − x_i) = Π_{j≠i} x_j / (x_j ⊕ x_i).
    final m = shares.length;
    final basis = Uint8List(m);
    for (var i = 0; i < m; i++) {
      var num = 1;
      var den = 1;
      final xi = shares[i].index;
      for (var j = 0; j < m; j++) {
        if (j == i) continue;
        final xj = shares[j].index;
        num = Gf256.mulTable(num, xj);
        den = Gf256.mulTable(den, xj ^ xi);
      }
      basis[i] = Gf256.mulTable(num, Gf256.inverse(den));
    }

    final out = Uint8List(len);
    for (var b = 0; b < len; b++) {
      var acc = 0;
      for (var i = 0; i < m; i++) {
        acc ^= Gf256.mul(shares[i].bytes[b], basis[i]); // secret operand → mul
      }
      out[b] = acc;
    }
    return out;
  }
}

/// Guardian thresholds (04 §7.3): allowed `n = 2..5`, `k = ⌈(n + 1) / 2⌉`.
abstract final class GuardianPolicy {
  /// Smallest guardian count.
  static const int minGuardians = 2;

  /// Largest guardian count.
  static const int maxGuardians = 5;

  /// `⌈(n + 1) / 2⌉`: 2→2, 3→2, 4→3, 5→3. Throws [ArgumentError] outside
  /// `2..5`. 2-of-2 is permitted; the data-loss warning is the UI's (04 §7.3).
  static int defaultThreshold(int n) {
    if (n < minGuardians || n > maxGuardians) {
      throw ArgumentError.value(
        n,
        'n',
        'guardian count must be in $minGuardians..$maxGuardians',
      );
    }
    return (n + 2) ~/ 2;
  }
}

/// One guardian's share of `UMK_priv` with its metadata (04 §7.3), before
/// sealing to that guardian's verified UMK public key.
///
/// Wire form ([encode]):
/// `u8(suite_version) ‖ u32be(share_set_version) ‖ u8(k) ‖ u8(n) ‖ u8(index) ‖ bytes`
/// — 8 header bytes, then the share. `share_set_version` changes on every
/// re-split (guardian change or UMK rotation) so shares from two generations
/// can never be combined (04 §7.3).
final class GuardianShare {
  /// Creates a share; [bytes] are copied. Validates `2 ≤ k ≤ n ≤ 255`,
  /// `1 ≤ index ≤ n`, a non-empty payload and a u32 `shareSetVersion`.
  GuardianShare({
    required this.suiteVersion,
    required this.shareSetVersion,
    required this.k,
    required this.n,
    required this.index,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes) {
    if (suiteVersion < 0 || suiteVersion > 0xff) {
      throw ArgumentError.value(suiteVersion, 'suiteVersion', 'not a byte');
    }
    if (shareSetVersion < 0 || shareSetVersion > 0xffffffff) {
      throw ArgumentError.value(
        shareSetVersion,
        'shareSetVersion',
        'not a u32',
      );
    }
    if (k < 2 || n > 255 || k > n) {
      throw ArgumentError.value((k, n), '(k, n)', 'need 2 ≤ k ≤ n ≤ 255');
    }
    if (index < 1 || index > n) {
      throw ArgumentError.value(index, 'index', 'must be in 1..$n');
    }
    if (bytes.isEmpty) throw ArgumentError.value(bytes, 'bytes', 'empty');
  }

  /// Length of the fixed header in front of the share bytes.
  static const int headerLength = 1 + 4 + 1 + 1 + 1;

  /// Parses [encode]'s output. Throws [FormatException] on a short buffer or
  /// an unknown `suite_version`, [ArgumentError] on inconsistent metadata.
  // ⚠️ SPEC: 04 §8.5 says old suites stay readable ≥ 2 years; with only 0x01
  // defined so far, any other value is unknown and refused rather than parsed
  // under assumptions. Revisit when a 0x02 exists.
  factory GuardianShare.decode(Uint8List encoded) {
    if (encoded.length <= headerLength) {
      throw FormatException(
        'guardian share needs more than $headerLength bytes, got ${encoded.length}',
      );
    }
    final suite = encoded[0];
    if (suite != _currentSuiteVersion) {
      throw FormatException('unknown suite_version $suite');
    }
    final version = encoded.buffer
        .asByteData(encoded.offsetInBytes, encoded.length)
        .getUint32(1);
    return GuardianShare(
      suiteVersion: suite,
      shareSetVersion: version,
      k: encoded[5],
      n: encoded[6],
      index: encoded[7],
      bytes: Uint8List.sublistView(encoded, headerLength),
    );
  }

  /// `suite_version` (04 §2 crypto agility).
  final int suiteVersion;

  /// Generation of the split this share belongs to (04 §7.3).
  final int shareSetVersion;

  /// Threshold.
  final int k;

  /// Share count.
  final int n;

  /// This guardian's x-coordinate, `1..n`.
  final int index;

  /// The Shamir share bytes — as secret as the UMK itself until sealed.
  final Uint8List bytes;

  /// Canonical wire bytes; see the class comment for the layout.
  Uint8List encode() => Bytes.concat([
    Bytes.u8(suiteVersion),
    Bytes.u32be(shareSetVersion),
    Bytes.u8(k),
    Bytes.u8(n),
    Bytes.u8(index),
    bytes,
  ]);

  /// The bare Shamir point, threshold attached.
  ShamirShare toShamirShare() =>
      ShamirShare(index: index, bytes: bytes, threshold: k);

  /// Overwrites [bytes] with zeros (04 §7.3 step 4).
  void dispose() => bytes.fillRange(0, bytes.length, 0);
}

/// The bytes reconstructed from k guardian shares do not re-derive the UMK
/// public key the recovering device already knows (04 §7.3 steps 4–5; ADR
/// 2026-09-06 §2). Raised by [GuardianShareSet.reconstructVerified] after the
/// bytes have been zeroised; nothing about *which* share was wrong is known
/// at this layer — the UI re-requests shares.
final class GuardianShareMismatch implements Exception {
  /// Creates the failure.
  const GuardianShareMismatch();

  @override
  String toString() =>
      'GuardianShareMismatch(reconstructed UMK does not match the known public key)';
}

/// Splitting `UMK_priv` for guardians and putting it back together (04 §7.3).
///
/// Deliberately stateless — static functions only — so there is no object
/// that could retain the reconstructed secret: the caller receives the bytes
/// from [reconstruct] and must zeroise them (04 §7.3 step 4).
abstract final class GuardianShareSet {
  /// Splits [umkSecret] (the 64-byte `UMK_priv` export) into [n] guardian
  /// shares under [shareSetVersion]. [k] defaults to
  /// [GuardianPolicy.defaultThreshold]; an explicit [k] must satisfy
  /// `2 ≤ k ≤ n`. [n] must be in `2..5` (04 §7.3; 2-of-2 permitted).
  static List<GuardianShare> create(
    CryptoSuite suite, {
    required Uint8List umkSecret,
    required int n,
    int? k,
    required int shareSetVersion,
  }) {
    final threshold = k ?? GuardianPolicy.defaultThreshold(n);
    if (n < GuardianPolicy.minGuardians || n > GuardianPolicy.maxGuardians) {
      throw ArgumentError.value(n, 'n', 'guardian count must be in 2..5');
    }
    if (threshold < 2 || threshold > n) {
      throw ArgumentError.value(threshold, 'k', 'need 2 ≤ k ≤ n ($n)');
    }
    final shares = Shamir.split(suite, umkSecret, k: threshold, n: n);
    try {
      return [
        for (final s in shares)
          GuardianShare(
            suiteVersion: suiteVersion,
            shareSetVersion: shareSetVersion,
            k: threshold,
            n: n,
            index: s.index,
            bytes: s.bytes,
          ),
      ];
    } finally {
      for (final s in shares) {
        s.dispose();
      }
    }
  }

  /// Reconstructs `UMK_priv` from at least `k` guardian shares of one
  /// generation. Refuses shares from different `share_set_version`s (a re-split
  /// after a guardian change — 04 §7.3), differing `(suite, k, n)`, duplicate
  /// indices and fewer than `k` shares. The caller zeroises the result.
  static Uint8List reconstruct(List<GuardianShare> shares) {
    if (shares.isEmpty) throw ArgumentError.value(shares, 'shares', 'empty');
    final first = shares.first;
    for (final s in shares.skip(1)) {
      if (s.shareSetVersion != first.shareSetVersion) {
        throw ArgumentError.value(
          shares,
          'shares',
          'share_set_version mismatch (${first.shareSetVersion} vs ${s.shareSetVersion}) — '
              'shares from different splits cannot be combined',
        );
      }
      if (s.suiteVersion != first.suiteVersion ||
          s.k != first.k ||
          s.n != first.n) {
        throw ArgumentError.value(
          shares,
          'shares',
          'suite/k/n metadata mismatch',
        );
      }
    }
    if (shares.length < first.k) {
      throw ArgumentError.value(
        shares,
        'shares',
        'need ${first.k} guardian shares, got ${shares.length}',
      );
    }
    final points = [for (final s in shares) s.toShamirShare()];
    try {
      return Shamir.combine(points);
    } finally {
      for (final p in points) {
        p.dispose();
      }
    }
  }

  /// [reconstruct], then proves the result is the right UMK before anyone
  /// trusts it: the 64 bytes re-derive both public halves, which must equal
  /// [expected] — the UMK public key the recovering device already holds for
  /// this user (it is in every device certificate and wrapped-key row, 04 §3.1,
  /// §3.4). Plain [reconstruct] cannot tell a tampered or mis-sealed share
  /// from a good one (B-04-57); this can, with no field added to the share set
  /// and no new primitive (ADR 2026-09-06 §2).
  ///
  /// On mismatch the reconstructed bytes are zeroised, the derived pair is
  /// disposed and [GuardianShareMismatch] is thrown. On success the caller
  /// owns the returned [UmkKeyPair] (secrets in guarded memory) and must
  /// [UmkKeyPair.dispose] it; the intermediate bytes are already zeroised
  /// (04 §7.3 step 4).
  static UmkKeyPair reconstructVerified(
    CryptoSuite suite,
    List<GuardianShare> shares, {
    required UmkPublic expected,
  }) {
    final secret = reconstruct(shares);
    UmkKeyPair? pair;
    try {
      pair = UmkKeyPair.fromSecretBytes(suite, secret);
      final ok =
          suite.constantTimeEquals(pair.public.x25519, expected.x25519) &&
          suite.constantTimeEquals(pair.public.ed25519, expected.ed25519);
      if (!ok) {
        pair.dispose();
        throw const GuardianShareMismatch();
      }
      return pair;
    } on ArgumentError {
      // Not 64 bytes — cannot be a UMK; treat as a mismatch, not a bug.
      throw const GuardianShareMismatch();
    } finally {
      suite.zeroize(secret);
    }
  }
}
