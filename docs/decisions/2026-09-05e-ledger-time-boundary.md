# ADR 2026-09-05e — Ledger time boundary: what a balance is, what a year certifies, and what the reader re-checks

Fifth ADR of 5 Sep 2026, from the seven-spec review fan-out. 02 is the strongest spec on
*representation* — the class model, placement-by-sign, the six verbs, post-then-review, partner
accounts and the two kinds of cash count are right and the M1 code implements them faithfully. Its
weaknesses are all at the **time boundary**: the balance formula in §9 is literally wrong, the
year-close vector has no as-of rule, P&L across 31 March is undefined and conflicts with the
accounting reference, and several objects 02 owns (period re-open, structural approvals, business
settings, Suspense, Profit Distributed, Drawings, Corpus) had no home in the spec or the registry.
Owner confirmed 5 Sep 2026 ("accept all recommendations").

**On the accounting-authority conflict.** CLAUDE.md says: when 02 and the worked examples appear to
disagree, stop and ask. The reference's trust section (`financial-accounting-standards.md` §6,
errata F-3) says Donation Income "closes to Corpus only at year end"; 02 §1.2 🔒 forbids closing
entries. The question was put to the owner as decision A1 and ruled: **the engine keeps the
no-closing-entries rule; the reference is amended, not the engine.** Recorded here so it is never
re-litigated at the golden freeze.

## Rulings 🔒 ⟦tests: n/a — section heading; each ruling below carries its own ids⟧

### 1. The balance formula (02 §9) ⟦tests: A-02-35, A-02-39, A-02-45⟧
`balance(account)` = Σ signed lines of **the head of every accepted amend chain** whose status is
`posted` or `void`, **excluding** (a) advance requests still `pending` (§7) and (b) late arrivals
sitting in the closer's tray (§8). A reversed entry and its reversal **both count** — they net to
zero; excluding `void` entries, as the old wording did, would remove the amount twice. Amended-away
entries count through their head only. `review_state` never affects a balance. The M1 code
(`projection.dart` `isCounted`) already does this; the spec now says it.

### 2. The certified vector has an as-of rule, and carries balance-sheet accounts only (02 §8.1) ⟦tests: A-05e-2, A-02-53⟧
- The year-close vector is the balance of every **money, party, advance, partner and
  equity_system** account restricted to entries whose **`accounting_date` ≤ the FY's last day**,
  regardless of HLC. An entry dated 3 April posted before a 5 April close belongs to the new year.
  (M1 cut by HLC position; that is a bug, fixed at M2.)
- **Category accounts are not carried.** P&L for a year is computed from that year's envelopes
  alone. The vector records the year's **net surplus/deficit** as one line, and the balance sheet
  presents **Accumulated surplus** (business/family) or **Corpus** (trust) as a *computed* line =
  Σ certified net results + opening equity − distributions. No closing entry exists; the reference's
  "closes to Corpus" becomes "is *presented* under Corpus" (errata entry F-5).
- Income and expense ledgers therefore open each FY at zero and carry no *b/f* row; money, party,
  advance and partner ledgers carry *Opening balance b/f* exactly as 02 §8.1 says.
- 03 §3.3 rule 3 and 05 §8 ("seed from vector, replay open FY") now produce an FY-scoped P&L by
  construction.

### 3. Late arrivals: in the live balance, out of the certified month (02 §3, §8) ⟦tests: A-02-51⟧
§3's principle wins: **no recorded reality is excluded from a live balance.** A late arrival counts
in every live figure the moment it lands. What it does not do is alter a **certified** month: the
locked month's statements, reports and close hash stay as certified; the tray is the reconciliation
surface where the closer re-dates it (default) or re-opens the month. Ruling 1's exclusion (b)
applies to *certified* figures only. 02 §8's "absent from all report totals" and §11's test are
reworded accordingly.

### 4. Close preconditions gain the sync-layer blocks (02 §8 step 3, §8.1) ⟦tests: A-05e-1⟧
A month cannot lock and a year cannot close while the book has **any open author-sequence gap**
(ADR 2026-09-05b §3) or **any `held` envelope** (ADR 2026-09-05b §4). Nobody certifies a balance
with entries known to be missing. `yearClosePreconditions` gains both checks at M2.

### 5. Locks are all-time objects (02 §8; 05 §8) ⟦tests: A-02-48, A-02-49⟧
The validity rule "entry HLC precedes the lock HLC of its period" needs the complete lock history,
including for cold-archived years. `period_lock` and **`period_unlock`** join `book_config`,
`account` and `rule` as **all-time** objects in the bootstrap hot set. They are tiny.

### 6. Verb → posting shapes are reader-enforced invariants (02 §1.4, §2) ⟦tests: A-05e-8⟧
§2's posting table is no longer authoring-only. Each `kind` has a **class-shape invariant** every
reader re-checks (as the advance shape already is): `money_in` = Dr money · Cr {income | party};
`money_out` = Dr {expense | party} · Cr money; `gave_credit` = Dr party · Cr {money | income};
`took_credit` = Dr {money | expense} · Cr party; `transfer` = Dr money · Cr money (or the §6 pair
shapes); `adjustment` = exactly one `equity_system` counter-account or a `refs.reverses` mirror.
Violation → quarantine `shape_violation`. This closes the last hostile-author hole: a mislabelled
kind can no longer corrupt day-books, P&L or ageing while passing sum-to-zero. The optional expert
Dr/Cr mode (§12 item 5), if ever built, is bound by the same shapes.

### 7. Family Reconciliation across sealed books (02 §6) ⟦tests: A-05e-10⟧
A due-to/due-from pair is **reconcilable only when the reader holds both books' keys**. Where one
side is a personal or sub-family book the reader cannot open (04 §5.2), the report shows that
book's side as **one-sided · unconfirmed**, never as a mismatch. The check remains the only
cross-book integrity check; it now says when it cannot run.

### 8. Profit distribution: losses, period, ceiling (02 §7.1) ⟦tests: A-05e-3, A-05e-4, A-05e-5, A-05e-6, A-05e-7⟧
- **Loss sharing mirrors the profit posting:** `Dr each Partner Current · Cr Profit Distributed`,
  split by the same ratio with the same remainder rule (remainder to the largest ratio), so
  sum-to-zero holds identically. `splitByRatio` accepts a negative total at M2.
- **"Net profit for the period" is FY-scoped:** the open FY's income minus expense, minus any
  distribution already posted in that FY. `netProfit` becomes FY-scoped at M2.
- **Ceiling:** cumulative distributions may not exceed accumulated surplus (ruling 2's computed
  line); the wizard refuses and says by how much.
- **Interest exceeding profit:** interest is still credited in full (it is a contractual
  appropriation); the remaining figure is then negative and is shared as a loss under the first
  bullet. The preview shows both lines.
- Rounding stated in integers: `floor(amount × weight ÷ Σweights)` per partner, never
  `amount × ratio` as a float. Interest day-count is **Actual/365** (366-day years divide by 365).

### 9. Structural actions and the peer reviewer (02 §7.2, §7.2.1; 06 §1.1; 03 §3.3 rule 5)
- **Member removal, FY-start change and book archive/delete are structural** (owners' quorum),
  as 02 §7.2.1 already lists; 06 §1.1's permission table is aligned (it said admin-only).
- **Changing the financial-year start is forbidden once any year has closed** — it would
  silently re-boundary every certificate. Before the first close it is structural.
- **The peer reviewer lives in the `book_config` envelope**, not in `book_roles`. The authoring
  client writes `review_approver` from it; readers re-check that the approver is the configured
  peer and is not the author. The projector stays pure (03 §3.3 rule 5) and self-approval is
  detectable by everyone.

### 10. One word, one state: `held` (02 §5; 03 §3.1; M2) ⟦tests: A-02-45, A-02-51⟧
`held` means **dangling reference awaiting its target** (ADR 2026-09-05b §4) and nothing else. The
M1 `EffectiveStatus.held` (a late arrival in the closer's tray) is renamed **`inTray`**. The tray
is a *presentation and certification* state (ruling 3); `held` is a *projection* state.

### 11. Registry and object housekeeping (02 §1.2, §1.3; 03 §2.3) ⟦tests: A-05b-6⟧
- `object_type` registry gains **`period_unlock`**, **`structural_approval`** (initiation,
  approval, veto, lapse — one type, a `phase` field) and **`business_setting`** (ratio, interest
  terms, quorum rule, FY start). Recurring entries stay parked (10 § Phase 2).
- 02 §1.2's `equity_system` examples list every system role the code already has: Opening
  Balance, Adjustments, Suspense (§10), Profit Distributed (§7.1), Drawings (07 §5.7), Corpus
  (trusts), Due to/from {Book}.
- The Entry JSON gains `currency` (already locked by §1.4 rule 5), `channel` (§2 prose) and
  `author_seq` (05 §4).

### 12. Smaller rulings ⟦tests: A-05e-9, A-05e-11⟧
- **Running-balance order is locked:** statements sort by `(accounting_date, hlc, envelope_id)`;
  identical on every device.
- **Import duplicate hash** is `(account, date, amount, normalised description, per-file ordinal)`;
  normalisation = trim, collapse whitespace, case-fold, strip the bank's own running balance. Two
  genuine identical same-day withdrawals no longer collide.
- **Negative physical cash** is legal (placement-by-sign) but always a missing entry: the `cash`
  subtype shows a warning; `cash_collection` and bank subtypes do not.
- **Year state is `closed`; "Certified ✓" is badge copy** (13 §6 said `certified`).
- **07 §13 blocking list aligned with 02 §8 step 3:** open review flags and Suspense **block**;
  aged advances and unverified cash counts **warn**.
- **09 §3.1's interest-tagging test is normative** — interest posts to Profit Distributed, never
  to an expense account; the 10 backlog item that still called this open is closed (interest on
  *hand loans* remains parked).
- **Interest illustration:** 02 and the test compute Harjit ₹1,354.52 (half-up to the paisa, then
  displayed to the rupee → ₹1,354; remaining ₹5,86,039). The worked example's ₹1,355 / ₹5,86,038 is
  a rounding slip corrected via errata F-6. The partnership fixture's equal-share split is stated
  in rupees; the rule is paise (errata F-7).

## Declined / deferred
- Making any `accounting_date` inside a closed FY invalid outright (alternative to ruling 5): it
  would forbid the legitimate reversal-dated-in-open-FY flow's *reference* to old dates and is not
  needed once locks are all-time.
- A stored `Accumulated surplus` account: it would reintroduce a closing entry by another name.
- Auto-posting late arrivals on re-open (02 §12 item 4) — still post-pilot.

## What changed where
02 §1.2 (roles list, computed surplus/Corpus), §1.3 (JSON fields), §1.4 (rule 7 shapes), §2
(shape note), §3 (live-vs-certified), §5 (`held`/`inTray`), §6 (unconfirmed pairs), §7.1 (loss,
period, ceiling, rounding, Actual/365), §7.2 (peer reviewer in book_config), §7.2.1 (FY-start after
close), §8 (late arrivals, step 3 blocks, all-time locks), §8.1 (as-of, balance-sheet-only vector,
preconditions), §9 (formula, order), §10 (dedupe), §11 (tests), §12 (open) · 03 §2.3 registry,
§3.1 comment, §3.3 rule 5 · 05 §8 hot set · 06 §1.1 structural row · 07 §13 blocking list · 09
suite A line, H2 line · 10 M2 row, backlog interest row · `reference/accounting-audit-errata.md`
F-5…F-7 (pending bookkeeper sign-off) · `reference/financial-accounting-standards.md` §6 wording ·
`worked-examples/joint-business-partnership.md` interest line.
Code (M2): rename `EffectiveStatus.held` → `inTray`; `held` state for dangling refs; vector as-of
by `accounting_date`; FY-scoped `netProfit`; negative `splitByRatio`; shape invariants in
`checkUniversalInvariants`; `projector_version` on `PeriodLock`/`YearClose` events; author-gap and
held checks in `yearClosePreconditions`; skip the stale `amendTargetMissing` test with a pointer here.

## Open ⚠️
1. Whether the trust's Corpus line should also show the split *restricted vs unrestricted* funds
   that some auditors ask for — reference §6 owner to say at bookkeeper sign-off.
2. Debit-balance partners charged interest (02 §7.1 ⚠️) — unchanged, still owner's call.
3. Interest day-count basis Actual/365 vs Actual/Actual — ruled Actual/365 here; confirm with the
   bookkeeper alongside F-6.
