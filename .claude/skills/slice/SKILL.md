---
name: slice
description: Start a milestone slice (M<n>) the CLAUDE.md way — read the owning spec sections and the newest ADRs on the topic, list the 09 test ids to write first, then implement tests-first. Use at the start of any coding session on packages/ or app/.
---

# /slice $ARGUMENTS

Start one milestone slice. `$ARGUMENTS` is the milestone (`M2`) optionally followed by a focus
(`M2 projector held state`). One slice per session (CLAUDE.md § Workflow).

## 1. Orient (read, do not edit)
1. `docs/10-roadmap.md` — the row for this milestone: scope, exit criterion, the ADRs it names.
2. The **owning spec** for the slice topic (02 ledger, 03 storage, 04 crypto, 05 sync, 06 identity,
   07 screens, 13 UX architecture). Read the sections the roadmap row cites, not the whole doc.
3. `docs/decisions/` — every ADR the roadmap row names, newest first. **ADRs beat the specs**
   (CLAUDE.md § Precedence). Note any ⚠️ items left to the owner; do not resolve them silently.
4. `docs/09-acceptance-tests.md` §2 — the suite(s) this milestone exits on, and the test ids
   (`A-02-9`, `D-05b-3` …) that belong to this slice. Also grep the ADRs for `⟦tests: …⟧` markers
   on the 🔒 lines you will implement — those ids are your test list.
5. `CHANGELOG.md` top entry — what the last session left open.

## 2. Plan (one short list, then go)
- Tests to write first, by id, with the doc line each asserts.
- Files to touch. `core_ledger` / `core_crypto` are pure: no Flutter, no I/O, no `DateTime.now()`,
  no `Random()`; money is integer paise; ledger is append-only; projector is a pure function.
- Any 🔒 line whose behaviour this slice changes → that needs an ADR, not code. Stop and say so.

## 3. Implement
- Test names start with their id: `test('A-02-9 …')`.
- If a doc change made an existing green test wrong, `@Skip('superseded by ADR <id> §<n>; re-lands at M<n>')`
  in the same commit — never leave a green test asserting a superseded rule.
- Unknown JSON fields round-trip; verified keys are a distinct type; all crypto via `sodium_libs`.
- Every user-facing string → ARB with EN, PA, HI.
- The post-edit hook runs `dart format`, `dart analyze` and `check_purity.sh` after each edit; fix what
  it reports before moving on.

## 4. Close the slice
- `/gate` (push lane) green.
- `/changelog` entry written (the Stop hook will insist).
- If any decision was made, `/adr` first, then cross-refs in the affected specs.
- Report: files changed, tests added (ids), anything ⚠️ for the owner, suggested commit message
  (`M<n>: <what>`). The owner commits — never run `git commit`.
