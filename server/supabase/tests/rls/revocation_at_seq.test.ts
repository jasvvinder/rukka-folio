// Desk 97 — ADR 2026-10-03b §6 (0027) in the database alone, with no edge in front of it. The edge's
// scenarios (E-03b-7, E-03b-9, E-03b-11, E-03b-12 on both stores) are in
// edge_record_authority.test.ts. This file holds what only raw SQL as rf_api can probe:
//   * E-03b-10: the subject's membership is judged at each approval's own seq, from membership_facts,
//     over rows no caller can see: a guardian still pending in the set's tenant cannot SELECT the
//     subject's membership or the other approvals, and still reads them judged. The history is the
//     SUBJECT's: another member's change in the same tenant never stands in for it. Only a write of
//     the memberships row is a fact: a removal record that rf_api files and marks "applied" itself
//     (0005:401 grants INSERT on every column of signed_records) is not one, nor is a refused
//     projection. membership_facts is nobody's: RLS is forced with no policy, rf_api holds no grant,
//     and the schema owner's own UPDATE and DELETE are refused append_only. rf.subject_held_at and
//     the trigger function are internal: SECURITY DEFINER, search_path public, pg_temp, and not
//     rf_api's or PUBLIC's.
//   * E-03b-13: every writer of a membership row is a fact at the moment it writes, never at a
//     record's seq (desk 97 review, findings 1-2): a re-admission the seat cap refused and that is
//     applied once a seat is free; an admin applying its own OLDER record as a removal; the expiry
//     sweep's demotion of `invited`; the owner's own UPDATE and DELETE.
//
// Fixtures are written by the schema owner without claims. Every hostile query and every write the
// rule depends on runs as rf_api with the caller's own claims, as PgStore.withClaims opens it.
// Synthetic bytes and ids only: no ledger content, no phone number (CLAUDE.md rule 4).
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why, and RLS_REQUIRE=1 makes that a failure.
import postgres from "postgres";
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { apiSql } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — revocation_at_seq.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP revocation_at_seq.test.ts: ${why}`);
}
const ignore = !url;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));
/** Seat- and book-unlimited, so no cap stands in for the refusal under test; removed after. */
const PLAN = "zz_rev97_many";
/** Four seats: E-03b-13's seat cap refusal. Removed after. */
const CAP4 = "zz_rev97_cap4";

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
        await sql`insert into plan_catalogue (id, entity_type, name, sort_order, members,
            business_books, devices, envelopes_per_book, tenant_bytes, attachment_bytes, features,
            price_yearly_paise, price_monthly_paise)
          values (${PLAN}, 'family', 'Rev97 many', 98, -1, -1, 5, 1000, 1000000, 1000, '{}', 0, 0),
                 (${CAP4}, 'family', 'Rev97 cap4', 99, 4, -1, 5, 1000, 1000000, 1000, '{}', 0, 0)
          on conflict (id) do nothing`;
        await fn();
      } finally {
        await sql`update subscriptions set plan = 'free' where plan in (${PLAN}, ${CAP4})`;
        await sql`delete from plan_catalogue where id in (${PLAN}, ${CAP4})`;
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
/** A record the CALLER files through rf_api (signed_records_insert decides), with any extra
 *  columns rf_api is able to set itself. Returns its id and seq. */
async function file(
  p: P,
  t: string,
  kind: string,
  payload: Record<string, unknown>,
  forged: { applied: boolean } = { applied: false },
): Promise<{ id: string; seq: string }> {
  const id = crypto.randomUUID();
  const [r] = await asApi(
    p,
    (s) =>
      forged.applied
        ? s`insert into signed_records (id, suite_version, tenant_id, kind, payload_json,
            payload_bytes, author_device, author_sig, hlc, applied_at, apply_note)
          values (${id}, 1, ${t}, ${kind}, ${s.json(payload as postgres.JSONValue)}, ${rand(8)},
                  ${p.dev}, ${rand(64)}, 1, now(), 'membership removed')
          returning seq::text as seq`
        : s`insert into signed_records
            (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device,
             author_sig, hlc)
          values (${id}, 1, ${t}, ${kind}, ${s.json(payload as postgres.JSONValue)}, ${rand(8)},
                  ${p.dev}, ${rand(64)}, 1)
          returning seq::text as seq`,
  );
  return { id, seq: r.seq as string };
}
/** A membership record filed by `admin` and APPLIED by rf.project_membership in the same
 *  transaction, as the edge applies it — the one write that is a fact. */
async function project(admin: P, t: string, user: string, status: string): Promise<string> {
  const id = crypto.randomUUID();
  const kind = status === "removed" ? "member_removal" : "membership_status";
  const payload = status === "removed" ? { user_id: user } : { user_id: user, status };
  const [r] = await asApi(admin, async (s) => {
    const rows = await s`insert into signed_records
        (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig,
         hlc)
      values (${id}, 1, ${t}, ${kind}, ${s.json(payload as postgres.JSONValue)}, ${rand(8)},
              ${admin.dev}, ${rand(64)}, 1)
      returning seq::text as seq`;
    await s`select rf.project_membership(${id}::uuid, ${t}::uuid, ${user}::uuid, ${status})`;
    await s`select rf.mark_record_applied(${id}::uuid, ${"membership " + status})`;
    return rows;
  });
  return r.seq as string;
}
async function countAs(p: P, dev: string) {
  const [r] = await asApi(p, (s) => s`select * from rf.revocation_count(${dev}::uuid)`);
  return {
    approvers: r.approvers as number,
    k: r.k as number | null,
    effective_seq: r.effective_seq === null ? null : String(r.effective_seq),
  };
}
const mayRevoke = async (g: P, dev: string, t: string) =>
  (await asApi(g, (s) => s`select rf.guardian_may_revoke(${dev}::uuid, ${t}::uuid, 1) as ok`))[0]
    .ok as boolean;
/** The log, read by the schema owner: `user`'s facts in `t`, oldest first. */
async function factsOf(t: string, user: string): Promise<{ at: bigint; status: string }[]> {
  const rows = await sql`select at_seq::text as at, status from membership_facts
    where tenant_id = ${t} and user_id = ${user} order by at_seq`;
  return rows.map((f) => ({ at: BigInt(f.at as string), status: f.status as string }));
}
/** A tenant on PLAN: `adm` active and admin of a business book (rf.is_tenant_admin), and `active`
 *  more people active after a verified ceremony, all seeded by the owner. */
async function family(active: P[]): Promise<{ t: string; adm: P }> {
  const adm = await person();
  const [tr] = await sql`insert into tenants (type) values ('family') returning id`;
  const t = tr.id as string;
  await sql`insert into subscriptions (tenant_id, plan) values (${t}, ${PLAN})`;
  await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${adm.user}, 'active')`;
  const ceremony = crypto.randomUUID();
  await sql`insert into signed_records
      (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${ceremony}, 1, ${t}, 'verification_event', '{}'::jsonb, ${rand(8)}, ${adm.dev},
            ${rand(64)}, 1)`;
  for (const p of active) {
    await sql`insert into verification_events
        (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${t}, ${p.user}, ${adm.user}, 'qr_in_person', 'verified', ${ceremony})`;
    await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${p.user}, 'active')`;
  }
  const book = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type) values (${book}, ${t}, 'business')`;
  await sql`insert into book_roles (book_id, user_id, role) values (${book}, ${adm.user}, 'admin')`;
  return { t, adm };
}
/** A k-of-n set at version 1 for `subject`, set up in `t`. */
async function guardianSet(subject: P, t: string, k: number, gs: P[]) {
  await sql`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
    values (${subject.user}, 1, ${gs.length}, ${k}, ${t})`;
  for (const g of gs) {
    await sql`insert into guardian_set_members
        (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
      values (${subject.user}, 1, ${g.user}, ${rand(32)})`;
  }
}
const approvalOf = (subject: P) => ({
  revoked_device_id: subject.dev,
  subject_user_id: subject.user,
  share_set_version: 1,
});

test(
  "E-03b-10 the database judges the subject's membership at each approval's own seq, from membership_facts and over rows no caller can see: an approval filed while the subject is removed never counts, not after a re-admission either, and rf.guardian_may_revoke answers it at that seq; a later removal never un-counts one already filed; the history is the SUBJECT's — another member joining after the subject's removal, or removed after its re-admission, changes nothing; a removal record that rf_api files and marks applied itself is not a fact, nor is a non-admin's refused projection; membership_facts holds exactly the memberships row's changes, each at a fresh seq above its applying record's, is RLS-forced with no policy and no rf_api grant, and refuses even the schema owner's UPDATE and DELETE; rf.subject_held_at and rf.membership_fact_log are SECURITY DEFINER with search_path public, pg_temp and are not rf_api's or PUBLIC's",
  async () => {
    // A family tenant: `adm` active and admin of a business book (rf.is_tenant_admin), the subject
    // active, g1 active, g2 still pending (it can see no membership row but its own), `plain` an
    // active member who is no admin.
    const adm = await person(), subject = await person(), g1 = await person();
    const g2 = await person(), plain = await person();
    const [tr] = await sql`insert into tenants (type) values ('family') returning id`;
    const t = tr.id as string;
    await sql`insert into subscriptions (tenant_id, plan) values (${t}, ${PLAN})`;
    await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${adm.user}, 'active')`;
    const ceremony = crypto.randomUUID();
    await sql`insert into signed_records
        (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
      values (${ceremony}, 1, ${t}, 'verification_event', '{}'::jsonb, ${rand(8)}, ${adm.dev},
              ${rand(64)}, 1)`;
    for (const p of [subject, g1, plain]) {
      await sql`insert into verification_events
          (tenant_id, subject_user, verifier_user, method, result, source_record_id)
        values (${t}, ${p.user}, ${adm.user}, 'qr_in_person', 'verified', ${ceremony})`;
      await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${p.user}, 'active')`;
    }
    await sql`insert into memberships (tenant_id, user_id, status)
      values (${t}, ${g2.user}, 'joined_pending_verification')`;
    const book = crypto.randomUUID();
    await sql`insert into books (id, tenant_id, type) values (${book}, ${t}, 'business')`;
    await sql`insert into book_roles (book_id, user_id, role) values (${book}, ${adm.user}, 'admin')`;
    await sql`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
      values (${subject.user}, 1, 2, 2, ${t})`;
    for (const g of [g1, g2]) {
      await sql`insert into guardian_set_members
          (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
        values (${subject.user}, 1, ${g.user}, ${rand(32)})`;
    }
    const approval = {
      revoked_device_id: subject.dev,
      subject_user_id: subject.user,
      share_set_version: 1,
    };
    assertEquals(await mayRevoke(g2, subject.dev, t), true, "precondition: g2 may revoke now");

    // The subject is removed (a fact). Another person then joins the tenant (a fact, not
    // `removed`, and the latest in the tenant): the subject's history is its own, so g1, filing
    // now, still files while the SUBJECT is removed.
    const out = await project(adm, t, subject.user, "removed");
    const newbie = await person();
    await project(adm, t, newbie.user, "joined_pending_verification");
    const a1 = await file(g1, t, "device_revocation", approval);
    assertEquals(
      await mayRevoke(g1, subject.dev, t),
      false,
      "rf.guardian_may_revoke judges g1's approval at its own seq, while the subject is removed",
    );
    assertEquals(
      await countAs(g1, subject.dev),
      { approvers: 0, k: null, effective_seq: null },
      "filed while the subject is removed: not counted",
    );

    // Re-admitted (a fact). Then `plain` files the subject's removal and marks it applied itself,
    // and its own projection of it is refused: neither is a fact.
    const back = await project(adm, t, subject.user, "joined_pending_verification");
    const forged = await file(plain, t, "member_removal", { user_id: subject.user }, {
      applied: true,
    });
    const [stored] = await sql`select applied_at is not null as applied, apply_note
      from signed_records where id = ${forged.id}`;
    assertEquals(
      [stored.applied, stored.apply_note],
      [true, "membership removed"],
      "precondition: rf_api wrote an 'applied' removal record of its own",
    );
    assertRefused(
      await pgErr(
        asApi(
          plain,
          (s) =>
            s`select rf.project_membership(${forged.id}::uuid, ${t}::uuid, ${subject.user}::uuid, 'removed')`,
        ),
      ),
      "42501",
      "not_admin",
      "a member who is no admin cannot apply it",
    );
    assertEquals(
      await countAs(g1, subject.dev),
      { approvers: 0, k: null, effective_seq: null },
      "g1's approval was filed while the subject was removed: the re-admission does not count it",
    );

    // `plain` is then removed (a fact, `removed`, the latest in the tenant): it is not the subject.
    // g2, still pending (it SELECTs no membership row of the subject and no approval but its own),
    // files after the re-admission and the forged record: counted, judged at its own seq.
    await project(adm, t, plain.user, "removed");
    const a2 = await file(g2, t, "device_revocation", approval);
    const [seen] = await asApi(
      g2,
      (s) =>
        s`select (select count(*)::int from memberships where user_id = ${subject.user}) as m,
               (select count(*)::int from signed_records where kind = 'device_revocation') as r`,
    );
    assertEquals([seen.m, seen.r], [0, 1], "precondition: g2 sees neither row the rule reads");
    assertEquals(await mayRevoke(g2, subject.dev, t), true, "g2's approval is answered counted");
    assertEquals(await countAs(g2, subject.dev), { approvers: 1, k: 2, effective_seq: null });

    // g1 files again after the re-admission: its first approval never counted, so it does not
    // shadow this one; k is reached at this approval's seq.
    const a3 = await file(g1, t, "device_revocation", approval);
    assertEquals(await mayRevoke(g1, subject.dev, t), true, "judged at g1's latest approval");
    assertEquals(await countAs(g2, subject.dev), { approvers: 2, k: 2, effective_seq: a3.seq });

    // A later removal never un-counts the approvals already filed.
    const again = await project(adm, t, subject.user, "removed");
    assertEquals(
      await countAs(g2, subject.dev),
      { approvers: 2, k: 2, effective_seq: a3.seq },
      "the cut-off only moves earlier (ADR 2026-09-06 §3)",
    );
    assertEquals(
      await mayRevoke(g1, subject.dev, t),
      true,
      "rf.guardian_may_revoke still answers g1's latest approval at its own seq, not now",
    );
    assert(BigInt(a1.seq) < BigInt(back) && BigInt(a2.seq) < BigInt(a3.seq));

    // The log holds exactly the row's changes: the owner's seeding INSERT and the three
    // projections, each at a fresh seq taken when the row changed — above its applying record's
    // seq, below the next approval's — and nothing rf_api filed or marked itself.
    const facts = await factsOf(t, subject.user);
    assertEquals(
      facts.map((f) => f.status),
      ["active", "removed", "joined_pending_verification", "removed"],
      "the memberships row's history, and nothing rf_api filed or marked itself",
    );
    assert(facts[1].at > BigInt(out) && facts[1].at < BigInt(a1.seq), "removal: after its record");
    assert(facts[2].at > BigInt(back) && facts[2].at < BigInt(forged.seq), "re-admission");
    assert(facts[3].at > BigInt(again), "the second removal: after its record");
    assertEquals(
      (await factsOf(t, newbie.user)).map((f) => f.status),
      ["joined_pending_verification"],
    );
    assertEquals((await factsOf(t, plain.user)).map((f) => f.status), ["active", "removed"]);

    // Nobody's table.
    for (const priv of ["SELECT", "INSERT", "UPDATE", "DELETE"]) {
      const [g] = await sql`select has_table_privilege('rf_api', 'public.membership_facts', ${priv})
        as ok`;
      assertEquals(g.ok, false, `rf_api holds no ${priv} on membership_facts`);
    }
    const [rel] = await sql`select relrowsecurity, relforcerowsecurity,
        (select count(*)::int from pg_policies where tablename = 'membership_facts') as policies
      from pg_class where oid = 'public.membership_facts'::regclass`;
    assertEquals([rel.relrowsecurity, rel.relforcerowsecurity, rel.policies], [true, true, 0]);
    assertRefused(
      await pgErr(asApi(adm, (s) => s`select count(*) from membership_facts`)),
      "42501",
      "permission denied",
      "rf_api cannot read the log",
    );
    assertRefused(
      await pgErr(
        asApi(
          plain,
          (s) =>
            s`insert into membership_facts (at_seq, tenant_id, user_id, status, source_record_id)
          values (${forged.seq}, ${t}, ${subject.user}, 'removed', ${forged.id})`,
        ),
      ),
      "42501",
      "permission denied",
      "rf_api cannot write a fact",
    );
    assertRefused(
      await pgErr(sql`update membership_facts set status = 'active'
        where tenant_id = ${t} and user_id = ${subject.user}`),
      "23514",
      "append_only",
      "the schema owner's UPDATE",
    );
    assertRefused(
      await pgErr(sql`delete from membership_facts where tenant_id = ${t}`),
      "23514",
      "append_only",
      "the schema owner's DELETE",
    );

    // The helpers are internal.
    for (const name of ["subject_held_at", "membership_fact_log"]) {
      const fns = await sql`select p.oid::regprocedure::text as sig, p.prosecdef, p.proconfig,
          has_function_privilege('rf_api', p.oid, 'execute') as api,
          has_function_privilege('public', p.oid, 'execute') as pub
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'rf' and p.proname = ${name}`;
      assertEquals(fns.length, 1, `rf.${name}: no overload`);
      assert(fns[0].prosecdef, `rf.${name} is SECURITY DEFINER`);
      assertEquals(fns[0].proconfig, ["search_path=public, pg_temp"]);
      assertEquals(
        [fns[0].api, fns[0].pub],
        [false, false],
        `rf.${name}: neither rf_api's nor PUBLIC's`,
      );
    }
    // …and the trigger that calls it fires on every insert, status change and delete of a row.
    const [tg] = await sql`select pg_get_triggerdef(t.oid) as def from pg_trigger t
      where t.tgrelid = 'public.memberships'::regclass and t.tgname = 'memberships_facts_log'`;
    assertEquals(
      tg?.def,
      "CREATE TRIGGER memberships_facts_log AFTER INSERT OR DELETE OR UPDATE OF status ON public.memberships FOR EACH ROW EXECUTE FUNCTION rf.membership_fact_log()",
    );
    assertRefused(
      await pgErr(
        asApi(
          g2,
          (s) => s`select rf.subject_held_at(${t}::uuid, ${subject.user}::uuid, 1::bigint)`,
        ),
      ),
      "42501",
      "permission denied",
      "rf_api cannot ask the history",
    );
  },
);

test(
  "E-03b-13 every writer of a membership row is a fact at the moment it writes, never at a record's seq (desk 97 review, findings 1-2): a re-admission the seat cap refused, applied once a seat is free (sync-meta's re-send), does not count the approvals filed while the subject was removed — the count stays empty and the device certified; an admin applying its own OLDER designation record as the subject's removal does not un-count the approval filed before it; the expiry sweep's demotion of an `invited` subject is a fact, so an approval filed after it never counts; the owner's own UPDATE and DELETE of a row are facts too; with no fact the subject holds no membership, so an approval filed before it ever joined never counts",
  async () => {
    const subject = await person(), g1 = await person(), g2 = await person();
    const spare = await person(), s2 = await person(), s3 = await person();
    const { t, adm } = await family([subject, g1, g2, spare, s2, s3]);
    await guardianSet(subject, t, 2, [g1, g2]);
    await guardianSet(s2, t, 2, [g1, g2]);
    await guardianSet(s3, t, 2, [g1, g2]);
    const empty = { approvers: 0, k: null, effective_seq: null };

    // (1) The seat cap refuses the re-admission; it is applied later, as sync-meta's duplicate arm
    // applies a stored record that was never applied (`rec = stored`).
    await project(adm, t, subject.user, "removed");
    await project(adm, t, s2.user, "removed");
    await project(adm, t, s3.user, "removed");
    // Holders now: adm, g1, g2, spare — four, the plan's four seats.
    await sql`update subscriptions set plan = ${CAP4} where tenant_id = ${t}`;
    const readmit = await file(adm, t, "membership_status", {
      user_id: subject.user,
      status: "joined_pending_verification",
    });
    const apply = () =>
      asApi(
        adm,
        (s) =>
          s`select rf.project_membership(${readmit.id}::uuid, ${t}::uuid, ${subject.user}::uuid,
            'joined_pending_verification')`,
      );
    assertRefused(await pgErr(apply()), "P0001", "seat_cap", "the plan is full: not applied");
    const a1 = await file(g1, t, "device_revocation", approvalOf(subject));
    assertEquals(
      await mayRevoke(g1, subject.dev, t),
      false,
      "g1 files while the subject is removed",
    );
    const a2 = await file(g2, t, "device_revocation", approvalOf(subject));
    assertEquals(
      await mayRevoke(g2, subject.dev, t),
      false,
      "g2 files while the subject is removed",
    );
    assertEquals(await countAs(g1, subject.dev), empty);

    await project(adm, t, spare.user, "removed"); // a seat is freed
    await apply(); // the stored record, applied now
    const [st] = await sql`select status from memberships
      where tenant_id = ${t} and user_id = ${subject.user}`;
    assertEquals(st.status, "joined_pending_verification", "precondition: re-admitted now");
    assertEquals(
      await countAs(g1, subject.dev),
      empty,
      "the re-admission is a fact when applied, after both approvals: neither counts (dated at its record's seq, they made 2 of 2 with the device still certified)",
    );
    const readmitted = (await factsOf(t, subject.user)).at(-1)!;
    assertEquals(readmitted.status, "joined_pending_verification");
    assert(readmitted.at > BigInt(a2.seq) && BigInt(readmit.seq) < BigInt(a1.seq));
    assertEquals(await mayRevoke(g1, subject.dev, t), false, "g1 is still answered at a1's seq");
    const [dv] = await sql`select status from devices where id = ${subject.dev}`;
    assertEquals(dv.status, "certified");
    const b1 = await file(g1, t, "device_revocation", approvalOf(subject));
    assertEquals(await mayRevoke(g1, subject.dev, t), true);
    assertEquals(await countAs(g1, subject.dev), { approvers: 1, k: 2, effective_seq: null });
    const b2 = await file(g2, t, "device_revocation", approvalOf(subject));
    assertEquals(await countAs(g2, subject.dev), { approvers: 2, k: 2, effective_seq: b2.seq });
    assert(BigInt(b1.seq) < BigInt(b2.seq));
    await sql`update subscriptions set plan = ${PLAN} where tenant_id = ${t}`;

    // (2) A hostile admin (rf_api with its own claims, ADR 2026-09-05d §2) holds an OLDER record of
    // its own device in the tenant — a designation, never a membership record — and applies it as
    // s2's removal after g1's approval. rf.require_record checks only the device and the tenant.
    await project(adm, t, s2.user, "joined_pending_verification");
    const label = await file(adm, t, "designation", { label: "synthetic" });
    const c1 = await file(g1, t, "device_revocation", approvalOf(s2));
    assertEquals(await countAs(g1, s2.dev), { approvers: 1, k: 2, effective_seq: null });
    await asApi(
      adm,
      (s) =>
        s`select rf.project_membership(${label.id}::uuid, ${t}::uuid, ${s2.user}::uuid, 'removed')`,
    );
    assert(BigInt(label.seq) < BigInt(c1.seq), "precondition: the record predates g1's approval");
    assertEquals(
      await countAs(g1, s2.dev),
      { approvers: 1, k: 2, effective_seq: null },
      "the removal is a fact when applied, after g1's approval: it never un-counts it",
    );
    assertEquals(await mayRevoke(g1, s2.dev, t), true, "g1 is still answered at c1's seq");
    await project(adm, t, s2.user, "joined_pending_verification");
    const c2 = await file(g2, t, "device_revocation", approvalOf(s2));
    assertEquals(await countAs(g2, s2.dev), { approvers: 2, k: 2, effective_seq: c2.seq });

    // (3) The expiry sweep. s3 (removed) is re-invited: a live invite to its number under the
    // admin's signed `invite` record, then the admin's membership_status `invited`.
    const inviteRec = await file(adm, t, "invite", { roles: [] });
    const [h] = await sql`select phone_hmac from users where id = ${s3.user}`; // the edge's HMAC
    const [inv] = await asApi(
      adm,
      (s) =>
        s`select rf.create_invite(${t}::uuid, ${h.phone_hmac}, '[]'::jsonb, ${rand(16)},
            ${inviteRec.id}::uuid) as id`,
    );
    await project(adm, t, s3.user, "invited");
    const d1 = await file(g1, t, "device_revocation", approvalOf(s3));
    assertEquals(
      await mayRevoke(g1, s3.dev, t),
      true,
      "invited is a membership other than removed",
    );
    assertEquals(await countAs(g1, s3.dev), { approvers: 1, k: 2, effective_seq: null });
    // Seven days pass: the window is fixed at issue, so only the owner, triggers off for this one
    // transaction, can back-date it. Then the sweep runs, as pg_cron runs it.
    await sql.begin(async (s) => {
      await s`set local session_replication_role = replica`;
      await s`update invites set created_at = now() - interval '8 days',
        expires_at = now() - interval '1 day' where id = ${inv.id}`;
    });
    await sql`select rf.expire_invites()`;
    const [s3row] = await sql`select status from memberships
      where tenant_id = ${t} and user_id = ${s3.user}`;
    assertEquals(s3row.status, "removed", "precondition: the sweep demoted s3");
    assertEquals((await factsOf(t, s3.user)).at(-1)?.status, "removed", "and it is a fact");
    const d2 = await file(g2, t, "device_revocation", approvalOf(s3));
    assertEquals(await mayRevoke(g2, s3.dev, t), false, "filed after the sweep's removal");
    assertEquals(
      await countAs(g2, s3.dev),
      { approvers: 1, k: 2, effective_seq: null },
      "g2's approval, filed while s3 is removed by the sweep, never counts",
    );
    assert(BigInt(d1.seq) < BigInt(d2.seq));

    // (4) The owner's own writes are facts too: an UPDATE of the status, and a DELETE (nothing
    // deletes a membership today; a deleted row holds none, so it is logged `removed`).
    const owner = await person();
    await sql`insert into memberships (tenant_id, user_id, status)
      values (${t}, ${owner.user}, 'joined_pending_verification')`;
    await sql`update memberships set status = 'removed'
      where tenant_id = ${t} and user_id = ${owner.user}`;
    await sql`update memberships set status = 'removed'
      where tenant_id = ${t} and user_id = ${owner.user}`; // no change: no fact
    await sql`update memberships set status = 'joined_pending_verification'
      where tenant_id = ${t} and user_id = ${owner.user}`;
    await sql`delete from memberships where tenant_id = ${t} and user_id = ${owner.user}`;
    assertEquals(
      (await factsOf(t, owner.user)).map((f) => f.status),
      ["joined_pending_verification", "removed", "joined_pending_verification", "removed"],
    );

    // (5) No fact is no membership (0027 §2; ⚠️ SPEC (d) in its header — the client reads "held"):
    // an approval filed before the subject ever joined the tenant never counts, even once the
    // subject joins and publishes the set it names.
    const late = await person();
    const e1 = await file(g1, t, "device_revocation", approvalOf(late));
    assertEquals(await factsOf(t, late.user), [], "precondition: no membership there yet");
    const seen = await file(adm, t, "verification_event", {});
    await sql`insert into verification_events
        (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${t}, ${late.user}, ${adm.user}, 'qr_in_person', 'verified', ${seen.id})`;
    await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${late.user}, 'active')`;
    await guardianSet(late, t, 2, [g1, g2]);
    assertEquals(await countAs(g1, late.dev), empty, "filed before the subject joined");
    const e2 = await file(g2, t, "device_revocation", approvalOf(late));
    assertEquals(await countAs(g2, late.dev), { approvers: 1, k: 2, effective_seq: null });
    assert(BigInt(e1.seq) < BigInt(e2.seq));
  },
);
