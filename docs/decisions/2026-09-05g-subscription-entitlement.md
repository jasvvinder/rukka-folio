# ADR 2026-09-05g — Subscription & entitlement: the one server key, quotas, two graces, and what a lapse may never do

Part of the seven-spec fan-out review of 5 Sep 2026 (after ADRs 2026-09-05 → 05d on the security
core). 08 got the two hardest things right — *lapsed ≠ locked* and *never per transaction* — and it
is honest about the iOS problem. But it is the thinnest spec relative to its blast radius: it owed
ADR 2026-09-05b §7 quota numbers it had not written, its "server-attested plan state" named a
signing key that exists nowhere in 04, its 🔒 checkout (coupon + GSTIN + our invoice) cannot be
delivered on the IAP path §3.2 recommends, and a content-blind free tier with no byte cap is free
encrypted file hosting. Owner ruled 5 Sep 2026: **"accept all recommendations"** (decision sheet
items 22–28 plus every reviewer gap).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The entitlement token — the only new server key in the system
The server holds **one Ed25519 signing key** (`entitlement_key`, rotated annually with a 30-day
overlap; ⚠️ Supabase Vault vs cloud KMS decided with the phone key, ADR 2026-09-05c open 2). It
signs an **entitlement token** per tenant:

```
{ tenant_id, plan, limits{members, business_books, devices, envelopes_per_book,
  tenant_bytes, attachment_bytes}, period_end, grace_kind, iat, exp }    exp − iat ≤ 30 d
```

The public key ships **pinned in the app beside the SPKI pins** (05 §1, ADR 2026-09-05 §1) and is
listed in 04 §4 as plaintext material and in 04 §8.6 as the second and last thing the server may
sign. Tokens travel on the meta channel (05 §5) and are refreshed on every meta pull. A tenant with
no valid token is *Free*, never *locked*. Nothing about a token is content: the server signs what
it already knows.

### 2. Enforcement — hard server-side, soft client-side, never on content
**Hard caps** are enforced by the server at the three plaintext choke points: invite creation
(seats), book creation (business books), device registration (devices) — plus envelope push
(quota, 05 §3). **Soft** enforcement is anything the client does from the token: the export
watermark, upgrade nudges, read-only banners. A rooted phone can defeat soft enforcement (ADR
2026-09-05 §6 warns, never blocks); stated in the same register as 05b §7 — *that is the whole
defence*, and it is enough because the watermark is marketing, not security.

### 3. Quotas — the numbers ADR 2026-09-05b §7 assigned to 08
| Limit | Free | Personal | Family | Family+ |
|---|---|---|---|---|
| Active members (seats, §6) | 1 | 1 | 5 | 15 |
| Business books | 1 | ∞ | 3 | ∞ |
| Devices per user (§7) | 5 | 5 | 8 | 15 |
| Envelopes per book | 10 k | 100 k | 250 k | 1 M |
| Tenant envelope bytes | 250 MB | 2 GB | 5 GB | 15 GB |
| Attachment bytes | 100 MB | 2 GB | 5 GB | 20 GB |
| Per-file cap | 10 MB | 10 MB | 10 MB | 10 MB |

**Rate limits are plan-independent:** 600 envelopes / min, 5,000 / h, 50 MB / day per device
(closes 05b §7's ⚠️ and 05 §3's two proposal notes). At **80 %** of any byte or count quota the
book shows a warning; at **100 %** push answers `rejected:quota` and the Inbox card says *"This
book is full — upgrade the plan"*. **Reads, pulls, statements and exports are never blocked** by a
quota. Why the bytes cap matters beyond cost: under the IT Rules 2021 we cannot take down what we
cannot see, so a byte cap is the only abuse control a zero-knowledge store can have.

### 4. Two graces, named apart
- **Dunning grace** — tenant-wide, after a *failed renewal*: 7 days from `period_end`, then
  read-only. Server-declared in the token (`grace_kind = dunning`, `grace_until`).
- **Offline grace** — device-local, when the phone has *not reached the server*: runs from the
  **last entitlement token seen**, not from `period_end`. Read-only engages only after the device
  has actually reached the server **and been told lapsed**. A renewed-by-autopay tenant on a phone
  that is off-network for three weeks never goes read-only.
- **Clock floor:** entitlement time = `max(local clock, highest server timestamp seen)`. A
  rolled-back clock cannot extend an entitlement; a rolled-forward one cannot lapse a paid tenant.
- 13's Subscription state machine names both graces (owned by the UX catch-up ADR, 2026-09-05f).

### 5. Lapsed ≠ locked, made precise
Expiry → **read-only + full export forever** (08 §1.4 stands). Watermark applies to **reports
(PDF) only, never to the CSV/XLSX data export** — 06 §9.2's *plan-independent export* is therefore
literally true. 04 §7.6's monthly readable export is **not plan-gated** (watermark only on Free).
**Long-lapsed retention:** 24 months with no login → three notices (WhatsApp/SMS/email over 90
days) → envelopes move to **cold storage** (03 §6), still pullable on next login. **Never
deletion.** The books are the family's; we only stop keeping them hot.

### 6. Seats are countable — around, not through
The seat cap counts **`invited` + `joined_pending_verification` + `active`** (06 §7), so five
outstanding invites on a 5-seat plan with one active member is 6 and is refused. Removal frees the
seat immediately. Re-inviting the **same `user_id` within 30 days** does not consume a new seat. A
**rolling cap of 2 × seats distinct members per year** stops seat rotation. Excess on downgrade:
nothing deleted, excess members keep read access (08 §3 stands).

### 7. Payer, tenants and the personal book
`subscriptions.payer_user_id`: **only a tenant admin may purchase**; the personal book is covered
by its **owning tenant's plan** (there is no personal-book plan). **Device cap per user = the
highest cap among the user's active tenants** (06 §6 amended — a Family+ member is not throttled
by also belonging to a Free tenant). One user, many tenants, each tenant one bill.

### 8. Channels — IAP on iOS, gateway elsewhere, web for GST buyers
**Option 1 of 08 §3.2 is ruled:** In-App Purchase on iOS, gateway (Razorpay/Cashfree ⚠️) on
Android and web. **Web-first checkout for GSTIN buyers** — Apple/Google are merchant of record on
IAP, so no input credit and no invoice from us there; the iOS plan screen says *"Buying for a
business? Get a GST invoice at rukka.in"* (⚠️ verify current App Store India rules on
external-link wording at M13). **Single INR price on every channel** — we absorb the commission;
platform-differentiated pricing is legal but unexplainable in-app. Enrol in the **Small Business
Program** at M13. Google Play India **user-choice billing** is adopted where offered. §3.2's
"decision needed" is closed.

### 9. Billing plumbing — a table, not a sentence
```
billing_events(event_id pk, gateway, type, payload_hash, received_at, applied_at null)
subscriptions(tenant_id pk, plan, status, gateway, gateway_ref, current_period_end,
        source text check (source in ('razorpay','apple','google','manual')),
        original_transaction_id, payer_user_id, trial_end, grace_until, grace_kind,
        cancel_at_period_end bool, seats_addon int, dispute_state, updated_at)
```
Every webhook: **signature verified**, **deduped on `event_id`** (05 §5's replay test now has
something to test), **out-of-order guard** (apply only if the event's sequence/timestamp is newer
than the last applied for that subscription), **daily reconciliation poll** against the gateway.
`updated_at` exists because 05 §5's meta cursor is `updated_at,id` — without it plan changes could
not sync. **RBI e-mandate 24 h pre-debit notification** is a regulatory message delivered by the
gateway/bank, distinct from our T-15/T-3/T-0 nudges; 08 §3 says so.

### 10. GST and invoicing
Prices are **integer paise, GST-inclusive at 18 %** (rule 1 — no float ever); tax split half-up to
the paisa; invoice `round_off` to the rupee shown as a line; **continuous per-FY invoice serial**;
SAC code ⚠️ (confirm 998314/9973-class at M13); **credit note on refund**. **Recipient state is
captured for GSTIN buyers only** — this *is* the one conditional address field 06 §9.1 allows, and
06 §9.1 now says so.

### 11. Refunds and chargebacks
The **15-day no-questions refund is scoped to gateway purchases**. IAP refunds belong to Apple /
Google: our copy is *"we will support your request with Apple/Google"* and support consents via
the store server APIs. Any refund or chargeback → **entitlement ends now, data untouched** (read-
only, export forever). **One refunded purchase per user, lifetime** (not per tenant). Refunds go
**only to the original instrument** — the gateway holds it, we never do.

### 12. Trial and promo abuse
Trial is **once per user**: `users.trial_consumed_at` (03 §2.1), not per tenant. **Free tenants
per user capped at 2** ⚠️. Promo codes: `promo_codes(code pk, max_redemptions, per_user_limit,
first_purchase_only, valid_from, valid_to)` + `promo_redemptions`; **server-validated, never
stacked**.

### 13. Admin billing powers, enumerated once
08 §4 lists what 12 §1 may do, and 12 may not exceed it: change plan; **manual plan grant**
(NGO / pilot, with reason and expiry); **promo code create/disable**; **dunning state view**;
**refund to original instrument only**; **webhook replay** (idempotent by `event_id` — a replay can
never double-refund or double-extend); invoice re-issue. Anything else is a spec change.

### 14. Organizations above 15 members
No tier exists today. **Ruled explicitly, not silently:** organizations use the Family bands up to
15; a dedicated per-member band above 15 is **decided at the pilot** with a real gurudwara's
committee size in hand. Until then a 40-trustee committee is told so on the plan screen, not
refused.

## Declined / deferred
- Per-transaction or per-envelope pricing — structurally impossible and stays so (08 §1.3).
- Platform-differentiated pricing to offset Apple's cut — declined; one price.
- A personal-book plan separate from the tenant — declined; it is covered by the owning tenant.
- Deleting long-lapsed data — declined forever; cold storage only.

## What changed where
08 §1.4 (lapsed precision, retention), §2 (quota table columns, trial/free-tenant rules,
organizations line), §3 (token, hard/soft, two graces, clock floor, RBI notice), §3.1 (GST
capture web-only), §3.2 (decision closed → option 1), §4 (billing tables, refunds, admin powers),
§5 (tests) · 03 §2.1 (`trial_consumed_at`), §2.4 (`subscriptions` columns, `billing_events`,
promo tables), §6 (long-lapsed cold storage) · 04 §4 (entitlement public key as plaintext), §8.6
(the second and last server signature) · 05 §3 (rate/quota numbers ruled), §5 (token on meta;
`updated_at`) · 06 §6 (device cap = highest across tenants), §7 (seat counting), §9.1 (state for
GSTIN buyers) · 09 suite G · 10 M13 row, Phase 2 attachment row (quota, not a tier).
Code lands at M13 (server: token issuance, hard caps, billing_events, promo; client: token cache,
graces, clock floor, watermark) and M4 (05 §3 `rejected:quota` numbers, rate limits).

## Open ⚠️
1. Gateway choice (Razorpay vs Cashfree) by UPI Autopay support and fees at M13 (08 §4 stands).
2. SAC code and the App Store India external-link wording for the GST web-checkout pointer.
3. Free tenants per user — 2 proposed; confirm against pilot behaviour.
4. Key custody for `entitlement_key` (Vault vs KMS) — decided together with 05c's phone key.
5. Organization band above 15 members — pilot.
