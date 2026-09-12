# CLAUDE.md — standing conventions for this repository

You are building **Rukka Folio** — a zero-knowledge, offline-first ledger app for individuals, joint families, and their businesses. The `/docs` folder is the source of truth; **when code and docs disagree, the docs win** — fix the code or PR the doc in the same commit. Lines marked 🔒 in docs are owner-locked: never change behavior they specify without asking.

## Precedence 🔒 (when two documents disagree) ⟦tests: n/a — precedence rule, not behaviour⟧

`docs/` is not flat. Resolve conflicts in this order, highest first:

1. **`docs/decisions/` ADRs** — dated; the newest ADR on a topic beats everything below.
2. **Numbered specs `00`–`13`** (13 = UX architecture, normative) and **`design/`** — `design-system.md` and `DESIGN-PACK.md` carry 🔒 decisions and rank with the numbered specs on visual and interaction matters; `design/tokens/tokens.json` is the sole source for token values.
2b. **Former item 2:** numbered specs — normative. Within them, the doc that *owns* the topic wins: 02 owns ledger semantics, 03 owns storage, 04 owns crypto, 05 owns sync, 06 owns identity, 07 owns screens, 11 owns brand. A passing mention in another doc never overrides the owner.
3. **`docs/reference/`** — behavioural reference for the ledger engine (see *Accounting authority* below), but the class model, verbs and invariants of 02 govern how it is represented.
4. **`docs/requirements-architecture.md`** — ⛔ **background only, non-normative.** It predates zero-knowledge and post-then-review and **loses every conflict**. See its banner for the list of superseded sections. Never implement from it.

If two sources at the same level genuinely conflict, stop and ask — leave a `⚠️ SPEC:` comment, do not pick one.

## Layout
```
/CLAUDE.md /README.md /PLAN.md(build tracker — read first) /pubspec.yaml(workspace) /.github/workflows(ci.yml…)
/docs            00-vision … 13-ux-architecture + requirements-architecture; docs/decisions/ = ADRs (one dated file per 🔒 change)
/app             Flutter UI only: lib/features/*, lib/shared/, lib/l10n/(app_en.arb, app_pa.arb, app_hi.arb), assets/fonts/(Mukta, Mukta Mahee; fallback Noto Sans — 11 §4.4)
/packages        pure Dart, NO Flutter imports (CI-enforced):
                 core_ledger(02) · core_crypto(04) · data(03: Drift+SQLCipher+projector) · sync_engine(05)
/server/supabase migrations/(incl. all RLS) · functions/(sync-push, sync-pull, sync-meta, auth-challenge, billing-webhook) · tests/rls/
/server/admin    internal panel (M13)
/testing         harness/(two-client rig, 09 §1; created at M2, ADR 2026-09-05i §7) · fixtures/(SYNTHETIC sync/UI data only — never real entries; accounting goldens stay in docs/reference/) · goldens/(export byte-comparisons, suite F3)
/design          design-system.md + tokens/ (tokens.json = single source → tokens.css, tokens.dart; UI code uses tokens ONLY — hex literals in widgets are review-blocking) · mockups, prototype exports, icons
/.claude         agents/(lane tiers — model+effort per lane) · workflows/(lanes.js, gate-run.js) · skills/ · hooks/ · bin/(wf-spend.sh, lane-status.sh) · lane-reports/(git-ignored, durable lane output)
/scripts         ci.sh (the gate) · check_strings.dart (fails on missing EN/PA/HI key, placeholder drift, forbidden jargon) · check_purity.sh (no Flutter in packages; no I/O/clock/RNG in core_*; no hex literals in app) · gen_tokens.dart (tokens.json → tokens.css/.dart; --check in CI) · gen_l10n_arb.dart (dotted ARB keys → identifier keys for gen_l10n)
```
Trunk-based on protected `main`; tags at milestone exits (`m1-ledger-core`); secrets only in CI secrets + local `.env` (never committed).

## Accounting authority 🔒 ⟦tests: A-ref-1, A-ref-2, A-ref-3, A-ref-4, A-ref-5, A-ref-6, A-ref-7⟧
`docs/reference/financial-accounting-standards.md` + `docs/reference/worked-examples/` (five entity types, eight books, 185 vouchers, machine-verified trial balances) are the **behavioural reference for the ledger engine**. When 02 and the worked examples appear to disagree, stop and ask — do not guess. On bookkeeper sign-off these examples become golden fixtures: the engine must reproduce every ledger and trial balance exactly (09, suite A).

## Non-negotiable rules
1. **Money is integer paise** (`int`/`BIGINT`). Any float touching money is a bug.
2. **Append-only ledger.** Never UPDATE/DELETE an envelope or posted entry; amend/reverse per 02 §5. Server role has no UPDATE/DELETE grant on `envelopes`.
3. **The projector is a pure function** of (ordered envelopes, certified vectors). It may not read clock, network, locale, or settings (03 §3.3). More broadly: `core_ledger` and `core_crypto` contain no Flutter, no I/O, no `DateTime.now()`, no `Random()` — clock and RNG are always injected.
4. **No plaintext financial data** in logs, crash reports, analytics, notifications, or test fixtures committed to the repo. Scrub before writing.
5. **Never wrap a book key to an unverified fingerprint** (04 §8.2). The type system should make this hard: verified keys are a distinct type.
6. **Unknown-field round-trip:** preserve JSON fields you don't understand when amending objects (03 §3.3.4).
7. **All crypto via libsodium** (`sodium_libs`). No hand-rolled primitives, no `dart:math` randomness, zeroize secrets after use.
8. Every user-facing string goes through ARB with EN, PA and HI entries (01 §1.8); CI fails on missing keys. Respect the forbidden-jargon list (01 §1.3).
9. **Two vocabularies, one engine:** consumer surfaces say *Money in / Money out*; professional surfaces (A/C statement, trial balance, exports) say true ledger Dr/Cr. The engine's posting logic never bends to the display language (02 §10).
10. UI rules of 07 §1 (8-second entry, no dead ends, color-never-alone) apply to every screen you build.
11. **Never assume, never guess** 🔒 (owner-directed, 9 Sep 2026) ⟦tests: n/a — process rule, not behaviour⟧. Verify before you assert — read the
    file, run the test, check the tool's own contract. State findings with the evidence attached
    (`accounts.dart:99`, `02 §7.1`, the worked example's row), so a claim can be checked rather than
    trusted. This binds three cases that all failed on 9 Sep: **the code** — *"the engine has no Drawings
    account"* was wrong, `SystemRole.drawings` had been declared and unused since day one; **your own
    limits** — *"I can't do that from here"* was asserted without trying, when node, the build script and
    a write API were all present; and **the specs** — an ADR ruling split Capital from Opening Balance
    without opening `docs/reference/`, where both worked examples name the single account
    `Opening Balance / Capital A/c`. If you cannot verify something, say so plainly and say what would
    settle it; an honest *"not checked"* costs a sentence, a confident wrong answer costs a lane. This
    extends, and does not replace, the two existing stop-and-ask rules: § Accounting authority (02 vs the
    worked examples) and § Workflow (ambiguous spec → conservative reading + `⚠️ SPEC:`).

## Workflow
- Tests first for `core_ledger` and `core_crypto` — take them from 09 (suites A/B) and the doc excerpts before implementing.
- **Traceability (ADR 2026-09-05i §1):** every test name starts with its id (`A-02-9 …`); every 🔒 line you write or touch in `docs/` ends with `⟦tests: id, id⟧` (or `⟦tests: n/a — reason⟧`). `scripts/check_coverage.dart` enforces this (warn-only until M4).
- **Supersession (ADR 2026-09-05i §4):** when a doc change flips behaviour a green test asserts, mark that test `@Skip('superseded by ADR <id> §<n>; re-lands at M<n>')` in the same commit — never leave a test green against a superseded rule.
- One milestone slice per session (10); begin by reading the referenced spec sections; end with tests green and docs updated if any decision was made.
- Commits small and scoped; commit message references the milestone (e.g. `M1: verb postings + invariants`).
- **Every session ends with a `CHANGELOG.md` entry** (newest first, dated, milestone-tagged: Added / Changed / Decided / Open / Commits). Write it before handing files to the owner to commit; fill the commit hashes in the next session. Git holds the diff — the changelog holds the *what* and *why*.
- If a spec is ambiguous, prefer the more conservative reading and leave a `⚠️ SPEC:` comment plus a note to the owner — do not silently invent behavior.

## Session economy 🔒 (owner-directed, 7 Sep 2026; restructured 8 Sep 2026; tiers + throughput 12 Sep 2026) ⟦tests: n/a — process rule, not behaviour⟧
- **Start with `PLAN.md`** §0 + the current phase; not CHANGELOG, not whole specs. Read spec *sections*: `grep -n "^## \|^### " docs/<n>.md` → `sed -n 'a,bp'`.
- **Milestone work runs as `/lane`:** one orchestrator session that holds PLAN rows and lane reports and nothing else; lanes are subagents owning **disjoint directories**. `/lane` runs at most **5** lanes per run and then **stops**.
- **Fill the session 🔒 (owner-directed, 12 Sep 2026; ADR 2026-09-12b).** The old rule was one lane per session, then `/clear`. It left most of the budget unspent — 12 Sep closed a two-lane session at **29 %**. A session now runs **round after round** — `/lane` → `/gate` → `/lane` → … — taking as many milestone slices as the remaining budget allows, and closes with `/close` when the budget is genuinely low or the phase is done. Disjointness is still per *run*, never per session: lanes inside one round must own disjoint directories, but the next round may take the directories the last one released. ⟦tests: n/a — process rule, not behaviour⟧
- **`/gate` is a separate invocation** — never in the same run as the lanes. A session-limit kill must cost one lane, not a phase.
- **Tiers are structural, not remembered.** Model and effort live in `.claude/agents/*.md`; a lane is chosen by naming an agent, never by passing a model:

  | Agent | Model · effort · turns | For |
  |---|---|---|
  | `lane-mech` | haiku · low · 60 | ARB drafts, l10n parts, fixtures, codegen, token regen |
  | `lane-ui` | **opus · medium · 180** | **repeat** screens by S-id (13 §3.2) on a settled pattern, F1 widget tests |
  | `lane-ui-hard` | **opus · high · 180** | new design-system components, foundation (theme/shell/nav), 200% · 360×800 layout defects, state-machine screens (S10, S15, S7) |
  | `lane-server` | **opus · high · 180** | migrations + RLS, edge functions, hostile-query tests |
  | `lane-sync` | **opus · high · 220** | `sync_engine`, ordering/conflict/trust logic, projector |
  | `lane-core` | fable · high · 240 | ⚠️ **escalation only** — `core_*` behaviour, 🔒/ADR reasoning, suite-A goldens |

  **Every build lane is Opus; never haiku on tests** 🔒 (owner-directed, 8 Sep 2026 and 12 Sep 2026; ADRs 2026-09-08b, 2026-09-12b) ⟦tests: n/a — process rule, not behaviour⟧. Orchestration, integration and review are Opus, and since 12 Sep so is **every** build lane — `lane-ui` moved off sonnet, and `lane-server`/`lane-sync`/`lane-ui-hard` moved to **high** effort. `lane-server` is adversarial security, not CRUD; `lane-sync` is ordering and trust, where a subtle error is a green test over a wrong ledger. The UI split survives the model merge as an **effort** split: settled patterns on `lane-ui` (medium), foundation-shaped and multi-state screens on `lane-ui-hard` (high). `lane-mech` stays haiku because transcription from a source of truth is the one job a small model does safely. **`lane-mech` never authors a test** — in this repo the test *is* the specification (tests-first from 09, ids blocking under `check_coverage --strict`), so test authoring belongs to the lane that owns the behaviour, minimum sonnet. **Split for scope; caps are a backstop** 🔒 (owner-directed, 10 Sep 2026 and 12 Sep 2026; ADRs 2026-09-10, 2026-09-12b) — splitting is still the first answer when a lane simply has too many screens in it (§M5: ~2–3 screens, ~1 where a screen is built from scratch), but a cap is no longer a ceiling to design around: 10 Sep doubled every tier after M5-U2a died twice on a verification toll and a slow test, and **12 Sep doubled them again so that a lane finishes rather than dies** — a cap should never be the reason a slice comes back partial. If a lane dies even at these caps, read the transcript before raising it again: at 180 turns the cap is not the diagnosis.

  **No lane starts on `lane-core`.** Fable 5.1 resets weekly on Sunday and is entered only when a lower tier reported a blocker it could not resolve — and only with the owner's say-so. Budget: **2 fable runs per week**. Check before spending: `.claude/bin/wf-spend.sh`.
- Every build lane **and the gate** runs `permissionMode: acceptEdits` (no stalling on edit prompts mid-run) and are denied `WebSearch`/`WebFetch` (every spec is local). Because edits are auto-accepted, **the disjoint-directory rule is enforced only by the lane prompt** — naming each lane's directories precisely is a correctness requirement, not tidiness.
- **Lane reports are durable.** A lane writes `.claude/lane-reports/<milestone>-<key>.json` as soon as it has anything to record and keeps it current, with `complete: false` until the task is wholly done; `/lane` skips only the complete ones and re-runs the rest. Every lane carries a `maxTurns` cap, so a partial report is a normal outcome — that is what makes an interrupted run cheap: the work survives even when the run does not.
- Lanes return JSON, never run `ci.sh`, never read whole docs, never re-read files after editing. The post-edit hook formats/analyzes/purity-checks — never repeat it by hand. Tests by file while working; package once at lane end; the gate once per phase.
- **End every session with `/close`:** `/plan` (✅ only for ids green in the gate) → `/changelog` → commit message for the owner → **`/clear`**. Chain rounds until the budget is low — but `/close` once, at the end, not after every round. Do not spawn a lane for work under ~30 minutes, or for what a `grep` answers.

## Commands
- Workspace: `dart pub get` at the root resolves every package (pub workspace; one lockfile).
- App: `flutter test` · `flutter build ios` · `dart run build_runner build -d` (Drift codegen) · `flutter analyze`
- Tokens / strings: `dart run scripts/gen_tokens.dart` after editing tokens.json · ARB keys stay dotted (`screen.element.state`); `scripts/gen_l10n_arb.dart` derives the identifier-keyed copies gen_l10n needs (`app.name` → `appName`), run by ci.sh
- Server: `eval "$(scripts/rls_db.sh)"` builds the RLS database from a local Postgres (no Docker — the migrations are
  plain Postgres + `pgcrypto`) and exports `RF_TEST_DB_URL`; then `cd server && deno task test` runs the hostile-query
  suite. `supabase db reset` remains the Docker path. · `deno test server/functions`
- Build: `/lane <keys>` (≤5 lanes per run, then stops) · `/gate [lane]` (separate run) · `/close` (plan → changelog → clear)
- Budget / recovery: `.claude/bin/wf-spend.sh` (week's token spend; `--all` for every run) · `.claude/bin/lane-status.sh` (which lanes landed, which are only part-way)
- Full gate: `./scripts/ci.sh` (push lane by default; `LANE=nightly|rc|release` selects the others — 09 §preamble, ADR 2026-09-05i §2) · `dart run scripts/check_coverage.dart` (🔒→test ids; warn-only until M4)
