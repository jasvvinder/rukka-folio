-- M11 · the WRITE side of the guardian recovery ladder — 04 §7.3 🔒 (Setup + Recovery steps 1–7),
-- 06 §5, 03 §2.2/§2.5, ADR 2026-09-05d §1 (24 h wait + one-tap Cancel) and §2, ADR 2026-09-06 §2,
-- ADR 2026-09-13c §1/§3, ADR 2026-09-16 (one device, one id).
-- ⟦tests: E-06-43, E-06-44, E-06-45, E-06-46, E-06-47, E-06-48, E-06-49, E-06-50, E-06-51,
--         E-06-52, E-06-53, E-06-54, E-06-55, E-06-56⟧
--
-- 0002 declared the tables and 0005 gave rf_api SELECT + INSERT on them; sync-meta already RETURNS
-- guardian-set history and the wrapped keys addressed to the caller. Nothing could ever be written.
-- This migration is the write side, and it is built on one decision:
--
-- ============================================================================================
-- THE DECISION 🔒 — approvals are COUNTED FROM APPEND-ONLY ROWS, never accumulated in a column.
-- ============================================================================================
-- `recovery_requests.approvals` is an `int` with no UPDATE grant for rf_api (0005), and CLAUDE.md
-- rule 2 reads append-only. Two shapes were available: hand rf_api (or a SECURITY DEFINER function)
-- the power to bump that counter, or make every guardian decision its OWN row and derive the count.
-- The second is taken, for three reasons that are properties, not preferences:
--
--   1. A counter is a lossy projection of the thing that matters. `2 of 3 approved` has to name
--      *which* two — the requester's screen shows it (ADR 2026-09-06 § Consequences), a cancel
--      "notifies the guardians who approved" (ADR 2026-09-05d §1), and a denial has to be
--      distinguishable from silence (04 §7.3 step 7: three denials close the attempt). A counter
--      cannot answer any of those; the rows answer all three.
--   2. An UPDATE grant on `recovery_requests` is an UPDATE grant on `state` as well. The whole of
--      ADR 2026-09-05d §1 is that the server, not the client, decides when a request may complete;
--      a row that can be re-written is a row whose `waiting_24h` can be re-written (E-06-56).
--   3. Every decision is therefore idempotent and replay-proof by the primary key
--      `(request_id, guardian_user_id)` rather than by a read-modify-write nobody can audit.
--
-- So: `recovery_requests.approvals` stays 0 for ever (it is vestigial — see the comment on the
-- column), `recovery_requests.state` records only the LADDER the request opened on, and the state a
-- client acts on is DERIVED by `rf.recovery_progress` from the rows. NO table in this file grants
-- UPDATE or DELETE to rf_api, and no SECURITY DEFINER function here performs an UPDATE.
--
-- The two SECURITY DEFINER functions below (`rf.recovery_decide`, `rf.recovery_progress`) exist for
-- reasons that are not "write a column the policies refuse":
--   * `rf.recovery_decide` INSERTS two rows atomically — the re-sealed share and the decision that
--     points at it — and binds them to the request's candidate key. A guardian addresses a
--     `wrapped_keys` row to ANOTHER user (the subject), which no `wrapped_keys` INSERT policy allows
--     and which should not become a general power; making it the only path keeps it special.
--   * `rf.recovery_progress` reads across three tables and derives a state. It is definer so that
--     the derivation is one expression in one place — the client never assembles the state itself.
--
-- ============================================================================================
-- What the server does NOT do (04 §8.6: the server's crypto surface is minimal by design)
-- ============================================================================================
-- It does not split, re-seal, open, hash or compare a share. Shares arrive sealed and leave sealed;
-- `blob` is bytea in and bytea out. It does not hold or derive the UMK. It does not decide who a
-- guardian is — the subject's own certified device publishes the set (04 §7.3 *Setup*). Grep this
-- file for a crypto call and you will not find one. What it DOES do is exactly ADR 2026-09-05b §7's
-- list of legitimate server powers: it enforces structure (n, k, one decision per guardian), it
-- enforces timers (72 h, 24 h), and it refuses with a NAMED reason, never a silent drop.

-- ---------------------------------------------------------------- 04 §7.3 Setup: the guardian set
-- 0002 keeps every `share_set_version` (ADR 2026-09-06 §3: a revocation record is counted against
-- the set *at the version it names*), so a re-split is an INSERT of the next version and never a
-- rewrite of the last. `superseded_at` therefore cannot be maintained without an UPDATE grant, and
-- is not: the CURRENT set is the highest version, derived.
create or replace function rf.current_guardian_set(p_subject uuid)
returns table (share_set_version int, k int, n int)
language sql stable security definer set search_path = public as $$
  select g.share_set_version, g.k, g.n from guardian_sets g
  where g.subject_user_id = p_subject and g.superseded_at is null
  order by g.share_set_version desc limit 1
$$;

comment on column guardian_sets.superseded_at is
  'Vestigial: rf_api holds no UPDATE grant and a re-split is a new version, so this is never set by '
  'the API. The current set is the highest share_set_version — rf.current_guardian_set (0010).';

-- n = 2..5 and k = ceil((n+1)/2) — 04 §7.3 🔒. The version is strictly the next one, so a client
-- cannot shadow a live set by inserting a LOWER version after the fact.
--
-- ⚠️ SPEC: 04 §7.3 reads "allowed n=2..5 with k=⌈(n+1)/2⌉" (the formula as the rule) while
-- ADR 2026-09-06 §2's heading reads "n ∈ 2..5 with k = ⌈(n+1)/2⌉ **by default**" (the formula as a
-- default, with k carried in the share wire form). 04 owns recovery, and its line is 🔒 and
-- unqualified, so the conservative reading is taken here: the formula is ENFORCED. If the owner
-- rules that k is the client's to choose, this one CHECK relaxes and nothing else in the file moves.
create or replace function rf.guardian_set_guard() returns trigger
language plpgsql as $$
declare hi int;
begin
  if TG_OP <> 'INSERT' then
    raise exception 'append_only' using errcode = '23514',
      detail = 'a guardian set is never rewritten; a change is the next share_set_version (ADR 2026-09-06 §3)';
  end if;
  if new.n < 2 or new.n > 5 then
    raise exception 'guardian_set_size' using errcode = '23514',
      detail = 'a guardian set is 2 to 5 guardians (04 §7.3)';
  end if;
  if new.k <> ((new.n + 1) / 2) + ((new.n + 1) % 2) then
    raise exception 'guardian_quorum' using errcode = '23514',
      detail = 'k = ceil((n+1)/2) — 2-of-2, 2-of-3, 3-of-4, 3-of-5 (04 §7.3)';
  end if;
  select coalesce(max(g.share_set_version), 0) into hi
    from guardian_sets g where g.subject_user_id = new.subject_user_id;
  if new.share_set_version <> hi + 1 then
    raise exception 'share_set_version_out_of_order' using errcode = '23514',
      detail = 'a re-split publishes the NEXT version; an older version can never be added behind a live one (ADR 2026-09-06 §3)';
  end if;
  new.created_at := now();
  return new;
end $$;
create trigger guardian_sets_guard before insert or update or delete on guardian_sets
  for each row execute function rf.guardian_set_guard();

-- Exactly n members, each a different person, never the subject themself.
create or replace function rf.guardian_set_member_guard() returns trigger
language plpgsql as $$
declare g guardian_sets%rowtype; c int;
begin
  if TG_OP <> 'INSERT' then
    raise exception 'append_only' using errcode = '23514',
      detail = 'a guardian set member is never rewritten (ADR 2026-09-06 §3)';
  end if;
  if new.guardian_user_id = new.subject_user_id then
    raise exception 'guardian_is_subject' using errcode = '23514',
      detail = 'a guardian is somebody else (04 §7.3)';
  end if;
  select * into g from guardian_sets s
    where s.subject_user_id = new.subject_user_id and s.share_set_version = new.share_set_version;
  select count(*) into c from guardian_set_members m
    where m.subject_user_id = new.subject_user_id and m.share_set_version = new.share_set_version;
  if c >= g.n then
    raise exception 'guardian_set_full' using errcode = '23514',
      detail = 'the set already holds n guardians (04 §7.3)';
  end if;
  return new;
end $$;
create trigger guardian_set_members_guard before insert or update or delete on guardian_set_members
  for each row execute function rf.guardian_set_member_guard();

-- ---------------------------------------------------------------- 04 §7.3 step 1: the request
-- The recovering device is UNCERTIFIED by construction — it is the fresh phone of 06 §5 "New phone,
-- no old device", holding nothing but its own keys, and ADR 2026-09-05d §2 names "its own
-- `recovery_requests`" among the four things such a device may see. 0005's INSERT policy is
-- therefore the ONE policy in the schema that does not require `rf.is_certified()`, and that is
-- deliberate. What bounds it instead: the row must name the caller's own user AND the caller's own
-- device (the policy), the device must be a live device of that user, and the state is the
-- server's (this guard).
--
-- ⚠️ SPEC: the M11 lane brief asks for a hostile test proving "an uncertified device cannot open a
-- request". Taken literally that forbids the flagship flow — 04 §7.3 step 1 and ADR 2026-09-05d §2
-- both have an uncertified device opening its own request. The conservative reading is taken: an
-- uncertified device may open a request for ITSELF and for nothing else; it may not name another
-- user, another device, or reach any other row. E-06-53 asserts that reading. Owner to settle.
alter table recovery_requests
  add column candidate_pub_x bytea,                    -- 04 §7.3 step 1: the *candidate* X25519 pair
  add column share_set_version int;                    -- the set this attempt runs against, pinned at open

alter table recovery_requests
  add constraint recovery_requests_candidate_pub
    check (candidate_pub_x is null or octet_length(candidate_pub_x) = 32);

comment on column recovery_requests.candidate_pub_x is
  'The candidate X25519 public key of 04 §7.3 step 1 — what each guardian re-seals its share to, and '
  'what the guardian''s device compares against the scanned DeviceQrPayload (ADR 2026-09-13c §3). '
  'Opaque to the server: it is stored, relayed and compared byte-for-byte, never used in a computation.';
comment on column recovery_requests.share_set_version is
  'Pinned from rf.current_guardian_set at open, so a re-split mid-attempt cannot move the quorum '
  '(the same rule ADR 2026-09-06 §3 gives k-of-n revocation).';
comment on column recovery_requests.approvals is
  'VESTIGIAL — always 0. rf_api holds no UPDATE grant and 0010 adds none: the count is derived from '
  'the append-only recovery_approvals rows by rf.recovery_progress (CLAUDE.md rule 2).';
comment on column recovery_requests.state is
  'The LADDER this request opened on, written once by rf.recovery_request_guard and never again: '
  '''waiting_24h'' when the user still had an active certified device, ''pending'' when none existed '
  '(ADR 2026-09-05d §1). The state a client acts on is rf.recovery_progress''s derived value.';

-- A BEFORE trigger runs as the CALLING role, so every lookup it makes is subject to that caller's
-- RLS — and the caller here is an uncertified device that can see almost nothing (ADR 2026-09-05d
-- §2). These three helpers are therefore SECURITY DEFINER: the guard must be able to check facts the
-- requester is not allowed to read. Each returns a boolean or a count and never a row, so nothing
-- leaks through them beyond the yes/no the refusal already states.
create or replace function rf.guardian_set_ready(p_subject uuid, p_version int) returns boolean
language sql stable security definer set search_path = public as $$
  select (select count(*) from guardian_set_members m
          where m.subject_user_id = p_subject and m.share_set_version = p_version)
       = (select g.n from guardian_sets g
          where g.subject_user_id = p_subject and g.share_set_version = p_version)
$$;

create or replace function rf.device_live_for(p_device uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from devices d where d.id = p_device and d.user_id = p_user
                   and d.status <> 'revoked' and d.revoked_at is null)
$$;

-- ADR 2026-09-05d §1 🔒 — "any active device exists" is exactly this question, and it is the only
-- input to the 24 h decision. `certified` is the status the server itself sets after verifying the
-- device certificate (ADR 2026-09-05d §2), so a registered-but-uncertified phone does not count:
-- it could not read the alarm or press Cancel.
create or replace function rf.has_other_active_device(p_user uuid, p_except uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from devices d where d.user_id = p_user and d.id is distinct from p_except
                   and d.status = 'certified' and d.revoked_at is null)
$$;

create or replace function rf.live_recovery_count(p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from recovery_requests r where r.user_id = p_user and r.expires_at > now()
$$;

create or replace function rf.recovery_request_guard() returns trigger
language plpgsql as $$
declare v_ver int; v_n int; n_live int;
begin
  if TG_OP = 'UPDATE' then
    raise exception 'append_only' using errcode = '23514',
      detail = 'a recovery request is never rewritten; approvals, cancellation and completion are their own rows (CLAUDE.md rule 2)';
  end if;
  if TG_OP = 'DELETE' then
    if old.expires_at > now() - interval '30 days' then
      raise exception 'append_only' using errcode = '23514',
        detail = 'a recovery request is deleted only by retention, well after it closed (03 §6)';
    end if;
    return old;
  end if;

  if new.candidate_pub_x is null or octet_length(new.candidate_pub_x) <> 32 then
    raise exception 'recovery_shape' using errcode = '23514',
      detail = 'the candidate X25519 public key is 32 bytes (04 §7.3 step 1)';
  end if;
  -- The candidate device is the caller's own live device. 0005's policy already pins it to
  -- rf.device_id(); this refuses a revoked row and a device belonging to somebody else.
  if not rf.device_live_for(new.candidate_device, new.user_id) then
    raise exception 'unknown_candidate_device' using errcode = '42501',
      detail = 'the candidate device is a live device of the recovering user (ADR 2026-09-16 §1)';
  end if;

  select c.share_set_version, c.n into v_ver, v_n from rf.current_guardian_set(new.user_id) c;
  if v_ver is null then
    raise exception 'no_guardian_set' using errcode = '42501',
      detail = 'rung 2 needs guardians; without a set the ladder falls through to the paper sheet (04 §7.4)';
  end if;
  if not rf.guardian_set_ready(new.user_id, v_ver) then
    raise exception 'guardian_set_incomplete' using errcode = '42501',
      detail = 'the published set holds fewer than n guardians; re-publish it (04 §7.3 Setup)';
  end if;
  new.share_set_version := v_ver;

  -- ADR 2026-09-05d §1 🔒 — THE WAIT IS THE SERVER'S TO SET, NOT THE CLIENT'S. Completion is
  -- immediate only when the user has no active certified device; if any exists the attempt lands in
  -- waiting_24h and every existing device alarms with a one-tap Cancel. Whatever `state` the client
  -- sent is overwritten here, which is why "ask for 'approved'" is not an attack (E-06-56).
  new.state := case when rf.has_other_active_device(new.user_id, new.candidate_device)
    then 'waiting_24h' else 'pending' end;
  new.approvals := 0;                                   -- vestigial; the rows carry the count
  new.created_at := now();
  new.expires_at := new.created_at + interval '72 hours';  -- 04 §7.3 step 7

  -- ADR 2026-09-05b §7: rate limits are the server's legitimate power. A hostile relative with the
  -- phone cannot paper every guardian's screen with asks.
  n_live := rf.live_recovery_count(new.user_id);
  if n_live >= 5 then
    raise exception 'recovery_flood' using errcode = '53400',
      detail = 'too many live recovery attempts for this user; let one close (ADR 2026-09-05b §7)';
  end if;
  return new;
end $$;
create trigger recovery_requests_guard before insert or update or delete on recovery_requests
  for each row execute function rf.recovery_request_guard();

create index recovery_requests_open_idx on recovery_requests (user_id, share_set_version, expires_at);

-- ---------------------------------------------------------------- 04 §7.3 step 3: the decision
-- One row per guardian per attempt, written once. `wrapped_key_id` points at the `recovery_blob`
-- the guardian re-sealed TO THE CANDIDATE KEY; `sealed_to_pub_x` is the key the guardian says it
-- sealed to, and the guard refuses it unless it is byte-identical to the request's. That is what
-- makes "a share sealed to one candidate key cannot be replayed into another request" a property of
-- the database rather than of the client (E-06-54): the unique on `wrapped_key_id` stops the same
-- sealed row backing a second attempt, and the key comparison stops a blob sealed for attempt A
-- being declared as an approval of attempt B.
create table recovery_approvals (
  request_id uuid not null references recovery_requests(id),
  guardian_user_id uuid not null references users(id),
  guardian_device uuid not null references devices(id),
  share_set_version int not null,
  decision text not null check (decision in ('approved', 'denied')),
  wrapped_key_id uuid null references wrapped_keys(id),
  sealed_to_pub_x bytea null check (sealed_to_pub_x is null or octet_length(sealed_to_pub_x) = 32),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (request_id, guardian_user_id),
  constraint recovery_approvals_share
    check ((decision = 'approved') = (wrapped_key_id is not null)),
  constraint recovery_approvals_sealed
    check ((decision = 'approved') = (sealed_to_pub_x is not null)),
  constraint recovery_approvals_one_use unique (wrapped_key_id)
);
create index recovery_approvals_guardian_idx on recovery_approvals (guardian_user_id, created_at);
comment on table recovery_approvals is
  '04 §7.3 step 3/step 7 — one guardian decision per attempt, append-only. The k-of-n count and the '
  'three-denial close are derived from these rows (0010: no approvals counter is ever written).';

-- ADR 2026-09-05d §1 — the one-tap Cancel. First cancel wins (primary key on request_id); a second
-- is the same outcome, so the route reports it as already cancelled rather than as a failure.
create table recovery_cancellations (
  request_id uuid primary key references recovery_requests(id),
  cancelled_by_user uuid not null references users(id),
  cancelled_by_device uuid not null references devices(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table recovery_cancellations is
  'ADR 2026-09-05d §1 — a cancel closes the attempt and is a ROW, never an UPDATE of the request.';

create or replace function rf.recovery_append_only_guard() returns trigger
language plpgsql as $$
begin
  if TG_OP = 'INSERT' then
    new.created_at := now();
    new.updated_at := new.created_at;
    return new;
  end if;
  raise exception 'append_only' using errcode = '23514',
    detail = 'a guardian decision and a cancellation are facts; they are never rewritten (CLAUDE.md rule 2)';
end $$;
create trigger recovery_approvals_guard before insert or update or delete on recovery_approvals
  for each row execute function rf.recovery_append_only_guard();
create trigger recovery_cancellations_guard before insert or update or delete on recovery_cancellations
  for each row execute function rf.recovery_append_only_guard();

-- ---------------------------------------------------------------- the derived state
-- Everything a client may act on, in one expression, in the database. No counter is read; the rows
-- ARE the count.
--
-- ⚠️ SPEC: 04 §7.3 step 7 closes an attempt at "3 denials or 72 h", and step 6 makes steps 4–6 wait
-- 24 h. Those collide when the k-th approval lands near hour 72. The reading taken — the
-- conservative one for the legitimate user, and no weaker for an attacker, because the 24 h alarm
-- window is untouched either way — is that the 72 h bound is the window guardians have to RESPOND:
-- once k approvals exist the attempt is no longer waiting on guardians, and the 24 h wait runs to
-- its end. An attempt with fewer than k approvals at 72 h is closed. The wait itself is measured
-- from the k-th approval (04 §7.3 step 6: "steps 4–6 wait 24 h"), which is never earlier than the
-- open, so it satisfies ADR 2026-09-05d §1's "completion is delayed 24 h" as well.
--
-- ⚠️ SPEC: 03 §2.2's `state` enum has no 'denied'. Three denials therefore surface as 'expired' —
-- the attempt is closed either way and the rows say which it was. Adding a state is a 03 §2.2 🔒
-- change, so it is reported, not made.
-- The derivation itself, with NO authorisation check: it is the single expression the whole slice
-- reads the state through, including `rf.recovery_decide`, which is called by a GUARDIAN and would
-- see nothing through the caller-scoped view below. Not granted to rf_api.
create or replace function rf.recovery_derive(p_request uuid)
returns table (request_id uuid, user_id uuid, candidate_device uuid, share_set_version int,
               k int, n int, approvals int, denials int, opened_state text, state text,
               kth_approval_at timestamptz, wait_until timestamptz,
               expires_at timestamptz, cancelled_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare r recovery_requests%rowtype; g record; c timestamptz; a int; d int;
        kth timestamptz; wait timestamptz; st text;
begin
  select * into r from recovery_requests q where q.id = p_request;
  if not found then return; end if;
  select s.k, s.n into g from guardian_sets s
    where s.subject_user_id = r.user_id and s.share_set_version = r.share_set_version;
  select count(*) filter (where x.decision = 'approved'),
         count(*) filter (where x.decision = 'denied')
    into a, d from recovery_approvals x where x.request_id = p_request;
  select x.created_at into kth from recovery_approvals x
    where x.request_id = p_request and x.decision = 'approved'
    order by x.created_at offset greatest(g.k - 1, 0) limit 1;
  select x.created_at into c from recovery_cancellations x where x.request_id = p_request;

  if r.state = 'waiting_24h' and kth is not null then
    wait := kth + interval '24 hours';
  end if;

  if c is not null then st := 'cancelled';
  elsif d >= 3 then st := 'expired';                    -- 04 §7.3 step 7 (see the ⚠️ SPEC above)
  elsif a >= g.k then
    st := case when wait is null or now() >= wait then 'approved' else 'waiting_24h' end;
  elsif now() >= r.expires_at then st := 'expired';     -- 72 h with fewer than k approvals
  else st := r.state;
  end if;

  return query select r.id, r.user_id, r.candidate_device, r.share_set_version, g.k, g.n,
                      a, d, r.state, st, kth, wait, r.expires_at, c;
end $$;

-- The caller-scoped read. ADR 2026-09-05d §2 — the requester (certified) or the candidate device
-- (uncertified, its own request) and nobody else; a guardian reads the ASK, not the tally.
create or replace function rf.recovery_progress(p_request uuid)
returns table (request_id uuid, user_id uuid, candidate_device uuid, share_set_version int,
               k int, n int, approvals int, denials int, opened_state text, state text,
               kth_approval_at timestamptz, wait_until timestamptz,
               expires_at timestamptz, cancelled_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare r recovery_requests%rowtype;
begin
  select * into r from recovery_requests q where q.id = p_request;
  if not found then return; end if;
  if not coalesce(r.candidate_device = rf.device_id(), false)
     and not (rf.is_certified() and coalesce(r.user_id = rf.user_id(), false)) then
    return;
  end if;
  return query select * from rf.recovery_derive(p_request);
end $$;

-- ---------------------------------------------------------------- 04 §7.3 step 3/7: approve, deny
-- SECURITY DEFINER because a guardian addresses a `wrapped_keys` row to ANOTHER user — the subject —
-- which no INSERT policy grants and which must not become a general power. It performs two INSERTs
-- and NO update. Everything it refuses, it refuses by name (05c: never a silent drop), and an
-- unknown request and a caller who is not a guardian of it refuse IDENTICALLY (`unknown_request`),
-- so the route is not an oracle for whose recovery is in flight.
create or replace function rf.recovery_decide(p_request uuid, p_decision text,
                                              p_blob bytea, p_sealed_to bytea)
returns uuid
language plpgsql security definer set search_path = public as $$
declare r recovery_requests%rowtype; p record; wk uuid;
begin
  if p_decision not in ('approved', 'denied') then
    raise exception 'recovery_shape' using errcode = '23514',
      detail = 'a guardian approves or denies (04 §7.3 steps 3 and 7)';
  end if;
  select * into r from recovery_requests q where q.id = p_request;
  if not found or not rf.is_certified()
     or not exists (select 1 from guardian_set_members m
                    where m.subject_user_id = r.user_id
                      and m.share_set_version = r.share_set_version
                      and m.guardian_user_id = rf.user_id()) then
    raise exception 'unknown_request' using errcode = '42501',
      detail = 'only a certified device of a guardian of this attempt''s share set decides it (04 §7.3)';
  end if;
  -- The state is read through the derivation, so a cancelled, expired or already-closed attempt
  -- cannot collect one more share.
  select * into p from rf.recovery_derive(p_request);
  if p.state is null or p.state not in ('pending', 'waiting_24h') then
    raise exception 'recovery_closed' using errcode = '23514',
      detail = 'this attempt is ' || coalesce(p.state, 'unknown') || ' (04 §7.3 step 7; ADR 2026-09-05d §1)';
  end if;

  if p_decision = 'denied' then
    insert into recovery_approvals (request_id, guardian_user_id, guardian_device,
                                    share_set_version, decision)
    values (p_request, rf.user_id(), rf.device_id(), r.share_set_version, 'denied');
    return null;
  end if;

  -- ADR 2026-09-13c §3 🔒 — the re-seal goes to the candidate key of THIS request, and the guardian
  -- says which key that was. The server compares 32 bytes it never interprets; it does not and
  -- cannot check the sealing itself (04 §8.6), which is why the guardian's device scans the
  -- candidate's DeviceQrPayload first. What this comparison buys is the REPLAY bound: a share
  -- declared for one candidate key can never be filed against a request carrying another.
  if p_sealed_to is null or octet_length(p_sealed_to) <> 32 then
    raise exception 'recovery_shape' using errcode = '23514',
      detail = 'the candidate X25519 public key the share was sealed to is 32 bytes (04 §7.3 step 3)';
  end if;
  if p_sealed_to is distinct from r.candidate_pub_x then
    raise exception 'candidate_key_mismatch' using errcode = '23514',
      detail = 'this share was sealed to a different candidate key; it belongs to another attempt (ADR 2026-09-13c §3)';
  end if;
  if p_blob is null or octet_length(p_blob) = 0 or octet_length(p_blob) > 4096 then
    raise exception 'recovery_shape' using errcode = '23514',
      detail = 'the re-sealed share is 1..4096 opaque bytes; the server never opens it (04 §8.6)';
  end if;

  wk := gen_random_uuid();
  -- Addressed to the SUBJECT's user and to the CANDIDATE DEVICE, which is exactly what 0005's
  -- wrapped_keys SELECT policy needs for an uncertified device to read a key of its own
  -- (`device_id = rf.device_id()`, ADR 2026-09-05d §2). No other party can read it.
  insert into wrapped_keys (id, kind, user_id, device_id, blob)
  values (wk, 'recovery_blob', r.user_id, r.candidate_device, p_blob);
  insert into recovery_approvals (request_id, guardian_user_id, guardian_device,
                                  share_set_version, decision, wrapped_key_id, sealed_to_pub_x)
  values (p_request, rf.user_id(), rf.device_id(), r.share_set_version, 'approved', wk, p_sealed_to);
  return wk;
exception
  when unique_violation then
    raise exception 'already_decided' using errcode = '23514',
      detail = 'this guardian has already decided this attempt; a decision is written once (04 §7.3)';
end $$;

-- ---------------------------------------------------------------- the guardian's ask
-- What a guardian may see: the attempt itself and NOTHING financial. The row carries a user, a
-- device, a public key and two timestamps — no book, no tenant, no envelope, no amount. This is a
-- second PERMISSIVE select policy on recovery_requests, so it only widens reads to guardians of the
-- set the attempt names; 0005's own policy (subject / candidate device) is untouched.
create policy recovery_requests_select_guardian on recovery_requests for select to rf_api
  using (rf.is_certified() and exists (
    select 1 from guardian_set_members g
    where g.subject_user_id = recovery_requests.user_id
      and g.share_set_version = recovery_requests.share_set_version
      and g.guardian_user_id = rf.user_id()));

-- ---------------------------------------------------------------- RLS, policies, grants
-- 0005's "every table" loop ran before these tables existed, so switch RLS on by name.
alter table recovery_approvals enable row level security;
alter table recovery_approvals force row level security;
alter table recovery_cancellations enable row level security;
alter table recovery_cancellations force row level security;

-- recovery_approvals: SELECT only for rf_api. There is no INSERT policy and no INSERT grant — the
-- only writer is rf.recovery_decide, which is what makes "a decision always carries its share, and
-- the share is always bound to this attempt's candidate key" true of the database.
grant select on recovery_approvals to rf_api;
create policy recovery_approvals_select on recovery_approvals for select to rf_api
  using (
    exists (select 1 from recovery_requests r where r.id = recovery_approvals.request_id
              and (r.candidate_device = rf.device_id()
                   or (rf.is_certified() and r.user_id = rf.user_id())))
    or (rf.is_certified() and guardian_user_id = rf.user_id()));

-- recovery_cancellations: the one-tap Cancel is a plain INSERT by an existing CERTIFIED device of
-- the user — the device that is alarming (ADR 2026-09-05d §1). The candidate device cannot cancel
-- its own attempt into silence, and nobody else can cancel at all.
grant select, insert on recovery_cancellations to rf_api;
create policy recovery_cancellations_select on recovery_cancellations for select to rf_api
  using (
    exists (select 1 from recovery_requests r where r.id = recovery_cancellations.request_id
              and (r.candidate_device = rf.device_id()
                   or (rf.is_certified() and r.user_id = rf.user_id())))
    -- ADR 2026-09-05d §1: "a cancel … notifies the guardians who approved"
    or exists (select 1 from recovery_approvals a where a.request_id = recovery_cancellations.request_id
                 and rf.is_certified() and a.guardian_user_id = rf.user_id()));
create policy recovery_cancellations_insert on recovery_cancellations for insert to rf_api
  with check (rf.is_certified()
              and cancelled_by_user = rf.user_id()
              and cancelled_by_device = rf.device_id()
              and exists (select 1 from recovery_requests r
                          where r.id = request_id and r.user_id = rf.user_id()
                            and r.candidate_device <> rf.device_id()));

-- Retention only, and only long after the attempt closed (03 §6).
grant select, delete on recovery_approvals, recovery_cancellations to rf_maintenance;
create policy recovery_approvals_maint on recovery_approvals for all to rf_maintenance using (true);
create policy recovery_cancellations_maint on recovery_cancellations for all to rf_maintenance using (true);
grant select, delete on recovery_requests to rf_maintenance;
create policy recovery_requests_maint on recovery_requests for all to rf_maintenance using (true);

-- 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before these existed.
revoke all on function rf.current_guardian_set(uuid), rf.guardian_set_ready(uuid, int),
  rf.device_live_for(uuid, uuid), rf.has_other_active_device(uuid, uuid),
  rf.live_recovery_count(uuid), rf.guardian_set_guard(),
  rf.guardian_set_member_guard(), rf.recovery_request_guard(), rf.recovery_append_only_guard(),
  rf.recovery_derive(uuid), rf.recovery_progress(uuid),
  rf.recovery_decide(uuid, text, bytea, bytea) from public;
-- The guard calls these as the CALLER (a trigger takes no EXECUTE check of its own only for the
-- trigger function itself), so rf_api needs EXECUTE on the helpers the guard invokes.
grant execute on function rf.current_guardian_set(uuid), rf.guardian_set_ready(uuid, int),
  rf.device_live_for(uuid, uuid), rf.has_other_active_device(uuid, uuid),
  rf.live_recovery_count(uuid), rf.recovery_progress(uuid),
  rf.recovery_decide(uuid, text, bytea, bytea) to rf_api;

-- ---------------------------------------------------------------- retention sweep (maintenance)
-- 03 §6: closed attempts and their rows go 30 days after the attempt's window ended. The request
-- itself is deleted last so the foreign keys hold.
create or replace function rf.sweep_recovery() returns int
language plpgsql security definer set search_path = public as $$
declare n int; m int;
begin
  delete from recovery_approvals a using recovery_requests r
    where a.request_id = r.id and r.expires_at <= now() - interval '30 days';
  get diagnostics n = row_count;
  delete from recovery_cancellations c using recovery_requests r
    where c.request_id = r.id and r.expires_at <= now() - interval '30 days';
  get diagnostics m = row_count; n := n + m;
  delete from recovery_requests r where r.expires_at <= now() - interval '30 days';
  get diagnostics m = row_count;
  return n + m;
end $$;
revoke all on function rf.sweep_recovery() from public;
grant execute on function rf.sweep_recovery() to rf_maintenance;
