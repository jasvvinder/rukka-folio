-- 0021 — repairs to the hard caps of 0019 (M13-CAP1 review findings 3, 4, 6; ADR 2026-09-05g §2,
-- §6 🔒; ADR 2026-09-25 §5 🔒). 0019 is applied and is not edited: every change is here.
-- ⟦tests: E-05g-11, E-05g-12, E-05g-15⟧
--
-- CLAUDE.md rule 2: nothing here grants UPDATE or DELETE on anything, and `envelopes` is not
-- touched. Zero-knowledge: an index over (tenant_id, owner_user_id, type) and two function bodies
-- / ACLs — no envelope, blob, wrapped key or phone is read or copied.

-- ---------------------------------------------------------------- 1. the caps bind EITHER claim
-- CAP1 finding 3. 0019 §2 exempted "a write with NO claims" (the schema owner's: a migration, a
-- repair, the console) but tested only the user claim. The writers it exempts do not all need one:
-- rf.project_membership authorises through rf.require_record, which checks the DEVICE claim alone
-- (0005:191), so an rf_api transaction that set its own device and no user walked a member into
-- joined_pending_verification past the seat cap and the rotation cap. A caller is now anyone who
-- set either claim; only a transaction with both null — which no rf_api writer admits (E-05g-11)
-- — is the owner's. Same function, same ACL (0019 revoked it from PUBLIC; `create or replace`
-- keeps that).
create or replace function rf.caps_apply() returns boolean
language sql stable as $$ select rf.user_id() is not null or rf.device_id() is not null $$;

-- ---------------------------------------------------------------- 2. one personal book per person per tenant
-- CAP1 finding 4. rf.book_cap (0019 §7) never counts a `type = 'personal'` book, and nothing bound
-- how many a person could hold — so the label was a way around the business-book cap on every plan,
-- Free's 0 included (books_insert, 0005:334, asks only that a personal book's owner be the caller).
--
-- ⚠️ SPEC (reported, NOT ruled here): ADR 2026-09-25 §5 says "Each person's personal book is free and
-- never counted" and ADR 2026-09-05g §7 "the personal book" — singular, so one per person is
-- IMPLIED, but neither states the bound or its scope. The conservative reading taken here is one per
-- (tenant, owner): it closes the bypass in every tenant, and it refuses nothing the specs promise
-- (a person in two tenants keeps a personal book in each, which a per-owner-across-tenants rule
-- would forbid — that alternative is the owner's to choose). An ARCHIVED personal book still holds
-- the place, as an archived business book still counts in 0019 §7: archiving is not deleting.
--
-- An index, not a trigger: it holds under any isolation level and any race, for every writer
-- including the owner's. RLS WITH CHECK runs before the index is consulted, so a stranger meets
-- books_insert's refusal, never this index — no oracle over whether someone holds a personal book.
-- The violation is 23505 naming `books_one_personal_per_owner`; no edge route creates a book yet,
-- and the future book-create route maps it to a named refusal (reported).
--
-- Checked before writing (grepped, not assumed): seed.sql inserts no book; every fixture under
-- server/supabase/tests/rls gives each owner at most one personal book per tenant; no edge route
-- and no SQL function inserts into `books`. A hosted project that somehow holds two personal books
-- for one owner in one tenant fails here, by name, rather than having one of them chosen for it.
do $$
declare v_n int;
begin
  select count(*) into v_n from (
    select 1 from books where type = 'personal'
    group by tenant_id, owner_user_id having count(*) > 1) d;
  if v_n > 0 then
    raise exception 'personal_book_duplicates' using errcode = 'P0001',
      detail = format('%s (tenant, owner) pairs already hold more than one personal book', v_n),
      hint = 'resolve them by hand (retype, never delete) before applying 0021';
  end if;
end $$;
create unique index books_one_personal_per_owner on books (tenant_id, owner_user_id)
  where type = 'personal';

-- ---------------------------------------------------------------- 3. the device cap is not an rf_api power
-- CAP1 finding 6. 0019 §8 refused rf_api the plan resolver rf.tenant_plan because a tenant-id
-- resolver is a cross-tenant plan oracle — then re-pointed rf.device_cap at it and kept the EXECUTE
-- that 0005's blanket grant (and PUBLIC's default) gave it, so any rf_api caller, claims or none,
-- could ask any user's highest device cap and read the plan off the number. Its one caller is
-- rf.register_device (0009), SECURITY DEFINER, which runs it as the owner; the edge only matches the
-- `device_cap` refusal name (store_pg.ts) and never calls the function. Grepped: no other function,
-- policy or edge path calls rf.device_cap.
revoke all on function rf.device_cap(uuid) from public;
revoke all on function rf.device_cap(uuid) from rf_api, rf_maintenance;
