# ADR 2026-09-09c — The chart of accounts is seeded from the setup answers, and S0.6b is one grouped screen

Owner-directed 9 Sep 2026: *"we are creating the accounts automatically… then use the 'What do you have?'
screen to let them instantly customize those accounts and add their Opening Balances."*

Seeding is not new — `02` (accounts table) already says the category tree is *"seeded tree per book type,
editable"*, `07 §5.7` says creating a business book *"seeds the shop or trade category tree"*, `07 §3.1`
lists the trust's seeds by name, and `07 §6` relies on it: *"seeded tree is already present, so never truly
empty"*. What this ADR settles is **the whole seed, per branch**, and what the opening-balances screen
becomes once the accounts already exist.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The seed, per book ⟦tests: A-09c-1⟧
Created by `createBook` from the answers already given on S0.6a / S0.6a1 / S0.6d / S0.6g. Names are the
seeded, editable defaults; the user renames them on S0.6b (ruling 3).

| Book | Money | Equity | Income · Expense | Interbook |
|---|---|---|---|---|
| **Personal** | `Cash A/c` | `Opening Balance / Capital` | household tree | — |
| **Business · Just me** | `Business Cash A/c` | `Opening Balance / Capital`, `Drawings A/c` | `Sales A/c` + shop or trade tree | — |
| **Business · Shared** | same | `Opening Balance / Capital`, `Profit Distributed`, **one `{Name} — Partner Current A/c` per owner** | same | — |
| **Family pool** | `Joint Cash A/c` | `Opening Balance / Capital` | household tree | one per linked book |
| **Trust** | `Cash`, `Gollak Cash` (`cash_collection`) | `Opening Balance / Capital` | Donation Income · Langar, Building Repair, Honorarium | — |

- The trust row restates `07 §3.1` 🔒 unchanged, including that the gollak and the Cash A/c are different
  accounts. ⟦tests: A-09c-1⟧
- **No party accounts are ever seeded** — `02 §1.2` 🔒, one party, one account, both roles, placement by sign, so there is no Sundry Debtors and no Sundry Creditors to create. ⟦tests: A-09c-2⟧
  Customers and suppliers appear as they are traded with, inline, class inferred from the slot. Seeding
  them would slow the 8-second entry and misrepresent the model.
- **Superseded by ADR 2026-09-09d §1 — no bank is seeded at all.** Formerly: bank accounts are seeded unnamed. The app cannot know the bank; the seed is a generic `Bank A/c`
  captioned *name it later*, and S0.6b is where it becomes *HDFC Bank*. This is already how the designed
  S9.5 artboard reads. ⟦tests: A-09c-3 @M5⟧
- **Interbook accounts are never typed.** A pool book gains one Due-to/from account per linked book
  automatically as those books are created (`02 §6`), matching `joint-family-sharma.md` rows 3–7. A family
  that later adds a business gets the pair on both sides for free. ⟦tests: A-09c-4 @M5⟧

### 2. Sub-family shares are books, not accounts ⟦tests: A-09c-4 @M5⟧
- A joint family that owns businesses is **several books linked by Due-to/from pairs**, never one book with
  sub-family shares — `joint-family-sharma.md` is four books, and `02 §7.1` 🔒 closes with *"Two separate
  fairness ledgers — partner accounts for the business, sub-family accounts for the pool — and conflating
  them corrupts the partnership arithmetic."* ⟦tests: A-09c-4 @M5⟧
- Consequently the family branch (S0.6d–f) creates **the pool book only**. Each head's own book comes from
  their own onboarding; each business is its own book via S0.6a. ⟦tests: A-09c-4 @M5⟧

### 3. S0.6b is one grouped screen, not a three-step wizard ⟦tests: F1-09c-1⟧
- The wizard shape recorded in `13 §3.2` (S0.6, *"design O6a–c: what you have · who owes you · who you
  owe"*) and in DESIGN-PACK O6 (*"Three steps with a progress bar"*) is **superseded for every branch**:
  once the accounts are seeded, this screen is a **review-and-fill**, not a creation flow, and the three
  steps become three **groups on one screen**. ⟦tests: F1-09c-1⟧
- Groups use the consumer vocabulary (`02 §10` 🔒) — never Assets/Liabilities, which belong to the professional surfaces. ⟦tests: F1-09c-1⟧
  *What you have* · *Who owes you* · *Who you owe*, plus *What each owner put in* on a shared business.
  A business book still names its accounts professionally (`01 §1` rule 4): Capital A/c, Drawings A/c,
  and Sundry debtors / creditors as group labels derived by sign.
- Every seeded row is editable in place: rename, set an opening balance, or add another of the same kind.
  *Skip for now* survives, and the S0.7 setup checklist still brings the user back. ⟦tests: F1-09c-1⟧
- Rows the user leaves at ₹0 are **still created** — the seeded chart is the point. ⟦tests: F1-09c-2 @M5⟧

### 4. The opening entry must balance, and the screen says how ⟦tests: A-09c-5 @M5⟧
- Opening balances post as one entry per `02 §4`; **`Opening Balance / Capital A/c` absorbs the
  difference**, which `verbs.dart:150` already states is correct. ⟦tests: A-09c-5 @M5⟧
- **Shared business:** each owner's contribution is **asked, never derived**. `02 §7.1` 🔒 keeps
  contribution and sharing ratio separate — *"Contribution never changes the sharing ratio"* — so the
  ratio must not be used to split the opening money. It may be offered as an **editable suggestion**,
  labelled as one. ⟦tests: A-09c-6 @M5⟧
- Each owner's opening contribution posts `Dr {money accounts} · Cr {owner} — Partner Current A/c`, the
  same shape as `02 §7.1`'s "owner pays a business cost from their own pocket". Not to a Capital account —
  there is one Partner Current per owner and it is the single place that relationship lives.
  ⟦tests: A-09c-6 @M5⟧
- Where the owners' contributions do not equal the net opening position, the screen **shows the difference
  and where it goes** (`Opening Balance / Capital`) rather than blocking. Never a silent plug.
  ⟦tests: A-09c-5 @M5, F1-09c-3 @M5⟧

## Consequences
- **`app/`:** `LocalLedger.createBook` grows the per-type seed of ruling 1; `features/onboarding` gains the
  grouped S0.6b and its per-branch variants (lanes U1c–U1f).
- **Docs:** `07 §5.7` (the seed is now specified, not "seeds the shop or trade category tree"), `13 §3.2`
  S0.6 row (three steps → one grouped screen), `07 §3.1.1`. DESIGN-PACK O6 needs rewriting from three
  steps to groups — a design-side change, so it goes with the artboards.
- **Design:** five journey variants of the screen drafted 9 Sep 2026 and staged in the Claude Design
  project (`partials/new-screens-d.json`).
- **Milestone:** M5.

## Open ⚠️
- **The category trees are drafted but not ratified** — `docs/reference/seed-category-trees.md`, EN only,
  every name taken verbatim from the worked examples. Two things need the owner: the ਪੰਜਾਬੀ/हिन्दी columns
  (native review per `01 §1.8`, never machine translation), and a **fourth tree**. `01 §1.8` and `02` both
  say household/shop/trust, but the examples carry a distinct **farm** vocabulary that no shop tree covers,
  and `07 §5.7` already hedges with *"the shop **or trade** category tree"*.
- **Original wording of this item:** the household / shop / trade category trees are not written. `02` (open items) lists them as
  *"Default seeded category trees per book type — draft with the family pilot; ship in EN + PA"*, and
  `01 §glossary` puts them behind the same native-review gate. This ADR specifies the **structure** of the
  seed, not its category names; those still need the pilot and the trilingual review. Until then the seed
  ships with the accounts named in the worked examples.
- **Personal-book seed** is the least evidenced row of the table — `individual-rahul-sharma.md` should be
  read against it before U1f builds S0.6.
