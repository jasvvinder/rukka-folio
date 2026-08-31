# 12 — Platform Admin Console

**Status:** Draft 1 for owner review. Fills the gap our specs left as "a tiny internal panel". 🔒 = locked by architecture (not policy — see §2). ⚠️ = decide before M13.

**Principle:** the console is a **metadata console, not an account console.** Everything a conventional admin portal does with customer data, ours cannot do — and that is the product working, not a limitation to engineer around.

---

## 1. What the console can see and do

| Domain | Capability |
|---|---|
| **Directory** | Tenants (id, type, created, plan, seat count, book count, device count) · users (phone, name, language, created, last active). **No balances, no book names, no account names — all encrypted (03 §4).** |
| **Billing** | Plan changes, refunds via gateway API, manual plan grants (NGO/pilot), promo codes, invoice re-issue, dunning state |
| **Support actions** | Revoke a device · re-send an invite · extend a trial · start account deletion (15-day cooling) · freeze a tenant (writes blocked, reads and export still work) |
| **Security telemetry** | OTP failure rates, rate-limit trips, verification-mismatch events, recovery requests, escrow countdowns — **as event counts and types, never content** |
| **Platform config** | Feature flags, minimum client version (06 §4.5), statement-parser toggles per bank, maintenance mode |
| **Analytics** | MRR, active tenants, retention cohorts, crash rates, sync error rates, parser success rates |

## 2. What the console cannot do — and why it's structural 🔒

Not "forbidden by policy". **Impossible by construction**, which is a stronger guarantee and worth publishing:

| Conventional admin action | Why it cannot exist here |
|---|---|
| View a tenant's balance / entries / accounts | Server holds ciphertext only; no key exists on the server (04) |
| Reset a password | There are no passwords anywhere in the system (06 §1) |
| Recover a user's data | Keys live only on member devices; recovery runs through guardians or the paper sheet (04 §7). **No endpoint exists** |
| Manually override a role / add a member | Membership requires *both* a database row **and** a book key wrapped to that member's verified device key. The server cannot wrap keys, so a hand-edited row grants nothing but an empty vault (04 §5.1). Access is enforced twice, and the server only controls one half |
| Impersonate a user | Sessions are hardware-key challenge–response; the server never holds a device private key (06 §4) |
| Force-reset all users' credentials | Same as above — and would strand data, since credentials aren't what unlocks it |

**Publish this table.** "Here is what our staff cannot do, and why the maths prevents it" is the strongest form of the brand's directional-trust claim (11 §1).

## 3. Architecture 🔒

- **Separate application, separate deployment, separate database role** from the member API. It reads the same Postgres through a dedicated role whose grants exclude `envelopes.blob`, `wrapped_keys.blob`, and all attachment storage. CI asserts the grant set.
- **Separate admin identity:** work email + **passkey/hardware key**, never phone OTP (staff must not share the members' auth path). Session ≤ 8 h, IP-allowlisted ⚠️.
- **Read-only by default.** Every write action requires a typed reason, and the destructive set — freeze tenant, refund > ₹X, delete account, feature flag on production — requires **four-eyes approval** by a second admin ⚠️ threshold.
- **Append-only admin audit log**, immutable, retained ≥ 3 years, exportable for any future compliance review.
- **Transparency to the member 🔒 (recommended):** when staff view a tenant's metadata or take an action on it, write a tenant-visible audit event — *"Support viewed your account details on 14 Sep"*. Almost no competitor does this, it costs one row, and it makes the privacy claim inspectable rather than asserted.

## 4. Guardrails in CI
Extend the endpoint-inventory test (06 §10): **no admin route may return ciphertext, key material, or any field outside the plaintext list in 03 §4.** A new admin endpoint that touches those tables fails the build.

## 5. Phasing ⚠️

| Phase | When | Build |
|---|---|---|
| **0** | pilot → ~100 tenants | Gateway dashboard + one read-only metadata page. Nothing more — premature tooling is wasted at this scale |
| **1** | ~100–500 tenants (M13) | Support console: directory, billing actions, device revoke, freeze, audit log, four-eyes |
| **2** | 500+ | Analytics, feature flags, promo engine, parser toggles, cohort retention |
| **3** | enterprise/NGO deals | Custom invoicing, dedicated-manager views, bulk NGO grants |

**Recommendation:** do not build Phase 1 before the pilot proves the product. Until then the gateway dashboard plus direct SQL, run by you, is genuinely sufficient — and every hour not spent on internal tooling goes into the eight-second entry.

## 6. Open items ⚠️
1. Four-eyes threshold values. 2. IP allowlist vs device-bound admin sessions. 3. Whether the member-visible transparency log ships at Phase 1 (recommended) or Phase 2. 4. Data-residency and access policy for staff, aligned with the DPDP checklist (M14).
