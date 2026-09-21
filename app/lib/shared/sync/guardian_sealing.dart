// The split itself (04 §7.3 🔒): `UMK_priv` into n Shamir shares, one sealed
// to each guardian's ceremony-verified UMK.
//
// It lives in its own file for the reason `recovery_seams.dart` keeps
// `RecoveryResealer` injected: the repository that talks to the server then
// holds no key material at all, and "no share crosses the seam" is a fact you
// can check by grepping for a UMK in `guardians_seams.dart` and finding none.
// This is the only file in `shared/sync` that touches one.
//
// Everything cryptographic is `core_crypto`'s — `GuardianShareSet.create`
// (Shamir over GF(256), coefficients from the injected libsodium CSPRNG, rule
// 7) and `sealToVerified` (`crypto_box_seal` to a [VerifiedUmkPublic], 04
// §8.2 🔒). This file adds no primitive, chooses no randomness and makes no
// policy: `k` and the generation arrive in the request, already decided.
//
// **Memory hygiene** (04 §8 rule 1, ADR 2026-09-05 §8): the exported UMK
// secret, every share and every encoded share buffer are zeroised in
// `finally`, including on the failure paths — a refused seal must not leave
// share bytes on the heap. Nothing is retained: the sealer keeps no field
// holding a share, and the caller forwards the sealed boxes once.
//
// **What is sealed** is `GuardianShare.encode()` — `suite ‖ share_set_version
// ‖ k ‖ n ‖ index ‖ bytes`. That is exactly what the guardian's device
// expects at recovery time: `resealShareToCandidate` opens its stored blob
// and calls `GuardianShare.decode` on the plaintext (04 §7.3 step 3). The
// recipient fingerprint is not uploaded and does not need to be — the
// guardian is the recipient and derives it from its own UMK.
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

import 'guardians_seams.dart';

/// Where the UMK comes from at the moment of a split.
///
/// A function, not a field: the ledger owns the key pair's lifetime, and this
/// file must not outlive or retain it.
typedef UmkSource = UmkKeyPair Function();

/// The production [GuardianShareSealer].
final class CryptoGuardianSealer {
  /// Creates the sealer over [suite] and [umk].
  const CryptoGuardianSealer({
    required CryptoSuite suite,
    required UmkSource umk,
  }) : _suite = suite,
       _umk = umk;

  final CryptoSuite _suite;
  final UmkSource _umk;

  /// Splits and seals. Usable directly as a [GuardianShareSealer].
  Future<List<SealedGuardianShare>> call(GuardianSplitRequest request) async {
    // A fresh split every time — never a reuse of the previous generation's
    // shares (04 §7.3: re-split on any guardian change or UMK rotation).
    final secret = _umk().exportSecretBytes();
    var shares = const <GuardianShare>[];
    try {
      shares = GuardianShareSet.create(
        _suite,
        umkSecret: secret,
        n: request.n,
        k: request.k,
        shareSetVersion: request.shareSetVersion,
      );
      final out = <SealedGuardianShare>[];
      for (var i = 0; i < shares.length; i++) {
        final Uint8List encoded = shares[i].encode();
        try {
          out.add(
            SealedGuardianShare(
              guardian: request.guardians[i],
              // The recipient is the guardian's *verified* key: there is no
              // overload of this call that takes bare key bytes (rule 5).
              blob: sealToVerified(_suite, request.guardians[i].umk, encoded),
            ),
          );
        } finally {
          _suite.zeroize(encoded);
        }
      }
      return out;
    } finally {
      for (final s in shares) {
        s.dispose();
      }
      _suite.zeroize(secret);
    }
  }
}
