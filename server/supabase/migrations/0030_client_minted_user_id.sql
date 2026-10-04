-- 0030 — the first device mints `user_id`; signup RECORDS it or refuses (ADR 2026-10-04b §1 🔒,
-- desk 107, owner 4 Oct 2026). ⟦tests: E-04b-1, E-04b-3⟧ — tests/rls/client_minted_user_id.test.ts
-- (database: the function, its grants, the edge arm on PgStore as rf_api) and
-- functions/_tests/auth_challenge.test.ts (route + MemStore, E-04b-1 … E-04b-4).
--
-- THE GAP. The ledger mints `user_id` at first run, before OTP, and seals it into signed and
-- encrypted content (ADR 04b § Why the client's id). rf.signup_user (0005) inserted with
-- users.id's default, so POST /otp/verify created a SECOND user id and one install carried two.
-- The insert lives in that SECURITY DEFINER function — rf_api holds no INSERT on `users` (0005) —
-- so carrying the client's id needs a function that takes it. ADR 04b § Consequences says "no
-- migration (the default stays for old clients)": the DEFAULT does stay, and no table, column,
-- policy or grant on a table changes; this file only adds the function that can record an id.
--
-- THE CHANGE. A 4-argument overload, rf.signup_user(p_hmac, p_ct, p_language, p_user):
--   * records `p_user` EXACTLY — it never mints, so a null is refused, not quietly replaced;
--   * an id ANY users row holds — live or erased — is refused by the primary key and named
--     `user_id_taken` (P0001; denialFromPg passes the bare token through as StoreDenied, and the
--     edge answers 409 {error: user_id_taken}). Users rows are never deleted (03 §2.5: erasure
--     blanks the profile in place and sets erased_at), so an id once used is never handed out
--     again, and nothing that names an erased user can be inherited by a newcomer;
--   * a phone collision (users_phone_hmac_key) is NOT renamed: it re-raises as the unique
--     violation it is. Naming it user_id_taken would send an honest client into a re-mint loop
--     that a new id can never win.
-- The race (two signups proposing one id at once) ends the same way: the loser's insert hits the
-- primary key, inside this function's own exception block, and is named user_id_taken.
--
-- WHAT DOES NOT CHANGE. users.id keeps `default gen_random_uuid()`, and the 3-argument
-- rf.signup_user (0005, search_path pinned by 0024) is kept untouched: an edge built before
-- ADR 04b, or a request from a client that sends no `user_id`, still signs up through it. The two
-- overloads cannot be confused at bind time — the new one has no default argument. The caller
-- (functions/auth-challenge) decides the phone has no account first; neither function re-keys an
-- existing user (ADR 04b §3).
--
-- CLAUDE.md rule 2: nothing here touches `envelopes`. Rule 4: the function takes the phone only as
-- HMAC and KMS ciphertext, exactly as 0005's does.

create function rf.signup_user(p_hmac bytea, p_ct bytea, p_language text, p_user uuid)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare c text;
begin
  if p_user is null then
    -- The overload exists to RECORD a client's id; minting is the 3-argument function's job.
    raise exception 'user_id_required' using errcode = '22004';
  end if;
  insert into users (id, phone_hmac, phone_ct, language) values (p_user, p_hmac, p_ct, p_language);
  return p_user;
exception when unique_violation then
  get stacked diagnostics c = constraint_name;
  if c = 'users_pkey' then
    raise exception 'user_id_taken';
  end if;
  raise;
end $$;

comment on function rf.signup_user(bytea, bytea, text, uuid) is
  'ADR 2026-10-04b §1: records the client-minted user id exactly, or raises user_id_taken (P0001) when any users row — erased included — holds it; never mints. Phone only as HMAC + ciphertext. The 3-argument overload keeps minting for clients that send no id.';

-- There are no default privileges on schema rf; PUBLIC's default EXECUTE is the door to close.
revoke all on function rf.signup_user(bytea, bytea, text, uuid) from public;
grant execute on function rf.signup_user(bytea, bytea, text, uuid) to rf_api;
