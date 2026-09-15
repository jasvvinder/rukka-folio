// C-05d-7 🔒 — verification and device events are SIGNED RECORDS (ADR 2026-09-05d §7), proved
// against the database rather than the edge function, because an edge function is just another
// client from RLS's point of view. Ids C-05d-7, E-06-36 … E-06-39.
//
// The attack this closes: `verification_events.source_record_id` was nullable and unreferenced, and
// 0006's membership guard read ANY row with `result='verified'` as proof that a ceremony happened.
// Anyone who could write the table — the table owner, a SECURITY DEFINER function, a maintenance
// path, a compromised server — could therefore mint "she was verified" and walk a membership from
// joined_pending_verification to active without a human ever holding two phones together. 0008
// makes the row impossible to write unsigned AND impossible to believe unbacked.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — verification_records.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP verification_records.test.ts: ${why}`);
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

interface Fx {
  t1: string;
  t2: string;
  admin: string;
  joiner: string;
  outsider: string;
  dev: Record<string, string>;
}
let fx: Fx;

/** A signed record of `kind`, authored by `device` for `tenant`. */
async function record(tenant: string, device: string, kind: string): Promise<string> {
  const id = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${id}, 1, ${tenant}, ${kind}, '{}'::jsonb, ${bytes(8, 1)}, ${device}, ${
    bytes(64, 2)
  }, 1)`;
  return id;
}

const statusOf = async (tenant: string, user: string): Promise<string | null> => {
  const [r] = await sql`select status from memberships
    where tenant_id = ${tenant} and user_id = ${user}`;
  return (r?.status as string) ?? null;
};

async function seed(): Promise<Fx> {
  const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
  const [t2] = await sql`insert into tenants (type) values ('family') returning id`;
  // unique per run: every RLS file shares one database, and users.phone_hmac is unique
  const uniqueHmac = () => {
    const hex = crypto.randomUUID().replace(/-/g, "");
    const a = new Uint8Array(32);
    for (let i = 0; i < 16; i++) a[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
    return a;
  };
  const mk = async () =>
    (await sql`insert into users (phone_hmac, phone_ct) values (${uniqueHmac()}, ${
      bytes(40, 1)
    }) returning id`)[0].id as string;
  const admin = await mk(), joiner = await mk(), outsider = await mk();
  const dev: Record<string, string> = {};
  for (
    const [name, user, status] of [
      ["admin", admin, "certified"],
      ["joiner", joiner, "certified"],
      ["outsider", outsider, "certified"],
    ] as const
  ) {
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${user}, ${bytes(32, 4)}, ${
      bytes(32, 5)
    }, ${status}) returning id`;
    dev[name] = d.id;
  }
  // the founder (06 §5: nobody to verify them), the other tenant's founder, and the person waiting
  await sql`insert into memberships (tenant_id, user_id, status) values
    (${t1.id}, ${admin}, 'active'), (${t2.id}, ${outsider}, 'active'),
    (${t1.id}, ${joiner}, 'joined_pending_verification')`;
  // rf.is_tenant_admin reads book_roles, so the admin needs a book to be an admin of
  const b1 = crypto.randomUUID(), b2 = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type) values (${b1}, ${t1.id}, 'family'), (${b2}, ${t2.id}, 'family')`;
  await sql`insert into book_roles (book_id, user_id, role) values
    (${b1}, ${admin}, 'admin'), (${b2}, ${outsider}, 'admin')`;
  return { t1: t1.id, t2: t2.id, admin, joiner, outsider, dev };
}

Deno.test({
  name: "E-06-36 setup: 0008 applied — the verification_events guard is a trigger on the table",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    const trg = await sql`select tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid
      where not t.tgisinternal and c.relname = 'verification_events' order by tgname`;
    assert(
      trg.some((r) => r.tgname === "verification_events_guard"),
      "the rule is on the table, so it binds the owner and every SECURITY DEFINER function too",
    );
    fx = await seed();
  },
});

Deno.test({
  name:
    "C-05d-7 an unsigned verification event is not believed: the TABLE OWNER cannot write one (no record, wrong kind, another tenant's record), rf_api cannot write one at all, and the membership stays joined_pending_verification throughout — then one properly signed record flips it (ADR 2026-09-05d §7)",
  ignore,
  async fn() {
    assertEquals(await statusOf(fx.t1, fx.joiner), "joined_pending_verification");

    // 1. the table owner, with no record at all — the classic "the server says she's verified"
    const bare = await pgErr(sql`insert into verification_events
      (tenant_id, subject_user, verifier_user, method, result)
      values (${fx.t1}, ${fx.joiner}, ${fx.admin}, 'qr_in_person', 'verified')`);
    assertEquals(bare.code, "23514");
    assertStringIncludes(bare.message, "no_record");

    // 2. the table owner, citing a record that is not a ceremony (a membership_status record)
    const wrongKind = await record(fx.t1, fx.dev.admin, "membership_status");
    const kind = await pgErr(sql`insert into verification_events
      (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${fx.t1}, ${fx.joiner}, ${fx.admin}, 'qr_in_person', 'verified', ${wrongKind})`);
    assertEquals(kind.code, "23514");
    assertStringIncludes(kind.message, "no_record");

    // 3. the table owner, citing ANOTHER tenant's ceremony record
    const foreign = await record(fx.t2, fx.dev.outsider, "verification_event");
    const cross = await pgErr(sql`insert into verification_events
      (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${fx.t1}, ${fx.joiner}, ${fx.admin}, 'qr_in_person', 'verified', ${foreign})`);
    assertEquals(cross.code, "23514");
    assertStringIncludes(cross.message, "no_record");

    // 4. the table owner, citing a record id that does not exist
    const dangling = await pgErr(sql`insert into verification_events
      (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${fx.t1}, ${fx.joiner}, ${fx.admin}, 'qr_in_person', 'verified', ${crypto.randomUUID()})`);
    assert(
      ["23514", "23503"].includes(dangling.code),
      `dangling record accepted (${dangling.code})`,
    );

    // 5. rf_api: no INSERT/UPDATE/DELETE grant on the table at all (0005), and the projector demands
    //    a record authored by THIS device (0005 rf.require_record)
    assertEquals(
      (await pgErr(asApi(
        fx.admin,
        fx.dev.admin,
        (s) =>
          s`insert into verification_events (tenant_id, subject_user, verifier_user, method, result)
            values (${fx.t1}, ${fx.joiner}, ${fx.admin}, 'qr_in_person', 'verified')`,
      ))).code,
      "42501",
    );
    assertEquals(
      (await pgErr(asApi(
        fx.admin,
        fx.dev.admin,
        (s) =>
          s`select rf.project_verification_event(${crypto.randomUUID()}, ${fx.t1}, ${fx.joiner}, ${fx.admin}, 'qr_in_person', 'verified')`,
      ))).code,
      "P0001",
    );

    // nothing was written, and nobody moved
    const [{ n }] = await sql`select count(*)::int as n from verification_events
      where tenant_id = ${fx.t1} and subject_user = ${fx.joiner}`;
    assertEquals(n, 0, "not one unsigned event landed");
    assertEquals(
      await statusOf(fx.t1, fx.joiner),
      "joined_pending_verification",
      "membership stays pending: an unsigned event is not a ceremony",
    );

    // 6. and the honest path still works — the refusals above are the rule, not a dead end
    const rec = await record(fx.t1, fx.dev.admin, "verification_event");
    await asApi(
      fx.admin,
      fx.dev.admin,
      (s) =>
        s`select rf.project_verification_event(${rec}, ${fx.t1}, ${fx.joiner}, ${fx.admin}, 'qr_in_person', 'verified')`,
    );
    assertEquals(await statusOf(fx.t1, fx.joiner), "active");
    const [m] = await sql`select verified_by, verified_method from memberships
      where tenant_id = ${fx.t1} and user_id = ${fx.joiner}`;
    assertEquals(m.verified_by, fx.admin, "06 §7 stamps who verified, from the signed event");
    assertEquals(m.verified_method, "qr_in_person");
  },
});

Deno.test({
  name:
    "E-06-37 the membership guard believes only a BACKED event: with the table's own guard disabled — the shape a row written before 0008 has — an unbacked 'verified' event still cannot walk a membership to active, and an unbacked 'mismatch' cannot block one",
  ignore,
  async fn() {
    const [u] = await sql`insert into users (phone_hmac, phone_ct)
      values (${crypto.getRandomValues(new Uint8Array(32))}, ${bytes(40, 31)}) returning id`;
    await sql`insert into memberships (tenant_id, user_id, status)
      values (${fx.t1}, ${u.id}, 'joined_pending_verification')`;

    // The only way to get an unbacked row into the table is to be the owner AND turn the guard off,
    // which is precisely the legacy row 0008 cannot retro-validate. The membership guard is the
    // second lock, and it holds on its own.
    await sql`alter table verification_events disable trigger verification_events_guard`;
    await sql`alter table verification_events drop constraint verification_events_record_required`;
    try {
      await sql`insert into verification_events (tenant_id, subject_user, verifier_user, method, result)
        values (${fx.t1}, ${u.id}, ${fx.admin}, 'qr_in_person', 'verified'),
               (${fx.t1}, ${u.id}, ${fx.admin}, 'qr_in_person', 'mismatch')`;
    } finally {
      // put 0008 back exactly as it ships — NOT VALID, so the legacy rows survive unvalidated,
      // which is the situation a real upgrade leaves behind
      await sql`alter table verification_events add constraint verification_events_record_required
        check (source_record_id is not null) not valid`;
      await sql`alter table verification_events enable trigger verification_events_guard`;
    }

    const up = await pgErr(sql`update memberships set status = 'active'
      where tenant_id = ${fx.t1} and user_id = ${u.id}`);
    assertEquals(up.code, "23514");
    assertStringIncludes(up.message, "ceremony_required");

    const blocked = await pgErr(sql`update memberships set status = 'blocked'
      where tenant_id = ${fx.t1} and user_id = ${u.id}`);
    assertEquals(blocked.code, "23514");
    assertStringIncludes(blocked.message, "mismatch_required");

    assertEquals(await statusOf(fx.t1, u.id), "joined_pending_verification");

    // sign the mismatch and the block becomes possible — the guard wants the record, not the row
    const rec = await record(fx.t1, fx.dev.admin, "verification_event");
    await sql`insert into verification_events
      (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${fx.t1}, ${u.id}, ${fx.admin}, 'qr_in_person', 'mismatch', ${rec})`;
    await sql`update memberships set status = 'blocked'
      where tenant_id = ${fx.t1} and user_id = ${u.id}`;
    assertEquals(await statusOf(fx.t1, u.id), "blocked");
  },
});

Deno.test({
  name:
    "E-06-38 an event is the copy of a signed fact, so it does not change afterwards: the table owner cannot flip `mismatch` to `verified`, re-point source_record_id, or move the event to another subject",
  ignore,
  async fn() {
    const rec = await record(fx.t1, fx.dev.admin, "verification_event");
    const [e] = await sql`insert into verification_events
      (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${fx.t1}, ${fx.joiner}, ${fx.admin}, 'code_remote', 'mismatch', ${rec}) returning id`;
    const other = await record(fx.t1, fx.dev.admin, "verification_event");

    for (
      const q of [
        sql`update verification_events set result = 'verified' where id = ${e.id}`,
        sql`update verification_events set source_record_id = ${other} where id = ${e.id}`,
        sql`update verification_events set subject_user = ${fx.admin} where id = ${e.id}`,
        sql`update verification_events set tenant_id = ${fx.t2} where id = ${e.id}`,
      ]
    ) {
      const err = await pgErr(q);
      assertEquals(err.code, "23514");
      assertStringIncludes(err.message, "verification_event_immutable");
    }
    const [still] =
      await sql`select result, source_record_id from verification_events where id = ${e.id}`;
    assertEquals(still.result, "mismatch");
    assertEquals(still.source_record_id, rec);
  },
});

Deno.test({
  name:
    "E-06-39 the invite's record kind: `invite` is a legal signed-record kind and the invite guard demands exactly it — a membership_status record no longer authorises an invite (0008 ⚠️ SPEC)",
  ignore,
  async fn() {
    const good = await record(fx.t1, fx.dev.admin, "invite");
    const wrong = await record(fx.t1, fx.dev.admin, "membership_status");
    const hmac = crypto.getRandomValues(new Uint8Array(32)), nonce = bytes(16, 7);

    const refused = await pgErr(asApi(
      fx.admin,
      fx.dev.admin,
      (s) => s`select rf.create_invite(${fx.t1}, ${hmac}, '[]'::jsonb, ${nonce}, ${wrong})`,
    ));
    assertEquals(refused.code, "23514");
    assertStringIncludes(refused.message, "no_record");

    const [r] = await asApi(
      fx.admin,
      fx.dev.admin,
      (s) => s`select rf.create_invite(${fx.t1}, ${hmac}, '[]'::jsonb, ${nonce}, ${good}) as id`,
    );
    const [row] = await sql`select status, source_record_id from invites where id = ${r.id}`;
    assertEquals(row.status, "sent");
    assertEquals(row.source_record_id, good);
    await sql.end();
  },
});
