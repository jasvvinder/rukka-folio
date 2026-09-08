#!/usr/bin/env bash
# Stop. One lane, one session, one clear (PLAN.md §3).
# Fires only when a build workflow actually ran in THIS session and the session closed properly
# (CHANGELOG.md touched) — so it reminds after real work, never after a question.
set -uo pipefail
cd "$(dirname "$0")/../.."
inp=$(cat)
sid=$(echo "$inp" | jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0

# a workflow run recorded under this session id = /lane or /gate ran
runs=$(ls "$HOME/.claude/projects/"*"/$sid/workflows/"*.json 2>/dev/null | wc -l | tr -d ' ')
[ "$runs" = "0" ] && exit 0

# only once the closing ritual has happened
git status --porcelain --untracked-files=all 2>/dev/null | awk '{print $2}' \
  | grep -qx 'CHANGELOG.md' || exit 0

spend=$(.claude/bin/wf-spend.sh 2>/dev/null | tail -3)
jq -n --arg s "$spend" '{systemMessage:("Session complete — run /clear now and start the next lane in a fresh session.\n\n" + $s)}'
exit 0
