#!/usr/bin/env bash
# Stop. Every session that changes the tree ends with a CHANGELOG.md entry (CLAUDE.md § Workflow).
# Blocks the stop once (stop_hook_active guards against loops) when files changed but the changelog did not.
set -uo pipefail
cd "$(dirname "$0")/../.."
inp=$(cat)
[ "$(echo "$inp" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
changed=$(git status --porcelain --untracked-files=all 2>/dev/null | awk '{print $2}' | grep -vE '^\.claude/settings\.local\.json$' || true)
[ -z "$changed" ] && exit 0
echo "$changed" | grep -qx 'CHANGELOG.md' && exit 0
n=$(echo "$changed" | wc -l | tr -d ' ')
jq -n --arg n "$n" '{decision:"block",
  reason:("\($n) file(s) changed this session but CHANGELOG.md was not updated. Add the dated, milestone-tagged entry (Added / Changed / Decided / Open / Commits) at the top of CHANGELOG.md, then finish. If the changes are genuinely not worth a changelog line, say so explicitly in your final message and stop.")}'
exit 0
