// Hostile-query suite for the seat-rotation ledger's retention sweep — migration 0023,
// rf.sweep_seat_grants(), against ADR 2026-09-05g §6 🔒 ("Re-inviting the same user_id within 30
// days does not consume a new seat. A rolling cap of 2 × seats distinct members per year stops seat
// rotation") and desk PLAN-60 (a)'s open reading (per year = the trailing year from now()).
//
// The ledger (seat_grants, 0019 §3) is append-only and read by exactly one function, rf.take_seat
// (0019 §4): the 30-day re-invite exemption (`granted_at > now() - interval '30 days'`) and the
// rolling count (`granted_at > now() - interval '1 year'`). A row older than a year is never read
// again, so it can go — but a sweep that took ONE row a reader still counts would hand a tenant a
// rotation slot back, silently. What an attacker — or a careless sweep — wants, and what each test
// denies:
//
//   * A WRONG CUTOFF — a sweep that deletes a row inside the year (or inside the 30-day margin 0023
//     keeps beyond it), or keeps a row past the cutoff forever (E-05g-27).
//   * BOUGHT-BACK BUDGET — a tenant at the boundary whose rotation or re-invite answer changes
//     because a sweep ran; and a NEW reader of the ledger, added later, that looks back further than
//     the sweep allows and nobody re-proved the margin for (E-05g-28's tripwire).
//   * A NEW POWER — rf_api (or PUBLIC) able to run the sweep; rf_maintenance able to choose its own
//     cutoff, or to reach the table other than through the one function (E-05g-29).
//   * A SECOND RUN THAT DOES HARM — the sweep run twice, or two overlapping cron runs, deleting more,
//     failing, or double-reporting (E-05g-30).
//
// Fixtures are written by the schema owner (no claims: 0019 §2 caps only API writes); grants are
// TAKEN through the real path (rf.create_invite as rf_api, which fires 0019's trigger) and only then
// back-dated by the owner, as E-05g-6 does. Every sweep under test runs as rf_maintenance through its
// EXECUTE grant — never as the owner — so a sweep that only worked for a superuser fails here.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-05g-27, E-05g-28, E-05g-29, E-05g-30.
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — seat_grants_sweep.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP seat_grants_sweep.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

/** 0023's cutoff, as the spec of this file states it: one year (the longest window any reader of
 *  seat_grants uses) plus a 30-day margin. Ages below are measured against it. */
const CUTOFF = "1 year 30 days";
const SWEEP = "rf.sweep_seat_grants()";

interface PgErr {
  code: string;
  message: string;
}
async function pgErr(p: Promise<unknown>): Promise<PgErr> {
  try {
    await p;
    return { code: "ok", message: "" };
  } catch (e) {
    const x = e as { code?: string; message?: string };
    return { code: x.code ?? "unknown", message: x.message ?? "" };
  }
}
const OK: PgErr = { code: "ok", message: "" };

// ---------------------------------------------------------------- test-only catalogue rows
const PLAN = {
  two: "zz_sweep_two", //   2 seats → rotation budget 4 (ADR 05g §6: 2 × seats)
  none: "zz_sweep_none", // -1: no cap — grants are still appended (0019 §3), so ages can be laid out freely
} as const;
async function ensurePlans() {
  await sql`insert into plan_catalogue (id, entity_type, name, sort_order, members, business_books,
      devices, envelopes_per_book, tenant_bytes, attachment_bytes, features, price_yearly_paise,
      price_monthly_paise)
    values (${PLAN.two},  'family', 'Sweep two',  94,  2,  0,  5, 1000, 1000, 1000, '{}', 0, 0),
           (${PLAN.none}, 'family', 'Sweep none', 95, -1, -1, -1, 1000, 1000, 1000, '{}', 0, 0)
    on conflict (id) do nothing`;
}
/** The catalogue as the seed wrote it: this file's tenants drop to the Free floor, the rows go. */
async function dropPlans() {
  const ids = Object.values(PLAN) as string[];
  await sql`update subscriptions set plan = 'free' where plan in ${sql(ids)}`;
  await sql`delete from plan_catalogue where id in ${sql(ids)}`;
}

/** One test: its own pool, the plans present, the pool closed and the plans removed whatever
 *  happens. */
function test(name: string, fn: () => Promise<void>) {
  Deno.test({
    name,
    ignore,
    async fn() {
      sql = postgres(url!, { max: 4, onnotice: () => {} });
      try {
        await ensurePlans();
        await fn();
      } finally {
        try {
          await dropPlans();
        } finally {
          await sql.end();
        }
      }
    },
  });
}

// ---------------------------------------------------------------- fixtures (schema owner, no claims)
interface P {
  user: string;
  dev: string;
  hmac: Uint8Array;
}
async function mkPerson(): Promise<P> {
  const hmac = rand(32);
  const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${hmac}, ${rand(40)})
    returning id`;
  const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${u.id}, ${rand(32)}, ${rand(32)}, 'certified') returning id`;
  return { user: u.id as string, dev: d.id as string, hmac };
}
async function record(tenant: string, device: string): Promise<string> {
  const id = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${id}, 1, ${tenant}, 'invite', '{}'::jsonb, ${rand(8)}, ${device}, ${rand(64)}, 1)`;
  return id;
}
interface Tn {
  t: string;
  admin: P;
}
/** A tenant on `plan` with its founder active and admin of the founder's personal book. */
async function tenant(plan: string): Promise<Tn> {
  const [row] = await sql`insert into tenants (type) values ('family') returning id`;
  const t = row.id as string;
  await sql`insert into subscriptions (tenant_id, plan) values (${t}, ${plan})`;
  const admin = await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${admin.user}, 'active')`;
  const personal = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type, owner_user_id)
    values (${personal}, ${t}, 'personal', ${admin.user})`;
  await sql`insert into book_roles (book_id, user_id, role) values (${personal}, ${admin.user}, 'admin')`;
  return { t, admin };
}

// ---------------------------------------------------------------- API writes (rf_api, with claims)
async function invite(tn: Tn, to: Uint8Array): Promise<string> {
  const rec = await record(tn.t, tn.admin.dev);
  const [r] = await sql.begin(async (s) => {
    await s.unsafe("set local role rf_api");
    await s`select rf.set_claims(${tn.admin.user}::uuid, ${tn.admin.dev}::uuid)`;
    return await s`select rf.create_invite(${tn.t}, ${to}, '[]'::jsonb, ${rand(16)}, ${rec}) as id`;
  });
  return r.id as string;
}
class Rollback extends Error {
  constructor(readonly e: PgErr) {
    super("rollback");
  }
}
/** What an admin's invite to `to` WOULD answer right now — through the real path (rf_api, claims,
 *  rf.create_invite, 0019's trigger, rf.take_seat) — inside a transaction that is then rolled back,
 *  so asking appends no grant and leaves no invite: the same question can be asked again later. */
async function wouldInvite(tn: Tn, to: Uint8Array): Promise<PgErr> {
  const rec = await record(tn.t, tn.admin.dev);
  try {
    await sql.begin(async (s) => {
      await s.unsafe("set local role rf_api");
      await s`select rf.set_claims(${tn.admin.user}::uuid, ${tn.admin.dev}::uuid)`;
      const e = await pgErr(
        s.savepoint((sp) =>
          sp`select rf.create_invite(${tn.t}, ${to}, '[]'::jsonb, ${rand(16)}, ${rec})`
        ),
      );
      throw new Rollback(e);
    });
  } catch (x) {
    if (x instanceof Rollback) return x.e;
    throw x;
  }
  throw new Error("wouldInvite: the probe transaction committed");
}

// ---------------------------------------------------------------- owner-side reads and edits
const revoke = (id: string) => sql`update invites set status = 'revoked' where id = ${id}`;
async function grants(t: string): Promise<number> {
  const [r] = await sql`select count(*)::int as n from seat_grants where tenant_id = ${t}`;
  return r.n as number;
}
/** Invite fresh people, revoking each, until the tenant's ledger holds `n` rows. Each person gets
 *  exactly one grant (0019's trigger resolves the number to the user, so `user_id` is set). */
async function spendTo(tn: Tn, n: number): Promise<P[]> {
  const out: P[] = [];
  while ((await grants(tn.t)) < n) {
    const p = await mkPerson();
    await revoke(await invite(tn, p.hmac));
    out.push(p);
  }
  return out;
}
/** Move a person's grant `age` into the past (an interval literal; negative parts allowed). */
async function age(tn: Tn, p: P, a: string): Promise<void> {
  const r = await sql`update seat_grants set granted_at = now() - ${a}::interval
    where tenant_id = ${tn.t} and user_id = ${p.user}`;
  assertEquals(r.count, 1, `exactly one grant for this person (${a})`);
}
async function hasGrant(tn: Tn, p: P): Promise<boolean> {
  const [r] = await sql`select exists (select 1 from seat_grants
    where tenant_id = ${tn.t} and user_id = ${p.user}) as ok`;
  return r.ok as boolean;
}
async function ledger(t: string): Promise<string[]> {
  const rows = await sql`select id::text || '@' || granted_at::text as k from seat_grants
    where tenant_id = ${t} order by id`;
  return rows.map((r) => r.k as string);
}
async function total(): Promise<number> {
  const [r] = await sql`select count(*)::int as n from seat_grants`;
  return r.n as number;
}

/** The sweep as the maintenance role runs it: `set local role rf_maintenance` — the EXECUTE grant
 *  is what is exercised, and current_user is asserted so a superuser can never stand in for it. */
async function sweep(): Promise<number> {
  const n = await sql.begin(async (t) => {
    await t.unsafe("set local role rf_maintenance");
    const [who] = await t`select current_user::text as cu`;
    assertEquals(who.cu, "rf_maintenance");
    const [r] = await t.unsafe(`select ${SWEEP} as n`);
    return r.n as number;
  });
  return n as number;
}

// ---------------------------------------------------------------- the reader tripwire (E-05g-28)
/** Every reader of seat_grants the catalogue can show, three ways — each covers another's blind
 *  spot:
 *   * `fns` — functions whose TEXT names the table: prosrc for plpgsql and quoted-body SQL, and the
 *     deparsed body for a SQL-standard function (`begin atomic … end`), whose prosrc is '' because
 *     its body is stored as a parse tree in prosqlbody (pg_get_functiondef deparses it; the CASE
 *     keeps it off aggregates, which it refuses, and none of which has a SQL body).
 *   * `deps` — every object Postgres RECORDS as depending on the table, its row type or the row
 *     type's array: SQL-standard bodies, views and rules (their _RETURN rule), policies and foreign
 *     keys on other tables, functions taking or returning the row type — less the table's own parts
 *     (indexes, constraints, defaults, owned sequence, row type, policies and triggers ON it — each
 *     auto- or internally dependent on it; seat_book_caps.test.ts holds the table to no policy and
 *     no grant). A plpgsql body records no dependency, which is why `fns` reads text.
 *   * `text` — views, materialised views and policies whose deparsed definition names it.
 *  What no catalogue check can see: a body that builds the name at run time (`execute 'select … from
 *  ' || 'seat' || '_grants'`). There is none in migrations/ (grepped for 0023's header); a new one is
 *  for review to catch, and would have to name the table somewhere a grep finds. */
async function readersOf(s: postgres.Sql) {
  const fns = await s`select p.oid::regprocedure::text as fn from pg_proc p
    where p.prosrc ~* 'seat_grants'
       or case when p.prosqlbody is not null
               then pg_get_functiondef(p.oid) ~* 'seat_grants' else false end
    order by 1`;
  const deps = await s`with t as (
      select c.oid as rel, c.reltype as typ, ty.typarray as arr
      from pg_class c join pg_type ty on ty.oid = c.reltype
      where c.oid = 'public.seat_grants'::regclass),
    dep as (
      select d.classid, d.objid, d.deptype from pg_depend d, t
      where (d.refclassid = 'pg_class'::regclass and d.refobjid = t.rel)
         or (d.refclassid = 'pg_type'::regclass and d.refobjid in (t.typ, t.arr)))
    select distinct pg_describe_object(x.classid, x.objid, 0) as obj from dep x
    where not exists (select 1 from dep o
      where o.classid = x.classid and o.objid = x.objid and o.deptype in ('a', 'i'))
    order by 1`;
  const [v] = await s`select
      (select count(*)::int from pg_views where definition ~* 'seat_grants') +
      (select count(*)::int from pg_matviews where definition ~* 'seat_grants') +
      (select count(*)::int from pg_policies
        where coalesce(qual, '') ~* 'seat_grants' or coalesce(with_check, '') ~* 'seat_grants')
      as n`;
  return {
    fns: fns.map((r) => r.fn as string),
    deps: deps.map((r) => r.obj as string),
    text: v.n as number,
  };
}
class Undo extends Error {}
/** Run `f` in a transaction that is always rolled back, and hand back what it returned. */
async function rolledBack<T>(f: (s: postgres.TransactionSql) => Promise<T>): Promise<T> {
  const box: { v?: T } = {};
  try {
    await sql.begin(async (s) => {
      box.v = await f(s);
      throw new Undo();
    });
  } catch (x) {
    if (!(x instanceof Undo)) throw x;
    return box.v as T;
  }
  throw new Error("rolledBack: the transaction committed");
}

// ================================================================ the tests

test("E-05g-27 rows older than the cutoff (1 year + 30 days) go and every newer row stays: a grant 3 years old, 1 year 31 days old and an hour past the cutoff is deleted; one an hour inside it, 1 year 29 days old, 1 year 1 day old (outside every reader's window, inside the margin), 1 year less a day (still counted) and a day old all survive; the sweep reports exactly the rows it removed, in every tenant", async () => {
  const tn = await tenant(PLAN.none);
  const ps = await spendTo(tn, 8);
  assertEquals(ps.length, 8);
  const goes = [
    [ps[0], "3 years"],
    [ps[1], "1 year 31 days"],
    [ps[2], `${CUTOFF} 1 hour`],
  ] as const;
  const stays = [
    [ps[3], "1 year 29 days 23 hours"],
    [ps[4], "1 year 29 days"],
    [ps[5], "1 year 1 day"],
    [ps[6], "1 year -1 day"],
    [ps[7], "1 day"],
  ] as const;
  for (const [p, a] of [...goes, ...stays]) await age(tn, p, a);
  // A second tenant's old row: the sweep is per table, not per tenant.
  const other = await tenant(PLAN.none);
  const [o] = await spendTo(other, 1);
  await age(other, o, "2 years");

  const before = await total();
  const n = await sweep();
  const after = await total();
  assertEquals(n, before - after, "the count it returns is the rows that left the table");
  assert(n >= goes.length + 1, `at least this file's ${goes.length + 1} old rows (${n})`);
  for (const [p, a] of goes) assertEquals(await hasGrant(tn, p), false, `${a} old: swept`);
  for (const [p, a] of stays) assertEquals(await hasGrant(tn, p), true, `${a} old: kept`);
  assertEquals(await hasGrant(other, o), false, "another tenant's 2-year-old row: swept too");
  assertEquals(await grants(tn.t), stays.length);
});

test("E-05g-28 the rolling cap and the 30-day exemption answer the same before and after a sweep — a 2-seat tenant at the boundary (4 grants counted in the trailing year, the oldest a day inside it; a 29-day re-invite exempt, a 31-day one not; three older grants, two past the cutoff): a new member is refused seat_rotation_cap, the 29-day person is let back, the 31-day and a swept person are refused, identically on both sides of a sweep that really removed this tenant's old rows; and the ledger's readers are exactly rf.take_seat (windows 30 days and 1 year) — no view, policy or edge function reads it", async () => {
  const tn = await tenant(PLAN.two);
  // Three grants that fall out of the year: one past the cutoff by years, one by a day, one inside
  // the margin (out of every window, kept by the sweep).
  const [pG, pF, pE] = await spendTo(tn, 3);
  await age(tn, pG, "3 years");
  await age(tn, pF, "1 year 31 days");
  await age(tn, pE, "1 year 1 day");
  // Four counted grants — the whole budget of 2 × 2 — laid on the boundaries the readers use.
  const [pA, pB, pC, pD] = await spendTo(tn, 7);
  await age(tn, pA, "29 days"); //        inside the 30-day exemption
  await age(tn, pB, "31 days"); //        outside it, inside the year
  await age(tn, pC, "1 year -1 day"); //  the oldest grant the rolling count still sees
  await age(tn, pD, "200 days");

  const ask = async () => [
    await wouldInvite(tn, rand(32)),
    await wouldInvite(tn, pA.hmac),
    await wouldInvite(tn, pB.hmac),
    await wouldInvite(tn, pE.hmac),
    await wouldInvite(tn, pF.hmac),
  ];
  const rotation: PgErr = { code: "P0001", message: "seat_rotation_cap" };
  const want = [rotation, OK, rotation, rotation, rotation];
  const before = await ask();
  assertEquals(before, want, "the boundary as 0019 reads it: budget spent, pA exempt");
  assertEquals(await grants(tn.t), 7, "asking appended nothing (every probe rolled back)");

  const n = await sweep();
  assert(n >= 2, `the sweep removed rows (${n})`);
  assertEquals(
    [await hasGrant(tn, pG), await hasGrant(tn, pF), await hasGrant(tn, pE)],
    [false, false, true],
    "this tenant's two rows past the cutoff are gone; the one inside the margin stays",
  );
  assertEquals(await grants(tn.t), 5);
  assertEquals(await ask(), before, "every answer is the same after the sweep");

  // The tripwire: the readers this proof covers are all the readers there are. A function, view,
  // policy, rule or foreign key that starts reading seat_grants — or a reader window that grows —
  // fails here, and the margin in 0023 has to be proved again for it before this list is edited.
  // readersOf (below) looks three ways, because each one alone has a blind spot.
  const now = await readersOf(sql);
  assertEquals(
    now.fns,
    ["rf.sweep_seat_grants()", "rf.take_seat(uuid,uuid,bytea,uuid)"],
    "seat_grants is read by rf.take_seat and swept by rf.sweep_seat_grants, nothing else",
  );
  assertEquals(now.deps, [], "nothing in the catalogue records a dependency on the ledger");
  assertEquals(now.text, 0, "no view, materialised view or policy reads the ledger");
  // …and the tripwire is not blind to the reader that once got past it: a SQL-standard body
  // (`begin atomic`, kept as a parse tree in prosqlbody with prosrc = '') that counts two years
  // back, beside a view — planted in a transaction that is rolled back, so nothing is left behind.
  const planted = await rolledBack(async (s) => {
    await s.unsafe(`create function rf.zz_tripwire_probe(p uuid) returns bigint
      language sql stable security definer set search_path = public
      begin atomic
        select count(*) from seat_grants g
        where g.tenant_id = p and g.granted_at > now() - interval '2 years';
      end`);
    await s.unsafe(`create view rf.zz_tripwire_view as select tenant_id from seat_grants`);
    const [p] = await s`select prosrc from pg_proc
      where oid = 'rf.zz_tripwire_probe(uuid)'::regprocedure and prosqlbody is not null`;
    assertEquals(p?.prosrc, "", "the probe is the blind-spot shape: no text in prosrc");
    return await readersOf(s);
  });
  assertEquals(
    planted.fns,
    [...now.fns, "rf.zz_tripwire_probe(uuid)"].sort(),
    "the SQL-standard body is found by its deparsed text",
  );
  assertEquals(
    planted.deps,
    ["function rf.zz_tripwire_probe(uuid)", "rule _RETURN on view rf.zz_tripwire_view"],
    "the SQL-standard body and the view are both found by their recorded dependency",
  );
  assertEquals(planted.text, 1, "the view is found by its deparsed definition");
  const windows = await sql`select m[1] as w
    from pg_proc p, regexp_matches(p.prosrc, 'interval ''([^'']+)''', 'g') m
    where p.oid = 'rf.take_seat(uuid,uuid,bytea,uuid)'::regprocedure order by 1`;
  assertEquals(
    windows.map((r) => r.w),
    ["1 year", "30 days"],
    "rf.take_seat's two windows: the rolling year and the 30-day re-invite",
  );
  const [m] = await sql`select bool_and(now() - w::interval - interval '29 days'
      > now() - ${CUTOFF}::interval) as ok
    from unnest(${windows.map((r) => r.w as string)}::text[]) w`;
  assertEquals(m.ok, true, "each window ends at least 29 days inside the sweep's cutoff");
  // …and no edge function reaches the table (rf_api holds no grant on it either — E-05g-11).
  const root = new URL("../../functions/", import.meta.url);
  const hits: string[] = [];
  const walk = async (dir: URL) => {
    for await (const e of Deno.readDir(dir)) {
      const u = new URL(e.name + (e.isDirectory ? "/" : ""), dir);
      if (e.isDirectory) await walk(u);
      else if (/\.ts$/.test(e.name) && /seat_grants/.test(await Deno.readTextFile(u))) {
        hits.push(u.pathname);
      }
    }
  };
  await walk(root);
  assertEquals(hits, [], "no edge function names seat_grants");
});

test("E-05g-29 rf_api cannot execute the sweep and rf_maintenance can — each connected as its own login role (rf_local, rf_local_maint) with current_user asserted; rf_api is refused with and without claims, PUBLIC and the platform roles hold no EXECUTE; the function takes no argument, so the maintenance role cannot choose its own cutoff, and it is still the only door: rf_maintenance holds no privilege on seat_grants and no policy names it", async () => {
  const login = (role: string) => {
    const u = new URL(url!);
    u.username = role;
    u.password = role; // seed.sql's LOCAL-ONLY passwords (rls_db.sh refuses a non-loopback host)
    return postgres(u.toString(), { max: 1, onnotice: () => {} });
  };
  const tn = await tenant(PLAN.none);

  const api = login("rf_local");
  try {
    for (
      const [claims, how] of [
        [[tn.admin.user, tn.admin.dev], "an admin's own claims"],
        [[null, null], "no claims"],
      ] as const
    ) {
      const e = await pgErr(api.begin(async (s) => {
        await s.unsafe("set local role rf_api");
        await s`select rf.set_claims(${claims[0]}::uuid, ${claims[1]}::uuid)`;
        const [who] = await s`select current_user::text as cu, session_user::text as su`;
        assertEquals([who.cu, who.su], ["rf_api", "rf_local"]);
        await s.unsafe(`select ${SWEEP}`);
      }));
      assertEquals(e.code, "42501", `rf_api with ${how}: ${e.message}`);
    }
    // The login role itself (it inherits rf_api) is refused too.
    const e = await pgErr(api.begin(async (s) => {
      const [who] = await s`select current_user::text as cu`;
      assertEquals(who.cu, "rf_local");
      await s.unsafe(`select ${SWEEP}`);
    }));
    assertEquals(e.code, "42501", `rf_local: ${e.message}`);
  } finally {
    await api.end();
  }

  const maint = login("rf_local_maint");
  try {
    const n = await maint.begin(async (s) => {
      await s.unsafe("set local role rf_maintenance");
      const [who] = await s`select current_user::text as cu, session_user::text as su`;
      assertEquals([who.cu, who.su], ["rf_maintenance", "rf_local_maint"]);
      const [r] = await s.unsafe(`select ${SWEEP} as n`);
      for (const q of ["select * from seat_grants", "delete from seat_grants"]) {
        const d = await pgErr(s.savepoint((sp) => sp.unsafe(q)));
        assertEquals(d.code, "42501", `rf_maintenance: ${q} — only the function reaches the table`);
      }
      return r.n as number;
    });
    assert(Number.isInteger(n) && n >= 0, `rf_maintenance ran it: ${n}`);
  } finally {
    await maint.end();
  }

  const [f] = await sql`select p.pronargs, p.prosecdef, p.proconfig,
      has_function_privilege('rf_api', p.oid, 'EXECUTE') as api,
      has_function_privilege('rf_maintenance', p.oid, 'EXECUTE') as maint,
      exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where a.grantee = 0 and a.privilege_type = 'EXECUTE') as pub
    from pg_proc p where p.oid = ${SWEEP}::regprocedure`;
  assertEquals(f.pronargs, 0, "no argument: the cutoff is the migration's, not the caller's");
  assertEquals(f.prosecdef, true, "SECURITY DEFINER: it reaches a table no role holds a grant on");
  assertEquals(
    f.proconfig,
    ["search_path=public, pg_temp"],
    "a pinned search_path, pg_temp last (0024)",
  );
  assertEquals([f.api, f.maint, f.pub], [false, true, false]);
  const platform = await sql`select rolname from pg_roles
    where rolname in ('anon', 'authenticated', 'service_role')`;
  for (const r of platform) {
    const [h] = await sql`select has_function_privilege(${r.rolname}, ${SWEEP}, 'EXECUTE') as ok`;
    assertEquals(h.ok, false, `${r.rolname} cannot EXECUTE the sweep`);
  }
  for (const role of ["rf_api", "rf_maintenance"]) {
    for (const priv of ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]) {
      const [h] =
        await sql`select has_table_privilege(${role}, 'public.seat_grants', ${priv}) as ok`;
      assertEquals(h.ok, false, `${role} still holds no ${priv} on seat_grants`);
    }
  }
  const [pol] =
    await sql`select count(*)::int as n from pg_policies where tablename = 'seat_grants'`;
  assertEquals(pol.n, 0, "still no policy on the ledger");
  for (const priv of ["UPDATE", "DELETE"]) {
    const [h] = await sql`select has_table_privilege('rf_api', 'public.envelopes', ${priv}) as ok`;
    assertEquals(h.ok, false, `rf_api still holds no ${priv} on envelopes (CLAUDE.md rule 2)`);
  }
});

test("E-05g-30 the sweep is idempotent: run again at once it removes nothing, reports 0 and leaves every surviving row (id and granted_at) as it was; and two overlapping runs — a cron run that starts while the last still holds its rows — neither fail nor double-count: together they report exactly the rows that left", async () => {
  const tn = await tenant(PLAN.none);
  const ps = await spendTo(tn, 4);
  await age(tn, ps[0], "2 years");
  await age(tn, ps[1], "1 year 1 day");
  await age(tn, ps[2], "10 days");

  const n1 = await sweep();
  assert(n1 >= 1, `the first run removed the 2-year-old row (${n1})`);
  const kept = await ledger(tn.t);
  assertEquals(kept.length, 3);
  assertEquals(await sweep(), 0, "the second run finds nothing");
  assertEquals(await ledger(tn.t), kept, "…and touches nothing");
  const twice = await sql.begin(async (t) => {
    await t.unsafe("set local role rf_maintenance");
    const [a] = await t.unsafe(`select ${SWEEP} as n`);
    const [b] = await t.unsafe(`select ${SWEEP} as n`);
    return [a.n, b.n];
  });
  assertEquals(twice, [0, 0], "twice in one transaction: nothing, twice");
  assertEquals(await ledger(tn.t), kept);

  // Overlap: the first run holds its deleted rows' locks until it commits; the second waits on them.
  const tc = await tenant(PLAN.none);
  const qs = await spendTo(tc, 3);
  for (const q of qs) await age(tc, q, "2 years");
  const before = await total();
  let swept!: () => void;
  const didSweep = new Promise<void>((r) => (swept = r));
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  const first = sql.begin(async (t) => {
    await t.unsafe("set local role rf_maintenance");
    const [r] = await t.unsafe(`select ${SWEEP} as n`);
    swept();
    await gate; // hold the transaction (and the row locks) open
    return r.n as number;
  });
  await didSweep;
  const second = sweep();
  let waiting = 0;
  for (let i = 0; i < 100 && waiting === 0; i++) {
    const [w] = await sql`select count(*)::int as n from pg_stat_activity
      where datname = current_database() and wait_event_type = 'Lock'
        and query ilike '%sweep_seat_grants%'`;
    waiting = w.n as number;
    if (waiting === 0) await new Promise((r) => setTimeout(r, 20));
  }
  assertEquals(waiting, 1, "the second run is WAITING on the first's rows");
  release();
  const [a, b] = [await first, await second];
  assert(a >= 3, `the first run took this tenant's three old rows (${a})`);
  assertEquals(b, 0, "the second, once the first commits, finds them gone and counts none");
  assertEquals(before - (await total()), a + b, "together: exactly the rows that left");
  assertEquals(await grants(tc.t), 0);
});
