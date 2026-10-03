// GET /sync-meta/recovery/has-guardian-set — ADR 2026-09-24b §3 🔒 (amends ADR 2026-09-05d §2 by one
// read) for 04 §7.3's rung 2. The database half is tests/rls/has_guardian_set.test.ts; this is what
// the client meets on the wire.
//
// The route exists so the uncertified phone on S11.6 can tell `noTrustedMembers` from `unknown`
// (recovery_ladder_source.dart's rung-2 probe cannot today: the meta pull's `guardian_sets` is
// certified-only and filters to `[]`). So the tests hold it to four things:
//   * an UNCERTIFIED caller gets its own user's answer — the one thing the ADR adds;
//   * the body is EXACTLY `{has_guardian_set: <boolean>}` — no k, n, version, member or share;
//   * nothing a caller sends (a `subject_user_id`, a request id) can move the answer to somebody
//     else, and people close to the subject read only their own bit;
//   * the bit agrees with what the open itself answers;
//   * REFUSED, never a false denial (desk 45, owner 3 Oct 2026; ADR 2026-10-03 § Desk 45; 0025):
//     a revoked device, a device that is not the caller user's and an erased user get ONE answer,
//     403 `unknown_request` — the very answer the open gives the same caller — never `false`, which
//     S11.6 renders as "you set nobody up" (04 §7.3 🔒). The client reads any non-2xx as `unknown`.
//     This superseded 0016's reading (b), whose `false` arms E-24b-1 asserted until 0025.
// Ids E-24b-1 (0016 readings (a) and (c), kept as built — live callers only), E-24b-3 (the
// refusal), E-24b-4 (parity under it) — the route half, with MemStore held to PgStore's refusal.
import { assert, assertEquals, assertRejects } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { StoreDenied } from "../_shared/store.ts";
import { mintAccessToken } from "../_shared/claims.ts";
import { handler as meta } from "../sync-meta/index.ts";
import { body, get, member, post, random, type Rig, rig } from "./harness.ts";

const PATH = "/sync-meta/recovery/has-guardian-set";

interface Who {
  user: string;
  device: { id: string };
}
function tok(r: Rig, w: Who): Promise<string> {
  return mintAccessToken(
    r.deps.jwtKey,
    { user_id: w.user, device_id: w.device.id },
    Math.floor(r.clock.now.getTime() / 1000),
  );
}
async function ask(r: Rig, w: Who, query = ""): Promise<{ status: number; json: unknown }> {
  const res = await meta(get(`${PATH}${query}`, { token: await tok(r, w) }), r.deps);
  return { status: res.status, json: await body(res) };
}
/** The answer, with the exact-shape check every read of it must pass. */
async function bit(r: Rig, w: Who, query = ""): Promise<boolean> {
  const { status, json } = await ask(r, w, query);
  assertEquals(status, 200);
  assertEquals(
    Object.keys(json as Record<string, unknown>),
    ["has_guardian_set"],
    "exactly one key — no k, no n, no version, no member, no share (ADR 2026-09-24b §3)",
  );
  const v = (json as { has_guardian_set: unknown }).has_guardian_set;
  assertEquals(typeof v, "boolean", "a boolean, never null or a count");
  return v as boolean;
}

/** A tenant with a subject who published a complete 2-of-3 set, its three guardians, a tenant-mate
 *  who is not a guardian, a stranger in another tenant, and the subject's fresh (registered) phone. */
async function world() {
  const r = rig();
  const t1 = r.db.addTenant(), t2 = r.db.addTenant();
  const subject = await member(r, t1, null, null);
  const g = [await member(r, t1, null, null), await member(r, t1, null, null)];
  g.push(await member(r, t1, null, null));
  const bystander = await member(r, t1, null, null);
  const stranger = await member(r, t2, null, null);
  r.db.addGuardianSet(
    subject.user,
    1,
    2,
    await Promise.all(g.map(async (x) => ({ user_id: x.user, umk_pub_ed: await random(32) }))),
  );
  const candidate = {
    user: subject.user,
    device: r.db.addDevice(subject.user, await random(32), await random(32), "registered"),
  };
  return { r, t1, subject, g, bystander, stranger, candidate };
}

Deno.test("E-24b-1 the UNCERTIFIED candidate phone learns its own user's bit, and the body is exactly {has_guardian_set: true} — a user with no set reads exactly {has_guardian_set: false}", async () => {
  const { r, subject, stranger, candidate } = await world();
  assertEquals(r.db.devices.get(candidate.device.id)!.status, "registered", "precondition");
  assertEquals(await bit(r, candidate), true, "not gated on certification (ADR 2026-09-24b §3)");
  assertEquals(await bit(r, subject), true, "the certified device of the same user agrees");

  const strangerRaw = {
    user: stranger.user,
    device: r.db.addDevice(stranger.user, await random(32), await random(32), "registered"),
  };
  assertEquals(await bit(r, strangerRaw), false);
  assertEquals(await bit(r, stranger), false);

  // The whole body, not just the key: nothing from the set rides along with `true` — not even a
  // store_epoch or a cursor, which every other sync-meta body carries.
  const { json } = await ask(r, candidate);
  assertEquals(json, { has_guardian_set: true });
  assert(!JSON.stringify(json).includes(subject.user), "no user id, the caller's included");
});

Deno.test("E-24b-1 nobody else's answer leaks through the route: a `subject_user_id` (or any other parameter) is ignored, and a tenant-mate, a guardian OF the subject and a stranger each read only their own bit", async () => {
  const { r, subject, g, bystander, stranger } = await world();
  // The stranger asks about the subject by name. The route does not read the parameter at all.
  assertEquals(await bit(r, stranger, `?subject_user_id=${subject.user}`), false);
  assertEquals(
    await bit(r, stranger, `?user_id=${subject.user}&request_id=${subject.user}`),
    false,
  );
  // …and the subject naming somebody without a set still gets its OWN answer.
  assertEquals(await bit(r, subject, `?subject_user_id=${stranger.user}`), true);

  assertEquals(await bit(r, bystander), false, "shares the tenant, has no set of its own");
  for (const x of g) assertEquals(await bit(r, x), false, "a guardian OF the subject has no set");

  // The stranger's answer does not move when somebody else's set does.
  const late = await member(r, r.db.addTenant(), null, null);
  assertEquals(await bit(r, late), false);
  r.db.addGuardianSet(late.user, 1, 2, [
    { user_id: g[0].user, umk_pub_ed: await random(32) },
    { user_id: g[1].user, umk_pub_ed: await random(32) },
  ]);
  assertEquals(await bit(r, late), true, "the bit follows the caller's own set");
  assertEquals(await bit(r, stranger), false, "and only the caller's");
});

/** The whole refused response — status and raw body — so two refusals compare byte for byte. */
async function refusedRaw(r: Rig, w: Who): Promise<string> {
  const res = await meta(get(PATH, { token: await tok(r, w) }), r.deps);
  return `${res.status} ${await res.text()}`;
}
const ONE_REFUSAL = `403 ${JSON.stringify({ error: "unknown_request" })}`;

Deno.test("E-24b-1 a SUSPENDED device is answered (0016 reading (c), kept as built by the desk-45 ruling), and an unauthenticated call is 401 with no body to read", async () => {
  const { r, subject } = await world();
  const suspended = r.db.addDevice(subject.user, await random(32), await random(32), "suspended");
  assertEquals(await bit(r, { user: subject.user, device: suspended }), true, "(c) as built");

  const anon = await meta(get(PATH), r.deps);
  assertEquals(anon.status, 401);
  assertEquals((await body(anon)).error, "unauthenticated");
});

Deno.test("E-24b-3 REFUSED, never a false denial (desk 45, 0025): a revoked device, a device that is not the caller user's and an erased user each get ONE response — 403 {error: unknown_request}, byte-identical whether or not the user holds a set — and MemStore refuses by PgStore's name, `unknown_candidate_device`; a live caller with no set still reads false", async () => {
  const { r, subject, stranger } = await world();
  const revoked = r.db.addDevice(subject.user, await random(32), await random(32), "revoked");
  revoked.revoked_at = r.clock.now;
  const strangerRevoked = r.db.addDevice(
    stranger.user,
    await random(32),
    await random(32),
    "revoked",
  );
  strangerRevoked.revoked_at = r.clock.now;
  // A status row the projector has not caught up with yet still counts: revoked_at alone refuses,
  // as rf.device_live_for reads `status <> 'revoked' and revoked_at is null`.
  const stamped = r.db.addDevice(subject.user, await random(32), await random(32), "certified");
  stamped.revoked_at = r.clock.now;

  const erasedWithSet = await member(r, r.db.addTenant(), null, null);
  r.db.addGuardianSet(erasedWithSet.user, 1, 2, [
    { user_id: stranger.user, umk_pub_ed: await random(32) },
    { user_id: subject.user, umk_pub_ed: await random(32) },
  ]);
  r.db.users.get(erasedWithSet.user)!.erased_at = r.clock.now;
  const erasedBare = await member(r, r.db.addTenant(), null, null);
  r.db.users.get(erasedBare.user)!.erased_at = r.clock.now;

  const refusedCallers: [string, Who][] = [
    ["a REVOKED device of a user WITH a set", { user: subject.user, device: revoked }],
    ["a REVOKED device of a user with NO set", { user: stranger.user, device: strangerRevoked }],
    ["revoked_at stamped, status not yet moved", { user: subject.user, device: stamped }],
    ["my user, somebody else's device", { user: subject.user, device: stranger.device }],
    ["the set-holder's device under a user with no set", {
      user: stranger.user,
      device: subject.device,
    }],
    ["an ERASED user WITH a set", erasedWithSet],
    ["an ERASED user with NO set", erasedBare],
  ];
  for (const [why, w] of refusedCallers) {
    assertEquals(await refusedRaw(r, w), ONE_REFUSAL, `${why}: one refusal, never a boolean`);

    // MemStore mirrors PgStore: the store refuses by the database's name, it does not answer.
    const e = await assertRejects(
      () =>
        r.deps.store.withClaims(
          { user_id: w.user, device_id: w.device.id },
          (tx) => tx.hasGuardianSet(),
        ),
      StoreDenied,
    );
    assertEquals(e.reason, "unknown_candidate_device", why);
  }
  // No claims at all never reach the route (401 above); the store refuses them by the same name.
  const none = await assertRejects(
    () => r.deps.store.withClaims(null, (tx) => tx.hasGuardianSet()),
    StoreDenied,
  );
  assertEquals(none.reason, "unknown_candidate_device");

  // The refusal is about the caller, not the set: live answers are unchanged, both ways.
  assertEquals(await bit(r, stranger), false, "live, no set → still exactly {false}");
  assertEquals(await bit(r, subject), true, "live, a set → still exactly {true}");
});

Deno.test("E-24b-4 parity under the refusal: for the same revoked (by status or by revoked_at alone) or foreign caller, GET has-guardian-set and the rung-2 open (POST /sync-meta/recovery) give the SAME response, 403 {error: unknown_request}; a live caller gets neither", async () => {
  const { r, subject, stranger, candidate } = await world();
  const open = async (w: Who) => {
    const res = await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(await random(32)) }, {
        token: await tok(r, w),
      }),
      r.deps,
    );
    return `${res.status} ${await res.text()}`;
  };
  const revoked = r.db.addDevice(subject.user, await random(32), await random(32), "revoked");
  revoked.revoked_at = r.clock.now;
  // revoked_at stamped, status not yet moved: rf.device_live_for (0010) reads BOTH fields, for the
  // bit (0025) and the open (0010's guard) alike — so MemStore's open must refuse it too, or the
  // parity above holds only because `revoked` sets both.
  const stamped = r.db.addDevice(subject.user, await random(32), await random(32), "certified");
  stamped.revoked_at = r.clock.now;
  for (
    const w of [
      { user: subject.user, device: revoked },
      { user: subject.user, device: stamped },
      { user: subject.user, device: stranger.device },
      { user: stranger.user, device: candidate.device },
    ]
  ) {
    assertEquals(await refusedRaw(r, w), ONE_REFUSAL);
    assertEquals(await open(w), ONE_REFUSAL, "the open refuses the same caller identically");
  }
  const strangerRaw = {
    user: stranger.user,
    device: r.db.addDevice(stranger.user, await random(32), await random(32), "registered"),
  };
  assertEquals(await bit(r, strangerRaw), false);
  assert(!(await open(strangerRaw)).startsWith("403"), "a live caller is not refused by the open");
  assertEquals(await bit(r, candidate), true);
  assert((await open(candidate)).startsWith("200"), "…and a live caller with a set opens");
});

Deno.test("E-24b-1 for a LIVE caller the bit agrees with the open: false ⇔ POST /sync-meta/recovery refuses no_guardian_set, true for a set short of n members (⚠️ SPEC 0016 (a)), and only GET answers — a caller that is not a live device of its own live user is refused by both, never false (E-24b-3, E-24b-4)", async () => {
  const { r, candidate, stranger, g } = await world();
  const open = async (w: Who) =>
    await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(await random(32)) }, {
        token: await tok(r, w),
      }),
      r.deps,
    );

  // no set: false, and the open says the same thing by name
  const strangerRaw = {
    user: stranger.user,
    device: r.db.addDevice(stranger.user, await random(32), await random(32), "registered"),
  };
  assertEquals(await bit(r, strangerRaw), false);
  const refused = await open(strangerRaw);
  assertEquals(refused.status, 409);
  assertEquals((await body(refused)).error, "no_guardian_set");

  // a published set short of n: the bit is existence, the open names the readiness refusal
  const short = await member(r, r.db.addTenant(), null, null);
  r.db.addGuardianSet(short.user, 1, 2, [{ user_id: g[0].user, umk_pub_ed: await random(32) }]);
  r.db.guardian_sets.at(-1)!.n = 3; // published as 3, one member uploaded
  const shortRaw = {
    user: short.user,
    device: r.db.addDevice(short.user, await random(32), await random(32), "registered"),
  };
  assertEquals(await bit(r, shortRaw), true);
  const incomplete = await open(shortRaw);
  assertEquals(incomplete.status, 409);
  assertEquals((await body(incomplete)).error, "guardian_set_incomplete");

  // a complete set: true, and the open succeeds
  assertEquals(await bit(r, candidate), true);
  assertEquals((await open(candidate)).status, 200);

  // superseded-only: false, and the open agrees
  const gone = await member(r, r.db.addTenant(), null, null);
  r.db.addGuardianSet(gone.user, 1, 2, [
    { user_id: g[0].user, umk_pub_ed: await random(32) },
    { user_id: g[1].user, umk_pub_ed: await random(32) },
  ]);
  r.db.guardian_sets.at(-1)!.superseded_at = r.clock.now;
  assertEquals(await bit(r, gone), false);
  assertEquals((await body(await open(gone))).error, "no_guardian_set");

  // Only GET is a read. A POST to the same path is not a route.
  const p = await meta(post(PATH, {}, { token: await tok(r, candidate) }), r.deps);
  assertEquals(p.status, 404);
});
