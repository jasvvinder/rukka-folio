---
name: server
description: Build the Supabase side — migrations with RLS, edge functions (sync-push/pull/meta, auth-challenge, billing-webhook), and the hostile-query RLS tests — from 03 §2, 05, 06 and ADRs 05b/05c/05d. Use for any server/ lane.
---

# /server $ARGUMENTS

`$ARGUMENTS` = the modules (`migrations rls sync-push`).

## Read (sections only)
`docs/03-data-model.md` §2.1–§2.5, §5, §6 · `docs/05-sync-protocol.md` §1, §3–§5, §8 · `docs/06-auth-devices.md` §2–§4 · ADR 2026-09-05b §1, §3, §5, §6, §7 · ADR 2026-09-05c §1–§8 · ADR 2026-09-05d (certified-only RLS, windows) · ADR 2026-09-05g/h only for billing/console modules.

## Layout
```
server/supabase/config.toml  migrations/NNNN_<topic>.sql  functions/<name>/index.ts  tests/rls/*.test.ts  deno.json
```
Secrets only in CI secrets and local `.env` (gitignored). Region: India (ap-south-1). `supabase db reset` must apply every migration and run the RLS tests.

## Rules that are 🔒 here
- **Envelopes are append-only:** the service role and every policy grant INSERT + SELECT only; **no UPDATE/DELETE grant on `envelopes`** (CLAUDE.md rule 2). Deletion is the `maintenance` role, retention only (ADR 05b §7, 03 §6).
- `seq` is one `bigserial` shared by envelopes and signed records (ADR 05b §5, Open 3) — the revocation cut-off compares across both.
- The server is content-blind: it stores `blob` + routing columns; `blob_hash = BLAKE2b-256(blob)` checked on push (05c §2); the eight shape checks (05c §5) refuse with named reasons.
- Structural facts (limits, roles, revocations) are **signed records**; a row without its record is a `meta_mismatch` the client logs (ADR 05b §1) — never let a function invent one.
- Phone numbers: `phone_ct` (KMS-encrypted) + `phone_hmac` only (05c); no plaintext phone column, no phone list in any dump.
- Claims through `SET LOCAL` per request on pooled connections (05c); certified devices only for tenant data (05d).
- Rate limits and quotas are the server's only "new powers" (ADR 05b §7): `rejected:quota`, `rejected:tenant_frozen`, throttle — never a silent drop.
- Money never appears server-side in plaintext; nothing here parses a payload.

## Functions
`sync-push` (idempotent by envelope_id, shape checks, quota, returns `seq` per accepted row) · `sync-pull` (`since_seq` cursor, `store_epoch` in every response) · `sync-meta` (wrapped keys, device certs, signed records, guardian-set history by `share_set_version`) · `auth-challenge` (OTP + device key challenge, 06 §2–§3, 426 min-version) · `billing-webhook` (stub until M13; idempotent by event id).

## Tests
- `tests/rls/` — table-driven hostile queries: cross-tenant SELECT/INSERT, UPDATE/DELETE on envelopes as every role, un-certified device reads, phone column absent. Ids `E-03-<n>` / `E-05b-<n>` / `E-05c-<n>` (next free from `check_coverage`).
- `deno test server/functions` — shape refusals named, idempotent replay, seq monotonic, epoch change → full re-pull.
- Wire both into `ci.sh` nightly/rc lanes (they are "scheduled — M4" today).

## Return (to /lane)
Write `.claude/lane-reports/<milestone>-<key>.json` as soon as you have anything to record and
keep it current (you have a turn cap) — `complete: false` until the task is wholly finished. Then
return the same object:
files · tests (ids) · open (every 🔒 conflict or 05 §11 / 03 §8 open item you hit) · notes (ops
checklist: PITR, KMS, bucket, sweep).
