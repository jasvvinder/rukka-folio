// ADR 2026-10-03c §3 (desk 37) on the wire: a revoked device cannot read or accept its user's
// invites. Ids E-03c-1 (GET /sync-meta/invites) and E-03c-2 (POST /sync-meta/invites/accept) — the
// route half, with MemStore held to PgStore's refusal. The database half is
// tests/rls/invites_live_device.test.ts.
//
// 0028 gates rf.my_invites and rf.accept_invite on rf.device_live_for(device claim, user claim) and
// refuses with the rung-2 open's own name, 42501 `unknown_candidate_device` (0010, 0025). The edge
// maps it to the ONE wire answer the other device-gated routes give that caller — 403
// `{error: "unknown_request"}` (sync-meta recoveryError, E-24b-3) — so a revoked phone gets a
// refusal, never an empty list, and nothing on the wire tells revoked from foreign from "you have
// no invite". Live = `status <> 'revoked' and revoked_at is null`; each half is tested alone. A
// SUSPENDED device is live under that predicate, so it is answered and may accept (⚠️ SPEC, owner
// to confirm — lane report M13-INV37).
//
// Test honesty: every refusal is asserted by status AND body, and each has a live twin on the same
// invite that is answered — remove the gate from MemStore or the route mapping and this fails.
import { assertEquals, assertRejects } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { mintAccessToken } from "../_shared/claims.ts";
import { phoneHmac } from "../_shared/phone.ts";
import type { MemDevice } from "../_shared/store_mem.ts";
import { StoreDenied } from "../_shared/store.ts";
import { handler as meta } from "../sync-meta/index.ts";
import {
  advance,
  body,
  get,
  type Member,
  member,
  post,
  random,
  type Rig,
  rig,
  signedRecord,
} from "./harness.ts";

const PHONE = "+919876500037";
const ONE_REFUSAL = `403 ${JSON.stringify({ error: "unknown_request" })}`;

interface Fx {
  r: Rig;
  tenant: string;
  admin: Member;
  joiner: Member;
}
async function fixture(phone = PHONE): Promise<Fx> {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const admin = await member(r, tenant, book, "admin");
  const joiner = await member(r, r.db.addTenant(), null, null);
  r.db.users.get(joiner.user)!.phone_hmac = await phoneHmac(r.deps.phoneHmacKey, phone);
  return { r, tenant, admin, joiner };
}
async function issue(f: Fx, phone = PHONE): Promise<string> {
  const rec = await signedRecord(f.admin, f.tenant, "invite", {
    roles: [],
    nonce: b64url.enc(await random(16)),
  });
  const res = await meta(
    post("/sync-meta/invites", { record: rec.wire, phone }, { token: f.admin.token }),
    f.r.deps,
  );
  assertEquals(res.status, 200, "precondition: the admin issued the invite");
  return (await body(res)).invite_id as string;
}
/** Another device of `user`, in `status`, with `revoked_at` set independently of the status. */
async function device(
  r: Rig,
  user: string,
  status: MemDevice["status"],
  revokedAt = false,
): Promise<string> {
  const d = r.db.addDevice(user, await random(32), await random(32), status);
  if (revokedAt) d.revoked_at = r.clock.now;
  return d.id;
}
/** A token for (user, device) at the rig's current clock — the claim pair, whatever the device. */
function tok(r: Rig, user: string, device: string): Promise<string> {
  return mintAccessToken(
    r.deps.jwtKey,
    { user_id: user, device_id: device },
    Math.floor(r.clock.now.getTime() / 1000),
  );
}
async function list(r: Rig, user: string, dev: string): Promise<Response> {
  return await meta(get("/sync-meta/invites", { token: await tok(r, user, dev) }), r.deps);
}
async function accept(r: Rig, user: string, dev: string, id: string): Promise<Response> {
  return await meta(
    post("/sync-meta/invites/accept", { invite_id: id }, { token: await tok(r, user, dev) }),
    r.deps,
  );
}
const raw = async (res: Response) => `${res.status} ${await res.text()}`;
const offered = async (res: Response) => {
  assertEquals(res.status, 200);
  return ((await body(res)).invites as { invite_id: string; status: string }[]).map((
    i,
  ) => [i.invite_id, i.status]);
};
const inviteRow = (r: Rig, id: string) => {
  const i = r.db.invites.find((x) => x.id === id)!;
  return { status: i.status, accepted_by: i.accepted_by, accepted_at: i.accepted_at };
};
const membership = (f: Fx) =>
  f.r.db.memberships.find((m) => m.tenant_id === f.tenant && m.user_id === f.joiner.user)
    ?.status ?? null;

Deno.test("E-03c-1 GET /sync-meta/invites REFUSES a device that is not live — revoked (status + revoked_at), status `revoked` alone, `revoked_at` alone, another user's device — with ONE response, 403 {error: unknown_request}, byte-identical to a revoked caller who has no invite at all; the same user's certified, fresh (registered) and suspended devices get the offer", async () => {
  const f = await fixture();
  const id = await issue(f);
  const { r, joiner } = f;
  const fresh = await device(r, joiner.user, "registered");
  const suspended = await device(r, joiner.user, "suspended");
  const revoked = await device(r, joiner.user, "revoked", true);
  const statusOnly = await device(r, joiner.user, "revoked");
  const stampOnly = await device(r, joiner.user, "certified", true);
  const other = await member(r, r.db.addTenant(), null, null);

  // live twins: the same invite, answered
  assertEquals(await offered(await list(r, joiner.user, joiner.device.id)), [[id, "sent"]]);
  assertEquals(await offered(await list(r, joiner.user, fresh)), [[id, "sent"]]);
  // ⚠️ SPEC: rf.device_live_for counts a suspended device as live (0025 (c)), so it is answered.
  assertEquals(await offered(await list(r, joiner.user, suspended)), [[id, "sent"]]);

  for (
    const [who, dev] of [
      ["revoked (status + revoked_at)", revoked],
      ["status `revoked`, no revoked_at", statusOnly],
      ["revoked_at on a `certified` row", stampOnly],
      ["another user's live device", other.device.id],
    ] as const
  ) {
    assertEquals(await raw(await list(r, joiner.user, dev)), ONE_REFUSAL, `${who}: refused`);
  }
  // no oracle: a revoked device of a user with no invite gets the very same bytes
  const nobody = await member(r, r.db.addTenant(), null, null);
  const nobodyRevoked = await device(r, nobody.user, "revoked", true);
  assertEquals(await raw(await list(r, nobody.user, nobodyRevoked)), ONE_REFUSAL);
  // …and the parity desk 37 asks for: the recovery route gives this caller the same answer
  const rung2 = await meta(
    get("/sync-meta/recovery/has-guardian-set", {
      token: await tok(r, joiner.user, revoked),
    }),
    r.deps,
  );
  assertEquals(await raw(rung2), ONE_REFUSAL, "same refusal as the other device-gated routes");
});

Deno.test("E-03c-1 a device revoked AFTER reading its offers is refused on its still-valid token — also for the ACCEPTED invite's nonce (S9.2's read) — while the user's live device keeps reading; MemStore.myInvites rejects StoreDenied('unknown_candidate_device'), PgStore's name, for a revoked device and for no claims", async () => {
  const f = await fixture();
  const id = await issue(f);
  const { r, joiner } = f;
  const phone = await device(r, joiner.user, "certified");
  const token = await tok(r, joiner.user, phone); // minted while the device was live
  const read = (t: string) => meta(get("/sync-meta/invites", { token: t }), r.deps);
  assertEquals(await offered(await read(token)), [[id, "sent"]]);

  const acc = await accept(r, joiner.user, joiner.device.id, id);
  assertEquals(acc.status, 200, "the live device accepts");
  const d = r.db.devices.get(phone)!;
  d.status = "revoked";
  d.revoked_at = r.clock.now;
  assertEquals(await raw(await read(token)), ONE_REFUSAL, "the old token on the revoked phone");
  assertEquals(
    await offered(await list(r, joiner.user, joiner.device.id)),
    [[id, "accepted"]],
    "the live device still finds its spent invite's nonce",
  );

  const err = await assertRejects(
    () =>
      r.deps.store.withClaims(
        { user_id: joiner.user, device_id: phone },
        (tx) => tx.myInvites(),
      ),
    StoreDenied,
  );
  assertEquals(err.reason, "unknown_candidate_device");
  const none = await assertRejects(
    () => r.deps.store.withClaims(null, (tx) => tx.myInvites()),
    StoreDenied,
  );
  assertEquals(none.reason, "unknown_candidate_device", "no claims: no live device (0028)");
});

Deno.test("E-03c-2 POST /sync-meta/invites/accept REFUSES a revoked device (and status-only, timestamp-only, another user's device) with 403 {error: unknown_request} and changes NOTHING — invite still `sent`, unaccepted, no membership — then the user's live device accepts that very invite; an unknown id draws the same refusal, never invite_not_for_you", async () => {
  const f = await fixture();
  const id = await issue(f);
  const { r, joiner } = f;
  const revoked = await device(r, joiner.user, "revoked", true);
  const statusOnly = await device(r, joiner.user, "revoked");
  const stampOnly = await device(r, joiner.user, "certified", true);
  const other = await member(r, r.db.addTenant(), null, null);
  const before = inviteRow(r, id);
  assertEquals(before, { status: "sent", accepted_by: null, accepted_at: null });

  for (
    const [who, dev] of [
      ["revoked (status + revoked_at)", revoked],
      ["status `revoked`, no revoked_at", statusOnly],
      ["revoked_at on a `certified` row", stampOnly],
      ["another user's live device", other.device.id],
    ] as const
  ) {
    assertEquals(await raw(await accept(r, joiner.user, dev, id)), ONE_REFUSAL, `${who}`);
    assertEquals(inviteRow(r, id), before, `${who}: the invite is untouched`);
    assertEquals(membership(f), null, `${who}: no membership`);
  }
  // the gate comes before the lookup: a revoked device learns nothing about which ids exist
  assertEquals(
    await raw(await accept(r, joiner.user, revoked, crypto.randomUUID())),
    ONE_REFUSAL,
  );

  // the live twin
  const ok = await accept(r, joiner.user, joiner.device.id, id);
  assertEquals(ok.status, 200);
  assertEquals((await body(ok)).status, "joined_pending_verification");
  assertEquals([inviteRow(r, id).status, inviteRow(r, id).accepted_by], [
    "accepted",
    joiner.user,
  ]);
  assertEquals(membership(f), "joined_pending_verification");
});

Deno.test("E-03c-2 the gate runs before anything is touched: a revoked device on an EXPIRED invite is refused without flipping it to `expired` (a live device's call does flip it); MemStore.acceptInvite rejects StoreDenied('unknown_candidate_device'); a SUSPENDED device accepts (rf.device_live_for counts it live — ⚠️ SPEC, owner to confirm)", async () => {
  const f = await fixture();
  const id = await issue(f);
  const { r, joiner } = f;
  const revoked = await device(r, joiner.user, "revoked", true);

  const err = await assertRejects(
    () =>
      r.deps.store.withClaims(
        { user_id: joiner.user, device_id: revoked },
        (tx) => tx.acceptInvite(id),
      ),
    StoreDenied,
  );
  assertEquals(err.reason, "unknown_candidate_device");
  assertEquals(inviteRow(r, id).status, "sent");

  advance(r, 8 * 86400_000); // past 06 §7's 7-day window
  assertEquals(await raw(await accept(r, joiner.user, revoked, id)), ONE_REFUSAL);
  assertEquals(inviteRow(r, id).status, "sent", "the revoked device moved nothing");
  const late = await accept(r, joiner.user, joiner.device.id, id);
  assertEquals(late.status, 410, "a live device meets the window as before");
  assertEquals(inviteRow(r, id).status, "expired");

  // suspended: live under rf.device_live_for, so it may accept (⚠️ SPEC)
  const g = await fixture("+919876500038");
  const idG = await issue(g, "+919876500038");
  const suspended = await device(g.r, g.joiner.user, "suspended");
  const res = await accept(g.r, g.joiner.user, suspended, idG);
  assertEquals(res.status, 200);
  assertEquals(inviteRow(g.r, idG).accepted_by, g.joiner.user);
});
