-- 0027 — the subject's membership is judged at each approval's own seq, not now.
-- ADR 2026-10-03b §6 🔒 (owner-ruled 3 Oct 2026, clearing desk 97). It settles WHEN 0026 reads §2's
-- "the subject holds a membership there other than removed": at the moment the approval is filed, at
-- its own `seq`.
-- ⟦tests: E-03b-7, E-03b-9, E-03b-10, E-03b-11, E-03b-12, E-03b-13⟧
--   functions/_tests/edge_record_authority.test.ts (MemStore) and
--   tests/rls/edge_record_authority.test.ts (PgStore on rf_api) run E-03b-7, E-03b-9, E-03b-11 and
--   E-03b-12 as the same scenarios (functions/_tests/record_authority_world.ts).
--   tests/rls/revocation_at_seq.test.ts holds the database-only arms, E-03b-10 and E-03b-13: the rule
--   over rows no caller can see, every writer of a membership row (the expiry sweep, the seat cap's
--   refusal and the record's later application), the log's grants and append-only guard, and the
--   helpers' catalogue entries.
--
-- What 0026 did, and where it parted from the subject's own devices:
--   rf.revocation_approvals (0026 §2) and rf.guardian_may_revoke (0026 §3) asked whether the subject
--   holds a membership other than `removed` in the set's tenant NOW, from the memberships row at
--   count time. The client (sync_engine revocation.dart countRevocation, D-03b-5/7/8, the reference
--   ADR §6 names) asks it at each approval's seq. The two part whenever the subject's membership
--   changes between approvals:
--     * a later removal un-counted approvals already filed, so the server's cut-off could move LATER.
--       ADR 2026-09-06 §3 says it only moves earlier;
--     * an approval refused `not_revoker` while the subject was removed is still stored, because it
--       is a signed fact. After a re-admission it counted, so the server could revoke at a cut-off no
--       client computes.
--
-- §1 membership_facts: the history of every memberships row, stamped when the row changed.
--    A memberships row keeps only its current status, so "as of seq Q" needs a history. An AFTER
--    trigger on memberships logs every insert, every change of status and every delete, in the
--    transaction that writes the row, at a FRESH value of store_seq (the sequence envelopes and
--    signed records share, ADR 2026-09-05b §5). The value is taken at the moment the row changes, so
--    it is above every seq already handed out: a change can never be dated under an approval already
--    filed.
--    Why the moment of the change, and not the applying record's seq (desk 97 review, finding 1): a
--    record can be applied long after it was filed. sync-meta re-applies a stored record that was
--    never applied when it is re-sent (`rec = stored`, the seat cap's refusal among them), and a
--    hostile rf_api (ADR 2026-09-05d §2) can call rf.project_membership on any older record of its
--    own device in the tenant, since rf.require_record checks only the device and the tenant. Dated
--    at the record, either one rewrites how approvals already filed are judged: a late re-admission
--    counts approvals refused `not_revoker` while the subject was removed (and can complete k with
--    no request left to revoke the device), and a late removal un-counts approvals filed while the
--    subject was there. Both break ADR §6's first two bullets.
--    Why every writer, and not only rf.project_membership (finding 2): 06 §7's own re-admission is
--    invite → rf.accept_invite (joined_pending_verification, 0006) → ceremony
--    (rf.project_verification_event: active or blocked, 0006). The expiry sweep (rf.expire_invites)
--    demotes `invited` to removed. None of them is a membership record. Logged only from
--    rf.project_membership, a subject removed once by record and re-admitted by invite stayed
--    `removed` here for good, so no guardian approval in that tenant could count again, and no
--    re-split could fix it. A trigger sees every writer, including the next one.
--    Why the row, and not the membership records in signed_records, which the client reads: the
--    server stores a record it refused (`not_admin`, `membership_transition`) like any other and
--    serves it. rf_api also writes signed_records, apply_note included, itself (0005:401 grants
--    INSERT on every column, and rf.mark_record_applied takes any note). So neither the row nor its
--    note proves that a membership changed. Reading them would let any member of the set's tenant
--    file the subject's "removal", refused but stored, and stop every later guardian approval from
--    counting. That includes a thief on the subject's own stolen device. A memberships row is
--    written only by SECURITY DEFINER functions that authorise in the database (0005/0006/0022);
--    rf_api holds SELECT on it and nothing else, and no grant at all on the log.
--    The log is append-only: RLS is on and FORCED with no policy, no role is granted anything, and a
--    trigger refuses UPDATE and DELETE even to the schema owner. Rows are plaintext ids and a status
--    (03 §4: membership rows are plaintext).
--    History before this file: each existing memberships row is logged once, at its current status,
--    at a fresh seq. No approval filed before this file can count anyway: a set published before
--    0026 has no tenant (ADR §1), and 0026 and 0027 are deployed together.
-- §2 rf.subject_held_at(tenant, user, seq): internal, SECURITY DEFINER. It answers from the latest
--    fact BEFORE seq: held when that fact is anything but `removed`. With no fact the user held no
--    membership row there at that seq, so the answer is NOT held — the literal reading of §2 ("holds
--    a membership there other than removed"). The log is complete from this file on, so "no fact"
--    can only mean "not yet a member". It is keyed by tenant AND user: another member's change
--    never stands in for the subject's.
-- §3 rf.revocation_approvals judges the subject at each approval's own seq. A later change never
--    alters how an approval already filed is judged: a removal never un-counts it, and an approval
--    filed while the subject was removed never counts, not after a re-admission either (ADR §6).
--    Everything else in 0026's rule is unchanged. rf.revocation_tally, rf.revocation_count and
--    rf.project_device_status read this function, so they follow without being rewritten.
-- §4 rf.guardian_may_revoke, the edge's `not_revoker` question, asks the same thing at the seq of the
--    caller's own approval. The edge files the record first (records.ts applyRecord: "Caller has
--    already inserted the row"), so that approval is the caller device's latest device_revocation of
--    the device in that tenant naming that version. The edge's answer and the count are then one
--    judgment. With no such approval, as on a direct call, it judges as of now.
-- rf.project_membership is NOT re-created: 0022 §2's function stands, and the trigger logs its write.
--
-- A consequence, stated so nobody relies on its opposite: a fact always takes a seq above every
-- approval already filed, so it never changes how an earlier approval is judged. A count therefore
-- completes only when an approval is filed, which is the only place the edge projects (records.ts).
-- Under 0026, a re-admission could complete a count that no request then projected.
-- The one exception is a race. A change that took its seq before an approval's, but commits after
-- that approval's own judgment (the edge's `not_revoker` and its count) read, is not seen by that
-- judgment (READ COMMITTED), and is seen by every later count. The edge's `not_revoker` check has
-- always had the same window. The subject's devices are cut off at a removal anyway (ADR 2026-09-05b
-- §5).
--
-- ⚠️ SPEC (owner, reported in M13-REV97S): the server's facts are no longer exactly the client's.
--   The client (revocation.dart MembershipFact, removedAt) reads the membership RECORDS at their
--   record seqs; the server reads the memberships row at the moment it changed. They part in four
--   places, and ADR §2 🔒 says the server and the subject's own devices count the same set:
--   (a) A REFUSED membership record is not a fact here. The client cannot judge admin authority, so it
--       takes one as a fact (revocation.dart MembershipFact ⚠️ SPEC; M13-REV89C's blocker). Then the
--       server counts, and revokes, where the subject's own device does not wipe.
--   (b) A change no membership record carries is a fact here only: rf.accept_invite's
--       joined_pending_verification, a ceremony's flip to active or blocked, and the expiry sweep's
--       removal. After an invite re-admission the server counts where the subject's devices (still
--       reading the record-borne removal) do not; after an expiry the server refuses approvals the
--       subject's devices count.
--   (c) A record applied late is a fact here at its application, and on the client at its seq. The
--       client cannot see when a stored record was applied.
--   (d) With no fact at all the client reads "held" (removedAt) and the server "not held". A
--       membership row exists from the set's publication on (0026 §1 guard), so this bears only on
--       an approval filed before the subject joined the set's tenant.
--   The server follows ADR §6's bullets as written; widening the client to the same facts is
--   lane-sync's, or the owner rules otherwise.
--
-- Conventions kept from 0022/0024/0026: every function pins `set search_path = public, pg_temp`
-- (E-03-84), `create or replace` keeps the ACLs of the functions it rewrites, and the revoke/grant
-- lines of 0026 are restated below. The new helpers are revoked from PUBLIC and rf_api.
--
-- CLAUDE.md rule 2: no UPDATE or DELETE grant is added on anything, `envelopes` is not touched, and
-- the new table is append-only by trigger. Taking a store_seq value leaves a gap in envelope and
-- record seqs, as a rolled-back push always has; seq is an order, never a count. Zero-knowledge:
-- membership rows, record-routing columns and plaintext ids of signed-record payloads (03 §4) only.
-- No blob, wrapped key or phone hash is read, and nothing is logged anywhere else.

-- ---------------------------------------------------------------- §1 the history of the memberships rows
create table membership_facts (
  id bigint generated always as identity primary key,
  -- a store_seq value taken when the row changed (ADR 2026-09-05b §5's sequence). It is named
  -- at_seq because only envelopes and signed_records carry a `seq` (E-03-28), and it has no
  -- default: rf.membership_fact_log takes it.
  at_seq bigint not null unique,
  tenant_id uuid not null,
  user_id uuid not null,
  status text not null check (status in
    ('invited','joined_pending_verification','active','blocked','removed')),
  -- the row's source_record_id at that moment, for audit only; never read by the rule. There is no
  -- foreign key, so a future retention sweep of signed_records (03 §6) is never blocked by this log.
  source_record_id uuid null,
  created_at timestamptz not null default now()
);
create index membership_facts_at_idx on membership_facts (tenant_id, user_id, at_seq);
comment on table membership_facts is
  'ADR 2026-10-03b §6: every change of a memberships row (insert, status change, delete), at a '
  'store_seq value taken when the row changed, so that a guardian approval is judged by the '
  'subject''s membership as it stood when the approval was filed (rf.subject_held_at). Written only '
  'by the memberships_facts_log trigger; append-only; no role holds a grant.';

create or replace function rf.membership_facts_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception 'append_only' using errcode = '23514',
    detail = 'a membership fact is never rewritten or deleted; the next change is the next fact (ADR 2026-10-03b §6)';
end $$;
create trigger membership_facts_append_only before update or delete on membership_facts
  for each row execute function rf.membership_facts_guard();

alter table membership_facts enable row level security;
alter table membership_facts force row level security;
revoke all on table membership_facts from public, rf_api, rf_maintenance;
do $$ declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on table public.membership_facts from %I', r);
    end if;
  end loop;
end $$;

-- History: every row as it stands, once, before the trigger exists (so nothing is logged twice).
insert into membership_facts (at_seq, tenant_id, user_id, status, source_record_id)
select nextval('store_seq'), m.tenant_id, m.user_id, m.status, m.source_record_id
  from (select * from memberships order by tenant_id, user_id) m;

-- The one writer. AFTER the row is written, so a write a BEFORE guard refuses (rf.membership_guard's
-- membership_transition, no_live_invite, ceremony_required …) logs nothing, and a write an AFTER
-- trigger then refuses (rf.membership_seat_cap's seat_cap) rolls its fact back with it. An UPDATE
-- that leaves the status as it was (an idempotent re-application) is no change and logs nothing. A
-- deleted row holds no membership, which is what `removed` means here (nothing deletes one today).
-- SECURITY DEFINER, so the fact is written whichever role wrote the row: only the owner holds any
-- privilege on the log.
create or replace function rf.membership_fact_log() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    insert into membership_facts (at_seq, tenant_id, user_id, status, source_record_id)
    values (nextval('store_seq'), old.tenant_id, old.user_id, 'removed', old.source_record_id);
  elsif tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into membership_facts (at_seq, tenant_id, user_id, status, source_record_id)
    values (nextval('store_seq'), new.tenant_id, new.user_id, new.status, new.source_record_id);
  end if;
  return null;
end $$;
create trigger memberships_facts_log after insert or update of status or delete on memberships
  for each row execute function rf.membership_fact_log();

-- ---------------------------------------------------------------- §2 the subject, as of a seq
-- Held when the latest fact strictly before p_seq is anything but `removed`; not held with no fact
-- (no membership row there yet). Keyed by tenant and user. at_seq is unique, so there are no ties.
create or replace function rf.subject_held_at(p_tenant uuid, p_user uuid, p_seq bigint)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select f.status <> 'removed'
                     from membership_facts f
                    where f.tenant_id = p_tenant and f.user_id = p_user and f.at_seq < p_seq
                    order by f.at_seq desc
                    limit 1), false)
$$;

-- ---------------------------------------------------------------- §3 the count, at each approval's seq
-- 0026's function. The one change is the last conjunct: the subject at the approval's own seq, in
-- the tenant it was filed in (which the join has already made the set's).
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
     and rf.subject_held_at(r.tenant_id, d.user_id, r.seq)
$$;

-- ---------------------------------------------------------------- §4 the edge's question, at the same seq
-- 0026's function. The one change is the last conjunct. The subject is judged at the seq of the
-- caller device's latest approval of this device, filed in p_tenant and naming p_version: the
-- record the edge has just filed. With none, it is judged as of now. The payload is read as 0026
-- reads it (lower-case text ids, and a share_set_version only when it is a JSON number).
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
       and rf.subject_held_at(p_tenant, d.user_id, coalesce((
             select max(r.seq)
               from signed_records r
              where r.kind = 'device_revocation'
                and r.author_device = rf.device_id()
                and r.tenant_id = p_tenant
                and lower(r.payload_json->>'revoked_device_id') = d.id::text
                and lower(r.payload_json->>'subject_user_id') = d.user_id::text
                and case when jsonb_typeof(r.payload_json->'share_set_version') = 'number'
                         then (r.payload_json->'share_set_version')::numeric end = p_version),
             9223372036854775807)))
$$;

-- ---------------------------------------------------------------- grants
-- `create or replace` kept the ACLs of the functions that existed. They are restated as 0026 left
-- them. The new helpers belong to their owner alone: rf.subject_held_at takes any tenant and user,
-- so granting it would be a membership-history oracle.
revoke all on function rf.revocation_approvals(uuid), rf.revocation_tally(uuid) from public, rf_api;
revoke all on function rf.revocation_count(uuid), rf.guardian_may_revoke(uuid, uuid, int) from public;
grant execute on function rf.revocation_count(uuid), rf.guardian_may_revoke(uuid, uuid, int) to rf_api;
revoke all on function rf.subject_held_at(uuid, uuid, bigint), rf.membership_facts_guard(),
  rf.membership_fact_log() from public, rf_api;
