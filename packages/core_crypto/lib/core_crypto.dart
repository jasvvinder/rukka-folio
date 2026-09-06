/// Crypto core: envelopes, key hierarchy, wrap/unwrap, sign/verify chain,
/// fingerprints, verification codes, Shamir (04). M3.
///
/// Spec owner: `docs/04-crypto.md`; ADR 2026-09-05b §1, §3, §8 (signed
/// records, `author_seq` in the payload, plaintext padding). Pure Dart — no
/// Flutter, no I/O, no `DateTime.now()`, no `Random()` (CLAUDE.md rule 3;
/// CI-enforced by `scripts/check_purity.sh`). All primitives come from
/// libsodium through `package:sodium` (rule 7); the `Sodium` instance and the
/// random source are injected through [CryptoSuite] so suite B runs
/// deterministically (09 §1).
///
/// Memory hygiene (ADR 2026-09-05 §8): key material lives in `SecureKey` or
/// `Uint8List`, never in a Dart `String`; every holder has `dispose()` which
/// zeroises. Verified keys are a distinct type — a book key can only be sealed
/// to a [VerifiedUmkPublic] (04 §8.2).
library;

export 'src/bytes.dart';
export 'src/ceremony.dart';
export 'src/device_cert.dart';
export 'src/envelope.dart';
export 'src/keys.dart';
export 'src/padding.dart';
export 'src/recovery.dart';
export 'src/shamir.dart';
export 'src/signed_record.dart';
export 'src/suite.dart';
export 'src/verify_chain.dart';
export 'src/wrapping.dart';
