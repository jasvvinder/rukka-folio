# ADR 2026-09-25 — OTP by SMS, invitations from the inviter's phone, statement import, support, and plans per entity type

**Status:** accepted (owner-ruled, 24–25 Sep 2026, in one discussion of PLAN desk 2, desk 15, real prices and
the R2.1 canvas row)
**Amends:** 06 §2 (channels) · 06 §7 and ADR 2026-09-05c §4 (who sends the invite) · 07 §11 (inputs) · 07 §12 ·
07 §22, 13 §3.2 S17.3 and DESIGN-PACK S17.3 (support channel) · ADR 2026-09-19 ruling 2 (one more `url_launcher`
scheme) · 08 §1–§3 and ADR 2026-09-05g §1, §3–§5 (plans, trial, token) · 13 §10 item 11 · 07 §14 and 13 S4.2
(deferred) · 10 M10. Everything else in those documents stands.

## Context

The owner took the two open desk items (the §4 lead-times; the support WhatsApp handle), then real prices and the
R2.1 canvas row, one at a time. Each ruling below was taken from a recommendation with its evidence. Several
proposals were considered and dropped along the way: Firebase phone auth, carrier SIM checks, passkeys, cloud AI
for statements, and in-app human chat. They are recorded under *Not taken* so they are not re-proposed without new
facts. Two findings drove the pricing rulings. First, **Canvas 10 S12.1 was already book-based** (One book ₹990 ·
Family up to 8 books ₹2,499 · Trust ₹1,999), but no doc recorded it. Second, the code follows 08 §2's member and
business-book table (`tier_catalogue.dart:106–160`, `registry.ts:40–96`).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. OTP is sent by SMS, through the owner's own DLT registration ⟦tests: E-25-1 @M6, C-25-1 @M6⟧
- **Amends 06 §2** *"WhatsApp Business API first, SMS fallback, auto-failover"*. The one channel is **SMS**, sent
  by an Indian provider on the owner's own TRAI DLT registration (principal entity, sender ID and **one** OTP
  template). The provider stays behind `OtpProvider` (06 §2). `Msg91Provider` is the default unless the owner
  picks another; adding WhatsApp later is a provider configuration, not a redesign.
- Everything else in 06 §2 stands: the four moments OTP fires, 6 digits, 5-minute expiry, 3 attempts, resend
  backoff, per-number and per-IP limits, generic errors, the single-use activation ticket.
- Until DLT clears, the dev project uses fixed test codes (`FakeOtpProvider`). A fixed code never exists in a
  pilot or production project.

### 2. The inviter sends the invitation from their own phone ⟦tests: F1-25-1 @M7, E-25-2 @M7⟧
- **Amends 06 §7** (*"the plaintext goes into the outbound message job … delivery via WhatsApp/SMS link"*) **and
  ADR 2026-09-05c §4** (*"the plaintext goes only into the outbound OTP/WhatsApp message job"*).
- *Send invite* creates the invite on the server. The server stores its nonce and `invitee_hmac` only. The app
  then opens the platform share sheet with the link and a prefilled message, and the inviter sends it by whatever
  app they choose. **The server sends nothing.** The invitee's number reaches the server once, only to be hashed.
  *Resend* reopens the share sheet.
- Unchanged: the phone-plus-per-book-roles form (S9.1), *the link alone admits nobody* (ADR 2026-09-05d §9, locked),
  the ceremony, and the invite states and expiry.

### 3. Statement import: PDF with a password, CSV, XLS, and photo, all on the phone ⟦tests: F1-25-2 @M10, F1-25-3 @M10⟧
- **Extends 07 §11** (titled *Phase 1: file upload*). The inputs are **PDF, CSV, XLS, and a photo or screenshot of
  a statement**. Every input feeds the same automatic column detection, the one-time confirmation remembered per
  bank, the 🔒 balance check and the S7.4 preview. **There are no per-bank parsers**, which is what 07 §11 already
  rules; `10-roadmap.md` M10's *"PDF per-bank"* is corrected.
- **A locked PDF** asks *"This statement is locked — enter its password."* The password opens the file on the
  phone once. It is **never stored, remembered or sent**, and a wrong one says so and asks again.
- **A photo or screenshot** is read by the platform's on-device text recognition (Apple Vision on iOS, ML Kit on
  Android). A misread amount breaks the statement's running-balance chain at that row, and the row is marked for
  checking before anything posts.
- Every step runs on the phone (07 §11, 04: nothing readable leaves the phone). **No AI model and no server take
  part in this phase**; that question is reopened only by user feedback and a new ADR.
- Test fixtures are synthetic statements, one per bank, from SBI, Axis, HDFC and ICICI. The owner synthesises them
  from real exports on their own machine, so no real statement enters the repo.

### 4. Support: FAQs and email for the pilot, in-app AI chat before launch ⟦tests: F1-25-4 @M12⟧
- **Amends 07 §22, 13 §3.2 S17.3 and DESIGN-PACK S17.3** (*"WhatsApp primary … because these users will never
  email"*).
- **Pilot:** S17 FAQs plus **email** to `support@rukkafolio.com`. S17.3's primary action is *Email support*; S17.4's
  scrubbed report travels by email. The 🔒 statement of what support cannot do (06 §8) stays on the screen word for
  word.
- **Before public launch:** an **in-app AI chat** becomes the primary channel, with email as the hand-off to a
  person. The chat answers only from the FAQ and help articles and never improvises on key recovery. It tells the
  user not to share amounts or account numbers. Its build needs its own ADR, covering the provider, retention,
  where the provider processes the data (S18.3 promises *India*), and the S18.3 and 06 §9.1 wording.
- **Amends ADR 2026-09-19 ruling 2** by one scheme: `url_launcher` may also open **`mailto:` to the one support
  address**, behind the same kind of seam as `tel:`. No other URL is opened.

### 5. Plans follow the entity type chosen at signup; book-flow features are never restricted ⟦tests: G-25-1 @M13, G-25-2 @M13, G-25-3 @M13⟧
- **Replaces 08 §2's tiers and amends ADR 2026-09-05g §3.** Each entity type from S0.3 (07 §3.1.1) has **2–3
  plans**. They differ **only** by scale (books, people, devices, storage), statement import, and PDF output
  (PDF statements and reports, and sharing them). Each person's personal book is free and never counted.
- **Never restricted, on any plan including Free.** This is the owner's rule, and it extends 08 §1:
  - every entry verb, accounts, amend and reverse;
  - moving money between books and the cross-book match check (02 §6);
  - advances, roles, approvals and limits;
  - month close with the cash and gollak count, and year close with profit distribution;
  - every statement and report **on screen**, search and the Inbox;
  - recovery, guardians, the sheet and backup;
  - **Export everything** as CSV/XLSX (06 §9.2), and read-only rather than locked after a lapse (08 §1).
- **Individual** (*Myself*) has a permanent **Free** plan: the personal book only, no statement import, and **no
  PDF output**; statements stay readable on screen. This amends 08 §1's *watermarked PDF* rule for Free. The CSV
  and XLSX data export is untouched.
- **Family, Business and Trust** have **no Free plan and a 30-day trial**. The trial always runs on the entity
  type's **popular** plan, once per person (`users.trial_consumed_at`, 08 §2). When it ends unpaid, the shared
  books go read-only (08 §1) and the personal book stays free.
- **The popular plan is the intended buy.** The step below it sits just short of a typical household (a nuclear
  family; a joint family averages 2–3 sub-families) and close in price. The step above it is the anchor. S12.1
  shows only the user's entity type's plans, with the popular card emphasised and pre-selected. Every card stays
  visible and selectable, and nothing is hidden.
- **Working prices** (GST-inclusive per year; monthly is *ten months' price for twelve*). These are placeholders
  until the pilot and the Apple price-point check, and they live in the catalogue (§6), not in this ADR:

  | Entity | Plans (books · people) |
  |---|---|
  | Individual | Free ₹0 (personal only · 1) · Personal ₹990 (personal + 3 · 1) |
  | Business | Shop ₹2,499 (1 · 2, no import or PDF) · **Business ₹2,999** (5 · 10) · Business+ ₹6,999 (15 · 30) |
  | Family | Family Lite ₹1,999 (2 · 4, no import or PDF) · **Family ₹2,499** (8 · 12) · Family+ ₹5,999 (20 · 30) |
  | Trust | Trust ₹1,999 (3 · 15) · Trust+ ₹3,999 (10 · 40) |
- **13 §10 item 11** (*Business tier ₹2,999, Family stays ₹1,999*) is superseded by this table.
- **In force from the catalogue lane (M13).** Until it lands, 08 §2's table as written is the interim catalogue,
  so no shipped test asserts a superseded rule meanwhile.

### 6. Plans live in a server-side catalogue that the owner edits; a price or feature change needs no app release ⟦tests: E-25-3 @M13, G-25-4 @M13, F1-25-5 @M13⟧
- **Amends 08 §2–§3 and ADR 2026-09-05g §1, §3.** One server-side **plan catalogue** holds every plan: entity type,
  name, limits, included extras, prices in integer paise, and the popular flag. The server's enforced limits are
  read from it. `PLAN_LIMITS` in `registry.ts` stops being a hard-coded table. The app downloads the catalogue on
  the meta channel (05 §5) and renders S12.1 from it.
- **The owner edits it in the admin console** (12; ADR 2026-09-05h) under the console's four-eyes rule and
  hash-chained staff log. That log is the price history. Until the console exists, a catalogue change is a data
  change plus a server deploy, still with no app release.
- **The entitlement token gains `features`**: the included extras, for example statement import and PDF output.
  This amends the exact field set of 08 §3 🔒 and ADR 2026-09-05g §1. The app's gates read the token, so moving a
  feature between plans takes effect at the next sync. The token's `plan` becomes a catalogue id, not one of four
  fixed names.
- **On iOS** the price shown is Apple's live price for the product (StoreKit). The price itself is set in App
  Store Connect. On Android and the web it comes from the catalogue and the gateway.
- 08 §2 keeps the **rules** (§5); the **numbers** live in the catalogue. Changing a rule needs an ADR; changing a
  price does not.

### 7. Donation receipts move to the next phase ⟦tests: n/a — deferral; F1-07-* for S4.2 were never written⟧
- 07 §14's receipt card (S4.2, ADR 2026-09-02) is **not built in this phase**. Receipts will follow the Income Tax
  department's standard format, so the next phase reopens 07 §14's *"no tax language"* line with that format in
  hand. S4.2 is unbuilt today, so nothing is removed.

### 8. Earmarked trust funds are a candidate for after the pilot ⟦tests: n/a — candidate, no behaviour ruled⟧
- Donations tied to a purpose (*Building Fund*, *Langar Fund*), each reporting received, spent and balance, are
  **not modelled** today. 02 has one trust book with a computed Corpus (ADR 2026-09-05e §2). If adopted, this is a
  02 ledger feature for `core_ledger` with bookkeeper review, decided with real committees at the pilot. Until
  then, the trust plans count **trust books**, not funds.

## Not taken (do not re-propose without new facts)
- **Firebase phone auth.** It avoids DLT, but it is a second vendor, Google sees every number, and delivery to
  DND numbers is unproven. The owner prefers one place plus their own DLT.
- **Carrier SIM checks.** Apple offers no API for them; Android's number is unreliable. Silent network
  authentication needs an aggregator, fails on Wi-Fi and still needs an OTP fallback.
- **Passkeys, authenticator apps.** Routine login is already a device signature plus biometric or PIN (06 §4),
  and the number is needed for invitations (05d §9). Passkeys remain a possible next-phase path for a new phone.
- **Cloud or "confidential" AI on statements.** It contradicts *nothing readable leaves the phone*.
- **In-app human chat for support.** Email is the human channel. The in-app thread is the AI chat (§4).

## Consequences
- **Code — superseded now (ADR 2026-09-05i §4), in this commit:**
  - `F1-07-397` (the S17.3 WhatsApp row) is `@Skip('superseded by ADR 2026-09-25 §4; re-lands at M12')`.
  - Mixed tests lose only their WhatsApp assertions; their 🔒 checks keep running: `E-06-1` (generic answers,
    rate limits, backoff, nothing stored on total failure), `C-06-7` (one post, channel as state, no phone or code
    in the log) and `F1-06-5` (the 426 gate).
- **Code — build rows:**
  - **OTP1** (`lane-server` + `lane-ui`, M6): SMS-only provider path and default channel; drop the WhatsApp
    fallback line on S0.2.
  - **INV1** (`lane-ui`, M7): share sheet after invite creation.
  - **IMP3** (`lane-ui`, M10): PDF password prompt and OCR photo input behind seams, plus dependency ADRs for the
    PDF and text-recognition packages. The PDF package must open encrypted PDFs.
  - **SUP1** (`lane-ui`, M12): S17.3 email primary through a `mailto:` seam.
  - **CAT1** (`lane-server` xhigh, then `lane-ui`, M13): the catalogue table, `registry.ts` reading it, token
    `features`, S12.1 per entity type, the Free-plan PDF gate, and trial-on-popular. The tests pinned to 08 §2's
    numbers are rewritten in that lane.
- **Docs:** cross-reference lines are added at 06 §2, 06 §7, ADR 2026-09-05c §4, 07 §11, 07 §12, 07 §14, 07 §18,
  07 §22, 08 §1–§3, ADR 2026-09-05g, ADR 2026-09-19, 10 M10, 13 S4.2/S17.3/§10, DESIGN-PACK S9.1/S12.1/S17.3,
  `docs/ops/lead-times.md` §3, and PLAN §4 and desk 2/15. `docs/ops/pricing-research-2026-09-24.md` is kept as a
  non-normative reference.
- **Design:** Canvas 10 S12.1 is redrawn with each entity type's plans (owner or design session). S17.3's canvas
  shows email.
- **Milestones:** M6 (OTP), M7 (invites), M10 (import), M12 (support), M13 (plans and catalogue).

## Open ⚠️
- Owner actions from desk 2: DLT registration (one OTP template), Apple enrolment (Individual today), the Supabase
  project, payment gateway KYC, PA/HI reviewers, the bookkeeper, the crypto reviewer, pilot families, and the four
  synthetic bank statements.
- The support mailbox `support@rukkafolio.com` must exist before the pilot, with SPF and DKIM if replies are sent
  from it. Whether the domain is registered to the owner has not been checked.
- Before any plan ships, confirm each working price exists as an Apple price point in App Store Connect.
- Apple's rules for existing subscribers on a price rise (notice, consent) are unverified. Decide a
  grandfathering policy at the first change.
