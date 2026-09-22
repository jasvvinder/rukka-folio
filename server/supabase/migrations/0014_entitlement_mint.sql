-- 0014 — the entitlement token's WRITE path: `rf.mint_entitlement_token`.
--
-- 0004 created `entitlement_tokens` and 0005 gave rf_api SELECT on it under `rf.active_in_tenant`
-- and nothing else, so until this migration NOTHING could ever write a row: every tenant was
-- tokenless, and ADR 2026-09-05g §1 🔒's "refreshed on every meta pull" had no refresh behind it.
-- This file adds the one write path, and adds no table grant at all.
--
-- 08 §3 line 35 🔒 / ADR 2026-09-05g §1 🔒: an Ed25519 token `{tenant_id, plan, limits, period_end,
-- grace_kind, iat, exp ≤ 30 d}` signed by the ONE server signing key `entitlement_key`, public key
-- pinned in the app, delivered on the meta channel (05 §5). The signing happens at the edge, in
-- Deno, because that is where the key is injected (04 §8 rule 6 🔒 keeps the key's surface to one
-- typed function; see functions/_shared/sodium.ts). Postgres therefore never sees the key and
-- never parses the token: to this function a token is opaque bytes with an expiry, exactly as an
-- envelope blob is. What Postgres DOES own is the authorisation — who may have a token written for
-- them — because that is an RLS question and RLS questions do not live in a handler.
--
-- CLAUDE.md rule 2: no UPDATE and no DELETE is granted to rf_api on anything here, and nothing in
-- this file touches `envelopes`, `signed_records`, `wrapped_keys`, `attachments` or any blob. A
-- token is plan metadata the server already holds (04 §4's plaintext list).

-- ---------------------------------------------------------------- 1. one current token per tenant
-- The token is a statement of the tenant's CURRENT entitlement, not a history: 05 §5 relays the
-- table on an `updated_at,id` cursor, so a new row per pull would churn that cursor forever, grow
-- without bound, and hand the client several tokens for one tenant with no rule for choosing
-- between them. One row, replaced in place; 0004's `entitlement_tokens_touch` trigger moves
-- `updated_at`, which is exactly what makes the refreshed token reach every device.
--
-- This is NOT the append-only ledger rule (CLAUDE.md rule 2, 02 §5): that rule binds envelopes and
-- posted entries — the family's records, which we may never rewrite. An entitlement token is the
-- server's own signed assertion about a plan it already stores, superseded rather than amended,
-- and the durable history of what was billed lives in `billing_events` (append-only under 0013's
-- guard) and `subscriptions`.
create unique index entitlement_tokens_tenant_uq on entitlement_tokens (tenant_id);

-- ---------------------------------------------------------------- 2. the mint
-- Takes opaque bytes and an expiry. It cannot be asked for a plan, a limit or a period: the caller
-- may only present a token that was already signed, for a tenant it is already active in. A
-- compromised rf_api can therefore re-store a token it could already read (every member of the
-- tenant can read it) and nothing more — it cannot mint entitlement, because it has no key.
create or replace function rf.mint_entitlement_token(
  p_tenant     uuid,
  p_token      bytea,
  p_expires_at timestamptz
) returns void
language plpgsql security definer set search_path = public as $$
begin
  -- Certified device + active membership (ADR 2026-09-05d §2 🔒), re-checked here rather than
  -- trusted from the edge: this is the same predicate 0005's `entitlement_select` policy uses, so
  -- a token can only be written for a tenant whose token the caller may already read.
  if not rf.active_in_tenant(p_tenant) then
    raise exception 'not_entitled' using errcode = '42501',
      detail = 'a token is minted only for a tenant the certified caller is active in';
  end if;
  if p_token is null or octet_length(p_token) = 0 or octet_length(p_token) > 4096 then
    raise exception 'bad_entitlement_token' using errcode = '22023';
  end if;
  if p_expires_at is null or p_expires_at <= now() then
    -- An already-expired token would be re-minted on the very next pull, forever.
    raise exception 'bad_entitlement_token' using errcode = '22023',
      detail = 'expires_at must be in the future';
  end if;

  insert into entitlement_tokens (tenant_id, token, expires_at)
    values (p_tenant, p_token, p_expires_at)
  on conflict (tenant_id) do update
    set token      = excluded.token,
        expires_at = excluded.expires_at,
        -- created_at is when THIS token was minted, and the re-mint rule compares it against
        -- `subscriptions.updated_at`; leaving it at the first insert's value would make every
        -- later pull re-mint forever. `updated_at` is moved by the 0004 touch trigger.
        created_at = now();
end $$;

-- 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before this existed.
revoke all on function rf.mint_entitlement_token(uuid, bytea, timestamptz) from public;
grant execute on function rf.mint_entitlement_token(uuid, bytea, timestamptz) to rf_api;

-- No new TABLE grant. rf_api keeps SELECT on `entitlement_tokens` under 0005's
-- `entitlement_select` policy and gains no INSERT, UPDATE or DELETE — E-03-71 … E-03-74 assert it.
