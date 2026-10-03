-- 0024 — every function in schema rf reads public before the caller's temp schema (desk PGT1).
-- 🔴 SECURITY, owner-approved 3 Oct 2026; the gap is pre-existing since 0005. Tests E-03-81 … E-03-86
-- (tests/rls/search_path_pg_temp.test.ts). Spec: ADR 2026-09-05d §2 (rf_api is hostile; RLS holds
-- without the edge), 03 §2.5 🔒 (RLS on every table), ADR 2026-09-05b §7 (throttle and quota are
-- the server's only new powers).
--
-- The gap
--   rf_api holds TEMPORARY on the database through PUBLIC — Postgres' default, which no migration
--   revokes (probe: has_database_privilege('rf_api', current_database(), 'TEMP') = true). Postgres
--   searches the session's temp schema FIRST for relation and type names unless the path names
--   pg_temp explicitly (CREATE FUNCTION reference, "Writing SECURITY DEFINER Functions Safely":
--   write pg_temp last). Probe on HEAD, as rf_api, after one `create temp table`:
--   current_schemas(true) = {pg_temp_N, pg_catalog, public}. So under `search_path = public` — what
--   62 SECURITY DEFINER functions here pinned — a temp table named books, book_roles, memberships,
--   devices, signed_records, push_rate, book_usage … created and filled in the caller's own session
--   is what the function reads or WRITES. The 20 SECURITY INVOKER functions pinned nothing, so they
--   run under the caller's own path, `set search_path = pg_temp, public` included. Measured on HEAD
--   by E-03-81 … 86: rf.book_tenant names a fake tenant, rf.book_role makes a stranger `admin` of
--   another tenant's book — envelopes_select then returns that book's envelopes and
--   envelopes_insert accepts a push into it — rf.shares_tenant / rf.device_visible say yes to a
--   stranger, invite_guard accepts an invite on a non-`invite` record, recovery_sheet_guard's flood
--   limit and guardian_set_member_guard's n are read from the caller's rows, rf.push_rate_check
--   reads a zeroed minute, and envelopes_usage bumps a temp book_usage instead of the quota.
--   0022 §5 already pinned `public, pg_temp` on its four functions and on rf.is_certified,
--   rf.active_in_tenant, rf.is_tenant_admin, rf.require_record; 0022 is not touched.
--
-- The fix
--   One loop over every routine in schema rf (prokind 'f' — and 'p', of which there are none today,
--   so a procedure added later is covered by the same rule; extension members excluded, there are
--   none in rf) runs `ALTER FUNCTION|PROCEDURE <regprocedure> SET search_path = public, pg_temp`.
--   ALTER … SET writes proconfig only: body, owner, grants, volatility, SECURITY mode unchanged
--   (probe: an md5 over oid, prosrc, proacl, proowner, prosecdef, provolatile, proleakproof,
--   proparallel of all 82 routines is identical before and after). Invoker functions get the pin
--   too: several guards read tables unqualified (memberships, invites, signed_records,
--   verification_events, guardian_sets, guardian_set_members, ceremony_sessions, recovery_sheets),
--   and one uniform rule is what E-03-84's catalogue tripwire can hold every future migration to.
--   A function's SET clause restores only the variables it names on exit, so rf.set_claims'
--   set_config('request.*', …, true) still reaches the rest of the transaction (E-03-85).
--
-- Why not `pg_catalog, public, pg_temp`
--   pg_catalog is searched first whenever the path does not name it. Probe on this database:
--   `set search_path = public, pg_temp` → current_schemas(true) = {pg_catalog, public, pg_temp_N},
--   byte-for-byte what `pg_catalog, public, pg_temp` gives; only `public, pg_catalog, pg_temp` would
--   differ (public before the built-ins — worse). Naming it adds nothing, so the pin keeps 0022 §5's
--   exact form and E-03-84 checks one shape. No rf body needs a schema other than public: the only
--   call into a function that also exists in public is gen_random_uuid(), which resolves to the
--   pg_catalog built-in (PG ≥ 13) ahead of pgcrypto's, here and where pgcrypto lives in `extensions`.
--
-- Not done here (owner items, lane report M13-PGT1): revoking TEMPORARY on the database from PUBLIC
-- (it cannot be revoked from rf_api alone, and on hosted Supabase PUBLIC covers platform roles);
-- confirming no untrusted role holds CREATE on schema public on the hosted project (the first entry
-- of every pinned path). No grant changes; envelopes untouched.
--
-- Any later `create or replace function rf.…` REPLACES proconfig with what its own definition says:
-- it must carry `set search_path = public, pg_temp` itself, or E-03-84 fails.

do $$
declare
  r record;
  n int := 0;
  missed text;
begin
  for r in
    select p.oid::regprocedure as sig, p.prokind
      from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'rf'
       and p.prokind in ('f', 'p')
       and not exists (select 1 from pg_depend d
                        where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
     order by p.oid
  loop
    execute format('alter %s %s set search_path = public, pg_temp',
                   case r.prokind when 'p' then 'procedure' else 'function' end, r.sig);
    n := n + 1;
  end loop;

  -- self-check: nothing in rf is left reading the caller's temp schema first
  select string_agg(p.oid::regprocedure::text, ', ') into missed
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'rf' and p.prokind in ('f', 'p')
     and not ('search_path=public, pg_temp' = any (coalesce(p.proconfig, '{}')));
  if missed is not null then
    raise exception '0024: rf routines still without search_path = public, pg_temp: %', missed;
  end if;
  raise notice '0024: search_path = public, pg_temp pinned on % rf routines', n;
end $$;
