/// Local persistence: Drift + SQLCipher, projector (pure), snapshots, recompute (03). M2.
///
/// Spec owner: `docs/03-data-model.md`. Pure Dart — no Flutter, and for `core_*`
/// no I/O, no `DateTime.now()`, no `Random()` (CLAUDE.md rule 3; CI-enforced by
/// `scripts/check_purity.sh`).
library;

/// Package identity used by the M0 hello-world gate. Real API lands per milestone.
const String packageName = 'data';
