---
name: goldens
description: Run only the worked-example golden tests in core_ledger (suite A goldens — five entity types, eight books, 185 vouchers) and explain any mismatch against docs/reference. Use after touching posting logic, projection, or the reference examples.
---

# /goldens $ARGUMENTS

The goldens are the **behavioural reference for the ledger engine** (CLAUDE.md § Accounting
authority): `docs/reference/financial-accounting-standards.md` + `docs/reference/worked-examples/*.md`,
parsed by `packages/core_ledger/test/golden_worked_examples_test.dart`.

```bash
cd packages/core_ledger && dart test test/golden_worked_examples_test.dart --reporter expanded $ARGUMENTS
```
(`$ARGUMENTS` may carry `--name '<book title>'` to narrow to one book.)

## Reading a failure
Per failing test, report: book, ledger account, the voucher or row, expected vs actual (integer paise,
show both as ₹ too), and which of these it is:
1. **Engine bug** — 02 and the example agree, the code does not. Fix the code; add or tighten a unit
   test with its id.
2. **Spec vs reference disagreement** — 02 says one thing, the worked example another. **Stop and
   ask the owner.** Do not patch either. Leave a `⚠️ SPEC:` comment where the test would change and
   put the item in the changelog **Open** list. Known reconciliations pending sign-off are listed in
   `docs/reference/accounting-audit-errata.md` (partnership paise split, ₹1,354/₹1,355 interest) — check
   there first.
3. **Parser drift** — the markdown table shape changed. Fix the parser, not the fixture.

## Governance (ADR 2026-09-05i §3)
The examples are *provisional* until bookkeeper sign-off (README front-matter `approved_by` /
`approved_on` / `content_hash`). After approval any figure change needs an ADR. Never edit a worked
example to make a test pass. Fixtures under `/testing/fixtures` are synthetic only — real-looking
entries never go there.

Report green/red, the classification above for each red, and the next step. Owner commits.
