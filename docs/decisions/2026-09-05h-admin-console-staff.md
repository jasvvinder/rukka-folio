# ADR 2026-09-05h — Admin console & staff: the insider is in the threat model now

Part of the seven-spec fan-out of 5 Sep 2026 (after the four ADRs 2026-09-05 / 05b / 05c / 05d).
12 gets the hardest thing right: it is a **metadata console**, and it publishes what staff *cannot*
do because the maths forbids it. But it was written before today's ADRs and now under-states the
constraints in three places (device revoke, phone ciphertext, server rows as copies) and over-states
staff power in one (tenant freeze, which 06 §8 does not grant). Its structural absence is the
**insider threat model**: one undifferentiated "admin" role, no break-glass discipline for the
privileged paths 05c created, and no rate limits on staff lookups. Owner confirmed 5 Sep 2026
("accept all recommendations").

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Tenant freeze exists — narrowly, and it belongs to 06 §8
**Grounds, exhaustive:** payment fraud · legal order · abuse (flood or harassment of members).
Anything else is not a freeze. **Definition:** the server refuses that tenant's pushes with
`rejected:tenant_frozen` — the same shape as `membership_not_active` (05 §3). **Pull, decrypt,
read, and export are untouched**; a frozen family can still see and take its books. Four-eyes
(ruling 8); **hard expiry ≤ 30 days**, renewal is a fresh four-eyes decision with a fresh reason;
every member device receives a plain notice naming the ground class and the expiry. Freeze is
added to 06 §8's Support CAN list with these grounds, because 06 owns support powers — 12 never
grants what 06 does not. A frozen tenant is distinct from 08 §3's client-side lapsed read-only,
which blocks nothing server-side.

### 2. Delayed, cancellable, and never twice without a human
- **Device revocation** by support follows ADR 2026-09-05d §3: a 24 h window, cancellable from any
  certified device. The console shows the **pending-window state** — who requested it, when it
  lands, and the cancel — and it lands **unsigned**, so the target suspends and never wipes
  (ADR 2026-09-05b §2). **After a user cancel, the same device may not be re-revoked** without
  four-eyes plus a fresh callback; otherwise support becomes a harassment loop.
- **Account deletion** is never started by support. Support sends a **deletion request to the
  user's devices**; the user's own certified device starts the 15-day clock (06 §9.3). Nothing in
  the console can begin a countdown that ends in a hard-deleted personal book.

### 3. Phone numbers: looked up, never rendered
The admin database role has **no KMS decrypt grant** for `phone_ct` (ADR 2026-09-05c §4). Staff
*look up* by number: the console computes `phone_hmac` from the typed digits and finds the user.
No screen, export, log line or API response renders a number, ever — not even masked. The same
holds for invitees (there is no plaintext to render; 05c §4). The console carries its **own
explicit column allowlist** per table — it no longer points at 03 §4's plaintext table, which
describes the member API, not staff eyes.

### 4. Break-glass doctrine (new 12 §3.1)
The privileged paths created this week — backup access (05c §1), the `maintenance` deletion role
(05b §8 / 03 §2.5), the phone KMS key (05c §4), and Phase 0's "direct SQL, run by you" — get one
doctrine: **named accounts** (never shared), **hardware key**, **two-person authorisation**,
**short-lived brokered credentials** (no standing human access to maintenance, backup or KMS —
credentials are minted for the session and expire with it), **session recorded**, **alert to a
second channel** when opened, **post-hoc review within 24 h** by someone who did not open it.
Phase 0 direct SQL runs **only through a logged session** under this doctrine; the "just run a
query" era ends with this ADR. The restore runbook includes the **`store_epoch` bump**
(05c §1, 05b §6) as a checklist item with the reviewer's initials.

### 5. Insider scraping
Per-staff **lookup quotas** with **velocity alerts** (a support agent does not open 200 tenants an
hour). Per-user **security telemetry** — recovery requests, escrow countdowns, mismatch events —
is visible **only on an open ticket** for that user; the dashboard shows aggregates. Every write
requires a **ticket id** beside the typed reason. Rationale: 12 §1's telemetry is exactly what an
insider would use to time a social-engineering call.

### 6. Staff audit log has integrity, not just append-only
**Hash-chained**, **shipped off-box** to a store the admin role cannot write, **reads logged as
well as writes**, **exportable per tenant**, retained **≥ 3 years**. It is explicitly **outside**
03 §6's 24-month `audit_events` aggregation — two stores, two retention rules; the purge job must
never see the staff log.

### 7. Staff roles and lifecycle
Five roles: **support-L1**, **billing**, **SRE**, **security-compliance**, **super-admin**.
The four-eyes approver is **a different human on a different role**. **SSO-driven
joiner-mover-leaver** (an ex-employee's access dies with their identity, not with a ticket);
**quarterly access review** with a signed record.

### 8. Four-eyes by irreversibility, not by value
Four-eyes is required for: **any refund > ₹5,000**, **any freeze**, **any deletion request**,
**any `min_client_version` or production feature-flag change**, **any break-glass**. Value
thresholds are not the interesting axis; irreversibility is.

### 9. Platform config is a kill switch and is governed like one
`min_client_version` (06 §4.5) can brick every client with one wrong bump. Every platform-config
write: four-eyes, **staged rollout with a canary cohort**, **one-click rollback**, and the change
recorded as a **config version** (diff, author, approver, time).

### 10. DPDP & legal (new 12 §7)
A **named grievance officer** with an SLA; **data-principal request intake** (access, correction,
erasure) that resolves to 06 §9.2 (export) and 06 §9.3 (deletion); a **breach-notification
runbook** to the Data Protection Board; a **law-enforcement path**: we can hand over **only** 06
§9.1 metadata plus ciphertext, one named handler, a **transparency count** published periodically.

### 11. Smaller rulings
- **Member-visible transparency event** for staff access ships at **Phase 1** — one row, and it
  is the claim.
- **Session recording** = metadata plus justification, not screen capture; PII minimisation
  already keeps content off the screen.
- **Phase 1 does not ship with fewer than two staff accounts held by two people**; four-eyes is
  impossible otherwise.
- **Webhook replay** is a console action (08 §4 grants it; 12 lists it): replays carry the
  gateway's original event id as idempotency key and re-verify the signature, so a replay can
  never double-refund. 08 owns billing powers; 12 enumerates only what 08 grants (ADR 2026-09-05g).
- **Refunds go only to the original instrument** — the gateway holds it; there is no "pay out to
  another account" path. Added to §2's structural table.
- **Hosting:** identity-aware proxy or VPN, **no public DNS**, a domain sharing **no cookie scope**
  with the member app; "IP-allowlisted" is retired as too thin.
- **Console idle re-auth 30–60 min on the write path**; the ≤ 8 h session stays for read.
- §2's "override a role / add a member" row gains its second reason: after ADR 2026-09-05b §1 a
  hand-edited row is *detected* by clients as `meta_mismatch`, not merely useless.
- **Suite G (09)** gains: grant set excludes blobs; every write yields an audit row **and** a
  member-visible event; four-eyes cannot be self-approved; the lookup limit trips.

## Declined / deferred
- Full screen-recording of staff sessions — metadata plus justification suffices while the console
  structurally shows no content; revisit if a content-adjacent surface ever appears.
- IP allowlisting as the primary control — replaced by identity-aware access (ruling 11).
- Per-tenant staff access policies (enterprise/NGO deals, 12 §5 Phase 3) — parked until Phase 3.

## What changed where
12 §1 (capability table: freeze grounds, pending revocation, deletion request, phone lookup,
webhook replay), §2 (two structural rows), §3 (roles, four-eyes list, audit chain, hosting,
re-auth) + new §3.1 break-glass, §4 (own allowlist), §5 Phase 0 (logged session), §6 (items
resolved), new §7 DPDP & legal · 06 §8 (Support CAN: freeze with grounds; deletion = request
only; revocation pending window) · 03 §2.4 (staff log is a separate store), §6 (retention
separation) · 05 §3 (`rejected:tenant_frozen` row) · 09 suite G · 10 M13/M14 rows.

## Open ⚠️
1. Grievance officer SLA and Data Protection Board notification window — set against final DPDP
   rules (06 §11.3).
2. Lookup-quota and velocity numbers per role — set at M13 with the first support runbook.
3. Off-box log store choice (append-only object store with object lock vs. a managed SIEM) — M13.
