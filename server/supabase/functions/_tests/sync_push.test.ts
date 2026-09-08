// sync-push (05 §3; ADR 2026-09-05c §5; ADR 2026-09-05b §7). Ids E-05-1 … E-05-6.
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { mintAccessToken } from "../_shared/claims.ts";
import { PUSH_BATCH_MAX } from "../_shared/registry.ts";
import { SHAPE_CHECKS } from "../_shared/shape.ts";
import { handler as push } from "../sync-push/index.ts";
import { advance, body, hlcAt, member, post, random, rig, T0, wireEnvelope } from "./harness.ts";

async function scene() {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const m = await member(r, tenant, book, "member");
  r.db.addWrappedKey({ kind: "bk_for_user", user_id: m.user, book_id: book, key_version: 1 });
  return { r, tenant, book, m };
}
const send = (r: ReturnType<typeof rig>, token: string, envelopes: unknown[]) =>
  push(post("/sync-push", { envelopes }, { token }), r.deps);

Deno.test("E-05-1 push: the eight shape checks refuse with the check named, in 05c §5 order", async (t) => {
  const { r, tenant, book, m } = await scene();
  const other = await member(r, tenant, book, "member");
  const bogusTenant = r.db.addTenant();
  const bigBlob = await random(300 * 1024);
  const wrongHash = b64url.enc(await random(32));
  const cases: { name: string; over: Record<string, unknown>; result: string; check: string }[] = [
    {
      name: "author_device",
      over: { author_device: other.device.id },
      result: "rejected:shape",
      check: "author_device",
    },
    {
      name: "tenant_id",
      over: { tenant_id: bogusTenant },
      result: "rejected:shape",
      check: "tenant_id",
    },
    {
      name: "blob_hash",
      over: { blob_hash: wrongHash },
      result: "rejected:shape",
      check: "blob_hash",
    },
    { name: "size", over: { size: 5 }, result: "rejected:shape", check: "size" },
    {
      name: "size cap",
      over: { blob: b64url.enc(bigBlob), size: bigBlob.length },
      result: "rejected:too_large",
      check: "size",
    },
    {
      name: "suite_version",
      over: { suite_version: 9 },
      result: "rejected:shape",
      check: "suite_version",
    },
    {
      name: "payload_schema above registry",
      over: { payload_schema: 99 },
      result: "rejected:version",
      check: "payload_schema",
    },
    {
      name: "key_version above highest issued",
      over: { key_version: 3 },
      result: "rejected:shape",
      check: "key_version",
    },
    {
      name: "hlc future",
      over: { hlc: hlcAt(T0.getTime() + 6 * 60_000) },
      result: "rejected:hlc_future",
      check: "hlc",
    },
    {
      name: "object_type outside registry",
      over: { object_type: "salary_slip" },
      result: "rejected:shape",
      check: "object_type",
    },
  ];
  for (const c of cases) {
    await t.step(c.name, async () => {
      const e = await wireEnvelope(m, tenant, book, c.over);
      const res = await body(await send(r, m.token, [e]));
      assertEquals(res.results[0].result, c.result, c.name);
      assertEquals(res.results[0].check, c.check, c.name);
      assertEquals(res.results[0].envelope_id, e.envelope_id);
    });
  }
  assertEquals(r.db.envelopes.length, 0, "nothing stored");
  assertEquals(SHAPE_CHECKS.length, 8);
});

Deno.test("E-05-1b push: key_version below highest is fine inside 48 h and rejected:key_version_stale after", async () => {
  const { r, tenant, book, m } = await scene();
  r.db.addWrappedKey({ kind: "bk_for_user", user_id: m.user, book_id: book, key_version: 2 });
  let res = await body(
    await send(r, m.token, [await wireEnvelope(m, tenant, book, { key_version: 1 })]),
  );
  assertEquals(res.results[0].result, "acked");
  advance(r, 49 * 3600e3);
  const fresh = await mintAccessToken(
    r.deps.jwtKey,
    m.claims,
    Math.floor(r.clock.now.getTime() / 1000),
  );
  res = await body(
    await send(r, fresh, [
      await wireEnvelope(m, tenant, book, { key_version: 1, hlc: hlcAt(r.clock.now.getTime()) }),
    ]),
  );
  assertEquals(res.results[0].result, "rejected:key_version_stale");
  assertEquals(res.results[0].check, "key_version");
});

Deno.test("E-05-2 push: idempotent by envelope_id — replay acks the same seq and stores nothing twice", async () => {
  const { r, tenant, book, m } = await scene();
  const e = await wireEnvelope(m, tenant, book);
  const a = await body(await send(r, m.token, [e]));
  const b = await body(await send(r, m.token, [e, e]));
  assertEquals(a.results[0].result, "acked");
  assertEquals(b.results.map((x: any) => x.result), ["acked", "acked"]);
  assertEquals(b.results[0].seq, a.results[0].seq);
  assertEquals(b.results[1].seq, a.results[0].seq);
  assertEquals(r.db.envelopes.length, 1);
  assertEquals(typeof a.store_epoch, "string");
});

Deno.test("E-05-3 push: seq is monotone by receipt and shared with signed records (ADR 05b §5)", async () => {
  const { r, tenant, book, m } = await scene();
  const res = await body(
    await send(r, m.token, [
      await wireEnvelope(m, tenant, book),
      await wireEnvelope(m, tenant, book),
    ]),
  );
  const [s1, s2] = res.results.map((x: any) => x.seq);
  assert(s1 < s2);
  // a signed record lands in the same sequence space
  await r.deps.store.withClaims(m.claims, (tx) =>
    tx.insertSignedRecord({
      id: crypto.randomUUID(),
      suite_version: 1,
      tenant_id: tenant,
      kind: "designation",
      payload_json: {},
      payload_bytes: new Uint8Array(2),
      author_device: m.device.id,
      author_sig: new Uint8Array(64),
      hlc: 1n,
    }));
  const res2 = await body(await send(r, m.token, [await wireEnvelope(m, tenant, book)]));
  assertEquals(res2.results[0].seq, s2 + 2);
});

Deno.test("E-05-4 push: authorisation results — unknown_book, membership_not_active, no_role, tenant_frozen, quota", async (t) => {
  const { r, tenant, book, m } = await scene();
  await t.step("unknown book", async () => {
    const res = await body(
      await send(r, m.token, [await wireEnvelope(m, tenant, crypto.randomUUID())]),
    );
    assertEquals(res.results[0].result, "rejected:unknown_book");
  });
  await t.step("archived book", async () => {
    const archived = r.db.addBook(tenant);
    r.db.books.get(archived)!.archived_at = T0;
    r.db.addRole(archived, m.user, "member");
    const res = await body(await send(r, m.token, [await wireEnvelope(m, tenant, archived)]));
    assertEquals(res.results[0].result, "rejected:unknown_book");
  });
  await t.step("viewer has no write role", async () => {
    const v = await member(r, tenant, book, "viewer");
    const res = await body(await send(r, v.token, [await wireEnvelope(v, tenant, book)]));
    assertEquals(res.results[0].result, "rejected:no_role");
  });
  await t.step("blocked membership is refused like not-active (ADR 05b §7)", async () => {
    const blocked = await member(r, tenant, book, "member", { membership: "blocked" });
    const res = await body(
      await send(r, blocked.token, [await wireEnvelope(blocked, tenant, book)]),
    );
    assertEquals(res.results[0].result, "membership_not_active");
  });
  await t.step("uncertified device sees no book at all (ADR 05d §2)", async () => {
    const u = await member(r, tenant, book, "member", { status: "registered" });
    const res = await body(await send(r, u.token, [await wireEnvelope(u, tenant, book)]));
    assertEquals(res.results[0].result, "rejected:unknown_book");
  });
  await t.step("tenant frozen: push refused, nothing stored", async () => {
    r.db.freeze(tenant);
    const res = await body(await send(r, m.token, [await wireEnvelope(m, tenant, book)]));
    assertEquals(res.results[0].result, "rejected:tenant_frozen");
    r.db.tenant_freezes = [];
  });
  await t.step("quota: free plan 10k envelopes per book", async () => {
    for (let i = 0; i < 10_000; i++) {
      r.db.envelopes.push({
        envelope_id: crypto.randomUUID(),
        seq: ++r.db.seq,
        tenant_id: tenant,
        book_id: book,
        object_id: crypto.randomUUID(),
        object_type: "entry",
        key_version: 1,
        suite_version: 1,
        payload_schema: 1,
        author_device: m.device.id,
        hlc: 1n,
        blob_hash: new Uint8Array(32),
        size: 10,
        blob: new Uint8Array(10),
        blob_ref: null,
      });
    }
    const res = await body(await send(r, m.token, [await wireEnvelope(m, tenant, book)]));
    assertEquals(res.results[0].result, "rejected:quota");
    r.db.setPlan(tenant, "personal");
    const ok = await body(await send(r, m.token, [await wireEnvelope(m, tenant, book)]));
    assertEquals(ok.results[0].result, "acked", "upgrade lifts the quota");
  });
});

Deno.test("E-05-5 push: per-device rate limit → rejected:rate_limited with retry_after_ms; batch caps → 413", async () => {
  const { r, tenant, book, m } = await scene();
  const batch: Record<string, unknown>[] = [];
  for (let i = 0; i < 100; i++) batch.push(await wireEnvelope(m, tenant, book, {}, 8));
  for (let i = 0; i < 6; i++) {
    const res = await body(
      await send(r, m.token, batch.map((e) => ({ ...e, envelope_id: crypto.randomUUID() }))),
    );
    assertEquals(res.results[0].result, "acked", `batch ${i}`);
  }
  const over = await body(await send(r, m.token, [await wireEnvelope(m, tenant, book)]));
  assertEquals(over.results[0].result, "rejected:rate_limited");
  assertEquals(typeof over.results[0].retry_after_ms, "number");
  advance(r, 61_000);
  const again = await body(await send(r, m.token, [await wireEnvelope(m, tenant, book)]));
  assertEquals(again.results[0].result, "acked", "window rolled");

  const tooMany = await send(
    r,
    m.token,
    Array.from({ length: PUSH_BATCH_MAX + 1 }, () => batch[0]),
  );
  assertEquals(tooMany.status, 413);
});

Deno.test("E-05-6 push: 426 below min client version; 401 without/with a bad token; 400 on a non-batch", async () => {
  const { r, tenant, book, m } = await scene();
  assertEquals(
    (await push(post("/sync-push", { envelopes: [] }, { token: m.token, version: null }), r.deps))
      .status,
    426,
  );
  r.db.config.set("min_client_version.sync", "0.2.0");
  const res = await push(post("/sync-push", { envelopes: [] }, { token: m.token }), r.deps);
  assertEquals(res.status, 426);
  assertEquals((await body(res)).min_client_version, "0.2.0");
  r.db.config.set("min_client_version.sync", "0.1.0");
  assertEquals((await push(post("/sync-push", { envelopes: [] }, {}), r.deps)).status, 401);
  assertEquals(
    (await push(post("/sync-push", { envelopes: [] }, { token: m.token + "x" }), r.deps)).status,
    401,
  );
  assertEquals(
    (await push(post("/sync-push", { nope: 1 }, { token: m.token }), r.deps)).status,
    400,
  );
  // an expired token is refused too
  advance(r, 16 * 60_000);
  const late = await push(
    post("/sync-push", { envelopes: [await wireEnvelope(m, tenant, book)] }, { token: m.token }),
    r.deps,
  );
  assertEquals(late.status, 401);
  assertNotEquals(r.db.envelopes.length, 1);
});
