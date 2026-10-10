#!/usr/bin/env bash
# run_journeys.sh — the end-to-end journey harness (release-readiness phase 0, owner 6 Oct 2026).
#
# Drives the REAL app (main → bootstrap) through each 13 §5 journey on an Android device or
# emulator against the hosted rukka-folio-dev project, and REPORTS — it never fixes.
#
#   scripts/run_journeys.sh                    # every journey, on the running emulator
#   scripts/run_journeys.sh emulator-5554      # a given device id (`flutter devices`)
#   JOURNEYS="f1_myself f2_first_entry" scripts/run_journeys.sh   # a subset
#   RF_JOURNEY_PURPOSE=myself scripts/run_journeys.sh             # F2's purpose card (default family)
#
# Each journey starts from a fresh install (ADR 2026-10-06b: a fresh install starts at S0.0 with no
# launch route): the app is uninstalled before every run, so no data, keystore item or PIN carries
# over. A journey uses a fresh random +91 5… demo number (OTP 123456 on dev, RF_DEMO_PHONES).
#
# Output (app/build is git-ignored):
#   app/build/journeys/<journey>/<journey>__<nn>-<S-id>.png   one screenshot per step
#   app/build/journeys/<journey>/result.json                  that journey's steps + first failure
#   app/build/journeys/<journey>/flutter_test.log             the run's full output
#   app/build/journeys/report.json                            every journey, machine-readable
# and one verdict line per journey on stdout, with each defect under it.
#
# Verdicts: PASS only when the journey recorded no failure and no defect AND `flutter test` exited 0
# (the two must agree — a test that failed outside the step loop, e.g. an uncaught async error from
# main(), turns a PASS result into FAIL). The script exits 1 when any journey run now is not PASS,
# 2 on a setup error, 0 otherwise.
#
# Print sheet (desk 191 a): a journey that prints (S0.5b's recovery sheet) opens Android's own print
# activity, which the test cannot drive. scripts/journey_print_watch.py runs beside each journey and
# taps Save as PDF -> save; it is started before the journey and stopped (kill + wait) after it, and
# on any exit of this script (trap EXIT). Its taps go to app/build/journeys/<journey>/print_watch.log.
# It only dumps the UI while the print or save activity is in front: a dump turns accessibility on,
# and over the app under test that leaves a SemanticsHandle the test framework fails on.
#
# One retry (desk 191 b): a run whose output says "Service connection disposed" (the VM service
# dropping while the test loads) is run once more from a fresh install. The retry is said on stderr,
# at the head of flutter_test.log, and as a warning in report.json; the first attempt's output is
# kept as flutter_test.attempt1.log.
#
# Debug only, like scripts/run_dev.sh: RF_DEMO_PHONES is refused by a release build.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ID="com.rukkafolio.rukka_folio"
OUT="$ROOT/app/build/journeys"
ALL_JOURNEYS="f1_myself f1_business f1_family f1_trust f1b_sign_in f2_first_entry"
JOURNEYS="${JOURNEYS:-$ALL_JOURNEYS}"

file_of() {
  case "$1" in
    f1_myself) echo f1_myself_test.dart ;;
    f1_business) echo f1_business_test.dart ;;
    f1_family) echo f1_family_test.dart ;;
    f1_trust) echo f1_trust_test.dart ;;
    f1b_sign_in) echo f1b_sign_in_unknown_number_test.dart ;;
    f2_first_entry) echo f2_first_entry_test.dart ;;
    *) return 1 ;;
  esac
}

# The dev project ref — the same lookup as scripts/run_dev.sh.
REF="$(cat "$ROOT/server/supabase/.temp/project-ref" 2>/dev/null || true)"
if [ -z "$REF" ] && [ -f "$ROOT/.env" ]; then
  REF="$(sed -n 's/^SUPABASE_PROJECT_REF=\([a-z0-9]*\).*/\1/p' "$ROOT/.env" | head -1)"
fi
[ -n "$REF" ] || { echo "no dev project ref — run 'supabase link' in server/ or set SUPABASE_PROJECT_REF in .env" >&2; exit 2; }

ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
[ -x "$ADB" ] || ADB="$(command -v adb || true)"
[ -n "$ADB" ] || { echo "adb not found — set ANDROID_HOME" >&2; exit 2; }

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  DEVICE="$("$ADB" devices | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ {print $1; exit}')"
fi
[ -n "$DEVICE" ] || { echo "no running emulator — start one: flutter emulators --launch rf_min" >&2; exit 2; }
"$ADB" -s "$DEVICE" wait-for-device
# After a reboot the user's credential-encrypted storage stays locked until the device PIN is entered, and Android
# then reports "Activity class … does not exist" for every launch (6 Oct: six NO-RESULTs). Fail early and say so.
if [ "$("$ADB" -s "$DEVICE" shell getprop sys.user.0.ce_available | tr -d '\r')" != "true" ]; then
  echo "$DEVICE is at its lock screen since boot — unlock it (rf_min PIN 1111), then re-run" >&2; exit 2
fi

mkdir -p "$OUT"
echo "journeys on $DEVICE against rukka-folio-dev ($REF) — demo numbers +91 5…, OTP 123456" >&2

# The print-sheet watcher of the journey in flight; stopped after each journey and on any exit.
WATCH_PID=""
start_print_watch() {
  ADB="$ADB" python3 "$ROOT/scripts/journey_print_watch.py" "$DEVICE" 3600 >>"$1/print_watch.log" 2>&1 &
  WATCH_PID=$!
}
stop_print_watch() {
  if [ -n "$WATCH_PID" ]; then
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true
    WATCH_PID=""
  fi
}
trap stop_print_watch EXIT
trap 'exit 130' INT TERM

# One attempt at journey $1 (file $2) from a fresh install, its output in $3.
run_journey() {
  # Fresh install: no books, no keystore items, no PIN, no onboarded flag.
  "$ADB" -s "$DEVICE" uninstall "$APP_ID" >/dev/null 2>&1 || true
  flutter test "integration_test/journeys/$2" -d "$DEVICE" --no-uninstall \
    --dart-define=RF_API_BASE="https://$REF.supabase.co/functions/v1/" \
    --dart-define=RF_DEMO_PHONES=true \
    ${RF_JOURNEY_PURPOSE:+--dart-define=RF_JOURNEY_PURPOSE=$RF_JOURNEY_PURPOSE} \
    >"$3" 2>&1
}

cd "$ROOT/app"
UNKNOWN=0
for J in $JOURNEYS; do
  F="$(file_of "$J")" || { echo "unknown journey: $J" >&2; UNKNOWN=1; continue; }
  DIR="$OUT/$J"
  rm -rf "$DIR"; mkdir -p "$DIR"
  start=$(date +%s)
  start_print_watch "$DIR"
  run_journey "$J" "$F" "$DIR/flutter_test.log"
  code=$?
  # A VM-service drop while the test loads is the harness, not the app: run it once more.
  if [ "$code" -ne 0 ] && grep -q 'Service connection disposed' "$DIR/flutter_test.log"; then
    msg="retried $J once: the first attempt (exit $code) reported 'Service connection disposed' at test load"
    echo "$msg" >&2
    mv "$DIR/flutter_test.log" "$DIR/flutter_test.attempt1.log"
    echo "$msg" >"$DIR/retried"
    run_journey "$J" "$F" "$DIR/flutter_test.retry.log"
    code=$?
    { echo "[run_journeys] $msg — this is the retry's output; the first is flutter_test.attempt1.log"
      cat "$DIR/flutter_test.retry.log"; } >"$DIR/flutter_test.log"
    rm -f "$DIR/flutter_test.retry.log"
  fi
  stop_print_watch
  echo "$code" >"$DIR/exit_code"
  echo "$(( $(date +%s) - start ))" >"$DIR/wall_seconds"
  # Screenshots + result.json live in the app's cache dir (a debug build is run-as-able).
  "$ADB" -s "$DEVICE" exec-out run-as "$APP_ID" tar -cf - -C cache "journeys/$J" 2>/dev/null \
    | tar -xf - -C "$OUT/.." 2>/dev/null || true
  # Fallback: the JOURNEY_RESULT line the test prints, when the files could not be pulled.
  if [ ! -s "$DIR/result.json" ]; then
    grep -o 'JOURNEY_RESULT .*' "$DIR/flutter_test.log" | tail -1 | sed 's/^JOURNEY_RESULT //' >"$DIR/result.json" || true
    [ -s "$DIR/result.json" ] || rm -f "$DIR/result.json"
  fi
done

# report.json covers every journey with a result on disk (a subset run keeps the others' last
# results); one verdict line is printed per journey run now.
python3 - "$OUT" "$ALL_JOURNEYS" $JOURNEYS <<'PY'
import json, os, sys, datetime
bad = 0
out, everything, ran = sys.argv[1], sys.argv[2].split(), sys.argv[3:]
names = [n for n in everything if n in ran or os.path.isdir(os.path.join(out, n))]
report = {"generated_at": datetime.datetime.now().isoformat(timespec="seconds"), "journeys": []}
for name in names:
    d = os.path.join(out, name)
    r = None
    try:
        with open(os.path.join(d, "result.json")) as f:
            r = json.load(f)
    except Exception:
        pass
    code = open(os.path.join(d, "exit_code")).read().strip() if os.path.exists(os.path.join(d, "exit_code")) else "?"
    if r is None:
        tail = []
        log = os.path.join(d, "flutter_test.log")
        if os.path.exists(log):
            tail = [l.rstrip() for l in open(log, errors="replace").readlines()[-25:]]
        r = {"journey": name, "verdict": "NO-RESULT", "failure": {"journey": name, "reason": "the test produced no result (build or launch failure?)", "log_tail": tail}}
    if r.get("verdict") == "RUNNING":
        r["verdict"] = "FAIL"
        r.setdefault("failure", None)
        r["failure"] = r["failure"] or {"journey": name, "reason": "the run ended before the journey finished (crash or timeout)", "last_step": (r.get("steps") or [{}])[-1]}
    r["exit_code"] = code
    retried = os.path.join(d, "retried")
    if os.path.exists(retried):
        r.setdefault("warnings", []).append(open(retried).read().strip())
    # The verdict and the test's exit code must agree; a disagreement is a FAIL with its own reason.
    if r["verdict"] == "PASS" and code != "0":
        r["verdict"] = "FAIL"
        r["failure"] = {"journey": name, "reason": f"the journey's steps passed but flutter test exited {code} (an error outside the step loop?) — see flutter_test.log"}
    elif r["verdict"] != "PASS" and code == "0":
        r.setdefault("warnings", []).append(f"verdict {r['verdict']} but flutter test exited 0 — the test did not fail on it")
    report["journeys"].append(r)
    if name not in ran:
        continue
    f = r.get("failure") or {}
    defects = r.get("defects") or []
    if r["verdict"] == "PASS":
        print(f"PASS  {name}  ({len(r.get('steps', []))} steps)")
    else:
        bad += 1
        if f:
            where = f"step {f.get('step', '?')} {f.get('sid', '')}".strip()
            print(f"{r['verdict']}  {name}  at {where}: {f.get('reason', '')}  [{f.get('screenshot') or 'no screenshot'}]")
        else:
            print(f"{r['verdict']}  {name}  completed with {len(defects)} defect(s)")
    for d in defects:
        loc = f" @ {d['location']}" if d.get("location") else ""
        print(f"      defect {d.get('sid', '?')}: {d.get('reason', '')}{loc}  [{d.get('screenshot') or 'no screenshot'}]")
    for w in r.get("warnings") or []:
        print(f"      warning: {w}")
for name in ran:
    if name not in everything:
        bad += 1
with open(os.path.join(out, "report.json"), "w") as fh:
    json.dump(report, fh, indent=2, ensure_ascii=False)
print(f"report: {os.path.join(out, 'report.json')}")
sys.exit(1 if bad else 0)
PY
status=$?
[ "$UNKNOWN" -eq 0 ] || status=1
exit "$status"
