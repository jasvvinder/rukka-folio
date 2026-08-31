# CLAUDE.md — standing conventions for this repository

You are building **Rukka Folio** — a zero-knowledge, offline-first ledger app for individuals, joint families, and their businesses. The `/docs` folder is the source of truth; **when code and docs disagree, the docs win** — fix the code or PR the doc in the same commit. Lines marked 🔒 in docs are owner-locked: never change behavior they specify without asking.

## Precedence 🔒 (when two documents disagree)

`docs/` is not flat. Resolve conflicts in this order, highest first:

1. **`docs/decisions/` ADRs** — dated; the newest ADR on a topic beats everything below.
2. **Numbered specs `00`–`13`** (13 = UX architecture, normative) and **`design/`** — `design-system.md` and `DESIGN-PACK.md` carry 🔒 decisions and rank with the numbered specs on visual and interaction matters; `design/tokens/tokens.json` is the sole source for token values.
2b. **Former item 2:** numbered specs — normative. Within them, the doc that *owns* the topic wins: 02 owns ledger semantics, 03 owns storage, 04 owns crypto, 05 owns sync, 06 owns identity, 07 owns screens, 11 owns brand. A passing mention in another doc never overrides the owner.
3. **`docs/reference/`** — behavioural reference for the ledger engine (see *Accounting authority* below), but the class model, verbs and invariants of 02 govern how it is represented.
4. **`docs/requirements-architecture.md`** — ⛔ **background only, non-normative.** It predates zero-knowledge and post-then-review and **loses every conflict**. See its banner for the list of superseded sections. Never implement from it.

If two sources at the same level genuinely conflict, stop and ask — leave a `⚠️ SPEC:` comment, do not pick one.

## Layout
```
/CLAUDE.md /README.md /pubspec.yaml(workspace) /.github/workflows(ci.yml…)
/docs            00-vision … 13-ux-architecture + requirements-architecture; docs/decisions/ = ADRs (one dated file per 🔒 change)
/app             Flutter UI only: lib/features/*, lib/shared/, lib/l10n/(app_en.arb, app_pa.arb, app_hi.arb), assets/fonts/(Mukta, Mukta Mahee; fallback Noto Sans — 11 §4.4)
/packages        pure Dart, NO Flutter imports (CI-enforced):
                 core_ledger(02) · core_crypto(04) · data(03: Drift+SQLCipher+projector) · sync_engine(05)
/server/supabase migrations/(incl. all RLS) · functions/(sync-push, sync-pull, sync-meta, auth-challenge, billing-webhook) · tests/rls/
/server/admin    internal panel (M13)
/testing         harness/(two-client rig, 09 §1) · fixtures/(SYNTHETIC data only — never real entries) · goldens/(export byte-comparisons)
/design          design-system.md + tokens/ (tokens.json = single source → tokens.css, tokens.dart; UI code uses tokens ONLY — hex literals in widgets are review-blocking) · mockups, prototype exports, icons
/scripts         ci.sh (the gate) · check_strings.dart (fails on missing EN/PA/HI key)
```
Trunk-based on protected `main`; tags at milestone exits (`m1-ledger-core`); secrets only in CI secrets + local `.env` (never committed).

## Accounting authority 🔒
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

## Workflow
- Tests first for `core_ledger` and `core_crypto` — take them from 09 (suites A/B) and the doc excerpts before implementing.
- One milestone slice per session (10); begin by reading the referenced spec sections; end with tests green and docs updated if any decision was made.
- Commits small and scoped; commit message references the milestone (e.g. `M1: verb postings + invariants`).
- If a spec is ambiguous, prefer the more conservative reading and leave a `⚠️ SPEC:` comment plus a note to the owner — do not silently invent behavior.

## Commands
- App: `flutter test` · `flutter build ios` · `dart run build_runner build -d` (Drift codegen) · `flutter analyze`
- Server: `supabase db reset` (applies migrations + RLS tests) · `deno test server/functions`
- Full gate: `./scripts/ci.sh` (suites A–E + lint + string check)
