-- 0022 — a signed record belongs to a tenant its author is in, and a projection 06 reserves to an
-- admin finds one. Desk 58 (🔴 SECURITY, pre-existing in 0005, owner-approved 3 Oct 2026).
-- ⟦tests: E-06-82, E-06-83, E-06-84, E-06-85, E-06-86, E-06-87, E-06-88, E-06-89, E-06-90⟧
--
-- What HEAD allowed (each probed on a fresh RLS database before this file was written — the eight
-- tests above all failed on 0021, the failure text is in the lane report M13-SEC58):
--   * `signed_records_insert` (0005:404) checked `rf.is_certified()` and `author_device` only, so a
--     certified device of tenant A could file a record of any kind IN tenant B (E-06-82);
--   * every projector authorises through `rf.require_record` (0005:191) — "a record of the
--     caller's device exists in that tenant" — and `rf.project_membership` (0005:200) checked
--     nothing else, so A walked itself into B at joined_pending_verification (E-06-83), set an
--     active member of B to `removed` and deleted their book_roles (E-06-84), and — with 0019 —
--     took B's seat when B had room and read `seat_cap` when it had none (E-06-85);
--   * the edge did NOT stop it on the real store: `applyRecord`'s founder bootstrap
--     (_shared/records.ts:147) asks `membershipCount`, which counts the rows the CALLER can see
--     (_shared/store_pg.ts membershipCount) — zero, for a stranger — so POST /sync-meta/records
--     answered `acked` (E-06-86). Desk 58's "the edge blocks it" held only on MemStore;
--   * `rf.project_book_role` (0005:211) and `rf.project_device_status` (0005:227) carried the same
--     missing check: any author of a record in B granted or deleted B's book roles (E-06-88), and
--     any author of a record in its OWN tenant revoked — or set `certified` on — any device in the
--     system, passing round rf.certify_device's certificate check (E-06-89).
--
-- The lines enforced here:
--   * ADR 2026-09-05d §2 🔒 / 03 §2.5 🔒 — RLS on every table, certified devices only; the API role
--     is treated as hostile, so the check lives in the database and holds without the edge;
--   * 06 §7 🔒 — "Every transition and every role/limit/designation change is a signed record
--     authored on a certified admin device (ADR 2026-09-05b §1)";
--   * 06 §1.0 🔒 — capability is "Granted, changed and revoked only by an admin of that book (its
--     creator is the first admin)"; "Invite / remove members · roles · limits · designations —
--     admin only";
--   * 06 §5 🔒 — the founder has nobody to verify them (0006's membership_guard exception), and a
--     new device "notifies … every tenant" the user belongs to (a `device_added` record);
--   * 06 §6 🔒 — "Revoke: any certified device of the same user, k guardians, or support";
--   * ADR 2026-09-05g §6 🔒 — seats are counted for the tenant's own members: a stranger reaching
--     0019's seat trigger both took a seat and learned the plan was full. Every refusal below fires
--     BEFORE the write that would fire the trigger, and is the same whether the tenant is full.
--
-- The narrowest owners of the check, one each:
--   §1 the record: `signed_records_insert` gains rf.may_file_record(tenant, kind) — the author holds
--      a live membership in the record's tenant, or the tenant exists with no member yet and the
--      record is the founder's membership_status. Since every projector demands a record of the
--      caller in the tenant it writes (rf.require_record), this alone takes the cross-tenant reach
--      out of every projector that derives its tenant from its target (membership, book role,
--      verification event, invite).
--   §2–§4 the projectors whose target is not bound by the record, or whose author 06 restricts:
--      rf.project_membership (admin or founder), rf.project_book_role (admin of that book, or its
--      creator first), rf.project_device_status (its user or their guardian, the subject in the
--      record's tenant, `revoked` only). rf.project_verification_event (0006/0008) and
--      rf.create_invite (0006) already check their author and are untouched.
--   §5 the search path every one of these checks reads under (E-06-90). rf_api holds TEMPORARY on
--      the database (PUBLIC's default; no migration revokes it), and Postgres searches the
--      session's temp schema FIRST unless a function's search_path lists pg_temp — so under
--      `search_path = public` a temp table named `memberships` (or devices, books, book_roles,
--      signed_records, guardian_set_members), created and filled in the caller's own session,
--      is what a SECURITY DEFINER check reads (Postgres docs, "Writing SECURITY DEFINER Functions
--      Safely"). Each function this file writes pins `public, pg_temp`, and so do the four helpers
--      its checks stand on — rf.is_certified, rf.active_in_tenant, rf.is_tenant_admin,
--      rf.require_record (0005) — or the check would be only as unflippable as them. No other
--      function is touched: the same pin on the rest of 0003–0021's SECURITY DEFINER functions is an
--      owner item (lane report M13-SEC58), not this file's.
-- rf.require_record itself is unchanged: every caller now checks its own author after it, and its
-- `no_record` stays the first answer an outsider meets — before any lookup of the target — so the
-- refusal carries nothing about the target tenant (E-06-85).
--
-- ⚠️ SPEC (reported in the lane's `open`; the readings the docs do not settle):
--   (a) WHO MAY FILE: a member at `active` or `joined_pending_verification`. 06 §5 sends a new
--       device's `device_added` to "every tenant" the user belongs to, and a pending member belongs
--       (06 §7: they have an account, device and UMK). `invited` (not yet accepted), `blocked`
--       (after a failed ceremony — possibly not the person) and `removed` may not. A pending
--       member's records reach no MEMBERSHIP or BOOK-ROLE projection (§2 and §3 need an admin or
--       an active member); the rest of what they can file (device_added, designation,
--       key_rotation) is inert here and read only by the tenant's active members, who verify it
--       (ADR 2026-09-05b §1). The one projection a pending member CAN reach is §4's revocation,
--       and only as the device's own user or as a guardian of a subject who is in the tenant:
--       that authority is 06 §6's (the user's own devices; the guardians the subject chose), not
--       the author's standing in the tenant, which §4 uses only as the place the record is filed —
--       so §4 does not ask for `active`. Whether a pending guardian should wait for verification
--       is for the owner (lane report M13-SEC58).
--   (b) THE FOUNDER IS FIRST-COME: `tenants` (0001:59) records no creator, so "the tenant has no
--       member yet" is the only test the database can make. Narrowed as far as it goes: only a
--       membership_status may be filed into a memberless tenant, only by a certified device, and it
--       projects only the caller's OWN membership at `active` — the one state 0006's guard grants a
--       founder. The edge's bootstrap (_shared/records.ts:147) admits any status; this refuses all
--       but `active`. A per-tenant lock makes two racing founders take turns (the second meets a
--       member and is refused). A creator column would close it fully — a 03 §2.1 change.
--   (c) BOOK ROLES are an admin OF THAT BOOK's (06 §1.0 🔒, quoted above). The edge asks
--       `isTenantAdmin` — admin of ANY book in the tenant (_shared/records.ts:181) — so a tenant
--       admin who does not hold `admin` on the book is now refused by the database, and the edge
--       answers `rejected:unauthorized`, check `not_admin`. Docs win; the edge should ask the same.
--   (d) A ROLE-LESS BOOK's first role is its creator's: `books` records no creator either, so the
--       first role on a book with none is the CALLER's own `admin` role, taken by an active member
--       (a business book) or by the owner (a personal book) — the edge's bootstrap
--       (_shared/records.ts:178-180) narrowed to "its creator is the first admin". A book that
--       already holds envelopes is not being created — its roles were all removed — so it is not
--       claimable this way (an envelope needs a role to be pushed, envelopes_insert 0005:394, so a
--       new book has none). Serialised per book like (b).
--   (e) DEVICE REVOCATION: the database bounds WHO (the device's own user, or a guardian of that
--       user in any share_set_version) and WHERE (that user holds a membership other than `removed`
--       in the record's tenant). The k-of-n count stays the edge's and the client's (ADR 2026-09-06
--       §3) — the database cannot recount it and does not try. A guardian who shares no tenant with
--       the subject can no longer complete a revocation through this projector (their record must
--       be filed in a tenant the subject is in). The projection now only ever revokes: un-revoking
--       or certifying is rf.certify_device's, which verifies a certificate (ADR 2026-09-05d §2).
--
-- CLAUDE.md rule 2: nothing here grants UPDATE or DELETE on anything; `envelopes` is not touched.
-- Zero-knowledge: membership, role, device and guardian rows, and in §3 whether a book holds any
-- envelope row at all (by its routing column) — no blob, wrapped key or phone hash is read, and
-- nothing is logged. `create or replace` keeps each existing
-- function's ACL (0005:295's EXECUTE to rf_api); the one new helper is revoked from PUBLIC and
-- granted to rf_api alone, which a policy needs to evaluate it.

-- ---------------------------------------------------------------- §1 a record is filed in the author's tenant
-- SECURITY DEFINER: "the tenant has no member" must see every membership row, which
-- memberships_select (0005:328) hides from a non-member. It answers one bit about the caller
-- (am I in it?) and one about a tenant whose id the caller already holds (is it memberless?); a
-- tenant that does not exist answers like one with members, so the insert's refusal is the same
-- 42501 either way (E-06-82) rather than 0003's foreign-key error naming the gap.
create or replace function rf.may_file_record(p_tenant uuid, p_kind text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select rf.is_certified() and (
    exists (select 1 from memberships m
             where m.tenant_id = p_tenant and m.user_id = rf.user_id()
               and m.status in ('active', 'joined_pending_verification'))
    or (p_kind = 'membership_status'
        and exists (select 1 from tenants t where t.id = p_tenant)
        and not exists (select 1 from memberships m where m.tenant_id = p_tenant)))
$$;
revoke all on function rf.may_file_record(uuid, text) from public;
grant execute on function rf.may_file_record(uuid, text) to rf_api;

alter policy signed_records_insert on signed_records
  with check (rf.is_certified() and author_device = rf.device_id()
              and rf.may_file_record(tenant_id, kind));

-- ---------------------------------------------------------------- §2 membership: an admin, or the founder
-- 0005's body after the authorisation; the write is unchanged.
create or replace function rf.project_membership(p_record uuid, p_tenant uuid, p_user uuid, p_status text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare ok boolean := false;
begin
  perform rf.require_record(p_record, p_tenant);
  if rf.is_tenant_admin(p_tenant) then
    ok := true;
  elsif p_status = 'active' and p_user = rf.user_id() and rf.is_certified() then
    -- the founder (06 §5): the same per-tenant lock 0019's seat trigger takes, so a second founder
    -- waits for the first and then sees a member (each statement takes a fresh snapshot).
    perform pg_advisory_xact_lock(hashtextextended('rf.seat_cap:' || p_tenant::text, 0));
    ok := not exists (select 1 from memberships m where m.tenant_id = p_tenant);
  end if;
  if not ok then
    raise exception 'not_admin' using errcode = '42501',
      detail = 'a membership changes only on a record from a certified admin device of the tenant; the founder''s own first membership is the one exception (06 §7, 06 §5)';
  end if;
  insert into memberships (tenant_id, user_id, status, source_record_id) values (p_tenant, p_user, p_status, p_record)
  on conflict (tenant_id, user_id) do update set status = excluded.status, source_record_id = p_record;
  if p_status = 'removed' then
    delete from book_roles r using books b where b.id = r.book_id and b.tenant_id = p_tenant and r.user_id = p_user;
  end if;
end $$;

-- ---------------------------------------------------------------- §3 book roles: an admin of that book, or its creator first
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
      ok := not exists (select 1 from book_roles r where r.book_id = p_book)
        and not exists (select 1 from envelopes e where e.book_id = p_book);
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

-- ---------------------------------------------------------------- §4 device status: revoke only, by its user or their guardian
create or replace function rf.project_device_status(p_record uuid, p_tenant uuid, p_device uuid, p_status text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_owner uuid;
begin
  perform rf.require_record(p_record, p_tenant);
  if p_status is distinct from 'revoked' then
    raise exception 'revoke_only' using errcode = '23514',
      detail = 'a device record revokes; certification is rf.certify_device''s, which verifies a certificate (ADR 2026-09-05d §2)';
  end if;
  select d.user_id into v_owner from devices d where d.id = p_device;
  -- One refusal for every miss — no device, not in this tenant, not yours to revoke — so the answer
  -- says nothing about a device the caller has no business with.
  if v_owner is null or not rf.is_certified()
     or not exists (select 1 from memberships m
                     where m.tenant_id = p_tenant and m.user_id = v_owner and m.status <> 'removed')
     or not (v_owner = rf.user_id()
             or exists (select 1 from guardian_set_members g
                         where g.subject_user_id = v_owner and g.guardian_user_id = rf.user_id())) then
    raise exception 'not_revoker' using errcode = '42501',
      detail = 'a device is revoked by its own user or their guardians, on a record of a tenant that user is in (06 §6)';
  end if;
  update devices set status = p_status, revoked_at = case when p_status = 'revoked' then now() else revoked_at end
  where id = p_device;
  if p_status = 'revoked' then
    update wrapped_keys set revoked_at = now() where device_id = p_device and revoked_at is null;
  end if;
end $$;

-- ---------------------------------------------------------------- §5 the helpers these checks stand on read public first
-- The four functions above pin `public, pg_temp` in their own definitions; these are the 0005
-- helpers every check above calls (and every RLS policy that calls them gains the same pin). The
-- bodies, owners and grants are unchanged — ALTER … SET touches only proconfig (E-06-90).
alter function rf.is_certified() set search_path = public, pg_temp;
alter function rf.active_in_tenant(uuid) set search_path = public, pg_temp;
alter function rf.is_tenant_admin(uuid) set search_path = public, pg_temp;
alter function rf.require_record(uuid, uuid) set search_path = public, pg_temp;
