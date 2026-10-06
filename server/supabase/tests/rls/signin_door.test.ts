// ADR 2026-10-05c §2 🔒 (the sign-in door) on the REAL database. The route's rules on MemStore are
// functions/auth-challenge/signin_door.test.ts (E-1005c-1 … E-1005c-10). This file proves what the
// fake cannot: that over PgStore as rf_api a device_activation verify for a number with no account
// writes NO users row, that /signup/adopt signs up exactly once even when two adopts — or an adopt
// and the I'm-new path's verify — are in flight together, that adopt's 409 leaves a transaction the
// edge can still COMMIT with the ticket unspent, and that the table the sign-up tickets live in is
// closed to every role but the edge's.
//
// Where the tickets live. A sign-up ticket is an `activation_tickets` row that names no user —
// 0004 declared `user_id uuid null … -- null until signup creates the user` for exactly this — so
// no migration is needed: the row inherits 0004's 24 h purge (rf.purge_ephemeral_auth), 0005's RLS
// (FORCE, rf_api + rf_maintenance policies only, platform roles revoked) and 03 §2.4's listing of the
// table. The row holds the hash of the ticket's bytes and the phone's HMAC; the number itself is
// sealed inside the ticket the client holds (ADR 2026-09-05c §4 🔒: nothing recoverable is kept for
// a person who has not signed up — and activation_tickets has no column that could hold it).
//
// What an attacker — or a confused client — wants here, and what each test denies:
//   * A SIGN-UP NOBODY CHOSE through the real store (E-1005c-11).
//   * TWO ACCOUNTS FROM ONE TICKET, or one ticket and one verify, by racing them (E-1005c-12).
//   * A SPENT TICKET ON A 409, or a 409 that poisons the commit into a 500 (E-1005c-13).
//   * A ROW READ OR WRITTEN by a platform role — even one that a hosted default privilege handed a
//     grant — or by the maintenance role writing one (E-1005c-14).
// Fixtures: random synthetic numbers and bytes, TEST-NET addresses, no ledger content (rule 4).
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`); without it every test is SKIPPED and says
// why, and RLS_REQUIRE=1 makes that a failure.
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";
import { b64url } from "../../functions/_shared/bytes.ts";
import { entry } from "../../functions/_shared/deps.ts";
import { phoneHmac } from "../../functions/_shared/phone.ts";
import { blake2b256 } from "../../functions/_shared/sodium.ts";
import type { Store, Tx } from "../../functions/_shared/store.ts";
import { handler as auth } from "../../functions/auth-challenge/index.ts";
import { advance, body, req, type Rig, rig } from "../../functions/_tests/harness.ts";
import { apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — signin_door.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP signin_door.test.ts: ${why}`);
}
const ignore = !url;
const INVALID = { error: "signup_ticket_invalid" };

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
async function pgErr(p: Promise<unknown>): Promise<{ code: string; message: string }> {
  try {
    await p;
    return { code: "ok", message: "" };
  } catch (e) {
    const x = e as { code?: string; message?: string };
    return { code: x.code ?? "unknown", message: x.message ?? "" };
  }
}

/** POST /auth-challenge<path> from one synthetic client address. */
const call = (edge: (r: Request) => Promise<Response>, path: string, b: unknown, ip: string) =>
  edge(req(`/auth-challenge${path}`, {
    method: "POST",
    body: JSON.stringify(b),
    headers: { "x-forwarded-for": ip },
  }));
/** A random synthetic Indian mobile number: +91 9xxxxxxxxx. */
const phone = () => `+919${Array.from(rand(9), (x) => String(x % 10)).join("")}`;
const testNet = () => `198.51.100.${1 + (rand(1)[0] % 250)}`; // TEST-NET-2: no real address
const byHmac = async (h: Uint8Array) =>
  (await sql`select id from users where phone_hmac = ${h}`).map((r) => r.id as string);
const ticketRow = async (ticket: string) =>
  (await sql`select user_id, phone_hmac, consumed_at,
      extract(epoch from expires_at - created_at)::int as ttl_s
    from activation_tickets where ticket_hash = ${await blake2b256(b64url.dec(ticket))}`)[0];

/** The edge over the REAL store as rf_api, optionally with each transaction wrapped. */
async function world(wrap?: (s: Store) => Store) {
  const r: Rig = rig();
  const store = await apiStore(url!);
  r.deps.store = wrap ? wrap(store) : store;
  const edge = entry(auth, () => r.deps);
  const p = phone(), ip = testNet();
  const h = await phoneHmac(r.deps.phoneHmacKey, p);
  /** The sign-in door for `p`: a verified device_activation code, `account: none`. */
  const signupTicket = async (): Promise<string> => {
    advance(r, 61 * 60_000);
    const req1 = await call(edge, "/otp/request", { phone: p, purpose: "device_activation" }, ip);
    assertEquals(req1.status, 200, "precondition: a code was issued");
    const res = await call(edge, "/otp/verify", {
      phone: p,
      purpose: "device_activation",
      code: r.otp.sent.at(-1)!.code,
      user_id: crypto.randomUUID(),
    }, ip);
    assertEquals(res.status, 200, "precondition: the code verifies");
    const out = await body(res);
    assertEquals(out.account, "none");
    return out.signup_ticket as string;
  };
  const cleanup = async () => {
    await store.end();
    await sql`delete from otp_challenges where phone_hmac = ${h}`;
    await sql`delete from activation_tickets where phone_hmac = ${h}`;
  };
  return { r, edge, p, ip, h, signupTicket, cleanup };
}

type Fn = (...a: unknown[]) => unknown;
/** `store` with every transaction's Tx wrapped by `hook` (a Proxy: the real PgTx underneath). */
function hooked(store: Store, hook: (key: string, v: Fn, target: Tx) => Fn): Store {
  const wrap = (tx: Tx): Tx =>
    new Proxy(tx, {
      get(target, key) {
        const v = Reflect.get(target, key, target);
        if (typeof v !== "function") return v;
        return hook(String(key), v as Fn, target);
      },
    });
  return { withClaims: (claims, fn) => store.withClaims(claims, (tx) => fn(wrap(tx))) };
}
/** A meeting point for `n` callers that gives up after `ms` (a held-back caller cannot hang it). */
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

// ---------------------------------------------------------------- E-1005c-11
test(
  "E-1005c-11 (database half) over the real store as rf_api: a device_activation verify for a number with no account writes NO users row and one activation_tickets row that names no user — the ticket's hash and the phone's HMAC, ≤ 10 minutes, in a table with no column that could hold the number; /signup/adopt then signs up exactly one user under the client's id, spends that row and issues an activation ticket naming the user; a second adopt is signup_ticket_invalid",
  async () => {
    const w = await world();
    try {
      const ticket = await w.signupTicket();
      assertEquals(await byHmac(w.h), [], "nobody signed up");
      const row = await ticketRow(ticket);
      assert(row, "stored under the hash of the ticket's bytes");
      assertEquals(row.user_id, null, "names no user");
      assertEquals(new Uint8Array(row.phone_hmac), w.h, "bound to the phone's HMAC");
      assertEquals(row.consumed_at, null);
      assert(row.ttl_s > 0 && row.ttl_s <= 600, `≤ 10 min (${row.ttl_s} s)`);
      const cols = await sql`select column_name from information_schema.columns
        where table_schema = 'public' and table_name = 'activation_tickets'`;
      assertEquals(
        cols.map((c) => c.column_name as string).filter((c) => /phone/.test(c)),
        ["phone_hmac"],
        "no column holds the number or its ciphertext",
      );

      const mine = crypto.randomUUID();
      const res = await call(
        w.edge,
        "/signup/adopt",
        { signup_ticket: ticket, user_id: mine },
        w.ip,
      );
      assertEquals(res.status, 200, "not a 500");
      const out = await body(res);
      assertEquals([out.account, out.user_id], ["created", mine]);
      assertEquals(await byHmac(w.h), [mine], "exactly one users row, under the proposal");
      assert((await ticketRow(ticket)).consumed_at, "the sign-up ticket is spent");
      const act = await ticketRow(out.ticket);
      assertEquals(act.user_id, mine, "the activation ticket names the new user");

      const again = await call(w.edge, "/signup/adopt", {
        signup_ticket: ticket,
        user_id: crypto.randomUUID(),
      }, w.ip);
      assertEquals([again.status, await body(again)], [400, INVALID]);
      assertEquals(await byHmac(w.h), [mine]);
    } finally {
      await w.cleanup();
    }
  },
);

// ---------------------------------------------------------------- E-1005c-12
test(
  "E-1005c-12 (database half, concurrent) two adopts of ONE ticket in flight together, made to meet just AFTER the ticket lookup: the row lock decides them — the second never gets past the ticket (it never looks the phone up), answers 400 signup_ticket_invalid, never 500 or 409 — one users row; and an adopt racing the I'm-new path's signup verify for the same number, the two made to meet just AFTER each has looked the number up, never makes two accounts: the per-phone lock decides them",
  async () => {
    // Arm 1: the FOR UPDATE row lock. Unlocked, both adopts would pass the lookup and meet; the
    // per-phone lock would still stop a second account, but only after BOTH had looked the phone
    // up — which is what `lookups` counts.
    {
      let lookups = 0;
      const meet = rendezvous(2, 400);
      const w = await world((s) =>
        hooked(s, (key, v, target) => {
          if (key === "lockSignupTicket") {
            return async (...a: unknown[]) => {
              const got = await v.apply(target, a);
              await meet();
              return got;
            };
          }
          if (key === "findUserByPhoneHmac") {
            return (...a: unknown[]) => {
              lookups++;
              return v.apply(target, a);
            };
          }
          return v.bind(target);
        })
      );
      try {
        const ticket = await w.signupTicket();
        lookups = 0;
        const answers = await Promise.all([0, 1].map(() =>
          call(w.edge, "/signup/adopt", {
            signup_ticket: ticket,
            user_id: crypto.randomUUID(),
          }, w.ip)
        ));
        const got = await Promise.all(
          answers.map(async (a) => ({ status: a.status, body: await body(a) })),
        );
        got.sort((a, b) => a.status - b.status);
        assertEquals(got.map((g) => g.status), [200, 400], JSON.stringify(got.map((g) => g.body)));
        assertEquals(got[1].body, INVALID);
        assertEquals(await byHmac(w.h), [got[0].body.user_id], "ONE users row");
        assertEquals(lookups, 1, "the loser never got past the ticket: the row lock held it");
      } finally {
        await w.cleanup();
      }
    }
    // Arm 2: adopt and the I'm-new path's verify, same number, together. What is under test is
    // adopt's per-phone lock (lockPhoneForVerify), so the two are made to meet just AFTER each has
    // asked "does this number have an account?" — the decision the lock exists to serialise.
    // Locked, the second is held at the lock until the first commits: the first waits out the
    // meet's timeout alone, and the second then finds the account. Unlocked, both find none, both
    // sign up, and the second insert hits users.phone_hmac's unique index (0001) — a 500. The meet
    // is ARMED only after the preconditions: signupTicket()'s own verify looks the phone up too,
    // and a meeting point it used up would let the race run unmet.
    {
      let meet: (() => Promise<void>) | null = null;
      const w = await world((s) =>
        hooked(s, (key, v, target) => {
          if (key === "findUserByPhoneHmac") {
            return async (...a: unknown[]) => {
              const got = await v.apply(target, a);
              if (meet) await meet();
              return got;
            };
          }
          return v.bind(target);
        })
      );
      try {
        const ticket = await w.signupTicket();
        advance(w.r, 31_000); // past the first resend backoff, well inside the ticket's life
        assertEquals(
          (await call(w.edge, "/otp/request", { phone: w.p, purpose: "signup" }, w.ip)).status,
          200,
        );
        const code = w.r.otp.sent.at(-1)!.code;
        meet = rendezvous(2, 400);
        const [a, v] = await Promise.all([
          call(w.edge, "/signup/adopt", {
            signup_ticket: ticket,
            user_id: crypto.randomUUID(),
          }, w.ip),
          call(w.edge, "/otp/verify", {
            phone: w.p,
            purpose: "signup",
            code,
            user_id: crypto.randomUUID(),
          }, w.ip),
        ]);
        const [ab, vb] = [await body(a), await body(v)];
        assertEquals(v.status, 200, "the verify always succeeds");
        const ids = await byHmac(w.h);
        assertEquals(ids.length, 1, "ONE account for the number, whichever came first");
        assertEquals(vb.user_id, ids[0]);
        if (a.status === 200) {
          assertEquals([ab.account, vb.account], ["created", "existing"], "adopt first");
        } else {
          assertEquals([a.status, ab, vb.account], [400, INVALID, "created"], "verify first");
        }
      } finally {
        await w.cleanup();
      }
    }
  },
);

// ---------------------------------------------------------------- E-1005c-13
test(
  "E-1005c-13 (database half) adopt's refusals on the real store: a proposal another user holds answers 409 user_id_taken — never 500 — with no users row and the ticket UNSPENT in Postgres (the refused insert rolled back to its savepoint and the transaction committed clean), so the retry with a fresh id and the same ticket answers 200; and a number that gained an account in between fails closed — 400 signup_ticket_invalid, the ticket spent, still one account",
  async () => {
    const [holder] = await sql`insert into users (phone_hmac, phone_ct) values (${rand(32)}, ${
      rand(40)
    }) returning id`;
    const w = await world();
    try {
      const ticket = await w.signupTicket();
      const res = await call(w.edge, "/signup/adopt", {
        signup_ticket: ticket,
        user_id: holder.id,
      }, w.ip);
      assertEquals([res.status, await body(res)], [409, { error: "user_id_taken" }]);
      assertEquals(await byHmac(w.h), [], "no users row for the number");
      assertEquals((await ticketRow(ticket)).consumed_at, null, "the ticket is NOT spent");
      const fresh = crypto.randomUUID();
      const again = await call(w.edge, "/signup/adopt", {
        signup_ticket: ticket,
        user_id: fresh,
      }, w.ip);
      assertEquals(again.status, 200, "the one retry, same ticket");
      assertEquals(await byHmac(w.h), [fresh]);
    } finally {
      await w.cleanup();
    }

    const v = await world();
    try {
      const ticket = await v.signupTicket();
      advance(v.r, 31_000);
      await call(v.edge, "/otp/request", { phone: v.p, purpose: "signup" }, v.ip);
      const owner = crypto.randomUUID();
      const made = await body(
        await call(v.edge, "/otp/verify", {
          phone: v.p,
          purpose: "signup",
          code: v.r.otp.sent.at(-1)!.code,
          user_id: owner,
        }, v.ip),
      );
      assertEquals(made.account, "created", "precondition: the number has books now");
      const res = await call(v.edge, "/signup/adopt", {
        signup_ticket: ticket,
        user_id: crypto.randomUUID(),
      }, v.ip);
      assertEquals([res.status, await body(res)], [400, INVALID], "fail closed, not `existing`");
      assert((await ticketRow(ticket)).consumed_at, "the ticket is spent: the branch ran");
      assertEquals(await byHmac(v.h), [owner], "still one account");
    } finally {
      await v.cleanup();
    }
  },
);

// ---------------------------------------------------------------- E-1005c-14
class Rollback extends Error {
  constructor() {
    super("rollback");
  }
}
const PLATFORM = ["anon", "authenticated", "service_role"];
/**
 * 0005's platform-role revoke, as the migration file has it: the `do $$ … end $$;` block that
 * revokes every table privilege from the three platform roles (the block E-03-20 finds by text).
 * Read from the file — not restated here — so that deleting or gutting it fails E-1005c-14.
 */
function revokeBlock0005(): string | undefined {
  const mig = Deno.readTextFileSync(
    new URL("../../migrations/0005_rls_and_grants.sql", import.meta.url),
  );
  return (mig.match(/^do \$\$[\s\S]*?^end \$\$;/gm) ?? []).find((b) =>
    PLATFORM.every((r) => b.includes(`'${r}'`)) &&
    b.includes("revoke all on all tables in schema public from")
  );
}
test(
  "E-1005c-14 hostile: the platform roles anon, authenticated and service_role cannot SELECT, INSERT, UPDATE or DELETE a sign-up ticket row — handed ALL on activation_tickets as a hosted project's default privileges hand it when 0004 creates the table (service_role with BYPASSRLS, as hosted, so the grant alone reads the row), 0005's own platform-role revoke, run from the migration file, takes every grant back and all twelve are refused outright; and even with the ALL grant leaked again afterwards, anon and authenticated read no row and write none, because RLS is FORCEd with no policy for them; rf_maintenance (the purge) cannot write one; rf_api holds no DELETE",
  async () => {
    // Why the revoke is simulated, not observed: on the plain-Postgres cluster this suite runs on
    // (scripts/rls_db.sh) the platform roles do not exist when 0005 runs, so its `if exists` guard
    // skips the revoke and there is nothing to observe. On a hosted project the roles exist first,
    // and Supabase's default privileges grant them ALL on every table the migrations create. So
    // the hosted state is rebuilt here — the roles, the grant, service_role's BYPASSRLS — and the
    // block 0005 ships is run over it. This runs 0005's text on today's schema, not at its place in
    // the order; for activation_tickets (created by 0004, before 0005, never re-created) it is the
    // same table either way.
    const block = revokeBlock0005();
    assert(block, "0005 still carries its platform-role revoke block");
    const outcome: Record<string, string> = {};
    const end = await pgErr(sql.begin(async (s) => {
      // CREATE ROLE is transactional: on this plain-Postgres cluster the roles exist only inside
      // this transaction, which is always rolled back. On a hosted project they already exist.
      for (const role of PLATFORM) {
        const attrs = role === "service_role" ? "nologin bypassrls" : "nologin";
        await s.unsafe(`do $$ begin
          if not exists (select 1 from pg_roles where rolname = '${role}') then
            create role ${role} ${attrs};
          end if; end $$`);
      }
      const th = rand(32), ph = rand(32);
      await s`insert into activation_tickets (ticket_hash, phone_hmac, purpose, user_id, expires_at)
        values (${th}, ${ph}, 'device_activation', null, now() + interval '10 minutes')`;
      const probe = (role: string, stmt: string) =>
        pgErr(s.savepoint(async (sp) => {
          await sp.unsafe(`set local role ${role}`);
          const rows = await sp.unsafe(stmt);
          const n = (rows as unknown as { count: number }).count;
          await sp.unsafe("reset role");
          if (n > 0) throw Object.assign(new Error(`${n} rows`), { code: "ROWS" });
        }));
      const STMTS: Record<string, string> = {
        select: "select * from activation_tickets where user_id is null",
        insert: `insert into activation_tickets (ticket_hash, phone_hmac, purpose, user_id,
          expires_at) values (decode(md5(random()::text) || md5(random()::text), 'hex'),
          decode(md5(random()::text) || md5(random()::text), 'hex'), 'device_activation', null,
          now() + interval '10 minutes')`,
        update:
          "update activation_tickets set consumed_at = null, expires_at = now() + interval '1 day' where user_id is null",
        delete: "delete from activation_tickets where user_id is null",
      };
      // The state before 0005, as a hosted project has it. The control proves the grant is live
      // and the probe can see a leak: service_role, bypassing RLS, reads the ticket row.
      await s`grant all on activation_tickets to anon, authenticated, service_role`;
      for (const role of PLATFORM) {
        outcome[`${role} before 0005 select`] = (await probe(role, STMTS.select)).code;
      }
      await s.unsafe(block!);
      for (const role of PLATFORM) {
        for (const [what, stmt] of Object.entries(STMTS)) {
          outcome[`${role} ${what}`] = (await probe(role, stmt)).code;
        }
      }
      // A table a LATER migration creates gets the default-privilege grant after 0005 has run.
      // Simulate that leak on this table: for anon and authenticated, RLS still holds.
      await s`grant all on activation_tickets to anon, authenticated`;
      for (const role of ["anon", "authenticated"]) {
        for (const [what, stmt] of Object.entries(STMTS)) {
          outcome[`${role}+grant ${what}`] = (await probe(role, stmt)).code;
        }
      }
      for (const what of ["insert", "update"]) {
        outcome[`rf_maintenance ${what}`] = (await probe("rf_maintenance", STMTS[what])).code;
      }
      const [d] =
        await s`select has_table_privilege('rf_api', 'public.activation_tickets', 'DELETE') as ok`;
      outcome["rf_api holds delete"] = String(d.ok);
      const [row] = await s`select consumed_at is null
          and expires_at <= now() + interval '10 minutes' as ok
        from activation_tickets where ticket_hash = ${th}`;
      outcome["row untouched"] = String(row?.ok === true);
      throw new Rollback();
    }));
    assertEquals(end.message, "rollback", `the probe ran to its end: ${end.code} ${end.message}`);

    const expect: Record<string, string> = {};
    expect["anon before 0005 select"] = "ok"; // granted; RLS FORCEd, no policy: no row
    expect["authenticated before 0005 select"] = "ok";
    expect["service_role before 0005 select"] = "ROWS"; // granted and BYPASSRLS: the leak is real
    for (const role of PLATFORM) {
      for (const what of ["select", "insert", "update", "delete"]) {
        expect[`${role} ${what}`] = "42501"; // insufficient_privilege: 0005 took every grant back
      }
    }
    for (const role of ["anon", "authenticated"]) {
      expect[`${role}+grant select`] = "ok"; // reads, but no row: no policy names the role
      expect[`${role}+grant insert`] = "42501"; // new row violates row-level security policy
      expect[`${role}+grant update`] = "ok"; // 0 rows: none visible to update
      expect[`${role}+grant delete`] = "ok"; // 0 rows: none visible to delete
    }
    expect["rf_maintenance insert"] = "42501";
    expect["rf_maintenance update"] = "42501";
    expect["rf_api holds delete"] = "false";
    expect["row untouched"] = "true";
    assertEquals(outcome, expect);
  },
);
