# ADR 2026-10-05b — A phone with no fingerprint or face enrolled runs PIN-only until one is

The design assumes every phone has Face ID or a fingerprint enrolled. O4b says *"You'll use Face ID
most of the time"*, 07 §5.6 says Face ID is *"not optional and not a setting"*, and 06 §4.4 / ADR
2026-09-05d §4 bind the device-key item to the current biometric set. No spec or canvas covers a phone
with **no strong biometric enrolled**. The only mention is 07 §5.6's *"Use PIN instead … for failed or
unavailable biometrics"*, and that is about unlocking an app already set up, not about creating the key.
On 5 Oct 2026 the Android app ran for the first time (desk 145, lane M13-KEY145, emulator API 36).
Android refuses to create a key that requires user authentication on a phone with no enrolled
biometric: with no screen lock it reports `BIOMETRIC_UNAVAILABLE`, and with a PIN but no fingerprint
it reports *"At least one biometric must be enrolled to create keys requiring user authentication for
every use"*. Bootstrap creates the device keys before any screen (`bootstrap.dart:443` →
`LocalLedger._firstRun`, `local_ledger.dart:2246`), so such a phone stops at *"Your books could not be
opened on this phone"* before the welcome screen. The Android floor phone (Android 9, 2 GB, 13 §10
decision 9) is exactly where people often never enrol a fingerprint.

Options put to the owner: **(A)** require a biometric, with an onboarding screen sending the person to
Settings; **(B)** run PIN-only until a biometric is enrolled, then upgrade; ~~(C)~~ use the phone
passcode, already ruled out by 07 §5.6 (*"the device passcode is never offered"*). **Owner chose B, 5 Oct
2026**, and clarified: *"PIN-only until fingerprint/faceid/biometric whatever the device has, is enrolled"*.
The upgrade trigger is therefore **any** biometric the phone offers, not one kind.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. No enrolled strong biometric → PIN-only mode, never a dead end 🔒 ⟦tests: C-1005b-1 @M13, F1-1005b-1 @M13⟧
- **"A biometric" means whatever the phone has: fingerprint, face, iris or any other**, provided it can
  guard a hardware key. On iOS that is Face ID or Touch ID, whichever the phone has (both work with
  `biometryCurrentSet`). On Android it is any **Class 3 (strong)** biometric of any kind. Android binds a
  Keystore key only to a strong biometric or to the device credential (`AUTH_BIOMETRIC_STRONG` /
  `AUTH_DEVICE_CREDENTIAL`; flutter_secure_storage 11.2.0 `KeyCipherImplementationAES23.java:174-176`),
  and the device credential is excluded by 07 §5.6.
- On a phone where no such biometric is enrolled (Android: `BIOMETRIC_STRONG` unavailable or none
  enrolled; iOS: `biometryCurrentSet` cannot be created), the device-key item is
  stored in the **hardware-backed keystore without a user-authentication binding**. On Android that is
  the TEE/StrongBox Keystore with no `setUserAuthenticationRequired`. On iOS it is the Keychain at
  this-device-only accessibility with no biometric access control.
- The app is then gated by the **6-digit MPIN alone**: the S15 lock screen shows the PIN boxes with no
  biometric button. The attempt policy (ADR 2026-09-05d §5) and *one PIN, not two* (06 §4.4) are unchanged.
- The **device passcode is still never offered**, as a gate or as a fallback (07 §5.6, unchanged).
- Onboarding never stops because no biometric is enrolled. The person goes through every step,
  including O4b *Set your PIN*.

### 2. The upgrade to biometric binding is automatic and happens only behind the PIN 🔒 ⟦tests: C-1005b-2 @M13⟧
> **ADR 2026-10-06 §4** — what is created or re-created under the biometric binding is the **gate key**, not the device-key item; the device keys stay in the hardware keystore without a biometric binding (§1 there). ⟦tests: C-1006-4 @M13⟧
- When any qualifying biometric (ruling 1) is enrolled on a PIN-only phone, whatever its kind, the switch happens at the **next successful
  MPIN unlock**. The app re-creates the device-key item under the current-biometric-set binding (ADR
  2026-09-05d §4), verifies the new item reads back, and only then deletes the PIN-only item. From then
  on ADR 2026-09-05d §4 applies in full.
- The upgrade never runs on a biometric success alone. A newly enrolled face is exactly the threat
  06 §4.4 names, so the PIN is what admits it.
- A failure part-way leaves the PIN-only item in place. No state may exist in which neither item opens.

### 3. Losing every biometric drops back to PIN-only, through the PIN 🔒 ⟦tests: C-1005b-3 @M13⟧
- If the biometric-bound item becomes unreadable because every biometric was removed, or because an
  enrolment change invalidated it, the app asks for the MPIN (ADR 2026-09-05d §4, unchanged). It then
  re-creates the item: biometric-bound if a strong biometric is enrolled now, PIN-only if none is.

### 4. No keystore item that needs the person exists before the PIN does 🔒 ⟦tests: F1-1005b-2 @M13⟧
> **ADR 2026-10-06 §1–§2** — the device keys are minted at S0.2 registration straight into the hardware keystore without a biometric binding and never move; the **gate** is minted after O4b. This settles PLAN desk 153 (the "minted after O4b" wording). ⟦tests: C-1006-1 @M13, C-1006-2 @M13⟧
- Device keys are minted **after O4b** (the MPIN is set), not at bootstrap. Before that point the app
  may hold only items that open without a person (the database key, 04 §3.3).
- At every cold start the lock screen's **Use PIN instead** (07 §5.6) is reachable whenever biometrics
  fail, are cancelled or are unavailable. A cancelled prompt never ends at a blocked screen.

## Consequences
- **Code (the next lane after the 5 Oct cycle, `app/lib/features/devices` + `app/lib/bootstrap.dart` +
  `app/lib/shared/ledger` + `app/lib/features/lock` + `app/lib/features/onboarding`):**
  - capability check at item creation (rulings 1, 3);
  - the upgrade on MPIN success (ruling 2);
  - device-key minting moved after O4b, and *Use PIN instead* wired at cold start (ruling 4).
- **Android native helper:** removing an invalidated Keystore alias with `resetOnError=false` has no
  plugin path today (M13-KEY145 open item). Ruling 3 needs one, either a small platform-channel helper
  or a plugin call the lane proves from source.
- **Tests:** C-1005b-1…3 and F1-1005b-1…2 are planned for M13. They must run against the platform
  channel, as KEY145's F1-05d tests do, and on the emulator with and without an enrolled fingerprint.
  A green test that asserts the old blocked-at-bootstrap behaviour is superseded by §1/§4.
- **Docs:** 06 §4 item 4 and 07 §5.6 carry the exception. The canvases (O4b, O5, S15, S15.3) draw only
  the Face ID case, so the PIN-only variants are a design desk item.
- **Not changed:** the MPIN is still a gate, never a key (06 §4.4, 04 §2); the attempt policy;
  the escrow, recovery and certification rules.

## Open ⚠️
- ⚠️ **SPEC: owner to confirm. Forgot PIN on a PIN-only phone.** 06 §4.4 says *"OTP to the registered
  number plus biometric"*, and after 10 failures *"OTP + biometric"*. A PIN-only phone has no biometric.
  Options: (a) **OTP alone**, which is weaker (a SIM swap plus physical access opens the app); (b)
  **OTP plus a delay**, cancellable from any other certified device, the ADR 2026-09-05d §3 pattern
  for support actions; (c) **the S11 recovery ladder** (guardians / paper sheet), the strongest and
  heaviest. Until ruled, the build takes the conservative reading (c) and leaves `⚠️ SPEC:` at the seam.
- ⚠️ **Design:** PIN-only variants of O4b (no "You'll use Face ID" line), O5 (the stated-not-asked line
  needs a PIN-only form) and S15 (no biometric button), plus the one-time line shown when the upgrade
  happens. EN/PA/HI copy follows 01 §1.8.
- ⚠️ **SPEC: owner to confirm. Android phones whose only biometric is a weak (Class 2) face unlock.** Many budget
  Android phones unlock with the front camera, and Android rates that Class 2. It **cannot** guard a Keystore key (ruling 1),
  and it gives no enrolment-change signal, so a relative who adds their own face would not be detected (the 06 §4.4 threat).
  Options: (a) treat such a phone as **PIN-only**, which is safe and matches the threat model; (b) let the weak face unlock
  open the app as a convenience gate over the PIN-only item, which is quicker for the person but weaker, because a photo can
  pass some Class 2 sensors and a new enrolment goes unseen. Until ruled, the build takes (a). The lock screen then needs a
  line explaining why face unlock is not offered (design desk 148).
- ⚠️ **iOS:** whether iOS hits the same wall with no Face ID or Touch ID enrolled is unverified (KEY145
  open item). Ruling 1 covers it either way.
