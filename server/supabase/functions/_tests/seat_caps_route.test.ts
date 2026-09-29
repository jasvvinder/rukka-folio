// The hard caps on the wire — sync-meta's half of migration 0019 (ADR 2026-09-05g §2, §6 🔒).
// Id E-05g-14.
//
// The database raises `seat_cap`, `seat_rotation_cap` and `book_cap` as P0001 with the bare name;
// _shared/store.ts denialFromPg passes the name through as StoreDenied(<name>) (proved against the
// real database by tests/rls/seat_book_caps.test.ts E-05g-2). This file pins what the ROUTES do with
// that name, so the client can tell a full plan from a forbidden request:
//   * POST /sync-meta/invites → 409 {error: "seat_cap" | "seat_rotation_cap"} (409 like
//     auth-challenge's device_cap), and the signed record stays stored, noted `rejected:<name>`;
//   * POST /sync-meta/records (membership_status) → result `rejected:<name>`, check `<name>` —
//     never `rejected:unauthorized`, which is what any other denial there still says.
// The MemStore has no plan catalogue behind it, so the store's refusal is injected at the one Tx
// method under test; everything else is the real handler over the real MemStore.
import { assertEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import type { Store, Tx } from "../_shared/store.ts";
import { StoreDenied } from "../_shared/store.ts";
import { handler as meta } from "../sync-meta/index.ts";
import { body, member, post, random, type Rig, rig, signedRecord } from "./harness.ts";

/** The rig's store, except that `method` refuses with `reason` — as PgStore would after 0019. */
function refusing(r: Rig, method: keyof Tx, reason: string): void {
  const inner: Store = r.deps.store;
  r.deps.store = {
    withClaims: (claims, fn) =>
      inner.withClaims(claims, (tx) =>
        fn(
          new Proxy(tx, {
            get(target, prop, recv) {
              if (prop === method) return () => Promise.reject(new StoreDenied(reason));
              const v = Reflect.get(target, prop, recv);
              return typeof v === "function" ? v.bind(target) : v;
            },
          }),
        )),
  };
}

async function fixture() {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const admin = await member(r, tenant, book, "admin");
  return { r, tenant, book, admin };
}

for (const reason of ["seat_cap", "seat_rotation_cap"]) {
  Deno.test(`E-05g-14 POST /sync-meta/invites on a plan with no room answers 409 ${reason} by name — not 403, not a generic denial — and the admin's signed record stays stored, noted rejected:${reason}`, async () => {
    const f = await fixture();
    refusing(f.r, "createInvite", reason);
    const rec = await signedRecord(f.admin, f.tenant, "invite", {
      roles: [{ book_id: f.book, role: "member" }],
      nonce: b64url.enc(await random(16)),
    });
    const res = await meta(
      post("/sync-meta/invites", { record: rec.wire, phone: "+919876500011" }, {
        token: f.admin.token,
      }),
      f.r.deps,
    );
    assertEquals(res.status, 409);
    assertEquals(await body(res), { error: reason });
    const stored = f.r.db.signed_records.find((x) => x.id === rec.row.id);
    assertEquals(stored?.apply_note, `rejected:${reason}`, "a signed fact is kept, append-only");
    assertEquals(f.r.db.invites.length, 0, "and no invite row exists");
  });
}

Deno.test("E-05g-14 POST /sync-meta/records: a membership_status record the seat cap refuses comes back rejected:seat_cap with check seat_cap, while any other store denial on the same path still reads rejected:unauthorized", async () => {
  for (
    const [reason, want] of [
      ["seat_cap", "rejected:seat_cap"],
      ["seat_rotation_cap", "rejected:seat_rotation_cap"],
      ["rls", "rejected:unauthorized"],
    ] as const
  ) {
    const f = await fixture();
    refusing(f.r, "projectMembership", reason);
    const joiner = f.r.db.addUser().id;
    const rec = await signedRecord(f.admin, f.tenant, "membership_status", {
      user_id: joiner,
      status: "joined_pending_verification",
    });
    const res = await meta(
      post("/sync-meta/records", { records: [rec.wire] }, { token: f.admin.token }),
      f.r.deps,
    );
    assertEquals(res.status, 200);
    const [out] = (await body(res)).results;
    assertEquals([out.id, out.result, out.check], [rec.row.id, want, reason], reason);
  }
});
