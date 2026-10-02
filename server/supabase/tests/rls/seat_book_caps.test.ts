// Hostile-query suite for the hard seat cap and the hard business-book cap — migration 0019,
// against ADR 2026-09-05g §2 🔒 (hard caps at the plaintext choke points: invite creation = seats,
// book creation = business books) and §6 🔒 (seats count invited + joined_pending_verification +
// active; removal frees the seat at once; the same user_id re-invited within 30 days takes no new
// seat; a rolling cap of 2 × seats distinct members per year; downgrade deletes nothing and excess
// members keep read access), 08 §3 🔒, 06 §7 Seats, and 03 §2.4's plan_catalogue (0018).
//
// What an attacker — or an over-eager family — wants, and what each test denies:
//
//   * ONE MORE SEAT than the plan holds — through rf.create_invite, a direct insert into invites, a
//     membership_status record walking someone back to joined_pending, or two admins racing at the
//     last seat (E-05g-2, -3, -5, -13).
//   * SEAT ROTATION — cycling people through a small plan by removing and re-inviting (E-05g-6, -7).
//   * ONE MORE BOOK than the plan holds, including by archiving and re-creating (E-05g-9).
//   * AN ORACLE — a stranger learning another tenant's plan or head-count from a cap refusal, the
//     plan resolver or the rotation ledger (E-05g-11).
//   * A BYPASS — a claims-less rf_api write, or writing the ledger to buy back budget (E-05g-11).
//   * A LOSS — a downgrade that deletes, hides or strands anyone (E-05g-10).
//
// Every number comes from a catalogue row (test-only rows below, or the column read at run time),
// never from the seed (desk PLAN-49: the seeded numbers are placeholders). The fixtures that fill
// seats are written by the schema owner WITHOUT claims, which 0019 does not cap (a fixture is not an
// API write — see 0019 §2); every write under test goes through rf_api with claims.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-05g-1 … E-05g-13, E-05g-15 and E-05g-16's database half (E-05g-11, -12 and -15 also cover
// the repairs migration 0021 makes); E-05g-14 and E-05g-16's MemStore half are
// functions/_tests/seat_caps_route.test.ts. E-05g-16 here runs only because PgTx.guarded() binds
// each refused write to its own savepoint (M13-CAPR-PG; tests/rls/guarded_savepoint.test.ts).
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import postgres from "postgres";
import { StoreDenied } from "../../functions/_shared/store.ts";
import { PgStore } from "../../functions/_shared/store_pg.ts";
import { handler as meta } from "../../functions/sync-meta/index.ts";
import {
  body,
  edKeypair,
  type Member,
  post,
  reissue,
  rig,
  signedRecord,
} from "../../functions/_tests/harness.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — seat_book_caps.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP seat_book_caps.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

async function asRole<T>(
  role: "rf_api" | "rf_maintenance",
  user: string | null,
  device: string | null,
  fn: (s: postgres.TransactionSql) => Promise<T>,
): Promise<T> {
  return await sql.begin(async (s) => {
    await s.unsafe(`set local role ${role}`);
    if (role === "rf_api") await s`select rf.set_claims(${user}::uuid, ${device}::uuid)`;
    return await fn(s);
  }) as T;
}
const asApi = <T>(
  u: string | null,
  d: string | null,
  fn: (s: postgres.TransactionSql) => Promise<T>,
) => asRole("rf_api", u, d, fn);

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
/** A cap refusal: named (P0001 + the bare reason, the shape denialFromPg passes through), never a
 *  generic RLS / privilege denial. */
function assertCap(e: PgErr, reason: "seat_cap" | "seat_rotation_cap" | "book_cap", why: string) {
  assertEquals([e.code, e.message], ["P0001", reason], why);
}
const OK: PgErr = { code: "ok", message: "" };

// ---------------------------------------------------------------- test-only catalogue rows
// Plans shaped for the rules under test; removed by the teardown test at the end of the file.
const PLAN = {
  five: "zz_cap_five", //  5 seats (ADR 05g §6's own example), 2 business books
  two: "zz_cap_two", //    2 seats → rotation budget 4, no business book
  none: "zz_cap_none", //  -1 everywhere: no cap
  data: "zz_cap_data", //  the row E-05g-12 edits; its `devices` (7) is NOT the Free floor's
} as const;
async function ensurePlans() {
  await sql`insert into plan_catalogue (id, entity_type, name, sort_order, members, business_books,
      devices, envelopes_per_book, tenant_bytes, attachment_bytes, features, price_yearly_paise,
      price_monthly_paise)
    values (${PLAN.five}, 'family', 'Cap five', 90,  5,  2,  5, 1000, 1000, 1000, '{}', 0, 0),
           (${PLAN.two},  'family', 'Cap two',  91,  2,  0,  5, 1000, 1000, 1000, '{}', 0, 0),
           (${PLAN.none}, 'family', 'Cap none', 92, -1, -1, -1, 1000, 1000, 1000, '{}', 0, 0),
           (${PLAN.data}, 'family', 'Cap data', 93,  2,  1,  7, 1000, 1000, 1000, '{}', 0, 0)
    on conflict (id) do nothing`;
}

/** One test: its own connection pool, the plans present, the pool closed whatever happens.
 *  `blockedBy` names a defect OUTSIDE this lane's directories that makes the test fail for a reason
 *  that is not the behaviour under test; the test is the specification and is switched on when the
 *  defect is fixed (reported in the lane's `open`), never rewritten to pass around it. */
function test(name: string, fn: () => Promise<void>, blockedBy?: string) {
  if (blockedBy && url) console.log(`IGNORED ${name.slice(0, 9)}: blocked by ${blockedBy}`);
  Deno.test({
    name,
    ignore: ignore || !!blockedBy,
    async fn() {
      sql = postgres(url!, { max: 4, onnotice: () => {} });
      try {
        await ensurePlans();
        await fn();
      } finally {
        await sql.end();
      }
    },
  });
}

// ---------------------------------------------------------------- fixtures (schema owner, no claims)
interface P {
  user: string;
  dev: string;
  hmac: Uint8Array;
}
async function mkPerson(status = "certified"): Promise<P> {
  const hmac = rand(32);
  const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${hmac}, ${rand(40)})
    returning id`;
  const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${u.id}, ${rand(32)}, ${rand(32)}, ${status}) returning id`;
  return { user: u.id as string, dev: d.id as string, hmac };
}
async function record(tenant: string, device: string, kind: string): Promise<string> {
  const id = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${id}, 1, ${tenant}, ${kind}, '{}'::jsonb, ${rand(8)}, ${device}, ${rand(64)}, 1)`;
  return id;
}
interface Tn {
  t: string;
  admin: P;
  personal: string;
}
/** A tenant on `plan` (null = no subscription row = the Free floor, 0018 / desk PLAN-48), with its
 *  founder active and admin of the founder's PERSONAL book — so the fixture itself spends no
 *  business book. */
async function tenant(plan: string | null, founder?: P): Promise<Tn> {
  const [row] = await sql`insert into tenants (type) values ('family') returning id`;
  const t = row.id as string;
  if (plan) await sql`insert into subscriptions (tenant_id, plan) values (${t}, ${plan})`;
  const admin = founder ?? await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status) values (${t}, ${admin.user}, 'active')`;
  const personal = crypto.randomUUID();
  await sql`insert into books (id, tenant_id, type, owner_user_id)
    values (${personal}, ${t}, 'personal', ${admin.user})`;
  await sql`insert into book_roles (book_id, user_id, role) values (${personal}, ${admin.user}, 'admin')`;
  return { t, admin, personal };
}
/** An ACTIVE member placed by the owner after a signed ceremony (0006/0008's guards). */
async function activeMember(tn: Tn, admin = false): Promise<P> {
  const p = await mkPerson();
  const rec = await record(tn.t, tn.admin.dev, "verification_event");
  await sql`insert into verification_events
    (tenant_id, subject_user, verifier_user, method, result, source_record_id)
    values (${tn.t}, ${p.user}, ${tn.admin.user}, 'qr_in_person', 'verified', ${rec})`;
  await sql`insert into memberships (tenant_id, user_id, status) values (${tn.t}, ${p.user}, 'active')`;
  if (admin) {
    await sql`insert into book_roles (book_id, user_id, role) values (${tn.personal}, ${p.user}, 'admin')`;
  }
  return p;
}

// ---------------------------------------------------------------- API writes (rf_api, with claims)
async function invite(tn: Tn, to: Uint8Array, by: P = tn.admin): Promise<string> {
  const rec = await record(tn.t, by.dev, "invite");
  const [r] = await asApi(
    by.user,
    by.dev,
    (s) => s`select rf.create_invite(${tn.t}, ${to}, '[]'::jsonb, ${rand(16)}, ${rec}) as id`,
  );
  return r.id as string;
}
const tryInvite = (tn: Tn, to: Uint8Array, by?: P) => pgErr(invite(tn, to, by));
async function project(tn: Tn, user: string, status: string, by: P = tn.admin): Promise<void> {
  const rec = await record(tn.t, by.dev, "membership_status");
  await asApi(
    by.user,
    by.dev,
    (s) => s`select rf.project_membership(${rec}, ${tn.t}, ${user}, ${status})`,
  );
}
async function accept(p: P, inviteId: string): Promise<void> {
  await asApi(p.user, p.dev, (s) => s`select rf.accept_invite(${inviteId}::uuid)`);
}
async function verify(tn: Tn, subject: P, by: P = tn.admin): Promise<void> {
  const rec = await record(tn.t, by.dev, "verification_event");
  await asApi(
    by.user,
    by.dev,
    (s) =>
      s`select rf.project_verification_event(${rec}, ${tn.t}, ${subject.user}, ${by.user},
          'qr_in_person', 'verified')`,
  );
}
async function mkBook(tn: Tn, by: P, type = "business"): Promise<string> {
  const id = crypto.randomUUID();
  const owner = type === "personal" ? by.user : null;
  await asApi(
    by.user,
    by.dev,
    (s) =>
      s`insert into books (id, tenant_id, type, owner_user_id)
        values (${id}, ${tn.t}, ${type}, ${owner})`,
  );
  return id;
}
const tryBook = (tn: Tn, by: P, type = "business") => pgErr(mkBook(tn, by, type));

// ---------------------------------------------------------------- owner-side reads and edits
const revoke = (id: string) => sql`update invites set status = 'revoked' where id = ${id}`;
async function holders(t: string): Promise<number> {
  const [r] = await sql`select rf.seat_holders(${t}, null, null) as n`;
  return r.n as number;
}
async function grants(t: string): Promise<number> {
  const [r] = await sql`select count(*)::int as n from seat_grants where tenant_id = ${t}`;
  return r.n as number;
}
async function liveInvites(t: string): Promise<number> {
  const [r] = await sql`select count(*)::int as n from invites
    where tenant_id = ${t} and status = 'sent'`;
  return r.n as number;
}
async function bookCount(t: string): Promise<number> {
  const [r] = await sql`select count(*)::int as n from books where tenant_id = ${t}`;
  return r.n as number;
}
async function statusOf(t: string, user: string): Promise<string | null> {
  const [r] =
    await sql`select status from memberships where tenant_id = ${t} and user_id = ${user}`;
  return (r?.status as string) ?? null;
}
/** Invite fresh people, revoking each, until `n` counted grants exist. Returns them. */
async function spendRotation(tn: Tn, n: number): Promise<P[]> {
  const out: P[] = [];
  while ((await grants(tn.t)) < n) {
    const p = await mkPerson();
    await revoke(await invite(tn, p.hmac));
    out.push(p);
  }
  return out;
}

// ================================================================ the tests

test("E-05g-1 0019's shape: the three caps are AFTER-row triggers (so RLS refuses a stranger before any cap can answer), the rotation ledger is RLS-forced with no policy and no grant to any role, no new function is an rf_api power, and envelopes still carry no UPDATE/DELETE grant (ADR 2026-09-05g §2, §6 🔒; CLAUDE.md rule 2)", async () => {
  const trig = await sql`select c.relname as tbl, t.tgname as name, pg_get_triggerdef(t.oid) as def,
      p.prosecdef as definer
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_proc p on p.oid = t.tgfoid
    where t.tgname in ('invites_seat_cap', 'memberships_seat_cap', 'books_book_cap')
    order by t.tgname`;
  assertEquals(trig.map((r) => [r.tbl, r.name]), [
    ["books", "books_book_cap"],
    ["invites", "invites_seat_cap"],
    ["memberships", "memberships_seat_cap"],
  ]);
  for (const r of trig) {
    assert(/ AFTER INSERT/.test(r.def as string), `${r.name} fires AFTER the row policy: ${r.def}`);
    assert(/FOR EACH ROW/.test(r.def as string), `${r.name} is a row trigger`);
    assert(r.definer, `${r.name}'s function is SECURITY DEFINER (it reads rows RLS hides)`);
  }
  assert(
    /AFTER INSERT OR UPDATE OF status ON public\.memberships/.test(
      trig.find((r) => r.name === "memberships_seat_cap")!.def as string,
    ),
    "a membership is capped on insert and on every status change",
  );

  const [rel] = await sql`select relrowsecurity, relforcerowsecurity from pg_class
    where oid = 'public.seat_grants'::regclass`;
  assertEquals([rel.relrowsecurity, rel.relforcerowsecurity], [true, true]);
  const [pol] =
    await sql`select count(*)::int as n from pg_policies where tablename = 'seat_grants'`;
  assertEquals(pol.n, 0, "no policy: nobody reads or writes the ledger but the definer");
  for (const role of ["rf_api", "rf_maintenance"]) {
    for (const priv of ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]) {
      const [h] =
        await sql`select has_table_privilege(${role}, 'public.seat_grants', ${priv}) as ok`;
      assertEquals(h.ok, false, `${role} holds no ${priv} on seat_grants`);
    }
  }
  const [cols] = await sql`select count(*)::int as n from information_schema.columns
    where table_name = 'seat_grants' and (column_name like '%hmac%' or column_name like '%phone%')`;
  assertEquals(cols.n, 0, "the ledger holds no copy of a phone hash (it joins to the invite)");

  for (
    const fn of [
      "rf.tenant_plan(uuid)",
      "rf.caps_apply()",
      "rf.seat_holders(uuid, uuid, bytea)",
      "rf.take_seat(uuid, uuid, bytea, uuid)",
      "rf.invite_seat_cap()",
      "rf.membership_seat_cap()",
      "rf.book_cap()",
    ]
  ) {
    for (const role of ["rf_api", "rf_maintenance", "public"]) {
      const [h] = role === "public"
        ? await sql`select exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl,
              acldefault('f', p.proowner))) a where p.oid = ${fn}::regprocedure
              and a.grantee = 0 and a.privilege_type = 'EXECUTE') as ok`
        : await sql`select has_function_privilege(${role}, ${fn}, 'EXECUTE') as ok`;
      assertEquals(h.ok, false, `${role} cannot EXECUTE ${fn}`);
    }
  }
  for (const priv of ["UPDATE", "DELETE"]) {
    const [h] = await sql`select has_table_privilege('rf_api', 'public.envelopes', ${priv}) as ok`;
    assertEquals(h.ok, false, `rf_api still holds no ${priv} on envelopes`);
  }
});

test("E-05g-2 at the cap an invite is refused, one under it is allowed — ADR 05g §6's own example: one active member and five outstanding invites on a 5-seat plan is 6 and is refused; the refusal is the named `seat_cap` (P0001, not an RLS denial), leaves no row, and reaches the edge as StoreDenied('seat_cap')", async () => {
  const tn = await tenant(PLAN.five);
  const [{ members }] = await sql`select members from plan_catalogue where id = ${PLAN.five}`;
  assertEquals(members, 5, "the test row is the ADR's 5-seat plan");
  for (let i = 1; i <= 4; i++) {
    assertEquals(await tryInvite(tn, rand(32)), OK, `invite ${i}: ${1 + i} of 5 seats`);
  }
  assertEquals(await holders(tn.t), 5, "one active + four outstanding = the plan, exactly");
  const fifth = await tryInvite(tn, rand(32));
  assertCap(fifth, "seat_cap", "the fifth outstanding invite makes 6 on a 5-seat plan");
  assertNotEquals(fifth.code, "42501", "a cap is not a privilege denial");
  assertEquals(await liveInvites(tn.t), 4, "the refused invite left no row");

  // The same refusal through the store the edge uses: denialFromPg passes the name through.
  const store = new PgStore(url!);
  try {
    const rec = await record(tn.t, tn.admin.dev, "invite");
    let reason = "";
    try {
      await store.withClaims(
        { user_id: tn.admin.user, device_id: tn.admin.dev },
        (tx) => tx.createInvite(rec, tn.t, rand(32), [], rand(16)),
      );
    } catch (e) {
      assert(e instanceof StoreDenied, `a named denial, not ${e}`);
      reason = e.reason;
    }
    assertEquals(reason, "seat_cap");
  } finally {
    await store.end();
  }
});

test("E-05g-3 seats count invited + joined_pending_verification + active and each person ONCE (06 §7): an invite, the invited row it backs and the acceptance are one seat; blocked, removed and revoked hold none; and at a full plan the moves INSIDE the counted set — accepting an invite, a verified ceremony — are never refused", async () => {
  const tn = await tenant(PLAN.five);
  // A: invited, then accepts → joined_pending_verification (one seat throughout)
  const a = await mkPerson();
  await accept(a, await invite(tn, a.hmac));
  assertEquals(await statusOf(tn.t, a.user), "joined_pending_verification");
  // B: invited, and the admin's record projects the `invited` membership row it backs
  const b = await mkPerson();
  await invite(tn, b.hmac);
  await project(tn, b.user, "invited");
  assertEquals(await statusOf(tn.t, b.user), "invited");
  // C removed, D blocked (after a signed mismatch), R: a revoked invite — none holds a seat
  const c = await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status) values (${tn.t}, ${c.user}, 'removed')`;
  const d = await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${tn.t}, ${d.user}, 'joined_pending_verification')`;
  await sql`insert into verification_events
    (tenant_id, subject_user, verifier_user, method, result, source_record_id)
    values (${tn.t}, ${d.user}, ${tn.admin.user}, 'qr_in_person', 'mismatch',
            ${await record(tn.t, tn.admin.dev, "verification_event")})`;
  await sql`update memberships set status = 'blocked' where tenant_id = ${tn.t} and user_id = ${d.user}`;
  await revoke(await invite(tn, rand(32)));
  assertEquals(await holders(tn.t), 3, "admin + A (joined_pending) + B (invited ≡ its invite)");

  // E: a number nobody has signed up with; F: a real user, invited — the plan is now full
  assertEquals(await tryInvite(tn, rand(32)), OK);
  const f = await mkPerson();
  const fInvite = await invite(tn, f.hmac);
  assertEquals(await holders(tn.t), 5);
  assertCap(await tryInvite(tn, rand(32)), "seat_cap", "a sixth person on five seats");

  // At full: F accepts (the seat moves from the invite to the row), A is verified to active.
  await accept(f, fInvite);
  assertEquals(await statusOf(tn.t, f.user), "joined_pending_verification");
  await verify(tn, a);
  assertEquals(await statusOf(tn.t, a.user), "active");
  assertEquals(await holders(tn.t), 5, "still five: nothing moved inside the set took a seat");
  assertCap(await tryInvite(tn, rand(32)), "seat_cap", "and a sixth is still refused");
});

test("E-05g-4 removal frees the seat at once (ADR 05g §6): a full plan refuses an invite, the member's removal frees the seat within the same second, and a withdrawn invite or one past its 7-day window holds no seat either — even before the expiry sweep has run", async () => {
  const tn = await tenant(PLAN.two);
  const a = await activeMember(tn);
  assertCap(await tryInvite(tn, rand(32)), "seat_cap", "admin + one member fill two seats");
  await project(tn, a.user, "removed");
  assertEquals(await statusOf(tn.t, a.user), "removed");
  const x = await invite(tn, rand(32));
  assertEquals(await holders(tn.t), 2, "the freed seat was taken at once");

  await revoke(x);
  const y = await invite(tn, rand(32));
  assertEquals(await holders(tn.t), 2, "a revoked invite freed its seat");

  // An invite whose window has closed, still at `sent` because rf.expire_invites has not run.
  await revoke(y);
  await sql`insert into invites (tenant_id, invitee_hmac, roles, nonce, created_by, source_record_id,
      created_at, expires_at)
    values (${tn.t}, ${rand(32)}, '[]'::jsonb, ${rand(16)}, ${tn.admin.user},
            ${await record(tn.t, tn.admin.dev, "invite")}, now() - interval '8 days',
            now() - interval '1 day')`;
  assertEquals(await liveInvites(tn.t), 1, "the stale invite is still `sent`");
  assertEquals(await tryInvite(tn, rand(32)), OK, "…but past its window it holds no seat");
});

test("E-05g-5 every ENTRY into a counted state is capped, not only an invite: at a full plan an admin's membership_status record cannot walk a removed member — or a stranger — to joined_pending_verification without an invite; the row is unchanged, and once a seat is freed the same record applies", async () => {
  const tn = await tenant(PLAN.two);
  const a = await activeMember(tn);
  const r = await mkPerson();
  await sql`insert into memberships (tenant_id, user_id, status) values (${tn.t}, ${r.user}, 'removed')`;
  const n = await mkPerson();

  assertCap(
    await pgErr(project(tn, r.user, "joined_pending_verification")),
    "seat_cap",
    "removed → joined_pending on a full plan",
  );
  assertEquals(await statusOf(tn.t, r.user), "removed", "refused whole: the row did not move");
  assertCap(
    await pgErr(project(tn, n.user, "joined_pending_verification")),
    "seat_cap",
    "(none) → joined_pending on a full plan",
  );
  assertEquals(await statusOf(tn.t, n.user), null);

  await project(tn, a.user, "removed");
  await project(tn, r.user, "joined_pending_verification");
  assertEquals(await statusOf(tn.t, r.user), "joined_pending_verification");
});

test("E-05g-6 the rolling cap stops seat rotation (ADR 05g §6): on a 2-seat plan the fifth distinct member inside a trailing year is refused `seat_rotation_cap` although a seat is free; another tenant's ledger is its own; and a grant older than a year no longer counts", async () => {
  const tn = await tenant(PLAN.two);
  const [{ members }] = await sql`select members from plan_catalogue where id = ${PLAN.two}`;
  await spendRotation(tn, 2 * members);
  assertEquals(await grants(tn.t), 4, "2 × seats grants, each invite withdrawn again");
  assertEquals(await holders(tn.t), 1, "only the founder holds a seat: one is free");
  const fifth = await mkPerson();
  assertCap(
    await tryInvite(tn, fifth.hmac),
    "seat_rotation_cap",
    "a fifth distinct member in a year",
  );
  assertEquals(await grants(tn.t), 4, "a refused grant is not appended");

  const other = await tenant(PLAN.two);
  assertEquals(await tryInvite(other, fifth.hmac), OK, "another tenant's budget is untouched");

  await sql`update seat_grants set granted_at = now() - interval '1 year 1 day'
    where tenant_id = ${tn.t}`;
  assertEquals(await tryInvite(tn, fifth.hmac), OK, "the year rolled: those grants fell out");
});

test("E-05g-7 re-inviting the SAME user_id within 30 days takes no new seat of the rotation budget, and after 30 days it counts again — the exemption never bends the seat cap itself, and it follows the person from a number invited before sign-up to the user who accepted it", async () => {
  const tn = await tenant(PLAN.two);
  const [p1, p2] = await spendRotation(tn, 4);
  const again = await invite(tn, p1.hmac);
  assertEquals(await grants(tn.t), 4, "within 30 days: the same person, no new grant");
  assertCap(
    await tryInvite(tn, p2.hmac),
    "seat_cap",
    "p2 is inside its 30 days too, but both seats are held — the exemption is not a seat",
  );
  await revoke(again);

  await sql`update seat_grants set granted_at = now() - interval '31 days'
    where tenant_id = ${tn.t} and user_id = ${p1.user}`;
  assertCap(
    await tryInvite(tn, p1.hmac),
    "seat_rotation_cap",
    "31 days on, p1 is a new grant again — and the year's budget is spent",
  );

  // One person across sign-up: invited as a bare number, then signs up, accepts, is removed.
  const tc = await tenant(PLAN.two);
  const h = rand(32);
  const first = await invite(tc, h);
  const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${h}, ${rand(40)})
    returning id`;
  const [dv] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${u.id}, ${rand(32)}, ${rand(32)}, 'certified') returning id`;
  const joiner: P = { user: u.id as string, dev: dv.id as string, hmac: h };
  await accept(joiner, first);
  await project(tc, joiner.user, "removed");
  await spendRotation(tc, 4);
  assertEquals(
    await tryInvite(tc, h),
    OK,
    "the same person within 30 days, though the budget is spent",
  );
  assertEquals(await grants(tc.t), 4);
  await sql`update invites set status = 'revoked' where tenant_id = ${tc.t} and status = 'sent'`;
  assertCap(
    await tryInvite(tc, rand(32)),
    "seat_rotation_cap",
    "a genuinely new member is refused",
  );
});

test("E-05g-8 -1 is no cap (ADR 2026-09-24b §7 (b) 🔒): on an unlimited plan invites and business books are never refused, however many — and the grants are still recorded, so a later downgrade reads real history", async () => {
  const tn = await tenant(PLAN.none);
  for (let i = 0; i < 12; i++) assertEquals(await tryInvite(tn, rand(32)), OK, `invite ${i}`);
  for (let i = 0; i < 12; i++) assertEquals(await tryBook(tn, tn.admin), OK, `book ${i}`);
  assertEquals(await liveInvites(tn.t), 12);
  assertEquals(await bookCount(tn.t), 13, "twelve business books + the personal one");
  assertEquals(await grants(tn.t), 12);
});

test("E-05g-9 the business-book cap: the personal book is never counted, Free (no subscription row → the floor) refuses the second book — any non-personal one — and a capped plan allows exactly its `business_books`; an archived book still counts (0019 ⚠️ SPEC)", async () => {
  const free = await tenant(null);
  const m = await activeMember(free);
  assertEquals(await tryBook(free, m, "personal"), OK, "another member's personal book is free");
  for (const type of ["business", "family", "joint"]) {
    assertCap(await tryBook(free, free.admin, type), "book_cap", `Free: a ${type} book is refused`);
  }
  assertEquals(await bookCount(free.t), 2, "two personal books, no refused row");

  const tn = await tenant(PLAN.five);
  const [{ business_books }] = await sql`select business_books from plan_catalogue
    where id = ${PLAN.five}`;
  const made: string[] = [];
  for (let i = 0; i < business_books; i++) made.push(await mkBook(tn, tn.admin));
  assertCap(await tryBook(tn, tn.admin), "book_cap", "one more than business_books");
  const n = await activeMember(tn);
  assertEquals(await tryBook(tn, n, "personal"), OK, "a personal book at the cap: never counted");
  await sql`update books set archived_at = now() where id = ${made[0]}`;
  assertCap(await tryBook(tn, tn.admin), "book_cap", "archiving is not deleting: it still counts");
});

test("E-05g-10 downgrade deletes nothing (ADR 05g §6, 08 §3): after a tenant drops below its members and books, every row stays, every excess member still reads the members and the books, re-applied records and an in-flight ceremony are not refused — only a NEW seat or a NEW book is", async () => {
  const tn = await tenant(PLAN.none);
  const members = [await activeMember(tn), await activeMember(tn), await activeMember(tn)];
  const pending = await mkPerson();
  await accept(pending, await invite(tn, pending.hmac));
  for (let i = 0; i < 3; i++) await mkBook(tn, tn.admin);
  const rows = async () =>
    (await sql`select user_id, status from memberships where tenant_id = ${tn.t} order by user_id`)
      .map((r) => [r.user_id as string, r.status as string]);
  const before = await rows();
  const books = await bookCount(tn.t);

  await sql`update subscriptions set plan = ${PLAN.two} where tenant_id = ${tn.t}`;
  assertEquals(await rows(), before, "no membership deleted or demoted");
  assertEquals(await bookCount(tn.t), books, "no book deleted");
  for (const p of members) {
    const [seen] = await asApi(
      p.user,
      p.dev,
      (s) =>
        s`select (select count(*)::int from memberships where tenant_id = ${tn.t}) as m,
               (select count(*)::int from books where tenant_id = ${tn.t}) as b`,
    );
    assertEquals([seen.m, seen.b], [before.length, books], "an excess member keeps read access");
  }
  await project(tn, members[0].user, "active");
  await verify(tn, pending);
  assertEquals(await statusOf(tn.t, pending.user), "active", "the ceremony in flight completes");
  assertCap(await tryInvite(tn, rand(32)), "seat_cap", "a NEW seat is refused");
  assertCap(await tryBook(tn, tn.admin), "book_cap", "a NEW business book is refused");
});

test("E-05g-11 no oracle and no bypass: a certified device of another tenant and an uncertified device of this one get the RLS / not_admin refusal on a FULL tenant — never a cap; a claims-less rf_api writes nothing; a caller holding only a DEVICE claim is capped like any other (0021: the caps skip only when both claims are null); and no role can read or write the rotation ledger, or ask the plan resolver or the device cap about anyone (0021 revokes rf.device_cap from rf_api; rf.register_device still enforces it)", async () => {
  const tn = await tenant(PLAN.two);
  await activeMember(tn);
  const full = await tryInvite(tn, rand(32));
  assertCap(full, "seat_cap", "the tenant is full");
  const other = await tenant(PLAN.none);
  const raw = await mkDev(tn.admin.user, "registered");

  for (
    // The claims-less caller cannot even SEE the authorising record (signed_records_select), so the
    // invite guard refuses it `no_record` before the policy is reached — named, and not a cap.
    const [who, u, d, directCode] of [
      ["another tenant's certified admin", other.admin.user, other.admin.dev, "42501"],
      ["this tenant's admin on an uncertified device", tn.admin.user, raw, "42501"],
      ["a caller with no claims", null, null, "23514"],
    ] as const
  ) {
    const rec = await record(tn.t, d ?? tn.admin.dev, "invite");
    const viaFn = await pgErr(
      asApi(
        u,
        d,
        (s) => s`select rf.create_invite(${tn.t}, ${rand(32)}, '[]'::jsonb, ${rand(16)}, ${rec})`,
      ),
    );
    assertEquals([viaFn.code, viaFn.message], ["42501", "not_admin"], `${who}: create_invite`);
    const direct = await pgErr(
      asApi(
        u,
        d,
        (s) =>
          s`insert into invites (tenant_id, invitee_hmac, roles, nonce, created_by, source_record_id)
        values (${tn.t}, ${rand(32)}, '[]'::jsonb, ${rand(16)}, ${u ?? tn.admin.user}, ${rec})`,
      ),
    );
    assertEquals(direct.code, directCode, `${who}: a direct invite is refused before any cap`);
    assert(!/cap/.test(direct.message), `${who} learns nothing about the plan: ${direct.message}`);
    const book = await pgErr(
      asApi(
        u,
        d,
        (s) =>
          s`insert into books (id, tenant_id, type) values (gen_random_uuid(), ${tn.t}, 'business')`,
      ),
    );
    assertEquals(book.code, "42501", `${who}: a book is the policy's refusal`);
    assert(!/cap/.test(book.message), `${who}: ${book.message}`);
  }
  assertEquals(await liveInvites(tn.t), 0);

  // CAP1 finding 3 (0021): rf.project_membership authorises on the DEVICE claim alone
  // (rf.require_record), so a transaction that sets the founder's own device and no user must meet
  // the seat cap too. Before 0021, rf.caps_apply() keyed on the user claim and this walked a third
  // person into a 2-seat tenant.
  const third = await mkPerson();
  const recDev = await record(tn.t, tn.admin.dev, "membership_status");
  const devOnly = await pgErr(
    asApi(
      null,
      tn.admin.dev,
      (s) =>
        s`select rf.project_membership(${recDev}, ${tn.t}, ${third.user}, 'joined_pending_verification')`,
    ),
  );
  assertCap(devOnly, "seat_cap", "device claim only: the full tenant still refuses the seat");
  assertEquals(await statusOf(tn.t, third.user), null, "and no membership row was left behind");
  assertEquals(await holders(tn.t), 2, "the seat count did not move");
  const devOnlyBook = await pgErr(
    asApi(
      null,
      tn.admin.dev,
      (s) =>
        s`insert into books (id, tenant_id, type) values (gen_random_uuid(), ${tn.t}, 'business')`,
    ),
  );
  assertEquals(devOnlyBook.code, "42501", "device claim only: a book is the policy's refusal");
  assert(!/cap/.test(devOnlyBook.message), devOnlyBook.message);

  // The ledger and the helpers: nobody but the definer.
  for (
    const [what, q] of [
      ["read the ledger", (s: postgres.TransactionSql) => s`select * from seat_grants`],
      [
        "forge a grant",
        (s: postgres.TransactionSql) =>
          s`insert into seat_grants (tenant_id, user_id) values (${tn.t}, ${tn.admin.user})`,
      ],
      [
        "buy back budget",
        (s: postgres.TransactionSql) =>
          s`update seat_grants set granted_at = now() - interval '2 years'`,
      ],
      ["erase history", (s: postgres.TransactionSql) => s`delete from seat_grants`],
      [
        "ask another tenant's plan",
        (s: postgres.TransactionSql) => s`select rf.tenant_plan(${other.t})`,
      ],
      [
        "count another tenant's seats",
        (s: postgres.TransactionSql) => s`select rf.seat_holders(${other.t}, null, null)`,
      ],
      [
        "take a seat by hand",
        (s: postgres.TransactionSql) =>
          s`select rf.take_seat(${other.t}, ${tn.admin.user}, null, null)`,
      ],
      [
        // CAP1 finding 6 (0021): the device cap is the plan resolver one function away — any
        // user's number (5 / 8 / 15 …) says which plan their tenants are on.
        "ask a stranger's device cap",
        (s: postgres.TransactionSql) => s`select rf.device_cap(${other.admin.user})`,
      ],
    ] as const
  ) {
    const e = await pgErr(asApi(tn.admin.user, tn.admin.dev, q));
    assertEquals(e.code, "42501", `rf_api cannot ${what}`);
  }
  const dcNoClaims = await pgErr(
    asApi(null, null, (s) => s`select rf.device_cap(${other.admin.user})`),
  );
  assertEquals(dcNoClaims.code, "42501", "a claims-less rf_api cannot ask a device cap either");
  const [dcAcl] = await sql`select
      has_function_privilege('rf_api', 'rf.device_cap(uuid)', 'EXECUTE') as api,
      has_function_privilege('rf_maintenance', 'rf.device_cap(uuid)', 'EXECUTE') as maint,
      exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where p.oid = 'rf.device_cap(uuid)'::regprocedure and a.grantee = 0
                and a.privilege_type = 'EXECUTE') as pub`;
  assertEquals([dcAcl.api, dcAcl.maint, dcAcl.pub], [false, false, false]);
  // …and the one caller that needs it, rf.register_device (SECURITY DEFINER, the pre-JWT path the
  // edge runs with no claims), still reads it: a user registers up to the cap and not one more.
  const [{ cap, held }] = await sql`select rf.device_cap(${tn.admin.user}) as cap,
    (select count(*)::int from devices where user_id = ${tn.admin.user}
       and status in ('registered', 'certified', 'suspended')) as held`;
  assert(cap > held && cap < 100, `a finite cap above what is held (${held} of ${cap})`);
  const reg = () =>
    pgErr(
      asApi(
        null,
        null,
        (s) =>
          s`select rf.register_device(gen_random_uuid(), ${tn.admin.user}::uuid, ${rand(32)},
            ${rand(32)}, null, null, null)`,
      ),
    );
  for (let i = held; i < cap; i++) assertEquals(await reg(), OK, `device ${i + 1} of ${cap}`);
  assertEquals([(await reg()).message], ["device_cap"], "one more than the cap is refused by name");
  for (const q of ["select * from seat_grants", "delete from seat_grants"]) {
    const e = await pgErr(asRole("rf_maintenance", null, null, (s) => s.unsafe(q)));
    assertEquals(e.code, "42501", `rf_maintenance: ${q}`);
  }
});
async function mkDev(user: string, status: string): Promise<string> {
  const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${user}, ${rand(32)}, ${rand(32)}, ${status}) returning id`;
  return d.id as string;
}

test("E-05g-12 one plan resolution for all three caps, and the caps read the COLUMN: rf.tenant_plan is the subscription's plan or the Free floor, rf.device_cap reads the same resolver, and editing a catalogue row's members / business_books moves the cap with no code change (desk PLAN-49)", async () => {
  const bare = await tenant(null);
  const [r0] = await sql`select rf.tenant_plan(${bare.t}) as p`;
  assertEquals(r0.p, "free", "no subscription row → the Free floor (ADR 05g §1; desk PLAN-48)");
  const tn = await tenant(PLAN.data);
  const [r1] = await sql`select rf.tenant_plan(${tn.t}) as p`;
  assertEquals(r1.p, PLAN.data);

  const [dc] = await sql`select rf.device_cap(${tn.admin.user}) as cap,
    (select devices from plan_catalogue where id = ${PLAN.data}) as want`;
  const [df] = await sql`select rf.device_cap(${bare.admin.user}) as cap,
    (select devices from plan_catalogue where id = 'free') as want`;
  // CAP1 finding 5: with zz_cap_data's devices equal to the Free floor's, a device cap that ignored
  // the subscription would still have passed. The two numbers must differ for this to prove a thing.
  assertNotEquals(dc.want, df.want, "the test row's devices differs from the Free floor's");
  assertEquals(dc.cap, dc.want, "the device cap reads the same plan the seat cap does");
  assertEquals(df.cap, df.want);

  await invite(tn, rand(32));
  assertCap(await tryInvite(tn, rand(32)), "seat_cap", "members = 2, both held");
  await sql`update plan_catalogue set members = 3 where id = ${PLAN.data}`;
  assertEquals(await tryInvite(tn, rand(32)), OK, "the next invite reads the new number");

  await mkBook(tn, tn.admin);
  assertCap(await tryBook(tn, tn.admin), "book_cap", "business_books = 1, in use");
  await sql`update plan_catalogue set business_books = 2 where id = ${PLAN.data}`;
  assertEquals(await tryBook(tn, tn.admin), OK, "the next book reads the new number");
});

test("E-05g-13 two admins racing for the last seat: exactly one wins — the cap is serialised per tenant, so a second invite waits for the first transaction and then sees its seat taken", async () => {
  const tn = await tenant(PLAN.five);
  const admin2 = await activeMember(tn, true);
  for (let i = 0; i < 2; i++) await invite(tn, rand(32));
  assertEquals(await holders(tn.t), 5 - 1, "admin + admin2 + two invites: one seat left");

  let inserted!: () => void;
  const didInsert = new Promise<void>((r) => (inserted = r));
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  const rec1 = await record(tn.t, tn.admin.dev, "invite");
  const rec2 = await record(tn.t, admin2.dev, "invite");
  const first = asApi(tn.admin.user, tn.admin.dev, async (s) => {
    await s`select rf.create_invite(${tn.t}, ${rand(32)}, '[]'::jsonb, ${rand(16)}, ${rec1})`;
    inserted();
    await gate; // hold the transaction open
  });
  await didInsert;
  const second = pgErr(
    asApi(
      admin2.user,
      admin2.dev,
      (s) => s`select rf.create_invite(${tn.t}, ${rand(32)}, '[]'::jsonb, ${rand(16)}, ${rec2})`,
    ),
  );
  let waiting = 0;
  for (let i = 0; i < 50 && waiting === 0; i++) {
    const [w] = await sql`select count(*)::int as n from pg_locks
      where locktype = 'advisory' and not granted`;
    waiting = w.n as number;
    if (waiting === 0) await new Promise((r) => setTimeout(r, 20));
  }
  assertEquals(waiting, 1, "the second admin is WAITING on the tenant's seat lock");
  release();
  await first;
  assertCap(await second, "seat_cap", "…and, once the first commits, finds the seat gone");
  assertEquals(await holders(tn.t), 5);
});

test("E-05g-15 one personal book per person per tenant (0021; ADR 2026-09-25 §5 'Each person's personal book is free and never counted' — ⚠️ SPEC: implied, not stated): a second personal book for the same owner in the same tenant is refused by a unique partial index on every plan, Free and unlimited alike, archived or not — so `type = 'personal'` is no longer a way around the business-book cap; another member's first personal book is still free; the same person's personal book in another tenant stands (the per-(tenant, owner) reading); and a stranger still meets the RLS refusal, never the index", async () => {
  const [ix] = await sql`select indexdef from pg_indexes
    where schemaname = 'public' and indexname = 'books_one_personal_per_owner'`;
  assert(ix, "the index exists");
  assert(
    /CREATE UNIQUE INDEX .* ON public\.books .*\(tenant_id, owner_user_id\) WHERE \(type = 'personal'::text\)/
      .test(ix.indexdef as string),
    `unique on (tenant_id, owner_user_id), partial on type = 'personal': ${ix.indexdef}`,
  );
  const dupe = (e: PgErr, why: string) =>
    assertEquals([e.code, /books_one_personal_per_owner/.test(e.message)], ["23505", true], why);

  for (const plan of [null, PLAN.none]) {
    const tn = await tenant(plan); // the founder already holds one personal book here
    for (let i = 0; i < 3; i++) {
      dupe(
        await tryBook(tn, tn.admin, "personal"),
        `plan ${plan ?? "free"}: personal book ${i + 2}`,
      );
    }
    await sql`update books set archived_at = now() where id = ${tn.personal}`;
    dupe(
      await tryBook(tn, tn.admin, "personal"),
      "an archived personal book still holds the place",
    );
    const m = await activeMember(tn);
    assertEquals(await tryBook(tn, m, "personal"), OK, "another member's first personal book");
    dupe(await tryBook(tn, m, "personal"), "…and only one");
    assertEquals(await bookCount(tn.t), 2, "two people, two personal books, nothing else");
  }

  // Free still refuses a business book, so the personal label was the only way past the cap.
  const free = await tenant(null);
  assertCap(await tryBook(free, free.admin), "book_cap", "Free: no business book");
  // The same person founding a second tenant gets that tenant's personal book (the fixture writes
  // it, and the index binds the owner's writes too — so this line is itself the per-tenant proof).
  const second = await tenant(null, free.admin);
  assertNotEquals(second.personal, free.personal);
  const [{ n }] = await sql`select count(*)::int as n from books
    where owner_user_id = ${free.admin.user} and type = 'personal'`;
  assertEquals(n, 2, "one personal book in each of the person's two tenants");

  // No oracle: a certified stranger naming this tenant's founder (who DOES hold a personal book
  // here) is refused by books_insert before the index is ever consulted.
  const stranger = await tenant(PLAN.none);
  const e = await pgErr(
    asApi(
      stranger.admin.user,
      stranger.admin.dev,
      (s) =>
        s`insert into books (id, tenant_id, type, owner_user_id)
          values (gen_random_uuid(), ${free.t}, 'personal', ${free.admin.user})`,
    ),
  );
  assertEquals(e.code, "42501", `the policy refuses the stranger, not the index: ${e.message}`);
  assert(!/personal|duplicate/.test(e.message), e.message);
});

test(
  "E-05g-16 (database half) desk 68(a) through the real handler over the real store: a re-sent membership_status record the seat cap refused answers rejected:seat_cap again — never acked — and leaves no row and no applied mark; once a seat is freed the same record applies and is acked, and its replay is acked with the same seq and changes nothing",
  async () => {
    // rls_db.sh applies the migrations and not seed.sql, so on a fresh database the one
    // store_epoch row /records answers with is absent; seed.sql's own line, as a fixture.
    await sql`insert into store_epoch (id, epoch) values (true, gen_random_uuid())
      on conflict (id) do nothing`;
    // A founder whose device key really signs, so sync-meta's own intake admits the record.
    const keys = await edKeypair();
    const hmac = rand(32);
    const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${hmac}, ${rand(40)})
    returning id`;
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${u.id}, ${keys.pub}, ${rand(32)}, 'certified') returning id`;
    const founder: P = { user: u.id as string, dev: d.id as string, hmac };
    const tn = await tenant(PLAN.two, founder);
    const filler = await activeMember(tn);
    assertEquals(await holders(tn.t), 2, "the 2-seat plan is full");

    const r = rig();
    const store = new PgStore(url!);
    r.deps.store = store;
    const signer = {
      user: founder.user,
      device: { id: founder.dev },
      keys,
      xpub: rand(32),
      claims: { user_id: founder.user, device_id: founder.dev },
      token: "",
    } as unknown as Member;
    await reissue(r, signer);
    try {
      const joiner = await mkPerson();
      const rec = await signedRecord(signer, tn.t, "membership_status", {
        user_id: joiner.user,
        status: "joined_pending_verification",
      });
      const send = async () =>
        (await body(
          await meta(
            post("/sync-meta/records", { records: [rec.wire] }, { token: signer.token }),
            r.deps,
          ),
        )).results[0];
      const applied = async () =>
        (await sql`select applied_at, apply_note from signed_records where id = ${rec.row.id}`)[0];

      const first = await send();
      assertEquals([first.result, first.check], ["rejected:seat_cap", "seat_cap"]);
      const again = await send();
      assertEquals(
        [again.id, again.result, again.check],
        [rec.row.id, "rejected:seat_cap", "seat_cap"],
        "the re-send is the same named refusal, not acked",
      );
      assertEquals(await statusOf(tn.t, joiner.user), null, "no membership row");
      assertEquals((await applied()).applied_at, null, "the stored record is not marked applied");
      assertEquals(await holders(tn.t), 2);

      await project(tn, filler.user, "removed");
      const later = await send();
      assertEquals(later.result, "acked", "a seat is free: the same record applies now");
      assertEquals(await statusOf(tn.t, joiner.user), "joined_pending_verification");
      const mark = await applied();
      assertNotEquals(mark.applied_at, null);
      const replay = await send();
      assertEquals([replay.result, replay.seq], ["acked", later.seq], "replay: the stored outcome");
      assertEquals(await statusOf(tn.t, joiner.user), "joined_pending_verification");
      assertEquals(
        ((await applied()).applied_at as Date).getTime(),
        (mark.applied_at as Date).getTime(),
        "not applied a second time",
      );
    } finally {
      await store.end();
    }
  },
);

test("E-05g-1 teardown: the test-only plan rows leave the catalogue as the seed wrote it", async () => {
  const ids = Object.values(PLAN) as string[];
  await sql`update subscriptions set plan = 'free' where plan in ${sql(ids)}`;
  await sql`delete from plan_catalogue where id in ${sql(ids)}`;
  const [r] = await sql`select count(*)::int as n from plan_catalogue where id in ${sql(ids)}`;
  assertEquals(r.n, 0);
});
