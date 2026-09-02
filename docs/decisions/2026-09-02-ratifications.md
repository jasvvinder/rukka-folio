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
