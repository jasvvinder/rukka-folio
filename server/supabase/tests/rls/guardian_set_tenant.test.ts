// Desk 89 — ADR 2026-10-03b (0026) in the database alone, with no edge in front of it. The edge's
// scenarios (E-03b-1 … E-03b-5 on both stores) are in edge_record_authority.test.ts; this file holds
// what only raw SQL as rf_api can probe:
//   * the set's tenant is written once with the version — rf_api holds no UPDATE, and the guard
//     refuses even the schema owner's;
//   * 0010's guards, extended, refuse a hostile rf_api insert that skips the route: no tenant, a
//     tenant the publisher is not active in, a guardian removed there;
//   * the count is SECURITY DEFINER over every row: a pending guardian who cannot SELECT the other
//     approvals still reads them counted; the internal helpers are not rf_api's to call; a payload
//     whose share_set_version is not a number is not counted and does not abort the reader.
//
// Fixtures are written by the schema owner without claims; every hostile query runs as rf_api with
// the caller's own claims, as PgStore.withClaims opens it. Synthetic bytes and ids only — no ledger
// content, no phone number (CLAUDE.md rule 4).
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`); without it every test is SKIPPED and says
// why, and RLS_REQUIRE=1 makes that a failure.
import postgres from "postgres";
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { apiSql } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — guardian_set_tenant.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP guardian_set_tenant.test.ts: ${why}`);
}
const ignore = !url;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

let sql: postgres.Sql; // the schema owner: fixtures and fresh reads only
let api: postgres.Sql; // rf_api: every hostile query

function test(name: string, fn: () => Promise<void>) {
  Deno.test({
    name,
    ignore,
    async fn() {
      sql = postgres(url!, { max: 2, onnotice: () => {} });
      api = await apiSql(url!, { max: 2 });
      try {
        await fn();
      } finally {
        await api.end();
        await sql.end();
      }
    },
  });
}

interface P {
  user: string;
  dev: string;
}
async function person(): Promise<P> {
  const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${rand(32)}, ${rand(40)})
    returning id`;
  const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${u.id}, ${rand(32)}, ${rand(32)}, 'certified') returning id`;
  return { user: u.id as string, dev: d.id as string };
}
/** A tenant founded by `founder` (06 §5: the first member is active without a ceremony), with each
 *  of `others` at the status given. Owner-written, so no seat cap applies. */
async function tenant(founder: P, others: [P, string][] = []): Promise<string> {
  const [t] = await sql`insert into tenants (type) values ('family') returning id`;
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t.id}, ${founder.user}, 'active')`;
  for (const [p, status] of others) {
    await sql`insert into memberships (tenant_id, user_id, status)
      values (${t.id}, ${p.user}, ${status})`;
  }
  return t.id as string;
}
async function asApi<T>(p: P, fn: (s: postgres.TransactionSql) => Promise<T>): Promise<T> {
  return await api.begin(async (s) => {
    await s`select rf.set_claims(${p.user}::uuid, ${p.dev}::uuid)`;
    return await fn(s);
  }) as T;
}
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
function assertRefused(e: PgErr, code: string, name: string, what: string) {
  assertEquals(e.code, code, `${what}: ${e.code} ${e.message}`);
  assertStringIncludes(e.message, name, what);
}
/** A record filed by the CALLER through rf_api (signed_records_insert decides). */
async function file(p: P, t: string, payload: Record<string, unknown>): Promise<string> {
  const id = crypto.randomUUID();
  await asApi(p, (s) =>
    s`insert into signed_records
        (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
      values (${id}, 1, ${t}, 'device_revocation', ${s.json(payload as postgres.JSONValue)},
              ${rand(8)}, ${p.dev}, ${rand(64)}, 1)`);
  return id;
}
async function countAs(p: P, dev: string) {
  const [r] = await asApi(p, (s) => s`select * from rf.revocation_count(${dev}::uuid)`);
  return {
    approvers: r.approvers as number,
    k: r.k as number | null,
    effective_seq: r.effective_seq === null ? null : String(r.effective_seq),
  };
}

test(
  "E-03b-5 a guardian set's tenant is written once with its version and checked in the database, not only at the route: rf_api holds no UPDATE or DELETE on guardian_sets or guardian_set_members, the schema owner's own UPDATE of tenant_id is refused append_only, and a hostile rf_api insert that skips the route is refused guardian_set_tenant with no tenant or a tenant the publisher is only pending in, and guardian_not_in_tenant for a guardian removed there",
  async () => {
    const subject = await person(), g1 = await person(), g2 = await person();
    const gone = await person(), pendingPub = await person();
    const t = await tenant(subject, [
      [g1, "joined_pending_verification"],
      [g2, "joined_pending_verification"],
      [gone, "joined_pending_verification"],
      [pendingPub, "joined_pending_verification"],
    ]);
    const u = await tenant(g1, [[subject, "joined_pending_verification"]]);
    await sql`update memberships set status = 'removed' where tenant_id = ${t} and user_id = ${gone.user}`;

    for (const table of ["guardian_sets", "guardian_set_members"]) {
      const [g] = await sql`select
          has_table_privilege('rf_api', ${"public." + table}, 'update') as upd,
          has_table_privilege('rf_api', ${"public." + table}, 'delete') as del`;
      assertEquals([g.upd, g.del], [false, false], `rf_api holds no UPDATE/DELETE on ${table}`);
    }

    const insertSet = (p: P, tenantId: string | null, version = 1) =>
      pgErr(
        asApi(p, (s) =>
          s`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
          values (${p.user}, ${version}, 2, 2, ${tenantId})`),
      );
    assertRefused(await insertSet(subject, null), "42501", "guardian_set_tenant", "no tenant");
    assertRefused(
      await insertSet(pendingPub, t),
      "42501",
      "guardian_set_tenant",
      "a publisher only pending in the tenant",
    );
    assertRefused(
      await insertSet(subject, u),
      "42501",
      "guardian_set_tenant",
      "a publisher pending in u, active only in t",
    );
    assertRefused(
      await insertSet(subject, crypto.randomUUID()),
      "42501",
      "guardian_set_tenant",
      "an unknown tenant answers like one the publisher is not in (before the foreign key)",
    );
    const removed = await pgErr(asApi(subject, async (s) => {
      await s`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
        values (${subject.user}, 1, 2, 2, ${t})`;
      await s`insert into guardian_set_members
          (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
        values (${subject.user}, 1, ${g1.user}, ${rand(32)}), (${subject.user}, 1, ${gone.user}, ${
        rand(32)
      })`;
    }));
    assertRefused(removed, "42501", "guardian_not_in_tenant", "a guardian removed from t");
    const [none] = await sql`select count(*)::int as n from guardian_sets
      where subject_user_id = ${subject.user}`;
    assertEquals(none.n, 0, "every refused publish rolled back");

    await asApi(subject, async (s) => {
      await s`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
        values (${subject.user}, 1, 2, 2, ${t})`;
      await s`insert into guardian_set_members
          (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
        values (${subject.user}, 1, ${g1.user}, ${rand(32)}), (${subject.user}, 1, ${g2.user}, ${
        rand(32)
      })`;
    });
    const asApiUpdate = await pgErr(
      asApi(
        subject,
        (s) => s`update guardian_sets set tenant_id = ${u} where subject_user_id = ${subject.user}`,
      ),
    );
    assertEquals(asApiUpdate.code, "42501", "rf_api: permission denied, no UPDATE grant");
    assertRefused(
      await pgErr(
        sql`update guardian_sets set tenant_id = ${u} where subject_user_id = ${subject.user}`,
      ),
      "23514",
      "append_only",
      "even the schema owner cannot move a version to another tenant",
    );
    const [kept] = await sql`select tenant_id from guardian_sets
      where subject_user_id = ${subject.user} and share_set_version = 1`;
    assertEquals(kept.tenant_id, t, "the tenant stands as written");
  },
);

test(
  "E-03b-1 the count is the database's, over every row: a guardian still pending in the set's tenant, who can SELECT no other approval, reads the k approvals filed there counted (rf.revocation_count) while an approval filed outside it is not; the two internal helpers (rf.revocation_approvals, rf.revocation_tally) are not rf_api's or PUBLIC's to call; the two the edge asks are rf_api's alone, SECURITY DEFINER with search_path public, pg_temp; a payload whose share_set_version is a string is not counted and does not abort the count",
  async () => {
    const subject = await person(), g1 = await person(), g2 = await person(), g3 = await person();
    const t = await tenant(subject, [
      [g1, "joined_pending_verification"],
      [g2, "joined_pending_verification"],
      [g3, "joined_pending_verification"],
    ]);
    const other = await tenant(g1, [[subject, "joined_pending_verification"]]);
    await sql`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
      values (${subject.user}, 1, 3, 2, ${t})`;
    for (const g of [g1, g2, g3]) {
      await sql`insert into guardian_set_members
          (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
        values (${subject.user}, 1, ${g.user}, ${rand(32)})`;
    }
    const approval = {
      revoked_device_id: subject.dev,
      subject_user_id: subject.user,
      share_set_version: 1,
    };

    await file(g1, other, approval); // g1 is active in `other`, where the subject is too
    await file(g3, t, { ...approval, share_set_version: "1" }); // not a JSON number
    assertEquals(
      await countAs(subject, subject.dev),
      { approvers: 0, k: null, effective_seq: null },
      "an approval filed outside the set's tenant, and one naming a string version, count nothing",
    );
    await file(g1, t, approval);
    await file(g2, t, approval);
    const [seqs] = await sql`select max(seq)::text as s from signed_records
      where tenant_id = ${t} and author_device = ${g2.dev}`;

    const [seen] = await asApi(
      g2,
      (s) => s`select count(*)::int as n from signed_records where kind = 'device_revocation'`,
    );
    assertEquals(seen.n, 1, "precondition: the pending guardian SELECTs only its own approval");
    assertEquals(
      await countAs(g2, subject.dev),
      { approvers: 2, k: 2, effective_seq: seqs.s },
      "…and reads both approvals filed in the set's tenant counted, cut off at the 2nd",
    );
    assertEquals(
      await countAs(await person(), subject.dev),
      { approvers: 0, k: null, effective_seq: null },
      "a stranger reads the empty count",
    );

    const fns = await sql`select p.oid::regprocedure::text as sig, p.prosecdef, p.proconfig,
        has_function_privilege('rf_api', p.oid, 'execute') as api,
        has_function_privilege('public', p.oid, 'execute') as pub
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname in
        ('revocation_approvals', 'revocation_tally', 'revocation_count', 'guardian_may_revoke')
      order by 1`;
    assertEquals(fns.length, 4, "no overload");
    for (const f of fns) {
      assert(f.prosecdef, `${f.sig} is SECURITY DEFINER`);
      assertEquals(f.proconfig, ["search_path=public, pg_temp"], `${f.sig} pins its path`);
      assertEquals(f.pub, false, `${f.sig}: not PUBLIC's`);
      const edge = f.sig.startsWith("rf.revocation_count") ||
        f.sig.startsWith("rf.guardian_may_revoke");
      assertEquals(f.api, edge, `${f.sig}: rf_api ${edge ? "may" : "may not"} call it`);
    }
    assertRefused(
      await pgErr(asApi(g2, (s) => s`select * from rf.revocation_approvals(${subject.dev}::uuid)`)),
      "42501",
      "permission denied",
      "rf_api cannot list the approvals themselves",
    );
  },
);
