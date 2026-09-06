#!/usr/bin/env bash
# scripts/check_purity.sh — package boundary rules, CI-enforced (CLAUDE.md § Layout, rule 3, rule 7).
#   packages/*      : no Flutter imports
#   core_ledger,
#   core_crypto     : additionally no dart:io, no DateTime.now(), no Random(), no dart:math
#                     (clock and RNG are injected; all crypto via libsodium)
#   app/lib         : no hex colour literals outside the generated tokens file
#   test trees      : no real-looking Indian mobile / Aadhaar / PAN strings (ADR 2026-09-05i §7;
#                     fixtures use +91 99999 xxxxx and the fictional Sharma/Kaur/Verma names)
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
report() { echo "PURITY: $1"; fail=1; }

hits=$(grep -rnE "^import 'package:flutter" packages testing --include='*.dart' || true)
[ -n "$hits" ] && { echo "$hits"; report "Flutter import inside packages/ or testing/ (pure Dart only)"; }

for p in core_ledger core_crypto; do
  hits=$(grep -rnE "^import 'dart:(io|math)'" packages/$p/lib --include='*.dart' || true)
  [ -n "$hits" ] && { echo "$hits"; report "$p imports dart:io / dart:math (no I/O; RNG is injected, crypto via libsodium)"; }
  hits=$(grep -rnE "DateTime\.now\(\)|\bRandom\(" packages/$p/lib --include='*.dart' | grep -vE '^[^:]+:[0-9]+:\s*//' || true)  # comments may name the rule
  [ -n "$hits" ] && { echo "$hits"; report "$p reads the clock or RNG directly (must be injected — 09 §1)"; }
done

hits=$(grep -rnE "Color\(0x|Color\.fromARGB|Color\.fromRGBO|#[0-9A-Fa-f]{6}\b" app/lib --include='*.dart' \
       | grep -v "app/lib/shared/tokens.dart" || true)
[ -n "$hits" ] && { echo "$hits"; report "hex colour literal in app/lib — use tokens (design/tokens/tokens.json)"; }

# Memory hygiene (ADR 2026-09-05 §8, B-04-8): key material in core_crypto lives in Uint8List /
# SecureKey, never in a Dart String. Flag any String-typed field, parameter or local whose name says
# it holds a key, secret, seed, share, nonce, signature or ciphertext. Ids (`bookId`, `deviceId`),
# `keyVersion` and record `kind`s are Strings/ints by design and are excluded by the pattern.
hits=$(grep -rnE "\bString\??\s+[A-Za-z0-9_]*([Kk]ey|[Ss]ecret|[Ss]eed|[Ss]hare|[Nn]once|[Ss]ignature|[Ss]ig\b|[Cc]iphertext|[Pp]riv|[Pp]laintext)[A-Za-z0-9_]*\b" packages/core_crypto/lib --include='*.dart' \
       | grep -vE "[Kk]eyVersion|[Kk]eyRef|[Kk]eyId|[Kk]ind\b|^[^:]+:[0-9]+:\s*//" || true)
[ -n "$hits" ] && { echo "$hits"; report "String-typed key material in core_crypto (use Uint8List/SecureKey — ADR 2026-09-05 §8)"; }
hits=$(grep -rnE "MethodChannel|EventChannel" packages/core_crypto/lib packages/core_ledger/lib --include='*.dart' || true)
[ -n "$hits" ] && { echo "$hits"; report "platform channel inside a core package (keys cross only over the libsodium FFI — ADR 2026-09-05 §8)"; }

# Test-data hygiene (ADR 2026-09-05i §7). Mobile: 10 digits starting 6–9 as a standalone token,
# or any +91 number outside the reserved 99999 block. Aadhaar: 4-4-4 digit groups. PAN: AAAAA9999A.
# Paise amounts are never written with a leading 6–9 and exactly ten digits in fixtures; if one
# ever is, spell it as an expression (e.g. `rs(60000000)`) rather than widening this rule.
test_trees=$(ls -d packages/*/test app/test testing 2>/dev/null || true)
if [ -n "$test_trees" ]; then
  hits=$(grep -rnE "(^|[^0-9A-Za-z_])[6-9][0-9]{9}([^0-9A-Za-z_]|$)|\+91[ -]?(?!99999)[0-9][0-9 -]{9,11}" $test_trees --include='*.dart' --include='*.json' --include='*.csv' --include='*.md' -P 2>/dev/null \
         | grep -vE "\+91 ?99999" || true)
  [ -n "$hits" ] && { echo "$hits"; report "real-looking Indian mobile number in a test tree (use +91 99999 xxxxx)"; }
  hits=$(grep -rnE "\b[0-9]{4} [0-9]{4} [0-9]{4}\b" $test_trees --include='*.dart' --include='*.json' --include='*.csv' || true)
  [ -n "$hits" ] && { echo "$hits"; report "Aadhaar-shaped string in a test tree"; }
  hits=$(grep -rnE "\b[A-Z]{5}[0-9]{4}[A-Z]\b" $test_trees --include='*.dart' --include='*.json' --include='*.csv' || true)
  [ -n "$hits" ] && { echo "$hits"; report "PAN-shaped string in a test tree"; }
fi

[ $fail -eq 0 ] && echo "purity ok"
exit $fail
