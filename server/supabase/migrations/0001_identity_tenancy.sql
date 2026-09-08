-- 03 §2.1 Identity & tenancy (plaintext) 🔒. Phone numbers: phone_ct (encrypted under the server
-- KMS/Vault key) + phone_hmac (keyed hash, unique) ONLY — ADR 2026-09-05c §4. No plaintext number.
create extension if not exists pgcrypto;

create schema if not exists rf;   -- helper functions + roles live here; tables stay in public

-- Roles (ADR 2026-09-05b §8, 03 §2.5): the API role and the deletion-only maintenance role.
-- Both NOLOGIN; the login user is provisioned by ops and GRANTed one of them (server/README.md §3).
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'rf_api') then
    create role rf_api nologin nobypassrls noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'rf_maintenance') then
    create role rf_maintenance nologin nobypassrls noinherit;
  end if;
end $$;

-- updated_at on every meta table: 05 §5 cursor = (updated_at, id) per table.
create or replace function rf.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create table users (
  id uuid primary key default gen_random_uuid(),
  trial_consumed_at timestamptz null,                   -- trial once per user (ADR 2026-09-05g §12)
  phone_ct bytea null,                                   -- ciphertext; null after erasure (06 §9.3)
  phone_hmac bytea null unique,                          -- lookup key; null after erasure
  display_name text null,
  photo_key text null,
  language text null check (language is null or language in ('en','pa','hi')),
  whatsapp_opt_in boolean not null default false,
  created_at timestamptz not null default now(),
  deletion_requested_at timestamptz null,
  deleted_at timestamptz null,                           -- 15-day cooling between the last two
  erased_at timestamptz null,                            -- 03 §2.5 deletion mechanics
  updated_at timestamptz not null default now(),
  constraint users_cooling_15d check (
    deleted_at is null or deletion_requested_at is null
    or deleted_at >= deletion_requested_at + interval '15 days')
);
create trigger users_touch before update on users for each row execute function rf.touch_updated_at();

-- UMK public keys: the verification material 06 §9.3 retains after erasure (04 §3.4). Server needs it
-- to verify a device certificate before setting devices.status='certified' (ADR 2026-09-05d §2).
create table umk_public_keys (
  user_id uuid not null references users(id),
  key_version int not null default 1 check (key_version >= 1),
  pub_ed bytea not null check (octet_length(pub_ed) = 32),
  created_at timestamptz not null default now(),
  superseded_at timestamptz null,
  updated_at timestamptz not null default now(),
  primary key (user_id, key_version)
);
create trigger umk_public_keys_touch before update on umk_public_keys for each row execute function rf.touch_updated_at();

create table tenants (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('family','business_group','organization')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger tenants_touch before update on tenants for each row execute function rf.touch_updated_at();

create table memberships (
  tenant_id uuid not null references tenants(id),
  user_id uuid not null references users(id),
  status text not null check (status in
    ('invited','joined_pending_verification','active','blocked','removed')),
  verified_by uuid null references users(id),
  verified_method text null check (verified_method is null or verified_method in
    ('qr_in_person','code_remote','device_link')),
  verified_at timestamptz null,
  -- 03 §2.5 / ADR 2026-09-05b §1: rows are projections of signed records
  source_record_id uuid null,
  updated_at timestamptz not null default now(),
  primary key (tenant_id, user_id)
);
create index memberships_user_idx on memberships (user_id);
create trigger memberships_touch before update on memberships for each row execute function rf.touch_updated_at();

create table books (
  id uuid primary key,                                   -- client-minted UUIDv7 (03 §1)
  tenant_id uuid not null references tenants(id),
  type text not null check (type in ('personal','family','joint','business')),
  owner_user_id uuid null references users(id),          -- personal books only
  fy_start_month int not null default 4 check (fy_start_month between 1 and 12),
  created_at timestamptz not null default now(),
  archived_at timestamptz null,
  updated_at timestamptz not null default now(),
  constraint books_personal_owner check ((type = 'personal') = (owner_user_id is not null))
);
create index books_tenant_idx on books (tenant_id);
create trigger books_touch before update on books for each row execute function rf.touch_updated_at();

create table book_roles (
  book_id uuid not null references books(id),
  user_id uuid not null references users(id),
  role text not null check (role in ('admin','head','member','operator','viewer')),
  auto_post_limit_paise bigint null check (auto_post_limit_paise is null or auto_post_limit_paise >= 0),
  source_record_id uuid null,
  updated_at timestamptz not null default now(),
  primary key (book_id, user_id)
);
create index book_roles_user_idx on book_roles (user_id);
create trigger book_roles_touch before update on book_roles for each row execute function rf.touch_updated_at();
