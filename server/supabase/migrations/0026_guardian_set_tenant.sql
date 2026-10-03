-- 0026 — a guardian set belongs to a tenant; guardian revocations are filed and counted there.
-- ADR 2026-10-03b 🔒 (owner-ruled 3 Oct 2026, desk 89), amending ADR 2026-09-06 §3 (which approvals
-- count) and narrowing 0022 §3 (the book bootstrap).
-- ⟦tests: E-03b-1, E-03b-2, E-03b-3, E-03b-4, E-03b-5⟧
--   functions/_tests/edge_record_authority.test.ts (MemStore) and
--   tests/rls/edge_record_authority.test.ts (PgStore on rf_api) run the same scenarios
--   (functions/_tests/record_authority_world.ts); tests/rls/guardian_set_tenant.test.ts holds the
--   database-only arms (write-once, the guards without the route, the count over rows RLS hides,
--   the grants). A pre-0026 set is E-03b-2's last arm.
--
-- What EDGE83 left (desk 89), and what this file does about each:
--   §1 `guardian_sets` recorded no tenant (0002:51-73), so "the tenant the subject verified every
--      guardian in" did not exist server-side. It is a column now, written once with the version.
--      A NEW version must carry it; the publisher is `active` there and every guardian of the
--      version holds a membership there other than `removed`. The checks live in 0010's two guards
--      (extended, not bypassed), so they hold for every inserter, the schema owner included, and the
--      guard's UPDATE/DELETE refusal is what makes the column write-once. Rows written before this
--      file keep `tenant_id` null: they still recover (04 §7.3 does not read the column) but count
--      nothing toward a revocation until the next re-split (ADR §1; no pilot data exists).
--   §2 0022 (e) left the k-of-n COUNT to the edge, which could read only the approvals RLS showed
--      the caller (signed_records_select). The database now counts, over every row, as a SECURITY
--      DEFINER function — and rf.project_device_status's guardian arm projects only on that count.
--      An approval counts iff (ADR 2026-10-03b §2, ADR 2026-09-06 §3 otherwise unchanged):
--        * it is a `device_revocation` naming the device and its owner as subject;
--        * its author's user is a guardian at the share_set_version it names;
--        * it is FILED in that version's tenant_id (a version with null tenant counts nothing);
--        * the subject holds a membership there other than `removed`.
--      Distinct authors (each at the lowest seq they filed); the threshold is the k of the EARLIEST
--      version among the counted records; the cut-off is the seq of the k-th counted author.
--   §3 a guardian still `joined_pending_verification` in the set's tenant may file an approval that
--      counts (ADR §3), but cannot see the subject's membership row (memberships_select), so the
--      edge refused it as `not_revoker`. rf.guardian_may_revoke answers it, SECURITY DEFINER.
--   §4 rf.project_book_role's role-less bootstrap read `envelopes` (0022 (d)): a book whose
--      envelopes were all deleted (03 §2, an erased user's personal book; or a cold-archive offload,
--      03 open 4) looked new. It reads book_usage.envelope_count now, a counter that only goes up.
--
-- Conventions kept from 0022/0024: every function pins `set search_path = public, pg_temp`
-- (E-03-84); every refusal the projection raises is the one `not_revoker`, whatever the miss (no
-- device, not yours, not counted, not yet k) — so it says nothing about a device the caller has no
-- business with; each new function is revoked from PUBLIC, and only the two the edge asks are
-- granted, to rf_api alone. The two guards stay SECURITY INVOKER: every check they add is an
-- `exists` over memberships, which a row hidden by RLS can only make FALSE — a narrower refusal,
-- never a wider grant — and the publisher they serve is active in the set's tenant, so
-- memberships_select (0005:328) shows it every membership row there anyway.
--
-- CLAUDE.md rule 2: no UPDATE or DELETE grant is added on anything; `envelopes` is not touched
-- (only book_usage, its trigger-kept counter, is READ). Zero-knowledge: membership, guardian, device
-- and record-routing rows, and three plaintext ids of a device_revocation payload (03 §4: signed
-- record payloads are plaintext by design) — no blob, wrapped key or phone hash is read, nothing is
-- logged.

-- ---------------------------------------------------------------- §1 the set's tenant
alter table guardian_sets add column tenant_id uuid null references tenants(id);
comment on column guardian_sets.tenant_id is
  'ADR 2026-10-03b §1: the tenant the set was set up in (S11.1) — whose members the guardians were '
  'chosen from and in which the subject verified each of them. Written once with the version '
  '(rf.guardian_set_guard refuses every UPDATE). Null only on a version published before 0026: it '
  'recovers, but counts no device_revocation approval (rf.revocation_approvals) until a re-split.';

-- 0010's guard, with ADR §1 between the quorum and the version checks. Everything else is
-- unchanged, refusal names included.
create or replace function rf.guardian_set_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
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
  -- One refusal whether the tenant is missing, unknown, or one the publisher is not active in —
  -- and it fires before the foreign key would name an unknown tenant.
  if new.tenant_id is null or not exists (
       select 1 from memberships m
        where m.tenant_id = new.tenant_id and m.user_id = new.subject_user_id
          and m.status = 'active') then
    raise exception 'guardian_set_tenant' using errcode = '42501',
      detail = 'a guardian set names the tenant it was set up in, and its publisher is active there (ADR 2026-10-03b §1)';
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

-- 0010's member guard, with ADR §1 after the size check (so a full set still answers
-- `guardian_set_full`, E-03-83). A version with no tenant takes no new member.
create or replace function rf.guardian_set_member_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
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
  if g.tenant_id is null or not exists (
       select 1 from memberships m
        where m.tenant_id = g.tenant_id and m.user_id = new.guardian_user_id
          and m.status <> 'removed') then
    raise exception 'guardian_not_in_tenant' using errcode = '42501',
      detail = 'every guardian of a version holds a membership other than removed in the set''s tenant (ADR 2026-10-03b §1)';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------- §2 the count, over every row
-- Every COUNTED approval of one device. Internal: reads every signed record, membership and guardian
-- row, so it is never granted to rf_api; the two functions below are its only callers.
-- The payload is read defensively: ids compared as lower-case text (a payload id that is not a uuid
-- simply matches nothing), and share_set_version only when it is a JSON number — a CASE, so a string
-- there is never cast and never aborts the caller's transaction.
create or replace function rf.revocation_approvals(p_device uuid)
returns table (record_id uuid, author_user uuid, share_set_version int, k int, seq bigint)
language sql stable security definer set search_path = public, pg_temp as $$
  select r.id, a.user_id, s.share_set_version, s.k, r.seq
    from devices d
    join signed_records r
      on r.kind = 'device_revocation'
     and lower(r.payload_json->>'revoked_device_id') = d.id::text
     and lower(r.payload_json->>'subject_user_id') = d.user_id::text
    join devices a on a.id = r.author_device
    join guardian_sets s
      on s.subject_user_id = d.user_id
     and s.share_set_version = case when jsonb_typeof(r.payload_json->'share_set_version') = 'number'
                                    then (r.payload_json->'share_set_version')::numeric end
     and s.tenant_id = r.tenant_id
    join guardian_set_members g
      on g.subject_user_id = s.subject_user_id
     and g.share_set_version = s.share_set_version
     and g.guardian_user_id = a.user_id
   where d.id = p_device
     and exists (select 1 from memberships m
                  where m.tenant_id = r.tenant_id and m.user_id = d.user_id
                    and m.status <> 'removed')
$$;

-- Earliest-k over the counted approvals (ADR 2026-09-06 §3), counted as the subject's own devices
-- count them (ADR 2026-10-03b §2: "the server and the subject's own devices count the same set";
-- sync_engine revocation.dart countRevocation). A counted RECORD is one per distinct author: that
-- author's lowest-seq approval among those that pass revocation_approvals. A later record by an
-- author already counted is not a counted record — it moves neither the cut-off nor the k (desk 89
-- review, finding 3: a stale device naming an older version with a lower k must not lower the bar
-- the author's first record set). k is the k of the earliest version among the counted records; the
-- cut-off is the k-th counted record's seq, null until k distinct authors are counted. With no
-- counted approval: (0, null, null).
create or replace function rf.revocation_tally(p_device uuid)
returns table (approvers int, k int, effective_seq bigint)
language sql stable security definer set search_path = public, pg_temp as $$
  with a as (select * from rf.revocation_approvals(p_device)),
       per as (select distinct on (a.author_user) a.author_user, a.share_set_version, a.k, a.seq
                 from a order by a.author_user, a.seq),
       thr as (select per.k from per order by per.share_set_version, per.seq limit 1),
       n as (select count(*)::int as c from per)
  select n.c,
         thr.k,
         case when thr.k is not null and n.c >= thr.k
              then (select per.seq from per order by per.seq offset thr.k - 1 limit 1) end
    from n left join thr on true
$$;

-- The count as the EDGE may read it (ADR §2: "the edge asks it, never the rows the caller can
-- see"): only for the device's own user and for a guardian of that user (any version). Anyone else
-- reads (0, null, null) — the same row a device with no approval gives, and the same whether the
-- device exists — so it is no oracle.
--
-- Serialised per device (desk 89 review, finding 1). Two guardians filing the approvals that reach k
-- at the same moment would otherwise each count under READ COMMITTED without the other's
-- uncommitted row, each read "1 of 2", and commit k counted approvals onto a device nothing ever
-- projects again (the edge projects only inside the completing request). The lock is transaction-
-- scoped, so it is held until the caller's record — already inserted — commits; the next counter
-- waits for that commit and then counts in a FRESH snapshot. That is why this function is VOLATILE,
-- not STABLE: a volatile plpgsql function takes a new snapshot for each statement, so the RETURN
-- QUERY after the lock sees every approval committed while it waited (a stable one would keep the
-- calling query's snapshot, taken before the wait). Taken only on the gated arm: the lock is the
-- owner's and the guardians', and anyone else's call reads the empty count and blocks nothing.
-- rf.project_device_status takes the same lock (re-entrant within one transaction).
create or replace function rf.revocation_count(p_device uuid)
returns table (approvers int, k int, effective_seq bigint)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
begin
  if rf.is_certified() and exists (
       select 1 from devices d
        where d.id = p_device
          and (d.user_id = rf.user_id()
               or exists (select 1 from guardian_set_members g
                           where g.subject_user_id = d.user_id
                             and g.guardian_user_id = rf.user_id()))) then
    perform pg_advisory_xact_lock(hashtextextended('rf.device_revocation:' || p_device::text, 0));
    return query select t.approvers, t.k, t.effective_seq from rf.revocation_tally(p_device) t;
  else
    return query select 0, null::int, null::bigint;
  end if;
end $$;

-- ---------------------------------------------------------------- §3 may this guardian's approval count
-- ADR §3: the edge's question for a guardian's device_revocation filed in p_tenant naming
-- p_version — would it be counted? The caller may file in p_tenant (rf.may_file_record: certified,
-- active or joined_pending_verification there), is a guardian of the device's owner at p_version,
-- that version was set up in p_tenant, and the owner holds a membership there other than removed.
-- One bit, false for every miss; asked only about a tenant the caller itself belongs to, where it
-- learns nothing about the subject a fellow member could not.
create or replace function rf.guardian_may_revoke(p_device uuid, p_tenant uuid, p_version int)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select rf.may_file_record(p_tenant, 'device_revocation') and exists (
    select 1
      from devices d
      join guardian_sets s
        on s.subject_user_id = d.user_id and s.share_set_version = p_version
       and s.tenant_id = p_tenant
      join guardian_set_members g
        on g.subject_user_id = s.subject_user_id and g.share_set_version = s.share_set_version
       and g.guardian_user_id = rf.user_id()
     where d.id = p_device
       and exists (select 1 from memberships m
                    where m.tenant_id = p_tenant and m.user_id = d.user_id
                      and m.status <> 'removed'))
$$;

-- ---------------------------------------------------------------- §2 the projection projects on the count
-- 0022 §4's function. The owner's arm is unchanged. The guardian arm no longer trusts the caller's
-- count: the caller's OWN record (p_record, already bound to its device and p_tenant by
-- rf.require_record) must be a counted approval of p_device, the caller must still be able to file
-- in p_tenant (a guardian since removed from the set's tenant cannot trigger it), and the count over
-- every approval must have reached k.
create or replace function rf.project_device_status(p_record uuid, p_tenant uuid, p_device uuid, p_status text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_owner uuid; ok boolean := false;
begin
  perform rf.require_record(p_record, p_tenant);
  if p_status is distinct from 'revoked' then
    raise exception 'revoke_only' using errcode = '23514',
      detail = 'a device record revokes; certification is rf.certify_device''s, which verifies a certificate (ADR 2026-09-05d §2)';
  end if;
  -- rf.revocation_count's lock (desk 89 review, finding 1), taken before anything is read: the
  -- statements below run in snapshots taken after it is granted, so a guardian's count here includes
  -- every approval committed by a concurrent filer of the same device. Taken on the owner's arm too,
  -- so an owner's and a guardian's revocation of one device queue in one order (no lock-order cycle
  -- on the devices row).
  perform pg_advisory_xact_lock(hashtextextended('rf.device_revocation:' || p_device::text, 0));
  select d.user_id into v_owner from devices d where d.id = p_device;
  if v_owner is not null and rf.is_certified() then
    if v_owner = rf.user_id() then
      -- 06 §6 "any certified device of the same user", on a record of a tenant that user is in.
      ok := exists (select 1 from memberships m
                     where m.tenant_id = p_tenant and m.user_id = v_owner and m.status <> 'removed');
    else
      -- 06 §6 "k guardians", counted here (ADR 2026-10-03b §2).
      ok := rf.may_file_record(p_tenant, 'device_revocation')
        and exists (select 1 from rf.revocation_approvals(p_device) a where a.record_id = p_record)
        and (select t.effective_seq from rf.revocation_tally(p_device) t) is not null;
    end if;
  end if;
  -- One refusal for every miss — no device, not yours, not counted, not yet k.
  if not ok then
    raise exception 'not_revoker' using errcode = '42501',
      detail = 'a device is revoked by its own user, or by k of their guardians on approvals filed in the guardian set''s tenant (06 §6, ADR 2026-10-03b §2)';
  end if;
  update devices set status = p_status, revoked_at = case when p_status = 'revoked' then now() else revoked_at end
  where id = p_device;
  if p_status = 'revoked' then
    update wrapped_keys set revoked_at = now() where device_id = p_device and revoked_at is null;
  end if;
end $$;

-- ---------------------------------------------------------------- §4 a book that ever held an envelope is never re-claimed
-- 0022 §3's function; the one change is the last conjunct of the bootstrap: book_usage, not envelopes.
create or replace function rf.project_book_role(p_record uuid, p_book uuid, p_user uuid, p_role text, p_limit bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare t uuid; v_type text; v_owner uuid; ok boolean := false;
begin
  select b.tenant_id, b.type, b.owner_user_id into t, v_type, v_owner from books b where b.id = p_book;
  perform rf.require_record(p_record, t);
  if rf.active_in_tenant(t) then
    if exists (select 1 from book_roles r
                where r.book_id = p_book and r.user_id = rf.user_id() and r.role = 'admin') then
      ok := true;
    elsif p_user = rf.user_id() and p_role = 'admin'
          and (v_type <> 'personal' or v_owner = rf.user_id()) then
      perform pg_advisory_xact_lock(hashtextextended('rf.book_role:' || p_book::text, 0));
      -- ADR 2026-10-03b §5: never held an envelope — book_usage only counts up (0003's trigger), so
      -- a book whose envelopes were deleted is still not new.
      ok := not exists (select 1 from book_roles r where r.book_id = p_book)
        and coalesce((select u.envelope_count from book_usage u where u.book_id = p_book), 0) = 0;
    end if;
  end if;
  if not ok then
    raise exception 'not_admin' using errcode = '42501',
      detail = 'a book role is granted, changed and revoked only by an admin of that book; its creator is the first (06 §1.0)';
  end if;
  if p_role is null then
    delete from book_roles where book_id = p_book and user_id = p_user;
  else
    insert into book_roles (book_id, user_id, role, auto_post_limit_paise, source_record_id)
    values (p_book, p_user, p_role, p_limit, p_record)
    on conflict (book_id, user_id) do update set role = excluded.role,
      auto_post_limit_paise = excluded.auto_post_limit_paise, source_record_id = p_record;
  end if;
end $$;

-- ---------------------------------------------------------------- the count's index
-- rf.revocation_approvals looks a device's approvals up by the payload id it compares.
create index signed_records_revocation_idx on signed_records (lower(payload_json->>'revoked_device_id'))
  where kind = 'device_revocation';

-- ---------------------------------------------------------------- grants
-- `create or replace` kept the ACLs of the four functions that existed. The new ones: internal
-- helpers to nobody but their owner; the edge's two questions to rf_api alone.
revoke all on function rf.revocation_approvals(uuid), rf.revocation_tally(uuid) from public, rf_api;
revoke all on function rf.revocation_count(uuid), rf.guardian_may_revoke(uuid, uuid, int) from public;
grant execute on function rf.revocation_count(uuid), rf.guardian_may_revoke(uuid, uuid, int) to rf_api;
