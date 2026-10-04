// ADR 2026-10-04b §1 🔒 (desk 107) on the REAL database: the first device mints `user_id`, and
// signup RECORDS it or refuses. The MemStore half — the route's rules on every purpose — is
// functions/_tests/auth_challenge.test.ts (E-04b-1 … E-04b-4). This file proves what the fake
// cannot: that what stops one person signing up under another's id is Postgres (the primary key on
// `users.id`, through 0030's rf.signup_user), and that the 409 leaves a transaction the edge can
// still COMMIT with the OTP challenge unconsumed — postgres.js poisons a transaction whose refused
// query was issued on its own scope (desk 70, guarded_savepoint.test.ts), which would turn the 409
// into a 500 and roll the client's one retry (ADR §2, C-04b-3) into a dead end.
//
// What an attacker — or a confused client — wants here, and what each test denies:
//   * ANOTHER PERSON'S ID: signing up under a user id someone else holds, live or erased (E-04b-3).
//   * A SECOND DOOR: rf_api inserting a users row itself, or PUBLIC / rf_maintenance calling the new
//     overload (E-04b-1).
//   * A MISNAMED REFUSAL: a phone collision reported as `user_id_taken`, which would send an honest
//     client into a re-mint loop it cannot win (E-04b-3).
//   * A SILENT MINT: a null id quietly given a server-minted one by the overload (E-04b-1).
//   * A SPENT CODE: the 409 consuming the challenge or bumping its attempts (E-04b-3, edge arm).
//
// Fixtures are written by the schema owner; the arms under test run as rf_api (`set local role` for
// the function-level arms, _pg_api.ts's apiStore for the edge arm, which asserts current_user =
// rf_api on the store's own pool). Phones are random synthetic numbers; phone bytes are random; no
// ledger content exists here (CLAUDE.md rule 4). Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`);
// without it every test is SKIPPED and says why, and RLS_REQUIRE=1 makes that a failure.
//   * AN OLD CLIENT LOCKED OUT: a verify that carries no user_id failing on the real store, e.g. by
//     being routed to the overload that refuses a null id (E-04b-4, edge arm).
//   * A SELF-INFLICTED 409: two verifies for one phone in flight together, both deciding "no
//     account" and both signing up, so the loser is told its OWN phone's id is taken — or, with no
//     id, gets a 500 (E-04b-3 / E-04b-4, concurrent arm; review finding on desk 107).
// Ids: the database halves of E-04b-1, E-04b-2, E-04b-3 and E-04b-4.
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import postgres from "postgres";
import { entry } from "../../functions/_shared/deps.ts";
import { phoneHmac } from "../../functions/_shared/phone.ts";
import { handler as auth } from "../../functions/auth-challenge/index.ts";
import { advance, body, req, type Rig, rig } from "../../functions/_tests/harness.ts";
import type { Store, Tx } from "../../functions/_shared/store.ts";
import { apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — client_minted_user_id.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP client_minted_user_id.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));
const SIG4 = "rf.signup_user(bytea, bytea, text, uuid)";
const SIG3 = "rf.signup_user(bytea, bytea, text)";

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

/** One transaction as rf_api with no claims — the pre-JWT path /otp/verify runs on. */
async function asApi<T>(fn: (s: postgres.TransactionSql) => Promise<T>): Promise<T> {
  return await sql.begin(async (s) => {
    await s`set local role rf_api`;
    await s`select rf.set_claims(null::uuid, null::uuid)`;
    return await fn(s);
  }) as T;
}
async function pgErr(p: Promise<unknown>): Promise<{ code: string; message: string }> {
  try {
    await p;
    return { code: "ok", message: "" };
  } catch (e) {
    const x = e as { code?: string; message?: string };
    return { code: x.code ?? "unknown", message: x.message ?? "" };
  }
}
/** A user the schema owner wrote, as signup would have: random phone bytes, no profile. */
async function holder(): Promise<{ id: string; hmac: Uint8Array }> {
  const hmac = rand(32);
  const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${hmac}, ${rand(40)})
    returning id`;
  return { id: u.id as string, hmac };
}
const userRow = async (id: string) =>
  (await sql`select id, phone_hmac, phone_ct, language, erased_at from users where id = ${id}`)[
    0
  ] ??
    null;
const byHmac = async (h: Uint8Array) =>
  (await sql`select id from users where phone_hmac = ${h}`).map((r) => r.id as string);
const signup4 = (s: postgres.TransactionSql, h: Uint8Array, id: string | null, lang = "en") =>
  s`select rf.signup_user(${h}, ${rand(40)}, ${lang}, ${id}::uuid) as id`;

// ---------------------------------------------------------------- E-04b-1 (database half)
test(
  "E-04b-1 (database half) 0030's shape and its one door: rf.signup_user(bytea, bytea, text, uuid) is SECURITY DEFINER with search_path pinned, EXECUTE-able by rf_api alone (not PUBLIC, not rf_maintenance); rf_api holds no INSERT on users; called by rf_api it records the given id EXACTLY — phone only as HMAC + ciphertext — and a null id is refused, never minted; the 3-argument function and users.id's default stay, so a client that sends no id still signs up",
  async () => {
    const [fn] = await sql`select p.prosecdef, p.proconfig, p.proretset,
        format_type(p.prorettype, null) as ret,
        has_function_privilege('rf_api', p.oid, 'execute') as api,
        has_function_privilege('public', p.oid, 'execute') as pub,
        has_function_privilege('rf_maintenance', p.oid, 'execute') as maint
      from pg_proc p where p.oid = ${SIG4}::regprocedure`;
    assertEquals(fn.prosecdef, true, "SECURITY DEFINER: rf_api has no INSERT on users");
    assertEquals(fn.proconfig, ["search_path=public, pg_temp"], "path pinned (E-03-84)");
    assertEquals([fn.ret, fn.proretset], ["uuid", false]);
    assertEquals(fn.api, true, "rf_api may EXECUTE it");
    assertEquals(fn.pub, false, "PUBLIC may not — a new function is PUBLIC's by default");
    assertEquals(fn.maint, false, "nor rf_maintenance: retention signs nobody up");
    const [g] = await sql`select
        has_table_privilege('rf_api', 'public.users', 'insert') as ins,
        has_table_privilege('rf_api', 'public.users', 'delete') as del,
        has_column_privilege('rf_api', 'public.users', 'id', 'update') as upd_id,
        has_function_privilege('rf_api', ${SIG3}::regprocedure, 'execute') as old_api,
        has_table_privilege('rf_api', 'public.envelopes', 'update') as env_upd,
        has_table_privilege('rf_api', 'public.envelopes', 'delete') as env_del`;
    assertEquals(
      [g.ins, g.del, g.upd_id],
      [false, false, false],
      "the definer function is the only way a users row is born, and an id never moves",
    );
    assertEquals(g.old_api, true, "the 3-argument function stays for clients that send no id");
    assertEquals([g.env_upd, g.env_del], [false, false], "CLAUDE.md rule 2 still holds");
    const [d] = await sql`select column_default from information_schema.columns
      where table_schema = 'public' and table_name = 'users' and column_name = 'id'`;
    assertEquals(d.column_default, "gen_random_uuid()", "users.id keeps its default (ADR 04b)");

    const mine = crypto.randomUUID();
    const h = rand(32);
    const got = await asApi(async (s) => (await signup4(s, h, mine, "pa"))[0].id as string);
    assertEquals(got, mine, "the id returned is the id proposed");
    const row = await userRow(mine);
    assert(row, "the row exists under the proposed id");
    assertEquals(new Uint8Array(row.phone_hmac), h);
    assertEquals((row.phone_ct as Uint8Array).length, 40, "the ciphertext as given");
    assertEquals(row.language, "pa");
    assertEquals(await byHmac(h), [mine], "one row for the phone — no server-minted twin");

    const h2 = rand(32);
    const nul = await pgErr(asApi((s) => signup4(s, h2, null)));
    assertNotEquals(nul.code, "ok", "a null id is refused by the overload");
    assertEquals(await byHmac(h2), [], "and no row is minted for it");

    const h3 = rand(32);
    const old = await asApi(async (s) =>
      (await s`select rf.signup_user(${h3}, ${rand(40)}, ${null}) as id`)[0].id as string
    );
    assert(/^[0-9a-f-]{36}$/.test(old), "the 3-argument function still mints for an old client");
    assertEquals(await byHmac(h3), [old]);
  },
);

// ---------------------------------------------------------------- E-04b-3 (database half)
test(
  "E-04b-3 (database half) rf.signup_user refuses an id ANY users row holds — a live user's or an erased one's — with the named reason `user_id_taken` (P0001, which denialFromPg passes through by name) and writes nothing; a PHONE collision under a fresh id is not misnamed user_id_taken — it stays the unique violation it is",
  async () => {
    const live = await holder();
    const h = rand(32);
    const taken = await pgErr(asApi((s) => signup4(s, h, live.id)));
    assertEquals(taken, { code: "P0001", message: "user_id_taken" });
    assertEquals(await byHmac(h), [], "no row for the claimant's phone");
    const kept = await userRow(live.id);
    assertEquals(new Uint8Array(kept.phone_hmac), live.hmac, "the holder's row is untouched");

    const [e] = await sql`insert into users (phone_hmac, phone_ct, erased_at)
      values (null, null, now()) returning id`;
    const erased = await pgErr(asApi((s) => signup4(s, h, e.id as string)));
    assertEquals(erased, { code: "P0001", message: "user_id_taken" }, "an id is never reused");
    assertEquals((await userRow(e.id as string)).phone_hmac, null, "the erased row gains no phone");
    assertEquals(await byHmac(h), []);

    const dup = await pgErr(asApi((s) => signup4(s, live.hmac, crypto.randomUUID())));
    assertEquals(dup.code, "23505", "a phone already registered is the unique violation it was");
    assertNotEquals(dup.message, "user_id_taken", "never named as an id collision");
    assertEquals(await byHmac(live.hmac), [live.id]);
  },
);

// ---------------------------------------------------------------- the edge arm
/** POST /auth-challenge<path> from one synthetic client address. */
const call = (edge: (r: Request) => Promise<Response>, path: string, b: unknown, ip: string) =>
  edge(req(`/auth-challenge${path}`, {
    method: "POST",
    body: JSON.stringify(b),
    headers: { "x-forwarded-for": ip },
  }));
/** A random synthetic Indian mobile number: +91 9xxxxxxxxx. */
const phone = () => `+919${Array.from(rand(9), (x) => String(x % 10)).join("")}`;

test(
  "E-04b-3 / E-04b-1 / E-04b-2 (database halves) POST /auth-challenge/otp/verify over the real store, through the edge wrapper: a proposal another user holds answers 409 user_id_taken — never 500 internal — with no users row, no ticket and the challenge in Postgres UNCONSUMED with attempts 0; the retry with a freshly minted id and the SAME code answers 200 and records that id; and a later verify for the same phone with yet another proposal answers the account's id and creates nothing",
  async () => {
    const taken = await holder();
    const r: Rig = rig();
    const store = await apiStore(url!);
    r.deps.store = store;
    const edge = entry(auth, () => r.deps);
    const p = phone();
    const ip = `198.51.100.${1 + (rand(1)[0] % 250)}`; // TEST-NET-2: no real address
    const h = await phoneHmac(r.deps.phoneHmacKey, p);
    const challenge = async () =>
      (await sql`select consumed_at, attempts from otp_challenges where phone_hmac = ${h}
        order by created_at desc limit 1`)[0];
    try {
      assertEquals(
        (await call(edge, "/otp/request", { phone: p, purpose: "signup" }, ip)).status,
        200,
      );
      const code = r.otp.sent.at(-1)!.code;

      const res = await call(edge, "/otp/verify", {
        phone: p,
        purpose: "signup",
        code,
        user_id: taken.id,
      }, ip);
      assertEquals(res.status, 409, "a named refusal, not a 500");
      assertEquals(await body(res), { error: "user_id_taken" });
      assertEquals(await byHmac(h), [], "no users row for the phone");
      const c = await challenge();
      assertEquals(
        c.consumed_at,
        null,
        "the challenge is NOT consumed — the transaction committed clean",
      );
      assertEquals(c.attempts, 0, "and no attempt was spent");
      assertEquals(
        (await sql`select count(*)::int as n from activation_tickets where phone_hmac = ${h}`)[0].n,
        0,
        "no ticket",
      );

      const fresh = crypto.randomUUID();
      const again = await call(edge, "/otp/verify", {
        phone: p,
        purpose: "signup",
        code,
        user_id: fresh,
      }, ip);
      assertEquals(again.status, 200, "the one retry, same code, succeeds");
      assertEquals((await body(again)).user_id, fresh, "under the freshly minted id");
      assertEquals(await byHmac(h), [fresh], "the row is the client's id");
      assert((await challenge()).consumed_at, "now the code is spent");
      const [t] = await sql`select user_id from activation_tickets where phone_hmac = ${h}`;
      assertEquals(t.user_id, fresh, "the ticket names it");

      // E-04b-2: the phone has an account now; another proposal changes nothing.
      advance(r, 61 * 60_000);
      assertEquals(
        (await call(edge, "/otp/request", { phone: p, purpose: "device_activation" }, ip)).status,
        200,
      );
      const later = await call(edge, "/otp/verify", {
        phone: p,
        purpose: "device_activation",
        code: r.otp.sent.at(-1)!.code,
        user_id: crypto.randomUUID(),
      }, ip);
      assertEquals(later.status, 200);
      assertEquals((await body(later)).user_id, fresh, "the account's id, not the proposal");
      assertEquals(await byHmac(h), [fresh], "no second row");
      assertEquals((await userRow(taken.id)).id, taken.id, "the holder is untouched throughout");
    } finally {
      await store.end();
      await sql`delete from otp_challenges where phone_hmac = ${h}`;
    }
  },
);

// ---------------------------------------------------------------- E-04b-4 (database half)
test(
  "E-04b-4 (database half) an OLDER CLIENT — POST /auth-challenge/otp/verify with no user_id key at all — signs up over the real store as rf_api exactly as before ADR 2026-10-04b: 200, one users row under a SERVER-minted id that the answer and the ticket name, the challenge spent; PgStore's no-proposal branch reaches 0005's 3-argument function, never 0030's overload (which refuses a null id, so a misrouting would answer 500 here)",
  async () => {
    const r: Rig = rig();
    const store = await apiStore(url!);
    r.deps.store = store;
    const edge = entry(auth, () => r.deps);
    const p = phone();
    const ip = `198.51.100.${1 + (rand(1)[0] % 250)}`; // TEST-NET-2: no real address
    const h = await phoneHmac(r.deps.phoneHmacKey, p);
    try {
      assertEquals(
        (await call(edge, "/otp/request", { phone: p, purpose: "signup" }, ip)).status,
        200,
      );
      const res = await call(edge, "/otp/verify", {
        phone: p,
        purpose: "signup",
        code: r.otp.sent.at(-1)!.code,
      }, ip);
      assertEquals(res.status, 200, "an old client still signs up — not a 500");
      const out = await body(res);
      assert(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(out.user_id),
        "the server minted a uuid",
      );
      assertEquals(await byHmac(h), [out.user_id], "one row for the phone, under the minted id");
      const [t] = await sql`select user_id from activation_tickets where phone_hmac = ${h}`;
      assertEquals(t?.user_id, out.user_id, "the ticket names it");
      const [c] = await sql`select consumed_at, attempts from otp_challenges where phone_hmac = ${h}
        order by created_at desc limit 1`;
      assert(c.consumed_at, "the code is spent");
    } finally {
      await store.end();
      await sql`delete from otp_challenges where phone_hmac = ${h}`;
    }
  },
);

// ---------------------------------------------------------------- concurrent verifies
/** A meeting point for `n` callers that gives up after `ms`: each caller waits until all `n` have
 *  arrived or its own wait runs out, so a caller the database is holding back cannot hang the rest. */
function rendezvous(n: number, ms: number): () => Promise<void> {
  let arrived = 0;
  const waiting: Array<() => void> = [];
  return () =>
    new Promise<void>((resolve) => {
      arrived++;
      if (arrived >= n) {
        for (const w of waiting.splice(0)) w();
        resolve();
        return;
      }
      // `done` runs only after it is queued below, by which time `timer` is set.
      const done = () => {
        clearTimeout(timer);
        resolve();
      };
      const timer = setTimeout(() => {
        waiting.splice(waiting.indexOf(done), 1);
        resolve();
      }, ms);
      waiting.push(done);
    });
}
/** `store` with every transaction's account lookup held at `meet()` — so two verifies that are in
 *  flight together are made to overlap exactly where resolve-before-consume can race: both past
 *  the code check, neither yet signed up. Everything else is the real PgStore, unchanged. */
function overlapAtAccountLookup(store: Store, meet: () => Promise<void>): Store {
  const hold = (tx: Tx): Tx =>
    new Proxy(tx, {
      get(target, key) {
        const v = Reflect.get(target, key, target);
        if (typeof v !== "function") return v;
        if (key === "findUserByPhoneHmac") {
          return async (...a: unknown[]) => {
            await meet();
            return await v.apply(target, a);
          };
        }
        return v.bind(target);
      },
    });
  return { withClaims: (claims, fn) => store.withClaims(claims, (tx) => fn(hold(tx))) };
}

for (const withId of [true, false]) {
  const what = withId ? "both carrying the same proposed user_id" : "both carrying no user_id";
  test(
    `E-04b-3 / E-04b-4 (database halves, concurrent) two POST /otp/verify for ONE phone in flight together, ${what}, over the real store as rf_api and made to meet at the account lookup: the verifies are serialised per phone, so exactly one answers 200 and creates the account${
      withId ? " under the proposal" : ""
    }, and the other reads what it committed — the code spent — and answers 400 otp_invalid; never 409 user_id_taken for the phone's own id (ADR 2026-10-04b §2: a 409 happens only by collision or someone else's id), never 500; one users row, one ticket`,
    async () => {
      const r: Rig = rig();
      const store = await apiStore(url!);
      // 400 ms: long enough that, unserialised, both verifies are past the code check before either
      // signs up; the serialised second never arrives, and the first goes on after the wait.
      r.deps.store = overlapAtAccountLookup(store, rendezvous(2, 400));
      const edge = entry(auth, () => r.deps);
      const p = phone();
      const ip = `198.51.100.${1 + (rand(1)[0] % 250)}`; // TEST-NET-2: no real address
      const h = await phoneHmac(r.deps.phoneHmacKey, p);
      try {
        assertEquals(
          (await call(edge, "/otp/request", { phone: p, purpose: "signup" }, ip)).status,
          200,
        );
        const mine = crypto.randomUUID();
        const verify = {
          phone: p,
          purpose: "signup",
          code: r.otp.sent.at(-1)!.code,
          ...(withId ? { user_id: mine } : {}),
        };
        const answers = await Promise.all([
          call(edge, "/otp/verify", verify, ip),
          call(edge, "/otp/verify", verify, ip),
        ]);
        const got = await Promise.all(
          answers.map(async (a) => ({ status: a.status, body: await body(a) })),
        );
        got.sort((a, b) => a.status - b.status);
        assertEquals(
          got.map((g) => g.status),
          [200, 400],
          `one sign-up, one spent code — not ${JSON.stringify(got.map((g) => g.body))}`,
        );
        assertEquals(got[1].body, { error: "otp_invalid" }, "the loser is told the code is spent");
        const id = got[0].body.user_id as string;
        if (withId) assertEquals(id, mine, "the account is the proposal");
        assertEquals(await byHmac(h), [id], "ONE users row for the phone");
        const tickets = await sql`select user_id from activation_tickets where phone_hmac = ${h}`;
        assertEquals(tickets.map((t) => t.user_id), [id], "ONE ticket, naming it");
      } finally {
        await store.end();
        await sql`delete from otp_challenges where phone_hmac = ${h}`;
      }
    },
  );
}
