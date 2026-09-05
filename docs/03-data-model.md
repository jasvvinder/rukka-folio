# 03 — Data Model

**Status:** Draft 1 for build. 🔒 = locked. ⚠️ = decide before the affected milestone.
**Companions:** 02 (domain objects & invariants), 04 (envelope format & keys), 05 (sync — cursors defined here, protocol there), 06 (identity & membership states).

**The one architectural sentence 🔒:** *Envelopes are the truth; everything else is a projection.* The server stores envelopes it cannot read plus the minimum plaintext needed to route, authorize, and bill. The client decrypts envelopes into relational tables purely for querying — those tables can be dropped and rebuilt from envelopes at any time, and "Recompute" does exactly that.

---

## 1. Identifiers, time, and money 🔒

- All object IDs are **client-minted UUIDv7** (time-ordered for index locality; ordering *authority* is still the HLC).
- **HLC**: 64-bit — 48-bit physical ms + 16-bit logical counter — with `device_id` as the deterministic tiebreak. Stored as `BIGINT` (server) / `INTEGER` (SQLite); never compared across objects except where 02/05 say so (locks, sync cursors).
- Money: `BIGINT` paise everywhere. No `NUMERIC`, no floats, including exports.
- Times: server rows `timestamptz` UTC; domain dates are the entry's `accounting_date` (date only) inside ciphertext.
- **Projector version 🔒 (ADR 2026-09-05c §3):** `core_ledger.projectorVersion` (int) is recorded in every `period_lock` and `year_close` envelope beside the vector hash; a reader on an older projector shows *"Update the app to verify this close"* instead of a mismatch. Result-changing projector changes bump it **and** `min_client_version` together and force a Recompute on upgrade.

---

## 2. Server schema (Postgres)

### 2.1 Identity & tenancy (plaintext) 🔒

```sql
users(id uuid pk,
      phone_ct bytea, phone_hmac bytea unique,   -- encrypted under the server KMS key; HMAC for lookup (ADR 2026-09-05c §4)
      display_name text, photo_key text,
      language text, whatsapp_opt_in bool, created_at, deletion_requested_at,
      deleted_at)                        -- 15-day cooling between the last two

tenants(id uuid pk, type text check (type in ('family','business_group','organization')),
        created_at)

memberships(tenant_id, user_id, status text check (status in
        ('invited','joined_pending_verification','active','blocked','removed')),
        verified_by uuid, verified_method text, verified_at,
        primary key (tenant_id, user_id))

books(id uuid pk, tenant_id fk, type text check (type in
        ('personal','family','joint','business')),
        owner_user_id uuid null,         -- set for personal books only
        fy_start_month int default 4, created_at, archived_at)
        -- book NAME is encrypted content (a book_config envelope), not a column

book_roles(book_id, user_id, role text check (role in
        ('admin','head','member','operator','viewer')),
        auto_post_limit_paise bigint, primary key (book_id, user_id))
```

### 2.2 Devices, keys, ceremonies (plaintext rows, opaque blobs) 🔒

```sql
devices(id uuid pk, user_id fk, pub_ed bytea, pub_x bytea, model, os,
        attestation jsonb null, status text, created_at, revoked_at)
device_certs(device_id pk, cert bytea, issued_by_device uuid, issued_at)

wrapped_keys(id uuid pk, kind text check (kind in
        ('umk_for_device','bk_for_user','guardian_share','recovery_blob','escrow_blob')),
        user_id, device_id null, book_id null, key_version int,
        share_set_version int null, blob bytea, created_at, revoked_at)

invites(id uuid pk, tenant_id, invitee_hmac bytea,   -- NO plaintext number: the invitee consented to nothing (ADR 2026-09-05c §4)
        roles jsonb, nonce bytea,
        status, expires_at, created_by)
verification_events(id, tenant_id, subject_user, verifier_user, method text
        check (method in ('qr_in_person','code_remote','device_link')),
        result text, at)                 -- the permanent tenant-visible log

recovery_requests(id, user_id, candidate_device uuid, state, approvals int,
        expires_at)
escrow_policies(id, member_user, head_user, book_id, blob_ref uuid,
        state, release_requested_at)     -- veto window enforced from this row
```

### 2.3 The envelope store 🔒

```sql
envelopes(
  envelope_id uuid pk,                   -- client-minted; idempotency key
  seq bigserial unique,                  -- server receipt order; THE pull cursor (05 §4)
  tenant_id uuid not null, book_id uuid not null,
  object_id uuid not null, object_type text not null,
  key_version int, suite_version smallint, payload_schema smallint,
  author_device uuid not null, hlc bigint not null,
  blob_hash bytea not null,              -- BLAKE2b-256(blob); server recomputes on write, readers on read (ADR 2026-09-05c §2)
  size int, blob bytea,                  -- ⚠️ blobs > 64 KB go to object storage,
  blob_ref text,                         --   with pointer here; threshold at build
  received_at timestamptz default now()
);
create index on envelopes (book_id, seq);                 -- the sync-pull index (05 §4)
create index on envelopes (tenant_id);
-- append-only: no UPDATE or DELETE grants to the API role, ever.
```

**Shape checks — the complete list 🔒 (ADR 2026-09-05c §5):** `author_device == jwt.device_id` · `tenant_id == books.tenant_id` · `blob_hash` and `size` recompute · `suite_version`/`payload_schema` in registry · `key_version` ≤ highest issued · HLC sanity (05 §2) · caps/quotas (05 §3). Failure → `rejected:shape` naming the check. **Hash mismatch on read is corruption, not tampering:** re-fetch, count it, no security event; only an intact blob with a failing signature is quarantined (04 §8.3).

**`object_type` registry 🔒:** `book_config · account · entry · approval_decision · period_lock · year_close · import_batch · import_line · rule · attachment_meta · cash_count` (+ reserved range). Everything in 02 and 07 maps into these; nothing financial exists outside them.

`attachments(id, book_id, storage_key, size, created_at)` — ciphertext files in object storage; their per-file keys ride inside `attachment_meta` envelopes (04 §3).

### 2.4 Billing, audit, ops 🔒

```sql
subscriptions(tenant_id pk, plan, status, gateway, gateway_ref, current_period_end)
audit_events(id, tenant_id null, user_id null, kind, details jsonb, at)
   -- operational/tenant-visible: device added, invite sent, member removed,
   -- recovery requested, escrow countdown… (never financial content)
app_config(key pk, value)               -- min_client_version per route group, etc.
otp_challenges / activation_tickets     -- ephemeral, TTL-purged (06 §2–3)
```

### 2.5 Row-level security 🔒

RLS on, `FORCE`, for every table above; the API connects as a non-superuser role with **our** `request.user_id` / `request.device_id` claims (06 §4 JWT, not platform auth) set with `SET LOCAL` per transaction so a pooled connection never carries them across (ADR 2026-09-05c §7).

- **Certified-only (ADR 2026-09-05d §2):** every tenant-scoped policy below additionally requires the caller's `devices.status = 'certified'` (set by the server after verifying the cert under the user's UMK public key). An uncertified device reads only its own `users`/`devices` rows, wrapped keys addressed to it and its own `recovery_requests`.
- `envelopes`: **SELECT/INSERT only** where the user holds a `book_roles` row for `book_id` with a role permitting it (viewer ⇒ select only) **and** membership status = `active`. No UPDATE/DELETE policy exists at all.
- `wrapped_keys`: readable only by the subject (`user_id` = requester, or guardian rows addressed to the requester); insertable per the flows in 04.
- `memberships`, `book_roles`, `verification_events`: readable by fellow active members of the tenant.
- Cross-tenant reads are impossible by construction; the acceptance suite includes a hostile-query test (§7).
- **Rows are projections of signed records 🔒 (ADR 2026-09-05b §1):** `memberships`, `book_roles` and device revocations are written by the server only when applying a `signed_records` row authored on a certified device; clients verify the record, not the row.
- **Deletion runs under a separate `maintenance` role** (ADR 2026-09-05b §8) reachable only from the scheduled deletion function, limited to the erased user's personal-book envelopes and wrapped keys, audited. The API role keeps no DELETE grant.

**Deletion mechanics (06 §9.3) 🔒:** erase the user row's **profile fields** (phone, name, photo, language, contacts) in place and set `erased_at`; hard-delete all their wrapped keys and their personal-book envelopes. 🔒 **Retain** `devices` rows, `device_certs` and the UMK public key, flagged `erased` — pseudonymous key material carrying no personal data, required so that a device joining later can still verify the signature chain (04 §3.4) on shared-book entries the user authored. **Shared-book envelopes are never updated or deleted**, and `author_device` is never re-pointed — that would violate the append-only grant (§2.3) and CLAUDE.md rule 2. Clients render an erased author as *"Removed member"* from the erased profile row; the signature chain still verifies on every device, old or new.

---

## 3. Client schema (SQLite via Drift, SQLCipher at rest)

### 3.1 Layer 1 — envelope mirror & outbox 🔒

```sql
envelopes_local(envelope_id pk, book_id, object_id, object_type, key_version,
        hlc, seq bigint null,                        -- server seq; revocation cut-off (ADR 2026-09-05b §5)
        author_device, author_seq int,               -- from inside the ciphertext (§3 of that ADR)
        blob, blob_hash,                             -- hash verified on read; mismatch = corruption → re-bootstrap (ADR 2026-09-05c §2, §6)
        verified int,                                -- 1 after sig-chain check
        quarantined int default 0, quarantine_reason text,
        held int default 0, held_for uuid null)      -- dangling ref, waiting for target (§4)
outbox(envelope_id pk, book_id, blob, created_at, push_state text
        check (push_state in ('queued','inflight','acked','observed','rejected')),
        acked_seq bigint null, reject_reason text)   -- prune only at 'observed' (§6)
author_seq_local(book_id, device_id, next_seq int, primary key (book_id, device_id))
author_gaps(book_id, author_device, expected_seq int, since_hlc)  -- derived, drives the status surface
signed_records_local(id pk, tenant_id, kind, payload, author_device, sig, hlc, seq, verified int)
store_epoch(epoch uuid)                             -- one row; change → all cursors reset
sync_cursors(book_id pk, last_seq bigint)               -- server-seq cursor (05 §4)
key_cache(book_id, key_version, wrapped_blob, primary key (book_id, key_version))
        -- BKs stored wrapped; unwrapped only in memory. UMK per 04 §3.3.
attachment_cache(id pk, book_id, local_path, state)
```

### 3.2 Layer 2 — projections (rebuildable, indexed for the UI) 🔒

```sql
books_p(id pk, tenant_id, type, name, fy_start_month, integrity_ok int)
accounts_p(id pk, book_id, name, class, money_subtype,  -- cash | cash_collection | saving | current | od | cc | loan
        collection_income_account_id null,               -- cash_collection: where counts post income (02 §8.2) usual_category_id,
        archived int)                                  -- 02 §1.2
entries_p(id pk, book_id, kind, status, accounting_date, note, channel,
        party_id, advance_ref, transfer_group, amends, reverses,
        superseded_by,                                 -- head of amend chain = null
        review_state text not null default 'none'      -- 02 §3 post-then-review
            check (review_state in ('none','open','approved','rejected')),
        review_approver uuid null,                     -- who must act, then who acted
        review_decided_hlc bigint null,
        review_reason text null,                       -- required on 'rejected'
        created_by_user, hlc)
        -- 🔒 status and review_state are INDEPENDENT. `status='pending'` means only
        -- "advance request awaiting approval" (02 §7). An ordinary over-limit entry
        -- is status='posted' + review_state='open' and IS in balances (02 §9).
entry_lines_p(entry_id, account_id, amount_paise, book_id, accounting_date)
        -- denormalized book_id+date: this table answers every ledger query
periods_p(book_id, year, month, state, lock_hlc)
cash_counts_p(id pk, account_id, mode, counted_at, counted_total_paise, breakdown_json,
        posted_entry_id null, counted_by, witness null)
        -- 02 §8.2. mode = 'verify' (cash) | 'collect' (cash_collection).
        -- verify: posted_entry_id set only when an adjustment was needed.
        -- collect: posted_entry_id always set (income entry); breakdown + witness mandatory.
year_close_p(book_id, fy_label, state, vector_hash, vector jsonb)  -- 02 §8.1
import_lines_p(id, book_id, bank_account_id, date, description, amount_paise,
        state, matched_entry, dedupe_hash unique)
rules_p(id, book_id, pattern, target_account, hits)
balances(account_id pk, balance_paise, as_of_hlc)      -- trigger-maintained cache
daily_snapshots(account_id, date, balance_paise, primary key (account_id, date))
```

Key indexes: `entry_lines_p(account_id, accounting_date)` (A/C statement, running balance), `entries_p(book_id, accounting_date desc)` (day book), `entries_p(book_id, review_approver) where review_state='open'` (**Inbox** — the approvals queue, 02 §3/07 §9), `entries_p(book_id) where status='pending'` (**advance requests** awaiting approval, 02 §7 — a separate, much smaller queue), `import_lines_p(book_id, state)`.

### 3.3 Projection rules 🔒
1. Apply only envelopes with `verified = 1` and `quarantined = 0`, in `(hlc, envelope_id)` order per book.
2. The projector is a **pure, deterministic function** of the ordered envelope stream + certified opening vectors — this is what makes the close-hash verification (02 §8) and *Recompute* possible. No projector step may read the clock, the network, or local settings.
3. `balances` and `daily_snapshots` update transactionally with each applied entry; a full rebuild seeds from the latest `year_close_p` vector (02 §8.1) then replays the open FY.
4. **Unknown-field round-trip 🔒:** payloads are JSON; clients must preserve fields they don't understand when amending an object (older app editing an entry created by a newer app must not strip new fields). `payload_schema` gates *interpretation*, never storage.
5. **`review_state` folds from envelopes only 🔒:** `auto_post_limit_paise` lives in `book_roles` — **plaintext server metadata, not an envelope** — so the projector may never read it (rule 2). The *authoring* client evaluates the limit at save time and writes the boolean `review_required` into the entry payload (02 §1.3); the projector then sets `review_state = 'open'` iff `review_required` and no decision has arrived, and folds any `approval_decision` envelopes for that entry in `(hlc, envelope_id)` order, last one winning, to `approved` or `rejected`. This keeps the projection a pure function of the envelope stream, so two devices with different cached role metadata still compute an identical close-hash (02 §8). A hostile client that sets `review_required=false` on an over-limit entry is caught by readers the same way any invariant violation is (02 preamble) — the limit is *also* carried in the payload for that check.

---

## 4. Plaintext ⇄ ciphertext boundary (single reference table) 🔒

| Plaintext (server can see) | Ciphertext (server never sees) |
|---|---|
| phone, name, photo, language | book & account **names**, category trees |
| tenant/book/membership/role rows, limits | every entry: amounts, dates*, parties, notes |
| device rows, certs, wrapped-key blobs (opaque) | attachment contents & filenames |
| invite + verification + audit events | import lines, rules, close vectors |
| subscription state, envelope routing fields, HLCs, sizes | anything else financial |

\* `accounting_date` is inside ciphertext; the server sees only HLC (creation time). Activity *timing* is visible metadata; content never is.

---

## 5. Migrations & versioning 🔒

- Server: forward-only SQL migrations, numbered, applied by CI; `payload_schema` registry lives with them.
- Client: Drift schema versions with tested upgrade paths from every shipped version; a failed migration must fail *closed* (app blocks with support screen) — never run on a half-migrated ledger.
- Envelope evolution: additive fields freely (rule 3.3.4); breaking changes bump `payload_schema` **and** min_client_version (06 §4.5) together.
- **Projector evolution (ADR 2026-09-05c §3):** a change that can alter any result bumps `projectorVersion` **and** min_client_version together and forces a full Recompute on first launch after upgrade; the golden replay (09 A) is the proof of which kind a change is.
- **Local corruption (ADR 2026-09-05c §6):** SQLCipher `quick_check` on every open; projections corrupt → drop + Recompute; envelope mirror corrupt → re-bootstrap the book (05 §8); `books_p.integrity_ok` gates the Home card so a book is never shown whole while any envelope is missing or unverified.

## 6. Retention 🔒
**Residency & durability 🔒 (ADR 2026-09-05c §1):** Postgres, object storage, backups and logs all in **India** (Mumbai region or equivalent; no Indian region = disqualified provider); backups never leave it. PITR on (⚠️ 7 d), daily encrypted snapshots 35 d, monthly 12 mo; backup access is a privileged audited path, never the API role; **quarterly restore drill** against written RTO/RPO (⚠️ ≤ 4 h / ≤ 5 min); **every restore bumps `store_epoch`** (05 §1). Platform backups of the client database are excluded (iOS attribute; Android `allowBackup=false`). Object storage: private bucket, per-tenant prefix, object written before row, nightly orphan sweep.

Ephemeral auth rows TTL-purged (24 h). `audit_events` 24 months then aggregated; `verification_events` permanent. Revoked wrapped keys kept 90 days then purged. Envelopes: forever (they are the books), with closed-FY partitions eligible for cold storage behind the same API (02 §8.1). Deleted users per §2.5 — profile erased, keys and personal-book envelopes purged, **device certs and UMK public keys retained indefinitely** as verification material for entries they authored in shared books. ⚠️ confirm final DPDP retention wording.

---

## 7. Acceptance tests (excerpt)

- **Hostile query:** an authenticated member of tenant A issuing arbitrary API calls (fuzzed) never receives a row keyed to tenant B — enforced at RLS, verified by a test that connects as the API role directly.
- **Append-only:** UPDATE/DELETE on `envelopes` as the API role fails at the grant level.
- **Idempotency:** inserting the same `envelope_id` twice yields one row and a success response both times.
- **Determinism:** two clients given identical envelope sets produce byte-identical `balances` and close vector hashes; drop-projections + Recompute reproduces them.
- **Round-trip:** an old-schema client amending a new-schema entry preserves the unknown fields byte-for-byte in the replacement payload.
- **Rebuild-from-vector:** after year close, Recompute using (vector + open-FY envelopes) equals Recompute using full history.
- **At-rest:** the SQLite file is unreadable without the SQLCipher key (raw-bytes entropy test in CI).
- **Blob integrity (ADR 2026-09-05c §2):** a flipped byte in a stored blob is reported as corruption and re-fetched — no quarantine, no security event, author untouched; the same blob with a forged signature is quarantined.
- **Projector version (ADR 2026-09-05c §3):** a close certified on projector v(n+1) is shown as *update to verify* on v(n), never as a mismatch; after upgrade + Recompute it verifies.
- **No phone list (ADR 2026-09-05c §4):** a full dump of `users` and `invites` yields no recoverable phone number without the KMS key; an expired invite leaves no number anywhere.
- **Pooled claims (ADR 2026-09-05c §7):** two interleaved requests on one pooled connection never observe each other's `request.user_id`.
- **Shape (ADR 2026-09-05c §5):** an envelope whose `author_device` is not the caller's device, or whose `tenant_id` mismatches the book, is refused at push with the check named.
- **Erasure:** after a user's deletion, their shared-book entries still verify their signature chain **on a freshly-installed device**, render the author as *Removed member*, and remain in balances; their personal-book envelopes and all wrapped keys are absent server-side, and no envelope row was updated or deleted.

## 8. Open items ⚠️
1. Envelope blob threshold for object-storage offload (proposal: 64 KB). 2. Object storage: Supabase Storage vs R2 (egress math at pilot scale). 3. UUIDv7 + HLC library choices for Dart. 4. Cold-archive trigger (age vs size) for closed FYs. 5. DPDP retention wording (§6). 6. PITR window / snapshot retention / RTO-RPO numbers vs hosting plan; KMS choice + rotation for the phone key (ADR 2026-09-05c).
