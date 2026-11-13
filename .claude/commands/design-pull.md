---
description: Pull the Rukka Folio Claude Design project, diff against design/canvas-mirror/, and propose doc updates
---

# /design-pull — sync the Claude Design project into the repo

**Project (since 12 Nov 2026):** the artifact **Rukka Folio**, https://claude.ai/artifact/PS6d6AFwvWPF8XMLDs9PsZ. The owner moved the project there from standalone Claude Design (it was moved on 27 Oct 2026; standalone closes by 14 Dec 2026). Everything that was at the project root is now under **`project/`**, and the page list is `project/compat.json`. Read files with the Artifact tool: `action: "read"`, the url, and `paths` (up to 256 per call). Each file is saved under the scratchpad's `artifact-files/<id>/project/…`. Copy the files from there into the mirror after the diff in step 3, with `project/` removed from the path. There is no 256 KiB cap.
*Old project:* DesignSync projectId `65a8ac2d-06c6-40a6-8b07-168198dfe2a2` (needs `/design-login`). Use it only if the owner asks.

**Mirror:** `design/canvas-mirror/` — **local-only** snapshot of the project's text-bearing
sources. It is gitignored (owner's call, 1 Sep 2026): never commit or push it. The change
record is `design/canvas-mirror/CHANGES.md` — append one dated entry per sync listing the
changed files/screens/strings; the on-disk mirror itself is the diff baseline.

**Mirror file set** (pull these, nothing else):
- `partials/**` — the per-canvas screen JSON sources + build script (the canvases'
  `.dc.html` files are *generated* from these; never pull the generated canvases)
- `i18n-*.json` — master and per-canvas ਪੰਜਾਬੀ/हिन्दी dictionaries
- `DUPLICATES.md` · `TRANSLATION-PENDING.md` · `FLOW-RESTRUCTURE-REPORT.md`
- **Canvas 17 (owner, 27 Sep 2026):** `Canvas 17 - Reports and statements.dc.html` · `reports-data.js` ·
  `Report Page.dc.html`. Canvas 17 has no partials: it is data-driven, so these three files *are* its source,
  and they are the one exception to the `*.dc.html` rule below. If `reports-data.js` ever exceeds 256 KiB,
  ask the app's agent to split it, as was done for canvas 1.
- **Canvas 1b (owner, 5 Oct 2026):** `Canvas 1b - Sign in.dc.html`. Like Canvas 17 it has no partials, so the
  `.dc.html` is its source and the second exception to the `*.dc.html` rule. `scripts/design_match.py` indexes its
  phone frames straight from the file (PLAN desk 157). `index` stops, naming the offset, if a static 390×844 phone
  has no `id · caption` header (the header markup drifted) — fix the parser then, never drop the frame;
  `python3 scripts/design_match.py selftest` checks the parser without the mirror.

**Never pull:** `uploads/` (copies of repo docs — the repo is the source of truth),
`screenshots/`, `_ds/`, `*.dc.html` (except Canvas 17's two and Canvas 1b above), `doc-page.js`, `support.js`, `.thumbnail`,
and the marketing pages (`Landing Page`, `Coming Soon*`). Those are the website's, not the app's (brand 11).

## Procedure

1. List the artifact's files (`action: "list"`, `scope: "files"`, the url) and read `project/compat.json`. Paths below are relative to `project/`. Any **new** file matching the mirror set (a new canvas's
   partials or i18n files, a new report) joins the pull; any file gone from the project is
   deleted from the mirror. Note both in the report.
2. Fetch every mirror-set file with the Artifact tool's `read` and `paths`, **in the main session**. Copy each saved file byte-exact from the scratchpad into a temp dir, and check that every `.json` parses. (Before 12 Nov 2026 this step used DesignSync `get_file` and `mirror_extract.py`, with a 256 KiB cap.)
   **Canvas 18 · Ledger model — proposals** (owner, 12 Nov 2026): pull it into the mirror like any other canvas. But `scripts/design_match.py index` must skip it until each pair is approved, because a proposal would otherwise take over its S-id (brief `design/briefs/2026-11-11-ledger-model-frames.md`, *After the frames*).
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
5b. Re-index the frames: `python3 scripts/design_match.py index` rewrites `design/match/canvas-index.json`
   (committed). Then `dart run scripts/check_design_match.dart`: every record whose frames changed now reads
   **stale**. List those S-ids in the report, because their screens must be re-matched (ADR 2026-10-05 §4).
6. Record the sync: append a dated entry to `design/canvas-mirror/CHANGES.md` (files
   touched, screens/strings changed, doc updates made). Then one commit of the **doc
   updates only**, message `design-sync: <summary>` — the mirror is gitignored and never
   committed.
7. Report to the owner: the diff summary, doc updates made, anything awaiting their call,
   and the current open items in `TRANSLATION-PENDING.md`.

**Direction note:** this command pulls design → repo only. Pushing repo docs back into the
project's `project/uploads/` is a separate, on-request action: publish to the artifact url with `root` set to a scratchpad folder that holds `project/compat.json` (unchanged) plus the new files, and `file_path` set to that `compat.json`. The project's own files are never rewritten.

## ⚠️ Pushing rebuilt canvases: exact display names, never short names

A rebuilt canvas MUST be written back to the project under its existing **display-named**
path — writing `canvas5.dc.html` creates a *duplicate* canvas in the app (happened 2–3 Sep
2026; four strays cleaned up 3 Sep). The canonical paths:

| n | project path |
|---|---|
| 0 | `Canvas 0 - Master map.dc.html` |
| 1 | `Canvas 1 - Onboarding.dc.html` |
| 1b | `Canvas 1b - Sign in.dc.html` (no partials — the file is the source) |
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
| 15 | `Canvas 15 - Menu and reports.dc.html` |
| 16 | `Canvas 16 - Reading by entity.dc.html` |
| 17 | `Canvas 17 - Reports and statements.dc.html` |
| 18 | `Canvas 18 - Ledger model proposals.dc.html` (12 Nov 2026; proposals only, see step 2) |

In the artifact (since 12 Nov 2026), each path above sits under `project/`, for example `project/Canvas 2 - Entry.dc.html`.

(plus `Core Patterns.dc.html`, not canvas-numbered). Canvas 7's *title* became "Reading the books" on 3 Sep 2026 when its Menu/report and per-entity rows split off into 15 and 16; its project path keeps the old name until the owner renames it. If unsure, `list_files` first and
match the existing name; a canvas rename is the owner's call only.
