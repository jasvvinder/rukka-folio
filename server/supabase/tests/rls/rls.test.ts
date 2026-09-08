// Hostile-query suite against a real Postgres with the migrations applied (03 §2.5 🔒; ADR 05c §7;
// ADR 05d §2). Needs RF_TEST_DB_URL (a superuser/owner connection to a `supabase db reset` database,
// e.g. postgresql://postgres:postgres@127.0.0.1:54322/postgres). Without it every test is SKIPPED and
// says why — the push lane has no Docker; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database
// fails loudly instead. Ids E-03-22 … E-03-27, E-05c-7 (claims isolation).
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — rls.test.ts needs a Postgres with the migrations applied (supabase db reset); Docker is not available on this runner";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP rls.test.ts: ${why}`);
}
const ignore = !url;

type Sql = postgres.Sql;
let sql: Sql;
interface Fixture {
  tenantA: string;
  tenantB: string;
  alice: string; // certified admin in A
  bob: string; // certified member in A (viewer on the book)
  carol: string; // certified member in B
  dave: string; // registered-only (OTP done, no cert) in A
  erin: string; // erased owner of a personal book in A
  dev: Record<string, string>;
  bookA: string;
  bookB: string;
  personalErin: string;
  envA: string;
  envB: string;
  envErin: string;
}
let fx: Fixture;

async function asApi<T>(
  user: string | null,
  device: string | null,
  fn: (s: postgres.TransactionSql) => Promise<T>,
): Promise<T> {
  return await sql.begin(async (s) => {
    await s`set local role rf_api`;
    await s`select rf.set_claims(${user}::uuid, ${device}::uuid)`;
    return await fn(s);
  }) as T;
}
async function asMaint<T>(fn: (s: postgres.TransactionSql) => Promise<T>): Promise<T> {
  return await sql.begin(async (s) => {
    await s`set local role rf_maintenance`;
    return await fn(s);
  }) as T;
}
async function pgCode(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "ok";
  } catch (e) {
    return (e as { code?: string }).code ?? "unknown";
  }
}

async function seed(): Promise<Fixture> {
  const b = (n: number, fill: number) => new Uint8Array(n).fill(fill);
  const [ta] = await sql`insert into tenants (type) values ('family') returning id`;
  const [tb] = await sql`insert into tenants (type) values ('family') returning id`;
  const mk = async (fill: number) =>
    (await sql`insert into users (phone_hmac, phone_ct) values (${b(32, fill)}, ${
      b(40, fill)
    }) returning id`)[0].id as string;
  const alice = await mk(1),
    bob = await mk(2),
    carol = await mk(3),
    dave = await mk(4),
    erin = await mk(5);
  await sql`update users set erased_at = now(), phone_ct = null, phone_hmac = null where id = ${erin}`;
  await sql`insert into memberships (tenant_id, user_id, status) values
    (${ta.id}, ${alice}, 'active'), (${ta.id}, ${bob}, 'active'), (${tb.id}, ${carol}, 'active'), (${ta.id}, ${dave}, 'active'), (${ta.id}, ${erin}, 'removed')`;
  const dev: Record<string, string> = {};
  for (
    const [name, user, status] of [
      ["alice", alice, "certified"],
      ["bob", bob, "certified"],
      ["carol", carol, "certified"],
      ["dave", dave, "registered"],
      ["erin", erin, "certified"],
    ] as const
  ) {
    const [d] = await sql`insert into devices (user_id, pub_ed, pub_x, status) values (${user}, ${
      b(32, 9)
    }, ${b(32, 8)}, ${status}) returning id`;
    dev[name] = d.id;
  }
  const bookA = crypto.randomUUID(),
    bookB = crypto.randomUUID(),
    personalErin = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type) values (${bookA}, ${ta.id}, 'family'), (${bookB}, ${tb.id}, 'family')`;
  await sql`insert into books (id, tenant_id, type, owner_user_id) values (${personalErin}, ${ta.id}, 'personal', ${erin})`;
  await sql`insert into book_roles (book_id, user_id, role) values (${bookA}, ${alice}, 'admin'), (${bookA}, ${bob}, 'viewer'), (${bookB}, ${carol}, 'admin'), (${personalErin}, ${erin}, 'admin')`;
  const env = async (book: string, tenant: string, device: string) => {
    const id = crypto.randomUUID();
    await sql`insert into envelopes (envelope_id, tenant_id, book_id, object_id, object_type, key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
      values (${id}, ${tenant}, ${book}, ${crypto.randomUUID()}, 'entry', 1, 1, 1, ${device}, 1, ${
      b(32, 3)
    }, 4, ${b(4, 1)})`;
    return id;
  };
  return {
    tenantA: ta.id,
    tenantB: tb.id,
    alice,
    bob,
    carol,
    dave,
    erin,
    dev,
    bookA,
    bookB,
    personalErin,
    envA: await env(bookA, ta.id, dev.alice),
    envB: await env(bookB, tb.id, dev.carol),
    envErin: await env(personalErin, ta.id, dev.erin),
  };
}

Deno.test({
  name: "E-03-22 setup: migrations applied, roles exist, store_epoch seeded",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    const roles =
      await sql`select rolname from pg_roles where rolname in ('rf_api','rf_maintenance')`;
    assertEquals(roles.length, 2);
    await sql`insert into store_epoch (id) values (true) on conflict do nothing`;
    fx = await seed();
  },
});

Deno.test({
  name:
    "E-03-23 cross-tenant: a certified admin of A sees nothing of B — envelopes, memberships, books, roles, devices",
  ignore,
  async fn() {
    const r = await asApi(fx.alice, fx.dev.alice, async (s) => ({
      env: await s`select envelope_id from envelopes where book_id = ${fx.bookB}`,
      envAll: await s`select envelope_id from envelopes`,
      mem: await s`select * from memberships where tenant_id = ${fx.tenantB}`,
      books: await s`select id from books where tenant_id = ${fx.tenantB}`,
      roles: await s`select * from book_roles where book_id = ${fx.bookB}`,
      devs: await s`select id from devices where user_id = ${fx.carol}`,
      own: await s`select envelope_id from envelopes where book_id = ${fx.bookA}`,
    }));
    assertEquals(r.env.length, 0);
    assertEquals(r.mem.length, 0);
    assertEquals(r.books.length, 0);
    assertEquals(r.roles.length, 0);
    assertEquals(r.devs.length, 0);
    assertEquals(r.own.map((x) => x.envelope_id), [fx.envA]);
    assertEquals(r.envAll.map((x) => x.envelope_id), [fx.envA], "only the book I hold a role on");
    // and B's envelope cannot be inserted into from A's session either
    const code = await pgCode(
      asApi(
        fx.alice,
        fx.dev.alice,
        (s) =>
          s`insert into envelopes (envelope_id, tenant_id, book_id, object_id, object_type, key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
        values (${crypto.randomUUID()}, ${fx.tenantB}, ${fx.bookB}, ${crypto.randomUUID()}, 'entry', 1, 1, 1, ${fx.dev.alice}, 1, ${new Uint8Array(
            32,
          )}, 1, ${new Uint8Array(1)})`,
      ),
    );
    assertEquals(code, "42501");
  },
});

Deno.test({
  name: "E-03-24 OTP-only (registered, uncertified) device sees nothing but itself (ADR 05d §2)",
  ignore,
  async fn() {
    const r = await asApi(fx.dave, fx.dev.dave, async (s) => ({
      mem: await s`select * from memberships`,
      roles: await s`select * from book_roles`,
      books: await s`select * from books`,
      tenants: await s`select * from tenants`,
      devs: await s`select id from devices`,
      users: await s`select id from users`,
      ver: await s`select * from verification_events`,
      env: await s`select * from envelopes`,
      recs: await s`select * from signed_records`,
    }));
    assertEquals(r.mem.length, 0, "not even its own membership row");
    assertEquals(r.roles.length, 0);
    assertEquals(r.books.length, 0);
    assertEquals(r.tenants.length, 0);
    assertEquals(r.devs.map((d) => d.id), [fx.dev.dave]);
    assertEquals(r.users.map((u) => u.id), [fx.dave]);
    assertEquals(r.ver.length, 0);
    assertEquals(r.env.length, 0);
    assertEquals(r.recs.length, 0);
  },
});

Deno.test({
  name:
    "E-03-25 append-only: UPDATE/DELETE on envelopes fail for rf_api (no grant) and UPDATE fails for maintenance; shared-book DELETE raises even for maintenance",
  ignore,
  async fn() {
    assertEquals(
      await pgCode(
        asApi(
          fx.alice,
          fx.dev.alice,
          (s) => s`update envelopes set size = 5 where envelope_id = ${fx.envA}`,
        ),
      ),
      "42501",
    );
    assertEquals(
      await pgCode(
        asApi(
          fx.alice,
          fx.dev.alice,
          (s) => s`delete from envelopes where envelope_id = ${fx.envA}`,
        ),
      ),
      "42501",
    );
    assertEquals(
      await pgCode(
        asApi(fx.alice, fx.dev.alice, (s) => s`update signed_records set kind = 'designation'`),
      ),
      "42501",
    );
    assertEquals(
      await pgCode(asApi(fx.alice, fx.dev.alice, (s) => s`delete from signed_records`)),
      "42501",
    );
    assertEquals(
      await pgCode(asMaint((s) => s`update envelopes set size = 5 where envelope_id = ${fx.envA}`)),
      "42501",
    );
    // maintenance DELETE of a shared-book envelope: the 0003 trigger raises append_only (P0001)
    assertEquals(
      await pgCode(asMaint((s) => s`delete from envelopes where envelope_id = ${fx.envA}`)),
      "P0001",
    );
    const [{ n }] = await sql`select count(*)::int as n from envelopes`;
    assertEquals(n, 3, "nothing deleted");
  },
});

Deno.test({
  name: "E-03-26 maintenance deletion is exactly the erased owner's personal-book envelopes",
  ignore,
  async fn() {
    // a personal book whose owner is NOT erased: refused
    const [live] = await sql`insert into users (phone_hmac, phone_ct) values (${
      new Uint8Array(32).fill(7)
    }, ${new Uint8Array(40)}) returning id`;
    const pb = crypto.randomUUID();
    await sql`insert into books (id, tenant_id, type, owner_user_id) values (${pb}, ${fx.tenantA}, 'personal', ${live.id})`;
    const [d] =
      await sql`insert into devices (user_id, pub_ed, pub_x, status) values (${live.id}, ${new Uint8Array(
        32,
      )}, ${new Uint8Array(32)}, 'certified') returning id`;
    const liveEnv = crypto.randomUUID();
    await sql`insert into envelopes (envelope_id, tenant_id, book_id, object_id, object_type, key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
      values (${liveEnv}, ${fx.tenantA}, ${pb}, ${crypto.randomUUID()}, 'entry', 1, 1, 1, ${d.id}, 1, ${new Uint8Array(
      32,
    )}, 1, ${new Uint8Array(1)})`;
    assertEquals(
      await pgCode(asMaint((s) => s`delete from envelopes where envelope_id = ${liveEnv}`)),
      "P0001",
    );
    // erased owner's personal book: allowed
    const deleted = await asMaint((s) =>
      s`delete from envelopes where envelope_id = ${fx.envErin} returning envelope_id`
    );
    assertEquals(deleted.length, 1);
    // rf_api cannot call maintenance-only functions
    assertEquals(
      await pgCode(asApi(fx.alice, fx.dev.alice, (s) => s`select rf.bump_store_epoch('x')`)),
      "42501",
    );
    assertEquals(
      await pgCode(asApi(fx.alice, fx.dev.alice, (s) => s`select rf.purge_ephemeral_auth()`)),
      "42501",
    );
  },
});

Deno.test({
  name:
    "E-03-27 insert policy: author_device must be the claim's device; viewer cannot insert; phone columns are unreadable through claims; projections need a record",
  ignore,
  async fn() {
    const ins = (user: string, device: string, author: string) =>
      asApi(
        user,
        device,
        (s) =>
          s`insert into envelopes (envelope_id, tenant_id, book_id, object_id, object_type, key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
          values (${crypto.randomUUID()}, ${fx.tenantA}, ${fx.bookA}, ${crypto.randomUUID()}, 'entry', 1, 1, 1, ${author}, 1, ${new Uint8Array(
            32,
          )}, 1, ${new Uint8Array(1)})`,
      );
    assertEquals(
      await pgCode(ins(fx.alice, fx.dev.alice, fx.dev.bob)),
      "42501",
      "author ≠ jwt device",
    );
    assertEquals(await pgCode(ins(fx.bob, fx.dev.bob, fx.dev.bob)), "42501", "viewer");
    assertEquals(await pgCode(ins(fx.alice, fx.dev.alice, fx.dev.alice)), "ok");
    assertEquals(
      await pgCode(
        asApi(fx.alice, fx.dev.alice, (s) => s`select phone_ct from users where id = ${fx.alice}`),
      ),
      "42501",
    );
    assertEquals(
      await pgCode(asApi(fx.alice, fx.dev.alice, (s) => s`select phone_hmac from users`)),
      "42501",
    );
    assertEquals(
      await pgCode(
        asApi(
          fx.alice,
          fx.dev.alice,
          (s) =>
            s`insert into memberships (tenant_id, user_id, status) values (${fx.tenantA}, ${fx.carol}, 'active')`,
        ),
      ),
      "42501",
    );
    assertEquals(
      await pgCode(
        asApi(
          fx.alice,
          fx.dev.alice,
          (s) =>
            s`select rf.project_membership(${crypto.randomUUID()}, ${fx.tenantA}, ${fx.carol}, 'active')`,
        ),
      ),
      "P0001",
      "no record → no row",
    );
  },
});

Deno.test({
  name:
    "E-05c-7 pooled-connection claims isolation: SET LOCAL dies with the transaction; a second transaction on the same connection sees no claims",
  ignore,
  async fn() {
    await asApi(fx.alice, fx.dev.alice, async (s) => {
      const [r] = await s`select rf.user_id() as u`;
      assertEquals(r.u, fx.alice);
    });
    const [after] = await sql`select rf.user_id() as u, rf.device_id() as d, current_user as who`;
    assertEquals(after.u, null);
    assertEquals(after.d, null);
    assert(after.who !== "rf_api", "role reset with the transaction too");
    const rows = await asApi(null, null, (s) => s`select envelope_id from envelopes`);
    assertEquals(rows.length, 0, "no claims → no rows");
    // two interleaved transactions on one pooled connection: each sees only its own claim (ADR 05c §7)
    const seen = await asApi(fx.carol, fx.dev.carol, (s) => s`select envelope_id from envelopes`);
    assertEquals(seen.map((x) => x.envelope_id), [fx.envB]);
    const seenA = await asApi(fx.alice, fx.dev.alice, (s) => s`select envelope_id from envelopes`);
    assert(
      !seenA.some((x) => x.envelope_id === fx.envB),
      "carol's claim did not leak into alice's transaction",
    );
    await sql.end();
  },
});
