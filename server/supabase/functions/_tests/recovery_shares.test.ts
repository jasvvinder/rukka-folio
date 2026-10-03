// GET /sync-meta/recovery/shares?request_id= — the server half of 04 §7.3 🔒 step 4 (migration 0020).
// The database half is tests/rls/recovery_shares.test.ts; this is what the recovering phone meets on
// the wire, against the MemStore restatement of the same rules.
//
// Before this route existed, the only way a re-sealed share reached the fresh phone was the meta
// pull's wrapped_keys page. That page served each share as soon as its guardian approved: before k,
// and inside the 24 h wait that ADR 2026-09-05d §1 🔒 puts in front of steps 4–6. So the tests hold
// the route to three things and the meta pull to one:
//   * the uncertified phone that OPENED an attempt gets that attempt's shares, and only once the
//     attempt is `approved`, in exactly the documented shape;
//   * every other case is the SAME 404 with the same body: a stranger, a guardian, the subject's
//     own certified device, another fresh phone, an attempt that does not exist, one not yet
//     approved, cancelled, expired, or asked for from a revoked device. The route is no oracle
//     for whose recovery is in flight (the BIL1 / 0010 `unknown_request` precedent);
//   * nothing a caller adds to the query moves the answer to anybody else;
//   * the meta pull carries no recovery_blob row to anyone.
// Ids E-06-77 … E-06-79 and E-06-81.
import { assert, assertEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { mintAccessToken } from "../_shared/claims.ts";
import { handler as meta } from "../sync-meta/index.ts";
import { advance, body, get, member, post, random, type Rig, rig } from "./harness.ts";

interface Who {
  user: string;
  device: { id: string };
}
/** A token at the CURRENT clock (06 §4: 15 minutes). These tests travel hours. */
function tok(r: Rig, w: Who): Promise<string> {
  return mintAccessToken(
    r.deps.jwtKey,
    { user_id: w.user, device_id: w.device.id },
    Math.floor(r.clock.now.getTime() / 1000),
  );
}
const eq = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((x, i) => x === b[i]);

async function fetchShares(r: Rig, w: Who, query: string) {
  const res = await meta(
    get(`/sync-meta/recovery/shares${query}`, { token: await tok(r, w) }),
    r.deps,
  );
  return { status: res.status, text: await res.text() };
}
const metaPull = async (r: Rig, w: Who) =>
  await body(await meta(get("/sync-meta", { token: await tok(r, w) }), r.deps));

/** A tenant with a subject, three guardians of a 2-of-3 set published through the route, a
 *  tenant-mate, a stranger, and the subject's two fresh (registered) phones. With `immediate`, the
 *  subject's certified phone is lost first, so the attempt runs on the no-wait ladder. */
async function world(opts: { immediate: boolean }) {
  const r = rig();
  const t1 = r.db.addTenant();
  const subject = await member(r, t1, null, null);
  const g = [
    await member(r, t1, null, null),
    await member(r, t1, null, null),
    await member(r, t1, null, null),
  ];
  const bystander = await member(r, t1, null, null);
  const stranger = await member(r, r.db.addTenant(), null, null);
  const guardians = [];
  for (const x of g) {
    guardians.push({
      guardian_user_id: x.user,
      umk_pub_ed: b64url.enc(await random(32)),
      blob: b64url.enc(await random(80)),
    });
  }
  const pub = await meta(
    // tenant_id: the tenant the set is set up in (ADR 2026-10-03b §1, 0026).
    post("/sync-meta/recovery/guardians", {
      share_set_version: 1,
      tenant_id: t1,
      n: 3,
      k: 2,
      guardians,
    }, { token: await tok(r, subject) }),
    r.deps,
  );
  assertEquals(pub.status, 200);
  const phone = (await random(32)).slice();
  const fresh = {
    user: subject.user,
    device: r.db.addDevice(subject.user, await random(32), await random(32), "registered"),
  };
  const fresh2 = {
    user: subject.user,
    device: r.db.addDevice(subject.user, await random(32), await random(32), "registered"),
  };
  if (opts.immediate) {
    subject.device.status = "revoked";
    subject.device.revoked_at = r.clock.now;
  }
  const opened = await body(
    await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(phone) }, {
        token: await tok(r, fresh),
      }),
      r.deps,
    ),
  );
  assertEquals(opened.opened_state, opts.immediate ? "pending" : "waiting_24h");
  return { r, subject, g, bystander, stranger, fresh, fresh2, phone, req: opened.request_id };
}

async function approve(r: Rig, g: Who, request: string, sealedTo: Uint8Array) {
  const blob = await random(96);
  const res = await meta(
    post("/sync-meta/recovery/approve", {
      request_id: request,
      sealed_to_pub_x: b64url.enc(sealedTo),
      blob: b64url.enc(blob),
    }, { token: await tok(r, g) }),
    r.deps,
  );
  assertEquals(res.status, 200);
  return blob;
}

Deno.test("E-06-77 the uncertified phone that opened an attempt gets its shares only once the attempt is approved, in exactly the documented shape: {request_id, shares:[{wrapped_key_id, guardian_user_id, candidate_device, sealed_to_pub_x, share_set_version, blob, approved_at}]}, the blobs byte-for-byte the guardians' (04 §7.3 step 4; ADR 2026-09-05d §1)", async (t) => {
  await t.step("the immediate ladder: nothing at 0 or 1 of 2, the k shares at 2 of 2", async () => {
    const w = await world({ immediate: true });
    const q = `?request_id=${w.req}`;
    assertEquals((await fetchShares(w.r, w.fresh, q)).status, 404, "0 of 2");
    const b1 = await approve(w.r, w.g[0], w.req, w.phone);
    assertEquals(
      (await fetchShares(w.r, w.fresh, q)).status,
      404,
      "1 of 2: the share exists, it stays",
    );
    const b2 = await approve(w.r, w.g[1], w.req, w.phone);

    const res = await fetchShares(w.r, w.fresh, q);
    assertEquals(res.status, 200);
    const b = JSON.parse(res.text);
    assertEquals(Object.keys(b).sort(), ["request_id", "shares"]);
    assertEquals(b.request_id, w.req);
    assertEquals(b.shares.length, 2);
    for (const s of b.shares) {
      assertEquals(
        Object.keys(s).sort(),
        [
          "approved_at",
          "blob",
          "candidate_device",
          "guardian_user_id",
          "sealed_to_pub_x",
          "share_set_version",
          "wrapped_key_id",
        ],
        "the share and its addressing; nothing about books, tenants or other keys",
      );
      assertEquals(s.candidate_device, w.fresh.device.id);
      assert(eq(b64url.dec(s.sealed_to_pub_x), w.phone), "sealed to THIS attempt's candidate key");
      assertEquals(s.share_set_version, 1);
      assertEquals(
        typeof s.approved_at,
        "number",
        "epoch ms, like every timestamp on this channel",
      );
    }
    const byG = new Map(b.shares.map((s: any) => [s.guardian_user_id, b64url.dec(s.blob)]));
    assert(eq(byG.get(w.g[0].user) as Uint8Array, b1), "g1's bytes, unchanged");
    assert(eq(byG.get(w.g[1].user) as Uint8Array, b2), "g2's bytes, unchanged");
  });

  await t.step("the waiting ladder: 404 through the 24 h wait, 200 once it has run", async () => {
    const w = await world({ immediate: false });
    const q = `?request_id=${w.req}`;
    await approve(w.r, w.g[0], w.req, w.phone);
    await approve(w.r, w.g[1], w.req, w.phone);
    assertEquals((await fetchShares(w.r, w.fresh, q)).status, 404, "k approvals, the wait runs");
    advance(w.r, 23 * 3600e3);
    assertEquals((await fetchShares(w.r, w.fresh, q)).status, 404, "an hour short is still short");
    advance(w.r, 3600e3);
    const res = await fetchShares(w.r, w.fresh, q);
    assertEquals(res.status, 200, "24 h after the k-th approval (04 §7.3 step 6)");
    assertEquals(JSON.parse(res.text).shares.length, 2);
  });
});

Deno.test("E-06-78 every case that is not a release is the SAME 404 with the same body, so the route is no oracle for whose recovery exists or where it stands: another user, a tenant-mate, a guardian who sealed a share, the subject's own certified device, the subject's other fresh phone, an unknown attempt, one not yet approved, one cancelled, one expired, and the opener on a revoked device; a malformed request is 400, no token 401, and no extra query parameter moves the answer (ADR 2026-09-05d §2; 0010 unknown_request)", async (t) => {
  const answers: [string, { status: number; text: string }][] = [];

  await t.step("on an attempt that IS approved, only the opener is answered", async () => {
    const w = await world({ immediate: false });
    await approve(w.r, w.g[0], w.req, w.phone);
    await approve(w.r, w.g[1], w.req, w.phone);
    advance(w.r, 24 * 3600e3);
    const q = `?request_id=${w.req}`;
    assertEquals((await fetchShares(w.r, w.fresh, q)).status, 200, "the opener");
    for (
      const [who, x] of [
        ["another user", w.stranger],
        ["a tenant-mate", w.bystander],
        ["the guardian who sealed a share", w.g[0]],
        ["a guardian who did not answer", w.g[2]],
        ["the subject's own certified device", w.subject],
        ["the subject's other fresh phone", w.fresh2],
      ] as const
    ) answers.push([who, await fetchShares(w.r, x, q)]);
    answers.push([
      "an attempt that does not exist",
      await fetchShares(
        w.r,
        w.fresh,
        `?request_id=${crypto.randomUUID()}`,
      ),
    ]);

    // Nothing in the query is read but request_id: no subject, no device, no user.
    for (
      const extra of [
        `&device_id=${w.fresh.device.id}`,
        `&user_id=${w.subject.user}`,
        `&subject_user_id=${w.subject.user}`,
      ]
    ) {
      answers.push([
        `a stranger adding ${extra.split("=")[0]}`,
        await fetchShares(w.r, w.stranger, q + extra),
      ]);
    }
    const plain = await fetchShares(w.r, w.fresh, q);
    const junk = await fetchShares(w.r, w.fresh, `${q}&device_id=${w.fresh2.device.id}`);
    assertEquals(junk, plain, "the opener's answer is its own whatever else it sends");

    // The opener on a revoked phone (06 §6, ADR 2026-09-05d §3): its token is still in date.
    w.fresh.device.status = "revoked";
    (w.fresh.device as { revoked_at: Date | null }).revoked_at = w.r.clock.now;
    answers.push(["the opener, revoked", await fetchShares(w.r, w.fresh, q)]);
  });

  await t.step("the opener's own attempts that are not approved", async () => {
    const pending = await world({ immediate: true });
    await approve(pending.r, pending.g[0], pending.req, pending.phone);
    answers.push([
      "its own attempt, 1 of 2",
      await fetchShares(pending.r, pending.fresh, `?request_id=${pending.req}`),
    ]);

    const expired = await world({ immediate: true });
    await approve(expired.r, expired.g[0], expired.req, expired.phone);
    advance(expired.r, 72 * 3600e3 + 1000);
    answers.push([
      "its own attempt, expired",
      await fetchShares(expired.r, expired.fresh, `?request_id=${expired.req}`),
    ]);

    const cancelled = await world({ immediate: false });
    await approve(cancelled.r, cancelled.g[0], cancelled.req, cancelled.phone);
    await approve(cancelled.r, cancelled.g[1], cancelled.req, cancelled.phone);
    const c = await meta(
      post("/sync-meta/recovery/cancel", { request_id: cancelled.req }, {
        token: await tok(cancelled.r, cancelled.subject),
      }),
      cancelled.r.deps,
    );
    assertEquals(c.status, 200);
    advance(cancelled.r, 25 * 3600e3);
    answers.push([
      "its own attempt, cancelled",
      await fetchShares(cancelled.r, cancelled.fresh, `?request_id=${cancelled.req}`),
    ]);
  });

  await t.step("…and every one of those answers is byte-identical", () => {
    const first = answers[0][1];
    assertEquals(first.status, 404);
    assertEquals(JSON.parse(first.text), { error: "not_found" });
    for (const [who, a] of answers) {
      assertEquals(a, first, `${who} must read exactly what a nonexistent attempt reads`);
    }
    assertEquals(answers.length, 14, "every adversary above was actually asked");
  });

  await t.step("malformed and unauthenticated", async () => {
    const w = await world({ immediate: true });
    assertEquals((await fetchShares(w.r, w.fresh, "")).status, 400, "request_id is required");
    assertEquals((await fetchShares(w.r, w.fresh, "?request_id=nope")).status, 400);
    const anon = await meta(get(`/sync-meta/recovery/shares?request_id=${w.req}`), w.r.deps);
    assertEquals(anon.status, 401);
    const post_ = await meta(
      post("/sync-meta/recovery/shares", { request_id: w.req }, { token: await tok(w.r, w.fresh) }),
      w.r.deps,
    );
    assertEquals(post_.status, 404, "a read, GET only");
  });
});

Deno.test("E-06-79 the meta pull carries no recovery_blob row to anyone: not the opener, not the subject's certified device, not the sealing guardian. The gated route is the only way a share leaves, while every other wrapped-key kind still syncs (05 §5; 04 §7.3 step 6; 06 §10)", async () => {
  const w = await world({ immediate: false });
  await approve(w.r, w.g[0], w.req, w.phone);
  await approve(w.r, w.g[1], w.req, w.phone);
  // the shares exist, addressed to the candidate device…
  const filed = w.r.db.wrapped_keys.filter((k) => k.kind === "recovery_blob");
  assertEquals(filed.length, 2);
  assert(filed.every((k) => k.device_id === w.fresh.device.id && k.user_id === w.subject.user));
  // …and another wrapped key of the subject's that must still sync
  const umk = w.r.db.addWrappedKey({
    kind: "umk_for_device",
    user_id: w.subject.user,
    device_id: w.subject.device.id,
  });

  for (
    const [who, x] of [["the opener", w.fresh], ["the subject's certified device", w.subject], [
      "the sealing guardian",
      w.g[0],
    ]] as const
  ) {
    const rows = (await metaPull(w.r, x)).wrapped_keys as { kind: string; id: string }[];
    assertEquals(
      rows.filter((k) => k.kind === "recovery_blob").length,
      0,
      `${who}: no share in the meta pull`,
    );
  }
  const mine = (await metaPull(w.r, w.subject)).wrapped_keys as { id: string }[];
  assert(mine.some((k) => k.id === umk), "the subject's own umk_for_device still syncs");

  advance(w.r, 24 * 3600e3);
  assertEquals((await fetchShares(w.r, w.fresh, `?request_id=${w.req}`)).status, 200);
  const still = (await metaPull(w.r, w.fresh)).wrapped_keys as { kind: string }[];
  assertEquals(still.filter((k) => k.kind === "recovery_blob").length, 0, "not even once released");
});

Deno.test("E-06-81 the route asks the 24 h question again at release: an attempt opened on the immediate ladder is 404 once the user has an active certified device again, GET /sync-meta/recovery tells its opener waiting_24h with wait_until 24 h after the k-th approval, the newly certified device can Cancel it, and uncancelled it is 200 once the 24 h have run (ADR 2026-09-05d §1; 04 §7.3 step 6; 0020 section 4)", async (t) => {
  const progress = async (w: Awaited<ReturnType<typeof world>>) =>
    await body(
      await meta(
        get(`/sync-meta/recovery?request_id=${w.req}`, { token: await tok(w.r, w.fresh) }),
        w.r.deps,
      ),
    );

  await t.step("re-certified before k: the wait applies, and runs out", async () => {
    const w = await world({ immediate: true });
    const q = `?request_id=${w.req}`;
    w.fresh2.device.status = "certified"; // the owner is back on another phone
    assertEquals((await progress(w)).state, "waiting_24h", "the live ladder, not the opened one");
    await approve(w.r, w.g[0], w.req, w.phone);
    await approve(w.r, w.g[1], w.req, w.phone);
    assertEquals(
      (await fetchShares(w.r, w.fresh, q)).status,
      404,
      "k approvals behind a live device",
    );
    const p = await progress(w);
    assertEquals(p.opened_state, "pending");
    assertEquals(p.state, "waiting_24h");
    assertEquals(p.wait_until - p.kth_approval_at, 24 * 3600e3);
    advance(w.r, 23 * 3600e3);
    assertEquals((await fetchShares(w.r, w.fresh, q)).status, 404, "an hour short is still short");
    advance(w.r, 3600e3);
    const res = await fetchShares(w.r, w.fresh, q);
    assertEquals(res.status, 200, "24 h after the k-th approval");
    assertEquals(JSON.parse(res.text).shares.length, 2);
  });

  await t.step("the newly certified device holds the one-tap Cancel", async () => {
    const w = await world({ immediate: true });
    const q = `?request_id=${w.req}`;
    w.fresh2.device.status = "certified";
    await approve(w.r, w.g[0], w.req, w.phone);
    await approve(w.r, w.g[1], w.req, w.phone);
    const c = await meta(
      post("/sync-meta/recovery/cancel", { request_id: w.req }, {
        token: await tok(w.r, w.fresh2),
      }),
      w.r.deps,
    );
    assertEquals(c.status, 200);
    advance(w.r, 25 * 3600e3);
    assertEquals((await progress(w)).state, "cancelled");
    assertEquals((await fetchShares(w.r, w.fresh, q)).status, 404, "cancelled for good");
  });
});
