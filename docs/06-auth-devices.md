# 06 — Authentication, Devices, Sessions & Invitations

**Status:** Draft 1 for build. 🔒 = locked decision. ⚠️ = choose/verify before the affected milestone.
**Companion:** 04-crypto.md owns all key material; this document owns identity, sessions, device lifecycle, invitations, support, and deletion. The dividing line: **OTP and sessions grant *login*; only keys (doc 04) grant *data*.** A SIM-swap attacker who beats every control in this document still reads nothing.

---

## 1. Identity model 🔒

- **One phone number (E.164) = one human = one account, globally.** A user is not per-tenant; Harpreet is one identity who belongs to n tenants (family, businesses, trust) via memberships.
- No passwords exist anywhere in the system. No email required (optional contact field only).
- Plaintext profile: phone, display name, photo (optional, shown in approvals/verification), preferred language (per-user, not per-tenant), WhatsApp opt-in.
- Phone-number change is supported (§9.4) — the number is the *claim*; the UMK is the identity.

### 1.0 Role labels are per tenant type 🔒 (gap closed 1 Sep 2026)
The **stored** role is always one of five; only the **displayed** name changes, so capability and code are identical everywhere:

| Stored | Family / business shows | Organization shows |
|---|---|---|
| `admin` | Admin | **Chairman** |
| `head` | Head | **Secretary** |
| `member` | Member | **Trustee** |
| `operator` | Operator | **Sevadar** (ਸੇਵਾਦਾਰ) |
| `viewer` | Viewer | **Auditor** |

A gurudwara committee will not recognise "Operator"; it will recognise ਸੇਵਾਦਾਰ. ⚠️ Owner to confirm Secretary/Trustee ranking against how a Singh Sabha committee actually orders them.

### 1.1 Multi-tenancy 🔒
- `tenants(id, type ∈ {family, business_group, organization}, name_ciphertext, plan, …)`
- `memberships(tenant_id, user_id, status, verified_by, verified_method, …)` and `book_roles(book_id, user_id, role ∈ {admin, head, member, operator, viewer}, auto_post_limit_paise, …)` — one role **per book**, never global.
- Access tokens carry `user_id` + `device_id` only — never a tenant. Every request is tenant-scoped by path and checked against memberships in Postgres **row-level security**. New tenant types (the trust case) are rows, not code.

---

## 2. OTP subsystem 🔒

- Channels: WhatsApp Business API first (cheaper, higher delivery in India), SMS fallback, auto-failover. Provider behind an interface (MSG91 / Kaleyra / Gupshup — ⚠️ pick by current pricing at build).
- Fires **only** at: signup, device activation, phone-number change, account deletion confirmation. Never at routine login.
- Code: 6 digits, 5-minute expiry, 3 attempts, then new code required. Resend backoff 30 s → 60 s → 5 min. Rate limits per number (5/hour, 10/day) and per IP. Generic error messages (no "number not registered" oracle).
- OTP verification yields a short-lived **activation ticket**, consumable exactly once by §3.

---

## 3. Device registration 🔒

On first run after OTP:

1. Generate device keys per 04 §3.3 (Ed25519 in hardware keystore; X25519 stored under a hardware-backed AES key).
2. `POST /devices` with activation ticket + public keys + model/OS metadata → server issues `device_id` and stores the record. ⚠️ Play Integrity / DeviceCheck attestation: design the field now, enforce in v2.
3. The device is **registered but uncertified** until it holds a certificate under the user's UMK (issued at signup for the first device, or via linking/recovery — 04 §3.4, §9.1, §7). Uncertified devices can authenticate (§4) but other clients will not trust content they author, and they hold no keys.
4. First device only: generate UMK, self-certify, then immediately walk the user through **recovery-sheet generation + verified-storage nag**, and **guardian selection** if the tenant has other members (04 §7.3–7.4).

---

## 4. Sessions 🔒

Challenge–response; no bearer secrets that outlive minutes.

1. `POST /auth/challenge {device_id}` → 32-byte nonce (60 s TTL, single use).
2. Device signs `nonce ‖ device_id ‖ unix_ts` with its hardware Ed25519 key → server verifies against the registered public key → issues **access JWT (15 min)** `{user_id, device_id}` + rotating **refresh token (30 days idle cap)** bound to `device_id`; every refresh requires a fresh signature. Reuse of a rotated refresh token revokes the family of tokens (theft signal).
3. Clock-skew window ±90 s on `unix_ts`.
4. **App PIN (MPIN) 🔒 (owner-raised 31 Aug 2026).** A **6-digit** PIN set during onboarding, alongside Face ID.
   - **Why, in this product specifically:** in a joint family, relatives commonly know each other's phone passcodes. Falling back to the device passcode would mean the family can open each other's books. A PIN the family does not know is a real layer, not ceremony — and Indian users already expect an MPIN from every banking app.
   - 🔒 **It is a local gate on the hardware keystore, never a key.** It is not a KDF input, never wraps key material, and never authenticates to the server. This preserves 04 §2's rule that the system contains **no low-entropy secrets**: rate-limiting and key protection stay with the Secure Enclave, and a 6-digit PIN could never protect a key by itself.
   - **Face ID is the fast path; the PIN is the alternative and the fallback.** Device passcode is no longer offered as the fallback.
   - **Forgetting it is not data loss:** re-verify by OTP to the registered number plus biometric, then set a new PIN. Nothing is re-encrypted.
   - 🔒 **One PIN, not two.** The Personal Book's extra lock re-prompts **the same PIN or biometric** rather than introducing a second number to remember.
5. **Local unlock** is the OS's job: biometric/PIN gates the keystore; app-lock timeout configurable (default 2 min background); the Personal Book's optional extra lock **re-prompts the same MPIN or biometric** — one PIN, never a second number (§4.4, ADR 2026-09-01).
5. Server maintains a **minimum client version** per API route group; below it → HTTP 426 and the app shows a mandatory-update screen. Crypto- or sync-breaking releases bump it.

---

## 5. Activation flows by scenario 🔒

| Scenario | Flow |
|---|---|
| Fresh signup | OTP → §3 → UMK + self-cert → sheet + guardians → done |
| **New phone, same Apple/Google account** | **Platform key sync (04 §7.0) restores silently — the common case; no guardians, no sheet** |
| Reinstall, same iPhone | Keychain intact? → keys found → normal device, no recovery. **On iOS-first this is the common path**, which materially reduces recovery-ladder traffic |
| Reinstall, same Android | Keystore was wiped → treat as **new phone** |
| New phone, has old device | OTP → §3 → **link** via ceremony (04 §9.1) |
| New phone, no old device | OTP → §3 → **recovery ladder** (04 §7): guardians → paper sheet |
| Every rung fails | Login succeeds, vault empty. Shared books are re-wrappable to the user's *new* UMK by tenant members after a **fresh verification ceremony**. The personal book stays sealed **for now** — its ciphertext remains on the server, so recovering the Apple/Google account or finding the recovery sheet later still opens it (04 §7.6). If a readable export exists it holds the books in plain form and can seed opening balances in a fresh book. Say all of this plainly; do not tell the user their data is destroyed when it is not |

Recovery completion always revokes all prior sessions and devices of that user and notifies every tenant they belong to (04 §7.3 step 6).

---

## 6. Device management 🔒

- **Linked devices** screen (WhatsApp-style): name, model, last active, certified state.
- Revoke: any certified device of the same user, k guardians, or support-on-request (§8). Effect per 04 §9.2; the **"stolen"** path additionally rotates BKs (+ recommended UMK rotation).
- Device cap: 5 per user (plan-adjustable).
- Every add/certify/revoke lands in the tenant-visible audit log.

---

## 7. Invitation & membership state machine 🔒

```
invited ──install+OTP──▶ joined_pending_verification ──ceremony ✓──▶ active
   │ 7-day expiry                    │ ceremony ✗ (mismatch)
   ▼                                 ▼
expired (one-tap re-invite)      blocked + security event (admin unblock only
                                  after investigation; new invite required)
```

- **invited:** admin picks phone + per-book roles (+ auto-post limit); server stores the invite with its 128-bit ceremony nonce; delivery via WhatsApp/SMS link.
- **joined_pending_verification:** invitee has an account, device, UMK — their **Personal Book works immediately** (it needs nobody's keys). Shared books are visible as named placeholders: *"Meet Sunita to activate."* Clients structurally cannot wrap BKs to this state (04 §5.1).
- **active:** on ceremony success (any mode: in-person QR default / logged remote code / delegated by any active member — 04 §6.4), the verifier's device wraps the BKs per the role grants; membership flips.
- Role changes later are database-only if within already-held books; granting a *new* book wraps that BK (no new ceremony — the human is already verified); removal follows 04 §5.3 with the ledger's advance-settlement precondition.
- Trustee/treasurer handover (organizations) = invite-with-ceremony for the incoming + removal for the outgoing, in one guided flow.

---

## 8. Support: verification & powers 🔒

Written policy, shipped with the product, so nobody can be socially engineered into an ability that doesn't exist.

- **Caller verification:** callback to the registered number **plus** one account fact (registration month, last payment amount, or count of linked devices). Never OTP-read-back (training users to read OTPs to "support" is how fraud happens — and our OTPs unlock nothing anyway).
- **Support CAN:** adjust plan/billing, extend trials, revoke a device, initiate account deletion (§9.3), resend invites.
- **Support CANNOT:** read any content, recover any key, bypass a ceremony, add a member, release an escrow. **No such endpoints exist.** The support script for "I lost everything" is the recovery ladder, and if the ladder is exhausted, the honest answer: *"Your shared books can be restored by your family after re-verification; your old personal book is gone — this is the privacy you were promised, working."*

---

## 9. Account lifecycle

### 9.1 Data stored (plaintext) — the complete list 🔒
Phone, name, photo, language, WhatsApp opt-in; tenants, memberships, per-book roles and limits; devices + certificates; wrapped keys/shares/escrow blobs (opaque); invites + ceremony logs; subscription state + payment-gateway reference IDs (gateway holds the instruments); audit events; envelope routing metadata (04 §4). **Not stored:** address (at most: state, only if subscription-GST demands it), DOB, Aadhaar, PAN, contacts upload, and — by construction — any financial content.

### 9.2 Data export 🔒
Available always, plan-independent, lapsed-plan included: full decrypted export (XLSX/CSV/PDF) generated **on device**. Open export is a trust feature, not a leak.

### 9.3 Deletion 🔒
User-initiated (in-app) or via support: 15-day cooling period, every device + guardians notified, cancel-anytime; then **profile data is erased** (phone, name, photo, language, contact fields), all wrapped keys and the user's personal-book envelopes are hard-deleted, and every session dies. 🔒 **Verification material is retained, not deleted:** the user's UMK *public* key and their device certificates survive as pseudonymous cryptographic material, flagged `erased`. They contain no personal data, and without them a device joining later could not verify the signature chain (04 §3.4) on entries that user authored in *shared* books — it would quarantine them, compute different balances, and fail the close hash (02 §8). Erasure of personal data and integrity of other people's financial records are both satisfied; this is the same reasoning that lets financial records outlive an erasure request. envelopes the user authored in *shared* books remain (they are the tenant's records) with authorship pseudonymized to a fixed label. DPDP-aligned; ⚠️ confirm final DPDP rules' retention/grievance details at build.

### 9.4 Phone-number change 🔒
OTP on old number (or, if lost, guardian approval k-of-n) + OTP on new number → identity record updates; UMK, keys, memberships untouched. The number was only ever the doorbell.

---

## 10. Acceptance tests (excerpt)

- **Given** a captured OTP + successful login on an attacker device, **when** sync completes, **then** zero envelopes decrypt and the account shows an empty vault + recovery prompts; all tenants see a "new uncertified device" audit event.
- **Given** a refresh token replayed after rotation, **then** the whole token family is revoked and the device must re-challenge.
- **Given** an invitee in `joined_pending_verification`, **then** their personal book accepts entries offline, and no wrapped BK for them exists server-side.
- **Given** a verification mismatch, **then** membership = `blocked`, a security event exists, and no re-try is possible without a new invite.
- **Given** a client below minimum version, **when** it calls any sync route, **then** 426 + update screen, and no envelope is accepted from it.
- **Given** account deletion completing, **then** the user's profile fields are erased and `erased_at` is set, their wrapped keys and personal-book envelopes are absent from storage, and **no shared-book envelope row was updated or deleted**.
- **Given** a deleted member's shared-book entries and a **freshly-installed device** that never saw them before, **then** the signature chain still verifies (retained device certs + UMK public key), the entries are **not** quarantined, the author renders as *Removed member*, and the device computes the same balance-vector hash as every other device (§9.1, 02 §8).
- **Given** a support agent's console session, **then** no UI or API path exists that returns key material or content (verified by endpoint inventory test).

---

## 11. Open items ⚠️

1. OTP provider selection by current WhatsApp/SMS pricing; verify current TRAI DLT registration requirements for SMS.
2. Play Integrity / DeviceCheck enforcement timing (field now, enforce v2).
3. DPDP rules status → consent text, grievance officer, retention windows (§9.3).
4. Device cap + guardian-minimum defaults to revisit after the family pilot.
