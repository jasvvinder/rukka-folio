// Hostile-query suite for migration 0016 — `rf.has_guardian_set()`, the ONE read ADR 2026-09-24b §3
// 🔒 adds to what an UNCERTIFIED device may learn (amending ADR 2026-09-05d §2 🔒), for 04 §7.3's
// rung 2.
//
// The ADR widens what a SIM-swapper's device can see "by exactly one bit". Every test below is
// about keeping it to that bit, and to the caller's own user:
//
//   * THE SHAPE — no argument (nobody can be named, so nobody can be enumerated), returns a boolean
//     (there is nowhere to put k, n, a version or a member), SECURITY DEFINER with search_path
//     pinned, EXECUTE for rf_api only (E-24b-1 setup).
//   * THE CALLER'S OWN BIT — the uncertified candidate phone learns its own user's answer; every
//     other user's answer is invisible to it, including a user it shares a tenant with and the
//     user it is a guardian for, and a claim pair that does not belong together reads false.
//   * NO SIDE DOOR — the five SECURITY DEFINER lookups 0010's open guard uses take any subject and
//     return k, n, readiness, liveness or a count; since 0017 they are owner-only, so rf_api cannot
//     call them for anyone, itself included, and the bit stays the only answer.
//   * NO ROWS — the carve-out is a function, not a policy: `guardian_sets` and
//     `guardian_set_members` keep 0005's certified-only policies and SELECT/INSERT grants, and an
//     uncertified device still reads ZERO rows of its own set.
//   * WITHHELD, NOT REFUSED — a revoked device and an erased user read `false`, a constant.
//   * CURRENT MEANS WHAT THE OPEN MEANS — superseded-only / no set → false, a re-split → true, and
//     the bit agrees with 0010's own open refusal for the same caller (parity), so the client is
//     never told "you have trusted members" by one read and "you have none" by the next.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Id E-24b-1 (the database half; the route half is functions/_tests/has_guardian_set.test.ts).
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";
import { PgStore } from "../../functions/_shared/store_pg.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — has_guardian_set.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP has_guardian_set.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
// Random, not fixed fills: every RLS file shares one database and users.phone_hmac is UNIQUE.
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

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

/** The read, exactly as PgStore makes it: rf_api, the claims, no argument. */
async function bit(user: string | null, device: string | null): Promise<boolean> {
  const [r] = await asApi(user, device, (s) => s`select rf.has_guardian_set() as v`);
  assertEquals(typeof r.v, "boolean", "a boolean, never null — there is no third answer");
  return r.v as boolean;
}

/** What 0010's rung-2 open would say to the same caller, WITHOUT leaving a request behind: the
 *  insert runs as rf_api with the same claims inside a transaction that is always rolled back. */
async function openOutcome(user: string, device: string): Promise<string> {
  let outcome = "opened";
  const ROLLBACK = "rollback-by-design";
  try {
    await sql.begin(async (s) => {
      await s`set local role rf_api`;
      await s`select rf.set_claims(${user}::uuid, ${device}::uuid)`;
      try {
        await s`insert into recovery_requests (user_id, candidate_device, candidate_pub_x, expires_at)
          values (${user}, ${device}, ${rand(32)}, now())`;
      } catch (e) {
        outcome = (e as { message?: string }).message ?? "error";
      }
      throw new Error(ROLLBACK);
    });
  } catch (e) {
    if ((e as Error).message !== ROLLBACK) throw e;
  }
  return outcome;
}

interface Fx {
  t1: string;
  t2: string;
  subject: string; // a complete, current 2-of-3 set
  g1: string; // a guardian OF the subject — has no set of its own
  g2: string;
  g3: string;
  bystander: string; // shares t1 with the subject, not a guardian, no set
  stranger: string; // t2, no set
  superseded: string; // its only set is superseded
  resplit: string; // v1 then v2
  incomplete: string; // a published 3-set holding 1 member
  erased: string; // had a set, then erasure (06 §9.3)
  dev: Record<string, string>;
}
let fx: Fx;

async function seed(): Promise<Fx> {
  const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
  const [t2] = await sql`insert into tenants (type) values ('family') returning id`;
  const mk = async () => {
    const [u] = await sql`insert into users (phone_hmac, phone_ct)
      values (${rand(32)}, ${rand(40)}) returning id`;
    return u.id as string;
  };
  const f = {
    subject: await mk(),
    g1: await mk(),
    g2: await mk(),
    g3: await mk(),
    bystander: await mk(),
    stranger: await mk(),
    superseded: await mk(),
    resplit: await mk(),
    incomplete: await mk(),
    erased: await mk(),
  };
  const dev: Record<string, string> = {};
  const devices: [string, string, string][] = [
    ["subjectOld", f.subject, "certified"],
    ["candidate", f.subject, "registered"], // the fresh phone — UNCERTIFIED by construction
    ["subjectRevoked", f.subject, "revoked"],
    ["subjectSuspended", f.subject, "suspended"],
    ["g1", f.g1, "certified"],
    ["g2", f.g2, "certified"],
    ["g3", f.g3, "certified"],
    ["bystander", f.bystander, "certified"],
    ["stranger", f.stranger, "certified"],
    ["strangerRaw", f.stranger, "registered"],
    ["superseded", f.superseded, "registered"],
    ["resplit", f.resplit, "registered"],
    ["incomplete", f.incomplete, "registered"],
    ["erased", f.erased, "registered"],
  ];
  for (const [name, user, status] of devices) {
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status, revoked_at)
      values (gen_random_uuid(), ${user}, ${rand(32)}, ${rand(32)}, ${status},
              ${status === "revoked" ? new Date() : null}) returning id`;
    dev[name] = d.id;
  }
  // The subject founds t1 and the stranger t2 (06 §5: a founder has nobody to verify them); the
  // bystander reaches `active` in t1 only behind a signed verification event (0008, as
  // recovery.test.ts seeds its guardians).
  await sql`insert into memberships (tenant_id, user_id, status) values
    (${t1.id}, ${f.subject}, 'active'), (${t2.id}, ${f.stranger}, 'active')`;
  const rec = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${rec}, 1, ${t1.id}, 'verification_event', '{}'::jsonb, ${rand(8)},
            ${dev.subjectOld}, ${rand(64)}, 1)`;
  await sql`insert into verification_events
    (tenant_id, subject_user, verifier_user, method, result, source_record_id)
    values (${t1.id}, ${f.bystander}, ${f.subject}, 'qr_in_person', 'verified', ${rec})`;
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${f.bystander}, 'active')`;

  const members = async (subject: string, version: number, guardians: string[]) => {
    for (const g of guardians) {
      await sql`insert into guardian_set_members
          (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
        values (${subject}, ${version}, ${g}, ${rand(32)})`;
    }
  };
  // 0010's guards still hold for a superuser insert: n, k, next version, never the subject itself.
  const set = async (subject: string, version: number, n: number, superseded = false) => {
    await sql`insert into guardian_sets (subject_user_id, share_set_version, n, k, superseded_at)
      values (${subject}, ${version}, ${n}, ${Math.ceil((n + 1) / 2)},
              ${superseded ? new Date() : null})`;
  };
  await set(f.subject, 1, 3);
  await members(f.subject, 1, [f.g1, f.g2, f.g3]);
  await set(f.superseded, 1, 2, true);
  await members(f.superseded, 1, [f.g1, f.g2]);
  await set(f.resplit, 1, 2);
  await members(f.resplit, 1, [f.g1, f.g2]);
  await set(f.resplit, 2, 3);
  await members(f.resplit, 2, [f.g1, f.g2, f.g3]);
  await set(f.incomplete, 1, 3);
  await members(f.incomplete, 1, [f.g1]);
  await set(f.erased, 1, 2);
  await members(f.erased, 1, [f.g1, f.g2]);
  // 06 §9.3 erasure, the way rls.test.ts performs it. The guardian rows are append-only and stay.
  await sql`update users set erased_at = now(), phone_ct = null, phone_hmac = null
    where id = ${f.erased}`;
  return { t1: t1.id, t2: t2.id, ...f, dev };
}

Deno.test({
  name:
    "E-24b-1 setup: 0016's shape — rf.has_guardian_set takes NO argument and returns boolean, is SECURITY DEFINER with search_path pinned, has no overload, and is EXECUTE-able by rf_api alone (not PUBLIC, not rf_maintenance)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();

    const fns = await sql`select p.pronargs, p.prosecdef, p.provolatile, p.proconfig,
        format_type(p.prorettype, null) as ret, p.proretset,
        has_function_privilege('rf_api', p.oid, 'execute') as api,
        has_function_privilege('public', p.oid, 'execute') as pub,
        has_function_privilege('rf_maintenance', p.oid, 'execute') as maint
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname = 'has_guardian_set'`;
    assertEquals(fns.length, 1, "one function — no overload that takes a subject");
    const [fn] = fns;
    assertEquals(fn.pronargs, 0, "no argument: the only subject it can answer for is the caller");
    assertEquals(fn.ret, "boolean", "a boolean — nowhere to put k, n, a version or a member");
    assertEquals(fn.proretset, false, "one value, not a set of rows");
    assertEquals(fn.prosecdef, true, "SECURITY DEFINER: the caller holds no row access to read");
    assertEquals(fn.provolatile, "s");
    assert(
      (fn.proconfig as string[] | null)?.includes("search_path=public"),
      `search_path pinned, or a definer function can be hijacked: ${fn.proconfig}`,
    );
    assertEquals(fn.api, true, "rf_api may EXECUTE it");
    assertEquals(fn.pub, false, "PUBLIC may not — a new function is PUBLIC-executable by default");
    assertEquals(fn.maint, false, "nor rf_maintenance: retention needs no recovery answer");
  },
});

Deno.test({
  name:
    "E-24b-1 the UNCERTIFIED candidate phone learns its own user's bit (ADR 2026-09-24b §3: not gated on rf.is_certified()), a certified device of the same user reads the same answer, and a user with no set reads false",
  ignore,
  async fn() {
    const [c] = await sql`select status from devices where id = ${fx.dev.candidate}`;
    assertEquals(c.status, "registered", "precondition: the asking phone is NOT certified");
    assertEquals(await bit(fx.subject, fx.dev.candidate), true);
    assertEquals(await bit(fx.subject, fx.dev.subjectOld), true, "certified reads the same bit");
    assertEquals(await bit(fx.stranger, fx.dev.strangerRaw), false, "no set → false");
    assertEquals(await bit(fx.stranger, fx.dev.stranger), false, "…certified or not");

    // and through PgStore, the call sync-meta makes
    const store = new PgStore(url!);
    try {
      const has = (user: string, device: string) =>
        store.withClaims({ user_id: user, device_id: device }, (tx) => tx.hasGuardianSet());
      assertEquals(await has(fx.subject, fx.dev.candidate), true);
      assertEquals(await has(fx.stranger, fx.dev.strangerRaw), false);
    } finally {
      await store.end();
    }
  },
});

Deno.test({
  name:
    "E-24b-1 nobody else's answer leaks: the function cannot be handed a subject, a claim pair that does not belong together reads false in every combination, and a tenant-mate, a guardian OF the subject and a stranger each read only their own (false) bit",
  ignore,
  async fn() {
    // There is no way to name the subject: an argument is not a parameter, it is an error.
    const named = await pgErr(
      asApi(
        fx.stranger,
        fx.dev.stranger,
        (s) => s`select rf.has_guardian_set(${fx.subject}::uuid)`,
      ),
    );
    assertEquals(named.code, "42883", `no overload takes a user id: ${named.message}`);

    // Claims are set by the edge from the JWT; if a pair ever disagreed, it still says nothing.
    assertEquals(await bit(fx.stranger, fx.dev.candidate), false, "the subject's device, my user");
    assertEquals(await bit(fx.subject, fx.dev.strangerRaw), false, "my user, somebody's device");
    assertEquals(await bit(fx.subject, fx.dev.stranger), false, "…certified or not");
    assertEquals(await bit(fx.subject, null), false, "a user claim with no device claim");
    assertEquals(await bit(null, fx.dev.candidate), false, "a device claim with no user claim");
    assertEquals(await bit(null, null), false, "no claims at all");
    const ghost = crypto.randomUUID();
    assertEquals(await bit(ghost, fx.dev.candidate), false, "a user id that does not exist");

    // People close to the subject read THEIR OWN answer, never the subject's.
    assertEquals(await bit(fx.bystander, fx.dev.bystander), false, "shares a tenant, has no set");
    assertEquals(await bit(fx.g1, fx.dev.g1), false, "a guardian OF the subject has no set itself");

    // And the stranger's bit does not move when somebody else's set does.
    const [late] = await sql`insert into users (phone_hmac, phone_ct)
      values (${rand(32)}, ${rand(40)}) returning id`;
    const [lateDev] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${late.id}, ${rand(32)}, ${rand(32)}, 'registered') returning id`;
    const before = await bit(fx.stranger, fx.dev.strangerRaw);
    assertEquals(await bit(late.id, lateDev.id), false, "no set yet");
    await sql`insert into guardian_sets (subject_user_id, share_set_version, n, k)
      values (${late.id}, 1, 2, 2)`;
    assertEquals(await bit(late.id, lateDev.id), true, "the bit follows the caller's own set");
    assertEquals(
      await bit(fx.stranger, fx.dev.strangerRaw),
      before,
      "somebody else publishing a set changes nothing anybody else reads",
    );
  },
});

Deno.test({
  name:
    "E-24b-1 the open's own lookups are no side door (0017): rf_api cannot EXECUTE rf.current_guardian_set, rf.guardian_set_ready, rf.device_live_for, rf.has_other_active_device or rf.live_recovery_count — not for a stranger's subject and not for the caller's own — so no session learns anyone's k, n, readiness, device liveness or attempt count; the guard that needs them is SECURITY DEFINER with search_path pinned, and the open and the bit still work",
  ignore,
  async fn() {
    // Each takes an arbitrary subject and is SECURITY DEFINER, so an EXECUTE grant would bypass
    // 0005's certified-only guardian_sets policy for ANY user (ADR 2026-09-24b §3: "no k, no n").
    const probes: [string, (s: postgres.TransactionSql) => Promise<unknown>][] = [
      [
        "current_guardian_set",
        (s) => s`select * from rf.current_guardian_set(${fx.subject}::uuid)`,
      ],
      ["guardian_set_ready", (s) => s`select rf.guardian_set_ready(${fx.subject}::uuid, 1)`],
      [
        "device_live_for",
        (s) => s`select rf.device_live_for(${fx.dev.subjectOld}::uuid, ${fx.subject}::uuid)`,
      ],
      [
        "has_other_active_device",
        (s) => s`select rf.has_other_active_device(${fx.subject}::uuid, ${fx.dev.candidate}::uuid)`,
      ],
      ["live_recovery_count", (s) => s`select rf.live_recovery_count(${fx.subject}::uuid)`],
    ];
    const callers: [string, string, string][] = [
      ["a certified stranger", fx.stranger, fx.dev.stranger],
      ["a guardian OF the subject", fx.g1, fx.dev.g1],
      ["the subject's own uncertified phone", fx.subject, fx.dev.candidate],
      ["the subject's own certified phone", fx.subject, fx.dev.subjectOld],
    ];
    for (const [fnName, probe] of probes) {
      for (const [who, user, device] of callers) {
        const e = await pgErr(asApi(user, device, probe));
        assertEquals(
          e.code,
          "42501",
          `rf.${fnName} refused to ${who} as insufficient_privilege, not answered: ${e.message}`,
        );
      }
    }

    // The catalog says the same, for every role that is not the owner.
    const sigs = [
      "rf.current_guardian_set(uuid)",
      "rf.guardian_set_ready(uuid, int)",
      "rf.device_live_for(uuid, uuid)",
      "rf.has_other_active_device(uuid, uuid)",
      "rf.live_recovery_count(uuid)",
    ];
    for (const sig of sigs) {
      const [p] = await sql`select
          has_function_privilege('rf_api', ${sig}::regprocedure, 'execute') as api,
          has_function_privilege('public', ${sig}::regprocedure, 'execute') as pub,
          has_function_privilege('rf_maintenance', ${sig}::regprocedure, 'execute') as maint`;
      assertEquals([p.api, p.pub, p.maint], [false, false, false], `${sig}: owner only`);
    }

    // The refusal is the grant, not a missing function: the owner still gets the real answer.
    const [own] = await sql`select * from rf.current_guardian_set(${fx.subject}::uuid)`;
    assertEquals([own.share_set_version, own.k, own.n], [1, 2, 3]);

    // The guard calls them as their owner now, so it must be a pinned definer.
    const [g] = await sql`select p.prosecdef, p.proconfig from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname = 'recovery_request_guard'`;
    assertEquals(g.prosecdef, true, "rf.recovery_request_guard runs as its owner (0017)");
    assert(
      (g.proconfig as string[] | null)?.includes("search_path=public"),
      `a definer trigger with an unpinned search_path can be hijacked: ${g.proconfig}`,
    );

    // And nothing that needed the helpers broke: the rung-2 open still opens (rolled back) and
    // still refuses by name, and the one bit still answers.
    assertEquals(await openOutcome(fx.subject, fx.dev.candidate), "opened");
    assertEquals(await openOutcome(fx.incomplete, fx.dev.incomplete), "guardian_set_incomplete");
    assertEquals(await openOutcome(fx.stranger, fx.dev.strangerRaw), "no_guardian_set");
    assertEquals(await bit(fx.subject, fx.dev.candidate), true);
  },
});

Deno.test({
  name:
    "E-24b-1 no row-level access is granted: guardian_sets and guardian_set_members keep 0005's certified-only policies and SELECT/INSERT grants, and the uncertified phone still reads ZERO rows of its own user's set",
  ignore,
  async fn() {
    for (const table of ["guardian_sets", "guardian_set_members"]) {
      const rows = await asApi(
        fx.subject,
        fx.dev.candidate,
        (s) => s`select count(*)::int as n from ${s(table)}`,
      );
      assertEquals(rows[0].n, 0, `${table}: the uncertified caller sees none of its own rows`);

      const privs = await sql<{ privilege_type: string }[]>`
        select privilege_type from information_schema.table_privileges
        where grantee = 'rf_api' and table_name = ${table}`;
      assertEquals(
        privs.map((p) => p.privilege_type).sort(),
        ["INSERT", "SELECT"],
        `${table}: 0016 grants nothing — no UPDATE, no DELETE, no new SELECT`,
      );
      const pols = await sql<
        { policyname: string; qual: string | null; with_check: string | null }[]
      >`
        select policyname, qual, with_check from pg_policies where tablename = ${table}`;
      assertEquals(pols.length, 2, `${table}: exactly 0005's select + insert policies`);
      for (const p of pols) {
        assert(
          `${p.qual ?? ""} ${p.with_check ?? ""}`.includes("is_certified"),
          `${table}.${p.policyname} still requires a certified device: ${p.qual} ${p.with_check}`,
        );
      }
    }
    // The certified device of the same user still reads the rows, so nothing above is vacuous.
    const certified = await asApi(
      fx.subject,
      fx.dev.subjectOld,
      (s) => s`select count(*)::int as n from guardian_sets where subject_user_id = ${fx.subject}`,
    );
    assertEquals(certified[0].n, 1, "the certified read is unchanged");
  },
});

Deno.test({
  name:
    "E-24b-1 withheld, not revealed: a REVOKED device of a user with a set reads false, an ERASED user with a set reads false, and a SUSPENDED device is answered exactly as the open treats it (⚠️ SPEC 0016 (b), (c))",
  ignore,
  async fn() {
    assertEquals(await bit(fx.subject, fx.dev.subjectRevoked), false, "revoked → false");
    assertEquals(await bit(fx.erased, fx.dev.erased), false, "erased → false, set rows or not");
    const [kept] = await sql`select count(*)::int as n from guardian_sets
      where subject_user_id = ${fx.erased}`;
    assertEquals(kept.n, 1, "precondition: the erased user's set row still exists");
    assertEquals(
      await bit(fx.subject, fx.dev.subjectSuspended),
      true,
      "suspended is live to rf.device_live_for, the predicate the open uses",
    );
  },
});

Deno.test({
  name:
    "E-24b-1 'current' means what the open means: superseded-only → false, a re-split → true, a published set short of n members → true (⚠️ SPEC 0016 (a)) — and for every caller the bit agrees with 0010's own open refusal",
  ignore,
  async fn() {
    assertEquals(await bit(fx.superseded, fx.dev.superseded), false, "superseded-only → false");
    assertEquals(await bit(fx.resplit, fx.dev.resplit), true, "v1 then v2 → a current set");
    assertEquals(await bit(fx.incomplete, fx.dev.incomplete), true, "existence, not readiness");

    // Parity: false ⇔ the open refuses no_guardian_set / unknown_candidate_device. Every open is
    // rolled back, so nothing here pages a guardian or leaves an attempt behind.
    const cases: [string, string, boolean, string][] = [
      [fx.subject, fx.dev.candidate, true, "opened"],
      [fx.resplit, fx.dev.resplit, true, "opened"],
      [fx.incomplete, fx.dev.incomplete, true, "guardian_set_incomplete"],
      [fx.subject, fx.dev.subjectSuspended, true, "opened"],
      [fx.stranger, fx.dev.strangerRaw, false, "no_guardian_set"],
      [fx.superseded, fx.dev.superseded, false, "no_guardian_set"],
      [fx.subject, fx.dev.subjectRevoked, false, "unknown_candidate_device"],
      [fx.subject, fx.dev.strangerRaw, false, "unknown_candidate_device"],
    ];
    for (const [user, device, want, open] of cases) {
      assertEquals(await bit(user, device), want);
      assertEquals(await openOutcome(user, device), open, `the open agrees for ${open}`);
    }
    const [left] = await sql`select count(*)::int as n from recovery_requests
      where user_id in (${fx.subject}, ${fx.resplit}, ${fx.incomplete})`;
    assertEquals(left.n, 0, "the parity probe left no attempt behind");

    await sql.end();
  },
});
