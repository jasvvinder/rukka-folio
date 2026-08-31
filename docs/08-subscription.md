# 08 — Subscription & Enforcement

**Status:** Draft 1. Prices are placeholders pending a competitor check at launch (⚠️ verify Vyapar/Khatabook/Tally current pricing — figures in this repo date from May 2026 knowledge).

## 1. Principles 🔒
1. **Price the family, not the seat.** Per-seat pricing makes the karta share one login and kills collaboration.
2. **Annual billing** (UPI Autopay e-mandate where possible ⚠️ verify current RBI e-mandate limits); monthly only as a fallback.
3. **Never charge per transaction** — and structurally can't: the server can't count them (03 §4).
4. **Lapsed ≠ locked 🔒:** expiry → read-only + full export forever. Data is never held hostage; this is a trust feature and a marketing claim.

## 2. Tiers (INR/year, placeholder)
| Tier | Limits (plaintext metadata) | Price |
|---|---|---|
| **Free** | 1 member, personal + 1 business book, exports watermarked | ₹0 |
| **Personal** | 1 member, unlimited books, clean exports, statement import | ₹599 |
| **Family** | ≤ 5 active members, ≤ 3 business books | ₹1,999 |
| **Family+** | ≤ 15 active members, unlimited business books | ₹3,999 |

Organizations (trusts): Family tiers apply by member count ⚠️ revisit if trust demand warrants its own tier. Trial: 30 days of Family on first tenant creation. The free tier is the distribution channel — one brother tries it, the family upgrades.

## 3. Enforcement 🔒
- Enforced **only** on plaintext metadata: active-membership count, business-book count, device count (06 §6), export watermark flag. Enforcement points: invite creation, book creation, device registration, export generation (client-side flag, server-attested plan state).
- Client caches signed plan state; **7-day offline grace** beyond `current_period_end` before read-only engages (rural reality).
- Downgrade with excess members/books: nothing is deleted; excess books go read-only, excess members keep read access; owner chooses what stays active.
- UX: renewal nudges at T-15/T-3/T-0 (content-free notifications); read-only mode banners explain and one-tap renew; **entry of new data is the only thing a lapse ever blocks.**

## 3.1 Upgrade flow 🔒 (owner-approved)
Plan comparison screen with a **Monthly / Annual toggle showing the saving** ("Annual — save 20%"), plan cards with a *popular* badge on the recommended tier, optional add-on seats, then checkout: **coupon-code field**, **GSTIN capture for our own invoice** (business buyers want the input-credit), UPI/card/netbanking. On success: invoice generated and delivered by **email *and* WhatsApp** (our users live on WhatsApp). Failure → inline error + retry or alternate method, never a dead end.

## 3.2 App Store consequence of shipping iOS first ⚠️ **decision needed**
Apple requires digital subscriptions to be sold through **In-App Purchase** (commission ~30%, or 15% under the Small Business Program — verify current terms). Our Razorpay/UPI-Autopay plan is an *external* payment path and would be **rejected on iOS** for unlocking in-app features. Options:
1. **IAP on iOS, gateway on Android/web** — compliant, but two billing systems and Apple's cut. Under the Small Business Program (< $1M/yr, which we are) 15% on ₹1,999 ≈ ₹300.
2. **"Reader"/external-link route** — permitted in some jurisdictions and under India's CCI-driven changes ⚠️ verify current App Store rules for India before relying on it.
3. **Sell nothing in-app on iOS** — account purchased on the web, app only signs in. Legal, common, but hurts conversion badly for our audience.
**Recommendation:** option 1, with prices set so the post-commission net matches the Android net; enrol in the Small Business Program from day one. Decide before M13.

## 4. Billing plumbing 🔒
Razorpay or Cashfree (⚠️ pick by current UPI Autopay support + fees): webhooks → `subscriptions` (03 §2.4); gateway holds instruments, we hold reference IDs only; invoices for our subscription emailed/WhatsApped as PDF. Refunds: 15-day no-questions on first purchase. Admin panel (internal, tiny): tenants, plan, renewal, device counts, webhook replay.

## 5. Acceptance tests (excerpt)
- Family at 5/5 members: 6th invite blocked with upgrade path; nothing else degrades.
- Expiry +7 days offline: entry still works; +8: read-only with banner; export still produces a complete, unwatermarked file for a previously-paid tenant.
- Webhook replay is idempotent; a failed renewal never deletes or hides data.
- No API path counts, sums, or gates on envelope contents (endpoint inventory test shared with 06 §10).
