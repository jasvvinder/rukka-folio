// Hostile-query suite for rung 3 of the recovery ladder — 04 §7.4 🔒 (the paper sheet), 03 §2.2/
// §2.5, ADR 2026-09-05d §2, ADR 2026-09-05b §7/§8, CLAUDE.md rule 2.
//
// The thing under test is one row of opaque bytes — `sealed_RK_blob = XChaCha20(RK, UMK_priv)` —
// and two questions about it that the database, not the edge function, has to answer:
//
//   * **who may READ it.** The honest reader is a fresh phone that has passed OTP and holds nothing
//     else (06 §5 "New phone, no old device"), with an RK a human is reading off paper. Everyone
//     else — a fellow member, a guardian, another tenant, an uncertified device of somebody else —
//     must reach nothing, and must reach it *indistinguishably* from a user who never printed a
//     sheet (no oracle, ADR 2026-09-05d §2).
//   * **who may OVERWRITE it.** Nobody, ever. 04 §7.4's "regenerating a sheet rotates RK and
//     invalidates the old sheet" is an INSERT of the next version; rf_api holds no UPDATE and no
//     DELETE grant on `recovery_sheets` at all, the same posture 0010 took for the decision rows.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-06-60, E-06-61.
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — recovery_sheet.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP recovery_sheet.test.ts: ${why}`);
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
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

interface Fx {
  t1: string;
  t2: string;
  subject: string;
  other: string; // certified member of t1 who is not the subject
  stranger: string; // certified member of t2
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
  const subject = await mk(), other = await mk(), stranger = await mk();
  const dev: Record<string, string> = {};
  for (
    const [name, user, status] of [
      ["subjectOld", subject, "certified"], // the device that printed the sheet at signup
      ["candidate", subject, "registered"], // the fresh phone — UNCERTIFIED by construction
      ["other", other, "certified"],
      ["otherRaw", other, "registered"],
      ["stranger", stranger, "certified"],
    ] as const
  ) {
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${user}, ${rand(32)}, ${rand(32)}, ${status}) returning id`;
    dev[name] = d.id;
  }
  // The subject founds t1 and the stranger founds t2 (06 §5: a founder has nobody to verify them);
  // anyone else reaches `active` only behind a signed verification event (0008, ADR 05d §7).
  await sql`insert into memberships (tenant_id, user_id, status) values (${t1.id}, ${subject}, 'active')`;
  await sql`insert into memberships (tenant_id, user_id, status) values (${t2.id}, ${stranger}, 'active')`;
  const rec = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${rec}, 1, ${t1.id}, 'verification_event', '{}'::jsonb, ${rand(8)},
            ${dev.subjectOld}, ${rand(64)}, 1)`;
  await sql`insert into verification_events
    (tenant_id, subject_user, verifier_user, method, result, source_record_id)
    values (${t1.id}, ${other}, ${subject}, 'qr_in_person', 'verified', ${rec})`;
  await sql`insert into memberships (tenant_id, user_id, status) values (${t1.id}, ${other}, 'active')`;
  return { t1: t1.id, t2: t2.id, subject, other, stranger, dev };
}

/** 04 §7.4: the sheet is printed by a device that already holds the UMK. */
function publish(
  user: string,
  device: string,
  version: number,
  blob = rand(72),
  as = user,
): Promise<PgErr> {
  return pgErr(
    asApi(
      user,
      device,
      (s) =>
        s`insert into recovery_sheets (user_id, sheet_version, blob)
          values (${as}, ${version}, ${blob})`,
    ),
  );
}

/** The fixture's only time machine: the guard stamps `created_at` from the server clock, so a
 *  second publication inside the 60 s rate bound is refused. Backdate with the trigger lifted. */
async function backdate(): Promise<void> {
  await sql`alter table recovery_sheets disable trigger recovery_sheets_guard`;
  await sql`update recovery_sheets set created_at = created_at - interval '2 minutes'`;
  await sql`alter table recovery_sheets enable trigger recovery_sheets_guard`;
}

Deno.test({
  name:
    "E-06-60 the sealed sheet blob is WRITE-ONCE: rf_api holds no UPDATE and no DELETE grant on recovery_sheets, the append-only trigger refuses both even with the grant lifted, a regenerated sheet is the NEXT version and an older or repeated version is refused by name, the rate bound is named rather than silent, and every earlier row survives untouched (04 §7.4 🔒; CLAUDE.md rule 2; ADR 2026-09-05b §7)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();

    // ---- the grant table itself: a policy cannot loosen a grant that does not exist
    const grants = await sql<{ privilege_type: string }[]>`
      select privilege_type from information_schema.role_table_grants
      where grantee = 'rf_api' and table_schema = 'public' and table_name = 'recovery_sheets'
        and privilege_type in ('UPDATE','DELETE')`;
    assertEquals(grants.length, 0, "no UPDATE/DELETE grant on the sheet store");

    const first = rand(72);
    assertEquals((await publish(fx.subject, fx.dev.subjectOld, 1, first)).code, "ok");

    // ---- rf_api: refused for want of a grant (42501), not merely by a policy
    assertEquals(
      await pgCode(
        asApi(
          fx.subject,
          fx.dev.subjectOld,
          (s) => s`update recovery_sheets set blob = ${rand(72)} where user_id = ${fx.subject}`,
        ),
      ),
      "42501",
    );
    assertEquals(
      await pgCode(
        asApi(
          fx.subject,
          fx.dev.subjectOld,
          (s) => s`delete from recovery_sheets where user_id = ${fx.subject}`,
        ),
      ),
      "42501",
    );

    // ---- and with the grant question set aside entirely, the trigger still refuses: the table
    //      owner cannot rewrite a sheet either, which is what makes append-only a property of the
    //      database rather than of the role list.
    assertStringIncludes(
      (await pgErr(
        sql`update recovery_sheets set blob = ${rand(72)} where user_id = ${fx.subject}`,
      ))
        .message,
      "append_only",
    );
    assertStringIncludes(
      (await pgErr(sql`delete from recovery_sheets where user_id = ${fx.subject}`)).message,
      "append_only",
    );

    // ---- the rate bound is a NAMED refusal (never a silent drop, 05c)
    assertStringIncludes(
      (await publish(fx.subject, fx.dev.subjectOld, 2)).message,
      "sheet_flood",
    );

    await backdate();

    // ---- an older version can never be added behind a live one, and a repeat is not an overwrite
    assertStringIncludes(
      (await publish(fx.subject, fx.dev.subjectOld, 1)).message,
      "sheet_version_out_of_order",
    );
    assertStringIncludes(
      (await publish(fx.subject, fx.dev.subjectOld, 3)).message,
      "sheet_version_out_of_order",
    );

    // ---- regenerating publishes the next version; the old row is still there, byte-for-byte
    const second = rand(72);
    assertEquals((await publish(fx.subject, fx.dev.subjectOld, 2, second)).code, "ok");
    const all = await asApi(
      fx.subject,
      fx.dev.subjectOld,
      (s) => s`select sheet_version, blob from recovery_sheets order by sheet_version`,
    );
    assertEquals(all.length, 2);
    assertEquals(Array.from(all[0].blob as Uint8Array), Array.from(first), "version 1 untouched");
    assertEquals(Array.from(all[1].blob as Uint8Array), Array.from(second));

    // ---- "the current sheet" is derived, never a flag: the highest version, and only it, is what
    //      the route serves (04 §7.4 — the old sheet is invalidated by rotation).
    const [cur] = await asApi(
      fx.subject,
      fx.dev.subjectOld,
      (s) =>
        s`select sheet_version, blob from recovery_sheets where user_id = rf.user_id()
          order by sheet_version desc limit 1`,
    );
    assertEquals(cur.sheet_version, 2);
    assertEquals(Array.from(cur.blob as Uint8Array), Array.from(second));

    // ---- retention is the maintenance role's, and it never takes the live sheet
    await backdate();
    const [swept] = await sql.begin(async (s) => {
      await s`set local role rf_maintenance`;
      return await s`select rf.sweep_recovery_sheets() as n`;
    }) as unknown as { n: number }[];
    assertEquals(swept.n, 0, "30 days, not two minutes");
    assertEquals(
      await pgCode(
        sql.begin(async (s) => {
          await s`set local role rf_api`;
          await s`select rf.sweep_recovery_sheets()`;
        }),
      ),
      "42501",
      "the API role cannot reach the sweep",
    );
    await sql.end();
  },
});

Deno.test({
  name:
    "E-06-61 who may read or write a sealed sheet blob: the subject's own devices read it — including the UNCERTIFIED fresh phone rung 3 exists for — while a fellow member, another tenant and an uncertified device of theirs read nothing and learn nothing from the answer; only a CERTIFIED device of the subject may publish, and no caller may publish under another user's id (04 §7.4 🔒; ADR 2026-09-05d §2; 03 §2.5)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();
    const blob = rand(72);
    assertEquals((await publish(fx.subject, fx.dev.subjectOld, 1, blob)).code, "ok");

    const read = (user: string, device: string) =>
      asApi(user, device, (s) => s`select sheet_version, blob from recovery_sheets`);

    // ---- the device that printed it
    assertEquals((await read(fx.subject, fx.dev.subjectOld)).length, 1);

    // ---- and the fresh phone: OTP passed, uncertified, an RK on paper. This is the whole rung.
    const fresh = await read(fx.subject, fx.dev.candidate);
    assertEquals(fresh.length, 1);
    assertEquals(
      Array.from(fresh[0].blob as Uint8Array),
      Array.from(blob),
      "bytes out exactly as they went in — the server can open none of them",
    );

    // ---- everybody else reads nothing, and the empty answer is the SAME answer a user with no
    //      sheet gets: the route is no oracle for who printed one (ADR 2026-09-05d §2).
    for (
      const [u, d] of [
        [fx.other, "other"],
        [fx.other, "otherRaw"],
        [fx.stranger, "stranger"],
      ] as const
    ) {
      assertEquals((await read(u, fx.dev[d])).length, 0);
    }
    // no claims at all is the same nothing
    assertEquals((await asApi(null, null, (s) => s`select * from recovery_sheets`)).length, 0);
    // and a member of the subject's own tenant cannot count them either
    const [n] = await asApi(
      fx.other,
      fx.dev.other,
      (s) => s`select count(*)::int as n from recovery_sheets`,
    );
    assertEquals(n.n, 0);

    // ---- writing: only a certified device of the subject. The uncertified fresh phone may READ
    //      its own blob but may not bury the real sheet under one of its own — a SIM-swapped phone
    //      would otherwise rotate RK out from under the owner.
    //      (The 60 s rate bound is lifted first so the refusal below is the POLICY and not the
    //      timer — a test that cannot tell those apart proves neither.)
    await backdate();
    assertEquals(
      (await publish(fx.subject, fx.dev.candidate, 2)).code,
      "42501",
      "an uncertified device publishes nothing",
    );
    // ---- nor may anyone publish under another user's id, with or without a certified device.
    //      Version 1, because under THEIR row policy the subject's sheet does not exist — so the
    //      version guard passes and what refuses them is the WITH CHECK, which is the point.
    assertEquals((await publish(fx.other, fx.dev.other, 1, rand(72), fx.subject)).code, "42501");
    assertEquals(
      (await publish(fx.stranger, fx.dev.stranger, 1, rand(72), fx.subject)).code,
      "42501",
    );
    // ---- and the subject's sheet is still the one it was
    const after = await read(fx.subject, fx.dev.subjectOld);
    assertEquals(after.length, 1);
    assertEquals(Array.from(after[0].blob as Uint8Array), Array.from(blob));

    // ---- nothing financial is reachable through this table: it carries a user, a version, a time
    //      and opaque bytes, and no column names a book, a tenant or an amount.
    const cols = await sql<{ column_name: string }[]>`
      select column_name from information_schema.columns
      where table_schema = 'public' and table_name = 'recovery_sheets'`;
    assertEquals(
      cols.map((c) => c.column_name).sort(),
      ["blob", "created_at", "sheet_version", "updated_at", "user_id"],
    );
    assert(
      !cols.some((c) => /book|tenant|amount|phone/.test(c.column_name)),
      "a sheet blob is not a ledger row",
    );
    await sql.end();
  },
});
