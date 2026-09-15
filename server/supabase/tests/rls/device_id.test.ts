// E-06-42 🔒 — ADR 2026-09-16 §2, §6: one device, one id, minted by the client's ledger and only
// RECORDED by the server. Proved against a real Postgres, because the thing that now stops one
// device registering under another's id is a database constraint (the primary key on `devices.id`),
// not a check in an edge function — and an edge function is just another client to RLS.
//
// Two halves, both hostile:
//   (1) a device registered under an id the CLIENT chose still reads only its own row — a chosen id
//       buys no read beyond ADR 2026-09-05d §2, because the JWT's device_id claim is issued by
//       /token from the row whose pub_ed verified the signed challenge (rf.device_auth_row), never
//       from anything the client says about itself;
//   (2) an id already held cannot be taken — `rf.register_device` refuses with `device_id_taken`,
//       rf_api has no INSERT on devices at all, and a duplicate insert fails on the primary key.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — device_id.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP device_id.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
const bytes = (n: number, fill: number) => new Uint8Array(n).fill(fill);

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
async function pgErr(p: Promise<unknown>): Promise<{ code: string; message: string }> {
  try {
    await p;
    return { code: "ok", message: "" };
  } catch (e) {
    const x = e as { code?: string; message?: string };
    return { code: x.code ?? "unknown", message: x.message ?? "" };
  }
}

interface Fx {
  tenant: string;
  holder: string; // owns the chosen id
  stranger: string; // another user, another tenant
  holderDev: string; // the id the holder's ledger minted
  strangerDev: string; // the id the stranger's ledger minted
  book: string;
  env: string;
}
let fx: Fx;

const register = (device: string, user: string, ed: number, x: number) =>
  sql`select rf.register_device(${device}::uuid, ${user}::uuid, ${bytes(32, ed)}, ${
    bytes(32, x)
  }, null, null, null) as id`;

Deno.test({
  name: "E-06-42 setup: two ledgers mint their own device ids; the server records them",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    const [t] = await sql`insert into tenants (type) values ('family') returning id`;
    const [t2] = await sql`insert into tenants (type) values ('business_group') returning id`;
    const mk = async (fill: number) =>
      (await sql`insert into users (phone_hmac, phone_ct) values (${bytes(32, fill)}, ${
        bytes(40, fill)
      }) returning id`)[0].id as string;
    const holder = await mk(41), stranger = await mk(42);
    for (const [tenant, user] of [[t.id, holder], [t2.id, stranger]] as const) {
      await sql`insert into memberships (tenant_id, user_id, status) values (${tenant}, ${user}, 'active')`;
    }
    // The ids the ledgers minted at first run (ADR 2026-09-16 §1) — the server never sees them first.
    const holderDev = crypto.randomUUID(), strangerDev = crypto.randomUUID();
    const [a] = await register(holderDev, holder, 1, 2);
    const [b] = await register(strangerDev, stranger, 3, 4);
    assertEquals(a.id, holderDev, "the row carries the client's id");
    assertEquals(b.id, strangerDev);
    const rows =
      await sql`select id, user_id from devices where id in (${holderDev}, ${strangerDev})`;
    assertEquals(rows.length, 2);
    await sql`update devices set status = 'certified' where id in (${holderDev}, ${strangerDev})`;
    const book = crypto.randomUUID(); // client-minted UUIDv7 (03 §1)
    await sql`insert into books (id, tenant_id, type) values (${book}, ${t.id}, 'family')`;
    await sql`insert into book_roles (book_id, user_id, role) values (${book}, ${holder}, 'admin')`;
    const envId = crypto.randomUUID();
    await sql`insert into envelopes (envelope_id, tenant_id, book_id, object_id, object_type,
      key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
      values (${envId}, ${t.id}, ${book}, ${crypto.randomUUID()}, 'entry', 1, 1, 1, ${holderDev},
      1, ${bytes(32, 7)}, 4, ${bytes(4, 1)})`;
    fx = {
      tenant: t.id,
      holder,
      stranger,
      holderDev,
      strangerDev,
      book,
      env: envId,
    };
  },
});

Deno.test({
  name:
    "E-06-42 a device registered under a client-chosen id reads only its own row — no tenant, book or envelope of anyone else",
  ignore,
  async fn() {
    const r = await asApi(fx.stranger, fx.strangerDev, async (s) => ({
      devs: await s`select id from devices`,
      holderDev: await s`select id from devices where id = ${fx.holderDev}`,
      certs: await s`select device_id from device_certs where device_id = ${fx.holderDev}`,
      books: await s`select id from books where tenant_id = ${fx.tenant}`,
      envs: await s`select envelope_id from envelopes`,
      mems: await s`select user_id from memberships where tenant_id = ${fx.tenant}`,
    }));
    assertEquals(r.devs.map((x) => x.id), [fx.strangerDev], "its own row and nothing else");
    assertEquals(r.holderDev.length, 0);
    assertEquals(r.certs.length, 0);
    assertEquals(r.books.length, 0);
    assertEquals(r.envs.length, 0);
    assertEquals(r.mems.length, 0);
    // Claiming somebody else's device id in the claims buys nothing either: rf.is_certified()
    // requires the row's user_id to match, so every tenant-scoped policy still closes. (The real
    // JWT cannot say this at all — /token issues device_id from rf.device_auth_row.)
    const stolen = await asApi(fx.stranger, fx.holderDev, async (s) => ({
      envs: await s`select envelope_id from envelopes`,
      books: await s`select id from books`,
      mems: await s`select user_id from memberships where tenant_id = ${fx.tenant}`,
    }));
    assertEquals(stolen.envs.length, 0);
    assertEquals(stolen.books.length, 0);
    assertEquals(stolen.mems.length, 0);
  },
});

Deno.test({
  name:
    "E-06-42 an id already held cannot be taken: device_id_taken from rf.register_device, no INSERT for rf_api, duplicate refused by the primary key",
  ignore,
  async fn() {
    // Another user under the holder's id.
    const other = await pgErr(register(fx.holderDev, fx.stranger, 5, 6));
    assertEquals(other.code, "P0001");
    assertEquals(other.message.split(/\s/)[0], "device_id_taken");
    // The same user under a different key pair: still taken — the id names the key pair (04 §3.4).
    const rekey = await pgErr(register(fx.holderDev, fx.holder, 9, 9));
    assertEquals(rekey.code, "P0001");
    assertEquals(rekey.message.split(/\s/)[0], "device_id_taken");
    // Same user, same keys, live row: idempotent, and no second row (06 §5 reinstall).
    const [same] = await register(fx.holderDev, fx.holder, 1, 2);
    assertEquals(same.id, fx.holderDev);
    const mine = await sql`select id from devices where user_id = ${fx.holder}`;
    assertEquals(mine.map((x) => x.id), [fx.holderDev]);
    // rf_api cannot write the table at all: registration is only ever the definer function.
    const direct = await pgErr(asApi(
      fx.stranger,
      fx.strangerDev,
      (s) =>
        s`insert into devices (id, user_id, pub_ed, pub_x, status)
          values (${fx.holderDev}, ${fx.stranger}, ${bytes(32, 5)}, ${bytes(32, 6)}, 'certified')`,
    ));
    assertEquals(direct.code, "42501");
    // And even with the table owner's own privileges the primary key refuses the duplicate — that
    // constraint is the whole defence now that the id comes from the client.
    const dup = await pgErr(
      sql`insert into devices (id, user_id, pub_ed, pub_x, status)
        values (${fx.holderDev}, ${fx.stranger}, ${bytes(32, 5)}, ${bytes(32, 6)}, 'certified')`,
    );
    assertEquals(dup.code, "23505");
  },
});

Deno.test({
  name:
    "E-06-42 structural: devices.id has no default and the id-less register_device overload is gone",
  ignore,
  async fn() {
    const [col] = await sql`select column_default, is_nullable from information_schema.columns
      where table_schema = 'public' and table_name = 'devices' and column_name = 'id'`;
    assertEquals(col.column_default, null, "no server path mints a device id");
    assertEquals(col.is_nullable, "NO");
    const stale = await pgErr(
      sql`select rf.register_device(${fx.holder}::uuid, ${bytes(32, 1)}, ${
        bytes(32, 2)
      }, null, null, null)`,
    );
    assertEquals(stale.code, "42883", "a caller that has not been updated fails at bind time");
    const overloads =
      await sql`select count(*)::int as n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'rf' and p.proname = 'register_device'`;
    assertEquals(overloads[0].n, 1);
    assert(fx.env.length > 0);
    await sql.end();
  },
});
