// PgTx.guarded() on the REAL store (desk 70, M13-CAPR open[0]). Every guarded write runs inside a
// savepoint so that a refused write — a row policy, a cap trigger, a named guard — is answered by
// name for THAT row and leaves the rest of the request standing. postgres.js 3.4.5 gives every scope
// (the `begin` and each savepoint) its own `sql`, records a failed query on the scope that ISSUED it
// (src/index.js:290-291) and re-throws that error when the scope's function resolves (:264-265). A
// savepoint whose queries are issued on the OUTER `sql` therefore rolls back to the savepoint and
// then poisons the whole transaction anyway: the caught StoreDenied becomes a thrown one at commit,
// the request rolls back and the caller sees a 500. MemStore has no scopes, which is why the
// functions/_tests suite never saw it; only a real Postgres can.
//
// What this file denies:
//   * A POISONED BATCH — one refused envelope in a sync-push batch rolling back the two good ones,
//     so sync_engine re-sends all three into the same 500 forever (E-05g-17).
//   * A LOST REFUSAL — a cap-refused /records record taking the batch down with it (E-05g-18), or
//     the /invites 409 dropping the signed record it promised to keep (E-05g-20): a refused row is
//     never dropped silently (ADR 2026-09-05b §7).
//   * A LEAKY NEST — a refusal at an inner guarded() level unwinding more than its own savepoint, or
//     the transaction's own scope not being restored afterwards (E-05g-19).
//   * A LOST 409 — POST /auth-challenge/devices answering 500 internal where ADR 2026-09-16 §6 🔒
//     says 409 device_cap / 409 device_id_taken, with the activation ticket rolled back instead of
//     consumed, because rf.register_device's refusal was issued on the transaction's own scope while
//     the handler caught it inside withClaims (E-06-3 and E-06-41, database half; the MemStore half
//     is functions/_tests/auth_challenge.test.ts, which has no scopes to poison).
//
// The store runs as rf_api (`options=-c role=rf_api` on the test connection), as the edge does under
// ADR 2026-09-05c §7, so 0005's row policies apply — the superuser URL the other files hand PgStore
// would bypass them. Fixtures are written by the schema owner without claims. Blobs are random bytes;
// no ledger content exists here. Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`); without it
// every test is SKIPPED and says why, and RLS_REQUIRE=1 makes that a failure.
// Ids E-05g-17, E-05g-18, E-05g-19, E-05g-20, and the database half of E-06-3 and E-06-41.
import { assert, assertEquals, assertNotEquals, assertRejects } from "@std/assert";
import postgres from "postgres";
import { b64url } from "../../functions/_shared/bytes.ts";
import { entry } from "../../functions/_shared/deps.ts";
import { blake2b256 } from "../../functions/_shared/sodium.ts";
import {
  type EnvelopeRow,
  type Store,
  StoreDenied,
  type Tx,
} from "../../functions/_shared/store.ts";
import { PgStore } from "../../functions/_shared/store_pg.ts";
import { handler as auth } from "../../functions/auth-challenge/index.ts";
import { handler as meta } from "../../functions/sync-meta/index.ts";
import { handler as push } from "../../functions/sync-push/index.ts";
import {
  body,
  edKeypair,
  hlcAt,
  type KeyPair,
  type Member,
  post,
  reissue,
  type Rig,
  rig,
  signedRecord,
  T0,
  wireEnvelope,
} from "../../functions/_tests/harness.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — guarded_savepoint.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP guarded_savepoint.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

/** The connection the edge holds: rf_api, never the owner. */
const apiUrl = () =>
  `${url}${url!.includes("?") ? "&" : "?"}options=${encodeURIComponent("-c role=rf_api")}`;

// A two-seat plan for the cap arms (E-05g-18, -20); removed after every test that made it.
const TWO = "zz_gs_two";

function test(name: string, fn: () => Promise<void>) {
  Deno.test({
    name,
    ignore,
    async fn() {
      sql = postgres(url!, { max: 4, onnotice: () => {} });
      try {
        // rls_db.sh applies the migrations, not seed.sql: seed.sql's store_epoch line, as a fixture.
        await sql`insert into store_epoch (id, epoch) values (true, gen_random_uuid())
          on conflict (id) do nothing`;
        await sql`insert into plan_catalogue (id, entity_type, name, sort_order, members,
            business_books, devices, envelopes_per_book, tenant_bytes, attachment_bytes, features,
            price_yearly_paise, price_monthly_paise)
          values (${TWO}, 'family', 'Guarded two', 94, 2, 2, 5, 1000, 1000000, 1000, '{}', 0, 0)
          on conflict (id) do nothing`;
        await fn();
      } finally {
        await sql`update subscriptions set plan = 'free' where plan = ${TWO}`;
        await sql`delete from plan_catalogue where id = ${TWO}`;
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
/** A family tenant (on `plan`, or the Free floor when null) whose founder is active and admin of
 *  the founder's personal book. */
async function tenant(plan: string | null): Promise<Tn> {
  const [row] = await sql`insert into tenants (type) values ('family') returning id`;
  const t = row.id as string;
  if (plan) await sql`insert into subscriptions (tenant_id, plan) values (${t}, ${plan})`;
  const founder = await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t}, ${founder.user}, 'active')`;
  const personal = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type, owner_user_id)
    values (${personal}, ${t}, 'personal', ${founder.user})`;
  await sql`insert into book_roles (book_id, user_id, role)
    values (${personal}, ${founder.user}, 'admin')`;
  return { t, founder, personal };
}
async function businessBook(tn: Tn, role = "admin"): Promise<string> {
  const id = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type) values (${id}, ${tn.t}, 'business')`;
  await sql`insert into book_roles (book_id, user_id, role) values (${id}, ${tn.founder.user}, ${role})`;
  return id;
}
/** An ACTIVE member placed by the owner after a signed ceremony (0006/0008's guards). */
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
async function envRow(
  tn: Tn,
  book: string,
  over: Partial<EnvelopeRow> = {},
): Promise<EnvelopeRow> {
  const blob = rand(48);
  return {
    envelope_id: crypto.randomUUID(),
    tenant_id: tn.t,
    book_id: book,
    object_id: crypto.randomUUID(),
    object_type: "entry",
    key_version: 1,
    suite_version: 1,
    payload_schema: 1,
    author_device: tn.founder.dev,
    hlc: hlcAt(T0.getTime()),
    blob_hash: await blake2b256(blob),
    size: blob.length,
    blob,
    blob_ref: null,
    ...over,
  };
}

/** An activation ticket for `user`, as /otp/verify leaves it (the OTP leg is E-06-1/-2's). */
async function ticketFor(user: string): Promise<{ wire: string; hash: Uint8Array }> {
  const raw = rand(32);
  const hash = await blake2b256(raw);
  await sql`insert into activation_tickets
      (ticket_hash, phone_hmac, purpose, user_id, created_at, expires_at)
    values (${hash}, ${rand(32)}, 'signup', ${user}, ${T0}, ${new Date(T0.getTime() + 600_000)})`;
  return { wire: b64url.enc(raw), hash };
}

// ---------------------------------------------------------------- fresh reads (owner, new transaction)
async function ticketConsumed(hash: Uint8Array): Promise<boolean> {
  const [r] = await sql`select consumed_at from activation_tickets where ticket_hash = ${hash}`;
  assert(r, "the ticket row exists");
  return r.consumed_at !== null;
}
async function devicesOf(user: string): Promise<string[]> {
  const rows = await sql`select id from devices where user_id = ${user} order by id`;
  return rows.map((x) => x.id as string);
}
async function committedEnvelopes(ids: string[]): Promise<Map<string, number>> {
  const rows = await sql`select envelope_id, seq from envelopes where envelope_id in ${sql(ids)}`;
  return new Map(rows.map((r) => [r.envelope_id as string, Number(r.seq)]));
}
async function storedRecord(id: string) {
  const [r] = await sql`select seq, applied_at, apply_note from signed_records where id = ${id}`;
  return r ?? null;
}
async function statusOf(t: string, user: string): Promise<string | null> {
  const [r] =
    await sql`select status from memberships where tenant_id = ${t} and user_id = ${user}`;
  return (r?.status as string) ?? null;
}

type Guarded = { guarded<T>(fn: () => Promise<T>): Promise<T> };
/** The postgres.js scope a PgTx issues its queries on (guarded() swaps it for a savepoint's). */
const scopeOf = (tx: Tx): unknown => (tx as unknown as { sql: unknown }).sql;

// ================================================================ the tests

test(
  "E-05g-17 sync-push over the real store: a batch of three envelopes whose middle one the envelopes_insert row policy refuses (the writer's role on that book removed while the batch is in flight) answers 200 acked / rejected:no_role / acked — never a 500 — and the two acked envelopes are COMMITTED: read back in a fresh transaction under the seqs the response gave, the refused one absent, and a re-send acks the two with the same seqs",
  async () => {
    const api = postgres(apiUrl(), { max: 1, onnotice: () => {} });
    try {
      const [who] = await api`select current_user as u`;
      assertEquals(
        who.u,
        "rf_api",
        "precondition: the store under test runs as rf_api, so RLS applies",
      );
    } finally {
      await api.end();
    }

    const tn = await tenant(null);
    const bookA = tn.personal;
    const bookB = await businessBook(tn);
    const r = rig();
    const w = await signer(r, tn.founder);
    const e1 = await wireEnvelope(w, tn.t, bookA);
    const e2 = await wireEnvelope(w, tn.t, bookB);
    const e3 = await wireEnvelope(w, tn.t, bookA);

    const real = new PgStore(apiUrl());
    // The real PgTx, with one side effect at the moment the middle envelope is written: the schema
    // owner, on its own connection, removes the writer's role on book B and commits. The handler
    // read book B's access before that (and caches it for the batch), so only the row policy — at
    // INSERT time, READ COMMITTED — can see it. Nothing about the row or the Tx is altered.
    let revoked = false;
    const store: Store = {
      withClaims: (claims, fn) =>
        real.withClaims(claims, (tx) =>
          fn(
            new Proxy(tx, {
              get(t, k) {
                const v = Reflect.get(t, k, t);
                if (k === "insertEnvelope") {
                  return async (row: EnvelopeRow) => {
                    if (row.envelope_id === e2.envelope_id && !revoked) {
                      revoked = true;
                      await sql`delete from book_roles
                        where book_id = ${bookB} and user_id = ${tn.founder.user}`;
                    }
                    return await (v as Tx["insertEnvelope"]).call(t, row);
                  };
                }
                return typeof v === "function" ? v.bind(t) : v;
              },
            }),
          )),
    };
    r.deps.store = store;
    try {
      const send = () =>
        push(post("/sync-push", { envelopes: [e1, e2, e3] }, { token: w.token }), r.deps);
      const res = await send();
      assertEquals(res.status, 200, "one refused row is that row's answer, not the batch's");
      const out = await body(res);
      assertEquals(
        out.results.map((x: { envelope_id: string; result: string }) => [x.envelope_id, x.result]),
        [
          [e1.envelope_id, "acked"],
          [e2.envelope_id, "rejected:no_role"],
          [e3.envelope_id, "acked"],
        ],
      );
      assert(revoked, "the middle envelope reached the store");
      const s1 = out.results[0].seq as number, s3 = out.results[2].seq as number;
      assert(s3 > s1, "seq is monotonic across the refusal");

      const kept = await committedEnvelopes([e1, e2, e3].map((e) => e.envelope_id as string));
      assertEquals(kept.get(e1.envelope_id as string), s1, "the first envelope is committed");
      assertEquals(kept.get(e3.envelope_id as string), s3, "the third envelope is committed");
      assertEquals(kept.has(e2.envelope_id as string), false, "the refused one left no row");

      const again = await body(await send());
      assertEquals(
        again.results.map((x: { result: string; seq?: number }) => [x.result, x.seq ?? null]),
        [["acked", s1], ["rejected:no_role", null], ["acked", s3]],
        "a re-send finds the two committed rows (idempotent by envelope_id) and refuses the third",
      );
    } finally {
      await real.end();
    }
  },
);

test(
  "E-05g-18 POST /sync-meta/records over the real store: a batch of membership_status (takes the plan's last seat) / membership_status (the seat cap refuses it) / verification_event answers 200 acked / rejected:seat_cap (check seat_cap) / acked — never a 500 — and in a fresh transaction all three records are stored, the refused one unapplied with no membership row, the other two applied: the first joiner is verified to active (E-05g-14's /records arm and desk 68(a) on the real store)",
  async () => {
    const tn = await tenant(TWO);
    const r = rig();
    const s = await signer(r, tn.founder);
    const a = await mkPerson(), b = await mkPerson();
    const r1 = await signedRecord(s, tn.t, "membership_status", {
      user_id: a.user,
      status: "joined_pending_verification",
    }, { hlc: hlcAt(T0.getTime(), 1) });
    const r2 = await signedRecord(s, tn.t, "membership_status", {
      user_id: b.user,
      status: "joined_pending_verification",
    }, { hlc: hlcAt(T0.getTime(), 2) });
    const r3 = await signedRecord(s, tn.t, "verification_event", {
      subject_user_id: a.user,
      verifier_user_id: tn.founder.user,
      method: "qr_in_person",
      result: "verified",
    }, { hlc: hlcAt(T0.getTime(), 3) });

    const store = new PgStore(apiUrl());
    r.deps.store = store;
    try {
      const res = await meta(
        post("/sync-meta/records", { records: [r1.wire, r2.wire, r3.wire] }, { token: s.token }),
        r.deps,
      );
      assertEquals(res.status, 200, "a cap refusal is that record's answer, not the batch's");
      const out = await body(res);
      assertEquals(
        out.results.map((x: { id: string; result: string; check?: string }) => [
          x.id,
          x.result,
          x.check ?? null,
        ]),
        [
          [r1.row.id, "acked", null],
          [r2.row.id, "rejected:seat_cap", "seat_cap"],
          [r3.row.id, "acked", null],
        ],
      );

      const [k1, k2, k3] = [
        await storedRecord(r1.row.id),
        await storedRecord(r2.row.id),
        await storedRecord(r3.row.id),
      ];
      assert(k1 && k2 && k3, "all three signed records are committed (the refused one is a fact)");
      assertNotEquals(k1.applied_at, null, "the first record is applied");
      assertEquals(k2.applied_at, null, "the refused record is stored but not applied");
      assertNotEquals(k3.applied_at, null, "the record after the refusal is applied");
      assertEquals(await statusOf(tn.t, a.user), "active", "verified after taking the last seat");
      assertEquals(await statusOf(tn.t, b.user), null, "the refused joiner has no membership row");
      const [v] = await sql`select count(*)::int as n from verification_events
        where source_record_id = ${r3.row.id}`;
      assertEquals(v.n, 1, "the verification after the refusal is committed");
    } finally {
      await store.end();
    }
  },
);

test(
  "E-05g-19 nested guarded() calls stack on the real store: an inner refusal (envelopes_insert row policy) caught inside an outer guarded() rolls back the inner savepoint only, and the writes around it in the outer one commit; an inner refusal let through rolls back the outer savepoint only and surfaces as the named StoreDenied; afterwards the transaction's own scope is back — the very scope withClaims opened, so a failure outside every guarded() still fails the transaction at commit instead of committing a transaction Postgres has aborted — and everything outside the rolled-back savepoints commits",
  async () => {
    const tn = await tenant(null);
    const other = await mkPerson(); // a real device that is not the caller's: the policy's author_device arm
    const store = new PgStore(apiUrl());
    const e1 = await envRow(tn, tn.personal);
    const bad1 = await envRow(tn, tn.personal, { author_device: other.dev });
    const e2 = await envRow(tn, tn.personal);
    const e3 = await envRow(tn, tn.personal);
    const bad2 = await envRow(tn, tn.personal, { author_device: other.dev });
    const e4 = await envRow(tn, tn.personal);
    try {
      const seen = await store.withClaims(
        { user_id: tn.founder.user, device_id: tn.founder.dev },
        async (tx) => {
          const g = tx as unknown as Guarded;
          const own = scopeOf(tx);
          const caught = await g.guarded(async () => {
            const a = await tx.insertEnvelope(e1);
            let denied = "";
            try {
              await tx.insertEnvelope(bad1);
            } catch (e) {
              assert(e instanceof StoreDenied, `a named denial, not ${e}`);
              denied = e.reason;
            }
            const b = await tx.insertEnvelope(e2);
            return { a: a.seq, b: b.seq, denied };
          });
          let through = "";
          try {
            await g.guarded(async () => {
              await tx.insertEnvelope(e3);
              await tx.insertEnvelope(bad2);
            });
          } catch (e) {
            assert(e instanceof StoreDenied, `the inner refusal surfaces by name, not ${e}`);
            through = e.reason;
          }
          // Outside every guarded(): this runs on the transaction's own scope again.
          const restoredAfterNest = scopeOf(tx) === own;
          const c = await tx.insertEnvelope(e4);
          const pulled = await tx.pullEnvelopes(tn.personal, 0n, 10, null);
          return {
            ...caught,
            through,
            restoredAfterNest,
            restoredAtEnd: scopeOf(tx) === own,
            c: c.seq,
            pulled: pulled.map((x) => x.envelope_id),
          };
        },
      );
      assertEquals(seen.denied, "rls", "the row policy refused the inner write by name");
      assertEquals(seen.through, "rls");
      assert(seen.restoredAfterNest, "after the nest, queries go to withClaims' own scope again");
      assert(seen.restoredAtEnd, "and still do after one more guarded write");
      assertEquals(
        seen.pulled,
        [e1.envelope_id, e2.envelope_id, e4.envelope_id],
        "inside the transaction: the caught refusal took only itself, the uncaught one only its savepoint",
      );
      const kept = await committedEnvelopes(
        [e1, bad1, e2, e3, bad2, e4].map((e) => e.envelope_id),
      );
      assertEquals(
        [...kept.keys()].sort(),
        [e1.envelope_id, e2.envelope_id, e4.envelope_id].sort(),
        "committed: e1, e2 (around the caught refusal) and e4 (after both); e3 went with its savepoint",
      );
      assertEquals(
        [kept.get(e1.envelope_id), kept.get(e2.envelope_id), kept.get(e4.envelope_id)],
        [Number(seen.a), Number(seen.b), Number(seen.c)],
      );

      // The restore, observed rather than inspected. A failed query OUTSIDE every guarded() has no
      // savepoint to roll back to: Postgres aborts the transaction, and postgres.js re-throws the
      // failure from the scope that issued it when that scope resolves (src/index.js:264-265) — even
      // if the caller caught it. Issued on a finished savepoint's scope instead (no restore), it would
      // be recorded where nothing re-checks it, `commit` on the aborted transaction would come back as
      // a silent rollback, and withClaims would RESOLVE with nothing stored.
      const e5 = await envRow(tn, tn.personal);
      let caughtInside = false;
      const err = await assertRejects(() =>
        store.withClaims({ user_id: tn.founder.user, device_id: tn.founder.dev }, async (tx) => {
          await tx.insertEnvelope(e5); // guarded: opens and leaves a savepoint
          try {
            await tx.bookAccess("not-a-uuid"); // unguarded, fails, caught by the caller
          } catch {
            caughtInside = true;
          }
        })
      );
      assert(caughtInside, "the caller caught the unguarded failure");
      assertEquals(
        (err as { code?: string }).code,
        "22P02",
        "the caught failure resurfaces from the transaction, by its own code",
      );
      assertEquals(
        (await committedEnvelopes([e5.envelope_id])).size,
        0,
        "and the transaction is rolled back as a whole, visibly — not reported committed",
      );
    } finally {
      await store.end();
    }
  },
);

test(
  "E-05g-20 POST /sync-meta/invites over the real store on a full plan: still 409 seat_cap by name, and the admin's signed invite record is COMMITTED with apply_note rejected:seat_cap — the refusal is kept, not rolled back with the request (E-05g-14's /invites arm on the real store; ADR 2026-09-05b §7)",
  async () => {
    const tn = await tenant(TWO);
    await activeMember(tn); // founder + one = the two seats
    const r = rig();
    const s = await signer(r, tn.founder);
    const rec = await signedRecord(s, tn.t, "invite", { roles: [], nonce: b64url.enc(rand(16)) });
    const store = new PgStore(apiUrl());
    r.deps.store = store;
    try {
      const res = await meta(
        post("/sync-meta/invites", { record: rec.wire, phone: "+919876500021" }, {
          token: s.token,
        }),
        r.deps,
      );
      assertEquals(res.status, 409);
      assertEquals((await body(res)).error, "seat_cap");
      const kept = await storedRecord(rec.row.id);
      assert(kept, "the signed record survives the refusal");
      assertNotEquals(kept.applied_at, null);
      assertEquals(kept.apply_note, "rejected:seat_cap");
      const [n] = await sql`select count(*)::int as n from invites where tenant_id = ${tn.t}`;
      assertEquals(n.n, 0, "and the refused invite left no row");
    } finally {
      await store.end();
    }
  },
);

// ---------------------------------------------------------------- POST /devices (ADR 2026-09-16 §6 🔒)
// Through `entry`, the wrapper every deployed function runs behind (deps.ts), so a throw out of the
// handler is seen as the edge answers it — 500 internal — rather than as a test exception.

test(
  "E-06-41 (database half) POST /auth-challenge/devices over the real store, through the edge wrapper: a device_id another user holds answers 409 device_id_taken — never 500 internal — the holder's row is untouched, the claimant gains no row, and the activation ticket IS consumed, so a second try answers 401 ticket_invalid (ADR 2026-09-16 §6 🔒: no row, ticket consumed)",
  async () => {
    const holder = await mkPerson();
    const claimant = await mkPerson();
    const before = await devicesOf(claimant.user);
    const t = await ticketFor(claimant.user);
    const r = rig();
    const store = new PgStore(apiUrl());
    r.deps.store = store;
    const edge = entry(auth, () => r.deps);
    const req = {
      device_id: holder.dev,
      ticket: t.wire,
      pub_ed: b64url.enc(rand(32)),
      pub_x: b64url.enc(rand(32)),
    };
    try {
      const res = await edge(post("/auth-challenge/devices", req));
      assertEquals(res.status, 409, "a named refusal, not a 500");
      // device_cap and device_id_taken share the status; the client branches on the string (§3).
      assertEquals((await body(res)).error, "device_id_taken");
      assertEquals(
        await devicesOf(holder.user),
        [holder.dev],
        "the id still belongs to its holder",
      );
      assertEquals(await devicesOf(claimant.user), before, "the claimant gained no row");
      assert(await ticketConsumed(t.hash), "the ticket is consumed: a refusal is not a free retry");
      const again = await edge(post("/auth-challenge/devices", req));
      assertEquals(again.status, 401);
      assertEquals((await body(again)).error, "ticket_invalid");
    } finally {
      await store.end();
    }
  },
);

test(
  "E-06-3 (database half) POST /auth-challenge/devices over the real store, through the edge wrapper: a user already at the Free device cap answers 409 device_cap — never 500 internal — no row is added, and the request's transaction commits (the ticket the handler consumed before the refusal stays consumed)",
  async () => {
    const p = await mkPerson(); // no active membership: rf.device_cap falls back to the Free plan
    const [free] = await sql`select devices from plan_catalogue where id = 'free'`;
    const cap = free.devices as number;
    assert(cap >= 1 && cap < 1000, `precondition: Free has a finite device cap (got ${cap})`);
    for (let i = 1; i < cap; i++) {
      await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
        values (gen_random_uuid(), ${p.user}, ${rand(32)}, ${rand(32)}, 'registered')`;
    }
    const full = await devicesOf(p.user);
    assertEquals(full.length, cap, "precondition: the user holds exactly the cap");
    const t = await ticketFor(p.user);
    const r = rig();
    const store = new PgStore(apiUrl());
    r.deps.store = store;
    const edge = entry(auth, () => r.deps);
    const id = crypto.randomUUID();
    try {
      const res = await edge(post("/auth-challenge/devices", {
        device_id: id,
        ticket: t.wire,
        pub_ed: b64url.enc(rand(32)),
        pub_x: b64url.enc(rand(32)),
      }));
      assertEquals(res.status, 409, "a named refusal, not a 500");
      assertEquals((await body(res)).error, "device_cap");
      assertEquals(await devicesOf(p.user), full, "no row is added past the cap");
      // Same transaction as E-06-41's arm: the handler answers 409 inside withClaims, so what it did
      // before the refusal commits. Rolled back (the defect), the ticket would read unconsumed.
      assert(await ticketConsumed(t.hash), "the request's transaction committed");
    } finally {
      await store.end();
    }
  },
);
