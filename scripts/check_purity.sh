#!/usr/bin/env bash
# scripts/check_purity.sh — package boundary rules, CI-enforced (CLAUDE.md § Layout, rule 3, rule 7).
#   packages/*      : no Flutter imports
#   core_ledger,
#   core_crypto     : additionally no dart:io, no DateTime.now(), no Random(), no dart:math
#                     (clock and RNG are injected; all crypto via libsodium)
#   app/lib         : no hex colour literals outside the generated tokens file
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
report() { echo "PURITY: $1"; fail=1; }

hits=$(grep -rnE "^import 'package:flutter" packages --include='*.dart' || true)
[ -n "$hits" ] && { echo "$hits"; report "Flutter import inside packages/ (pure Dart only)"; }

for p in core_ledger core_crypto; do
  hits=$(grep -rnE "^import 'dart:(io|math)'" packages/$p/lib --include='*.dart' || true)
  [ -n "$hits" ] && { echo "$hits"; report "$p imports dart:io / dart:math (no I/O; RNG is injected, crypto via libsodium)"; }
  hits=$(grep -rnE "DateTime\.now\(\)|\bRandom\(" packages/$p/lib --include='*.dart' | grep -vE '^[^:]+:[0-9]+:\s*//' || true)  # comments may name the rule
  [ -n "$hits" ] && { echo "$hits"; report "$p reads the clock or RNG directly (must be injected — 09 §1)"; }
done

hits=$(grep -rnE "Color\(0x|Color\.fromARGB|Color\.fromRGBO|#[0-9A-Fa-f]{6}\b" app/lib --include='*.dart' \
       | grep -v "app/lib/shared/tokens.dart" || true)
[ -n "$hits" ] && { echo "$hits"; report "hex colour literal in app/lib — use tokens (design/tokens/tokens.json)"; }

[ $fail -eq 0 ] && echo "purity ok"
exit $fail
