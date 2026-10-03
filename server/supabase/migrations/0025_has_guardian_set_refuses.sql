-- 0025 — rf.has_guardian_set() REFUSES a caller it cannot answer truthfully, instead of `false`
-- (desk 45, owner ruling 3 Oct 2026, recorded in ADR 2026-10-03 § Desk 45; amends 0016's
-- ⚠️ SPEC reading (b) only). Spec: ADR 2026-09-24b §3 🔒 (the one read), 04 §7.3 🔒 (rung 2 never
-- a false denial), ADR 2026-09-05d §2 🔒 (what an uncertified device may learn).
-- ⟦tests: E-24b-3, E-24b-4⟧ — tests/rls/has_guardian_set.test.ts (database) and
-- functions/_tests/has_guardian_set.test.ts (route + MemStore).
--
-- WHAT CHANGES. 0016 answered `false`, a constant, when the caller's device claim was not a live
-- device of the caller's own user (a revoked phone, a claim that is somebody else's device, no
-- device claim) or when that user was erased. The client renders `false` as rung 2's
-- `noTrustedMembers` — "you set nobody up" — so a revoked phone reaching S11.6 was told that even
-- when members hold shares: the false denial 04 §7.3 🔒 and ADR 2026-09-24b §4 exist to prevent.
-- Now every such caller is REFUSED: `raise exception 'unknown_candidate_device'` with errcode
-- 42501 — the very name and code 0010's rung-2 open (rf.recovery_request_guard) raises for the
-- same caller. denialFromPg (_shared/store_pg.ts) maps a bare-token 42501 to
-- StoreDenied('unknown_candidate_device'), and sync-meta's recoveryError gives both routes ONE wire
-- answer, 403 `unknown_request`. The client already reads any non-2xx from this route as rung 2
-- `unknown` (guardians_api.dart `_send`, recovery_ladder_source.dart `trustedMembersProbe`).
--
-- ONE REFUSAL, NO NEW ORACLE. The refusal carries nothing a `false` did not: one message, one
-- detail, one code, raised BEFORE the set is looked at — so it is byte-identical for a revoked
-- device, a foreign device, a missing claim, a user id that does not exist and an erased user, and
-- identical whether or not that user holds a set (E-24b-3 compares the whole error). A caller who
-- is a live device of a live user is answered exactly as before: a current set → true, none →
-- false.
--
-- WHAT DOES NOT CHANGE (owner: readings (a) and (c) stay AS BUILT). (a) A published set short of n
-- members reads true. (c) A SUSPENDED device is answered, because rf.device_live_for — the
-- predicate the open uses — counts it as live. The function keeps 0016's shape: no argument,
-- boolean return, STABLE, SECURITY DEFINER, `search_path = public, pg_temp` (0024's pin — a
-- `create or replace` replaces proconfig, so it is restated here; E-03-84 holds every rf routine to
-- it), EXECUTE revoked from PUBLIC and granted to rf_api only. CREATE OR REPLACE keeps the owner and
-- the ACL; both statements are repeated anyway so this file says what it leaves behind.
--
-- PARITY. For a revoked or foreign caller the bit and the open now refuse by the same name
-- (E-24b-4); for a live caller neither does. The one place the bit stays stricter than the open is
-- an erased user (0016's note: 0010's guard does not check erasure) — refused here, by the same
-- one name.
--
-- CLAUDE.md rule 2: nothing here touches `envelopes`; no table, column, policy or grant is added
-- or widened. Migrations are append-only: 0016 is not edited, it is replaced by this definition.

create or replace function rf.has_guardian_set()
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- One test, made before the set is read: the caller's user exists, is not erased, and its
  -- device claim is a live device of that user. Null claims fail it (device_live_for of null is
  -- false; a null user matches no row).
  if not exists (
    select 1 from users u
     where u.id = rf.user_id()
       and u.erased_at is null
       and rf.device_live_for(rf.device_id(), u.id)
  ) then
    raise exception 'unknown_candidate_device' using errcode = '42501',
      detail = 'the caller is not a live device of a live user (desk 45: refused, never false)';
  end if;
  return exists (select 1 from rf.current_guardian_set(rf.user_id()));
end
$$;

comment on function rf.has_guardian_set() is
  'ADR 2026-09-24b §3: does the CALLER''s own user have a current guardian set (rf.current_guardian_set). '
  'One boolean, no argument, not gated on rf.is_certified(). A caller whose device claim is not a live '
  'device of its own user, or whose user is erased, is REFUSED with 42501 unknown_candidate_device '
  '(desk 45, 0025) — never answered false. Never k, n, a version, a member or a share.';

revoke all on function rf.has_guardian_set() from public;
grant execute on function rf.has_guardian_set() to rf_api;
