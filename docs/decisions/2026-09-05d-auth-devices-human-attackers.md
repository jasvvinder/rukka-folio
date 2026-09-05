# ADR 2026-09-05d — Auth & devices: waiting periods, certified-only metadata, and the hostile relative

Fourth review of the day (after 2026-09-05 client hardening, 05b sync trust boundaries, 05c storage).
06 is the strongest of the four specs: no passwords, login separated from data, hardware
challenge-response, a PIN the family does not know, a support desk that structurally cannot help an
attacker. Its gaps cluster in one place — **the ceremony defeats a hostile server, but several
flows still let a hostile human, or two, act faster than the real owner can notice.** Most fixes
are a waiting period and a notification. Owner confirmed 5 Sep 2026 ("do whatever is best").

## Rulings 🔒

### 1. Recovery waits when the owner still has a working device
Guardian recovery (04 §7.3) and guardian-approved phone-number change (06 §9.4) complete
**immediately only when the user has no active certified device** — the genuine lost-phone case.
If any active device exists, completion is **delayed 24 h**; every existing device alarms with the
requester's name, photo, new-device fingerprint and a **one-tap Cancel**, and a cancel closes the
attempt, logs `recovery_cancelled` and notifies the guardians who approved. Two colluding
guardians plus a borrowed phone can no longer take a member's identity — and their personal book —
before the member sees it. A user who still has a device and wants a new one should **link**
(rung 1), which is instant; the app says so on the recovery screen.

### 2. Uncertified devices see nothing but themselves
An OTP proves the doorbell, not the person. Until a device holds a certificate the **server has
verified** under the user's registered UMK public key (one more Ed25519 verify — within 04 §8.6's
minimal surface), RLS returns only: the device's own `users` row, its own `devices` row, wrapped
keys and shares **addressed to it**, and its own `recovery_requests`. No memberships, no member
names, no roles, no device lists, no verification log. A SIM-swapper learns nothing about the
family. `devices.status` gains `certified` set by the server on cert verification; the RLS
predicate for every tenant table requires it.

### 3. Support actions are delayed and cancellable
Support-initiated **device revocation** follows the deletion pattern: a 24 h window, a notice on
every certified device of the user — *"Support revoked {device} at your request. Not you? Cancel."*
— and the revocation lands as an **unsigned** server assertion, so per ADR 2026-09-05b §2 the
target device **suspends, never wipes**. Support keeps the power to help a real victim; nobody can
be talked into destroying a stranger's phone in one call.

### 4. Keystore bound to the current biometric set
The keystore item guarding the device key uses the platform's *current biometric set* access
control (iOS `biometryCurrentSet`; Android `setInvalidatedByBiometricEnrollment(true)`). Any
enrolment change makes the item unreadable by biometrics and the app falls back to the **MPIN**,
then re-creates the item. This closes the exact threat 06 §4.4 names: a relative who knows the
passcode enrols their own face. The onboarding line (07 §5.6) gains half a sentence.

### 5. MPIN attempt policy — ours to enforce, not the enclave's
The MPIN is compared by our code, so our code rate-limits it: **5 free attempts**, then 30 s, 1 min,
5 min, 15 min, 1 h between attempts; after **10 failures** the PIN is disabled and reset requires
OTP to the registered number **plus** biometric (06 §4.4 forgot-PIN path). Storage: a 32-byte random
key in the hardware-backed keychain (this-device-only) and `HMAC(key, pin)` compared in constant
time; the attempt counter and lockout-until timestamp live in the same protected item so they
survive reinstall on iOS and cannot be reset by clearing app data. Never a KDF input (04 §2).

### 6. Every new certified device announces itself
On **every** path — signup, link, guardian recovery, paper sheet, platform key sync, iOS Keychain
remnant — the newly certified device causes a notice to **all of the user's other devices and every
tenant** ("{name} added a device: {model}"), and a `device_added` **signed record** (the certificate
itself, ADR 2026-09-05b §1). Today only guardian recovery notified. This is the sole signal a user
has that their Apple or Google account was just used against them.

### 7. Verification and device events are signed records
`verification_events` (who verified whom, method) and device add/revoke are authored on the acting
device as signed records; the server's rows are its copy (ADR 2026-09-05b §1). The tenant's trust
history is no longer the server's word.

### 8. Threat model names the cloud account
04 §1.2 gains: *"Compromise of the user's Apple/Google account **plus** their phone number defeats
platform key sync and restores the vault silently. Accepted as the price of silent recovery for the
common case; detection is ruling 6, mitigation is turning key sync off in Devices & security."*

### 9. Smaller rulings
- **Invites are phone-bound.** An invite is accepted only by a device whose OTP-verified number
  matches `invitee_hmac` (03 §2.1); the link alone admits nobody. Stated in 06 §7.
- **Revocation lag.** A revoked device can read metadata for up to one access-token lifetime
  (15 min); content it could already decrypt it already had. Stated, accepted.
- **Rate limits** on `/auth/challenge` and `/devices`: per-IP and per-device, generic errors,
  in line with 06 §2's OTP limits (numbers ⚠️ at M6).
- 06 §9.3 phone-erasure sentence moved beneath the section's main paragraph (placement slip from
  ADR 2026-09-05c).

## Declined
- Per-request signing (DPoP-style) of every API call: envelopes and records are already signed
  individually, TLS is pinned, and the token lives 15 min; a stolen token can read ciphertext and
  metadata only. Revisit if a web client ever exists (10 § parking lot).
- Blocking guardian recovery entirely while a device is active: linking is the right path, but a
  user with a broken-screen phone that is still "active" needs recovery — hence the window, not a wall.

## What changed where
06 §3 (certified status, rate limits), §4.4 (biometric set, MPIN policy), §5 (recovery window row),
§6 (announce on every path), §7 (phone-bound invite; signed verification), §8 (support revocation
delayed), §9.3 (placement), §9.4 (window), §10 tests, §11 open · 04 §1.2 (cloud account), §7.3
(step 6 window) · 03 §2.5 (certified-only RLS) · 07 §5.6 (onboarding half-sentence) · 09 suite C ·
10 M6 row.

## Open ⚠️
1. Rate-limit numbers for challenge/registration (M6).
2. Whether the 24 h recovery window is configurable per tenant (organizations may want 72 h) —
   default fixed at 24 h until the pilot says otherwise.
3. Android keystore invalidation behaviour across OEMs — verify on the low-end test devices at M6.
