# Design brief — frames for the ledger model of ADR 2026-11-11

**Date:** 11 Nov 2026 · **For:** the Claude Design project (canvas mirror: `design/canvas-mirror/`, last pulled 8 Oct 2026). **From:** PLAN-210, after the owner's ruling (ADR 2026-11-11).
**Order of work (owner, 11 Nov 2026):** design first → the doc rewrites (02, 07, 13, 09) are written from these frames → development. No engine or UI slice starts until these frames are drawn and pulled.

**What this brief is.** It lists every frame the ruling needs, new or changed. Each item gives the screen's S-id and name, where it is drawn today (canvas no. · frame caption, from `design/match/canvas-index.json`), the app file that will build it, what the frame must show, and the rule behind it. The frames decide **how** a screen looks. The rules cited here decide **what** it does, and the frames must not change that. Where a frame seems to need a different rule, raise a `⚠️ SPEC:` question; don't draw around it.

**Sources the designer reads.** All paths are under `docs/`.
- `decisions/2026-11-11-app-requirements-after-sign-off.md` — the ruling (§0–§14).
- `app-requirements-pass.md` §3 — the register (R-ids, scope P / V / L).
- `accounting/02-accounts-and-transactions.md` — kinds of account (table at the head), worked entries.
- `accounting/03-entities.md` — partnership, joint family, between books, trust.
- `accounting/04-year-end-and-reports.md` — month end, year close, every report.

**House rules that still bind every frame.**
- 07 §1: the 8-second entry, no dead ends, colour never alone.
- 13 §8 accessibility; tokens only.
- Consumer words on entry screens (*Money in / Money out*), true Dr/Cr on professional surfaces (CLAUDE.md rule 9; ADR 2026-10-10b §4).
- English in all three language slots, with every new string added to `TRANSLATION-PENDING.md`. Never machine-translate.
- **Forbidden words** (R-133…135): *Due to/from*, *suspense*, *Adjustments* (as an account), *Opening Balance* (as an account), *on khata*, *Wages outstanding*, *imprest* (outside a petty cashier), and the 01 §1.3 jargon list.
- **Figures:** keep each canvas's existing cast (Sharma Family, Sharma Textile, Singh Sabha Gurudwara, Kaur Family Agriculture). Every entry drawn must be correct double entry under the rule cited beside it; check it against that rule's worked example.

**Scope marks.** **P** = the pilot: what the owner's joint family needs to run one month (ADR §10). Draw these first. **V** = v1, everything the five reference books use. **L** = later; not in this brief.

---

## Part A — Pilot frames (draw first)

### A1. New A/C: the kinds-of-account grid · P
- **Where:** S3.1 *Quick add sheet* — canvas 7 · *Quick add · a sheet, from the Ledger tab*; the deliberate-creation wizard step 1 (07 §6). App: `app/lib/features/ledger/screens/s3_1_quick_add_sheet.dart`.
- **Today:** eight tiles: Bank · Cash/vault · Credit card or OD · Person you'll pay · Person who'll pay you · Expense · Income · Capital.
- **Must show:** a grid that offers the kinds of account in `accounting/02`'s table (ADR §2, R-01…R-25).
  - **Pilot kinds:** cash · bank (may run overdrawn) · wallet · credit card · cash-credit / KCC · person or shop (one running account, side changes) · *Advance – {any named person}* · income head · expense head · gollak · sub-family running account and *Udhaar – {sub-family}* page (in a family book) · *Cash short / over* · *Not yet sorted*.
  - **v1 kinds, drawn in the same grid** so it is designed once: thing owned · loan taken / loan given · deposit (FD / RD) · deposit held · deposit paid · retention held · fund for a purpose · own money and Drawings · partner capital and partner current.
  - No *Opening Balance*, *Adjustments*, *Suspense* or *Due to/from* tile.
  - **The grid is the same in every book.** Which tiles come first may follow the setup purpose; no tile is hidden because of the kind of book (ADR §0).
  - **Step 2:** name + opening balance, asked in the kind's own words (02 §4 today). The opening posts into the book's one opening entry (A3), never into an *Opening Balance* account.
- **Also:** S2.1 *A/C picker + inline create* (canvas 2 · *S2-B*). Inline create infers the kind from the slot and asks one plain question when the slot allows two. The new kinds must be reachable here too, through *More kinds* rather than more chips.

### A2. The entry screen: shortcuts, the any-account entry, guided entries · P
- **Where:** S2 *Add entry* — canvas 2 (*State 1 · typing*, *State 2 · choosing*, *State 3 · chosen*, *Slot labels by verb*, *Preview · split entry*), canvas 11 (*First entry · typing*). App: `app/lib/features/entry/screens/s2_add_entry_screen.dart`.
- **Keep:** the single screen, amount first, the five-position pill (🔒 ADR 2026-09-03b), the live preview line, nothing pre-selected (07 §5).
- **Must show:**
  1. **The verbs are shortcuts** (ADR §1). Each still builds its entry as today; nothing on the pill changes.
  2. **An entry from any opened account to any other** (ADR §1), for the cases no verb names. The pill stays at five positions, so this needs a door of its own on S2 (see Q3). The preview line is the same sentence: `₹2,000 · Mohan → Ram`.
  3. **Guided entries** for the multi-line shapes, each one screen with the preview showing every line before Save:
     - **P** — advance settled across several heads, with the unspent part returned or the remainder handled in one of three ways (`accounting/02` §3.2–3.4, §8.4; R-39).
     - **P** — salary with an advance recovered in the same entry (`accounting/02` §3.5; R-40).
     - **P** — paid by the joint family for a sub-family, and a sub-family's money put straight into a family business: a three-book entry (`accounting/03` §3.3, §4.2–4.3; R-47…49). Each book shows only its own side.
     - **V** — loan instalment split into principal and interest (`accounting/02` §4.3; R-35).
     - **V** — thing owned bought on credit or with a loan, and sold with a gain or loss (`accounting/02` §5.6–5.7; R-36, R-41).
     - **V** — spending from a fund: one action, two postings, *paid from the Hall Fund* (`accounting/03` §5.5; R-51).
  4. **The kind rules show as plain words, never as errors after Save** (ADR §1). For example, a transfer offers only the book's own money and deposit accounts; the gollak empties only into cash or bank. A rule the entry would break is stated on the screen before Save (*"Cash would go below nil — is an entry missing?"* is a warning, not a refusal; R-02).
- **Rename:** canvas 2 · *No chip row · milk on khata* → *milk on credit* (*on khata* is forbidden, R-134). Its entry, `Dr Milk Expense · Cr Vardhman Dairy`, stays.

### A3. The opening entry · P
- **Where:** S0.6 *Opening balances — one grouped screen* (canvas 1 · *Opening balances · first run*; canvas 11 · *O6a*, *O6c*), S0.6b (canvas 1 · *What the shop has · Capital is computed*, *What the business has · each owner's capital*), S0.6f (canvas 1 · *What the joint fund has*), S0.6i (canvas 1 · *What the trust has · gollak counted*), S9.5 (canvas 4 · *Add a business · name, FY, balances*). App: `app/lib/features/onboarding/screens/s0_6_opening_balances_screen.dart`, `…/s0_6b_business_opening_balances_screen.dart`.
- **Must show:** one compound opening entry (ADR §8, `accounting/01` §4, R-34).
  - **Own money** is the balancing figure, shown and never typed (`accounting/01` §4.3).
  - **With several owners,** the partners' figures must equal *what it has less what it owes*. There is no balancing line. Draw the state where they don't agree, and how the screen says by how much (`accounting/03` §2.3).
  - **Openable:** things owned · goods on the shelf (to *Goods bought for sale*) · sub-family running accounts (ADR §8).
  - **Later in the year,** an account created then asks its opening balance afterwards (ADR 2026-10-07b, unchanged). The answer joins the opening entry's date, not a new account.
- **Withdraw:** canvas 2 · S2.4 *Opening balance correction* as an adjustment against *Opening Balance*. A wrong opening figure is fixed by a correction (A4) against own money.

### A4. Corrections, and Cancel · P
- **Where:** S4.1 *Entry detail* — canvas 2 (*Entry detail · open period*, *Locked period · Fix this entry*, *Reversed*, *Amended · struck-through history*), canvas 11 (*Entry detail*); S2.4 — canvas 2 · *Fix an old entry*. App: `app/lib/features/ledger/screens/s4_1_entry_detail_screen.dart`.
- **Must show** (ADR §3, `accounting/02` §7.1–7.3, §7.6; R-54):
  - A posted entry is **never edited**, in any period. **Remove the Edit action.**
  - ***Fix this entry***: the user says what was wrong (amount, account, or both). The app builds one balanced correcting entry **dated today**, whose note names the entry it fixes by number and date (*"corrects entry no. 41 of 12 Aug"*). The preview shows its lines before Save.
  - **Wrong account, right amount:** one entry moves it (§7.3).
  - **An income or expense of a closed year:** the correction goes to that head's *— earlier year* line (*Rent — earlier year*) (§7.6). Draw this variant.
  - ***Cancel this entry***: posts a full mirror. Both entries stay visible, the first marked *cancelled by entry no. …*.
  - **The fixed entry** shows a link to its correction, and the correction a link back.
- **Withdraw:** canvas 2 · S4.1 *Amended · struck-through history* (*"edited by …, n changes"*).
- **Rework:** canvas 2 · S4.1 *Locked period · Fix this entry*. Locked and open periods now take the same correction flow.
- **See Q2:** the 10-second Undo after Save.

### A5. Advances to anyone; approval as a setting · P
- **Where:** S5 *Advances* — canvas 6 (*Advances · who is holding what*, *The card, four ages*), canvas 13 (*The advance, four ages*); S5.1 *Advance request* — canvas 6 (*Ask for an advance*, *Sent · waiting for Sunita*), canvas 13. App: `app/lib/features/advances/screens/s5_advances_screen.dart`.
- **Must show** (ADR §4, `accounting/02` §3; R-10, R-39, R-40):
  - **An advance to any named person** (driver, house help, sewadar, member), opened like a person's account, *Advance – {name}*.
  - **Setting off (the default):** the advance posts on Save like any entry (02 §3, post-then-review). S5.1 is an ordinary entry, and nothing waits.
  - **Setting on:** today's request → approver flow (*Sent · waiting for Sunita*). Draw both variants side by side.
  - **The card's actions:** *Add bills* (the guided settle-across-heads entry, A2), *Return the rest*, *Top up*, and the three outcomes of a remainder with no bills (§3.4).
  - **Write-off goes to an expense head**, not *Adjustments* (ADR §4).
- **The setting itself:** see A8 and Q1.

### A6. Month close: the two answers · P
- **Where:** S10 *Month close wizard* — canvas 5 (*Close August · step 1*, *Step 3 · the tray*, *Step 4 · what you are signing*), canvas 11/13/14 (*Confirm & lock*); S5.5 *Cash count sheet* — canvas 5 (*Verify mode · a difference*). App: `app/lib/features/close/screens/s10_month_close_screen.dart`, `app/lib/features/cash_count/screens/s5_5_cash_count_screen.dart`.
- **Must show** (ADR §7, `accounting/02` §7.4–7.5, ADR 2026-10-27; R-24, R-25, R-70/71):
  - **Cash count differs:** one question, *whose page?*: the person minding the cash, or *Cash short / over*. A shortage the person makes good goes on their page; a small or unexplained one goes to *Cash short / over*. The difference is stated in words.
  - **Bank step:** *Matches ✓ / Doesn't match ▸ reconcile / Not checked this month*. The third answer warns, and is **not offered in the year's last month** (PLAN-211).
  - **The tray:** *Not yet sorted* lines **warn** monthly and **block only the year close**. Today's frame shows Suspense blocking the month lock; that changes.
- **PLAN-211** (the close wizard of ADR 2026-10-27) is built from these same frames.

### A7. Between books · P
- **Where:** S2.3 *Transfer* — canvas 2 (*Transfer between books*), canvas 13 (*Inter-book transfer*, *In transit, on both sides*); S8.3 *Family reconciliation* — canvas 13 · *D5*, canvas 15 (*D5 Family reconciliation*, *D5b When a pair disagrees*), canvas 15 · S8.2 *Family match check*; Canvas 17 · *4a Family match check*. App: `app/lib/features/reports/screens/s8_3_family_reconciliation_screen.dart`.
- **Must show** (ADR §6, `accounting/03` §3–§4; R-21/22, R-90…98):
  - **Naming:** each book's account for another is **named after that book** (*Rajinder's household A/c*, *Family A/c*, *Sharma Textile A/c*). *Due to/from* appears nowhere.
  - **The family book** holds one running account per sub-family, plus an *Udhaar – {sub-family}* page for money to be returned. Show both in the Ledger index (S3) and the position (S1).
  - **Money a business sends home** is *Income from {business}* in the family book and Drawings in the business book. The transfer flow says so in one line, like the B5 Drawings sheet.
  - **S8.3 becomes *Account between {A} and {B}*** (`accounting/03` §4.6): both books' accounts side by side, opening, every entry, closing, and a closing line *Agrees* or the entries found in only one book.
  - **Owner ↔ business pairs** agree entry by entry and print *profit kept in the business* or *taken out beyond the profit* (§4.1). Draw both pair kinds.
  - **Fix in one book only:** the book that missed the item gets the fix (§4.4), and the screen says which book that is.
  - **Year end:** each sub-family account is **carried forward** (preselected) or **settled** (§3.5). This sits in the year-close review (B2), but it is pilot logic, so draw the choice.

### A8. Book settings · P
- **Where:** S9 *Books & members* — canvas 4 (*Books & members · roles and log*), canvas 13, canvas 14 (*Members & roles · a trust's labels*). App: `app/lib/features/members/screens/s9_members_screen.dart`.
- **Must show** the book's policies as settings, never as a kind of book (ADR §0):
  - **Advances need approval** — off by default (ADR §4; Q1).
  - **Count notes at every cash count** — on by default when the setup purpose is a trust (ADR §0; replaces 02 §8.2's trust-only rule).
  - **The book's words:** the own-money account's name (*Own money*, *Capital – {name}*, *General Fund*), the result account's name (*Income & Expenses*, *Profit & Loss*, *Income & Expenditure*), and the result word (*Saving*, *Profit*, *Surplus*). They are set at setup from the purpose card, editable here, and never drive logic.
  - **Shared business only:** capital fixed or fluctuating (`accounting/03` §2.2; fluctuating when nothing is agreed); interest on capital (already on S14, 02 §7.1).
  - **v1, not drawn now:** year-end adjustments opt-in (ADR §14f, Later scope).

### A9. Pilot reports · P
- **Where:** S8.1 *Reports list* — canvas 15 · *Reports list*; S8.2 — canvas 15 (*Report viewer · Profit and Loss*, *Trial Balance*, *You will get, by age*); Canvas 17 (1a–1i statements, 2a Day Book, 2b Cash Book, 3a Trial Balance, 3d Full position); S8.4 *PDF preview & options* (Canvas 17). App: `app/lib/features/reports/screens/s8_1_reports_list_screen.dart`, `…/s8_2_report_viewer_screen.dart`.
- **Must show** (ADR §9, `accounting/04` §4–§5):
  - **Every report starts with the five-line head** (`accounting/04` §4.1; R-100): book · period · basis line · *Year open – figures may change* / *Year closed* · *Made on {date, time}*. On screen and on every printed page.
  - **Pilot reports:**
    - ledger page and statement of any account for any period (R-104/109)
    - the Day Book list (R-105)
    - the Cash Book, with a column per bank and the gollak (R-107; Canvas 17 · 2b today shows the gollak alone)
    - the trial balance at any date (R-108; R-73 needs a screen)
    - the position: *What I have / What I owe / Own money* (R-111)
  - **Print and export chooser** (R-117): All or several reports, any period, with or without notes.

---

## Part B — v1 frames (draw after Part A)

### B1. Reports by the accounts a book has · V
- **Where:** S8.1/S8.2, Canvas 17 (3b Profit and Loss, 3c Income and Expenditure, 3e by age, 4b Partner positions). Rules: `accounting/04` §5–§6; R-100…R-118.
- **Must show:**
  - **The Day Book's three layouts** (§5.3; R-105/106):
    - the list, without the year-close entries
    - the accountant's layout: Dr line, *To* line beneath, the note as narration. It opens with the opening entry and ends with the year-close entries.
    - the Cash Book
    - Plus a *Journal entries only* filter.
  - **The trust set,** printed together: Receipts & Payments, Income & Expenditure, Balance Sheet, and one statement per fund (`accounting/04` §6.7; R-116). Offered to every book, and the default set for the trust purpose.
  - **Last year beside this year** (§4.2) and the standing notes (§4.3) (R-101/102).
  - **The year's result** in the book's own words (Saving / Profit / Surplus), with the appropriation and the partners' table where the book has several owners (§6.4–6.5; R-112…115).
  - **Who owes what,** in age bands ≤30 / 31–90 / >90, a payment settling the oldest amount first (§5.7; R-110). Canvas 17 · 3e already ages each amount from the day it arose; check that its bands are these three.
  - **The family summary** (§6.6; R-97/98).

### B2. Year close: the review, the appropriation, settle or carry · V
- **Where:** S10.4 *Year close + carry-forward* — canvas 5 (*Year close · the ceremony*, *Sealed · brought forward*, *Reopened · certificate voided*); S14.1 *Profit distribution wizard* — canvas 6 (*Distribution · 1 Period*, *2 Preview*, *3 Confirm*); S14 / S14.2 — canvas 6, 12, 13. App: `app/lib/features/close/screens/s10_4_year_close_screen.dart`, `app/lib/features/partners/screens/s14_1_distribute_screen.dart`.
- **Must show** (ADR §5, `accounting/04` §2.1, §2.6, `accounting/03` §2; R-60, R-62, R-74…80):
  - **The book posts the year close; the user reads it and confirms** (§2.1):
    - income and expense heads to the result account
    - the result and Drawings to own money
    - with several owners, the result through the appropriation to each owner's account
  - **The appropriation step replaces S14.1's mid-year distribution:**
    - interest on capital only if agreed and only out of profit, worked by months
    - equal shares when no ratio is agreed
    - a ratio change during the year divides the profit by days
    - the remainder paisa rule of 02 §7.1 stays
    - S14 and S14.2 stay as views.
  - **Carry-forward** (§2.6): what carries, what starts again at nothing.
  - **Sub-family accounts:** carried forward or settled (A7).
  - **Owner pairs:** settle or carry (R-50).
- **Withdraw:**
  - canvas 5 · S10.4 *Reopened · certificate voided*: a closed year is never reopened (ADR §5, `accounting/02` §7.6)
  - canvas 6 · S14.1 *Distribution · 1 Period* as a mid-year action

### B3. Guided entries of v1 · V
- The loan, thing-owned and fund-spend guided entries listed in A2 item 3, drawn to the pattern Part A settles.
- Deposit interest and maturity; deposit returned, set off or forfeited; retention held and released (`accounting/02` §2.4, §5.9–5.13; R-44…46). These are ordinary from → to entries; draw them only if A2's any-account door does not already read well for them.

---

## Part C — Existing frames that become wrong

| Canvas · frame caption | S-id · screen | App path | What is wrong | Rule |
|---|---|---|---|---|
| c2 · *No chip row · milk on khata* | S2 · Add entry | `app/lib/features/entry/screens/s2_add_entry_screen.dart` | caption uses the forbidden *on khata* | R-134, `accounting/01` §3.9 |
| c2 · *Fix an old entry* | S2.4 · Adjustment wizards | `app/lib/features/entry/` (no own screen file) | reversal-only, locked periods only | ADR §3 → A4 |
| c2 · *Cash count difference* | S2.4 | as above | posts to *Adjustments* | ADR §7 → A6 |
| c2 · *Opening balance correction* | S2.4 | as above | posts against *Opening Balance* | ADR §8 → A3, A4 |
| c2 · *Write off a balance* | S2.4 | as above | posts to *Adjustments* | ADR §4: to an expense head |
| c2 · *Amended · struck-through history* | S4.1 · Entry detail | `app/lib/features/ledger/screens/s4_1_entry_detail_screen.dart` | amend chain removed | ADR §3 |
| c2 · *Locked period · Fix this entry* | S4.1 | as above | correction now the same in every period | ADR §3 |
| c6 · *Sent · waiting for Sunita* | S5.1 · Advance request | `app/lib/features/advances/` (no own screen file) | only when *Advances need approval* is on | ADR §4 |
| c5 · *Step 3 · the tray* | S10 · Month close | `app/lib/features/close/screens/s10_month_close_screen.dart` | Suspense blocks the month | ADR §7 |
| c5 · *Verify mode · a difference* | S5.5 · Cash count | `app/lib/features/cash_count/screens/s5_5_cash_count_screen.dart` | one destination, *Adjustments* | ADR §7 |
| c5 · *Reopened · certificate voided* | S10.4 · Year close | `app/lib/features/close/screens/s10_4_year_close_screen.dart` | a closed year is never reopened | ADR §5 |
| c6 · *Distribution · 1 Period*, *2 Preview*, *3 Confirm* | S14.1 · Profit distribution | `app/lib/features/partners/screens/s14_1_distribute_screen.dart` | mid-year distribution removed; becomes the year-close step | ADR §5 |
| c13 · *D5*, c15 · *D5*, *D5b*, c15 · S8.2 *Family match check*, Canvas 17 · *4a* | S8.3 · Family reconciliation | `app/lib/features/reports/screens/s8_3_family_reconciliation_screen.dart` | pair balance only, *Due to/from* pairs | ADR §6 → A7 |
| Canvas 17 · *1i Partner · Amrit Kaur — Partner Current A/c* | S4 · statement | `app/lib/features/ledger/screens/s4_account_statement_screen.dart` | a partner has a capital account (and a current account only with fixed capital) | ADR §2, `accounting/03` §2.2 |
| Canvas 17 · *1g Owner · Drawings A/c* | S4 | as above | still right; check its year-end line closes to own money | `accounting/04` §2.1 |
| c1 · *What the shop has · Capital is computed* | S0.6b | `app/lib/features/onboarding/screens/s0_6b_business_opening_balances_screen.dart` | check: own money as the balancing figure of one opening entry, not an account plug | ADR §8 |

---

## Part D — Questions the frames settle (with a recommendation)

**Q1. Where the *Advances need approval* setting sits, and who switches it.**
- The ADR's Open item says *Settings (S16)*. In 13 §3.2, S16 is *My account* (name, photo, phone, language), and S13 is Settings. A book's own policies (members, limits, roles) are on **S9 Books & members**.
- **Recommendation:** a row on the book's S9 page, beside the review limits and the peer reviewer, off by default.
  - Switching it **on** is routine: any owner or admin (the ADR says *"an owner or admin can switch it on"*).
  - Switching it **off** again is structural (02 §7.2.1 quorum), because it removes a check other members rely on.
  - The ADR does not say who may switch it off; this half is my recommendation for the owner to rule.

**Q2. The 10-second *Undo* after Save** (07 §5 step 6: *"undo = amendment/void while still local"*).
- Under ADR §3, an entry is posted the moment Save is tapped, and there is no amend.
- **Recommendation:** *Undo* stays and posts *Cancel this entry* (a full mirror), so both entries remain.
- The other reading, holding the entry unposted for 10 s, contradicts ADR §3 (*"Until the user taps Save, anything … can be changed"*) and 02 §3 (*"every entry posts … the moment it is saved"*).

**Q3. Where the any-account entry starts.**
- The pill's five positions are 🔒 (ADR 2026-09-03b), so a sixth is not drawn.
- **Recommendation:** one door on S2, *Other kinds of entry ▸*, opening a short list: the guided entries (A2 item 3) and *From any account to any account*. It takes S2.4's place as the home of the multi-line shapes. The design may propose a better place, if it keeps the one-screen rule (07 §5).

**Q4. The kinds of account on the New A/C grid in a household book.**
- ADR §0 says no tile is hidden because of the kind of book.
- **Recommendation:** order the tiles by the setup purpose (a household sees cash, bank, person, expense, income first), with the rest under *More kinds* on the same sheet. Nothing is removed.

---

## After the frames

1. `/design-pull`, then `python3 scripts/design_match.py index`.
2. The owner rules Q1–Q4 (or accepts the recommendations) → amend ADR 2026-11-11 (§13 re-sequenced, the Open S16 item closed).
3. Rewrite 02 (§1.2, §1.4, §2, §4, §5, §6, §7, §7.1, §8, §8.1, §10), 07 (§5, §6, §8, §10, §13, §14, §16) and 13 (§3.2 rows S2.4, S5.1, S8.3, S10.4, S14.1; §5 flows) from the frames; 09 ids per guided entry and per report.
4. Read the tests listed in the ADR's Consequences one by one before any is skipped.
5. Development: engine (`core_ledger`, tests first, suite A against the reference books), then UI slices, pilot rows first.
