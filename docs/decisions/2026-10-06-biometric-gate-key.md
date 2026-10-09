# ADR 2026-10-06 — The fingerprint guards a gate key, not the device keys

ADR 2026-09-05d §4 binds "the keystore item guarding the device key" to the phone's current biometric set, so
that a relative who knows the passcode and enrols their own face meets the PIN (06 §4.4). As built, the item that
the biometric set binds **is** the device keys. The KEY145B lane established from the code (5 Oct 2026; PLAN desk
152) what that costs:
- The device seeds are minted once (`local_ledger.dart:2251`) and kept only in the biometric-bound class
  (`keychain_key_store.dart:402/436`).
- No item is synchronizable, and the server holds no device private key (04 §3.3, zero-knowledge).
- The local copy of the UMK is wrapped to that device's X25519 key (`local_ledger.dart:2264`).

So any enrolment change makes the platform destroy the device keys, and the UMK copy becomes unreadable with them.
The emulator showed it: a second fingerprint → `KeyPermanentlyInvalidated` → PIN → *"Your books could not be opened
on this phone"*. Only the recovery ladder brings the books back, and a person on one phone with no recovery sheet
loses them on that phone. iOS `biometryCurrentSet` gives the same outcome from the code (not verified on a device).

Options put to the owner (desk 152):
- (a) accept it and route to the ladder;
- (b) bind a separate gate key, not the device keys;
- (c) keep a PIN-only copy alongside;
- (d) build platform key sync first.

**Owner chose (b), 6 Oct 2026.** This is ADR 05d §4's literal wording, *the item guarding the device key*, applied
as written.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The device keys are never biometric-bound 🔒 ⟦tests: C-1006-1⟧
- The device signing seed (Ed25519), the device agreement key (X25519) and the locally wrapped UMK live in the
  **hardware-backed keystore without a user-authentication binding**:
  - Android: Keystore with StrongBox where the phone has one, else TEE; no `setUserAuthenticationRequired`, no
    invalidation on enrolment.
  - iOS: Keychain, this-device-only, no biometric access control.
- 04 §3.3 is unchanged: the keys are hardware-backed, StrongBox / Secure Enclave when available, and never leave the
  phone.
- They are minted when the device is first registered (S0.2), straight into this class. Nothing moves them later.
  This **supersedes ADR 2026-10-05b §4's** "move to the biometric class after O4b" and settles PLAN desk 153.

### 2. The biometric set guards a separate gate key 🔒 ⟦tests: C-1006-2 @M13⟧
- A **gate key** is a random secret in its own keystore item, bound to the current biometric set:
  - Android: `BIOMETRIC_STRONG`, user authentication required per use, invalidated by any enrolment change.
  - iOS: `biometryCurrentSet`.
- Reading the gate item requires the person's biometric. That read **is** the unlock.
- The gate is minted **after O4b** (the MPIN exists) on a phone with a qualifying biometric (ADR 2026-10-05b §1). A
  PIN-only phone has no gate.
- The gate secret opens nothing cryptographically. It is proof of presence, and it is never a key to data (06 §4.4:
  the MPIN is a gate, never a key; the same holds for this gate).

### 3. The app uses the device keys only after the gate or the MPIN has opened 🔒 ⟦tests: C-1006-3 @M13⟧
- At cold start and after the background timeout (07 §5.6), the keystore items that hold the device keys are not read,
  and no signing, unwrapping or sync that needs them runs, until:
  - the gate item has been read with the biometric; or
  - the MPIN has been verified (attempt policy ADR 2026-09-05d §5, unchanged).
- The lock screen (S15) is the only door. A cancelled or failed biometric reaches *Use PIN instead*, never a blocked
  screen (ADR 2026-10-05b §4).
- The device passcode is still never offered (07 §5.6).

### 4. An enrolment change costs only the gate, and the PIN mints a new one 🔒 ⟦tests: C-1006-4 @M13⟧
- When the gate item is invalidated (a fingerprint or face added or removed, or every biometric removed), the app asks
  for the **MPIN**. On success it mints a new gate, bound to the biometric set now enrolled, or none if the phone has
  no qualifying biometric left (PIN-only, ADR 2026-10-05b §3).
- The device keys, the UMK copy and the books are untouched. **Adding a fingerprint never loses data.**
- The 06 §4.4 threat stays closed: a relative who enrols their face invalidates the gate and meets the PIN.
- This replaces ADR 2026-10-05b §2 and §3's "re-create the device-key item under the biometric binding": what is
  re-created is the gate. The upgrade from PIN-only still happens only behind a successful MPIN unlock.

### 5. Existing installs move once, behind an unlock 🔒 ⟦tests: C-1006-5 @M13⟧
- An install whose device keys sit in the old biometric-bound class is migrated on its next successful unlock, while
  the biometric-bound items can still be read:
  1. read the keys;
  2. write them to the ruling-1 class;
  3. read them back and compare;
  4. only then mint the gate and delete the old items.
- A failure part-way leaves the old items in place, so no state may exist in which neither copy opens.
- Pre-launch there are only development installs (Android first ran on 5 Oct), but the migration is built and tested
  anyway.

## What this costs, stated plainly
The device keys are no longer *cryptographically* tied to a fresh biometric check. The app's own lock (ruling 3)
enforces that they wait for the gate or the PIN. Code already running inside the app on an unlocked phone (a rooted
phone or malware) could use them without the biometric, exactly as on a PIN-only phone today (ADR 2026-10-05b). The
keys still cannot be exported from the hardware keystore, and the threat this design exists for (a relative enrolling
their face, 06 §4.4) is still met by the PIN.

## Consequences
- **Code (one security-briefed lane, 3-lens review):**
  - `app/lib/features/devices/keychain_key_store.dart`: the item classes. The device-key class loses the biometric
    binding and keeps StrongBox where available (verify from the plugin source whether a non-auth AES key can request
    StrongBox; if not, use the platform helper `RukkaKeystoreChannel.kt` / iOS).
  - The new gate item.
  - The `cold_start_gate.dart` / `keystore_biometric_gate.dart` unlock (gate read or MPIN, then the keys).
  - Minting the gate after O4b.
  - The ruling-5 migration.
  - The existing invalidation path (KEY145B's native reset) now resets the gate only.
- **Device proof:** on `rf_min` with a PIN and a fingerprint, add a second fingerprint → PIN → Home with the books
  intact.
- **Tests:** C-1006-1…5, planned for M13. Tests that assert the device keys are biometric-bound (F1-05d-1…3, KEY145B's
  C-1005b-2/3) are superseded where they say so: `@Skip('superseded by ADR 2026-10-06 §…')` with the replacement
  test, never deleted.
- **Docs:**
  - 06 §4 item 4 (the "Keystore bound to the current biometric set" line) carries the change.
  - ADR 2026-09-05d §4 and ADR 2026-10-05b §2–§4 get cross-references.
  - 04 §3.3 gets a cross-reference.
  - PLAN desks 152 and 153 close on this ruling.
- **Not changed:** the MPIN attempt policy, the passcode rule, 04 §3.3's hardware residency, certification and
  recovery, ADR 2026-10-05b §1 (what counts as a biometric), and desks 147 and 149.

## Open ⚠️
- ⚠️ Whether a non-auth key can be StrongBox-backed through flutter_secure_storage 11.2.0 is unverified. The build lane
  checks it from the source and uses the platform helper if not (ruling 1 requires StrongBox where available).
- ⚠️ iOS: the gate on `biometryCurrentSet` and the keys without access control are reasoned from the code and the
  platform documentation; there has been no iOS device run yet.
