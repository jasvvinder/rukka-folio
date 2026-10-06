# ADR 2026-10-05 — The canvas defines how a screen looks; every UI slice is design-matched

On 5 Oct 2026 the owner checked the demo and found that **no screen matched the design**. The cause
was in the tooling, not in any requirement. The screen recipe (`.claude/skills/ui-screen`), the UI
lane prompts and `lane-review` named only `tokens.json`, `design-system.md`, 07 and 13, never the
drawn canvases (`design/canvas-mirror/partials/`, ~300 frames at 390×844). CLAUDE.md § Precedence
ranked `design-system.md` and `DESIGN-PACK.md` but not the canvases, and `design-system.md:3` sent
*screen behaviour* to 07 and *layout* nowhere. So lanes built each layout from prose, F1 tests checked
states and strings, review checked the docs, and nothing ever looked at a screen. Evidence on the day:
S1 Home draws its four verbs as wrapping outlined buttons inside the scroll
(`home_cards.dart:526-590`), where canvas 2 row 1 and 13 §10 decision 3 both dock them above the tab
bar. The app also uses Material Icons in 601 places, while the canvases draw stroke icons. Owner ruled
5 Oct 2026: *"In the workflow, a step should be added to verify, match and test the developed UI of
the screen against the available design of the screen on the canvas"*, then *"start phase 0: write
the ADR and add the design-match step"*.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The canvas is the authority on how a screen looks 🔒 ⟦tests: n/a — precedence rule, enforced by ruling 4's check and ruling 5's review⟧
- For any screen with a canvas frame, the frame defines **layout, component choice, hierarchy,
  placement, iconography and density**. The S-id ↔ design-id translation is 13 §3.3.
- The numbered specs keep **behaviour, states, copy rules, roles and accessibility** (07, 13).
  `design/tokens/tokens.json` keeps **values**: a canvas size that is not a token maps to its
  typography role (design-system §H4) and never becomes a literal.
- Two things a frame cannot override. First, **07 §1 and 13 §8 accessibility**: 200 % text, 360×800
  and the +40 % script budget may reflow a canvas layout, but only at the sizes that need it, and the
  default 390×844 English render still matches. Second, **any 🔒 line**: where a frame and a 🔒 line
  disagree, the lane stops and leaves a `⚠️ SPEC:` comment. It does not pick one (CLAUDE.md § Precedence).
- When a frame and a non-🔒 spec line disagree on *appearance*, the frame wins. When they disagree on
  *behaviour*, the spec wins. When it is unclear which one a difference is, that is a `⚠️ SPEC:` desk item.
- CLAUDE.md § Precedence item 2 now names the canvases. `design-system.md:3` and 13 §9 carry the
  cross-reference.

### 2. Every UI slice ends with a design match 🔒 ⟦tests: F1-1005-1, F1-1005-2, F1-1005-3, F1-1005-4⟧
The lane that builds or changes a screen runs this before it reports `complete: true`:
1. **Render the canvas:** `python3 scripts/design_match.py render <S-id>…` renders that S-id's frames
   (and its entity/role/state variants named in 13 §3.3) to `build/design_match/canvas/` at 390×844, 2×.
2. **Capture the app:** a design test in `app/test/features/<feature>/` (`<screen>_design_test.dart`, inside the feature lane's own folder) calls `rkDesignCapture`
   (`app/test/shared/design_capture.dart`). It pumps the screen at 390×844 with the real Mukta,
   Mukta Mahee, Noto Sans and icon fonts, inside the phone's safe area (the frame's 47 px status row and
   home indicator), and writes `app/build/design_match/app/<S-id>__<state>.png`. A tab screen is mounted
   in the production `RkShell`. Text drawn in any other family **fails the capture**, because it is a solid
   box in the PNG: a pair is only readable when the capture draws the screen's real faces.
   At minimum it captures the default English light state. Every canvas variant of the screen
   (empty, error, role and entity frames) gets a capture of its own.
   **Every state is captured twice** (owner, 5 Oct 2026: *"are we checking for Android too?"*):
   - `RkDesignTarget.ios` at 390×844 is the render **matched against the frame**.
   - `RkDesignTarget.android` at 360×800, Android's floor (13 §10 decision 9), is **reviewed** for
     reflow and Android's platform defaults (title alignment, scroll physics, back affordance). It is
     not expected to match the 390-wide frame pixel for pixel, but anything broken, clipped or
     unreadable there is a defect.
   - The platform is always set explicitly, because a Flutter test runs as Android unless told
     otherwise (`foundation/_platform_io.dart`, `FLUTTER_TEST`).
3. **Compare:** `python3 scripts/design_match.py pair <S-id>` lays each canvas frame beside its
   capture in one image. The lane opens it and fixes what differs.
4. **Record:** the lane writes `design/match/<S-id>.json` with the verdict (`match` or `deviates`)
   and every remaining difference, each with its reason and authority (a 🔒 line, 07 §1, or an open
   `⚠️ SPEC:`). `python3 scripts/design_match.py stamp <S-id>` then fills in the hashes of the
   screen files and the canvas frames, which ruling 4 uses to detect stale records.
- A difference with no recorded reason is a defect, not a choice.
- The record names **every** frame the index holds for the S-id, plus any variant frames matched, and
  no other screen's frame (repair, 5 Oct 2026: the gate checked only that a named key existed).
- **No canvas:** the record says `no-canvas` and names the nearest drawn pattern followed (`"nearest"`);
  the gate refuses `no-canvas` for an S-id the index has frames for. The screen
  becomes an owner/design desk item, so it gets drawn rather than staying undrawn forever.

### 3. An approved capture becomes a golden, checked on macOS only 🔒 ⟦tests: F1-1005-5⟧
- Once a screen's record says `match` and the owner has seen the pair, the design test asserts
  `matchesGoldenFile('goldens/<S-id>__<state>.png')`, so later drift fails the test.
- Flutter rasterises text differently on macOS and Linux, and CI runs on `ubuntu-latest`. Golden
  assertions therefore **run on macOS only**. Elsewhere they skip with a printed reason, and the
  capture still runs. The local `scripts/ci.sh` on the owner's Mac is the place goldens are enforced.
- Flutter and Chrome will never produce identical pixels. The canvas↔app comparison is a reviewed
  visual match (ruling 2), and the golden locks the approved *app* render. Nobody asserts pixel
  equality with the canvas.

### 4. The gate knows which screens have a canvas and which records are stale 🔒 ⟦tests: F1-1005-1⟧
- `design/match/canvas-index.json` (committed; written by `design_match.py index`) maps every S-id
  to its frame ids and a hash of each frame's HTML. The mirror itself stays git-ignored (owner, 1 Sep
  2026). The index carries ids, captions and hashes, never frame content.
- `scripts/check_design_match.dart` reports, for every `app/lib/features/**/s*_screen.dart` (plus
  the inventory rows in 13 §3.2 the index names):
  - **missing**: has a canvas but no record;
  - **stale**: the screen files' hash or the frames' hash no longer matches the record, or the index
    holds a frame of the S-id the record does not name;
  - **unexplained**: a `deviates` record with a difference that has no reason;
  - **invalid**: a malformed record (reported, never a crash of the warn-only step), a frame of another
    S-id, or `no-canvas` where the canvas has drawn the screen.
- The inventory rows are read from the 13 §3.2 table, so a screen built as a sheet or widget (S2.1,
  S12.5, S15.1 …) is reported and its record validated like any `s*_screen.dart`.
- It is **warn-only** until the owner closes the re-skin (phase 3 of the 5 Oct plan), then runs
  with `--strict` in `ci.sh`. Flipping it is an owner call recorded in PLAN.md, like
  `check_coverage`'s M4 flip.

### 5. Review looks at the screen 🔒 ⟦tests: n/a — review-process rule; the review lane is a prompt, not code⟧
- `lane-review` gains a `design` category, checked right after test honesty for any slice that
  touches `app/lib/features`. It opens the pair images from ruling 2 and the record. A visible
  difference the record does not explain is a **major** finding. A record that claims `match` where
  the pair shows otherwise is a **major** test-honesty finding.
- The verify lens *authority* treats the canvas frame as a citable authority (frame file + caption),
  the same as a spec section.

## Consequences
- **Device check:** two Android emulators exist for looking at the real app (`scripts/run_dev.sh
  emulator-5554`): `rf_phone` (Medium Phone, 411×914) and `rf_min` (360×800, the floor). The
  iPhone simulator remains `run_dev.sh` with no argument. A capture is a picture of the widget tree;
  the emulator and simulator are where the status bar, keyboard, gestures and system fonts are seen.
- **Code:**
  - `scripts/design_match.py` (index · render · pair · stamp; needs local Chrome and the mirror)
  - `scripts/check_design_match.dart` + `test/scripts/check_design_match_test.dart` (F1-1005-1)
  - `app/test/shared/design_capture.dart` + `app/test/shared/design_capture_test.dart` (F1-1005-2 … F1-1005-5;
    the harness captures a probe under `HARNESS`, never a real S-id)
  - `design/match/` (index and records)
  - `ci.sh` gets a warn-only step
- **Prompts:** `.claude/skills/ui-screen/SKILL.md` (new *Design match* step), `.claude/agents/lane-ui.md`,
  `lane-ui-hard.md`, `lane-review.md`, `.claude/workflows/cycle.js` (`design` category, review and
  authority-lens wording), `.claude/skills/cycle/SKILL.md`.
- **Docs:** CLAUDE.md § Precedence (owner-locked, changed at the owner's direction today) · `design-system.md:3` · 13 §9 handoff
  checklist · 13 §3.3.
- **No test is superseded.** Nothing green asserted a layout. The existing screens are simply
  unmatched, which the warn-only gate reports without failing.
- **Milestone:** M13 tooling now. The re-skin is phases 1–4 of the 5 Oct plan: full audit → shared
  components → screens → undrawn screens.

## Open ⚠️
- ✅ **Icon set, ruled by the owner 6 Oct 2026:** icons and all app assets come from the design. The canvas SVG icons (Lucide geometry, ISC notice on S18.4) are extracted into an app icon set over `svg_path.dart`, with no new package. Illustrations use the canvas wireframes until commissioned artwork exists.
- ⚠️ **Budget (owner):** the re-skin is ~8–9 cycles, ~55–75 M tokens. A cycle costs ~7–10 M against
  a 1.2 M daily ceiling, so it needs `budget.daily_overrides` entries.
- ⚠️ **Freeze (owner):** pause new screen slices until the phase-2 shared components land. Otherwise
  new screens are built on components that are about to be replaced.
- ⚠️ **Goldens in CI (owner, cost):** enforcing ruling 3 in GitHub CI needs a macOS runner, which
  bills at 10× the Linux rate (very-low-budget rule). Until then, goldens are enforced by the local gate.
- ⚠️ **Theme gap before the UI match phase (desk 141):** `theme.dart:81` gives the app-bar title
  `text.titleLarge` with no family, so every screen with an `AppBar` title fails its capture (probe on
  5 Oct: S1's only unfaced text is "Home"). That theme fix is the dependency to land first.
- ⚠️ **Nine screens have no canvas** (S0, S7.0, S11.9, S12, S15.4, S18.1, S18.2, S18.4, S19.5, by the
  5 Oct coverage pass). They need drawing on the design side.
