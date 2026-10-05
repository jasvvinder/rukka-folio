---
name: ui-screen
description: Build one or more Flutter screens by S-id (13 §3.2) inside a feature folder — tokens only, ARB parts for EN/PA/HI, states from 13 §4.3, an F1 widget test per screen. Use for any app/ lane.
---

# /ui-screen $ARGUMENTS

`$ARGUMENTS` = feature folder + S-ids (`entry S2 S2.1 S2.2`).

## Read (sections only)
1. `docs/13-ux-architecture.md` §3.2 — the rows for your S-ids (`grep -n "S2\b\|S2\.1" docs/13-ux-architecture.md`); §4.1–§4.3 components and states; §8 cross-cutting rules.
2. `docs/07-ui-flows.md` — the section that owns the screen (§4 Home, §5 entry, §6 ledger …) and §1 global rules 🔒.
3. `design/design-system.md` — only the component sections you use; `app/lib/shared/tokens.dart` for names.
4. The newest ADR in `docs/decisions/` that names your S-id (`grep -l "S2\b" docs/decisions/*`).
5. **The canvas frames — before you write a widget** (ADR 2026-10-05 §1): `python3 scripts/design_match.py render <S-ids>`
   (add the design ids of any entity/role/state variant 13 §3.3 lists for your screen), then open each PNG in
   `build/design_match/canvas/`. **The frame decides layout, components, placement, icons and density**; the docs decide
   behaviour, states and copy rules; `tokens.json` decides values (a canvas size maps to its type role, never a literal).
   A frame that contradicts a 🔒 line → stop, `⚠️ SPEC:`, `open`. An S-id with no frame → follow the nearest drawn pattern and
   say which in the record.

## Build
- Files: `app/lib/features/<feature>/<screen>_screen.dart` (+ `widgets/`), `app/lib/features/<feature>/routes.dart` exporting `List<RouteBase> routes`. Nothing outside your folder except your ARB part and `design/match/<S-id>.json` for the S-ids you build (Design match step 4; ADR 2026-10-05 §2). The capture and pair PNGs (`app/build/design_match/`, `build/design_match/`) are git-ignored output the tools write, not files you own.
- **Strings:** `app/lib/l10n/parts/<feature>_en.arb`, `_pa.arb`, `_hi.arb` — dotted keys `screen.element.state`; PA/HI are real translations, or a faithful draft marked `"@key": {"description": "machine-draft — native review M12"}`. Forbidden jargon (01 §1.3): no *debit/credit* on consumer screens — *Money in / Money out*; professional surfaces (statement, exports) say Dr/Cr.
- **Tokens only:** colours, spacing, radii, type from `tokens.dart`. A hex literal is review-blocking (`check_purity`). Colour never alone — pair with icon or text (07 §1).
- **States** for every screen: loading (ruled skeleton, 11 §4.5), empty, error, offline (S19.3 is non-blocking), read-only (S12.5 pattern), and the role variants of 13 §2.3.1 that apply.
- **Data:** through `data`/`core_ledger` APIs only — never re-implement posting logic, never touch money as double. Sync/auth through the `SyncClient`/`AuthClient` interfaces with the in-memory fakes.
- Entry-flow screens: the 8-second budget — keypad first, defaults prefilled, no dead ends; `Semantics` labels for amount-plus-direction.
- Accessibility: 200 % font scale without overflow at 375×667 and 360×800; focus visible; `lang` on user-typed strings.

## Test (F1, every push)
`app/test/features/<feature>/<screen>_test.dart`; names start with the id (`F1-07-<n>` — next free number from `dart run scripts/check_coverage.dart`). Per screen: renders each state; strings resolve in EN/PA/HI (`Localizations` pumped per locale, no overflow at 200 %); primary action reaches the engine (fake) with integer paise; for S2: tap sequence completes in ≤ 8 steps.

## Design match (ADR 2026-10-05 §2) — required before `complete: true`
1. **Capture:** `app/test/features/<feature>/<screen>_design_test.dart` (inside your folder; goldens land in its `goldens/`), tagged `F1`, one `rkDesignCapture(...)` per state the
   canvas draws (default first; plus each empty/error/role/entity frame the canvas has). Pass `tab:` for a tab screen so the
   tab bar is in the picture. **Capture each state twice**: `target: RkDesignTarget.ios` (390×844, the default; matched against
   the frame) and `target: RkDesignTarget.android` (360×800, Android's floor; reviewed for reflow and platform defaults). Helper: `app/test/shared/design_capture.dart`. Run that file only.
   The helper lays the screen out inside the phone's safe area (the frame's 47 px status row and home indicator), mounts a
   `tab:` screen in the production `RkShell`, and **fails the capture when any text is drawn outside Mukta / Mukta Mahee / Noto
   Sans / Material Icons** — that text is a solid box in the PNG. Fix the style (or the theme, through its owner), never work
   around it; only a face the screen asks of the phone on purpose (`'monospace'` in a raw-file preview) goes in `platformFaces:`.
2. **Pair:** `python3 scripts/design_match.py pair <S-id> [variant design ids]` → open `build/design_match/pairs/<S-id>.png`.
3. **Fix what differs**, then capture and pair again. In the Android capture, fix anything clipped, overlapping or unreadable;
   differences that are only Android's platform defaults are fine. Differences at default size (390×844, EN, light) are defects unless a
   🔒 line, 07 §1 / 13 §8 accessibility, or an open `⚠️ SPEC:` requires them.
4. **Record** `design/match/<S-id>.json`, then `python3 scripts/design_match.py stamp <S-id>`:
   `{ "sid", "verdict": "match"|"deviates"|"no-canvas", "frames": [canvas-index keys], "captures": ["<S-id>__<state>"],
      "screen_files": [every file that draws it], "deviations": [{ "what", "reason", "authority" }],
      "approved_by_owner": false, "checked_on": "YYYY-MM-DD" }`
   Frame keys come from `design/match/canvas-index.json`: name **every** frame the index holds for your S-id (each needs a
   capture) plus any variant frames you matched, and never another screen's frame. `no-canvas` is only for an S-id the index
   has no frame for, and adds `"nearest": "<the drawn pattern you followed>"`. A deviation without a reason and an authority
   fails the gate; so does any of these rules (`stamp` warns first).
5. Never set `golden: true` yourself — that follows the owner's approval of the pair (ADR 2026-10-05 §3).

## Return (to /lane)
Write `.claude/lane-reports/<milestone>-<key>.json` as soon as you have anything to record and
keep it current (you have a turn cap) — `complete: false` until the task is wholly finished. Then
return the same object:
files · tests (ids) · open (any 🔒 line you would have needed to change, any design gap: cite
canvas + S-id) · notes — including each S-id's design-match verdict and the pair image path.
