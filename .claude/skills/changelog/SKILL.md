---
name: changelog
description: Write this session's CHANGELOG.md entry in the house format (dated, milestone-tagged, Added / Changed / Decided / Open / Commits) from the working-tree changes. Use at the end of every session; the Stop hook blocks until it exists.
---

# /changelog $ARGUMENTS

`$ARGUMENTS` = optional heading tag (`M2`, `docs`, `env`). Infer it from the changes if omitted:
`env` for toolchain/config, `docs` for spec-only, `M<n>` for code.

## Gather
```bash
git status --porcelain --untracked-files=all
git diff --stat
```
Plus what you know from this session: decisions taken, ⚠️ items raised, tests added (by id).
Read the top entry of `CHANGELOG.md` first so the new one does not repeat it, and so "Commits —
pending" from the previous entry can be filled if the owner has committed since
(`git log --oneline -5`).

## Write (newest first, directly under the `---` after the header block)
```
## YYYY-MM-DD — <tag>: <one-line slice title>

<1–3 sentences of context: what the session set out to do and the outcome.>

**Added** — <one line per item; tests by id>
**Changed** — <one line per item; name the doc sections or packages>
**Decided** — <one line per ADR: `file.md` — 🔒 summary>   (only with an ADR in the same commit)
**Open** ⚠️ — <items handed to the owner>
**Commits** — pending.

---
```
Sections are optional; drop empty ones. Record *what* and *why*, never the diff. **No financial
data, keys or secrets** — this file is committed. Today's date is in the environment; never guess it.

Then tell the owner: files ready to commit and a suggested message. Do not run `git commit`.
