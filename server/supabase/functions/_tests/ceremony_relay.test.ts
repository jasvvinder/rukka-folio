// The ceremony session relay on the meta channel — ADR 2026-09-13d ruling 4 🔒 (RATIFIED
// 13 Sep 2026), 04 §6.1/§6.3/§6.4/§8.6/§10.
//
// The DATABASE half of these rules is proved against a real Postgres in
// supabase/tests/rls/ceremony_sessions.test.ts (E-13d-1, E-06-20…26). This file proves the WIRE:
// that the three values reach the row byte-for-byte, that the edge function computes nothing with
// them, and that it cannot loosen the order or the write-once rule on the way past.
// Ids E-06-27, E-06-28, E-06-69.
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { handler as meta } from "../sync-meta/index.ts";
import { advance, body, get, member, post, rig } from "./harness.ts";

const B = (n: number, fill: number) => new Uint8Array(n).fill(fill);
const enc = (b: Uint8Array) => b64url.enc(b);

Deno.test("E-06-27 relay: commitment → verifier_random → opening travel opaquely and in order; the invitee writes the commitment and the opening, an active member writes r_V, and each side polls the session for the other's value (ADR 2026-09-13d ruling 4)", async () => {
  const r = rig();
  const tenant = r.db.addTenant();
  const bookId = r.db.addBook(tenant);
  const verifier = await member(r, tenant, bookId, "admin");
  const invitee = await member(r, tenant, null, null, {
    membership: "joined_pending_verification",
  });

  const commitment = B(32, 0xc1), rV = B(16, 0x52), rS = B(16, 0x53);

  // (1) the invitee commits. The digits do not exist yet on either device.
  const opened = await meta(
    post("/sync-meta/ceremony", { tenant_id: tenant, commitment: enc(commitment) }, {
      token: invitee.token,
    }),
    r.deps,
  );
  assertEquals(opened.status, 200);
  const s1 = await body(opened);
  assertEquals(s1.commitment, enc(commitment), "byte-for-byte, base64url, unchanged");
  assertEquals(s1.verifier_random, null);
  assertEquals(s1.opening, null);
  assertEquals(
    new Date(s1.expires_at).getTime() - new Date(s1.committed_at).getTime(),
    10 * 60_000,
    "ten minutes from the commitment's server timestamp (04 §6.3)",
  );

  // (2) the opening cannot come first — ordering is the whole scheme (ruling 1)
  const early = await meta(
    post("/sync-meta/ceremony/opening", { session_id: s1.session_id, opening: enc(rS) }, {
      token: invitee.token,
    }),
    r.deps,
  );
  assertEquals(early.status, 409);
  assertEquals((await body(early)).error, "ceremony_order");

  // (3) the verifier polls, sees the commitment, and only then draws r_V
  const seen = await body(
    await meta(
      get(`/sync-meta/ceremony?session_id=${s1.session_id}`, { token: verifier.token }),
      r.deps,
    ),
  );
  assertEquals(seen.commitment, enc(commitment));
  const contributed = await meta(
    post("/sync-meta/ceremony/verifier", { session_id: s1.session_id, verifier_random: enc(rV) }, {
      token: verifier.token,
    }),
    r.deps,
  );
  assertEquals(contributed.status, 200);
  assertEquals((await body(contributed)).verifier_random, enc(rV));

  // (4) the invitee polls, sees r_V, and opens
  const back = await body(
    await meta(
      get(`/sync-meta/ceremony?session_id=${s1.session_id}`, { token: invitee.token }),
      r.deps,
    ),
  );
  assertEquals(back.verifier_random, enc(rV), "the invitee's device learns r_V, unchanged");
  const openRes = await meta(
    post("/sync-meta/ceremony/opening", { session_id: s1.session_id, opening: enc(rS) }, {
      token: invitee.token,
    }),
    r.deps,
  );
  assertEquals(openRes.status, 200);

  // the stored row is exactly the three values and nothing derived from them (04 §8.6)
  const row = r.db.ceremony_sessions[0];
  assertEquals(Array.from(row.commitment), Array.from(commitment));
  assertEquals(Array.from(row.verifier_random!), Array.from(rV));
  assertEquals(Array.from(row.opening!), Array.from(rS));
  assertEquals(row.verifier_user, verifier.user, "the row records who contributed");
  const flat = JSON.stringify(
    await body(
      await meta(
        get(`/sync-meta/ceremony?session_id=${s1.session_id}`, { token: verifier.token }),
        r.deps,
      ),
    ),
  );
  for (const k of ["code", "digits", "expected", "fingerprint", "hash"]) {
    assert(!flat.includes(k), `the wire carries a derived ${k} — the server computes nothing`);
  }

  // and no source file in the relay hashes a ceremony value (ruling 4 rule 4)
  for (
    const f of ["../sync-meta/index.ts", "../_shared/store_pg.ts", "../_shared/store_mem.ts"]
  ) {
    const src = (await Deno.readTextFile(new URL(f, import.meta.url)))
      .replace(/\/\/[^\n]*/g, "");
    // every line that names a ceremony value, in any of the three files, and not one of them
    // reaches for a hash: the server relays bytes (04 §8.6, ruling 4 rule 4)
    const lines = src.split("\n").filter((l) =>
      /ceremony|commitment|verifier_random|opening/i.test(l)
    );
    assert(lines.length > 0, `${f} has no ceremony code to check`);
    for (const l of lines) {
      for (const h of ["blake2b", "sha256", "sha512", "digest(", "hmac(", "md5"]) {
        assert(
          !l.toLowerCase().includes(h),
          `${f} computes ${h} over a ceremony value: ${l.trim()}`,
        );
      }
    }
  }
});

Deno.test("E-06-28 relay refusals: another tenant, an uncertified device, the subject drawing its own r_V, a second r_V, a second opening and a malformed length are each refused by name — never silently accepted (ADR 2026-09-13d ruling 4 rules 1–3)", async () => {
  const r = rig();
  const tenant = r.db.addTenant();
  const bookId = r.db.addBook(tenant);
  const verifier = await member(r, tenant, bookId, "admin");
  const invitee = await member(r, tenant, null, null, {
    membership: "joined_pending_verification",
  });
  const raw = await member(r, tenant, null, null, {
    membership: "joined_pending_verification",
    status: "registered",
  });
  const outsider = await member(r, r.db.addTenant(), null, null);

  const commit = (token: string, t = tenant, c = B(32, 1)) =>
    meta(
      post("/sync-meta/ceremony", { tenant_id: t, commitment: enc(c) }, { token }),
      r.deps,
    );

  // an uncertified device of this tenant commits to nothing (ADR 2026-09-05d §2)
  assertEquals((await commit(raw.token)).status, 403);
  // a certified device of another tenant cannot open a session in this one
  const cross = await commit(outsider.token, tenant);
  assertEquals(cross.status, 403);
  assertEquals((await body(cross)).error, "subject_not_in_tenant");
  // lengths are pinned: 32 / 16 / 16, never anything else
  assertEquals((await commit(invitee.token, tenant, B(31, 1))).status, 400);

  const s = await body(await commit(invitee.token));

  const rv = (token: string, bytes = B(16, 2)) =>
    meta(
      post("/sync-meta/ceremony/verifier", {
        session_id: s.session_id,
        verifier_random: enc(bytes),
      }, {
        token,
      }),
      r.deps,
    );
  const open = (token: string, bytes = B(16, 3)) =>
    meta(
      post("/sync-meta/ceremony/opening", { session_id: s.session_id, opening: enc(bytes) }, {
        token,
      }),
      r.deps,
    );

  // only an already-verified ACTIVE member draws r_V (04 §6.4 delegated)
  assertEquals((await rv(outsider.token)).status, 403);
  assertEquals((await rv(raw.token)).status, 403);
  const self = await rv(invitee.token);
  assertEquals(self.status, 403);
  assert(["unknown_session", "self_verification"].includes((await body(self)).error));
  assertEquals((await rv(verifier.token, B(15, 2))).status, 400, "r_V is 128 bits");

  assertEquals((await rv(verifier.token)).status, 200);
  // r_V is drawn once: a second draw after the opening would be the grind the commitment stops
  const twice = await rv(verifier.token, B(16, 9));
  assertEquals(twice.status, 409);
  assertEquals((await body(twice)).error, "ceremony_spent");

  // the opening belongs to the device that committed, and happens once
  assertEquals((await open(verifier.token)).status, 403, "the verifier cannot open");
  assertEquals((await open(outsider.token)).status, 403);
  assertEquals((await open(invitee.token)).status, 200);
  const again = await open(invitee.token, B(16, 8));
  assertEquals(again.status, 409);
  assertEquals((await body(again)).error, "ceremony_spent");

  // the values that landed are the first ones, unchanged
  const row = r.db.ceremony_sessions[0];
  assertEquals(Array.from(row.verifier_random!), Array.from(B(16, 2)));
  assertEquals(Array.from(row.opening!), Array.from(B(16, 3)));

  // another tenant cannot even read the session
  assertEquals(
    (await meta(
      get(`/sync-meta/ceremony?session_id=${s.session_id}`, { token: outsider.token }),
      r.deps,
    )).status,
    404,
  );
});

Deno.test("E-06-69 discovery: GET /sync-meta/ceremony?subject_user_id=&tenant_id= hands a verifier the newest UNEXPIRED session for a scanned subject, in the SAME shape as the by-id GET, and adds no authority — another tenant's certified device and an uncertified device of this tenant get 404 no_live_session, an expired session is never returned, and the subject reads its own (04 §6.1/§6.4, 0007's select policy unchanged)", async () => {
  const r = rig();
  const tenant = r.db.addTenant();
  const bookId = r.db.addBook(tenant);
  const verifier = await member(r, tenant, bookId, "admin");
  const invitee = await member(r, tenant, null, null, {
    membership: "joined_pending_verification",
  });
  const raw = await member(r, tenant, null, null, {
    membership: "joined_pending_verification",
    status: "registered",
  });
  const outsider = await member(r, r.db.addTenant(), null, null);

  // Why this route exists: 04 §6.1's QR payload is
  // base64url( suite_version ‖ user_id ‖ UMK_pub_ed ‖ UMK_pub_x ‖ nonce ) — no session id, and the
  // session id is minted HERE at commit. A verifier that has just scanned therefore holds a
  // user_id and has no way to reach the row it must write r_V into, which makes 04 §6.4's
  // *delegated* ceremony unimplementable. Discovery is the missing step and nothing more.
  const find = (token: string, subject = invitee.user, t = tenant) =>
    meta(
      get(`/sync-meta/ceremony?subject_user_id=${subject}&tenant_id=${t}`, { token }),
      r.deps,
    );

  assertEquals((await find(verifier.token)).status, 404, "no session yet, and no oracle about it");
  assertEquals((await body(await find(verifier.token))).error, "no_live_session");

  const older = await body(
    await meta(
      post("/sync-meta/ceremony", { tenant_id: tenant, commitment: enc(B(32, 0xa1)) }, {
        token: invitee.token,
      }),
      r.deps,
    ),
  );
  advance(r, 30_000); // *Regenerate* (04 §6.3) opens a fresh session; nothing mutates the old one
  const newest = await body(
    await meta(
      post("/sync-meta/ceremony", { tenant_id: tenant, commitment: enc(B(32, 0xa2)) }, {
        token: invitee.token,
      }),
      r.deps,
    ),
  );

  // ---- the answer is the newest live session, and byte-identical to the by-id GET, so the app
  // decodes ONE shape (the app lane consumes this next cycle and must not have to guess).
  const discovered = await body(await find(verifier.token));
  assertEquals(discovered.session_id, newest.session_id, "newest first, by committed_at");
  const byId = await body(
    await meta(
      get(`/sync-meta/ceremony?session_id=${newest.session_id}`, { token: verifier.token }),
      r.deps,
    ),
  );
  assertEquals(discovered, byId, "the same JSON shape as ?session_id= — one decoder, not two");
  assertEquals(discovered.commitment, enc(B(32, 0xa2)));
  assertNotEquals(discovered.session_id, older.session_id);

  // and it is a route to a row the caller could already read: r_V goes straight in
  const contributed = await meta(
    post("/sync-meta/ceremony/verifier", {
      session_id: discovered.session_id,
      verifier_random: enc(B(16, 0x52)),
    }, { token: verifier.token }),
    r.deps,
  );
  assertEquals(contributed.status, 200, "the scan reaches the ceremony it was meant to reach");

  // ---- the subject polls its own the same way
  assertEquals(
    (await body(await find(invitee.token))).session_id,
    newest.session_id,
    "the subject reads its own live session",
  );

  // ---- no new authority. These three already saw nothing asking by id (E-06-28); they see
  // nothing asking by subject, and get the SAME named 404, never a distinguishable refusal that
  // would say whose ceremony is in flight.
  for (
    const [who, token] of [
      ["a certified device of ANOTHER tenant", outsider.token],
      ["an UNCERTIFIED device of this tenant", raw.token],
    ] as const
  ) {
    const res = await find(token);
    assertEquals(res.status, 404, `${who} discovers nothing`);
    assertEquals((await body(res)).error, "no_live_session");
  }
  // the uncertified device is refused for its own user, too
  assertEquals((await find(raw.token, raw.user)).status, 404);
  // and a subject in another tenant is not found through this tenant
  assertEquals((await find(verifier.token, outsider.user)).status, 404);

  // ---- malformed parameters are a 400, not a scan of the table
  for (const q of ["", "?subject_user_id=nope&tenant_id=nope", `?tenant_id=${tenant}`]) {
    const res = await meta(get(`/sync-meta/ceremony${q}`, { token: verifier.token }), r.deps);
    assertEquals(res.status, 400, `"${q}" is bad_request`);
    assertEquals((await body(res)).error, "bad_request");
  }

  // ---- an EXPIRED session is never handed back: a device that polled it would wait forever, and
  // 0007's guard would refuse every write to it anyway (04 §6.3, ten minutes from the commitment).
  advance(r, 11 * 60_000);
  const dead = await find(verifier.token);
  assertEquals(dead.status, 404);
  assertEquals((await body(dead)).error, "no_live_session");
  assertEquals(
    (await meta(
      get(`/sync-meta/ceremony?session_id=${newest.session_id}`, { token: verifier.token }),
      r.deps,
    )).status,
    200,
    "…while the by-id GET still returns it, so an open screen can see it has expired",
  );
});
