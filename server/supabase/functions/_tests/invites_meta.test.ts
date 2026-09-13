// The invite half of the meta channel (05 §5, 06 §7, ADR 2026-09-05c §4). Ids E-06-18, E-06-19.
//
// The database now keeps `invitee_hmac` and the ceremony nonce outside rf_api's column grant, so
// the only way they could still reach a second admin's screen is the wire. This pins that shut:
// the row sync-meta hands out says an invite exists, when it expires and who sent it — nothing
// that identifies whom the family invited.
import { assert, assertEquals } from "@std/assert";
import { handler as meta } from "../sync-meta/index.ts";
import { body, get, type Member, member, post, rig, signedRecord } from "./harness.ts";

Deno.test("E-06-18 meta: an invite on the wire carries no invitee_hmac and no nonce — a second admin learns that an invite exists and who sent it, never whom (ADR 2026-09-05c §4)", async () => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const admin = await member(r, tenant, book, "admin");
  const coAdmin = await member(r, tenant, book, "admin");
  const outsider = await member(r, r.db.addTenant(), null, null);

  const hmac = new Uint8Array(32).fill(42);
  const nonce = new Uint8Array(16).fill(7);
  r.db.invites.push({
    id: crypto.randomUUID(),
    tenant_id: tenant,
    invitee_hmac: hmac,
    nonce,
    roles: [{ book_id: book, role: "member" }],
    status: "sent",
    expires_at: new Date(r.clock.now.getTime() + 7 * 86400_000),
    created_by: admin.user,
    created_at: new Date(r.clock.now),
    accepted_by: null,
    accepted_at: null,
    source_record_id: crypto.randomUUID(),
    updated_at: new Date(r.clock.now),
  });

  for (const who of [admin, coAdmin]) {
    const page = await body(await meta(get("/sync-meta", { token: who.token }), r.deps));
    assertEquals(page.invites.length, 1);
    const inv = page.invites[0];
    assertEquals(inv.created_by, admin.user, "who sent it is part of the tenant's own history");
    assertEquals(inv.status, "sent");
    assert(inv.expires_at > 0, "the 7-day window is visible");
    for (const leak of ["invitee_hmac", "nonce", "phone", "phone_e164", "invitee"]) {
      assert(!(leak in inv), `invite row leaks ${leak}`);
    }
    // and nothing hmac-shaped smuggled through under another name
    const flat = JSON.stringify(page.invites);
    for (const b of [hmac, nonce]) {
      assert(!flat.includes(btoa(String.fromCharCode(...b)).replace(/[+/=]/g, "")), "raw bytes");
    }
  }

  // another tenant sees no invite at all
  const theirs = await body(await meta(get("/sync-meta", { token: outsider.token }), r.deps));
  assertEquals(theirs.invites.length, 0);

  // an uncertified device of this tenant sees none either (ADR 2026-09-05d §2)
  const raw = await member(r, tenant, book, "member", { status: "registered" });
  const rawPage = await body(await meta(get("/sync-meta", { token: raw.token }), r.deps));
  assertEquals(rawPage.invites.length, 0);
});

Deno.test("E-06-19 meta/records: a membership_status record cannot walk an edge 06 §7 does not draw — no jump to active without a ceremony, no way back out of blocked", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const admin = await member(r, tenant, book, "admin");
  const send = async (m: Member, user: string, status: string) => {
    const rec = await signedRecord(m, tenant, "membership_status", { user_id: user, status });
    const res = await body(
      await meta(
        post("/sync-meta/records", { records: [rec.wire] }, {
          token: m.token,
        }),
        r.deps,
      ),
    );
    return res.results[0];
  };

  await t.step("a stranger cannot be declared active — the ceremony grants that edge", async () => {
    const stranger = r.db.addUser().id;
    assertEquals((await send(admin, stranger, "active")).result, "rejected:membership_transition");
    assertEquals(r.db.memberships.find((m) => m.user_id === stranger), undefined);
    // the honest edge is acked
    assertEquals((await send(admin, stranger, "joined_pending_verification")).result, "acked");
  });

  await t.step(
    "blocked reaches nothing but removed (06 §7: a new invite is required)",
    async () => {
      const bad = await member(r, tenant, book, "member", { membership: "blocked" });
      for (const s of ["active", "joined_pending_verification", "invited"]) {
        assertEquals(
          (await send(admin, bad.user, s)).result,
          "rejected:membership_transition",
          `blocked → ${s}`,
        );
      }
      assertEquals((await send(admin, bad.user, "removed")).result, "acked");
    },
  );

  await t.step("an active member is not demoted back to invited", async () => {
    const peer = await member(r, tenant, book, "member");
    assertEquals(
      (await send(admin, peer.user, "invited")).result,
      "rejected:membership_transition",
    );
    assertEquals(
      r.db.memberships.find((m) => m.user_id === peer.user)!.status,
      "active",
      "refused records change nothing",
    );
  });

  await t.step("the tenant's founder is the one exception (06 §5)", async () => {
    const fresh = r.db.addTenant();
    const rec = await signedRecord(admin, fresh, "membership_status", {
      user_id: admin.user,
      status: "active",
    });
    const res = await body(
      await meta(
        post("/sync-meta/records", { records: [rec.wire] }, {
          token: admin.token,
        }),
        r.deps,
      ),
    );
    assertEquals(res.results[0].result, "acked", "nobody exists yet to verify the first member");
  });
});
