---
name: adr
description: Scaffold a dated ADR in docs/decisions/ for a 🔒 decision, with tests markers, the cross-reference lines for the affected specs, and the matching CHANGELOG "Decided" line. Use whenever a session changes or fixes behaviour a 🔒 line specifies.
---

# /adr $ARGUMENTS

`$ARGUMENTS` = short topic (`sync quotas`) and, if known, the specs touched (`05 08`).

## Rules before writing
- An ADR records an **owner decision**. If the owner has not ruled, write the ADR with the ruling
  marked `⚠️ SPEC: owner to confirm` and list the options — do not pick one silently.
- Newest ADR on a topic beats every spec (CLAUDE.md § Precedence). Check `ls docs/decisions/` for
  an existing ADR on this topic; if the new ruling supersedes one, say so in both.
- A 🔒 change is never recorded in the changelog alone (CHANGELOG.md header).

## File
`docs/decisions/YYYY-MM-DD<suffix>-<kebab-topic>.md`. Same-day ADRs get a letter suffix
(`2026-09-05b-…`); look at today's files to pick the next letter. Model the layout on
`docs/decisions/2026-09-05i-test-contract.md`:

```
# ADR <date><suffix> — <title>

<2–6 lines: context, what was wrong or open, who ruled and when ("Owner confirmed <date>").>

## Rulings 🔒
### 1. <ruling>  ⟦tests: <id>, <id>⟧
- <normative bullets; 🔒 lines end with ⟦tests: …⟧ or ⟦tests: n/a — reason⟧>
### 2. …

## Consequences
- Code: <packages/files; @Skip any green test the ruling flips: @Skip('superseded by ADR <id> §<n>; re-lands at M<n>')>
- Docs: <the spec sections that need a cross-reference line>
- Milestone: <where it lands, per 10>

## Open ⚠️
- <items handed to the owner>
```

Test ids: `<Suite>-<source>-<n>` (`A-02-9`, `D-05b-3`); source for an ADR ruling is the ADR suffix.
Check `grep -rho '⟦tests: [^⟧]*⟧' docs | sort -u` and the test files so ids are not reused.

## Cross-references
For each affected spec, add one line at the relevant section, in the house style:
`> **ADR <date><suffix> §<n>** — <one-sentence summary>. ⟦tests: …⟧` (see how 02–13 reference the 05x ADRs).
If the ADR flips a 🔒 line in a spec, edit that line and keep the marker.

## Changelog
Add to the current session's `**Decided**` list:
`- \`<file>.md\` — 🔒 <one-line summary of rulings>.`

Report: the ADR path, specs touched, tests to (re)write, and the ⚠️ list. Owner commits.
