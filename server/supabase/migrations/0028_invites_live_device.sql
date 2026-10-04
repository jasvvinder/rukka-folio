-- 0028 — a revoked or suspended device cannot read or accept its user's invites (ADR 2026-10-03c §3
-- 🔒, desk 37; ADR 2026-10-04 suspended-invites 🔒, desk 108).
-- ⟦tests: E-03c-1, E-03c-2, E-03c-3, E-03c-4⟧ — tests/rls/invites_live_device.test.ts (database,
-- PgStore on rf_api) and functions/_tests/invites_live_device.test.ts (route + MemStore).
--
-- THE GAP. rf.my_invites (0015) and rf.accept_invite (0006) keyed on the USER claim alone. An
-- access token is valid until it expires (06 §4), so the token on a phone that has just been
-- revoked could still list its user's offers with their nonces, and accept one. The nonce is not
-- secret (04 §6.1), but a revoked device must not act for its user.
--
-- THE GATE. Both functions now first ask rf.device_live_for(rf.device_id(), rf.user_id()) — the
-- predicate the rung-2 open (rf.recovery_request_guard, 0010) and rf.has_guardian_set (0025) use:
-- the device claim names a device OF the caller's user whose `status <> 'revoked'` and whose
-- `revoked_at is null` — AND that the device's `status <> 'suspended'`, in rf.recovery_shares'
-- shape (0020: the same predicate with the same `d.status <> 'suspended'` beside it). A miss of
-- either half raises the same named refusal the open and rf.has_guardian_set raise for a caller
-- that is not live: `unknown_candidate_device`, errcode 42501, with one detail text — so nothing
-- the caller sees tells suspended from revoked from somebody else's. denialFromPg (_shared/store.ts) passes the bare token
-- through as StoreDenied('unknown_candidate_device'), and sync-meta's inviteError maps it to the
-- wire answer recoveryError gives it — 403 `unknown_request` — so a revoked phone gets one refusal
-- on every device-gated route, never an empty list.
--
-- WHERE THE GATE SITS, and why that is not an oracle. It is the first thing either function
-- does after 0006's own `no_claims` check (kept, and still first in accept_invite): before the
-- caller's user row, before any invite is read, before the FOR UPDATE lock. So the refusal is
-- byte-identical whether or not the user has invites, and whether or not the id names one; a
-- refused accept writes nothing; and it is also ahead of the 7-day check, so a revoked or suspended
-- caller on a lapsed invite draws this refusal, never `invite_expired`, and cannot learn the invite
-- lapsed. (0006's flip of a lapsed invite to `expired`, kept below, never persists on ANY caller:
-- the `raise invite_expired` after it in the same statement, with no EXCEPTION block, rolls it
-- back. Only the maintenance sweep rf.expire_invites moves an invite to `expired`.)
--
-- WHAT A NULL CLAIM MEANS. rf.device_live_for of a null device or a null user is false, so a caller
-- with no device claim is refused by rf.my_invites (0015 answered it zero rows). That is 0025's
-- reading ("Null claims fail it"), strictly narrower than before, and the edge never calls without
-- both claims (route.ts authenticate). rf.accept_invite still answers null claims `no_claims` first.
--
-- A SUSPENDED DEVICE IS REFUSED (owner ruling, 4 Oct 2026 — ADR 2026-10-04 suspended-invites,
-- desk 108). Suspension is the server asserting a revocation without a signed record (ADR
-- 2026-09-05b §2; support revocation, 24 h and cancellable — ADR 2026-09-05d §3): a stolen phone
-- under suspension must not join new books, and a cancel restores the device. rf.device_live_for
-- itself is NOT changed — it has other callers that keep its reading, notably rf.has_guardian_set
-- (0025 (c), ADR 2026-10-03 § Desk 45: a suspended device is still answered there) — so the
-- suspended test sits beside it here, as it does in rf.recovery_shares (0020).
--
-- WHAT DOES NOT CHANGE. Signatures, return types and every other behaviour: my_invites' scope (sent
-- to my OTP-verified number, or accepted by me, inside the 7-day window; erased user → no rows), its
-- columns and order (0015 (c)); accept_invite's phone binding, refusal names and codes, the landing
-- at joined_pending_verification, the cited record. Both stay SECURITY DEFINER with 0024's
-- `search_path = public, pg_temp` (a CREATE OR REPLACE replaces proconfig, so it is restated; E-03-84
-- holds every rf routine to it). rf.my_invites moves from `language sql` to plpgsql because SQL
-- cannot raise; it stays STABLE, and its query is 0015's verbatim under RETURN QUERY (every column
-- reference is qualified, so the OUT parameters cannot shadow one). CREATE OR REPLACE keeps the
-- owner and the ACL; the revoke/grant pair is restated so this file says what it leaves behind.
-- rf.device_live_for stays owner-only (0017): both callers are SECURITY DEFINER and call it, and
-- read `devices` for the suspended test, as the owner, so rf_api gains no EXECUTE and no read.
--
-- CLAUDE.md rule 2: nothing here touches `envelopes`; no table, column, policy or grant is added or
-- widened. Migrations are append-only: 0006 and 0015 are not edited, they are replaced here.

create or replace function rf.my_invites()
returns table (id uuid, tenant_id uuid, roles jsonb, expires_at timestamptz, created_by uuid,
               status text, nonce bytea)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- ADR 2026-10-03c §3 + ADR 2026-10-04 (desk 108): the caller's device claim is a live device of
  -- the caller's user and is not suspended — asked before anything is read, so the refusal says
  -- nothing about what the user has, nor which half failed.
  if not rf.device_live_for(rf.device_id(), rf.user_id())
     or not exists (select 1 from devices d
                    where d.id = rf.device_id() and d.status <> 'suspended') then
    raise exception 'unknown_candidate_device' using errcode = '42501',
      detail = 'the caller''s device is not a live, unsuspended device of its user (ADR 2026-10-03c §3, ADR 2026-10-04)';
  end if;
  return query
    select i.id, i.tenant_id, i.roles, i.expires_at, i.created_by, i.status, i.nonce
    from invites i join users u on u.id = rf.user_id()
    where u.erased_at is null
      and i.expires_at > now()
      and (   (i.status = 'sent' and u.phone_hmac is not null and i.invitee_hmac = u.phone_hmac)
           or (i.status = 'accepted' and i.accepted_by = u.id))
    -- live offers first (0015 (c)), then soonest-closing, then id: the order the MemStore mirrors
    order by (i.status <> 'sent'), i.expires_at, i.id;
end
$$;

comment on function rf.my_invites() is
  'The caller''s own invites — at sent and addressed to its OTP-verified number, or accepted by it — inside the 7-day window, with the inviter-drawn nonce (ADR 2026-09-25b §2) and the invite status (sent | accepted), live offers first. The only rf_api read of invites.nonce. A caller whose device claim is not a live device of its user (rf.device_live_for) or is suspended is REFUSED with 42501 unknown_candidate_device (ADR 2026-10-03c §3, ADR 2026-10-04, 0028) — never answered with an empty list.';

-- Accept. Phone-bound (ADR 2026-09-05d §9); lands at joined_pending_verification, never at active.
-- The membership cites the ADMIN's signed record (the one the invite was issued under), so the row
-- is still a projection even though the invitee's device authored nothing (ADR 2026-09-05b §1).
create or replace function rf.accept_invite(p_invite uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare i invites%rowtype; h bytea;
begin
  if rf.user_id() is null or rf.device_id() is null then
    raise exception 'no_claims' using errcode = '42501';
  end if;
  -- ADR 2026-10-03c §3 + ADR 2026-10-04 (desk 108): a revoked or suspended device does not act
  -- for its user. Before the invite is looked up or locked, so an unknown id and a real one draw
  -- the same refusal, and nothing is written.
  if not rf.device_live_for(rf.device_id(), rf.user_id())
     or not exists (select 1 from devices d
                    where d.id = rf.device_id() and d.status <> 'suspended') then
    raise exception 'unknown_candidate_device' using errcode = '42501',
      detail = 'the caller''s device is not a live, unsuspended device of its user (ADR 2026-10-03c §3, ADR 2026-10-04)';
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
    -- 0006's line, kept verbatim: the raise below undoes it (one statement, no EXCEPTION block), so
    -- the row stays `sent` until rf.expire_invites. The refusal is what binds the window.
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

comment on function rf.accept_invite(uuid) is
  'Phone-bound acceptance of an invite (ADR 2026-09-05d §9), landing at joined_pending_verification. A caller whose device claim is not a live device of its user (rf.device_live_for) or is suspended is REFUSED with 42501 unknown_candidate_device before the invite is read or locked, and nothing is written (ADR 2026-10-03c §3, ADR 2026-10-04, 0028).';

revoke all on function rf.my_invites(), rf.accept_invite(uuid) from public;
grant execute on function rf.my_invites(), rf.accept_invite(uuid) to rf_api;
