-- 0018 — the plan catalogue (ADR 2026-09-25 §5–§6, amending 08 §2–§3 and ADR 2026-09-05g §1, §3).
-- ⟦tests: E-25-3, G-25-1, G-25-2, G-25-3, G-25-4, E-03-75, E-03-76, E-03-77, E-03-78, E-03-79⟧
--
-- ADR 2026-09-25 §6 🔒: "One server-side plan catalogue holds every plan: entity type, name, limits,
-- included extras, prices in integer paise, and the popular flag. The server's enforced limits are
-- read from it. `PLAN_LIMITS` in `registry.ts` stops being a hard-coded table." 08 §2 keeps the
-- RULES; the NUMBERS live here. So this file splits the two the same way:
--
--   * a RULE of ADR 25 §5 is a constraint or a guard in this file, and changing one needs an ADR and
--     a migration — the feature vocabulary (only statement import and PDF output may ever be gated;
--     everything else is never restricted, on any plan), Free is the Individual floor with no extra
--     and no price, one popular plan per entity type, monthly = ten months' price for twelve, the
--     30-day trial on the popular plan once per person;
--   * a NUMBER is a row, and changing one is a data change with no code change and no app release
--     (G-25-4): the next push reads the new quota, the next device registration the new cap, and
--     the next meta pull re-mints every token whose plan row moved.
--
-- Zero-knowledge (CLAUDE.md rule 4): nothing here is tenant data. The catalogue names no tenant,
-- user, device or book; it is product configuration in the same class as `app_config`. The only
-- tenant rows this file touches are `subscriptions` (through rf.start_trial, SECURITY DEFINER) and
-- `users.trial_consumed_at` (the same function). It reads no envelope, blob or wrapped key, and
-- CLAUDE.md rule 2 holds: no UPDATE or DELETE is granted to anyone on anything here.

-- ---------------------------------------------------------------- 1. the table
-- Limits are named EXACTLY as the entitlement token's `limits` object names them (ADR 2026-09-05g
-- §1 🔒), so the row, the enforced quota and the signed promise cannot drift by a mapping. ADR 25
-- §5's "books · people" are `business_books` · `members`: "Each person's personal book is free and
-- never counted", so `business_books` counts every book but the personal one, and Free's 0 is
-- "the personal book only". -1 is "no cap" on the wire (ADR 2026-09-24b §7 (b) 🔒) and is the only
-- negative any limit may hold. Every integer column is capped at 2^53 − 1 so the edge (Deno numbers)
-- reads it exactly — a limit or a price that silently rounds is the float bug of CLAUDE.md rule 1.
create table plan_catalogue (
  id text primary key check (id ~ '^[a-z][a-z0-9_]{0,31}$'),        -- the token's `plan` (ADR 25 §6)
  -- S0.3's five cards (07 §3.1 🔒) collapse to four entity types: Myself → individual, My shop and
  -- My businesses → business, My family → family, Our trust → trust (ADR 25 §5's table rows).
  entity_type text not null check (entity_type in ('individual', 'family', 'business', 'trust')),
  -- The owner's English label for the console. ⚠️ SPEC (CLAUDE.md rule 8): the app renders the
  -- plan's ARB string keyed by `id`, never this column, so an owner-typed name cannot bypass
  -- EN/PA/HI. Reported for the S12.1 client lane.
  name text not null check (char_length(name) between 1 and 40),
  sort_order int not null default 0,                                 -- S12.1 card order in an entity
  members int not null check (members = -1 or members between 1 and 2147483647),
  business_books int not null check (business_books >= -1),
  devices int not null check (devices = -1 or devices >= 1),
  envelopes_per_book bigint not null
    check (envelopes_per_book = -1 or envelopes_per_book between 1 and 9007199254740991),
  tenant_bytes bigint not null
    check (tenant_bytes = -1 or tenant_bytes between 1 and 9007199254740991),
  attachment_bytes bigint not null
    check (attachment_bytes between -1 and 9007199254740991),
  -- G-25-1 as a schema fact. ADR 25 §5 🔒: plans "differ only by scale (books, people, devices,
  -- storage), statement import, and PDF output" and everything else is "never restricted, on any
  -- plan including Free". So the ONLY extras a plan can include — and therefore the only features a
  -- token can ever carry and an app gate can ever read — are these two. A catalogue row that tried
  -- to gate CSV export, month close or any other book-flow feature is refused by the database, not
  -- by a reviewer. A null element fails the containment too.
  features text[] not null default '{}'
    check (features <@ array['statement_import', 'pdf_output']::text[]),
  -- GST-inclusive integer paise (CLAUDE.md rule 1; ADR 25 §5 "GST-inclusive per year").
  price_yearly_paise bigint not null check (price_yearly_paise between 0 and 9007199254740991),
  price_monthly_paise bigint not null check (price_monthly_paise between 0 and 9007199254740991),
  -- ADR 25 §5: "monthly is *ten months' price for twelve*" — a year costs ten months. This rule
  -- supersedes ADR 2026-09-24b §11's "≈ 20 % dearer, rounded up" placeholder ratio (ADR 25 is the
  -- newer ruling on the same numbers). Any yearly price in whole rupees satisfies it exactly.
  constraint plan_catalogue_ten_for_twelve check (price_monthly_paise * 10 = price_yearly_paise),
  popular boolean not null default false,
  -- ADR 2026-09-24b §11 🔒: prices "ship as flagged placeholders … until then both columns stay
  -- marked placeholder"; ADR 25 §5: "placeholders until the pilot and the Apple price-point check".
  placeholder boolean not null default true,
  updated_at timestamptz not null default now()          -- the re-mint rule reads it (entitlement.ts)
);
-- ADR 25 §5: "The trial always runs on the entity type's **popular** plan" — which needs at most one.
create unique index plan_catalogue_one_popular on plan_catalogue (entity_type) where popular;
create trigger plan_catalogue_touch before update on plan_catalogue
  for each row execute function rf.touch_updated_at();

-- ---------------------------------------------------------------- 2. the rules a row may not break
-- `free` is the floor: ADR 2026-09-05g §1 🔒 "a tenant with no valid token is *Free*, never
-- *locked*", and rf.device_cap / the edge fall back to it for a tenant with no subscription row.
-- ADR 25 §5 🔒 fixes what Free IS — "Individual (*Myself*) has a permanent **Free** plan: the
-- personal book only, no statement import, and **no PDF output**" — so those are rules, not
-- numbers: the row can never be deleted, renamed, moved to another entity type, priced, or given an
-- extra. (Its scale — devices, storage — stays data.) A plan id is immutable for every row: it is
-- the value stored in `subscriptions.plan` and signed into every token.
create or replace function rf.plan_catalogue_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.id = 'free' then
      raise exception 'plan_catalogue_floor' using errcode = '42501',
        detail = 'the free plan is the floor every tokenless tenant reads (ADR 2026-09-05g §1)';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and new.id is distinct from old.id then
    raise exception 'plan_id_immutable' using errcode = '42501',
      detail = 'a plan id is stored in subscriptions and signed into tokens';
  end if;
  if new.id = 'free' and (new.entity_type <> 'individual' or new.price_yearly_paise <> 0
      or new.price_monthly_paise <> 0 or cardinality(new.features) <> 0
      or new.business_books <> 0) then
    raise exception 'plan_catalogue_floor' using errcode = '42501',
      detail = 'Free is Individual, personal book only, no import, no PDF, no price (ADR 2026-09-25 §5)';
  end if;
  return new;
end $$;
create trigger plan_catalogue_guard before insert or update or delete on plan_catalogue
  for each row execute function rf.plan_catalogue_guard();

-- ---------------------------------------------------------------- 3. the seed: ADR 25 §5's table
-- "Working prices (GST-inclusive per year; monthly is ten months' price for twelve). These are
-- placeholders until the pilot and the Apple price-point check, and they live in the catalogue."
-- Every row is `placeholder = true` (ADR 2026-09-24b §11 🔒).
--
-- The four ids 08 §2 used (free, personal, family, family_plus) are kept as catalogue ids, so every
-- `subscriptions.plan` value that could exist before this file is still valid and the FK below
-- adds cleanly.
--
-- Books · people · price · extras are ADR 25 §5's, verbatim. Devices and the three storage limits
-- are NOT in ADR 25's table:
--   * free, personal, family, family_plus keep 08 §2's quota column for their id exactly (ADR
--     2026-09-05g §3 🔒's numbers, now catalogue data);
--   * ⚠️ SPEC: the six new plans have no quota ruled anywhere. Conservative reading — no new plan is
--     given less than 08 §2 gave its nearest predecessor: every plan below the top of its entity
--     type (shop, business, family_lite, trust) takes the Family column (8 devices, 250 k
--     envelopes/book, 5 GiB, 5 GiB), and every top plan (business_plus, trust_plus) takes the
--     Family+ column (15, 1 M, 15 GiB, 20 GiB). Reported to the owner; changing it is a data change.
--
-- Popular: ADR 25 §5 bolds **Business ₹2,999** and **Family ₹2,499** (and ADR 2026-09-24b §11 put
-- *popular* on Family). ⚠️ SPEC: Trust's row bolds neither plan, yet "Family, Business and Trust
-- have … a 30-day trial [that] always runs on the entity type's popular plan", so Trust needs one.
-- ADR 25 §5's shape is "the step below it sits just short … the step above it is the anchor"; with
-- two plans the top one is the anchor, so `trust` (the lower) is popular. Individual has no trial
-- and no bolded plan, so neither of its rows is popular. Both reported.
insert into plan_catalogue (id, entity_type, name, sort_order, members, business_books, devices,
    envelopes_per_book, tenant_bytes, attachment_bytes, features, price_yearly_paise,
    price_monthly_paise, popular, placeholder) values
  -- Individual: Free ₹0 (personal only · 1) · Personal ₹990 (personal + 3 · 1)
  ('free',          'individual', 'Free',        1,  1,  0,  5,    10000,   262144000,   104857600,
     '{}',                                   0,      0, false, true),
  ('personal',      'individual', 'Personal',    2,  1,  3,  5,   100000,  2147483648,  2147483648,
     '{statement_import,pdf_output}',    99000,   9900, false, true),
  -- Business: Shop ₹2,499 (1 · 2, no import or PDF) · Business ₹2,999 (5 · 10) · Business+ ₹6,999 (15 · 30)
  ('shop',          'business',   'Shop',        1,  2,  1,  8,   250000,  5368709120,  5368709120,
     '{}',                              249900,  24990, false, true),
  ('business',      'business',   'Business',    2, 10,  5,  8,   250000,  5368709120,  5368709120,
     '{statement_import,pdf_output}',   299900,  29990, true,  true),
  ('business_plus', 'business',   'Business+',   3, 30, 15, 15,  1000000, 16106127360, 21474836480,
     '{statement_import,pdf_output}',   699900,  69990, false, true),
  -- Family: Family Lite ₹1,999 (2 · 4, no import or PDF) · Family ₹2,499 (8 · 12) · Family+ ₹5,999 (20 · 30)
  ('family_lite',   'family',     'Family Lite', 1,  4,  2,  8,   250000,  5368709120,  5368709120,
     '{}',                              199900,  19990, false, true),
  ('family',        'family',     'Family',      2, 12,  8,  8,   250000,  5368709120,  5368709120,
     '{statement_import,pdf_output}',   249900,  24990, true,  true),
  ('family_plus',   'family',     'Family+',     3, 30, 20, 15,  1000000, 16106127360, 21474836480,
     '{statement_import,pdf_output}',   599900,  59990, false, true),
  -- Trust: Trust ₹1,999 (3 · 15) · Trust+ ₹3,999 (10 · 40)
  ('trust',         'trust',      'Trust',       1, 15,  3,  8,   250000,  5368709120,  5368709120,
     '{statement_import,pdf_output}',   199900,  19990, true,  true),
  ('trust_plus',    'trust',      'Trust+',      2, 40, 10, 15,  1000000, 16106127360, 21474836480,
     '{statement_import,pdf_output}',   399900,  39990, false, true);

-- ---------------------------------------------------------------- 4. a subscription names a catalogue plan
-- ADR 25 §6: "The token's `plan` becomes a catalogue id, not one of four fixed names." 0004's
-- column CHECK listed 08 §2's four names; a Business or Trust purchase could not be stored under
-- it. 03 §2.4 🔒 lists `plan` without a CHECK, so replacing the CHECK with a foreign key changes no
-- 🔒 shape — it narrows the column to exactly the ids the catalogue holds (and, with the guard
-- above, a plan in use can never be deleted from under a subscription: ON DELETE is RESTRICT).
alter table subscriptions drop constraint subscriptions_plan_check;
alter table subscriptions add constraint subscriptions_plan_fk
  foreign key (plan) references plan_catalogue (id);

-- ---------------------------------------------------------------- 5. the device cap reads the catalogue
-- 06 §6 as amended by ADR 2026-09-05g §7 🔒: "Device cap per user = the highest cap among the
-- user's active tenants." 0005 hard-coded 5 / 8 / 15 by plan name; the number is now the plan
-- row's `devices`, and a user in no active tenant gets the Free floor's. NO_CAP (-1) is "no cap"
-- (ADR 2026-09-24b §7 (b)), so it sorts ABOVE every count rather than below.
create or replace function rf.device_cap(p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(
    max(case when c.devices = -1 then 2147483647 else c.devices end),
    (select case when f.devices = -1 then 2147483647 else f.devices end
       from plan_catalogue f where f.id = 'free'))
  from memberships m
  left join subscriptions s on s.tenant_id = m.tenant_id
  join plan_catalogue c on c.id = coalesce(s.plan, 'free')
  where m.user_id = p_user and m.status = 'active'
$$;

-- ---------------------------------------------------------------- 6. the trial
-- ADR 25 §5 🔒: "Family, Business and Trust have **no Free plan and a 30-day trial**. The trial
-- always runs on the entity type's **popular** plan, once per person (`users.trial_consumed_at`,
-- 08 §2)." "Individual (*Myself*) has a permanent **Free** plan" — no trial. ADR 2026-09-05g §12 🔒:
-- "Trial is **once per user** … not per tenant."
--
-- What the server enforces, and nothing else (client presentation is S12.1's):
--   * only a tenant admin, on a certified device, active in the tenant (rf.is_tenant_admin) — the
--     same person ADR 2026-09-05g §7 lets purchase;
--   * never for `individual`;
--   * the entity type must agree with the one tenant type 07 §3.1 🔒 ties to a card: "This card is
--     the only one that sets `tenant.type = organization`", so trust ⇔ organization. ⚠️ SPEC: 07
--     does not say which tenant type Myself / My shop / My businesses create, so family vs
--     business vs individual is taken from the caller and only the trust link is checked;
--   * once per PERSON: `users.trial_consumed_at` is null, and is set in the same transaction;
--   * the plan is the entity type's popular row AT THE TIME the trial starts, written onto
--     `subscriptions.plan`, so the token, the push quota and the device cap all read one row and
--     no reader re-derives the trial. ⚠️ SPEC: moving the popular flag later does not move a trial
--     already running (the conservative reading: a data change never re-grants or narrows a trial
--     in flight). Reported.
--   * ⚠️ SPEC: once per TENANT as well — a tenant that has already had a trial, a paid period or a
--     gateway reference is refused (`trial_unavailable`). ADR 05g §12 keys the trial on the person
--     "not per tenant"; the conservative reading is that a second admin cannot re-start 30 days on
--     a tenant that already had them. Reported.
create or replace function rf.start_trial(p_tenant uuid, p_entity text)
-- OUT names differ from the subscriptions columns so no statement below can read one as the other.
returns table (trial_plan text, trial_ends_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_type text;
  v_plan text;
  v_sub  subscriptions%rowtype;
  v_end  timestamptz := now() + interval '30 days';   -- ADR 25 §5: "a 30-day trial" (a rule)
begin
  if not rf.is_tenant_admin(p_tenant) then
    raise exception 'not_admin' using errcode = '42501';
  end if;
  if p_entity is null or p_entity not in ('individual', 'family', 'business', 'trust') then
    raise exception 'bad_entity_type';
  end if;
  if p_entity = 'individual' then
    raise exception 'no_trial';          -- ADR 25 §5: Individual has a permanent Free plan instead
  end if;
  select t.type into v_type from tenants t where t.id = p_tenant;
  if (p_entity = 'trust') is distinct from (v_type = 'organization') then
    raise exception 'entity_mismatch';
  end if;

  perform 1 from users u where u.id = rf.user_id() and u.trial_consumed_at is null for update;
  if not found then
    raise exception 'trial_consumed';    -- once per person (ADR 2026-09-05g §12)
  end if;

  select c.id into v_plan from plan_catalogue c where c.entity_type = p_entity and c.popular;
  if v_plan is null then
    raise exception 'no_popular_plan';
  end if;

  select * into v_sub from subscriptions s where s.tenant_id = p_tenant for update;
  if found then
    if v_sub.trial_end is not null or v_sub.current_period_end is not null
       or v_sub.gateway_ref is not null or v_sub.status <> 'active' then
      raise exception 'trial_unavailable';
    end if;
    update subscriptions s set plan = v_plan, status = 'trial', trial_end = v_end
      where s.tenant_id = p_tenant;
  else
    insert into subscriptions (tenant_id, plan, status, trial_end)
      values (p_tenant, v_plan, 'trial', v_end)
      on conflict (tenant_id) do nothing;
    if not found then
      raise exception 'trial_unavailable';   -- another admin's start won the race
    end if;
  end if;

  update users u set trial_consumed_at = now() where u.id = rf.user_id();
  return query select v_plan, v_end;
end $$;

-- ---------------------------------------------------------------- 7. an activation must name a catalogue plan
-- 0013's apply path wrote `coalesce(p_plan, plan)`, and the webhook dropped any plan outside 08 §2's
-- four names to null first — so, with the catalogue, a Business or Trust purchase would activate
-- with the tenant's OLD plan. The webhook now passes any well-formed id through, and a PRESENT but
-- malformed plan as '' (which the id CHECK above means no row can hold) rather than as null, so
-- only an event that names no plan at all keeps the old one. The one place that knows which ids
-- exist then decides: an activation naming a plan the catalogue does not hold is
-- RECORDED and not applied (`unknown_plan`) — never guessed, never silently kept at the old plan,
-- never a silent drop (ADR 2026-09-05b §7's shape; 0013's own rule for what it cannot read). The
-- rest of the body is 0013's, unchanged.
create or replace function rf.apply_billing_event(
  p_event_id   text,
  p_gateway    text,
  p_type       text,
  p_hash       bytea,
  p_action     text,
  p_tenant     uuid        default null,
  p_event_at   timestamptz default null,
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
    return query select true, false, 'no_event_at'::text;
    return;
  end if;
  if p_action = 'activate' and p_plan is not null
     and not exists (select 1 from plan_catalogue c where c.id = p_plan) then
    return query select true, false, 'unknown_plan'::text;   -- 0018: recorded, not applied
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
      return query select true, false, 'no_period_end'::text;
      return;
    end if;
    update subscriptions set
      status      = 'past_due',
      grace_kind  = 'dunning',
      grace_until = v_base + interval '7 days'
    where tenant_id = v_tenant;

  elsif p_action = 'end_now' then
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

-- ---------------------------------------------------------------- 8. RLS, policies, grants — each one justified
-- 0005's DO block enabled + forced RLS on the tables that existed then; a later table does its own
-- (the 0007 / 0010 / 0011 pattern).
alter table plan_catalogue enable row level security;
alter table plan_catalogue force row level security;

-- rf_api: SELECT, for the one route that serves the catalogue (sync-meta GET /plans, 05 §5 meta
-- channel) and for the edge's quota / token reads. The policy asks only for an authenticated
-- caller — deliberately NOT rf.is_certified(): the catalogue is not tenant data (ADR 2026-09-05d
-- §2 🔒 is certified-only for TENANT data), it names no tenant, user or device, and a phone on
-- S12.1 before its certificate lands has nothing to learn from it but public prices. A claims-less
-- rf_api transaction (the min-version gate's) reads nothing.
grant select on plan_catalogue to rf_api;
create policy plan_catalogue_select on plan_catalogue for select to rf_api
  using (rf.user_id() is not null);

-- NO INSERT, UPDATE or DELETE to rf_api or rf_maintenance. ADR 25 §6: "Until the console exists,
-- a catalogue change is a data change plus a server deploy" — i.e. a migration, which runs as the
-- schema owner and needs no grant. The console (M13, ADR 2026-09-05h four-eyes + hash-chained
-- staff log, "that log is the price history") will add its own role and path; nothing here
-- pre-grants it. rf_maintenance's retention powers have no business with prices.

-- Platform roles keep nothing (0005's rule, restated for a table created after its DO block).
do $$ declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on table public.plan_catalogue from %I', r);
    end if;
  end loop;
end $$;

-- Functions. 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before
-- these existed. The guard is a trigger function: nobody calls it. rf.start_trial is the one new
-- rf_api power, and it is SECURITY DEFINER so that rf_api still holds no write on `subscriptions`
-- or `users.trial_consumed_at`. rf.device_cap and rf.apply_billing_event are `create or replace`
-- of 0005's / 0013's functions and keep the grants those files gave them.
revoke all on function rf.plan_catalogue_guard() from public;
revoke all on function rf.start_trial(uuid, text) from public;
grant execute on function rf.start_trial(uuid, text) to rf_api;
