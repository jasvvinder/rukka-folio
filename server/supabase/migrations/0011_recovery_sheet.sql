-- M11 · rung 3 of the recovery ladder — 04 §7.4 🔒 (the paper sheet), 03 §2.2/§2.5, 05 §5,
-- ADR 2026-09-05d §2, ADR 2026-09-05b §7 (the server's only new powers: structure, timers, named
-- refusals), CLAUDE.md rule 2 (append-only) and rule 4 (no plaintext financial data).
-- ⟦tests: E-06-58, E-06-60, E-06-61⟧
--
-- ============================================================================================
-- THE GAP THIS CLOSES
-- ============================================================================================
-- 04 §7.4 🔒 reads: "`RK` = random 256-bit, generated at signup. Server stores
-- `sealed_RK_blob = XChaCha20(RK, UMK_priv)` … Recovery: scan/type RK → fetch blob → decrypt UMK".
-- Every other half of rung 3 exists — the sheet, the QR, the Crockford fallback, the client's
-- `openUmkWithRecoveryKey` — but NO migration ever stored that blob and NO route ever returned it.
-- The consequence was visible from the client: `HttpRecoverySheet` (app/lib/shared/sync/
-- recovery_seams.dart) can only throw a generic `RecoveryFailure`, and F1-06-40 pins that it must
-- NEVER throw `RecoverySheetRejected` — because "this sheet is wrong" would be a falsehood about a
-- correctly copied sheet when the truth is that there is nothing to check it against. This
-- migration is the storage; sync-meta's two routes are the fetch and the upload.
--
-- ============================================================================================
-- WHY ITS OWN TABLE, AND NOT `wrapped_keys`
-- ============================================================================================
-- 03 §2.2 gives `wrapped_keys` a `recovery_blob` kind, and that kind is already spoken for: 0010's
-- `rf.recovery_decide` writes the guardian's RE-SEALED SHARE as a `recovery_blob` addressed to the
-- candidate DEVICE. Two things then pull in opposite directions:
--
--   * 0005's `wrapped_keys` SELECT policy reaches an uncertified device only through
--     `device_id = rf.device_id()`. The sheet's blob is addressed to a USER, not to a device — the
--     device that will need it does not exist yet when the sheet is printed at signup. Filed in
--     `wrapped_keys` it would be unreadable by the one caller that must read it.
--   * `wrapped_keys` carries `revoked_at` and a wider grant surface. The sheet blob wants the
--     narrowest possible contract: written once, never rewritten, never revoked in place, and
--     superseded only by publishing the NEXT version (04 §7.4: "regenerating a sheet rotates RK and
--     invalidates the old sheet").
--
-- So: a table of its own, one row per sheet ever printed, `rf_api` holding SELECT + INSERT and
-- nothing else. 03 §2.2 does not declare this table — the same doc gap 0010 opened with
-- `recovery_approvals`/`recovery_cancellations`, reported to the owner, never edited by a lane.
--
-- ============================================================================================
-- ⚠️ SPEC — who may READ the blob
-- ============================================================================================
-- ADR 2026-09-05d §2 🔒 enumerates what an UNCERTIFIED device may see: "the device's own `users`
-- row, its own `devices` row, wrapped keys and shares **addressed to it**, and its own
-- `recovery_requests`." A sealed sheet blob is none of those four, yet 04 §7.4's recovery path is
-- performed by exactly such a device: a fresh phone that has passed OTP and holds nothing else
-- (06 §5 "New phone, no old device"), whose next act is to decrypt the blob with the RK a human is
-- reading off paper. A rule that hid the blob from it would delete rung 3, which 04 §7.4 makes
-- MANDATORY for solo users — and 04 owns recovery (CLAUDE.md § Precedence 2b).
--
-- The conservative reading taken, and the one asserted by E-06-60/E-06-61: the caller may read the
-- CURRENT blob of its OWN user and nothing else — never another user's, never an older version,
-- never a list, and never anything financial. What that hands a SIM-swapper is 40-odd bytes of
-- XChaCha20-Poly1305 ciphertext under a 256-bit key that exists only on paper; it is the same
-- posture 04 §1.2 already accepts for every wrapped blob the server holds. Reported for the owner
-- to fold into ADR 2026-09-05d §2's list (a fifth item) rather than decided here.

-- ---------------------------------------------------------------- the store
create table recovery_sheets (
  user_id uuid not null references users(id),
  sheet_version int not null check (sheet_version >= 1),
  -- XChaCha20-Poly1305(RK, UMK_priv) with its nonce, exactly as the client sealed it. The server
  -- neither derives, opens, hashes nor compares it (04 §8.6): bytea in, bytea out.
  blob bytea not null check (octet_length(blob) between 1 and 4096),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, sheet_version)
);
comment on table recovery_sheets is
  '04 §7.4 🔒 rung 3 — sealed_RK_blob = XChaCha20(RK, UMK_priv). Append-only and versioned: '
  'regenerating a sheet rotates RK and publishes the NEXT version; the old row is never rewritten '
  'and stops being served (0011). RK is on paper and never on this server.';
comment on column recovery_sheets.sheet_version is
  'Strictly the next version. The CURRENT sheet is the highest version — derived, never a flag, '
  'because maintaining a flag would need the UPDATE grant rf_api does not have (CLAUDE.md rule 2).';

-- Append-only, and the version order is the server's. A client that re-publishes version 1 after
-- version 2 exists would otherwise silently un-rotate a sheet the user believes they invalidated.
--
-- ADR 2026-09-05b §7: rate limiting is a legitimate server power and a refusal is always NAMED.
-- One publication per minute bounds an append-only table nothing else bounds.
create or replace function rf.recovery_sheet_guard() returns trigger
language plpgsql as $$
declare hi int; last timestamptz;
begin
  if TG_OP <> 'INSERT' then
    raise exception 'append_only' using errcode = '23514',
      detail = 'a sealed sheet blob is never rewritten; a new sheet is the next version (04 §7.4)';
  end if;
  select coalesce(max(s.sheet_version), 0), max(s.created_at) into hi, last
    from recovery_sheets s where s.user_id = new.user_id;
  if new.sheet_version <> hi + 1 then
    raise exception 'sheet_version_out_of_order' using errcode = '23514',
      detail = 'a regenerated sheet publishes the NEXT version; an older version can never be added behind a live one (04 §7.4)';
  end if;
  if last is not null and last > now() - interval '60 seconds' then
    raise exception 'sheet_flood' using errcode = '23514',
      detail = 'one sheet publication per minute (ADR 2026-09-05b §7)';
  end if;
  new.created_at := now();
  new.updated_at := new.created_at;
  return new;
end $$;
create trigger recovery_sheets_guard before insert or update or delete on recovery_sheets
  for each row execute function rf.recovery_sheet_guard();

-- ---------------------------------------------------------------- RLS, policies, grants
alter table recovery_sheets enable row level security;
alter table recovery_sheets force row level security;

-- SELECT + INSERT only. There is no UPDATE and no DELETE grant for rf_api anywhere in this file,
-- which is what makes "write-once" a property of the database rather than of the edge function.
grant select, insert on recovery_sheets to rf_api;

-- The read: the caller's OWN user. Deliberately NOT gated on rf.is_certified() — see the ⚠️ SPEC
-- block above; this is the one read rung 3 cannot live without, and it is bounded to one user's
-- own sealed bytes.
create policy recovery_sheets_select on recovery_sheets for select to rf_api
  using (user_id = rf.user_id());

-- The write: only a CERTIFIED device of that same user. A sheet is printed by a device that already
-- holds the UMK (04 §7.4: "generated at signup"), so nothing legitimate needs the uncertified path,
-- and allowing it would let a SIM-swapped phone bury the real sheet under a version of its own.
create policy recovery_sheets_insert on recovery_sheets for insert to rf_api
  with check (rf.is_certified() and user_id = rf.user_id());

-- Retention only (03 §6, ADR 2026-09-05b §8). Deletion is the maintenance role's, never the API's.
grant select, delete on recovery_sheets to rf_maintenance;
create policy recovery_sheets_maint on recovery_sheets for all to rf_maintenance using (true);

-- 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before this existed.
revoke all on function rf.recovery_sheet_guard() from public;

-- ---------------------------------------------------------------- retention sweep (maintenance)
-- Superseded sheets only, 30 days after they were replaced. The CURRENT sheet is never swept: it is
-- the user's last way back in, and 04 §7.4 makes it mandatory for solo users.
create or replace function rf.sweep_recovery_sheets() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from recovery_sheets s
    where s.created_at <= now() - interval '30 days'
      and exists (select 1 from recovery_sheets t
                  where t.user_id = s.user_id and t.sheet_version > s.sheet_version);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function rf.sweep_recovery_sheets() from public;
grant execute on function rf.sweep_recovery_sheets() to rf_maintenance;
