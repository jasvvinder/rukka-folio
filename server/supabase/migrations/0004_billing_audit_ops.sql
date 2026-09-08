-- 03 §2.4 Billing, audit, ops 🔒 + the ephemeral auth tables of 06 §2–§4 and the server's
-- rate-limit / freeze bookkeeping (ADR 2026-09-05b §7, ADR 2026-09-05h §1).
create table subscriptions (
  tenant_id uuid primary key references tenants(id),
  plan text not null default 'free' check (plan in ('free','personal','family','family_plus')),
  status text not null default 'active' check (status in ('active','past_due','cancelled','expired','trial')),
  gateway text null,
  gateway_ref text null,
  current_period_end timestamptz null,
  source text null check (source is null or source in ('razorpay','apple','google','manual')),
  original_transaction_id text null,
  payer_user_id uuid null references users(id),          -- only a tenant admin (ADR 2026-09-05g §7)
  trial_end timestamptz null,
  grace_until timestamptz null,
  grace_kind text null check (grace_kind is null or grace_kind in ('dunning')),
  cancel_at_period_end boolean not null default false,
  seats_addon int not null default 0 check (seats_addon >= 0),
  dispute_state text null,
  updated_at timestamptz not null default now()          -- 05 §5 cursor
);
create trigger subscriptions_touch before update on subscriptions for each row execute function rf.touch_updated_at();

-- Entitlement tokens (ADR 2026-09-05g §1, §4): Ed25519 by the server's entitlement_key; served via sync-meta.
create table entitlement_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id),
  token bytea not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index entitlement_tokens_tenant_idx on entitlement_tokens (tenant_id, updated_at);
create trigger entitlement_tokens_touch before update on entitlement_tokens for each row execute function rf.touch_updated_at();

create table billing_events (
  event_id text primary key,                             -- gateway event id: the idempotency key
  gateway text not null,
  type text not null,
  payload_hash bytea not null check (octet_length(payload_hash) = 32),
  received_at timestamptz not null default now(),
  applied_at timestamptz null
);

create table promo_codes (
  code text primary key,
  max_redemptions int not null check (max_redemptions > 0),
  per_user_limit int not null default 1 check (per_user_limit > 0),
  first_purchase_only boolean not null default false,
  valid_from timestamptz not null,
  valid_to timestamptz not null
);
create table promo_redemptions (
  code text not null references promo_codes(code),
  user_id uuid not null references users(id),
  tenant_id uuid not null references tenants(id),
  at timestamptz not null default now(),
  primary key (code, user_id, tenant_id)
);

-- Member-facing operational log. Never financial content. The STAFF log is off-box (12 §3).
create table audit_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid null references tenants(id),
  user_id uuid null references users(id),
  kind text not null,
  details jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
create index audit_events_tenant_idx on audit_events (tenant_id, at);
create index audit_events_user_idx on audit_events (user_id, at);

create table app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
insert into app_config (key, value) values
  ('min_client_version.sync', '"0.1.0"'),
  ('min_client_version.auth', '"0.1.0"'),
  ('min_client_version.billing', '"0.1.0"'),
  ('registry.suite_versions', '[1]'),
  ('registry.payload_schemas', '[1]');

-- Ephemeral auth rows, TTL-purged 24 h (06 §2–§3; 03 §6). Phone appears ONLY as phone_hmac here.
create table otp_challenges (
  id uuid primary key default gen_random_uuid(),
  phone_hmac bytea not null,
  purpose text not null check (purpose in ('signup','device_activation','phone_change','account_deletion')),
  code_hash bytea not null check (octet_length(code_hash) = 32),   -- BLAKE2b of the 6 digits; never the code
  attempts int not null default 0 check (attempts >= 0 and attempts <= 3),
  channel text not null check (channel in ('whatsapp','sms')),
  ip_hash bytea null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,                       -- created_at + 5 min
  consumed_at timestamptz null
);
create index otp_challenges_phone_idx on otp_challenges (phone_hmac, created_at);
create index otp_challenges_ip_idx on otp_challenges (ip_hash, created_at);

create table activation_tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_hash bytea not null unique check (octet_length(ticket_hash) = 32),
  phone_hmac bytea not null,
  purpose text not null,
  user_id uuid null references users(id),               -- null until signup creates the user
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz null                           -- consumable exactly once (06 §2)
);

create table auth_nonces (
  nonce bytea primary key check (octet_length(nonce) = 32),   -- 06 §4: 32 bytes, 60 s TTL, single use
  device_id uuid not null references devices(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz null
);
create index auth_nonces_device_idx on auth_nonces (device_id, created_at);

create table refresh_tokens (
  token_hash bytea primary key check (octet_length(token_hash) = 32),
  family_id uuid not null,                               -- reuse of a rotated token revokes the family (06 §4)
  device_id uuid not null references devices(id),
  user_id uuid not null references users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,                       -- 30 days idle cap
  rotated_at timestamptz null,
  revoked_at timestamptz null
);
create index refresh_tokens_family_idx on refresh_tokens (family_id);
create index refresh_tokens_device_idx on refresh_tokens (device_id);

-- Per-device push rate windows (05 §3: 600/min, 5,000/h, 50 MB/day, plan-independent).
create table push_rate (
  device_id uuid primary key references devices(id),
  minute_start timestamptz not null,
  minute_count int not null default 0,
  hour_start timestamptz not null,
  hour_count int not null default 0,
  day_start timestamptz not null,
  day_bytes bigint not null default 0
);

-- Support freeze (06 §8, ADR 2026-09-05h §1): pushes refused with rejected:tenant_frozen; pull,
-- read and export continue; grounds exhaustive; expiry ≤ 30 days; four-eyes (imposed ≠ approved).
create table tenant_freezes (
  tenant_id uuid primary key references tenants(id),
  ground text not null check (ground in ('payment_fraud','legal_order','abuse')),
  imposed_by text not null,                              -- staff id (console, 12) — not a users row
  approved_by text not null check (approved_by <> imposed_by),
  imposed_at timestamptz not null default now(),
  expires_at timestamptz not null,
  lifted_at timestamptz null,
  updated_at timestamptz not null default now(),
  constraint tenant_freezes_max_30d check (expires_at <= imposed_at + interval '30 days')
);
create trigger tenant_freezes_touch before update on tenant_freezes for each row execute function rf.touch_updated_at();

-- TTL purge for the ephemeral auth rows (03 §6: 24 h). Scheduled by pg_cron in the hosted project
-- (server/README.md §5); callable by rf_maintenance only.
create or replace function rf.purge_ephemeral_auth() returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; m int;
begin
  delete from otp_challenges where created_at < now() - interval '24 hours'; get diagnostics m = row_count; n := n + m;
  delete from activation_tickets where created_at < now() - interval '24 hours'; get diagnostics m = row_count; n := n + m;
  delete from auth_nonces where created_at < now() - interval '24 hours'; get diagnostics m = row_count; n := n + m;
  delete from refresh_tokens where expires_at < now() - interval '24 hours'; get diagnostics m = row_count; n := n + m;
  delete from wrapped_keys where revoked_at is not null and revoked_at < now() - interval '90 days'; get diagnostics m = row_count; n := n + m;
  return n;
end $$;
revoke all on function rf.purge_ephemeral_auth() from public;
