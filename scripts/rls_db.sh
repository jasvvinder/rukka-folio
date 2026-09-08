#!/usr/bin/env bash
# Local Postgres for the RLS hostile-query suite (E-03-22 … E-05c-7).
#
# The migrations are plain Postgres + pgcrypto — no auth./storage./supabase extensions — so the
# suite does NOT need Docker or `supabase start`. Any Postgres with the migrations applied and a
# superuser connection will do; this script builds one from a Homebrew postgresql@16.
#
#   brew install postgresql@16 && brew services start postgresql@16
#   eval "$(./scripts/rls_db.sh)"        # resets the database, exports RF_TEST_DB_URL
#   (cd server && RLS_REQUIRE=1 deno task test)
#
# Everything but the final export line goes to stderr, so `eval` gets only the export.
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@16/bin}"
[ -d "$PGBIN" ] && PATH="$PGBIN:$PATH"
DB="${RLS_DB_NAME:-rukka_rls}"
HOST="${PGHOST:-127.0.0.1}"
PORT="${PGPORT:-5432}"
USER="${PGUSER:-$(whoami)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v psql >/dev/null 2>&1 || { echo "psql not found (PGBIN=$PGBIN)" >&2; exit 1; }
pg_isready -h "$HOST" -p "$PORT" >/dev/null 2>&1 || {
  echo "no Postgres at $HOST:$PORT — brew services start postgresql@16" >&2; exit 1; }

echo "resetting $DB …" >&2
psql -q -h "$HOST" -p "$PORT" -U "$USER" -d postgres \
  -c "drop database if exists $DB;" -c "create database $DB;" >&2

for f in "$ROOT"/server/supabase/migrations/*.sql; do
  echo "  apply $(basename "$f")" >&2
  psql -v ON_ERROR_STOP=1 -q -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -f "$f" >&2
done

echo "export RF_TEST_DB_URL=postgresql://$USER@$HOST:$PORT/$DB"
