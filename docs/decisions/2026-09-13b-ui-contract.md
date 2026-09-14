# ADR 2026-09-13b — The UI contract: one look, one state pattern, two form factors

**RATIFIED by the owner, 14 Sep 2026** — *"Fix the four items that are waiting."* Answers recorded from that instruction; the reasoning for each is in the ruling it belongs to.

**Raised by the owner, 13 Sep 2026**, after a shell defect and five lane-local components landed in one
round: *"Every lane should have error, issue free result… the style, UI should be uniform through all the
ways. And for all platforms."* Then, on form factor: iPad is **in scope**, and the layout base is to be
designed **before the pilot**.

The three complaints have one root cause. **A lane cannot consume a contract that does not exist.** Lanes
own disjoint directories and run in parallel, which is what makes them fast and also means they cannot see
each other's work. Where the repository already publishes a contract, lanes comply perfectly and CI proves
it — not one hex literal has reached `app/lib` in five milestones, because `check_purity.sh` refuses them.
Where no contract exists, every lane invents, and the divergence is discovered later and paid for by a
cleanup lane (SW1 existed only to fold a duplicated `SuspendedBanner` into one atom).

So this ADR does not ask lanes to try harder. It writes down the missing contracts and makes each one
machine-checkable.

## What already holds, and is not changing 🔒 ⟦tests: n/a — restates enforced rules⟧

The owner's Clean Architecture reference (Presentation / Domain / Data, dependencies pointing inward) is
**already this repository's architecture, enforced more strictly than the diagram asks**:

| Diagram | Here | Enforced by |
|---|---|---|
| Domain — entities, use cases | `packages/core_ledger` (02), `packages/core_crypto` (04) | `check_purity.sh`: no Flutter, no `dart:io`, no `dart:math`, no `DateTime.now()`, no `Random()`, no platform channel |
| Domain — repository interfaces | seams: `ReportSink`, `ClosedYearsSource`, `ReviewQueue`, `SyncClient`, `AuthClient`, `KeyStore` | type system; every one has a fake |
| Data — implementations, models, local/remote sources | `packages/data` (03), `packages/sync_engine` (05) | `check_purity.sh`: no Flutter imports |
| Presentation — widgets | `app/` | `check_purity.sh`: no hex literals |
| **data ✗ presentation** | a package cannot import Flutter, so it cannot reach the UI | CI |

**No layer is renamed and no state-management package is adopted.** Introducing BLoC or Riverpod across 46
built screens would be a large refactor with no behavioural gain, weeks before a pilot. The diagram's one
genuinely missing box is **Presentation Logic Holders**, and §3 supplies it with what the repo already has.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Components are built before the screens that use them; a lane never invents one ⟦tests: F1-13-16 @M6⟧
- The queued atoms of `design-system.md` §6 — toast, countdown, progress meter, provisional badge,
  held-row state, cooldown/disabled, plus `RkLoader` and `RkSkeletonRow` — are built into
  `app/lib/shared/widgets/` **as their own slice**, ahead of the screens that consume them. ⟦tests: F1-13-16 @M6⟧
- **A screen lane that needs a component which does not exist stops and reports it.** It does not create
  one in `features/*/widgets/`. This is the same rule as `⚠️ SPEC:` for an ambiguous spec: the conservative
  action is to report, not to invent. ⟦tests: n/a — lane-prompt contract, enforced by §5⟧
- A feature-local widget remains legitimate when it is genuinely one screen's composition of shared atoms.
  The test is reuse: if a second screen would want it, it belongs in `shared/`. ⟦tests: n/a — review criterion⟧

### 2. Two form factors, one set of screens ⟦tests: F1-13-17⟧
- **iPad and Android tablets are supported.** `TARGETED_DEVICE_FAMILY = "1,2"` stays, and is now a
  decision rather than the Flutter default it has been since M0. ⟦tests: n/a — build configuration⟧
- **Breakpoints** (Material 3's canonical set, which Flutter aligns to): `compact` < 600 ·
  `medium` 600–839 · `expanded` ≥ 840. They live in `tokens.json` so code and canvas cannot drift.
  Portrait iPads measure roughly 744–834pt and are therefore **medium**; landscape iPads are
  **expanded**. ⟦tests: F1-13-17⟧
- **The width rule is two-tier, and this is the ruling that matters most.** Reading and form surfaces are
  capped to a readable measure and centred. **The professional surfaces are not** — the A/C statement,
  trial balance and reports take the width they are given, because `ਨਾਮੇ | ਜਮ੍ਹਾਂ | ਬਾਕੀ` is a real data
  table and `design-system.md` §3.1 rule 8 already requires it to reflow wide. Capping everything would
  waste a tablet on exactly the surfaces a bookkeeper bought one for. ⟦tests: F1-13-17⟧
- **Navigation**: the bottom tab bar holds at compact and medium; at **expanded** the shell presents a
  `NavigationRail` instead. This amends `13 §3.1`, which describes one navigation model. ⟦tests: F1-13-17⟧
- The shell applies the width rule, so **no screen knows about breakpoints**. A screen that reads a
  breakpoint directly is a defect. ⟦tests: F1-13-17⟧
- **Scope: this ADR rules the layout base only.** Two-pane compositions (A/C index + statement, Inbox +
  review card, Members + detail) are a later milestone and need tablet artboards; they are additive on top
  of this foundation and invalidate none of it. ⟦tests: n/a — scope note⟧

### 3. The shell is tested through, not around ⟦tests: F1-13-19⟧
- Every tab root is rendered **inside the real `RkShell`** and asserted to have a non-zero content region
  with its content on stage. No such test existed, which is why `RkTabBar` — taking the full screen height
  as `bottomNavigationBar` and leaving every tab's body at zero — shipped in M5 and survived two green
  gates and a nightly RLS run. ⟦tests: F1-13-19⟧
- Screen tests pump screens directly and always will; that is correct and fast. This adds the one
  integration layer above them, at the shell seam where nothing was looking. ⟦tests: F1-13-19⟧
- `rkStrictViewport` (`app/test/shared/test_app.dart:309`) flips to `true` when the last of the 20
  unconverted files lands, so a zero-sized tree becomes fatal rather than a printed warning. Note it would
  **not** have caught the `RkTabBar` defect — that tree's `MediaQuery` is a healthy 800×600 — which is why
  §4's test is a separate instrument, not a tightening of that one. ⟦tests: F1-13-19⟧

### 4. Uniformity is machine-checked, not reviewed ⟦tests: F1-10-17 @M6⟧
- `check_purity.sh` gains, for `app/lib/features` only: **no raw numeric `EdgeInsets`/`SizedBox`
  dimensions** (spacing comes from `RkSpace`) and **no `TextStyle(` construction** (type comes from the
  theme's ramp). Colour is already covered. ⟦tests: F1-10-17 @M6⟧
- **These will have false positives** — `SizedBox(height: 1)` for a hairline is legitimate — so the rule
  ships with an allowlist and is tuned against the existing tree before it blocks. A check that cries wolf
  gets suppressed, which is worse than no check. ⟦tests: F1-10-17 @M6⟧
- CI **reports** every new file under `app/lib/features/*/widgets/`, so a lane inventing a component is
  visible at the gate rather than found a milestone later. Reported, not blocked: §1's escape hatch is
  legitimate and this is how it stays visible. ⟦tests: F1-10-17 @M6⟧

## Consequences
- **`design/`:** `design-system.md` gains a breakpoints + width-rule section and the rail threshold;
  `tokens.json` gains `layout.breakpoint.*` and the measure cap, regenerated into `tokens.css`/`.dart`.
  **No per-screen tablet artboards are needed for this ADR** — one set of rules, not 23 canvases.
- **`app/`:** `RkShell` applies the width rule and swaps to `NavigationRail` at expanded; `RkTabBar`
  bounds its own height; `shared/widgets/` gains the §1 atoms; the tablet viewport joins `rkPhone360` /
  `rkPhone375` in the test matrix.
- **`docs/`:** `13 §3.1` amended for the second navigation model.
- **`scripts/`:** `check_purity.sh` gains §4's rules; `ci.sh` reports feature-local widgets.
- **Sequencing:** components + shell + rail are **one slice**, because all three open `shared/` and the
  shell is opened once, not three times.
- **No 🔒 line is contradicted** — `13 §3.1` is amended by §2 and every other ruling fills a gap — so **no
  test needs `@Skip`** (ADR 2026-09-05i §4).
- **Milestone:** M5/M6, before the pilot.

## Open ⚠️
- **§2's width rule reaches only what passes through `RkShell` — a gap in this ADR, found by lane T2 on
  14 Sep 2026.** `/entry` and the detail screens pushed on the **root** navigator (the A/C statement among
  them, via `LedgerPaths.statementOf`) never enter the shell, so on a tablet they render uncapped at full
  width. That is accidentally *right* for the statement — a professional surface, which §2 exempts anyway —
  and *wrong* for entry and the forms. Closing it needs a wrapper in `main.dart`'s `MaterialApp.router`
  builder or a route-table change; T2 correctly declined a half-fix that capped only the routes it owned,
  which would have been worse than none. ⟦tests: F1-13-17⟧
- **`RkReadablePane` caps the whole branch content, app bar included**, so a capped screen on a tablet is a
  600-wide column carrying its own app bar rather than full-bleed chrome over a capped body. That is the
  literal reading of §2 and the only thing achievable at the shell seam; worth revisiting when tablet
  artboards exist. ⟦tests: n/a — design question⟧
- **`scripts/gen_tokens.dart` has no `layout` emitter**, so `RkLayout` mirrors `tokens.json` by hand.
  Mitigated rather than trusted: `F1-13-17`'s first case reads `tokens.json` and asserts every value
  against `RkLayout`, so drift fails CI. A `scripts/` lane should add the emitter and delete the mirror. ⟦tests: F1-13-17⟧
- **`readableMeasure = 600` is proposed, not ruled** (see below) — 568px of text after gutters, ~75
  characters at body 16 Mukta, and set equal to the medium floor so the cap provably never engages on a
  phone. The reasoning is written into `tokens.json`, `layout.dart` and `design-system.md` §4.2 so it can
  be argued with. ⟦tests: F1-13-17⟧
- **Presentation logic has no shared pattern, and this ADR does not rule one.** The app carries 46
  `StatefulWidget`s in `features/` against 5 `ChangeNotifier`s, three of them in `shared/`, so each lane
  invents its own state handling — the same root cause as §1, and it has already cost real time (U2a died
  twice on a teardown deadlock from a hand-rolled stream combinator awaiting its own cancels). A pattern
  exists in the repo to adopt — `ChangeNotifier` + an `InheritedWidget` scope, as `HomeScopeController`,
  `AppSettings` and `ReviewQueueScope` already do — and it needs no package. **Recorded as an open item,
  not ruled:** it was drafted as a ruling on 13 Sep from a Clean Architecture reference image the owner had
  sent as an *example*, not a directive, and was cut back the same day. The repository's layering is
  justified by its own domain (02 ledger · 03 storage · 04 crypto · 05 sync) and is not to be reshaped to
  match an external diagram.
- **The readable-measure value is not set here.** It wants one number (a character count or a dp cap) in
  `tokens.json`, proposed in code and ratified the 5 Sep way, once it can be seen against the statement at
  a real tablet width.
- **Three canvas-vs-spec conflicts from the M7 ceremony lane are still unruled** and they block any claim
  of visual uniformity, because `design/` and the numbered specs rank **equal** (CLAUDE.md § Precedence):
  the S9.2 code alphabet (canvas draws alphanumeric, `04 §6.1` 🔒 says 8 decimal digits), S9.4's wording,
  and whether the ceremony is mutual. Uniformity is undefined while two equal sources disagree.
- **Android tablet** has no declaration to change — it runs on tablets regardless — so §2 covers it by the
  same breakpoints, but it has no equivalent of `TARGETED_DEVICE_FAMILY` to record the decision in.
