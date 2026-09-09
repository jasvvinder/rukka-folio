# Seeded category trees — DRAFT (EN only)

⚠️ **Draft, not shippable.** `01 §1.8` puts these behind the same gate as every other string:
*"Seeded category trees (household/shop/trust) ship in all three languages in a separate seed file, same
review gate."* `02` (open items) adds: *"draft with the family pilot; ship in EN + PA."* So **ਪੰਜਾਬੀ and
हिन्दी are deliberately blank** below and must come from native review, not from translation — and the
EN column itself is a proposal for the pilot, not a ruling.

What ADR 2026-09-09c §1 settles is the **structure** of the seed. This file is the missing half: the
names. Every EN name below is taken verbatim from `docs/reference/worked-examples/`, the behavioural
reference (CLAUDE.md § Accounting authority) — nothing here is invented.

**Finding: there are four trees, not three.** `01 §1.8` and `02` both say *household / shop / trust*, but
the worked examples carry a distinct **farm** vocabulary (Seed & Fertiliser, Diesel & Machinery, Labour,
Cattle Feed, Crop Sale, Milk Sale) that no shop tree covers, and `07 §5.7` already hedges by saying *"the
shop **or trade** category tree"*. A Punjabi joint family's agriculture book is a first-class case, not a
variant of a cloth shop. Owner to confirm the fourth tree before it ships.

---

## 1. Household — `BookType.personal`, `family`, `joint`
Source: `individual-rahul-sharma.md`, `joint-family-sharma.md` (books 1 and 4).

| EN | ਪੰਜਾਬੀ | हिन्दी | Class |
|---|---|---|---|
| Salary Income | | | income |
| Household Expense | | | expense |
| Grocery Expense | | | expense |
| Utility Expense | | | expense |
| Milk Expense | | | expense |
| Education Expense | | | expense |
| School Fee Expense | | | expense |
| Medical Expense | | | expense |
| Travel & Fuel Expense | | | expense |
| Insurance Expense | | | expense |
| House Repair Expense | | | expense |
| Function & Ceremony Expense | | | expense |
| Festival Expense | | | expense |
| Property Tax Expense | | | expense |

## 2. Shop / trade — `BookType.business`
Source: `business-sharma-textile.md`, `joint-family-sharma.md` (book 3).

| EN | ਪੰਜਾਬੀ | हिन्दी | Class |
|---|---|---|---|
| Sales | | | income |
| Purchases | | | expense |
| Rent Expense | | | expense |
| Staff Salary Expense | | | expense |
| Freight Expense | | | expense |
| Shop Utility Expense | | | expense |
| Packing & Misc. Expense | | | expense |

## 3. Farm — `BookType.business`, agriculture ⚠️ new tree
Source: `joint-business-partnership.md`, `joint-family-sharma.md` (book 2).

| EN | ਪੰਜਾਬੀ | हिन्दी | Class |
|---|---|---|---|
| Crop Sale Income | | | income |
| Milk Sale Income | | | income |
| Seed & Fertiliser Expense | | | expense |
| Diesel & Machinery Expense | | | expense |
| Labour Expense | | | expense |
| Machinery Repair Expense | | | expense |
| Cattle Feed Expense | | | expense |

## 4. Trust — `BookType.organization`
Source: `trust-singh-sabha-gurudwara.md`. `07 §3.1` 🔒 already names this seed and it is reproduced
unchanged. The gollak is a `cash_collection` **money** account, not a category, and 🔒 stays a different
account from the Cash A/c (02 §8.2).

| EN | ਪੰਜਾਬੀ | हिन्दी | Class |
|---|---|---|---|
| Gollak Donation Income | | | income |
| Sponsor Donation Income | | | income |
| Langar Expense | | | expense |
| Building Repair Expense | | | expense |
| Electricity Expense | | | expense |
| Granthi Honorarium | | | expense |
| Sound & Media Expense | | | expense |

---

## How these reach the app

Not as ARB keys. `createBook` already takes seeded names as **parameters** (`openingBalanceName`, and
since ADR 2026-09-09b `drawingsName`), so the caller supplies them and the engine stays free of strings —
which is also what keeps the `core_*` purity rule intact. The category tree follows the same route: the
UI passes the localised list in, loaded per book type and locale.

Consequences for whoever ships this:
- These are **account names** — user data the user may rename — not UI labels. `check_strings.dart`
  governs ARB keys and should not be pointed at this file.
- A book seeded in ਪੰਜਾਬੀ keeps its ਪੰਜਾਬੀ account names if the user later switches to हिन्दी. Renaming
  is the user's to do: `03 §3.3` treats account names as content, and rewriting them behind the user's
  back would be rewriting their ledger.
- ⚠️ That last point needs the owner's confirmation. The alternative — seeding language-neutral ids and
  translating at display time — conflicts with the names being editable, and is not what `01 §1.8`
  describes.

## Open ⚠️
- ਪੰਜਾਬੀ and हिन्दी columns: native review, per `01 §1.8`. Not machine-translatable — `01` is explicit
  that the glossary governs and that a term absent from it must be asked for, never translated.
- The fourth (farm) tree needs the owner's yes.
- Tree-per-book-type is a starting set, not a taxonomy: `02` calls the trees *editable*, and `07 §6`
  relies on the tree being present so the ledger is *"never truly empty"*.
