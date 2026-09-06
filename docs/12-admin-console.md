# 12 — Platform Admin Console

**Status:** Draft 1 for owner review. Fills the gap our specs left as "a tiny internal panel". 🔒 = locked by architecture (not policy — see §2). ⚠️ = decide before M13. **Amended 5 Sep 2026 by ADR 2026-09-05h — the insider is in the threat model: staff roles, break-glass, lookup quotas, a hash-chained staff log, freeze narrowed to 06 §8's grounds.**

**Principle:** the console is a **metadata console, not an account console.** Everything a conventional admin portal does with customer data, ours cannot do — and that is the product working, not a limitation to engineer around.

---

## 1. What the console can see and do

| Domain | Capability |
|---|---|
| **Directory** | Tenants (id, type, created, plan, seat count, book count, device count) · users (name, language, created, last active). **Phone numbers are never rendered** — staff *look up* by number (the console computes `phone_hmac`); the admin role has no KMS decrypt grant (ADR 2026-09-05c §4, ADR 2026-09-05h §3). **No balances, no book names, no account names — all encrypted (03 §4).** |
| **Billing** | Plan changes, refunds via gateway API (**to the original instrument only**), manual plan grants (NGO/pilot), promo codes, invoice re-issue, dunning state, **webhook replay** (original gateway event id as idempotency key, signature re-verified — never a double refund). 08 §4 owns this list; 12 enumerates only what 08 grants (ADR 2026-09-05h §11) |
| **Support actions** | **Revoke a device** — delayed 24 h, cancellable by the user, shown here as a pending window with requester and cancel; lands unsigned so the target suspends, never wipes; **no re-revoke after a user cancel without four-eyes + fresh callback** (ADR 2026-09-05d §3, ADR 2026-09-05h §2) · re-send an invite · extend a trial · **request account deletion** — the console sends a request to the user's devices; only the user's own device starts the 15-day clock (06 §9.3) · **freeze a tenant** — grounds exhaustive: payment fraud / legal order / abuse; pushes refused as `rejected:tenant_frozen`; pull, read and export untouched; four-eyes; expiry ≤ 30 days; members notified (06 §8, ADR 2026-09-05h §1) |
| **Security telemetry** | OTP failure rates, rate-limit trips, verification-mismatch events, recovery requests, escrow countdowns — **as event counts and types, never content**. **Per-user telemetry is visible only on an open ticket for that user; the dashboard shows aggregates** (ADR 2026-09-05h §5) |
| **Platform config** | Feature flags, minimum client version (06 §4.5), statement-parser toggles per bank, maintenance mode. **Governed as a kill switch:** four-eyes, staged rollout with a canary cohort, one-click rollback, every change a recorded config version (ADR 2026-09-05h §9) |
| **Analytics** | MRR, active tenants, retention cohorts, crash rates, sync error rates, parser success rates |

## 2. What the console cannot do — and why it's structural 🔒

Not "forbidden by policy". **Impossible by construction**, which is a stronger guarantee and worth publishing:

| Conventional admin action | Why it cannot exist here |
|---|---|
| View a tenant's balance / entries / accounts | Server holds ciphertext only; no key exists on the server (04) |
| Reset a password | There are no passwords anywhere in the system (06 §1) |
| Recover a user's data | Keys live only on member devices; recovery runs through guardians or the paper sheet (04 §7). **No endpoint exists** |
| Manually override a role / add a member | Membership requires *both* a database row **and** a book key wrapped to that member's verified device key. The server cannot wrap keys, so a hand-edited row grants nothing but an empty vault (04 §5.1). Access is enforced twice, and the server only controls one half. **And since ADR 2026-09-05b §1 the rows are copies of signed records: a hand-edited row is *detected* by every client as `meta_mismatch`, not merely useless** |
| Refund to a different account | The gateway holds the instrument; refunds can only return to it (08 §4). No payout path exists |
| Read a phone number | Stored encrypted under a KMS key the admin role cannot use (ADR 2026-09-05c §4); the console can only compute a lookup hash |
| Impersonate a user | Sessions are hardware-key challenge–response; the server never holds a device private key (06 §4) |
| Force-reset all users' credentials | Same as above — and would strand data, since credentials aren't what unlocks it |

**Publish this table.** "Here is what our staff cannot do, and why the maths prevents it" is the strongest form of the brand's directional-trust claim (11 §1).

## 3. Architecture 🔒

- **Separate application, separate deployment, separate database role** from the member API. It reads the same Postgres through a dedicated role whose grants exclude `envelopes.blob`, `wrapped_keys.blob`, and all attachment storage. CI asserts the grant set.
- **Separate admin identity:** work email + **passkey/hardware key**, never phone OTP (staff must not share the members' auth path). Session ≤ 8 h for reads; **idle re-auth every 30–60 min on the write path**. Reached only through an **identity-aware proxy or VPN, no public DNS, a domain sharing no cookie scope with the member app** — "IP-allowlisted" is retired as too thin (ADR 2026-09-05h §11).
- **Staff roles 🔒 (ADR 2026-09-05h §7):** support-L1 · billing · SRE · security-compliance · super-admin. The four-eyes approver is a **different human on a different role**. SSO-driven joiner-mover-leaver; quarterly access review with a signed record. **Phase 1 does not ship with fewer than two staff accounts held by two people.**
- **Lookup quotas 🔒 (ADR 2026-09-05h §5):** per-staff lookup limits with velocity alerts; every write carries a **ticket id** beside the typed reason.
- **Read-only by default.** Every write action requires a typed reason and a ticket id. **Four-eyes is triggered by irreversibility, not value 🔒 (ADR 2026-09-05h §8):** any refund > ₹5,000 · any freeze · any deletion request · any `min_client_version` or production feature-flag change · any break-glass (§3.1).
- **Staff audit log 🔒 (ADR 2026-09-05h §6):** **hash-chained**, shipped **off-box** to a store the admin role cannot write, **reads logged as well as writes**, exportable per tenant, retained ≥ 3 years. It is a **separate store from `audit_events`** and explicitly outside 03 §6's 24-month aggregation — the purge job never sees it.
- **Transparency to the member 🔒 (ships at Phase 1 — ADR 2026-09-05h §11):** when staff view a tenant's metadata or take an action on it, write a tenant-visible audit event — *"Support viewed your account details on 14 Sep"*. Almost no competitor does this, it costs one row, and it makes the privacy claim inspectable rather than asserted. **Session recording** is metadata plus justification, not screen capture.

### 3.1 Break-glass 🔒 (ADR 2026-09-05h §4)
One doctrine for every privileged path: backup access (ADR 2026-09-05c §1), the `maintenance` deletion role (ADR 2026-09-05b §8, 03 §2.5), the phone KMS key (ADR 2026-09-05c §4), and any direct database session.
- **Named accounts** (never shared) with a **hardware key**; **two-person authorisation** to open.
- **Short-lived brokered credentials** — minted for the session, expire with it. **No standing human access** to maintenance, backup or KMS.
- **Session recorded**; **alert to a second channel** the moment it opens; **post-hoc review within 24 h** by someone who did not open it.
- **Phase 0 direct SQL** (§5) runs only through such a logged session.
- The **restore runbook** includes the **`store_epoch` bump** (05 §1, ADR 2026-09-05c §1) as a checklist item with the reviewer's initials.

## 4. Guardrails in CI
Extend the endpoint-inventory test (06 §10): **no admin route may return ciphertext, key material, or any field outside the console's own column allowlist** — a per-table list kept with the console, narrower than 03 §4 (which describes the member API, not staff eyes) and **never containing `phone_ct`** (ADR 2026-09-05h §3). A new admin endpoint that touches other columns fails the build. Suite G (09) also asserts: the grant set excludes blobs; every write yields an audit row **and** a member-visible event; four-eyes cannot be self-approved; the lookup limit trips.

## 5. Phasing ⚠️

| Phase | When | Build |
|---|---|---|
| **0** | pilot → ~100 tenants | Gateway dashboard + one read-only metadata page. Nothing more — premature tooling is wasted at this scale |
| **1** | ~100–500 tenants (M13) | Support console: directory, billing actions, device revoke, freeze, audit log, four-eyes |
| **2** | 500+ | Analytics, feature flags, promo engine, parser toggles, cohort retention |
| **3** | enterprise/NGO deals | Custom invoicing, dedicated-manager views, bulk NGO grants |

**Recommendation:** do not build Phase 1 before the pilot proves the product. Until then the gateway dashboard plus direct SQL, run by you, is genuinely sufficient — and every hour not spent on internal tooling goes into the eight-second entry. **Since ADR 2026-09-05h §4 that direct SQL runs only through a logged break-glass session (§3.1); the query itself is unchanged, the discipline around it is not.**

## 6. Open items ⚠️
~~1. Four-eyes threshold values.~~ Ruled by irreversibility, §3 (ADR 2026-09-05h §8). ~~2. IP allowlist vs device-bound admin sessions.~~ Identity-aware proxy/VPN, §3 (ADR 2026-09-05h §11). ~~3. Whether the member-visible transparency log ships at Phase 1 or Phase 2.~~ Phase 1 (ADR 2026-09-05h §11). 4. Data-residency for staff access — India, per ADR 2026-09-05c §1; the staff access policy is §3/§3.1/§7. 5. Lookup-quota and velocity numbers per role (M13). 6. Off-box log store choice (M13).

## 7. DPDP & legal 🔒 (ADR 2026-09-05h §10)
- A **named grievance officer** with a published SLA (⚠️ window set against the final DPDP rules, 06 §11.3).
- **Data-principal request intake** — access, correction, erasure — resolving to 06 §9.2 (export, always available) and 06 §9.3 (deletion, user-device-initiated). The console records the request and its resolution; it cannot perform either itself.
- **Breach-notification runbook** to the Data Protection Board and to affected members, rehearsed with the restore drill.
- **Law-enforcement path:** one named handler; we can hand over **only** what 06 §9.1 lists — metadata plus ciphertext — and the request, the handler and what was produced are logged; a **transparency count** is published periodically.
