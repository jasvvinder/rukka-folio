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
| `acct-munim` | Senior bookkeeper: plain words vs Dr/Cr, uncovered cases, vocabulary; practice claims come back as questions for the bookkeeper | docs, book |
| `acct-entities` | Partnership, joint family, trust/NPO, landlord, related books | docs, book |
| `acct-auditor` | Re-derives every figure; compares app output with its reference book | book, output |

## What the panel is, and what it is not
- **It is not the bookkeeper sign-off** of PLAN-209. It runs before that review and makes it shorter. It never replaces it.
- **It is the same model that wrote the docs.** It catches what a careful reader can show from the text: citations that don't say what the rule claims, arithmetic, contradictions between documents, plain words that contradict the Dr/Cr, missing report statements. It cannot catch an error the writer and the panel share. Claims about real practice come back as **questions for the bookkeeper**, not findings.
- **It is not the test of the app's output.** That test is deterministic: the golden tests (suite A, `A-ref-*`, re-landing at M14) compare the engine's books with the reference books exactly, every run, at no token cost, and `check_md.py` does the same for the reference books themselves. Use `output` mode to diagnose a golden mismatch, to check what a printed or exported report must state (which a byte-diff does not explain), or to help write a new golden test. Do not use it as the test.

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
   - Then list `questions_for_bookkeeper` separately, unverified, under that heading. They go to PLAN-209's bookkeeper, not to the owner for a ruling.
   - Do not edit anything in the same run. The owner rules *keep* or *change* on each finding. Edits are made in the main session afterwards and recorded in the changelog.

## In the build loop
`/cycle` runs `acct-auditor` beside `lane-review` only for slices that produce a book: `packages/core_ledger`, `testing/goldens` and `app/lib/features/reports`. Its findings are verified with an accounting lens first. Set `accounting: true` on any other slice that changes book output, or `accounting: false` to turn it off (`.claude/workflows/cycle.js`, `ACCOUNTING`).
