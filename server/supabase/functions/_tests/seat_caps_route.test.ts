// The hard caps on the wire — sync-meta's half of migration 0019 (ADR 2026-09-05g §2, §6 🔒).
// Ids E-05g-14, E-05g-16.
//
// The database raises `seat_cap`, `seat_rotation_cap` and `book_cap` as P0001 with the bare name;
// _shared/store.ts denialFromPg passes the name through as StoreDenied(<name>) (proved against the
// real database by tests/rls/seat_book_caps.test.ts E-05g-2). This file pins what the ROUTES do with
// that name, so the client can tell a full plan from a forbidden request:
//   * POST /sync-meta/invites → 409 {error: "seat_cap" | "seat_rotation_cap" | "book_cap"} (409
//     like auth-challenge's device_cap; book_cap included so a future route through inviteError
//     cannot turn it into a 403 — desk 68(b)), and the signed record stays stored, noted
//     `rejected:<name>`;
//   * POST /sync-meta/records (membership_status) → result `rejected:<name>`, check `<name>` —
//     never `rejected:unauthorized`, which is what any other denial there still says;
//   * a RE-SENT /records record the cap refused is never `acked` while nothing was applied
//     (desk 68(a), E-05g-16).
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

for (const reason of ["seat_cap", "seat_rotation_cap", "book_cap"]) {
  Deno.test(
    "E-05g-14 POST /sync-meta/invites on a plan with no room answers 409 by name — not 403, not a generic denial — and the admin's signed record stays stored, noted rejected: " +
      reason,
    async () => {
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
    },
  );
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

Deno.test("E-05g-16 POST /sync-meta/records, re-sent (desk 68(a)): a record the cap refused is never answered `acked` while nothing was applied — the stored record is asked again and, the plan still full, answers the same rejected:<name>, projecting nothing; once the plan has room that same record applies and only then is acked; a record that WAS applied is acked on replay and not applied a second time; and a re-sent id that is another device's record is refused, never acked", async (t) => {
  for (const reason of ["seat_cap", "seat_rotation_cap"]) {
    await t.step(reason, async () => {
      const f = await fixture();
      const roomy = f.r.deps.store;
      refusing(f.r, "projectMembership", reason);
      const joiner = f.r.db.addUser().id;
      const rec = await signedRecord(f.admin, f.tenant, "membership_status", {
        user_id: joiner,
        status: "joined_pending_verification",
      });
      const send = async () =>
        (await body(
          await meta(
            post("/sync-meta/records", { records: [rec.wire] }, { token: f.admin.token }),
            f.r.deps,
          ),
        )).results[0];
      const first = await send();
      assertEquals([first.result, first.check], [`rejected:${reason}`, reason]);
      for (let i = 0; i < 2; i++) {
        const again = await send();
        assertEquals(
          [again.id, again.result, again.check, again.seq],
          [rec.row.id, `rejected:${reason}`, reason, undefined],
          `re-send ${i + 1}: the same named refusal, not acked`,
        );
      }
      const stored = f.r.db.signed_records.filter((x) => x.id === rec.row.id);
      assertEquals(stored.length, 1, "stored once (append-only), however often it is re-sent");
      assertEquals(stored[0].applied_at, null, "and never marked applied");
      assertEquals(
        f.r.db.memberships.find((m) => m.tenant_id === f.tenant && m.user_id === joiner),
        undefined,
        "nothing projected",
      );

      // ⚠️ SPEC (0021 / sync-meta): a never-applied record is asked again, so once the plan has
      // room the same record applies — and is acked because it applied.
      f.r.deps.store = roomy;
      const later = await send();
      assertEquals(later.result, "acked");
      assertEquals(typeof later.seq, "string");
      assertEquals(
        f.r.db.memberships.find((m) => m.tenant_id === f.tenant && m.user_id === joiner)?.status,
        "joined_pending_verification",
      );
    });
  }

  await t.step("an applied record is acked on replay and not applied again", async () => {
    const f = await fixture();
    const joiner = f.r.db.addUser().id;
    const send = async (wire: unknown) =>
      (await body(
        await meta(
          post("/sync-meta/records", { records: [wire] }, { token: f.admin.token }),
          f.r.deps,
        ),
      )).results[0];
    const join = await signedRecord(f.admin, f.tenant, "membership_status", {
      user_id: joiner,
      status: "joined_pending_verification",
    });
    const a = await send(join.wire);
    assertEquals(a.result, "acked");
    const removal = await signedRecord(f.admin, f.tenant, "member_removal", { user_id: joiner });
    assertEquals((await send(removal.wire)).result, "acked");
    const replay = await send(join.wire);
    assertEquals([replay.result, replay.seq], ["acked", a.seq], "the stored outcome, its seq");
    assertEquals(
      f.r.db.memberships.find((m) => m.tenant_id === f.tenant && m.user_id === joiner)?.status,
      "removed",
      "the later record still stands: a replay never re-applies an applied record",
    );
  });

  await t.step("another device's record id is refused, not acked", async () => {
    const f = await fixture();
    refusing(f.r, "projectMembership", "seat_cap");
    const admin2 = await member(f.r, f.tenant, f.book, "admin");
    const joiner = f.r.db.addUser().id;
    const mine = await signedRecord(f.admin, f.tenant, "membership_status", {
      user_id: joiner,
      status: "joined_pending_verification",
    });
    await meta(
      post("/sync-meta/records", { records: [mine.wire] }, { token: f.admin.token }),
      f.r.deps,
    );
    const theirs = await signedRecord(admin2, f.tenant, "membership_status", {
      user_id: joiner,
      status: "joined_pending_verification",
    }, { id: mine.row.id });
    const [out] = (await body(
      await meta(
        post("/sync-meta/records", { records: [theirs.wire] }, { token: admin2.token }),
        f.r.deps,
      ),
    )).results;
    assertEquals([out.id, out.result, out.check], [mine.row.id, "rejected:shape", "id"]);
    assertEquals(f.r.db.signed_records.filter((x) => x.id === mine.row.id).length, 1);
  });
});
