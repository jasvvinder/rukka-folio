#!/usr/bin/env bash
# Release-build hardening gate — 09 §4 (🔒, client-hardening gates; ADR 2026-09-05):
#
#   "release lane carries --obfuscate --split-debug-info and never the pinning-off define"
#
# Plus 09 §1 (🔒) / ADR 2026-09-05i §7: "the release lane asserts [HOSTILE_ENVELOPES] is
# absent from the build, exactly as it does for the pinning-off define" — the hostile-client
# fixture define. And, owner-directed 4 Oct 2026: never the dev-only demo-phone define
# RF_DEMO_PHONES (app/lib/features/auth/phone_shape.dart), and — since the same day —
# any RF_DEMO_ define, so the demo roster RF_DEMO_ROSTER too (app/lib/features/demo).
#
# Every clause is checkable from the build configuration alone, so they run on
# every push rather than waiting for M14's device gates (ADR 2026-09-15 § Consequences).
#
# Fail-closed by construction: a release build that cannot be found is not a pass.
# Until a release build exists, the release LANE fails and the others report the gap —
# a shipped release with no obfuscation is exactly what this gate is for.
set -euo pipefail
cd "$(dirname "$0")/.."

LANE="${LANE:-push}"
red()  { printf '\033[1;31m%s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$1"; }

# Release build invocations, wherever they are declared.
# bash 3.2 (macOS): no mapfile, and `set -u` dislikes empty arrays — plain string.
HITS="$(grep -rnE 'flutter[[:space:]]+build[[:space:]]+(ipa|apk|appbundle|ios|macos)' \
  .github scripts 2>/dev/null || true)"

if [ -z "$HITS" ]; then
  if [ "$LANE" = release ]; then
    red "FAIL — the release lane ran with no release build defined."
    red "      09 §4 requires --obfuscate --split-debug-info on the release build;"
    red "      there is nothing to assert that against. Define the build first."
    exit 1
  fi
  warn "release build not defined yet — 09 §4's flags cannot be asserted."
  warn "  When one lands it must carry --obfuscate --split-debug-info and a non-empty"
  warn "  RF_SPKI_PINS, and never HOSTILE_ENVELOPES or any RF_DEMO_ define. This gate fails the"
  warn "  release lane until then."
  exit 0
fi

fail=0
count=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  count=$((count + 1))
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; cmd="${hit#*:*:}"
  case "$cmd" in
    *--obfuscate*) ;;
    *) red "FAIL $file:$line — release build without --obfuscate (09 §4)"; fail=1 ;;
  esac
  case "$cmd" in
    *--split-debug-info*) ;;
    *) red "FAIL $file:$line — release build without --split-debug-info (09 §4)"; fail=1 ;;
  esac
  # The pinning-off define: an empty RF_SPKI_PINS selects SpkiPins.localDev(),
  # the only unpinned build (05 §1 🔒). A release must never select it.
  # Tested with grep, not a case glob: `*RF_SPKI_PINS=''*` undergoes quote
  # removal and collapses to `*RF_SPKI_PINS=*`, which matches every build.
  if ! printf '%s' "$cmd" | grep -q 'RF_SPKI_PINS'; then
    red "FAIL $file:$line — release build sets no RF_SPKI_PINS at all; an absent"
    red "     define is the unpinned local-dev set (05 §1 🔒)"; fail=1
  elif ! printf '%s' "$cmd" | grep -qE 'RF_SPKI_PINS=[^[:space:]\"'"'"']'; then
    red "FAIL $file:$line — release build ships an EMPTY RF_SPKI_PINS: that is the"
    red "     pinning-off define (05 §1 🔒 — only a local-dev build may disable it)"; fail=1
  fi
  # The hostile-client fixture define (09 §1, ADR 2026-09-05i §7): a test-only
  # switch that makes the client emit hostile envelopes. Any mention fails,
  # whatever the value — the spec asserts the define absent, not false.
  if printf '%s' "$cmd" | grep -q 'HOSTILE_ENVELOPES'; then
    red "FAIL $file:$line — release build carries HOSTILE_ENVELOPES: the hostile-client"
    red "     fixture define must be absent from a release build (09 §1, ADR 2026-09-05i §7)"; fail=1
  fi
  # The demo-phone define (owner-directed 4 Oct 2026): RF_DEMO_PHONES lets a dev
  # build accept the synthetic 5XXXXXXXXX demo range, which no real Indian mobile
  # can hold. The app already ignores it in release mode; this is the second lock.
  # Any mention fails, whatever the value — `=false` in a release build is still
  # a dev define that has no business there.
  # Since 4 Oct 2026 the check covers every `RF_DEMO_` define, so the demo
  # roster (RF_DEMO_ROSTER — base64 of a git-ignored file of real names and
  # numbers, app/lib/features/demo) is refused by the same lock.
  if printf '%s' "$cmd" | grep -q 'RF_DEMO_'; then
    red "FAIL $file:$line — release build carries an RF_DEMO_ define (RF_DEMO_PHONES,"
    red "     RF_DEMO_ROSTER, …): dev-only demo switches must never reach a release build"; fail=1
  fi
done <<EOF
$HITS
EOF

[ "$fail" -eq 0 ] || exit 1
printf '   %d release build(s) carry --obfuscate, --split-debug-info and a pin set, and no hostile-fixture or demo-phone define.\n' "$count"
