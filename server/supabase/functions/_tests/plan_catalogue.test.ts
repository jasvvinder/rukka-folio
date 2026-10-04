// The plan catalogue over the MemStore — ADR 2026-09-25 §5 (plans follow the entity type; book-flow
// features are never restricted; Free has no import and no PDF; the trial runs on the popular
// plan, once per person) and §6 (one server-side catalogue, the server's enforced limits read from
// it, the token gains `features`, a price or feature change needs no app release).
//
// What each test holds the server to, and why the assertion would FAIL on a hollow seam:
//
//   * E-25-3 — the read path is the catalogue and only the catalogue. The expected rows are ADR 25
//     §5's table written out HERE from the ADR (books · people · price · extras · popular), not
//     read back from the fake's seed, so a seed that drifted from the ADR fails. The route must
//     carry no identifier of the caller, their tenant or their device.
//   * G-25-4 — the enforced numbers MOVE with a data change: the push quota, the device cap and the
//     token's limits and features each change when one catalogue row changes, with no code change.
//     Each is observed through the real handler (push refuses, registration refuses, the pull
//     re-mints), so a registry that still held its own table would fail every step.
//   * G-25-1 — nothing but statement import and PDF output can ever be gated: a Free tenant (no
//     extras at all) pushes every object type 03 §2.3 registers, and the signer refuses a payload
//     that names any other feature.
//   * G-25-2 — Free is the personal book only, with no import and no PDF, and signs `features: []`.
//   * G-25-3 — the trial: popular plan, once per person, never Individual, only by an admin.
//
//   * E-04c-1 — ADR 2026-10-04c §3: the `shop` plan's NAME is Business Lite; its id and numbers are
//     not touched. The names are transcribed here from the ADRs, so a seed left at "Shop" fails.
//
// Ids E-25-3, G-25-1, G-25-2, G-25-3, G-25-4, E-04c-1. The PgStore halves are
// tests/rls/plan_catalogue.test.ts.
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { NO_CAP, OBJECT_TYPES } from "../_shared/registry.ts";
import {
  type EntitlementPayload,
  parseEntitlementToken,
  signEntitlementToken,
} from "../_shared/sodium.ts";
import { TOKEN_TTL_MS } from "../_shared/entitlement.ts";
import { DeviceCapError } from "../_shared/store.ts";
import { CATALOGUE_SEED } from "../_shared/store_mem.ts";
import { handler as meta } from "../sync-meta/index.ts";
import { handler as push } from "../sync-push/index.ts";
import {
  advance,
  body,
  ENTITLEMENT_SEED,
  get,
  member,
  post,
  random,
  reissue,
  type Rig,
  rig,
  wireEnvelope,
} from "./harness.ts";

const DAY = 86_400_000;
const GiB = 1024 ** 3;

/** ADR 2026-09-25 §5's working-price table, transcribed from the ADR (not from any seed):
 *  id → [entity, books, people, yearly ₹, import+PDF, popular]. Monthly is ten months' price for
 *  twelve, i.e. yearly / 10. Popular is the bolded plan; Trust bolds neither — 0018's ⚠️ SPEC
 *  reading puts it on `trust`, and this table records that reading so a change to it is seen. */
const ADR_25_TABLE: Record<string, [string, number, number, number, boolean, boolean]> = {
  free: ["individual", 0, 1, 0, false, false],
  personal: ["individual", 3, 1, 990, true, false],
  shop: ["business", 1, 2, 2_499, false, false],
  business: ["business", 5, 10, 2_999, true, true],
  business_plus: ["business", 15, 30, 6_999, true, false],
  family_lite: ["family", 2, 4, 1_999, false, false],
  family: ["family", 8, 12, 2_499, true, true],
  family_plus: ["family", 20, 30, 5_999, true, false],
  trust: ["trust", 3, 15, 1_999, true, true],
  trust_plus: ["trust", 10, 40, 3_999, true, false],
};
const PLAN_KEYS = [
  "entity_type",
  "features",
  "id",
  "limits",
  "name",
  "placeholder",
  "popular",
  "price_monthly_paise",
  "price_yearly_paise",
  "sort_order",
  "updated_at",
];

async function catalogue(r: Rig, token: string): Promise<Record<string, any>> {
  const res = await meta(get("/sync-meta/plans", { token }), r.deps);
  assertEquals(res.status, 200);
  return await body(res);
}
async function tokens(r: Rig, token: string): Promise<Map<string, EntitlementPayload>> {
  const res = await body(await meta(get("/sync-meta", { token }), r.deps));
  return new Map(
    ((res.entitlement_tokens ?? []) as { tenant_id: string; token: string }[]).map((w) => [
      w.tenant_id,
      parseEntitlementToken(b64url.dec(w.token)).payload,
    ]),
  );
}
const trial = (r: Rig, token: string, tenant_id: string, entity_type: string) =>
  meta(post("/sync-meta/plans/trial", { tenant_id, entity_type }, { token }), r.deps);

Deno.test("E-25-3 the catalogue read path (ADR 2026-09-25 §6 🔒): GET /sync-meta/plans serves every plan of ADR 25 §5's table in integer paise with exactly the catalogue's fields — no caller, tenant or device identifier — and the token a pull mints reads its limits and extras from the same rows", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const me = await member(r, tenant, r.db.addBook(tenant), "admin");
  r.db.addSubscription(tenant, {
    plan: "family",
    status: "active",
    current_period_end: new Date(r.clock.now.getTime() + 200 * DAY),
  });
  const res = await catalogue(r, me.token);

  await t.step("ADR 25 §5's table, row for row, and nothing else", () => {
    assertEquals(Object.keys(res).sort(), ["catalogue_updated_at", "plans"]);
    const plans = res.plans as Record<string, any>[];
    assertEquals(plans.map((p) => p.id).sort(), Object.keys(ADR_25_TABLE).sort());
    for (const p of plans) {
      const [entity, books, people, rupees, extras, popular] = ADR_25_TABLE[p.id];
      assertEquals(Object.keys(p).sort(), PLAN_KEYS, `${p.id}: only catalogue fields`);
      assertEquals(p.entity_type, entity, p.id);
      assertEquals(p.limits.business_books, books, `${p.id}: books (personal never counted)`);
      assertEquals(p.limits.members, people, `${p.id}: people`);
      assertEquals(p.price_yearly_paise, rupees * 100, `${p.id}: GST-inclusive yearly paise`);
      assertEquals(
        p.price_monthly_paise * 10,
        p.price_yearly_paise,
        `${p.id}: monthly is ten months' price for twelve (ADR 25 §5)`,
      );
      assertEquals(
        [...p.features].sort(),
        extras ? ["pdf_output", "statement_import"] : [],
        `${p.id}: extras`,
      );
      assertEquals(p.popular, popular, `${p.id}: popular`);
      assertEquals(p.placeholder, true, `${p.id}: flagged placeholder (ADR 2026-09-24b §11)`);
      for (
        const v of [
          p.price_yearly_paise,
          p.price_monthly_paise,
          p.sort_order,
          p.updated_at,
          ...Object.values(p.limits),
        ]
      ) assert(Number.isSafeInteger(v), `${p.id}: integer, got ${v}`);
    }
  });

  await t.step("names nobody: the caller's user, device and tenant ids appear nowhere", () => {
    const text = JSON.stringify(res);
    for (const id of [me.user, me.device.id, tenant]) {
      assert(!text.includes(id), `catalogue response carries ${id}`);
    }
    assert(!/tenant_id|user_id|device_id|subscription|status/.test(text));
  });

  await t.step(
    "an uncertified phone reads the same public catalogue (not tenant data)",
    async () => {
      const pending = await member(r, tenant, null, null, { status: "registered" });
      assertEquals((await catalogue(r, pending.token)).plans, res.plans);
    },
  );

  await t.step("no JWT, no catalogue", async () => {
    const anon = await meta(get("/sync-meta/plans"), r.deps);
    assertEquals(anon.status, 401);
  });

  await t.step("the minted token is the catalogue row's limits and extras", async () => {
    const p = (await tokens(r, me.token)).get(tenant)!;
    const row = (res.plans as Record<string, any>[]).find((x) => x.id === "family")!;
    assertEquals(p.plan, "family");
    assertEquals(p.limits, row.limits);
    assertEquals(p.features, ["pdf_output", "statement_import"], "sorted, as encoded");
    assertEquals(p.limits.members, 12, "ADR 25 §5 Family · 12 people");
    assertEquals(p.limits.business_books, 8, "ADR 25 §5 Family · 8 books");
    assertEquals(p.limits.envelopes_per_book, 250_000, "08 §2's Family quota, kept as data");
    assertEquals(p.limits.tenant_bytes, 5 * GiB);
  });
});

/** ADR 2026-10-04c §3's display names, transcribed from the ADRs (ADR 25 §5 as amended by 04c §3),
 *  not read back from the seed: id → name. The two ladders read Lite · base · plus. */
const DISPLAY_NAMES: Record<string, string> = {
  free: "Free",
  personal: "Personal",
  shop: "Business Lite",
  business: "Business",
  business_plus: "Business+",
  family_lite: "Family Lite",
  family: "Family",
  family_plus: "Family+",
};

Deno.test("E-04c-1 the `shop` plan is named Business Lite (ADR 2026-10-04c §3 🔒): the MemStore seed and GET /sync-meta/plans both say so, and only the name moved — the id `shop`, its entity type, step, limits, price and extras are ADR 25 §5's — so the Business ladder reads Business Lite · Business · Business+ beside Family Lite · Family · Family+", async () => {
  const seed = CATALOGUE_SEED.find((p) => p.id === "shop");
  assert(seed, "the id `shop` is kept: tokens, subscriptions and billing carry it");
  assertEquals(seed.name, "Business Lite", "the MemStore seed (store_mem.ts) is renamed");
  assert(!CATALOGUE_SEED.some((p) => p.name === "Shop"), "no plan is still called Shop");

  const r = rig();
  const tenant = r.db.addTenant();
  const me = await member(r, tenant, r.db.addBook(tenant), "admin");
  const plans = (await catalogue(r, me.token)).plans as Record<string, any>[];
  const shop = plans.find((p) => p.id === "shop")!;
  assertEquals(shop.name, "Business Lite", "the read path serves the new name");
  const [entity, books, people, rupees, extras, popular] = ADR_25_TABLE.shop;
  assertEquals(shop.entity_type, entity);
  assertEquals(shop.sort_order, 1, "the first step of the Business ladder");
  assertEquals(shop.limits.business_books, books, "limits unchanged");
  assertEquals(shop.limits.members, people);
  assertEquals(shop.price_yearly_paise, rupees * 100, "price unchanged, integer paise");
  assertEquals(shop.features, extras ? ["pdf_output", "statement_import"] : []);
  assertEquals(shop.popular, popular);
  for (const [id, name] of Object.entries(DISPLAY_NAMES)) {
    assertEquals(plans.find((p) => p.id === id)?.name, name, id);
  }
  const ladder = (entity: string) =>
    plans.filter((p) => p.entity_type === entity).sort((a, b) => a.sort_order - b.sort_order)
      .map((p) => p.name);
  assertEquals(ladder("business"), ["Business Lite", "Business", "Business+"]);
  assertEquals(ladder("family"), ["Family Lite", "Family", "Family+"]);
});

Deno.test("G-25-4 a catalogue DATA change moves what the server enforces and signs, with no code change (ADR 2026-09-25 §6 🔒): the push quota, the device cap, and the token's limits and features all follow one edited row, and the next pull re-mints", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const me = await member(r, tenant, book, "admin");
  r.db.addWrappedKey({ kind: "bk_for_user", user_id: me.user, book_id: book, key_version: 1 });
  r.db.addSubscription(tenant, {
    plan: "family",
    status: "active",
    current_period_end: new Date(r.clock.now.getTime() + 200 * DAY),
  });
  const send = async () =>
    (await body(
      await push(
        post("/sync-push", { envelopes: [await wireEnvelope(me, tenant, book)] }, {
          token: await reissue(r, me),
        }),
        r.deps,
      ),
    )).results[0].result as string;

  const first = (await tokens(r, me.token)).get(tenant)!;
  assertEquals(first.features, ["pdf_output", "statement_import"]);

  await t.step(
    "moving PDF output off Family re-mints at the next pull, not in 30 days",
    async () => {
      advance(r, 60_000);
      r.db.setCataloguePlan("family", { features: ["statement_import"], limits: { members: 14 } });
      advance(r, 60_000);
      const p = (await tokens(r, await reissue(r, me))).get(tenant)!;
      assertNotEquals(p.iat, first.iat, "re-signed: the plan row moved after the token was minted");
      assertEquals(p.features, ["statement_import"], "the app's gate now reads no PDF output");
      assertEquals(p.limits.members, 14, "and the new seat count");
      const again = (await tokens(r, await reissue(r, me))).get(tenant)!;
      assertEquals(again.iat, p.iat, "…and is then stable: no re-mint without another change");
    },
  );

  await t.step(
    "a change that COMMITS after a pull that began later still re-mints: the rule compares what the token says, not clocks",
    async () => {
      advance(r, 60_000);
      const served = (await tokens(r, await reissue(r, me))).get(tenant)!;
      const mintedAt = r.db.entitlement_tokens.find((x) => x.tenant_id === tenant)!
        .created_at as Date;
      // The catalogue migration's transaction BEGAN 30 s before that token was minted and commits
      // only now, so its row carries its transaction-start now() — earlier than the token's
      // created_at. A rule comparing the two would never fire again until the 30-day expiry.
      const row = r.db.setCataloguePlan("family", { features: [], limits: { members: 13 } });
      row.updated_at = new Date(mintedAt.getTime() - 30_000);
      assert(row.updated_at < mintedAt, "the race's precondition holds");
      advance(r, 60_000);
      const p = (await tokens(r, await reissue(r, me))).get(tenant)!;
      assertNotEquals(p.iat, served.iat, "re-signed at the next pull, not in 30 days");
      assertEquals(p.features, [], "the change reached the token");
      assertEquals(p.limits.members, 13);
      const again = (await tokens(r, await reissue(r, me))).get(tenant)!;
      assertEquals(again.iat, p.iat, "…and is then stable again");
      r.db.setCataloguePlan("family", { features: ["statement_import"], limits: { members: 14 } });
    },
  );

  await t.step("the push quota is the row's envelopes_per_book", async () => {
    assertEquals(await send(), "acked");
    r.db.setCataloguePlan("family", { limits: { envelopes_per_book: 1 } });
    assertEquals(await send(), "rejected:quota", "one envelope stored, the cap is now one");
    r.db.setCataloguePlan("family", { limits: { envelopes_per_book: NO_CAP } });
    assertEquals(await send(), "acked", "NO_CAP (-1) is no cap, never a cap already exceeded");
    r.db.setCataloguePlan("family", { limits: { tenant_bytes: 1 } });
    assertEquals(await send(), "rejected:quota", "and the tenant byte cap likewise");
    r.db.setCataloguePlan("family", {
      limits: { envelopes_per_book: 250_000, tenant_bytes: 5 * GiB },
    });
  });

  await t.step("NO_CAP on a limit is signed as -1 (ADR 2026-09-24b §7 (b))", async () => {
    advance(r, 60_000);
    r.db.setCataloguePlan("family", { limits: { business_books: NO_CAP } });
    advance(r, 60_000);
    assertEquals((await tokens(r, await reissue(r, me))).get(tenant)!.limits.business_books, -1);
  });

  await t.step("the device cap is the row's devices", async () => {
    const reg = (user: string) =>
      r.deps.store.withClaims(null, async (tx) =>
        tx.registerDevice(
          crypto.randomUUID(),
          user,
          await random(32),
          await random(32),
          null,
          null,
          null,
        ));
    r.db.setCataloguePlan("family", { limits: { devices: 2 } }); // `me` already holds one device
    await reg(me.user);
    let capped = false;
    try {
      await reg(me.user);
    } catch (e) {
      capped = e instanceof DeviceCapError;
    }
    assert(capped, "a third device is refused at a catalogue cap of 2");
    r.db.setCataloguePlan("family", { limits: { devices: 3 } });
    await reg(me.user); // and accepted once the row says 3
  });
});

Deno.test("G-25-1 book-flow features are never gated server-side (ADR 2026-09-25 §5 🔒): a Free tenant, which includes no extra at all, pushes every registered object type — import lines included — and the signer refuses a token naming any feature but statement import and PDF output", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const me = await member(r, tenant, book, "admin");
  r.db.addWrappedKey({ kind: "bk_for_user", user_id: me.user, book_id: book, key_version: 1 });
  // no subscription row: the floor, Free.

  await t.step("every object type is accepted on Free", async () => {
    const envelopes = [];
    for (const object_type of OBJECT_TYPES) {
      envelopes.push(await wireEnvelope(me, tenant, book, { object_type }));
    }
    const res = await body(
      await push(post("/sync-push", { envelopes }, { token: me.token }), r.deps),
    );
    assertEquals(
      res.results.map((x: { result: string }) => x.result),
      [...OBJECT_TYPES].map(() => "acked"),
      "the server never reads a feature on push: the extras are soft, client-side gates (ADR 2026-09-05g §2)",
    );
  });

  await t.step("the signer cannot carry a gate on a never-restricted feature", async () => {
    const base: EntitlementPayload = {
      tenant_id: tenant,
      plan: "free",
      limits: { ...r.db.plan_catalogue.find((p) => p.id === "free")!.limits },
      features: [],
      period_end: null,
      grace_kind: null,
      grace_until: null,
      iat: r.clock.now.getTime(),
      exp: r.clock.now.getTime() + TOKEN_TTL_MS,
    };
    assert((await signEntitlementToken(base, ENTITLEMENT_SEED)).length > 0);
    for (
      const f of ["csv_export", "xlsx_export", "month_close", "year_close", "search", "reports"]
    ) {
      let threw = false;
      try {
        await signEntitlementToken({ ...base, features: [f] }, ENTITLEMENT_SEED);
      } catch {
        threw = true;
      }
      assert(threw, `a token gating ${f} must not be signable`);
    }
    for (
      const bad of [["statement_import", "pdf_output"], ["pdf_output", "pdf_output"]]
    ) {
      let threw = false;
      try {
        await signEntitlementToken({ ...base, features: bad }, ENTITLEMENT_SEED);
      } catch {
        threw = true;
      }
      assert(threw, `unsorted or repeated features ${bad} have a second encoding`);
    }
    let threw = false;
    try {
      await signEntitlementToken(
        { ...base, features: undefined as unknown as string[] },
        ENTITLEMENT_SEED,
      );
    } catch {
      threw = true;
    }
    assert(threw, "features is part of the exact field set (ADR 25 §6)");
  });
});

Deno.test("G-25-2 Free is Individual's permanent floor with the personal book only, no statement import and no PDF output (ADR 2026-09-25 §5 🔒): a tenant with no subscription signs plan 'free', features [], 0 books — and the two lower-step plans ADR 25 marks 'no import or PDF' carry no extra either", async () => {
  const r = rig();
  const tenant = r.db.addTenant();
  const me = await member(r, tenant, r.db.addBook(tenant), "admin");
  const p = (await tokens(r, me.token)).get(tenant)!;
  assertEquals(p.plan, "free");
  assertEquals(p.features, [], "no import, no PDF — statements stay readable on screen");
  assertEquals(p.limits.business_books, 0, "the personal book only; it is never counted");
  assertEquals(p.limits.members, 1);
  assertEquals(p.period_end, null, "Free has no period: it is permanent, not a lapse");
  const plans = (await catalogue(r, me.token)).plans as Record<string, any>[];
  const free = plans.find((x) => x.id === "free")!;
  assertEquals([free.price_yearly_paise, free.price_monthly_paise], [0, 0]);
  assertEquals(free.entity_type, "individual");
  for (const id of ["shop", "family_lite"]) {
    assertEquals(plans.find((x) => x.id === id)!.features, [], `${id}: "no import or PDF"`);
  }
  assertEquals(
    plans.filter((x) => x.entity_type !== "individual" && x.price_yearly_paise === 0),
    [],
    "Family, Business and Trust have no Free plan",
  );
});

Deno.test("G-25-3 the trial (ADR 2026-09-25 §5 🔒): Family, Business and Trust start 30 days on their entity type's POPULAR plan, once per person — never for Individual, only by the tenant's admin, never twice on one tenant — and the next pull signs that plan with period_end = trial_end", async (t) => {
  const r = rig();
  const fam = r.db.addTenant("family"), biz = r.db.addTenant("business_group");
  const org = r.db.addTenant("organization"), solo = r.db.addTenant("family");
  const karta = await member(r, fam, r.db.addBook(fam), "admin");
  for (const x of [biz, org, solo]) {
    r.db.addMembership(x, karta.user, "active");
    r.db.addRole(r.db.addBook(x), karta.user, "admin");
  }
  const brother = await member(r, fam, r.db.addBook(fam), "member");
  const outsider = await member(r, biz, r.db.addBook(biz), "admin");

  await t.step("a member who is not an admin cannot start one", async () => {
    const res = await trial(r, brother.token, fam, "family");
    assertEquals(res.status, 403);
    assertEquals((await body(res)).error, "not_admin");
  });

  await t.step("an admin of ANOTHER tenant cannot start one here, and learns nothing", async () => {
    const res = await trial(r, outsider.token, fam, "family");
    assertEquals(res.status, 403);
    assertEquals((await body(res)).error, "not_admin");
    assertEquals(r.db.subscriptions.find((s) => s.tenant_id === fam), undefined);
  });

  await t.step("Individual has permanent Free, not a trial", async () => {
    const res = await trial(r, karta.token, solo, "individual");
    assertEquals(res.status, 409);
    assertEquals((await body(res)).error, "no_trial");
  });

  await t.step("Our trust ⇔ organization (07 §3.1 🔒)", async () => {
    assertEquals((await body(await trial(r, karta.token, fam, "trust"))).error, "entity_mismatch");
    assertEquals((await body(await trial(r, karta.token, org, "family"))).error, "entity_mismatch");
  });

  let trialEnd = 0;
  await t.step("Family's trial runs on Family, the popular plan, for 30 days", async () => {
    const res = await trial(r, karta.token, fam, "family");
    assertEquals(res.status, 200);
    const b = await body(res);
    assertEquals(b.plan, "family");
    assertEquals(b.trial_end, r.clock.now.getTime() + 30 * DAY);
    trialEnd = b.trial_end;
    const sub = r.db.subscriptions.find((s) => s.tenant_id === fam)!;
    assertEquals([sub.plan, sub.status], ["family", "trial"]);
    assert(r.db.users.get(karta.user)!.trial_consumed_at, "users.trial_consumed_at is set");
  });

  await t.step("the token signs the trial's plan and its end", async () => {
    advance(r, 1000);
    const p = (await tokens(r, await reissue(r, karta))).get(fam)!;
    assertEquals(p.plan, "family");
    assertEquals(p.period_end, trialEnd, "the trial IS the period");
    assertEquals(p.features, ["pdf_output", "statement_import"]);
  });

  await t.step("once per PERSON: the same karta cannot trial his business too", async () => {
    const res = await trial(r, await reissue(r, karta), biz, "business");
    assertEquals(res.status, 409);
    assertEquals((await body(res)).error, "trial_consumed");
  });

  await t.step(
    "⚠️ SPEC (open, owner): the refused business tenant keeps no row, and is signed — for now — as the Free floor, never a trial or a paid plan",
    async () => {
      // entitlement.ts planOf's ⚠️ SPEC: ADR 2026-09-05g §1 🔒 ("no valid token is Free") and ADR
      // 2026-09-25 §5 🔒 ("Family, Business and Trust have no Free plan") meet here and neither
      // names a shared-type tenant with no subscription row. This pins the PRESENT reading so the
      // owner's ruling flips a test instead of passing silently.
      assertEquals(r.db.subscriptions.find((s) => s.tenant_id === biz), undefined);
      const p = (await tokens(r, await reissue(r, karta))).get(biz)!;
      assertEquals([p.plan, p.features, p.period_end], ["free", [], null]);
    },
  );

  await t.step("another person's Business trial runs on Business, its popular plan", async () => {
    const b = await body(await trial(r, outsider.token, biz, "business"));
    assertEquals(b.plan, "business");
  });

  await t.step(
    "a tenant that already had its trial cannot be re-trialled by a second admin",
    async () => {
      const second = await member(r, fam, r.db.addBook(fam), "admin");
      const res = await trial(r, second.token, fam, "family");
      assertEquals(res.status, 409);
      assertEquals((await body(res)).error, "trial_unavailable");
      assertEquals(
        r.db.users.get(second.user)!.trial_consumed_at ?? null,
        null,
        "and his is unspent",
      );
    },
  );

  await t.step("moving the popular flag (a data change) moves the NEXT trial", async () => {
    r.db.setCataloguePlan("trust", { popular: false });
    r.db.setCataloguePlan("trust_plus", { popular: true });
    const treasurer = await member(r, org, r.db.addBook(org), "admin");
    assertEquals((await body(await trial(r, treasurer.token, org, "trust"))).plan, "trust_plus");
  });

  await t.step("bad input is a 400, not a guess", async () => {
    assertEquals((await trial(r, karta.token, "nope", "family")).status, 400);
    assertEquals((await trial(r, karta.token, fam, "joint_family")).status, 400);
  });
});
