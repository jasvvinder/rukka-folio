// Hostile-query suite for the plan catalogue — migration 0018, against ADR 2026-09-25 §5–§6 (the
// catalogue, its rules, the trial), 03 §2.4 🔒 (subscriptions), ADR 2026-09-05d §2 🔒 and CLAUDE.md
// rules 1, 2 and 4. functions/_tests/plan_catalogue.test.ts proves the same rules over the
// MemStore; this file proves what the fake cannot — that the REAL database refuses what it must.
//
// What an attacker wants from this table, and what each test denies:
//
//   * A CHEAPER PLAN or A BIGGER ONE — writing the catalogue. rf_api holds SELECT and nothing else,
//     and rf_maintenance holds nothing; INSERT, UPDATE and DELETE are refused by privilege
//     (E-03-76). Until the console exists, a catalogue change is a migration (ADR 25 §6).
//   * A GATE ON A NEVER-RESTRICTED FEATURE, a free trial on a paid price, a Free plan with PDF
//     output, a second popular plan — the schema itself refuses each (E-03-77, G-25-1, G-25-2).
//   * ANOTHER TENANT'S DATA through the catalogue read — it has none to give: no tenant, user or
//     device column exists on it, and a claims-less transaction reads nothing (E-03-76).
//   * A TRIAL ON SOMEONE ELSE'S TENANT, or a second trial for oneself — rf.start_trial checks the
//     caller is a certified admin of THAT tenant and that the person never trialled (E-03-78,
//     G-25-3).
//   * AN ACTIVATION TO A PLAN THAT DOES NOT EXIST — recorded, never applied (E-03-79).
//   * DRIFT between the MemStore's seed and the migration's (E-25-3), and a data change that does
//     not reach what is enforced (G-25-4).
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly. Every catalogue
// edit below is either inside a transaction that is rolled back or on a test-only plan row that is
// removed afterwards, so no other file ever sees an edited seed.
//   * A RENAME THAT MOVED MORE THAN THE NAME — 0029 renames `shop` to Business Lite (ADR 2026-10-04c
//     §3); its id and every number stay 0018's (E-04c-1).
// Ids E-03-75 … E-03-79, E-25-3, G-25-1, G-25-2, G-25-3, G-25-4, E-04c-1 (the database halves).
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";
import { hex } from "../../functions/_shared/bytes.ts";
import type { Deps } from "../../functions/_shared/deps.ts";
import { entitlementFor, needsMint } from "../../functions/_shared/entitlement.ts";
import { FakeOtpProvider } from "../../functions/_shared/otp/provider.ts";
import { PlanCatalogue } from "../../functions/_shared/registry.ts";
import { hmacSha256AnyKey, signEntitlementToken } from "../../functions/_shared/sodium.ts";
import { CATALOGUE_SEED } from "../../functions/_shared/store_mem.ts";
import { handler as webhook } from "../../functions/billing-webhook/index.ts";
import { apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — plan_catalogue.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP plan_catalogue.test.ts: ${why}`);
}
const ignore = !url;

const DAY = 86400e3;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));
let sql: postgres.Sql;

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
/** Run `fn` as the schema owner inside a transaction that is ALWAYS rolled back. */
const ROLLBACK = new Error("rollback");
async function rolledBack(fn: (s: postgres.TransactionSql) => Promise<void>): Promise<void> {
  try {
    await sql.begin(async (s) => {
      await fn(s);
      throw ROLLBACK;
    });
  } catch (e) {
    if (e !== ROLLBACK) throw e;
  }
}

// ---------------------------------------------------------------- fixtures
async function mkUser(): Promise<string> {
  const [u] = await sql`insert into users (phone_hmac, phone_ct)
    values (${rand(32)}, ${rand(40)}) returning id`;
  return u.id as string;
}
async function mkDev(user: string, status = "certified"): Promise<string> {
  const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
    values (gen_random_uuid(), ${user}, ${rand(32)}, ${rand(32)}, ${status}) returning id`;
  return d.id as string;
}
async function mkTenant(type: string): Promise<string> {
  const [t] = await sql`insert into tenants (type) values (${type}) returning id`;
  return t.id as string;
}
/** Active membership (founder, or after a signed ceremony — 0006/0008's guard) + a role on a book. */
async function join(tenant: string, user: string, role: string | null) {
  const [{ n }] = await sql`select count(*)::int as n from memberships where tenant_id = ${tenant}`;
  if (n > 0) {
    const [founder] = await sql`select m.user_id, d.id as device from memberships m
      join devices d on d.user_id = m.user_id where m.tenant_id = ${tenant} limit 1`;
    const rec = crypto.randomUUID();
    await sql`insert into signed_records
      (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
      values (${rec}, 1, ${tenant}, 'verification_event', '{}'::jsonb, ${rand(8)},
              ${founder.device}, ${rand(64)}, 1)`;
    await sql`insert into verification_events
      (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${tenant}, ${user}, ${founder.user_id}, 'qr_in_person', 'verified', ${rec})`;
  }
  await sql`insert into memberships (tenant_id, user_id, status) values (${tenant}, ${user}, 'active')`;
  if (role) {
    const [b] = await sql`insert into books (id, tenant_id, type)
      values (gen_random_uuid(), ${tenant}, 'joint') returning id`;
    await sql`insert into book_roles (book_id, user_id, role) values (${b.id}, ${user}, ${role})`;
  }
}
interface Person {
  user: string;
  dev: string;
}
async function person(tenant: string, role: string | null, status = "certified"): Promise<Person> {
  const user = await mkUser();
  const dev = await mkDev(user, status);
  await join(tenant, user, role);
  return { user, dev };
}
const startTrial = (p: Person | null, tenant: string, entity: string) =>
  asApi(
    p?.user ?? null,
    p?.dev ?? null,
    (s) => s`select * from rf.start_trial(${tenant}::uuid, ${entity}::text)`,
  );
const subOf = async (tenant: string) =>
  (await sql`select * from subscriptions where tenant_id = ${tenant}`)[0] ?? null;
const consumed = async (user: string) =>
  (await sql`select trial_consumed_at from users where id = ${user}`)[0].trial_consumed_at;

function setup() {
  sql = postgres(url!, { max: 1, onnotice: () => {} });
}

Deno.test({
  name:
    "E-03-75 0018's shape: plan_catalogue holds integer paise and integer limits (BIGINT, never float), RLS is on and FORCEd, rf_api's privilege is SELECT only, no other role holds any, subscriptions.plan is a foreign key onto it, rf.start_trial is SECURITY DEFINER for rf_api alone — and rf_api still has no UPDATE/DELETE on envelopes (CLAUDE.md rule 2)",
  ignore,
  async fn() {
    setup();
    try {
      const cols = new Map(
        (await sql`select column_name, data_type from information_schema.columns
          where table_schema = 'public' and table_name = 'plan_catalogue'`)
          .map((c) => [c.column_name as string, c.data_type as string]),
      );
      for (
        const c of [
          "price_yearly_paise",
          "price_monthly_paise",
          "envelopes_per_book",
          "tenant_bytes",
          "attachment_bytes",
        ]
      ) assertEquals(cols.get(c), "bigint", `${c} is BIGINT (CLAUDE.md rule 1)`);
      for (const c of ["members", "business_books", "devices"]) {
        assertEquals(cols.get(c), "integer", c);
      }
      assertEquals(cols.get("features"), "ARRAY");
      for (const c of ["tenant_id", "user_id", "device_id", "book_id", "phone_hmac"]) {
        assert(!cols.has(c), `the catalogue names no ${c}: it is not tenant data`);
      }
      assert(![...cols.values()].some((t) => /real|double|numeric|money/.test(t)), "no float");

      const [rls] = await sql`select relrowsecurity, relforcerowsecurity from pg_class
        where oid = 'public.plan_catalogue'::regclass`;
      assertEquals([rls.relrowsecurity, rls.relforcerowsecurity], [true, true]);

      const privs =
        await sql`select grantee, privilege_type from information_schema.role_table_grants
        where table_schema = 'public' and table_name = 'plan_catalogue'
          and grantee <> current_user order by grantee, privilege_type`;
      assertEquals(
        privs.map((p) => `${p.grantee}:${p.privilege_type}`),
        ["rf_api:SELECT"],
        "rf_api reads; nobody else holds anything (no console role pre-granted)",
      );

      const fk = await sql`select conname, confrelid::regclass::text as ref from pg_constraint
        where conrelid = 'public.subscriptions'::regclass and contype in ('f', 'c')
          and pg_get_constraintdef(oid) like '%plan%'`;
      assertEquals(fk.map((c) => `${c.conname}->${c.ref}`), [
        "subscriptions_plan_fk->plan_catalogue",
      ]);

      const [fn] = await sql`select prosecdef, proconfig from pg_proc
        where oid = 'rf.start_trial(uuid, text)'::regprocedure`;
      assertEquals(fn.prosecdef, true);
      assert((fn.proconfig as string[]).some((c) => c.startsWith("search_path=")), "pinned path");
      const [g] = await sql`select
        has_function_privilege('rf_api', 'rf.start_trial(uuid, text)', 'execute') as api,
        has_function_privilege('rf_maintenance', 'rf.start_trial(uuid, text)', 'execute') as maint,
        has_table_privilege('rf_api', 'public.envelopes', 'update') as env_upd,
        has_table_privilege('rf_api', 'public.envelopes', 'delete') as env_del,
        has_table_privilege('rf_api', 'public.subscriptions', 'update') as sub_upd,
        has_column_privilege('rf_api', 'public.users', 'trial_consumed_at', 'update') as trial_upd`;
      assertEquals(
        [g.api, g.maint, g.env_upd, g.env_del, g.sub_upd, g.trial_upd],
        [true, false, false, false, false, false],
      );
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-03-76 hostile queries on plan_catalogue: a certified tenant admin on rf_api cannot INSERT, UPDATE or DELETE a plan (privilege, not policy); rf_maintenance cannot even read it; a claims-less rf_api transaction reads nothing; an authenticated caller — certified or not — reads the ten public rows and no tenant's data",
  ignore,
  async fn() {
    setup();
    try {
      const t = await mkTenant("family");
      const admin = await person(t, "admin");
      const pending = await mkUser();
      const pendingDev = await mkDev(pending, "registered");

      const writes: [string, (s: postgres.TransactionSql) => Promise<unknown>][] = [
        ["insert", (s) =>
          s`insert into plan_catalogue (id, entity_type, name, members,
            business_books, devices, envelopes_per_book, tenant_bytes, attachment_bytes,
            price_yearly_paise, price_monthly_paise)
          values ('cheap', 'family', 'Cheap', 99, 99, 99, 1000000, 1000000, 1000000, 0, 0)`],
        ["update price", (s) =>
          s`update plan_catalogue set price_yearly_paise = 0,
            price_monthly_paise = 0 where id = 'family_plus'`],
        ["update limits", (s) => s`update plan_catalogue set members = 1000 where id = 'free'`],
        ["update features", (s) =>
          s`update plan_catalogue
            set features = '{statement_import,pdf_output}' where id = 'free'`],
        ["delete", (s) => s`delete from plan_catalogue where id = 'family'`],
      ];
      for (const [what, q] of writes) {
        const e = await pgErr(asApi(admin.user, admin.dev, q));
        assertEquals(e.code, "42501", `rf_api ${what} must be refused by privilege: ${e.message}`);
      }
      const m = await pgErr(
        asRole("rf_maintenance", null, null, (s) => s`select * from plan_catalogue`),
      );
      assertEquals(m.code, "42501", "rf_maintenance has no business with prices");

      const none = await asApi(null, null, (s) => s`select id from plan_catalogue`);
      assertEquals(none.length, 0, "no claims, no catalogue");
      const mine = await asApi(admin.user, admin.dev, (s) => s`select * from plan_catalogue`);
      assertEquals(mine.length, 10);
      const theirs = await asApi(pending, pendingDev, (s) => s`select * from plan_catalogue`);
      assertEquals(
        theirs.length,
        10,
        "public prices for a phone not yet certified (not tenant data)",
      );
      const text = JSON.stringify(mine, (_k, v) => typeof v === "bigint" ? String(v) : v);
      for (const id of [t, admin.user, admin.dev]) assert(!text.includes(id));

      const [row] = await sql`select price_yearly_paise, members from plan_catalogue
        where id = 'family_plus'`;
      assertEquals(String(row.price_yearly_paise), "599900", "nothing moved");
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-03-77 the catalogue's RULES are schema facts (ADR 2026-09-25 §5): monthly is ten months' price for twelve, one popular plan per entity type, no negative price or out-of-range limit, a plan in use cannot be deleted, an id cannot be renamed, a subscription cannot name a plan that does not exist — and the Free floor cannot be deleted, priced, moved or given an extra",
  ignore,
  async fn() {
    setup();
    try {
      const refuse = async (
        what: string,
        code: string,
        q: (s: postgres.TransactionSql) => Promise<unknown>,
      ) => {
        let got = "ok";
        await rolledBack(async (s) => {
          got = (await pgErr(s.savepoint((sp) => q(sp)))).code;
        });
        assertEquals(got, code, what);
      };
      const ins = (s: postgres.TransactionSql, over: Record<string, unknown>) => {
        const row = {
          id: "zz_rule",
          entity_type: "family",
          name: "Rule",
          members: 5,
          business_books: 2,
          devices: 5,
          envelopes_per_book: 1000,
          tenant_bytes: 1000,
          attachment_bytes: 1000,
          features: "{}",
          price_yearly_paise: 100000,
          price_monthly_paise: 10000,
          popular: false,
          ...over,
        };
        return s`insert into plan_catalogue ${s(row)}`;
      };
      await refuse("monthly ≠ yearly / 10", "23514", (s) => ins(s, { price_monthly_paise: 12000 }));
      await refuse(
        "negative price",
        "23514",
        (s) => ins(s, { price_yearly_paise: -10, price_monthly_paise: -1 }),
      );
      await refuse("a limit below NO_CAP", "23514", (s) => ins(s, { business_books: -2 }));
      await refuse("zero members", "23514", (s) => ins(s, { members: 0 }));
      await refuse(
        "bytes beyond 2^53 − 1",
        "23514",
        (s) => ins(s, { tenant_bytes: "9007199254740992" }),
      );
      await refuse("a malformed id", "23514", (s) => ins(s, { id: "Family Plus" }));
      await refuse(
        "an entity type S0.3 does not have",
        "23514",
        (s) => ins(s, { entity_type: "joint_family" }),
      );
      await refuse("a second popular plan for family", "23505", (s) => ins(s, { popular: true }));
      await refuse(
        "renaming an id",
        "42501",
        (s) => s`update plan_catalogue set id = 'fam' where id = 'family'`,
      );
      await refuse(
        "deleting Free",
        "42501",
        (s) => s`delete from plan_catalogue where id = 'free'`,
      );
      await refuse(
        "pricing Free",
        "42501",
        (s) =>
          s`update plan_catalogue set price_yearly_paise = 1000, price_monthly_paise = 100
          where id = 'free'`,
      );
      await refuse(
        "moving Free off Individual",
        "42501",
        (s) => s`update plan_catalogue set entity_type = 'family' where id = 'free'`,
      );
      await refuse(
        "giving Free a book",
        "42501",
        (s) => s`update plan_catalogue set business_books = 1 where id = 'free'`,
      );

      const t = await mkTenant("family");
      await sql`insert into subscriptions (tenant_id, plan) values (${t}, 'family_lite')`;
      await refuse(
        "deleting a plan a subscription names",
        "23503",
        (s) => s`delete from plan_catalogue where id = 'family_lite'`,
      );
      await refuse(
        "a subscription naming an unknown plan",
        "23503",
        (s) => s`update subscriptions set plan = 'platinum' where tenant_id = ${t}`,
      );
      // …and the old four-name CHECK is gone: a Business plan can now be stored at all.
      await rolledBack(async (s) => {
        await s`update subscriptions set plan = 'business' where tenant_id = ${t}`;
      });
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "G-25-1 (database half) book-flow features are never gated: the only extras a catalogue row can include are statement_import and pdf_output — a row gating CSV export, month close, search or reports is refused by the schema, and no seeded row holds anything else (ADR 2026-09-25 §5 🔒)",
  ignore,
  async fn() {
    setup();
    try {
      for (
        const f of ["csv_export", "xlsx_export", "month_close", "year_close", "search", "reports"]
      ) {
        let code = "ok";
        await rolledBack(async (s) => {
          code = (await pgErr(s.savepoint((sp) =>
            sp`update plan_catalogue set features = array['pdf_output', ${f}]::text[]
              where id = 'family'`
          ))).code;
        });
        assertEquals(code, "23514", `a plan gating ${f}`);
      }
      const held = await sql`select distinct unnest(features) as f from plan_catalogue order by f`;
      assertEquals(held.map((r) => r.f), ["pdf_output", "statement_import"]);
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "G-25-2 (database half) Free is Individual's permanent floor — ₹0, the personal book only, no statement import and no PDF output — and neither Family, Business nor Trust has a Free plan (ADR 2026-09-25 §5 🔒)",
  ignore,
  async fn() {
    setup();
    try {
      const [free] = await sql`select * from plan_catalogue where id = 'free'`;
      assertEquals(free.entity_type, "individual");
      assertEquals([String(free.price_yearly_paise), String(free.price_monthly_paise)], ["0", "0"]);
      assertEquals(free.features, []);
      assertEquals(free.business_books, 0);
      const zero = await sql`select id from plan_catalogue
        where entity_type <> 'individual' and price_yearly_paise = 0`;
      assertEquals(zero.length, 0);
      const noExtras = await sql`select id from plan_catalogue
        where cardinality(features) = 0 order by id`;
      assertEquals(noExtras.map((r) => r.id), ["family_lite", "free", "shop"]);
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-03-78 hostile rf.start_trial: an admin of ANOTHER tenant, a plain member, an admin on an uncertified device and a claims-less caller are all refused `not_admin` and write nothing — no subscription row, no trial_consumed_at",
  ignore,
  async fn() {
    setup();
    try {
      const t = await mkTenant("family");
      const admin = await person(t, "admin");
      const member = await person(t, "member");
      const other = await mkTenant("family");
      const outsider = await person(other, "admin");
      const lone = await mkTenant("family");
      const uncertified = await person(lone, "admin", "registered");

      for (
        const [who, p, tenant] of [
          ["outsider", outsider, t],
          ["member", member, t],
          ["uncertified admin", uncertified, lone],
          ["no claims", null, t],
        ] as const
      ) {
        const e = await pgErr(startTrial(p, tenant, "family"));
        assertEquals([e.code, e.message], ["42501", "not_admin"], who);
      }
      assertEquals(await subOf(t), null, "nothing was written for the tenant");
      assertEquals(await subOf(lone), null);
      for (const p of [outsider, member, uncertified]) assertEquals(await consumed(p.user), null);
      assertEquals(await consumed(admin.user), null);
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "G-25-3 (database half) rf.start_trial runs 30 days on the entity type's POPULAR plan, once per person — refused for Individual, refused when trust and organization disagree, refused a second time for the same person and on a tenant that already had one; moving the popular flag moves the next trial (ADR 2026-09-25 §5 🔒)",
  ignore,
  async fn() {
    setup();
    try {
      const fam = await mkTenant("family");
      const karta = await person(fam, "admin");
      const biz = await mkTenant("business_group");
      await join(biz, karta.user, "admin");
      const org = await mkTenant("organization");
      const treasurer = await person(org, "admin");

      const code = async (p: Person, t: string, e: string) => {
        const x = await pgErr(startTrial(p, t, e));
        return x.code === "ok" ? "ok" : x.message;
      };
      assertEquals(await code(karta, fam, "individual"), "no_trial");
      assertEquals(await code(karta, fam, "trust"), "entity_mismatch");
      assertEquals(await code(treasurer, org, "family"), "entity_mismatch");
      assertEquals(await consumed(karta.user), null, "a refusal spends nothing");

      const before = Date.now();
      const [r] = await startTrial(karta, fam, "family");
      assertEquals(r.trial_plan, "family", "Family is the family type's popular plan");
      const end = (r.trial_ends_at as Date).getTime();
      assert(Math.abs(end - (before + 30 * DAY)) < 60_000, "30 days from now");
      const sub = await subOf(fam);
      assertEquals([sub.plan, sub.status], ["family", "trial"]);
      assertEquals((sub.trial_end as Date).getTime(), end);
      assert(await consumed(karta.user), "users.trial_consumed_at set in the same transaction");

      assertEquals(await code(karta, biz, "business"), "trial_consumed", "once per PERSON");
      assertEquals(await subOf(biz), null);

      const second = await person(fam, "admin");
      assertEquals(await code(second, fam, "family"), "trial_unavailable", "once per tenant");
      assertEquals(await consumed(second.user), null);

      // Moving the popular flag is a data change; the next trial follows it. Rolled back, so no
      // other test ever sees trust_plus as popular.
      let moved = "";
      await rolledBack(async (s) => {
        await s`update plan_catalogue set popular = false where id = 'trust'`;
        await s`update plan_catalogue set popular = true where id = 'trust_plus'`;
        await s`set local role rf_api`;
        await s`select rf.set_claims(${treasurer.user}::uuid, ${treasurer.dev}::uuid)`;
        const [x] = await s`select * from rf.start_trial(${org}::uuid, 'trust')`;
        moved = x.trial_plan as string;
      });
      assertEquals(moved, "trust_plus");
      const [t2] = await startTrial(treasurer, org, "trust");
      assertEquals(t2.trial_plan, "trust", "and with the seed as shipped, Trust's is `trust`");
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-03-79 an activation naming a plan the catalogue does not hold is RECORDED, never applied (`unknown_plan`) — and an activation to a new catalogue id (business) applies, which 0013's four-name world could not",
  ignore,
  async fn() {
    setup();
    try {
      const t = await mkTenant("business_group");
      const ref = `sub_${crypto.randomUUID()}`;
      await sql`insert into subscriptions (tenant_id, plan, gateway, gateway_ref)
        values (${t}, 'free', 'razorpay', ${ref})`;
      const apply = (id: string, plan: string, at: Date) =>
        asApi(
          null,
          null,
          (s) =>
            s`select * from rf.apply_billing_event(${id}, 'razorpay', 'subscription.activated',
            ${rand(32)}::bytea, 'activate', null::uuid, ${at}::timestamptz, ${plan}::text,
            ${new Date(Date.now() + 365 * DAY)}::timestamptz, ${ref}::text, 'razorpay'::text,
            null::text, null::text)`,
        );
      const bad = crypto.randomUUID();
      const [u] = await apply(bad, "platinum", new Date(Date.UTC(2026, 8, 20)));
      assertEquals([u.fresh, u.applied, u.outcome], [true, false, "unknown_plan"]);
      const [ev] =
        await sql`select tenant_id, applied_at from billing_events where event_id = ${bad}`;
      assertEquals(ev.tenant_id, t, "recorded against its tenant — never dropped");
      assertEquals(ev.applied_at, null);
      assertEquals((await subOf(t)).plan, "free", "and nothing changed");

      const [ok] = await apply(crypto.randomUUID(), "business", new Date(Date.UTC(2026, 8, 21)));
      assertEquals([ok.applied, ok.outcome], [true, "activate"]);
      const sub = await subOf(t);
      assertEquals([sub.plan, sub.status], ["business", "active"]);
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-25-3 (database half) PgStore.planCatalogue() reads, as rf_api, exactly the rows the MemStore fakes — ADR 2026-09-25 §5's table — as safe integers, so the fake cannot drift from 0018 unnoticed",
  ignore,
  async fn() {
    const store = await apiStore(url!); // the edge's rf_api login; fixtures stay on the owner's `sql`
    setup();
    try {
      const t = await mkTenant("family");
      const p = await person(t, "admin");
      const rows = await store.withClaims(
        { user_id: p.user, device_id: p.dev },
        (tx) => tx.planCatalogue(),
      );
      const strip = <T extends { id: string; updated_at: Date }>(x: T) => ({ ...x, updated_at: 0 });
      const byId = (a: { id: string }, b: { id: string }) => a.id < b.id ? -1 : 1;
      assertEquals(
        rows.map(strip).sort(byId),
        CATALOGUE_SEED.map(strip).sort(byId),
        "0018's seed and store_mem's CATALOGUE_SEED are the same catalogue",
      );
      for (const r of rows) {
        for (const v of [r.price_yearly_paise, r.price_monthly_paise, ...Object.values(r.limits)]) {
          assert(Number.isSafeInteger(v), `${r.id}: ${v}`);
        }
        assert(r.updated_at instanceof Date);
      }
    } finally {
      await store.end();
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "G-25-4 (database half) a catalogue data change moves the enforced device cap (rf.device_cap) and re-mints the token with the row's new limits and features at the next pull — no code change (ADR 2026-09-25 §6 🔒)",
  ignore,
  async fn() {
    const store = await apiStore(url!); // the edge's rf_api login; fixtures stay on the owner's `sql`
    setup();
    const plan = `zz_${crypto.randomUUID().slice(0, 8)}`;
    let tenant = "";
    try {
      // A test-only plan row, so the seed is never edited outside a rolled-back transaction.
      await sql`insert into plan_catalogue (id, entity_type, name, members, business_books,
          devices, envelopes_per_book, tenant_bytes, attachment_bytes, features,
          price_yearly_paise, price_monthly_paise)
        values (${plan}, 'family', 'Test', 6, 4, 9, 50000, 1000000000, 1000000000,
                '{statement_import,pdf_output}', 150000, 15000)`;
      tenant = await mkTenant("family");
      const p = await person(tenant, "admin");
      await sql`insert into subscriptions (tenant_id, plan, status, current_period_end)
        values (${tenant}, ${plan}, 'active', ${new Date(Date.now() + 100 * DAY)})`;
      const cap = async () => (await sql`select rf.device_cap(${p.user}) as c`)[0].c as number;
      assertEquals(await cap(), 9, "the row's devices, not 0005's hard-coded 5 / 8 / 15");
      await sql`update plan_catalogue set devices = 3 where id = ${plan}`;
      assertEquals(await cap(), 3);
      await sql`update plan_catalogue set devices = -1 where id = ${plan}`;
      assertEquals(await cap(), 2147483647, "NO_CAP is no cap, never a cap of -1");

      const claims = { user_id: p.user, device_id: p.dev };
      const read = () =>
        store.withClaims(claims, async (tx) => ({
          states: await tx.entitlementStates(),
          catalogue: new PlanCatalogue(await tx.planCatalogue()),
        }));
      // A REAL signed token, as sync-meta stores one: the re-mint rule reads what it says.
      const seed = rand(32);
      const mint = async (states: Awaited<ReturnType<typeof read>>["states"], c: PlanCatalogue) => {
        const payload = entitlementFor(states[0], c, new Date());
        const tok = await signEntitlementToken(payload, seed);
        await store.withClaims(
          claims,
          (tx) => tx.putEntitlementToken(tenant, tok, new Date(payload.exp)),
        );
        return payload;
      };
      let { states, catalogue } = await read();
      assertEquals(states.length, 1);
      const minted = await mint(states, catalogue);
      assertEquals(minted.plan, plan);
      assertEquals(minted.features, ["pdf_output", "statement_import"]);
      assertEquals(minted.limits.members, 6);
      ({ states, catalogue } = await read());
      assertEquals(needsMint(states[0], catalogue, new Date()), false, "fresh token: served as is");

      await new Promise((r) => setTimeout(r, 5)); // distinct DB instants at ms resolution
      await sql`update plan_catalogue set features = '{statement_import}', members = 7
        where id = ${plan}`;
      ({ states, catalogue } = await read());
      assertEquals(
        needsMint(states[0], catalogue, new Date()),
        true,
        "the plan row changed what the token must say",
      );
      const again = await mint(states, catalogue);
      assertEquals(again.features, ["statement_import"], "PDF output left the plan");
      assertEquals(again.limits.members, 7);
      ({ states, catalogue } = await read());
      assertEquals(needsMint(states[0], catalogue, new Date()), false, "re-minted, then stable");

      // The race, on two real connections. A catalogue change is a migration — ONE transaction
      // (ADR 25 §6) — and `updated_at` is its transaction-START now(). A pull that runs while it is
      // still open reads the committed (old) row and mints a token whose created_at is LATER than
      // the row's new updated_at. Once it commits, the token must still be seen as stale.
      const migration = postgres(url!, { max: 1, onnotice: () => {} });
      try {
        await migration.begin(async (m) => {
          await m`update plan_catalogue set features = '{}', members = 5 where id = ${plan}`;
          await new Promise((r) => setTimeout(r, 5));
          ({ states, catalogue } = await read());
          assertEquals(
            catalogue.get(plan)!.features,
            ["statement_import"],
            "the pull reads the committed row: the change is not visible yet",
          );
          await mint(states, catalogue);
        });
      } finally {
        await migration.end();
      }
      const [{ row_at, token_at }] = await sql`
        select c.updated_at as row_at, e.created_at as token_at
          from plan_catalogue c, entitlement_tokens e
         where c.id = ${plan} and e.tenant_id = ${tenant}`;
      assert(
        (row_at as Date) < (token_at as Date),
        "the race's precondition: the committed row is OLDER than the token a clock rule compares",
      );
      ({ states, catalogue } = await read());
      assertEquals(
        needsMint(states[0], catalogue, new Date()),
        true,
        "the next pull after the commit re-mints — the change is not lost for 30 days",
      );
      const raced = entitlementFor(states[0], catalogue, new Date());
      assertEquals([raced.features, raced.limits.members], [[], 5]);
    } finally {
      if (tenant) await sql`update subscriptions set plan = 'free' where tenant_id = ${tenant}`;
      await sql`delete from plan_catalogue where id = ${plan}`;
      await store.end();
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-03-79 (webhook through the database) the real route, read() and all, activates a catalogue id outside 08 §2's four names (business_plus) against Postgres, and records a present-but-malformed plan ('Business+') as `unknown_plan` with not one subscription column moved",
  ignore,
  async fn() {
    const store = await apiStore(url!); // the edge's rf_api login; fixtures stay on the owner's `sql`
    setup();
    const secret = rand(32);
    const deps: Deps = {
      store,
      now: () => new Date(),
      jwtKey: rand(32),
      phoneHmacKey: rand(32),
      phoneKek: rand(32),
      entitlementSeed: rand(32),
      otp: new FakeOtpProvider(),
      webhookSecret: secret,
    };
    const deliver = async (eventId: string, text: string) => {
      const sig = hex.enc(await hmacSha256AnyKey(secret, new TextEncoder().encode(text)));
      const res = await webhook(
        new Request("https://edge.local/functions/v1/billing-webhook", {
          method: "POST",
          headers: { "x-razorpay-signature": sig, "x-razorpay-event-id": eventId },
          body: text,
        }),
        deps,
      );
      assertEquals(res.status, 200);
      return await res.json();
    };
    const secs = (d: Date) => Math.floor(d.getTime() / 1000);
    const activation = (tenant: string, ref: string, plan: string, at: Date) =>
      JSON.stringify({
        entity: "event",
        event: "subscription.activated",
        created_at: secs(at),
        payload: {
          subscription: {
            entity: {
              id: ref,
              notes: { tenant_id: tenant, plan },
              current_end: secs(new Date(at.getTime() + 365 * DAY)),
            },
          },
        },
      });
    try {
      const t = await mkTenant("business_group");
      const ref = `sub_${crypto.randomUUID()}`;
      await sql`insert into subscriptions (tenant_id, plan, status, gateway, gateway_ref,
          current_period_end, grace_kind, grace_until)
        values (${t}, 'business', 'past_due', 'razorpay', ${ref},
          ${new Date(Date.now() - DAY)}, 'dunning', ${new Date(Date.now() + 6 * DAY)})`;
      const before = await subOf(t);

      const bad = crypto.randomUUID();
      assertEquals(
        await deliver(bad, activation(t, ref, "Business+", new Date(Date.UTC(2026, 8, 20)))),
        { ok: true, duplicate: false, applied: false },
      );
      const [ev] =
        await sql`select tenant_id, applied_at from billing_events where event_id = ${bad}`;
      assertEquals([ev.tenant_id, ev.applied_at], [t, null], "recorded, never dropped");
      assertEquals(await subOf(t), before, "not the plan, the status, the period or the grace");

      assertEquals(
        await deliver(
          crypto.randomUUID(),
          activation(t, ref, "business_plus", new Date(Date.UTC(2026, 8, 21))),
        ),
        { ok: true, duplicate: false, applied: true },
      );
      const sub = await subOf(t);
      assertEquals([sub.plan, sub.status, sub.grace_kind], ["business_plus", "active", null]);
    } finally {
      await store.end();
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-04c-1 (database half) after every migration the catalogue row `shop` is named Business Lite (0029, ADR 2026-10-04c §3 🔒) and ONLY its name moved — entity type, step, limits, devices, quota, bytes, prices, extras and popular are 0018's — no plan is still called Shop, and rf_api reads the new name through PgStore exactly as the MemStore seed carries it",
  ignore,
  async fn() {
    const store = await apiStore(url!);
    setup();
    try {
      const [shop] = await sql`select * from plan_catalogue where id = 'shop'`;
      assert(shop, "the id `shop` is kept: subscriptions, tokens and billing carry it");
      assertEquals(shop.name, "Business Lite");
      assertEquals(
        {
          entity_type: shop.entity_type,
          sort_order: shop.sort_order,
          members: shop.members,
          business_books: shop.business_books,
          devices: shop.devices,
          envelopes_per_book: Number(shop.envelopes_per_book),
          tenant_bytes: Number(shop.tenant_bytes),
          attachment_bytes: Number(shop.attachment_bytes),
          features: shop.features,
          price_yearly_paise: Number(shop.price_yearly_paise),
          price_monthly_paise: Number(shop.price_monthly_paise),
          popular: shop.popular,
        },
        {
          entity_type: "business",
          sort_order: 1,
          members: 2,
          business_books: 1,
          devices: 8,
          envelopes_per_book: 250_000,
          tenant_bytes: 5_368_709_120,
          attachment_bytes: 5_368_709_120,
          features: [],
          price_yearly_paise: 249_900,
          price_monthly_paise: 24_990,
          popular: false,
        },
        "0018's numbers, untouched",
      );
      assertEquals(
        (await sql`select id from plan_catalogue where name = 'Shop'`).length,
        0,
        "no plan is still called Shop",
      );
      const ladder = async (entity: string) =>
        (await sql`select name from plan_catalogue where entity_type = ${entity}
          and id not like 'zz_%' order by sort_order`).map((r) => r.name as string);
      assertEquals(await ladder("business"), ["Business Lite", "Business", "Business+"]);
      assertEquals(await ladder("family"), ["Family Lite", "Family", "Family+"]);

      const t = await mkTenant("business_group");
      const p = await person(t, "admin");
      const rows = await store.withClaims(
        { user_id: p.user, device_id: p.dev },
        (tx) => tx.planCatalogue(),
      );
      assertEquals(rows.find((r) => r.id === "shop")?.name, "Business Lite", "rf_api reads it");
      assertEquals(
        CATALOGUE_SEED.find((r) => r.id === "shop")?.name,
        "Business Lite",
        "the MemStore seed says the same (E-25-3 holds the rest of the row)",
      );
    } finally {
      await store.end();
      await sql.end();
    }
  },
});
