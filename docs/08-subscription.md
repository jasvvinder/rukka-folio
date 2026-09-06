# 08 — Subscription & Enforcement

**Status:** Draft 1. Prices are placeholders pending a competitor check at launch (⚠️ verify Vyapar/Khatabook/Tally current pricing — figures in this repo date from May 2026 knowledge).

## 1. Principles 🔒
1. **Price the family, not the seat.** Per-seat pricing makes the karta share one login and kills collaboration.
2. **Annual billing** (UPI Autopay e-mandate where possible ⚠️ verify current RBI e-mandate limits); monthly only as a fallback.
3. **Never charge per transaction** — and structurally can't: the server can't count them (03 §4).
4. **Lapsed ≠ locked 🔒:** expiry → read-only + full export forever. Data is never held hostage; this is a trust feature and a marketing claim. **Made precise (ADR 2026-09-05g §5):** the watermark applies to **reports (PDF) only, never to the CSV/XLSX data export** (06 §9.2 stays literally true); 04 §7.6's monthly readable export is not plan-gated. **Long-lapsed:** 24 months with no login → three notices over 90 days → envelopes move to cold storage (03 §6), still pullable on next login. **Never deletion.**

## 2. Tiers (INR/year, placeholder)
| Tier | Limits (plaintext metadata) | Price |
|---|---|---|
| **Free** | 1 member, personal + 1 business book, exports watermarked | ₹0 |
| **Personal** | 1 member, unlimited books, clean exports, statement import | ₹599 |
| **Family** | ≤ 5 active members, ≤ 3 business books | ₹1,999 |
| **Family+** | ≤ 15 active members, unlimited business books | ₹3,999 |

**Quotas 🔒 (ADR 2026-09-05g §3 — the numbers ADR 2026-09-05b §7 assigned here):**

| Limit | Free | Personal | Family | Family+ |
|---|---|---|---|---|
| Devices per user (= highest across the user's active tenants, 06 §6) | 5 | 5 | 8 | 15 |
| Envelopes per book | 10 k | 100 k | 250 k | 1 M |
| Tenant envelope bytes | 250 MB | 2 GB | 5 GB | 15 GB |
| Attachment bytes | 100 MB | 2 GB | 5 GB | 20 GB |
| Per-file cap | 10 MB | 10 MB | 10 MB | 10 MB |

Rate limits are plan-independent: 600 envelopes/min, 5,000/h, 50 MB/day per device (05 §3). 80 % → warning; 100 % → `rejected:quota`, Inbox *"This book is full — upgrade the plan"*; **reads, pulls, statements and exports are never blocked.** The byte cap is also the only abuse control a zero-knowledge store can have (IT Rules 2021: we cannot take down what we cannot see).

Organizations (trusts): Family tiers apply by member count up to 15; **a dedicated per-member band above 15 is decided at the pilot** with a real committee's size in hand — until then the plan screen says so rather than refusing (ADR 2026-09-05g §14). Trial: 30 days of Family, **once per user** (`users.trial_consumed_at`, 03 §2.1), not per tenant; **free tenants per user capped at 2 ⚠️**; promo codes are server-validated with `max_redemptions`, `per_user_limit`, `first_purchase_only`, never stacked (ADR 2026-09-05g §12). The free tier is the distribution channel — one brother tries it, the family upgrades.

## 3. Enforcement 🔒
- Enforced **only** on plaintext metadata: active-membership count, business-book count, device count (06 §6), export watermark flag. Enforcement points: invite creation, book creation, device registration, export generation (client-side flag, server-attested plan state).
- **The entitlement token 🔒 (ADR 2026-09-05g §1):** "server-attested" means an Ed25519 token `{tenant_id, plan, limits, period_end, grace_kind, iat, exp ≤ 30 d}` signed by the **one server signing key** (`entitlement_key`, 04 §8.6), public key pinned in the app beside the SPKI pins (05 §1), delivered on the meta channel (05 §5). **Hard** caps (seats, business books, devices, quota) are enforced server-side at invite, book-create, device-register and push; **soft** enforcement (watermark, nudges, banners) is client-side from the token and a rooted phone can defeat it — that is the whole defence and it is enough (ADR 2026-09-05g §2).
- **Seats count `invited` + `joined_pending_verification` + `active`** (06 §7); removal frees the seat at once; re-inviting the same `user_id` within 30 days is free; rolling cap of 2 × seats distinct members per year (ADR 2026-09-05g §6). **Payer:** `subscriptions.payer_user_id`, only a tenant admin may purchase; the personal book is covered by its owning tenant's plan (ADR 2026-09-05g §7).
- **Two graces, named apart 🔒 (ADR 2026-09-05g §4).** *Dunning grace* (tenant-wide, failed renewal): 7 days from `period_end`, server-declared in the token, then read-only. *Offline grace* (device-local): runs from the **last entitlement token seen**, and read-only engages only after the device has reached the server **and been told lapsed** — a renewed tenant on a phone off-network for three weeks never goes read-only. Clock floor = `max(local, highest server timestamp seen)`: a rolled-back clock cannot extend, a rolled-forward one cannot lapse.
- Downgrade with excess members/books: nothing is deleted; excess books go read-only, excess members keep read access; owner chooses what stays active.
- UX: renewal nudges at T-15/T-3/T-0 (content-free notifications); read-only mode banners explain and one-tap renew; **entry of new data is the only thing a lapse ever blocks.** The RBI e-mandate **24 h pre-debit notification** is a regulatory message sent by the gateway/bank and is distinct from these nudges (ADR 2026-09-05g §9).

## 3.1 Upgrade flow 🔒 (owner-approved)
Plan comparison screen with a **Monthly / Annual toggle showing the saving** ("Annual — save 20%"), plan cards with a *popular* badge on the recommended tier, optional add-on seats, then checkout: **coupon-code field**, **GSTIN capture for our own invoice** (business buyers want the input-credit), UPI/card/netbanking. **Coupon and GSTIN exist on the gateway/web checkout only** — on IAP Apple/Google are merchant of record, so the iOS plan screen points GST buyers to web checkout (ADR 2026-09-05g §8, §10). Prices are integer paise GST-inclusive at 18 %, half-up to the paisa, invoice `round_off` to the rupee, continuous per-FY serial, credit note on refund; recipient state captured for GSTIN buyers only (06 §9.1). On success: invoice generated and delivered by **email *and* WhatsApp** (our users live on WhatsApp). Failure → inline error + retry or alternate method, never a dead end.

## 3.2 App Store consequence of shipping iOS first — 🔒 **ruled option 1 (ADR 2026-09-05g §8)**

**Ruling:** IAP on iOS, gateway on Android/web, **web-first checkout for GSTIN buyers**, **single INR price on every channel** (we absorb the commission), Small Business Program at M13, Google Play India user-choice billing where offered. The options below are kept for the record.
Apple requires digital subscriptions to be sold through **In-App Purchase** (commission ~30%, or 15% under the Small Business Program — verify current terms). Our Razorpay/UPI-Autopay plan is an *external* payment path and would be **rejected on iOS** for unlocking in-app features. Options:
1. **IAP on iOS, gateway on Android/web** — compliant, but two billing systems and Apple's cut. Under the Small Business Program (< $1M/yr, which we are) 15% on ₹1,999 ≈ ₹300.
2. **"Reader"/external-link route** — permitted in some jurisdictions and under India's CCI-driven changes ⚠️ verify current App Store rules for India before relying on it.
3. **Sell nothing in-app on iOS** — account purchased on the web, app only signs in. Legal, common, but hurts conversion badly for our audience.
**Recommendation:** option 1, with prices set so the post-commission net matches the Android net; enrol in the Small Business Program from day one. Decide before M13.

## 4. Billing plumbing 🔒
Razorpay or Cashfree (⚠️ pick by current UPI Autopay support + fees): webhooks → `subscriptions` (03 §2.4); gateway holds instruments, we hold reference IDs only; invoices for our subscription emailed/WhatsApped as PDF. Refunds: 15-day no-questions on first purchase. Admin panel (internal, tiny): tenants, plan, renewal, device counts, webhook replay.

**Plumbing rules 🔒 (ADR 2026-09-05g §9):** every webhook is signature-verified, deduped on `event_id` in `billing_events` (03 §2.4), guarded against out-of-order delivery, and reconciled by a daily poll against the gateway. `subscriptions` carries `source ∈ {razorpay, apple, google, manual}`, `original_transaction_id`, `payer_user_id`, `trial_end`, `grace_until`, `grace_kind`, `cancel_at_period_end`, `seats_addon`, `dispute_state`, `updated_at` (05 §5's meta cursor).

**Refunds 🔒 (ADR 2026-09-05g §11):** the 15-day no-questions refund is scoped to **gateway purchases**; IAP refunds belong to Apple/Google ("we will support your request"). Refund or chargeback → entitlement ends now, data untouched (read-only, export forever). One refunded purchase per user, lifetime. Refunds go only to the original instrument.

**Admin billing powers — the complete list (ADR 2026-09-05g §13; 12 §1 may not exceed it):** change plan · manual plan grant (reason + expiry) · promo code create/disable · dunning state view · refund to original instrument · webhook replay (idempotent by `event_id`) · invoice re-issue.

## 5. Acceptance tests (excerpt)
- Family at 5/5 members: 6th invite blocked with upgrade path; nothing else degrades.
- Expiry +7 days offline: entry still works; +8: read-only with banner; export still produces a complete, unwatermarked file for a previously-paid tenant.
- Webhook replay is idempotent; a failed renewal never deletes or hides data.
- No API path counts, sums, or gates on envelope contents (endpoint inventory test shared with 06 §10).
- **ADR 2026-09-05g:** a forged or expired entitlement token is rejected by the pinned public key; 5 outstanding invites + 1 active member on a Family plan refuse the 6th invite; a device that has not reached the server stays writable indefinitely and goes read-only only after the server says *lapsed*; a clock rolled back a year does not extend entitlement; a book at 100 % quota refuses push with `rejected:quota` while pull, statement and export succeed; a replayed webhook applies once; a refund ends entitlement and deletes nothing; the same user's second tenant gets no trial; the CSV export of a Free tenant carries no watermark while its PDF report does.
