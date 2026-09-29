// Hostile-query suite for the invite-nonce relay (ADR 2026-09-25b §1–§2 🔒, 04 §6.1 as amended,
// 06 §7 🔒, ADR 2026-09-05c §4). Ids E-25b-1 (the PgStore half) and E-25b-2.
//
// 0015 widens `rf.my_invites()` to the caller's own invites at `sent`, or accepted by the caller,
// within the invite's 7-day window, and hands back each row's `nonce`. The nonce is not secret
// (04 §6.1), but it is still nobody else's: the only door to it stays the SECURITY DEFINER
// function keyed on the caller's own OTP-verified number or on its own acceptance. rf_api keeps no
// SELECT on `invites.nonce`, so there is no lookup by nonce and no oracle on it.
//
// Adversaries, per CLAUDE.md: a second user, another tenant's (certified) admin, a co-admin of the
// inviting tenant, an uncertified stranger, a caller with no claims, and a recycled number.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";
import { PgStore } from "../../functions/_shared/store_pg.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — invite_nonce.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP invite_nonce.test.ts: ${why}`);
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
async function pgCode(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "ok";
  } catch (e) {
    return (e as { code?: string }).code ?? "unknown";
  }
}
const bytes = (n: number, fill: number) => new Uint8Array(n).fill(fill);
// Random, not fixed fills: every RLS file shares one database and users.phone_hmac is UNIQUE.
const rnd = (n: number) => crypto.getRandomValues(new Uint8Array(n));
const u8 = (v: unknown) => new Uint8Array(v as Uint8Array);

interface Fx {
  t1: string;
  t2: string;
  admin1: string;
  coAdmin: string;
  outsider: string;
  invitee: string;
  stranger: string;
  rawStranger: string;
  dev: Record<string, string>;
  hmac: Record<string, Uint8Array>;
}
let fx: Fx;

async function record(tenant: string, device: string, kind: string): Promise<string> {
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
  // 0019 (ADR 2026-09-05g §6): an API invite takes a seat. This suite pins the state machine, not
  // the cap (seat_book_caps.test.ts does), so both tenants sit on the catalogue's widest plan — read
  // from the catalogue, never a literal (desk PLAN-49).
  await sql`insert into subscriptions (tenant_id, plan)
    select v.t, (select c.id from plan_catalogue c order by (c.members = -1) desc, c.members desc limit 1)
    from (values (${t1.id}::uuid), (${t2.id}::uuid)) v(t)`;
  const hmac: Record<string, Uint8Array> = {};
  const mk = async (name: string) => {
    hmac[name] = rnd(32);
    const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${hmac[name]}, ${
      rnd(40)
    }) returning id`;
    return u.id as string;
  };
  const admin1 = await mk("admin1"),
    coAdmin = await mk("coAdmin"),
    outsider = await mk("outsider"),
    invitee = await mk("invitee"),
    stranger = await mk("stranger"),
    rawStranger = await mk("rawStranger");

  const dev: Record<string, string> = {};
  for (
    const [name, user, status] of [
      ["admin1", admin1, "certified"],
      ["coAdmin", coAdmin, "certified"],
      ["outsider", outsider, "certified"], // certified admin of ANOTHER tenant
      ["invitee", invitee, "certified"],
      ["stranger", stranger, "certified"], // a second user, in no tenant at all
      ["rawStranger", rawStranger, "registered"], // an uncertified stranger
    ] as const
  ) {
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${user}, ${rnd(32)}, ${rnd(32)}, ${status}) returning id`;
    dev[name] = d.id;
  }

  // founders first (06 §5), then the co-admin through a signed ceremony (0008).
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${admin1}, 'active'), (${t2.id}, ${outsider}, 'active')`;
  await sql`insert into verification_events (tenant_id, subject_user, verifier_user, method, result, source_record_id)
    values (${t1.id}, ${coAdmin}, ${admin1}, 'qr_in_person', 'verified', ${await record(
    t1.id,
    dev.admin1,
    "verification_event",
  )})`;
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${coAdmin}, 'active')`;
  const b1 = crypto.randomUUID(), b2 = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type) values (${b1}, ${t1.id}, 'family'), (${b2}, ${t2.id}, 'business')`;
  await sql`insert into book_roles (book_id, user_id, role) values
    (${b1}, ${admin1}, 'admin'), (${b1}, ${coAdmin}, 'admin'), (${b2}, ${outsider}, 'admin')`;

  return {
    t1: t1.id,
    t2: t2.id,
    admin1,
    coAdmin,
    outsider,
    invitee,
    stranger,
    rawStranger,
    dev,
    hmac,
  };
}

/** Issue an invite through the API path, as the inviting admin's device would: IT drew the nonce. */
async function invite(
  to: Uint8Array,
  nonce: Uint8Array,
  by: { tenant: string; user: string; device: string } = {
    tenant: fx.t1,
    user: fx.admin1,
    device: fx.dev.admin1,
  },
): Promise<string> {
  const rec = await record(by.tenant, by.device, "invite");
  const [r] = await asApi(
    by.user,
    by.device,
    (s) => s`select rf.create_invite(${by.tenant}, ${to}, '[]'::jsonb, ${nonce}, ${rec}) as id`,
  );
  return r.id as string;
}

/** An invite whose window has already closed — written as the table owner, which the 7-day CHECK
 *  still binds (expires_at ≤ created_at + 7 d), so this is a real row shape, not a forged one. */
async function agedInvite(to: Uint8Array, nonce: Uint8Array): Promise<string> {
  const rec = await record(fx.t1, fx.dev.admin1, "invite");
  const [r] = await sql`insert into invites
      (tenant_id, invitee_hmac, roles, nonce, created_by, source_record_id, created_at, expires_at)
    values (${fx.t1}, ${to}, '[]'::jsonb, ${nonce}, ${fx.admin1}, ${rec},
            now() - interval '8 days', now() - interval '1 day')
    returning id`;
  return r.id as string;
}

const mine = (user: string | null, device: string | null) =>
  asApi(user, device, (s) => s`select * from rf.my_invites()`);

Deno.test({
  name:
    "E-25b-2 setup: 0015 replaced rf.my_invites() — no arguments (no lookup by nonce), SECURITY DEFINER, returns nonce; rf_api may EXECUTE it, PUBLIC may not, and rf_api still holds no SELECT on invites.nonce",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    const [fn] = await sql`select p.pronargs, p.prosecdef,
        pg_get_function_result(p.oid) as result,
        has_function_privilege('rf_api', p.oid, 'execute') as api,
        has_function_privilege('public', p.oid, 'execute') as pub
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname = 'my_invites'`;
    assert(fn, "rf.my_invites exists");
    assertEquals(fn.pronargs, 0, "the function takes nothing a caller could look an invite up by");
    assertEquals(fn.prosecdef, true);
    assert(String(fn.result).includes("nonce bytea"), `result is ${fn.result}`);
    // each row says whether it is a live offer or the caller's own spent one (INV1 finding 1)
    assert(String(fn.result).includes("status text"), `result is ${fn.result}`);
    assertEquals(fn.api, true);
    assertEquals(fn.pub, false, "an ungranted role cannot reach the nonce");
    const [col] =
      await sql`select has_column_privilege('rf_api', 'invites', 'nonce', 'select') as n,
      has_column_privilege('rf_api', 'invites', 'invitee_hmac', 'select') as h`;
    assertEquals(col.n, false, "the nonce column stays outside rf_api's grant (0006)");
    assertEquals(col.h, false);
    // the envelope rule is not this migration's business, but a migration must not loosen it
    const [env] = await sql`select has_table_privilege('rf_api', 'envelopes', 'update') as u,
      has_table_privilege('rf_api', 'envelopes', 'delete') as d`;
    assertEquals([env.u, env.d], [false, false]);
    fx = await seed();
  },
});

Deno.test({
  name:
    "E-25b-2 the invitee's own live invite comes back with the nonce the inviter drew, byte for byte; a second user, another tenant's admin, a co-admin of the inviting tenant, an uncertified stranger and a caller with no claims get zero rows — and no caller at all can SELECT the nonce column or filter on it",
  ignore,
  async fn() {
    const drawn = rnd(16);
    const id = await invite(fx.hmac.invitee, drawn);

    const rows = await mine(fx.invitee, fx.dev.invitee);
    assertEquals(rows.map((r) => r.id), [id]);
    assertEquals(u8(rows[0].nonce), drawn, "relayed as drawn — the server never alters it");
    assertEquals(rows[0].tenant_id, fx.t1);

    for (
      const [who, user, device] of [
        ["second user", fx.stranger, fx.dev.stranger],
        ["another tenant's admin", fx.outsider, fx.dev.outsider],
        ["co-admin of the inviting tenant", fx.coAdmin, fx.dev.coAdmin],
        ["the inviting admin", fx.admin1, fx.dev.admin1],
        ["uncertified stranger", fx.rawStranger, fx.dev.rawStranger],
        ["no claims", null, null],
      ] as const
    ) {
      assertEquals((await mine(user, device)).length, 0, `${who} is offered nothing`);
    }

    // the column itself: refused for everyone on rf_api, the invitee included, and not usable as a
    // filter either (Postgres demands SELECT on every column a query references) — no oracle.
    for (
      const [user, device] of [
        [fx.invitee, fx.dev.invitee],
        [fx.coAdmin, fx.dev.coAdmin],
        [fx.stranger, fx.dev.stranger],
      ] as const
    ) {
      assertEquals(
        await pgCode(asApi(user, device, (s) => s`select nonce from invites where id = ${id}`)),
        "42501",
      );
      assertEquals(
        await pgCode(asApi(user, device, (s) => s`select id from invites where nonce = ${drawn}`)),
        "42501",
        "no lookup by nonce",
      );
    }
    await sql`update invites set status = 'revoked' where id = ${id}`;
  },
});

Deno.test({
  name:
    "E-25b-2 after acceptance the invite stays reachable by the user who accepted it, with its nonce, for the rest of its window — and by nobody else: not a second user, not another tenant's admin, not an uncertified stranger, not a caller with no claims",
  ignore,
  async fn() {
    const drawn = rnd(16);
    const id = await invite(fx.hmac.invitee, drawn);
    const [a] = await asApi(
      fx.invitee,
      fx.dev.invitee,
      (s) => s`select rf.accept_invite(${id}) as state`,
    );
    assertEquals(a.state, "joined_pending_verification");

    const rows = await mine(fx.invitee, fx.dev.invitee);
    assertEquals(rows.map((r) => r.id), [id], "S9.2 survives a restart: the accepted invite");
    assertEquals(u8(rows[0].nonce), drawn);

    for (
      const [who, user, device] of [
        ["second user", fx.stranger, fx.dev.stranger],
        ["another tenant's admin", fx.outsider, fx.dev.outsider],
        ["co-admin", fx.coAdmin, fx.dev.coAdmin],
        ["uncertified stranger", fx.rawStranger, fx.dev.rawStranger],
        ["no claims", null, null],
      ] as const
    ) {
      assertEquals((await mine(user, device)).length, 0, `${who} is offered nothing`);
    }
  },
});

Deno.test({
  name:
    "E-25b-2 an invite older than 7 days is not returned, sent or accepted; a revoked or expired invite is not returned inside its window either",
  ignore,
  async fn() {
    // a fresh invitee, so this test reads only its own rows
    const h = rnd(32);
    const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${h}, ${
      rnd(40)
    }) returning id`;
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${u.id}, ${rnd(32)}, ${rnd(32)}, 'certified') returning id`;
    const me = u.id as string, dev = d.id as string;

    // aged at `sent`
    await agedInvite(h, rnd(16));
    // aged and ACCEPTED by this very caller — the accepted branch is bounded by the window too
    const agedAccepted = await agedInvite(h, rnd(16));
    await sql`update invites set status = 'accepted', accepted_by = ${me},
      accepted_at = now() - interval '7 days' where id = ${agedAccepted}`;
    assertEquals((await mine(me, dev)).length, 0, "past the window: nothing, whatever its status");

    // inside the window but no longer live: superseded by a re-invite (06 §7 one-tap) → revoked
    const first = await invite(h, rnd(16));
    const second = await invite(h, rnd(16));
    const [s1] = await sql`select status from invites where id = ${first}`;
    assertEquals(s1.status, "revoked");
    assertEquals((await mine(me, dev)).map((r) => r.id), [second], "a revoked invite is gone");

    // expired by the sweep's rule (status flipped, window notionally open) is not returned either
    await sql`update invites set status = 'expired' where id = ${second}`;
    assertEquals((await mine(me, dev)).length, 0);
  },
});

Deno.test({
  name:
    "E-25b-2 an invite accepted by someone else is not returned: a recycled number (the accepter erased, a new user signing up on the same number) inherits neither the accepted invite nor its nonce, and the erased accepter reads nothing",
  ignore,
  async fn() {
    const h = rnd(32);
    const [a] = await sql`insert into users (phone_hmac, phone_ct) values (${h}, ${
      rnd(40)
    }) returning id`;
    const [ad] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${a.id}, ${rnd(32)}, ${rnd(32)}, 'certified') returning id`;
    const id = await invite(h, rnd(16));
    await asApi(a.id, ad.id, (s) => s`select rf.accept_invite(${id})`);
    assertEquals((await mine(a.id, ad.id)).map((r) => r.id), [id]);

    // erasure (03 §6) nulls the HMAC; the number is then free for someone else to sign up with
    await sql`update users set phone_hmac = null, erased_at = now() where id = ${a.id}`;
    const [b] = await sql`insert into users (phone_hmac, phone_ct) values (${h}, ${
      rnd(40)
    }) returning id`;
    const [bd] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${b.id}, ${rnd(32)}, ${rnd(32)}, 'certified') returning id`;

    assertEquals(
      (await mine(b.id, bd.id)).length,
      0,
      "addressed to this number, but accepted by another user: not this caller's",
    );
    assertEquals((await mine(a.id, ad.id)).length, 0, "an erased user reads nothing");
  },
});

Deno.test({
  name:
    "E-25b-1 PgStore carries the nonce: myInvites() rows hold the stored 16 bytes, acceptInvite() returns {status, nonce} with the same bytes, and the accepted invite is still in myInvites() afterwards",
  ignore,
  async fn() {
    const h = rnd(32);
    const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${h}, ${
      rnd(40)
    }) returning id`;
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${u.id}, ${rnd(32)}, ${rnd(32)}, 'certified') returning id`;
    const drawn = rnd(16);
    const id = await invite(h, drawn);

    const store = new PgStore(url!);
    try {
      const claims = { user_id: u.id as string, device_id: d.id as string };
      const before = await store.withClaims(claims, (tx) => tx.myInvites());
      assertEquals(before.map((i) => i.invite_id), [id]);
      assertEquals(before[0].status, "sent");
      assert(before[0].nonce instanceof Uint8Array);
      assertEquals(u8(before[0].nonce), drawn);

      const accepted = await store.withClaims(claims, (tx) => tx.acceptInvite(id));
      assertEquals(accepted.status, "joined_pending_verification");
      assertEquals(u8(accepted.nonce), drawn);

      const after = await store.withClaims(claims, (tx) => tx.myInvites());
      assertEquals(after.map((i) => i.invite_id), [id]);
      assertEquals(after[0].status, "accepted", "spent, and says so");
      assertEquals(u8(after[0].nonce), drawn);

      // and through the store, a stranger still reads nothing
      const other = await store.withClaims(
        { user_id: fx.stranger, device_id: fx.dev.stranger },
        (tx) => tx.myInvites(),
      );
      assertEquals(other.length, 0);
    } finally {
      await store.end();
    }
  },
});

Deno.test({
  name:
    "E-25b-1 PgStore tells a live offer from a spent one and lists it first: after accepting tenant A's (older) invite, a live invite from tenant B comes back ahead of A, B at status sent and A at status accepted, each with its own nonce — and the first row accepts",
  ignore,
  async fn() {
    const h = rnd(32);
    const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${h}, ${
      rnd(40)
    }) returning id`;
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${u.id}, ${rnd(32)}, ${rnd(32)}, 'certified') returning id`;
    const me = u.id as string, dev = d.id as string;

    // A first: the older row, whose window closes first — expires_at order alone puts it ahead
    const nA = rnd(16), nB = rnd(16);
    const a = await invite(h, nA);
    await asApi(me, dev, (s) => s`select rf.accept_invite(${a})`);
    const b = await invite(h, nB, { tenant: fx.t2, user: fx.outsider, device: fx.dev.outsider });

    const raw = await mine(me, dev);
    assertEquals(raw.map((r) => [r.id, r.status]), [[b, "sent"], [a, "accepted"]]);

    const store = new PgStore(url!);
    try {
      const claims = { user_id: me, device_id: dev };
      const list = await store.withClaims(claims, (tx) => tx.myInvites());
      assertEquals(list.map((i) => [i.invite_id, i.status]), [[b, "sent"], [a, "accepted"]]);
      assertEquals(u8(list[0].nonce), nB);
      assertEquals(u8(list[1].nonce), nA);

      const took = await store.withClaims(claims, (tx) => tx.acceptInvite(list[0].invite_id));
      assertEquals(took.status, "joined_pending_verification");
      assertEquals(u8(took.nonce), nB);

      const spent = await store.withClaims(claims, (tx) => tx.myInvites());
      assertEquals(spent.map((i) => i.status), ["accepted", "accepted"]);
    } finally {
      await store.end();
    }
  },
});

Deno.test({
  name: "E-25b-2 teardown",
  ignore,
  async fn() {
    await sql.end();
  },
});
