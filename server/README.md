# server/ — the Supabase side of Rukka Folio

Content-blind by construction: the server stores opaque `blob`s plus routing columns, applies signed
records to rows for RLS, and hands out its own challenge–response JWT. It never parses a payload,
never sees a book key, never logs a request body, a phone number or a blob (CLAUDE.md rule 4).
Owning specs: 03 §2 (schema, RLS), 05 (sync), 06 (identity); ADRs 2026-09-05b/c/d, 2026-09-06.

```
supabase/config.toml          local dev (Docker) — platform auth OFF, private attachments bucket, pooler in transaction mode
supabase/migrations/0001…0005 identity · devices/keys · envelope store (one seq for envelopes + signed records) · billing/audit/ops · RLS + grants
supabase/seed.sql             LOCAL ONLY: rf_local / rf_local_maint login roles, store_epoch row
supabase/functions/_shared/   store.ts (the Tx seam) · store_pg.ts (Postgres, SET LOCAL claims) · store_mem.ts (deno test fake) · shape/records/claims/phone/sodium/…
supabase/functions/<name>/    sync-push · sync-pull · sync-meta · auth-challenge · billing-webhook (each index.ts exports `handler`, serves under import.meta.main)
supabase/functions/_tests/    suite E-server over the in-memory store (E-05-*, E-06-*, E-05b-8)
supabase/tests/rls/           schema.test.ts (static, libpg-query — no DB) · rls.test.ts (hostile queries; needs RF_TEST_DB_URL, else SKIPS)
deno.json                     tasks: test · test:functions · test:schema · test:rls · lint · fmt
```

## 1. Run

```sh
cd server
deno task test          # functions + schema tests; rls.test.ts prints SKIP without RF_TEST_DB_URL
deno task lint          # deno lint + fmt --check (ci.sh runs both)
supabase start && supabase db reset          # Docker: migrations + seed; then
RF_TEST_DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres deno task test:rls
supabase functions serve --env-file ../.env  # local edge runtime; functions read RF_* from .env
```

`scripts/ci.sh` runs `deno task lint && deno task test` on every push. The RLS suite runs where a
database exists: nightly and RC lanes set `RLS_REQUIRE=1` so a missing database fails instead of
skipping (ADR 2026-09-05i §2).

## 2. Wire (what the client meets)

Bytes travel base64url (the server also accepts standard base64). `hlc` and `seq` are bare JSON
integers; an HLC exceeds 2^53, so the server parses them exactly (`parseJsonBig`) and Dart reads
them as `int`. Every sync response carries `store_epoch` (05 §1).

| route | shape |
|---|---|
| `POST /sync-push {envelopes[]}` | `{store_epoch, results:[{envelope_id, result, seq?, check?, retry_after_ms?}]}` — results are the 05 §3 codes; `check` names the failing shape check |
| `GET /sync-pull?book_id&after_seq&limit≤500[&object_types=a,b][&fy=]` | `{store_epoch, envelopes[], next_seq}`; 404 `unknown_book` also covers "not your tenant"; 403 `no_role` |
| `GET /sync-meta[?after=<cursor>][&subject_user_id=]` | every 05 §5 table + `signed_records` (after seq) + `guardian_sets` (history by `share_set_version`) + `min_client_version` + `next` (null when drained) + `cursor` (always) |
| `POST /sync-meta/records {records[]}` | `{store_epoch, results:[{id, result, seq?, check?}]}` — records verified under the caller's device key, stored, projected |
| `POST /auth-challenge/otp/request · /otp/verify · /devices · /devices/certify · /challenge · /token · /refresh` | 06 §2–§4; see the header comment in `auth-challenge/index.ts` |
| `POST /billing-webhook` | `x-razorpay-signature` HMAC over the raw body; idempotent by event id; stub until M13 |

Any route answers `426 {error:"upgrade_required", min_client_version}` when `x-rukka-client-version`
is below `app_config.min_client_version.<sync|auth|billing>` (06 §4.5).

## 3. Roles and login provisioning

Migrations create two `NOLOGIN` roles and never a password:

| role | may | may not |
|---|---|---|
| `rf_api` | SELECT/INSERT per policy; `rf.*` helper functions; UPDATE on the ephemeral auth tables and the user's own profile columns | UPDATE/DELETE `envelopes` or `signed_records` (no grant exists); read `phone_ct`/`phone_hmac` (column grant excludes them); `rf.bump_store_epoch`; `rf.purge_ephemeral_auth`; touch `push_rate` directly |
| `rf_maintenance` | SELECT/DELETE `envelopes` (trigger limits DELETE to an erased owner's personal book), purge auth rows and 90-day-revoked keys, bump the store epoch | INSERT/UPDATE anything |

Hosted provisioning (ops, once per environment; passwords go to Edge Function secrets, never to git):

```sql
create role rf_api_login login password '<from the secret manager>' nobypassrls noinherit;
grant rf_api to rf_api_login;   alter role rf_api_login set role rf_api;
create role rf_maint_login login password '<…>' nobypassrls noinherit;
grant rf_maintenance to rf_maint_login;   alter role rf_maint_login set role rf_maintenance;
insert into store_epoch (id) values (true) on conflict do nothing;
```

`RF_API_DB_URL` points the functions at `rf_api_login` through the **transaction-mode pooler**
(port 6543 hosted; `[db.pooler]` locally). Claims are `SET LOCAL` per transaction
(`rf.set_claims`), so pooled connections never carry a user across requests (ADR 2026-09-05c §7;
tested by E-05c-7). `RF_MAINT_DB_URL` is used only by scheduled functions (deletion, purge, sweep).
Platform roles (`anon`, `authenticated`, `service_role`) hold no table grants at all: PostgREST is not
an API surface here (0005).

## 4. Secrets: phone keys, JWT key, webhook secret (Vault/KMS)

| secret | env | purpose | rotation |
|---|---|---|---|
| phone HMAC key (32 B) | `RF_PHONE_HMAC_KEY` | `phone_hmac = HMAC-SHA256(key, e164)` lookup (ADR 05c §4) | rotating re-keys every `phone_hmac`, `invitee_hmac`, `otp_challenges.phone_hmac`; plan a dual-key window or accept a re-verify |
| phone KEK (32 B) | `RF_PHONE_KEK` | `phone_ct = XChaCha20-Poly1305(kek, e164)` — decrypted only to send a code | **annual (proposed)**, re-encrypt in place under `rf_maintenance`; `phone_ct` carries the nonce, so a versioned prefix can be added without a schema change |
| JWT HMAC key (≥32 B) | `RF_JWT_HMAC_KEY` | our HS256 access tokens (06 §4), 15 min | rotate with a 15-minute dual-verify window |
| webhook secret | `PAYMENT_GATEWAY_WEBHOOK_SECRET` | gateway signature | per gateway console |

**Default: Supabase Vault** (CHANGELOG open item, 03 §11 item 6 — "lane S defaults to Vault unless the
owner says otherwise"). The keys live as Vault secrets in the project; Edge Functions receive them as
function secrets (`supabase secrets set RF_PHONE_KEK=…`), never via `.env` in a hosted build. Vault
gives us: encrypted at rest under the project's managed key, access audited, no plaintext in dumps.
What it does not give: HSM custody or per-use audit of *decryptions* — if the external crypto review
(lead-times §8) wants that, swap to a cloud KMS (AWS KMS in ap-south-1) behind the same two env
vars; nothing in the functions changes. Rule of thumb from ADR 2026-09-05h: the admin console role
has **no** decrypt right — only `auth-challenge` holds `RF_PHONE_KEK`.

## 5. Ops checklist (hosted project — ADR 2026-09-05c §1, §8; ADR 05b §8; 09 E-05c-8)

- [ ] **Region `ap-south-1` (Mumbai)**, Pro plan; project ref → `.env` (`SUPABASE_PROJECT_REF`). Data never leaves India (DPDP; 12 §7).
- [ ] **PITR 7 days** on; daily snapshots retained 30 days; **quarterly restore drill** → `REL-05c-1` artefact (report dated < 90 days, RTO/RPO within target). ⚠️ RTO/RPO numbers are 03 §11 open item 1.
- [ ] **Private `attachments` bucket**, per-tenant key prefix `<tenant_id>/<book_id>/<attachment_id>`, anonymous GET = 403; signed URLs: upload PUT-only single object 15 min, download 5 min (`_shared/storage.ts`, E-05b-8). Object written *before* the row.
- [ ] **Orphan sweep** (nightly, `rf_maintenance`): delete objects whose `attachments` row never landed after 24 h; lifecycle rules only for orphans. E-05c-8 live half runs in the nightly lane.
- [ ] **pg_cron** jobs under `rf_maintenance`: `rf.purge_ephemeral_auth()` hourly (24 h auth rows, 90 d revoked keys); user erasure (06 §9.3) after the 15-day cooling; `audit_events` aggregation after 24 months (`verification_events` are permanent).
- [ ] **Store epoch**: bump (`rf.bump_store_epoch(reason)`) after every restore or rebuild — clients reset cursors (05 §1). Never bump casually; every client re-pulls everything.
- [ ] **SPKI pin rotation** (05 §1 🔒): clients pin ≥ 2 SPKI hashes (current + backup) of the API host's chain at the intermediate-CA level. Runbook: (1) publish the backup pin in a release *before* any rotation; (2) rotate the certificate; (3) verify the exact chain with `openssl s_client -showcerts` and recompute pins (`openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`); (4) ship the next backup. A pin failure is a hard fail with no override; only local-dev builds disable pinning, and the release lane asserts it.
- [ ] **Edge Function secrets**: `RF_API_DB_URL`, `RF_MAINT_DB_URL`, `RF_JWT_HMAC_KEY`, `RF_PHONE_HMAC_KEY`, `RF_PHONE_KEK`, `OTP_PROVIDER` (+ key, DLT ids), `PAYMENT_GATEWAY_WEBHOOK_SECRET`. A hosted build with `OTP_PROVIDER=fake` sends nothing — deploy refuses it.
- [ ] **Metrics are plaintext counters only** (ADR 05b §8): rejections by `result`/`check`, push/pull latency, cursor lag, `write_lost`/`meta_mismatch` counts. No log line joins an envelope id to a phone.
- [ ] **Rate limits** (05 §3): 600 envelopes/min, 5,000/h, 50 MB/day per device via `rf.push_rate_check`; OTP 5/h + 10/day per number, 30/h per IP (⚠️ per-IP number is M6).

## 6. Open (owner)

See the lane's structured return and `CHANGELOG.md`: cold-storage `fy` tiering (05 §8) needs an
ops story, not a wire change; `recipient_fingerprint` on `wrapped_keys` is not in 03 §2.2; the live
half of E-05b-8 / E-05c-8 and the whole of `rls.test.ts` need the hosted (or Docker) database.
