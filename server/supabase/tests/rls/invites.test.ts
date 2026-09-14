// Hostile-query suite for the invitation & membership state machine (06 §7 🔒, 03 §2.1/§2.5,
// ADR 2026-09-05b §1, ADR 2026-09-05c §4, ADR 2026-09-05d §2/§7/§9).
//
// Two adversaries appear in every test that touches a new policy, per CLAUDE.md:
//   * a CERTIFIED device of ANOTHER tenant, and
//   * an UNCERTIFIED device of THIS tenant
// both get zero rows and a refusal, never a partial answer.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-06-9 … E-06-16.
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — invites.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP invites.test.ts: ${why}`);
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
  stranger: string;
  dev: Record<string, string>;
  b1: string;
  b2: string;
  hmac: Record<string, Uint8Array>;
}
let fx: Fx;

/** A signed record of the given kind, authored by `device` for `tenant`. */
async function record(tenant: string, device: string, kind = "membership_status"): Promise<string> {
  const id = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${id}, 1, ${tenant}, ${kind}, '{}'::jsonb, ${bytes(8, 1)}, ${device}, ${
    bytes(64, 2)
  }, 1)`;
  return id;
}

async function seed(): Promise<Fx> {
  const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
  const [t2] = await sql`insert into tenants (type) values ('business_group') returning id`;
  const hmac: Record<string, Uint8Array> = {};
  const mk = async (name: string, fill: number) => {
    hmac[name] = bytes(32, fill);
    const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${hmac[name]}, ${
      bytes(40, fill)
    }) returning id`;
    return u.id as string;
  };
  const admin1 = await mk("admin1", 11),
    admin2 = await mk("admin2", 12),
    outsider = await mk("outsider", 13),
    invitee = await mk("invitee", 14),
    stranger = await mk("stranger", 15);
  // a number nobody has signed up with — what most invites are addressed to
  hmac.nobody = bytes(32, 99);

  const dev: Record<string, string> = {};
  for (
    const [name, user, status] of [
      ["admin1", admin1, "certified"],
      ["admin1raw", admin1, "registered"], // uncertified device of THIS tenant
      ["admin2", admin2, "certified"],
      ["outsider", outsider, "certified"], // certified device of ANOTHER tenant
      ["invitee", invitee, "certified"],
      ["inviteeraw", invitee, "registered"],
      ["stranger", stranger, "certified"],
    ] as const
  ) {
    const [d] = await sql`insert into devices (user_id, pub_ed, pub_x, status)
      values (${user}, ${bytes(32, 4)}, ${bytes(32, 5)}, ${status}) returning id`;
    dev[name] = d.id;
  }

  // founders first (06 §5: the tenant's first member has nobody to verify them), then a ceremony
  // for the second admin — the guard refuses `active` without one.
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${admin1}, 'active'), (${t2.id}, ${outsider}, 'active')`;
  // since 0008 the ceremony must be signed before it is believed (ADR 2026-09-05d §7)
  await sql`insert into verification_events (tenant_id, subject_user, verifier_user, method, result, source_record_id)
    values (${t1.id}, ${admin2}, ${admin1}, 'qr_in_person', 'verified', ${await record(
    t1.id,
    dev.admin1,
    "verification_event",
  )})`;
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${admin2}, 'active')`;

  const b1 = crypto.randomUUID(), b2 = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type) values (${b1}, ${t1.id}, 'family'), (${b2}, ${t2.id}, 'business')`;
  await sql`insert into book_roles (book_id, user_id, role) values
    (${b1}, ${admin1}, 'admin'), (${b1}, ${admin2}, 'admin'), (${b2}, ${outsider}, 'admin')`;

  return {
    t1: t1.id,
    t2: t2.id,
    admin1,
    admin2,
    outsider,
    invitee,
    stranger,
    dev,
    b1,
    b2,
    hmac,
  };
}

/** Issue an invite as admin1 through the API path. Returns the invite id. */
async function invite(to: Uint8Array, roles: unknown = []): Promise<string> {
  // 0008: the authorising record is an `invite` — a membership_status payload is {user_id, status}
  // and an invitee has no user_id yet (06 §7).
  const rec = await record(fx.t1, fx.dev.admin1, "invite");
  const [r] = await asApi(
    fx.admin1,
    fx.dev.admin1,
    (s) =>
      s`select rf.create_invite(${fx.t1}, ${to}, ${JSON.stringify(roles)}::jsonb, ${
        bytes(16, 7)
      }, ${rec}) as id`,
  );
  return r.id as string;
}

Deno.test({
  name: "E-06-9 setup: migrations applied, invites/memberships guards installed",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    const trg = await sql`select tgname, c.relname from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      where not t.tgisinternal and tgname in ('invites_guard','memberships_guard')
      order by tgname`;
    assertEquals(trg.map((r) => `${r.relname}.${r.tgname}`), [
      "invites.invites_guard",
      "memberships.memberships_guard",
    ], "the state machine is in the database, not only in the edge function");
    fx = await seed();
  },
});

Deno.test({
  name:
    "E-06-10 invite privacy: a second admin of the same tenant sees THAT an invite exists and who sent it — never invitee_hmac or the nonce; another tenant and an uncertified device see nothing at all (ADR 2026-09-05c §4)",
  ignore,
  async fn() {
    const id = await invite(fx.hmac.nobody);

    // the co-admin: the row is visible, the identity is not
    const rows = await asApi(
      fx.admin2,
      fx.dev.admin2,
      (s) => s`select id, tenant_id, status, created_by, expires_at from invites`,
    );
    assertEquals(rows.length, 1);
    assertEquals(rows[0].id, id);
    assertEquals(rows[0].created_by, fx.admin1, "who sent it is allowed");
    for (
      const q of [
        (s: postgres.TransactionSql) => s`select invitee_hmac from invites`,
        (s: postgres.TransactionSql) => s`select nonce from invites`,
        (s: postgres.TransactionSql) => s`select * from invites`,
      ]
    ) {
      assertEquals(await pgCode(asApi(fx.admin2, fx.dev.admin2, q)), "42501", "column not granted");
    }
    // and not even as a filter — Postgres demands SELECT on every column a query REFERENCES, so a
    // co-admin cannot probe the hmac by guessing it either
    assertEquals(
      await pgCode(
        asApi(
          fx.admin2,
          fx.dev.admin2,
          (s) => s`select id from invites where invitee_hmac = ${fx.hmac.nobody}`,
        ),
      ),
      "42501",
      "no oracle on invitee_hmac",
    );

    // certified device of another tenant: zero rows
    assertEquals(
      (await asApi(fx.outsider, fx.dev.outsider, (s) => s`select id from invites`)).length,
      0,
    );
    // uncertified device of THIS tenant: zero rows
    assertEquals(
      (await asApi(fx.admin1, fx.dev.admin1raw, (s) => s`select id from invites`)).length,
      0,
    );
  },
});

Deno.test({
  name:
    "E-06-11 issuing an invite: tenant admin only, signed record required, window fixed at 7 days; a member, another tenant's admin and an uncertified device are all refused",
  ignore,
  async fn() {
    const id = await invite(fx.hmac.invitee);
    const [row] = await sql`select status, expires_at, created_at, source_record_id,
      (expires_at - created_at) as window from invites where id = ${id}`;
    assertEquals(row.status, "sent");
    assertEquals(String(row.window), "7 days");
    assert(row.source_record_id !== null, "the invite cites the admin's signed record");

    // no signed record → the projection rule bites (ADR 2026-09-05b §1)
    assertEquals(
      await pgCode(
        asApi(
          fx.admin1,
          fx.dev.admin1,
          (s) =>
            s`select rf.create_invite(${fx.t1}, ${fx.hmac.nobody}, '[]'::jsonb, ${
              bytes(16, 7)
            }, ${crypto.randomUUID()})`,
        ),
      ),
      "P0001",
    );
    // a record authored by SOMEONE ELSE's device is not this device's record
    const foreign = await record(fx.t1, fx.dev.admin2);
    assertEquals(
      await pgCode(
        asApi(
          fx.admin1,
          fx.dev.admin1,
          (s) =>
            s`select rf.create_invite(${fx.t1}, ${fx.hmac.nobody}, '[]'::jsonb, ${
              bytes(16, 7)
            }, ${foreign})`,
        ),
      ),
      "P0001",
    );
    // another tenant's certified admin cannot invite into t1
    const rec2 = await record(fx.t2, fx.dev.outsider);
    assertEquals(
      await pgCode(
        asApi(
          fx.outsider,
          fx.dev.outsider,
          (s) =>
            s`select rf.create_invite(${fx.t1}, ${fx.hmac.nobody}, '[]'::jsonb, ${
              bytes(16, 7)
            }, ${rec2})`,
        ),
      ),
      "42501",
    );
    // an uncertified device of this tenant's own admin cannot either
    const rec3 = await record(fx.t1, fx.dev.admin1raw);
    assertEquals(
      await pgCode(
        asApi(
          fx.admin1,
          fx.dev.admin1raw,
          (s) =>
            s`select rf.create_invite(${fx.t1}, ${fx.hmac.nobody}, '[]'::jsonb, ${
              bytes(16, 7)
            }, ${rec3})`,
        ),
      ),
      "42501",
    );
    // the window cannot be widened by writing the row directly either
    const rec4 = await record(fx.t1, fx.dev.admin1);
    assertEquals(
      await pgCode(
        sql`insert into invites (tenant_id, invitee_hmac, nonce, created_by, source_record_id, expires_at)
          values (${fx.t1}, ${fx.hmac.nobody}, ${
          bytes(16, 7)
        }, ${fx.admin1}, ${rec4}, now() + interval '90 days')`,
      ),
      "23514",
      "invites_window_7d binds the table owner too",
    );
    // …and a 16-byte ceremony nonce is the shape 06 §7 specifies
    assertEquals(
      await pgCode(
        sql`insert into invites (tenant_id, invitee_hmac, nonce, created_by, source_record_id)
          values (${fx.t1}, ${fx.hmac.nobody}, ${bytes(32, 7)}, ${fx.admin1}, ${rec4})`,
      ),
      "23514",
      "128-bit nonce",
    );
    await sql`update invites set status = 'revoked' where id = ${id}`;
  },
});

Deno.test({
  name:
    "E-06-12 the link alone admits nobody: acceptance matches the caller's OTP-verified number against invitee_hmac, and lands at joined_pending_verification — never at active (ADR 2026-09-05d §9, 06 §7)",
  ignore,
  async fn() {
    const id = await invite(fx.hmac.invitee, [{ book_id: fx.b1, role: "member" }]);

    // the invite id is a link, and a link is not an admission: a different certified user holding
    // it is refused, and told nothing about whom it was for
    const wrong = await pgErr(
      asApi(fx.stranger, fx.dev.stranger, (s) => s`select rf.accept_invite(${id})`),
    );
    assertEquals(wrong.code, "42501");
    assertStringIncludes(wrong.message, "phone_mismatch");
    assertEquals(
      (await sql`select count(*)::int as n from memberships where tenant_id = ${fx.t1} and user_id = ${fx.stranger}`)[
        0
      ]
        .n,
      0,
    );
    // another tenant's admin: same refusal
    assertEquals(
      await pgCode(asApi(fx.outsider, fx.dev.outsider, (s) => s`select rf.accept_invite(${id})`)),
      "42501",
    );
    // no claims at all: same refusal
    assertEquals(
      await pgCode(asApi(null, null, (s) => s`select rf.accept_invite(${id})`)),
      "42501",
    );

    // the invitee's own device finds it by its own number and nothing else
    const mine = await asApi(fx.invitee, fx.dev.invitee, (s) => s`select * from rf.my_invites()`);
    assertEquals(mine.map((r) => r.id), [id]);
    assertEquals(
      (await asApi(fx.stranger, fx.dev.stranger, (s) => s`select * from rf.my_invites()`)).length,
      0,
    );

    const [r] = await asApi(
      fx.invitee,
      fx.dev.invitee,
      (s) => s`select rf.accept_invite(${id}) as state`,
    );
    assertEquals(r.state, "joined_pending_verification", "join never short-circuits the ceremony");
    const [m] = await sql`select status, source_record_id, verified_at from memberships
      where tenant_id = ${fx.t1} and user_id = ${fx.invitee}`;
    assertEquals(m.status, "joined_pending_verification");
    assert(m.source_record_id !== null, "the row is a projection of the admin's record");
    assertEquals(m.verified_at, null);
    const [inv] = await sql`select status, accepted_by from invites where id = ${id}`;
    assertEquals(inv.status, "accepted");
    assertEquals(inv.accepted_by, fx.invitee);
    // an accepted invite is spent — replaying it changes nothing
    assertEquals(
      await pgCode(asApi(fx.invitee, fx.dev.invitee, (s) => s`select rf.accept_invite(${id})`)),
      "23514",
    );
  },
});

Deno.test({
  name:
    "E-06-13 the state machine is enforced by the database: invited → active, joined_pending → active without a ceremony, blocked → active and active → invited are all refused — for rf_api AND for the table owner (an edge function is a client)",
  ignore,
  async fn() {
    const bad = (t: string, u: string, s: string) =>
      pgErr(sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${u}, ${s})
        on conflict (tenant_id, user_id) do update set status = excluded.status`);

    // invitee is joined_pending_verification and has no verified ceremony yet
    const jump = await bad(fx.t1, fx.invitee, "active");
    assertEquals(jump.code, "23514");
    assertStringIncludes(jump.message, "ceremony_required");

    // a brand-new row cannot start at active either, once the tenant has a founder
    const fresh = await bad(fx.t1, fx.stranger, "active");
    assertEquals(fresh.code, "23514");
    assertStringIncludes(fresh.message, "ceremony_required");

    // nor at invited without a live invite naming that number
    const noInvite = await bad(fx.t1, fx.stranger, "invited");
    assertEquals(noInvite.code, "23514");
    assertStringIncludes(noInvite.message, "no_live_invite");

    // nor at blocked without a failed ceremony
    const noMismatch = await bad(fx.t1, fx.invitee, "blocked");
    assertEquals(noMismatch.code, "23514");
    assertStringIncludes(noMismatch.message, "mismatch_required");

    // active → invited is not an edge of 06 §7's graph
    const back = await pgErr(
      sql`update memberships set status = 'invited' where tenant_id = ${fx.t1} and user_id = ${fx.admin2}`,
    );
    assertEquals(back.code, "23514");
    assertStringIncludes(back.message, "membership_transition");

    // and rf_api holds no direct write on memberships at all — the only door is rf.project_*
    for (
      const q of [
        (s: postgres.TransactionSql) =>
          s`insert into memberships (tenant_id, user_id, status) values (${fx.t1}, ${fx.stranger}, 'active')`,
        (s: postgres.TransactionSql) => s`update memberships set status = 'active'`,
        (s: postgres.TransactionSql) => s`delete from memberships`,
      ]
    ) {
      assertEquals(await pgCode(asApi(fx.admin1, fx.dev.admin1, q)), "42501");
    }
    // …and rf.project_membership cannot be used to smuggle the jump through
    const rec = await record(fx.t1, fx.dev.admin1);
    const viaFn = await pgErr(
      asApi(
        fx.admin1,
        fx.dev.admin1,
        (s) => s`select rf.project_membership(${rec}, ${fx.t1}, ${fx.invitee}, 'active')`,
      ),
    );
    assertEquals(viaFn.code, "23514");
    assertStringIncludes(viaFn.message, "ceremony_required");
    assertEquals(
      (await sql`select status from memberships where tenant_id = ${fx.t1} and user_id = ${fx.invitee}`)[
        0
      ]
        .status,
      "joined_pending_verification",
    );
  },
});

Deno.test({
  name:
    "E-06-14 the ceremony is what flips the row: a verified event moves joined_pending → active and stamps the verifier; a mismatch blocks and raises a security event; a non-member, another tenant and an uncertified device cannot verify (ADR 2026-09-05d §7)",
  ignore,
  async fn() {
    // another tenant's certified admin: refused
    const rec2 = await record(fx.t2, fx.dev.outsider);
    assertEquals(
      await pgCode(
        asApi(
          fx.outsider,
          fx.dev.outsider,
          (s) =>
            s`select rf.project_verification_event(${rec2}, ${fx.t2}, ${fx.invitee}, ${fx.outsider}, 'qr_in_person', 'verified')`,
        ),
      ),
      "42501",
      "a ceremony verifies a member of THIS tenant — t1's people are not t2's to vouch for",
    );
    // an uncertified device of this tenant: refused
    const rec3 = await record(fx.t1, fx.dev.admin1raw);
    assertEquals(
      await pgCode(
        asApi(
          fx.admin1,
          fx.dev.admin1raw,
          (s) =>
            s`select rf.project_verification_event(${rec3}, ${fx.t1}, ${fx.invitee}, ${fx.admin1}, 'qr_in_person', 'verified')`,
        ),
      ),
      "42501",
    );
    // no signed record at all: refused
    assertEquals(
      await pgCode(
        asApi(
          fx.admin1,
          fx.dev.admin1,
          (s) =>
            s`select rf.project_verification_event(${crypto.randomUUID()}, ${fx.t1}, ${fx.invitee}, ${fx.admin1}, 'qr_in_person', 'verified')`,
        ),
      ),
      "P0001",
    );
    assertEquals(
      (await sql`select status from memberships where tenant_id = ${fx.t1} and user_id = ${fx.invitee}`)[
        0
      ]
        .status,
      "joined_pending_verification",
      "three refusals, no movement",
    );

    // an active member of the tenant verifies (04 §6.4: any active member may)
    const rec = await record(fx.t1, fx.dev.admin2, "verification_event");
    await asApi(
      fx.admin2,
      fx.dev.admin2,
      (s) =>
        s`select rf.project_verification_event(${rec}, ${fx.t1}, ${fx.invitee}, ${fx.admin2}, 'code_remote', 'verified')`,
    );
    const [m] = await sql`select status, verified_by, verified_method, verified_at
      from memberships where tenant_id = ${fx.t1} and user_id = ${fx.invitee}`;
    assertEquals(m.status, "active");
    assertEquals(m.verified_by, fx.admin2);
    assertEquals(m.verified_method, "code_remote");
    assert(m.verified_at !== null);

    // a mismatch on a pending member blocks them and lands a security event
    const id = await invite(fx.hmac.stranger);
    await asApi(fx.stranger, fx.dev.stranger, (s) => s`select rf.accept_invite(${id})`);
    const recX = await record(fx.t1, fx.dev.admin1, "verification_event");
    await asApi(
      fx.admin1,
      fx.dev.admin1,
      (s) =>
        s`select rf.project_verification_event(${recX}, ${fx.t1}, ${fx.stranger}, ${fx.admin1}, 'qr_in_person', 'mismatch')`,
    );
    assertEquals(
      (await sql`select status from memberships where tenant_id = ${fx.t1} and user_id = ${fx.stranger}`)[
        0
      ]
        .status,
      "blocked",
    );
    const ev =
      await sql`select kind from audit_events where tenant_id = ${fx.t1} and user_id = ${fx.stranger}`;
    assertEquals(ev.map((e) => e.kind), ["ceremony_mismatch"]);
  },
});

Deno.test({
  name:
    "E-06-15 expiry frees the seat: an invite past its 7-day window cannot be accepted, rf.expire_invites marks it expired and demotes the invited row to removed — and rf_api cannot run the sweep",
  ignore,
  async fn() {
    const id = await invite(fx.hmac.nobody);
    // an `invited` membership needs a live invite, so make one for a user who has an account
    const idU = await invite(fx.hmac.admin1); // admin1 is already active — use a fresh account instead
    await sql`update invites set status = 'revoked' where id = ${idU}`;
    const [late] = await sql`insert into users (phone_hmac, phone_ct) values (${bytes(32, 21)}, ${
      bytes(40, 21)
    }) returning id`;
    const idL = await invite(bytes(32, 21));
    await sql`insert into memberships (tenant_id, user_id, status) values (${fx.t1}, ${late.id}, 'invited')`;

    // back-date both windows: the guard fixes expires_at at issue, so only a superuser rewrite can
    // simulate the passage of seven days — and even that must go through the immutability check
    assertEquals(
      await pgCode(sql`update invites set expires_at = now() - interval '1 day' where id = ${id}`),
      "23514",
      "the window is fixed at issue (06 §7)",
    );
    await sql`alter table invites disable trigger invites_guard`;
    await sql`update invites set created_at = now() - interval '8 days',
      expires_at = now() - interval '1 day' where id in (${id}, ${idL})`;
    await sql`alter table invites enable trigger invites_guard`;

    // expired: acceptance refuses, and the row self-marks on the way out
    const exp = await pgErr(
      asApi(fx.admin1, fx.dev.admin1, (s) => s`select rf.accept_invite(${idL})`),
    );
    assertEquals(
      exp.code,
      "42501",
      "wrong number first — an expired invite still tells you nothing",
    );
    const [lateDev] = await sql`insert into devices (user_id, pub_ed, pub_x, status)
      values (${late.id}, ${bytes(32, 4)}, ${bytes(32, 5)}, 'certified') returning id`;
    const exp2 = await pgErr(
      asApi(late.id, lateDev.id, (s) => s`select rf.accept_invite(${idL})`),
    );
    assertEquals(exp2.code, "23514");
    assertStringIncludes(exp2.message, "invite_expired");

    // the sweep is a maintenance power, never an API one
    assertEquals(
      await pgCode(asApi(fx.admin1, fx.dev.admin1, (s) => s`select rf.expire_invites()`)),
      "42501",
    );
    await asMaint((s) => s`select rf.expire_invites()`);
    const rows = await sql`select id, status from invites where id in (${id}, ${idL})`;
    assertEquals(rows.every((r) => r.status === "expired"), true);
    assertEquals(
      (await sql`select status from memberships where tenant_id = ${fx.t1} and user_id = ${late.id}`)[
        0
      ]
        .status,
      "removed",
      "an expired invite frees the seat (06 §7 Seats)",
    );
  },
});

Deno.test({
  name:
    "E-06-16 re-invite is a new invite, not a revived one: issuing again supersedes the live invite, a blocked member cannot be waved back to active, and the whole surface stays read-only for rf_api",
  ignore,
  async fn() {
    const first = await invite(fx.hmac.nobody);
    const second = await invite(fx.hmac.nobody);
    assert(first !== second);
    const rows = await sql`select id, status from invites where id in (${first}, ${second})`;
    assertEquals(rows.find((r) => r.id === first)!.status, "revoked", "superseded");
    assertEquals(rows.find((r) => r.id === second)!.status, "sent");

    // a superseded invite is dead: not re-openable, not acceptable
    assertEquals(
      await pgCode(sql`update invites set status = 'sent' where id = ${first}`),
      "23514",
      "revoked is terminal",
    );

    // 06 §7: after a mismatch, "new invite required" — blocked reaches nothing but removed.
    // Build the blocked member here so this test stands on its own.
    const hmacB = bytes(32, 31);
    const [blocked] = await sql`insert into users (phone_hmac, phone_ct) values (${hmacB}, ${
      bytes(40, 31)
    }) returning id`;
    const [devB] = await sql`insert into devices (user_id, pub_ed, pub_x, status)
      values (${blocked.id}, ${bytes(32, 4)}, ${bytes(32, 5)}, 'certified') returning id`;
    const invB = await invite(hmacB);
    await asApi(blocked.id, devB.id, (s) => s`select rf.accept_invite(${invB})`);
    const recB = await record(fx.t1, fx.dev.admin1, "verification_event");
    await asApi(
      fx.admin1,
      fx.dev.admin1,
      (s) =>
        s`select rf.project_verification_event(${recB}, ${fx.t1}, ${blocked.id}, ${fx.admin1}, 'qr_in_person', 'mismatch')`,
    );
    assertEquals(
      (await sql`select status from memberships where tenant_id = ${fx.t1} and user_id = ${blocked.id}`)[
        0
      ]
        .status,
      "blocked",
    );

    for (const s of ["active", "joined_pending_verification", "invited"]) {
      const e = await pgErr(
        sql`update memberships set status = ${s} where tenant_id = ${fx.t1} and user_id = ${blocked.id}`,
      );
      assertEquals(e.code, "23514", `blocked → ${s}`);
      assertStringIncludes(e.message, "membership_transition");
    }
    await sql`update memberships set status = 'removed' where tenant_id = ${fx.t1} and user_id = ${blocked.id}`;
    // and even then, coming back needs a LIVE invite for that number
    const back = await pgErr(
      sql`update memberships set status = 'invited' where tenant_id = ${fx.t1} and user_id = ${blocked.id}`,
    );
    assertEquals(back.code, "23514");
    assertStringIncludes(back.message, "no_live_invite");
    await invite(hmacB);
    assertEquals(
      await pgCode(
        sql`update memberships set status = 'invited' where tenant_id = ${fx.t1} and user_id = ${blocked.id}`,
      ),
      "ok",
      "one-tap re-invite, through a fresh invite row",
    );

    // rf_api writes none of it directly, from either adversary's seat or the tenant's own
    for (
      const [u, d] of [
        [fx.admin1, fx.dev.admin1],
        [fx.outsider, fx.dev.outsider],
        [fx.admin1, fx.dev.admin1raw],
      ] as const
    ) {
      for (
        const q of [
          (s: postgres.TransactionSql) => s`update invites set status = 'accepted'`,
          (s: postgres.TransactionSql) => s`delete from invites`,
          (s: postgres.TransactionSql) => s`update book_roles set role = 'admin'`,
          (s: postgres.TransactionSql) => s`delete from book_roles`,
          (s: postgres.TransactionSql) =>
            s`insert into verification_events (tenant_id, subject_user, verifier_user, method, result)
              values (${fx.t1}, ${fx.invitee}, ${fx.admin1}, 'qr_in_person', 'verified')`,
          (s: postgres.TransactionSql) => s`update verification_events set result = 'verified'`,
          (s: postgres.TransactionSql) => s`delete from verification_events`,
        ]
      ) {
        assertEquals(await pgCode(asApi(u, d, q)), "42501");
      }
    }
    await sql.end();
  },
});
