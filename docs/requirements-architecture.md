# Family & Business Ledger App — Requirements and Architecture

**Scope:** India. Full double-entry engine. No chartered accountant in the loop.
**Version:** 0.1 (requirements freeze candidate)

---

> ## ⛔ STATUS: BACKGROUND ONLY — NOT NORMATIVE 🔒
>
> This document captures the **original product thinking** and is kept for the
> *why* behind decisions. It predates the zero-knowledge architecture and the
> post-then-review approval model. **It loses every conflict with docs 00–12.**
> Do not implement from this file.
>
> **Sections known to be superseded — do not build from them:**
>
> | Section here | Says | Superseded by |
> |---|---|---|
> | §3 Flow 3, Flow 4 | Over-limit entries save as **Pending**, not Posted; approver may **Query** | **02 §3** 🔒 (revised by owner): every entry posts instantly; the limit is a *review threshold, not a gate*; only approve/reject exist |
> | §5 Flow 6 step 3 | Close step 3 clears "every pending item" | **02 §8** step 3: clears open *needs review* flags, Suspense lines, aged advances |
> | §6.2 Sync | "server validates (balanced, period not locked, member within limits)" | **02 preamble** 🔒 the server enforces **no** ledger rule; **05 §3** 🔒 the server never rejects on content |
> | §6.2 Sync | Server rejects entries for locked periods | **02 §8** + **05 §4**: locks are client-verified; late arrivals go to the Late Arrivals tray |
> | §6.3 Backend | Plaintext `accounts`, `journal_entries`, `journal_lines`, `approvals`, `advances` tables | **03 §2.3** 🔒: the server holds one opaque `envelopes` table; no financial row exists server-side |
> | §6.3 Backend | Balance strategy via server-side trigger table | **03 §3.2**: balances are a **client** projection; the server cannot compute them |
> | §6.3 Backend | Service language **Go** (or NestJS) | **CLAUDE.md** + **03**: Supabase Postgres + Deno edge functions |
> | §3.2 roles | "Joint Admin / Sub-family Head / Business Operator", daily cash limit | **03 §2.1** `book_roles` enum (`admin·head·member·operator·viewer`) + **06 §1.1** `auto_post_limit_paise` (per-entry threshold, not a daily aggregate) |
>
> Where a section here is *not* listed above it is still useful context, but
> docs 00–12 remain the source of truth on every point.

---

## 0. What this product actually is

A **single ledger app that works identically** whether the user is:

- one individual tracking personal money,
- one shopkeeper tracking a business,
- a businessman with several firms,
- a joint family with several sub-families and several businesses.

The engine is textbook double-entry. The interface is a rokad-bahi (cashbook). The user never sees the word *debit*.

The central design bet: **the number of books changes, the flow never does.**

---

## 1. The Book abstraction (this solves Requirement 3)

Everything in the system is a **Book** — an independent, self-balancing ledger container.

| Book type | Owned by | Created when |
|---|---|---|
| Personal Book | one member | automatically, on signup |
| Family Book (sub-family) | a sub-family head | when a sub-family is added |
| Joint Book (common pool) | the joint family | when joint-family mode is turned on |
| Business Book | a business entity | when a business is added |

**Consequences:**

- **Individual user** → 1 Personal Book. The book switcher is hidden entirely.
- **Single business owner** → 1 Personal + 1 Business. Switcher shows two chips.
- **Multi-business owner** → 1 Personal + n Business.
- **Joint family** → 1 Joint + n Family + n Personal + n Business.

Every screen (Add Entry, Day Book, Ledger, Position, Reports) takes a `book_id` and behaves the same way. There is no separate "family mode" codebase.

**Upgrade path is purely additive.** An individual who later forms a joint family adds books; nothing migrates, no data is rewritten, no re-onboarding. This is only possible because books are independent ledgers linked by due-to/due-from accounts (§4.3) rather than by nesting.

### 1.1 Onboarding

One question at signup: *"What will you use this for?"* — four illustrated cards (Myself / My shop / My businesses / My family). This only decides which books to pre-create and which sample chart of accounts to seed. Every option can be changed later in Settings.

---

## 2. Language and terminology (Requirement 2)

### 2.1 Principle: double-entry underneath, single-entry on top

The user enters a **narrative**, not a journal line:

> Money **went out** → from **Cash** → for **Diesel** → ₹2,400

The app posts `Dr Diesel Expense 2400 / Cr Cash 2400`. The user is never asked which account to debit. Behind every entry template is a fixed debit/credit rule the user cannot get wrong.

Only four entry verbs are exposed, matching how a cashbook is actually kept:

1. **आया / Money in** (receipt)
2. **गया / Money out** (payment)
3. **दिया उधार / Gave on credit** (creates a debtor)
4. **लिया उधार / Took on credit** (creates a creditor)

Plus two secondary ones: **Transfer** (between own accounts) and **Hisab-kitab / Adjustment** (guided, for corrections and closing).

### 2.2 Terminology map

The accounting term is stored in the database. Only the vernacular term is shown. Hindi shown as the example; each language gets its own reviewed set, not a machine translation.

| Internal (DB) | English UI | Hindi UI | Notes |
|---|---|---|---|
| Journal Entry | Entry | एंट्री / नोंद | |
| Debit / Credit | *never shown* | *never shown* | replaced by in/out arrows and colour |
| Day Book | Day Book | रोजनामचा | the home screen |
| Cash Book | Cash Book | रोकड़ बही | filtered day book |
| Ledger Account | Account | खाता | |
| Sundry Debtor | You will get | जिनसे लेना है | ₹ shown in green |
| Sundry Creditor | You will give | जिन्हें देना है | ₹ shown in red |
| Advance / Suspense | Hand loan | हाथ उधार / पेशगी | §4.2 |
| Capital | Own money | पूंजी | |
| Drawings | Money taken out | निकासी | |
| Trial Balance | Match check | मिलान | shown as ✓ or ✗, not as a report |
| Profit & Loss | Profit / Loss | नफा-नुकसान | |
| Balance Sheet | Full position | कुल स्थिति | |
| Period Close | Month lock | महीना बंद | |

### 2.3 Language requirements

- **Launch set:** English, Hindi, Marathi, Gujarati, Tamil, Telugu, Kannada, Bengali. **Phase 2:** Punjabi, Malayalam, Odia, Assamese, Bhojpuri.
- Bundle **Noto Sans** for each script in the APK. Do not rely on the device font — low-end Android devices frequently lack Indic shaping for some scripts.
- **Indian digit grouping** (`12,34,567`) everywhere, driven by locale, not by hand-rolled string formatting.
- **Amount-in-words** in the selected language on every receipt and PDF (`बारह लाख चौंतीस हज़ार पाँच सौ सड़सठ रुपये`).
- **Voice entry** in the selected language for amount and party name. This is the single highest-leverage accessibility feature for the target user; budget real effort for it.
- **Icon + colour first.** Every category has a picture. Green in, red out, consistently, app-wide. A user who cannot read should be able to record a cash sale.
- Language is a **per-member** setting, not per-family. The father uses Marathi, the son uses English, on the same books.

---

## 3. Users, roles and collaboration (Requirement 5)

### 3.1 Roles

| Role | Scope | Rights |
|---|---|---|
| **Joint Admin** (Karta) | whole family | all books except others' Personal Books; add/remove members; add businesses; set limits; lock periods |
| **Sub-family Head** | own Family Book | full entry + view; approve members' requests; enter in businesses where assigned |
| **Member** | own Personal Book | full control of own book; submit entries/requests to Family or Business books |
| **Business Operator** | one Business Book | entry only, within a daily cash limit; cannot view P&L or other books |
| **Viewer** | assigned books | read + export only |

A person holds **one role per book**, not one global role. Ramesh can be Sub-family Head of his family, Business Operator in the kirana shop, and Viewer on the transport business — simultaneously.

### 3.2 Visibility rules (non-negotiable)

- **Personal Books are private.** Not visible to the Joint Admin. Only the member's *net position* and *outstanding advances* roll up to the family view.
- Sub-family Head sees own Family Book in full; sees members' Personal Books only as a one-line net figure.
- Joint Admin sees Joint Book and all Business Books in full; sees each Family Book's summary and can drill in only if that head has enabled it.
- Every Business Book has an explicit member access list. Adding a business does not grant everyone access.

If personal privacy is not guaranteed, members will keep a second private khata on paper and the data will be wrong. This is a product-survival requirement, not a nice-to-have.

### 3.3 The eight collaboration flows

**Flow 1 — Form the family**
Karta creates the family → names it → invites sub-family heads by phone number → each invitee installs, verifies OTP, and on accept the system auto-creates their Family Book and Personal Book → head then invites their own members. Two-level invite tree only; heads cannot invite other heads.

**Flow 2 — Add a business (Requirement 4)**
Only the Joint Admin adds a business. Inputs: name, type (proprietorship / partnership / HUF / firm), GSTIN if any, opening balances, and the **ownership split across sub-families** (must total 100%). This split later drives profit distribution (Flow 7). A Business Book is created and members are assigned roles. Unlimited businesses; each is fully independent, with its own chart of accounts, financial year and closing.

**Flow 3 — Daily entry**  ⛔ *superseded in part — see banner. The Pending-on-over-limit behaviour below is replaced by 02 §3 post-then-review.*
Member opens app → book switcher (defaults to last used) → one of the four verbs → amount → party or category → optional bill photo → save. Saves offline instantly; syncs when connected. If the entry is in someone else's book and exceeds that member's limit, it saves as **Pending** instead of **Posted** and goes to Flow 4.

**Flow 4 — Approval**  ⛔ *superseded — see banner. Replaced wholesale by 02 §3; there is no Pending state for ordinary entries and no Query action.*
Configurable per member per book: an auto-post limit (e.g. ₹5,000) and an approver. Above the limit → Pending → push notification to the approver → approver sees amount, party, photo, and the member's month-to-date total → Approve posts it with the original date, Reject returns it with a reason, Query asks for a better photo. Nothing above a member's limit ever silently enters the books.

**Flow 5 — Hand loan / advance (हाथ उधार)**
The most important flow in a joint family.

1. Member requests ₹20,000 from the Business or Joint Book, with a stated purpose.
2. Approver approves. Posting: `Dr Advance – Ramesh / Cr Business Cash`.
3. The amount now shows on Ramesh's own dashboard as *money you are holding*, and on the business dashboard as *money out with Ramesh*, with an ageing counter in days.
4. Ramesh records spends against it. Each bill posts `Dr Expense / Cr Advance – Ramesh` and reduces the balance.
5. Remaining cash returned posts `Dr Cash / Cr Advance – Ramesh`, closing it to zero.
6. Unsettled after N days → reminder to Ramesh, then to the approver.

At any moment the app can answer "who is holding how much of the family's cash, since when, for what" without anyone doing arithmetic.

**Flow 6 — Month close (महीना बंद)**
Runs on the 1st. Each book owner gets a 4-step wizard: (1) count your cash and enter the figure — app shows the difference and posts a guided adjustment; (2) confirm bank/card balances against the statement; (3) clear or confirm every pending item and open advance; (4) confirm. When all books confirm, the Joint Admin taps **Lock**. Locked periods are read-only; later corrections must be reversal entries dated in the open period, with a reason recorded.

This wizard is what replaces the CA (Requirement 1). It must be completable by someone who has never heard of a trial balance.

**Flow 7 — Profit distribution**
At close of financial year (or any chosen date), each Business Book's net profit is computed. The Joint Admin runs Distribute → app proposes amounts per the ownership split from Flow 2 → admin can override with a reason → posting `Dr Business Capital / Cr Due to Family A, Family B…`, matched by `Dr Due from Business / Cr Capital` in each Family Book. Each sub-family sees its share arrive without any manual entry.

**Flow 8 — Exit and correction**
Removing a member: all open advances must be settled or written off first (app blocks otherwise) → their Personal Book detaches and stays with them as an individual account → their entries remain in family books permanently, attributed. Corrections in an open period edit in place with an audit trail; in a locked period, only reversal.

---

## 4. Accounting engine

### 4.1 Rules

- Every entry is a journal entry of **two or more lines summing to exactly zero**. Enforced by a database constraint, not by application code.
- Money is stored as **integer paise**. No floating point anywhere.
- The journal is **append-only**. Corrections are reversals. This makes offline sync safe (§6.2) and gives an unbreakable audit trail.
- Each book has its own **financial year** (default 1 April – 31 March) and its own closing.
- Balances are never computed by summing all history at read time. See §6.3.

### 4.2 Chart of accounts (seeded per book type, fully editable)

- **Assets** — Cash in hand; Bank (Savings / Current / OD / CC-limit); Advances to members; Sundry debtors; Stock; Fixed assets
- **Liabilities** — Credit cards; Loans (term / vehicle / gold); Sundry creditors; Due to other books; GST payable
- **Equity** — Capital (per owner or sub-family); Drawings
- **Income / Expense** — a seeded Indian-household and small-business category tree

OD, loan and credit card accounts are ordinary liability accounts. A savings account going into overdraft needs no special handling — the balance simply crosses zero and the display flips colour.

### 4.3 Inter-book movement

Books never nest. They connect through paired **Due to / Due from** accounts. Business pays ₹50,000 to a sub-family:

```
Business Book:     Dr  Due from Family B   50,000
                       Cr  Bank                     50,000

Family B Book:     Dr  Bank                50,000
                       Cr  Due to Business X        50,000
```

Each book balances independently. A single **Family Reconciliation** report checks that every pair nets to zero, which is the only integrity check anyone needs to run across the group.

The one-sided case matters too: if a member pays a family expense from his own pocket, it posts to his Personal Book as `Due from Family` and appears in the Family Book as an unpaid liability, not as a lost transaction.

---

## 5. Bank and card import

### 5.1 Options, in order of quality

1. **Account Aggregator (RBI framework), via a TSP** — Finvu, Setu, Onemoney, Anumati, Perfios and similar. Consent-based, read-only, covers savings/current/OD and increasingly cards.
   **Constraint to verify before committing:** consuming AA data requires registration as a **Financial Information User**, which has historically required being regulated by RBI/SEBI/IRDAI/PFRDA. A pure bookkeeping app may not qualify directly and may need to consume data through a licensed partner. *Confirm current Sahamati/RBI eligibility rules with a TSP before building any roadmap around this.*
2. **Statement upload** — per-bank CSV/XLS/PDF parsers, plus OFX where offered. Unglamorous, works for every bank, no licensing. **Build this first regardless of AA outcome.**
3. **Corporate banking APIs** for business current accounts, at sufficient volume.
4. **SMS parsing** — restricted `READ_SMS` permission on Google Play is generally not granted to this app category. Do not design around it.

### 5.2 Reconciliation

Imported lines land in an inbox, never straight into the ledger. Matching screen: imported line on the left, candidate manual entries on the right, matched on amount within a date window and fuzzy party name. User confirms, splits or creates new. A rules engine learns (`SWIGGY*` → Food) after one correction. Duplicate detection is mandatory, since the same payment is often entered by hand and then imported.

---

## 6. Architecture

### 6.1 Client

**Flutter, iOS-first** (owner ruling, 30 Aug 2026 — supersedes the Android-first reasoning below, which still governs the Android build that follows). Reasons, in order: correct and consistent Indic text shaping across all target scripts (the single biggest technical risk in this product); one codebase; APK small enough and performant enough on 2 GB / Android 9 devices, which is where these users are; mature offline SQLite via Drift.

- Local **SQLite is the source of truth for entry.** The app is fully usable with no network — that is a hard requirement for rural and semi-urban use.
- iOS from the same codebase, shipped second.
- Target: cold start under 2s, entry save under 300ms, APK under 25 MB.

### 6.2 Sync  ⛔ *superseded — see banner. The server validates nothing about content (02 preamble, 05 §3).*

Event-sourced and append-only, which makes this far simpler than it usually is.

- Client mints the journal entry with a client-side UUID and a hybrid logical clock timestamp.
- Entries go into a local outbox and push when online; server validates (balanced, period not locked, member within limits) and appends.
- **Because posted entries are never edited, there are almost no merge conflicts.** Two members entering simultaneously in the same book both succeed. The only real conflict is an entry arriving for a period that got locked while the device was offline: server rejects, client surfaces it for re-dating. This avoids needing CRDTs.
- Idempotency keys on every write so retries are safe on flaky networks.

### 6.3 Backend  ⛔ *superseded — see banner. No financial table exists server-side (03 §2.3); stack is Supabase + Deno, not Go/NestJS.*

- **PostgreSQL.** Core tables: `families`, `books`, `memberships`, `accounts`, `journal_entries`, `journal_lines`, `attachments`, `approvals`, `advances`, `periods`, `bank_connections`, `import_lines`, `audit_log`.
- **Row-level security keyed on `family_id` and book membership.** Enforce isolation in the database, not in application code — the privacy rules in §3.2 are too important to leave to a forgotten `WHERE` clause.
- Balance strategy: a `account_balances` running-total table maintained by trigger on `journal_lines`, plus a nightly `daily_snapshots` table per account. The Position screen and the day/month/year reports read snapshots and are O(1) regardless of history size.
- **Service language: Go** for the ledger service — correctness under concurrency, small memory footprint, cheap to run. If the team is JavaScript-first, NestJS + TypeScript is an acceptable substitute; do not split the ledger across two languages.
- REST/JSON API with idempotency keys. GraphQL is not worth the complexity here.

### 6.4 Infrastructure

- **Hosting in India** — AWS `ap-south-1` (Mumbai) or GCP Mumbai. Required in practice by the DPDP Act 2023 posture and mandatory for any AA-derived data.
- Object storage for bill photos, compressed client-side to ~200 KB before upload, thumbnails served to the list views.
- Auth: phone OTP (MSG91 / Kaleyra / Gupshup), refresh tokens, biometric unlock, **a separate PIN for the Personal Book** so a shared or borrowed phone does not expose it.
- FCM for approval and reminder notifications, with vernacular templates.
- Encryption at rest and in transit; per-family key separation for attachments.
- Full audit log on every mutation, immutable, exportable.

### 6.5 Reports and export

Day book, cash book, ledger for any account, You-will-get / You-will-give lists with ageing, P&L, balance sheet, cash flow, member-wise advance ageing, family reconciliation, business comparison.
Export to PDF (vernacular, with amount-in-words) and XLSX. **Tally XML export** should still ship — not for a CA, but because banks, buyers and any future accountant will ask for it. GST-ready summaries if a business is registered, though the user files the return themselves.

---

## 7. Roadmap

| Phase | Duration | Contents |
|---|---|---|
| **MVP** | ~3 months | Book abstraction, double-entry engine, four entry verbs, offline-first, Personal + Business books, day book, ledger, You-get/You-give, position screen, Hindi + English, PDF day book |
| **v1** | +2 months | Joint family, invites, roles and visibility, approvals, hand-loan flow, month-close wizard, statement upload + reconciliation, 6 more languages, full reports |
| **v2** | +3 months | Account Aggregator (subject to §5.1), profit distribution, voice entry, business modules (stock, invoicing), Tally export, iOS |

---

## 8. Open items to verify before build

These are current as of my knowledge in May 2026 and should be confirmed directly, not taken on trust:

1. **FIU eligibility** for the Account Aggregator framework for a non-regulated bookkeeping app — confirm with two TSPs.
2. **Google Play policy** on restricted SMS permissions for finance apps.
3. **DPDP Act 2023 rules** — notification status and the consequent consent, retention and grievance-officer obligations.
4. Whether any of the businesses are registered entities with statutory filing duties. This app produces the data for those filings; it does not file them, and it is not a substitute for professional tax advice.
