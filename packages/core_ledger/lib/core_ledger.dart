/// Ledger engine: entries, verbs to postings, invariants, amend/reverse, periods, balances (02). M1.
///
/// Spec owner: `docs/02-ledger-rules.md`. Pure Dart — no Flutter, and for `core_*`
/// no I/O, no `DateTime.now()`, no `Random()` (CLAUDE.md rule 3; CI-enforced by
/// `scripts/check_purity.sh`).
library;

/// Package identity used by the M0 hello-world gate. Real API lands per milestone.
const String packageName = 'core_ledger';
