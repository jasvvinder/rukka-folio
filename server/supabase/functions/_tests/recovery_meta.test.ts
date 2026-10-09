// sync-meta's recovery routes — the WRITE side of rung 2 (04 §7.3 🔒 Setup and steps 1–7, 04 §7.4,
// 06 §5, 05 §5, ADR 2026-09-05d §1/§2, ADR 2026-09-06 §2, ADR 2026-09-13c §1/§3).
// The read side (guardian-set history, the wrapped keys addressed to the caller) is E-05-9 in
// sync_meta.test.ts and is extended here rather than duplicated.
// Ids E-06-43 … E-06-49.
import { assert, assertEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { mintAccessToken } from "../_shared/claims.ts";
import { handler as auth } from "../auth-challenge/index.ts";
import { handler as meta } from "../sync-meta/index.ts";
import {
  advance,
  body,
  certBytes,
  edKeypair,
  get,
  type Member,
  member,
  post,
  random,
  type Rig,
  rig,
  sign,
} from "./harness.ts";

/** Anyone who can hold a session: a `Member` from the harness, or a fresh candidate phone. */
interface Who {
  user: string;
  device: { id: string };
}

/** A token minted at the CURRENT clock. Access tokens live 15 minutes (06 §4) and these tests
 *  travel hours to reach the 24 h wait and the 72 h window, so a token is never reused across an
 *  `advance` — a 401 there would prove nothing about recovery. */
function tok(r: Rig, w: Who): Promise<string> {
  return mintAccessToken(
    r.deps.jwtKey,
    { user_id: w.user, device_id: w.device.id },
    Math.floor(r.clock.now.getTime() / 1000),
  );
}

/** 04 §7.3 step 1: the fresh phone. A registered device of the same user, never certified — that
 *  is the whole premise of rung 2 (06 §5 "New phone, no old device", ADR 2026-09-05d §2). */
async function candidate(r: Rig, user: string) {
  const device = r.db.addDevice(user, await random(32), await random(32), "registered");
  return { user, device, pub: await random(32) };
}

async function publish(
  r: Rig,
  subject: Who,
  guardians: Who[],
  over: Record<string, unknown> = {},
) {
  const g = [];
  for (const x of guardians) {
    g.push({
      guardian_user_id: x.user,
      umk_pub_ed: b64url.enc(await random(32)),
      blob: b64url.enc(await random(80)),
    });
  }
  // ADR 2026-10-03b §1 (0026): a set names the tenant it is set up in — here, the subject's own
  // (each test seeds one tenant, with the subject and every guardian in it). E-03b-5 holds the rule.
  const tenant_id = r.db.memberships.find((m) =>
    m.user_id === subject.user && m.status === "active"
  )?.tenant_id;
  return await meta(
    post("/sync-meta/recovery/guardians", {
      share_set_version: 1,
      tenant_id,
      n: guardians.length,
      k: Math.ceil((guardians.length + 1) / 2),
      guardians: g,
      ...over,
    }, { token: await tok(r, subject) }),
    r.deps,
  );
}

const approve = async (r: Rig, g: Who, request: string, sealedTo: Uint8Array, blob: Uint8Array) =>
  await meta(
    post("/sync-meta/recovery/approve", {
      request_id: request,
      sealed_to_pub_x: b64url.enc(sealedTo),
      blob: b64url.enc(blob),
    }, { token: await tok(r, g) }),
    r.deps,
  );

const deny = async (r: Rig, g: Who, request: string) =>
  await meta(
    post("/sync-meta/recovery/deny", { request_id: request }, { token: await tok(r, g) }),
    r.deps,
  );

const progress = async (r: Rig, w: Who, request: string) =>
  await meta(get(`/sync-meta/recovery?request_id=${request}`, { token: await tok(r, w) }), r.deps);

/** The caller's own meta pull — the channel a sealed share actually travels on (05 §5). */
const metaPull = async (r: Rig, w: Who) =>
  await body(await meta(get("/sync-meta", { token: await tok(r, w) }), r.deps));

Deno.test("E-06-43 publish a guardian set and its sealed shares at a new share_set_version: n = 2..5 with k = ceil((n+1)/2), one share per guardian addressed to them, a re-split is the NEXT version, and the server computes nothing (04 §7.3 Setup; ADR 2026-09-06 §2)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const subject = await member(r, tenant, book, "admin");
  const g1 = await member(r, tenant, null, null);
  const g2 = await member(r, tenant, null, null);
  const g3 = await member(r, tenant, null, null);

  await t.step("2-of-3 is the default shape, and it lands", async () => {
    const res = await publish(r, subject, [g1, g2, g3]);
    assertEquals(res.status, 200);
    assertEquals((await body(res)).share_set_version, 1);
  });

  await t.step("each guardian holds exactly one sealed share: its own", async () => {
    for (const g of [g1, g2, g3]) {
      const mine = (await body(await meta(get("/sync-meta", { token: await tok(r, g) }), r.deps)))
        .wrapped_keys;
      assertEquals(mine.length, 1);
      assertEquals(mine[0].kind, "guardian_share");
      assertEquals(mine[0].user_id, g.user);
      assertEquals(mine[0].share_set_version, 1);
      assertEquals(b64url.dec(mine[0].blob).length, 80, "opaque bytes, unchanged");
    }
    // The subject who uploaded them cannot read them back: a share is addressed to the guardian.
    const subjectSees =
      (await body(await meta(get("/sync-meta", { token: await tok(r, subject) }), r.deps)))
        .wrapped_keys;
    assertEquals(subjectSees.filter((w: any) => w.kind === "guardian_share").length, 0);
  });

  await t.step(
    "the set shows up in the history the read side already serves (E-05-9)",
    async () => {
      const m = await body(await meta(get("/sync-meta", { token: await tok(r, subject) }), r.deps));
      assertEquals(m.guardian_sets.length, 1);
      assertEquals(m.guardian_sets[0].k, 2);
      assertEquals(m.guardian_sets[0].n, 3);
      assertEquals(m.guardian_sets[0].guardian_user_ids.sort(), [g1.user, g2.user, g3.user].sort());
    },
  );

  await t.step("04 §7.3's allowed shapes, and only those", async () => {
    const s2 = await member(r, tenant, null, null);
    // n outside 2..5
    assertEquals((await publish(r, s2, [g1])).status, 400);
    const six = [];
    for (let i = 0; i < 6; i++) six.push(await member(r, tenant, null, null));
    assertEquals((await publish(r, s2, six)).status, 400);
    // k the client chose rather than the formula
    assertEquals((await publish(r, s2, [g1, g2, g3], { k: 1 })).status, 400);
    assertEquals((await publish(r, s2, [g1, g2, g3], { k: 3 })).status, 400);
    // a guardian is somebody else
    assertEquals((await publish(r, s2, [g1, s2, g3])).status, 400);
  });

  await t.step(
    "a re-split is the next version; an older one can never slip in behind",
    async () => {
      const again = await publish(r, subject, [g1, g2, g3]); // version 1 once more
      assertEquals(again.status, 400);
      assertEquals((await body(again)).error, "share_set_version_out_of_order");
      const next = await publish(r, subject, [g1, g2, g3], { share_set_version: 2 });
      assertEquals(next.status, 200);
      const m = await body(await meta(get("/sync-meta", { token: await tok(r, subject) }), r.deps));
      assertEquals(
        m.guardian_sets.map((s: any) => s.share_set_version),
        [1, 2],
        "both versions are kept — a revocation record names the version it was counted against",
      );
    },
  );
});

Deno.test("E-06-44 open a recovery request: the uncertified candidate device asks for ITSELF, carrying its candidate X25519 public key; the server pins the share set and picks the ladder — waiting_24h while any active certified device exists, pending when none does (04 §7.3 step 1; ADR 2026-09-05d §1/§2)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const subject = await member(r, tenant, null, null);
  const g1 = await member(r, tenant, null, null);
  const g2 = await member(r, tenant, null, null);
  const g3 = await member(r, tenant, null, null);
  const fresh = await candidate(r, subject.user);

  await t.step("without guardians rung 2 does not exist — fall through to 04 §7.4", async () => {
    const res = await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(fresh.pub) }, {
        token: await tok(r, fresh),
      }),
      r.deps,
    );
    assertEquals(res.status, 409);
    assertEquals((await body(res)).error, "no_guardian_set");
  });

  await publish(r, subject, [g1, g2, g3]);

  let req = "";
  await t.step("the fresh, uncertified phone opens its own attempt", async () => {
    const res = await meta(
      post("/sync-meta/recovery", {
        candidate_pub_x: b64url.enc(fresh.pub),
        // a client that simply asks for a state: ignored, not obeyed
        state: "approved",
        approvals: 99,
      }, { token: await tok(r, fresh) }),
      r.deps,
    );
    assertEquals(res.status, 200);
    const b = await body(res);
    req = b.request_id;
    assertEquals(b.candidate_device, fresh.device.id);
    assertEquals(b.candidate_pub_x, b64url.enc(fresh.pub));
    assertEquals(b.share_set_version, 1, "the attempt pinned the set it opened against");
    assertEquals(b.opened_state, "waiting_24h", "the subject still holds a certified device");
    const p = await body(await progress(r, fresh, req));
    assertEquals(p.approvals, 0, "the client's 99 reached nothing");
    assertEquals(p.k, 2);
    assertEquals(p.n, 3);
    assertEquals(p.expires_at, r.clock.now.getTime() + 72 * 3600e3, "72 h (04 §7.3 step 7)");
  });

  await t.step("a candidate key that is not 32 bytes is not a candidate key", async () => {
    const res = await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(await random(16)) }, {
        token: await tok(r, fresh),
      }),
      r.deps,
    );
    assertEquals(res.status, 400);
  });

  await t.step(
    "with no active certified device left, the ladder is the immediate one",
    async () => {
      subject.device.status = "revoked";
      subject.device.revoked_at = r.clock.now;
      const other = await candidate(r, subject.user);
      const b = await body(
        await meta(
          post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(other.pub) }, {
            token: await tok(r, other),
          }),
          r.deps,
        ),
      );
      assertEquals(b.opened_state, "pending", "the genuine lost-phone case (ADR 2026-09-05d §1)");
    },
  );
});

Deno.test("E-06-45 a guardian's approval is the share re-sealed to the candidate key: only a guardian of the attempt's set may decide, the key it sealed to must be this attempt's, one decision per guardian, and the sealed share reaches the candidate device and nobody else (04 §7.3 step 3; ADR 2026-09-13c §3)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const subject = await member(r, tenant, null, null);
  const g1 = await member(r, tenant, null, null);
  const g2 = await member(r, tenant, null, null);
  const g3 = await member(r, tenant, null, null);
  const outsider = await member(r, r.db.addTenant(), null, null);
  const fresh = await candidate(r, subject.user);
  await publish(r, subject, [g1, g2, g3]);
  const req = (await body(
    await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(fresh.pub) }, {
        token: await tok(r, fresh),
      }),
      r.deps,
    ),
  )).request_id;

  await t.step("the guardian approves; the response carries an id, never the share", async () => {
    const blob = await random(96);
    const res = await approve(r, g1, req, fresh.pub, blob);
    assertEquals(res.status, 200);
    const b = await body(res);
    assertEquals(b.decision, "approved");
    assert(b.wrapped_key_id, "the sealed row's id");
    assert(!("blob" in b), "no route hands a share back on the wire");
  });

  await t.step("the re-sealed share is addressed to the candidate device", async () => {
    // Filed for the candidate device, byte-for-byte what the guardian sent…
    const filed = r.db.wrapped_keys.filter((w) => w.kind === "recovery_blob");
    assertEquals(filed.length, 1);
    assertEquals(filed[0].device_id, fresh.device.id);
    assertEquals(filed[0].user_id, subject.user);
    assertEquals((filed[0].blob as Uint8Array).length, 96);
    // …and served to NOBODY on the meta channel. Until 0020 this step asserted that the candidate
    // read the share here after ONE approval, i.e. before k and inside the 24 h wait of 04 §7.3
    // step 6 / ADR 2026-09-05d §1 🔒, and that the subject's certified device read it too. The
    // share now leaves only through GET /sync-meta/recovery/shares, once the attempt is approved
    // (E-06-77…E-06-79).
    for (const who of [fresh, subject, g1, g2]) {
      const theirs = (await metaPull(r, who)).wrapped_keys;
      assertEquals(theirs.filter((w: any) => w.kind === "recovery_blob").length, 0);
    }
    const early = await meta(
      get(`/sync-meta/recovery/shares?request_id=${req}`, { token: await tok(r, fresh) }),
      r.deps,
    );
    assertEquals(early.status, 404, "1 of 2 approvals releases nothing");
  });

  await t.step("a share sealed to a different candidate key is refused", async () => {
    const res = await approve(r, g2, req, await random(32), await random(96));
    assertEquals(res.status, 409);
    assertEquals((await body(res)).error, "candidate_key_mismatch");
  });

  await t.step("one guardian, one decision", async () => {
    const res = await approve(r, g1, req, fresh.pub, await random(96));
    assertEquals(res.status, 409);
    assertEquals((await body(res)).error, "already_decided");
    assertEquals((await body(await deny(r, g1, req))).error, "already_decided");
  });

  await t.step("a non-guardian and an unknown attempt refuse identically — no oracle", async () => {
    const stranger = await approve(r, outsider, req, fresh.pub, await random(96));
    assertEquals(stranger.status, 403);
    assertEquals((await body(stranger)).error, "unknown_request");
    const ghost = await approve(r, g3, crypto.randomUUID(), fresh.pub, await random(96));
    assertEquals(ghost.status, 403);
    assertEquals((await body(ghost)).error, "unknown_request");
  });
});

Deno.test("E-06-46 progress reads: k-of-n for the requester, the pending ask for a guardian — and neither read is the other's (04 §7.3 step 2; ADR 2026-09-05d §2)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const subject = await member(r, tenant, book, "admin");
  const g1 = await member(r, tenant, null, null);
  const g2 = await member(r, tenant, null, null);
  const g3 = await member(r, tenant, null, null);
  const bystander = await member(r, tenant, book, "member");
  const fresh = await candidate(r, subject.user);
  await publish(r, subject, [g1, g2, g3]);
  const req = (await body(
    await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(fresh.pub) }, {
        token: await tok(r, fresh),
      }),
      r.deps,
    ),
  )).request_id;
  await approve(r, g1, req, fresh.pub, await random(96));

  await t.step("the requester counts k of n", async () => {
    const p = await body(await progress(r, fresh, req));
    assertEquals([p.approvals, p.denials, p.k, p.n], [1, 0, 2, 3]);
    assertEquals(p.state, "waiting_24h");
    assertEquals(p.wait_until, null, "no k-th approval yet, so no window has started");
    // …and so does the subject's own certified device
    const same = await body(await progress(r, subject, req));
    assertEquals(same.approvals, 1);
  });

  await t.step("the guardian sees the ask, not the tally", async () => {
    const asks =
      (await body(await meta(get("/sync-meta/recovery/asks", { token: await tok(r, g2) }), r.deps)))
        .asks;
    assertEquals(asks.length, 1);
    assertEquals(asks[0].request_id, req);
    assertEquals(asks[0].subject_user_id, subject.user);
    assertEquals(asks[0].candidate_device, fresh.device.id);
    assertEquals(
      asks[0].candidate_pub_x,
      b64url.enc(fresh.pub),
      "what g2 must compare its scan to",
    );
    assertEquals(asks[0].my_decision, null);
    for (const k of ["approvals", "denials", "k", "n", "book_id", "tenant_id"]) {
      assert(!(k in asks[0]), `the ask carries no ${k}`);
    }
    // the tally itself is not theirs to read
    assertEquals((await progress(r, g2, req)).status, 404);
    // the guardian who already decided sees its own decision and only its own
    const g1asks =
      (await body(await meta(get("/sync-meta/recovery/asks", { token: await tok(r, g1) }), r.deps)))
        .asks;
    assertEquals(g1asks[0].my_decision, "approved");
  });

  await t.step("a fellow member who is not a guardian is asked nothing", async () => {
    const asks = (await body(
      await meta(get("/sync-meta/recovery/asks", { token: await tok(r, bystander) }), r.deps),
    ))
      .asks;
    assertEquals(asks.length, 0);
    assertEquals((await progress(r, bystander, req)).status, 404);
  });

  await t.step("the candidate device polls its own attempts and sees only those", async () => {
    const mine =
      (await body(await meta(get("/sync-meta/recovery", { token: await tok(r, fresh) }), r.deps)))
        .requests;
    assertEquals(mine.length, 1);
    assertEquals(mine[0].request_id, req);
  });
});

Deno.test("E-06-47 the 24 h wait and the one-tap Cancel: k approvals do not complete an attempt while the window runs, the window ends 24 h after the k-th approval, and a Cancel from an existing certified device closes it for good (ADR 2026-09-05d §1; 04 §7.3 step 6)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const subject = await member(r, tenant, null, null);
  const g1 = await member(r, tenant, null, null);
  const g2 = await member(r, tenant, null, null);
  const g3 = await member(r, tenant, null, null);
  const fresh = await candidate(r, subject.user);
  await publish(r, subject, [g1, g2, g3]);
  const req = (await body(
    await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(fresh.pub) }, {
        token: await tok(r, fresh),
      }),
      r.deps,
    ),
  )).request_id;

  await t.step("k shares in, and the attempt is still waiting", async () => {
    await approve(r, g1, req, fresh.pub, await random(96));
    advance(r, 3600e3);
    await approve(r, g2, req, fresh.pub, await random(96));
    const p = await body(await progress(r, fresh, req));
    assertEquals([p.approvals, p.state], [2, "waiting_24h"]);
    assertEquals(p.wait_until, p.kth_approval_at + 24 * 3600e3);
  });

  await t.step("one hour short of the window it is still waiting", async () => {
    advance(r, 23 * 3600e3);
    assertEquals((await body(await progress(r, fresh, req))).state, "waiting_24h");
  });

  await t.step(
    "a Cancel is reachable from that state, and only from a device that alarms",
    async () => {
      const byCandidate = await meta(
        post("/sync-meta/recovery/cancel", { request_id: req }, { token: await tok(r, fresh) }),
        r.deps,
      );
      assertEquals(byCandidate.status, 403, "the candidate cannot cancel the alarm against it");
      const byGuardian = await meta(
        post("/sync-meta/recovery/cancel", { request_id: req }, { token: await tok(r, g1) }),
        r.deps,
      );
      assertEquals(byGuardian.status, 403);
      const ok = await meta(
        post("/sync-meta/recovery/cancel", { request_id: req }, { token: await tok(r, subject) }),
        r.deps,
      );
      assertEquals(ok.status, 200);
      assertEquals((await body(await progress(r, fresh, req))).state, "cancelled");
    },
  );

  await t.step("and time cannot reopen it, nor can another guardian", async () => {
    advance(r, 48 * 3600e3);
    assertEquals((await body(await progress(r, fresh, req))).state, "cancelled");
    const late = await approve(r, g3, req, fresh.pub, await random(96));
    assertEquals(late.status, 409);
    assertEquals((await body(late)).error, "recovery_closed");
  });

  await t.step(
    "an uncancelled attempt completes when the window ends, and not before",
    async () => {
      const again = await candidate(r, subject.user);
      const req2 = (await body(
        await meta(
          post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(again.pub) }, {
            token: await tok(r, again),
          }),
          r.deps,
        ),
      )).request_id;
      await approve(r, g1, req2, again.pub, await random(96));
      await approve(r, g2, req2, again.pub, await random(96));
      assertEquals((await body(await progress(r, again, req2))).state, "waiting_24h");
      advance(r, 24 * 3600e3);
      assertEquals((await body(await progress(r, again, req2))).state, "approved");
    },
  );
});

Deno.test("E-06-48 an attempt closes without completing: three denials, or 72 h with fewer than k approvals (04 §7.3 step 7)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const subject = await member(r, tenant, null, null);
  const gs: Member[] = [];
  for (let i = 0; i < 5; i++) gs.push(await member(r, tenant, null, null));
  const fresh = await candidate(r, subject.user);
  await publish(r, subject, gs); // n = 5, k = 3
  const req = (await body(
    await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(fresh.pub) }, {
        token: await tok(r, fresh),
      }),
      r.deps,
    ),
  )).request_id;

  await t.step("two denials are not three", async () => {
    await deny(r, gs[0], req);
    await deny(r, gs[1], req);
    const p = await body(await progress(r, fresh, req));
    assertEquals([p.denials, p.k, p.n, p.state], [2, 3, 5, "waiting_24h"]);
  });

  await t.step("the third closes the attempt, and it stays closed", async () => {
    await deny(r, gs[2], req);
    // ⚠️ SPEC: 03 §2.2's state enum has no 'denied'; a closed attempt is `expired` either way, and
    // the denial rows say which it was. Reported to the owner, not invented here.
    assertEquals((await body(await progress(r, fresh, req))).state, "expired");
    const late = await approve(r, gs[3], req, fresh.pub, await random(96));
    assertEquals((await body(late)).error, "recovery_closed");
  });

  await t.step("and silence closes it at 72 h", async () => {
    const again = await candidate(r, subject.user);
    const req2 = (await body(
      await meta(
        post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(again.pub) }, {
          token: await tok(r, again),
        }),
        r.deps,
      ),
    )).request_id;
    await approve(r, gs[0], req2, again.pub, await random(96)); // one short of k
    advance(r, 72 * 3600e3 + 1000);
    assertEquals((await body(await progress(r, again, req2))).state, "expired");
    assertEquals(
      (await body(await approve(r, gs[1], req2, again.pub, await random(96)))).error,
      "recovery_closed",
    );
  });
});

Deno.test("E-06-49 a share sealed for one attempt cannot be filed against another: two live attempts from two fresh phones keep separate candidate keys, separate sealed rows and separate tallies (ADR 2026-09-13c §3; 04 §7.3 step 3)", async () => {
  const r = rig();
  const tenant = r.db.addTenant();
  const subject = await member(r, tenant, null, null);
  const g1 = await member(r, tenant, null, null);
  const g2 = await member(r, tenant, null, null);
  const g3 = await member(r, tenant, null, null);
  await publish(r, subject, [g1, g2, g3]);
  const a = await candidate(r, subject.user);
  const b = await candidate(r, subject.user);
  const open = async (c: Who & { pub: Uint8Array }) =>
    (await body(
      await meta(
        post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(c.pub) }, {
          token: await tok(r, c),
        }),
        r.deps,
      ),
    )).request_id as string;
  const reqA = await open(a), reqB = await open(b);
  assert(reqA !== reqB);

  // the key A's guardians sealed to is not the key B's request carries
  assertEquals(
    (await body(await approve(r, g1, reqB, a.pub, await random(96)))).error,
    "candidate_key_mismatch",
  );
  await approve(r, g1, reqA, a.pub, await random(96));
  await approve(r, g1, reqB, b.pub, await random(96)); // the same guardian, a different attempt
  assertEquals((await body(await progress(r, a, reqA))).approvals, 1);
  assertEquals((await body(await progress(r, b, reqB))).approvals, 1);

  // each attempt's share is its own row, addressed to its own phone. (Until 0020 each phone read
  // it on the meta pull at 1 of 2 approvals; the meta channel now carries no recovery_blob, and
  // the release is GET /sync-meta/recovery/shares once approved, E-06-74 / E-06-77.)
  const filed = r.db.wrapped_keys.filter((w) => w.kind === "recovery_blob");
  const forA = filed.filter((w) => w.device_id === a.device.id);
  const forB = filed.filter((w) => w.device_id === b.device.id);
  assertEquals(forA.length, 1);
  assertEquals(forB.length, 1);
  assert(forA[0].id !== forB[0].id, "two attempts, two sealed rows");
  for (const c of [a, b]) {
    const pulled =
      (await body(await meta(get("/sync-meta", { token: await tok(r, c) }), r.deps))).wrapped_keys;
    assertEquals(pulled.filter((w: any) => w.kind === "recovery_blob").length, 0);
  }

  // and neither phone can read the other's attempt
  assertEquals((await progress(r, a, reqB)).status, 404);
});

// ---------------------------------------------------------------------------------------------
// M11 RV7 — the two gaps the wire itself showed: a tally that names nobody, and a rung with no
// surface at all. Ids E-06-57, E-06-58.
// ---------------------------------------------------------------------------------------------

Deno.test("E-06-57 the progress route NAMES the guardians who decided: `decisions` carries one row per guardian from the append-only table, an approval and a denial are told apart from silence, the tally still matches, and no caller but the requester and its candidate device sees a decision at all (0010 THE DECISION 🔒; 04 §7.3 steps 3 and 7; ADR 2026-09-05d §2)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const subject = await member(r, tenant, book, "admin");
  const g1 = await member(r, tenant, null, null);
  const g2 = await member(r, tenant, null, null);
  const g3 = await member(r, tenant, null, null);
  const bystander = await member(r, tenant, null, null); // certified, not a guardian
  await publish(r, subject, [g1, g2, g3]);
  const fresh = await candidate(r, subject.user);
  const req = (await body(
    await meta(
      post("/sync-meta/recovery", { candidate_pub_x: b64url.enc(fresh.pub) }, {
        token: await tok(r, fresh),
      }),
      r.deps,
    ),
  )).request_id as string;

  await t.step("nobody has answered: the array is empty, not absent", async () => {
    const p = await body(await progress(r, fresh, req));
    assertEquals(p.approvals, 0);
    assertEquals(p.denials, 0);
    assertEquals(p.decisions, []);
  });

  await t.step("one denial is a ROW — silence is the absence of one", async () => {
    await deny(r, g1, req);
    const p = await body(await progress(r, fresh, req));
    assertEquals(p.approvals, 0);
    assertEquals(p.denials, 1);
    assertEquals(p.decisions.length, 1);
    assertEquals(p.decisions[0].guardian_user_id, g1.user);
    assertEquals(p.decisions[0].decision, "denied");
    assert(typeof p.decisions[0].created_at === "number", "a time the screen can order by");
    // g2 and g3 have said nothing, and nothing in the payload claims otherwise.
    assertEquals(
      p.decisions.filter((d: { guardian_user_id: string }) =>
        d.guardian_user_id === g2.user || d.guardian_user_id === g3.user
      ).length,
      0,
    );
  });

  await t.step("an approval names its guardian and carries no share", async () => {
    await approve(r, g2, req, fresh.pub, await random(96));
    const p = await body(await progress(r, fresh, req));
    assertEquals(p.approvals, 1);
    assertEquals(p.denials, 1);
    assertEquals(p.decisions.length, 2);
    const by = Object.fromEntries(
      p.decisions.map((d: { guardian_user_id: string; decision: string }) => [
        d.guardian_user_id,
        d.decision,
      ]),
    );
    assertEquals(by[g1.user], "denied");
    assertEquals(by[g2.user], "approved");
    for (const d of p.decisions) {
      assertEquals(Object.keys(d).sort(), ["created_at", "decision", "guardian_user_id"]);
      assert(!("wrapped_key_id" in d), "the sealed share travels on the meta pull, never here");
      assert(!("sealed_to_pub_x" in d), "and neither does the key it was sealed to");
    }
  });

  await t.step("the requester's own certified device reads the same rows", async () => {
    const p = await body(await progress(r, subject, req));
    assertEquals(p.decisions.length, 2);
  });

  await t.step("a guardian, a bystander and a stranger read no decision at all", async () => {
    const other = r.db.addTenant();
    const stranger = await member(r, other, null, null);
    for (const w of [g1, g2, bystander, stranger]) {
      const res = await progress(r, w, req);
      assertEquals(
        res.status,
        404,
        "an attempt not yours and one that does not exist are one answer",
      );
      assertEquals((await body(res)).error, "not_found");
    }
    // What a guardian DOES get is its own ask and its own decision — never another guardian's.
    const asks = (await body(
      await meta(get("/sync-meta/recovery/asks", { token: await tok(r, g1) }), r.deps),
    )).asks;
    assertEquals(asks.length, 1);
    assertEquals(asks[0].my_decision, "denied");
    assert(!("decisions" in asks[0]), "an ask is not a tally");
  });
});

Deno.test("E-06-58 rung 3 has a surface at last: a certified device uploads `sealed_RK_blob` and gets a version, the caller fetches its OWN current blob byte-for-byte, regenerating rotates to the next version and the old blob stops being served, a user with no sheet is told `no_sheet` rather than given a falsehood, and nobody else's blob is reachable (04 §7.4 🔒; 0011)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const subject = await member(r, tenant, null, null);
  const other = await member(r, tenant, null, null);
  const sheet1 = await random(72);

  const put = async (w: Who, blob: Uint8Array) =>
    await meta(
      post("/sync-meta/recovery/sheet", { blob: b64url.enc(blob) }, { token: await tok(r, w) }),
      r.deps,
    );
  const fetchSheet = async (w: Who) =>
    await meta(get("/sync-meta/recovery/sheet", { token: await tok(r, w) }), r.deps);

  await t.step("a user who never printed a sheet is told exactly that", async () => {
    const res = await fetchSheet(subject);
    assertEquals(res.status, 404);
    assertEquals((await body(res)).error, "no_sheet");
  });

  await t.step("signup uploads the blob and it comes back unchanged", async () => {
    assertEquals((await body(await put(subject, sheet1))).sheet_version, 1);
    const got = await body(await fetchSheet(subject));
    assertEquals(got.sheet_version, 1);
    assertEquals(got.user_id, subject.user);
    assertEquals(b64url.enc(sheet1), got.sealed_rk_blob, "bytes in, bytes out (04 §8.6)");
  });

  await t.step("the fresh phone of 06 §5 — uncertified — may fetch its own blob", async () => {
    // Rung 3 exists for exactly this caller: OTP passed, nothing else held, an RK on paper.
    const fresh = await candidate(r, subject.user);
    const got = await body(await fetchSheet(fresh));
    assertEquals(got.sheet_version, 1);
    assertEquals(b64url.enc(sheet1), got.sealed_rk_blob);
    // …and it may not publish one: burying the real sheet is a certified device's act only.
    assertEquals((await put(fresh, await random(72))).status, 403);
  });

  await t.step("regenerating rotates RK: the next version, and only it, is served", async () => {
    advance(r, 61_000); // one publication per minute (ADR 2026-09-05b §7)
    const sheet2 = await random(72);
    assertEquals((await body(await put(subject, sheet2))).sheet_version, 2);
    const got = await body(await fetchSheet(subject));
    assertEquals(got.sheet_version, 2);
    assertEquals(b64url.enc(sheet2), got.sealed_rk_blob, "the old sheet is invalidated (04 §7.4)");
  });

  await t.step("the rate bound refuses by name, never silently", async () => {
    const res = await put(subject, await random(72));
    assertEquals(res.status, 429);
    assertEquals((await body(res)).error, "sheet_flood");
  });

  await t.step("another member of the same tenant reaches none of it", async () => {
    const res = await fetchSheet(other);
    assertEquals(res.status, 404);
    assertEquals((await body(res)).error, "no_sheet", "no oracle: the same answer as having none");
    // and a blob is never in anybody's meta pull
    const pull = await metaPull(r, other);
    assert(!("recovery_sheets" in pull), "the sheet is fetched deliberately, never broadcast");
  });
});

// ============================================================================================
// RUNG 3's `expected` — ADR 2026-10-06d ruling 2 🔒, ADR 2026-09-13c §1 (ratified), 04 §7.4 🔒.
// ============================================================================================
// The restoring phone (uncertified, wiped) opens `sealed_RK_blob` with the RK read off paper and
// may adopt the UMK it recovers ONLY if its public halves match "the account's published UMK"
// (ruling 2). That phone holds nothing else, so the published key has to come from the same read
// that hands it the blob: GET /recovery/sheet now carries the caller's OWN registered UMK — the
// copy /devices/certify stored through rf.set_umk_pubs (0012) — as `umk_pub_ed` + `umk_pub_x`.
// The AEAD under the paper RK is what authenticates the key (ADR 13c §1): a server that relays a
// wrong public key can only make the phone REFUSE, never make it adopt something the user did not
// seal. Ids E-1006d-1 … E-1006d-3; the PgStore arm is E-1006d-4 (tests/rls/recovery_sheet_umk).

/** /devices/certify exactly as the app sends it since M11-CER2: the certificate is signed by the
 *  UMK, and both public halves ride the body (auth-challenge certifyWith → tx.setUmkPubs, 0012).
 *  What this writes is "the registered copy" every later assertion compares against. */
async function certifyUmk(r: Rig, m: Member, opts: { x?: boolean } = {}) {
  const umk = await edKeypair();
  const umkX = await random(32);
  const issued = r.clock.now.getTime();
  const sig = await sign(certBytes(m.device.id, m.keys.pub, m.xpub, issued), umk.priv);
  const res = await auth(
    post("/auth-challenge/devices/certify", {
      umk_pub_ed: b64url.enc(umk.pub),
      ...(opts.x === false ? {} : { umk_pub_x: b64url.enc(umkX) }),
      umk_key_version: 1,
      cert: { signature: b64url.enc(sig), issued_at_ms: issued },
    }, { token: await tok(r, m) }),
    r.deps,
  );
  assertEquals(res.status, 200, `precondition: certify registered the UMK (${await res.text()})`);
  const row = r.db.umk_public_keys.find((k) => k.user_id === m.user && k.key_version === 1);
  assert(row, "precondition: the registered copy exists");
  return { ed: umk.pub, x: umkX, row };
}

const sheetPut = async (r: Rig, w: Who, blob: Uint8Array) =>
  await meta(
    post("/sync-meta/recovery/sheet", { blob: b64url.enc(blob) }, { token: await tok(r, w) }),
    r.deps,
  );
const sheetGet = async (r: Rig, w: Who) =>
  await meta(get("/sync-meta/recovery/sheet", { token: await tok(r, w) }), r.deps);

Deno.test("E-1006d-1 GET /recovery/sheet hands the restoring phone its OWN account's published UMK, both halves, byte-equal to the copy /devices/certify registered, beside the blob it already served — the uncertified wiped phone included, and the body is exactly the six fields (ADR 2026-10-06d ruling 2 🔒; ADR 2026-09-13c §1; 04 §7.4 🔒)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const subject = await member(r, tenant, null, null);
  const reg = await certifyUmk(r, subject);
  const blob = await random(72);
  assertEquals((await body(await sheetPut(r, subject, blob))).sheet_version, 1);

  const expectOwn = (got: Record<string, unknown>, who: string) => {
    assertEquals(
      Object.keys(got).sort(),
      ["created_at", "sealed_rk_blob", "sheet_version", "umk_pub_ed", "umk_pub_x", "user_id"],
      `${who}: the six fields and nothing else — no key_version, no tenant, no device`,
    );
    assertEquals(got.user_id, subject.user);
    assertEquals(got.sealed_rk_blob, b64url.enc(blob), `${who}: the blob is unchanged`);
    // byte-equal to what certify was sent AND to what the store holds — never re-derived
    assertEquals(got.umk_pub_ed, b64url.enc(reg.ed), `${who}: the Ed25519 half certify registered`);
    assertEquals(got.umk_pub_x, b64url.enc(reg.x), `${who}: the X25519 half certify registered`);
    assertEquals(b64url.dec(got.umk_pub_ed as string), reg.row.pub_ed as Uint8Array);
    assertEquals(b64url.dec(got.umk_pub_x as string), reg.row.pub_x as Uint8Array);
    assertEquals(b64url.dec(got.umk_pub_ed as string).length, 32);
    assertEquals(b64url.dec(got.umk_pub_x as string).length, 32);
  };

  await t.step("the certified device that printed the sheet reads both halves", async () => {
    const res = await sheetGet(r, subject);
    assertEquals(res.status, 200);
    expectOwn(await body(res), "certified");
  });

  await t.step(
    "the wiped phone of 06 §5 — registered, NEVER certified — reads the same",
    async () => {
      const fresh = await candidate(r, subject.user);
      assertEquals(r.db.devices.get(fresh.device.id)?.status, "registered", "precondition");
      const res = await sheetGet(r, fresh);
      assertEquals(res.status, 200);
      expectOwn(await body(res), "uncertified");
    },
  );

  await t.step("regenerating the sheet keeps relaying the same published key", async () => {
    advance(r, 61_000);
    const blob2 = await random(72);
    assertEquals((await body(await sheetPut(r, subject, blob2))).sheet_version, 2);
    const got = await body(await sheetGet(r, subject));
    assertEquals(got.sheet_version, 2);
    assertEquals(got.sealed_rk_blob, b64url.enc(blob2));
    assertEquals(got.umk_pub_ed, b64url.enc(reg.ed));
    assertEquals(got.umk_pub_x, b64url.enc(reg.x));
  });
});

Deno.test("E-1006d-2 nobody else's UMK travels: a tenant-mate with its own key reads its own, a tenant-mate with a sheet and NO registered key reads null — never the subject's — and a caller with no sheet is `no_sheet` with no key field at all (ADR 2026-09-05d §2; 0005 umk_select; 04 §7.4 🔒)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  // Registration order matters to the mutation check: the subject's key row is FIRST in the store,
  // so a read that forgot to filter on the caller would hand the subject's key to everybody.
  const subject = await member(r, tenant, null, null);
  const regS = await certifyUmk(r, subject);
  const mate = await member(r, tenant, null, null);
  const keyless = await member(r, tenant, null, null);
  const stranger = await member(r, r.db.addTenant(), null, null);
  await sheetPut(r, subject, await random(72));
  const regM = await certifyUmk(r, mate);
  const mateBlob = await random(72);
  await sheetPut(r, mate, mateBlob);
  const keylessBlob = await random(72);
  assertEquals((await sheetPut(r, keyless, keylessBlob)).status, 200, "precondition");
  assert(!r.db.umk_public_keys.some((k) => k.user_id === keyless.user), "precondition: no key");

  const S_ED = b64url.enc(regS.ed), S_X = b64url.enc(regS.x);

  await t.step("a tenant-mate with its own key reads ITS key, not the subject's", async () => {
    const got = await body(await sheetGet(r, mate));
    assertEquals(got.user_id, mate.user);
    assertEquals(got.sealed_rk_blob, b64url.enc(mateBlob));
    assertEquals(got.umk_pub_ed, b64url.enc(regM.ed));
    assertEquals(got.umk_pub_x, b64url.enc(regM.x));
  });

  await t.step("a tenant-mate with no registered key reads null, never a neighbour's", async () => {
    const res = await sheetGet(r, keyless);
    assertEquals(res.status, 200, "the blob is still served: S0.5b's scan-back reads this route");
    const got = await body(res);
    assertEquals(got.sealed_rk_blob, b64url.enc(keylessBlob));
    assertEquals(got.umk_pub_ed, null);
    assertEquals(got.umk_pub_x, null);
  });

  await t.step("a stranger with no sheet is `no_sheet`, and the body names no key", async () => {
    const res = await sheetGet(r, stranger);
    assertEquals(res.status, 404);
    const got = await body(res);
    assertEquals(got, { error: "no_sheet" }, "exactly the old refusal — nothing added to it");
  });

  await t.step("query parameters name nobody: the route answers for the caller alone", async () => {
    const res = await meta(
      get(`/sync-meta/recovery/sheet?user_id=${subject.user}&subject_user_id=${subject.user}`, {
        token: await tok(r, keyless),
      }),
      r.deps,
    );
    const text = await res.text();
    assert(!text.includes(S_ED) && !text.includes(S_X), "the subject's key never appears");
    assertEquals(JSON.parse(text).user_id, keyless.user);
  });
});

Deno.test("E-1006d-3 no key is invented: a sheet with no registered UMK is served with umk_pub_ed = umk_pub_x = null; an Ed-only row relays its Ed half and a null X half (0012); the NEWEST key_version is the published one; a newest row that is superseded relays null rather than falling back to an older key (04 §6.3 'There is no override'; 04 §9.2; ADR 2026-09-05b §1)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const m = await member(r, tenant, null, null);
  const blob = await random(72);
  await sheetPut(r, m, blob);
  const read = async () => {
    const res = await sheetGet(r, m);
    assertEquals(res.status, 200);
    const got = await body(res);
    assertEquals(got.sealed_rk_blob, b64url.enc(blob), "the blob is served in every case");
    return got;
  };
  const row = (v: number, ed: Uint8Array, x: Uint8Array | null, superseded: Date | null = null) =>
    r.db.umk_public_keys.push({
      user_id: m.user,
      key_version: v,
      pub_ed: ed,
      pub_x: x,
      created_at: r.clock.now,
      superseded_at: superseded,
      updated_at: r.clock.now,
    });

  await t.step(
    "no registered key: both fields present and null — not omitted, not made up",
    async () => {
      const got = await read();
      assert("umk_pub_ed" in got && "umk_pub_x" in got, "the shape is stable");
      assertEquals(got.umk_pub_ed, null);
      assertEquals(got.umk_pub_x, null);
    },
  );

  const ed1 = await random(32);
  await t.step("an Ed-only row (no x half offered yet): Ed relayed, X null", async () => {
    row(1, ed1, null);
    const got = await read();
    assertEquals(got.umk_pub_ed, b64url.enc(ed1));
    assertEquals(got.umk_pub_x, null, "the device fails closed on a missing half (04 §6.3)");
  });

  const ed2 = await random(32), x2 = await random(32);
  // Both rotation states below are seeded as maintenance would write them: 0031 allows at most ONE
  // live row per user (partial unique index), and rf_api cannot add a second key_version at all
  // (E-05d-1, E-05d-2). A fixture holding two live rows would be a state the database refuses.
  const at = (v: number) =>
    r.db.umk_public_keys.find((k) => k.user_id === m.user && k.key_version === v)!;
  await t.step("after a UMK rotation the NEWEST version is the published key", async () => {
    at(1).superseded_at = r.clock.now; // the rotation retires version 1 …
    row(2, ed2, x2); // … and version 2 is the one live row
    const got = await read();
    assertEquals(got.umk_pub_ed, b64url.enc(ed2));
    assertEquals(got.umk_pub_x, b64url.enc(x2));
  });

  await t.step("a superseded newest row relays null — never the older key behind it", async () => {
    at(2).superseded_at = r.clock.now;
    at(1).superseded_at = null; // the one live row is now the OLDER version
    const got = await read();
    assertEquals(got.umk_pub_ed, null, "no fallback to version 1 (the key a rotation retired)");
    assertEquals(got.umk_pub_x, null);
  });
});
