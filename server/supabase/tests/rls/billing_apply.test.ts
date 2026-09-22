// Hostile-query suite for the billing apply path — migration 0013, against 03 §2.4 🔒, 08 §3 🔒,
// 08 §4 🔒, ADR 2026-09-05g §4, §9, §11, and CLAUDE.md rule 2.
//
// What an attacker wants from this table set, and what each test denies:
//
//   * ANOTHER TENANT'S plan, period end and payer — `subscriptions` is the one billing table
//     rf_api may read at all, and 0005's `subscriptions_select` scopes it to rf.active_in_tenant.
//     A certified device in tenant B must see nothing of tenant A (E-03-66).
//   * A FREE UPGRADE — an UPDATE on `subscriptions` from the API role. There is no such grant and
//     0013 adds none; the only write path is a SECURITY DEFINER function that takes an ACTION, not
//     a column, so the worst a compromised API role can ask for is a state change the gateway's
//     vocabulary already allows (E-03-65, E-03-66).
//   * THE AUDIT TRAIL — rewriting or deleting a recorded `billing_events` row would erase the
//     evidence the daily reconciliation poll (ADR 2026-09-05g §9) reads. The guard refuses every
//     column but `applied_at`, refuses a second `applied_at`, and refuses DELETE outright (E-03-70).
//   * A REPLAY, or a stale retry that overtakes a newer event — dedupe and the out-of-order guard
//     (E-03-67).
//   * ANY sight of financial content — the apply path must not read `envelopes` (E-03-70,
//     08 §5 / 06 §10 🔒 "No API path counts, sums, or gates on envelope contents").
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-03-65 … E-03-70.
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — billing_apply.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP billing_apply.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
const DAY = 86400e3;
const T0 = new Date("2026-09-22T09:00:00.000Z");
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
const pgCode = async (p: Promise<unknown>) => (await pgErr(p)).code;

interface Apply {
  eventId: string;
  action: string;
  tenant?: string | null;
  at?: Date | null;
  plan?: string | null;
  periodEnd?: Date | null;
  ref?: string | null;
  source?: string | null;
  original?: string | null;
  dispute?: string | null;
  type?: string;
  fill?: number;
}
/** The one call the webhook makes, through the role the webhook actually runs as (rf_api, no
 *  claims — a gateway delivery carries no user). */
function apply(a: Apply): Promise<{ fresh: boolean; applied: boolean; outcome: string }[]> {
  return asApi(null, null, (s) =>
    s`select * from rf.apply_billing_event(
      ${a.eventId}, 'razorpay', ${a.type ?? "subscription.charged"},
      ${bytes(32, a.fill ?? 1)}::bytea, ${a.action},
      ${a.tenant ?? null}::uuid, ${a.at ?? null}::timestamptz, ${a.plan ?? null}::text,
      ${a.periodEnd ?? null}::timestamptz, ${a.ref ?? null}::text, ${a.source ?? null}::text,
      ${a.original ?? null}::text, ${a.dispute ?? null}::text)`) as Promise<
      { fresh: boolean; applied: boolean; outcome: string }[]
    >;
}

interface Fx {
  t1: string;
  t2: string;
  owner: string; // certified, active in t1
  outsider: string; // certified, active in t2 only
  dev: Record<string, string>;
}
let fx: Fx;

/** Fresh tenants and subscriptions for one test, so the out-of-order guard of one test cannot
 *  reach into the next. Fills 0xc1+ (umk_public_x.test.ts owns 0xb1–0xb4). */
async function seed(): Promise<Fx> {
  const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
  const [t2] = await sql`insert into tenants (type) values ('business_group') returning id`;
  const mk = async (fill: number) => {
    const [u] = await sql`insert into users (phone_hmac, phone_ct)
      values (${bytes(32, fill)}, ${bytes(40, fill)}) returning id`;
    return u.id as string;
  };
  const owner = await mk(0xc1), outsider = await mk(0xc2);
  const dev: Record<string, string> = {};
  for (const [name, user] of [["owner", owner], ["outsider", outsider]] as const) {
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${user}, ${bytes(32, 6)}, ${bytes(32, 7)}, 'certified')
      returning id`;
    dev[name] = d.id;
  }
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${owner}, 'active'), (${t2.id}, ${outsider}, 'active')`;
  await sql`insert into subscriptions (tenant_id) values (${t1.id}), (${t2.id})`;
  return { t1: t1.id, t2: t2.id, owner, outsider, dev };
}
const row = (t: string) =>
  sql`select * from subscriptions where tenant_id = ${t}`.then((r) => r[0] as postgres.Row);
/** `updated_at` at FULL precision. A JS Date truncates to the millisecond, and two transactions
 *  microseconds apart round to the same one — so the cursor assertion is made in Postgres, against
 *  the text Postgres itself rendered. */
const stamp = (t: string) =>
  sql<{ u: string }[]>`select updated_at::text as u from subscriptions where tenant_id = ${t}`
    .then((r) => r[0].u);
const movedSince = (t: string, was: string) =>
  sql<{ moved: boolean }[]>`select updated_at > ${was}::timestamptz as moved
    from subscriptions where tenant_id = ${t}`.then((r) => r[0].moved);

Deno.test({
  name:
    "E-03-65 0013's shape: billing_events gains a nullable tenant_id and the GATEWAY's event_at, rf.apply_billing_event is SECURITY DEFINER granted to rf_api and revoked from public, and no new table privilege exists anywhere (03 §2.4 🔒, ADR 2026-09-05g §9, CLAUDE.md rule 2)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();

    const cols = await sql<{ column_name: string; data_type: string; is_nullable: string }[]>`
      select column_name, data_type, is_nullable from information_schema.columns
      where table_name = 'billing_events' order by column_name`;
    const by = new Map(cols.map((c) => [c.column_name, c]));
    // 0004's six columns of 03 §2.4 🔒 are untouched — 0013 widens, it does not reshape.
    for (const c of ["event_id", "gateway", "type", "payload_hash", "received_at", "applied_at"]) {
      assert(by.has(c), `0004's ${c} survives`);
    }
    assertEquals(by.get("tenant_id")?.data_type, "uuid");
    assertEquals(
      by.get("tenant_id")?.is_nullable,
      "YES",
      "an event whose tenant we could not resolve is still RECORDED (never a silent drop), so the column must accept null",
    );
    assertEquals(by.get("event_at")?.data_type, "timestamp with time zone");
    assertEquals(by.get("event_at")?.is_nullable, "YES");

    // The guard's read path, and the guard itself.
    const idx = await sql<{ indexname: string }[]>`
      select indexname from pg_indexes where tablename = 'billing_events'
        and indexdef ilike '%event_at%'`;
    assert(idx.length >= 1, "the newest-applied-event lookup has an index");
    const trg = await sql<{ tgname: string; tgtype: number }[]>`
      select tgname, tgtype from pg_trigger t join pg_class c on c.oid = t.tgrelid
      where not t.tgisinternal and c.relname = 'billing_events'`;
    assertEquals(trg.length, 1, "billing_events carries exactly one guard");
    assert((Number(trg[0].tgtype) & 2) !== 0, "the guard runs BEFORE the write");

    const [fn] = await sql<{ prosecdef: boolean; provolatile: string; acl: string | null }[]>`
      select p.prosecdef, p.provolatile, array_to_string(p.proacl, ',') as acl
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname = 'apply_billing_event'`;
    assert(fn, "rf.apply_billing_event exists");
    assert(fn.prosecdef, "SECURITY DEFINER: rf_api holds no write privilege on either table");
    assert(
      (fn.acl ?? "").includes("rf_api=X"),
      `EXECUTE is granted to rf_api and to nobody else: ${fn.acl}`,
    );
    assert(
      !(fn.acl ?? "").includes("=X/") || !/(^|,)=X/.test(fn.acl ?? ""),
      `PUBLIC holds no EXECUTE — 0005's blanket grant ran before this function existed: ${fn.acl}`,
    );

    // The privilege picture 0005 drew, unchanged by 0013.
    const privs = await sql<{ table_name: string; privilege_type: string }[]>`
      select table_name, privilege_type from information_schema.table_privileges
      where grantee = 'rf_api'
        and table_name in ('subscriptions','billing_events','promo_codes','promo_redemptions')`;
    assertEquals(
      privs.filter((p) => p.table_name === "subscriptions").map((p) => p.privilege_type).sort(),
      ["SELECT"],
      "no INSERT, UPDATE or DELETE on subscriptions for the API role (CLAUDE.md rule 2's shape)",
    );
    for (const t of ["billing_events", "promo_codes", "promo_redemptions"]) {
      assertEquals(
        privs.filter((p) => p.table_name === t).map((p) => p.privilege_type),
        [],
        `rf_api has no privilege at all on ${t}`,
      );
    }
  },
});

Deno.test({
  name:
    "E-03-66 cross-tenant: a certified member of another tenant reads nothing of this one's subscription, and no role but the definer may write plan, status or the event log (03 §2.4 🔒)",
  ignore,
  async fn() {
    // t1 is on family; t2's member must not learn that.
    await apply({
      eventId: "e66_seed",
      action: "activate",
      tenant: fx.t1,
      at: T0,
      plan: "family",
      periodEnd: new Date(T0.getTime() + 30 * DAY),
      ref: "sub_t1",
      source: "razorpay",
    });

    const mine = await asApi(
      fx.owner,
      fx.dev.owner,
      (s) => s`select tenant_id, plan from subscriptions`,
    );
    assertEquals(mine.length, 1, "the owner sees exactly one subscription: their own tenant's");
    assertEquals(mine[0].tenant_id, fx.t1);
    assertEquals(mine[0].plan, "family");

    const theirs = await asApi(
      fx.outsider,
      fx.dev.outsider,
      (s) => s`select tenant_id, plan from subscriptions where tenant_id = ${fx.t1}`,
    );
    assertEquals(theirs.length, 0, "a certified device of another tenant reads nothing here");

    // Not a member of anything: no claims at all (the webhook's own connection shape).
    const anon = await asApi(null, null, (s) => s`select tenant_id from subscriptions`);
    assertEquals(anon.length, 0, "claimless rf_api reads no subscription row");

    // Writes: refused by privilege, not by policy — there is no grant to have a policy about.
    for (
      const q of [
        () =>
          asApi(fx.owner, fx.dev.owner, (s) => s`update subscriptions set plan = 'family_plus'`),
        () =>
          asApi(
            fx.owner,
            fx.dev.owner,
            (s) => s`delete from subscriptions where tenant_id = ${fx.t1}`,
          ),
        () =>
          asApi(
            fx.owner,
            fx.dev.owner,
            (s) => s`insert into subscriptions (tenant_id, plan) values (${fx.t2}, 'family_plus')`,
          ),
        () => asApi(fx.owner, fx.dev.owner, (s) => s`select * from billing_events`),
        () => asApi(fx.owner, fx.dev.owner, (s) => s`update billing_events set applied_at = null`),
        () => asApi(fx.owner, fx.dev.owner, (s) => s`delete from billing_events`),
        () => asApi(fx.owner, fx.dev.owner, (s) => s`select * from promo_codes`),
        () =>
          asApi(
            fx.owner,
            fx.dev.owner,
            (s) =>
              s`insert into promo_codes (code, max_redemptions, valid_from, valid_to)
              values ('FREE', 999, now(), now() + interval '1 year')`,
          ),
        () => asApi(fx.owner, fx.dev.owner, (s) => s`select * from promo_redemptions`),
      ]
    ) {
      assertEquals(await pgCode(q()), "42501", "insufficient_privilege");
    }
    assertEquals((await row(fx.t1)).plan, "family", "nothing above moved the plan");
    assertEquals((await row(fx.t2)).plan, "free");
  },
});

Deno.test({
  name:
    "E-03-67 dedupe + out-of-order (08 §4 🔒, ADR 2026-09-05g §9): a replayed event applies once and answers duplicate; an older event arriving after a newer one changes nothing yet is still recorded",
  ignore,
  async fn() {
    const end1 = new Date(T0.getTime() + 30 * DAY);
    const [a] = await apply({
      eventId: "e67_a",
      action: "activate",
      tenant: fx.t2,
      at: T0,
      plan: "personal",
      periodEnd: end1,
      ref: "sub_t2",
      source: "razorpay",
      original: "otx_1",
    });
    assertEquals([a.fresh, a.applied, a.outcome], [true, true, "activate"]);
    const s1 = await row(fx.t2);
    assertEquals(s1.plan, "personal");
    assertEquals(s1.status, "active");
    assertEquals((s1.current_period_end as Date).getTime(), end1.getTime());
    assertEquals(s1.source, "razorpay");
    assertEquals(s1.gateway, "razorpay");
    assertEquals(s1.gateway_ref, "sub_t2");
    assertEquals(s1.original_transaction_id, "otx_1");
    assert(
      (s1.updated_at as Date).getTime() > 0,
      "updated_at is 05 §5's meta cursor: the subscriptions_touch trigger moved it",
    );

    // Replay: same event id, a body that WOULD upgrade. Applies nothing at all.
    const [rep] = await apply({
      eventId: "e67_a",
      action: "activate",
      tenant: fx.t2,
      at: new Date(T0.getTime() + 5 * DAY),
      plan: "family_plus",
      ref: "sub_t2",
    });
    assertEquals([rep.fresh, rep.applied, rep.outcome], [false, false, "duplicate"]);
    assertEquals((await row(fx.t2)).plan, "personal");
    const [{ n }] = await sql<{ n: number }[]>`
      select count(*)::int as n from billing_events where event_id = 'e67_a'`;
    assertEquals(n, 1, "one row per event id — the idempotency key of 08 §4 🔒");

    // A newer event, then the stale retry that overtook it.
    const end2 = new Date(T0.getTime() + 60 * DAY);
    const [b] = await apply({
      eventId: "e67_b",
      action: "activate",
      tenant: fx.t2,
      at: new Date(T0.getTime() + 2 * DAY),
      plan: "family",
      periodEnd: end2,
      ref: "sub_t2",
    });
    assertEquals(b.applied, true);
    const before = await row(fx.t2);

    const [stale] = await apply({
      eventId: "e67_c",
      action: "activate",
      tenant: fx.t2,
      at: new Date(T0.getTime() + DAY), // OLDER than e67_b
      plan: "free", // would strip the tenant of the plan it just paid for
      periodEnd: new Date(T0.getTime() + 3 * DAY),
      ref: "sub_t2",
    });
    assertEquals([stale.fresh, stale.applied, stale.outcome], [true, false, "out_of_order"]);
    assertEquals(await row(fx.t2), before, "not one column of the subscription moved");
    const [rec] = await sql`select tenant_id, event_at, applied_at from billing_events
      where event_id = 'e67_c'`;
    assert(rec, "the stale event is RECORDED — that row is what the reconciliation poll reads");
    assertEquals(rec.applied_at, null);
    assertEquals(rec.tenant_id, fx.t2, "…and it says which subscription it was for");

    // An event at the SAME timestamp as the last applied is not newer, so it is not applied.
    const [tie] = await apply({
      eventId: "e67_d",
      action: "activate",
      tenant: fx.t2,
      at: new Date(T0.getTime() + 2 * DAY),
      plan: "free",
      ref: "sub_t2",
    });
    assertEquals(tie.outcome, "out_of_order");
    // No ordering key at all → the guard cannot run, so nothing is applied (ADR §9 is unconditional).
    const [noAt] = await apply({
      eventId: "e67_e",
      action: "activate",
      tenant: fx.t2,
      plan: "free",
      ref: "sub_t2",
    });
    assertEquals([noAt.fresh, noAt.applied, noAt.outcome], [true, false, "no_event_at"]);
    // An event naming no resolvable tenant is recorded and not applied.
    const [noTenant] = await apply({
      eventId: "e67_f",
      action: "activate",
      at: new Date(T0.getTime() + 9 * DAY),
      plan: "family_plus",
      ref: "sub_nobody",
    });
    assertEquals([noTenant.fresh, noTenant.applied, noTenant.outcome], [
      true,
      false,
      "unknown_tenant",
    ]);
    assertEquals(await row(fx.t2), before);
    // An action the state machine does not name is refused outright, not guessed at.
    assertEquals(
      await pgCode(
        apply({ eventId: "e67_g", action: "grant_free_forever", tenant: fx.t2, at: T0 }),
      ),
      "22023",
    );
  },
});

Deno.test({
  name:
    "E-03-68 dunning 🔒 (08 §3, ADR 2026-09-05g §4): a failed renewal sets status past_due, grace_kind 'dunning' and grace_until = period_end + 7 days, and touches nothing else",
  ignore,
  async fn() {
    const end = new Date(T0.getTime() + 30 * DAY);
    await sql`update subscriptions set seats_addon = 4, cancel_at_period_end = true,
      payer_user_id = ${fx.owner}, trial_end = ${new Date(T0.getTime() - DAY)}
      where tenant_id = ${fx.t1}`;
    const before = await row(fx.t1);
    const was = await stamp(fx.t1);
    assertEquals((before.current_period_end as Date).getTime(), end.getTime());

    const [d] = await apply({
      eventId: "e68_a",
      action: "dunning",
      type: "subscription.halted",
      tenant: fx.t1,
      at: new Date(T0.getTime() + 31 * DAY),
      ref: "sub_t1",
    });
    assertEquals([d.fresh, d.applied, d.outcome], [true, true, "dunning"]);
    const s = await row(fx.t1);
    assertEquals(s.status, "past_due");
    assertEquals(s.grace_kind, "dunning");
    assertEquals(
      (s.grace_until as Date).getTime(),
      end.getTime() + 7 * DAY,
      "7 days from period_end (08 §3 🔒) — not 7 days from the webhook's arrival",
    );
    for (
      const k of [
        "plan",
        "current_period_end",
        "gateway",
        "gateway_ref",
        "source",
        "original_transaction_id",
        "payer_user_id",
        "trial_end",
        "cancel_at_period_end",
        "seats_addon",
        "dispute_state",
      ]
    ) {
      assertEquals(String(s[k]), String(before[k]), `dunning must not touch ${k}`);
    }
    assert(
      await movedSince(fx.t1, was),
      "05 §5's cursor moved: a plan state a device cannot pull is a plan state that does not exist",
    );

    // A dunning event on a subscription with no period_end has nothing to measure from: recorded,
    // not applied, rather than an invented window (⚠️ SPEC in 0013 — 08 §3 does not define it).
    await sql`insert into tenants (id, type) values (gen_random_uuid(), 'family')`;
    const [t3] = await sql`select id from tenants order by created_at desc limit 1`;
    await sql`insert into subscriptions (tenant_id) values (${t3.id})`;
    const [none] = await apply({
      eventId: "e68_b",
      action: "dunning",
      tenant: t3.id,
      at: T0,
    });
    assertEquals([none.fresh, none.applied, none.outcome], [true, false, "no_period_end"]);
    const s3 = await row(t3.id);
    assertEquals(s3.status, "active");
    assertEquals(s3.grace_kind, null);
    assertEquals(s3.grace_until, null);
  },
});

Deno.test({
  name:
    "E-03-69 refunds 🔒 (ADR 2026-09-05g §11): refund or chargeback ends entitlement now, clears BOTH grace columns, records dispute_state — and deletes no row in any table",
  ignore,
  async fn() {
    const counts = async () => {
      const [c] = await sql<{ s: number; b: number; e: number }[]>`
        select (select count(*) from subscriptions)::int as s,
               (select count(*) from billing_events)::int as b,
               (select count(*) from envelopes)::int as e`;
      return c;
    };
    const before0 = await counts();
    const before = await row(fx.t1);
    assertEquals(before.grace_kind, "dunning", "we start from the dunning state E-03-68 left");

    const [r1] = await apply({
      eventId: "e69_a",
      action: "end_now",
      type: "refund.processed",
      tenant: fx.t1,
      at: new Date(T0.getTime() + 32 * DAY),
      dispute: "refunded",
      ref: "sub_t1",
    });
    assertEquals([r1.fresh, r1.applied, r1.outcome], [true, true, "end_now"]);
    const s = await row(fx.t1);
    assertEquals(s.status, "expired", "entitlement ends NOW");
    assertEquals(s.grace_until, null, "no grace survives a refund");
    assertEquals(s.grace_kind, null);
    assertEquals(s.dispute_state, "refunded");
    // "data untouched": what the tenant bought is still on the row, so 08 §1.4's read-only + export
    // forever has something to read.
    for (
      const k of [
        "plan",
        "current_period_end",
        "gateway",
        "gateway_ref",
        "source",
        "payer_user_id",
        "seats_addon",
        "trial_end",
      ]
    ) {
      assertEquals(String(s[k]), String(before[k]), `end_now must not touch ${k}`);
    }

    // A chargeback on the SAME subscription, later: dispute_state moves, still nothing deleted.
    const [r2] = await apply({
      eventId: "e69_b",
      action: "end_now",
      type: "payment.dispute.lost",
      tenant: fx.t1,
      at: new Date(T0.getTime() + 33 * DAY),
      dispute: "chargeback",
      ref: "sub_t1",
    });
    assertEquals(r2.applied, true);
    assertEquals((await row(fx.t1)).dispute_state, "chargeback");

    const after = await counts();
    assertEquals(after.s, before0.s, "no subscription row deleted");
    assertEquals(
      after.e,
      before0.e,
      "no envelope row deleted — the ledger is not billing's to touch",
    );
    assertEquals(after.b, before0.b + 2, "two events recorded, none removed");
  },
});

Deno.test({
  name:
    "E-03-70 the event log is append-only and the apply path is content-blind: only applied_at may ever change on a recorded event, it is set once, DELETE is refused for every role, and no statement in rf.apply_billing_event reads envelopes (08 §5, 06 §10 🔒, CLAUDE.md rule 2)",
  ignore,
  async fn() {
    // The guard binds the TABLE OWNER too — this connection is the superuser that ran the
    // migrations, i.e. the most privileged reach anything in this repo has.
    assertEquals(
      await pgCode(sql`update billing_events set type = 'subscription.activated'
        where event_id = 'e69_a'`),
      "42501",
    );
    assertEquals(
      await pgCode(sql`update billing_events set payload_hash = ${bytes(32, 9)}
        where event_id = 'e69_a'`),
      "42501",
    );
    assertEquals(
      await pgCode(sql`update billing_events set tenant_id = ${fx.t2} where event_id = 'e69_a'`),
      "42501",
    );
    assertEquals(
      await pgCode(sql`update billing_events set event_at = now() where event_id = 'e69_a'`),
      "42501",
    );
    // applied_at is set once and never moved or cleared: un-applying an event would let the next
    // delivery of an OLDER event pass the out-of-order guard.
    assertEquals(
      await pgCode(sql`update billing_events set applied_at = null where event_id = 'e69_a'`),
      "42501",
    );
    assertEquals(
      await pgCode(sql`update billing_events set applied_at = now() where event_id = 'e69_a'`),
      "42501",
    );
    assertEquals(await pgCode(sql`delete from billing_events where event_id = 'e69_a'`), "42501");
    // …and the one legal transition still works: an unapplied row may be marked applied.
    assertEquals(
      await pgCode(sql`update billing_events set applied_at = now() where event_id = 'e67_c'`),
      "ok",
    );
    await sql`update billing_events set applied_at = null where event_id = 'zzz_none'`; // no rows: fine

    // Content-blindness, read off the function's own source rather than inferred from a row count.
    const [src] = await sql<{ prosrc: string }[]>`
      select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname = 'apply_billing_event'`;
    for (const forbidden of ["envelopes", "blob", "attachments", "signed_records", "book_usage"]) {
      assert(
        !new RegExp(`\\b${forbidden}\\b`).test(src.prosrc),
        `the apply path must not name ${forbidden}: 06 §10 🔒 forbids a billing path that counts, sums or gates on envelope contents`,
      );
    }
    const tables = [...src.prosrc.matchAll(/\b(?:from|into|update)\s+(\w+)/gi)]
      .map((m) => m[1].toLowerCase())
      .filter((t) => !["query", "v_last", "v_sub", "v_tenant", "v_base"].includes(t));
    assertEquals(
      [...new Set(tables)].sort(),
      ["billing_events", "subscriptions"],
      "two tables, both billing's own",
    );

    await sql.end();
  },
});
