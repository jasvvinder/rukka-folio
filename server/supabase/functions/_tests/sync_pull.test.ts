// sync-pull (05 §4 🔒) + store_epoch across routes (ADR 2026-09-05b §6). Ids E-05-7, E-05-8, E-05-11.
import { assert, assertEquals } from "@std/assert";
import { PULL_LIMIT_MAX } from "../_shared/registry.ts";
import { handler as meta } from "../sync-meta/index.ts";
import { handler as pull } from "../sync-pull/index.ts";
import { handler as push } from "../sync-push/index.ts";
import { body, get, hlcAt, member, post, rig, T0, wireEnvelope } from "./harness.ts";

async function scene(n: number) {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const m = await member(r, tenant, book, "member");
  const envelopes = [];
  for (let i = 0; i < n; i++) {
    envelopes.push(await wireEnvelope(m, tenant, book, { hlc: hlcAt(T0.getTime(), i) }, 16));
  }
  const acked = await body(
    await push(post("/sync-push", { envelopes }, { token: m.token }), r.deps),
  );
  return { r, tenant, book, m, envelopes, acked };
}
const pullUrl = (book: string, after: number | string, limit?: number, extra = "") =>
  `/sync-pull?book_id=${book}&after_seq=${after}${limit ? `&limit=${limit}` : ""}${extra}`;

Deno.test("E-05-7 pull: seq cursor pages in receipt order, next_seq resumes, hlc round-trips beyond 2^53, page cap 500", async () => {
  const { r, book, m, envelopes, acked } = await scene(7);
  const p1 = await body(await pull(get(pullUrl(book, 0, 3), { token: m.token }), r.deps));
  assertEquals(p1.envelopes.length, 3);
  assertEquals(
    p1.envelopes.map((e: any) => e.seq),
    acked.results.slice(0, 3).map((x: any) => x.seq),
  );
  assertEquals(p1.next_seq, acked.results[2].seq);
  const p2 = await body(await pull(get(pullUrl(book, p1.next_seq, 3), { token: m.token }), r.deps));
  const p3 = await body(await pull(get(pullUrl(book, p2.next_seq, 3), { token: m.token }), r.deps));
  assertEquals(p3.envelopes.length, 1);
  const p4 = await body(await pull(get(pullUrl(book, p3.next_seq, 3), { token: m.token }), r.deps));
  assertEquals(p4.envelopes, []);
  assertEquals(p4.next_seq, p3.next_seq, "empty page keeps the cursor");
  const all = [...p1.envelopes, ...p2.envelopes, ...p3.envelopes];
  assertEquals(all.map((e: any) => e.envelope_id), envelopes.map((e) => e.envelope_id));
  // hlc arrives as an exact integer literal, not a float
  const raw = await (await pull(get(pullUrl(book, 0, 1), { token: m.token }), r.deps)).text();
  const hlcText = raw.match(/"hlc":(\d+)/)![1];
  assertEquals(BigInt(hlcText), hlcAt(T0.getTime(), 0));
  assert(BigInt(hlcText) > 2n ** 53n);
  // every row carries the 05 §3 field names wire.dart reads
  for (
    const k of [
      "envelope_id",
      "seq",
      "tenant_id",
      "book_id",
      "object_id",
      "object_type",
      "key_version",
      "suite_version",
      "payload_schema",
      "author_device",
      "hlc",
      "blob_hash",
      "size",
      "blob",
    ]
  ) {
    assert(k in all[0], k);
  }
  // limit is capped
  const capped = await pull(get(pullUrl(book, 0, 9999), { token: m.token }), r.deps);
  assertEquals(capped.status, 200);
  assert(PULL_LIMIT_MAX === 500);
  // object_types filter serves the bootstrap hot set (05 §8)
  const filtered = await body(
    await pull(
      get(pullUrl(book, 0, 500, "&object_types=book_config,account"), { token: m.token }),
      r.deps,
    ),
  );
  assertEquals(filtered.envelopes, []);
  // fy is accepted (ignored today — see ⚠️ SPEC in sync-pull)
  assertEquals(
    (await pull(get(pullUrl(book, 0, 500, "&fy=2024-25"), { token: m.token }), r.deps)).status,
    200,
  );
  assertEquals(
    (await pull(get("/sync-pull?book_id=nope&after_seq=0", { token: m.token }), r.deps)).status,
    400,
  );
});

Deno.test("E-05-8 pull: viewer pulls but cannot push; non-member / uncertified / other tenant get nothing", async () => {
  const { r, tenant, book, m } = await scene(2);
  const viewer = await member(r, tenant, book, "viewer");
  const v = await body(await pull(get(pullUrl(book, 0), { token: viewer.token }), r.deps));
  assertEquals(v.envelopes.length, 2);
  const vp = await body(
    await push(
      post("/sync-push", { envelopes: [await wireEnvelope(viewer, tenant, book)] }, {
        token: viewer.token,
      }),
      r.deps,
    ),
  );
  assertEquals(vp.results[0].result, "rejected:no_role");

  const stranger = await member(r, r.db.addTenant(), null, null);
  assertEquals(
    (await pull(get(pullUrl(book, 0), { token: stranger.token }), r.deps)).status,
    404,
    "other tenant: book does not exist for them",
  );
  const noRole = await member(r, tenant, null, null);
  assertEquals((await pull(get(pullUrl(book, 0), { token: noRole.token }), r.deps)).status, 403);
  const uncertified = await member(r, tenant, book, "member", { status: "registered" });
  assertEquals(
    (await pull(get(pullUrl(book, 0), { token: uncertified.token }), r.deps)).status,
    404,
    "OTP-only device sees no tenant data (ADR 05d §2)",
  );
  const revoked = await member(r, tenant, book, "member", { status: "revoked" });
  assertEquals((await pull(get(pullUrl(book, 0), { token: revoked.token }), r.deps)).status, 404);
  assertEquals(
    (await pull(get(pullUrl(book, 0), { token: m.token, version: "0.0.1" }), r.deps)).status,
    426,
  );
  assertEquals((await pull(get(pullUrl(book, 0), {}), r.deps)).status, 401);
});

Deno.test("E-05-11 store_epoch: identical on push, pull and meta; a restore bump is visible on every route", async () => {
  const { r, book, m, acked } = await scene(1);
  const p = await body(await pull(get(pullUrl(book, 0), { token: m.token }), r.deps));
  const mt = await body(await meta(get("/sync-meta", { token: m.token }), r.deps));
  assertEquals(p.store_epoch, acked.store_epoch);
  assertEquals(mt.store_epoch, acked.store_epoch);
  r.db.bumpEpoch();
  const p2 = await body(await pull(get(pullUrl(book, 0), { token: m.token }), r.deps));
  assert(p2.store_epoch !== p.store_epoch);
  assertEquals(
    p2.envelopes.length,
    1,
    "cursor reset to 0 re-pulls; envelopes_local dedupes client-side",
  );
});
