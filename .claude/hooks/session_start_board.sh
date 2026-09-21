#!/usr/bin/env bash
# Rukka Folio — print the board at session start: where we are, what is next.
# Replaces "go read PLAN.md §0" with a rendered position.
set -uo pipefail
cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || cd "$(dirname "$0")/../.."
exec .claude/bin/board.sh
