-- M7 · ADR 2026-09-16 §2, §6 🔒 — **one device, one id.** The ledger mints `device_id` once at first
-- run (ADR 2026-09-16 §1) and bakes it into the device key pair, the self-certificate (04 §3.4),
-- every envelope's `author_device_id` and every signed record. A server-minted id made that key pair
-- two devices to every verifier: the cert for one never vouches for the other, and a revocation of
-- one never reaches the other. So `POST /devices` now carries the id and the server *records* it —
-- it never issues one.
--
-- Structural, not conventional: `devices.id` loses its default, so no server code path can mint a
-- device id even by omission. `rf.register_device` gains a leading `p_device`; the 6-argument
-- overload is DROPPED rather than kept, so a stale caller fails at bind time instead of silently
-- minting an id nobody's certificate names.
--
-- What now stops one device registering under another's id is the primary key on `devices.id`
-- (E-06-42). The JWT's `device_id` claim is still issued by `/token` from the row whose `pub_ed`
-- verified the signed challenge (`rf.device_auth_row`), never from anything the client says about
-- itself — so a client-chosen id buys no read beyond its own row under ADR 2026-09-05d §2, and no
-- RLS policy changes here. ⟦tests: E-06-40, E-06-41, E-06-42⟧

alter table devices alter column id drop default;
comment on column devices.id is
  'Minted by the client ledger at first run and carried in POST /devices (ADR 2026-09-16 §1–§2). No default: the server has no path that mints a device id.';

-- The 6-argument overload goes; a caller that has not been updated must fail at bind time.
drop function if exists rf.register_device(uuid, bytea, bytea, text, text, jsonb);

-- Record the client's id, or refuse. Idempotent for the same user with the same keys on a
-- non-revoked row (06 §5 *Reinstall, same iPhone*, sign-out then sign-in): the existing row is
-- returned, no second row is created and the device cap is not charged. Any other holder of the id
-- — another user, another key pair, a revoked row — is `device_id_taken`.
create function rf.register_device(p_device uuid, p_user uuid, p_pub_ed bytea, p_pub_x bytea,
  p_model text, p_os text, p_attestation jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare d devices%rowtype; n int;
begin
  select * into d from devices where id = p_device;
  if found then
    if d.user_id = p_user and d.pub_ed = p_pub_ed and d.pub_x = p_pub_x and d.status <> 'revoked' then
      return p_device;                                   -- same device, same keys: nothing to do
    end if;
    raise exception 'device_id_taken';
  end if;
  select count(*) into n from devices dd
    where dd.user_id = p_user and dd.status in ('registered','certified','suspended');
  if n >= rf.device_cap(p_user) then raise exception 'device_cap'; end if;
  insert into devices (id, user_id, pub_ed, pub_x, model, os, attestation)
  values (p_device, p_user, p_pub_ed, p_pub_x, p_model, p_os, p_attestation);
  return p_device;
exception
  -- A concurrent registration of the same id lost the race on the primary key: same refusal.
  when unique_violation then raise exception 'device_id_taken';
end $$;

-- 0005's blanket `grant execute on all functions in schema rf` ran once; a new function needs its own.
grant execute on function rf.register_device(uuid, uuid, bytea, bytea, text, text, jsonb) to rf_api;
