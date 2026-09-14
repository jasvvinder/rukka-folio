-- M7 · two rules the database now owns, not the edge function.
--
-- (1) ADR 2026-09-05d §7 🔒 — **verification and device events are signed records.** 0002 gave
--     `verification_events.source_record_id` as a nullable column with a comment, and 0005/0006 then
--     let `rf.membership_guard` read ANY row with `result = 'verified'` as proof of a ceremony. So a
--     writer who could reach the table at all — the table owner, a SECURITY DEFINER function, a
--     future maintenance path — could mint an unsigned "she was verified" row and walk a membership
--     from `joined_pending_verification` to `active` without a ceremony ever happening. The tenant's
--     trust root would then be the server's word, which is the one thing ADR 2026-09-05d §7 removes.
--     This migration closes it at the row: an event without its signed record cannot be written, and
--     an event that is not backed is not believed. ⟦tests: C-05d-7, E-06-30, E-06-31, E-06-32⟧
--
-- (2) 06 §7 🔒 — the invite that a second phone can actually accept. 0006 landed the tables, the
--     state machine and `rf.create_invite` / `rf.my_invites` / `rf.accept_invite`, and left the wire
--     open: neither 05 §5 nor 06 §7 says which record kind authorises an invite. 0006 demanded
--     `kind = 'membership_status'` "for now"; this migration names the kind `invite`, because a
--     membership_status payload is `{user_id, status}` and an invitee HAS no user_id yet — the whole
--     point of 06 §7's `invited` state is that the person has not installed the app.
--     ⚠️ SPEC (owner): the wire contract below is a conservative reading, not a quoted line.
--       * kind `invite`, payload `{roles, nonce}` — and **no identifier of the invitee in the
--         record**, because the admin's device CANNOT compute `invitee_hmac`: the HMAC key is the
--         server's (ADR 2026-09-05c §4). 06 §7 already says the number reaches the server only in
--         transit ("the plaintext goes into the outbound message job and is gone once sent"), so the
--         route takes the E.164 number, HMACs it, stores the HMAC and drops the number. Signing the
--         HMAC was considered and rejected twice over: the admin cannot produce it, and a record
--         carrying it would be broadcast to every active member by `signed_records_select` —
--         undoing 0006's column-level hiding of `invitee_hmac`.
--       * whom the admin invited therefore stays where 06 §7 puts it: "the admin's device shows whom
--         it invited from its own contact card". The server's copy is an HMAC and nothing else.
--       If the owner would rather the invitee be named inside the signed record, that needs a
--       client-computable identifier (a client-held HMAC key, or the number itself) — a 04/05c
--       change, not a server one.

-- ---------------------------------------------------------------- (1) events are signed records
-- Referential integrity for the rows written from here on. NOT VALID: a deployment that already
-- holds unbacked rows keeps them (they are history) — the guard below refuses new ones, and
-- rf.membership_guard refuses to BELIEVE any of them, old or new.
alter table verification_events
  add constraint verification_events_record_fk foreign key (source_record_id)
  references signed_records (id) not valid;
alter table verification_events
  add constraint verification_events_record_required check (source_record_id is not null) not valid;

-- The guard binds every writer, the table owner included: a trigger is not a privilege.
create or replace function rf.verification_event_guard() returns trigger
language plpgsql as $$
begin
  if TG_OP = 'UPDATE' then
    -- The event is a copy of a signed fact; the fact does not change. (`updated_at` may.)
    if old.tenant_id is distinct from new.tenant_id
       or old.subject_user is distinct from new.subject_user
       or old.verifier_user is distinct from new.verifier_user
       or old.method is distinct from new.method
       or old.result is distinct from new.result
       or old.at is distinct from new.at
       or old.source_record_id is distinct from new.source_record_id then
      raise exception 'verification_event_immutable' using errcode = '23514',
        detail = 'a verification event is the server''s copy of a signed record (ADR 2026-09-05d §7)';
    end if;
    return new;
  end if;
  if new.source_record_id is null then
    raise exception 'no_record' using errcode = '23514',
      detail = 'verification events are signed records; an unsigned row is not a ceremony (ADR 2026-09-05d §7)';
  end if;
  if not exists (select 1 from signed_records r
                 where r.id = new.source_record_id
                   and r.tenant_id = new.tenant_id
                   and r.kind = 'verification_event') then
    raise exception 'no_record' using errcode = '23514',
      detail = 'the backing record must be a verification_event of THIS tenant (ADR 2026-09-05d §7)';
  end if;
  return new;
end $$;
create trigger verification_events_guard before insert or update on verification_events
  for each row execute function rf.verification_event_guard();

-- ---------------------------------------------------------------- 06 §7 membership machine, hardened
-- Identical to 0006's guard except that the two ceremony lookups now join `signed_records`: an event
-- nothing signed is not evidence. Kept whole rather than split, so the machine reads in one place.
create or replace function rf.membership_guard() returns trigger
language plpgsql as $$
declare prev text;
        v record;
begin
  -- The projectors write with INSERT … ON CONFLICT DO UPDATE, and a BEFORE INSERT trigger fires
  -- before the conflict is seen — so read the row rather than assuming there isn't one.
  if TG_OP = 'UPDATE' then
    prev := old.status;
  else
    select m.status into prev from memberships m
     where m.tenant_id = new.tenant_id and m.user_id = new.user_id;
  end if;
  if not rf.membership_transition_ok(prev, new.status) then
    raise exception 'membership_transition' using errcode = '23514',
      detail = format('%s -> %s is not a transition of 06 §7',
                      coalesce(prev, '(none)'), new.status);
  end if;

  -- invited: a live invite must name this person's number (ADR 2026-09-05d §9).
  if new.status = 'invited' and prev is distinct from 'invited' then
    if not exists (
      select 1 from invites i join users u on u.id = new.user_id
      where i.tenant_id = new.tenant_id and i.status = 'sent' and i.expires_at > now()
        and u.phone_hmac is not null and i.invitee_hmac = u.phone_hmac) then
      raise exception 'no_live_invite' using errcode = '23514',
        detail = 'membership.invited requires a live invite for this number (06 §7)';
    end if;
  end if;

  -- active: only after a ceremony that succeeded AND was signed. The one exception is the tenant's
  -- founding member, who has nobody to verify them (06 §5).
  if new.status = 'active' and prev is distinct from 'active' then
    select e.id, e.verifier_user, e.method, e.at into v
      from verification_events e
      join signed_records r on r.id = e.source_record_id and r.tenant_id = e.tenant_id
                           and r.kind = 'verification_event'
     where e.tenant_id = new.tenant_id and e.subject_user = new.user_id and e.result = 'verified'
     order by e.at desc limit 1;
    if v.id is null then
      if not (prev is null and not exists (
                select 1 from memberships m where m.tenant_id = new.tenant_id)) then
        raise exception 'ceremony_required' using errcode = '23514',
          detail = 'a member becomes active only on a SIGNED verified ceremony (06 §7, ADR 2026-09-05d §7)';
      end if;
    else
      new.verified_by     := coalesce(new.verified_by, v.verifier_user);
      new.verified_method := coalesce(new.verified_method, v.method);
      new.verified_at     := coalesce(new.verified_at, v.at);
    end if;
  end if;

  -- blocked: reachable only from a signed ceremony that reported a mismatch (06 §7).
  if new.status = 'blocked' and prev is distinct from 'blocked' then
    if not exists (
      select 1 from verification_events e
      join signed_records r on r.id = e.source_record_id and r.tenant_id = e.tenant_id
                           and r.kind = 'verification_event'
      where e.tenant_id = new.tenant_id and e.subject_user = new.user_id and e.result = 'mismatch') then
      raise exception 'mismatch_required' using errcode = '23514',
        detail = 'blocked follows a failed ceremony, not an admin''s say-so (06 §7)';
    end if;
  end if;

  return new;
end $$;

-- ---------------------------------------------------------------- (2) the invite's own record kind
-- 0003 fixed the kind registry as a column CHECK; `invite` joins it. (Named lookup, not a guessed
-- constraint name: 0003 let Postgres name it.)
do $$ declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'signed_records'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) like '%kind%' loop
    execute format('alter table signed_records drop constraint %I', c);
  end loop;
end $$;
alter table signed_records add constraint signed_records_kind_check check (kind in (
  'membership_status','book_role','member_removal','device_revocation','device_added',
  'key_rotation','verification_event','designation','invite'));

-- ---------------------------------------------------------------- (2) the invite's own record kind
-- 0006 accepted `membership_status`; the kind is now `invite` (see the ⚠️ SPEC block above). The
-- rest of the guard is 0006's, unchanged.
create or replace function rf.invite_guard() returns trigger
language plpgsql as $$
begin
  if TG_OP = 'INSERT' then
    if new.status <> 'sent' then
      raise exception 'invite_state' using errcode = '23514',
        detail = 'an invite is issued at sent (06 §7)';
    end if;
    if new.accepted_by is not null or new.accepted_at is not null then
      raise exception 'invite_state' using errcode = '23514',
        detail = 'a new invite is not already accepted';
    end if;
    if new.source_record_id is null or not exists (
         select 1 from signed_records r where r.id = new.source_record_id
           and r.tenant_id = new.tenant_id and r.kind = 'invite') then
      raise exception 'no_record' using errcode = '23514',
        detail = 'invites are projections of a signed `invite` record (ADR 2026-09-05b §1, 06 §7)';
    end if;
    return new;
  end if;
  if old.tenant_id is distinct from new.tenant_id
     or old.invitee_hmac is distinct from new.invitee_hmac
     or old.nonce is distinct from new.nonce
     or old.created_by is distinct from new.created_by
     or old.created_at is distinct from new.created_at
     or old.expires_at is distinct from new.expires_at
     or old.source_record_id is distinct from new.source_record_id then
    raise exception 'invite_immutable' using errcode = '23514',
      detail = 'tenant, invitee, nonce, sender, record and the 7-day window are fixed at issue (06 §7)';
  end if;
  if old.status is distinct from new.status
     and not (old.status = 'sent' and new.status in ('accepted', 'expired', 'revoked')) then
    raise exception 'invite_state' using errcode = '23514',
      detail = format('invite %s -> %s is not a transition of 06 §7', old.status, new.status);
  end if;
  return new;
end $$;

-- Trigger functions are not API powers: the table owner needs EXECUTE, nobody else does.
revoke all on function rf.verification_event_guard() from public;
