# ADR 2026-09-06 — Shamir over GF(256) in-house; guardian revocation as k counted records

**Status: accepted — ratified by the owner 7 Sep 2026 (four checklist answers below).** Prepared during the M3 crypto-core slice (6 Sep
2026) because 04 §2 and §11.1 leave the Shamir source open ("select an audited package; fallback:
combination wrapping") and ADR 2026-09-05b Open 2 defers the shape of a guardians' k-of-n device
revocation "to M3 with the Shamir choice". Both are implemented as recommended below and are
`⚠️ SPEC`-marked in code; nothing here changes a 🔒 line of 04 — it fills two blanks 04 left.
Reviewed the same evening: §2 gained verified reconstruction (no new field), §3 gained the two
rulings a counting scheme needs (cut-off direction, re-split), ids reserved for M4, and a
ratification checklist for the owner at the end.

## Rulings 🔒

### 1. Shamir secret sharing is implemented in-house, over GF(256) ⟦tests: B-04-50, B-04-51, B-04-52, B-04-53, B-04-54, B-04-55, B-04-56, B-04-57, B-04-58, B-04-59, B-04-60, B-04-61, B-04-69, B-04-73⟧
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
  k-subset reconstruction for n ≤ 5, the k−1 zero-information proof (B-04-55), a shrinking
  property test, and — because every other test is self-consistent (split, then combine with the
  same code) — a **known-answer vector from a second, table-free implementation**
  (`test/vectors/shamir_ref.py`; B-04-73 replays both the combine side and, through a scripted
  RNG, the split side byte for byte). **An external one-hour review of this single file is
  requested before M14**; a third-party vector (libgfshare, Vault) pasted in beforehand would
  shorten it.

### 2. Guardian shares carry `share_set_version`; a set is n ∈ 2..5 with k = ⌈(n+1)/2⌉ by default ⟦tests: B-04-62, B-04-63, B-04-64, B-04-65, B-04-66, B-04-67, B-04-68, B-04-72⟧
- Wire form of one share (before sealing to the guardian's verified UMK, 04 §7.3 step "seal share_i"):
  `u8(suite_version) ‖ u32be(share_set_version) ‖ u8(k) ‖ u8(n) ‖ u8(index) ‖ share bytes`.
- Reconstruction refuses shares of mixed `share_set_version` (a re-split after a guardian change
  supersedes the old set), fewer than k, duplicate indices, or metadata that disagrees. 2-of-2 is
  permitted only behind a typed confirmation, not a dismissible warning (ruling 4; 04 §7.3, 04 §11.3 closed).
- **Integrity at reconstruction comes from the key itself, not from a new field.** Shamir has no
  integrity of its own — a tampered share yields a wrong secret silently (B-04-57) — but the
  recovered 64 bytes re-derive both UMK public halves, and the recovering device already holds
  the user's UMK public key (it is in every device certificate and wrapped-key row, 04 §3.1,
  §3.4). `GuardianShareSet.reconstructVerified` compares them in constant time and fails closed:
  `GuardianShareMismatch`, bytes zeroised, nothing about *which* share was bad (the UI
  re-requests). The recovery flow (M11) calls only the verified form; the raw `reconstruct` stays
  for tests. A `BLAKE2b-256(UMK_priv)` beside the share set — the option first written here — is
  not adopted: a digest travelling with the shares can be replaced with them; the pinned public
  key cannot. Transit integrity is still the sealed box (04 §7.3 step 3).

### 3. Guardians' k-of-n device revocation = k separate signed records, counted by the client ⟦tests: D-06a-1, D-06a-2, D-06a-3, D-06a-4⟧
- Each approving guardian's device authors its own `device_revocation` `SignedRecord`
  (ADR 2026-09-05b §1) over the same body `{revoked_device_id, subject_user_id, share_set_version}`;
  readers count distinct verified guardian authors whose UMKs are in the subject's guardian set
  *at the `share_set_version` the record names* and treat the revocation as effective at the
  **`seq` of the k-th record** — that `seq` is the cut-off of ADR 05b §5.
- **The cut-off can only move earlier, and readers must expect it to.** The effective `seq` is the
  k-th smallest among counted records, so a late-arriving approval with a lower `seq` moves the
  cut-off *back*, and envelopes accepted meanwhile are re-quarantined on the next Recompute. This
  is the conservative direction (evidence never weakens a revocation) and it is the same on every
  device regardless of arrival order; the alternative — freeze at the first-observed k-th record —
  diverges between clients. Consequence for M4: the cut-off is a derived value, recomputed from
  the record set, never cached as final; the projector already recomputes from ordered envelopes.
  ⟦tests: D-06a-1, D-06a-2⟧
- **A re-split does not reset the count.** The device under revocation is, by definition, still
  certified — it can change the guardian set and bump `share_set_version`. If approvals were
  pinned to the *current* version it could discard k−1 collected approvals indefinitely. So:
  a record counts if its author was a guardian at the version it names, approvals for the same
  `revoked_device_id` carry across versions, and the threshold applied is the k of the *earliest*
  version among the counted records (a bump cannot raise the bar mid-revocation). A guardian
  removed by a bump keeps the approval already authored and can author no new one.
  Ratified as *earliest-k* (checklist 3); the current-k alternative was not taken.
  ⟦tests: D-06a-3, D-06a-4⟧
- **Why not a multi-signature record.** libsodium ships no threshold signature; Shamir here splits
  the UMK, not a signing key, and reconstructing the UMK to sign a revocation is exactly what a
  revocation must never require. A single record carrying k signatures needs someone online to
  assemble it (a coordination round with a partial-state failure mode); k independent records need
  no coordination, work asynchronously, and reuse the existing chain verifier unchanged.
- The server stores records; it needs no new logic beyond ADR 05b §1's application to rows, and its
  row is, as always, only a projection the client verifies.

## Consequences
- Code: `core_crypto/shamir.dart` incl. `GuardianShareSet.reconstructVerified` +
  `GuardianShareMismatch` (M3, landed); `test/vectors/shamir_ref.py` (the KAT source);
  `SignedRecordKind.deviceRevocation` (M3, landed); counting logic in `sync_engine` at M4 —
  which needs the guardian-set history by `share_set_version` (not only the current set) in the
  meta channel (05 §5); recovery UI (M11) calls the verified reconstruction and shows *2 of 3
  guardians approved* for a pending revocation (07 owner — no such state is drawn today).
- Docs (applied on ratification, 7 Sep 2026): 04 §2 Shamir row → "in-house GF(256), `core_crypto/shamir.dart`; no
  audited package exists; combination wrapping not adopted"; 04 §11.1 closed; 04 §9.2 gains the
  k-records sentence plus the two §3 rules; 04 §7.3 step 4 gains "and verifies the re-derived
  public key against the user's known UMK"; ADR 2026-09-05b Open 2 closed; 03 §3.1
  `signed_records_local` unchanged.
- Milestone: M3 (rulings 1–2), M4 (ruling 3).

## Ids reserved for M4 / M11 (`check_coverage` reports them dangling until the tests land)
| Id | Ruling | One-line test |
|---|---|---|
| D-06a-1 | k-th record's `seq` is the cut-off | 2-of-3: approvals at seq 10 and 14 → device's envelopes at seq 12 valid, seq 15 quarantined |
| D-06a-2 | cut-off moves earlier, never later | third approval arrives with seq 8 → cut-off becomes 10; seq 12 now quarantined on Recompute; two clients with opposite arrival order agree |
| D-06a-3 | re-split does not reset | one approval at version 3; device bumps to version 4; second approval naming 4 → revocation effective |
| D-06a-4 | removed guardian's approval stands; non-guardian's does not | approval by a guardian dropped in the bump still counts; a record from a never-guardian UMK is ignored and logged |
| F1-06a-1 (M11, suite F1) | checklist 4 | S11.1 with n = 2: the Continue button stays disabled until the user types the confirmation phrase; a dismissible warning alone never enables it |

## Ratification checklist — four answers, given by the owner 7 Sep 2026 🔒 ⟦tests: n/a — heading; each answer below carries its own marker⟧
1. **Ruling 1** — in-house GF(256) Shamir, no package: **yes.** ⟦tests: B-04-50, B-04-73⟧
2. **Ruling 2** — share wire form + verified reconstruction via the pinned public key: **yes.** ⟦tests: B-04-62, B-04-72⟧
3. **Ruling 3** — k counted records, cut-off moves earlier, re-split does not reset, earliest-k:
   **yes** (earliest-k; not current-k, not a multi-signature record). ⟦tests: D-06a-1, D-06a-2, D-06a-3, D-06a-4⟧
4. **04 §11.3** — guardian minimum: **default 2-of-3; n = 2 allowed only behind a typed
   confirmation, not a dismissible warning.** 2-of-2 has no loss tolerance *and* needs both
   guardians to act — the worst of both shapes — but forbidding it excludes a couple with no third
   person they would trust with this, which is a real Rukka household. The typed confirmation is a
   UI rule for S11.1 (07/13 owner). ⟦tests: B-04-63, F1-06a-1⟧

## Open ⚠️
- External review of `shamir.dart` before M14 (ruling 1); a third-party known-answer vector first.
- 07 has no screen state for a pending k-of-n revocation (*2 of 3 approved*) or for a re-quarantine
  after the cut-off moved earlier — design owner, before M11.
