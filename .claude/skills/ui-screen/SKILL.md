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

## Build
- Files: `app/lib/features/<feature>/<screen>_screen.dart` (+ `widgets/`), `app/lib/features/<feature>/routes.dart` exporting `List<RouteBase> routes`. Nothing outside your folder except your ARB part.
- **Strings:** `app/lib/l10n/parts/<feature>_en.arb`, `_pa.arb`, `_hi.arb` — dotted keys `screen.element.state`; PA/HI are real translations, or a faithful draft marked `"@key": {"description": "machine-draft — native review M12"}`. Forbidden jargon (01 §1.3): no *debit/credit* on consumer screens — *Money in / Money out*; professional surfaces (statement, exports) say Dr/Cr.
- **Tokens only:** colours, spacing, radii, type from `tokens.dart`. A hex literal is review-blocking (`check_purity`). Colour never alone — pair with icon or text (07 §1).
- **States** for every screen: loading (ruled skeleton, 11 §4.5), empty, error, offline (S19.3 is non-blocking), read-only (S12.5 pattern), and the role variants of 13 §2.3.1 that apply.
- **Data:** through `data`/`core_ledger` APIs only — never re-implement posting logic, never touch money as double. Sync/auth through the `SyncClient`/`AuthClient` interfaces with the in-memory fakes.
- Entry-flow screens: the 8-second budget — keypad first, defaults prefilled, no dead ends; `Semantics` labels for amount-plus-direction.
- Accessibility: 200 % font scale without overflow at 375×667 and 360×800; focus visible; `lang` on user-typed strings.

## Test (F1, every push)
`app/test/features/<feature>/<screen>_test.dart`; names start with the id (`F1-07-<n>` — next free number from `dart run scripts/check_coverage.dart`). Per screen: renders each state; strings resolve in EN/PA/HI (`Localizations` pumped per locale, no overflow at 200 %); primary action reaches the engine (fake) with integer paise; for S2: tap sequence completes in ≤ 8 steps.

## Return (to /lane)
Write `.claude/lane-reports/<milestone>-<key>.json` as soon as you have anything to record and
keep it current (you have a turn cap) — `complete: false` until the task is wholly finished. Then
return the same object:
files · tests (ids) · open (any 🔒 line you would have needed to change, any design gap: cite
canvas + S-id) · notes.
