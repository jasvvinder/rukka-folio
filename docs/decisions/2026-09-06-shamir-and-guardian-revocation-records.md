# ADR 2026-09-06 — Shamir over GF(256) in-house; guardian revocation as k counted records

**Status: proposed — ⚠️ SPEC: owner to confirm.** Prepared during the M3 crypto-core slice (6 Sep
2026) because 04 §2 and §11.1 leave the Shamir source open ("select an audited package; fallback:
combination wrapping") and ADR 2026-09-05b Open 2 defers the shape of a guardians' k-of-n device
revocation "to M3 with the Shamir choice". Both are implemented as recommended below and are
`⚠️ SPEC`-marked in code; nothing here changes a 🔒 line of 04 — it fills two blanks 04 left.

## Rulings 🔒 (proposed)

### 1. Shamir secret sharing is implemented in-house, over GF(256) ⟦tests: B-04-50, B-04-51, B-04-52, B-04-53, B-04-54, B-04-55, B-04-56, B-04-57, B-04-58, B-04-59, B-04-60, B-04-61, B-04-69⟧
- `packages/core_crypto/lib/src/shamir.dart`: GF(2⁸) with the AES polynomial 0x11b; branch-free
  multiply on the secret path (no table lookup on secret operands), exp/log tables only for the
  public Lagrange basis at x = 0; one polynomial per secret byte, coefficients from the injected
  libsodium RNG in a single draw; shares indexed 1…n. No dependency is added.
- **Why not a package.** A pub.dev audit on 6 Sep 2026 found no Shamir package with any audit or
  security-review statement. The candidates: `sss256` (prime field despite the name, `String`
  secrets, `dart:math`, SDK < 3), `ntcdcrypto` (prime field, `String`, `Random.secure()`),
  `slip39` (GF(256) but mnemonic-shaped and pulls `pinenacl`, a second crypto stack beside
  libsodium — against 04 §2), `shamir_secret_plg` (Flutter plugin — forbidden in `packages/`),
  `dart_ssss` (Dart 2). None is Flutter-free *and* GF(256) *and* uses injected randomness.
- **Why not combination wrapping.** It costs C(n,k) sealed copies of the whole UMK — 1/3/6/4/10/10/5/1
  for the allowed (k,n) — and each copy needs a multi-recipient sealing scheme libsodium also lacks,
  so it trades one small reviewed file for a larger unreviewed one.
- Residual risk is implementation error, not primitive weakness; it is bounded by FIPS-197 known
  answers, an exhaustive table-versus-loop cross-check over all 65,536 products, the enumerated
  k-subset reconstruction for n ≤ 5, the k−1 zero-information proof (B-04-55) and a shrinking
  property test. **An external one-hour review of this single file is requested before M14.**

### 2. Guardian shares carry `share_set_version`; a set is n ∈ 2..5 with k = ⌈(n+1)/2⌉ by default ⟦tests: B-04-62, B-04-63, B-04-64, B-04-65, B-04-66, B-04-67, B-04-68⟧
- Wire form of one share (before sealing to the guardian's verified UMK, 04 §7.3 step "seal share_i"):
  `u8(suite_version) ‖ u32be(share_set_version) ‖ u8(k) ‖ u8(n) ‖ u8(index) ‖ share bytes`.
- Reconstruction refuses shares of mixed `share_set_version` (a re-split after a guardian change
  supersedes the old set), fewer than k, duplicate indices, or metadata that disagrees. 2-of-2 is
  permitted; the data-loss warning is the UI's (04 §7.3, 04 §11.3 stays open for the owner).
- No integrity check at this layer: a tampered share yields a wrong secret silently. Integrity rests
  on the sealed-box transit (04 §7.3 step 3) and the chain of 04 §3.4. ⚠️ If the owner wants
  detection at reconstruction, add `BLAKE2b-256(UMK_priv)` beside the share set (not in 04 today).

### 3. Guardians' k-of-n device revocation = k separate signed records, counted by the client ⟦tests: n/a — lands with signed-record application at M4 (suite D)⟧
- Each approving guardian's device authors its own `device_revocation` `SignedRecord`
  (ADR 2026-09-05b §1) over the same body `{revoked_device_id, subject_user_id, share_set_version}`;
  readers count distinct verified guardian authors whose UMKs are in the subject's *current*
  guardian set (pinned by `share_set_version`) and treat the revocation as effective at the
  **`seq` of the k-th record** — that `seq` is the cut-off of ADR 05b §5.
- **Why not a multi-signature record.** libsodium ships no threshold signature; Shamir here splits
  the UMK, not a signing key, and reconstructing the UMK to sign a revocation is exactly what a
  revocation must never require. A single record carrying k signatures needs someone online to
  assemble it (a coordination round with a partial-state failure mode); k independent records need
  no coordination, work asynchronously, and reuse the existing chain verifier unchanged.
- The server stores records; it needs no new logic beyond ADR 05b §1's application to rows, and its
  row is, as always, only a projection the client verifies.

## Consequences
- Code: `core_crypto/shamir.dart` (M3, landed); `SignedRecordKind.deviceRevocation` (M3, landed);
  counting logic in `sync_engine` at M4; guardian-set pinning needs the current `share_set_version`
  in the meta channel (05 §5) at M4.
- Docs (on ratification): 04 §2 Shamir row → "in-house GF(256), `core_crypto/shamir.dart`; no
  audited package exists; combination wrapping not adopted"; 04 §11.1 closed; 04 §9.2 gains the
  k-records sentence; ADR 2026-09-05b Open 2 closed; 03 §3.1 `signed_records_local` unchanged.
- Milestone: M3 (rulings 1–2), M4 (ruling 3).

## Open ⚠️
- Owner to ratify (status *proposed*). Until then the code stands as `⚠️ SPEC` and the 04 markers
  point at these tests.
- 04 §11.3 (guardian minimum at launch: allow 2-of-2 or require ≥ 3) is still the owner's.
- External review of `shamir.dart` before M14 (ruling 1).
