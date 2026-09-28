-- 0015 — the invitee is handed its own invite's nonce (ADR 2026-09-25b §1–§2 🔒, 04 §6.1 as amended).
-- ⟦tests: E-25b-1, E-25b-2⟧
--
-- What was already built, and stays exactly as built:
--   * the INVITER's device draws the 128-bit nonce and signs it into its `invite` record
--     `{roles, nonce}` (0008); POST /sync-meta/invites passes `payload.nonce` to rf.create_invite,
--     which stores it (0006:182-193). The server never chooses a nonce and never alters one.
--   * `invites.nonce` is 16 bytes (0006 `invites_nonce_128`) and immutable once issued
--     (rf.invite_guard, 0006/0008). No column, CHECK or trigger changes here.
--   * rf_api holds NO SELECT on `invites.nonce` (or `invitee_hmac`) — 0006's column grant. That is
--     kept, so the meta pull's `invites` rows still carry no nonce, a co-admin still cannot read
--     it, and no caller can filter on it: there is no lookup by nonce (ADR 2026-09-25b §2).
--
-- What changes: rf.my_invites(), the one read a joining device has, now
--   (a) returns `nonce`, and
--   (b) widens from "at `sent`, addressed to my number" to "at `sent` addressed to my number, OR
--       accepted by me" — either way still inside the invite's own 7-day window (`expires_at`,
--       fixed at issue). An accepted invite therefore stays reachable for S9.2 after a restart,
--       which is when the ceremony runs, without the device keeping a copy.
--   (c) ⚠️ SPEC (repair, M11-INV1 review finding 1): returns the invite's `status` — only ever
--       'sent' or 'accepted' here — and lists the `sent` rows first. ADR 2026-09-25b §2 names only
--       `nonce` as the new field, but once (b) puts a spent invite on the same list as the live
--       offers, a reader cannot tell them apart without it, and an order by expiry alone put the
--       older, already-accepted invite ahead of a newer live one: S0.9 with no invite id takes the
--       first row, so it offered the spent invite, the accept failed `invite_not_live`, and the
--       live invite was unreachable from that screen. `status` is the column the meta pull's
--       `invites` rows already carry under the same name (0006 grant); it tells the caller only
--       what it did itself, so the scope below is unchanged. Owner to confirm on the ADR.
-- Scope is otherwise unchanged: keyed on the caller's user claim, the caller's OTP-verified
-- `users.phone_hmac` and `invites.accepted_by`; an erased user reads nothing. A second user,
-- another tenant's admin and an uncertified stranger see nothing (E-25b-2). A recycled number
-- (the accepter erased, a new user on the same number) does not inherit an accepted invite: the
-- `sent` branch requires `sent`, and the accepted branch requires `accepted_by = caller`.
--
-- Migrations are append-only: 0006 is untouched. The return type changes, and Postgres cannot
-- CREATE OR REPLACE across a changed RETURNS TABLE, so the 0-argument function is dropped and
-- created again, grants included. No view or function depends on it; its one caller is the edge
-- function (store_pg.ts myInvites / acceptInvite).
-- CLAUDE.md rule 2: nothing here touches `envelopes`, and no table grant is added.

drop function rf.my_invites();

create function rf.my_invites()
returns table (id uuid, tenant_id uuid, roles jsonb, expires_at timestamptz, created_by uuid,
               status text, nonce bytea)
language sql stable security definer set search_path = public as $$
  select i.id, i.tenant_id, i.roles, i.expires_at, i.created_by, i.status, i.nonce
  from invites i join users u on u.id = rf.user_id()
  where u.erased_at is null
    and i.expires_at > now()
    and (   (i.status = 'sent' and u.phone_hmac is not null and i.invitee_hmac = u.phone_hmac)
         or (i.status = 'accepted' and i.accepted_by = u.id))
  -- live offers first (c), then soonest-closing, then id: a stable order the MemStore mirrors
  order by (i.status <> 'sent'), i.expires_at, i.id
$$;

comment on function rf.my_invites() is
  'The caller''s own invites — at sent and addressed to its OTP-verified number, or accepted by it — inside the 7-day window, with the inviter-drawn nonce (ADR 2026-09-25b §2) and the invite status (sent | accepted), live offers first. The only rf_api read of invites.nonce.';

-- 0005's blanket `grant execute on all functions in schema rf to rf_api` ran before this existed,
-- and a dropped function takes its grants with it: name them again, and keep PUBLIC out.
revoke all on function rf.my_invites() from public;
grant execute on function rf.my_invites() to rf_api;
