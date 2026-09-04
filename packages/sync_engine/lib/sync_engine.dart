/// Sync engine: push/pull with seq cursors, meta/key channel, outbox (05). M4.
///
/// Spec owner: `docs/05-sync-protocol.md`. Pure Dart — no Flutter, and for `core_*`
/// no I/O, no `DateTime.now()`, no `Random()` (CLAUDE.md rule 3; CI-enforced by
/// `scripts/check_purity.sh`).
library;

/// Package identity used by the M0 hello-world gate. Real API lands per milestone.
const String packageName = 'sync_engine';
