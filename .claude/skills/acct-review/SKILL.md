---
name: acct-review
description: Run the accounting panel (CA, munim, entity specialist, auditor) over an accounting document, a reference book, or a book the app produced; every finding is cross-examined by another panel member before it reaches the owner. Use to review docs/accounting before the bookkeeper (PLAN-209), and to test app output against the reference books.
---

# /acct-review $ARGUMENTS

`$ARGUMENTS` takes one of these forms:
- `docs <01|02|03|04|05|all> [focus…]` reviews the accounting rules.
- `book <individual|joint-family|shop|partnership|trust|all> [focus…]` reviews a finished reference book.
- `output <path…> [--golden <reference book>] [focus…]` tests a book the app produced: an export, a printout or a CSV.

## The panel (`.claude/agents/acct-*.md`, all read-only)
| Agent | Discipline | Default for |
|---|---|---|
| `acct-ca` | Chartered Accountant (ICAI): standards, textbooks, report formats; checks every citation with WebFetch on ICAI/NCERT | docs, book, output |
| `acct-munim` | Senior bookkeeper: real practice, plain words vs Dr/Cr, workability, vocabulary | docs, book |
| `acct-entities` | Partnership, joint family, trust/NPO, landlord, related books | docs, book |
| `acct-auditor` | Re-derives every figure; compares app output with its reference book | book, output |

The panel is **not** the bookkeeper sign-off of PLAN-209. It runs before that review and makes it shorter. It never replaces it.

## Run
1. **Budget first.** Run `.claude/bin/board.sh`. If today's ceiling cannot hold the run, say so and stop. Cost per run has not been measured yet: read `wf-spend.sh` after the first run and record the figure here.
2. **Resolve the files.**
   - `docs 03` → `docs/accounting/03-entities.md`, and so on. For `all`, run once per document, never all five in one run.
   - `book shop` → the three files `docs/accounting/reference-books/shop-sukhwinder-sales-co{.md,.export.md,.tech.md}`.
   - `output` → the paths given, with `--golden` naming the reference book's `.md`.
3. **Call the workflow:**
   ```
   Workflow({ scriptPath: '.claude/workflows/acct-review.js',
              args: { kind, target, files: [...], golden?, panel?, focus? } })
   ```
   `target` is a short label (`01`, `shop`, `app-export-S`); the reports land in `.claude/lane-reports/acct-<kind>-<target>-<agent>.json`.
4. **Report to the owner.**
   - Give the confirmed findings, blockers first, one line each: what is wrong, where (file, section or entry number), the evidence, and the proposed fix.
   - Group them by document.
   - Then give one line for how many findings were refuted, and the citation table, if `acct-ca` checked citations (`verified` / `does not support` / `not found` / `not checked`).
   - Do not edit anything in the same run. The owner rules *keep* or *change* on each finding. Edits are made in the main session afterwards and recorded in the changelog.

## In the build loop
`/cycle` runs `acct-auditor` beside `lane-review` for any slice whose directories produce accounting: `packages/core_ledger`, `packages/data`, `testing/goldens`, and the ledger, reports, close, partners, advances and entry features. Its findings are verified with an accounting lens first. Set `accounting: false` on a slice to turn it off, or `accounting: true` to force it on (`.claude/workflows/cycle.js`, `ACCOUNTING`).
