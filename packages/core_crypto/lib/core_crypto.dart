/// Crypto core: envelopes, key hierarchy, wrap/unwrap, sign/verify chain, fingerprints, Shamir (04). M3.
///
/// Spec owner: `docs/04-crypto.md`. Pure Dart — no Flutter, and for `core_*`
/// no I/O, no `DateTime.now()`, no `Random()` (CLAUDE.md rule 3; CI-enforced by
/// `scripts/check_purity.sh`).
library;

/// Package identity used by the M0 hello-world gate. Real API lands per milestone.
const String packageName = 'core_crypto';
