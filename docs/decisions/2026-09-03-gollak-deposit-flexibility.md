# ADR 2026-09-03 — Gollak deposits are flexible: Cash A/c or bank, in one go or in parts

Refines the 2 Sep gollak ruling (ADR 2026-09-02, "Ledger — the gollak empties only into
Cash in hand"). The owner, on seeing that trusts differ in practice ("As you said there
could be multiple cases. So this should be done flexible"):

> The gollak will not be emptied until the counted cash fully deposits to cash account
> or bank a/c.

## The rule 🔒 (02 §8.2)

- A `cash_collection` account's only outward posting is a Transfer to one of the book's
  **money accounts — the Cash A/c or a bank account**. The 2 Sep "Cash first, always"
  reading is widened: count-and-bank-directly trusts are as legitimate as
  count-into-the-cash-box trusts.
- **Partial deposits are ordinary**: the box may be emptied in one transfer or several.
  The collection account's balance is always exactly *what is still in the box*; the
  gollak is not "emptied" until the counted cash is fully deposited.
- Unchanged from 2 Sep: the gollak is **never a spending source** (no collection account
  in expense chips), a count never moves money, and every organization book seeds a
  plain Cash A/c.

## What changed where

- **02 §8.2** — locked paragraph rewritten (destinations now `cash` **and `bank`**;
  partial-deposit and balance-means-box sentences added).
- **07 §3.1 + O6i** — lock sentence updated to the flexible wording.
- **Design (canvases 5, 14 + packC source)** — C3/C3b: button "Move to Cash A/c" →
  **"Deposit into Cash or bank"**; explainer rewritten in EN/PA/HI (deposit into Cash
  or bank, one go or in parts, balance = what is still in the box, never expenses);
  designer note updated. C3c (the Cash A/c verify count) is unaffected.
