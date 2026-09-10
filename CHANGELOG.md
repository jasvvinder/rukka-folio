# Changelog — Rukka Folio

Running record of what changed in this repository and in the development environment, one entry per working session. Newest first. Kept by hand at the end of every session, before the owner commits; the commit hash is filled in afterwards.

**How to write an entry**

- Heading: `## YYYY-MM-DD — <milestone or slice>` (use `env` for toolchain/environment work, `docs` for spec-only sessions).
- Sections, each optional: **Added**, **Changed**, **Decided** (link the ADR in `docs/decisions/`), **Open** (⚠️ items handed to the owner), **Commits** (hashes once committed).
- Record *what* and *why*, not the diff — git holds the diff. One line per item.
- A 🔒 change is never recorded here alone; it needs an ADR in the same commit.
- No financial data, keys or secrets — this file is committed.

---

## 2026-09-10 — M5: U2c completes — S2 keypad-first entry green, gate green (supersedes the capped entry below)

The `lane-ui-hard` re-run finished U2c (run 2, 19:31 report), and this session ran `/gate push` as its own
invocation. Green: the only thing to fix was `dart format` on the seven new `features/entry` files
(whitespace). No behavioural failure, so no fix lane and no ADR. All seven M5 lane reports are now
`complete: true`.

**Added — U2c, S2 · S2.1 · S2.3 now green (`F1-07-17`, `F1-07-54`, `F1-07-55`, `F1-07-56`)**
- `app/test/features/entry/` 19/19 green in ~3 s; app package 202/202. `entryScreen` wired into
  `main.dart` as `entryRoot`, so the shell's centre ( + ) opens the real S2 instead of the placeholder.
- Doc markers placed now that the ids are seen green: `@M5` dropped from `F1-07-17` in 07 §5 and 01 §2.1;
  `⟦tests: F1-07-56⟧` on ADR 2026-09-03b ruling 1; `⟦tests: F1-07-17⟧` on ADR 2026-09-05f §C.

**Changed — two real defects fixed in the re-run (no 🔒 behaviour changed)**
- `entry_account_picker.dart`: `_ClassQuestion` overflowed its 78 pt region by 62 px — it now scrolls
  inside the picker; the entry screen itself still never scrolls (07 §5 🔒).
- `s2_add_entry_screen.dart` + `entry_slot_field.dart`: chrome tightens at `textScale ≥ 1.5` (row padding
  s2→s1, slot-field padding s1→0) to absorb the 35 px overflow on *Move money* at 375×667 / 200 %.
- Test harness only: a `_settleIo` helper — a ledger write started from a tap is real sqlite I/O and
  `pumpAndSettle` only turns the fake clock, which is what hung the Undo test to the 10-minute timeout
  (the U2a finding again, in a second shape).

**Open**
- ⛔ **Owner call:** 07 §5 🔒 "never scrolls" and 200 % text scale genuinely collide on *Move money* at
  375×667 — the keypad is left ~30 px, present and correct but unusable. Conservative reading is in the
  code (no-scroll stands, chrome tightens). Either the transfer verb shows one chip row at a time at large
  scale, or the lower region gets a floor and 07 §5 gains a large-text exception (design canvas 2, S2/S2.3).
  ⚠️ SPEC in `s2_add_entry_screen.dart`.
- ⬜ Still unbuilt in Lane U2: S2.2 date, S2.5 drawings confirmation, the ≤ 8 s stopwatch test; plus U2b's
  two seams (scope does not persist per tab; rebuild progress has no producer in `packages/data`).
- PA/HI entry strings are lane drafts, not native-reviewed — M12 pass.
- Budget unchanged: fable runs this week 5 / 2 budgeted — no `lane-core` without the owner.

**Commits**
- _(pending)_

---

## 2026-09-10 — M5: U2c S2 keypad-first entry — lane capped part-way, 15/19 green, re-run needed

One `lane-ui-hard` run (`/lane` with no key; U2c chosen from PLAN as the next unbuilt piece of the Phase A
exit "solo entries flow end to end offline"). The lane wrote the whole screen and hit its 90-turn cap while
re-running its own tests. No gate this session; the route is not yet wired into `main.dart`.

**Added — U2c, S2 · S2.1 in place · S2.3 within one book (`F1-07-17`, `F1-07-54`, `F1-07-55`, `F1-07-56`) — ⬜ not yet green**
- `features/entry`: keypad with `+` quick-sum and `.` paise, five-position verb pill (Move money fifth,
  ADR 2026-09-03b), slots labelled per the 07 §5 verb table, chip row of the three most-used money A/Cs
  + More (absent when no money A/C is involved), live preview line with reserved height, in-place picker
  in the lower region with inline create (class inferred from slot), Save → `LocalLedger` verbs, zeroed
  keypad stays, Undo as an append-only reversal. `entry_routes.dart` exports the builder for `RkPaths.entry`.
- `entry_{en,pa,hi}.arb` parts (PA/HI lane drafts, not native-reviewed). Date chip is static; note/photo/
  channel, S2.2, S2.5, over-limit snackbar, inter-book transfer and book-full are `// U2d:` attach points.
- 19 tests in `s2_add_entry_screen_test.dart`; 15 green, 4 red after the cap (200 % EN/PA/HI, Undo
  reversal, chip row absent, ambiguous-slot two-chip question). Wall time 10:02 points at one test hanging
  to the per-test timeout — the U2a fake-async pattern. Details in `.claude/lane-reports/M5-U2c.json`.

**Open**
- ⚠️ Re-run `/lane U2c` in a fresh session; the report's `notes` carry the four failing names and the
  hit-test warning to fix first. Then wire `entryRoutes`/builder into `main.dart`, then `/gate`.
- ⚠️ `@M5` on `F1-07-17` (07 §5, 01 §2.1) and the ADR 03b / 05f §C markers are still to be placed —
  only once the ids are seen green.
- Budget: fable runs this week 5 / 2 budgeted — no `lane-core` without the owner.

**Commits**
- _(pending)_

---

## 2026-09-10 — M5: U2b lands the Home scope switcher and rebuilding state (S1.2, S1.3, S1.4); gate green

One `lane-ui-hard` run in its own session, then this gate in its own invocation. The push lane is green
with nothing mechanical to fix. Verified against the log, not the summary: exit 0, `check_coverage --strict`
clean, root scripts 21, pure packages 75 + 155 + 31 + 17 + 10, app 183, Deno 31 passed / 7 ignored; the two
landed test files re-run by name (32/32) so every id below is seen green, not inferred.

**Added — U2b, S1.2 · S1.3 · Everything · S1.4 (`F1-07-52`, `F1-07-53`, `F1-07-38`)**
- S1.2 two-chip inline toggle for one business; S1.3 grouped bottom sheet from three books, empty groups
  omitted, never shown at exactly two (07 §2 🔒); *Everything* renders read-only book cards.
- S1.4 determinate rebuild loader — "{done} of {total} entries restored" on a 2 px rule, no spinner anywhere
  (07 §28 🔒, 11 §4.5 🔒); the return to the normal Home card is gated on `BookHealth.integrityOk`.
- Wired into S1's app bar. The Home body is passed as a `WidgetBuilder` because `watchHome`'s combined
  stream is single-subscription — returning from S1.4 must build a fresh one. New stream combinators cancel
  synchronously (unawaited), applying U2a's teardown-deadlock finding.
- 10 tests in `s1_scope_switcher_test.dart`, EN/PA/HI at 200%; `test/features/home` 30/30; `F1-07-49/50`
  unchanged and green. 14 new `home.*` keys in EN/PA/HI (335 × 3 now); PA/HI are lane drafts, not
  native-reviewed (01 §1.8).
- Traceability: 07 §28's `F1-07-38` marker lost its `@M5`; the S1.2/S1.3 🔒 line in 07 §2 carries
  `F1-07-52`, `F1-07-53`.

**Changed**
- `PLAN.md` §0 and M5: U2b ✅; the app row names all six gated lanes (183 tests); two new ⬜ rows for the
  seams below.

**Open**
- ⚠️ SPEC / seam — **scope does not persist per tab.** 13 §2.2 says "scope persists per tab, defaults to
  last used"; that is shell state and `HomeScopeController` lives only for the screen. `HomeScreen`
  already takes `scopeController:` — the shell (`app/lib/shared/`, outside the lane) needs to own one
  per tab or persist the `Scope` value.
- **S1.4 has no real producer.** `Recompute.run` (`packages/data/lib/src/recompute.dart:112`) exposes no
  progress. S1.4 consumes `RebuildProgressSource` fed by a fake in `F1-07-38`; `homeRoot` passes
  `rebuildProgress: null`, so behaviour is unchanged for users until `packages/data` grows a per-book
  progress stream and the shell feeds it.
- Gate note, unchanged from U1c: the 7 RLS hostile-query tests reported *ignored* because `RF_TEST_DB_URL`
  was not set in the gate agent's shell. Push permits it; nightly/rc set `RLS_REQUIRE=1`.
- Fable spend stands at 5 / 2 for the week; nothing in this session touched it.

**Commits**
- (fill next session)

---

## 2026-09-10 — M5: U1c lands the business branch of onboarding (S0.6a, S0.6a1, S0.6b); gate green

One `lane-ui-hard` run, then the gate in its own invocation. The push lane is green with nothing mechanical
to fix — the first M5 gate that found no drift at all.

**Added — U1c, S0.6a · S0.6a1 · S0.6b (`F1-07-51`, `F1-07-45`, `F1-13-15`, `F1-09c-1`)**
- S0.6a business name; S0.6a1 owners with share weights and steppers (ADR 2026-09-09 §1–3) — percentages
  are integer arithmetic on the weights and are displayed only, never typed; S0.6b grouped opening balances
  (ADR 2026-09-09c §3, 09d) taking its rows from the caller as `List<OpeningRow>`, so the screen tests
  without a database. Money is integer paise throughout: `parseRupeesToPaise` is string arithmetic.
- 22 tests in `s0_6_business_screens_test.dart`, all asserted at 200% on 360×800 in EN/PA/HI; the
  onboarding directory is at 41 tests and the app package at 173.
- `createBook` (`app/lib/shared/ledger/local_ledger.dart`) seeds the shared-business branch: *Profit
  Distributed* plus one `{Name} — Partner Current A/c` per owner. Just-me still seeds Opening Balance /
  Capital + Drawings; no bank, as ADR 09d §1 requires.
- 50 new `onboarding.*` keys in EN/PA/HI (321 × 3 now). PA/HI are lane drafts, not native-reviewed (01 §1.8).
- Routes: *Just me* goes S0.4 → S0.6b directly; the business purposes go S0.6a → S0.6a1 → S0.6b.
- Traceability: 13 §3.2's S0.6a row gained `F1-07-51`; the `@M5` planned markers came off `F1-07-45`,
  `F1-13-15` and `F1-09c-1` in 13, 07 and the two ADRs. `check_coverage --strict` clean.
- Tiering note: this lane was correctly on `lane-ui-hard` — owner rows with weight steppers and a
  grouped balancing screen are new components, not repeats of a settled pattern. It finished under the
  ADR 2026-09-10 cap in one run.

**Changed**
- `PLAN.md` §0 and M5: U1c ✅; five new ⬜ rows carrying the lane's open findings (below); the app row now
  names all five gated lanes.

**Open**
- ⚠️ SPEC (`local_ledger.dart:700`) — **the S0.6a1 share weights have nowhere to persist.** `BookConfig`
  (`packages/data/lib/src/payload_codec.dart:100`) carries `ownership` but no partner ratio, and
  `PartnerShare` takes its weight per call (`core_ledger/lib/src/verbs.dart:432`). ADR 2026-09-09 §2 makes
  the weights load-bearing (02 §7.1 divides by them), so they need a field in the `book_config` envelope.
  That is a `packages/data` schema change the lane did not own; S0.6a1 hands the weights up in
  `OwnerDraft.shares` and nothing stores them. Owner call on where they live.
- ⚠️ SPEC (`onboarding_routes.dart:73`) — the book is not created in the routes: S0.6b mounts with
  `rows: const []` and S0.6a1 with `yourName: ''`, because the committing step (07 §3.1 step 8 / S0.7) has
  no screen yet and S0.4's name is still not carried forward (U1b's gap, unchanged). U1f owns the wiring.
- `A-09c-1` is unwritten: the shared-business seed added to `createBook` is untested (its test lives in
  `app/test/shared/ledger`, outside the lane), and `createBook` still seeds none of ADR 2026-09-09c §1's
  `Business Cash A/c`, `Sales A/c` or the shop/trade tree.
- Design app: S0.6a1 (ADR 2026-09-09, Canvas 1 branch segment) and the five S0.6b variants
  (`partials/new-screens-d.json`) are not placed yet — these screens were built from ADR text, not artboards.
- Gate note: the RLS suite (`E-03-22…27`) reported *ignored* — `RF_TEST_DB_URL` was not set in the gate
  agent's shell. The push lane permits that; nightly/rc set `RLS_REQUIRE=1`. Run `eval "$(scripts/rls_db.sh)"`
  first if the next gate should exercise it.

**Commits**
- (fill next session)

## 2026-09-10 — M5: three UI lanes land (S0.3/S0.4, S1/S1.1), and the push lane goes green

Three `lane-ui` runs against disjoint feature folders, then the gate. Home stops being a tab placeholder,
onboarding reaches the name-and-photo step, and `ci.sh` is green on the push lane with every M5 screen id
in it. Two reds on the way, both mechanical, both fixed here — one of them pre-existing on `main`.

**Added — U1b, onboarding S0.3 + S0.4 (`F1-07-16`, `F1-07-48`)**
- S0.3 purpose cards: the five cards 2x2 with the trust card full width beneath (07 §3.1.1's layout
  ruling); the trust card alone sets `tenant.type = organization`.
- S0.4 name & photo: Continue **disabled-with-reason** until a name is typed (13 §4.3), and the photo goes
  through a callback seam rather than a plugin, so the screen tests without a platform channel.
- Both assert EN/PA/HI at 200% text scale on 360x800 with no overflow. 19/19 in `test/features/onboarding`.

**Added — U2a, Home S1 + S1.1 (`F1-07-49`, `F1-07-50`)**
- `features/home`: position hero, cards and states, plus the drill-down behind any position row.
  `homeRoot` wired into `main.dart` mirroring `ledgerTabRoot`, so Home is no longer the tab placeholder;
  shell tests 10/10. `F1-07-49` 8/8, `F1-07-50` 12 cases.
- **Why the lane died twice before landing**, recorded because the symptom lies: `_combine`'s `onCancel`
  in `home_data.dart` was async and awaited each Drift subscription's cancel, so widget **disposal**
  awaited a future that only completes on a real event-loop turn — never delivered inside `flutter_test`'s
  fake-async zone. Teardown deadlocked for the full 10-minute timeout. It was not `pumpAndSettle` and not
  the screen: a bounded-pump probe rendered the hero correctly and still hung at unmount, and
  `flutter test --timeout` does **not** cut this deadlock short.

**Changed — the gate, two mechanical reds**
- **Strings (8 keys).** U1b's `onboarding.namePhoto.*` used camelCase segments, which `check_strings.dart`
  rejects — every other key in the repo is snake_case within a segment (`auth.otp.sent_to`). Renamed to
  `onboarding.name_photo.*`. **No Dart change was needed**: `gen_l10n_arb` folds snake to camel
  (`home.money_in.label` → `homeMoneyInLabel`), so the regenerated identifiers are byte-identical to the
  ones the screen already calls. 271 keys x 3 languages.
- **Coverage (1 line), pre-existing on `main` from `a36740c`.** `design/DESIGN-PACK.md:309` cites
  *01 §1 rule 4 🔒* and was followed by a semicolon; `check_coverage.dart:53` reads 🔒 + punctuation as a
  ruling but 🔒 + lowercase as a citation, so the identical citation on line 306 (`02 §4 🔒 asks money`)
  passed and this one did not. Fixed **without changing a word of the prose** — the wrap point moved so
  the clause ends its line, and the line now carries `⟦tests: F3-01-1 @M12⟧`, the marker rule 4 itself
  carries in `01-glossary.md:12`. It names the cited rule's test rather than inventing one.
- Traceability warnings cleared, both this phase's debt: `13-ux-architecture.md:291` dropped the stale
  `@M5` on the landed `F1-07-16`, and `07 §4. Home 🔒` now names `F1-07-49, F1-07-50` so U2a's tests are no
  longer orphans (the precedent U3a set for §6). `check_coverage --strict`: 0 unmarked, 0 warnings.
- `dart format` reformatted `home_data.dart` and `home_cards.dart` (done by the gate agent).

**Decided**
- **ADR 2026-09-10 — lane turn caps** (`docs/decisions/2026-09-10-lane-turn-caps.md`): every tier's cap
  roughly doubled, and `.claude/agents/*.md` + `.claude/skills/lane/SKILL.md` updated to match. U2a is the
  evidence — it died twice on a verification toll and a slow test, not on over-scoping, then finished in
  22 tool uses once the cap rose and file inventories left the lane prompt. **Splitting stays the first
  answer** for a lane with too many screens; a cap is a backstop, not a ceiling to design around. If a lane
  dies at its cap, read the transcript before raising it again.

**Open**
- ⚠️ `design/DESIGN-PACK.md:309` is a 🔒 line — the marker above wants owner ratification. The alternative
  was rewording the citation into the mention form line 306 uses, which would have edited the owner's prose.
- ⚠️ SPEC (U3a, in-file, still open): S3.1 ships 7 quick-add tiles not 8 — Capital/Drawings is structural
  per 02 §7.1, an owner call. S4 has no FY switcher (07 §6, 13 §7): `watchStatement()` takes no date range,
  so it needs a data-seam change in U3b.
- S1.1's bank drill-down app-bar title falls back to `home.position.title` ("Position") —
  `positionLineLabel()` has no per-account label for `PositionLine.bank`. Asserted as-built; a design nit.
- `buildRouter`'s `initialLocation` still points at the shell, not `OnboardingPaths.splash` — first-launch
  routing remains an owner decision (carried from U1a).

**Commits**
- (fill next session)

## 2026-09-10 — M5: the book start date built end to end; design synced both ways

The owner reopened Capital/Drawings, was left confused by a day of fragment-by-fragment iteration, and
asked for the flow to be fixed as one coherent model. This entry is that model landing: an immutable
**book start date**, opening balances dated there, nothing dated before it — built, tested, gated — plus
the design project pushed and pulled so canvas 1 and the repo agree.

**Built 10 Sep — the book start date, end to end (ADR 2026-09-09d §4)**
- `BookConfig.startDate` → `books_p.start_date` (schema **v2**, `m.addColumn` forward migration, Drift
  regenerated) → `createBook` stamps `startDate ?? today()` → `openingBalances` dates at the start by
  default → `post()` refuses `ViolationKind.beforeBookStart`. **Stamp is at creation, not first opening
  balance**: the lazy version had a hole (skip balances, post for a week, record one on day 8 — the floor
  would land after live entries). `A-09d-3`–`A-09d-6` + `E-09d-1`; `F1-02-2` unchanged; fixture books
  now begin a week before "today" so their back-dated history stays legal. **45/45** ledger tests, **31/31**
  data tests.
- The one `core_ledger` touch is the enum value `beforeBookStart`, authoring-only like `futureDate`;
  `A-09d-6` proves no reader invariant emits it — that is the difference between a rule and a security
  event fired at a family member for using the app offline.
- Deferred: `E-09d-2`, the v1→v2 migration fixture test (needs drift's schema-dump tooling).

**Changed**
- **ADR 2026-09-09d §4 re-cut, §4a/§4b added.** Stamp at **creation**, not first opening balance (the lazy
  stamp had a hole); the floor is an **authoring guard, never a §1.4 invariant** — as an invariant, the
  zero-knowledge rule would raise a family member as a security event for recording a sale while offline;
  a pre-start entry that does arrive by sync is an **Inbox review flag**, never quarantined. Owner-ruled
  boundary: *"the date on which the first time user recorded the o/b during account setup or ledger book
  setup"* — a stored property of the book, not a figure derived from the entry stream, so every device
  agrees on the floor the moment it holds the book.
- **The five opening-balance artboards, final:** every figure blank on first run; a plain read-only
  *Balances as on <today>* line (no box, no picker); seed is cash only in every journey — **no bank is
  seeded anywhere**, the trust included (ADR 09d §1–2 amended 07 §3.1 🔒); no "Made for you" group. Pushed
  to the design project as `partials/new-screens-d.json`.
- **Design pulled** (`/design-pull`): canvas 1 rebuilt by the app agent with `S0.6a1` (state pair), the five
  `S0.6` variants replacing the three-step O6a–c wizard, and S9.5 on canvas 4 stripped of its seeded bank
  row; dictionaries untouched (1497 keys each). All copy/design-only and already ratified — no behavioural
  change awaited the owner. `design/DESIGN-PACK.md` O6 rewritten to the grouped single screen.

**Decided** 🔒 — see ADR 2026-09-09d §4/§4a/§4b above (owner-ruled 9–10 Sep). *"It should not be before the
opening balance, never."*

**Open**
- ⚠️ `E-09d-2`, the v1→v2 in-place migration fixture test, deferred (needs drift's schema-dump tooling).
- ⚠️ The refusal copy for a pre-start date needs writing in EN/PA/HI — it may not offer *"change your
  starting date"*; the date is immutable.
- ⚠️ *"Partner Current A/c"* and *"Capital"* are not in the master dictionaries; the shop footer's
  markup-split *Capital* is fixed at source in `new-screens-d.json` but **not yet re-pushed**.
- ⚠️ Not re-pulled this sync: canvases 2–3, 5–16 and `partials/src/*` (the project's own records name no
  work on them since 3 Sep); `src/core.json` remains over the 256 KiB cap.
- The Drawings **verb** (ADR 09b §3) is still `lane-core`; fable is over budget until Sunday.

**Commits**
- `b33a5e3` — M5: book start date end to end (ADR 2026-09-09d §4) + Drawings seeding + 4 ADRs
- `a36740c` — design-sync: O6 brief follows canvas 1 — grouped opening-balances screen, S0.6a1 placed, S9.5 loses its seeded bank
- _(pending — this CHANGELOG entry)_

---

## 2026-09-09 — M5 lane U3a closed: ledger index, quick add, A/C statement

`U3a` had been `complete: false` for three runs. Run four went up a tier to `lane-ui-hard` (opus) and
cleared the blocker; the owner then called out that a lane should land green **and gated** in one
go, so the remainder — under the ~30-minute lane threshold — was finished inline rather than by
spawning a fifth lane. **`./scripts/ci.sh` is green on the push lane.**

**Added**
- `F1-07-44` — the S4 A/C statement widget test (7 cases): professional Dr/Cr vocabulary with the
  consumer *Money in / Money out* asserted absent (02 §10 🔒), b/f and c/f rows, the counter account
  as particulars, empty · loading · error states (13 §4.3), and EN/PA/HI at 200% on 360×800.
- `F1-07-43` — the S3.1 quick-add sheet test (5 cases).
- A sticky alphabet rail on S3 (07 §6): the list is now a `CustomScrollView` of `SliverMainAxisGroup`
  + a pinned `SliverPersistentHeader` per letter, asserted both structurally and by scrolling.
- **19/19 green** in `app/test/features/ledger`.

**Changed**
- `flutter test test/features/ledger` finishes at all: it was killed at 600s before this session.
  Two real defects behind it — S3.1's action `Row` put a `FilledButton` under unbounded width against
  the theme's `Size.fromHeight(48)`, so every frame threw *BoxConstraints forces an infinite width*
  and `pumpAndSettle` ground through ten simulated minutes of error frames (actions are now stacked
  full-width); and the test awaited a drift stream's `.first` inside the fake-async zone, whose
  zero-duration timer never fires (now read through `tester.runAsync`).
- **S4 carried the same `initState` defect S3 had**, found by `F1-07-44`: it read
  `LedgerScope.of(context)` from `initState`, which throws, and the caught throw pinned every case to
  the error state. Moved to `didChangeDependencies` behind a `_resolveStarted` guard, with a
  `_retry()` that clears the error.
- S4 at 200% on 360×800: the Dr | Cr | Balance columns were hard-coded 72/72/84 px and could not fit
  beside the particulars. They are now scaled by `MediaQuery.textScalerOf`, the line folds so the
  figures take a row of their own when they would need more than two-thirds of the width, and the
  b/f and c/f rows stack past 1.3×.
- 07 §6 marker line now reads `⟦tests: F1-02-9, F1-02-10, F1-07-42, F1-07-43, F1-07-44⟧`
  (marker append on a 🔒 heading; no behaviour of §6 changed).
- `dart format` over the tree, which the gate requires — it also touched `scripts/check_coverage.dart`,
  unformatted before this session and unrelated to this lane.

**Decided** 🔒 — [ADR 2026-09-09](docs/decisions/2026-09-09-shared-ownership-and-fy-switcher.md).
- **S0.6a1 "Who owns this business?"** is a screen — the *Shared with others* branch of S0.6a had no
  designed surface at all (canvas 4 drew the chip pair and stopped), so a shared business could not be
  created. Owner ruled: owners are **invited by phone at setup**, reusing the S0.6e row unchanged.
- **Shares are whole-number weights, not percentages.** 02 §7.1 divides by weight, so three equal owners
  cannot be written in percent — 33/33/34 is a real 1% difference on every distribution. The percentage
  is computed and shown, never typed, which removes the "must add to 100" state entirely.
- **S0.6a1 is not skippable**, unlike every other S0.6 branch step: the ratio is fixed at creation. Its
  secondary returns to *Just me* rather than being a dead end (07 §1 rule 6).
- **The FY switcher is one control on three surfaces** (S4 · S8.2 · S10.4), absent until the first year
  close, with b/f computed until S10.4 certifies it in M9.

- **A book gets an immutable start date, and nothing may be dated before it** — ADR 2026-09-09d §4/§4a/§4b,
  owner-ruled: *"It should not be before the opening balance, never"*, with the boundary being *"the date on
  which the first time user recorded the o/b"*. Refused, not warned. The opening figure is **counted**, so
  anything earlier is already inside it — and the ledger being append-only means a bad back-dated entry can
  only be reversed, never removed, so the door is the one cheap point of control. Re-running setup (`02 §4`
  🔒, re-runnable until first lock) corrects the **amounts**, never the date.
  - Stamped once on `book_config`, not derived from the entry stream, so every device agrees on the floor
    the moment it has the book.
  - 🔒 **An authoring guard, never a §1.4 invariant.** `02`'s zero-knowledge rule quarantines an
    invariant-violating envelope and raises a security event — so as an invariant this would accuse a family
    member of an attack for recording a sale while their phone was offline. Only `post()` refuses; no reading
    client rejects or hides.
  - A pre-start entry that does arrive by sync raises an **Inbox review flag** (`02 §3`), offering the two
    real repairs — correct the opening balance, or reverse the entry. Never quarantined.
- **No book seeds a bank account** — [ADR 2026-09-09d](docs/decisions/2026-09-09d-no-seeded-bank-account.md).
  Owner-ruled: a bank is added, not seeded, in every book type — the trust included, which amends the 🔒 seed
  list in `07 §3.1` (everything else on that line, including the gollak rules and mandatory denomination
  counting, is untouched). The argument is `02 §4` 🔒's own: *"Every new account asks for its opening balance
  at creation — not only during first-run setup"*, so adding a bank later costs one tap and asks for its
  balance in the same breath. Seeding it costs more: `local_ledger.dart:982` skips zero balances, so a bank
  left blank posts nothing and just sits there under a name the user never chose.
- **The chart of accounts is seeded from the setup answers** — [ADR 2026-09-09c](docs/decisions/2026-09-09c-seeded-chart-and-opening-balances.md).
  Seeding was already implied by 02, 07 §5.7 and 07 §3.1; this settles the whole seed per book type and
  turns S0.6b from the three-step O6 wizard into **one grouped review-and-fill**. No party accounts are
  ever seeded (02 §1.2 🔒 — one party, one account, sign decides), banks are seeded unnamed, and
  Due-to/from accounts appear as books are created rather than being typed. §4 fixes the arithmetic:
  opening balances must balance, `Opening Balance / Capital` absorbs the difference and the screen says
  so out loud, and a shared business's owner contributions are **asked, never derived from the sharing
  ratio** (02 §7.1 🔒 keeps the two apart).
- **Sub-family shares are books, not accounts.** `joint-family-sharma.md` is four books joined by
  Due-to/from pairs; putting sub-family shares inside one book is the conflation 02 §7.1 warns
  "corrupts the partnership arithmetic".
- **Capital/Drawings is real** — [ADR 2026-09-09b](docs/decisions/2026-09-09b-capital-drawings-pair.md).
  02 §7.1 always said a *Just me* business book gets a Capital/Drawings pair; nothing created one.
  `SystemRole.drawings` turned out to already exist and be referenced **nowhere**, there was no `capital`
  role at all, and `openingBalance` was documented as being Capital too. Owner ruled: make it real, seeded
  by `createBook` for business books. A shared business gets Partner Current accounts *instead of* the pair
  (02 §7.1 calls them "the single place that relationship lives"). Owner takeout posts
  `Dr Drawings · Cr money` and is never an expense, which makes S2.5 buildable. Not implemented this
  session — it is core_ledger work against a 🔒 line, and fable is 5/2 over budget.

**Design**
- Five journey variants of the seeded opening-balances screen pushed as `partials/new-screens-d.json`
  (personal · business Just-me · business Shared · family pool · trust). Two owner corrections shaped
  them: business books say the accounting words outright — `01 §1` rule 4 🔒 requires it, so the Just-me
  variant groups by *Sundry debtors / Sundry creditors* and names `Capital A/c` and `Drawings A/c` —
  and there is now **one** *Add an account* per screen opening S3.1's type grid, rather than a
  per-group add that pre-decided the class. That matches the ratified S9.5 artboard, which already
  worked that way.
- Three artboards drafted and pushed to the Claude Design project as `partials/new-screens-c.json`
  (S0.6a1 in both states, and the FY switcher). Written to a **new** staging file on purpose:
  `canvas12-screens.json` is 247 KB and the additions would breach the 256 KiB cap, and the mirror had
  not re-pulled since 3 Sep so overwriting an existing file risked clobbering remote work. Placement into
  Canvas 12 and the rebuild remain to be done in the design app; PA/HI copy joins the existing
  `TRANSLATION-PENDING.md` backlog for the S0.6 branches.
- S4's ⚠️ SPEC comment about the missing FY switcher is resolved into a TODO pointing at ADR §4.

**Decided** 🔒 — CLAUDE.md rule 11, *never assume, never guess* (owner-directed).
Verify before asserting, and attach the evidence to the claim. Written against three failures from this
session rather than as a maxim: *"the engine has no Drawings account"* (it had been declared and unused
since day one), *"I can't do that from here"* (node, the build script and a write API were all present),
and an ADR ruling that split Capital from Opening Balance without opening `docs/reference/`, where both
worked examples name the single account `Opening Balance / Capital A/c`. Extends, and does not replace,
the existing stop-and-ask rules in § Accounting authority and § Workflow.

**Also landed**
- **The Drawings seeding is built and green** — `BookOwnership { justMe, shared }` on `BookConfig`
  (`packages/data`), threaded through `LocalLedger.createBook`, which now seeds `Drawings A/c` for a
  *Just me* business book and for nothing else. `A-09b-1`–`A-09b-3`, four tests, plus `F1-02-2` updated:
  a business book legitimately has **two** system accounts now, so its `.single` assertion became a
  two-element expectation rather than being skipped — the behaviour it guards (system accounts first, in
  creation order) is unchanged. 22/22 green in `local_ledger_test.dart`. Old books carry no `ownership`
  on the wire and read back as `justMe` (rule 6, unknown-field round-trip).
- **Category trees drafted** — `docs/reference/seed-category-trees.md`, EN only, every name lifted
  verbatim from the worked examples. **Finding: there are four trees, not three.** `01 §1.8` and `02` say
  household/shop/trust, but the examples carry a distinct farm vocabulary (Seed & Fertiliser, Diesel &
  Machinery, Cattle Feed, Crop Sale, Milk Sale) that no shop tree covers, and `07 §5.7` already hedges
  with *"the shop or trade category tree"*. ਪੰਜਾਬੀ/हिन्दी columns are deliberately blank — `01 §1.8` puts
  them behind native review, not translation.
- The remaining `lane-core` item is now only the **Drawings verb** (ADR 2026-09-09b §3); the seeding
  needed no escalation.

**Open**
- ⚠️ **Owner call:** 07 §6 bullet 3 is 🔒 and lists eight quick-add tiles including Capital; S3.1 ships
  seven, because 02 §7.1 makes the Capital/Drawings pair structural and created at business setup, and
  no `AccountClass` models an ad-hoc capital account. Matching §6 needs either a doc change or invented
  engine semantics. ⚠️ SPEC comment stays in `s3_1_quick_add_sheet.dart` until ruled.
- ⚠️ S4 has no FY switcher or period tabs (07 §6, 13 §7): `watchStatement()` takes no date range, so
  this needs a data-seam change in a later lane. ⚠️ SPEC comment in the screen.
- ⚠️ Process, for the owner: four runs died on this one lane. Only run 1 was over-scoping. Run 4 spent
  roughly a quarter of its 40 turns discovering that `timeout` does not exist on macOS and working out
  how to run a hanging test — a repo gap, not a model gap. Worth one line in CLAUDE.md § Commands
  (`flutter test --timeout 30s`), and worth separating *diagnosis* lanes from *build* lanes, since a
  bug hunt cannot be sized against a turn cap in advance.

**Commits**
- _(pending — the owner commits)_

---

## 2026-09-08 (third session) — M5 lanes U1a + U3a, and the model-tier ruling

Ran `/lane U1a U3` as the orchestrator. U1a landed; U3 died at its turn cap for the third time this
week, which prompted the owner to revisit the tier table — and the week's own telemetry to be read
before changing it.

**Added**
- S0.05 Welcome (3 skippable slides, dot progress, live-region slide announcement, Skip always
  present) — `app/lib/features/onboarding/screens/s0_05_welcome_screen.dart`.
- `F1-07-39/40/41` (S0.0 splash · S0.1 language · S0.05 welcome), 11 tests green with
  `router_test.dart`; the three ids attached to the 🔒 marker on 07 §3.1, which they were orphaned from.
- `onboarding_routes.dart`, composed into `main.dart` `featureRoutes` by the orchestrator (lanes may
  not touch `shared/router.dart`).
- `.claude/agents/lane-ui-hard.md` — the opus UI tier (ADR 2026-09-08b §2).

**Changed**
- `lane-server` → opus; `lane-mech` explicitly barred from authoring tests; tier tables in
  CLAUDE.md § Session economy and `.claude/skills/lane/SKILL.md` §1.4 restated to match the agent
  frontmatter, which is the only real source.
- U1a fixed three pre-existing defects its tests exposed on `main`: a missing `shared/theme.dart`
  import left `RkStatusColors` undefined in **both** S0.0 and S0.1 (a live compile error), and a
  200% text-scale overflow in the language screen's `Column`+`Spacer` layout.
- `onboarding_routes.dart` now uses `AuthPaths.phoneOtp` rather than a retyped `/auth/phone`.

**Decided** 🔒 — [ADR 2026-09-08b](docs/decisions/2026-09-08b-model-tiers.md). The owner proposed
dropping sonnet from development entirely (Opus for UI + business logic, fable for complex logic).
Adopted in a narrower form after the telemetry was checked: of seven runs since 6 Sep, three did not
complete and **none** failed on model quality — all three were over-scoped against `maxTurns`, while
sonnet at correct scope (U1a) completed *and* found three real defects. So: Opus at the pipeline ends
and on the hard cases (`lane-server`, new `lane-ui-hard`, orchestration/integration, which was
already opus), sonnet for settled-pattern screens, **never haiku on a test** (the owner's own clause —
in this repo the test is the specification), and *tier up, never cap up*. Fable's remit unchanged:
`lane-core` stays escalation-only at 2 runs/week.

**Open** ⚠️
- **U3a is incomplete and `features/ledger` does not compile.** Two screens survived on disk
  (`s3_1_quick_add_sheet.dart`, `s4_account_statement_screen.dart`), untested, with 64 analyze errors
  in three classes: ~31 undefined l10n getters (no `ledger_*.arb` exists), `StatementRow`
  `ambiguous_import` (exported by both `core_ledger` and `shared/ledger/local_ledger.dart`), and the
  same missing `shared/theme.dart` import U1a hit. `F1-07-42/43/44` all still owed. Report written by
  the orchestrator, since the lane died before writing one: `.claude/lane-reports/M5-U3a.json`.
- **`flutter analyze` gave a false green.** Bare from `app/`: `No issues found! (ran in 0.2s)`.
  Scoped to the directory: 64 errors on the same tree. If `scripts/ci.sh` shells out to the bare
  form, the gate can pass over non-compiling code — a gate-integrity defect, unfixed.
- Fable spend stands at **5 runs against 2 budgeted** for the week to 8 Sep.
- `initialLocation` was deliberately **not** pointed at the splash for a fresh install: U1a suggested
  it, but first-launch routing is a behavioural decision for the owner, not an integration step.

**Commits** — pending.

---

## 2026-09-08 (second session) — M4 exit gates: the RLS suite finally runs, traceability goes blocking, M5 started

Picked up the three ⛔ items standing in `PLAN.md` §0. Two are now closed; the third (the M5 app lanes) is
begun and explicitly unfinished. Along the way the session found one real privilege bug, four defects in
the traceability checker and two in the lane harness — every one of them a tool that was reporting success
over work it was not actually checking.

**Added**
- `scripts/rls_db.sh` — builds the RLS database from a local Postgres and exports `RF_TEST_DB_URL`.
  **Docker was never the requirement**: the migrations are plain Postgres + `pgcrypto`, no `auth.`/`storage.`
  /Supabase extensions, so a Homebrew `postgresql@16` serves. `eval "$(scripts/rls_db.sh)"` resets the
  database, applies all five migrations and prints the URL. This closes ⛔ item 1, open since M4 began.
- `docs/decisions/2026-09-08-planned-test-markers.md` — 🔒 ADR adding a **third marker form**, ` @M<n>`.
  05i §1 allowed only real ids or `n/a — reason`, and neither fits the ~90 🔒 lines whose behaviour is real
  but whose milestone is unbuilt: an intended id fails the dangling-id check, and `n/a` is both false and
  *terminal* — nothing would ever force those lines to gain real ids. A planned marker instead **expires**:
  `--milestone M<n>` fails any ` @M<k>` with `k ≤ n` that still has no test. Verified both ways (fails at
  M4, passes at M3). ADR 2026-09-06 §7 was already writing `F1-06a-1 (M11)` illegally; it is now legal.

**Changed**
- `server/supabase/migrations/0005_rls_and_grants.sql` — **security fix.** `:296` revoked
  `bump_store_epoch` from `rf_api` but omitted the sibling revoke for `purge_ephemeral_auth`, which the
  blanket `grant execute on all functions in schema rf to rf_api` then handed over. It is `SECURITY
  DEFINER`, so `rf_api` could bypass RLS to delete `refresh_tokens`, `auth_nonces`, `otp_challenges`,
  `activation_tickets` and revoked `wrapped_keys`. Found by `E-03-26` on the suite's **first ever run** —
  exactly the class of bug the 7 Sep entry warned was unevidenced. Restores what 03 §2.5 already says; no
  🔒 rule changed, so no ADR.
- `server/supabase/tests/rls/schema.test.ts` — `E-03-20` claimed to assert "maintenance-only powers are
  revoked from rf_api" but its `||` accepted the `from public` revoke, which does **not** take back an
  explicit later grant. That is why a static test sat green over the hole above. Tightened to require the
  `rf_api` revoke by name; confirmed it fails when the migration fix is reverted.
- `scripts/check_coverage.dart` — **four defects, all of them false assurance**: (a) object-form
  `Deno.test({name:…})` unmatched, so the entire RLS suite read as declaring no ids and its markers looked
  dangling; (b) root `test/` absent from `_testRoots` (and from the path filter), hiding 15 green `F1-10-*`
  tests; (c) an `n/a` marker on a heading blanketed its whole section — an `n/a` on `## Rulings 🔒` would
  have excused every ruling beneath it; (d) 🔒 *mentions* (`🔒/ADR`, `🔒→test ids`, a line-wrapped "on 🔒
  / lines") counted as rulings. Fixing these alone took discovered tests 373 → 395. Also teaches it the
  ` @M<n>` form and skips fenced code blocks so a doc documenting marker syntax is not parsed as using it.
- `scripts/ci.sh` — coverage step flipped to `--strict --milestone M4` (05i §1 phased it to block at M4;
  it now passes). Server step documents the no-Docker path and sets `RLS_REQUIRE=1` on nightly/rc/release
  so an absent database **fails loudly instead of skipping in silence**.
- `.claude/workflows/lanes.js` — **`/lane` has been broken since `bfc3714`.** Unescaped backticks inside a
  template literal meant the script never parsed; every earlier run used the older `milestone-lanes`
  workflow, so the restructured harness had never actually been exercised. Second bug on the failure path:
  `settled.filter(r => r.dead)` threw `TypeError` because `parallel` yields `null` for a schema-failed
  agent — losing *which* lanes to re-run, defeating durable reports precisely when needed. Both fixed.
- `docs/` + `design/` — every 🔒 line now carries a marker: **0 unmarked** (was 185), 0 dangling, 0
  malformed, 0 orphan tests, 0 tests without an id. 83 lines carry planned ` @M<n>` markers. Malformed
  `E-03-16b`/`E-05-1b` renamed to `E-03-28`/`E-05-13` (tests and markers together). 14 ADR `## Rulings 🔒`
  container headings marked `n/a` now that an `n/a` heading no longer launders its section.
- `PLAN.md` — `server/` ⬜→✅ M4 (Deno 31 → **38**, RLS included); Traceability ⚠️→✅; `app/` records the
  partial M5 work; the M5 section carries the lane-sizing warning below.

**Verified**
- RLS hostile-query suite **7/7 green** against a real Postgres (`E-03-22…28`, `E-05c-7`); full server
  Deno suite **38 passed**, lint clean. Nightly-without-a-database fails loudly, as intended.
- `check_coverage --strict --milestone M4` → `coverage ok`, zero findings and zero warnings (from 198).
- `flutter analyze --fatal-infos` clean; `gen_l10n_arb` + `check_strings` green (169 keys × 3 languages);
  no hex literals in the new app code.
- ⚠️ **`ci.sh` was not run end to end this session** — the gate is a separate invocation (`/gate`) and the
  M5 tree is mid-lane. The individual steps above were run directly.

**Decided** — ADR 2026-09-08 (planned-test markers) 🔒. Nothing else 🔒: the `purge_ephemeral_auth` revoke
and the checker fixes restore what the specs already said rather than changing a rule.

**Open** ⚠️
- ⛔ **M5 is ~10 lanes, not 3.** U1/U2/U3 were given 10–16 screens each against `lane-ui`'s 40-turn cap;
  all three capped mid-read — **418K tokens for one screen, an EN-only ARB and empty directories**. A
  re-scoped 3-screen lane (U1a) still capped at 55 tool uses. Budget **2–3 screens per lane**. My
  over-scoping, not the harness's fault; the harness bugs above merely hid the outcome.
- **U1a incomplete**: S0.0 splash and S0.1 language built; **S0.05 welcome missing, no F1 tests written**
  (F1-07-39/40/41 owed), and `onboarding_routes.dart` was never created so nothing is wired into
  `router.dart`. **U3 incomplete**: S3 ledger index only, no test. Both reports are on disk and current.
- The lanes wrote **no tests at all** — both capped before the tests-first step could produce anything.
  The next lane on these features must write the owed F1 ids before adding screens.
- Postgres now runs locally as a Homebrew service; `RF_TEST_DB_URL` is not persisted anywhere — each
  session runs `eval "$(scripts/rls_db.sh)"`. CI still has no database; the RLS suite skips on any runner
  that does not set one, which is why the push lane stays silent about RLS.
- Unchanged from the last session: hardening gates still absent from `ci.sh` (gitleaks, OSV, `print(`);
  SPKI rotation runbook still missing; goldens still PROVISIONAL (no `approved_on`).

**Commits** — pending; see the handover blocks.

## 2026-09-08 — M4 + M6: stage 2a closed out — server, sync_engine and the auth/devices client gated and recorded

The four stage-2a lanes (S server · Y sync_engine · C auth+devices client · U0 ledger facade) landed their files in the session that died on its limit (`wf_16e00993`), and their lane reports died with it. So ~40 files of security-critical work sat on disk **never analyzed, never tested, never PLAN-marked, and named in no changelog entry** — the 7 Sep entry says outright that its files are not in it. This session did no new feature work: it gated that tree, fixed what the gate found, and wrote down what is actually true about it.

**Changed**
- `packages/sync_engine/test/engine_crypto_test.dart`, `test/wire_test.dart` — dropped a stale `userId:` argument from two `WireDeviceCert(...)` call sites. This was the gate's only hard blocker (`analyze`, exit 3). The field belongs on `WireDevice`, not the cert row, and three independent sources agree: `device_certs` has no `user_id` column (migration `0002:19–21`, it lives on `devices`), `sync-meta/index.ts:234` carries an explicit `⚠️ WIRE:` note saying user_id comes from the devices row in the same response, and `guard.dart:110` takes `buildCert(WireDeviceCert, WireDevice)` precisely so it can read it from there. Both tests already construct the paired `WireDevice` carrying `userId`, so no coverage was lost. Tests only — no production code, no assertion changed.
- `app/lib/main.dart`, `app/lib/shared/router.dart` — `dart format` (the gate's first failure).
- `docs/` — `⟦tests: …⟧` markers on the 🔒 lines stage 2a now covers, across `02`, `03`, `04`, `05`, `06`, `07`, `09` and ADRs `05b`, `05c`, `05d`, `05i`, `2026-09-06`: 35 lines gain a marker, 15 have theirs extended (ADR 2026-09-05i §1). Marker-only — every added line carries a marker and no specification prose changed, so no ADR is implicated. Committed separately as `b08abc6` to keep the 🔒-line diff readable.
- `PLAN.md` — §0 redated and rewritten against the tree rather than the intent: `sync_engine` ⬜ stub → 🟡 M4, `server/` ⬜ absent → 🟡 M4, `app/` ⬜ shell → 🟡 M6 client. P0 → ✅ (all six items). M4/M6 rows marked per green id. Phase A row: P0/S/Y/C done, U1–U3 remaining.

**Verified** — `LANE=push ./scripts/ci.sh` green (exit 0), reaching the end for the first time over this tree. 393 Dart tests + 31 Deno, 0 failures: root `test/` 21 · `core_crypto` 75 · `core_ledger` 155 · `data` 30 · **`sync_engine` 17** · **`testing/harness` 10** · **`app` 85** · server Deno 31. Confirmed from the log that every stage-2a file actually ran (`ci.sh:55` iterates `packages/*` wholesale, so the new `engine_plain`/`engine_crypto`/`wire`/`engine_two_device` files were all in scope) — the ids now evidenced are `D-05-1…13`, `D-05b-1`, `D-06a-1…4`, `D-10-1`, `C-06-1…13`, `C-05d-1…10`, `F1-06-1…16`, `E-03-15…21`, `E-05-1…12`, `E-06-1…8`.

**Decided** — nothing 🔒; no ADR. The `WireDeviceCert` fix restores code to what the specs and the server schema already said, rather than changing a rule.

**Open** ⚠️
- ⛔ **The RLS hostile-query suite has never executed.** `server/supabase/tests/rls/rls.test.ts` (7 tests, `E-03-22`…`E-05c-7`) skips for want of `RF_TEST_DB_URL`: Docker is absent on this machine, so `supabase db reset` cannot apply the migrations. `ci.sh:62` defers it to the nightly lane by design, so **the push lane going green is not evidence about RLS** — the policies in `0005_rls_and_grants.sql` are written and unverified. This is M4's exit gate and the first thing the owner should unblock; it is why `server/` is 🟡 and not ✅. (Static reading is reassuring — `envelopes` is `grant select, insert` to `rf_api` with `DELETE` to `rf_maintenance` alone, satisfying rule 2; `phone_ct`/`phone_hmac` with no plaintext number — but reading is not testing.)
- **Traceability debt, new PLAN row, blocks M4 exit** (`check_coverage --strict` turns blocking at M4, ADR 2026-09-05i §1): 319 🔒 lines with **185 unmarked**; 44 orphan test ids named by no `⟦tests⟧` marker; 11 markers naming ids no test declares (`E-03-25/26/27`, `E-05c-7`, `F1-06a-1`); 2 malformed ids (`E-05-1b`, `E-03-16b` — the `Nb` suffix is not the `A-02-9` shape); 2 tests with no id (`tests/rls/schema.test.ts:215`, `_tests/sync_push.test.ts:97`). Stage 2a widened this considerably. It spans three lanes' territory and is a docs+naming pass, so it is tracked as its own item rather than folded into a build lane.
- Hardening still absent from `ci.sh`: gitleaks, OSV, the `print(` check (ADR 2026-09-05). SPKI pins landed; the rotation runbook did not.
- Process note: both gate agents hit their 20-turn cap — the first before reporting anything. The cap is right, but a gate over a never-tested tree needs two runs (fix, then verify), so budgeting one `/gate` invocation per *run* rather than per *phase* is the cheaper shape when the tree is cold.

**Commits** — `b08abc6` (docs markers), `f45a940` (stage-2a code: server, sync_engine, auth/devices client; 148 files, push lane green).

## 2026-09-08 — env: build harness restructured around lane tiers, durable reports and short sessions

Phase A's first week spent 2.69M tokens across five `/fanout` runs, all of them on Fable 5.1, and two died mid-run — `wf_16e00993` on the session limit with three `effort: high` lanes in flight (725K tokens, 15 min), leaving two lanes' files on disk and their reports lost, so the phase could not be marked. Cause: lane args carried `effort` but never `model`, so every lane fell through to the workflow default (`claude-fable-5-1`), and lanes + gate were one atomic unit that had to survive half an hour. No code behaviour changed in this session.

**Added**
- `.claude/agents/` — six lane tiers, each pinning **model and effort in frontmatter** so a forgotten arg can no longer choose the model: `lane-mech` (haiku · low), `lane-ui` (sonnet · medium), `lane-server` (sonnet · medium), `lane-sync` (opus · medium), `lane-core` (**fable · high, escalation only**), `gate` (sonnet · low, `Bash`/`Read`/`Edit` only). The repo rules that were re-sent per lane inside the workflow script now live once per tier in these bodies, with each tier carrying the rules it can actually violate.
- `.claude/workflows/lanes.js` — runs 1–3 lanes in parallel **by `agentType`** and then stops. Caps the run at 3 and refuses more; refuses a lane missing `key`/`agent`/`dirs`/`prompt`; reports `ok: false` plus `incomplete: [keys]` when a lane dies instead of silently dropping it; surfaces `escalate: [keys]` for lanes whose `open` items mention 🔒, an ADR, a golden or a STOP.
- `.claude/workflows/gate-run.js` — the gate as its own invocation, so a limit hit costs one lane and not a phase.
- **Durable lane reports.** A lane's last action writes `.claude/lane-reports/<milestone>-<key>.json` (git-ignored); `/lane` skips lanes already reported there. `resumeFromRunId` is same-session only and so useless when the limit takes the session — disk is not.
- `.claude/bin/wf-spend.sh` — token spend per run and per week from the persisted workflow run state, grouped by model, with the fable budget (2 runs/week) and any non-completed run called out. Run at session start, before spending more.
- Skills `lane` (budget check → PLAN rows → skip-if-reported → disjointness → **tier choice** → run → integrate → stop) and `close` (`/plan` → `/changelog` → commit message → ask for `/clear`).
- Hook `stop_clear_hint.sh` (Stop) — after a session in which a build workflow actually ran and the changelog was written, prints the week's spend and asks for `/clear`.

**Changed**
- `CLAUDE.md` § Session economy — rewritten and marked 🔒: `/lane` replaces `/fanout`, the gate is a separate invocation, the tier table is normative, no lane starts on `lane-core`, reports are durable, every session ends with `/close` and a clear. Layout gains a `/.claude` row; Commands gains the build and budget commands.
- `PLAN.md` §1 principle and §3 (all twelve items) — a phase is built one lane at a time, not one phase at a time; tiers are structural; the failure that prompted it is recorded inline so the reasoning survives.
- Skills `gate` (now delegates to the `gate-run` workflow and pipes `ci.sh` to a file to grep, so the CI log never enters the orchestrator's context; routes each remaining failure to a tier, one round), `ui-screen` / `server` / `sync-slice` (**Return** sections now name the report path and, for `sync-slice`, make a `core_*` behaviour change an escalation trigger rather than lane work).
- `.gitignore` — `!/.claude/agents/`, `!/.claude/workflows/`, `!/.claude/bin/`. `milestone-lanes.js`, the script that ran the entire build, was untracked; `lane-reports/` stays ignored.
- `~/.claude/settings.json` (not in the repo; backup alongside) — `model: opus` (was `opus[1m]`: a premium tier above 200K, and the headroom invited context growth), opus `effortLevel: medium` (was `high` on every turn, against our own rule that `high` is for `core_*` only), `env.CLAUDE_CODE_SUBAGENT_MODEL=sonnet` (the default that Fable was standing in for; agent files still win), `skipWorkflowUsageWarning` removed.
- Removed: skill `fanout`, workflow `milestone-lanes.js`.

**Decided** — nothing 🔒 in `docs/`. The CLAUDE.md § Session economy rules are owner-directed process, marked 🔒 with `⟦tests: n/a⟧`; the fable budget of **2 escalation runs per week** is the owner's number and can be changed without an ADR.

**Open** ⚠️
- ~~`effort:` frontmatter unverified~~ **Closed 8 Sep** against the subagent docs: `effort` is a documented field (`low`/`medium`/`high`/`xhigh`/`max`, "overrides the session effort level"), as is `model: fable`. All six definitions are valid as written; the `lanes.js` fallback is not needed. (`/agents` is not the way to check — the wizard was removed in v2.1.263.)
- Expected effect to confirm against `wf-spend.sh` over the next runs: peak per run **150–250K** instead of 700K–1M, and fable at zero unless escalated.

**Follow-on, same day** (after `bfc3714`)
- Agent frontmatter gains `maxTurns` (15 mech · 40 ui/server · 50 sync · 60 core · 20 gate) — a capped lane returns **partial and resumable** instead of running until the session limit does it for us; `skills:` preloads each lane's own skill (`ui-screen`, `server`, `sync-slice`) so a lane no longer spends a turn reading it; `disallowedTools: ["WebSearch", "WebFetch"]` on the four unrestricted lanes, since every spec is local.
- Consequence, and the reason the report shape changed: a turn cap makes a **partial report the normal outcome**, so reports are now written early and kept current rather than as a last action, and carry **`complete: bool`**. `/lane` skips only complete reports and re-runs the rest with their own `notes` fed back; `lanes.js` counts `complete: false` as incomplete alongside a dead lane, and `LANE_SCHEMA` requires the field. Without it, skip-if-reported would have silently dropped the unfinished half of a capped lane.
- `.claude/bin/lane-status.sh` — which lanes have landed and which are only part-way, with each report's `notes`. Replaces an inline glob in `/lane` that **errored under zsh on an empty `lane-reports/`**, i.e. failed precisely at the start of a fresh phase.
- `permissionMode: acceptEdits` on the four build lanes (owner-approved) — a lane no longer stalls on an edit prompt part-way through a run, which was another way a run failed to finish. The trade is recorded because it matters: that prompt was the only mechanism actually enforcing the disjoint-directory split, so all four bodies now carry the boundary themselves ("check the path before every write; an edit outside your directories is a build break, not a merge conflict"), and `/lane` step 3 is marked load-bearing. `lane-mech` and `gate` keep default permissions.
- Verified every field against the subagent frontmatter docs: all six definitions valid, `effort` and `model: fable` included.
- `stop_changelog.sh` fixed — it blocked this session twice after the owner committed mid-session. Three faults: it only looked at `git status`, so a **committed** entry read as a missing one; `awk '{print $2}'` mangled renames (`R old -> new` → `old`) and any path containing a space, now `cut -c4-`; and the message said "N file(s) changed this session" when N was the whole dirty tree, most of it predating the session. It now passes when `CHANGELOG.md` is dirty **or** the file contains an entry dated today, and says so accurately. Deliberately does *not* require today's entry to be the topmost one — enforcing entry order here would just be another way to block a session that did write its entry.

**Commits** — `bfc3714` (the restructure). The same-day follow-on above is a second commit, pending.

---

## 2026-09-07 — P0: tooling for parallel lanes (Phase A, stage 1) — gate green; stage 2a lanes running

First `/fanout` of Phase A. P0 ran as two disjoint lanes plus one gate (`LANE=push ./scripts/ci.sh` green, nothing to fix). Stage 2a (lanes S server · Y sync_engine · U0 app ledger facade · C auth/devices client) was launched at the end of this session and reports in the next one; its files are not in this entry.

**Added**
- ARB parts: lanes write `app/lib/l10n/parts/<feature>_{en,pa,hi}.arb`; `scripts/gen_l10n_arb.dart` now merges parts → `app_*.arb` (generated, `@@x-generated`, still committed) → identifier copies in `gen/`; fails naming the part file on duplicate keys, a language missing for a feature, or a malformed ARB. Logic in `scripts/src/arb_merge.dart`; `check_strings.dart` blames the part file. `app/lib/l10n/README.md` documents it.
- `scripts/check_contrast.dart` (+ `scripts/src/contrast.dart`): WCAG 2.1 for every colour token × four grounds (`bg`, `surface`, `sunk`, `danger-surface`) × both modes, role mapping documented at the top; 74 gated pairs, 0 failing, 3 waived as *pending ruling* (see Open). Wired into `ci.sh` after the generated-files step; root `test/scripts/` (F1-10-2 … F1-10-15) runs in a new `dart test test/` step; root pubspec gains `test`.
- App shell: `shared/theme.dart` (`rkTheme` light/dark from tokens only, `RkStatusColors` extension), `shared/router.dart` (go_router shell — Home · Ledger · ( + ) · Inbox · Menu per 13 §3.1; `RkPaths`, `RkTabRoot`, `buildRouter(featureRoutes:)`), `shared/widgets/rk_tab_bar.dart` (design-system §4.1 verbatim glyphs, 21×21, min-height 50, active/inactive styling), `shared/seams/{sync_client,auth_client,key_store}.dart` (sealed five-state `SyncStatus`; `AuthClient` OTP → ticket → session; `KeyStore` bytes-by-id with `KeyIds`; in-memory fakes for all three), `shared/app_scope.dart` (`RkScope`: db · sync · auth · keys · injected clock), `features/README.md` (the lane convention), `app/test/shared/test_app.dart` (`pumpRk`). Tests F1-13-1 … F1-13-14; F1-10-1 now boots the shell in EN/PA/HI. Dependencies: go_router, drift, path_provider.

**Changed**
- `main.dart` — `MaterialApp.router`, `RkScope` with fakes, file-backed `NativeDatabase` under app documents; **plain SQLite until lane C's Keychain-held SQLCipher key is wired** (`⚠️ SPEC` comment in the file). Must not ship past the dev loop.
- `scripts/ci.sh` — contrast step; root test step; `test/` added to format and analyze.

**Decided** — nothing 🔒.

**Open** ⚠️
- Owner ruling: light `text-muted` measures 4.46:1 on `sunk` and 4.36:1 on `danger-surface` (below AA 4.5 for captions). Not covered by any design-system §3/§3.1 ruling; waived as *pending ruling* in `scripts/src/contrast.dart` — darken the token or accept, then delete the waiver.
- Already ruled, hex pending: light `credit` on `sunk` = 4.30:1 (design-system §3.1 "darken one step"); waived until the token session lands the new value.
- Role-mapping judgement calls documented at the top of `check_contrast.dart` (`primary` as text, `accent` as UI, `locked` disabled-exempt, hairline/skeleton/scrim decorative, amounts never on `danger-surface`) — owner may confirm.
- `app_{en,pa,hi}.arb` are generated but committed; git-ignoring them is a one-line change if preferred.
- 07 §1.7 speaks of six status states (adds *rebuilding*); 05 §9 owns five and the sealed `SyncStatus` has five — rebuilding is Home's S1.4 state, not a sync state. Lane U2 is told so.

**Commits** — pending.

---

## 2026-09-07 — docs: ADR 2026-09-06 ratified; §4 lead-times kicked off

Owner ratified the Shamir / guardian-revocation ADR with its four recommended answers and asked for the external lead-times to start. Docs-only session; no code changed, no tests moved.

**Decided** 🔒 — [ADR 2026-09-06](docs/decisions/2026-09-06-shamir-and-guardian-revocation-records.md) status *proposed* → **accepted**, four checklist answers recorded: (1) in-house GF(256) Shamir, no package — yes; (2) share wire form + `reconstructVerified` against the pinned UMK public key — yes; (3) k counted `device_revocation` records, cut-off only moves earlier, re-split does not reset, **earliest-k** — yes; (4) guardian minimum: default 2-of-3, **2-of-2 only behind a typed confirmation**, never a dismissible warning. Applied the ADR's "on ratification" list: 04 §2 Shamir row rewritten (in-house; external one-file review before M14); 04 §7.3 setup says typed confirmation, step 4 verifies the re-derived public key; 04 §9.2 gains the k-records paragraph with both rules and the D-06a ids in its marker; 04 §11 items 1 and 3 closed; ADR 2026-09-05b Open 2 closed; 10 M3 row no longer flags §11.1. New reserved id **F1-06a-1** (S11.1, n = 2 Continue disabled until the phrase is typed; M11).

**Added**
- `docs/ops/lead-times.md` — kickoff sheet for the nine external items: steps, the spec each must satisfy, what comes back to the repo, and the local-machine state (Xcode 26.6; supabase/gh CLIs installed but not logged in; no provisioning profiles).
- `.env.example` — the variable names lane S, the OTP client and M13 will read; `.env` and `.env.*` were already git-ignored.

**Changed**
- `PLAN.md` §0 owner line (ADR ✅; lead-times are the only ⛔), §2 M3 row, §4 table gains **Status** and **First action** columns; the iOS bundle id cited is the one already in the Xcode project (`com.rukkafolio.rukkaFolio`).

**Open** ⚠️
- Owner: the nine §4 items — the Supabase project (Mumbai, Pro + PITR) and the Apple enrolment (D-U-N-S if Organization) are the long poles; TRAI DLT registration for OTP is 1–2 weeks.
- 03 §11 item 6 (KMS choice for the phone key) — lane S will default to Supabase Vault unless the owner says otherwise.
- `check_coverage` now lists D-06a-1…4 (M4) and F1-06a-1 (M11) as dangling ids by design; warn-only until M4.

**Commits** — pending.

---

## 2026-09-07 — env: build tracker, parallel-lane workflow, lane skills, session economy

Owner asked for the fastest path to completion with parallel agents and the smallest possible usage per session. Re-planned M4–M14 as four phases of disjoint lanes; every session now starts from one tracker file and runs milestone work through one saved workflow.

**Added**
- `PLAN.md` — the build tracker: §0 where we are (M0–M3 ✅ with evidence; app is a shell, server absent, sync_engine a stub), §1 four phases with dated lanes (A foundations 7–13 Sep · B people 14–20 · C import/exports/subscription 21–27 · D harden + pilot 28 Sep–4 Oct), §2 every milestone broken into modules with ✅/🟡/⬜/⛔, incl. **P0 tooling** that makes UI lanes conflict-free (ARB parts + merge, theme from tokens, router skeleton, feature folders, fake sync/auth seams, server skeleton), §3 session-economy rules, §4 external lead-times to start today.
- `.claude/workflows/milestone-lanes.js` — saved workflow: lanes in parallel (`parallel`, disjoint dirs, structured LANE_SCHEMA returns, per-lane effort/model), then one gate agent running `ci.sh` once and fixing only mechanical failures.
- Skills: `fanout` (prepare lanes from PLAN rows → run workflow → integrate → `/plan` `/changelog`), `ui-screen` (S-id screens: tokens only, ARB parts EN/PA/HI, 13 §4.3 states, F1 test per screen), `server` (migrations + RLS + functions + hostile-query tests; the 🔒 server rules in one page), `sync-slice` (sync_engine modules on the harness, suite D incl. D-06a-1…4), `plan` (refresh the tracker; ✅ only from a green gate).

**Changed**
- `CLAUDE.md` — Layout lists `PLAN.md`; new **Session economy** section (start from PLAN, sections not docs, fanout with lanes, right-sized effort, one gate, `/plan` then `/changelog`).

**Decided** — nothing 🔒. The tracker assumes every roadmap gate (pilot month, sign-offs, external review) stays; dropping any is an owner ADR.

**Open** ⚠️
- Owner: ratify ADR 2026-09-06; start the §4 lead-times (Supabase India project, Apple account, OTP provider, PA/HI reviewers, bookkeeper, crypto reviewer, pilot banks, gateway KYC).
- If the saved workflow is not found by name, `/fanout` falls back to `scriptPath` — verify on the first Phase A run.
- P0 tooling (ARB parts merge in `gen_l10n_arb.dart`, `check_strings` on merged files) must land before the first UI lane.

**Commits** — pending.

---

## 2026-09-06 — M3 follow-up: Shamir ADR reviewed — verified reconstruction, independent known-answer vector, ruling 3 sharpened

Evening pass over `docs/decisions/2026-09-06-shamir-and-guardian-revocation-records.md` at the owner's request ("what does it mean, any suggestions — do the best of your knowledge"). Three findings acted on, two owner decisions surfaced, and the ADR now ends in a four-line ratification checklist. Still **proposed**. `core_crypto`: 75 tests (+B-04-72, B-04-73), all green.

**Added**
- `GuardianShareSet.reconstructVerified(suite, shares, expected:)` + `GuardianShareMismatch` — reconstruct, re-derive both UMK public halves from the 64 bytes, compare (constant time) with the UMK public key the recovering device already holds; fail closed with the bytes zeroised. Closes the "tampered share yields a wrong secret silently" gap (B-04-57) **without a new field** — the BLAKE2b(UMK_priv)-beside-the-shares option is withdrawn (a digest travelling with the shares can be replaced with them; the pinned key cannot). B-04-72.
- `packages/core_crypto/test/vectors/shamir_ref.py` — a second, table-free GF(256) Shamir (Russian-peasant multiply, brute-force inverse) written without consulting `shamir.dart`; B-04-73 replays its 3-of-5 vector on the combine side (every subset, both orders) and, through a scripted RNG, reproduces the shares byte for byte on the split side. Every earlier test was self-consistent; this is the first cross-implementation check. A third-party vector (libgfshare / Vault) is still wanted before the external review.

**Changed**
- ADR 2026-09-06 §3 gains the two rules a counting scheme needs: (a) the cut-off is the k-th *smallest* `seq`, so it can only move **earlier** as approvals arrive — deterministic across devices, conservative, but it means re-quarantine on Recompute and the cut-off is never cached as final; (b) a **re-split does not reset the count** — the device under revocation is still certified and could otherwise bump `share_set_version` to discard k−1 approvals; records count against the version they name, carry across versions, threshold = k of the earliest counted version (⚠️ SPEC: proposer's choice). Counting set reworded from "current set" to "set at the version the record names".
- ADR §3 marker `n/a` → reserved ids **D-06a-1…4** with one-line tests (table in the ADR); `check_coverage` reports them dangling until M4 — intended (05i §1 warn-only until then).
- ADR §1/§2 markers gain B-04-73 / B-04-72; 04 §2 (ADR quote line) and §7.3 markers likewise. ADR consequences: M4 meta channel needs guardian-set *history* by `share_set_version`; 07 has no state for "2 of 3 approved" or a moved cut-off.

**Decided** — nothing 🔒 ratified; recommendation recorded for 04 §11.3: default 2-of-3, n = 2 allowed only behind a typed confirmation (2-of-2 has no loss tolerance *and* needs both guardians — but forbidding it excludes a two-person household).

**Open** ⚠️
- **Owner: the four-line ratification checklist at the end of the ADR** (rulings 1, 2, 3 incl. earliest-k vs current-k, and 04 §11.3).
- 07 owner: screen states for a pending k-of-n revocation and for a re-quarantine after the cut-off moved — before M11.
- External review of `shamir.dart` before M14, with a third-party KAT pasted in first.

**Commits** — pending.

---

## 2026-09-06 — M3: crypto core (suite B) — envelopes, key hierarchy, ceremony, signed records, trust chain, Shamir

First and only M3 slice. A shared skeleton (suite, bytes, key types, test helpers) was written first; three agents then filled disjoint modules in parallel — ceremony/wrapping/recovery · padding/envelope/certs/signed records/chain · Shamir — and the data package was wired to the new crypto boundary. One agent lost its session to a rate limit after its five library files; its three missing test files were written by hand. `core_crypto`: 73 tests (B-04-1…71 with gaps, B-05b-1…8, B-10-1). `data`: 30 tests (+E-04-1…3). Push gate green. **M3 exit reached** (10 M3 row: suite B) — tag after committing: `git tag m3-crypto-core`.

**Added — `packages/core_crypto`**
- **Foundation.** `sodium: ^4.1.0` (pure-Dart libsodium FFI; v4 builds libsodium 1.0.22 through Dart build hooks, so `dart test` needs no system library — the Homebrew libsodium installed today is unused). `CryptoSuite` is the single injection point (`Sodium` + `RandomBytes`; `blake2b256`, `randomBytes`, `randomSecureKey`, `constantTimeEquals`, `zeroize`); `suiteVersion = 0x01`. `Bytes`/`Uuid16` canonical encodings for everything that enters AAD or a signature (uuids as 16 bytes, u32/i64 big-endian, length-prefixed UTF-8). Test helpers: deterministic `testSuite(seed:)` (RNG = BLAKE2b(seed ‖ counter)), `verifiedUmk(...)` through the real ceremony, `MapTrustStore`.
- **Key types (04 §3).** `Fingerprint` = BLAKE2b-256(x25519 ‖ ed25519); `UmkPublic` (server-relayed, unverified) vs `VerifiedUmkPublic` (ceremony-only `@internal` constructor — 04 §8.2 is structural: a book key, guardian share or UMK can only be sealed to a verified type; `VerifiedDevicePublic` likewise for linking); `UmkKeyPair` (⚠️ SPEC: `UMK_priv` = 64 bytes `x25519_seed ‖ ed25519_seed`, pairs re-derived with `seedKeyPair`); `DevicePublic`/`DeviceKeyPair`; `BookKeyRef`/`BookKey`. Every holder has an idempotent `dispose()` and throws `StateError` on use after dispose — reading freed guarded memory segfaults the VM (found by B-04-70).
- **Ceremony (04 §6, §9.1).** `QrPayload` (`base64url(suite ‖ user_id ‖ UMK_pub_ed ‖ UMK_pub_x ‖ nonce)`), `verificationCode` (8 digits from BLAKE2b-256(FP ‖ nonce ‖ "verify-v1")), `Ceremony.verifyQr` (byte-for-byte, constant time; mismatch has no override), immutable `CodeChallenge.attempt(typed, nowMs)` (3 attempts per nonce, 10-minute lifetime, exhausted nonce dead even for the right code), `DeviceQrPayload` + `verifyDeviceQr` for linking.
- **Wrapping (04 §5, §7.5, §9.1).** Generic `sealToVerified`/`openSealed` (`crypto_box_seal`, typed `UnsealFailed`); `wrapBookKey`/`unwrapBookKey`; `wrapUmkToDevice`/`unwrapUmk`; `rotateBookKey` → v+1 wrapped to each remaining member, never the leaver; `sealPersonalBookKeyForHead` (BK only, never the UMK).
- **Recovery (04 §7.4).** `RecoveryKey`, `sealUmkUnderRecoveryKey`/`openUmkWithRecoveryKey` (XChaCha20-Poly1305 over the 64 secret bytes), sheet QR `base64url(version ‖ user_id ‖ RK)` and typed Crockford-Base32 fallback in groups of 4 with a 2-char checksum (⚠️ SPEC: first 10 bits of BLAKE2b-256(version ‖ user_id ‖ RK); decoder accepts O/I/L aliases and lowercase).
- **Padding (ADR 05b §8).** `padPlaintext`/`unpadPlaintext` via `sodium_pad`: 1 KiB buckets up to 16 KiB, then 4 KiB; the unpad block size is derived from the padded length (unambiguous: a 4 KiB result is ≥ 20,480). B-05b-8: 3-char and 900-char notes → identical ciphertext length; 1,025 → next bucket.
- **Envelope (04 §4).** `Envelope` + `EnvelopeBuilder.seal/reseal` + `Envelope.open`. Payload `{author_seq, object}` (ADR 05b §3) → UTF-8 → pad → XChaCha20-Poly1305 with AAD `uuid16(tenant) ‖ uuid16(book) ‖ uuid16(object) ‖ lenPrefixedUtf8(object_type) ‖ u32be(key_version) ‖ u8(suite_version)`; `author_sig = Ed25519(BLAKE2b-256(ciphertext ‖ aad))`. ⚠️ SPEC blob layout for the server `blob` column / `envelopes_local.blob`: `nonce(24) ‖ author_sig(64) ‖ ciphertext`; `blob_hash = BLAKE2b-256(blob)` (05c §2). Re-seal (05 §3) keeps envelope_id, object_id, hlc, header and the padded plaintext byte-for-byte; changes only key_version, nonce, ciphertext, sig; refuses a non-increasing version. Unknown top-level payload fields round-trip (rule 6). A header the server changes (book_id, object_id, object_type, key_version, tenant) fails the AEAD (04 §10).
- **Device certificates (04 §3.4).** `DeviceCert.issue/verify` over `uuid16(device_id) ‖ pub_ed ‖ pub_x ‖ i64be(issued_at)`; `issued_at` injected. ⚠️ SPEC: `user_id` and `suite_version` are carried plaintext beside the signature, as 04 writes it.
- **Signed records (ADR 05b §1).** `SignedRecord.sign/verifySignature/withSeq`, `SignedRecordKind` constants (membership_status, book_role, member_removal, device_revocation, device_added, key_rotation, verification_event, designation). Payload bytes are kept exactly as signed (a re-serialised payload does not verify — that is the point); ⚠️ SPEC header order `u8(suite) ‖ uuid16(tenant) ‖ lenPrefixedUtf8(kind) ‖ uuid16(author_device) ‖ i64be(hlc)`; `seq` is server-stamped and excluded from the signature.
- **Trust chain (04 §3.4, §8.3; ADR 05b §5; ADR 05c §2).** `TrustStore` interface (verified UMK per user, cert per device, revocation seq per device) and `ChainVerifier.verifyEnvelope/verifySignedRecord` → `ChainVerified` | `ChainCorrupt` (hash mismatch: corruption, no security event, checked first) | `ChainQuarantine(reason)` with `suiteUnsupported · certMissing · certInvalid · authorUnverified · sigInvalid · revoked` (seq ≥ revocation seq; ⚠️ SPEC: unknown seq with a revocation on file is refused conservatively; a backdated HLC never rescues a post-revocation envelope).
- **Shamir (04 §2, §7.3).** GF(2⁸) with the AES polynomial; branch-free multiply on the secret path, exp/log tables only for the public Lagrange basis; one polynomial per byte, coefficients from the injected RNG in one draw; `GuardianPolicy.defaultThreshold` (k = ⌈(n+1)/2⌉, n ∈ 2..5, 2-of-2 allowed), `GuardianShare` wire form `u8(suite) ‖ u32be(share_set_version) ‖ u8(k) ‖ u8(n) ‖ u8(index) ‖ bytes`, `GuardianShareSet.create/reconstruct` (refuses mixed versions, < k, duplicates). Tests include FIPS-197 known answers, an exhaustive table-vs-loop check over all 65,536 products, every k-subset for n ≤ 5, the k−1 zero-information proof, and a shrinking `kiri_check` property (B-04-69; `kiri_check` is now a `core_crypto` dev dependency too).
- **Hygiene (ADR 2026-09-05 §8).** `B-04-8` greps `core_crypto/lib` for `String`-typed key/secret/seed/share/nonce/signature/ciphertext names and platform channels; `B-04-70/71` zeroise + dispose + no key bytes in `toString`. `scripts/check_purity.sh` carries the same two greps for CI.

**Added — `packages/data`**
- Depends on `core_crypto`. `blake2bHasher(suite)` for `Mirror`; `CryptoPayloadOpener(suite, KeySource)` rebuilds the `Envelope` from a mirror row's columns + blob, decrypts, unpads and returns the object with the wrapper's `author_seq` at the top level (⚠️ SPEC: it overrides an `author_seq` inside the object); `KeySource`/`InMemoryKeySource`; typed `KeyUnavailable` (05 §4 `key_wait`, not a quarantine). Tests `E-04-1` (hasher = BLAKE2b; flipped blob byte → `BlobCorrupt`), `E-04-2` (a book sealed by core_crypto replays through Mirror + Recompute: balances right, integrity 1, `author_seq` from inside the ciphertext), `E-04-3` (server moves an envelope to another book → AEAD fails → quarantined `payload: EnvelopeOpenFailed(aeadFailed)`; missing key → `KeyUnavailable`).

**Changed**
- `PayloadOpener.open(blob, BlobHeader)` — the opener now receives the row's routing fields (envelope_id, book_id, object_id, object_type, key_version, author_device, hlc) so the AAD can be rebuilt; `JsonPayloadOpener` and Recompute's call site updated; the harness needed no change.
- ⟦tests⟧ markers on 04 §2, §3.1–§3.4, §4, §5.1–§5.3, §6, §7.3, §7.4, §7.5, §9.1, §9.2; ADR 05b §1, §5, §8; ADR 05c §2; ADR 2026-09-05 §8; 09 §1 (determinism ids) and the suite B sentence in 09 §2. Coverage at close: 316 🔒 lines · 68 marked + 10 heading-covered · 238 unmarked (from 252) · 6 `n/a` · 240 tests · 240 ids · 0 orphans · 0 dangling · 0 tests without id.
- `pubspec.lock` — sodium and its build-hook dependencies; `kiri_check` for core_crypto; `sodium` as a `data` dev dependency (tests initialise the binding).

**Decided** — nothing 🔒 ratified. `docs/decisions/2026-09-06-shamir-and-guardian-revocation-records.md` is **proposed, owner to confirm**: (1) Shamir over GF(256) in-house — the pub.dev audit found no package with an audit statement, none that is Flutter-free *and* GF(256) *and* uses injected randomness (`sss256`/`ntcdcrypto` are prime-field with `String` secrets and `dart:math`; `slip39` pulls `pinenacl`; `shamir_secret_plg` is a Flutter plugin; `dart_ssss` is Dart 2); combination wrapping not adopted (C(n,k) whole-UMK copies and a multi-recipient sealing scheme libsodium also lacks). (2) `share_set_version` wire form. (3) Guardians' k-of-n device revocation = k separate signed records counted by the client, cut-off at the k-th record's `seq` (closes ADR 05b Open 2 when ratified). 04 §2 carries a cross-reference line marked proposed.

**Open** ⚠️
- **Owner to ratify** the proposed ADR above; until then the code stands as `⚠️ SPEC`. External one-hour review of `shamir.dart` requested before M14.
- **`hlc` is unsigned** (04 §4: `author_sig` covers `ciphertext ‖ aad` only; `created_hlc` is plaintext outside both). A server could alter an envelope's HLC without any reader noticing, and 02 §8 late-arrival handling depends on it. Recommend adding `hlc` (and `envelope_id`) to the AAD or the signed digest in an ADR before M4 — a one-line change in `envelope.dart` today, a suite bump later.
- **`envelopes_local` lacks `suite_version` and `payload_schema`** (03 §3.1 vs the server row 03 §2.3). `CryptoPayloadOpener` assumes the current suite; a future suite would fail to open rather than be misread. 03 §3.1 should gain both columns (🔒 line — owner).
- `crypto_box_seal` draws its ephemeral key from libsodium's own RNG, so sealed boxes are **not** reproducible under the injected RNG; determinism tests assert on the AEAD paths instead (B-04-19). Fine for tests; noted so nobody expects golden sealed blobs.
- Shares carry no integrity check (a tampered share yields a wrong secret silently — integrity rests on the sealed transit); a `BLAKE2b-256(UMK_priv)` beside the share set would detect it if the owner wants that.
- The sync engine (M4) must mark a row `verified` only after `ChainVerifier` passes **and** the blob decrypted once, so Recompute never sees an un-keyed row (which it would quarantine `payload: KeyUnavailable`).
- 04 §11.2 (StrongBox / Secure Enclave, X25519 at-rest pattern) and §11.3 (guardian minimum) stay open for M5/M6; 04 §7.0/§7.6 backup defaults are app-level and unmarked by design.

**Commits** — pending.

---

## 2026-09-06 — M2 close-out: duplicate author_seq at the mirror, dead violation kinds pruned, first two-device tests on the harness

Third M2 session of the day, three forks. Part A (data + core_ledger follow-ups) and part B (the first behavioural suite D tests on `/testing/harness`) landed; part B exposed two seams in Recompute's author-sequence handling, fixed by part C so the harness needs no local workaround.

**Added**
- `packages/data` — derived table `author_duplicates(book_id, author_device, author_seq, kept_envelope_id, duplicate_envelope_id)` (schema version still 1, unshipped); `Mirror.recomputeAuthorDuplicates(book)` keeps the earliest by `(hlc, envelope_id)` and reports every later carrier of the same seq; Recompute step 0 quarantines each duplicate with reason `author_seq_duplicate` and holds `integrity_ok` at 0 while one exists. Test `E-05b-4` (seqs 1, 2, 2 → later 2 quarantined, earlier counted, no gap, stable across a second Recompute). Data package: 25 tests.
- `testing/harness` — `SimulatedDevice` (in-memory `LedgerDatabase` via `openLedgerDatabase`, `Mirror` with an FNV `BlobHasher`, `Recompute` with `JsonPayloadOpener`, HLC ticked from the scheduler's virtual clock; `author`, `receive`, `dump`, `integrityOk`, `balance`, `gaps`, `state`) and `Relay` (content-blind stand-in for the server: broadcasts every authored envelope to every other device through the seeded `Network`, applies arrivals in scheduler order). Harness pubspec depends on `core_ledger`, `data`, `drift`. `Scheduler.run(untilMs)` now advances `now` to `untilMs` even when later events remain queued (D-09-4 adjusted).
- Suite D behavioural tests (`test/two_device_test.dart`): **D-05b-2** orphan amendment — seed 1 delivers the amendment to device B 845 ms before its original; B holds it (`held_for` = original, not in `entries_p`, Cash unchanged, `integrity_ok` 0), then folds both once (Cash −₹300, `superseded_by` set, integrity 1), A and B dumps byte-identical, and the whole run replays from `model.log` through `ReplayNetwork` with the same intermediate observation. **D-05b-3** withheld envelope — seed 10 at drop rate 0.34 drops seq 2 (asserted); B shows the gap, keeps counting seqs 1 and 3 live, and both `monthLockPreconditions` and `yearClosePreconditions` refuse with `authorGapOpen`; a re-send clears everything and dumps match. **D-05b-4** twenty interleaved entries from two authors under reordering — arrival orders differ, dumps identical. Setup envelopes reach the peer out of band (bootstrap pull, 05 §8) so pinned seeds address entries only.
- `packages/data` Recompute (part C) ranks every event of an author uniformly over its projected seqs ∪ the mirror's missing seqs — a hole keeps its rank and nothing occupies it — so `project()` reports the gap with the exact device, `monthLockPreconditions` / `yearClosePreconditions` refuse with `authorGapOpen` from Recompute's own state, and healthy config/account objects never fake a gap. An inner `author_seq` that disagrees with the mirror row is quarantined `author_seq_mismatch` (⚠️ SPEC). `BookRecompute.state/chart` and `Recompute.stateOf(book)` expose the ranked state (a real Recompute, so it can never disagree with the rows). Tests `E-05b-5` (setup objects + entries with one reserved seq missing → one hole, provisional, preconditions refuse, integrity 0; arrival clears all; `stateOf` agrees with `run`) and `E-05b-6` (inner seq ≠ row → `author_seq_mismatch`). The harness's local ranking and its ⚠️ SPEC workaround are deleted; `SimulatedDevice.state()` is `recompute.stateOf`. Data 27 tests, harness 8.

**Changed**
- `packages/core_ledger` — `ViolationKind.amendTargetMissing`, `reverseTargetMissing`, `decisionTargetMissing` removed (no reference anywhere in packages/, testing/, app/); `targetMissing` stays. 155 tests green.
- ADR 05b §3 marker gains `E-05b-4`.
- ADR 05b §3 marker also gains `D-05b-3, E-05b-5, E-05b-6`, §4 `D-05b-2`; 09 §2 suite D sentence names `D-05b-2..4`.
- Coverage at close: 315 🔒 lines · 63 marked or heading-covered · 252 unmarked · 165 tests · 165 ids · 0 dangling · 0 orphans · 0 tests without id · 0 live skips. Push gate green.

**Decided** — nothing 🔒. Duplicates are caught at the mirror before Recompute's dense-rank pass, so the projector's own `authorSeqDuplicate` rule is unreachable from Recompute by design (it still guards direct `project()` callers).

**Fixed the same day (surfaced by the harness, closed by part C)** — (1) Recompute took an entry's inner `author_seq` verbatim while dense-ranking every other event, so a healthy single device that numbers its config/account objects too reported a gap. (2) Recompute gave a gap author no seqs at all, so `project()` saw no gap and the close preconditions could not refuse — the harness had to rank over present ∪ missing seqs itself. Both were Recompute's job; the rig's workaround is gone.

**Open** ⚠️
- **M2 exit reached** (10 M2 row: suite E client half green, harness created, held/gaps/as-of/shape/projectorVersion landed, skip re-landed). Tag after committing: `git tag m2-local-persistence`. Test-id rule learned: ids must end in digits (`E-05b-5b` is rejected), so sibling cases take the next integer.
- Platform backup exclusion (ADR 05c §8) remains app-level work at M5.

**Commits** — pending.

---

## 2026-09-06 — M2: ledger time boundary (ADR 05e/05b/05c in core_ledger) + local persistence (packages/data)

Second M2 slice, run as three forked agents on disjoint file sets (core_ledger rulings · data persistence · re-pointing data to the new projector output), then one gate. `projectorVersion` is now **2**: the certified-vector as-of rule and `held` change results for existing envelope sets (ADR 05c §3), so this bump also requires a min-client-version bump when the app ships (06 §4.5). Goldens unchanged and green.

**Added — `packages/core_ledger` (154 → 155 tests incl. the shrink pilot; ids `A-05b-1…6`, `A-05e-1…11`, `A-05c-1…2`, `A-05i-1`)**
- **`held` (ADR 05b §4, 05e §10):** an amendment, reversal or decision whose target is absent goes to `LedgerState.held` (event, `heldFor`, reason) — not counted, not quarantined; when the target is in the set the chain folds once, whatever the arrival order. `targetMissing` quarantine only when every author in the set carries `authorSeq` and no author has a gap (the target provably never existed). The M1 skip on `A-02-45` is gone; `A-02-57` (decision for an unknown entry) now asserts held.
- **Author sequence (ADR 05b §3):** `LedgerEvent.authorDevice` / `authorSeq` on every event; `Entry` JSON gains `author_seq` (positive int, validated, round-tripped). The projector reports `authorGaps` (device, expectedSeq, sinceHlc) and `isProvisional`; a duplicate seq refuses the later event.
- **Close blocks (05e §4):** `yearClosePreconditions` and new `monthLockPreconditions` refuse on `authorGapOpen` / `heldEnvelope`. The projector still records any lock it receives (all-time object, 05e §5) and re-verifies its vector — `lockVerification`.
- **Certified vector (05e §2):** `closingVector(state, chart, fy)` — money/party/advance/partner/equity_system only, cut by `accounting_date ≤ FY last day` regardless of HLC; categories not carried; one `net_result:<fy>` line per year; `trialBalance` shows net-result lines so a seeded state balances. `netProfit(state, chart, fy)` is FY-scoped (minus distributions in that FY) — **breaking: the FY argument is now required**. `accumulatedSurplus` and `distributionHeadroom` (returns the excess for the wizard's "by how much").
- **Loss distribution (05e §8):** `splitByRatio` takes a negative total as the exact mirror of `|total|`; `Verbs.profitDistribution` posts a loss (Dr partners · Cr Profit Distributed) and handles interest > profit (interest in full, negative remainder shared as loss). Actual/365 verified across leap-year 2028.
- **Shape invariants (05e §6):** `checkShape` for all six kinds (`shapeViolation`), extended with ⚠️ SPEC interpretations for classes the ADR table omits — `partner` party-like; `advance` beside money; Due to/from stands in for money on the far side of a transfer and the payee half of a pocket expense; reversals exempt (the projector proves the mirror). Table-driven `A-05e-8` over 6 wrong + 17 right shapes. The golden parser's kind inference was tightened to the same shapes; no figure changed.
- **`projectorVersion` (05c §3):** exported constant, recorded on `PeriodLock`/`YearClose`; `CloseVerification {verified, mismatch, readerOutdated, certifierOutdated}` — an older reader shows *update to verify*, never a false mismatch.
- Statement order locked to `(accounting_date, hlc, envelope_id)` (05e §12); `InterBook.reconcile` reports a sealed side as `unconfirmed`, never mismatch (05e §7); `negativeCashWarnings` for the `cash` subtype only (05e §12).
- **Shrinking property tests (ADR 05i §5, closes its Open 1):** `kiri_check` 1.3.1 adopted as a dev dependency (Dart 3, no Flutter dependency, maintained Jan 2026; `glados` is Dart-2-era and unmaintained, `propcheck` Dart 1). Pilot `A-05i-1` shrinks counter-examples over the ratio-split rule incl. the loss mirror, seeded from the same `PROPTEST_SEED`. `forEachSeed` stays for generators the combinators cannot express. `check_coverage` recognises `property(` declarations.

**Added — `packages/data` (24 tests; ids `E-03-1…14`, `E-05b-1…3`, `E-05c-1…6`)**
- Drift 2.34 + sqlite3 3.5, pure Dart; `database.g.dart` committed. `openLedgerDatabase(executor, {cipherKey})` → `Opened | MigrationFailed | QuickCheckFailed | OpenFailed`: migrations (downgrade fails closed, 03 §5), `PRAGMA quick_check` on every open (05c §6), key buffer zeroised. `sqlcipherSetup(key32)` is the `NativeDatabase(setup:)` hook that issues `PRAGMA key` from raw bytes — ⚠️ SPEC: the key cannot go through `openLedgerDatabase` itself because drift reads `user_version` inside the executor's own open. The app supplies the SQLCipher executor at M5; tests use in-memory sqlite.
- Schema v1 = 03 §3.1 + §3.2 verbatim (all Layer-1 and Layer-2 tables, key indexes incl. the partial Inbox and advance-request indexes, `push_state`/`review_state` checks, single-row `store_epoch`), plus append-only triggers on the mirror (UPDATE of blob/hlc and DELETE throw; only flag columns change). Rebuildable additions to §3.2, ⚠️ SPEC: `books_p.needs_rebootstrap`, `accounts_p.{system_role, member_id, counterpart_book_id, created_order}`, `entry_lines_p.line_index`, `year_close_p.{projector_version, verification}`, `periods_p.verification`.
- `Mirror`: idempotent append, `blob_hash` re-verified on every read via an injected hasher (core_crypto at M3) — mismatch is `BlobCorrupt`, never quarantine (05c §2); outbox state machine `queued→inflight→acked→observed` (+`rejected` with reason) with the legal-move table, prune only at `observed`; `nextAuthorSeq` atomic 1…n per (book, device) under concurrency; `observeStoreEpoch` resets all cursors and returns acked rows to queued (05b §6); `recomputeAuthorGaps` derived from the mirror; `rebootstrapBook` guarded delete that never touches the outbox.
- `Recompute`: per-book transaction; drops Layer 2, seeds from the latest `year_close_p` vector when that FY's entries are absent locally (03 §3.3 rule 3), replays verified/non-quarantined envelopes in `(hlc, envelope_id)` order through `core_ledger.project()` with an injected `PayloadOpener` (JSON in tests; M3 supplies decryption), mirrors `state.held` into the flag columns, writes every projection table; `integrity_ok` = 0 while anything is unverified, corrupt, held or gapped. Determinism: three insertion orders → byte-identical dumps of every projection table (`dumpProjections`, ⚠️ SPEC format). `verifyBalances` / `checkAndRepair` detect tampered or deleted `balances` rows and repair by Recompute.
- ⚠️ SPEC (in code): the projector sees only projected object types while `author_seq` numbers every object, so for an author with no mirror gap Recompute feeds the projector a dense rank of its projected events (contiguous ⇒ a missing target is provably absent), and for an author with a mirror gap it feeds null seqs so dangling refs stay `held`. The mirror's `author_gaps` table is authoritative. Payload wire shapes for `approval_decision`, `period_lock`, `period_unlock`, `year_close`, `cash_count`, `account`, `book_config` are M2 interpretations (snake_case, paise ints, `YYYY-MM`).

**Changed**
- `docs/02-ledger-rules.md` markers extended on §1.3, §1.4, §2, §5, §6, §7.1, §8, §8.1, §9; ADR 05e §1–§8, §10–§12, ADR 05b §3, §4, §6, ADR 05c §3, §6, ADR 05i §2 (`n/a`), §5, §7 and 03 §3.1, §3.2, §3.3, §5 carry markers. Coverage now: 315 🔒 lines · 62 marked or heading-covered · 253 unmarked · 5 `n/a` · 159 tests · 159 ids · 0 orphans · 0 dangling · 0 live superseded skips.
- `docs/09-acceptance-tests.md` §1 property line names the pilot.
- `scripts/check_coverage.dart` — counts `property(` declarations.
- `pubspec.lock` — drift, sqlite3, drift_dev, build_runner, kiri_check and transitive deps.

**Decided** — no 🔒 change. All interpretations are `⚠️ SPEC` comments in code and listed above; the owner may promote any of them to an ADR. Notable: negative `splitByRatio` as the mirror of the positive rule; net-result vector lines keyed `net_result:<fy>`; a quarantined target counts as absent for `held`; version-outdated states decided on mismatch only.

**Open** ⚠️
- **Authoring-time gap checks:** `yearClosePreconditions` sees only the projector's (dense-rank) gaps; the authoring client at M9 must also consult the mirror's `author_gaps` before offering a close. Follow-up: `Mirror.recomputeAuthorGaps` does not yet flag duplicate `author_seq`.
- `ViolationKind.{amend,reverse,decision}TargetMissing` are no longer emitted; prune once nothing serialises them (M3).
- ADR 05c §8 (backup attribute, private bucket, sweeper) is untested by design at M2 — app (M5) and server (M4) work.
- Two agents each needed one round of API reconciliation; both landed. Remaining M2 roadmap item not in code: platform backup exclusion (app-level, M5).

**Commits** — `e5acd22` (together with the test-contract slice).

---

## 2026-09-06 — M2: test contract infrastructure (ADR 2026-09-05i)

First M2 slice. Lands the traceability, lane, seed and harness machinery that ADR 2026-09-05i assigned to M2, and pays down M1's traceability backlog: every suite A test now carries an id and every 02 🔒 line those tests cover names them. Persistence (Drift + projector, 03 §3) is the next slice.

**Added**
- `scripts/check_coverage.dart` — 🔒 ↔ test-id checker (ADR 05i §1) + golden governance (§3). Scans `docs/`, `design/*.md`, `CLAUDE.md` (not `requirements-architecture.md`, not the canvas mirror) for lock marks; a heading's marker covers its section; a 🔒 followed by a lowercase word or `=` is a mention, not a mark. Fails on unmarked 🔒 lines, marker ids no test declares, malformed ids, superseded skips past their `--milestone`, and a `content_hash` that no longer matches the five worked-example files (BLAKE2b-256 via `pointycastle`, root dev dependency). Warns on orphan ids and tests without an id; lists live `superseded by ADR …` skips. **Warn-only** (exit 0) until M4 — `--strict` / `COVERAGE_STRICT=1` enforce. Wired into `ci.sh` after the strings step. Today: 315 🔒 lines · 58 marked or heading-covered · 257 unmarked (backlog, annotated milestone by milestone) · 3 `n/a` · 116 tests · 116 ids · 0 orphans · 0 tests without an id. Push and nightly lanes both green.
- **Test ids everywhere they exist.** All 111 `core_ledger` tests renamed `A-02-1 … A-02-93`, `A-03-1 … A-03-5` (HLC, unknown-field round-trip, determinism), `A-09-1` (property), `A-ref-1 … A-ref-7` (golden replay), `A-10-1`; M0 hello-worlds `B-10-1`, `D-10-1`, `E-10-1`, `F1-10-1`; harness `D-09-1 … D-09-5`. Numbering is a running integer per source, in test-file order — ids are stable from here.
- **`⟦tests: …⟧` markers** on 34 lines of 02 (§1.1–§1.4, §2, §3, §4, §5, §6, §7, §7.1 rules that have engine tests, §8, §8.1, §8.2, §9), 3 of 03 (§1, §3.3, unknown-field rule), 3 of the worked-examples README, 3 of the accounting standards, 09 §1, CLAUDE.md (Accounting authority; Precedence = `n/a`), 10 (Platform / Cross-references = `n/a`; Sequencing → the four hello-world ids). UI-only, M9+ and §10 import lines were **left unmarked on purpose** — an unmarked line is honest backlog; `n/a` is reserved for rules that are untestable by nature.
- `dart_test.yaml` at the workspace root (tags `A B C D E F1 G property flaky slow`, per-tag timeouts, `flaky` skipped by default and re-enabled by `--preset nightly`), included by every package's own `dart_test.yaml`. `@Tags(['A'])` on every suite A file, `tags: 'property'` on the three generators, `D` on the harness, `F1` on the app shell test. Probe-tested: a `flaky` test is skipped in the default preset and runs under `nightly`.
- **Seeds (ADR 05i §5):** `forEachSeed(testId, body)` in `core_ledger/test/helpers.dart` replays every seed listed for the test in `test/regress/seeds.txt`, then one fresh seed (`PROPTEST_SEED` pins it, else drawn from the clock — test code, not lib/). A failure re-throws with the seed, the replay command and the pin instruction. The three M1 generators (`Random(20260904)`, `Random(71)`, `Random(7)`) moved to the seeds file as permanent regression cases.
- **Golden path fix (ADR 05i §9):** `workspaceRoot()` walks up to `CLAUDE.md`; `dart test packages/core_ledger/test/golden_worked_examples_test.dart` now passes from the repository root as well as from the package.
- **`/testing/harness`** (workspace package `harness`, pure Dart, `dart:math` allowed — not a `core_*` package): `Scheduler` (discrete-event, virtual clock, `(at, seq)` order, `run(untilMs)`, `cancel`, `trace`), `NetworkModel` (one seed → uniform delay, reorder by delay, drop rate, `OfflineWindow`s that hold sender and receiver traffic until reconnect), `NetworkLog` (JSON round-trip) and `ReplayNetwork` (drives the identical run from the log and refuses a drifted scenario) behind a `Network` interface for M4's devices and server. Five self-tests. `/testing/fixtures` and `/testing/goldens` created with READMEs stating the synthetic-only and goldens-stay-in-docs rules.
- `.github/workflows/ci.yml` — nightly schedule (03:00 IST) runs `LANE=nightly`; `workflow_dispatch` takes a lane input.

**Changed**
- `scripts/ci.sh` — `LANE=push|nightly|rc|release` (default push); nightly runs `dart test --preset nightly`; steps a lane does not own yet print *scheduled — lands at M<n>* instead of pretending to run; test loop now includes `testing/harness`; coverage step added.
- `scripts/check_purity.sh` — Flutter-import check extends to `testing/`; test-data hygiene grep (ADR 05i §7) over `packages/*/test`, `app/test`, `testing/` for real-looking Indian mobile numbers (standalone `[6-9]\d{9}`, or `+91` outside the reserved `99999` block), Aadhaar-shaped and PAN-shaped strings. Zero false positives on the current trees — the ₹-amount concern in ADR 05i Open 3 does not bite because paise in tests are written as `rs(…)` expressions.
- `pubspec.yaml` (workspace) — `testing/harness` joins the workspace; `pointycastle` root dev dependency.
- `docs/10-roadmap.md` — parking-lot status line says "locked" in words (the emoji was a mention the checker would otherwise read as a mark).
- `CHANGELOG.md` — commit hashes filled for M0 (`4eee9c1`), M1 (`ae7293d`), 05d (`b7d7535`), the 05e–i fan-out (`354437a`) and the env session (`d1d26c6`, `4bc3048`); the env session's Open item (no `LANE`, no `check_coverage`) closed.

**Decided** — no 🔒 change, no ADR. Conventions fixed in code comments: id numbering is a running integer per source in test-file order; the golden `content_hash` is BLAKE2b-256 over the five example files' bytes concatenated in the README's file order; `n/a` markers only for rules untestable by nature.

**Open** ⚠️
- **Shrinking property-test package (ADR 05i §5, Open 1)** — not adopted this slice; `forEachSeed` is the interim rule the ADR allows. Candidates to evaluate next slice: `glados` (shrinking, Flutter-free, maintenance to confirm) vs staying on seeded loops; recommendation: decide only once a generator actually needs shrinking.
- 257 🔒 lines still unmarked — by design, they are annotated as their milestone's tests land (03/05 at M2–M4, 04 at M3, 06 at M6, 07/13/design at M5+, 08/12 at M13). The checker stays warn-only until M4 exit.
- The skipped `A-02-45` (amend target missing → `held`) re-lands with the `held` state in the next M2 slice, as the skip reason says.
- `flutter_test` accepts `@Tags`; whether `flutter test` honours the root `dart_test.yaml` include is untested until F1 grows past one file.

**Commits** — `e5acd22` (together with the ledger-time-boundary + persistence slice).

---

## 2026-09-06 — env: Claude Code hooks + project skills

Owner asked whether to add plugins/skills for coding, testing and database work. Ruling: wire the existing `scripts/ci.sh` gate into the session via hooks, encode the CLAUDE.md workflow as project skills, defer stack plugins (Supabase MCP until the M4 server milestone and then against a local project only; TypeScript LSP once `server/functions` exists; no Dart/Flutter LSP exists in the official marketplace).

**Added**
- `.claude/settings.json` — three hooks. PostToolUse on Write|Edit runs `dart format` + `dart analyze --fatal-infos` (package-scoped; `flutter analyze` under `app/`) + `scripts/check_purity.sh`, failures returned to the model as a blocking reason. PreToolUse on Bash denies `git commit` / `git push` / `gh pr create` at command position (owner commits). Stop blocks once when the tree changed but `CHANGELOG.md` did not (`stop_hook_active` guard).
- `.claude/hooks/{dart_post_edit,block_git_commit,stop_changelog}.sh` — the hook scripts; pipe-tested on pass and fail paths (nine-case table for the commit block, incl. prose mentions that must be allowed and `git -C . commit` that must be denied); PreToolUse proven live in-session.
- `.claude/skills/` — `/slice M<n>` (orient on roadmap row + owning spec + ADRs + 09 ids, tests-first), `/gate [lane]` (run ci.sh, report by step/suite, mechanical fixes only), `/adr` (dated ADR scaffold with `⟦tests: …⟧` markers, spec cross-refs, changelog Decided line), `/changelog` (house-format entry), `/goldens` (suite A worked-example goldens with the engine-bug / spec-vs-reference / parser-drift triage).

**Changed**
- Plugins installed by the owner from `claude-plugins-official` (user-level, not in the repo): `hookify` (rule-based hooks from conversation analysis) and `context7` (live library docs via MCP — Drift, sodium_libs, Supabase, Deno).
- `.gitignore` — `.claude/settings.json`, `.claude/hooks/`, `.claude/skills/` now tracked alongside `.claude/commands/` so hooks and skills travel with the repo.

**Open** ⚠️
- `ci.sh` has no `LANE` switch and no `check_coverage.dart` yet, though CLAUDE.md § Commands describes both; they land at M2 per ADR 2026-09-05i. `/gate` passes `LANE` through and says so. → *closed 2026-09-06 (M2 test-contract slice).*

**Commits** — `d1d26c6`, `4bc3048`.

---

## 2026-09-05 — docs: seven-spec review fan-out → five ADRs (05e–05i) + M2 code follow-ups

Seven parallel review agents (02, 07, 08, 09, 12, 13, design system) produced one consolidated decision sheet of 40 items; owner ruled **"accept all recommendations"**. Five forked agents drafted one ADR each plus an edit script; scripts applied serially (e → g → h → i → f), shifted anchors re-anchored by hand, zero table breakage, `gen_tokens --check` green.

**Decided**
- `2026-09-05e-ledger-time-boundary.md` — 🔒 §9 balance formula restated (reversal + target both count); certified vector as-of `accounting_date`, balance-sheet accounts only, FY P&L from FY envelopes, Corpus a computed line (accounting-reference conflict owner-ruled; errata F-5/F-6/F-7 pending bookkeeper sign-off); late arrivals in live balance, out of certified month; close blocked on author gap / `held`; `period_lock`/`period_unlock` all-time objects; per-kind shape invariants; sealed-book pairs *unconfirmed*; loss distribution + FY-scoped period + ceiling; member removal / FY-start / archive structural (quorum), FY-start frozen after any close; peer reviewer in `book_config`; `held` = dangling ref only, tray state renamed `inTray`; registry + `period_unlock`, `structural_approval`, `business_setting`.
- `2026-09-05f-ux-design-catch-up.md` — 🔒 tab bar = four tabs + docked centre (+) in 13/07/design-system/DESIGN-PACK; the seventeen ADR states given screens (S1.4, S10.5, S11.9, S11.10, S15.4, S19.5, variants), 13 §6 gains Device and App-lock models, Sync aligned to 05 §9; 07 §5 contradictions resolved (later rulings win); Inbox card taxonomy; notification→destination map (13 §3.4); nine screens 07 did not own + Opening-balances door; copy honesty fixes; design system: status colour family (icons/borders/words, never amounts), four grounds audited, `focus-on-primary`, type scale + Indic line-height floor, canvas palette generated from tokens, skeletons/loader drawn, paise none in-app / two decimals in statements, `check_contrast.dart` in ci.sh; pending/locked/sunk/scrim approved with the sunk caveat; PIN lockout = ADR behaviour + canvas tone.
- `2026-09-05g-subscription-entitlement.md` — 🔒 entitlement token under the **one** server signing key (pinned beside SPKI pins); hard caps server-side, watermark soft and reports-only; quota table (10k/100k/250k/1M envelopes per book · 250 MB/2/5/15 GB · attachments 100 MB/2/5/20 GB · 10 MB/file · devices 5/5/8/15 = max across tenants · 600/min, 5k/h, 50 MB/day) closes 05b §7 ⚠️; dunning grace ≠ offline grace, clock floor; seats count invited+pending+active; `payer_user_id`; IAP option 1 + web GST checkout + single INR price; `billing_events`, `subscriptions.updated_at` etc.; GST in paise half-up; refunds scoped to gateway, one per user lifetime; trial once per user; 24-month lapsed → cold storage, never deletion.
- `2026-09-05h-admin-console-staff.md` — 🔒 freeze exists narrowly (fraud/legal/abuse, four-eyes, ≤30 d, member notified; `rejected:tenant_frozen` pushes only) and is in 06 §8; support revocation pending-window + no re-revoke after cancel; support deletion = request to user devices; admin role has no KMS decrypt, phone lookup by HMAC, own column allowlist; break-glass doctrine (12 §3.1) for backup/maintenance/KMS incl. Phase-0 SQL; staff lookup quotas; hash-chained off-box staff log ≥3 y separate from 03 §6; staff roles + SSO + quarterly review; four-eyes by irreversibility; config canary/rollback; DPDP & legal (12 §7); transparency event Phase 1; ≥2 staff accounts.
- `2026-09-05i-test-contract.md` — 🔒 test ids + `⟦tests: …⟧` marker on every 🔒 line, `check_coverage.dart` warn→block at M4; four CI lanes; golden governance (provisional until bookkeeper sign-off, README front-matter approval + hash, blocks M14 exit; README header corrected 5/8/185); supersession `@Skip` rule; shrinking property tests / seed corpus; perf gate SE 3 p95/20 nightly, Android at M12; `/testing/harness`; hygiene grep + flaky policy; suite F → F1/F2/F3; E server runner; 13 previously untested 🔒 rulings given ids.

**Added (code, M2 follow-ups)** — `packages/core_ledger`: `EffectiveStatus.held` → `inTray`; orphan-amendment test split, the superseded half `@Skip`ped with the ADR pointer. `dart analyze` clean; 134 passed, 1 skipped.

**Changed** — 02, 03, 04, 05, 06, 07 (+ new §§20–28), 09, 10, 11, 13, CLAUDE.md, design-system.md, DESIGN-PACK.md, tokens.json (`_proposed_2026-09-05f` note only), reference errata + worked-examples README + one Corpus sentence + one interest figure (pending sign-off).

**Open** ⚠️ — per-ADR Open sections; notably exact hex for the darker light `credit` (05f), shrinking-generator package (05i), SAC code (05g), canvas-mirror versioning (05f), 07 §19 renumber pass.

**Commits** — `354437a`.

---

## 2026-09-05 — docs: auth & devices vs the hostile relative (ADR 2026-09-05d)

Fourth review of the day, of 06. The strongest spec of the four; its gaps were flows that let a hostile human — or two colluding guardians — act faster than the owner can notice.

**Decided** — `docs/decisions/2026-09-05d-auth-devices-human-attackers.md`
- 🔒 Guardian recovery and guardian phone-change **wait 24 h with one-tap Cancel** on every existing device when the user still has an active device; immediate only when none exists.
- 🔒 **Uncertified devices see nothing but themselves** — server verifies the cert under the UMK public key, RLS requires `certified` for every tenant table.
- 🔒 **Support revocation delayed 24 h, cancellable**, lands unsigned → target suspends, never wipes.
- 🔒 Keystore bound to the **current biometric set**; enrolment change → MPIN. 🔒 **MPIN attempt policy** (5 free, escalating, 10 → OTP+biometric), HMAC under a hardware-backed key, counter survives app-data clearance.
- 🔒 **New-device notice on every path** (incl. silent platform key sync) + `device_added` signed record; verification events are signed records.
- Threat model names Apple/Google-account + number compromise; invites phone-bound; 15-min revocation lag stated; challenge/registration rate limits.

**Changed** — 06 §3, §4.4, §5, §6, §7, §8, §9.3 (placement fix), §9.4, §10, §11 · 04 §1.2, §7.3 · 03 §2.5 · 07 §5.6 · 09 suite C · 10 M6.

**Open** ⚠️ — rate-limit numbers; per-tenant 24 h window; Android keystore invalidation across OEMs.

**Commits** — `b7d7535`.

---

## 2026-09-05 — docs: storage durability & integrity (ADR 2026-09-05c)

Third review of the day, of the data model (03). Spine stands (envelopes are truth, projections disposable, integer paise, one plaintext boundary, append-only by grant). Gaps were at the edges 03 had not looked at.

**Decided** — `docs/decisions/2026-09-05c-storage-durability-integrity.md`
- 🔒 **India residency** for DB, object storage, backups, logs; PITR + snapshot policy (numbers ⚠️); quarterly restore drill; every restore bumps `store_epoch`.
- 🔒 **`blob_hash`** plaintext column — corruption is re-fetched and counted, never quarantined; only an intact blob with a bad signature is tampering.
- 🔒 **`projectorVersion`** recorded in every lock/close envelope; older readers show *update to verify*, never a false mismatch; result-changing projector changes bump min-client-version and force Recompute.
- 🔒 **Phone numbers encrypted at rest** (`phone_ct` + `phone_hmac`, server KMS); **invitees' numbers never stored** (HMAC only).
- Shape checks enumerated (`rejected:shape`); local corruption path (`quick_check`, drop+Recompute / re-bootstrap; `integrity_ok` gates Home); RLS with our own claims via `SET LOCAL`; platform backups excluded; private bucket + orphan sweep; audit retention 24 mo.

**Changed** — 03 §1/§2.1/§2.3/§2.5/§3.1/§5/§6/§7/§8 · 02 §8 step 4 · 04 §4 · 05 §3, §8 · 06 §7, §9.3 · 09 suite E · 10 M2/M4.

**Open** ⚠️ — PITR/snapshot/RTO-RPO numbers vs hosting plan; KMS/Vault choice + rotation; whether projector bumps share the crypto/sync min-version route group.

**Commits** — `460eb53`.

---

## 2026-09-05 — docs: sync trust boundaries (ADR 2026-09-05b)

Same review as the client blueprint, applied to 05. Core of 05 stands (seq cursors, idempotency, key-sync-before-drain, content-blind server, cross-client close hashes). Every gap was one shape: the server was still trusted for things it should only relay.

**Decided** — `docs/decisions/2026-09-05b-sync-trust-boundaries.md`
- 🔒 Structural facts (membership, roles, limits, revocation, removal, rotation) are **signed records** from certified devices; server rows are their projection; clients verify the record, not the row.
- 🔒 **No wipe on the server's word** — unsigned revocation → *suspended*, data kept; wipe only on a verified signed record.
- 🔒 **Per-author sequence inside the ciphertext** — withholding becomes a visible gap; provisional projection; month/year-close blocked while gaps exist.
- 🔒 **Dangling refs are `held`**, not counted (fixes the M1 orphan-amendment double-count when the original arrives late).
- 🔒 **Revocation cut-off = server `seq`**, never HLC (a stolen phone cannot backdate its receipt).
- 🔒 **Store epoch** on every response + outbox `observed` state (read-your-writes; `write_lost` event) — survives a server restore.
- Rate limits + per-plan quotas (numbers ⚠️ 08), plaintext padding to size buckets, signed-URL lifetimes, content-free server metrics, separate `maintenance` deletion role.

**Changed** — 05 §1/§3/§4/§5/§9/§10/§11 · 03 §2.5, §3.1 (schema) · 04 §1.2, §9.2 · 02 §5 · 06 §7 · 09 §2 suite D · 10 M2/M3/M4 rows.

**Open** ⚠️ — quota/rate numbers per plan (08); guardian k-of-n revocation as multi-sig vs k records (M3); one `bigserial` for records + envelopes (with 05 §11.1 test). Owner raised **whether to drop zero-knowledge** for a server-readable tier; **ruled 5 Sep 2026: keep zero-knowledge for now.** The opt-in company-assisted-recovery tier is parked in 10 § Phase 2 (not scheduled, not 🔒). Owner also asked why libsodium rather than Flutter/Dart built-ins — answered in session (Dart has no AEAD/signature/KX primitives; libsodium is native C over FFI, audited, one implementation for both platforms); rule 7 stands.

**Commits** — `217818a` (ADR + cross-refs); zero-knowledge ruling + parking-lot row follow in the next commit.

---

## 2026-09-05 — docs: client hardening (ADR 2026-09-05)

Owner brought a generic Flutter fintech security blueprint (MASVS / PCI framed) and asked what we adopt. Assessed against 04/05/06/07/13; about two thirds already decided or compatible.

**Decided** — `docs/decisions/2026-09-05-client-hardening.md`
- **Rejected 🔒:** "server is the sole authority for financial calculations" — contradicts zero-knowledge; the ADR tabulates our equivalents (signed envelopes, deterministic projector + cross-client hash, flag-for-review limits, signed quorum approvals) so the idea does not return.
- **Adopted 🔒:** SPKI public-key pinning with backup pins, hard-fail in staging too (05 §1) · OS transport configs, `FLAG_SECURE`, tap-jacking flag (M0 shell) · obfuscated release builds with symbols kept as CI artefacts · **screenshots/recording blocked** — owner-ruled, because PDF/WhatsApp share already exists (07 §5.6) · root/jailbreak/debugger **detect-warn-log, never block** (06 §4; 04 §1.2) · foreground inactivity lock 5 min beside the 2 min background lock (06 §4) · key material only in `Uint8List`/`SecureKey`, FFI-only, never a `MethodChannel` · CI: secret scan, dependency audit, no bare `print(` · temp exports purged after share (readable Drive export untouched) · MASVS L2+R as the M14 checklist; PCI out of scope, DPDP not GDPR.

**Changed**
- 04 §1.2, 05 §1, 06 §4 + §11, 07 §5.6, 09 §4 (client-hardening gates), 10 (M14 row + hardening-by-milestone note).

**Open** ⚠️
- SPKI pin set for hosted Supabase (intermediate CA + backup) and rotation runbook — verify at M4.
- `FLAG_SECURE` on the *Show my code* ceremony screen (consistent; confirm camera path unaffected).
- Detection library: prefer a small native check we own over a third-party package in the trust path.
- Code items (manifest flags, ci.sh steps, purity grep) land with their owning milestone — none written this session.

**Commits** — `2b89db7`.

---

## 2026-09-04 — M1: ledger core (pure Dart)

Exit gate (10 M1): **suite A incl. property tests, green** — `./scripts/ci.sh` passes end to end; `core_ledger` carries 134 tests, among them the golden replay of all five worked examples (8 books, 185 vouchers: every ledger row, every closing c/f, every trial-balance row and total, and the three Due to/from pairs whose both sides are in the package).

**Added** (`packages/core_ledger/lib/src/`, ~2,900 lines + ~2,300 lines of tests)
- `money.dart` — `Paise` extension type over `int`: integer arithmetic only, no path to a float (rule 1); `Side`; `floorDiv`, `roundHalfUp`.
- `local_date.dart`, `hlc.dart` — `LocalDate` / `YearMonth` / `FinancialYear` (per-book start month, default April) with no clock anywhere; `Hlc` = 48-bit ms + 16-bit counter (03 §1), `tick()` takes the physical reading as an argument; `(hlc, id)` event order.
- `accounts.dart` — `BookType`, the seven `AccountClass`es, `MoneySubtype` (incl. `cashCollection`), `SystemRole` for the equity_system wizards, `Account`, `Chart`.
- `entry.dart` — `Entry` / `Line` / `EntryRefs` per 02 §1.3 wire names; `fromJson` rejects non-integer money; unknown fields ride along at entry, refs and line level and are written back byte-stable (03 §3.3.4); `amendWith` / `reversal` builders (02 §5).
- `invariants.dart` — universal invariants 02 §1.4 + reader re-checks (`review_required` vs carried limit, `pending` only for an advance request shape); authoring-only future-date rule kept out of the projector.
- `verbs.dart` — the six verbs, the adjustment wizards (opening, cash-count difference, write-off), advance request/spend/return, partner paid-cost/drawing, and one-entry `profitDistribution` (interest first, then remainder by ratio). Wrong-class slots throw; a gollak is never a spending source and empties only into Cash or a bank account (02 §8.2).
- `ratio.dart` — `splitByRatio` 🔒 rule: floors, remainder to the largest ratio, ties to earliest; property-tested.
- `projection.dart` — `project(events, chart, {opening, heldInTray})`: sorts by `(hlc, id)`, quarantines violators as security events, folds approval decisions (last wins; self-approval quarantined — 02 §7.2 item 1), amend chains (head only, kind fixed), reversals (exact mirror, once), the advance queue vs the review queue, period lock rule (02 §8), year close with reader-side vector re-verification and certificate voiding on re-open (02 §8.1); `BalanceVector.canonical()` as the close-hash input; `trialBalance`, `statement` (running balance + side per row), `netProfit`, `yearClosePreconditions`.
- `partners.dart` — `interestOnCapital` (average daily balance, inclusive days, half-up to the paisa; debit balances charged unless told otherwise), `settlementCapacity`, `partnerDrift` (02 §7.1).
- `advances.dart` — `openAdvances` with FIFO ageing (02 §7). `interbook.dart` — `InterBook.transfer` / `pocketExpense` pairs sharing `transfer_group`, `isInTransit`, `reconcile` (02 §6). `cash_count.dart` — `DenominationSheet`, `CashCount` memo event, `countPolicy` / `validateCount`, `resolveCount` → verified / adjustment / recognition (02 §8.2).
- Tests: `test/golden_worked_examples_test.dart` parses the worked-example markdown directly (chart, daybook, ledger rows, TB) so the fixtures stay in `docs/reference/` as the single source; unit/property suites per module.

**Decided** (interpretations, all conservative, marked `⚠️ SPEC` in code — no 🔒 change, no ADR)
- `review_limit_paise` is nullable in the engine: `null` = no limit applies (own personal book, single-member book). 02 §1.3 types it as a plain int; the "never flagged" cases needed a representation.
- Advance movements map onto the six kinds as request = `money_out` + `pending`, spend = `money_out`, return = `money_in`. 02 fixes the postings, not the kind; balances never depend on kind.
- Re-dating a late arrival is the one amendment accepted against a locked period: lines identical, only the date moves, into a period open at the amendment's HLC. Everything else in a locked period must go through reversal. The tray itself (arrival order) is client-local and is passed to `project` as `heldInTray`.
- Verified interest illustration in paise: Amrit ₹4,295.89 · Sukhdev ₹2,311.23 · Harjit ₹1,354.52 (8 %, 1 Apr–31 Jul, day of posting counts).

**Open**
- ⚠️ 02 §7.1 shows Harjit's interest as ₹1,354 and the remainder as ₹5,86,039; `joint-business-partnership.md` §5 shows ₹1,355 / ₹5,86,038. Both are whole-rupee displays of ₹1,354.52 — no engine conflict, but the two documents should agree. Suggest both print paise.
- ⚠️ `joint-business-partnership.md` §5 "equal share of costs" splits ₹3,35,000 in rupees (1,11,668 / 1,11,666 / 1,11,666). The 🔒 rule divides in paise: 1,11,666.68 / 1,11,666.66 / 1,11,666.66. Presentation column only; flag for the bookkeeper pass.
- ⚠️ `trust-singh-sabha-gurudwara.md` predates the 2–3 Sep gollak ADRs: its "Gollak Cash A/c" is spent from directly (T-003, T-018…), so the fixture treats it as plain `cash`. On sign-off, consider splitting it into a `cash_collection` Gollak plus the seeded Cash A/c with Transfer vouchers between them.
- ⚠️ Owner to confirm the three interpretations under *Decided* (nullable limit, advance kinds, re-date rule) or point at the section that settles them.
- Not in M1 by design: envelope signing/encryption around these payloads (M2, 04), Drift persistence + the running-balance cache (M3, 03 §3.2), HLC generation from a real clock (M4 sync), FY-scoped P&L views and statement presentation strings (M5+).

**Commits**
- `ae7293d`

---

## 2026-09-04 — M0: scaffold

Exit gate: **CI green on hello-world tests** — `./scripts/ci.sh` passes end to end (pub get · generators current · format · purity · strings · analyze · 4 package suites · 3 app widget tests).

**Added**
- Pub workspace root (`pubspec.yaml`, one `pubspec.lock`) over `packages/core_ledger`, `core_crypto`, `data`, `sync_engine` and `app`; strict analysis options at root, per package and in the app.
- Four pure-Dart packages, each with a `packageName` hello export and one test; doc comments name the spec they own (02/04/03/05).
- `app/`: Flutter, iOS + Android targets (`com.rukkafolio.*`), Material 3 theme built from tokens only, light + dark, brand fonts (Mukta 400/500/600, Mukta Mahee 400/500/600, Noto Sans variable; OFL licences beside them), `flutter_localizations`, hello screen showing `app.name` + `splash.opening`; widget test renders EN / PA / HI.
- `scripts/ci.sh` — the gate, also run by `.github/workflows/ci.yml` (Flutter 3.47.0 stable, ubuntu).
- `scripts/gen_tokens.dart` — the only writer of `tokens.css`, `design/tokens/tokens.dart` and `app/lib/shared/tokens.dart`; `--check` fails CI on drift (design-system.md §status). Regenerated outputs verified value-identical to the hand-synced files; new: `RkIcon`, `RkMarkLight/Dark`, `RkMotion.markUnlockTotal`, `RkSpace.cardPadding`, `--row-min-h`.
- `scripts/check_strings.dart` — EN/PA/HI key parity, ICU placeholder parity (01 §1 rule 7), forbidden-jargon scan with the rule-4 whitelist (`app.name`, `app.name.short`, `about.*`), dotted key shape.
- `scripts/check_purity.sh` — no Flutter in `packages/`; no `dart:io`/`dart:math`/`DateTime.now()`/`Random()` in `core_*`; no hex colour literals in `app/lib` outside the generated tokens file.
- `scripts/gen_l10n_arb.dart` — see Decided.

**Changed**
- `design/tokens/tokens.json`: `space` gains structured `gutter` / `cardPadding` / `rowMinHeight` (values already present in its note); `$meta.note` now names the generator. No token value changed.
- `design/tokens/tokens.css`, `tokens.dart`: now generator output (headers say so).
- `design/design-system.md`: generator landed; M0 checklist ticked. `CLAUDE.md`: scripts listed in Layout; workspace / tokens / strings commands.
- `.gitignore`: Dart/Flutter/iOS/Android artefacts, `app/lib/l10n/gen/`, `.env*`.

**Decided** (build-time bridge, not a spec change — no ADR)
- 01 §1 rule 9 🔒 keeps ARB keys dotted (`screen.element.state`); Flutter gen_l10n only accepts Dart identifiers. Canonical ARBs stay dotted in `app/lib/l10n/`; `gen_l10n_arb.dart` derives identifier-keyed copies into the git-ignored `app/lib/l10n/gen/` (`app.name` → `appName`). Collisions fail the build.
- Product name stays Latin in PA/HI ARBs (01 §1 rule 8: a name the user matches, not a word inside a sentence; lockup shows it that way, 11 §4.2).

**Open**
- ⚠️ `splash.opening` PA/HI (ਤੁਹਾਡੇ ਵਹੀ-ਖਾਤੇ ਖੋਲ੍ਹ ਰਹੇ ਹਾਂ। / आपके बही-खाते खोल रहे हैं।) drafted from the 01 §2 term table; native review at the M12 gate.
- ⚠️ Bundle id `com.rukkafolio.*` is a placeholder until the domain / store-name check in README § Name.
- Not in M0 by design: `server/supabase` (M4, needs Docker), `testing/` harness (M4), Drift/SQLCipher/libsodium deps (M2/M3), `tokens.dart` consumers beyond the hello theme (M5).

**Commits**
- `4eee9c1`

---

## 2026-09-04 — env: development toolchain

**Added**
- Flutter 3.47.0 stable (Dart 3.13.0) via Homebrew cask; `flutter doctor` clean in every category.
- CocoaPods 1.17.0, Deno 2.9.5, GitHub CLI 2.97.0, Supabase CLI 2.116.0.
- Android SDK via `android-commandlinetools` cask: platforms 35 + 36, build-tools 35.0.0 + 36.0.0, platform-tools 37.0.1, emulator 37.1.11; all licenses accepted.
- OpenJDK 17.0.20.1 (Homebrew formula, no sudo) — Flutter configured with `--jdk-dir`.
- `~/.zprofile`: `ANDROID_HOME`, `JAVA_HOME`, `platform-tools` on PATH.
- This file, and the changelog rule in `CLAUDE.md` § Workflow.

**Open**
- ⚠️ Docker Desktop not installed — cask needs a sudo password. Required from M4 for `supabase db reset` and local RLS tests. Owner runs `brew install --cask docker-desktop`.
- No Android emulator image yet; not needed before M12 (iOS ships first, 10 🔒).

**Commits**
- `a08ec51`

---

## 2026-09-03 → 2026-09-04 — docs: design fold, brand v1.4, loading states

**Changed**
- Dark-theme credit/debit tokens → `#4FA37A` / `#CB6F6F` (debit lifted one step for AA on surface).
- 11 §4.5 — how the app waits: loader rule, ruled skeletons, splash branches; canvases 1/11 lockup, spinner removed.
- 11 §4.2 → v1.4: brand v1.2 mark canonical, icon package + animation reference, canvas 3 sealed mark.
- Verb pill: *Move money* is the fifth position; one door per adjustment wizard.
- Menu gains *Close the month*; Import lives in the entry header (S2), not a Menu row; Legal row on the Menu (07 §1).
- Roadmap: Phase 2 parking lot (non-normative).
- Gollak: deposits flexible (Cash A/c or bank, whole or in parts); empties only into the Cash A/c. Trust Cash A/c gets its own verify-mode count (C3c).
- Canvas 7 split into 7 / 15 / 16; canonical bottom-nav icon set; `/design-pull` pins canonical canvas display names.

**Decided**
- `docs/decisions/2026-09-03-gollak-deposit-flexibility.md`
- `docs/decisions/2026-09-03-menu-close-row-and-import-in-entry.md`
- `docs/decisions/2026-09-03b-entry-doors-move-money-and-wizards.md`
- `docs/decisions/2026-09-03c-brand-v1.2-mark-canonical.md`
- `docs/decisions/2026-09-03d-loading-and-splash.md`

**Commits**
- `9125a8f` `6f02926` `b2c6e08` `2655410` `098a8cf` `6d8a1f7` `ddcfede` `a761ea0` `2c1a42c` `d66ca49` `93d7dac` `4a00f50`

---

## 2026-09-01 → 2026-09-02 — docs: design slices 2–4, rulings A1–A4, Option B

**Changed**
- Slice 2: 13's screen inventory reconciled with the drawn canvases.
- Slice 3: danger-surface verdict; `sunk` + `scrim` tokens added as PROPOSED.
- Slice 4: S6.1 drawn, S17.1 folded, S18.x are documents, Narration carve-out, branch order ruled.
- A1+A2: one PIN everywhere; S7.2 = import balance check. A3: drawings (S2.5) + donation receipt (S4.2) ratified, D6 removed. A4: head displays as *President*; S7.4 import preview added.
- Option B ruled: designations are labels, permissions admin-granted; designation vocabulary tables (trust/org + business) saved.
- Trial Balance transliterates — ਟ੍ਰਾਇਲ ਬੈਲੇਂਸ / ट्रायल बैलेंस 🔒.
- 1 Sep design fold landed: MPIN, role labels, onboarding branches, vocabulary.

**Added**
- `/design-pull` command + byte-exact extractor `scripts/design_mirror_extract.py` (envelopes ordered chronologically).

**Decided**
- `docs/decisions/2026-09-01-pin-model-and-import-ids.md`
- `docs/decisions/2026-09-02-ratifications.md`

**Commits**
- `ab96d83` `6992bcc` `6bf4e99` `db8df45` `6493ece` `30b04b5` `b8c6843` `2fbaac6` `07f1980` `cc42990` `a6e0a5e` `31661b4` `ab1c7f1`

---

## 2026-08-30 → 2026-08-31 — docs: specification set v1.0

**Added**
- Specs 00–13, `requirements-architecture.md` (non-normative), `design/` system + tokens, `CLAUDE.md`, `README.md`.
- Screens: account · subscription · support · legal · system states; entry detail, invite, profile, plans, help, legal, update/maintenance, permissions, viewer, search, Group-by flow; backup setup, recovery flow, devices and backup settings.

**Changed**
- Phone recovery flow; language keyword corrections.

**Decided**
- `docs/decisions/2026-08-30-audit-remediation.md`

**Commits**
- `6d030a6` `774c421` `0efff54` `caa2499` `c3c66ce`
