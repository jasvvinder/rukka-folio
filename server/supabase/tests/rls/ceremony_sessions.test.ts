// Hostile-query suite for the ceremony session record — ADR 2026-09-13d ruling 4 🔒 (RATIFIED
// 13 Sep 2026), 04 §6.1/§6.3/§6.4/§8.6/§10, 03 §2.2/§2.5, 06 §7.
//
// The record is what makes the commitment-based SAS work. The shipped 04 §6.1 code was derivable by
// the server in ~2·10⁴ hashes (ADR §1); the repair holds only while the server cannot forge,
// reorder, re-write or compute these three values. So every rule gets the same three adversaries:
//
//   * a CERTIFIED device of ANOTHER tenant,
//   * an UNCERTIFIED device of THIS tenant,
//   * the API role itself (`rf_api` with whatever claims it likes) reaching the table directly.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-13d-1, E-06-20 … E-06-26.
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — ceremony_sessions.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP ceremony_sessions.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;

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
const bytes = (n: number, fill: number) => new Uint8Array(n).fill(fill);

interface Fx {
  t1: string;
  t2: string;
  admin1: string;
  admin2: string;
  outsider: string;
  invitee: string;
  dev: Record<string, string>;
}
let fx: Fx;

/** Open a session as the invitee's certified device: the commitment, and nothing else. */
async function commit(fill = 0x5a, user = "invitee", device = "invitee"): Promise<string> {
  const [r] = await asApi(
    (fx as unknown as Record<string, string>)[user],
    fx.dev[device],
    (s) =>
      s`insert into ceremony_sessions (tenant_id, subject_user, subject_device, commitment)
        values (${fx.t1}, ${(fx as unknown as Record<string, string>)[user]}, ${fx.dev[device]}, ${
        bytes(32, fill)
      }) returning id`,
  );
  return r.id as string;
}

async function seed(): Promise<Fx> {
  const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
  const [t2] = await sql`insert into tenants (type) values ('business_group') returning id`;
  // fills are 0xA0+: invites.test.ts shares this database and owns 11–15, 21, 31 and 99
  const mk = async (fill: number) => {
    const [u] = await sql`insert into users (phone_hmac, phone_ct)
      values (${bytes(32, fill)}, ${bytes(40, fill)}) returning id`;
    return u.id as string;
  };
  const admin1 = await mk(0xa1),
    admin2 = await mk(0xa2),
    outsider = await mk(0xa3),
    invitee = await mk(0xa4);

  const dev: Record<string, string> = {};
  for (
    const [name, user, status] of [
      ["admin1", admin1, "certified"],
      ["admin1raw", admin1, "registered"], // uncertified device of THIS tenant
      ["admin2", admin2, "certified"],
      ["outsider", outsider, "certified"], // certified device of ANOTHER tenant
      ["invitee", invitee, "certified"],
      ["invitee2", invitee, "certified"], // a SECOND device of the subject
      ["inviteeraw", invitee, "registered"],
    ] as const
  ) {
    const [d] = await sql`insert into devices (user_id, pub_ed, pub_x, status)
      values (${user}, ${bytes(32, 4)}, ${bytes(32, 5)}, ${status}) returning id`;
    dev[name] = d.id;
  }

  // founders, then a ceremony for admin2 (the guard refuses `active` without one), then the
  // invitee sitting at joined_pending_verification — exactly where the code path is used.
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${admin1}, 'active'), (${t2.id}, ${outsider}, 'active')`;
  await sql`insert into verification_events (tenant_id, subject_user, verifier_user, method, result)
    values (${t1.id}, ${admin2}, ${admin1}, 'qr_in_person', 'verified')`;
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${admin2}, 'active')`;
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${invitee}, 'joined_pending_verification')`;

  return { t1: t1.id, t2: t2.id, admin1, admin2, outsider, invitee, dev };
}

Deno.test({
  name:
    "E-13d-1 the ceremony session record: opaque bytes, the invitee writes commitment and opening, only an active member writes verifier_random, every value immutable once written, and the server computes nothing (ADR 2026-09-13d ruling 4)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();

    // ---- the machine is in the DATABASE, not only in the edge function (the 0006 precedent)
    const trg =
      await sql`select tgname, tgtype from pg_trigger t join pg_class c on c.oid = t.tgrelid
      where not t.tgisinternal and c.relname = 'ceremony_sessions'`;
    assertEquals(trg.length, 1, "ceremony_sessions carries its guard");
    assert((Number(trg[0].tgtype) & 2) !== 0, "the guard runs BEFORE the write");

    // ---- the shape of ruling 4: 32 / 16 / 16 opaque bytes plus server timestamps
    const cols = await sql<{ column_name: string; data_type: string; is_nullable: string }[]>`
      select column_name, data_type, is_nullable from information_schema.columns
      where table_name = 'ceremony_sessions' order by ordinal_position`;
    const byName = new Map(cols.map((c) => [c.column_name, c]));
    for (const c of ["commitment", "verifier_random", "opening"]) {
      assertEquals(byName.get(c)?.data_type, "bytea", `${c} is opaque bytes`);
    }
    assertEquals(
      byName.get("commitment")?.is_nullable,
      "NO",
      "a session is born with its commitment",
    );
    for (const c of ["committed_at", "verifier_random_at", "opened_at", "expires_at"]) {
      assertEquals(
        byName.get(c)?.data_type,
        "timestamp with time zone",
        `${c} is a server timestamp`,
      );
    }

    // ---- (1) the invitee commits; lengths are pinned; the server stamps both timestamps itself
    const id = await commit(0x11);
    const [row] = await sql`select * from ceremony_sessions where id = ${id}`;
    assertEquals(row.subject_user, fx.invitee);
    assertEquals(row.verifier_random, null, "r_V does not exist yet");
    assertEquals(row.opening, null, "nothing is opened yet");
    assertEquals(
      new Date(row.expires_at as string).getTime() - new Date(row.committed_at as string).getTime(),
      10 * 60 * 1000,
      "ten minutes from the commitment's SERVER timestamp (04 §6.3, ruling 3)",
    );
    for (const n of [31, 33, 16]) {
      assertEquals(
        await pgCode(
          asApi(
            fx.invitee,
            fx.dev.invitee,
            (s) =>
              s`insert into ceremony_sessions (tenant_id, subject_user, subject_device, commitment)
                values (${fx.t1}, ${fx.invitee}, ${fx.dev.invitee}, ${bytes(n, 1)})`,
          ),
        ),
        "23514",
        `a ${n}-byte commitment is not a BLAKE2b-256`,
      );
    }

    // ---- (2) an active member draws r_V; (3) the committing device opens. Happy path, in order.
    const t = await asApi(
      fx.admin1,
      fx.dev.admin1,
      (s) => s`select rf.ceremony_contribute(${id}, ${bytes(16, 0x22)}) as at`,
    );
    assert(t[0].at !== null, "r_V lands");
    const opened = await asApi(
      fx.invitee,
      fx.dev.invitee,
      (s) => s`select rf.ceremony_open(${id}, ${bytes(16, 0x33)}) as at`,
    );
    assert(opened[0].at !== null, "the opening lands");
    const [done] = await sql`select * from ceremony_sessions where id = ${id}`;
    assertEquals(Array.from(done.verifier_random as Uint8Array), Array.from(bytes(16, 0x22)));
    assertEquals(Array.from(done.opening as Uint8Array), Array.from(bytes(16, 0x33)));
    assertEquals(done.verifier_user, fx.admin1, "the row records WHO contributed");
    assertEquals(done.verifier_device, fx.dev.admin1);
    assert(
      new Date(done.opened_at as string) >= new Date(done.verifier_random_at as string),
      "the opening follows r_V in time as well as in order",
    );

    // ---- rule 4: NO SERVER-SIDE COMPUTATION. Nothing derives, hashes or compares a code.
    // The three values reach the row byte-for-byte, and no function of the schema touches a digest.
    const src = await Deno.readTextFile(
      new URL("../../migrations/0007_ceremony_sessions.sql", import.meta.url),
    );
    const code = src.replace(/--[^\n]*/g, ""); // comments quote the formulas; code must not
    for (const forbidden of ["digest(", "hmac(", "blake2", "sha256", "sha512", "crypt("]) {
      assert(
        !code.toLowerCase().includes(forbidden),
        `0007 must not compute over the ceremony values — found ${forbidden} (04 §8.6)`,
      );
    }
    // and no function in the schema reads two of the three values together, which is what a
    // server-side check of the commitment would have to do
    const bodies = await sql<{ nm: string; prosrc: string }[]>`
      select p.proname as nm, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname like 'ceremony%'`;
    assert(bodies.length >= 3, "the relay is three functions and a guard, no more");
    for (const b of bodies) {
      // strip comments (they quote the formulas) and the UPDATE statements (their `set x = y` is
      // an assignment, not a comparison) — what is left is every test the server makes
      const body = b.prosrc.replace(/--[^\n]*/g, "")
        .replace(/update\s+ceremony_sessions[\s\S]*?;/gi, "")
        .toLowerCase();
      assert(!/digest|hmac|sha2|blake|md5/.test(body), `rf.${b.nm} hashes something (04 §8.6)`);
      // the only comparisons of the three values are old-vs-new immutability checks and the
      // length pins; nothing compares a stored value against something the server derived
      for (
        const m of body.matchAll(
          /(commitment|verifier_random|opening)\s*(=|<>|is distinct from)\s*([a-z_.0-9]+)/g,
        )
      ) {
        assert(
          /^(new|old)\./.test(m[3]) || m[3] === "null",
          `rf.${b.nm} compares ${m[1]} with ${m[3]} — the server validates no code (ruling 4)`,
        );
      }
    }
  },
});

Deno.test({
  name:
    "E-06-20 who may commit: the subject's own certified device only — another tenant, an uncertified device, a second device speaking for the subject and the API role forging a subject are all refused (ruling 4 rule 1)",
  ignore,
  async fn() {
    const ins = (user: string, device: string, subjUser: string, subjDev: string) =>
      asApi(
        user,
        device,
        (s) =>
          s`insert into ceremony_sessions (tenant_id, subject_user, subject_device, commitment)
            values (${fx.t1}, ${subjUser}, ${subjDev}, ${bytes(32, 9)})`,
      );

    // certified device of ANOTHER tenant, naming this tenant
    assertEquals(
      await pgCode(ins(fx.outsider, fx.dev.outsider, fx.outsider, fx.dev.outsider)),
      "42501",
      "another tenant cannot open a ceremony here",
    );
    // …and it cannot impersonate the invitee either
    assertEquals(
      await pgCode(ins(fx.outsider, fx.dev.outsider, fx.invitee, fx.dev.invitee)),
      "42501",
    );
    // UNCERTIFIED device of THIS tenant (the invitee's own registered-but-uncertified device)
    assertEquals(
      await pgCode(ins(fx.invitee, fx.dev.inviteeraw, fx.invitee, fx.dev.inviteeraw)),
      "42501",
      "an uncertified device commits to nothing (ADR 2026-09-05d §2)",
    );
    // the API role with any claims it likes: it cannot name a subject that is not the caller,
    // nor a device that is not the calling device
    assertEquals(
      await pgCode(ins(fx.admin1, fx.dev.admin1, fx.invitee, fx.dev.invitee)),
      "42501",
      "an admin cannot commit on the invitee's behalf",
    );
    assertEquals(
      await pgCode(ins(fx.invitee, fx.dev.invitee, fx.invitee, fx.dev.invitee2)),
      "42501",
      "the committing device is the calling device",
    );
    // and nobody at all with no claims
    assertEquals(
      await pgCode(
        ins(null as unknown as string, null as unknown as string, fx.invitee, fx.dev.invitee),
      ),
      "42501",
    );
    // the honest case still works
    assert(await commit(0x12));
  },
});

Deno.test({
  name:
    "E-06-21 who may draw r_V: an already-verified ACTIVE member only — another tenant, an uncertified device, the subject themself and a pending member are refused (04 §6.4 delegated)",
  ignore,
  async fn() {
    const id = await commit(0x13);
    const rv = (user: string, device: string) =>
      asApi(user, device, (s) => s`select rf.ceremony_contribute(${id}, ${bytes(16, 7)})`);

    assertEquals(await pgCode(rv(fx.outsider, fx.dev.outsider)), "42501", "another tenant");
    assertEquals(await pgCode(rv(fx.admin1, fx.dev.admin1raw)), "42501", "uncertified device");
    // the subject of THIS session is a pending member, so it never even reaches the self check
    assertEquals(await pgCode(rv(fx.invitee, fx.dev.invitee)), "42501", "the subject is refused");
    // an ACTIVE subject — 04 §6's other three uses put two active members on the two sides — is
    // refused by name: nobody verifies themself
    const mine = await commit(0x2a, "admin1", "admin1");
    assertStringIncludes(
      (await pgErr(
        asApi(
          fx.admin1,
          fx.dev.admin1,
          (s) => s`select rf.ceremony_contribute(${mine}, ${bytes(16, 7)})`,
        ),
      )).message,
      "self_verification",
      "the verifier is never the subject (04 §6)",
    );
    // a member still at joined_pending_verification is not yet "already verified" (04 §6.4)
    const [p] = await sql`insert into users (phone_hmac, phone_ct)
      values (${bytes(32, 0xa5)}, ${bytes(40, 0xa5)}) returning id`;
    const [pd] = await sql`insert into devices (user_id, pub_ed, pub_x, status)
      values (${p.id}, ${bytes(32, 4)}, ${bytes(32, 5)}, 'certified') returning id`;
    await sql`insert into memberships (tenant_id, user_id, status)
      values (${fx.t1}, ${p.id}, 'joined_pending_verification')`;
    assertEquals(await pgCode(rv(p.id, pd.id)), "42501", "pending members do not verify");

    // shape: r_V is 128 bits, never anything else
    for (const n of [8, 15, 17, 32]) {
      assertEquals(
        await pgCode(
          asApi(
            fx.admin1,
            fx.dev.admin1,
            (s) => s`select rf.ceremony_contribute(${id}, ${bytes(n, 7)})`,
          ),
        ),
        "23514",
        `${n} bytes is not r_V`,
      );
    }
    // and the honest active member succeeds — including a DELEGATED one who is not the inviter
    await asApi(
      fx.admin2,
      fx.dev.admin2,
      (s) => s`select rf.ceremony_contribute(${id}, ${bytes(16, 7)})`,
    );
    const [row] = await sql`select verifier_user from ceremony_sessions where id = ${id}`;
    assertEquals(row.verifier_user, fx.admin2, "any active member may verify (04 §6.4)");
  },
});

Deno.test({
  name:
    "E-06-22 who may open: the device that committed, and only it — a second device of the same user, an admin, another tenant and an uncertified device are all refused (ruling 2)",
  ignore,
  async fn() {
    const id = await commit(0x14);
    await asApi(
      fx.admin1,
      fx.dev.admin1,
      (s) => s`select rf.ceremony_contribute(${id}, ${bytes(16, 8)})`,
    );
    const open = (user: string, device: string) =>
      asApi(user, device, (s) => s`select rf.ceremony_open(${id}, ${bytes(16, 9)})`);

    assertEquals(
      await pgCode(open(fx.invitee, fx.dev.invitee2)),
      "42501",
      "a second device of the subject",
    );
    assertEquals(await pgCode(open(fx.invitee, fx.dev.inviteeraw)), "42501", "uncertified device");
    assertEquals(await pgCode(open(fx.admin1, fx.dev.admin1)), "42501", "the verifier cannot open");
    assertEquals(await pgCode(open(fx.outsider, fx.dev.outsider)), "42501", "another tenant");
    for (const n of [8, 15, 17, 32]) {
      assertEquals(
        await pgCode(
          asApi(
            fx.invitee,
            fx.dev.invitee,
            (s) => s`select rf.ceremony_open(${id}, ${bytes(n, 9)})`,
          ),
        ),
        "23514",
      );
    }
    await open(fx.invitee, fx.dev.invitee); // the committing device
    const [row] = await sql`select opening from ceremony_sessions where id = ${id}`;
    assertEquals(Array.from(row.opening as Uint8Array), Array.from(bytes(16, 9)));
  },
});

Deno.test({
  name:
    "E-06-23 immutable once written: rf_api holds no UPDATE or DELETE grant at all, and even the SECURITY DEFINER path refuses a second commitment, a second r_V or a second opening — the grind the commitment exists to stop (ruling 4 rule 2)",
  ignore,
  async fn() {
    // the grant surface, first: SELECT + INSERT and nothing else, like `envelopes` (03 §2.3)
    const privs = await sql<{ privilege_type: string }[]>`
      select distinct privilege_type from information_schema.role_table_grants
      where table_name = 'ceremony_sessions' and grantee = 'rf_api'`;
    assertEquals(
      privs.map((p) => p.privilege_type.toLowerCase()).sort(),
      ["insert", "select"],
      "no UPDATE, no DELETE, ever (CLAUDE.md rule 2 shape)",
    );
    const pols = await sql<{ cmd: string }[]>`
      select cmd from pg_policies where tablename = 'ceremony_sessions' and 'rf_api' = any(roles)`;
    assert(
      !pols.some((p) => ["UPDATE", "DELETE", "ALL"].includes(p.cmd)),
      "there is no UPDATE or DELETE policy for rf_api on this table",
    );

    const id = await commit(0x15);
    // rf_api reaching the table directly: refused by the grant, not by politeness
    assertEquals(
      await pgCode(
        asApi(
          fx.invitee,
          fx.dev.invitee,
          (s) => s`update ceremony_sessions set commitment = ${bytes(32, 0xff)} where id = ${id}`,
        ),
      ),
      "42501",
    );
    assertEquals(
      await pgCode(
        asApi(fx.admin1, fx.dev.admin1, (s) => s`delete from ceremony_sessions where id = ${id}`),
      ),
      "42501",
    );

    // and the guard refuses the same rewrites even to a superuser-owned definer path
    const ownerErr = async (q: Promise<unknown>) => (await pgErr(q)).detail;
    assertStringIncludes(
      await ownerErr(
        sql`update ceremony_sessions set commitment = ${bytes(32, 0xee)} where id = ${id}`,
      ),
      "fixed when written",
      "a commitment is never replaced after r_V is seen",
    );
    assertStringIncludes(
      await ownerErr(
        sql`update ceremony_sessions set committed_at = now() - interval '1 hour' where id = ${id}`,
      ),
      "fixed when written",
      "the lifetime cannot be backdated",
    );
    assertStringIncludes(
      await ownerErr(
        sql`update ceremony_sessions set expires_at = now() + interval '1 day' where id = ${id}`,
      ),
      "fixed when written",
      "nor extended",
    );

    // r_V once
    await asApi(
      fx.admin1,
      fx.dev.admin1,
      (s) => s`select rf.ceremony_contribute(${id}, ${bytes(16, 1)})`,
    );
    assertStringIncludes(
      (await pgErr(
        asApi(
          fx.admin1,
          fx.dev.admin1,
          (s) => s`select rf.ceremony_contribute(${id}, ${bytes(16, 2)})`,
        ),
      )).message,
      "ceremony_spent",
      "r_V is drawn once per session",
    );
    assertStringIncludes(
      (await pgErr(
        asApi(
          fx.admin2,
          fx.dev.admin2,
          (s) => s`select rf.ceremony_contribute(${id}, ${bytes(16, 2)})`,
        ),
      )).message,
      "ceremony_spent",
      "…by anybody, not just by the same member",
    );
    assertStringIncludes(
      await ownerErr(
        sql`update ceremony_sessions set verifier_random = ${bytes(16, 3)} where id = ${id}`,
      ),
      "written once",
    );
    assertStringIncludes(
      await ownerErr(sql`update ceremony_sessions set verifier_random = null,
        verifier_random_at = null, verifier_user = null, verifier_device = null where id = ${id}`),
      "never withdrawn",
      "a value is not un-written so it can be re-drawn",
    );

    // the opening once — 2 000 alternative openings after r_V is the B-04-88 adversary
    await asApi(
      fx.invitee,
      fx.dev.invitee,
      (s) => s`select rf.ceremony_open(${id}, ${bytes(16, 4)})`,
    );
    for (const alt of [5, 6, 7]) {
      assertStringIncludes(
        (await pgErr(
          asApi(
            fx.invitee,
            fx.dev.invitee,
            (s) => s`select rf.ceremony_open(${id}, ${bytes(16, alt)})`,
          ),
        )).message,
        "ceremony_spent",
        "one session, one opening (ruling 2)",
      );
    }
    assertStringIncludes(
      await ownerErr(sql`update ceremony_sessions set opening = ${bytes(16, 8)} where id = ${id}`),
      "written once",
    );
    assertStringIncludes(
      await ownerErr(
        sql`update ceremony_sessions set opening = null, opened_at = null where id = ${id}`,
      ),
      "never withdrawn",
    );
    const [row] = await sql`select * from ceremony_sessions where id = ${id}`;
    assertEquals(Array.from(row.commitment as Uint8Array), Array.from(bytes(32, 0x15)));
    assertEquals(Array.from(row.verifier_random as Uint8Array), Array.from(bytes(16, 1)));
    assertEquals(Array.from(row.opening as Uint8Array), Array.from(bytes(16, 4)));
  },
});

Deno.test({
  name:
    "E-06-24 ordering is enforced: no r_V before a commitment, no opening before r_V — and neither can be smuggled in at INSERT (ruling 4 rule 3)",
  ignore,
  async fn() {
    // a session cannot be born carrying r_V or an opening: there is nothing to commit to
    for (
      const q of [
        (s: postgres.TransactionSql) =>
          s`insert into ceremony_sessions (tenant_id, subject_user, subject_device, commitment,
              verifier_random, verifier_random_at, verifier_user, verifier_device)
            values (${fx.t1}, ${fx.invitee}, ${fx.dev.invitee}, ${bytes(32, 1)},
              ${bytes(16, 1)}, now(), ${fx.admin1}, ${fx.dev.admin1})`,
        (s: postgres.TransactionSql) =>
          s`insert into ceremony_sessions (tenant_id, subject_user, subject_device, commitment,
              opening, opened_at)
            values (${fx.t1}, ${fx.invitee}, ${fx.dev.invitee}, ${bytes(32, 1)}, ${
            bytes(16, 1)
          }, now())`,
      ]
    ) {
      assertEquals(
        await pgCode(asApi(fx.invitee, fx.dev.invitee, q)),
        "23514",
        "a session is born with its commitment and nothing else",
      );
    }
    // a commitment is mandatory — there is no session without one
    assertEquals(
      await pgCode(
        asApi(
          fx.invitee,
          fx.dev.invitee,
          (s) =>
            s`insert into ceremony_sessions (tenant_id, subject_user, subject_device)
              values (${fx.t1}, ${fx.invitee}, ${fx.dev.invitee})`,
        ),
      ),
      "23502",
    );

    // opening before r_V
    const id = await commit(0x16);
    assertStringIncludes(
      (await pgErr(
        asApi(
          fx.invitee,
          fx.dev.invitee,
          (s) => s`select rf.ceremony_open(${id}, ${bytes(16, 1)})`,
        ),
      )).message,
      "ceremony_order",
      "the invitee opens only in response to r_V (ADR 2026-09-13d §5)",
    );
    // the guard says so first…
    assertStringIncludes(
      (await pgErr(
        sql`update ceremony_sessions set opening = ${
          bytes(16, 1)
        }, opened_at = now() where id = ${id}`,
      )).message,
      "ceremony_order",
    );
    // …and the CHECK constraint says so again with the guard switched off, because a rule this
    // load-bearing should not rest on a trigger alone
    await sql`alter table ceremony_sessions disable trigger ceremony_sessions_guard`;
    const bare = await pgErr(
      sql`update ceremony_sessions set opening = ${
        bytes(16, 1)
      }, opened_at = now() where id = ${id}`,
    );
    await sql`alter table ceremony_sessions enable trigger ceremony_sessions_guard`;
    assertEquals(bare.code, "23514");
    assertStringIncludes(bare.message.toLowerCase(), "ceremony_sessions_order");
  },
});

Deno.test({
  name:
    "E-06-25 lifetime: ten minutes from the commitment's server timestamp, expiry spends nothing, and Regenerate opens a FRESH session rather than mutating one (ruling 3, ruling 4 rule 5)",
  ignore,
  async fn() {
    const id = await commit(0x17);
    // age the row past its window — only the owner can, and only because the guard is the one
    // thing between it and a rewrite; do it by moving the session, not the clock, so the test is
    // deterministic. The guard refuses, which is itself the assertion: nothing extends a session.
    assertStringIncludes(
      (await pgErr(
        sql`update ceremony_sessions set expires_at = now() - interval '1 minute' where id = ${id}`,
      )).detail,
      "fixed when written",
      "not even the database owner shortens or extends the window",
    );

    // so age it the only honest way: a row planted at a committed_at in the past. The INSERT guard
    // stamps now(), so this is the owner writing directly with the trigger momentarily off — the
    // point under test is the FUNCTIONS' expiry check, not the guard's.
    await sql`alter table ceremony_sessions disable trigger ceremony_sessions_guard`;
    const old = crypto.randomUUID();
    await sql`insert into ceremony_sessions (id, tenant_id, subject_user, subject_device,
        commitment, committed_at, expires_at)
      values (${old}, ${fx.t1}, ${fx.invitee}, ${fx.dev.invitee}, ${bytes(32, 0x18)},
        now() - interval '11 minutes', now() - interval '1 minute')`;
    await sql`alter table ceremony_sessions enable trigger ceremony_sessions_guard`;

    assertStringIncludes(
      (await pgErr(
        asApi(
          fx.admin1,
          fx.dev.admin1,
          (s) => s`select rf.ceremony_contribute(${old}, ${bytes(16, 1)})`,
        ),
      )).message,
      "ceremony_expired",
    );
    // an expired session opens to nothing either
    await sql`alter table ceremony_sessions disable trigger ceremony_sessions_guard`;
    await sql`update ceremony_sessions set verifier_random = ${bytes(16, 1)},
      verifier_random_at = now() - interval '2 minutes', verifier_user = ${fx.admin1},
      verifier_device = ${fx.dev.admin1} where id = ${old}`;
    await sql`alter table ceremony_sessions enable trigger ceremony_sessions_guard`;
    assertStringIncludes(
      (await pgErr(
        asApi(
          fx.invitee,
          fx.dev.invitee,
          (s) => s`select rf.ceremony_open(${old}, ${bytes(16, 1)})`,
        ),
      )).message,
      "ceremony_expired",
    );

    // Regenerate: a NEW row, the old one untouched (ruling 4 rule 5)
    const again = await commit(0x19);
    assert(again !== id, "Regenerate mints a session, it does not mutate one");
    const [before] = await sql`select commitment from ceremony_sessions where id = ${id}`;
    assertEquals(Array.from(before.commitment as Uint8Array), Array.from(bytes(32, 0x17)));

    // …and it is rate-limited, because each regeneration is one blind guess in 10⁸ for a relay
    // that withholds r_V (04 §6.4 residual, ADR 2026-09-05b §7)
    let flooded = "";
    for (let i = 0; i < 20 && !flooded; i++) {
      flooded = (await pgErr(commit(0x40 + i))).message;
    }
    assertStringIncludes(flooded, "ceremony_flood");
  },
});

Deno.test({
  name:
    "E-06-26 reads: the subject and the tenant's active members see the session; a certified device of another tenant and an uncertified device of this tenant see zero rows; deletion is retention-only under rf_maintenance",
  ignore,
  async fn() {
    const mine = await asApi(
      fx.invitee,
      fx.dev.invitee,
      (s) => s`select id from ceremony_sessions`,
    );
    assert(mine.length > 0, "the subject polls its own session for r_V");
    const verifier = await asApi(
      fx.admin1,
      fx.dev.admin1,
      (s) => s`select id, commitment, opening from ceremony_sessions`,
    );
    assert(verifier.length > 0, "an active member polls for the commitment and the opening");

    assertEquals(
      (await asApi(fx.outsider, fx.dev.outsider, (s) => s`select id from ceremony_sessions`))
        .length,
      0,
      "another tenant sees nothing",
    );
    assertEquals(
      (await asApi(fx.invitee, fx.dev.inviteeraw, (s) => s`select id from ceremony_sessions`))
        .length,
      0,
      "an uncertified device sees nothing, not even its user's own session",
    );
    assertEquals(
      (await asApi(fx.admin1, fx.dev.admin1raw, (s) => s`select id from ceremony_sessions`)).length,
      0,
    );

    // rf_maintenance sweeps, and only rows a day past their window (03 §6)
    assertEquals(
      await pgCode(
        asApi(fx.admin1, fx.dev.admin1, (s) => s`select rf.sweep_ceremony_sessions()`),
      ),
      "42501",
      "the sweep is not an API power",
    );
    assertStringIncludes(
      (await pgErr(asMaint((s) => s`delete from ceremony_sessions`))).detail,
      "only by retention",
      "maintenance may not delete a live session either",
    );
    await sql`alter table ceremony_sessions disable trigger ceremony_sessions_guard`;
    const stale = crypto.randomUUID();
    await sql`insert into ceremony_sessions (id, tenant_id, subject_user, subject_device,
        commitment, committed_at, expires_at)
      values (${stale}, ${fx.t1}, ${fx.invitee}, ${fx.dev.invitee}, ${bytes(32, 0x21)},
        now() - interval '3 days', now() - interval '3 days' + interval '10 minutes')`;
    await sql`alter table ceremony_sessions enable trigger ceremony_sessions_guard`;
    const n = await asMaint((s) => s`select rf.sweep_ceremony_sessions() as n`);
    assert(Number(n[0].n) >= 1, "the sweep collects sessions a day past their window");
    assertEquals(
      (await sql`select id from ceremony_sessions where id = ${stale}`).length,
      0,
    );
    await sql.end();
  },
});
