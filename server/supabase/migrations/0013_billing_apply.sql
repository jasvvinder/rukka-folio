-- 0013 — the billing apply path: `rf.apply_billing_event`, beside 0005's `rf.record_billing_event`.
--
-- 0004 built the tables of 03 §2.4 🔒 and 0005 gave the webhook a way to RECORD an event and
-- nothing more (`applied: false` in billing-webhook/index.ts until M13). This migration adds the
-- one transaction that records AND applies, so that dedupe, the out-of-order guard and the state
-- change cannot come apart: 08 §4 🔒 "every webhook is signature-verified, deduped on `event_id`
-- in `billing_events`, guarded against out-of-order delivery"; ADR 2026-09-05g §9 spells the guard
-- out — "apply only if the event's sequence/timestamp is newer than the last applied for that
-- subscription".
--
-- The three outcomes this file implements, and nothing else (08 §3, ADR 2026-09-05g §4, §11):
--
--   activate   subscription.activated / .charged  → plan, status='active', current_period_end,
--              source, gateway, gateway_ref, original_transaction_id; both grace columns cleared.
--   dunning    a failed renewal                   → status='past_due', grace_kind='dunning',
--              grace_until = period_end + 7 days. 08 §3 🔒: "*Dunning grace* (tenant-wide, failed
--              renewal): 7 days from `period_end`". Plan and current_period_end are NOT touched —
--              a dunning tenant keeps the plan it is being dunned for.
--   end_now    refund / chargeback / dispute      → status='expired', BOTH grace columns cleared,
--              dispute_state recorded. ADR 2026-09-05g §11 🔒: "Any refund or chargeback →
--              entitlement ends now, data untouched (read-only, export forever)." Nothing in this
--              file deletes a row of any table, and no DELETE is granted anywhere.
--
-- Anything else is RECORDED and not applied — an unknown type, a malformed body, an event with no
-- resolvable tenant, an out-of-order event. A webhook we do not understand must never be a silent
-- drop (ADR 2026-09-05b §7's shape) and must never be a guess.
--
-- CLAUDE.md rule 2: rf_api gains no UPDATE and no DELETE on any table here. The only write path is
-- this SECURITY DEFINER function, which touches `subscriptions` and `billing_events` and reads
-- neither `envelopes` nor any blob — 08 §5 / 06 §10: "No API path counts, sums, or gates on
-- envelope contents." Rule 4: payer data lives in the gateway's body, which is hashed (BLAKE2b-256)
-- and never stored, never logged.

-- ---------------------------------------------------------------- 1. the out-of-order marker
-- ⚠️ SPEC: ADR 2026-09-05g §9 mandates a guard on "the event's sequence/timestamp … for that
-- subscription", but neither shape in 03 §2.4 🔒 has anywhere to keep it: `subscriptions` has no
-- last-applied stamp and `billing_events(event_id, gateway, type, payload_hash, received_at,
-- applied_at)` says neither WHICH subscription an event belongs to nor WHEN the gateway raised it
-- (`received_at` is our clock, and retries arrive out of order precisely because our clock is not
-- the gateway's). The conservative route of the two is taken: widen the EVENT LOG, not the 🔒
-- `subscriptions` shape — `subscriptions` is on 05 §5's meta cursor and every column added there
-- is a column that syncs to every device. Both columns are nullable, so every row 0004 could hold
-- is still valid, and neither carries payer data. 03 §2.4 needs the two names added; reported.
alter table billing_events
  add column tenant_id uuid null references tenants(id),
  add column event_at timestamptz null;      -- the GATEWAY's timestamp for the event, not ours

comment on column billing_events.tenant_id is
  'Which subscription this event belongs to, once resolved; null when it could not be resolved '
  '(the event is still recorded — never dropped). ADR 2026-09-05g §9.';
comment on column billing_events.event_at is
  'The gateway''s own timestamp/sequence for the event. The out-of-order guard compares it against '
  'the newest APPLIED event of the same tenant; received_at cannot serve, it is our clock. §9.';

-- The guard's read path: newest applied event per tenant.
create index billing_events_applied_idx on billing_events (tenant_id, event_at desc)
  where applied_at is not null;

-- ---------------------------------------------------------------- 2. the event log is append-only
-- `applied_at` is the one column that may ever change, and only null → set, once. Everything else
-- about a recorded event is what the gateway said and what we hashed; rewriting it would rewrite
-- the audit trail the reconciliation poll (ADR 2026-09-05g §9) checks against.
create or replace function rf.billing_events_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'billing_event_immutable' using errcode = '42501',
      detail = 'billing_events is the webhook audit trail: recorded events are never deleted';
  end if;
  if old.applied_at is not null and new.applied_at is distinct from old.applied_at then
    raise exception 'billing_event_immutable' using errcode = '42501',
      detail = 'an applied event is applied once: applied_at is set once and never moved or cleared';
  end if;
  if (new.event_id, new.gateway, new.type, new.payload_hash, new.received_at, new.tenant_id,
      new.event_at)
     is distinct from
     (old.event_id, old.gateway, old.type, old.payload_hash, old.received_at, old.tenant_id,
      old.event_at) then
    raise exception 'billing_event_immutable' using errcode = '42501',
      detail = 'only applied_at may change on a recorded billing event';
  end if;
  return new;
end $$;
create trigger billing_events_guard before update or delete on billing_events
  for each row execute function rf.billing_events_guard();

-- ---------------------------------------------------------------- 3. record-and-apply, one txn
-- `p_action` is decided by the handler from the gateway's event type — that mapping is gateway
-- vocabulary and belongs where the gateway shape lives (billing-webhook/index.ts). What is OUR
-- policy, and lives here where no handler can skip it, is: dedupe, order, and the three state
-- changes above. A caller can only ask for an action; it cannot ask for a column.
create or replace function rf.apply_billing_event(
  p_event_id   text,
  p_gateway    text,
  p_type       text,
  p_hash       bytea,
  p_action     text,                       -- 'activate' | 'dunning' | 'end_now' | 'record_only'
  p_tenant     uuid        default null,   -- from the signed body, when it names one
  p_event_at   timestamptz default null,   -- the gateway's timestamp; the ordering key
  p_plan       text        default null,
  p_period_end timestamptz default null,
  p_gateway_ref text       default null,
  p_source     text        default null,
  p_original_transaction_id text default null,
  p_dispute    text        default null
) returns table (fresh boolean, applied boolean, outcome text)
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid;
  v_last   timestamptz;
  v_sub    subscriptions%rowtype;
  v_base   timestamptz;
begin
  if p_action is null or p_action not in ('activate', 'dunning', 'end_now', 'record_only') then
    raise exception 'unknown_billing_action' using errcode = '22023';
  end if;

  -- Resolve the subscription BEFORE recording, so the event log says which tenant it belonged to
  -- even when we go on to refuse to apply it. gateway_ref first: it is the reference WE stored at
  -- purchase (08 §4 🔒 "gateway holds instruments, we hold reference IDs only"), so it beats a
  -- tenant id carried in the body. p_tenant is the first-activation path, before a ref exists.
  v_tenant := null;
  if p_gateway_ref is not null then
    select s.tenant_id into v_tenant from subscriptions s
      where s.gateway_ref = p_gateway_ref
        and (s.gateway is null or s.gateway = p_gateway)
      limit 1;
  end if;
  v_tenant := coalesce(v_tenant, p_tenant);

  insert into billing_events (event_id, gateway, type, payload_hash, tenant_id, event_at)
    values (p_event_id, p_gateway, p_type, p_hash, v_tenant, p_event_at)
    on conflict (event_id) do nothing;
  if not found then
    -- Replay. 08 §5: "Webhook replay is idempotent". The first delivery already did whatever this
    -- event does; a second one does nothing at all, not even a re-apply of the same state.
    return query select false, false, 'duplicate'::text;
    return;
  end if;

  if p_action = 'record_only' then
    return query select true, false, 'not_applicable'::text;
    return;
  end if;
  if v_tenant is null then
    return query select true, false, 'unknown_tenant'::text;
    return;
  end if;
  if p_event_at is null then
    -- No ordering key means the guard cannot run, and ADR 2026-09-05g §9 makes the guard
    -- unconditional. Recorded, not applied; the daily reconciliation poll is the backstop.
    return query select true, false, 'no_event_at'::text;
    return;
  end if;

  select * into v_sub from subscriptions where tenant_id = v_tenant for update;
  if not found then
    return query select true, false, 'unknown_tenant'::text;
    return;
  end if;

  select max(b.event_at) into v_last from billing_events b
    where b.tenant_id = v_tenant and b.applied_at is not null;
  if v_last is not null and p_event_at <= v_last then
    -- Out of order: an older event overtaking a newer one changes NOTHING. It stays recorded with
    -- applied_at null — that is the evidence the reconciliation poll reads.
    return query select true, false, 'out_of_order'::text;
    return;
  end if;

  if p_action = 'activate' then
    update subscriptions set
      plan               = coalesce(p_plan, plan),
      status             = 'active',
      current_period_end = coalesce(p_period_end, current_period_end),
      gateway            = coalesce(p_gateway, gateway),
      gateway_ref        = coalesce(p_gateway_ref, gateway_ref),
      source             = coalesce(p_source, source),
      original_transaction_id = coalesce(p_original_transaction_id, original_transaction_id),
      grace_until = null, grace_kind = null
    where tenant_id = v_tenant;

  elsif p_action = 'dunning' then
    v_base := coalesce(p_period_end, v_sub.current_period_end);
    if v_base is null then
      -- 08 §3 🔒 measures the dunning grace "7 days from `period_end`". With no period_end there is
      -- nothing to measure from, and inventing one either robs a payer of grace or grants a
      -- never-paid tenant seven days. Conservative reading (CLAUDE.md § Workflow): recorded, not
      -- applied. ⚠️ SPEC: 08 §3 does not say what a dunning event on a subscription with no
      -- period_end means; it should not arise (a renewal implies a period) — reported.
      return query select true, false, 'no_period_end'::text;
      return;
    end if;
    update subscriptions set
      status      = 'past_due',
      grace_kind  = 'dunning',
      grace_until = v_base + interval '7 days'
    where tenant_id = v_tenant;

  elsif p_action = 'end_now' then
    -- "entitlement ends now, data untouched" (ADR 2026-09-05g §11 🔒). Ends = status; untouched =
    -- no delete, here or anywhere: plan, current_period_end and the payer stay exactly as they
    -- were, so the tenant keeps read + export forever (08 §1.4) and the record of what it bought.
    update subscriptions set
      status        = 'expired',
      grace_until   = null,
      grace_kind    = null,
      dispute_state = coalesce(p_dispute, dispute_state)
    where tenant_id = v_tenant;
  end if;

  update billing_events set applied_at = now() where event_id = p_event_id;
  return query select true, true, p_action::text;
end $$;

-- 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before these existed.
revoke all on function rf.billing_events_guard(),
  rf.apply_billing_event(text, text, text, bytea, text, uuid, timestamptz, text, timestamptz,
                         text, text, text, text) from public;
grant execute on function
  rf.apply_billing_event(text, text, text, bytea, text, uuid, timestamptz, text, timestamptz,
                         text, text, text, text) to rf_api;

-- No new TABLE grant. rf_api keeps SELECT on `subscriptions` under 0005's `subscriptions_select`
-- policy (rf.active_in_tenant) and keeps NO privilege at all on billing_events / promo_codes /
-- promo_redemptions. The apply path reaches them only through the SECURITY DEFINER function above,
-- which is the whole point: the API role can ask for a webhook to be applied, it cannot write a
-- plan. E-03-65 … E-03-70 assert each of those as hostile queries.
