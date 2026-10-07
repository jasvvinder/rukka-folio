# ADR 2026-10-07b — An account created inside an entry asks for its opening balance afterwards, on its statement

02 §4 (owner-locked): *"Every new account asks for its opening balance at creation — not only during first-run
setup."* The Ledger's *+ New A/C* sheet does ask (S3.1, `s3_1_quick_add_sheet.dart:141-183`). An account created
from the entry picker does not (`s2_add_entry_screen.dart:1195`, `_create` → `ledger.addAccount`, no opening). A
person added during *Gave on credit* therefore starts at ₹0 even if they already owed money. Asking in the middle of
the entry would break 07 §1 rule 1, the owner-locked 8-second entry.

**Owner ruled, 7 Oct 2026:** ask afterwards, on the account, not during the entry or on the *Saved* toast. The frames
were approved the same day (c7 S4 *opening balance not set*, S4 *add the opening balance*, S3 marker; staged in
`partials/new-screens-e.json`).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Inline creation stays one tap; the question waits on the account 🔒 ⟦tests: F1-1007b-1 @M13, F1-1007b-2 @M13⟧
- Creating a money or people account from the entry picker adds nothing to the entry flow.
- Until its opening balance is answered, the account's A/C statement (S4) shows **Opening balance not set** at the top,
  with **Add opening balance** and **Not needed**. Its row in the Ledger index (S3) carries a quiet
  *Opening balance not set* line in the accent colour, not amber.
- Expense and income accounts never get it. They start at zero for the current year (02 §4).
- This is how 02 §4's *"asks … at creation"* is met for inline creation. S3.1 is unchanged.

### 2. The answer posts what S3.1 posts 🔒 ⟦tests: F1-1007b-3 @M13⟧
- **Add opening balance** opens a sheet with the same class-worded question as S3.1. For a person: *They owe you / You
  owe them* plus the amount. For a money account: *balance today*.
- It posts **one** opening adjustment against Opening Balance (equity), dated at the book's start (ADR 2026-09-09d §4),
  through the same `openingBalances` path as S3.1. The read-only gate of ADR 2026-09-24b §13 applies.
- **Not needed** records that the opening is zero, posts nothing, and removes the prompt and the marker. Either answer
  is final for the prompt. Later corrections go through *Your books → Opening balances* (ADR 2026-09-03b ruling 2).

## Consequences
- **Code (one `lane-ui` slice):**
  - `app/lib/features/ledger` (S4 prompt, S3 marker, the sheet reusing S3.1's opening widgets);
  - a per-account *opening answered* flag in the data layer: set by S3.1, S0.6/S0.6b and this sheet; unset for inline
    creation;
  - F1-1007b-1…3; design match against the staged c7 frames once placed.
- **Docs:** 02 §4 and 07 §6 (the `+ New A/C` / inline creation line) carry the cross-reference.

## Open ⚠️
- ⚠️ Where the *opening answered* flag lives (an account field vs a device preference) is for the lane to propose. It
  must survive sync, because a second device should not ask again. If it needs an envelope field, that is 03's call
  and comes back to the owner.
