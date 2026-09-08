#!/usr/bin/env bash
# Stop. Every session that changes the tree ends with a CHANGELOG.md entry (CLAUDE.md § Workflow).
# Blocks the stop once (stop_hook_active guards against loops) when the tree is dirty and today has
# no changelog entry.
#
# The entry counts as written whether it is still in the working tree OR already committed — the
# owner often commits mid-session, and an earlier version of this hook only looked at `git status`,
# so a committed entry read as a missing one and blocked a properly-closed session.
set -uo pipefail
cd "$(dirname "$0")/../.."
inp=$(cat)
[ "$(echo "$inp" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

# `cut -c4-` keeps the whole path field: `awk '{print $2}'` mangled renames (`R old -> new`)
# and any path containing a space.
changed=$(git status --porcelain --untracked-files=all 2>/dev/null \
  | cut -c4- | grep -vE '^\.claude/settings\.local\.json$' || true)
[ -z "$changed" ] && exit 0

# Satisfied if today's entry is being written right now …
echo "$changed" | grep -qx 'CHANGELOG.md' && exit 0
# … or if it is already in the file, committed or not. Ask only whether today has an entry — not
# whether it is the topmost one. Entry ordering is a house convention the owner can see for
# themselves; making this hook enforce it too would just reintroduce a way to block a session that
# did write its entry.
today=$(date +%Y-%m-%d)
grep -qE "^## ${today}([^0-9]|$)" CHANGELOG.md 2>/dev/null && exit 0
newest=$(grep -m1 -oE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' CHANGELOG.md 2>/dev/null | tr -d '# ')

n=$(echo "$changed" | wc -l | tr -d ' ')
jq -n --arg n "$n" --arg newest "${newest:-none}" '{decision:"block",
  reason:("The working tree has \($n) uncommitted path(s) and CHANGELOG.md has no entry for today (newest entry: \($newest)). Note the count is the whole dirty tree, not only this session — some of it may predate you. Add the dated, milestone-tagged entry (Added / Changed / Decided / Open / Commits) at the top of CHANGELOG.md, then finish. If this session genuinely changed nothing worth a changelog line, say so explicitly in your final message and stop.")}'
exit 0
