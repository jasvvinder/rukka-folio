// Hostile-query suite for ADR 2026-10-03c §3 (desk 37): a revoked device cannot read or accept its
// user's invites. Ids E-03c-1 (rf.my_invites) and E-03c-2 (rf.accept_invite).
//
// Before 0028 both functions keyed on the USER claim alone, so an unexpired access token on a
// revoked phone could still list its user's offers and their nonces, and accept one. The nonce is
// not secret (04 §6.1), but a revoked device must not act for its user. 0028 gates both on
// rf.device_live_for(rf.device_id(), rf.user_id()) — the predicate the rung-2 open (0010) and
// rf.has_guardian_set (0025) use — and refuses with THEIR named refusal: 42501
// `unknown_candidate_device`, raised before any invite is looked at, so the refusal is identical
// whether or not the user has an invite, and whether or not the id names one.
//
// Live = rf.device_live_for (0010): `status <> 'revoked' and revoked_at is null`. Each half is
// tested on its own (a `revoked` status with no timestamp, a timestamp on a `certified` row), and a
// device that is not the caller user's is not live for that user. A SUSPENDED device is live under
// that predicate, so it is answered and may accept — 0025 (c) kept the same reading for
// rf.has_guardian_set. ⚠️ SPEC: ADR 2026-10-03c §3 names rf.device_live_for and does not mention
// suspended; the conservative-but-faithful reading builds exactly the named predicate rather than
// invent a stricter one (rf.recovery_shares, 0020, is the one read that adds `status <>
// 'suspended'`, and it releases vault keys). Owner to confirm — lane report M13-INV37 `open`.
//
// Test honesty: every refusal is asserted by code AND name — never by "zero rows" — and every
// refused case has a live twin on the same invite that IS answered, so removing the gate fails the
// suite rather than leaving it green.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
import { assert, assertEquals, assertRejects } from "@std/assert";
import postgres from "postgres";
import { StoreDenied } from "../../functions/_shared/store.ts";
import { apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — invites_live_device.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP invites_live_device.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;

/** The one refusal both functions give a caller whose device is not live — 0025's, verbatim. */
const REFUSED = "42501 unknown_candidate_device";

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
/** `ok`, or the error's code and message — the whole refusal a caller sees. */
async function outcome(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "ok";
  } catch (e) {
    const err = e as { code?: string; message?: string };
    return `${err.code ?? "unknown"} ${err.message ?? ""}`;
  }
}
// Random, not fixed fills: every RLS file shares one database and users.phone_hmac is UNIQUE.
const rnd = (n: number) => crypto.getRandomValues(new Uint8Array(n));
const u8 = (v: unknown) => new Uint8Array(v as Uint8Array);

interface Fx {
  t1: string;
  admin: string;
  adminDev: string;
}
let fx: Fx;

async function record(tenant: string, device: string, kind: string): Promise<string> {
  const id = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${id}, 1, ${tenant}, ${kind}, '{}'::jsonb, ${rnd(8)}, ${device}, ${rnd(64)}, 1)`;
  return id;
}

async function seed(): Promise<Fx> {
  const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
  // 0019: an API invite takes a seat. The cap is seat_book_caps.test.ts's business; this tenant
  // sits on the catalogue's widest plan, read from the catalogue, never a literal (desk PLAN-49).
  await sql`insert into subscriptions (tenant_id, plan)
    values (${t1.id}, (select c.id from plan_catalogue c
                       order by (c.members = -1) desc, c.members desc limit 1))`;
  const [admin] = await sql`insert into users (phone_hmac, phone_ct) values (${rnd(32)}, ${
    rnd(40)
  }) returning id`;
  const [ad] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${admin.id}, ${rnd(32)}, ${rnd(32)}, 'certified') returning id`;
  await sql`insert into memberships (tenant_id, user_id, status) values (${t1.id}, ${admin.id}, 'active')`;
  const book = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type) values (${book}, ${t1.id}, 'family')`;
  await sql`insert into book_roles (book_id, user_id, role) values (${book}, ${admin.id}, 'admin')`;
  return { t1: t1.id, admin: admin.id, adminDev: ad.id };
}

/** A joining user with an OTP-verified number and NO device yet. */
async function joiner(): Promise<{ id: string; hmac: Uint8Array }> {
  const hmac = rnd(32);
  const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${hmac}, ${
    rnd(40)
  }) returning id`;
  return { id: u.id as string, hmac };
}

/** One device of `user`. `revokedAt` sets `revoked_at` independently of `status`, so each half of
 *  rf.device_live_for's predicate can be tested on its own. */
async function device(user: string, status: string, revokedAt = false): Promise<string> {
  const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status, revoked_at)
    values (gen_random_uuid(), ${user}, ${rnd(32)}, ${rnd(32)}, ${status},
            ${revokedAt ? new Date() : null}) returning id`;
  return d.id as string;
}

/** The inviting admin's device issues the invite through the API path (it drew the nonce). */
async function invite(to: Uint8Array, nonce = rnd(16)): Promise<string> {
  const rec = await record(fx.t1, fx.adminDev, "invite");
  const [r] = await asApi(
    fx.admin,
    fx.adminDev,
    (s) => s`select rf.create_invite(${fx.t1}, ${to}, '[]'::jsonb, ${nonce}, ${rec}) as id`,
  );
  return r.id as string;
}

const mine = (user: string | null, device: string | null) =>
  asApi(user, device, (s) => s`select * from rf.my_invites()`);
const accept = (user: string | null, device: string | null, id: string) =>
  asApi(user, device, (s) => s`select rf.accept_invite(${id}::uuid) as state`);

async function inviteRow(id: string) {
  const [r] = await sql`select status, accepted_by, accepted_at from invites where id = ${id}`;
  return { status: r.status, accepted_by: r.accepted_by, accepted_at: r.accepted_at };
}
async function membershipOf(user: string): Promise<string | null> {
  const [m] =
    await sql`select status from memberships where tenant_id = ${fx.t1} and user_id = ${user}`;
  return (m?.status as string | undefined) ?? null;
}

Deno.test({
  name:
    "E-03c-1 setup: 0028 keeps both functions' shape — my_invites takes nothing and returns status + nonce, accept_invite takes one uuid; SECURITY DEFINER, search_path pinned `public, pg_temp` (0024), EXECUTE for rf_api and not PUBLIC; envelopes still have no UPDATE/DELETE grant",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    const rows = await sql`select p.proname, pg_get_function_identity_arguments(p.oid) as args,
        pg_get_function_result(p.oid) as result, p.prosecdef, p.proconfig,
        has_function_privilege('rf_api', p.oid, 'execute') as api,
        has_function_privilege('public', p.oid, 'execute') as pub
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname in ('my_invites', 'accept_invite')
      order by p.proname`;
    assertEquals(rows.map((r) => r.proname), ["accept_invite", "my_invites"], "one of each");
    const [acc, my] = rows;
    assertEquals(acc.args, "p_invite uuid");
    assertEquals(acc.result, "text");
    assertEquals(my.args, "", "no argument — nothing to look an invite up by (ADR 2026-09-25b §2)");
    assertEquals(
      my.result,
      "TABLE(id uuid, tenant_id uuid, roles jsonb, expires_at timestamp with time zone, created_by uuid, status text, nonce bytea)",
    );
    for (const f of rows) {
      assertEquals(f.prosecdef, true, `${f.proname} is SECURITY DEFINER`);
      assertEquals(f.proconfig, ["search_path=public, pg_temp"], `${f.proname}: 0024's pin`);
      assertEquals(f.api, true, `rf_api may EXECUTE ${f.proname}`);
      assertEquals(f.pub, false, `PUBLIC may not EXECUTE ${f.proname}`);
    }
    const [env] = await sql`select has_table_privilege('rf_api', 'envelopes', 'update') as u,
      has_table_privilege('rf_api', 'envelopes', 'delete') as d`;
    assertEquals([env.u, env.d], [false, false], "CLAUDE.md rule 2");
    fx = await seed();
  },
});

Deno.test({
  name:
    "E-03c-1 rf.my_invites REFUSES a caller whose device is not live — revoked (status and timestamp), status `revoked` alone, `revoked_at` alone, another user's device, no device claim, no claims — with ONE refusal, 42501 unknown_candidate_device, identical whether or not the user has an invite; the same user's live certified, fresh (registered) and suspended devices are answered with the offer",
  ignore,
  async fn() {
    const j = await joiner();
    const id = await invite(j.hmac);
    const live = await device(j.id, "certified");
    const fresh = await device(j.id, "registered");
    const suspended = await device(j.id, "suspended");
    const revoked = await device(j.id, "revoked", true);
    const statusOnly = await device(j.id, "revoked");
    const stampOnly = await device(j.id, "certified", true);
    const other = await joiner();
    const foreign = await device(other.id, "certified");
    // a user with NO invite, on a revoked device: the refusal must not differ (no oracle)
    const empty = await joiner();
    const emptyRevoked = await device(empty.id, "revoked", true);

    // the live twins: the gate lets the user's own live devices through, offer intact
    for (const [who, dev] of [["certified", live], ["registered", fresh]] as const) {
      const rows = await mine(j.id, dev);
      assertEquals(rows.map((r) => [r.id, r.status]), [[id, "sent"]], `${who} device: answered`);
      assertEquals(u8(rows[0].nonce).length, 16);
    }
    // ⚠️ SPEC (header): rf.device_live_for counts suspended as live, so it is answered (0025 (c)).
    assertEquals((await mine(j.id, suspended)).map((r) => r.id), [id], "suspended: answered");

    for (
      const [who, user, dev] of [
        ["revoked (status + revoked_at)", j.id, revoked],
        ["status `revoked`, no revoked_at", j.id, statusOnly],
        ["revoked_at on a `certified` row", j.id, stampOnly],
        ["another user's live device", j.id, foreign],
        ["no device claim", j.id, null],
        ["no claims", null, null],
        ["revoked device of a user with no invite", empty.id, emptyRevoked],
      ] as const
    ) {
      assertEquals(await outcome(mine(user, dev)), REFUSED, `${who}: refused, never zero rows`);
    }

    // The case desk 37 names: a device that WAS live and read its offers is revoked; its still
    // unexpired token now reads nothing — refused — while the user's other device is unaffected.
    const later = await device(j.id, "certified");
    assertEquals((await mine(j.id, later)).map((r) => r.id), [id], "live: answered");
    await sql`update devices set status = 'revoked', revoked_at = now() where id = ${later}`;
    assertEquals(await outcome(mine(j.id, later)), REFUSED, "revoked after the read: refused");
    assertEquals((await mine(j.id, live)).map((r) => r.id), [id], "the live device still reads");
  },
});

Deno.test({
  name:
    "E-03c-1 an ACCEPTED invite's nonce (the S9.2 read, 0015 (b)) is refused to the accepter's revoked device by the same name, while its live device still reads the spent row; through the real PgStore on rf_api, myInvites() rejects StoreDenied('unknown_candidate_device') for the revoked device and answers the live one",
  ignore,
  async fn() {
    const j = await joiner();
    const nonce = rnd(16);
    const id = await invite(j.hmac, nonce);
    const live = await device(j.id, "certified");
    const revoked = await device(j.id, "revoked", true);
    assertEquals((await accept(j.id, live, id))[0].state, "joined_pending_verification");

    const spent = await mine(j.id, live);
    assertEquals(spent.map((r) => [r.id, r.status]), [[id, "accepted"]]);
    assertEquals(u8(spent[0].nonce), nonce);
    assertEquals(await outcome(mine(j.id, revoked)), REFUSED, "the nonce is not the revoked's");

    const store = await apiStore(url!);
    try {
      const err = await assertRejects(
        () => store.withClaims({ user_id: j.id, device_id: revoked }, (tx) => tx.myInvites()),
        StoreDenied,
      );
      assertEquals(err.reason, "unknown_candidate_device", "PgStore passes the name through");
      const rows = await store.withClaims(
        { user_id: j.id, device_id: live },
        (tx) => tx.myInvites(),
      );
      assertEquals(rows.map((r) => [r.invite_id, r.status]), [[id, "accepted"]]);
    } finally {
      await store.end();
    }
  },
});

Deno.test({
  name:
    "E-03c-2 rf.accept_invite REFUSES a revoked device (and status-only, timestamp-only, another user's device) with 42501 unknown_candidate_device and changes NOTHING — the invite stays `sent`, unaccepted, no membership — then the same user's live device accepts that very invite; a refused caller cannot tell a real invite id from an unknown one",
  ignore,
  async fn() {
    const j = await joiner();
    const id = await invite(j.hmac);
    const live = await device(j.id, "certified");
    const revoked = await device(j.id, "revoked", true);
    const statusOnly = await device(j.id, "revoked");
    const stampOnly = await device(j.id, "certified", true);
    const foreign = await device((await joiner()).id, "certified");
    const before = await inviteRow(id);
    assertEquals(before, { status: "sent", accepted_by: null, accepted_at: null });

    for (
      const [who, dev] of [
        ["revoked (status + revoked_at)", revoked],
        ["status `revoked`, no revoked_at", statusOnly],
        ["revoked_at on a `certified` row", stampOnly],
        ["another user's live device", foreign],
      ] as const
    ) {
      assertEquals(await outcome(accept(j.id, dev, id)), REFUSED, `${who}: refused`);
      assertEquals(await inviteRow(id), before, `${who}: the invite is untouched`);
      assertEquals(await membershipOf(j.id), null, `${who}: no membership`);
    }
    // raised before the invite is looked up: an unknown id draws the same refusal, not
    // unknown_invite — a revoked device learns nothing about which invites exist
    assertEquals(await outcome(accept(j.id, revoked, crypto.randomUUID())), REFUSED);
    // the claim-less precedent of 0006 is unchanged (no_claims comes first)
    assertEquals(await outcome(accept(j.id, null, id)), "42501 no_claims");
    // 0027's membership_facts log: a refused accept left no membership fact for this user
    const [{ n: facts }] = await sql`select count(*)::int as n from membership_facts
      where tenant_id = ${fx.t1} and user_id = ${j.id}`;
    assertEquals(facts, 0, "no membership fact logged by a refused accept");

    // the live twin: the very same invite is still acceptable, by the live device
    assertEquals((await accept(j.id, live, id))[0].state, "joined_pending_verification");
    const after = await inviteRow(id);
    assertEquals([after.status, after.accepted_by], ["accepted", j.id]);
    assertEquals(await membershipOf(j.id), "joined_pending_verification");
  },
});

Deno.test({
  name:
    "E-03c-2 a device revoked AFTER it read the offer cannot accept it on its still-valid token (refused, invite untouched), a SUSPENDED device accepts (rf.device_live_for counts it live — ⚠️ SPEC, owner to confirm), and through PgStore on rf_api acceptInvite() rejects StoreDenied('unknown_candidate_device') without spending the invite",
  ignore,
  async fn() {
    // revoked between read and accept — desk 37's token-on-a-revoked-phone case
    const a = await joiner();
    const idA = await invite(a.hmac);
    const phone = await device(a.id, "certified");
    assertEquals((await mine(a.id, phone)).map((r) => r.id), [idA]);
    await sql`update devices set status = 'revoked', revoked_at = now() where id = ${phone}`;
    assertEquals(await outcome(accept(a.id, phone, idA)), REFUSED);
    assertEquals(await inviteRow(idA), { status: "sent", accepted_by: null, accepted_at: null });

    // PgStore arm — the edge's own call path, rf_api login
    const store = await apiStore(url!);
    try {
      const err = await assertRejects(
        () => store.withClaims({ user_id: a.id, device_id: phone }, (tx) => tx.acceptInvite(idA)),
        StoreDenied,
      );
      assertEquals(err.reason, "unknown_candidate_device");
      assertEquals((await inviteRow(idA)).status, "sent", "not spent by the refused call");
      const fresh = await device(a.id, "registered");
      const took = await store.withClaims(
        { user_id: a.id, device_id: fresh },
        (tx) => tx.acceptInvite(idA),
      );
      assertEquals(took.status, "joined_pending_verification", "a live (fresh) device accepts");
      assertEquals(took.nonce.length, 16);
    } finally {
      await store.end();
    }

    // ⚠️ SPEC (header): suspended is live under rf.device_live_for, so it may accept.
    const b = await joiner();
    const idB = await invite(b.hmac);
    const susp = await device(b.id, "suspended");
    assertEquals((await accept(b.id, susp, idB))[0].state, "joined_pending_verification");
    assert((await inviteRow(idB)).accepted_by === b.id);
  },
});

Deno.test({
  name: "E-03c-2 teardown",
  ignore,
  async fn() {
    await sql.end();
  },
});
