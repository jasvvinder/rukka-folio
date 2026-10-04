// POST /sync-meta/records over the REAL store (PgStore as rf_api, via _pg_api.ts): what a record id
// answers when it is sent again, or was never the caller's to send — desk 90 (b), (c). The MemStore
// half is functions/_tests/records_replay.test.ts; this half exists because only Postgres has the
// two things the defects live in: signed_records_select hiding another tenant's record from the
// duplicate lookup, and the primary key the INSERT then meets.
//
//   * E-05g-32 (database half, desk 90(c)): a re-sent id whose stored record was refused with a note
//     (applied_at set, apply_note `rejected:<name>`) answers that refusal again — the same result and
//     seq — never `acked`; nothing is projected, the row is not touched. A record applied with an
//     ordinary note is still acked on replay. ADR 2026-10-03 §7 and its *Open* item (§7 (a)'s
//     neighbour); the `/records` replay is that ADR's §7, marker family E-05g.
//   * E-05g-33 (database half, desk 90(b); ADR 2026-10-03 §7 (b)): a new record reusing the id of a
//     record the caller cannot see answers `rejected:shape`, check `id`, no seq — what another
//     device's VISIBLE record under the id answers — never a 500 (23505 on signed_records_pkey was
//     unmapped). The batch's other records commit; the stored record is untouched; /invites answers
//     400 bad_record (check id).
//   * E-05g-34 (database only, desk 90(b) repair; ADR 2026-10-03 §7 (b)): the primary key also meets
//     a row ANOTHER TRANSACTION is inserting — under READ COMMITTED the duplicate lookup cannot see
//     an uncommitted row, the INSERT waits on the key, and raises 23505 once that transaction
//     commits. When the committed row is the caller's OWN device's record (a sibling request of the
//     same device), it is answered from the stored record — never `rejected:shape`/`id`, which §7
//     (b) gives only to an id owned by another device. When it is another device's record, it still
//     answers `rejected:shape`, check `id`.
//
// Fixtures are written by the schema owner without claims; payloads are synthetic labels and random
// bytes — no ledger content exists here. Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`);
// without it every test is SKIPPED and says why, and RLS_REQUIRE=1 makes that a failure.
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import postgres from "postgres";
import { b64url } from "../../functions/_shared/bytes.ts";
import { handler as meta } from "../../functions/sync-meta/index.ts";
import {
  body,
  edKeypair,
  type KeyPair,
  type Member,
  post,
  random,
  reissue,
  type Rig,
  rig,
  signedRecord,
} from "../../functions/_tests/harness.ts";
import { apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — records_replay.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP records_replay.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

function test(name: string, fn: () => Promise<void>) {
  Deno.test({
    name,
    ignore,
    async fn() {
      sql = postgres(url!, { max: 2, onnotice: () => {} });
      try {
        await fn();
      } finally {
        await sql.end();
      }
    },
  });
}

// ---------------------------------------------------------------- fixtures (schema owner, no claims)
interface P {
  user: string;
  dev: string;
  keys: KeyPair;
}
async function mkPerson(): Promise<P> {
  const keys = await edKeypair();
  const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${rand(32)}, ${rand(40)})
    returning id`;
  const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${u.id}, ${keys.pub}, ${rand(32)}, 'certified') returning id`;
  return { user: u.id as string, dev: d.id as string, keys };
}
interface Tn {
  t: string;
  founder: P;
  personal: string;
}
/** A family tenant on the Free floor whose founder is active and admin of their personal book. */
async function tenant(): Promise<Tn> {
  const [row] = await sql`insert into tenants (type) values ('family') returning id`;
  const t = row.id as string;
  const founder = await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${founder.user}, 'active')`;
  const personal = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type, owner_user_id)
    values (${personal}, ${t}, 'personal', ${founder.user})`;
  await sql`insert into book_roles (book_id, user_id, role)
    values (${personal}, ${founder.user}, 'admin')`;
  return { t, founder, personal };
}
/** An ACTIVE member with no role, placed by the owner after a signed ceremony (0006/0008). */
async function activeMember(tn: Tn): Promise<P> {
  const p = await mkPerson();
  const rec = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${rec}, 1, ${tn.t}, 'verification_event', '{}'::jsonb, ${rand(8)}, ${tn.founder.dev},
            ${rand(64)}, 1)`;
  await sql`insert into verification_events
    (tenant_id, subject_user, verifier_user, method, result, source_record_id)
    values (${tn.t}, ${p.user}, ${tn.founder.user}, 'qr_in_person', 'verified', ${rec})`;
  await sql`insert into memberships (tenant_id, user_id, status) values (${tn.t}, ${p.user}, 'active')`;
  return p;
}
/** The harness's Member shape for a person whose rows live in Postgres. */
async function signer(r: Rig, p: P): Promise<Member> {
  const m = {
    user: p.user,
    device: { id: p.dev },
    keys: p.keys,
    xpub: rand(32),
    claims: { user_id: p.user, device_id: p.dev },
    token: "",
  } as unknown as Member;
  await reissue(r, m);
  return m;
}

// ---------------------------------------------------------------- fresh reads (owner)
async function rowsUnder(id: string) {
  return await sql`select tenant_id, author_device, seq, applied_at, apply_note
    from signed_records where id = ${id}`;
}
async function statusOf(t: string, user: string): Promise<string | null> {
  const [r] =
    await sql`select status from memberships where tenant_id = ${t} and user_id = ${user}`;
  return (r?.status as string) ?? null;
}

type Answer = { id: string; result: string; seq?: string; check?: string };
async function send(r: Rig, m: Member, wires: unknown[]): Promise<Answer[]> {
  const res = await meta(
    post("/sync-meta/records", { records: wires }, { token: m.token }),
    r.deps,
  );
  assertEquals(res.status, 200, "a refusal is that record's answer, never the request's");
  return (await body(res)).results as Answer[];
}

test(
  "E-05g-32 (database half) POST /sync-meta/records over the real store, re-sent (desk 90(c)): a record refused with a note — a non-admin's member_removal (rejected:unauthorized, not_admin) and a membership_status of no such status (rejected:shape) — answers that refusal again with the same seq, never acked; one row, its applied mark and note unchanged, nothing projected; a record applied with an ordinary note is acked on replay (ADR 2026-10-03 §7 and its Open item, §7 (a)'s neighbour)",
  async () => {
    const tn = await tenant();
    const plainP = await activeMember(tn);
    const r = rig();
    const admin = await signer(r, tn.founder);
    const plain = await signer(r, plainP);
    const removal = await signedRecord(plain, tn.t, "member_removal", { user_id: tn.founder.user });
    const bogus = await signedRecord(admin, tn.t, "membership_status", {
      user_id: plainP.user,
      status: "no_such_status",
    });
    const label = await signedRecord(admin, tn.t, "designation", { label: "synthetic" });

    const store = await apiStore(url!);
    r.deps.store = store;
    try {
      for (
        const [who, rec, result, check] of [
          [plain, removal, "rejected:unauthorized", "not_admin"],
          [admin, bogus, "rejected:shape", undefined],
        ] as const
      ) {
        const [first] = await send(r, who, [rec.wire]);
        const want: Answer = { id: rec.row.id, result, seq: first.seq };
        if (check) want.check = check;
        assertEquals(first, want, `${result}: the first answer names the refusal`);
        assert(typeof first.seq === "string" && /^\d+$/.test(first.seq), "answered with its seq");
        const [kept] = await rowsUnder(rec.row.id);
        assertEquals(kept.apply_note, result, `precondition: stored, noted ${result}`);
        assertNotEquals(kept.applied_at, null, "precondition: marked (refused) on arrival");

        for (let i = 1; i <= 2; i++) {
          const [again] = await send(r, who, [rec.wire]);
          assertEquals(
            [again.id, again.result, again.seq],
            [rec.row.id, result, first.seq],
            `${result}, re-send ${i}: the stored refusal and its seq, not acked`,
          );
          assertEquals("check" in again, false, `${result}, re-send ${i}: no check is invented`);
        }
        const rows = await rowsUnder(rec.row.id);
        assertEquals(rows.length, 1, "one row, however often the id is re-sent");
        assertEquals(
          [rows[0].applied_at?.getTime(), rows[0].apply_note],
          [kept.applied_at.getTime(), result],
          "the applied mark and the note are the first ones",
        );
      }
      assertEquals(await statusOf(tn.t, tn.founder.user), "active", "nothing projected");
      assertEquals(await statusOf(tn.t, plainP.user), "active", "nothing projected");

      const [a] = await send(r, admin, [label.wire]);
      assertEquals(a.result, "acked");
      assertEquals((await rowsUnder(label.row.id))[0].apply_note, "label only");
      const [again] = await send(r, admin, [label.wire]);
      assertEquals([again.result, again.seq], ["acked", a.seq], "acked with the stored seq");
    } finally {
      await store.end();
    }
  },
);

test(
  "E-05g-33 (database half) POST /sync-meta/records over the real store, a new record under the id of another tenant's record (desk 90(b); ADR 2026-10-03 §7 (b)): 200, that row answers rejected:shape check id with no seq — exactly what another device's VISIBLE record under the id answers — never a 500; the batch's good record commits, the stored record is untouched, and /invites answers 400 bad_record check id for the same id",
  async () => {
    const tA = await tenant(), tB = await tenant();
    const a2P = await activeMember(tA);
    const r = rig();
    const a = await signer(r, tA.founder);
    const a2 = await signer(r, a2P);
    const b = await signer(r, tB.founder);
    const theirs = await signedRecord(b, tB.t, "designation", { label: "synthetic" });
    const seen = await signedRecord(a2, tA.t, "designation", { label: "synthetic" });
    const reuse = await signedRecord(a, tA.t, "designation", { label: "synthetic" }, {
      id: theirs.row.id,
    });
    const reuseSeen = await signedRecord(a, tA.t, "designation", { label: "synthetic" }, {
      id: seen.row.id,
    });
    const good = await signedRecord(a, tA.t, "designation", { label: "synthetic" });
    const invite = await signedRecord(a, tA.t, "invite", {
      roles: [{ book_id: tA.personal, role: "member" }],
      nonce: b64url.enc(await random(16)),
    }, { id: theirs.row.id });

    const store = await apiStore(url!);
    r.deps.store = store;
    try {
      assertEquals((await send(r, b, [theirs.wire]))[0].result, "acked", "precondition: B's");
      assertEquals((await send(r, a2, [seen.wire]))[0].result, "acked", "precondition: a2's");
      const before = await rowsUnder(theirs.row.id);
      assertEquals(before.length, 1);

      const [hidden, visible, ok] = await send(r, a, [reuse.wire, reuseSeen.wire, good.wire]);
      assertEquals(hidden, { id: theirs.row.id, result: "rejected:shape", check: "id" });
      assertEquals(visible, { id: seen.row.id, result: "rejected:shape", check: "id" });
      assertEquals([ok.id, ok.result], [good.row.id, "acked"], "the batch's other record stands");
      const [kept] = await rowsUnder(good.row.id);
      assert(kept && kept.applied_at !== null, "and is committed, applied");

      const after = await rowsUnder(theirs.row.id);
      assertEquals(after.length, 1, "nothing stored under the id for the caller");
      assertEquals(
        [after[0].tenant_id, after[0].author_device, after[0].seq, after[0].apply_note],
        [tB.t, tB.founder.dev, before[0].seq, before[0].apply_note],
        "B's record is untouched",
      );

      const res = await meta(
        post("/sync-meta/invites", { record: invite.wire, phone: "+919876500013" }, {
          token: a.token,
        }),
        r.deps,
      );
      assertEquals(res.status, 400, "/invites shares the intake: a named refusal, never a 500");
      assertEquals(await body(res), { error: "bad_record", check: "id" });
      assertEquals((await rowsUnder(theirs.row.id)).length, 1, "still B's row alone");
      const [inv] = await sql`select count(*)::int as n from invites
        where source_record_id = ${theirs.row.id}`;
      assertEquals(inv.n, 0, "no invite issued under the id");
    } finally {
      await store.end();
    }
  },
);

/** Until a backend other than this one waits on a lock inside `insert into signed_records` — the
 *  caller's INSERT, meeting the key a sibling transaction holds uncommitted. */
async function insertWaitsOnKey(): Promise<void> {
  for (let i = 0; i < 250; i++) {
    const [w] = await sql`select count(*)::int as n from pg_stat_activity
      where pid <> pg_backend_pid() and wait_event_type = 'Lock'
        and query ilike 'insert into signed_records%'`;
    if (w.n > 0) return;
    await new Promise((res) => setTimeout(res, 20));
  }
  throw new Error("the caller's INSERT never waited on the sibling's uncommitted key");
}

test(
  "E-05g-34 (database half) POST /sync-meta/records over the real store, an id a sibling transaction is inserting at that moment (desk 90(b) repair, READ COMMITTED; ADR 2026-10-03 §7 (b)): the caller's INSERT waits on the key and meets 23505 when the sibling commits; if the committed record is the caller's OWN device's, the answer is the stored record's — acked with its seq — never rejected:shape check id; if it is another device's record the caller can see, rejected:shape check id; one row under the id either way, the sibling's row untouched, and the batch's other record stands",
  async () => {
    const tn = await tenant();
    const otherP = await activeMember(tn);
    const r = rig();
    const me = await signer(r, tn.founder);
    const other = await signer(r, otherP);

    const store = await apiStore(url!);
    r.deps.store = store;
    try {
      for (
        const [name, author, want] of [
          ["the caller's own device", me, "acked"],
          ["another device of the tenant", other, "rejected:shape"],
        ] as const
      ) {
        // The sibling's record, and what the caller sends under the same id: the same record when
        // the sibling is the caller's own device (a retry racing the first request), the caller's
        // own record when the id is another device's.
        const theirs = await signedRecord(author, tn.t, "designation", { label: "synthetic" });
        const sent = author === me ? theirs : await signedRecord(me, tn.t, "designation", {
          label: "synthetic",
        }, { id: theirs.row.id });
        const good = await signedRecord(me, tn.t, "designation", { label: "synthetic" });

        // The sibling inserts and applies the record (as a /records request of its author does)
        // and holds its transaction open until the caller's INSERT is waiting on the key.
        let release!: () => void;
        const held = new Promise<void>((res) => (release = res));
        let inserted!: () => void;
        const ready = new Promise<void>((res) => (inserted = res));
        const row = theirs.row;
        const sibling = sql.begin(async (tx) => {
          await tx`insert into signed_records
            (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device,
             author_sig, hlc, applied_at, apply_note)
            values (${row.id}, ${row.suite_version}, ${row.tenant_id}, ${row.kind}, ${
            tx.json(row.payload_json as postgres.JSONValue)
          }, ${row.payload_bytes}, ${row.author_device}, ${row.author_sig},
                    ${row.hlc.toString()}::bigint, now(), 'label only')`;
          inserted();
          await held;
        });
        await ready;
        const answer = send(r, me, [sent.wire, good.wire]);
        let notWaiting: unknown = null;
        try {
          await insertWaitsOnKey();
        } catch (e) {
          notWaiting = e;
        }
        release();
        await sibling;
        const [a, ok] = await answer;
        if (notWaiting) throw notWaiting;

        const rows = await rowsUnder(row.id);
        assertEquals(rows.length, 1, `${name}: one row under the id`);
        assertEquals(
          [rows[0].author_device, rows[0].apply_note],
          [author.device.id, "label only"],
          `${name}: the sibling's row, untouched`,
        );
        assertEquals(
          a,
          want === "acked"
            ? { id: row.id, result: "acked", seq: String(rows[0].seq) }
            : { id: row.id, result: "rejected:shape", check: "id" },
          want === "acked"
            ? `${name}: answered from the stored record, never as another device's id`
            : `${name}: another device's id, as §7 (b) answers it`,
        );
        assertEquals([ok.id, ok.result], [good.row.id, "acked"], `${name}: the batch goes on`);
      }
    } finally {
      await store.end();
    }
  },
);
