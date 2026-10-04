// The recovery candidate's own X25519 pair, held in the platform key store for
// the life of one attempt (04 §7.3 steps 1–4, ADR 2026-09-24b §1 🔒).
//
// ============================================================================
// WHAT THIS FILE IS FOR
// ============================================================================
//
// 04 §7.3 step 1 reads "fresh device keys **+** a *candidate* X25519 pair".
// ADR 2026-09-24b §1 ruled that the candidate is **its own pair**: minted when
// this device opens an attempt, held in the key store until the attempt
// closes (approved, cancelled, denied or expired), and zeroised after
// `reconstructVerified` and on every close. It never wraps a book key and is
// never registered as a device key, so an abandoned attempt never shares a
// key with the device's identity.
//
// So this file owns exactly one key-store item, [KeyIds.recoveryCandidate],
// and every path through it ends with the secret back in guarded memory or
// gone:
//
//   * the pair itself lives in a `RecoveryCandidateKeyPair` (libsodium
//     guarded memory) only for the length of one call, and is disposed in
//     `finally`;
//   * every buffer read from, or written to, the key store is zeroised in
//     `finally` (the store keeps its own copy, which `delete` zeroises);
//   * the secret never leaves this file. [HttpGuardianRecovery] sees public
//     halves only, through [RecoveryCandidateKeys].
//
// It never touches [KeyIds.deviceAgreementKey] or any other device item: the
// candidate is not this device's `pub_x` and is never written where one would
// be looked for.
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

import '../seams/key_store.dart';
import '../seams/recovery_ladder.dart';
import 'recovery_seams.dart';

/// [RecoveryCandidateKeys] over the platform [KeyStore].
final class KeyStoreRecoveryCandidate implements RecoveryCandidateKeys {
  /// Creates the holder. All crypto is [suite]'s (rule 7): the pair is drawn
  /// from its injected random source, never from `dart:math`.
  KeyStoreRecoveryCandidate({
    required KeyStore keys,
    required CryptoSuite suite,
  }) : _keys = keys,
       _suite = suite;

  final KeyStore _keys;
  final CryptoSuite _suite;

  static const String _id = KeyIds.recoveryCandidate;

  @override
  Future<Uint8List> mint() async {
    final pair = RecoveryCandidateKeyPair.generate(_suite);
    Uint8List? secret;
    try {
      secret = pair.exportSecretBytes();
      // Whatever was held belonged to an earlier attempt, and one attempt's
      // key is never another's: it is deleted (the store zeroises its copy)
      // before the new secret is written.
      await _keys.delete(_id);
      await _keys.write(_id, secret);
      return Uint8List.fromList(pair.x25519);
    } finally {
      if (secret != null) zeroise(secret);
      pair.dispose();
    }
  }

  @override
  Future<Uint8List?> held() async {
    final secret = await _keys.read(_id);
    if (secret == null) return null;
    RecoveryCandidateKeyPair? pair;
    try {
      pair = RecoveryCandidateKeyPair.fromSecretBytes(_suite, secret);
      return Uint8List.fromList(pair.x25519);
    } on ArgumentError {
      // Not 32 bytes, so not a candidate secret: nothing can be sealed to it
      // and nothing is held. The next mint overwrites it; [discard] removes it.
      return null;
    } finally {
      zeroise(secret);
      pair?.dispose();
    }
  }

  @override
  Future<void> discard(Uint8List publicHalf) async {
    final secret = await _keys.read(_id);
    if (secret == null) return;
    RecoveryCandidateKeyPair? pair;
    var remove = false;
    try {
      pair = RecoveryCandidateKeyPair.fromSecretBytes(_suite, secret);
      remove = _suite.constantTimeEquals(pair.x25519, publicHalf);
    } on ArgumentError {
      remove = true; // not a key at all — nothing is lost by removing it
    } finally {
      zeroise(secret);
      pair?.dispose();
    }
    if (remove) await _keys.delete(_id);
  }

  /// 04 §7.3 step 4: opens each re-sealed share with the held pair and
  /// reconstructs `UMK_priv`, **verified** against [expected] — the user's
  /// key as a ceremony produced it, never the server's copy (ADR 2026-09-13c
  /// ruling 1, ADR 2026-09-06 §2). The caller owns the returned [UmkKeyPair]
  /// and must dispose it.
  ///
  /// The held secret is deleted **whichever way this goes** (ADR 2026-09-24b
  /// §1 🔒): on success, because the attempt's work is done; on failure — a
  /// share that does not open (`UnsealFailed`), a reconstruction that does
  /// not re-derive the known key (`GuardianShareMismatch`), too few shares —
  /// because a mismatch is an attack and the ladder fails closed.
  ///
  /// ADR 2026-10-03c §5 reads "zeroised after `reconstructVerified`" as
  /// after *any* reconstruct: a failed one costs a fresh attempt rather
  /// than leaving a key that shares have been tried against.
  ///
  /// With no pair held it throws [RecoveryFailure] and opens nothing.
  Future<UmkKeyPair> reconstruct({
    required List<ResealedShare> shares,
    required VerifiedUmkPublic expected,
  }) async {
    final secret = await _keys.read(_id);
    if (secret == null) throw const RecoveryFailure('no candidate');
    RecoveryCandidateKeyPair? pair;
    final opened = <GuardianShare>[];
    try {
      pair = RecoveryCandidateKeyPair.fromSecretBytes(_suite, secret);
      for (final r in shares) {
        opened.add(openResealedShare(_suite, r, pair));
      }
      return GuardianShareSet.reconstructVerified(
        _suite,
        opened,
        expected: expected,
      );
    } finally {
      zeroise(secret);
      for (final s in opened) {
        s.dispose();
      }
      pair?.dispose();
      await _keys.delete(_id);
    }
  }
}
