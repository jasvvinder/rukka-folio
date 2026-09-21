-- 0012 — the UMK's X25519 public half, and a verifier's way to FIND a live ceremony session.
-- Conformance repair, not a behaviour change: 04 §6.1 🔒 and 04 §6.3 🔒 already require both halves.
--
--   04 §6.1 🔒: QR payload = base64url( suite_version ‖ user_id ‖ UMK_pub_ed ‖ UMK_pub_x ‖ nonce )
--   04 §6.3 🔒: "the verifier's device compares scanned public keys **byte-for-byte** against the
--               server-relayed keys for that user … There is no override."  KEYS, plural.
--
-- `umk_public_keys` (0001:48) stored `pub_ed` alone, so the relay could only ever hand a verifier
-- half of what it must compare — and the missing half is not derivable: core_crypto's UmkPublic
-- (packages/core_crypto/lib/src/keys.dart:57-65) cannot be constructed without both 32-byte halves,
-- and the X25519 half comes from its own seed (keys.dart:13), not from the Ed25519 one. verifyQr
-- (ceremony.dart:490-492) constant-time-compares BOTH. So with pub_ed alone the ceremony 04 §6
-- calls MANDATORY cannot complete at all: the ladder fails closed, which is why this is a gap and
-- not an exploit. This migration closes it.
--
-- Migrations are append-only: 0001 and 0005 are untouched. Nothing here grants rf_api an UPDATE or
-- DELETE on anything (CLAUDE.md rule 2); the one UPDATE path added is a SECURITY DEFINER backfill
-- of a NULL, guarded to be write-once.

-- ---------------------------------------------------------------- 1. the column
-- Nullable, exactly as 0010:148-153 added `recovery_requests.candidate_pub_x`: rows written before
-- this migration have no x half and no way to invent one, and a NOT NULL would make the table
-- unmigratable without fabricating key material — which is the one thing a zero-knowledge relay
-- must never do. The length check is the same shape as 0010's, so nothing but 32 bytes can land.
--
-- NOT ONLY the pre-migration rows, though, and this is the honest shape of it: NULL means "no x
-- half has been offered for this (user, key_version)", and as of this milestone no client offers
-- one — the app's /devices/certify body carries `umk_key_version` + `umk_pub_ed` and nothing else.
-- So every row, old and new, is ed-only, and the ceremony 04 §6 MANDATES is unpassable for every
-- user until the client sends the half. The nullability is therefore not a migration artefact that
-- ages out; it is a state the relay must keep handling, and a `not null` later (see the ⚠️ SPEC in
-- section 3) can only follow the client change, never precede it.
alter table umk_public_keys add column pub_x bytea;

alter table umk_public_keys
  add constraint umk_public_keys_pub_x
    check (pub_x is null or octet_length(pub_x) = 32);

comment on column umk_public_keys.pub_x is
  'The X25519 public half of the UMK (04 §3.1). Relayed to a verifier so its device can compare '
  'BOTH scanned public keys byte-for-byte against the server''s copy (04 §6.3 🔒) and to a sealing '
  'device so book keys can be wrapped to a VERIFIED fingerprint (04 §8.2). Opaque to the server: '
  'stored, relayed and compared, never used in a computation (04 §8.6). NULL whenever no x half '
  'has been offered for this (user, key_version) — which includes, but as of this milestone is not '
  'limited to, rows written before migration 0012: no client sends umk_pub_x yet. A ceremony '
  'against such a row fails closed on the device (04 §6.3 ''There is no override'').';
comment on column umk_public_keys.pub_ed is
  'The Ed25519 public half of the UMK. Verifies device certificates before devices.status flips to '
  '''certified'' (ADR 2026-09-05d §2) and is half of FP = BLAKE2b-256(pub_x ‖ pub_ed) (04 §3.1).';

-- ---------------------------------------------------------------- 2. write-once, in the database
-- A substituted x half is PRECISELY the attack 04 §6.3 exists to stop, and the server is the
-- untrusted relay: if it could swap a stored key the byte-for-byte comparison would be comparing
-- against the attacker's own material and would pass. So "written once" is a property of the
-- database here, not a habit of an edge function — the same discipline 0007 applies to a ceremony
-- commitment and 0009's rf.register_device applies to a device's key pair (it refuses
-- `device_id_taken` rather than quietly re-keying a row).
--
-- rf_api holds SELECT on this table and nothing else (0005:317), so no client can reach an UPDATE
-- at all. This guard is the backstop for the two paths that CAN: the SECURITY DEFINER backfill
-- below, and any future migration or maintenance statement.
create or replace function rf.umk_public_keys_guard() returns trigger
language plpgsql as $$
begin
  if new.user_id is distinct from old.user_id or new.key_version is distinct from old.key_version then
    raise exception 'umk_pub_immutable' using errcode = '23514',
      detail = 'a UMK public key row is identified by (user_id, key_version) for its lifetime';
  end if;
  if new.pub_ed is distinct from old.pub_ed then
    raise exception 'umk_pub_immutable' using errcode = '23514',
      detail = 'the Ed25519 half verifies every device certificate of this user (ADR 2026-09-05d §2); replacing it re-roots trust';
  end if;
  -- NULL → 32 bytes is the one permitted transition: the backfill of a row that predates 0012.
  -- Once set, the x half is what 04 §6.3's byte-for-byte comparison runs against, so it is final.
  if old.pub_x is not null and new.pub_x is distinct from old.pub_x then
    raise exception 'umk_pub_immutable' using errcode = '23514',
      detail = 'the X25519 half is written once; substituting it is the attack 04 §6.3 exists to stop';
  end if;
  return new;
end $$;

create trigger umk_public_keys_guard before update on umk_public_keys
  for each row execute function rf.umk_public_keys_guard();

-- ---------------------------------------------------------------- 3. successors to 0005's helpers
-- 0005:163 selected `pub_ed` alone and 0005:167 inserted `(user_id, key_version, pub_ed)` alone.
-- Both go, by the 0009:23 precedent ("a caller that has not been updated must fail at bind time"):
-- a helper that silently drops the x half is how the gap survived this long.
drop function if exists rf.umk_pub_for(uuid, int);
drop function if exists rf.set_umk_pub(uuid, int, bytea);

-- The read the certify path needs before any certificate is verified. NARROWER than its
-- predecessor on purpose: 0005's version was SECURITY DEFINER over an arbitrary p_user, so it
-- bypassed the `umk_select` policy and answered for any uuid a caller cared to try. Its only caller
-- ever passes its own user (auth-challenge certifyWith), so it is now bounded to the caller's own
-- row and the enumeration oracle goes away. A VERIFIER reads another user's keys the way it always
-- did — through the meta relay, under `umk_select` (0005:318), which is the RLS-checked path.
create function rf.umk_pubs_for(p_user uuid, p_version int)
returns table (pub_ed bytea, pub_x bytea)
language plpgsql stable security definer set search_path = public as $$
begin
  if p_user is distinct from rf.user_id() then raise exception 'not_owner'; end if;
  return query
    select k.pub_ed, k.pub_x from umk_public_keys k
    where k.user_id = p_user and k.key_version = p_version;
end $$;

-- Register the pair. Idempotent for the same material; a REFUSAL, never a silent overwrite, for
-- different material (0009's rf.register_device is the precedent: same keys → return, anything
-- else → raise). `p_pub_x` may be NULL so that a client that has not yet shipped the x half still
-- registers its ed half — the ceremony then fails closed on the device rather than verifying
-- against a key the server made up. ⚠️ SPEC: 04 §6.1/§6.3 arguably make the x half mandatory at
-- registration; refusing an ed-only registration outright would be the stricter reading but would
-- break every client shipped before 0012 — and, today, every client FULL STOP, since none sends
-- umk_pub_x (section 1). So the conservative reading is taken here and the question goes to the
-- owner, with the sequencing noted: the strict rule is only adoptable AFTER the client offers the
-- half, or it locks every user out of certification.
create function rf.set_umk_pubs(p_user uuid, p_version int, p_pub_ed bytea, p_pub_x bytea)
returns void language plpgsql security definer set search_path = public as $$
declare k umk_public_keys%rowtype;
begin
  if p_user is distinct from rf.user_id() then raise exception 'not_owner'; end if;
  if p_pub_ed is null or octet_length(p_pub_ed) <> 32 then
    raise exception 'umk_pub_malformed' using errcode = '23514',
      detail = 'the Ed25519 half is exactly 32 bytes (04 §3.1)';
  end if;
  if p_pub_x is not null and octet_length(p_pub_x) <> 32 then
    raise exception 'umk_pub_malformed' using errcode = '23514',
      detail = 'the X25519 half is exactly 32 bytes (04 §3.1)';
  end if;

  insert into umk_public_keys (user_id, key_version, pub_ed, pub_x)
  values (p_user, p_version, p_pub_ed, p_pub_x)
  on conflict (user_id, key_version) do nothing;

  select * into k from umk_public_keys
    where user_id = p_user and key_version = p_version;
  if not found then                              -- cannot happen: the insert above either wrote it
    raise exception 'umk_pub_malformed';          -- or found it. Fail closed rather than proceed.
  end if;

  if k.pub_ed is distinct from p_pub_ed then
    raise exception 'umk_pub_conflict' using errcode = '23514',
      detail = 'this user already has a UMK Ed25519 key at this version; it is written once';
  end if;
  if p_pub_x is null then return; end if;        -- nothing offered: the stored row stands
  if k.pub_x is null then
    -- The only UPDATE in this migration: fill a NULL on a row that predates 0012. `pub_x is null`
    -- in the predicate makes the backfill itself write-once under concurrency — the loser of a race
    -- updates nothing and falls through to the compare.
    update umk_public_keys set pub_x = p_pub_x
      where user_id = p_user and key_version = p_version and pub_x is null;
    select * into k from umk_public_keys
      where user_id = p_user and key_version = p_version;
  end if;
  if k.pub_x is distinct from p_pub_x then
    raise exception 'umk_pub_conflict' using errcode = '23514',
      detail = 'this user already has a UMK X25519 key at this version; substituting it is the attack 04 §6.3 stops';
  end if;
end $$;

-- 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before these existed.
revoke all on function rf.umk_public_keys_guard(), rf.umk_pubs_for(uuid, int),
  rf.set_umk_pubs(uuid, int, bytea, bytea) from public;
grant execute on function rf.umk_pubs_for(uuid, int),
  rf.set_umk_pubs(uuid, int, bytea, bytea) to rf_api;

-- No new grant on the table itself. 0005:317 is `grant select on umk_public_keys to rf_api` — a
-- TABLE-level privilege, which in Postgres covers columns added later, so `pub_x` is readable by
-- rf_api under the existing `umk_select` policy (0005:318) and by nobody else. E-06-62 asserts
-- that rather than trusting it. Had the grant been column-scoped (as `users`' is, 0005:308) this
-- migration would have needed a `grant select (pub_x)` too.

-- ---------------------------------------------------------------- 4. ceremony session discovery
-- A verifier that has just scanned a QR holds a `user_id` and a nonce (04 §6.1) — and nothing else.
-- The session id is minted server-side at commit and the QR payload carries no session id, so
-- there was no way to reach the row the verifier must write r_V into. 0007's own read index,
-- `ceremony_sessions_subject_idx on (tenant_id, subject_user, committed_at desc)` (0007:80-81), is
-- exactly this lookup; it existed for the poll and is reused here.
--
-- This adds NO authority. It is an ordinary SELECT as the CALLING role — not SECURITY DEFINER —
-- so 0007:295's policy decides every row: `rf.is_certified() and (subject_user = rf.user_id() or
-- rf.active_in_tenant(tenant_id))`. A non-member and a member of another tenant get zero rows, as
-- they already did by id. What the caller gains is the id of a row that was already theirs to read,
-- which is what 04 §6.4 *delegated* requires — "any already-verified, active member of the tenant
-- may perform the ceremony on the tenant's behalf" is unimplementable if that member cannot find
-- the session. Expired sessions are excluded here as well as refused by 0007's guard, so a stale
-- row is never handed to a device that would poll it forever.
create function rf.live_ceremony_for(p_tenant uuid, p_subject uuid)
returns setof ceremony_sessions
language sql stable as $$
  select * from ceremony_sessions
  where tenant_id = p_tenant and subject_user = p_subject and expires_at > now()
  order by committed_at desc
  limit 1
$$;
comment on function rf.live_ceremony_for(uuid, uuid) is
  'The newest UNEXPIRED ceremony session for a subject in a tenant (04 §6.4 delegated verification). '
  'INVOKER rights on purpose: 0007''s select policy filters it, so it can return nothing a caller '
  'could not already have fetched by session_id.';
revoke all on function rf.live_ceremony_for(uuid, uuid) from public;
grant execute on function rf.live_ceremony_for(uuid, uuid) to rf_api;
