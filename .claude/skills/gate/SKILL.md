---
name: gate
description: Run the CI gate (scripts/ci.sh) for a lane and report failures grouped by step and suite, with the fix for each. Use before handing files to the owner, or when asked "does CI pass".
---

# /gate $ARGUMENTS

Run the gate exactly as CI does. `$ARGUMENTS` is the lane: `push` (default), `nightly`, `rc`, `release`
(ADR 2026-09-05i §2). Until `ci.sh` grows its `LANE` switch the variable is passed through and ignored;
say so in the report if a non-push lane was requested.

```bash
LANE=${ARGUMENTS:-push} ./scripts/ci.sh 2>&1 | tee "$CLAUDE_JOB_DIR/tmp/gate.log"
```
(Fall back to `/tmp/rukka-gate.log` when `$CLAUDE_JOB_DIR` is unset.) Timeout generously — Flutter
analyze and `flutter test` are the slow steps.

## Report
Lead with **green** or **red**. If red, one bullet per failing step in `ci.sh` order:
- **generated files** — which of `tokens.css`/`tokens.dart`/identifier ARBs drifted; fix is
  `dart run scripts/gen_tokens.dart` or `dart run scripts/gen_l10n_arb.dart`.
- **format** — files; fix is `dart format <paths>`.
- **purity** — the `PURITY:` lines verbatim; these are CLAUDE.md rules 3 and 7 and the hex-literal rule.
- **strings** — missing EN/PA/HI keys, placeholder drift, forbidden jargon (01 §1.3).
- **analyze** — per package, error count and the first three diagnostics.
- **tests** — per package: failed test names (they start with their suite id, so group by suite
  A/B/C/D/E/F1/G) and the assertion message. A failing golden in suite A means the engine and the
  worked examples disagree: **stop and ask**, do not patch the fixture (CLAUDE.md § Accounting authority).

Then fix what is mechanical (format, generated files, analyzer infos) and re-run once. Leave
behavioural failures to the caller with the diagnosis. Never `git commit`.
