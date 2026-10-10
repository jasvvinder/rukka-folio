// Whose signature a structural record carries — the one judgement
// `LedgerStructuralRequests` adds over the engine's (02 §7.2.1 🔒: *each
// approval is authored on that owner's own device, so the server cannot
// manufacture one*).
//
// Sync proves *which device* signed an envelope (04 §8 rule 3) and sets
// `envelopes_local.verified` once. Which **user** that device belongs to is a
// different claim, and the trust store's map entry is not, on its own, a
// certified answer to it: `CryptoGuard.buildCert` copies the user id from the
// server's `devices` row and 04 §3.4 does not sign it (`DeviceCert` class
// note). A certificate binds a device to a user only while it verifies under
// **that user's** ceremony-verified UMK — the check `ChainVerifier` makes, but
// only at the moment it marks a row verified. Any later meta page can replace
// the entry, and the flag stays 1 (review finding F200I-1). So the chain is
// run again here, over the stored envelope, at every read:
//
//   a certificate for exactly this device → its user has a ceremony-verified
//   UMK → the suite is one this build verifies → the UMK's signature over the
//   device keys holds → **the envelope's own signature holds under those
//   keys** → the device was not revoked before this envelope's `seq`.
//
// The mirror's blob carries the author signature (`nonce ‖ author_sig ‖
// ciphertext`), so the last two steps need nothing the mirror does not keep.
// A server that relabels a member's device as an owner's therefore gets
// *nobody* back, never the owner: the relabelled certificate does not verify
// under the owner's UMK. One that serves a different certificate for the same
// device id gets nobody for every envelope those keys did not sign.
//
// No clock, no I/O, no plaintext; the crypto is libsodium's, through
// `core_crypto` (rule 7) — this file walks no chain of its own.
import 'package:core_crypto/core_crypto.dart';

import 'ledger_structural_requests.dart'
    show OpenedStructuralEnvelope, StructuralSigner;

/// [StructuralSigner] over [trust] — the composition root passes the sync
/// engine's `RecordTrustStore`, the very store `ChainVerifier` read when the
/// row was first verified.
///
/// Answers the certificate's user only when [ChainVerifier.verifyEnvelope]
/// holds for the stored envelope **now** (04 §3.4, §8.3; ADR 2026-09-05b §5).
/// Anything else — no certificate yet (every launch before the meta read), no
/// ceremony, a relabelled or forged certificate, keys that did not sign this
/// envelope, a revocation at or below its `seq` — is null: *this phone cannot
/// say who signed*, never a guess.
StructuralSigner certifiedSignerOf(TrustStore trust, CryptoSuite suite) {
  final chain = ChainVerifier(suite, trust);
  return (OpenedStructuralEnvelope e) {
    final sealed = e.sealed;
    if (sealed == null || sealed.authorDeviceId != e.authorDevice) return null;
    final ChainVerdict verdict;
    try {
      verdict = chain.verifyEnvelope(sealed, seq: e.seq);
    } on Object {
      return null;
    }
    if (verdict is! ChainVerified) return null;
    // The certificate the chain just accepted (no await between the two).
    return trust.certOf(e.authorDevice)?.userId;
  };
}
