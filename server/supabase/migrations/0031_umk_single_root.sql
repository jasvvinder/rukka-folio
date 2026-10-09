-- 0031 — one registered UMK per user, and a device is certified under THAT key and no other.
-- 🔴 SECURITY repair (M13 RUNG3S review, finding 1, blocker). Tests E-05d-1 (MemStore through the
-- real handlers, _tests/umk_single_root.test.ts) and E-05d-2 (rf_api, tests/rls/umk_single_root).
--
-- Spec
--   06 §3 🔒 step 3: "the server verifies the uploaded certificate under the user's REGISTERED UMK
--     public key and sets devices.status='certified'". Step 4: "First device only: generate UMK,
--     self-certify".
--   04 §3.4 🔒: the first device self-certifies; "every later device gets its certificate issued by
--     an existing certified device (linking, §9.1) or during recovery completion (§7.3 step 6)".
--   ADR 2026-09-05d §2 🔒: until a device holds a certificate the server has verified under the
--     user's registered UMK public key, it sees nothing but itself.
--
-- The hole (pre-existing; it decided what RUNG3S's GET /recovery/sheet relays)
--   auth-challenge certifyWith reads the stored key at the `umk_key_version` the REQUEST BODY names
--   and treats "no row at that version" as "first device": it then verifies the certificate under
--   the key the body offered and stores that key at that version. Neither guard below it looked any
--   further: rf.set_umk_pubs (0012) checked only p_user = rf.user_id(), rf.certify_device (0005)
--   only p_device = rf.device_id(). So a registered, OTP-only phone of an account whose UMK sits at
--   version 1 could post version 2 with a key it minted, sign its own certificate, and be certified
--   — a second trust root the server minted on a stranger's say-so — and GET /recovery/sheet
--   (newest key_version) relayed that key to a restoring phone as the account's published UMK.
--   Measured on HEAD, MemStore through the handlers and PgStore as rf_api: E-05d-1/E-05d-2 red.
--
-- The fix, in the database so that no edge function can reopen it
--   1. umk_public_keys_one_live: at most ONE live (superseded_at is null) row per user. Structural:
--      it holds for every writer, the owner included, and under concurrency, where an explicit
--      "is there another row?" check cannot see a racing transaction's uncommitted insert.
--   2. rf.set_umk_pubs refuses a NEW key_version once the user has ANY row — live or retired — with
--      the named reason `umk_version_conflict`. Writing to the version that already exists is
--      unchanged (0012: same material → no-op, the one NULL → x backfill, different → conflict). A
--      race loser that meets the index is refused under the same name, never a 500.
--   3. rf.certify_device requires the caller's own LIVE row at p_umk_version (`umk_unknown`). The
--      database cannot verify an Ed25519 signature (04 §8.6 keeps that in the edge); what it can
--      hold is that the version a certificate claims is the account's registered root. A retired
--      row certifies nobody: 04 §9.2 retires a UMK after a stolen phone, which is precisely when an
--      attacker may hold its private half.
--
-- ⚠️ SPEC (owner): 04 §9.2 and 06 §6 RECOMMEND rotating the UMK after "This phone was stolen", but
-- no spec gives a rotation a write path: nothing says how a new key_version is proven under the
-- current one (a signed rotation record, 05b §1), or who marks the old row superseded (rf_api holds
-- no UPDATE on this table, 0005:317). Until one does, the only conservative reading of 06 §3 step 4
-- is that an account registers its UMK once. When rotation is specified, (2) and (3) are relaxed by
-- that ADR for a key_version proven under the live root — never for "the body asked for it".
--
-- Not done here (outside this lane's directories; reported in M13-RUNG3S `open`):
--   auth-challenge/index.ts:472-497 still takes `umk_key_version` from the body and still reads "no
--   row at that version" as "first device". It is now harmless — the store refuses the write before
--   the certificate is stored — and the refusal reaches the wire as 400 `umk_version_conflict` /
--   `umk_unknown` through its existing `catch (StoreDenied) → return e.reason`. Tightening the
--   handler itself is defence in depth for whoever owns auth-challenge.
--
-- Migrations are append-only: 0005 and 0012 are untouched; both functions are replaced in place
-- with their signatures unchanged, so their grants (0012 §3: rf_api only; 0005's blanket grant) and
-- owners carry over (CREATE OR REPLACE keeps both). Each carries `set search_path = public, pg_temp`
-- itself (0024; E-03-84). Nothing here grants anything, and envelopes are not touched.

-- ---------------------------------------------------------------- 0. refuse to guess on old data
-- If any account ALREADY holds two live rows, the server cannot tell which is the registered root
-- and which was minted through the hole — so the migration stops and says so rather than picking
-- one. The operator resolves it (mark the minted row superseded as `maintenance`, after checking
-- which key the account's ceremony-verified fingerprint and first device_certs row were issued
-- under) and re-runs. Identifiers stay out of the message; the query below finds them.
--   select user_id, array_agg(key_version order by key_version) from umk_public_keys
--   where superseded_at is null group by user_id having count(*) > 1;
do $$
declare n int;
begin
  select count(*) into n from (
    select user_id from umk_public_keys where superseded_at is null
    group by user_id having count(*) > 1
  ) ambiguous;
  if n > 0 then
    raise exception 'umk_roots_ambiguous'
      using detail = format('%s account(s) hold more than one live UMK public key row; the '
        'server cannot tell the registered root from a minted one (06 §3 step 4)', n),
      hint = 'resolve by hand (see the query in 0031''s header), then re-run this migration';
  end if;
end $$;

-- ---------------------------------------------------------------- 1. one live root per user
create unique index umk_public_keys_one_live on umk_public_keys (user_id)
  where superseded_at is null;

comment on index umk_public_keys_one_live is
  'At most one live UMK public key per user (06 §3 step 4; ADR 2026-09-05d §2): the key every '
  'certificate of that user is verified under. Holds under concurrency and for every writer.';

-- ---------------------------------------------------------------- 2. no second registration
-- 0012's body, with one new refusal before the insert and the index's race turned into the same
-- named refusal. Everything 0012 said about the x half stands.
create or replace function rf.set_umk_pubs(p_user uuid, p_version int, p_pub_ed bytea, p_pub_x bytea)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  k umk_public_keys%rowtype;
  c text;
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

  -- 0031: a key_version this user has no row at is a NEW registration, and an account registers
  -- its UMK once (06 §3 step 4 "first device only"). A retired row counts: it is not a vacancy.
  if not exists (select 1 from umk_public_keys where user_id = p_user and key_version = p_version)
     and exists (select 1 from umk_public_keys where user_id = p_user) then
    raise exception 'umk_version_conflict' using errcode = '23514',
      detail = 'this user already has a registered UMK; a second key_version is a second trust '
        'root and has no write path (06 §3 step 4; 04 §9.2 rotation unspecified)';
  end if;

  begin
    insert into umk_public_keys (user_id, key_version, pub_ed, pub_x)
    values (p_user, p_version, p_pub_ed, p_pub_x)
    on conflict (user_id, key_version) do nothing;
  exception when unique_violation then
    -- ON CONFLICT names the primary key, so the only unique violation left is the one-live index:
    -- a concurrent FIRST registration at another version committed while this insert waited on it
    -- (the check above could not see it uncommitted). Same refusal, same name — never a 500.
    get stacked diagnostics c = constraint_name;
    if c = 'umk_public_keys_one_live' then
      raise exception 'umk_version_conflict' using errcode = '23514',
        detail = 'a concurrent registration of this user''s UMK won; it is written once';
    end if;
    raise;
  end;

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
    -- 0012's one UPDATE: fill a NULL x half, write-once under concurrency (`pub_x is null`).
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

-- ---------------------------------------------------------------- 3. certify only under the root
-- 0005's body, with the root check first. The edge has verified the certificate under the key it
-- read at p_umk_version (ADR 2026-09-05d §2); this makes sure that key IS the account's live
-- registered root, so a certificate under anything else is never stored and never flips status.
create or replace function rf.certify_device(p_device uuid, p_cert bytea, p_issued_at timestamptz,
  p_issued_by uuid, p_umk_version int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_device is distinct from rf.device_id() then raise exception 'not_owner'; end if;
  if not exists (
    select 1 from umk_public_keys k
    where k.user_id = rf.user_id() and k.key_version = p_umk_version and k.superseded_at is null
  ) then
    raise exception 'umk_unknown' using errcode = '23514',
      detail = 'no live registered UMK at this key_version for this user (06 §3 step 3)';
  end if;
  insert into device_certs (device_id, cert, issued_by_device, issued_at, umk_key_version)
  values (p_device, p_cert, p_issued_by, p_issued_at, p_umk_version)
  on conflict (device_id) do update set cert = excluded.cert, issued_by_device = excluded.issued_by_device,
    issued_at = excluded.issued_at, umk_key_version = excluded.umk_key_version;
  update devices set status = 'certified' where id = p_device and status = 'registered';
end $$;
