// Hostile-query suite for desk PGT1 (🔴 SECURITY, owner-approved 3 Oct 2026; pre-existing since
// 0005): no function in schema rf may read a relation — or a row type — from the CALLER's temp
// schema. ADR 2026-09-05d §2 treats rf_api as hostile and makes the database the boundary; 03 §2.5 🔒
// puts RLS on every table. Both are only as strong as the functions the policies and triggers call.
//
// Why HEAD (0005 … 0023) is open:
//   * rf_api holds TEMPORARY on the database through PUBLIC (Postgres' default; no migration revokes
//     it), so it can create a temp table named like any public table in its OWN session.
//   * Postgres searches the session's temp schema FIRST for relation and type names unless a search
//     path lists pg_temp explicitly — probe on HEAD, as rf_api, after one `create temp table`:
//     current_schemas(true) = {pg_temp_N, pg_catalog, public}. The CREATE FUNCTION reference's
//     "Writing SECURITY DEFINER Functions Safely" says to write pg_temp LAST for exactly this reason.
//   * 62 SECURITY DEFINER functions in rf pinned `search_path = public` (all but the eight 0022 §5
//     repaired), and the 20 SECURITY INVOKER ones pinned nothing — they run under whatever path the
//     caller set, `pg_temp, public` included.
// So a hostile rf_api session could feed fake rows to a definer helper an RLS policy calls
// (rf.book_role → envelopes_select / envelopes_insert; rf.book_tenant; rf.shares_tenant;
// rf.device_visible), to an invoker guard (invite_guard, recovery_sheet_guard,
// guardian_set_member_guard), and to the two counters that are the server's only "new powers"
// (ADR 2026-09-05b §7: rf.push_rate_check's throttle, envelopes_usage's quota bump).
// 0024 pins `public, pg_temp` on every function in rf; E-03-84 is the tripwire that keeps it so.
//
//   E-03-81  read-side definer helpers answer from public, not from a shadow
//   E-03-82  a stranger's shadowed books/book_roles buy no role, no read and no write of a book
//   E-03-83  invoker guards read public even when the caller's own path is `pg_temp, public`
//   E-03-84  catalogue tripwire: every rf routine's search_path ends in pg_temp
//   E-03-85  control: every legitimate path these functions serve still works
//   E-03-86  the throttle and the quota count into public, never into a shadow
//
// Every hostile query runs on a FRESH rf_api connection built by _pg_api.ts's apiSql (it asserts
// current_user = rf_api, not superuser, not BYPASSRLS) — fresh, because PL/pgSQL caches statement
// plans per session and an attacker shadows first, in its own session. Fixtures are written by the
// schema owner. Blobs, hashes and signatures are random bytes; no ledger content, no phone number
// (CLAUDE.md rule 4).
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`); without it every test is SKIPPED and says
// why, and RLS_REQUIRE=1 makes that a failure.
import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "@std/assert";
import postgres from "postgres";
import { apiSql } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — search_path_pg_temp.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP search_path_pg_temp.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql; // the schema owner: fixtures and fresh reads only
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

// ---------------------------------------------------------------- errors
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
function assertRefused(e: PgErr, code: string, message: string, what: string) {
  assertEquals(
    e.code,
    code,
    `${what}: refused with ${code} (${message}), got ${e.code} ${e.message}`,
  );
  assertStringIncludes(e.message, message, what);
}

// ---------------------------------------------------------------- fixtures (owner)
interface P {
  user: string;
  dev: string;
}
async function mkUser(): Promise<string> {
  const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${rand(32)}, ${rand(40)})
    returning id`;
  return u.id as string;
}
async function mkPerson(): Promise<P> {
  const user = await mkUser();
  const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${user}, ${rand(32)}, ${rand(32)}, 'certified') returning id`;
  return { user, dev: d.id as string };
}
/** ADR 2026-10-03b §1 (0026): a guardian set names a tenant its subject is active in and every
 *  guardian is a member of — a fresh one, founded by the subject (06 §5), guardians pending. */
async function home(subject: string, guardians: string[]): Promise<string> {
  const [t] = await sql`insert into tenants (type) values ('family') returning id`;
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t.id}, ${subject}, 'active')`;
  for (const g of guardians) {
    await sql`insert into memberships (tenant_id, user_id, status)
      values (${t.id}, ${g}, 'joined_pending_verification')`;
  }
  return t.id as string;
}
interface Tn {
  t: string;
  admin: P;
  book: string;
}
/** A family tenant on the `family` plan (twelve seats, so no cap answers for the check under
 *  test) whose founder is active and admin of one business book. */
async function tenant(): Promise<Tn> {
  const [row] = await sql`insert into tenants (type) values ('family') returning id`;
  const t = row.id as string;
  await sql`insert into subscriptions (tenant_id, plan) values (${t}, 'family')`;
  const admin = await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${admin.user}, 'active')`;
  const book = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type) values (${book}, ${t}, 'business')`;
  await sql`insert into book_roles (book_id, user_id, role) values (${book}, ${admin.user}, 'admin')`;
  return { t, admin, book };
}
async function ownerRecord(tenant: string, device: string, kind: string): Promise<string> {
  const id = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${id}, 1, ${tenant}, ${kind}, '{}'::jsonb, ${rand(8)}, ${device}, ${rand(64)}, 1)`;
  return id;
}
/** One envelope in `book` — random bytes, no content — written by the owner. */
async function ownerEnvelope(tn: Tn): Promise<string> {
  const id = crypto.randomUUID();
  await sql`insert into envelopes (envelope_id, tenant_id, book_id, object_id, object_type,
      key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
    values (${id}, ${tn.t}, ${tn.book}, gen_random_uuid(), 'entry', 1, 1, 1, ${tn.admin.dev}, 1,
      ${rand(32)}, 8, ${rand(8)})`;
  return id;
}
/** The envelope a caller pushes: book `book`, tenant `tenant`, its own device. */
function pushEnvelope(s: postgres.TransactionSql, tenant: string, book: string, dev: string) {
  return s`insert into public.envelopes (envelope_id, tenant_id, book_id, object_id, object_type,
      key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
    values (gen_random_uuid(), ${tenant}, ${book}, gen_random_uuid(), 'entry', 1, 1, 1, ${dev}, 1,
      ${rand(32)}, 8, ${rand(8)})`;
}
async function usage(book: string): Promise<number> {
  const [r] = await sql`select coalesce((select envelope_count from book_usage
    where book_id = ${book}), 0)::int as n`;
  return r.n as number;
}

// ---------------------------------------------------------------- the hostile session
/** A temp relation rf_api creates in its OWN session, named like a public one, open to every role
 *  (the definer functions run as the schema owner, which on hosted Supabase is not a superuser),
 *  dropped at commit or rollback. Ids, counts and timestamps only. */
interface Shadow {
  table: string;
  cols: string;
  rows: (string | number | null)[][];
}
const sh = (table: string, cols: string, ...rows: (string | number | null)[][]): Shadow => ({
  table,
  cols,
  rows,
});

/** One transaction on a FRESH rf_api connection: the caller's claims, `path` as its own session
 *  search_path when given, then the shadows — each asserted to be what the bare name now means in
 *  that session, so a refusal below is the pin's and never a dud fixture. Commits on success. */
async function hostile<T>(
  p: P | null,
  shadows: Shadow[],
  fn: (s: postgres.TransactionSql) => Promise<T>,
  path?: string,
): Promise<T> {
  const api = await apiSql(url!);
  try {
    return await api.begin(async (s) => {
      if (p) await s`select rf.set_claims(${p.user}::uuid, ${p.dev}::uuid)`;
      if (path) await s.unsafe(`set local search_path = ${path}`);
      for (const { table, cols, rows } of shadows) {
        await s.unsafe(`create temp table ${table} (${cols}) on commit drop`);
        await s.unsafe(`grant all on pg_temp.${table} to public`);
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
    await api.end();
  }
}

// ---------------------------------------------------------------- E-03-81
test(
  "E-03-81 read-side SECURITY DEFINER helpers answer from public, not from a caller's temp table: rf.book_tenant of an unknown book stays null and of a real book stays its tenant under a `books` shadow, rf.shares_tenant stays false for a stranger under a `memberships` shadow, rf.device_visible stays false for a stranger's device under a `devices` shadow",
  async () => {
    const victim = await tenant();
    const mine = await tenant();
    const me = mine.admin;
    const ghost = crypto.randomUUID();
    const fake = crypto.randomUUID();

    // the orchestrator's probe: an unknown book has no tenant, whatever the caller's session holds
    const bt = await hostile(me, [
      sh("books", "id uuid, tenant_id uuid", [ghost, fake], [victim.book, mine.t]),
    ], async (s) => {
      const [r] = await s`select rf.book_tenant(${ghost}::uuid) as ghost,
        rf.book_tenant(${victim.book}::uuid) as real`;
      return r;
    });
    assertEquals(bt.ghost, null, "rf.book_tenant(unknown book) is null under a `books` shadow");
    assertEquals(bt.real, victim.t, "rf.book_tenant(real book) is its real tenant under a shadow");

    // shares_tenant: the shadow puts me and the victim's admin in one tenant
    const shares = await hostile(me, [
      sh(
        "memberships",
        "tenant_id uuid, user_id uuid, status text",
        [fake, me.user, "active"],
        [fake, victim.admin.user, "active"],
      ),
    ], async (s) => {
      const [r] = await s`select rf.shares_tenant(${victim.admin.user}::uuid) as v`;
      return r.v as boolean;
    });
    assertEquals(
      shares,
      false,
      "rf.shares_tenant(stranger) stays false under a `memberships` shadow",
    );

    // device_visible: the shadow says the victim's device is mine
    const visible = await hostile(me, [
      sh("devices", "id uuid, user_id uuid, status text", [victim.admin.dev, me.user, "certified"]),
    ], async (s) => {
      const [r] = await s`select rf.device_visible(${victim.admin.dev}::uuid) as v`;
      return r.v as boolean;
    });
    assertEquals(visible, false, "rf.device_visible(stranger's device) stays false under a shadow");
  },
);

// ---------------------------------------------------------------- E-03-82
test(
  "E-03-82 a stranger's shadowed books, book_roles and memberships buy nothing in another tenant's book: rf.book_role stays null, rf.is_tenant_admin false, rf.book_access reports no role and no membership, envelopes_select returns none of the book's envelopes and envelopes_insert refuses a push into it",
  async () => {
    const victim = await tenant();
    await ownerEnvelope(victim);
    const mine = await tenant();
    const me = mine.admin; // certified and active — in its OWN tenant only
    // The shadow: the victim's book belongs to MY tenant (so rf.active_in_tenant, pinned by 0022,
    // answers true from the real memberships) and I am its admin; and I am active in theirs.
    const shadows = () => [
      sh("books", "id uuid, tenant_id uuid, archived_at timestamptz", [victim.book, mine.t, null]),
      sh("book_roles", "book_id uuid, user_id uuid, role text", [victim.book, me.user, "admin"]),
      sh(
        "memberships",
        "tenant_id uuid, user_id uuid, status text",
        [victim.t, me.user, "active"],
        [mine.t, me.user, "active"],
      ),
    ];

    const r = await hostile(me, shadows(), async (s) => {
      const [h] = await s`select rf.book_role(${victim.book}::uuid) as role,
        rf.is_tenant_admin(${victim.t}::uuid) as admin,
        (select count(*)::int from public.envelopes where book_id = ${victim.book}) as seen`;
      const acc =
        await s`select tenant_id, role, membership_status from rf.book_access(${victim.book}::uuid)`;
      return { role: h.role, admin: h.admin, seen: h.seen, t: h.t, acc };
    });
    assertEquals(r.role, null, "rf.book_role(stranger's book) stays null under the shadows");
    assertEquals(r.admin, false, "rf.is_tenant_admin(stranger's tenant) stays false");
    assertEquals(r.seen, 0, "envelopes_select shows a stranger none of the book's envelopes");
    assertEquals(r.acc.length, 1, "rf.book_access answers for the real book, once");
    assertEquals(r.acc[0].tenant_id, victim.t, "rf.book_access: the book's real tenant");
    assertEquals(r.acc[0].role, null, "rf.book_access: the stranger holds no role");
    assertEquals(r.acc[0].membership_status, null, "rf.book_access: nor a membership");

    const before = await usage(victim.book);
    const push = await pgErr(
      hostile(me, shadows(), (s) => pushEnvelope(s, mine.t, victim.book, me.dev)),
    );
    assertRefused(push, "42501", "row-level security", "envelopes_insert into a stranger's book");
    assertEquals(await usage(victim.book), before, "nothing landed in the stranger's book");
  },
);

// ---------------------------------------------------------------- E-03-83
test(
  "E-03-83 SECURITY INVOKER guards read public even when the caller's own search_path is `pg_temp, public`: invite_guard refuses an invite whose record is not an `invite` under a `signed_records` shadow, recovery_sheet_guard keeps its one-per-minute flood limit under a `recovery_sheets` shadow, guardian_set_member_guard keeps a 2-of-2 set full under `guardian_sets`/`guardian_set_members` shadows",
  async () => {
    // invite_guard: a real record of the wrong kind; the shadow calls it an invite
    const tn = await tenant();
    const wrongKind = await ownerRecord(tn.t, tn.admin.dev, "book_role");
    const invite = (s: postgres.TransactionSql) =>
      s`insert into public.invites (tenant_id, invitee_hmac, nonce, created_by, source_record_id)
        values (${tn.t}, ${rand(32)}, ${rand(16)}, ${tn.admin.user}, ${wrongKind})`;
    const plain = await pgErr(hostile(tn.admin, [], invite));
    assertRefused(plain, "23514", "no_record", "control: invite_guard refuses a non-invite record");
    const shadowedInvite = await pgErr(
      hostile(
        tn.admin,
        [sh("signed_records", "id uuid, tenant_id uuid, kind text", [wrongKind, tn.t, "invite"])],
        invite,
        "pg_temp, public",
      ),
    );
    assertRefused(
      shadowedInvite,
      "23514",
      "no_record",
      "invite_guard under a signed_records shadow",
    );
    const [inv] =
      await sql`select count(*)::int as n from invites where source_record_id = ${wrongKind}`;
    assertEquals(inv.n, 0, "no invite stands on a non-invite record");

    // recovery_sheet_guard: version 1 was published a moment ago, so version 2 waits a minute
    const me = await mkPerson();
    await sql`insert into recovery_sheets (user_id, sheet_version, blob) values (${me.user}, 1, ${
      rand(64)
    })`;
    const sheet = (s: postgres.TransactionSql) =>
      s`insert into public.recovery_sheets (user_id, sheet_version, blob)
        values (${me.user}, 2, ${rand(64)})`;
    const flood = await pgErr(
      hostile(me, [
        sh(
          "recovery_sheets",
          "user_id uuid, sheet_version int, created_at timestamptz",
          [me.user, 1, "2000-01-01T00:00:00Z"],
        ),
      ], sheet),
    );
    assertRefused(
      flood,
      "23514",
      "sheet_flood",
      "recovery_sheet_guard under a recovery_sheets shadow",
    );
    const [sv] =
      await sql`select max(sheet_version)::int as v from recovery_sheets where user_id = ${me.user}`;
    assertEquals(sv.v, 1, "no second sheet inside the minute");

    // guardian_set_member_guard: a real 2-of-2 set with both guardians in; the shadow says 5, empty
    const subj = await mkPerson();
    const g1 = await mkUser(), g2 = await mkUser(), g3 = await mkUser();
    await sql`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
      values (${subj.user}, 1, 2, 2, ${await home(subj.user, [g1, g2, g3])})`;
    await sql`insert into guardian_set_members (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
      values (${subj.user}, 1, ${g1}, ${rand(32)}), (${subj.user}, 1, ${g2}, ${rand(32)})`;
    const third = (s: postgres.TransactionSql) =>
      s`insert into public.guardian_set_members
          (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
        values (${subj.user}, 1, ${g3}, ${rand(32)})`;
    const full = await pgErr(
      hostile(subj, [
        sh(
          "guardian_sets",
          "subject_user_id uuid, share_set_version int, n int, k int",
          [subj.user, 1, 5, 3],
        ),
        sh(
          "guardian_set_members",
          "subject_user_id uuid, share_set_version int, guardian_user_id uuid",
        ),
      ], third),
    );
    assertRefused(full, "23514", "guardian_set_full", "guardian_set_member_guard under shadows");
    const [gm] = await sql`select count(*)::int as n from guardian_set_members
      where subject_user_id = ${subj.user} and share_set_version = 1`;
    assertEquals(gm.n, 2, "the 2-of-2 set still holds two guardians");
  },
);

// ---------------------------------------------------------------- E-03-84
test(
  "E-03-84 catalogue tripwire: every routine in schema rf — SECURITY DEFINER and INVOKER, trigger functions included — pins a search_path that ends in pg_temp and names it nowhere else, so a migration that forgets the pin fails here",
  async () => {
    const rows = await sql`select p.oid::regprocedure::text as fn, p.prosecdef as definer,
        coalesce(p.proconfig, '{}') as cfg
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.prokind in ('f', 'p')
        and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass
                          and d.objid = p.oid and d.deptype = 'e')
      order by 1`;
    // 82 on a fresh database after 0023 (62 definer + 20 invoker); a vacuous query passes nothing
    assert(
      rows.length >= 82,
      `precondition: the catalogue query sees rf's routines (${rows.length})`,
    );
    assert(rows.some((r) => r.definer) && rows.some((r) => !r.definer), "precondition: both kinds");
    const bad: string[] = [];
    for (const r of rows) {
      const sp = (r.cfg as string[]).find((c) => c.startsWith("search_path="));
      const path = sp ? sp.slice("search_path=".length).split(",").map((x) => x.trim()) : [];
      const ok = path.length >= 2 && path[path.length - 1] === "pg_temp" &&
        path.indexOf("pg_temp") === path.length - 1 && path[0] !== "pg_temp";
      if (!ok) {
        bad.push(`${r.fn} [${r.definer ? "definer" : "invoker"}] ${sp ?? "(no search_path)"}`);
      }
    }
    assertEquals(bad, [], `every rf routine pins search_path … , pg_temp (${bad.length} do not)`);
  },
);

// ---------------------------------------------------------------- E-03-85
test(
  "E-03-85 control — behaviour unchanged: rf.set_claims' SET LOCAL claims outlive the call and end with the transaction; the real admin's rf.book_tenant, rf.book_role, rf.is_tenant_admin, rf.book_access and envelopes_select answer as before, and a push, an invite on a real `invite` record, a first recovery sheet and a guardian joining a set with room all go through",
  async () => {
    const tn = await tenant();
    const env = await ownerEnvelope(tn);
    const a = tn.admin;

    // the claims: rf.set_claims now carries its own SET clause, and its set_config(…, true) must
    // still reach the rest of the transaction (only search_path is restored on the way out)
    const api = await apiSql(url!);
    try {
      const inTx = await api.begin(async (s) => {
        await s`select rf.set_claims(${a.user}::uuid, ${a.dev}::uuid)`;
        const [r] = await s`select rf.user_id() as u, rf.device_id() as d,
          current_setting('search_path') as sp`;
        return r;
      });
      assertEquals(inTx.u, a.user, "rf.user_id() after rf.set_claims, same transaction");
      assertEquals(inTx.d, a.dev, "rf.device_id() after rf.set_claims, same transaction");
      assertNotEquals(inTx.sp, "public, pg_temp", "the caller's own search_path is its own again");
      const [after] = await api`select rf.user_id() as u, rf.device_id() as d`;
      assertEquals(after.u, null, "the claims end with the transaction (SET LOCAL)");
      assertEquals(after.d, null, "the device claim too");
    } finally {
      await api.end();
    }

    const r = await hostile(a, [], async (s) => {
      const [h] =
        await s`select rf.book_tenant(${tn.book}::uuid) as t, rf.book_role(${tn.book}::uuid) as role,
        rf.is_tenant_admin(${tn.t}::uuid) as admin,
        array(select envelope_id::text from public.envelopes where book_id = ${tn.book}) as seen`;
      const acc =
        await s`select tenant_id, role, membership_status from rf.book_access(${tn.book}::uuid)`;
      return { role: h.role, admin: h.admin, seen: h.seen, t: h.t, acc };
    });
    assertEquals(r.t, tn.t, "rf.book_tenant(own book)");
    assertEquals(r.role, "admin", "rf.book_role(own book)");
    assertEquals(r.admin, true, "rf.is_tenant_admin(own tenant)");
    assertEquals(r.seen, [env], "envelopes_select shows the admin its book's envelope");
    assertEquals(r.acc.length, 1, "rf.book_access(own book) answers once");
    assertEquals(r.acc[0].role, "admin", "rf.book_access: role");
    assertEquals(r.acc[0].membership_status, "active", "rf.book_access: membership");

    // writes: a push (and its usage bump), an invite on a real invite record
    const before = await usage(tn.book);
    await hostile(a, [], (s) => pushEnvelope(s, tn.t, tn.book, a.dev));
    assertEquals(await usage(tn.book), before + 1, "the push landed and counted");
    const rec = await ownerRecord(tn.t, a.dev, "invite");
    await hostile(
      a,
      [],
      (s) =>
        s`insert into public.invites (tenant_id, invitee_hmac, nonce, created_by, source_record_id)
        values (${tn.t}, ${rand(32)}, ${rand(16)}, ${a.user}, ${rec})`,
    );
    const [inv] = await sql`select status from invites where source_record_id = ${rec}`;
    assertEquals(inv?.status, "sent", "the invite stands on its invite record");

    // a first recovery sheet; a guardian set with room
    const me = await mkPerson();
    await hostile(
      me,
      [],
      (s) =>
        s`insert into public.recovery_sheets (user_id, sheet_version, blob) values (${me.user}, 1, ${
          rand(64)
        })`,
    );
    const [sv] =
      await sql`select max(sheet_version)::int as v from recovery_sheets where user_id = ${me.user}`;
    assertEquals(sv.v, 1, "the first sheet is published");
    const g1 = await mkUser(), g2 = await mkUser();
    const meHome = await home(me.user, [g1, g2]);
    await hostile(me, [], async (s) => {
      await s`insert into public.guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
        values (${me.user}, 1, 2, 2, ${meHome})`;
      await s`insert into public.guardian_set_members
          (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
        values (${me.user}, 1, ${g1}, ${rand(32)}), (${me.user}, 1, ${g2}, ${rand(32)})`;
    });
    const [gm] = await sql`select count(*)::int as n from guardian_set_members
      where subject_user_id = ${me.user}`;
    assertEquals(gm.n, 2, "both guardians joined the set");
  },
);

// ---------------------------------------------------------------- E-03-86
test(
  "E-03-86 the server's only new powers count into public, never into a shadow (ADR 2026-09-05b §7): rf.push_rate_check refuses a device already at its 600-a-minute limit under a `push_rate` shadow, and envelopes_usage bumps public.book_usage — the quota — under a `book_usage` shadow",
  async () => {
    const tn = await tenant();
    const a = tn.admin;

    // the throttle: the real row says the minute is spent
    await sql`insert into push_rate (device_id, minute_start, minute_count, hour_start, hour_count,
        day_start, day_bytes)
      values (${a.dev}, now(), 600, now(), 600, now(), 0)`;
    const plainRate = await hostile(a, [], async (s) => {
      const [r] = await s`select rf.push_rate_check(${a.dev}::uuid, 1, 0) as ok`;
      return r.ok as boolean;
    });
    assertEquals(plainRate, false, "control: the spent minute refuses one more");
    const shadowRate = await hostile(a, [
      sh(
        "push_rate",
        "device_id uuid primary key, minute_start timestamptz not null, minute_count int not null default 0, hour_start timestamptz not null, hour_count int not null default 0, day_start timestamptz not null, day_bytes bigint not null default 0",
      ),
    ], async (s) => {
      const [r] = await s`select rf.push_rate_check(${a.dev}::uuid, 1, 0) as ok`;
      return r.ok as boolean;
    });
    assertEquals(shadowRate, false, "rf.push_rate_check reads the real minute under a shadow");
    const [pr] = await sql`select minute_count from push_rate where device_id = ${a.dev}`;
    assertEquals(pr.minute_count, 600, "the throttle row is untouched");

    // the quota: an accepted push is counted where the quota reads it
    const before = await usage(tn.book);
    await hostile(a, [
      sh(
        "book_usage",
        "book_id uuid primary key, tenant_id uuid, envelope_count bigint not null default 0, bytes bigint not null default 0, updated_at timestamptz not null default now()",
      ),
    ], (s) => pushEnvelope(s, tn.t, tn.book, a.dev));
    assertEquals(
      await usage(tn.book),
      before + 1,
      "envelopes_usage counted into public.book_usage",
    );
  },
);
