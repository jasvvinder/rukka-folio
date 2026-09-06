import 'dart:typed_data';

import 'package:sodium/sodium.dart';

/// Source of random bytes. Production: libsodium's CSPRNG
/// (`sodium.randombytes.buf`, 04 §2, §8.4). Tests: a deterministic stream.
typedef RandomBytes = Uint8List Function(int length);

/// Current `suite_version` (04 §2): `0x01` = XChaCha20-Poly1305 · X25519 sealed
/// box · Ed25519 · BLAKE2b-256 · Shamir over GF(256). Every stored artefact
/// carries it; old suites stay readable for ≥ 2 years (04 §8.5).
const int suiteVersion = 0x01;

/// The one injection point for libsodium and randomness.
///
/// Everything in `core_crypto` takes a [CryptoSuite]; nothing reaches for
/// `SodiumInit`, the clock or `dart:math`. Key generation draws seeds from
/// [randomBytes] and derives pairs with libsodium's `seedKeyPair`, so a seeded
/// suite produces byte-identical keys, nonces and ciphertexts run after run.
final class CryptoSuite {
  /// Creates a suite over an initialised [sodium]. [random] defaults to
  /// libsodium's CSPRNG and must only be overridden by tests.
  CryptoSuite(this.sodium, {RandomBytes? random})
    : _random = random ?? sodium.randombytes.buf;

  /// The libsodium binding.
  final Sodium sodium;

  final RandomBytes _random;

  /// [length] random bytes from the injected source.
  Uint8List randomBytes(int length) {
    final out = _random(length);
    if (out.length != length) {
      throw StateError('random source returned ${out.length} of $length bytes');
    }
    return out;
  }

  /// A fresh [SecureKey] of [length] random bytes (libsodium guarded memory).
  SecureKey randomSecureKey(int length) {
    final bytes = randomBytes(length);
    try {
      return sodium.secureCopy(bytes);
    } finally {
      zeroize(bytes);
    }
  }

  /// BLAKE2b-256 of [message] (04 §2 — hashing and fingerprints).
  Uint8List blake2b256(Uint8List message) =>
      sodium.crypto.genericHash(message: message, outLen: 32);

  /// Constant-time equality (`sodium_memcmp`); false on length mismatch.
  bool constantTimeEquals(Uint8List a, Uint8List b) =>
      a.length == b.length && sodium.memcmp(a, b);

  /// Overwrites [bytes] with zeros (04 §8.1). Dart cannot pin memory, so this
  /// is best effort; long-lived secrets belong in [SecureKey].
  void zeroize(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
}
