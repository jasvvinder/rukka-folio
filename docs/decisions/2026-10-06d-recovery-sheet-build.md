# ADR 2026-10-06d — Rung 3, the paper recovery sheet, is built end to end

On 6 Oct 2026 the phase 1 journeys on `rf_min` (`scripts/run_journeys.sh`) found S0.5b *Make the sheet* disabled on all
six paths (PLAN desk 171). The cause was checked in the code, and rung 3 (04 §7.4) is missing at both ends:
- **Making a sheet.** `sealUmkUnderRecoveryKey` (`packages/core_crypto/lib/src/recovery.dart:101`) returns
  `SealedRecoveryBlob` as three fields (suite byte, 24-byte nonce, ciphertext) and defines no byte encoding.
  `RecoveryApi.publishSheet` (`app/lib/shared/sync/recovery_api.dart:698`) stores one opaque byte string. There is also no
  sheet PDF and no scan-back check, so S0.5b is wired with no generator (`onboarding_routes.dart:281-297`).
- **Using a sheet.** S11.3 is installed with no opener (`app/lib/bootstrap.dart:809-830`). The encoding is the first
  missing piece. The second is that `LedgerKeyMaterial` (`app/lib/shared/ledger/local_ledger.dart:1149`) has no way to
  adopt a recovered UMK.

The sheet's own payload is already built and tested: `version ‖ user_id ‖ RK`, the QR and typed Crockford codec, and the
checksum (`recovery.dart:185-215`). 04 §7.4 makes the sheet mandatory for solo users.

**Owner ruled, 6 Oct 2026:** build it now. The `core_crypto` part goes to `lane-core` (escalation approved for this
work), tests first, and the app part follows in a `lane-ui-hard` slice.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The sealed blob's bytes are `suite_version ‖ nonce ‖ ciphertext` 🔒 ⟦tests: B-1006d-1, B-1006d-2⟧
- `sealed_RK_blob` = 1 byte `suite_version` (04 §2, currently `0x01`) ‖ the 24-byte XChaCha20-Poly1305 nonce ‖
  the ciphertext with its 16-byte tag. This follows the `GuardianShare.encode` precedent (`shamir.dart:420`).
- `core_crypto` owns both directions: an encode on `SealedRecoveryBlob` and a strict decode. The decode refuses a wrong
  length, an unknown suite or a truncated tag with `RecoveryUnsealFailed`. It never guesses.
- 04 §2 crypto agility is unchanged: a later suite bumps the first byte, and older blobs stay readable.

### 2. A recovered UMK is adopted only after it is verified 🔒 ⟦tests: B-1006d-3, C-1006d-1⟧
- After `openUmkWithRecoveryKey`, the recovered key pair is adopted into the device's key material **only if** its public
  halves match the account's published UMK, the same check as every other rung (04 §7.3 step 6, CLAUDE.md rule 5).
- On a mismatch nothing is stored, and S11.3 shows its *"that code didn't work"* state (R2.4).
- Adoption re-wraps the local UMK copy to this device's key, as at signup (ADR 2026-10-06 §1). No secret is logged and
  every buffer is zeroised.

### 3. S0.5b makes, prints and checks a real sheet 🔒 ⟦tests: F1-1006d-1, F1-1006d-2, F1-1006d-3⟧
- *Make the sheet* generates RK, seals the UMK, publishes the blob (`publishSheet`) and only then shows the sheet. A
  failed publish shows its reason and keeps *Skip for now*. It never shows a sheet the server does not hold.
- The sheet is a one-page PDF laid out as 04 §7.4 says: QR, the typed fallback (Crockford Base32, groups of 4, 2-char
  checksum), and instructions in English plus the user's language. It is handed to the platform's print or share sheet.
- Scanning the printed sheet back clears the verified-storage badge (04 §7.4). Regenerating rotates RK and invalidates the
  old sheet (04 §7.4, unchanged).
- S11.3 restore opens the blob with the scanned or typed code, adopts per ruling 2, and completes as rung 2 does.

## Consequences
- **Code, slice RUNG3A (`lane-core`):** `packages/core_crypto` (blob encode/decode, B-1006d-1…3) and the adoption path in
  `app/lib/shared/ledger/` (C-1006d-1). 3-lens review.
- **Code, slice RUNG3B (`lane-ui-hard`), after RUNG3A lands:**
  - the sheet PDF and print/share;
  - the scan-back check;
  - S0.5b wiring in `onboarding_routes.dart`;
  - the S11.3 opener in `bootstrap.dart`, plus the device proof on `rf_min` (make, print to PDF, wipe, restore).
  - F1-1006d-1…3; the journeys must show S0.5b enabled.
- **Tests superseded:** F1-1006c-5 (*S0.5b with no sheet maker says why*) stays green for the no-generator seam but no
  longer describes the production wiring. RUNG3B decides whether it keeps a meaning, and skips it per ADR 2026-09-05i §4
  if not.
- **Docs:** 04 §7.4 gets a cross-reference line. PLAN desk 171 closes with RUNG3B.

## Open ⚠️
- ⚠️ Where RK is first generated: 04 §7.4 says "at signup". This build makes it at S0.5b, the first point the person can
  hold the sheet. *Skip for now* therefore leaves no RK and no blob until the sheet is made from the S0.7 checklist row.
  This is the conservative reading (no blob on the server that no printed sheet matches); the owner may refine it.
- ⚠️ Whether the blob should bind `user_id` or `sheet_version` as AEAD associated data. It is not needed for the threats in
  04 §10 (a swapped blob already fails under the wrong RK). `lane-core` reports it and does not add it unasked.
