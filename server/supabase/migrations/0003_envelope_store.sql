-- 03 §2.3 The envelope store 🔒 + signed records (ADR 2026-09-05b §1, §5).
-- ONE sequence shared by envelopes and signed_records: the revocation cut-off compares `seq`
-- across both (ADR 2026-09-05b §5, Open 3). 03 §2.3 spells `seq bigserial`; the newer ADR's shared
-- sequence keeps bigserial semantics (bigint, default nextval) on a named sequence.
create sequence store_seq as bigint start with 1 increment by 1 no cycle;

-- Server-side store epoch (05 §1, ADR 2026-09-05b §6): one row; every restore/rebuild bumps it.
create table store_epoch (
  id boolean primary key default true check (id),
  epoch uuid not null default gen_random_uuid(),
  bumped_at timestamptz not null default now(),
  reason text null
);

create table envelopes (
  envelope_id uuid primary key,                          -- client-minted; idempotency key
  seq bigint not null unique default nextval('store_seq'),   -- server receipt order; THE pull cursor (05 §4)
  tenant_id uuid not null references tenants(id),
  book_id uuid not null references books(id),
  object_id uuid not null,
  object_type text not null check (object_type in (
    'book_config','account','entry','approval_decision','period_lock','year_close',
    'import_batch','import_line','rule','attachment_meta','cash_count',
    'period_unlock','structural_approval','business_setting')),   -- registry 03 §2.3 + ADR 2026-09-05e §11
  key_version int not null check (key_version >= 1),
  suite_version smallint not null check (suite_version >= 1),
  payload_schema smallint not null check (payload_schema >= 1),
  author_device uuid not null references devices(id),
  hlc bigint not null,
  blob_hash bytea not null check (octet_length(blob_hash) = 32),  -- BLAKE2b-256(blob) (ADR 2026-09-05c §2)
  size int not null check (size >= 0 and size <= 262144),          -- ⚠️ cap 256 KB/envelope (05 §3)
  blob bytea null,                                       -- ⚠️ blobs > 64 KB go to object storage
  blob_ref text null,                                    --   with the pointer here; threshold at build
  received_at timestamptz not null default now(),
  constraint envelopes_blob_or_ref check ((blob is null) <> (blob_ref is null))
);
create index envelopes_book_seq_idx on envelopes (book_id, seq);      -- the sync-pull index (05 §4)
create index envelopes_tenant_idx on envelopes (tenant_id);
create index envelopes_author_idx on envelopes (author_device, seq);
-- append-only: no UPDATE or DELETE grants to the API role, ever (0005).

-- Blob hash and size are recomputed on write by the function (shape check); the database re-checks
-- inline blobs as a second line so a bypassing writer cannot store a mismatch either.
create or replace function rf.envelope_inline_size_check() returns trigger
language plpgsql as $$
begin
  if new.blob is not null and octet_length(new.blob) <> new.size then
    raise exception 'rejected:shape' using detail = 'size', hint = 'inline blob length differs from size';
  end if;
  return new;
end $$;
create trigger envelopes_size_check before insert on envelopes
  for each row execute function rf.envelope_inline_size_check();

-- Structural facts (ADR 2026-09-05b §1): SignedRecord{suite_version, tenant_id, kind, payload_json,
-- author_device_id, author_sig, hlc, seq}. Server rows are projections of these; clients verify these.
create table signed_records (
  id uuid primary key,                                   -- client-minted; idempotency key
  seq bigint not null unique default nextval('store_seq'),
  suite_version smallint not null check (suite_version >= 1),
  tenant_id uuid not null references tenants(id),
  kind text not null check (kind in (
    'membership_status','book_role','member_removal','device_revocation','device_added',
    'key_rotation','verification_event','designation')),
  payload_json jsonb not null,                           -- plaintext by design (03 §4 — roles are plaintext already)
  payload_bytes bytea not null,                          -- the exact signed bytes; jsonb re-serialisation is not byte-stable
  author_device uuid not null references devices(id),
  author_sig bytea not null check (octet_length(author_sig) = 64),
  hlc bigint not null,
  received_at timestamptz not null default now(),
  applied_at timestamptz null,                           -- when the server projected it onto rows
  apply_note text null                                   -- e.g. 'counted 1 of 2' for guardian revocations
);
create index signed_records_tenant_seq_idx on signed_records (tenant_id, seq);
create index signed_records_kind_idx on signed_records (kind, seq);

-- Attachments: ciphertext files in object storage; per-file keys ride inside attachment_meta envelopes.
create table attachments (
  id uuid primary key,
  book_id uuid not null references books(id),
  storage_key text not null unique,                      -- '<tenant_id>/<book_id>/<id>' — per-tenant prefix (ADR 05c §8)
  size bigint not null check (size >= 0 and size <= 10485760),   -- 10 MB per file (08 §2)
  blob_hash bytea not null check (octet_length(blob_hash) = 32),
  created_at timestamptz not null default now()
);
create index attachments_book_idx on attachments (book_id);

-- Usage counters for quotas (05 §3, ADR 2026-09-05b §7): maintained by trigger on the append-only
-- store, so the function never counts a book's envelopes at push time.
create table book_usage (
  book_id uuid primary key references books(id),
  tenant_id uuid not null references tenants(id),
  envelope_count bigint not null default 0,
  bytes bigint not null default 0,
  updated_at timestamptz not null default now()
);
create index book_usage_tenant_idx on book_usage (tenant_id);

create or replace function rf.envelope_usage_bump() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into book_usage (book_id, tenant_id, envelope_count, bytes)
  values (new.book_id, new.tenant_id, 1, new.size)
  on conflict (book_id) do update
    set envelope_count = book_usage.envelope_count + 1,
        bytes = book_usage.bytes + excluded.bytes,
        updated_at = now();
  return new;
end $$;
create trigger envelopes_usage after insert on envelopes
  for each row execute function rf.envelope_usage_bump();

-- Deletion under the maintenance role (03 §2.5, ADR 2026-09-05b §8): only personal-book envelopes
-- of an erased user may ever be deleted; a shared-book delete raises even for rf_maintenance.
create or replace function rf.guard_envelope_delete() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_type text; v_owner uuid; v_erased timestamptz;
begin
  select b.type, b.owner_user_id into v_type, v_owner from books b where b.id = old.book_id;
  if v_type is distinct from 'personal' then
    raise exception 'append_only' using detail = 'shared-book envelopes are never deleted (CLAUDE.md rule 2)';
  end if;
  select u.erased_at into v_erased from users u where u.id = v_owner;
  if v_erased is null then
    raise exception 'append_only' using detail = 'personal-book envelopes are deleted only for an erased owner (06 §9.3)';
  end if;
  return old;
end $$;
create trigger envelopes_delete_guard before delete on envelopes
  for each row execute function rf.guard_envelope_delete();

create or replace function rf.refuse_update() returns trigger
language plpgsql as $$
begin
  raise exception 'append_only' using detail = format('%s rows are never updated', tg_table_name);
end $$;
create trigger envelopes_no_update before update on envelopes for each row execute function rf.refuse_update();
create trigger signed_records_no_update before update on signed_records
  for each row when (old.applied_at is not null) execute function rf.refuse_update();
