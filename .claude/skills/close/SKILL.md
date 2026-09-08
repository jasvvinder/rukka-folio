---
name: close
description: Close a Rukka Folio session the CLAUDE.md way — /plan, then /changelog, then the commit message for the owner, then tell the owner to clear the context. Use at the end of every session; it is the last thing you do.
---

# /close

The closing ritual. One pass, no loops, no new work.

## 1. `/plan`
Mark ✅ **only** for test ids green in the gate. Add newly discovered ⬜/⛔ items. Update §0
"Where we are" and the phase status.

## 2. `/changelog`
The dated, milestone-tagged entry (Added / Changed / Decided / Open / Commits) at the top of
`CHANGELOG.md`. Leave the commit hashes blank — the next session fills them.
(The `Stop` hook blocks the session until this exists.)

## 3. Hand off
Give the owner:
- the files changed, grouped
- a suggested commit message: `M<n>: <what>` — one line, scoped
- anything still `⚠️ SPEC:` or waiting on the owner

**Never run `git commit` or `git push`** — the owner commits (the `PreToolUse` hook enforces it).

## 4. Ask for a clear
End with exactly this, on its own line:

> **Session complete — run `/clear` now and start the next lane in a fresh session.**

A fresh session is the cheapest session: context is resent in full on every turn, so a long
session costs more per turn than a short one doing the same work. One lane, one session, one clear.

Optionally show the week's spend so the next session starts informed:
```bash
.claude/bin/wf-spend.sh
```

## Do not
- Start the next lane. Do not chain work after a close — that is the owner's next decision.
- Re-run the gate, re-read files to verify, or re-check the changelog you just wrote.
