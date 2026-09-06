---
name: sync-slice
description: Build a packages/sync_engine module (outbox/push, pull cursors, key sync, signed-record application, revocation counting) tests-first on the two-client harness, suite D. Use for any sync_engine lane.
---

# /sync-slice $ARGUMENTS

`$ARGUMENTS` = modules (`outbox pull revocation-count`).

## Read (sections only)
`docs/05-sync-protocol.md` — the sections your modules own (§3 push, §4 pull, §5 meta/keys, §8 bootstrap, §9 status) · ADR 2026-09-05b §1–§6 · ADR 2026-09-06 §3 (k counted records, cut-off moves earlier, re-split does not reset) · `docs/09-acceptance-tests.md` §2 D · `testing/harness/lib/harness.dart` (SimulatedDevice, Relay — how D-05b-2/3/4 are written).

## Rules
- Pure Dart, no Flutter (CI-enforced). `sync_engine` may do I/O through **injected** transport and clock interfaces (`SyncTransport`, `Clock`) — never `DateTime.now()` or `Random()` directly, so the harness stays deterministic.
- Everything the server says is a claim until verified: `ChainVerifier` passes **and** the blob decrypts once before a row is marked `verified` (M3 changelog Open); unsigned revocation → suspend, never wipe (ADR 05b §2).
- Revocation cut-off = `seq` of the signed record; for guardians' k-of-n = the k-th smallest `seq` among counted records, recomputed from the record set, never cached (ADR 2026-09-06 §3; tests D-06a-1…4).
- `author_seq` gaps → `held`/gap state to the projector; `store_epoch` change → full re-pull with zero duplicates and re-push of un-observed outbox rows (ADR 05b §3, §6).
- Key-sync before drain: new wrapped keys are applied before envelopes are opened; a missing key is `key_wait`, not a quarantine (05 §4).
- Status surface (05 §9) feeds 07 §1.7 — expose a typed state, no strings.

## Tests (suite D, on the harness)
Ids `D-05-<n>`, `D-05b-<n>`, `D-06a-<n>` — next free from `dart run scripts/check_coverage.dart`. Every 05 §10 and ADR 05b Open case has one: withheld envelope blocks close, orphan amend held then counted once, unsigned revocation suspends, backdated push quarantined by seq, epoch re-pull zero duplicates, flood throttled + quota-stopped, and the four D-06a cases. Run `dart test` in `packages/sync_engine` and `testing/harness` by file while working, once whole at the end.

## Return (to /fanout)
files · tests (ids) · open · notes (any transport shape the `server` lane must match — name the function and field).
