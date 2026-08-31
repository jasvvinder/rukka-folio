# 07 — UI Flows & Screens

**Status:** Draft 1 for build → to be validated against the interactive mockup before development. 🔒 = locked. ⚠️ = decide during mockup testing.
**Companions:** 02-ledger-rules.md (every posting and rule referenced here), 04-crypto.md (ceremony, recovery), 06-auth-devices.md (states, roles). Strings live in 01-glossary.md — this document uses English keys; every string ships in EN + ਪੰਜਾਬੀ.

---

## 1. Global design rules 🔒

1. **The 8-second entry.** From app icon to saved cash entry in ≤ 8 s. Every design decision loses to this.
2. **One-hand, bottom-heavy** (respect the iOS home-indicator inset; nothing critical under it). Primary actions in thumb reach; nothing critical only at the top.
3. **Color is meaning, never alone — and lives in the numerals.** Credit `--credit` / debit `--debit` tokens color **amounts only**, always paired with sign (`+`/`−`), column position, and a word; the app is near-monochrome otherwise, per brand (11 §4.3). Pending = amber, locked = grey (tokens to be added to the brand set).
4. **Money format:** ₹ + Indian grouping (`₹12,34,567`), paise shown only when non-zero; **tabular figures always** (`font-variant-numeric: tabular-nums` on every amount — 11 §4.4). Amount-in-words on receipts/exports in the user's language.
5. **Dates:** English uses abbreviated months (`DD Aug YYYY`); ਪੰਜਾਬੀ and हिन्दी use **full month names** (ਅਗਸਤ, अगस्त) — abbreviations don't exist naturally in these scripts. Relative labels *Today / Yesterday* in lists.
6. **No dead ends.** Every blocked action explains why and offers the path: locked date → *Fix an old entry*; unverified member → *Meet Sunita to activate*; empty vault → recovery ladder.
7. **Offline is normal, not an error.** A quiet chip (`Saved on phone · will sync`) — never a blocking banner. Sync failures surface in Inbox, not as popups.
8. **Trust surfaces:** the books-balanced verification card on Home (§4, 02 §8); *uncertified year* banner where applicable; audit trail one tap from any entry.
9. **Typography:** large by default (target users skew 40+); respects OS font scaling to 200% without breakage; **Mukta superfamily** bundled (Mukta for Latin+Devanagari, Mukta Mahee for Gurmukhi), fallback Noto Sans — one family across scripts, per brand (11 §4.4).
10. **Dark mode is required** (shopkeepers close at night): ink background, paper text, credit/debit hues lifted for contrast (11 §4.3).
11. **Containers are sized for the longest scripts** (+30–40% vs English, 11 §5) even in Phase 1, so added languages never force redesign.
12. Every list screen defines its **empty state** (friendly line + the one next action) and its **error state** (what failed + retry). No blank whites, no raw error codes.

---

## 2. Navigation map 🔒

Bottom bar, five slots:

```
┌───────────────────────────────────────────────┐
│  Home    Ledger    [ + ]    Inbox(●)    Menu  │
└───────────────────────────────────────────────┘
```

- **Home** — position + today (§4).
- **Ledger** — the A–Z A/C index (§6).
- **[+]** — opens the verb chooser (or repeats the last verb on long-press) (§5).
- **Inbox** — everything awaiting a human: approvals, late arrivals, import lines, verification requests, recovery requests, aged-advance reminders. Badge = count. One tray, so nothing important hides in five places.
- **Menu** — reports, books & members, subscription, devices & security, settings.

**Scope switcher 🔒** — a chip in the top app bar showing the current scope. Tap → bottom sheet grouped: **Me** (personal book) · **Family** · **Businesses** · **Organizations** · **Everything** (position/reports only, read-only aggregate). Solo users never see the chip at all — the app *is* their personal book. Last-used scope persists per tab.

---

## 3. Onboarding & activation

### 3.1 Fresh signup 🔒
1. Language picker (EN / ਪੰਜਾਬੀ / हिन्दी) — first screen, before anything else.
2. Phone → OTP (06 §2). Generic errors; resend with visible countdown. Splash and every successful unlock play the **sealed→open mark animation** (11 §4.2; m=0.6 on biometric unlock, jump cut under `prefers-reduced-motion`) — never decoratively.
3. *"What will you use this for?"* — four illustrated cards: **Myself / My shop / My businesses / My family** (seeds books + category tree only; changeable later; no lock-in copy).
4. Name (+ optional photo — shown in approvals & ceremonies, worth asking here).
5. **Recovery sheet moment** (04 §7.4): explain in one screen why there is no "forgot password" (*"Your data is locked so well that even we can't open it"*), generate PDF, share/print, then the **verified-storage nag** badge lives on Menu until they scan the printed sheet back.
6. Opening balances wizard (02 §4) — skippable, resumable from Home's setup card.
7. If invited (deep link): §12 flow instead of step 3.

### 3.2 Returning / new device
Follows the scenario table in 06 §5 verbatim. Key screens: **Link with old phone** (camera + *Show my code* on the old device), **Ask your guardians** (live k-of-n progress: `Sunita ✓ · Rajesh …pending · Bauji —`, each row shows *called them?* hint), **Scan your paper sheet**, and the honest last screen: *"Shared books can be restored by your family after they verify you again; your old personal book cannot be recovered."* No euphemisms.

---

## 4. Home 🔒

```
┌──────────────────────────────────────┐
│ ⌄ Sharma Family        ✓  ⟳  🔔      │  scope chip · integrity · sync
│                                      │
│  TOTAL MONEY YOU HAVE   ₹2,41,500  │  ← hero (owner-approved)
│  SBI ₹1,38,210 · Cash ₹18,240 ...   │
│  ── ✓ BOOKS BALANCED ─────────────  │  ← verification card
│  Dr ₹3,23,000 = Cr ₹3,23,000 · nil  │
│  POSITION (this scope)               │
│  Cash in hand            ₹ 12,450    │
│  SBI Saving              ₹ 1,08,210  │
│  HDFC CC              −  ₹ 22,915    │
│  You will get            ₹ 45,000 ▸  │
│  You will give        −  ₹ 8,200 ▸   │
│  Advances out            ₹ 20,000 ▸  │
│  In transit              ₹ 50,000 ▸  │
│  ── This month: In ₹1.2L · Out ₹84k ─│
│                                      │
│  [₹ In]  [₹ Out]  [Gave ↗]  [Took ↙] │  four verb buttons
│                                      │
│  TODAY · 28 Aug ▸ full day book      │
│  ↓ Diesel A/C · Cash        ₹ 2,400  │
│  ↑ Shop sales · SBI         ₹ 18,600 │
│  Cement — UPI ⏱ review     ₹ 7,000 │
└──────────────────────────────────────┘
```

- **Total money you have 🔒 (owner-approved):** one hero figure at the top = sum of all `money` accounts in scope (cash + banks, overdrafts subtracted), with the per-account breakdown beneath. This is the headline the position list alone did not give.
- **Books-balanced verification card 🔒 (owner-approved):** replaces the bare ✓/✗ integrity light — shows status pill, total Dr, total Cr and the difference, tapping through to the full trial balance (S8.1). In this product it is a genuine trust artefact, not decoration: at close, every member's device recomputes the same vector independently (02 §8).
- Position card = 02 §9 exactly; every line drills into its list; **Everything** scope aggregates all visible books with per-book subtotals.
- Verb buttons carry EN + PA labels and icons; they open §5 with the verb pre-chosen.
- Today section: newest first. Under-review entries are marked only by a small **amber clock beside the timestamp** — included in every balance (02 §3); the reviewer's name and full status live in the entry detail. One **summary chip** per book view ("7 under review · ₹23,400 — Sunita") is the single place the status is written out; tapping it opens the filtered list. Tap any row → entry detail (audit trail, amend/reverse per 02 §5).
- Empty (new user): position card collapses to the **setup checklist** (opening balances → first entry → recovery sheet → add family).
- 🔒 Owner-confirmed: the *This month In/Out* figures stay on Home; their exact presentation (separate line vs merged onto the Money in/out buttons) is settled in the Home rework.

---

## 5. Add Entry — the 8-second flow 🔒

**Screen order: amount first.** Full-screen numeric keypad with the amount huge at top; verb shown as a colored header chip (switchable by swipe or tap without losing the amount).

1. **Amount** — keypad supports `+` quick-sum (`120+80+40`); paise via `.`; Next.
2. **Slot A** (Into / From — a `money` A/C): horizontal chips of this book's money accounts, most-recent first. One tap.
3. **Slot B** (From / For / Whom — per verb, 02 §2): search-first picker; recents and favorites on top; **inline create** per 02 §1.2 (*"+ Create 'Langar' A/C"*, class inferred from slot, the one two-chip question only when the slot is ambiguous).
4. **Date chip — `Today`** 🔒: tap → calendar; any date in an open period selectable (backdating); **future dates disabled** (tooltip: *"Use a recurring entry for future dates"*); locked dates shown 🔒-greyed — tapping one explains the lock and offers ***Fix an old entry*** (reversal flow, 02 §5). Never a dead error.
5. Optional row: note · 📷 bill photo (camera-first, auto-compress) · channel tag (Cash/UPI/Card/Bank ⚠️ finalize taxonomy).
5.5. **Entry preview 🔒 (owner-directed, 30 Aug 2026).** Above Save, one line shows the value flow of the posting the app has already computed:

> **₹2,400 · ਰੋਕੜ ਖਾਤਾ → ਡੀਜ਼ਲ ਖਰਚ ਖਾਤਾ · ਇਸੁਜ਼ੂ ਗੱਡੀ ਦੇ ਡੀਜ਼ਲ ਲਈ**

Left of the arrow is the credited account, right of it the debited account, then the user's own narration (clause and separator omitted when blank). Both sides are always **named ledger accounts** existing in the book.

**Why an arrow rather than words 🔒:** prepositions like *from/to* imply an accounting rule that does not hold generally — debit and credit follow the **account's class**, not the direction of transfer (01 reference §1.2, DEAD CLIC). The arrow states the flow without asserting a rule, reads identically in all three languages (one ICU template, not three), avoids the Punjabi/Hindi oblique-case problem with user-typed account names (ਖਾਤਾ → ਖਾਤੇ before a postposition), and degrades cleanly for splits: `₹50,000 · 3 accounts → ਖਰੀਦ ਖਾਤਾ`.

**The preview never computes anything.** It describes a posting already derived from the verb and the account classes (02 §2); it is read-only and cannot influence the entry. Formal **ਨਾਮੇ / ਜਮ੍ਹਾਂ** columns remain on statements, reports and exports (01 §1.9), where classification is explicit.

6. **Save** — instant local write, haptic tick, snackbar `Saved ✓ (on phone)` with **Undo (10 s)** (undo = amendment/void while still local). If over the member's limit for this book → snackbar reads `Saved ✓ · Sunita will review` — saved and counted either way (02 §3).
7. After save: stay on keypad zeroed for rapid consecutive entries (shopkeeper mode); Back exits. Long-press [+] anywhere = repeat last entry pre-filled.

**Transfer** and **Adjustment** verbs live behind the [+] chooser's second row; Adjustment shows only its wizards (02 §2 row 6), never a freeform journal screen. Inter-book transfer: choosing a destination in another book switches the flow to §10.

**States:** offline = identical (that's the point); attachment upload failures retry silently, visible in entry detail; validation failures cannot happen by construction (the UI can't build an unbalanced entry) — any quarantined envelope from *other* devices surfaces in Inbox as a security event.

---

## 5.5 Cash count sheet 🔒
One screen, two modes driven by the account's subtype (02 §8.2): **verify** for a galla/household cash account (shows book balance and the difference) and **collect** for a gollak/donation box (shows only the counted total, posts it as income, requires the denomination grid and two names). Reached from a cash account's statement (*Count again* / *Open and count*), from month close step 1, or from the account screen. A denomination grid — one row per note (₹500 · ₹200 · ₹100 · ₹50 · ₹20 · ₹10, optional ₹2000), each with a stepper and a live line total, plus a single **coins** value field. The running **counted total** sits large at the top; beneath it, the book balance and the difference, stated in words ("₹230 less than the book — we'll adjust it"). Optional *counted by* and *witness* name fields (the gurudwara gollak pattern). Save records the count; only a non-zero difference posts an entry (02 §8.2). Cash statement header shows the last count and its breakdown.

## 6. Ledger — the A/C index 🔒

- A–Z list of every A/C in scope with live balance, colored by sign; sticky alphabet rail; **search is the header** (the fastest path to any khata); filter chips: All · Parties · Categories · Money · System.
- Row tap → **A/C statement**: professional paper-ledger layout in the traditional three columns — **ਨਾਮੇ | ਜਮ੍ਹਾਂ | ਬਾਕੀ** (नामे | जमा | बाकी / Dr | Cr | Balance), cells colored directionally per the approved option A (design-system §5) — with *Opening balance b/f* carrying its as-on date (the period's first day, e.g. `as on 01 ਅਗਸਤ 2026`) and *Closing balance c/f* carrying the date it is forwarded — the period's last day, or today's date while the period is still open 🔒 (owner rule), dated entries with running balance between them; FY switcher (02 §8.1); export this A/C (PDF/XLSX) top-right; for parties: WhatsApp-share a statement image (the Khatabook habit — it drives adoption).
- `+ New A/C` here opens the **deliberate-creation wizard 🔒 (owner-approved)** — step 1 is a grid of illustrated type tiles (Bank · Cash/vault · Credit card or OD · Person you'll pay (creditor) · Person who'll pay you (debtor) · Expense · Income · Capital), step 2 is name + **opening balance**, step 3 optional details. Inline creation during an entry keeps inferring the class from the slot (02 §1.2); the grid is for setup, where the user is choosing on purpose, and rename / merge-duplicates / delete-if-unused under ⋮. ⚠️ merge UX in mockup.
- Empty state: seeded tree is already present, so never truly empty; search-miss state = the create row.

## 7. You-will-get / You-will-give 🔒
Drill-downs from Home: party list sorted by balance, ageing chips (`> 30 d` amber, `> 90 d` red), total header; row → party statement (§6); *Remind on WhatsApp* per party ⚠️ Phase 1?; bulk export.

## 8. Advances 🔒
- **My advances** (money I'm holding): per-book cards — purpose, taken date, spent vs remaining bar, `Add spend` (pre-filtered entry) and `Return remaining` buttons.
- **Given out** (book view): aged list per 02 §7; approver sees `Remind` and `Write off (reason)` actions.
- Request flow: amount → purpose (required) → from which book → submits to approver; tracked in Inbox both sides.

## 9. Approvals (in Inbox) 🔒
Flags group into **one card per author + book + day**: avatar, "Ramesh · Kirana Store · 7 entries · ₹23,400", expandable list with photo thumbnails and a per-row ✕ quick-reject. Two actions 🔒 (owner-approved):
- **Approve all** — clears every flag in the card in one tap (entries were already posted and counted, 02 §3).
- **One by one** — a guided stepper: each entry full-screen (photo, amount, A/Cs, date/time, author, note) with **Approve / Reject (reason required → auto-reversal posts) / Skip (stays flagged)** and a quiet *ask for a better photo* link; every decision advances, progress shown ("3 of 7"). Nothing is approved unseen; rejecting one never blocks the rest.

## 10. Inter-book transfer 🔒
One flow: From (book + money A/C) → To (book + money A/C) → amount → save. Creates the pair (02 §6). If the actor lacks rights on one side, that half shows ⏳ and the position lines show **In transit** until both halves post. The **Family Reconciliation** screen (Menu → Reports) lists any non-zero pair with its composing entries — normally a single proud green ✓.

---

## 11. Statement import 🔒 (Phase 1: file upload)

1. **Pick account → pick file → confirm mapping → duplicates skipped → review → submit** 🔒 (refined 30 Aug 2026). All parsing on-device (04: nothing readable leaves the phone).
   - Pick the bank A/C, then the file. The drop zone states what it accepts: *CSV, XLS, OFX or PDF · up to 10 MB*.
   - **Column mapping step** — the app auto-detects date, description, withdrawal, deposit and balance columns and asks the user to confirm; corrections are **remembered per bank**, so the next statement from that bank needs no mapping. Replaces maintaining a parser per bank with a one-time confirmation per bank.
   - **Duplicates removed before anything is shown**, count stated up front ("12 lines already imported — skipped").
   - **Balance check** 🔒 — the statement's own opening and closing balances are compared with the ledger for those dates ("Opening matches your book ✓ · Closing will match once these 23 lines are recorded"). A mismatched opening means an earlier statement is missing, and says so.
   - **Partial submit always allowed** — classified lines post, the rest stay in the inbox; unknowns may go to Suspense but must clear before the month locks (§13).
**Bank language throughout 🔒:** every line renders as the user's statement does — **Money in / Money out** with the amount — never Dr/Cr (02 §10). The bank's raw narration sits beneath in small grey type for recognition; the user's own words replace it in the books.

2. **Import inbox** (also surfaces in main Inbox): each line = date · bank text (grey) · **Money in/out** amount · one question — *"Where did it come from?"* / *"Where did it go?"* — with state chip:
   - `Matched ✓` — auto-linked to an existing entry (confidence shown); tap to unlink.
   - `Suggested` — rule/fuzzy match awaiting one-tap confirm.
   - `New` — answer the one question by picking or inline-creating an A/C (full picker) → posts normally; the user never chooses a side. **Narration is editable inline** on every row — the bank's text stays greyed beneath as the original, the user's words become the entry's note.
   - `Suggested` rows carry a green chip naming the guess (*"Milk Expense — suggested"*) with a one-tap **Approve**; approving teaches the rule, correcting re-teaches it.
   - `Transfer?` — an opposite line in another own-account matches (equal amount, date window): *"Is this the same money moving between your accounts?"* → one tap posts a single Transfer instead of two entries (02 §10).
   - `Suspense` — *"record now, explain later"* button; posts to Suspense (02 §10); a persistent chip on the book screen counts unexplained lines, and month-close step 3 walks them to zero.
3. Rules learn from corrections (`SWIGGY* → Food` toast: *"Always? Yes/No"*).
4. Parse-failure state: *"Couldn't read this file"* + supported-format list + *send file format to support* (file itself never leaves device; user shares format sample voluntarily).

---

## 12. Members, invitations & the ceremony 🔒

- **Members screen** (per tenant): list with role badges per book, verification method + date (the permanent log, 04 §6.4), auto-post limits (tap to edit, admin only), `+ Invite`.
- **Invite:** phone → per-book role + limit grid → sends WhatsApp/SMS link. Invite card shows state machine (06 §7): `Invited (expires in 7 d)` → `Joined — verification needed` → `Active`.
- **Invitee experience:** installs via link → OTP → **their personal book works immediately**; shared books appear greyed with *"Meet Sunita to activate"*.
- **Ceremony screens** (04 §6): *Show my code* (huge QR; the 8-digit code beneath rendered as **eight separate character boxes with a visible expiry countdown** 🔒 owner-approved — presentation only: the code remains derived from the key fingerprint + invite nonce per 04 §6.1, never a password) and *Verify member* (camera default, `Enter code instead`). Success = green tick + confetti-restraint; **mismatch = full red screen, no override**, *Contact support*, event logged. Remote mode (admin toggles per invite): verifier screen instructs *"Call them and ask them to read the code aloud"* — no share button, by design. Delegated: any active member's *Verify member* works.
- Removal flow: blocked-by-advances gate first (02 §7), then confirmation explaining rotation honestly (04 §5.3), then done.
- Guardian setup lives in Menu → Devices & security: pick 2–3 members → **mutual** ceremony checklist per guardian → active. Escrow opt-in (04 §7.5) sits here too, with its plain-language disclosure and the veto explanation.

---

## 13. Month close, Late Arrivals, Year close 🔒

- **Close card** appears on Home from the 1st for each book the user closes: `Close August ▸ 4 steps`.
- **Resumable 🔒:** progress saves at every step; leaving and returning resumes where the user stopped. A shopkeeper will not finish this in one sitting.
- **Blocking vs warning 🔒 — stated plainly on the tray step:** unexplained bank lines (Suspense) and unposted pending items **block** the lock; aged advances and unverified cash counts **warn** but do not. The screen says which is which rather than presenting one undifferentiated list.
- **The family's state, not just yours 🔒:** in a multi-book tenant the wizard shows every book's close status — *"Kirana closed ✓ · Agriculture waiting on Pankaj · Joint pool not started"* — because closing is a joint act (§8) and the karta needs to know who he is waiting for.
- Wizard = 02 §8 steps verbatim, one screen each: cash count (big keypad, difference shown in words: *"₹230 less than the book — adjust?"*), bank confirm (per account: `Matches ✓ / Doesn't match ▸ reconcile`), tray clearing (pendings, Suspense, aged advances warn-only), confirm & lock (shows the balance vector summary; other devices verify in background; mismatch → both devices alert with a *Recompute* action).
- **Month summary card 🔒 (adopted 30 Aug 2026):** the screen shown immediately after a book locks is a reward, not a receipt — *"August · in ₹1,75,000 · out ₹1,38,200 · saved ₹36,800"* with the three largest expenses and, in a joint family, each sub-family's total. Shareable to WhatsApp as an image. This turns a chore into something people want to reach, and is the product's natural monthly re-engagement moment: ledger apps die of retention decay, and the close ritual is the cure.
- **Cash-count step accepts either** a single figure or the denomination sheet (§5.5), mandatory in trust books.
- **Late Arrivals** (Inbox): per 02 §8 — each item: entry + why it's here; actions `Re-date to today` (default) / `Re-open August` (admin, scary-styled, logged).
- **Year close** (Menu → per book, or the prompt after March locks): preconditions checklist → optional *Distribute profit first* for businesses (Flow 7 UI: proposed split per ownership %, editable with reason) → certify → year seals; **FY switcher** appears on every ledger/report; closed years show `Certified ✓ FY 2026-27`; a reopened month voids certificates with the loud banner (02 §8.1).

---

## 14. Reports & Export 🔒

Menu → Reports, per scope, each with FY + date-range control and share/export (PDF & XLSX; on-device generation; b/d–c/d rows on ledgers; amount-in-words; A4 print-clean):

Day Book · Cash Book · A/C statement (any) · **Trial Balance** (02 §8) · You-will-get / You-will-give with ageing · Profit/Loss (per FY/range) · Full Position (balance-sheet layout by sign, 02 §1.2) · Advances ageing · Family Reconciliation · **Partner positions** (02 §7.1, shared-ownership businesses only) · Business comparison (Everything scope).

Report screens are tables with a one-line takeaway header (*"August: In ₹1,21,400 · Out ₹84,250 · Saved ₹37,150"*). No dashboards-for-dashboards'-sake in Phase 1 ⚠️ charts revisit after pilot.

---

## 15. Devices & security screens 🔒
Menu → Devices & security: linked devices list (06 §6) with revoke + **"This phone was stolen"** path (04 §9.2 consequences spelled out before confirm); guardians; recovery sheet (view status, re-verify, regenerate = old sheet invalid warning); escrow; app-lock timeout; **Personal Book PIN** toggle; security events log.

## 16. Settings 🔒
Language (per member) · book management (create/rename/archive, FY start) · category tree editor · notification preferences · export everything (06 §9.2 — always available, plan-independent) · subscription · about/support (WhatsApp).

## 17. Notification catalog 🔒 (all content-free per 04 §4)
Review requested — **digest per author+book**: the first flag notifies, later flags fold into the same notification, never N pings 🔒 · review decided · advance reminder (holder, then approver) · verification needed/completed · recovery requested (guardian) — **loud** · new uncertified device on your account — **loud** · close reminders (1st) · late arrival waiting · import lines waiting · escrow release countdown — **daily, loud**. Each deep-links to its Inbox card. Per-type mute except the security three.

---

## 18. UI acceptance criteria (excerpt)
- Stopwatch test: icon → saved cash entry ≤ 8 s with warm cache; ≤ 3 taps + amount digits for a repeat entry.
- Airplane-mode test: every §5 path completes; chip states correct; sync completes silently later.
- Locked-date tap never shows a dead error; always offers *Fix an old entry*.
- 200% OS font scale: no truncation on Home, Entry, Ceremony screens.
- Punjabi & Hindi: every screen renders Gurmukhi and Devanagari correctly incl. numerals context; no string overflows in either on smallest supported device (iPhone SE 3rd gen, 375×667).
- Every list has its designed empty state; airplane + fresh-install shows setup checklist, not blanks.
- A colorblind user (grayscale filter) can distinguish in/out/pending on every screen.

## 19. Open items ⚠️
1. ~~All Phase-A open items~~ — settled in `docs/13-ux-architecture.md` §10 (icons, group headers, Home layout, statement colour, voucher/date, WhatsApp share, merge, min device, nav, pricing). 2. Channel-tag taxonomy. 3. WhatsApp remind & statement-share in Phase 1 or 2. 4. ~~Batch approve~~ — resolved by the grouped review card (§9). 5. A/C merge UX. 6. Minimum supported device + smallest-screen budget. 7. Charts in reports (post-pilot).
