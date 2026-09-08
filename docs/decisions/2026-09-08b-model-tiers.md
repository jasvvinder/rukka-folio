# ADR 2026-09-08b — Model tiers: Opus at the ends, sonnet for settled patterns, never haiku on a test

The tier table of CLAUDE.md § Session economy (owner-directed, 7 Sep 2026) put `lane-ui` and
`lane-server` on sonnet, `lane-mech` on haiku for "fixtures, codegen and file moves", and reserved
fable for `lane-core`. On 8 Sep 2026 the owner proposed dropping sonnet from development
altogether — Opus 5 for building UI and business logic, fable for complex logic and architecture.

The week's own telemetry argues against the blanket form of that, and the session recorded why
before adopting anything. Of seven runs since 6 Sep, three did not complete; **none** failed on
model quality. They failed on scope against `maxTurns`: the 8 Sep run gave `U1/U2/U3` 10–16 screens
apiece against a 40-turn cap; a re-scoped 3-screen `U3a` still died mid-edit because two of its
three screens were written from scratch. Meanwhile `U1a` — sonnet, correctly scoped at one screen
plus three tests — completed, and surfaced three real pre-existing defects on `main` (a missing
`shared/theme.dart` import that made S0.0 and S0.1 uncompilable, and a 200% text-scale overflow).
Tiering up without fixing scope buys more expensive cap deaths, not better screens.

Two further facts shaped the split. Rukka Folio's *foundation* — theme, router, shell, seams — is
already built and green (85 tests), so the work that most deserves Opus at the start of a UI
pipeline is done; what remains in M5 is reuse of a settled feature-folder + tokens + ARB-trio +
one-F1-test pattern. And the integration seat — composing feature routes, reviewing lane output —
is already Opus, because it is the orchestrator's own `/lane` session.

Owner ruling, 8 Sep 2026, with the test clause added by the owner directly: *writing tests, testing
and automation testing must not be done on haiku.*

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. No haiku on any test ⟦tests: n/a — process rule, not behaviour⟧
`lane-mech` **never writes, edits or deletes a test**, and no test, test harness or test-automation
work is dispatched to haiku. In this repo a test is the specification: tests come first (CLAUDE.md
§ Workflow), they are taken from 09, and every id carries traceability weight that
`check_coverage --strict` blocks on since M4. Test authoring belongs to the lane that **owns the
behaviour**, minimum sonnet. Test *fixtures* under `testing/fixtures/` stay mechanical work; the
tests that consume them do not. `lane-mech` that finds itself needing to touch a test stops and
reports it in `open`.

### 2. The UI tier splits in two ⟦tests: n/a — process rule, not behaviour⟧
`lane-ui` stays **sonnet** and takes repeat screens on a settled pattern. A new `lane-ui-hard`
runs **opus** and takes work that is not a reuse: new design-system components, foundation-shaped
work (theme, shell, navigation), layout defects at 200% text scale or 360×800, and screens carrying
a real state machine per 13 §4.3 — S10 month/year close, S15 app lock and cooldown, S7 statement
import mapping. A `lane-ui-hard` lane that discovers its screen is an ordinary repeat says so in
`open`; it should not have cost that tier.

### 3. `lane-server` moves to opus ⟦tests: n/a — process rule, not behaviour⟧
RLS policies and hostile-query tests are adversarial security work on a zero-knowledge system,
where a plausible-looking miss is a silent data-exposure bug and "it passed" is not evidence. That
is a different activity from the CRUD data-layer work sonnet is well suited to, and it earns the
tier regardless of how settled the surrounding pattern is.

### 4. Tier up, never cap up ⟦tests: n/a — process rule, not behaviour⟧
Raising a lane's model never raises its `maxTurns`. When work will not fit the cap, the work is
split (§M5: ~2–3 screens, and ~1 where a screen is built from scratch). This ADR does not change
any cap.

### 5. Fable's remit is unchanged ⟦tests: n/a — process rule, not behaviour⟧
`lane-core` remains **escalation only** at 2 runs per week; no lane starts there. The owner's
"fable for complex business logic and architecture" is already what `lane-core` is for, so the
remit needed no widening — only the reminder that spend stood at 5 runs against 2 budgeted in the
week to 8 Sep. Widening entry without raising the budget would have made the limit decorative.

## Consequences
- `.claude/agents/lane-ui.md` sonnet (unchanged in the end), `lane-server.md` → opus,
  new `lane-ui-hard.md` → opus, `lane-mech.md` gains the no-tests bar.
- Tier tables in CLAUDE.md § Session economy and `.claude/skills/lane/SKILL.md` §1.4 restated;
  the two must agree with the agent frontmatter, which is the only real source (tiers are
  structural, not remembered).
- `gate` stays sonnet · low: it is deliberately forbidden from changing logic or tests, and ruling 1
  is satisfied. Its effort is *not* raised here, but see the open item below.

## Open ⚠️
- `flutter analyze` run bare from `app/` reported `No issues found! (ran in 0.2s)` while
  `flutter analyze lib/features/ledger/` reported **64 errors** on the same tree. If `scripts/ci.sh`
  shells out to the bare form, the gate can pass over non-compiling code. This is a gate-integrity
  defect independent of model tiers and is not fixed by this ADR.
