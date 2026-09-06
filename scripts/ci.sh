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
TEST_PRESET=""; [ "$LANE" = nightly ] && TEST_PRESET="--preset nightly"   # plain string: bash 3.2 + set -u dislike empty arrays

step "pub get (workspace)"
dart pub get

step "generated files are current"
dart run scripts/gen_tokens.dart --check        # tokens.json → tokens.css / tokens.dart (design-system.md)
dart run scripts/gen_l10n_arb.dart               # dotted ARB → identifier ARB for gen_l10n
(cd app && flutter gen-l10n)

step "format"
dart format --output=none --set-exit-if-changed packages scripts app/lib app/test

step "package purity"
scripts/check_purity.sh

step "strings (EN / PA / HI)"
dart run scripts/check_strings.dart

step "coverage — 🔒 lines ↔ test ids, golden front-matter (warn-only until M4, ADR 2026-09-05i §1)"
dart run scripts/check_coverage.dart --milestone M1

step "analyze"
dart analyze --fatal-infos scripts
for p in packages/*; do (cd "$p" && dart analyze --fatal-infos); done
(cd app && flutter analyze --fatal-infos)

step "tests — pure packages (suites A/B/D/E as they land) + harness [$LANE]"
# $TEST_PRESET unquoted on purpose: empty, or the two words "--preset nightly".
for p in packages/* testing/harness; do (cd "$p" && dart test $TEST_PRESET); done

step "tests — app"
(cd app && flutter test)

case "$LANE" in
  nightly) step "nightly — two-client soak (D), fresh-seed fuzz, perf p95, E-server"; scheduled "M4" ;;
  rc)      step "rc — F2 device lab, F3 export goldens, H"; scheduled "M5 (F2/F3 at M12)" ;;
  release) step "release — MASVS L2+R, decompile, MITM, log-scrub, restore-drill artefact"; scheduled "M4 scanners · M14 gates" ;;
esac

printf '\n\033[1;32mCI green (%s lane).\033[0m\n' "$LANE"
