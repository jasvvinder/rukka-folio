#!/usr/bin/env bash
# PostToolUse (Write|Edit). Formats the edited .dart file, analyzes its package,
# and re-runs scripts/check_purity.sh when the edit touched packages/ or app/lib.
# Failures are fed back to Claude as a blocking reason so they get fixed immediately.
set -uo pipefail
cd "$(dirname "$0")/../.."
f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)
[ -z "$f" ] && exit 0
case "$f" in
  /*) rel="${f#"$PWD"/}" ;;
  *)  rel="$f" ;;
esac
[ -f "$rel" ] || exit 0

out=""
if [[ "$rel" == *.dart ]]; then
  dart format "$rel" >/dev/null 2>&1 || out+="dart format failed on $rel"$'\n'
  # nearest pubspec.yaml above the file = its package
  d=$(dirname "$rel")
  while [ "$d" != "." ] && [ ! -f "$d/pubspec.yaml" ]; do d=$(dirname "$d"); done
  if [ -f "$d/pubspec.yaml" ] && [ "$d" != "." ]; then
    if [[ "$d" == app* ]]; then
      res=$(cd "$d" && flutter analyze --fatal-infos --no-pub 2>&1) || out+="flutter analyze ($d):"$'\n'"$res"$'\n'
    else
      res=$(cd "$d" && dart analyze --fatal-infos 2>&1) || out+="dart analyze ($d):"$'\n'"$res"$'\n'
    fi
  fi
fi
if [[ "$rel" == packages/* || "$rel" == app/lib/* ]]; then
  res=$(scripts/check_purity.sh 2>&1) || out+="check_purity.sh:"$'\n'"$res"$'\n'
fi

if [ -n "$out" ]; then
  jq -n --arg r "$out" '{decision:"block", reason:("Post-edit gate failed (fix before continuing):\n"+$r)}'
fi
exit 0
