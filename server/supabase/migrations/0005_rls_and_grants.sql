-- 03 §2.5 Row-level security 🔒 — RLS on + FORCE for every table; policies read OUR claims
-- (request.user_id / request.device_id, set per transaction with set_config(..., true) = SET LOCAL,
-- ADR 2026-09-05c §7); every tenant-scoped policy requires devices.status = 'certified'
-- (ADR 2026-09-05d §2); envelopes are SELECT/INSERT only; deletion is rf_maintenance only.

-- ---------------------------------------------------------------- claims
create or replace function rf.user_id() returns uuid
language sql stable as $$ select nullif(current_setting('request.user_id', true), '')::uuid $$;
create or replace function rf.device_id() returns uuid
language sql stable as $$ select nullif(current_setting('request.device_id', true), '')::uuid $$;

-- set_config(name, value, is_local => true) is SET LOCAL: dies with the transaction, so a pooled
-- connection never carries claims into the next request.
create or replace function rf.set_claims(p_user uuid, p_device uuid) returns void
language sql as $$
  select set_config('request.user_id', coalesce(p_user::text, ''), true),
         set_config('request.device_id', coalesce(p_device::text, ''), true)
$$;

-- ---------------------------------------------------------------- helpers (security definer = bypass RLS for the lookup only)
create or replace function rf.is_certified() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from devices d
                 where d.id = rf.device_id() and d.user_id = rf.user_id() and d.status = 'certified')
$$;

create or replace function rf.active_in_tenant(p_tenant uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select rf.is_certified() and exists (
    select 1 from memberships m
    where m.tenant_id = p_tenant and m.user_id = rf.user_id() and m.status = 'active')
$$;

create or replace function rf.is_tenant_admin(p_tenant uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select rf.active_in_tenant(p_tenant) and exists (
    select 1 from book_roles r join books b on b.id = r.book_id
    where b.tenant_id = p_tenant and r.user_id = rf.user_id() and r.role = 'admin')
$$;

create or replace function rf.shares_tenant(p_other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select rf.is_certified() and exists (
    select 1 from memberships mine join memberships theirs on theirs.tenant_id = mine.tenant_id
    where mine.user_id = rf.user_id() and mine.status = 'active'
      and theirs.user_id = p_other and theirs.status <> 'removed')
$$;

create or replace function rf.book_tenant(p_book uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select b.tenant_id from books b where b.id = p_book
$$;

-- The requester's role on a book, or null. Requires certified device + active membership.
create or replace function rf.book_role(p_book uuid) returns text
language sql stable security definer set search_path = public as $$
  select r.role from book_roles r join books b on b.id = r.book_id
  where r.book_id = p_book and r.user_id = rf.user_id()
    and b.archived_at is null and rf.active_in_tenant(b.tenant_id)
$$;

create or replace function rf.device_visible(p_device uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_device = rf.device_id() or exists (
    select 1 from devices d where d.id = p_device
      and rf.is_certified() and (d.user_id = rf.user_id() or rf.shares_tenant(d.user_id)))
$$;

-- What sync-push needs to know about the caller's relationship to a book — one row, no leak
-- beyond the caller's own standing. Returns no row for an unknown book.
create or replace function rf.book_access(p_book uuid)
returns table (tenant_id uuid, archived boolean, role text, membership_status text, frozen boolean,
               plan text, envelope_count bigint, tenant_bytes bigint)
language sql stable security definer set search_path = public as $$
  select b.tenant_id, b.archived_at is not null,
         (select r.role from book_roles r where r.book_id = b.id and r.user_id = rf.user_id()),
         (select m.status from memberships m where m.tenant_id = b.tenant_id and m.user_id = rf.user_id()),
         exists (select 1 from tenant_freezes f where f.tenant_id = b.tenant_id
                   and f.lifted_at is null and f.expires_at > now()),
         coalesce((select s.plan from subscriptions s where s.tenant_id = b.tenant_id), 'free'),
         coalesce((select u.envelope_count from book_usage u where u.book_id = b.id), 0),
         coalesce((select sum(u.bytes) from book_usage u where u.tenant_id = b.tenant_id), 0)
  from books b where b.id = p_book and rf.is_certified()
$$;

-- Highest BK version issued for a book and when the first wrap at that version landed
-- (key_version ≤ highest issued; superseded > 48 h → key_version_stale — 05 §3, 04 §5.3).
create or replace function rf.highest_key_version(p_book uuid)
returns table (key_version int, issued_at timestamptz)
language sql stable security definer set search_path = public as $$
  select w.key_version, min(w.created_at) from wrapped_keys w
  where w.book_id = p_book and w.kind = 'bk_for_user' and rf.book_role(p_book) is not null
  group by w.key_version order by w.key_version desc limit 1
$$;

-- Per-device push rate (05 §3: 600/min, 5,000/h, 50 MB/day). True = allowed (and counted).
create or replace function rf.push_rate_check(p_device uuid, p_count int, p_bytes bigint) returns boolean
language plpgsql security definer set search_path = public as $$
declare r push_rate%rowtype; t timestamptz := now();
begin
  if p_device is distinct from rf.device_id() then return false; end if;
  insert into push_rate (device_id, minute_start, hour_start, day_start)
  values (p_device, t, t, t) on conflict (device_id) do nothing;
  select * into r from push_rate where device_id = p_device for update;
  if r.minute_start < t - interval '1 minute' then r.minute_start := t; r.minute_count := 0; end if;
  if r.hour_start   < t - interval '1 hour'   then r.hour_start := t;   r.hour_count := 0;   end if;
  if r.day_start    < t - interval '1 day'    then r.day_start := t;    r.day_bytes := 0;    end if;
  if r.minute_count + p_count > 600 or r.hour_count + p_count > 5000 or r.day_bytes + p_bytes > 52428800 then
    return false;
  end if;
  update push_rate set minute_start = r.minute_start, minute_count = r.minute_count + p_count,
    hour_start = r.hour_start, hour_count = r.hour_count + p_count,
    day_start = r.day_start, day_bytes = r.day_bytes + p_bytes where device_id = p_device;
  return true;
end $$;

-- ---------------------------------------------------------------- pre-JWT auth plumbing (06 §2–§4)
-- These run before any claim exists, so they are the only path to phone_hmac / phone_ct.
create or replace function rf.find_user_by_phone_hmac(p_hmac bytea) returns uuid
language sql stable security definer set search_path = public as $$
  select u.id from users u where u.phone_hmac = p_hmac and u.erased_at is null
$$;
create or replace function rf.phone_ct_for_otp(p_user uuid) returns bytea
language sql stable security definer set search_path = public as $$
  select u.phone_ct from users u where u.id = p_user
$$;
create or replace function rf.signup_user(p_hmac bytea, p_ct bytea, p_language text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  insert into users (phone_hmac, phone_ct, language) values (p_hmac, p_ct, p_language) returning id into v;
  return v;
end $$;

-- Device cap = highest cap among the user's active tenants (06 §6): 5 / 5 / 8 / 15.
create or replace function rf.device_cap(p_user uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(max(case coalesce(s.plan, 'free')
    when 'family_plus' then 15 when 'family' then 8 else 5 end), 5)
  from memberships m left join subscriptions s on s.tenant_id = m.tenant_id
  where m.user_id = p_user and m.status = 'active'
$$;

create or replace function rf.register_device(p_user uuid, p_pub_ed bytea, p_pub_x bytea,
  p_model text, p_os text, p_attestation jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid; n int;
begin
  select count(*) into n from devices d where d.user_id = p_user and d.status in ('registered','certified','suspended');
  if n >= rf.device_cap(p_user) then raise exception 'device_cap'; end if;
  insert into devices (user_id, pub_ed, pub_x, model, os, attestation)
  values (p_user, p_pub_ed, p_pub_x, p_model, p_os, p_attestation) returning id into v;
  return v;
end $$;

-- Row the challenge endpoint needs before any JWT exists.
create or replace function rf.device_auth_row(p_device uuid)
returns table (user_id uuid, pub_ed bytea, status text)
language sql stable security definer set search_path = public as $$
  select d.user_id, d.pub_ed, d.status from devices d where d.id = p_device
$$;

create or replace function rf.umk_pub_for(p_user uuid, p_version int) returns bytea
language sql stable security definer set search_path = public as $$
  select k.pub_ed from umk_public_keys k where k.user_id = p_user and k.key_version = p_version
$$;
create or replace function rf.set_umk_pub(p_user uuid, p_version int, p_pub bytea) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user is distinct from rf.user_id() then raise exception 'not_owner'; end if;
  insert into umk_public_keys (user_id, key_version, pub_ed) values (p_user, p_version, p_pub)
  on conflict (user_id, key_version) do nothing;
end $$;

-- The function verified the certificate under the user's UMK public key (ADR 2026-09-05d §2);
-- this stores it and flips status. Only the device's own transaction may certify it.
create or replace function rf.certify_device(p_device uuid, p_cert bytea, p_issued_at timestamptz,
  p_issued_by uuid, p_umk_version int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_device is distinct from rf.device_id() then raise exception 'not_owner'; end if;
  insert into device_certs (device_id, cert, issued_by_device, issued_at, umk_key_version)
  values (p_device, p_cert, p_issued_by, p_issued_at, p_umk_version)
  on conflict (device_id) do update set cert = excluded.cert, issued_by_device = excluded.issued_by_device,
    issued_at = excluded.issued_at, umk_key_version = excluded.umk_key_version;
  update devices set status = 'certified' where id = p_device and status = 'registered';
end $$;

-- ---------------------------------------------------------------- projections of signed records (ADR 2026-09-05b §1)
-- Every writer demands the applying record: rows are written ONLY when applying a signed record.
create or replace function rf.require_record(p_record uuid, p_tenant uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from signed_records r where r.id = p_record and r.tenant_id = p_tenant
                 and r.author_device = rf.device_id()) then
    raise exception 'no_record' using detail = 'rows are projections of signed records (ADR 2026-09-05b §1)';
  end if;
end $$;

create or replace function rf.project_membership(p_record uuid, p_tenant uuid, p_user uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rf.require_record(p_record, p_tenant);
  insert into memberships (tenant_id, user_id, status, source_record_id) values (p_tenant, p_user, p_status, p_record)
  on conflict (tenant_id, user_id) do update set status = excluded.status, source_record_id = p_record;
  if p_status = 'removed' then
    delete from book_roles r using books b where b.id = r.book_id and b.tenant_id = p_tenant and r.user_id = p_user;
  end if;
end $$;

create or replace function rf.project_book_role(p_record uuid, p_book uuid, p_user uuid, p_role text, p_limit bigint) returns void
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select tenant_id into t from books where id = p_book;
  perform rf.require_record(p_record, t);
  if p_role is null then
    delete from book_roles where book_id = p_book and user_id = p_user;
  else
    insert into book_roles (book_id, user_id, role, auto_post_limit_paise, source_record_id)
    values (p_book, p_user, p_role, p_limit, p_record)
    on conflict (book_id, user_id) do update set role = excluded.role,
      auto_post_limit_paise = excluded.auto_post_limit_paise, source_record_id = p_record;
  end if;
end $$;

create or replace function rf.project_device_status(p_record uuid, p_tenant uuid, p_device uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rf.require_record(p_record, p_tenant);
  update devices set status = p_status, revoked_at = case when p_status = 'revoked' then now() else revoked_at end
  where id = p_device;
  if p_status = 'revoked' then
    update wrapped_keys set revoked_at = now() where device_id = p_device and revoked_at is null;
  end if;
end $$;

create or replace function rf.project_verification_event(p_record uuid, p_tenant uuid, p_subject uuid,
  p_verifier uuid, p_method text, p_result text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform rf.require_record(p_record, p_tenant);
  insert into verification_events (tenant_id, subject_user, verifier_user, method, result, source_record_id)
  values (p_tenant, p_subject, p_verifier, p_method, p_result, p_record);
end $$;

create or replace function rf.mark_record_applied(p_record uuid, p_note text) returns void
language sql security definer set search_path = public as $$
  update signed_records set applied_at = now(), apply_note = p_note
  where id = p_record and author_device = rf.device_id() and applied_at is null
$$;

-- Support freeze / epoch bump / billing intake are not rf_api powers.
create or replace function rf.bump_store_epoch(p_reason text) returns uuid
language plpgsql security definer set search_path = public as $$
declare e uuid := gen_random_uuid();
begin
  insert into store_epoch (id, epoch, reason) values (true, e, p_reason)
  on conflict (id) do update set epoch = e, bumped_at = now(), reason = p_reason;
  return e;
end $$;

create or replace function rf.record_billing_event(p_event_id text, p_gateway text, p_type text, p_hash bytea) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  insert into billing_events (event_id, gateway, type, payload_hash) values (p_event_id, p_gateway, p_type, p_hash)
  on conflict (event_id) do nothing;
  return found;
end $$;

-- ---------------------------------------------------------------- RLS on + FORCE, every table
do $$ declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

-- Platform roles keep nothing: the API is our functions, not PostgREST (05 §1, 06 §4).
do $$ declare r text;
begin
  foreach r in array array['anon','authenticated','service_role'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('revoke all on all tables in schema public from %I', r);
      execute format('revoke all on all sequences in schema public from %I', r);
      execute format('revoke all on all functions in schema public from %I', r);
    end if;
  end loop;
end $$;

grant usage on schema public to rf_api, rf_maintenance;
grant usage on schema rf to rf_api, rf_maintenance;
revoke all on all functions in schema rf from public;
grant execute on all functions in schema rf to rf_api;
revoke execute on function rf.bump_store_epoch(text) from rf_api;
grant execute on function rf.bump_store_epoch(text) to rf_maintenance;
-- purge_ephemeral_auth is SECURITY DEFINER and deletes otp_challenges, activation_tickets,
-- auth_nonces, refresh_tokens and revoked wrapped_keys: maintenance only, never the API role
-- (E-03-26). The blanket `grant execute on all functions` above would otherwise hand it to rf_api.
revoke execute on function rf.purge_ephemeral_auth() from rf_api;
grant execute on function rf.purge_ephemeral_auth() to rf_maintenance;
grant execute on function rf.user_id(), rf.device_id(), rf.set_claims(uuid, uuid) to rf_maintenance;
grant usage on sequence store_seq to rf_api;

-- ---------------------------------------------------------------- policies + grants, per table
-- users: own row always (even uncertified); fellow members' profile fields when certified.
-- phone_ct / phone_hmac are NOT in the column grant: no claim-bearing path reads them.
grant select (id, trial_consumed_at, display_name, photo_key, language, whatsapp_opt_in, created_at,
              deletion_requested_at, deleted_at, erased_at, updated_at) on users to rf_api;
grant update (display_name, photo_key, language, whatsapp_opt_in, deletion_requested_at) on users to rf_api;
create policy users_select on users for select to rf_api
  using (id = rf.user_id() or rf.shares_tenant(id));
create policy users_update_self on users for update to rf_api
  using (id = rf.user_id()) with check (id = rf.user_id());

grant select on umk_public_keys to rf_api;
create policy umk_select on umk_public_keys for select to rf_api
  using (user_id = rf.user_id() or rf.shares_tenant(user_id));

grant select on tenants to rf_api;
grant insert on tenants to rf_api;
create policy tenants_select on tenants for select to rf_api
  using (rf.is_certified() and exists (select 1 from memberships m where m.tenant_id = tenants.id and m.user_id = rf.user_id()));
create policy tenants_insert on tenants for insert to rf_api with check (rf.is_certified());

grant select on memberships to rf_api;
create policy memberships_select on memberships for select to rf_api
  using (rf.active_in_tenant(tenant_id) or (rf.is_certified() and user_id = rf.user_id()));
-- no insert/update/delete policy: written via rf.project_membership only

grant select, insert on books to rf_api;
create policy books_select on books for select to rf_api using (rf.active_in_tenant(tenant_id));
create policy books_insert on books for insert to rf_api
  with check (rf.active_in_tenant(tenant_id) and (type <> 'personal' or owner_user_id = rf.user_id()));

grant select on book_roles to rf_api;
create policy book_roles_select on book_roles for select to rf_api
  using (rf.active_in_tenant(rf.book_tenant(book_id)));

grant select on devices to rf_api;
create policy devices_select on devices for select to rf_api using (rf.device_visible(id));

grant select on device_certs to rf_api;
create policy device_certs_select on device_certs for select to rf_api using (rf.device_visible(device_id));

grant select, insert on wrapped_keys to rf_api;
create policy wrapped_keys_select on wrapped_keys for select to rf_api
  using (user_id = rf.user_id() and (device_id = rf.device_id() or rf.is_certified()));
create policy wrapped_keys_insert on wrapped_keys for insert to rf_api
  with check (rf.is_certified() and (
    user_id = rf.user_id()
    or (kind = 'bk_for_user' and rf.book_role(book_id) in ('admin','head'))
    or (kind in ('guardian_share','escrow_blob') and rf.shares_tenant(user_id))));

grant select, insert on guardian_sets, guardian_set_members to rf_api;
create policy guardian_sets_select on guardian_sets for select to rf_api
  using (rf.is_certified() and (subject_user_id = rf.user_id() or rf.shares_tenant(subject_user_id)));
create policy guardian_sets_insert on guardian_sets for insert to rf_api
  with check (rf.is_certified() and subject_user_id = rf.user_id());
create policy guardian_set_members_select on guardian_set_members for select to rf_api
  using (rf.is_certified() and (subject_user_id = rf.user_id() or guardian_user_id = rf.user_id()
         or rf.shares_tenant(subject_user_id)));
create policy guardian_set_members_insert on guardian_set_members for insert to rf_api
  with check (rf.is_certified() and subject_user_id = rf.user_id());

grant select, insert on invites to rf_api;
create policy invites_select on invites for select to rf_api using (rf.active_in_tenant(tenant_id));
create policy invites_insert on invites for insert to rf_api
  with check (rf.is_tenant_admin(tenant_id) and created_by = rf.user_id());

grant select on verification_events to rf_api;
create policy verification_events_select on verification_events for select to rf_api
  using (rf.active_in_tenant(tenant_id));

grant select, insert on recovery_requests to rf_api;
create policy recovery_requests_select on recovery_requests for select to rf_api
  using (candidate_device = rf.device_id() or (rf.is_certified() and user_id = rf.user_id()));
create policy recovery_requests_insert on recovery_requests for insert to rf_api
  with check (candidate_device = rf.device_id() and user_id = rf.user_id());

grant select, insert on escrow_policies to rf_api;
create policy escrow_select on escrow_policies for select to rf_api
  using (rf.is_certified() and (member_user = rf.user_id() or head_user = rf.user_id()));
create policy escrow_insert on escrow_policies for insert to rf_api
  with check (rf.is_certified() and member_user = rf.user_id());

-- envelopes: SELECT/INSERT only for rf_api (CLAUDE.md rule 2). rf_maintenance: DELETE only, and the
-- 0003 trigger limits even that to an erased owner's personal book. Nobody holds UPDATE.
grant select, insert on envelopes to rf_api;
grant select, delete on envelopes to rf_maintenance;
create policy envelopes_select on envelopes for select to rf_api
  using (rf.book_role(book_id) is not null);
create policy envelopes_insert on envelopes for insert to rf_api
  with check (rf.book_role(book_id) in ('admin','head','member','operator')
              and tenant_id = rf.book_tenant(book_id)
              and author_device = rf.device_id());
create policy envelopes_maintenance_select on envelopes for select to rf_maintenance using (true);
create policy envelopes_maintenance_delete on envelopes for delete to rf_maintenance using (true);

grant select, insert on signed_records to rf_api;
create policy signed_records_select on signed_records for select to rf_api
  using (rf.active_in_tenant(tenant_id) or author_device = rf.device_id());
create policy signed_records_insert on signed_records for insert to rf_api
  with check (rf.is_certified() and author_device = rf.device_id());

grant select, insert on attachments to rf_api;
create policy attachments_select on attachments for select to rf_api using (rf.book_role(book_id) is not null);
create policy attachments_insert on attachments for insert to rf_api
  with check (rf.book_role(book_id) in ('admin','head','member','operator'));

grant select on book_usage to rf_api;
create policy book_usage_select on book_usage for select to rf_api using (rf.book_role(book_id) is not null);

grant select on store_epoch to rf_api, rf_maintenance;
create policy store_epoch_select on store_epoch for select to rf_api using (true);
create policy store_epoch_maint on store_epoch for select to rf_maintenance using (true);

grant select on subscriptions, entitlement_tokens, tenant_freezes to rf_api;
create policy subscriptions_select on subscriptions for select to rf_api using (rf.active_in_tenant(tenant_id));
create policy entitlement_select on entitlement_tokens for select to rf_api using (rf.active_in_tenant(tenant_id));
create policy freezes_select on tenant_freezes for select to rf_api using (rf.active_in_tenant(tenant_id));
-- billing_events / promo_*: no rf_api access at all (M13 console writes via rf.record_billing_event).

grant select, insert on audit_events to rf_api;
create policy audit_select on audit_events for select to rf_api
  using ((tenant_id is not null and rf.active_in_tenant(tenant_id)) or user_id = rf.user_id());
create policy audit_insert on audit_events for insert to rf_api
  with check (rf.is_certified() and user_id = rf.user_id());

grant select on app_config to rf_api;
create policy app_config_select on app_config for select to rf_api using (true);

-- Ephemeral auth tables (06 §2–§4): hash-only rows, read/written before any claim exists, so the
-- rf_api policy is permissive; the phone appears only as phone_hmac. rf_maintenance purges (03 §6).
grant select, insert, update on otp_challenges, activation_tickets, auth_nonces, refresh_tokens to rf_api;
grant select, delete on otp_challenges, activation_tickets, auth_nonces, refresh_tokens to rf_maintenance;
create policy otp_api on otp_challenges for all to rf_api using (true) with check (true);
create policy tickets_api on activation_tickets for all to rf_api using (true) with check (true);
create policy nonces_api on auth_nonces for all to rf_api using (true) with check (true);
create policy refresh_api on refresh_tokens for all to rf_api using (true) with check (true);
create policy otp_maint on otp_challenges for all to rf_maintenance using (true);
create policy tickets_maint on activation_tickets for all to rf_maintenance using (true);
create policy nonces_maint on auth_nonces for all to rf_maintenance using (true);
create policy refresh_maint on refresh_tokens for all to rf_maintenance using (true);
-- push_rate: only through rf.push_rate_check (no direct grant).
-- wrapped_keys purge of 90-day-revoked rows (03 §6) runs in rf.purge_ephemeral_auth as maintenance.
grant select, delete on wrapped_keys to rf_maintenance;
create policy wrapped_keys_maint on wrapped_keys for all to rf_maintenance using (true);
