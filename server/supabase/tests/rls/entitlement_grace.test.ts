// The PgStore half of ADR 2026-09-24b §6 🔒 (amending ADR 2026-09-05g §1 and 08 §3): the
// entitlement token carries `grace_until`, null unless `grace_kind = dunning`, in which case it is
// `subscriptions.grace_until` — the date 0013's `rf.apply_billing_event` writes on a dunning event.
//
// functions/_tests/entitlement_token.test.ts proves the mint over the MemStore. This file proves
// the thing the MemStore cannot: that the REAL database's column reaches the mint — PgStore's
// `entitlementStates()` selects it under 0005's RLS, as rf_api with the caller's claims — and that
// the value it reaches is the one 0013 wrote, moved by the real apply path, not a fixture.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-24b-2 (the database half) and E-05-15 (the database half of ADR 2026-09-24b §7 (a): a
// lapse that 0013's real `end_now` produces on a row with no current_period_end).
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";
import { entitlementFor } from "../../functions/_shared/entitlement.ts";
import { PlanCatalogue } from "../../functions/_shared/registry.ts";
import { PgStore } from "../../functions/_shared/store_pg.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — entitlement_grace.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP entitlement_grace.test.ts: ${why}`);
}
const ignore = !url;

const DAY = 86400e3;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

Deno.test({
  name:
    "E-24b-2 PgStore reads subscriptions.grace_until as 0013's apply path wrote it: a dunning event puts period_end + 7 d into the state and the minted payload's grace_until, an activate clears it to null, and another tenant's certified device never receives the date",
  ignore,
  async fn() {
    const sql = postgres(url!, { max: 1, onnotice: () => {} });
    const store = new PgStore(url!);
    try {
      const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
      const [t2] = await sql`insert into tenants (type) values ('family') returning id`;
      const mkUser = async () =>
        (await sql`insert into users (phone_hmac, phone_ct)
          values (${rand(32)}, ${rand(40)}) returning id`)[0].id as string;
      const owner = await mkUser(), outsider = await mkUser();
      const mkDev = async (user: string) =>
        (await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
          values (gen_random_uuid(), ${user}, ${rand(32)}, ${rand(32)}, 'certified')
          returning id`)[0].id as string;
      const ownerDev = await mkDev(owner), outsiderDev = await mkDev(outsider);
      await sql`insert into memberships (tenant_id, user_id, status)
        values (${t1.id}, ${owner}, 'active'), (${t2.id}, ${outsider}, 'active')`;
      const periodEnd = new Date(Date.UTC(2026, 8, 20, 0, 0, 0));
      const ref = `sub_${crypto.randomUUID()}`;
      await sql`insert into subscriptions (tenant_id, plan, status, current_period_end, gateway,
          gateway_ref)
        values (${t1.id}, 'family', 'active', ${periodEnd}, 'razorpay', ${ref}),
               (${t2.id}, 'free', 'active', null, null, null)`;

      const apply = (action: string, at: Date, pe: Date | null) =>
        sql.begin(async (s) => {
          await s`set local role rf_api`;
          await s`select rf.set_claims(null::uuid, null::uuid)`;
          return await s`select * from rf.apply_billing_event(
            ${crypto.randomUUID()}, 'razorpay', 'subscription.test', ${rand(32)}::bytea,
            ${action}, null::uuid, ${at}::timestamptz, null::text, ${pe}::timestamptz,
            ${ref}::text, null::text, null::text, null::text)`;
        });
      const states = (user: string, device: string) =>
        store.withClaims({ user_id: user, device_id: device }, (tx) => tx.entitlementStates());
      // The REAL catalogue (0018), read through rf_api exactly as sync-meta reads it.
      const catalogue = new PlanCatalogue(
        await store.withClaims({ user_id: owner, device_id: ownerDev }, (tx) => tx.planCatalogue()),
      );

      // Before any dunning: the column is null and so is the token's field.
      let [s] = await states(owner, ownerDev);
      assertEquals(s.tenant_id, t1.id);
      assertEquals(s.grace_kind, null);
      assertEquals(s.grace_until, null, "the state carries the column even when it is null");
      assertEquals(entitlementFor(s, catalogue, new Date()).grace_until, null);

      // A failed renewal, through the real apply path.
      const [dun] = await apply("dunning", new Date(Date.UTC(2026, 8, 21)), periodEnd);
      assertEquals(dun.outcome, "dunning");
      assertEquals(dun.applied, true);
      [s] = await states(owner, ownerDev);
      assertEquals(s.grace_kind, "dunning");
      assert(s.grace_until instanceof Date, "PgStore selects subscriptions.grace_until");
      assertEquals(
        s.grace_until!.getTime(),
        periodEnd.getTime() + 7 * DAY,
        "0013 writes the gateway default, period_end + 7 d",
      );
      const now = new Date(Date.UTC(2026, 8, 22));
      const p = entitlementFor(s, catalogue, now);
      assertEquals(p.grace_kind, "dunning");
      assertEquals(
        p.grace_until,
        s.grace_until!.getTime(),
        "the token declares the column's date (ADR 2026-09-24b §6 🔒)",
      );
      assertEquals(p.period_end, periodEnd.getTime(), "period_end is unchanged by dunning");

      // The outsider's certified device reads its own tenant's state and never t1's date.
      const theirs = await states(outsider, outsiderDev);
      assertEquals(theirs.map((x) => x.tenant_id), [t2.id]);
      assertEquals(theirs[0].grace_until, null);

      // Renewal succeeds: 0013 clears both, and the token says so.
      const [act] = await apply(
        "activate",
        new Date(Date.UTC(2026, 8, 23)),
        new Date(periodEnd.getTime() + 365 * DAY),
      );
      assertEquals(act.outcome, "activate");
      [s] = await states(owner, ownerDev);
      assertEquals(s.grace_kind, null);
      assertEquals(s.grace_until, null, "an activate clears the grace date");
      assertEquals(entitlementFor(s, catalogue, now).grace_until, null);
    } finally {
      await store.end();
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-05-15 PgStore: a trial row ended by 0013's end_now lapses with current_period_end still NULL, and the mint clamps period_end to iat anyway — the row keeps its plan and reads read-only, never unbounded (08 §3 🔒 'lapsed ⇒ period_end = iat', ADR 2026-09-24b §7 (a) 🔒)",
  ignore,
  async fn() {
    const sql = postgres(url!, { max: 1, onnotice: () => {} });
    const store = new PgStore(url!);
    try {
      const [t] = await sql`insert into tenants (type) values ('family') returning id`;
      const [u] = await sql`insert into users (phone_hmac, phone_ct)
        values (${rand(32)}, ${rand(40)}) returning id`;
      const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
        values (gen_random_uuid(), ${u.id}, ${rand(32)}, ${rand(32)}, 'certified') returning id`;
      await sql`insert into memberships (tenant_id, user_id, status)
        values (${t.id}, ${u.id}, 'active')`;
      const ref = `sub_${crypto.randomUUID()}`;
      const trialEnd = new Date(Date.now() + 20 * DAY);
      await sql`insert into subscriptions (tenant_id, plan, status, current_period_end, trial_end,
          gateway, gateway_ref)
        values (${t.id}, 'family', 'trial', null, ${trialEnd}, 'razorpay', ${ref})`;

      // A chargeback on the trial's card, through the real apply path.
      const [ended] = await sql.begin(async (s) => {
        await s`set local role rf_api`;
        await s`select rf.set_claims(null::uuid, null::uuid)`;
        return await s`select * from rf.apply_billing_event(
          ${crypto.randomUUID()}, 'razorpay', 'payment.dispute.lost', ${rand(32)}::bytea,
          'end_now', null::uuid, ${new Date()}::timestamptz, null::text, null::timestamptz,
          ${ref}::text, null::text, null::text, 'chargeback'::text)`;
      });
      assertEquals(ended.outcome, "end_now");
      assertEquals(ended.applied, true);

      const [st] = await store.withClaims(
        { user_id: u.id, device_id: d.id },
        (tx) => tx.entitlementStates(),
      );
      assertEquals(st.tenant_id, t.id);
      assertEquals(st.status, "expired", "0013's end_now sets the status");
      assertEquals(st.current_period_end, null, "…and never sets a period the row did not have");

      const now = new Date();
      const catalogue = new PlanCatalogue(
        await store.withClaims({ user_id: u.id, device_id: d.id }, (tx) => tx.planCatalogue()),
      );
      const p = entitlementFor(st, catalogue, now);
      assertEquals(p.plan, "family", "lapsed keeps its plan (ADR 2026-09-05g §5 🔒)");
      assertEquals(
        p.period_end,
        now.getTime(),
        "period_end = iat, not null and not the trial's end",
      );
      assertEquals(p.period_end, p.iat);
      assertEquals(p.grace_kind, null);
      assertEquals(p.grace_until, null);
    } finally {
      await store.end();
      await sql.end();
    }
  },
});
