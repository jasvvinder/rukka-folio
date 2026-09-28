-- 0016 — one yes/no question an UNCERTIFIED device may ask about its own user
-- (ADR 2026-09-24b §3 🔒, amending ADR 2026-09-05d §2 🔒 by exactly one read; 04 §7.3 🔒 rung 2).
-- ⟦tests: E-24b-1⟧
--
-- THE READ. "An uncertified device may learn whether ITS OWN USER (`user_id = rf.user_id()`) has a
-- current guardian set. The answer is a boolean: no k, no n, no member identity, no share, no
-- generation. The read is deliberately NOT gated on `rf.is_certified()`." Everything else in
-- 05d §2 stands: no memberships, names, roles, device lists or verification log.
--
-- HOW IT IS CARVED OUT, and why nothing wider moves. 05d §2's certified-only gate is not a route
-- gate — sync-meta authenticates any JWT holder (route.ts `authenticate`) and it is RLS that
-- answers an uncertified caller with nothing: every policy on `guardian_sets` and
-- `guardian_set_members` requires `rf.is_certified()` (0005:357-365). This file leaves every one of
-- those policies and grants exactly as they are, and adds ONE SECURITY DEFINER function that:
--   * takes NO argument — there is no subject to name, so nobody can ask about anyone else, and the
--     answer cannot be turned into an oracle over other users by enumeration;
--   * keys on the caller's own user claim `rf.user_id()`, and answers only for a caller whose
--     device claim `rf.device_id()` is a LIVE device of that same user (rf.device_live_for, 0010:
--     not revoked, `revoked_at` null) and whose user is not erased. Anything else reads `false`,
--     a constant, so a revoked phone, a device claim that belongs to somebody else and a stale
--     claim for an erased user learn nothing — not even that the bit exists for them;
--   * returns `boolean` and nothing else — the function cannot return k, n, a version or a member
--     because its type has nowhere to put one;
--   * pins `search_path`, is revoked from PUBLIC and granted EXECUTE to rf_api only (the 0010/0015
--     pattern). rf_maintenance is not granted it: nothing it does needs the bit.
--
-- WHAT "CURRENT" MEANS. Exactly what the rung-2 open means by it: `rf.current_guardian_set` (0010),
-- the highest share_set_version whose `superseded_at` is null. The bit therefore agrees with the
-- open's own refusal — for the same caller, `false` here ⇔ `POST /sync-meta/recovery` would refuse
-- `no_guardian_set` or `unknown_candidate_device` — so the client is never told "you have trusted
-- members" by one read and "you have none" by the next. That parity is asserted (E-24b-1). The one
-- place the bit is STRICTER than the open is an erased user (06 §9.3), which reads false here as it
-- reads nothing from rf.my_invites (0015). (0010's open does not check erasure; an erased user can
-- no longer be found by OTP login, 0005:121, but whether a surviving refresh token still works was
-- not checked here — the stricter answer costs nothing either way.)
--
-- WHAT THIS DOES NOT ADD. The open itself (0010's guard, reachable by the same uncertified device
-- since M11) already answered 409 `no_guardian_set` vs `guardian_set_incomplete` vs a created
-- request — the same bit and more, with a side effect (a live attempt that pages every guardian).
-- This read is that bit without the side effect, and without the readiness fact.
--
-- ⚠️ SPEC (owner, ADR 2026-09-24b §3): three readings the ADR does not spell out, each taken
-- conservatively and each asserted by E-24b-1 so a ruling flips one test, not a guess:
--   (a) A published set with fewer than n members (`guardian_set_incomplete`) reads TRUE. The ADR
--       names existence ("has a current guardian set"); readiness is a second fact about the set
--       (how many members have been uploaded) that the ADR's "no k, no n, no member" withholds, and
--       a `false` would make rung 2 say "you set no trusted members up" to somebody who did — the
--       false denial 04 §7.3 and ADR 2026-09-24b §4 exist to prevent. The open still refuses such a
--       set by name (409 `guardian_set_incomplete`), so taking the rung is never a dead end.
--   (b) A REVOKED device (or a device claim that is not the caller user's) reads FALSE, a constant,
--       rather than a refusal. It withholds the bit exactly as a refusal would; the difference is
--       only what the client renders (`noTrustedMembers` vs `unknown`), and such a device cannot
--       open a request anyway (0010 `unknown_candidate_device`). Owner: a refusal instead?
--   (c) A SUSPENDED device (05 §5 / ADR 2026-09-05b §2: sync stopped on a bare 401 or row) is
--       answered, because rf.device_live_for — the predicate the open uses — counts it as live.
--       Parity with the open is the property kept; narrowing it here alone would break parity.
--
-- CLAUDE.md rule 2: nothing here touches `envelopes`, and no table, column, policy or grant is
-- added or altered. Migrations are append-only: 0005 and 0010 are untouched.

create function rf.has_guardian_set()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from users u
    where u.id = rf.user_id()
      and u.erased_at is null
      and rf.device_live_for(rf.device_id(), u.id)
      and exists (select 1 from rf.current_guardian_set(u.id)))
$$;

comment on function rf.has_guardian_set() is
  'ADR 2026-09-24b §3: does the CALLER''s own user have a current guardian set (rf.current_guardian_set). '
  'One boolean, no argument, not gated on rf.is_certified(); false for a caller whose device claim is not '
  'a live device of its user, or whose user is erased. Never k, n, a version, a member or a share.';

-- A new function is EXECUTE-able by PUBLIC by default, and 0005's blanket
-- `grant execute on all functions in schema rf to rf_api` ran before this existed: name both.
revoke all on function rf.has_guardian_set() from public;
grant execute on function rf.has_guardian_set() to rf_api;
