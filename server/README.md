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
| `GET /sync-meta[?after=<cursor>][&subject_user_id=]` | every 05 §5 table + `signed_records` (after seq) + `guardian_sets` (history by `share_set_version`) + `min_client_version` + `next` (null when drained) + `cursor` (always). `entitlement_tokens` rows are `{id, tenant_id, token, expires_at, updated_at}`; `token` is base64url of `<payload_b64url>.<sig_b64url>`, an Ed25519 detached signature under `RF_ENTITLEMENT_KEY` over the canonical payload `{tenant_id, plan, limits{6}, period_end, grace_kind, grace_until, iat, exp}` in that order, times in epoch ms. `grace_until` is null unless `grace_kind = "dunning"`, and is then `subscriptions.grace_until` — the client reads it and never derives `period_end + 7 d`; a lapsed tenant has `period_end = iat`; unlimited is `-1`; no key id (ADR 2026-09-24b §6–§7; full format in `_shared/sodium.ts`) |
| `POST /sync-meta/records {records[]}` | `{store_epoch, results:[{id, result, seq?, check?}]}` — records verified under the caller's device key, stored, projected |
| `POST /sync-meta/invites {record, phone}` | `{invite_id, record_id, seq}` — the admin's signed `invite` record (payload `{roles, nonce}`) plus the invitee's E.164 number, which is HMAC'd and dropped; 403 `not_admin`, 409 `no_record`/`record_replayed`, 400 `bad_phone` (06 §7, 0008 ⚠️ SPEC) |
| `GET /sync-meta/invites` | `{invites:[{invite_id, tenant_id, roles, expires_at, created_by, status, nonce}]}` — the CALLER's own invites: at `sent` and addressed to its OTP-verified number, **or** accepted by the caller, inside the 7-day window. `status` is the invite's own, `"sent"` (a live offer) or `"accepted"` (spent — kept for S9.2's nonce, never an offer), and the `sent` rows come first (⚠️ SPEC, 0015 (c)). `nonce` is base64url, 16 B, the one the inviter's device drew and signed; the server relays it and never chooses one (ADR 2026-09-25b §1–§2, `rf.my_invites` 0015) |
| `POST /sync-meta/invites/accept {invite_id}` | `{invite_id, status:"joined_pending_verification", nonce}` (nonce as on `GET`, ADR 2026-09-25b §2); 403 `invite_not_for_you` (wrong number **or** unknown invite — identical, ADR 2026-09-05d §9), 410 `invite_expired`, 409 `invite_not_live` |
| `GET /sync-meta/recovery/has-guardian-set` | `{has_guardian_set: bool}` and nothing else — does the CALLER's own user have a current guardian set (the highest non-superseded `share_set_version`, what the rung-2 open pins). Deliberately **not** gated on certification, so the uncertified phone on S11.6 can answer rung 2's `noTrustedMembers` (ADR 2026-09-24b §3, amending ADR 2026-09-05d §2). Query parameters are ignored; `false` for a revoked device, a device that is not the caller's, an erased user, or no set; `true` for a published set still short of n members (the open then answers 409 `guardian_set_incomplete`) — `rf.has_guardian_set` 0016 |
| `POST /auth-challenge/otp/request · /otp/verify · /devices · /devices/certify · /challenge · /token · /refresh` | 06 §2–§4; see the header comment in `auth-challenge/index.ts` |
| `POST /billing-webhook` | `x-razorpay-signature` HMAC over the raw body; idempotent by event id; stub until M13 |

Any route answers `426 {error:"upgrade_required", min_client_version}` when `x-rukka-client-version`
is below `app_config.min_client_version.<sync|auth|billing>` (06 §4.5).

## 3. Roles and login provisioning

Migrations create two `NOLOGIN` roles and never a password:

| role | may | may not |
|---|---|---|
| `rf_api` | SELECT/INSERT per policy; the `rf.*` helper functions granted to it; UPDATE on the ephemeral auth tables and the user's own profile columns | UPDATE/DELETE `envelopes` or `signed_records` (no grant exists); read `phone_ct`/`phone_hmac` (column grant excludes them); `rf.bump_store_epoch`; `rf.purge_ephemeral_auth`; `rf.sweep_seat_grants`; touch `push_rate` directly; call the recovery guard's subject lookups `rf.current_guardian_set` · `guardian_set_ready` · `device_live_for` · `has_other_active_device` · `live_recovery_count` (owner-only since 0017 — each would hand any user's k, n, readiness or liveness past 0005's certified-only policy; ADR 2026-09-24b §3) |
| `rf_maintenance` | SELECT/DELETE `envelopes` (trigger limits DELETE to an erased owner's personal book), purge auth rows and 90-day-revoked keys, bump the store epoch, sweep `seat_grants` rows older than 1 year + 30 days through `rf.sweep_seat_grants()` (0023 — the function is the only door; the role holds no privilege on the table) | INSERT/UPDATE anything; read or delete `seat_grants` directly; choose the sweep's cutoff (the function takes no argument) |

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
| Entitlement key (32 B Ed25519 seed, base64) | `RF_ENTITLEMENT_KEY` | signs entitlement tokens (08 §3, ADR 2026-09-05g §1); public half pinned in the app beside the SPKI pins | annual, 30-day overlap — the app holds two pinned public keys meanwhile; Vault vs KMS is ADR 2026-09-05c open 2 |
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
- [ ] **Before 0021 reaches a hosted project: no duplicate personal books** (ADR 2026-10-03 §7 (d); PLAN desk 73 (d)). 0021 adds the unique index `books_one_personal_per_owner` (one personal book per tenant and owner), and its pre-check refuses to apply, by name, if any pair already holds two. Before the push that carries 0021 to each hosted project (`supabase migration list` shows whether it is applied), run this in the SQL Editor: `select tenant_id, owner_user_id, count(*) from books where type = 'personal' group by 1, 2 having count(*) > 1;`. It must return **no rows**. If it returns any, the push fails with `personal_book_duplicates` (P0001). The migration's hint is *"resolve them by hand (retype, never delete) before applying 0021"*. Which book to retype is the owner's call: never delete one, and never let a script choose.
- [ ] **The owner of every SECURITY DEFINER function holds `BYPASSRLS`** (ADR 2026-10-03 §10 (c); 0023:61–64). Check this after every migration push to a hosted project. 0005:271–278 turns on **FORCE** RLS for every `public` table, so a SECURITY DEFINER function bypasses RLS only if its owner, the role that applied the migrations, is a superuser or holds `BYPASSRLS`. `seat_grants` has no policy at all (0019 §8). Without that right, `rf.take_seat`'s insert fails, so every invite and join is refused. Worse, `rf.sweep_seat_grants()` and the other sweeps **fail silently**: a DELETE that RLS hides every row from deletes 0 rows and raises nothing. The local database (`scripts/rls_db.sh`, `supabase db reset`) applies migrations as a superuser, so no local test can catch this. Not verified on hosted Supabase. Run: `select p.oid::regprocedure, r.rolname, r.rolsuper, r.rolbypassrls from pg_proc p join pg_roles r on r.oid = p.proowner where p.pronamespace = 'rf'::regnamespace and p.prosecdef and not (r.rolsuper or r.rolbypassrls);`. It must return **no rows**. If it returns any, stop: granting `BYPASSRLS` to a platform role is an owner decision, not an ops fix.
- [ ] **pg_cron** jobs under `rf_maintenance`: `rf.expire_invites()` hourly (06 §7's 7-day window; lazy expiry already binds at accept time, so a missed sweep is a stale row, never an admitted invite); `rf.purge_ephemeral_auth()` hourly (24 h auth rows, 90 d revoked keys); `rf.sweep_seat_grants()` daily (seat-rotation ledger rows older than 1 year + 30 days — every reader of `seat_grants` looks back at most a year, so a swept row is never counted again; a missed run keeps rows longer, never changes a cap answer; 0023, E-05g-27…30); `rf.sweep_ceremony_sessions()` **hourly** (deletes `ceremony_sessions` whose `expires_at` is a day or more past, 0007:272–279 — 03 §2.2's *"swept a day past expiry"*; a row lingers at most 1 d + 1 h. A missed run keeps a dead row, never a usable one: `rf.ceremony_contribute`/`rf.ceremony_open` refuse an expired session with `ceremony_expired`); `rf.sweep_recovery()` **hourly** (deletes `recovery_approvals`, `recovery_cancellations`, then `recovery_requests` 30 days or more past the attempt's `expires_at`, 0010:547–560. An approved attempt's shares stay releasable until this deletes it — ADR 2026-10-03 §5 (b) — so a late run lengthens that window by its delay, which is why this one is hourly. It does **not** delete the `recovery_blob` `wrapped_keys` rows the approvals point at; see §6); `rf.sweep_recovery_sheets()` **daily** (deletes a **superseded** sheet once its own `created_at` is 30 days or more past, 0011:136–145; the current sheet is never swept. The code measures from the old sheet's creation, not from its replacement as its comment says, so an old sheet can go at the first run after it is replaced. 04 §7.4 invalidates it on regeneration anyway). ⚠️ SPEC: no doc fixes a cadence for these three. Each is the conservative one: the window lives in the function, so the cadence only decides how long a row outlives it. All three are SECURITY DEFINER with EXECUTE for `rf_maintenance` alone (0007:314–315, 0010:561–562, 0011:147–148). User erasure (06 §9.3) after the 15-day cooling; `audit_events` aggregation after 24 months (`verification_events` are permanent).
  - **As deployed on `rukka-folio-dev` (3 Oct 2026):** six jobs — `rf_expire_invites` `5 * * * *`, `rf_purge_ephemeral_auth` `10 * * * *`, `rf_sweep_ceremony` `15 * * * *`, `rf_sweep_recovery` `20 * * * *`, `rf_sweep_recovery_sheets` `30 3 * * *`, `rf_sweep_seat_grants` `40 3 * * *`. ⚠️ They run as the functions' owner (`postgres`), not `rf_maintenance`: on PG 16+ the creating role holds `rf_maintenance` with `SET FALSE` (`pg_auth_members`, probed), so `set role rf_maintenance` inside a job would fail. The functions take no argument, so the work is identical; erasure and `audit_events` aggregation jobs are not scheduled (no function exists yet).
- [ ] **Store epoch**: bump (`rf.bump_store_epoch(reason)`) after every restore or rebuild — clients reset cursors (05 §1). Never bump casually; every client re-pulls everything.
- [ ] **SPKI pin rotation** (05 §1 🔒): clients pin ≥ 2 SPKI hashes (current + backup) of the API host's chain at the intermediate-CA level. Runbook: (1) publish the backup pin in a release *before* any rotation; (2) rotate the certificate; (3) verify the exact chain with `openssl s_client -showcerts` and recompute pins (`openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`); (4) ship the next backup. A pin failure is a hard fail with no override; only local-dev builds disable pinning, and the release lane asserts it.
- [ ] **Functions deploy with the one import map**: `config.toml` sets `import_map = "../deno.json"` per function (bare `sodium`/`postgres`/`@std/*` resolve only through `server/deno.json`); without it `supabase functions deploy` uploads and silently deploys nothing. Deploy from `server/`: `supabase functions deploy <fn> --use-api`. Smoke: a POST without `x-rukka-client-version` answers 426 (sync-pull 405), never 503 `unconfigured`; `billing-webhook` answers 503 `webhook_unconfigured` until `PAYMENT_GATEWAY_WEBHOOK_SECRET` is set. Dev deployed 3 Oct 2026; OTP request + verify with the fixed code returned 200 end to end.
- [ ] **Edge Function secrets**: `RF_API_DB_URL`, `RF_MAINT_DB_URL`, `RF_JWT_HMAC_KEY`, `RF_ENTITLEMENT_KEY`, `RF_PHONE_HMAC_KEY`, `RF_PHONE_KEK`, `OTP_PROVIDER` (+ key, DLT ids), `PAYMENT_GATEWAY_WEBHOOK_SECRET`; on the **dev project only**, `RF_DEV_PROJECT_REF`. **Nothing at deploy time checks these.** `supabase functions deploy` accepts any value. The check runs when a function starts (`_shared/otp/select.ts`, PLAN desk 57; E-25-4 … E-25-9):
  - `OTP_PROVIDER` must be exactly `msg91` (and needs `OTP_PROVIDER_API_KEY`, `OTP_DLT_ENTITY_ID`, `OTP_DLT_TEMPLATE_ID`) or `fake`. If it is unset, empty or anything else, every function logs `startup refused <reason>` and answers every call `503 {"error":"unconfigured"}`. `kaleyra` and `twilio` do not exist. `2factor` refuses as `otp_provider_not_built` until row OTP3 builds it. The same 503 follows any missing required secret (`missing_env <NAME>`).
  - `fake` sends nothing. On its own it issues random codes and stores only their hash, so **no one can sign in**. It fails closed.
  - **The fixed dev code** (`DEV_FIXED_OTP_CODE` in `select.ts`; ADR 2026-09-25 §1) needs `OTP_PROVIDER=fake` **and** `RF_DEV_PROJECT_REF` set to this project's own ref. That ref must equal the one in the platform-injected `SUPABASE_URL` (`https://<ref>.supabase.co`, a form **verified on `rukka-folio-dev` 4 Oct 2026** — see the first-dev-deploy check below; select.ts ⚠️ SPEC (e), ADR 2026-10-03 §6 (b); see the first-dev-deploy check below), which the operator cannot set: the CLI refuses `SUPABASE_`-prefixed secrets. If the switch is set and does not match, the function refuses to start (`otp_fixed_code_unbound`). That covers dev secrets copied onto the pilot, a custom domain, and local `functions serve` (`http://kong:8000`). The fixed code is stored only as its hash and is never logged.
  - [x] **First dev deploy: confirm the `SUPABASE_URL` form** — **done 4 Oct 2026:** `otp/request` for a synthetic `+91 5…` number answered 200, `otp/verify` refused a wrong code (`otp_invalid`, 2 attempts left) and accepted `DEV_FIXED_OTP_CODE` (200, ticket). The injected URL is `https://<ref>.supabase.co`. (ADR 2026-10-03 §6 (b), select.ts ⚠️ SPEC (e)). Do this once, on `rukka-folio-dev` only. With `OTP_PROVIDER=fake` and `RF_DEV_PROJECT_REF=<the dev project's ref>` set, deploy and call `POST /auth-challenge/otp/request` for a synthetic test number. If the function log says `startup refused otp_fixed_code_unbound` and the call answers `503 unconfigured`, the injected URL is not `https://<ref>.supabase.co`. It fails closed, so nothing is exposed, but no tester can sign in. Fix the parse in `select.ts` in a server lane. Do not try to fix it by setting a secret: the CLI refuses `SUPABASE_` names. If the request succeeds and `otp/verify` accepts `DEV_FIXED_OTP_CODE`, the form is confirmed. Record the date here and drop the "not yet verified" note above. Never paste the project's keys or a log line carrying a phone number into this file.
  - **Pilot and production:** `OTP_PROVIDER=msg91`, and `RF_DEV_PROJECT_REF` is **never** set. ⚠️ The ref binding cannot stop someone who deliberately writes the pilot's own ref into `RF_DEV_PROJECT_REF` *and* sets `OTP_PROVIDER=fake` there. That takes two deliberate acts, not a mistype.
- [ ] **Metrics are plaintext counters only** (ADR 05b §8): rejections by `result`/`check`, push/pull latency, cursor lag, `write_lost`/`meta_mismatch` counts. No log line joins an envelope id to a phone.
- [ ] **Rate limits** (05 §3): 600 envelopes/min, 5,000/h, 50 MB/day per device via `rf.push_rate_check`; OTP 5/h + 10/day per number, 30/h per IP (⚠️ per-IP number is M6).
- [ ] **Data API off, PostgREST quieted** (§3: PostgREST is not an API surface here). Switch the Data API off in the dashboard. That alone does not stop PostgREST: Supabase points it at a placeholder schema, `pg_pgrst_no_exposed_schemas`, which does not exist, so Postgres logs `3F000 schema "pg_pgrst_no_exposed_schemas" does not exist` every 32 s. Silence it once per hosted project in the SQL Editor ([Supabase troubleshooting](https://supabase.com/docs/guides/troubleshooting/schema-pg_pgrst_no_exposed_schemas-does-not-exist)): `create schema pgrst_no_exposed_schemas; alter role authenticator set pgrst.db_schemas = 'pgrst_no_exposed_schemas'; notify pgrst;`. The schema is empty and the platform roles hold no grants, so nothing is exposed. **Not a migration:** `authenticator` exists only on hosted Supabase, and `scripts/rls_db.sh` builds on plain Postgres. To undo it before ever re-enabling the Data API: `alter role authenticator reset pgrst.db_schemas; notify pgrst;`. Applied on `rukka-folio-dev` 3 Oct 2026; the pilot needs it too.

## 6. Open (owner)

**Invite delivery: ADR 2026-09-25 §2 settled.** The server does not send invitations. *Send invite*
creates the invite and stores its nonce and `invitee_hmac` only. The app opens the platform share
sheet with the link and a prefilled message; the inviter sends it by whatever app they choose
(WhatsApp, SMS, email, …). *Resend* reopens the share sheet. The invitee's phone number reaches the
server once, only to be hashed (06 §7 amended). `POST /sync-meta/invites` returns the `invite_id` to
the inviter's device so their app can read it; no outbound message job is needed.

**`recovery_blob` rows have no retention path (⚠️ owner, observed 3 Oct 2026).** `rf.sweep_recovery` (0010:547–560) deletes an attempt's approvals, cancellations and request, but not the `wrapped_keys` rows of kind `recovery_blob` those approvals pointed at (`recovery_approvals.wrapped_key_id`, 0010:280). `rf.purge_ephemeral_auth` (0004:169) deletes only *revoked* wrapped keys, and a `recovery_blob` row is revoked only when its candidate device is revoked (0005:234, 0022:218). So the shares of a closed attempt stay stored, unreferenced, for as long as the candidate device lives. They are sealed to a candidate key that ADR 2026-09-24b §1 zeroises on every close, and 0020 withholds them from every read, so nothing is exposed. 03 §6 still names no retention for them. Fixing it is a migration in a `lane-server` round.

See the lane's structured return and `CHANGELOG.md`: cold-storage `fy` tiering (05 §8) needs an
ops story, not a wire change; `recipient_fingerprint` on `wrapped_keys` is not in 03 §2.2; the live
half of E-05b-8 / E-05c-8 and the whole of `rls.test.ts` need the hosted (or Docker) database.
