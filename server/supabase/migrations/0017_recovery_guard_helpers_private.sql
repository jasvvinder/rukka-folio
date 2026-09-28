-- 0017 — the rung-2 open's lookups belong to its guard, not to the API role
-- (ADR 2026-09-24b §3 🔒 "The answer is a boolean: no k, no n"; ADR 2026-09-05d §2 🔒 uncertified
-- devices get nothing else; 04 §7.3 🔒 rung 2). ⟦tests: E-24b-1⟧
--
-- WHAT WAS OPEN. 0010 made five lookups SECURITY DEFINER so that rf.recovery_request_guard, a BEFORE
-- trigger that ran as the CALLING role, could check facts the uncertified requester may not read.
-- Because the guard ran as the caller, 0010 then had to grant rf_api EXECUTE on the five
-- (0010:537-542). Each takes an arbitrary subject, so rf_api could call them directly, for anyone:
--
--   rf.current_guardian_set(user)          → that user's current (share_set_version, k, n)
--   rf.guardian_set_ready(user, version)   → whether that user's set holds all n members
--   rf.device_live_for(device, user)       → whether a device is a live device of that user
--   rf.has_other_active_device(user, dev)  → whether that user has another certified device
--   rf.live_recovery_count(user)           → how many recovery attempts that user has open
--
-- That bypassed 0005's certified-only policies on guardian_sets and guardian_set_members, and gave
-- any rf_api session more than ADR 24b §3 lets even the user's OWN uncertified device learn (one
-- boolean via rf.has_guardian_set, 0016). No HTTP route hands these a caller-chosen subject, so this
-- was not a wire leak. But the role is the boundary the hostile-query suite tests, and a boundary
-- that holds only while the edge behaves is not a boundary.
--
-- THE FIX. The guard becomes SECURITY DEFINER with search_path pinned, the same shape as every other
-- rf.* function that must see what its caller may not. It now calls the five as their owner, so
-- rf_api needs no EXECUTE on them, and the grant is revoked. What does NOT change:
--   * the guard's body, its refusals (no_guardian_set, guardian_set_incomplete,
--     unknown_candidate_device, recovery_flood, append_only, recovery_shape) and their error codes;
--   * the server-set state and timers (ADR 2026-09-05d §1 🔒: the 24 h wait is the server's);
--   * RLS on recovery_requests. A policy binds the role that runs the statement, not the role a
--     trigger function runs as, so 0005's recovery_requests_insert (candidate_device =
--     rf.device_id() and user_id = rf.user_id()) still decides as rf_api;
--   * rf.has_guardian_set (0016), the only other caller, which is SECURITY DEFINER already.
-- The guard reads the claims nowhere (it checks `new.*` against the helpers), so running it as the
-- owner cannot widen what a request may name. The trigger itself needs no EXECUTE grant: Postgres
-- checks EXECUTE on a trigger function at CREATE TRIGGER, never when it fires.
--
-- 0010 is committed and may already be applied, so it is amended here rather than edited.
-- No table, column, policy or table grant changes, and nothing touches envelopes (CLAUDE.md rule 2).

alter function rf.recovery_request_guard() security definer;
alter function rf.recovery_request_guard() set search_path = public;

revoke all on function rf.current_guardian_set(uuid), rf.guardian_set_ready(uuid, int),
  rf.device_live_for(uuid, uuid), rf.has_other_active_device(uuid, uuid),
  rf.live_recovery_count(uuid)
  from public, rf_api, rf_maintenance;

comment on function rf.current_guardian_set(uuid) is
  'The current guardian set is the highest share_set_version (0010). Owner-only since 0017: called by '
  'rf.recovery_request_guard and rf.has_guardian_set, both SECURITY DEFINER. rf_api may not call it: '
  'it returns k and n for any subject, which ADR 2026-09-24b §3 withholds.';
