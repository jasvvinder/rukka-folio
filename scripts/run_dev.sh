#!/usr/bin/env bash
# run_dev.sh — run the app (debug) against the hosted rukka-folio-dev project, in one command.
#
#   scripts/run_dev.sh            # iPhone 17 simulator
#   scripts/run_dev.sh ipad       # iPad Pro 13-inch (M5) simulator
#   scripts/run_dev.sh "<name>"   # any simulator or plugged-in device, as `flutter devices` names it
#
# Debug only (`flutter run`, never `flutter build`): RF_SPKI_PINS stays empty, which is the local-dev
# pin set (spki_pins.dart:73) — a release build refuses it (scripts/check_release_flags.sh), and the
# same check refuses RF_DEMO_PHONES. RF_DEMO_PHONES=true lets S0.2 accept the dev-only +91 5… demo
# numbers (never a real Indian mobile); on dev every number signs in with OTP 123456 (ADR 2026-09-25 §1).
#
# Demo builder (owner-directed 4 Oct 2026, debug only): when the git-ignored .demo/demo_roster.json
# exists, it is passed as RF_DEMO_ROSTER (base64) so S0.3 can offer "Demo: build <name>'s books" to a
# roster number that signs in; without it the app uses its fictional roster. DEMO=1 starts the app at
# the signup chain (splash → language → welcome → S0.2 → S0.3) instead of Home:
#   DEMO=1 scripts/run_dev.sh       # one person per fresh install — erase the simulator between people
# The roster carries real names and numbers: it is never echoed here, and check_release_flags.sh
# fails any release build that carries an RF_DEMO_ define.
# Hot reload: press r in this terminal; R restarts; q quits.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The dev project ref: the supabase CLI's link cache first, then SUPABASE_PROJECT_REF in .env.
REF="$(cat "$ROOT/server/supabase/.temp/project-ref" 2>/dev/null || true)"
if [ -z "$REF" ] && [ -f "$ROOT/.env" ]; then
  REF="$(sed -n 's/^SUPABASE_PROJECT_REF=\([a-z0-9]*\).*/\1/p' "$ROOT/.env" | head -1)"
fi
[ -n "$REF" ] || { echo "no dev project ref — run 'supabase link' in server/ or set SUPABASE_PROJECT_REF in .env" >&2; exit 1; }

case "${1:-iphone}" in
  iphone) DEVICE="iPhone 17" ;;
  ipad)   DEVICE="iPad Pro 13-inch (M5)" ;;
  *)      DEVICE="$1" ;;
esac

# Boot the simulator if it is one and is not running (a physical device is simply passed through).
UDID="$(xcrun simctl list devices available 2>/dev/null | grep -F "    $DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
if [ -n "$UDID" ]; then
  xcrun simctl boot "$UDID" 2>/dev/null || true   # already booted → harmless error
  open -a Simulator 2>/dev/null || echo "no Simulator.app — running headless (xcrun simctl io booted screenshot <file>)" >&2
  DEVICE="$UDID"
fi

EXTRA=()
ROSTER="$ROOT/.demo/demo_roster.json"
if [ -f "$ROSTER" ]; then
  EXTRA+=("--dart-define=RF_DEMO_ROSTER=$(base64 < "$ROSTER" | tr -d '\n')")
  echo "demo roster: .demo/demo_roster.json" >&2
else
  echo "demo roster: fictional (no .demo/demo_roster.json)" >&2
fi
if [ "${DEMO:-}" = 1 ]; then
  EXTRA+=(--route /onboarding/splash)
fi

echo "rukka-folio-dev ($REF) on $DEVICE — demo numbers +91 5…, OTP 123456" >&2
cd "$ROOT/app"
exec flutter run -d "$DEVICE" \
  --dart-define=RF_API_BASE="https://$REF.supabase.co/functions/v1/" \
  --dart-define=RF_DEMO_PHONES=true \
  ${EXTRA[@]+"${EXTRA[@]}"}
