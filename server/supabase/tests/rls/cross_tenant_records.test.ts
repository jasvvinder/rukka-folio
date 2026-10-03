// Hostile-query suite for desk 58 (🔴 SECURITY, owner-approved 3 Oct 2026): a signed record, and
// the projection it authorises, must belong to a tenant the AUTHOR is in — and a projection that 06
// reserves to an admin must find an admin — in the DATABASE, because the edge is just another
// client (ADR 2026-09-05d §2; 03 §2.5 🔒 RLS on every table; 06 §7 🔒 "every transition and every
// role/limit/designation change is a signed record authored on a certified admin device").
//
// What HEAD (0005 … 0021) allowed, and what each test denies:
//   * `signed_records_insert` (0005:404) checked only `is_certified` + `author_device`, so a certified
//     device of tenant A could file a record IN tenant B (E-06-82);
//   * `rf.project_membership` (0005:200) checked only `rf.require_record` — a record of the caller's
//     device in that tenant — so A could put itself at joined_pending_verification in B (E-06-83),
//     set an active member of B to `removed` and delete their book_roles (E-06-84), and take B's
//     seats or read B's fullness off the answer (E-06-85);
//   * the edge did NOT close it on the real store: `applyRecord`'s founder bootstrap counted the
//     memberships the CALLER could see (store_pg.ts membershipCount), which for a stranger is zero,
//     so POST /sync-meta/records walked A into B with `acked` (E-06-86). Desk 83 took that count out
//     of the edge: it now asks the database (rf.may_file_record, before it files anything) and
//     decides book roles and revocations as 0022 does — edge_record_authority.test.ts, E-06-91 … 95;
//   * `rf.project_book_role` (0005:211) and `rf.project_device_status` (0005:227) had the same
//     missing check: anyone with a record in B could grant or delete B's roles (E-06-88), and anyone
//     with a record in their OWN tenant could revoke — or mark `certified` — any device anywhere
//     (E-06-89).
// E-06-87 is the control: B's admin, B's founder, B's own members still do every legitimate thing.
// E-06-90: every check above is a SECURITY DEFINER function, and rf_api may create temp tables; a
// function whose search_path does not list pg_temp LAST reads the caller's temp table of the same
// name first, so each one 0022 writes or stands on pins `public, pg_temp`.
//
// Every hostile query runs on a connection opened as rf_api (`options=-c role=rf_api`, asserted
// with current_user), with the caller's own claims — exactly what the edge holds. Fixtures are
// written by the schema owner without claims. Payloads are `{}` or ids, blobs and signatures random
// bytes: no ledger content, no phone number (CLAUDE.md rule 4).
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`); without it every test is SKIPPED and says
// why, and RLS_REQUIRE=1 makes that a failure. Ids E-06-82 … E-06-90.
import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "@std/assert";
import postgres from "postgres";
import { PgStore } from "../../functions/_shared/store_pg.ts";
import { handler as meta } from "../../functions/sync-meta/index.ts";
import {
  body,
  edKeypair,
  type KeyPair,
  type Member,
  post,
  reissue,
  type Rig,
  rig,
  signedRecord,
} from "../../functions/_tests/harness.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — cross_tenant_records.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP cross_tenant_records.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql; // the schema owner: fixtures and fresh reads only
let api: postgres.Sql; // rf_api: every hostile query
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

/** The connection the edge holds: rf_api, never the owner. */
const apiUrl = () =>
  `${url}${url!.includes("?") ? "&" : "?"}options=${encodeURIComponent("-c role=rf_api")}`;

// A two-seat plan for the oracle arms (E-06-85, -86) and a seat-unlimited one for the legitimate
// arms (E-06-87), so a cap never stands in for the refusal under test; removed after every test.
const TWO = "zz_sec58_two";
const MANY = "zz_sec58_many";

const KINDS = [
  "membership_status",
  "book_role",
  "member_removal",
  "device_revocation",
  "device_added",
  "key_rotation",
  "verification_event",
  "designation",
  "invite",
] as const;

function test(name: string, fn: () => Promise<void>) {
  Deno.test({
    name,
    ignore,
    async fn() {
      sql = postgres(url!, { max: 2, onnotice: () => {} });
      api = postgres(apiUrl(), { max: 2, onnotice: () => {} });
      try {
        const [who] = await api`select current_user as u`;
        assertEquals(
          who.u,
          "rf_api",
          "precondition: every hostile query runs as rf_api, so RLS applies",
        );
        await sql`insert into plan_catalogue (id, entity_type, name, sort_order, members,
            business_books, devices, envelopes_per_book, tenant_bytes, attachment_bytes, features,
            price_yearly_paise, price_monthly_paise)
          values (${TWO}, 'family', 'Sec58 two', 95, 2, 2, 5, 1000, 1000000, 1000, '{}', 0, 0),
                 (${MANY}, 'family', 'Sec58 many', 96, -1, -1, 5, 1000, 1000000, 1000, '{}', 0, 0)
          on conflict (id) do nothing`;
        await fn();
      } finally {
        await sql`update subscriptions set plan = 'free' where plan in (${TWO}, ${MANY})`;
        await sql`delete from plan_catalogue where id in (${TWO}, ${MANY})`;
        await api.end();
        await sql.end();
      }
    },
  });
}

// ---------------------------------------------------------------- the rf_api caller
/** One transaction on the rf_api connection with the caller's own claims (rf.set_claims is SET
 *  LOCAL — ADR 2026-09-05c §7), as PgStore.withClaims opens it. */
async function asApi<T>(
  user: string | null,
  device: string | null,
  fn: (s: postgres.TransactionSql) => Promise<T>,
): Promise<T> {
  return await api.begin(async (s) => {
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
function assertRefused(e: PgErr, code: string, name: string, what: string) {
  assertEquals(e.code, code, `${what}: ${e.code} ${e.message}`);
  assertStringIncludes(e.message, name, what);
}
/** A record filed by the CALLER through rf_api (signed_records_insert decides). */
const fileRecord = (
  s: postgres.TransactionSql,
  tenant: string,
  device: string,
  kind: string,
  payload: Record<string, unknown> = {},
) => {
  const id = crypto.randomUUID();
  return s`insert into signed_records
      (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${id}, 1, ${tenant}, ${kind}, ${s.json(payload as postgres.JSONValue)}, ${rand(8)},
            ${device}, ${rand(64)}, 1)
    returning id`.then((r) => r[0].id as string);
};
async function file(
  p: P,
  tenant: string,
  kind: string,
  payload: Record<string, unknown> = {},
): Promise<string> {
  return await asApi(p.user, p.dev, (s) => fileRecord(s, tenant, p.dev, kind, payload));
}
const tryFile = (p: P, tenant: string, kind: string) => pgErr(file(p, tenant, kind));

// ---------------------------------------------------------------- fixtures (schema owner, no claims)
interface P {
  user: string;
  dev: string;
  keys: KeyPair;
}
async function mkPerson(status = "certified"): Promise<P> {
  const keys = await edKeypair();
  const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${rand(32)}, ${rand(40)})
    returning id`;
  return { user: u.id as string, dev: await mkDev(u.id as string, status, keys.pub), keys };
}
async function mkDev(
  user: string,
  status = "certified",
  pub: Uint8Array = rand(32),
): Promise<string> {
  const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${user}, ${pub}, ${rand(32)}, ${status}) returning id`;
  return d.id as string;
}
/** A record that EXISTS — filed by the owner, as history or as a fixture, past every policy. */
async function ownerRecord(tenant: string, device: string, kind: string): Promise<string> {
  const id = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${id}, 1, ${tenant}, ${kind}, '{}'::jsonb, ${rand(8)}, ${device}, ${rand(64)}, 1)`;
  return id;
}
interface Tn {
  t: string;
  founder: P;
  personal: string;
  business: string;
}
/** A family tenant (on `plan`, or the Free floor when null) whose founder is active and admin of
 *  the founder's personal book and of one business book. */
async function tenant(plan: string | null = null): Promise<Tn> {
  const [row] = await sql`insert into tenants (type) values ('family') returning id`;
  const t = row.id as string;
  if (plan) await sql`insert into subscriptions (tenant_id, plan) values (${t}, ${plan})`;
  const founder = await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${founder.user}, 'active')`;
  const personal = crypto.randomUUID(), business = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type, owner_user_id)
    values (${personal}, ${t}, 'personal', ${founder.user})`;
  await sql`insert into books (id, tenant_id, type) values (${business}, ${t}, 'business')`;
  await sql`insert into book_roles (book_id, user_id, role)
    values (${personal}, ${founder.user}, 'admin'), (${business}, ${founder.user}, 'admin')`;
  return { t, founder, personal, business };
}
/** A tenant row and nothing else: no membership yet — the founder's moment (06 §5). */
async function emptyTenant(): Promise<string> {
  const [row] = await sql`insert into tenants (type) values ('family') returning id`;
  return row.id as string;
}
/** `p` made ACTIVE in `tn` by the owner after a signed ceremony (0006/0008's guards). */
async function makeActive(tn: Tn, p: P): Promise<P> {
  const rec = await ownerRecord(tn.t, tn.founder.dev, "verification_event");
  await sql`insert into verification_events
    (tenant_id, subject_user, verifier_user, method, result, source_record_id)
    values (${tn.t}, ${p.user}, ${tn.founder.user}, 'qr_in_person', 'verified', ${rec})`;
  await sql`insert into memberships (tenant_id, user_id, status) values (${tn.t}, ${p.user}, 'active')`;
  return p;
}
/** A new person, ACTIVE in `tn`. */
async function activeMember(tn: Tn): Promise<P> {
  return await makeActive(tn, await mkPerson());
}
/** A member at `status` (joined_pending_verification / removed), walked there by the owner. */
async function memberAt(tn: Tn, status: string): Promise<P> {
  const p = await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status) values (${tn.t}, ${p.user}, ${status})`;
  return p;
}
async function role(book: string, user: string, r: string): Promise<void> {
  await sql`insert into book_roles (book_id, user_id, role) values (${book}, ${user}, ${r})`;
}

// ---------------------------------------------------------------- fresh reads (owner)
async function statusOf(t: string, user: string): Promise<string | null> {
  const [r] =
    await sql`select status from memberships where tenant_id = ${t} and user_id = ${user}`;
  return (r?.status as string) ?? null;
}
async function rolesOf(book: string): Promise<string[]> {
  const rows = await sql`select user_id, role from book_roles where book_id = ${book}
    order by user_id, role`;
  return rows.map((r) => `${r.user_id}:${r.role}`);
}
async function rolesInTenant(t: string): Promise<string[]> {
  const rows = await sql`select r.book_id, r.user_id, r.role from book_roles r
    join books b on b.id = r.book_id where b.tenant_id = ${t} order by 1, 2`;
  return rows.map((r) => `${r.book_id}:${r.user_id}:${r.role}`);
}
async function recordsIn(t: string): Promise<number> {
  const [r] = await sql`select count(*)::int as n from signed_records where tenant_id = ${t}`;
  return r.n as number;
}
async function membershipsIn(t: string): Promise<string[]> {
  const rows = await sql`select user_id, status from memberships where tenant_id = ${t}
    order by user_id`;
  return rows.map((r) => `${r.user_id}:${r.status}`);
}
async function grantsIn(t: string): Promise<number> {
  const [r] = await sql`select count(*)::int as n from seat_grants where tenant_id = ${t}`;
  return r.n as number;
}
async function deviceState(d: string): Promise<{ status: string; revoked: boolean }> {
  const [r] = await sql`select status, revoked_at from devices where id = ${d}`;
  return { status: r.status as string, revoked: r.revoked_at !== null };
}

// ---------------------------------------------------------------- session-local shadows (E-06-90)
/** A temp table rf_api creates in its OWN session — it holds TEMPORARY on the database, as PUBLIC
 *  does by default — named like a public table a check reads, readable by anyone, gone at commit
 *  or rollback. Postgres searches the session's temp schema FIRST unless a function's search_path
 *  lists pg_temp last ('Writing SECURITY DEFINER Functions Safely'). Ids only, no ledger content. */
interface Shadow {
  table: string;
  cols: string;
  rows: (string | number | null)[][];
}
const SH = {
  devices: "id uuid, user_id uuid, status text",
  memberships:
    "tenant_id uuid, user_id uuid, status text, source_record_id uuid, primary key (tenant_id, user_id)",
  guardian_set_members: "subject_user_id uuid, share_set_version int, guardian_user_id uuid",
  books: "id uuid, tenant_id uuid, type text, owner_user_id uuid",
  book_roles: "book_id uuid, user_id uuid, role text",
  signed_records: "id uuid, tenant_id uuid, author_device uuid",
} as const;
const sh = (table: keyof typeof SH, ...rows: (string | number | null)[][]): Shadow => ({
  table,
  cols: SH[table],
  rows,
});
/** One transaction on a FRESH rf_api session, the caller's claims, the shadows in place — each
 *  asserted to be what the bare table name now means there, so a refusal below is the pin's and not
 *  a dud. Fresh, because PL/pgSQL caches a statement's plan per session: on the shared pool a
 *  function an earlier arm already ran keeps reading public whatever its search_path, and the arm
 *  would pass without its pin. An attacker shadows first, in its own session; so does this. */
async function shadowed<T>(
  p: { user: string; dev: string },
  shadows: Shadow[],
  fn: (s: postgres.TransactionSql) => Promise<T>,
): Promise<T> {
  const own = postgres(apiUrl(), { max: 1, onnotice: () => {} });
  try {
    return await own.begin(async (s) => {
      const [who] = await s`select current_user as u`;
      assertEquals(who.u, "rf_api", "precondition: the shadowing session is rf_api");
      await s`select rf.set_claims(${p.user}::uuid, ${p.dev}::uuid)`;
      for (const { table, cols, rows } of shadows) {
        await s.unsafe(`create temp table ${table} (${cols}) on commit drop`);
        await s.unsafe(`grant select on pg_temp.${table} to public`);
        for (const r of rows) {
          const ph = r.map((_, i) => `$${i + 1}`).join(", ");
          await s.unsafe(`insert into pg_temp.${table} values (${ph})`, r as never[]);
        }
        const [n] = await s`select n.nspname from pg_class c
          join pg_namespace n on n.oid = c.relnamespace where c.oid = to_regclass(${table})`;
        assert(
          String(n?.nspname).startsWith("pg_temp"),
          `precondition: in rf_api's session '${table}' names the shadow (${n?.nspname})`,
        );
      }
      return await fn(s);
    }) as T;
  } finally {
    await own.end();
  }
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

// ================================================================ the tests

test(
  "E-06-82 a signed record belongs to a tenant its author is IN: a certified, active admin of tenant A files a record of every kind into tenant B and is refused by signed_records_insert (42501, no row); so are B's own removed, blocked and invited members; a tenant that does not exist answers the same 42501 as one that does (no existence oracle); and a tenant with no member yet takes only the founder's membership_status, never another kind",
  async () => {
    const a = await tenant(), b = await tenant();
    const before = await recordsIn(b.t);
    for (const kind of KINDS) {
      assertRefused(
        await tryFile(a.founder, b.t, kind),
        "42501",
        "row-level security",
        `A's admin files ${kind} into B`,
      );
    }
    for (const st of ["removed", "blocked", "invited"]) {
      const p = await mkPerson();
      // blocked is reachable only from a mismatch ceremony, invited only from a live invite (0006's
      // guard) — the owner writes the row through the state machine's own back door: insert at
      // removed (always allowed from nothing), then walk it where the test needs it.
      await sql`insert into memberships (tenant_id, user_id, status) values (${b.t}, ${p.user}, 'removed')`;
      if (st !== "removed") {
        await sql`alter table memberships disable trigger memberships_guard`;
        try {
          await sql`update memberships set status = ${st} where tenant_id = ${b.t} and user_id = ${p.user}`;
        } finally {
          await sql`alter table memberships enable trigger memberships_guard`;
        }
      }
      assertRefused(
        await tryFile(p, b.t, "device_added"),
        "42501",
        "row-level security",
        `a ${st} member of B files into B`,
      );
    }
    assertEquals(await recordsIn(b.t), before, "no record of any of them reached B");

    // No existence oracle: a random tenant id and B answer alike.
    const ghost = await tryFile(a.founder, crypto.randomUUID(), "membership_status");
    const real = await tryFile(a.founder, b.t, "membership_status");
    assertEquals(ghost, real, "a tenant that does not exist answers exactly as B does");

    // The founder's moment: an EXISTING tenant with no member yet takes a membership_status from a
    // certified device (06 §5 — the founder has nobody to verify them) and nothing else.
    const e = await emptyTenant();
    const p = await mkPerson();
    for (const kind of KINDS.filter((k) => k !== "membership_status")) {
      assertRefused(
        await tryFile(p, e, kind),
        "42501",
        "row-level security",
        `${kind} into a memberless tenant`,
      );
    }
    assertEquals(await recordsIn(e), 0);
    const unc = await mkPerson("registered");
    assertRefused(
      await tryFile(unc, e, "membership_status"),
      "42501",
      "row-level security",
      "an uncertified device founds nothing (ADR 2026-09-05d §2)",
    );
  },
);

test(
  "E-06-83 a device of tenant A cannot project itself into tenant B's membership: the record cannot be filed in B, rf.project_membership citing a record of A's own tenant or an invented id answers no_record, a REMOVED former member of B replaying the record it once filed in B is refused not_admin, and B holds no membership row for any of them",
  async () => {
    const a = await tenant(), b = await tenant();
    const roster = await membershipsIn(b.t);
    const intoB = await pgErr(asApi(a.founder.user, a.founder.dev, async (s) => {
      const rec = await fileRecord(s, b.t, a.founder.dev, "membership_status");
      await s`select rf.project_membership(${rec}, ${b.t}, ${a.founder.user},
        'joined_pending_verification')`;
    }));
    assertRefused(intoB, "42501", "row-level security", "filing the record in B");

    const own = await file(a.founder, a.t, "membership_status");
    for (
      const [what, rec] of [["A's own-tenant record", own], ["an invented id", crypto.randomUUID()]]
    ) {
      const e = await pgErr(asApi(
        a.founder.user,
        a.founder.dev,
        (s) =>
          s`select rf.project_membership(${rec}, ${b.t}, ${a.founder.user}, 'joined_pending_verification')`,
      ));
      assertRefused(e, "P0001", "no_record", what);
    }
    assertEquals(await statusOf(b.t, a.founder.user), null, "A holds no row in B");

    // A former member keeps the records it filed while it belonged (append-only, ADR 05b §1): a
    // record is not a standing licence.
    const gone = await memberAt(b, "removed");
    const old = await ownerRecord(b.t, gone.dev, "membership_status");
    const replay = await pgErr(asApi(
      gone.user,
      gone.dev,
      (s) =>
        s`select rf.project_membership(${old}, ${b.t}, ${gone.user}, 'joined_pending_verification')`,
    ));
    assertRefused(replay, "42501", "not_admin", "a removed member replaying its old record");
    assertEquals(await statusOf(b.t, gone.user), "removed");
    assertEquals(
      (await membershipsIn(b.t)).filter((x) => !x.startsWith(gone.user)),
      roster,
      "B's roster is untouched",
    );
  },
);

test(
  "E-06-84 nobody but an admin of B sets an active member of B to removed: tenant A's admin (record in B refused; A's own-tenant record cited for B → no_record) and B's own active NON-admin member (record filed, projection refused not_admin, 06 §1.0 'remove members … admin only') both fail, and the victim stays active with every book_role intact",
  async () => {
    const a = await tenant(), b = await tenant();
    const victim = await activeMember(b);
    await role(b.business, victim.user, "head");
    const insider = await activeMember(b);
    await role(b.business, insider.user, "member");
    const rolesBefore = await rolesInTenant(b.t);

    const outsider = await pgErr(asApi(a.founder.user, a.founder.dev, async (s) => {
      const rec = await fileRecord(s, b.t, a.founder.dev, "member_removal");
      await s`select rf.project_membership(${rec}, ${b.t}, ${victim.user}, 'removed')`;
    }));
    assertRefused(outsider, "42501", "row-level security", "A files a removal into B");
    const own = await file(a.founder, a.t, "member_removal");
    assertRefused(
      await pgErr(asApi(
        a.founder.user,
        a.founder.dev,
        (s) => s`select rf.project_membership(${own}, ${b.t}, ${victim.user}, 'removed')`,
      )),
      "P0001",
      "no_record",
      "A cites its own tenant's record for B",
    );

    for (const kind of ["member_removal", "membership_status"]) {
      const rec = await file(insider, b.t, kind); // an active member MAY file in its own tenant
      assertRefused(
        await pgErr(asApi(
          insider.user,
          insider.dev,
          (s) => s`select rf.project_membership(${rec}, ${b.t}, ${victim.user}, 'removed')`,
        )),
        "42501",
        "not_admin",
        `B's non-admin member projects ${kind} → removed`,
      );
    }
    assertEquals(await statusOf(b.t, victim.user), "active", "the victim is still active");
    assertEquals(await rolesInTenant(b.t), rolesBefore, "and every book_role in B is intact");
  },
);

test(
  "E-06-85 a device of tenant A can neither take a seat of tenant B nor learn whether B is full: against B with room and B full (a two-seat plan, ADR 2026-09-05g §6), A's attempt to walk itself in answers the SAME refusal — code, message and detail — at the record and at the projection, and neither tenant's seat ledger, roster or holder count moves",
  async () => {
    const a = await tenant();
    const room = await tenant(TWO); // founder: 1 of 2
    const full = await tenant(TWO);
    await activeMember(full); // 2 of 2
    const snap = async (t: string) => ({
      grants: await grantsIn(t),
      roster: await membershipsIn(t),
      holders: (await sql`select rf.seat_holders(${t}, null, null) as n`)[0].n as number,
    });
    const before = { room: await snap(room.t), full: await snap(full.t) };
    assertEquals(before.full.holders, 2, "precondition: B is full");
    assertEquals(before.room.holders, 1, "precondition: B' has a free seat");

    const attempt = (t: string) =>
      pgErr(asApi(a.founder.user, a.founder.dev, async (s) => {
        const rec = await fileRecord(s, t, a.founder.dev, "membership_status");
        await s`select rf.project_membership(${rec}, ${t}, ${a.founder.user},
          'joined_pending_verification')`;
      }));
    const viaOwn = async (t: string) => {
      const rec = await file(a.founder, a.t, "membership_status");
      return await pgErr(asApi(
        a.founder.user,
        a.founder.dev,
        (s) =>
          s`select rf.project_membership(${rec}, ${t}, ${a.founder.user}, 'joined_pending_verification')`,
      ));
    };
    const [r1, f1] = [await attempt(room.t), await attempt(full.t)];
    assertEquals(r1, f1, "the record is refused alike whether B is full or not");
    assertRefused(r1, "42501", "row-level security", "filing into B");
    const [r2, f2] = [await viaOwn(room.t), await viaOwn(full.t)];
    assertEquals(r2, f2, "the projection is refused alike whether B is full or not");
    assertRefused(r2, "P0001", "no_record", "projecting into B");
    for (const x of [r1, f1, r2, f2]) assert(!/cap/.test(x.message + x.detail), x.message);

    assertEquals(await snap(room.t), before.room, "B' with room: no seat taken, nothing moved");
    assertEquals(await snap(full.t), before.full, "B full: nothing moved");
  },
);

test(
  "E-06-86 POST /sync-meta/records over the real store as rf_api: tenant A's founder sends a membership_status walking itself into B at joined_pending_verification (the edge's founder bootstrap counts only the memberships the caller can SEE — zero, for a stranger) and is answered rejected:unauthorized, never acked — the same answer whether B is full or has room — and B gains no record, no membership and no seat",
  async () => {
    const a = await tenant();
    const room = await tenant(TWO);
    const full = await tenant(TWO);
    await activeMember(full);
    const r = rig();
    const s = await signer(r, a.founder);
    const store = new PgStore(apiUrl());
    r.deps.store = store;
    try {
      const answers: unknown[] = [];
      for (const b of [room, full]) {
        const recs = await recordsIn(b.t), grants = await grantsIn(b.t);
        const rec = await signedRecord(s, b.t, "membership_status", {
          user_id: a.founder.user,
          status: "joined_pending_verification",
        });
        const res = await meta(
          post("/sync-meta/records", { records: [rec.wire] }, { token: s.token }),
          r.deps,
        );
        assertEquals(res.status, 200);
        const out = await body(res);
        const got = out.results.map((x: { id: string; result: string; check?: string }) => [
          x.id === rec.row.id,
          x.result,
          x.check ?? null,
        ]);
        assertEquals(got[0][1], "rejected:unauthorized", JSON.stringify(got));
        answers.push(got);
        assertEquals(await statusOf(b.t, a.founder.user), null, "A holds no membership in B");
        assertEquals(await recordsIn(b.t), recs, "no record of A's was stored in B");
        assertEquals(await grantsIn(b.t), grants, "no seat was taken");
      }
      assertEquals(answers[0], answers[1], "full or not, the wire answer is the same");
    } finally {
      await store.end();
    }
  },
);

test(
  "E-06-87 the legitimate paths still work: B's admin files in B and walks a new person to joined_pending_verification and an active member to removed (their book_roles go); a certified founder of a memberless tenant files and projects their own active membership (06 §5); a joined_pending_verification member files its own device_added in B (06 §5 'every tenant'); and B's admin over POST /sync-meta/records on the real store is acked",
  async () => {
    const b = await tenant(MANY);
    const joiner = await mkPerson();
    const rec1 = await file(b.founder, b.t, "membership_status");
    await asApi(
      b.founder.user,
      b.founder.dev,
      (s) =>
        s`select rf.project_membership(${rec1}, ${b.t}, ${joiner.user}, 'joined_pending_verification')`,
    );
    assertEquals(await statusOf(b.t, joiner.user), "joined_pending_verification");

    const leaver = await activeMember(b);
    await role(b.business, leaver.user, "member");
    const rec2 = await file(b.founder, b.t, "member_removal");
    await asApi(
      b.founder.user,
      b.founder.dev,
      (s) => s`select rf.project_membership(${rec2}, ${b.t}, ${leaver.user}, 'removed')`,
    );
    assertEquals(await statusOf(b.t, leaver.user), "removed");
    assertEquals(
      (await rolesInTenant(b.t)).filter((x) => x.includes(leaver.user)),
      [],
      "removal deletes the member's book_roles (0005)",
    );

    // The founder (06 §5): a memberless tenant, a certified device, its own membership at active.
    const e = await emptyTenant();
    const founder = await mkPerson();
    await asApi(founder.user, founder.dev, async (s) => {
      const rec = await fileRecord(s, e, founder.dev, "membership_status");
      await s`select rf.project_membership(${rec}, ${e}, ${founder.user}, 'active')`;
    });
    assertEquals(await statusOf(e, founder.user), "active");
    // …and only its OWN, only at active: a second person is not a founder.
    const late = await mkPerson();
    const e2 = await emptyTenant();
    const lateTry = await pgErr(asApi(late.user, late.dev, async (s) => {
      const rec = await fileRecord(s, e2, late.dev, "membership_status");
      await s`select rf.project_membership(${rec}, ${e2}, ${joiner.user}, 'active')`;
    }));
    assertRefused(lateTry, "42501", "not_admin", "founding a tenant FOR someone else");
    const jpvSelf = await pgErr(asApi(late.user, late.dev, async (s) => {
      const rec = await fileRecord(s, e2, late.dev, "membership_status");
      await s`select rf.project_membership(${rec}, ${e2}, ${late.user}, 'joined_pending_verification')`;
    }));
    assertRefused(jpvSelf, "42501", "not_admin", "the founder's exception is active, nothing else");
    assertEquals(await membershipsIn(e2), []);

    // A joined_pending_verification member is IN the tenant: its device announcement lands there.
    const pending = await memberAt(b, "joined_pending_verification");
    const ann = await file(pending, b.t, "device_added");
    assert(ann, "the pending member's device_added is stored in B");

    // Over the edge, on the real store, as rf_api.
    const r = rig();
    const s = await signer(r, b.founder);
    const third = await mkPerson();
    const rec = await signedRecord(s, b.t, "membership_status", {
      user_id: third.user,
      status: "joined_pending_verification",
    });
    const store = new PgStore(apiUrl());
    r.deps.store = store;
    try {
      const res = await meta(
        post("/sync-meta/records", { records: [rec.wire] }, { token: s.token }),
        r.deps,
      );
      assertEquals(res.status, 200);
      const out = await body(res);
      assertEquals(out.results[0].result, "acked", JSON.stringify(out.results));
      assertEquals(await statusOf(b.t, third.user), "joined_pending_verification");
    } finally {
      await store.end();
    }
  },
);

test(
  "E-06-88 book roles are granted, changed and revoked only by an admin of THAT book (06 §1.0 🔒), its creator being the first: tenant A's admin cannot grant itself a role on B's book or strip B's admin (no_record / RLS); B's active non-admin member, B's pending member and the admin of ANOTHER book of B are refused not_admin; the book's admin grants and revokes; the first role on a role-less book that holds no envelope is its creator's own admin role and nobody else's — on a personal book its OWNER's, refused even to the tenant's founder",
  async () => {
    const a = await tenant(), b = await tenant();
    const member = await activeMember(b);
    await role(b.business, member.user, "member");
    const pending = await memberAt(b, "joined_pending_verification");
    const otherAdmin = await activeMember(b);
    const other = crypto.randomUUID();
    await sql`insert into books (id, tenant_id, type) values (${other}, ${b.t}, 'business')`;
    await role(other, otherAdmin.user, "admin");
    const before = await rolesOf(b.business);

    // The outsider: cannot file in B; its own-tenant record does not authorise B's book.
    const filed = await pgErr(asApi(a.founder.user, a.founder.dev, async (s) => {
      const rec = await fileRecord(s, b.t, a.founder.dev, "book_role");
      await s`select rf.project_book_role(${rec}, ${b.business}, ${a.founder.user}, 'admin', null)`;
    }));
    assertRefused(filed, "42501", "row-level security", "A files a book_role into B");
    const own = await file(a.founder, a.t, "book_role");
    for (
      const [what, user, r] of [
        ["grant itself admin", a.founder.user, "admin"],
        ["strip B's admin", b.founder.user, null],
      ] as const
    ) {
      assertRefused(
        await pgErr(asApi(
          a.founder.user,
          a.founder.dev,
          (s) => s`select rf.project_book_role(${own}, ${b.business}, ${user}, ${r}, null)`,
        )),
        "P0001",
        "no_record",
        `A, citing its own tenant's record, tries to ${what}`,
      );
    }

    // Insiders who are not this book's admin.
    for (
      const [who, p] of [["member", member], ["pending", pending], [
        "other book's admin",
        otherAdmin,
      ]] as const
    ) {
      const rec = await file(p, b.t, "book_role");
      for (
        const [what, user, r] of [
          ["grant itself admin", p.user, "admin"],
          ["strip the admin", b.founder.user, null],
        ] as const
      ) {
        assertRefused(
          await pgErr(asApi(
            p.user,
            p.dev,
            (s) => s`select rf.project_book_role(${rec}, ${b.business}, ${user}, ${r}, null)`,
          )),
          "42501",
          "not_admin",
          `B's ${who} tries to ${what}`,
        );
      }
    }
    assertEquals(await rolesOf(b.business), before, "B's book roles are untouched");

    // The book's admin grants and revokes.
    const g = await file(b.founder, b.t, "book_role");
    await asApi(
      b.founder.user,
      b.founder.dev,
      (s) => s`select rf.project_book_role(${g}, ${b.business}, ${member.user}, 'head', 500000)`,
    );
    const [h] = await sql`select role, auto_post_limit_paise from book_roles
      where book_id = ${b.business} and user_id = ${member.user}`;
    assertEquals([h.role, Number(h.auto_post_limit_paise)], ["head", 500000]);
    await asApi(
      b.founder.user,
      b.founder.dev,
      (s) => s`select rf.project_book_role(${g}, ${b.business}, ${member.user}, null, null)`,
    );
    assertEquals(
      (await rolesOf(b.business)).filter((x) => x.startsWith(member.user)),
      [],
      "the admin revoked it",
    );

    // A role-less book: its first role is its creator's own admin role (06 §1.0).
    const fresh = crypto.randomUUID(), fresh2 = crypto.randomUUID();
    await sql`insert into books (id, tenant_id, type) values (${fresh}, ${b.t}, 'business'),
      (${fresh2}, ${b.t}, 'business')`;
    const c = await file(member, b.t, "book_role");
    assertRefused(
      await pgErr(asApi(
        member.user,
        member.dev,
        (s) => s`select rf.project_book_role(${c}, ${fresh2}, ${otherAdmin.user}, 'admin', null)`,
      )),
      "42501",
      "not_admin",
      "the first role is the creator's own, not one handed to someone else",
    );
    assertRefused(
      await pgErr(asApi(
        member.user,
        member.dev,
        (s) => s`select rf.project_book_role(${c}, ${fresh2}, ${member.user}, 'viewer', null)`,
      )),
      "42501",
      "not_admin",
      "the first role is admin",
    );
    const pr = await file(pending, b.t, "book_role");
    assertRefused(
      await pgErr(asApi(
        pending.user,
        pending.dev,
        (s) => s`select rf.project_book_role(${pr}, ${fresh2}, ${pending.user}, 'admin', null)`,
      )),
      "42501",
      "not_admin",
      "a pending member creates no book (books_insert needs active)",
    );
    await asApi(
      member.user,
      member.dev,
      (s) => s`select rf.project_book_role(${c}, ${fresh}, ${member.user}, 'admin', null)`,
    );
    assertEquals(await rolesOf(fresh), [`${member.user}:admin`], "the creator is the first admin");
    // A role-less PERSONAL book is founded by its owner alone (0022 §3, ⚠️ SPEC (d)): not by another
    // active member — not even B's founder, admin of every other book of B — only by the owner.
    const mine = crypto.randomUUID();
    await sql`insert into books (id, tenant_id, type, owner_user_id)
      values (${mine}, ${b.t}, 'personal', ${member.user})`;
    assertRefused(
      await pgErr(asApi(
        b.founder.user,
        b.founder.dev,
        (s) => s`select rf.project_book_role(${g}, ${mine}, ${b.founder.user}, 'admin', null)`,
      )),
      "42501",
      "not_admin",
      "B's founder claims a role-less personal book that is another member's",
    );
    assertEquals(await rolesOf(mine), [], "a personal book is not anybody's to found");
    await asApi(
      member.user,
      member.dev,
      (s) => s`select rf.project_book_role(${c}, ${mine}, ${member.user}, 'admin', null)`,
    );
    assertEquals(await rolesOf(mine), [`${member.user}:admin`], "its owner is its first admin");
    // A book whose roles are all gone but which holds envelopes was created long ago: nobody
    // re-founds it (an envelope needs a role to be pushed, so a new book holds none).
    const used = crypto.randomUUID();
    await sql`insert into books (id, tenant_id, type) values (${used}, ${b.t}, 'business')`;
    const blob = rand(8);
    await sql`insert into envelopes (envelope_id, tenant_id, book_id, object_id, object_type,
        key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
      values (gen_random_uuid(), ${b.t}, ${used}, gen_random_uuid(), 'entry', 1, 1, 1,
              ${b.founder.dev}, 1, ${rand(32)}, ${blob.length}, ${blob})`;
    assertRefused(
      await pgErr(asApi(
        member.user,
        member.dev,
        (s) => s`select rf.project_book_role(${c}, ${used}, ${member.user}, 'admin', null)`,
      )),
      "42501",
      "not_admin",
      "a used book whose roles are all gone is not claimable",
    );
    assertEquals(await rolesOf(used), []);
    assertEquals(await rolesOf(fresh2), [], "the refused bootstraps left no role");
  },
);

test(
  "E-06-89 a device is revoked only by its own user or that user's guardian, inside the record's tenant, and the projection only ever revokes: tenant A's admin, citing a record of its OWN tenant, cannot revoke a device of B's member nor mark any device certified (that is rf.certify_device's, ADR 2026-09-05d §2); B's non-guardian member cannot revoke a fellow member's device; a genuine guardian citing a record of a tenant the subject is not in, or was removed from, and the owner replaying a record of a tenant that removed it, are refused; the owner, in the subject's tenant, can; and since 0026 a guardian projects only on the database's own count — one approval of k = 2 is refused, the second (from a guardian still pending in the set's tenant) revokes (ADR 2026-10-03b §2, §3)",
  async () => {
    const a = await tenant(), b = await tenant();
    const victim = await activeMember(b);
    const guardian = await activeMember(b);
    const bystander = await activeMember(b);
    const g2 = await mkPerson();
    // ADR 2026-10-03b §1 (0026): the set is set up in B, where the victim is active and both
    // guardians are members — g2 still at joined_pending_verification.
    await sql`insert into memberships (tenant_id, user_id, status)
      values (${b.t}, ${g2.user}, 'joined_pending_verification')`;
    await sql`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
      values (${victim.user}, 1, 2, 2, ${b.t})`;
    await sql`insert into guardian_set_members
        (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
      values (${victim.user}, 1, ${guardian.user}, ${rand(32)}),
             (${victim.user}, 1, ${g2.user}, ${rand(32)})`;

    const own = await file(a.founder, a.t, "device_revocation");
    const proj = (p: P, rec: string, t: string, dev: string, st: string) =>
      pgErr(asApi(
        p.user,
        p.dev,
        (s) => s`select rf.project_device_status(${rec}, ${t}, ${dev}, ${st})`,
      ));
    assertRefused(
      await proj(a.founder, own, a.t, victim.dev, "revoked"),
      "42501",
      "not_revoker",
      "A revokes B's member's device on A's own record",
    );
    assertEquals(await deviceState(victim.dev), { status: "certified", revoked: false });
    const ghost = await proj(a.founder, own, a.t, crypto.randomUUID(), "revoked");
    assertEquals(
      ghost,
      await proj(a.founder, own, a.t, victim.dev, "revoked"),
      "a device that does not exist answers as one that does",
    );

    const fresh = await mkDev(a.founder.user, "registered");
    for (const dev of [fresh, victim.dev]) {
      assertRefused(
        await proj(a.founder, own, a.t, dev, "certified"),
        "23514",
        "revoke_only",
        "the projection never certifies",
      );
    }
    assertEquals(
      (await deviceState(fresh)).status,
      "registered",
      "certification stays rf.certify_device's",
    );

    const nb = await file(bystander, b.t, "device_revocation");
    assertRefused(
      await proj(bystander, nb, b.t, victim.dev, "revoked"),
      "42501",
      "not_revoker",
      "a fellow member who is not a guardian",
    );
    assertEquals(await deviceState(victim.dev), { status: "certified", revoked: false });

    // WHERE (0022 §4, ⚠️ SPEC (e)): a GENUINE guardian, and the owner, act only on a record of a
    // tenant the subject holds a non-removed membership in. The guardian also belongs to A, where
    // the victim is not, and to C, which removed the victim; the victim replays the record its
    // device filed in C before the removal. Since 0026 the guardian's two records are refused
    // first because neither A nor C is the set's tenant (B, ADR 2026-10-03b §2), so for the
    // guardian these rows no longer exercise the subject-membership clause; E-03b-7
    // (edge_record_authority, both stores) removes the SUBJECT from the set's own tenant and holds
    // that clause in rf.revocation_approvals and rf.guardian_may_revoke — judged at each approval's
    // own seq since 0027 (ADR 2026-10-03b §6; E-03b-10 in revocation_at_seq.test.ts without the
    // edge). The owner's row below still exercises it for the owner's arm, which reads the owner's
    // membership as it stands when the record is applied (0022 (e), unchanged).
    await makeActive(a, guardian);
    const c = await tenant();
    await makeActive(c, guardian);
    await sql`insert into memberships (tenant_id, user_id, status)
      values (${c.t}, ${victim.user}, 'removed')`;
    const second = await mkDev(victim.user);
    const approval = {
      revoked_device_id: victim.dev,
      subject_user_id: victim.user,
      share_set_version: 1,
    };
    const ga = await file(guardian, a.t, "device_revocation", approval);
    const gc = await file(guardian, c.t, "device_revocation", approval);
    const vc = await ownerRecord(c.t, victim.dev, "device_revocation");
    for (
      const [what, p, rec, t, dev] of [
        [
          "the guardian, on a record of A, where the victim is no member",
          guardian,
          ga,
          a.t,
          victim.dev,
        ],
        ["the guardian, on a record of C, which removed the victim", guardian, gc, c.t, victim.dev],
        ["the owner, replaying its record of C after C removed it", victim, vc, c.t, second],
      ] as const
    ) {
      assertRefused(await proj(p, rec, t, dev, "revoked"), "42501", "not_revoker", what);
    }
    assertEquals(await deviceState(victim.dev), { status: "certified", revoked: false });
    assertEquals(await deviceState(second), { status: "certified", revoked: false });

    // The owner (06 §6 "any certified device of the same user"), in B, where the victim is.
    const vr = await file(victim, b.t, "device_revocation");
    assertEquals((await proj(victim, vr, b.t, second, "revoked")).code, "ok");
    assertEquals(await deviceState(second), { status: "revoked", revoked: true });
    // k guardians (06 §6): since 0026 the database counts — over every approval filed in the set's
    // tenant (ADR 2026-10-03b §2) — and no longer takes one guardian's word for k. One of two is
    // refused; the second, from a guardian still pending in B (§3), revokes.
    const gr = await file(guardian, b.t, "device_revocation", approval);
    assertRefused(
      await proj(guardian, gr, b.t, victim.dev, "revoked"),
      "42501",
      "not_revoker",
      "one counted approval of k = 2",
    );
    assertEquals(await deviceState(victim.dev), { status: "certified", revoked: false });
    const g2r = await file(g2, b.t, "device_revocation", approval);
    assertEquals((await proj(g2, g2r, b.t, victim.dev, "revoked")).code, "ok");
    assertEquals(await deviceState(victim.dev), { status: "revoked", revoked: true });
    assertNotEquals(victim.dev, second);
  },
);

test(
  "E-06-90 a session-local relation cannot stand in for a table 0022's checks read: rf_api holds TEMPORARY, so it shadows devices, memberships, guardian_set_members, books, book_roles and signed_records with temp tables granting it every right, and rf.is_certified, rf.may_file_record, signed_records_insert, rf.require_record, rf.is_tenant_admin, rf.project_membership, rf.project_book_role and rf.project_device_status still answer from public, because each pins search_path = public, pg_temp",
  async () => {
    const a = await tenant(), b = await tenant();
    const victim = await activeMember(b), insider = await activeMember(b);
    const recordsB = await recordsIn(b.t), rosterB = await membershipsIn(b.t);
    const rolesB = await rolesInTenant(b.t);

    // is_certified: B's founder on a REGISTERED device lists that device as certified.
    const reg = await mkDev(b.founder.user, "registered");
    const asReg = { user: b.founder.user, dev: reg };
    const fake = [sh("devices", [reg, b.founder.user, "certified"])];
    const [r1] = await shadowed(
      asReg,
      fake,
      (s) => s`select rf.is_certified() as c, rf.may_file_record(${b.t}, 'device_added') as f`,
    );
    assertEquals([r1.c, r1.f], [false, false], "an uncertified device stays uncertified");
    assertRefused(
      await pgErr(shadowed(asReg, fake, (s) => fileRecord(s, b.t, reg, "device_added"))),
      "42501",
      "row-level security",
      "an uncertified device files in its own tenant behind a shadow devices",
    );

    // may_file_record: A's founder lists itself as an active member of B.
    const inB = [sh("memberships", [b.t, a.founder.user, "active", null])];
    const [r2] = await shadowed(
      a.founder,
      inB,
      (s) => s`select rf.may_file_record(${b.t}, 'device_added') as f`,
    );
    assertEquals(r2.f, false, "an outsider stays outside");
    assertRefused(
      await pgErr(shadowed(a.founder, inB, (s) => fileRecord(s, b.t, a.founder.dev, "book_role"))),
      "42501",
      "row-level security",
      "A files in B behind a shadow memberships",
    );

    // project_device_status: on its OWN tenant's record, A's founder lists B's member as a member
    // of A and itself as that member's guardian — the write it is after (devices) is real.
    const own = await file(a.founder, a.t, "device_revocation");
    assertRefused(
      await pgErr(shadowed(
        a.founder,
        [
          sh("memberships", [a.t, victim.user, "active", null]),
          sh("guardian_set_members", [victim.user, 1, a.founder.user]),
        ],
        (s) => s`select rf.project_device_status(${own}, ${a.t}, ${victim.dev}, 'revoked')`,
      )),
      "42501",
      "not_revoker",
      "A revokes B's member's device behind shadow memberships + guardians",
    );
    assertEquals(await deviceState(victim.dev), { status: "certified", revoked: false });

    // project_book_role: a role-less book of B, listed as A's, so A's own record would authorise
    // the creator's bootstrap — and the role it is after (book_roles) is real.
    const orphan = crypto.randomUUID();
    await sql`insert into books (id, tenant_id, type) values (${orphan}, ${b.t}, 'business')`;
    const br = await file(a.founder, a.t, "book_role");
    assertRefused(
      await pgErr(shadowed(
        a.founder,
        [sh("books", [orphan, a.t, "business", null])],
        (s) => s`select rf.project_book_role(${br}, ${orphan}, ${a.founder.user}, 'admin', null)`,
      )),
      "P0001",
      "no_record",
      "A founds B's role-less book behind a shadow books",
    );
    assertEquals(await rolesOf(orphan), []);

    // Each arm below isolates one pin: the other functions on its path already read public.
    // active_in_tenant: a record of A's device that EXISTS in B (planted, as a replay would be), and
    // A listed as an active member of B — project_book_role's bootstrap asks only that, then writes
    // a real role on B's role-less book.
    const planted = await ownerRecord(b.t, a.founder.dev, "membership_status");
    const asMemberOfB = [sh("memberships", [b.t, a.founder.user, "active", null])];
    assertRefused(
      await pgErr(shadowed(
        a.founder,
        asMemberOfB,
        (s) =>
          s`select rf.project_book_role(${planted}, ${orphan}, ${a.founder.user}, 'admin', null)`,
      )),
      "42501",
      "not_admin",
      "A founds B's role-less book on a planted record behind a shadow memberships",
    );
    assertEquals(await rolesOf(orphan), []);

    // is_tenant_admin: B's own active NON-admin member lists itself as admin of a book of B; the
    // removal it is after (memberships) is real.
    const ir = await file(insider, b.t, "membership_status");
    const fb = crypto.randomUUID();
    assertRefused(
      await pgErr(shadowed(
        insider,
        [sh("books", [fb, b.t, "business", null]), sh("book_roles", [fb, insider.user, "admin"])],
        (s) => s`select rf.project_membership(${ir}, ${b.t}, ${victim.user}, 'removed')`,
      )),
      "42501",
      "not_admin",
      "B's non-admin member removes a fellow member behind shadow books + book_roles",
    );
    assertEquals(await statusOf(b.t, victim.user), "active");

    // project_membership's own founder test: on the planted record, A shows B as memberless — the
    // projection must not answer `applied` to the edge.
    assertRefused(
      await pgErr(shadowed(
        a.founder,
        [sh("memberships")],
        (s) => s`select rf.project_membership(${planted}, ${b.t}, ${a.founder.user}, 'active')`,
      )),
      "42501",
      "not_admin",
      "A founds B, which a shadow memberships shows empty",
    );

    // require_record: a record that does not exist, listed as A's in a memberless tenant — the
    // founder's membership it is after (memberships) is real.
    const e = await emptyTenant();
    assertRefused(
      await pgErr(shadowed(
        a.founder,
        [sh("signed_records", [crypto.randomUUID(), e, a.founder.dev])],
        async (s) => {
          const [x] = await s`select id from pg_temp.signed_records`;
          await s`select rf.project_membership(${x.id}, ${e}, ${a.founder.user}, 'active')`;
        },
      )),
      "P0001",
      "no_record",
      "A founds a tenant on a record that exists only in its own session",
    );
    assertEquals(await membershipsIn(e), [], "no membership without a record");

    // Nothing moved, and the pin is what the catalogue says.
    assertEquals(await recordsIn(b.t), recordsB + 2, "only the planted and the insider's records");
    assertEquals(await membershipsIn(b.t), rosterB);
    assertEquals(await rolesInTenant(b.t), rolesB);
    const pinned = await sql`select p.oid::regprocedure::text as f, p.proconfig as c
      from pg_proc p where p.oid = any(array[
        'rf.is_certified()', 'rf.active_in_tenant(uuid)', 'rf.is_tenant_admin(uuid)',
        'rf.require_record(uuid,uuid)', 'rf.may_file_record(uuid,text)',
        'rf.project_membership(uuid,uuid,uuid,text)',
        'rf.project_book_role(uuid,uuid,uuid,text,bigint)',
        'rf.project_device_status(uuid,uuid,uuid,text)']::regprocedure[]) order by 1`;
    assertEquals(pinned.length, 8);
    for (const r of pinned) {
      assertEquals(r.c, ["search_path=public, pg_temp"], `${r.f} lists pg_temp last`);
    }
  },
);
