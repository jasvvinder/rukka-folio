// POST /sync-meta/records — what a record id answers when it is sent again, or was never the
// caller's to send (desk 90 (b), (c); MemStore half — the database half is
// tests/rls/records_replay.test.ts, which runs the same handler over PgStore as rf_api).
//
//   * E-05g-32 (desk 90(c)): a re-sent id whose stored record was refused WITH A NOTE (applied_at
//     set, apply_note `rejected:<name>`) answers that refusal again — the same `result` and the
//     same `seq` — and never `acked`. ADR 2026-10-03 *Open* (§7 (a)'s neighbour) names the defect:
//     the replay said `acked` although nothing was applied. The `/records` replay is ADR 2026-10-03
//     §7's (marker family E-05g); ADR 2026-09-05b §7 is rate limits and quotas and is not the
//     authority here. The applied arm is unchanged: a record applied with an ordinary note is
//     still acked on replay and applied once.
//   * E-05g-33 (desk 90(b); ADR 2026-10-03 §7 (b)): a NEW record reusing the id of a record the
//     caller cannot see (another tenant's) is refused for that row with the answer the visible arm
//     already gives another device's record under the id — `rejected:shape`, check `id`, no seq —
//     never a 500, and the rest of the batch stands. Nothing about the stored record changes.
//     (The concurrent-insert arm, E-05g-34, has no MemStore half: MemStore has no transactions to
//     race. It is in tests/rls/records_replay.test.ts.)
//
// The `check` of the first answer (`not_admin`, …) is not stored — the note holds the result only
// — so a replay carries none (reported to the owner in the lane's `open`).
// Fixtures are synthetic: random keys, uuids and label payloads; no ledger content exists here.
import { assert, assertEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { handler as meta } from "../sync-meta/index.ts";
import { body, type Member, member, post, random, type Rig, rig, signedRecord } from "./harness.ts";

type Answer = { id: string; result: string; seq?: string; check?: string };

async function send(r: Rig, m: Member, wires: unknown[]): Promise<Answer[]> {
  const res = await meta(
    post("/sync-meta/records", { records: wires }, { token: m.token }),
    r.deps,
  );
  assertEquals(res.status, 200, "a refusal is that record's answer, never the request's");
  return (await body(res)).results as Answer[];
}

async function fixture() {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const admin = await member(r, tenant, book, "admin");
  const plain = await member(r, tenant, book, "member");
  return { r, tenant, book, admin, plain };
}

Deno.test("E-05g-32 POST /sync-meta/records, re-sent (desk 90(c)): a record the server refused with a note answers that refusal again — same result, same seq — never acked, however often it is re-sent; it is stored once, its applied mark is not moved, and nothing is projected; a record applied with an ordinary note is still acked on replay (ADR 2026-10-03 §7 and its Open item, §7 (a)'s neighbour)", async (t) => {
  const cases: {
    name: string;
    author: "admin" | "plain";
    kind: string;
    payload: (f: Awaited<ReturnType<typeof fixture>>) => Promise<Record<string, unknown>>;
    result: string;
    check?: string;
  }[] = [
    {
      name: "a non-admin's member_removal: rejected:unauthorized (not_admin)",
      author: "plain",
      kind: "member_removal",
      payload: (f) => Promise.resolve({ user_id: f.admin.user }),
      result: "rejected:unauthorized",
      check: "not_admin",
    },
    {
      name: "a membership_status with no such status: rejected:shape",
      author: "admin",
      kind: "membership_status",
      payload: (f) => Promise.resolve({ user_id: f.plain.user, status: "no_such_status" }),
      result: "rejected:shape",
    },
    {
      name: "an invite sent to /records: rejected:invite_route",
      author: "admin",
      kind: "invite",
      payload: async (f) => ({
        roles: [{ book_id: f.book, role: "member" }],
        nonce: b64url.enc(await random(16)),
      }),
      result: "rejected:invite_route",
    },
  ];
  for (const c of cases) {
    await t.step(c.name, async () => {
      const f = await fixture();
      const author = c.author === "admin" ? f.admin : f.plain;
      const rec = await signedRecord(author, f.tenant, c.kind, await c.payload(f));
      const before = JSON.stringify(f.r.db.memberships);

      const [first] = await send(f.r, author, [rec.wire]);
      const want: Answer = { id: rec.row.id, result: c.result, seq: first.seq };
      if (c.check) want.check = c.check;
      assertEquals(first, want, "the first answer names the refusal");
      assert(typeof first.seq === "string" && /^\d+$/.test(first.seq), "answered with its seq");
      const stored = f.r.db.signed_records.find((x) => x.id === rec.row.id)!;
      assertEquals(stored.apply_note, c.result, "precondition: stored, noted with the refusal");
      const appliedAt = stored.applied_at;
      assert(appliedAt instanceof Date, "precondition: marked (refused) on arrival");

      for (let i = 1; i <= 2; i++) {
        const [again] = await send(f.r, author, [rec.wire]);
        assertEquals(
          [again.id, again.result, again.seq],
          [rec.row.id, c.result, first.seq],
          `re-send ${i}: the stored refusal and its seq, not acked`,
        );
        assertEquals(
          "check" in again,
          false,
          `re-send ${i}: no check is invented — none is stored`,
        );
      }
      assertEquals(
        f.r.db.signed_records.filter((x) => x.id === rec.row.id).length,
        1,
        "stored once (append-only), however often it is re-sent",
      );
      assertEquals(stored.applied_at, appliedAt, "the applied mark is the first one, not moved");
      assertEquals(stored.apply_note, c.result, "the note is the first one");
      assertEquals(JSON.stringify(f.r.db.memberships), before, "nothing projected, ever");
    });
  }

  await t.step("a record applied with an ordinary note is acked on replay", async () => {
    const f = await fixture();
    const rec = await signedRecord(f.admin, f.tenant, "designation", { label: "synthetic" });
    const [first] = await send(f.r, f.admin, [rec.wire]);
    assertEquals(first.result, "acked");
    assertEquals(
      f.r.db.signed_records.find((x) => x.id === rec.row.id)?.apply_note,
      "label only",
      "precondition: applied with a note that is not a refusal",
    );
    const [again] = await send(f.r, f.admin, [rec.wire]);
    assertEquals([again.result, again.seq], ["acked", first.seq], "acked with the stored seq");
  });

  await t.step("a refused replay does not take the rest of the batch with it", async () => {
    const f = await fixture();
    const refused = await signedRecord(f.plain, f.tenant, "member_removal", {
      user_id: f.admin.user,
    });
    await send(f.r, f.plain, [refused.wire]);
    const good = await signedRecord(f.plain, f.tenant, "designation", { label: "synthetic" });
    const [a, b] = await send(f.r, f.plain, [refused.wire, good.wire]);
    assertEquals([a.id, a.result], [refused.row.id, "rejected:unauthorized"]);
    assertEquals([b.id, b.result], [good.row.id, "acked"]);
  });
});

Deno.test("E-05g-33 POST /sync-meta/records, a new record under the id of a record the caller cannot see (desk 90(b); ADR 2026-10-03 §7 (b)): refused for that row exactly as the visible arm refuses another device's record under the id — rejected:shape, check id, no seq — never a 500; the batch's other records stand, the stored record is untouched, and /invites answers 400 bad_record (check id) for the same id", async () => {
  const r = rig();
  const tA = r.db.addTenant(), tB = r.db.addTenant();
  const bookA = r.db.addBook(tA), bookB = r.db.addBook(tB);
  const a = await member(r, tA, bookA, "admin");
  const a2 = await member(r, tA, bookA, "admin");
  const b = await member(r, tB, bookB, "admin");

  // B's record, which nobody in A can see.
  const theirs = await signedRecord(b, tB, "designation", { label: "synthetic" });
  assertEquals((await send(r, b, [theirs.wire]))[0].result, "acked", "precondition: B's record");
  // A second device of A's tenant files under another id: the VISIBLE arm, for comparison.
  const seen = await signedRecord(a2, tA, "designation", { label: "synthetic" });
  assertEquals((await send(r, a2, [seen.wire]))[0].result, "acked", "precondition: a2's record");
  const storedBefore = structuredClone(r.db.signed_records.find((x) => x.id === theirs.row.id));

  const reuse = await signedRecord(a, tA, "designation", { label: "synthetic" }, {
    id: theirs.row.id,
  });
  const reuseSeen = await signedRecord(a, tA, "designation", { label: "synthetic" }, {
    id: seen.row.id,
  });
  const good = await signedRecord(a, tA, "designation", { label: "synthetic" });
  const [hidden, visible, ok] = await send(r, a, [reuse.wire, reuseSeen.wire, good.wire]);
  assertEquals(hidden, { id: theirs.row.id, result: "rejected:shape", check: "id" });
  assertEquals(visible, { id: seen.row.id, result: "rejected:shape", check: "id" });
  assertEquals(
    Object.keys(hidden).sort(),
    Object.keys(visible).sort(),
    "an id the caller cannot see answers no more than one it can",
  );
  assertEquals([ok.id, ok.result], [good.row.id, "acked"], "the batch's other record stands");
  assertEquals(
    r.db.signed_records.filter((x) => x.id === theirs.row.id).length,
    1,
    "nothing stored under the id for the caller",
  );
  assertEquals(
    r.db.signed_records.find((x) => x.id === theirs.row.id),
    storedBefore,
    "B's record is untouched",
  );

  const inv = await signedRecord(a, tA, "invite", {
    roles: [{ book_id: bookA, role: "member" }],
    nonce: b64url.enc(await random(16)),
  }, { id: theirs.row.id });
  const res = await meta(
    post("/sync-meta/invites", { record: inv.wire, phone: "+919876500012" }, { token: a.token }),
    r.deps,
  );
  assertEquals(res.status, 400, "/invites shares the intake: a named refusal, never a 500");
  assertEquals(await body(res), { error: "bad_record", check: "id" });
});
