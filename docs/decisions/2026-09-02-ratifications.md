# ADR 2026-09-02 — A3 ruled: drawings and donation receipt ratified, monthly allowances removed

Closes finding A3 of the Phase-1 design↔docs audit. The owner supplied the original fold
commission (the prompt that produced canvases 0–14), which settles provenance:

## Ratified — they were commissioned, the docs just never caught up

- **B5 · Drawings confirmation** — ordered in the fold prompt ("purpose 'My shop' …
  adding the business, **drawings**"). Now specced in 07 §5 and inventoried as **S2.5**.
  In a business book, owner takeout posts to Drawings (equity), never an expense; a
  one-line confirmation states it.
- **C5 · Donation receipt** — ordered in the fold prompt ("trustee roles, the gollak
  count … a sevadar advance, **donation receipt**"). Now specced in 07 §14 and
  inventoried as **S4.2**. Trust books only; the receipt card carries no tax language.

## Rejected — never commissioned

- **D6 · Monthly allowances** (pool → sub-family repeating entry) appeared nowhere in
  the fold prompt; it was the one invented screen, and the owner ruled it not required
  (1–2 Sep 2026). Removed from Canvas 6 (was screen 13/13) and Canvas 13 (was screen
  12/20); Canvas 13's blurb and Canvas 0's id line updated. The screen's markup is
  archived at `design/canvas-mirror/_removed/D6-monthly-allowances.json` should it ever
  be reconsidered. A karta sending monthly money to sub-families uses the ordinary
  inter-book transfer (07 §10).

## Tokens — danger-surface verdict; sunk and scrim added (audit B6/B7)

Owner ruled "best shade, uniform": **tokens.json wins** — `danger-surface` stays
`#F6E3DD` light / `#3A2723` dark (the brand-derived values; the canvases' drifted
`#FBF0EC`/`#3A2420` read too close to `surface` to work as a warning ground). The
canvases' `build-canvas.js` constants were aligned and every buildable canvas rebuilt.
Canvases 1, 2, 7 and 11 still embed the old constants until they can be rebuilt (their
partials exceed the 256 KiB read cap — pending the ZIP export).

Two tokens the fold has been using without a definition are now in tokens.json /
tokens.css / tokens.dart as **PROPOSED**: `sunk` (#EFE9DA / #1F1E1B — recessed wells:
avatar discs, keypad wells, summary strips) and `scrim` (rgba(26,26,24,.42) /
rgba(0,0,0,.45) — sheet backdrops). The canvases' `--frame` and `--dim` variables are
canvas furniture (mockup frame border, dimmed bands), not product tokens, and stay out.

## Slice 4 — the last four audit calls (owner: "do recommended")

- **S6.1 drawn.** The grouped review card ("Ramesh Sharma · Sharma Textile · 7 entries ·
  ₹23,400", per-row ✕ quick-reject, **Approve all 7** / **One by one**) now sits on
  Canvas 9 between the Inbox and the stepper, per 07 §9.
- **S17.1 folded into S17.** The Help hub as drawn *is* the grouped, searchable FAQ list;
  a separate list screen added a level for nothing. 13's row removed.
- **S18.1/S18.2/S18.4 are document pages,** rendered in a shared template patterned on
  S18.3 (which is fully drawn); the designed surface is each one's summary card on the
  S18 hub. Recorded in 13; nothing further to draw.
- **"Narration" on S7.0b stays.** It is the bank file's own column header quoted back as
  data — the user matches it against the statement in their hand (01 rule 8). A second
  carve-out is recorded under 01's forbidden-jargon rule; the app's own labels still
  never use the word.
- **Onboarding branch order ruled: after the shared steps** (07 §3.1.1 wins over Canvas
  1's drawing) — identity and safety complete before any entity setup, and every branch
  step is skippable into the checklist regardless. Canvas 0's master map realigned;
  Canvas 1's flow band follows when its partial is recovered.

## Designations — Option B ruled 🔒

Owner-ruled (2 Sep): **designations are free display labels; permissions come only from
the admin.** Any organization may pick from the 01 §2 designation tables or type its own
label per member; the capability stays one of the five stored roles plus the entry limit,
granted/changed/revoked only by a book's admin (the creator is the first admin — the
"superadmin" is the admin role itself, no new tier). A permission-verbs table now sits in
06 §1.0 mapping the owner's read/write/read-only/delete framing onto the model — with one
ledger-true refinement: **delete does not exist** (append-only, 02 §5); the corresponding
power is amend/reverse with the trail kept. `memberships` gains `designation_label`
(display-only, never consulted by permission checks). The A4 labels become *defaults*.
Surfaced for a later ruling: canvases describe Trustee as "approves" while 13 §7 gives
review to admin/head only.

**Changed:** 06 §1.0 (rewritten) + §1.1 · 07 §12 (invite gains the designation field) ·
13 §2.4 + S9.1 row · 01 (designations ⚠ → ruled). Design: Canvas 4 S9.1 gains the
designation field.

## Ledger — the gollak empties only into Cash in hand 🔒
### ⚠ Refined by ADR 2026-09-03 (gollak-deposit-flexibility): destination widened to Cash **or bank**, in one deposit or several.

Owner-ruled (2 Sep, two messages): **the Gollak account and the Cash account are
different accounts**, and counted gollak money always moves Gollak → Cash first; bank
deposits, savings and expenses are paid from Cash, never straight from the gollak. The
follow-up ruled the name: it is not a trust-specific "Trust Cash" — **it is the ordinary
Cash A/c that every ledger has**. Encoded in 02 §8.2 (a `cash_collection` account's only
outward posting is a Transfer to a `cash` account; UI offers no other destination and
never lists a collection account in expense chips). Trust seeds gain a plain **Cash A/c**
(07 §3.1, O6i). Design: C3/C3b's "Deposit into Trust SBI" replaced with **"Move to Cash
A/c"** and the explainer rewritten, EN/PA/HI (canvases 5 and 14); S0.6i shows the
three-account setup (bank · cash · collection); the sample trust ledger C2 gains a
visible Cash A/c row, native-sorted in each script (canvases 7 and 14).

## Vocabulary — Trial Balance transliterates 🔒

Owner-directed (2 Sep): **ਟ੍ਰਾਇਲ ਬੈਲੇਂਸ / ट्रायल बैलेंस** is the label everywhere — the
transliterated English term is what an accountant asks for by name. ਕੱਚਾ ਚਿੱਠਾ /
कच्चा चिट्ठा appears **in brackets only where space allows** and stays a search synonym.
Supersedes 01's earlier ਕੱਚਾ ਚਿੱਠਾ label and the fold dictionaries' ਤਲਪਟ/तलपट.
Changed: docs/01 (§2 table + ruling note) · both master dictionaries and the canvas-7
extracts (canvas 7's rendered file updates at its post-ZIP rebuild).
