-- 06 §7 Invitation & membership state machine 🔒 — enforced in the DATABASE, because an edge
-- function is just another client from RLS's point of view.
--
--   invited ──install+OTP──▶ joined_pending_verification ──ceremony ✓──▶ active
--      │ 7-day expiry                    │ ceremony ✗ (mismatch)
--      ▼                                 ▼
--   expired (one-tap re-invite)       blocked (new invite required)
--
-- Three rules bind every writer here, including the SECURITY DEFINER projectors:
--   * no plaintext number ever reaches the server — invites carry `invitee_hmac` only, and after
--     this migration rf_api cannot even SELECT that column, so a second admin's device learns that
--     an invite exists and who sent it, never whom (ADR 2026-09-05c §4);
--   * the link alone admits nobody — acceptance matches the accepting user's OTP-verified
--     `users.phone_hmac` against `invites.invitee_hmac` (ADR 2026-09-05d §9);
--   * rows stay projections of signed records — invites and memberships both demand the record
--     (ADR 2026-09-05b §1, E-03-19).

-- ---------------------------------------------------------------- invites: shape
-- 06 §7 says a 128-bit ceremony nonce; 0002 wrote 32 bytes. docs win (CLAUDE.md precedence).
do $$ declare c text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'invites'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) like '%octet_length(nonce)%' loop
    execute format('alter table invites drop constraint %I', c);
  end loop;
end $$;
alter table invites add constraint invites_nonce_128 check (octet_length(nonce) = 16);

-- The applying signed record (ADR 2026-09-05b §1) and the acceptance footprint.
alter table invites add column if not exists source_record_id uuid null references signed_records(id);
alter table invites add column if not exists accepted_by uuid null references users(id);
alter table invites add column if not exists accepted_at timestamptz null;

-- The 7-day window of 06 §7, fixed at issue and unextendable.
alter table invites alter column expires_at set default (now() + interval '7 days');
alter table invites add constraint invites_window_7d
  check (expires_at > created_at and expires_at <= created_at + interval '7 days');

create index if not exists invites_live_idx on invites (invitee_hmac, expires_at) where status = 'sent';

-- ---------------------------------------------------------------- invites: state machine
-- sent ──▶ accepted | expired | revoked, and nothing else; tenant, invitee, nonce, sender and the
-- window are immutable once issued. A terminal invite never comes back — re-invite mints a new row.
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
           and r.tenant_id = new.tenant_id and r.kind = 'membership_status') then
      raise exception 'no_record' using errcode = '23514',
        detail = 'invites are projections of signed records (ADR 2026-09-05b §1)';
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
create trigger invites_guard before insert or update on invites
  for each row execute function rf.invite_guard();

-- ---------------------------------------------------------------- memberships: state machine
-- The shape of 06 §7. Self-transitions are allowed so re-applying a signed record is idempotent.
-- `expired` is a state of the INVITE, not of the membership: 03 §2.1's 🔒 status enum has no
-- `expired`, so an expired invite frees the seat by demoting the row to `removed`
-- ("removal frees the seat at once", 06 §7 Seats). ⚠️ SPEC: 06 §7's diagram draws `expired` on the
-- same machine as the membership states; 03 §2.1 owns the storage enum and wins here.
create or replace function rf.membership_transition_ok(p_old text, p_new text) returns boolean
language sql immutable as $$
  select case coalesce(p_old, '-')
    when '-'                           then p_new in ('invited', 'joined_pending_verification', 'active', 'removed')
    when 'invited'                     then p_new in ('invited', 'joined_pending_verification', 'removed')
    when 'joined_pending_verification' then p_new in ('joined_pending_verification', 'active', 'blocked', 'removed')
    when 'active'                      then p_new in ('active', 'removed')
    when 'blocked'                     then p_new in ('blocked', 'removed')
    when 'removed'                     then p_new in ('removed', 'invited', 'joined_pending_verification')
    else false end
$$;

create or replace function rf.membership_guard() returns trigger
language plpgsql as $$
declare prev text;
        v record;
begin
  -- The projectors write with INSERT … ON CONFLICT DO UPDATE, and a BEFORE INSERT trigger fires
  -- before the conflict is seen — so read the row rather than assuming there isn't one, or every
  -- legitimate flip would be judged as if it were a first sighting.
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

  -- invited: a live invite must name this person's number. The link alone admits nobody, and
  -- neither does an admin's bare assertion (ADR 2026-09-05d §9).
  if new.status = 'invited' and prev is distinct from 'invited' then
    if not exists (
      select 1 from invites i join users u on u.id = new.user_id
      where i.tenant_id = new.tenant_id and i.status = 'sent' and i.expires_at > now()
        and u.phone_hmac is not null and i.invitee_hmac = u.phone_hmac) then
      raise exception 'no_live_invite' using errcode = '23514',
        detail = 'membership.invited requires a live invite for this number (06 §7)';
    end if;
  end if;

  -- active: only after a ceremony that succeeded. The one exception is the tenant's founding
  -- member, who has nobody to verify them (06 §5). Nothing else may reach active — in particular
  -- invited -> active and blocked -> active are refused by the transition table above.
  if new.status = 'active' and prev is distinct from 'active' then
    select e.id, e.verifier_user, e.method, e.at into v
      from verification_events e
     where e.tenant_id = new.tenant_id and e.subject_user = new.user_id and e.result = 'verified'
     order by e.at desc limit 1;
    if v.id is null then
      if not (prev is null and not exists (
                select 1 from memberships m where m.tenant_id = new.tenant_id)) then
        raise exception 'ceremony_required' using errcode = '23514',
          detail = 'a member becomes active only on a verified ceremony (06 §7)';
      end if;
    else
      new.verified_by     := coalesce(new.verified_by, v.verifier_user);
      new.verified_method := coalesce(new.verified_method, v.method);
      new.verified_at     := coalesce(new.verified_at, v.at);
    end if;
  end if;

  -- blocked: reachable only from a ceremony that reported a mismatch (06 §7).
  if new.status = 'blocked' and prev is distinct from 'blocked' then
    if not exists (
      select 1 from verification_events e
      where e.tenant_id = new.tenant_id and e.subject_user = new.user_id and e.result = 'mismatch') then
      raise exception 'mismatch_required' using errcode = '23514',
        detail = 'blocked follows a failed ceremony, not an admin''s say-so (06 §7)';
    end if;
  end if;

  return new;
end $$;
create trigger memberships_guard before insert or update on memberships
  for each row execute function rf.membership_guard();

-- ---------------------------------------------------------------- invite privacy (ADR 2026-09-05c §4)
-- Postgres requires SELECT privilege on every column a query REFERENCES, so dropping invitee_hmac
-- and nonce from the grant also blocks `where invitee_hmac = $1` — a second admin cannot even probe.
revoke select on invites from rf_api;
grant select (id, tenant_id, roles, status, expires_at, created_by, created_at, updated_at,
              accepted_by, accepted_at, source_record_id) on invites to rf_api;

-- ---------------------------------------------------------------- invite lifecycle functions
-- Issue (or re-issue) an invite. Admin only, 7-day window stamped server-side, the previous live
-- invite to the same number superseded — 06 §7's one-tap re-invite.
create or replace function rf.create_invite(p_tenant uuid, p_hmac bytea, p_roles jsonb,
  p_nonce bytea, p_record uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not rf.is_tenant_admin(p_tenant) then
    raise exception 'not_admin' using errcode = '42501';
  end if;
  perform rf.require_record(p_record, p_tenant);
  update invites set status = 'revoked'
   where tenant_id = p_tenant and invitee_hmac = p_hmac and status = 'sent';
  insert into invites (tenant_id, invitee_hmac, roles, nonce, created_by, source_record_id, expires_at)
  values (p_tenant, p_hmac, coalesce(p_roles, '[]'::jsonb), p_nonce, rf.user_id(), p_record,
          now() + interval '7 days')
  returning id into v;
  return v;
end $$;

-- What a joining device may see: invites addressed to its OWN OTP-verified number, nothing else.
-- No certification gate — this is the one read a freshly registered device needs (06 §7); it is
-- keyed on the caller's own phone_hmac, so it reveals nothing about anyone else.
create or replace function rf.my_invites()
returns table (id uuid, tenant_id uuid, roles jsonb, expires_at timestamptz, created_by uuid)
language sql stable security definer set search_path = public as $$
  select i.id, i.tenant_id, i.roles, i.expires_at, i.created_by
  from invites i join users u on u.id = rf.user_id()
  where u.phone_hmac is not null and u.erased_at is null
    and i.invitee_hmac = u.phone_hmac and i.status = 'sent' and i.expires_at > now()
$$;

-- Accept. Phone-bound (ADR 2026-09-05d §9); lands at joined_pending_verification, never at active.
-- The membership cites the ADMIN's signed record (the one the invite was issued under), so the row
-- is still a projection even though the invitee's device authored nothing (ADR 2026-09-05b §1).
create or replace function rf.accept_invite(p_invite uuid) returns text
language plpgsql security definer set search_path = public as $$
declare i invites%rowtype; h bytea;
begin
  if rf.user_id() is null or rf.device_id() is null then
    raise exception 'no_claims' using errcode = '42501';
  end if;
  select u.phone_hmac into h from users u where u.id = rf.user_id() and u.erased_at is null;
  select * into i from invites where id = p_invite for update;
  if i.id is null then
    raise exception 'unknown_invite' using errcode = '42501';
  end if;
  if h is null or i.invitee_hmac is distinct from h then
    -- same shape of refusal as an unknown invite: a wrong caller learns nothing about the invitee
    raise exception 'phone_mismatch' using errcode = '42501',
      detail = 'an invite is accepted only by the device whose OTP-verified number matches invitee_hmac (ADR 2026-09-05d §9)';
  end if;
  if i.expires_at <= now() then
    if i.status = 'sent' then update invites set status = 'expired' where id = i.id; end if;
    raise exception 'invite_expired' using errcode = '23514',
      detail = 'invites live 7 days; ask for a new one (06 §7)';
  end if;
  if i.status <> 'sent' then
    raise exception 'invite_not_live' using errcode = '23514', detail = i.status;
  end if;
  insert into memberships (tenant_id, user_id, status, source_record_id)
  values (i.tenant_id, rf.user_id(), 'joined_pending_verification', i.source_record_id)
  on conflict (tenant_id, user_id) do update
    set status = 'joined_pending_verification', source_record_id = excluded.source_record_id;
  update invites set status = 'accepted', accepted_by = rf.user_id(), accepted_at = now()
   where id = i.id;
  return 'joined_pending_verification';
end $$;

-- Sweep: expire live invites past their window and free the seat (06 §7 Seats). Maintenance only.
create or replace function rf.expire_invites() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update invites set status = 'expired' where status = 'sent' and expires_at <= now();
  get diagnostics n = row_count;
  update memberships m set status = 'removed'
   where m.status = 'invited'
     and not exists (
       select 1 from invites i join users u on u.phone_hmac = i.invitee_hmac
       where i.tenant_id = m.tenant_id and u.id = m.user_id
         and i.status = 'sent' and i.expires_at > now());
  return n;
end $$;

-- ---------------------------------------------------------------- verification → membership
-- ADR 2026-09-05d §7: verification events are signed records; the server's row is its copy, and
-- 06 §7's flip happens here, in the database, as part of applying that record.
create or replace function rf.project_verification_event(p_record uuid, p_tenant uuid, p_subject uuid,
  p_verifier uuid, p_method text, p_result text) returns void
language plpgsql security definer set search_path = public as $$
declare cur text;
begin
  perform rf.require_record(p_record, p_tenant);
  if p_verifier is distinct from rf.user_id() then
    raise exception 'not_verifier' using errcode = '42501',
      detail = 'the verifier is the device that authored the record (ADR 2026-09-05d §7)';
  end if;
  if not rf.active_in_tenant(p_tenant) then
    raise exception 'not_active_member' using errcode = '42501',
      detail = 'any ACTIVE member may verify (04 §6.4); nobody else may';
  end if;
  select m.status into cur from memberships m
   where m.tenant_id = p_tenant and m.user_id = p_subject;
  -- A ceremony is about somebody joining THIS tenant. Without this, an admin of another tenant
  -- could author events naming strangers as subjects — noise in a log the family is asked to trust.
  if cur is null or cur = 'removed' then
    raise exception 'subject_not_in_tenant' using errcode = '42501',
      detail = 'a ceremony verifies a member of this tenant (06 §7)';
  end if;
  insert into verification_events (tenant_id, subject_user, verifier_user, method, result, source_record_id)
  values (p_tenant, p_subject, p_verifier, p_method, p_result, p_record);
  if cur = 'joined_pending_verification' then
    if p_result = 'verified' then
      update memberships set status = 'active'
       where tenant_id = p_tenant and user_id = p_subject;
    elsif p_result = 'mismatch' then
      update memberships set status = 'blocked'
       where tenant_id = p_tenant and user_id = p_subject;
      insert into audit_events (tenant_id, user_id, kind, details)
      values (p_tenant, p_subject, 'ceremony_mismatch',
              jsonb_build_object('method', p_method, 'record', p_record));
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------- grants for the new functions
-- 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before these existed,
-- so every function above is grantless until named here. That is the safe default; keep it.
revoke all on function rf.invite_guard(), rf.membership_guard(),
  rf.membership_transition_ok(text, text), rf.create_invite(uuid, bytea, jsonb, bytea, uuid),
  rf.my_invites(), rf.accept_invite(uuid), rf.expire_invites(),
  rf.project_verification_event(uuid, uuid, uuid, uuid, text, text) from public;
grant execute on function rf.create_invite(uuid, bytea, jsonb, bytea, uuid), rf.my_invites(),
  rf.accept_invite(uuid), rf.membership_transition_ok(text, text),
  rf.project_verification_event(uuid, uuid, uuid, uuid, text, text) to rf_api;
grant execute on function rf.expire_invites() to rf_maintenance;
-- rf.expire_invites is a sweep, not an API power: rf_api must never be able to expire an invite.
revoke execute on function rf.expire_invites() from rf_api;
