-- ADR 2026-09-13d ruling 4 🔒 (RATIFIED 13 Sep 2026) — the ceremony session record: three opaque
-- values the server stores and forwards, and **computes nothing** with.
--
--   invitee's device            server (this table)              verifier's device
--   ----------------            -------------------              -----------------
--   draw r_S, c = H(FP‖uid‖r_S) ── INSERT commitment ─▶  (1)
--                                       (2)  ◀── r_V ──  draw r_V, only now, only holding c
--   reveal r_S ────────────────── (3) opening ─▶                 check c, then the 8 digits
--
-- Why this table is the security property (ADR 2026-09-13d §1, §5): the shipped 04 §6.1 code was
-- derived from a fingerprint the server holds and a nonce the server chose, so a substituting relay
-- pre-computed it in ~2·10⁴ BLAKE2b — a birthday search over two relayed nonces, under a second, and
-- the ghost key verified on the first attempt with `attemptsUsed == 0`. The commitment repairs that
-- only while **each value is fixed before the value it would be tuned against exists**. So the three
-- rules below are not hygiene; they are the whole fix, and they live in the DATABASE, because an
-- edge function is just another client from RLS's point of view (the 0006 precedent):
--
--   1. WHO — the subject's own certified device writes `commitment` and `opening`; only an already
--      verified, ACTIVE member of the tenant writes `verifier_random` (04 §6.4 *delegated*).
--   2. ONCE — every value is write-once. If the server could replace a commitment after seeing r_V,
--      or re-draw r_V after seeing the opening, it would be back to grinding. rf_api therefore holds
--      SELECT + INSERT and nothing else; the two later writes go through the SECURITY DEFINER
--      functions below, and the BEFORE UPDATE guard refuses a second write even to them.
--   3. ORDER — no r_V before a commitment (the commitment is NOT NULL at INSERT, so a session
--      cannot exist without one), no opening before r_V. Out-of-order writes are refused.
--   4. NO COMPUTATION — bytea in, bytea out. Nothing here hashes, derives, compares or validates a
--      code (04 §8.6: "if server code ever needs a content key, the design has been violated").
--   5. LIFETIME — 10 minutes from the commitment's **server** timestamp (04 §6.3, ADR ruling 3);
--      both timestamps are stamped here, never supplied by the caller. *Regenerate* INSERTs a fresh
--      session; nothing ever mutates an old one.
--
-- Delivery (ADR 2026-09-13d Open 2) is **short polling of the session row**, not Realtime — see the
-- note at the foot of this file.

-- ---------------------------------------------------------------- the record
create table ceremony_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id),

  -- (1) the shower: who is being verified, and the device that drew r_S and committed to it.
  subject_user uuid not null references users(id),
  subject_device uuid not null references devices(id),
  commitment bytea not null check (octet_length(commitment) = 32),   -- BLAKE2b-256, opaque here
  committed_at timestamptz not null default now(),                   -- stamped by the guard
  expires_at timestamptz not null default now() + interval '10 minutes',  -- = committed_at + 10 min

  -- (2) the verifier's contribution, drawn only once the commitment is in hand.
  verifier_user uuid null references users(id),
  verifier_device uuid null references devices(id),
  verifier_random bytea null check (verifier_random is null or octet_length(verifier_random) = 16),
  verifier_random_at timestamptz null,

  -- (3) the opening, revealed only once r_V has arrived.
  opening bytea null check (opening is null or octet_length(opening) = 16),
  opened_at timestamptz null,

  -- the three values arrive in order, so the timestamps do too; asserted as a constraint as well as
  -- in the guard, because a constraint survives a trigger someone disables.
  constraint ceremony_sessions_window
    check (expires_at = committed_at + interval '10 minutes'),
  constraint ceremony_sessions_rv_pairs
    check ((verifier_random is null) = (verifier_random_at is null)
           and (verifier_random is null) = (verifier_user is null)
           and (verifier_random is null) = (verifier_device is null)),
  constraint ceremony_sessions_open_pairs
    check ((opening is null) = (opened_at is null)),
  constraint ceremony_sessions_order
    check (opening is null or verifier_random is not null),
  constraint ceremony_sessions_clock
    check (verifier_random_at is null or verifier_random_at >= committed_at),
  constraint ceremony_sessions_clock2
    check (opened_at is null or opened_at >= verifier_random_at)
);
comment on table ceremony_sessions is
  'ADR 2026-09-13d ruling 4: commitment(32B) / verifier_random(16B) / opening(16B) + server '
  'timestamps. Opaque bytes relayed between two devices. The server computes nothing with them.';

-- The subject polls for r_V; the verifier polls for the opening. One live session per subject is
-- the normal case, so this index is the whole read path.
create index ceremony_sessions_subject_idx
  on ceremony_sessions (tenant_id, subject_user, committed_at desc);
create index ceremony_sessions_live_idx on ceremony_sessions (expires_at);

-- ---------------------------------------------------------------- the guard (rules 1–3, 5)
-- A session is a member of this tenant's ceremony, so the subject must already be *in* the tenant:
-- joined_pending_verification (the member ceremony of 06 §7) or active (guardian activation,
-- trustee handover, device linking — 04 §6's other three uses of the same component).
-- ⚠️ SPEC: ADR 2026-09-13d speaks only of the member ceremony; 04 §6 says "one component, four
-- uses", and guardian setup is mutual between two ACTIVE members, so refusing an active subject
-- would break a ceremony 04 §6 mandates. Narrower than "any user", wider than "invitees only".
create or replace function rf.ceremony_subject_ok(p_tenant uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships m
                 where m.tenant_id = p_tenant and m.user_id = p_user
                   and m.status in ('joined_pending_verification', 'active'))
$$;

create or replace function rf.ceremony_session_guard() returns trigger
language plpgsql as $$
declare n int;
begin
  if TG_OP = 'INSERT' then
    -- rule 5: the lifetime runs from the SERVER's clock, not from anything a caller sends. A relay
    -- that could backdate committed_at could keep a session alive past its ten minutes.
    new.committed_at := now();
    new.expires_at   := new.committed_at + interval '10 minutes';

    -- rule 3: a session is born with its commitment and NOTHING else. r_V cannot precede it because
    -- there is no row to carry r_V until the commitment exists.
    if new.verifier_random is not null or new.verifier_random_at is not null
       or new.verifier_user is not null or new.verifier_device is not null then
      raise exception 'ceremony_order' using errcode = '23514',
        detail = 'r_V is drawn only once the commitment is in the verifier''s hands (ADR 2026-09-13d ruling 1)';
    end if;
    if new.opening is not null or new.opened_at is not null then
      raise exception 'ceremony_order' using errcode = '23514',
        detail = 'the opening is revealed only after r_V arrives (ADR 2026-09-13d ruling 1)';
    end if;

    if not rf.ceremony_subject_ok(new.tenant_id, new.subject_user) then
      raise exception 'subject_not_in_tenant' using errcode = '42501',
        detail = 'a ceremony verifies a member of this tenant (06 §7)';
    end if;

    -- A relay can force *Regenerate* (04 §6.4 residual: it may withhold r_V), and each regeneration
    -- buys it one blind guess in 10⁸. Human patience bounds that; so does this. Rate limits are the
    -- server's one legitimate power (ADR 2026-09-05b §7) and this is the only one on this table.
    select count(*) into n from ceremony_sessions s
     where s.tenant_id = new.tenant_id and s.subject_user = new.subject_user
       and s.expires_at > now();
    if n >= 10 then
      raise exception 'ceremony_flood' using errcode = '53400',
        detail = 'too many live ceremony sessions for this subject; let one expire (ADR 2026-09-05b §7)';
    end if;
    return new;
  end if;

  if TG_OP = 'DELETE' then
    -- retention only, and only well after the session is dead (03 §6). rf_api holds no DELETE grant
    -- at all; this bounds even rf_maintenance.
    if old.expires_at > now() - interval '1 day' then
      raise exception 'append_only' using errcode = '23514',
        detail = 'a ceremony session is deleted only by retention, a day after it expired (03 §6)';
    end if;
    return old;
  end if;

  -- rule 2: write-once, field by field. The identity of the session and the commitment it is
  -- built on are frozen from the moment it exists.
  if old.id is distinct from new.id
     or old.tenant_id is distinct from new.tenant_id
     or old.subject_user is distinct from new.subject_user
     or old.subject_device is distinct from new.subject_device
     or old.commitment is distinct from new.commitment
     or old.committed_at is distinct from new.committed_at
     or old.expires_at is distinct from new.expires_at then
    raise exception 'ceremony_immutable' using errcode = '23514',
      detail = 'the commitment and its session are fixed when written; *Regenerate* opens a fresh session, it never rewrites one (ADR 2026-09-13d ruling 4)';
  end if;
  -- nothing may be un-written back to null and re-drawn: that is the grind by another name
  if (old.verifier_random is not null and new.verifier_random is null)
     or (old.opening is not null and new.opening is null) then
    raise exception 'ceremony_immutable' using errcode = '23514',
      detail = 'a written value is never withdrawn (ADR 2026-09-13d ruling 4)';
  end if;
  if old.verifier_random is not null and (
       new.verifier_random is distinct from old.verifier_random
       or new.verifier_random_at is distinct from old.verifier_random_at
       or new.verifier_user is distinct from old.verifier_user
       or new.verifier_device is distinct from old.verifier_device) then
    raise exception 'ceremony_immutable' using errcode = '23514',
      detail = 'r_V is written once; re-drawing it after the opening is exactly the grind the commitment exists to stop (ADR 2026-09-13d ruling 4)';
  end if;
  if old.opening is not null and (
       new.opening is distinct from old.opening
       or new.opened_at is distinct from old.opened_at) then
    raise exception 'ceremony_immutable' using errcode = '23514',
      detail = 'the opening is written once (ADR 2026-09-13d ruling 2: one session, one opening)';
  end if;
  -- rule 3 again, on the update path: an opening with no r_V in the row is out of order.
  if new.opening is not null and new.verifier_random is null then
    raise exception 'ceremony_order' using errcode = '23514',
      detail = 'the opening follows r_V (ADR 2026-09-13d ruling 1)';
  end if;
  return new;
end $$;

create trigger ceremony_sessions_guard
  before insert or update or delete on ceremony_sessions
  for each row execute function rf.ceremony_session_guard();

-- ---------------------------------------------------------------- (2) the verifier's contribution
-- Only an already-verified, ACTIVE member of the session's tenant, on a certified device, and never
-- the subject themself. Returns the server timestamp so the caller can see its own write landed.
--
-- A caller who is not an active member of this tenant gets `unknown_session`, the same refusal as a
-- session id that does not exist: another tenant learns nothing about which ceremonies are running
-- (the accept_invite precedent in 0006).
create or replace function rf.ceremony_contribute(p_session uuid, p_random bytea)
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare s ceremony_sessions%rowtype; t timestamptz;
begin
  if p_random is null or octet_length(p_random) <> 16 then
    raise exception 'ceremony_shape' using errcode = '23514',
      detail = 'r_V is 128 bits (ADR 2026-09-13d ruling 1)';
  end if;
  select * into s from ceremony_sessions where id = p_session for update;
  if s.id is null or not rf.active_in_tenant(s.tenant_id) then
    raise exception 'unknown_session' using errcode = '42501',
      detail = 'only an active, certified member of the tenant draws r_V (04 §6.4 delegated)';
  end if;
  if s.subject_user = rf.user_id() then
    raise exception 'self_verification' using errcode = '42501',
      detail = 'the verifier is never the subject (04 §6)';
  end if;
  if s.expires_at <= now() then
    raise exception 'ceremony_expired' using errcode = '23514',
      detail = 'a session lives ten minutes from the commitment (04 §6.3)';
  end if;
  if s.verifier_random is not null then
    raise exception 'ceremony_spent' using errcode = '23514',
      detail = 'r_V is drawn once per session; *Regenerate* opens a fresh one (ADR 2026-09-13d ruling 2)';
  end if;
  t := now();
  update ceremony_sessions
     set verifier_random = p_random, verifier_random_at = t,
         verifier_user = rf.user_id(), verifier_device = rf.device_id()
   where id = p_session;
  return t;
end $$;

-- ---------------------------------------------------------------- (3) the opening
-- The device that committed, and only it, and only after r_V. One opening per session: a second
-- response under the same r_S is what would let a relay search r_V″ against a second code.
create or replace function rf.ceremony_open(p_session uuid, p_opening bytea)
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare s ceremony_sessions%rowtype; t timestamptz;
begin
  if p_opening is null or octet_length(p_opening) <> 16 then
    raise exception 'ceremony_shape' using errcode = '23514',
      detail = 'r_S is 128 bits (ADR 2026-09-13d ruling 1)';
  end if;
  select * into s from ceremony_sessions where id = p_session for update;
  if s.id is null or s.subject_user is distinct from rf.user_id()
     or s.subject_device is distinct from rf.device_id() or not rf.is_certified() then
    raise exception 'unknown_session' using errcode = '42501',
      detail = 'the device that committed is the only device that opens (ADR 2026-09-13d ruling 4)';
  end if;
  if s.verifier_random is null then
    raise exception 'ceremony_order' using errcode = '23514',
      detail = 'the opening follows r_V (ADR 2026-09-13d ruling 1)';
  end if;
  if s.expires_at <= now() then
    raise exception 'ceremony_expired' using errcode = '23514',
      detail = 'a session lives ten minutes from the commitment (04 §6.3)';
  end if;
  if s.opening is not null then
    raise exception 'ceremony_spent' using errcode = '23514',
      detail = 'one session, one opening (ADR 2026-09-13d ruling 2)';
  end if;
  t := now();
  update ceremony_sessions set opening = p_opening, opened_at = t where id = p_session;
  return t;
end $$;

-- ---------------------------------------------------------------- retention sweep (maintenance)
create or replace function rf.sweep_ceremony_sessions() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from ceremony_sessions where expires_at <= now() - interval '1 day';
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------- RLS, policies, grants
-- 0005's "every table" loop ran before this table existed, so switch it on by name.
alter table ceremony_sessions enable row level security;
alter table ceremony_sessions force row level security;

-- rf_api: SELECT + INSERT and nothing else. There is no UPDATE policy and no DELETE policy on this
-- table for rf_api at all — the same shape as `envelopes` (03 §2.3, CLAUDE.md rule 2). The two later
-- writes reach the row only through the two SECURITY DEFINER functions above, which is what makes
-- "write-once" a property of the database rather than a habit of the edge function.
grant select, insert on ceremony_sessions to rf_api;
grant select, delete on ceremony_sessions to rf_maintenance;

create policy ceremony_sessions_select on ceremony_sessions for select to rf_api
  using (rf.is_certified()
         and (subject_user = rf.user_id() or rf.active_in_tenant(tenant_id)));
create policy ceremony_sessions_insert on ceremony_sessions for insert to rf_api
  with check (rf.is_certified()
              and subject_user = rf.user_id()
              and subject_device = rf.device_id()
              and rf.ceremony_subject_ok(tenant_id, rf.user_id()));
create policy ceremony_sessions_maintenance_select on ceremony_sessions for select to rf_maintenance
  using (true);
create policy ceremony_sessions_maintenance_delete on ceremony_sessions for delete to rf_maintenance
  using (true);

-- 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before these existed.
revoke all on function rf.ceremony_session_guard(), rf.ceremony_subject_ok(uuid, uuid),
  rf.ceremony_contribute(uuid, bytea), rf.ceremony_open(uuid, bytea),
  rf.sweep_ceremony_sessions() from public;
-- ceremony_subject_ok is read by the INSERT policy and by the guard, both evaluated AS rf_api, so
-- it needs the grant; the guard itself does not (Postgres checks no EXECUTE when firing a trigger).
grant execute on function rf.ceremony_contribute(uuid, bytea), rf.ceremony_open(uuid, bytea),
  rf.ceremony_subject_ok(uuid, uuid) to rf_api;
grant execute on function rf.sweep_ceremony_sessions() to rf_maintenance;
revoke execute on function rf.sweep_ceremony_sessions() from rf_api;

-- ---------------------------------------------------------------- delivery (ADR 2026-09-13d Open 2)
-- Chosen: **short polling of the session row**, ~1 s while a ceremony screen is open, through
-- sync-meta's `/ceremony` route. Not Supabase Realtime, for three reasons:
--   * Realtime authorises from the platform's `authenticated` role and its own JWT. Ours is not
--     platform auth (06 §4) and 0005 deliberately revokes every table privilege from `anon`,
--     `authenticated` and `service_role`; wiring Realtime would mean handing those roles grants back
--     and re-deriving `request.user_id` / `request.device_id` in a second authorisation path. Two
--     authorisation paths over the table that carries the trust root is exactly the wrong trade.
--   * The exchange is two round-trips inside a ten-minute window at human pace. A 1 s poll costs
--     ~20 requests per ceremony, a handful per member per lifetime.
--   * Polling adds no transport to audit and keeps the server content-blind (04 §8.6). Realtime can
--     be added later behind the same policies without changing this table.
