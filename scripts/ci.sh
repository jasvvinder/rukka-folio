#!/usr/bin/env bash
# scripts/ci.sh — THE gate (CLAUDE.md § Commands). Runs locally and in .github/workflows/ci.yml.
# Suites (09 §2): A ledger core · B crypto · C auth · D sync · E data/RLS · G subscription
# run on every commit as they land in their milestones; M0 wires the harness with
# hello-world tests. F (UI) is release-candidate only; H before pilot.
set -euo pipefail
cd "$(dirname "$0")/.."
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

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

step "analyze"
dart analyze --fatal-infos scripts
for p in packages/*; do (cd "$p" && dart analyze --fatal-infos); done
(cd app && flutter analyze --fatal-infos)

step "tests — pure packages (suites A/B/D/E as they land)"
for p in packages/*; do (cd "$p" && dart test); done

step "tests — app"
(cd app && flutter test)

printf '\n\033[1;32mCI green.\033[0m\n'
