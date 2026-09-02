---
description: Pull the Rukka Folio Claude Design project, diff against design/canvas-mirror/, and propose doc updates
---

# /design-pull — sync the Claude Design project into the repo

**Project:** "Rukka Folio", DesignSync projectId `65a8ac2d-06c6-40a6-8b07-168198dfe2a2`.
It is a regular design project (`PROJECT_TYPE_PROJECT`), so it does **not** appear in
`list_projects` (that lists design-system projects only) — address it by id directly.
If DesignSync returns an authorization error, ask the owner to run `/design-login` first.

**Mirror:** `design/canvas-mirror/` — **local-only** snapshot of the project's text-bearing
sources. It is gitignored (owner's call, 1 Sep 2026): never commit or push it. The change
record is `design/canvas-mirror/CHANGES.md` — append one dated entry per sync listing the
changed files/screens/strings; the on-disk mirror itself is the diff baseline.

**Mirror file set** (pull these, nothing else):
- `partials/**` — the per-canvas screen JSON sources + build script (the canvases'
  `.dc.html` files are *generated* from these; never pull the generated canvases)
- `i18n-*.json` — master and per-canvas ਪੰਜਾਬੀ/हिन्दी dictionaries
- `DUPLICATES.md` · `TRANSLATION-PENDING.md` · `FLOW-RESTRUCTURE-REPORT.md`

**Never pull:** `uploads/` (copies of repo docs — the repo is the source of truth),
`screenshots/`, `_ds/`, `*.dc.html`, `doc-page.js`, `support.js`, `.thumbnail`.

## Procedure

1. `list_files` on the project. Any **new** file matching the mirror set (a new canvas's
   partials or i18n files, a new report) joins the pull; any file gone from the project is
   deleted from the mirror. Note both in the report.
2. Fetch every mirror-set file with `get_file` — **in the main session** (subagents do not
   have DesignSync; the design authorization is session-bound). Then write the fetched
   bytes to the mirror **via extraction, never by hand-copying**: large results are
   auto-persisted as JSON envelopes under the session's `tool-results/` directory, and
   inline results are recorded in the session transcript
   (`~/.claude/projects/-Users-office-Github-rukka-folio/<session-id>.jsonl`) — a small
   python script can parse both, write each envelope's `content` to
   `design/canvas-mirror/<path>` byte-exact, and validate that every `.json` parses
   (pattern: `mirror_extract.py`, first used 1 Sep 2026).
   ⚠️ Files whose content exceeds **256 KiB** come back `truncated` and must be skipped —
   see the known-gaps table in `design/canvas-mirror/README.md`.
3. Diff before overwriting: compare each fetched file against the on-disk mirror copy
   (write fetched content to a temp dir in the scratchpad, `diff -u` against the mirror,
   then overwrite). Summarize per file: which screens / strings changed, old → new.
4. Classify every change:
   - **copy-only** — wording, labels, translations → apply to the owning doc directly
   - **behavioral** — flow, states, rules → stop and ask the owner; 🔒 lines need explicit
     approval and a dated ADR in `docs/decisions/`
   - **design-only** — layout/visual with no doc impact → mirror commit only
5. Update the owning docs per CLAUDE.md precedence (02 ledger · 06 identity · 07 screens ·
   13 UX architecture · design/DESIGN-PACK.md · 01 vocabulary).
6. Record the sync: append a dated entry to `design/canvas-mirror/CHANGES.md` (files
   touched, screens/strings changed, doc updates made). Then one commit of the **doc
   updates only**, message `design-sync: <summary>` — the mirror is gitignored and never
   committed.
7. Report to the owner: the diff summary, doc updates made, anything awaiting their call,
   and the current open items in `TRANSLATION-PENDING.md`.

**Direction note:** this command pulls design → repo only. Pushing repo docs back into the
project's `uploads/` is a separate, on-request action (`finalize_plan` → `write_files`).

## ⚠️ Pushing rebuilt canvases: exact display names, never short names

A rebuilt canvas MUST be written back to the project under its existing **display-named**
path — writing `canvas5.dc.html` creates a *duplicate* canvas in the app (happened 2–3 Sep
2026; four strays cleaned up 3 Sep). The canonical paths:

| n | project path |
|---|---|
| 0 | `Canvas 0 - Master map.dc.html` |
| 1 | `Canvas 1 - Onboarding.dc.html` |
| 2 | `Canvas 2 - Entry.dc.html` |
| 3 | `Canvas 3 - Locks and system.dc.html` |
| 4 | `Canvas 4 - Members ceremony and roles.dc.html` |
| 5 | `Canvas 5 - Closing.dc.html` |
| 6 | `Canvas 6 - Money between people.dc.html` |
| 7 | `Canvas 7 - Reading menu and reports.dc.html` |
| 8 | `Canvas 8 - Bank import.dc.html` |
| 9 | `Canvas 9 - Review and approval.dc.html` |
| 10 | `Canvas 10 - Account money and help.dc.html` |
| 11 | `Canvas 11 - Journey individual.dc.html` |
| 12 | `Canvas 12 - Journey individual with a business.dc.html` |
| 13 | `Canvas 13 - Journey joint family.dc.html` |
| 14 | `Canvas 14 - Journey trust.dc.html` |

(plus `Core Patterns.dc.html`, not canvas-numbered). If unsure, `list_files` first and
match the existing name; a canvas rename is the owner's call only.
