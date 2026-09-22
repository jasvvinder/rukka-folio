// Hostile-query suite for the entitlement token's write path — migration 0014, against 08 §3 🔒
// (line 35's token), 03 §2.4 🔒, ADR 2026-09-05g §1, §2, §5, ADR 2026-09-05d §2 🔒 and CLAUDE.md
// rule 2.
//
// What an attacker wants from this table, and what each test denies:
//
//   * A FORGED ENTITLEMENT — writing one's own `entitlement_tokens` row. rf_api holds SELECT and
//     nothing else; INSERT, UPDATE and DELETE are refused by privilege, not by policy, because
//     there is no grant to have a policy about (E-03-71, E-03-73). Even the one write path takes
//     an already-signed opaque token, never a plan or a limit: the signing key lives only at the
//     edge, so a compromised API role has nothing to sign with.
//   * ANOTHER TENANT'S token — it names their plan, their period end and their seat count.
//     0005's `entitlement_select` scopes reads to `rf.active_in_tenant`; the mint re-checks the
//     same predicate rather than trusting the caller's word for which tenant it is writing for
//     (E-03-72).
//   * A TOKEN FOR A DEVICE THE SERVER DOES NOT TRUST — ADR 2026-09-05d §2 🔒 is certified-only, and
//     `rf.active_in_tenant` carries `rf.is_certified()` inside it (E-03-72).
//   * ANY SIGHT OF FINANCIAL CONTENT — the mint path must not read `envelopes`, `wrapped_keys` or
//     any blob (E-03-74, asserted off `prosrc` exactly as E-03-70 does for the billing path).
//   * CURSOR CHURN / UNBOUNDED GROWTH — one row per tenant, replaced in place, with `created_at`
//     moved so the re-mint rule terminates and `updated_at` moved so 05 §5's cursor carries the
//     new token to every device (E-03-74).
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-03-71 … E-03-74.
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — entitlement_tokens.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP entitlement_tokens.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
const DAY = 86400e3;
const bytes = (n: number, fill: number) => new Uint8Array(n).fill(fill);
/** Stand-in for a signed token: this suite is about WHO may write one, never about its contents —
 *  Postgres is content-blind about the token exactly as it is about an envelope blob. */
const fakeToken = (fill: number) => bytes(120, fill);

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
interface PgErr {
  code: string;
  message: string;
  detail: string;
}
async function pgErr(p: Promise<unknown>): Promise<PgErr> {
  try {
    await p;
    return { code: "ok", message: "", detail: "" };
  } catch (e) {
    const x = e as { code?: string; message?: string; detail?: string };
    return { code: x.code ?? "unknown", message: x.message ?? "", detail: x.detail ?? "" };
  }
}
const pgCode = async (p: Promise<unknown>) => (await pgErr(p)).code;

/** The one call sync-meta makes, through the role it actually runs as. */
function mint(
  user: string | null,
  device: string | null,
  tenant: string,
  token: Uint8Array,
  expires: Date,
): Promise<unknown> {
  return asApi(
    user,
    device,
    (s) =>
      s`select rf.mint_entitlement_token(${tenant}::uuid, ${token}::bytea, ${expires}::timestamptz)`,
  );
}

interface Fx {
  t1: string;
  t2: string;
  t3: string;
  owner: string; // certified, active in t1
  outsider: string; // certified, active in t2 only
  /** REGISTERED, not certified — and the founding, active member of t3. 06 §7's membership guard
   *  lets only a founding member reach `active` without a ceremony, so an uncertified device gets
   *  its own tenant rather than a second seat in t1. */
  pending: string;
  dev: Record<string, string>;
}
let fx: Fx;

/** Fresh tenants, users and devices for this file. Fills 0xd1+ (billing_apply.test.ts owns
 *  0xc1–0xc2, umk_public_x.test.ts owns 0xb1–0xb4). */
async function seed(): Promise<Fx> {
  const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
  const [t2] = await sql`insert into tenants (type) values ('business_group') returning id`;
  const [t3] = await sql`insert into tenants (type) values ('family') returning id`;
  const mk = async (fill: number) => {
    const [u] = await sql`insert into users (phone_hmac, phone_ct)
      values (${bytes(32, fill)}, ${bytes(40, fill)}) returning id`;
    return u.id as string;
  };
  const owner = await mk(0xd1), outsider = await mk(0xd2), pending = await mk(0xd3);
  const dev: Record<string, string> = {};
  for (
    const [name, user, status] of [
      ["owner", owner, "certified"],
      ["outsider", outsider, "certified"],
      ["pending", pending, "registered"],
    ] as const
  ) {
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${user}, ${bytes(32, 6)}, ${bytes(32, 7)}, ${status})
      returning id`;
    dev[name] = d.id;
  }
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${owner}, 'active'), (${t2.id}, ${outsider}, 'active'),
           (${t3.id}, ${pending}, 'active')`;
  await sql`insert into subscriptions (tenant_id) values (${t1.id}), (${t2.id}), (${t3.id})`;
  return { t1: t1.id, t2: t2.id, t3: t3.id, owner, outsider, pending, dev };
}
const rowFor = (t: string) =>
  sql`select * from entitlement_tokens where tenant_id = ${t}`.then((r) => r[0] as postgres.Row);

Deno.test({
  name:
    "E-03-71 0014's shape: entitlement_tokens holds at most ONE row per tenant, rf.mint_entitlement_token is SECURITY DEFINER granted to rf_api and revoked from public, and rf_api's privilege on the table is still SELECT and only SELECT (CLAUDE.md rule 2, 08 §3 🔒)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();

    const uq = await sql<{ indexdef: string }[]>`
      select indexdef from pg_indexes
      where tablename = 'entitlement_tokens' and indexdef ilike '%unique%'`;
    assert(
      uq.some((i) => /\(tenant_id\)/.test(i.indexdef)),
      `one current token per tenant is enforced by the database, not by the handler: ${
        JSON.stringify(uq)
      }`,
    );

    const [fn] = await sql<{ prosecdef: boolean; acl: string | null }[]>`
      select p.prosecdef, array_to_string(p.proacl, ',') as acl
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname = 'mint_entitlement_token'`;
    assert(fn, "rf.mint_entitlement_token exists");
    assert(fn.prosecdef, "SECURITY DEFINER: rf_api holds no write privilege on the table");
    assert(
      (fn.acl ?? "").includes("rf_api=X"),
      `EXECUTE is granted to rf_api: ${fn.acl}`,
    );
    assert(
      !/(^|,)=X/.test(fn.acl ?? ""),
      `PUBLIC holds no EXECUTE — 0005's blanket grant ran before this function existed: ${fn.acl}`,
    );

    const privs = await sql<{ privilege_type: string }[]>`
      select privilege_type from information_schema.table_privileges
      where grantee = 'rf_api' and table_name = 'entitlement_tokens'`;
    assertEquals(
      privs.map((p) => p.privilege_type).sort(),
      ["SELECT"],
      "no INSERT, no UPDATE, no DELETE on entitlement_tokens for the API role",
    );
    // …and the same for rf_maintenance: retention sweeps the ledger, not the plan state.
    const maint = await sql<{ privilege_type: string }[]>`
      select privilege_type from information_schema.table_privileges
      where grantee = 'rf_maintenance' and table_name = 'entitlement_tokens'`;
    assertEquals(maint.map((p) => p.privilege_type).sort(), []);
  },
});

Deno.test({
  name:
    "E-03-72 cross-tenant and uncertified 🔒 (ADR 2026-09-05d §2, 05 §5): a token is minted only for a tenant the CERTIFIED caller is active in, and another tenant's device can neither read it nor mint one for it",
  ignore,
  async fn() {
    const exp = new Date(Date.now() + 30 * DAY);

    // The happy path first, so the refusals below are refusals and not a broken call.
    await mint(fx.owner, fx.dev.owner, fx.t1, fakeToken(0x11), exp);
    const mine = await asApi(
      fx.owner,
      fx.dev.owner,
      (s) => s`select tenant_id from entitlement_tokens`,
    );
    assertEquals(mine.map((r) => r.tenant_id), [fx.t1], "the owner sees exactly their own token");

    // A certified device of ANOTHER tenant: reads nothing, and cannot mint for t1.
    const theirs = await asApi(
      fx.outsider,
      fx.dev.outsider,
      (s) => s`select * from entitlement_tokens where tenant_id = ${fx.t1}`,
    );
    assertEquals(theirs.length, 0, "tenant B's device never receives tenant A's token");
    const e1 = await pgErr(mint(fx.outsider, fx.dev.outsider, fx.t1, fakeToken(0x22), exp));
    assertEquals(e1.code, "42501");
    assert(/not_entitled/.test(e1.message), `named refusal, never a silent no-op: ${e1.message}`);
    // …and nothing moved.
    assertEquals(
      Array.from((await rowFor(fx.t1)).token as Uint8Array).slice(0, 4),
      [0x11, 0x11, 0x11, 0x11],
      "the refused mint did not overwrite tenant A's token",
    );

    // Claimless rf_api — the shape a webhook or a cron connection has.
    const anon = await asApi(null, null, (s) => s`select * from entitlement_tokens`);
    assertEquals(anon.length, 0);
    assertEquals(await pgCode(mint(null, null, fx.t1, fakeToken(0x33), exp)), "42501");

    // An ACTIVE member of its OWN tenant on an UNCERTIFIED device: 05d §2 🔒 is certified-only, so
    // membership alone buys nothing — no read, and no mint even for the tenant it founded.
    const pendingRead = await asApi(
      fx.pending,
      fx.dev.pending,
      (s) => s`select * from entitlement_tokens`,
    );
    assertEquals(pendingRead.length, 0, "an uncertified device reads no entitlement at all");
    assertEquals(
      await pgCode(mint(fx.pending, fx.dev.pending, fx.t3, fakeToken(0x44), exp)),
      "42501",
      "and none is minted for it — a token is an entitlement statement, not a greeting",
    );
    assertEquals(
      (await sql`select count(*)::int as n from entitlement_tokens where tenant_id = ${fx.t3}`)[0]
        .n,
      0,
    );

    // A tenant that exists but has no membership for the caller at all.
    assertEquals(await pgCode(mint(fx.owner, fx.dev.owner, fx.t2, fakeToken(0x55), exp)), "42501");
    assertEquals(
      (await sql`select count(*)::int as n from entitlement_tokens where tenant_id = ${fx.t2}`)[0]
        .n,
      0,
    );
  },
});

Deno.test({
  name:
    "E-03-73 no forged entitlement: the API role cannot INSERT, UPDATE or DELETE entitlement_tokens by any route, and the one write path refuses a token that is empty, oversized or already expired",
  ignore,
  async fn() {
    const exp = new Date(Date.now() + 30 * DAY);
    for (
      const q of [
        () =>
          asApi(
            fx.owner,
            fx.dev.owner,
            (s) =>
              s`insert into entitlement_tokens (tenant_id, token, expires_at)
                values (${fx.t1}, ${fakeToken(0x66)}::bytea, ${exp}::timestamptz)`,
          ),
        () =>
          asApi(
            fx.owner,
            fx.dev.owner,
            (s) =>
              s`update entitlement_tokens set expires_at = ${new Date(Date.now() + 3650 * DAY)}`,
          ),
        () =>
          asApi(
            fx.owner,
            fx.dev.owner,
            (s) => s`update entitlement_tokens set token = ${fakeToken(0x77)}::bytea`,
          ),
        () => asApi(fx.owner, fx.dev.owner, (s) => s`delete from entitlement_tokens`),
        () =>
          asApi(
            fx.owner,
            fx.dev.owner,
            (s) => s`delete from entitlement_tokens where tenant_id = ${fx.t1}`,
          ),
      ]
    ) {
      assertEquals(await pgCode(q()), "42501", "insufficient_privilege");
    }
    assertEquals(
      Array.from((await rowFor(fx.t1)).token as Uint8Array).slice(0, 2),
      [0x11, 0x11],
      "not one of those touched the stored token",
    );

    // The write path itself refuses what cannot be a token, rather than storing it.
    assertEquals(
      await pgCode(mint(fx.owner, fx.dev.owner, fx.t1, new Uint8Array(0), exp)),
      "22023",
    );
    assertEquals(
      await pgCode(mint(fx.owner, fx.dev.owner, fx.t1, bytes(5000, 1), exp)),
      "22023",
    );
    assertEquals(
      await pgCode(
        mint(fx.owner, fx.dev.owner, fx.t1, fakeToken(0x88), new Date(Date.now() - DAY)),
      ),
      "22023",
      "an already-expired token would be re-minted on the very next pull, forever",
    );
  },
});

Deno.test({
  name:
    "E-03-74 one row per tenant, replaced in place with created_at and updated_at moved (05 §5's cursor), and the mint path is content-blind: no statement in rf.mint_entitlement_token names envelopes, blobs, wrapped keys or attachments (06 §10 🔒, 08 §5)",
  ignore,
  async fn() {
    const before = await rowFor(fx.t1);
    const exp2 = new Date(Date.now() + 29 * DAY);
    await mint(fx.owner, fx.dev.owner, fx.t1, fakeToken(0x99), exp2);

    const after = await rowFor(fx.t1);
    const [{ n }] = await sql<{ n: number }[]>`
      select count(*)::int as n from entitlement_tokens where tenant_id = ${fx.t1}`;
    assertEquals(n, 1, "a re-mint REPLACES: a second row would churn 05 §5's cursor forever");
    assertEquals(
      after.id,
      before.id,
      "…and keeps the row's id, so the client updates rather than adds",
    );
    assertEquals(Array.from(after.token as Uint8Array).slice(0, 2), [0x99, 0x99]);
    assert(
      (after.created_at as Date).getTime() >= (before.created_at as Date).getTime(),
      "created_at is when THIS token was minted — the re-mint rule compares it with subscriptions.updated_at, so leaving it behind would re-mint on every pull forever",
    );
    assert(
      (after.updated_at as Date).getTime() >= (before.updated_at as Date).getTime(),
      "the 0004 touch trigger moved the cursor: a token no device can pull is no token",
    );

    // Content-blindness, read off the function's own source rather than inferred from a row count.
    const [src] = await sql<{ prosrc: string }[]>`
      select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname = 'mint_entitlement_token'`;
    for (
      const forbidden of [
        "envelopes",
        "blob",
        "attachments",
        "wrapped_keys",
        "signed_records",
        "book_usage",
        "phone_ct",
        "phone_hmac",
      ]
    ) {
      assert(
        !new RegExp(`\\b${forbidden}\\b`).test(src.prosrc),
        `the mint path must not name ${forbidden}: 06 §10 🔒 forbids a billing path that counts, sums or gates on envelope contents`,
      );
    }
    // Comments stripped first: a prose "…from the edge…" is not a table read.
    const code = src.prosrc.replace(/--[^\n]*/g, " ");
    const tables = [...code.matchAll(/\b(?:from|into|update)\s+(\w+)/gi)]
      .map((m) => m[1].toLowerCase())
      .filter((t) => t !== "set"); // `do update set …` is the upsert, not a second table
    assertEquals(
      [...new Set(tables)].sort(),
      ["entitlement_tokens"],
      "one table, the token's own — the plan itself is read at the edge under RLS, not here",
    );

    await sql.end();
  },
});
