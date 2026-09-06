#!/usr/bin/env bash
# PreToolUse (Bash). The owner commits and pushes; Claude never does.
# Denies git commit / git push / gh pr create so Claude hands the files over instead.
set -uo pipefail
cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0
# Command position only: start of a line or after ; & | — prose that merely mentions the words
# (a changelog line, a doc heredoc) is not caught.
# Up to four tokens may sit between `git` and the subcommand (`git -C . commit`, `git -c k=v push`).
if echo "$cmd" | grep -qE '(^|[;&|])[[:space:]]*(git[[:space:]]+([^[:space:]]+[[:space:]]+){0,4}(commit|push)([[:space:]]|$)|gh[[:space:]]+pr[[:space:]]+create)'; then
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",
    permissionDecisionReason:"Owner commits, not Claude (CLAUDE.md workflow). Stage nothing; report the changed files and a suggested commit message instead."}}'
fi
exit 0
