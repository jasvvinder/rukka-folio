# ADR 2026-09-03 — Menu rows: "Close the month" in; Import is part of entry, not a Menu row

Owner, reviewing the restructured Menu canvas (canvas 15) on 3 Sep 2026, on the two Menu
children 13's screen table listed but the drawn Menu (S8) lacked:

> Close the Month could be listed in menu, but Import a bank statement is the part of
> entry, so it should be manage accordingly.

## The rulings 🔒

1. **Close the month is a Menu row** — in *The books* group, directly after Reports, with a
   live subtitle (e.g. *August open · 3 items waiting*). It opens the month-close wizard
   (S10); year close (S10.4) is reached through it after March. 13's parent for S10 stays
   **S1 / S8** (the Home prompt on the 1st remains).
2. **Import a bank statement is part of entry.** Its entry point is the **entry screen (S2)
   header — the action slot top right, opposite the close ✕** — because importing is a way of
   *entering* many lines at once. It is **not** a Menu row. 13's parent for S7 changes from
   S8 to **S2**; flow F4 starts `S2 → S7`. Import lines still surface in the Inbox (S6).
3. (Same day, earlier) **Legal is the last Menu row** under *This app* (S18).

## What changed where

- **13 §screen table** — S7 parent `S8` → `S2 (import button, header)`; F4 first hop rewritten.
- **07 §1** — Menu bullet lists *close the month* and *legal*; **07 §11** gains the
  entry-point sentence (S2 header, not Menu).
- **Design** — canvas 15 S8: *Close the month* row + Menu path → canvas 5 (S10 · S10.1 ·
  S10.4); the "not yet a row" placeholder path removed. Canvas 2: the S2 header's empty
  right slot becomes the import button (all three language variants of S2 state 1); new
  branch *Import · part of entry* → canvas 8 cards. Canvas 8 row labelled with its entry
  point; blurb updated. Master map cards for 2 and 15 updated.
- **Dictionaries** — *Close the month*, *August open · 3 items waiting* (pa/hi drafts).
