#!/usr/bin/env bash
# scripts/ci.sh — THE gate (CLAUDE.md § Commands). Runs locally and in .github/workflows/ci.yml.
# Suites (09 §2): A ledger core · B crypto · C auth · D sync · E data/RLS · G subscription
# run on every commit as they land in their milestones; M0 wires the harness with
# hello-world tests. F (UI) is release-candidate only; H before pilot.
#
# Lanes (09 §preamble, ADR 2026-09-05i §2): LANE=push (default) | nightly | rc | release.
#   push     — everything below.
#   nightly  — push + `flaky`-tagged tests re-enabled (dart test --preset nightly); the two-client
#              soak, fresh-seed fuzz, perf p95 and E-server join at M4.
#   rc       — push + F2 device lab, F3 export goldens, H — wired at M5/M12.
#   release  — rc + MASVS / decompile / MITM / log-scrub gates — wired at M4 (scanners) and M14.
# Steps that a lane does not yet own print "scheduled" rather than pretending to run.
set -euo pipefail
cd "$(dirname "$0")/.."
LANE="${LANE:-push}"
case "$LANE" in push|nightly|rc|release) ;; *) echo "LANE must be push|nightly|rc|release (got '$LANE')"; exit 2;; esac
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
scheduled() { printf '   (scheduled — lands at %s; not run in this lane yet)\n' "$1"; }
# need <command> <install hint> — a scanner the gate relies on is never optional: if it is missing
# the gate FAILS with the hint, in every lane (ADR 2026-09-05 ruling 10: "either red blocks merge").
need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  printf '\033[1;31m%s is not installed — the gate cannot pass without it.\033[0m\n   install: %s\n' "$1" "$2" >&2
  exit 1
}
TEST_PRESET=""; [ "$LANE" = nightly ] && TEST_PRESET="--preset nightly"   # plain string: bash 3.2 + set -u dislike empty arrays
ROOT="$PWD"
CI_TMP="$(mktemp -d "${TMPDIR:-/tmp}/rf-ci.XXXXXX")"   # scan scratch (tree copy, SBOMs); never in the repo
trap 'rm -rf "$CI_TMP"' EXIT

step "pub get (workspace)"
dart pub get

step "secret scan — gitleaks over every commit + the committable tree (ADR 2026-09-05 ruling 10)"
need gitleaks "brew install gitleaks (macOS); CI installs a pinned release in .github/workflows/ci.yml"
# .gitleaks.toml is the ONLY allowlist and is reviewed like code: inline `gitleaks:allow` comments
# are ignored (--ignore-gitleaks-allow) and a fingerprint file is refused. --redact keeps every
# matched value out of this log (CLAUDE.md rule 4); --verbose still names rule, file and line.
[ ! -e .gitleaksignore ] || { echo ".gitleaksignore found — allowlist a known-safe match in .gitleaks.toml, with its reason"; exit 1; }
[ "$(git rev-parse --is-shallow-repository)" = false ] \
  || { echo "shallow clone — the history scan would silently skip commits (actions/checkout needs fetch-depth: 0; locally: git fetch --unshallow)"; exit 1; }
leaks() { sub="$1"; shift; gitleaks "$sub" --no-banner --redact --verbose --ignore-gitleaks-allow --exit-code 1 --config "$ROOT/.gitleaks.toml" "$@"; }
# --log-opts REPLACES gitleaks' default `--full-history --all --diff-filter=tuxdb`, which skips two
# things (probed 3 Oct 2026, gitleaks 8.30.1, plumbing-built scratch repos): a merge commit's own
# diff — `git log -p` shows none without --diff-merges, so a secret added in a merge resolution and
# deleted after was never seen — and a type change (symlink → file holding a secret, filtered by
# the `t` in tuxdb). first-parent diffs every merge against its first parent: a line new in the
# merge is new against that parent, and anything already in a parent was scanned on its own commit.
# No --diff-filter: every change type is scanned (deletions add no lines, so they cost nothing).
# gitleaks SWALLOWS a failing `git log` — "0 commits scanned … no leaks found", exit 0 (probed with
# a bad option) — so git walks the same history with the same options first (an old git without
# --diff-merges, a corrupt object: red here), and the scan must then report a non-zero count.
gl_opts="--all --full-history --diff-merges=first-parent"   # gitleaks splits --log-opts on spaces
# shellcheck disable=SC2086  # split on purpose, exactly as gitleaks will split it
git log $gl_opts -p -U0 --format=%H >/dev/null \
  || { echo "git log rejects or cannot walk '$gl_opts' (--diff-merges needs git >= 2.31) — the history scan would scan nothing"; exit 1; }
leaks git --log-opts="$gl_opts" "$ROOT" 2>"$CI_TMP/gitleaks-git.log" || { cat "$CI_TMP/gitleaks-git.log" >&2; exit 1; }
cat "$CI_TMP/gitleaks-git.log" >&2
gl_commits="$(tr -d '\033' <"$CI_TMP/gitleaks-git.log" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) commits scanned.*/\1/p' | tail -1)"
gl_total="$(git rev-list --all --count)"
case "$gl_commits" in ''|*[!0-9]*) echo "gitleaks printed no 'N commits scanned' line — cannot prove the history was scanned"; exit 1 ;; esac
[ "$gl_total" -eq 0 ] || [ "$gl_commits" -gt 0 ] \
  || { echo "gitleaks scanned 0 of $gl_total commits — its git log failed silently"; exit 1; }
printf '   history: gitleaks scanned %s commits with content of %s on all refs\n' "$gl_commits" "$gl_total"
# The committable tree: tracked + untracked-not-ignored files, as they are on disk now. The
# git-ignored local .env (where local secrets belong, CLAUDE.md § Layout) and build caches
# (.dart_tool/, build/) are out by construction — never by an allowlist entry.
mkdir "$CI_TMP/tree"
git ls-files -z --cached --others --exclude-standard \
  | while IFS= read -r -d '' f; do if [ -f "$f" ]; then printf '%s\0' "$f"; fi; done \
  | tar --null -T - -cf - | tar -xf - -C "$CI_TMP/tree"
(cd "$CI_TMP/tree" && leaks dir .)

step "dependency audit — OSV over pubspec.lock, every lockfile osv-scanner reads, server/deno.lock npm (ADR 2026-09-05 ruling 10)"
need osv-scanner "brew install osv-scanner (macOS); CI installs a pinned release in .github/workflows/ci.yml"
need jq "brew install jq (macOS 15+ ships /usr/bin/jq; ubuntu runners have it)"
[ -f pubspec.lock ] || { echo "pubspec.lock missing — the workspace lockfile is the audit's primary input"; exit 1; }
# osv-scanner.toml may only ignore with a reason AND a near expiry (its header). TOML has many
# spellings that osv-scanner 2.6.0 honours — an inline `IgnoredVulns = [ { id = … } ]`, a
# lower-case `[[ignoredvulns]]`, `ID =` / `Reason =`, quoted or spaced headers (all probed 3 Oct
# 2026: each silenced a lodash advisory) — so the guard is a WHITELIST, not a search: a line is a
# comment, a blank, an exact `[[IgnoredVulns]]` / `[[PackageOverrides]]` header, or one of the
# exact keys below with a one-line value; anything else is refused. Blocks must carry: IgnoredVulns
# — `id`, `reason`, `ignoreUntil`; PackageOverrides — `name` (an override with no name matches
# every package in its ecosystem: probed, all six advisories gone), `reason`, `effectiveUntil`.
# Dates are plain TOML dates no later than today + $osv_max_days. (A nested osv-scanner.toml
# elsewhere in the tree is NOT read under --config — probed — so this file is the only policy.)
# ⚠️ SPEC: "≤ one release cycle" has no number in docs/; 90 days mirrors the release lane's
# 90-day restore-drill freshness (ADR 2026-09-05i §2). Owner to confirm or change the number.
osv_max_days=90
osv_cutoff="$(jq -rn --argjson d "$osv_max_days" 'now + $d * 86400 | strftime("%Y-%m-%d")')"
awk -v cutoff="$osv_cutoff" -v maxdays="$osv_max_days" '
  function refuse(msg) { printf "osv-scanner.toml:%d: %s\n", NR, msg; bad = 1 }
  function need(ok, what) {
    if (!ok) { printf "osv-scanner.toml:%d: [[%s]] needs %s\n", start, kind, what; bad = 1 }
  }
  function close_block() {
    if (kind == "IgnoredVulns") {
      need(has_id, "an id"); need(has_reason, "a non-empty reason"); need(has_until, "an ignoreUntil date")
    } else if (kind == "PackageOverrides") {
      need(has_name, "a name (no name = every package)"); need(has_reason, "a non-empty reason")
      need(has_until, "an effectiveUntil date")
    }
    kind = ""; has_id = 0; has_name = 0; has_reason = 0; has_until = 0
  }
  function date_ok() {
    match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
    d = substr($0, RSTART, RLENGTH)
    if (d > cutoff) refuse("expiry " d " is later than " cutoff " (today + " maxdays " days)")
    has_until = 1
  }
  BEGIN {
    T = "[ \t]*(#.*)?$"                                  # end of line: spaces, optional comment
    S = "\"[^\"]*\""                                     # one-line basic string
    R = "\"[^\" \t][^\"]*\""                             # ... starting with a non-blank
    D = "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"    # plain TOML date, no time part
    B = "(true|false)"
    K = "^[ \t]*"                                        # indentation before a key
    E = "[ \t]*=[ \t]*"
  }
  { sub(/\r$/, "") }
  /^[ \t]*(#.*)?$/ { next }
  $0 ~ ("^\\[\\[IgnoredVulns\\]\\]" T)     { close_block(); kind = "IgnoredVulns"; start = NR; next }
  $0 ~ ("^\\[\\[PackageOverrides\\]\\]" T) { close_block(); kind = "PackageOverrides"; start = NR; next }
  kind == "" { refuse("outside an exact [[IgnoredVulns]] / [[PackageOverrides]] block, or a spelling the guard does not accept"); next }
  $0 ~ (K "reason" E R T) { has_reason = 1; next }
  kind == "IgnoredVulns" && $0 ~ (K "id" E S T) && $0 !~ (K "id" E "\"\"") { has_id = 1; next }
  kind == "IgnoredVulns" && $0 ~ (K "ignoreUntil" E D T) { date_ok(); next }
  kind == "PackageOverrides" && $0 ~ (K "name" E R T) { has_name = 1; next }
  kind == "PackageOverrides" && $0 ~ (K "(version|ecosystem|group)" E S T) { next }
  kind == "PackageOverrides" && $0 ~ (K "(ignore|vulnerability\\.ignore|license\\.ignore)" E B T) { next }
  kind == "PackageOverrides" && $0 ~ (K "license\\.override" E "\\[[ \t]*(" S "[ \t]*,?[ \t]*)*\\]" T) { next }
  kind == "PackageOverrides" && $0 ~ (K "effectiveUntil" E D T) { date_ok(); next }
  { refuse("[[" kind "]] does not accept this line (exact key, one-line value; sub-tables as dotted keys)") }
  END { close_block(); exit bad }
' osv-scanner.toml
# deno.lock: osv-scanner 2.6.0 has no extractor for it ("could not determine extractor", exit 127,
# probed 3 Oct 2026), so its npm half is bridged to a CycloneDX 1.5 SBOM, which osv-scanner does
# read natively. jsr: and remote-URL imports have no OSV ecosystem (osv-scanner filters a pkg:jsr
# purl as "unscannable") — they are listed below as unaudited, never silently dropped.
osv_sboms=()   # expanded as ${a[@]+"${a[@]}"}: bash 3.2 + set -u reject a bare empty array
n=0
deno_locks="$(git ls-files -- ':(glob)**/deno.lock')"
while IFS= read -r lock; do
  [ -n "$lock" ] || continue
  n=$((n + 1))
  ver="$(jq -r '.version' "$lock")"
  case "$ver" in 4|5) ;; *) echo "$lock: deno.lock version '$ver' — the npm bridge reads v4/v5 keys only; re-verify it"; exit 1 ;; esac
  sbom="$CI_TMP/deno-$n.cdx.json"
  jq '{bomFormat: "CycloneDX", specVersion: "1.5", version: 1, components: [
        (.npm // {}) | keys[] | capture("^(?<name>@?[^@]+)@(?<ver>[^_]+)")
        | {type: "library", name: .name, version: .ver,
           purl: ("pkg:npm/" + (.name | sub("^@"; "%40")) + "@" + .ver)} ]}' "$lock" > "$sbom"
  want="$(jq '(.npm // {}) | length' "$lock")"; got="$(jq '.components | length' "$sbom")"
  [ "$want" = "$got" ] || { echo "$lock: bridged $got of $want npm packages — a key no longer parses as name@version"; exit 1; }
  printf '   %s: %s npm packages -> %s\n' "$lock" "$got" "$sbom"
  unaudited="$(jq -r '((.jsr // {}) | keys[] | "jsr:" + .), ((.remote // {}) | keys[])' "$lock")"
  if [ -n "$unaudited" ]; then
    printf '   %s: not auditable by OSV (no ecosystem for JSR / remote URLs):\n' "$lock"
    printf '%s\n' "$unaudited" | sed 's/^/     /'
  fi
  osv_sboms+=(-L "$sbom")
done <<EOF
$deno_locks
EOF
# -r discovers every lockfile osv-scanner supports (pubspec.lock today), honouring .gitignore.
# Exit 1 = advisories found, 127/128 = error / nothing scanned: all red under set -e.
osv-scanner scan source --config osv-scanner.toml -r ${osv_sboms[@]+"${osv_sboms[@]}"} .

step "generated files are current"
dart run scripts/gen_tokens.dart --check        # tokens.json → tokens.css / tokens.dart (design-system.md)
dart run scripts/gen_l10n_arb.dart               # dotted ARB → identifier ARB for gen_l10n
(cd app && flutter gen-l10n)

step "contrast — every colour token × four grounds × both modes (design-system §3.1)"
dart run scripts/check_contrast.dart

step "format"
dart format --output=none --set-exit-if-changed packages scripts test app/lib app/test

step "package purity"
scripts/check_purity.sh

step "no bare print( in shipped Dart — app/lib, packages/*/lib (ADR 2026-09-05 ruling 9, CLAUDE.md rule 4)"
# A bare top-level print( — not obj.print(, not debugPrint(, not Fingerprint( — outside a // comment
# line. Belt to the `avoid_print` lint's braces: a lint can be silenced with `// ignore:`, this
# cannot. `print(` exactly (no space) because dart format, enforced above, never writes `print (`;
# tear-offs (`forEach(print)`) are left to the lint. No debugPrint policy exists in the repo
# (grep, 3 Oct 2026) — ⚠️ SPEC: ruling 9's "release builds strip all debug logging" is not
# grep-checkable for debugPrint/log(); owner item, not invented here.
print_hits="$(grep -rnE --include='*.dart' '(^|[^A-Za-z0-9_$.])print\(' app/lib packages/*/lib)" && rc=0 || rc=$?
[ "$rc" -le 1 ] || { echo "grep failed (exit $rc) — the print( check did not run"; exit 1; }
print_hits="$(printf '%s\n' "$print_hits" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' || true)"
[ -z "$print_hits" ] || { printf '%s\n' "$print_hits"; echo "bare print( in shipped code — logs may carry plaintext (CLAUDE.md rule 4); remove it (ruling 9: debug logging only behind kDebugMode)"; exit 1; }
echo "no bare print("

step "release-build hardening flags (09 §4)"
scripts/check_release_flags.sh

step "strings (EN / PA / HI)"
dart run scripts/check_strings.dart

step "coverage — 🔒 lines ↔ test ids, golden front-matter (blocking from M4, ADR 2026-09-05i §1)"
# --strict from M4 exit as 05i §1 phased it: every 🔒 line is annotated as of 8 Sep. --milestone M4
# additionally fails a superseded skip, or an ` @M<k>` planned test (ADR 2026-09-08 §2), that is due.
dart run scripts/check_coverage.dart --strict --milestone M4

step "analyze"
dart analyze --fatal-infos scripts test
for p in packages/*; do (cd "$p" && dart analyze --fatal-infos); done
(cd app && flutter analyze --fatal-infos)

step "tests — root scripts (gen_l10n_arb merge, check_contrast; suite F1-10)"
dart test test/

step "tests — pure packages (suites A/B/D/E as they land) + harness [$LANE]"
# $TEST_PRESET unquoted on purpose: empty, or the two words "--preset nightly".
for p in packages/* testing/harness; do (cd "$p" && dart test $TEST_PRESET); done

step "tests — app"
(cd app && flutter test)

step "tests — server functions + schema (deno; suite E-server, 03 §2.5 / 05 / 06)"
# The tests/rls hostile-query files need a live Postgres in RF_TEST_DB_URL and skip otherwise.
# The migrations are plain Postgres + pgcrypto, so any server will do — `scripts/rls_db.sh` builds
# one from a local postgresql@16 (no Docker, no `supabase start`); GitHub CI starts a pinned
# postgres:16 container for the non-push lanes (.github/workflows/ci.yml). The nightly, rc and
# release lanes carry E-server (ADR 2026-09-05i §2) and set RLS_REQUIRE=1: a missing database OR
# a missing deno fails loudly there instead of skipping in silence. deno is `need`ed in every
# lane — until 3 Oct a runner without it printed "scheduled" and went green with no server test.
need deno "brew install deno (macOS); CI installs a pinned release in .github/workflows/ci.yml"
case "$LANE" in nightly|rc|release) export RLS_REQUIRE=1 ;; esac
if [ "${RLS_REQUIRE:-}" = 1 ]; then
  [ -n "${RF_TEST_DB_URL:-}" ] || { echo "RLS_REQUIRE=1 ($LANE lane) but RF_TEST_DB_URL is unset — eval \"\$(scripts/rls_db.sh)\" first (CI: the Postgres step in ci.yml)"; exit 1; }
elif [ -z "${RF_TEST_DB_URL:-}" ]; then
  printf '   (RF_TEST_DB_URL unset — the tests/rls hostile-query files will skip; eval "$(scripts/rls_db.sh)" to run them)\n'
fi
(cd server && deno task lint && deno task test)

case "$LANE" in
  nightly) step "nightly — two-client soak (D), fresh-seed fuzz, perf p95"; scheduled "M4"
           printf '   (E-server: the RLS hostile-query suite ran above under RLS_REQUIRE=1)\n' ;;
  rc)      step "rc — F2 device lab, F3 export goldens, H"; scheduled "M5 (F2/F3 at M12)" ;;
  release) step "release — MASVS L2+R, decompile, MITM, log-scrub, restore-drill artefact"; scheduled "M4 scanners · M14 gates" ;;
esac

printf '\n\033[1;32mCI green (%s lane).\033[0m\n' "$LANE"
