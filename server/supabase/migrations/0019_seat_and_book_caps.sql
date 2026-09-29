-- 0019 — the hard seat cap and the hard business-book cap (ADR 2026-09-05g §2, §6 🔒; 08 §3 🔒;
-- 06 §7 Seats; 03 §2.4 plan_catalogue as 0018 ratified it).
-- ⟦tests: E-05g-1, E-05g-2, E-05g-3, E-05g-4, E-05g-5, E-05g-6, E-05g-7, E-05g-8, E-05g-9,
--         E-05g-10, E-05g-11, E-05g-12, E-05g-13, E-05g-14⟧
--
-- ADR 2026-09-05g §2 🔒: "Hard caps are enforced by the server at the three plaintext choke points:
-- invite creation (seats), book creation (business books), device registration (devices)". 0018
-- moved the device cap onto the catalogue; this file adds the other two, reading the SAME plan the
-- same way (§1 below), so all three caps can never disagree about which plan a tenant is on.
--
-- ADR 2026-09-05g §6 🔒, verbatim: "The seat cap counts `invited` + `joined_pending_verification`
-- + `active` (06 §7), so five outstanding invites on a 5-seat plan with one active member is 6 and
-- is refused. Removal frees the seat immediately. Re-inviting the same `user_id` within 30 days
-- does not consume a new seat. A rolling cap of 2 × seats distinct members per year stops seat
-- rotation. Excess on downgrade: nothing deleted, excess members keep read access (08 §3 stands)."
--
-- Where a seat and a book are TAKEN today (grepped, not assumed):
--   * a seat — rf.create_invite (0006:181) and rf_api's direct `insert into invites` under
--     invites_insert (0005); a membership row entering invited / joined_pending_verification /
--     active through rf.project_membership (0005:200, the /records membership_status route) and
--     rf.accept_invite (0006:239). All of them are covered by TRIGGERS on the two tables, so no
--     present or future writer can take a seat around the cap.
--   * a book — there is no rf.create_book: rf_api inserts into `books` directly under 0005's
--     books_insert policy, and no edge route does it yet. So the book cap is a trigger on `books`.
--
-- The refusals are named, never an RLS denial (05c: a refusal is always named): `seat_cap`,
-- `seat_rotation_cap` and `book_cap`, raised as P0001 with the bare name as the message — the shape
-- 0005's `device_cap` already has, which _shared/store.ts denialFromPg passes through as
-- StoreDenied(<name>) and sync-meta maps to 409 (as auth-challenge does `device_cap`).
--
-- All three triggers are AFTER ROW triggers, deliberately: Postgres enforces an INSERT's RLS WITH
-- CHECK after the BEFORE triggers, so a BEFORE-trigger cap would answer `book_cap` to a device of
-- ANOTHER tenant — an oracle over a stranger's plan and book count. AFTER the policy, only a caller
-- the policy (or the SECURITY DEFINER writer's own authorisation) already admitted ever sees a cap.
-- AFTER also means an `insert … on conflict do update` fires exactly the branch that happened.
--
-- Zero-knowledge (CLAUDE.md rule 4): the caps count ROWS — memberships, invites, books — and read
-- no envelope, blob, wrapped key or phone. The one new table (seat_grants) holds tenant, user,
-- invite and time; it stores no invitee_hmac (it joins to the invite row for that) so this file
-- adds no copy of a phone hash anywhere. CLAUDE.md rule 2: nothing here is granted UPDATE or DELETE
-- on anything, and `envelopes` is not touched.

-- ---------------------------------------------------------------- 1. one plan resolution for all three caps
-- 0018's rf.device_cap resolved a tenant's plan as `coalesce(subscriptions.plan, 'free')` — the
-- subscription row's plan whatever its status, and the Free floor when there is no row (ADR
-- 2026-09-05g §1 🔒 "a tenant with no valid token is Free, never locked"). That expression now lives
-- in ONE function and the device cap is re-pointed at it (same semantics, E-05g-12), so the seat,
-- book and device caps read the plan one way and cannot drift.
--
-- ⚠️ SPEC (desk PLAN-48, NOT ruled here): a Family / Business / Trust tenant with no subscription
-- row therefore reads as Free — members 1, business_books 0 — for the seat and book caps too.
-- Reported with the consequence in the lane's `open`.
create or replace function rf.tenant_plan(p_tenant uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select s.plan from subscriptions s where s.tenant_id = p_tenant), 'free')
$$;

-- 0018 §5's body with its join re-pointed at rf.tenant_plan; nothing else changes. `create or
-- replace` keeps the grants 0005 gave it.
create or replace function rf.device_cap(p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(
    max(case when c.devices = -1 then 2147483647 else c.devices end),
    (select case when f.devices = -1 then 2147483647 else f.devices end
       from plan_catalogue f where f.id = 'free'))
  from memberships m
  join plan_catalogue c on c.id = rf.tenant_plan(m.tenant_id)
  where m.user_id = p_user and m.status = 'active'
$$;

-- ---------------------------------------------------------------- 2. which writes are capped
-- The caps bind the API — every rf_api path into memberships, invites and books carries request
-- claims (books_insert and invites_insert need rf.active_in_tenant / rf.is_tenant_admin; the
-- SECURITY DEFINER writers need rf.is_tenant_admin, rf.require_record or the caller's own claims),
-- so a claims-less rf_api transaction cannot write any of these rows at all (E-05g-11). A write
-- with NO claims is the schema owner's — a migration, a repair, the M13 console's own path — and is
-- not one of ADR 05g §2's choke points, exactly as 0005's device cap binds rf.register_device and
-- not an owner's `insert into devices`.
create or replace function rf.caps_apply() returns boolean
language sql stable as $$ select rf.user_id() is not null $$;

-- ---------------------------------------------------------------- 3. the rotation ledger
-- "A rolling cap of 2 × seats distinct members per year" needs history the tables do not keep: a
-- membership is one row per (tenant, user) that is overwritten, and an invite names a number, not
-- a person. So each seat TAKEN is appended here, once, by the triggers below and by nothing else.
--
-- ⚠️ SPEC (reported): ADR 05g §6 does not say what "distinct members per year" keys on, nor what
-- the 30-day sentence is measured from. The conservative reading, taken here:
--   * "per year" is ROLLING — the trailing year from now(), never a calendar or financial year
--     (the ADR says "rolling"; a calendar year would hand out a second budget every 1 January);
--   * a member is a PERSON: the user_id when the invitee has signed up, else the invite's
--     invitee_hmac (joined through invite_id), so the same person invited before sign-up and
--     accepted after is one member, not two;
--   * "re-inviting the same user_id within 30 days does not consume a new seat" is read against
--     THIS budget: a seat taken by a person who already has a counted grant in the last 30 days
--     appends nothing; one taken 30 days or more after that person's last counted grant is counted
--     again. Measuring from the last COUNTED grant (not from a removal, not from the last free
--     re-invite) means the exemption cannot be chained into a permanent free pass;
--   * the 30-day exemption never bends the instantaneous seat cap: `members` seats are never
--     exceeded by a new entry, whoever it is (06 §7 "removal frees the seat at once" already makes
--     a re-invite into a free seat possible; a full plan stays full).
-- A grant is appended on every plan, -1 included, so a later downgrade reads real history rather
-- than a fresh budget.
create table seat_grants (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references tenants(id),
  user_id uuid null references users(id),
  invite_id uuid null references invites(id),
  granted_at timestamptz not null default now(),
  constraint seat_grants_someone check (user_id is not null or invite_id is not null)
);
create index seat_grants_tenant_at on seat_grants (tenant_id, granted_at);
create index seat_grants_user on seat_grants (tenant_id, user_id) where user_id is not null;

-- ---------------------------------------------------------------- 4. counting seats
-- Seat holders of a tenant, EXCLUDING one person (the one taking a seat): every membership at
-- invited / joined_pending_verification / active, plus every LIVE invite (sent, inside its 7-day
-- window) to a number that does not already hold one of those memberships — a person counts once
-- however many rows name them. An invite past its window frees its seat even before the sweep
-- (rf.expire_invites) has run; blocked and removed never count (06 §7).
create or replace function rf.seat_holders(p_tenant uuid, p_except_user uuid, p_except_hmac bytea)
returns int
language sql stable security definer set search_path = public as $$
  select (
    (select count(*) from memberships m
      where m.tenant_id = p_tenant
        and m.status in ('invited', 'joined_pending_verification', 'active')
        and m.user_id is distinct from p_except_user)
    +
    (select count(distinct i.invitee_hmac) from invites i
      where i.tenant_id = p_tenant and i.status = 'sent' and i.expires_at > now()
        and i.invitee_hmac is distinct from p_except_hmac
        and not exists (
          select 1 from memberships m join users u on u.id = m.user_id
          where m.tenant_id = p_tenant
            and m.status in ('invited', 'joined_pending_verification', 'active')
            and u.phone_hmac = i.invitee_hmac))
  )::int
$$;

-- A person takes a seat in a tenant. Serialised per tenant (a transaction-scoped advisory lock, so
-- two admins inviting at `members − 1` cannot both succeed, and an FK check on the tenant row never
-- waits on it), then:
--   1. the seat cap: holders other than this person + 1 must not exceed the plan's `members`;
--   2. the rotation cap: unless this person has a counted grant inside 30 days, counted grants in
--      the trailing year + 1 must not exceed 2 × `members`;
--   3. the grant is appended (counted) unless the 30-day exemption applied.
-- `members = -1` is "no cap" (ADR 2026-09-24b §7 (b) 🔒) and is never refused. The numbers are the
-- catalogue row's, read at the moment of the write (desk PLAN-49: the seed is a placeholder, so no
-- number is written here — only ADR 05g §6's rules: the 2 ×, the 30 days, the year).
create or replace function rf.take_seat(p_tenant uuid, p_user uuid, p_hmac bytea, p_invite uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cap    int;
  v_recent boolean;
  v_used   int;
begin
  perform pg_advisory_xact_lock(hashtextextended('rf.seat_cap:' || p_tenant::text, 0));
  select c.members into v_cap from plan_catalogue c where c.id = rf.tenant_plan(p_tenant);

  if v_cap <> -1 and rf.seat_holders(p_tenant, p_user, p_hmac) + 1 > v_cap then
    raise exception 'seat_cap' using errcode = 'P0001',
      detail = 'the plan''s seats are all held: invited + joined_pending_verification + active (ADR 2026-09-05g §6)',
      hint = 'remove a member or withdraw an invite, or upgrade the plan';
  end if;

  select exists (
    select 1 from seat_grants g left join invites i on i.id = g.invite_id
    where g.tenant_id = p_tenant and g.granted_at > now() - interval '30 days'
      and ((p_user is not null and g.user_id = p_user)
           or (p_hmac is not null and i.invitee_hmac = p_hmac))) into v_recent;
  if v_recent then
    return;   -- ADR 05g §6: the same person within 30 days does not consume a new seat
  end if;

  if v_cap <> -1 then
    select count(*) into v_used from seat_grants g
      where g.tenant_id = p_tenant and g.granted_at > now() - interval '1 year';
    if v_used + 1 > 2 * v_cap then
      raise exception 'seat_rotation_cap' using errcode = 'P0001',
        detail = 'rolling cap of 2 x seats distinct members per year (ADR 2026-09-05g §6)',
        hint = 'upgrade the plan for more members';
    end if;
  end if;

  insert into seat_grants (tenant_id, user_id, invite_id) values (p_tenant, p_user, p_invite);
end $$;

-- ---------------------------------------------------------------- 5. the seat cap at invite creation
-- An invite is a seat from the moment it is sent (06 §7 counts `invited`). Not a new seat when the
-- number already holds one here — a counted membership of the user it belongs to, or another live
-- invite to it (rf.create_invite revokes the previous live one first, so the one-tap re-invite of
-- 06 §7 never double-counts; a direct insert that does not revoke still counts the number once).
create or replace function rf.invite_seat_cap() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_user uuid;
begin
  if not rf.caps_apply() or new.status <> 'sent' then
    return null;
  end if;
  select u.id into v_user from users u
   where u.phone_hmac = new.invitee_hmac and u.erased_at is null;
  if exists (select 1 from memberships m
              where m.tenant_id = new.tenant_id and m.user_id = v_user
                and m.status in ('invited', 'joined_pending_verification', 'active'))
     or exists (select 1 from invites i
                 where i.tenant_id = new.tenant_id and i.id <> new.id
                   and i.invitee_hmac = new.invitee_hmac
                   and i.status = 'sent' and i.expires_at > now()) then
    return null;
  end if;
  perform rf.take_seat(new.tenant_id, v_user, new.invitee_hmac, new.id);
  return null;
end $$;
create trigger invites_seat_cap after insert on invites
  for each row execute function rf.invite_seat_cap();

-- ---------------------------------------------------------------- 6. the seat cap wherever a membership enters a counted state
-- Only an ENTRY is capped: a row arriving at invited / joined_pending_verification / active from
-- nothing, removed or blocked. A move inside the counted set (invited → joined_pending_verification
-- → active) is the same seat, and a self-transition is a re-applied record — so a ceremony in
-- flight is never stranded, and after a downgrade the excess members' rows are never refused
-- (ADR 05g §6: nothing deleted, excess members keep read access). An entry backed by a live invite
-- to this person's number is the seat that invite already took (rf.accept_invite inserts the
-- membership before it marks the invite accepted, so the invite is still live here) — the seat
-- moves, a second is not taken.
create or replace function rf.membership_seat_cap() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_prev text := case when tg_op = 'UPDATE' then old.status else null end;
  v_hmac bytea;
begin
  if not rf.caps_apply()
     or new.status not in ('invited', 'joined_pending_verification', 'active')
     or v_prev in ('invited', 'joined_pending_verification', 'active') then
    return null;
  end if;
  select u.phone_hmac into v_hmac from users u where u.id = new.user_id;
  if v_hmac is not null and exists (
       select 1 from invites i
        where i.tenant_id = new.tenant_id and i.invitee_hmac = v_hmac
          and i.status = 'sent' and i.expires_at > now()) then
    return null;
  end if;
  perform rf.take_seat(new.tenant_id, new.user_id, v_hmac, null);
  return null;
end $$;
create trigger memberships_seat_cap after insert or update of status on memberships
  for each row execute function rf.membership_seat_cap();

-- ---------------------------------------------------------------- 7. the business-book cap at book creation
-- 0018 / ADR 2026-09-25 §5: "Each person's personal book is free and never counted", so
-- `business_books` counts every book but the personal one, and Free's 0 is "the personal book
-- only". -1 is no cap. A personal book returns before anything is read.
--
-- ⚠️ SPEC (reported): an ARCHIVED business book still counts. Archiving is not deleting (the rows
-- and the envelopes stay), 08 §3 counts the "business-book count" without an exception, and the
-- conservative reading is the one that never lets a tenant hold more non-personal books than its
-- plan by archiving and re-creating.
create or replace function rf.book_cap() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_cap int;
  v_n   int;
begin
  if not rf.caps_apply() or new.type = 'personal' then
    return null;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('rf.book_cap:' || new.tenant_id::text, 0));
  select c.business_books into v_cap from plan_catalogue c where c.id = rf.tenant_plan(new.tenant_id);
  if v_cap = -1 then
    return null;
  end if;
  select count(*) into v_n from books b where b.tenant_id = new.tenant_id and b.type <> 'personal';
  if v_n > v_cap then     -- v_n includes the new row (AFTER)
    raise exception 'book_cap' using errcode = 'P0001',
      detail = 'the plan''s business books are all in use; the personal book is never counted (ADR 2026-09-05g §2)',
      hint = 'upgrade the plan for more books';
  end if;
  return null;
end $$;
create trigger books_book_cap after insert on books
  for each row execute function rf.book_cap();

-- ---------------------------------------------------------------- 8. RLS, policies, grants — each one justified
-- seat_grants is written by the SECURITY DEFINER triggers above and read by rf.take_seat, and by
-- nothing else. No role is granted anything on it, and RLS is on and FORCED with NO policy, so even
-- a future grant reads and writes zero rows until a policy is argued for. In particular rf_api
-- cannot learn another tenant's (or its own tenant's) rotation history, and nobody can delete a
-- grant to buy back rotation budget (append-only, CLAUDE.md rule 2's posture).
alter table seat_grants enable row level security;
alter table seat_grants force row level security;
revoke all on table seat_grants from rf_api, rf_maintenance;
do $$ declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on table public.seat_grants from %I', r);
    end if;
  end loop;
end $$;

-- Functions: nothing new is an rf_api power. rf.tenant_plan in particular is SECURITY DEFINER and
-- takes any tenant id, so granting it would be a cross-tenant plan oracle; the caps call it as the
-- definer. Trigger functions are never called directly. rf.device_cap is `create or replace` of
-- 0018's and keeps its grants.
revoke all on function rf.tenant_plan(uuid), rf.caps_apply(),
  rf.seat_holders(uuid, uuid, bytea), rf.take_seat(uuid, uuid, bytea, uuid),
  rf.invite_seat_cap(), rf.membership_seat_cap(), rf.book_cap() from public;
