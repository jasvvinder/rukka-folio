-- 0023 — the retention sweep for the seat-rotation ledger `seat_grants` (0019 §3; ADR 2026-09-05g
-- §6 🔒; PLAN M13 caps row "seat_grants retention sweep (rows > 1 y never read)").
-- ⟦tests: E-05g-27, E-05g-28, E-05g-29, E-05g-30⟧
--
-- CLAUDE.md rule 2: nothing here grants UPDATE or DELETE on any table, and `envelopes` is not
-- touched. The one new object is a SECURITY DEFINER function that only rf_maintenance may execute
-- (the shape of rf.purge_ephemeral_auth, 0004 / 0005:302, and rf.sweep_ceremony_sessions, 0007).
-- Zero-knowledge: it reads and deletes (tenant, user, invite, time) rows — no envelope, blob,
-- wrapped key or phone hash (seat_grants holds none; 0019 §3).
--
-- ---------------------------------------------------------------- may seat_grants be deleted at all?
-- Read before writing (grepped, not assumed): no 🔒 line in docs/ names seat_grants, and 03 §6 🔒
-- (retention) does not list it. The one sentence that speaks to deletion is 0019 §8's comment:
-- "nobody can delete a grant to buy back rotation budget (append-only, CLAUDE.md rule 2's posture)".
-- Its object is BUYING BACK BUDGET — deleting a row a reader still counts — which this sweep is
-- built and tested never to do (below; E-05g-28). "CLAUDE.md rule 2's posture" is no API UPDATE or
-- DELETE, with retention deletion the maintenance role's alone (03 §2.5 🔒; 0005:388 gives
-- rf_maintenance DELETE even on envelopes) — the posture this file keeps: the table gains no grant
-- and no policy; only this function reaches it, and only as its definer.
-- ⚠️ SPEC (reported): 03 §6 lists no retention for seat_grants (it predates the table). The reading
-- taken is data minimisation — a row nothing will ever read again is personal data (who joined
-- which tenant, when) kept for no purpose — bounded by the proof below. 03 §6 should gain the line.
--
-- ---------------------------------------------------------------- every reader, and the proof
-- Readers of seat_grants (grepped across migrations 0001–0021 and supabase/functions; E-05g-28
-- re-checks it in the live catalogue and fails if a new reader appears. It checks three ways:
--   * function text: prosrc, plus the deparsed body of a SQL-standard `begin atomic` function,
--     whose prosrc is empty;
--   * every pg_depend dependent of the table or its row type that is not one of the table's own
--     parts: SQL bodies, views, rules, policies and foreign keys elsewhere, row-type signatures;
--   * view, materialised-view and policy definitions.
-- It also scans the edge functions' source. The one shape no catalogue check can see is a name
-- built at run time in dynamic SQL; there is none here, and review has to catch a new one):
--   * rf.take_seat (0019 §4), the 30-day re-invite exemption, 0019:169:
--       g.granted_at > now() - interval '30 days'
--   * rf.take_seat (0019 §4), the rolling count of ADR 05g §6, 0019:178:
--       g.granted_at > now() - interval '1 year'
--   * nothing else: no view, no policy (0019 §8: RLS forced, no policy, no grant), no edge function
--     (rf_api holds no privilege on the table — E-05g-11), no other SQL function.
-- The longest window is the trailing year. Desk PLAN-60 (a) is still open on what "per year" means;
-- every reading on the table — trailing, calendar, Indian financial, subscription-anniversary — looks
-- back AT MOST one year, so the cutoff below holds under whichever the owner rules.
--
-- The sweep deletes `granted_at < now() - interval '1 year 30 days'`: strictly older than the
-- longest window by 30 days. The margin absorbs every way two `now() - interval '1 year'` can
-- disagree, each of which is a day or less:
--   * month arithmetic clamps at month ends (29 Feb minus a year is 28 Feb) — ≤ 1 day;
--   * timestamptz − months is computed in the SESSION time zone, so a reader and the sweep in
--     different zones (or across a DST change) differ by ≤ 1 day;
--   * now() is the TRANSACTION's start: a reader whose transaction began before the sweep's sees an
--     earlier window, but it overlaps a swept row only if it began more than 30 days earlier;
--   * a database clock stepped forward and back again by less than 30 days.
-- No lock is taken: no row the sweep can touch is one rf.take_seat's count or exemption can see,
-- whatever the interleaving, so there is nothing to serialise against 0019's per-tenant advisory
-- lock. Two overlapping sweeps are safe under READ COMMITTED (the second waits on the first's row
-- locks, then skips the rows it deleted) and report each row once (E-05g-30).
--
-- No argument, deliberately: a caller-chosen cutoff would let the maintenance role delete counted
-- rows and hand rotation budget back. The number lives here, beside its proof.
--
-- SECURITY DEFINER because seat_grants is RLS-FORCED with no policy (0019 §8): the function deletes
-- as the migration owner, which must be a superuser or hold BYPASSRLS — exactly what rf.take_seat's
-- INSERT into the same table already requires (E-05g-27 runs the sweep as rf_maintenance and fails
-- if it deletes nothing). Returns the rows removed, like rf.purge_ephemeral_auth.
create or replace function rf.sweep_seat_grants() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from seat_grants where granted_at < now() - interval '1 year 30 days';
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------- grants — rf_maintenance only
-- 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before this existed and
-- there are no default privileges on schema rf; PUBLIC's default EXECUTE is the one door to close.
-- The rf_api and platform-role revokes are belt and braces, as 0019 §8 does for the table.
revoke all on function rf.sweep_seat_grants() from public;
revoke all on function rf.sweep_seat_grants() from rf_api;
do $$ declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on function rf.sweep_seat_grants() from %I', r);
    end if;
  end loop;
end $$;
grant execute on function rf.sweep_seat_grants() to rf_maintenance;
