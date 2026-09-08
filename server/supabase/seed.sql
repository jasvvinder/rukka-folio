-- LOCAL DEV ONLY. Applied by `supabase db reset` after migrations. Never run against a hosted project.
-- Provisions the login role the functions and the RLS test runner connect as; hosted projects get
-- theirs from ops (server/README.md §3) and the password lives in Edge Function secrets.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'rf_local') then
    create role rf_local login password 'rf_local' nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'rf_local_maint') then
    create role rf_local_maint login password 'rf_local_maint' nobypassrls;
  end if;
end $$;
grant rf_api to rf_local;
grant rf_maintenance to rf_local_maint;
insert into store_epoch (id, epoch) values (true, gen_random_uuid()) on conflict (id) do nothing;
