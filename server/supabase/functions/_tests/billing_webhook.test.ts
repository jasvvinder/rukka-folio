// billing-webhook: signature, dedupe, out-of-order guard and the three state changes of 08 §3 🔒 /
// ADR 2026-09-05g §4, §11 (migration 0013, restated in MemStore). Ids E-05-12, G-08-9, G-08-10,
// G-08-11.
//
// Fixtures are SYNTHETIC (rule 4). No body here carries a real payer, instrument or amount, and
// nothing financial exists on this route at all — a webhook moves plan and status, never money.
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { hex } from "../_shared/bytes.ts";
import type { Deps } from "../_shared/deps.ts";
import { hmacSha256AnyKey } from "../_shared/sodium.ts";
import type { Store, Tx } from "../_shared/store.ts";
import { handler } from "../billing-webhook/index.ts";
import { type Rig, rig, T0 } from "./harness.ts";

const secs = (d: Date) => Math.floor(d.getTime() / 1000);
const DAY = 86400e3;

async function post(
  r: Rig,
  bodyText: string,
  eventId: string,
  tamper = false,
  deps: Deps = r.deps,
) {
  const sig = hex.enc(
    await hmacSha256AnyKey(
      deps.webhookSecret,
      new TextEncoder().encode(tamper ? bodyText + " " : bodyText),
    ),
  );
  return new Request("https://edge.local/functions/v1/billing-webhook", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-razorpay-signature": sig,
      "x-razorpay-event-id": eventId,
    },
    body: bodyText,
  });
}

/** A Razorpay subscription-event body. `notes` is where OUR identifiers ride (08 §3.1). */
function subBody(o: {
  event: string;
  at: Date;
  tenant?: string | null;
  plan?: string | null;
  ref?: string | null;
  periodEnd?: Date | null;
  paymentStatus?: string;
}): string {
  const notes: Record<string, string> = {};
  if (o.tenant) notes.tenant_id = o.tenant;
  if (o.plan) notes.plan = o.plan;
  const entity: Record<string, unknown> = { id: o.ref ?? "sub_syn_1", notes };
  if (o.periodEnd) entity.current_end = secs(o.periodEnd);
  const payload: Record<string, unknown> = { subscription: { entity } };
  if (o.paymentStatus) {
    payload.payment = { entity: { id: "pay_syn_1", status: o.paymentStatus } };
  }
  return JSON.stringify({ entity: "event", event: o.event, created_at: secs(o.at), payload });
}

/** A refund/dispute body: NO subscription entity, notes on the payment — the real gateway shape. */
function refundBody(o: { event: string; at: Date; tenant: string }): string {
  return JSON.stringify({
    entity: "event",
    event: o.event,
    created_at: secs(o.at),
    payload: {
      payment: { entity: { id: "pay_syn_1", notes: { tenant_id: o.tenant } } },
      refund: { entity: { id: "rfnd_syn_1" } },
    },
  });
}

/** Deps whose Tx records every method the handler calls, so "the apply path never reads envelopes"
 *  is asserted from the seam itself rather than from a row count that a no-op would also pass. */
function spied(r: Rig): { deps: Deps; calls: string[] } {
  const calls: string[] = [];
  const store: Store = {
    withClaims<T>(claims: Parameters<Store["withClaims"]>[0], fn: (tx: Tx) => Promise<T>) {
      return r.deps.store.withClaims(claims, (tx) =>
        fn(
          new Proxy(tx, {
            get(t, k) {
              const v = Reflect.get(t, k) as unknown;
              if (typeof v === "function") {
                calls.push(String(k));
                return (v as (...a: unknown[]) => unknown).bind(t);
              }
              return v;
            },
          }),
        ));
    },
  };
  return { deps: { ...r.deps, store }, calls };
}

/** A tenant with a subscription row carrying every 03 §2.4 column. */
function seed(r: Rig, row: Record<string, unknown> = {}): { tenant: string } {
  const tenant = r.db.addTenant();
  r.db.addSubscription(tenant, row);
  return { tenant };
}
const sub = (r: Rig, tenant: string) =>
  r.db.subscriptions.find((s) => s.tenant_id === tenant) as Record<string, unknown>;

Deno.test("E-05-12 billing-webhook: HMAC over the RAW body, idempotent by event id, and an event we do not act on is still recorded", async () => {
  const r = rig();
  // payment.captured is a one-off capture, not a subscription state change: recorded, applied=false.
  const text = JSON.stringify({
    event: "payment.captured",
    created_at: secs(T0),
    payload: { payment: { entity: { id: "pay_x", amount: 49900 } } },
  });
  const first = await handler(await post(r, text, "evt_1"), r.deps);
  assertEquals(first.status, 200);
  assertEquals(await first.json(), { ok: true, duplicate: false, applied: false });
  const replay = await handler(await post(r, text, "evt_1"), r.deps);
  assertEquals(await replay.json(), { ok: true, duplicate: true, applied: false });
  assertEquals(r.db.billing_events.size, 1);
  assertEquals((await handler(await post(r, text, "evt_2", true), r.deps)).status, 401);
  assertEquals(r.db.billing_events.size, 1, "an unsigned event is not recorded");
  const noSig = new Request("https://edge.local/functions/v1/billing-webhook", {
    method: "POST",
    body: text,
  });
  assertEquals((await handler(noSig, r.deps)).status, 401);
  assertEquals(r.db.subscriptions.length, 0, "an unknown tenant changes nothing");
  const unconfigured = { ...r.deps, webhookSecret: new Uint8Array(0) };
  assertEquals((await handler(await post(r, text, "evt_3"), unconfigured)).status, 503);

  // A signed body that is not JSON at all, and a signed body with no event id: recorded / refused,
  // never a silent drop (08 §4 🔒 dedupe is on `event_id`, so an event without one cannot be run).
  assertEquals((await handler(await post(r, "{not json", "evt_4"), r.deps)).status, 200);
  assertEquals(r.db.billing_events.get("evt_4")?.type, "malformed");
  assertEquals(r.db.billing_events.get("evt_4")?.applied_at, null);
  const anon = new Request("https://edge.local/functions/v1/billing-webhook", {
    method: "POST",
    headers: {
      "x-razorpay-signature": hex.enc(
        await hmacSha256AnyKey(r.deps.webhookSecret, new TextEncoder().encode("{}")),
      ),
    },
    body: "{}",
  });
  assertEquals((await handler(anon, r.deps)).status, 400);
  assertEquals((await handler(new Request("https://edge.local/x"), r.deps)).status, 405);
});

Deno.test("G-08-9 plumbing 🔒 (08 §4, ADR 2026-09-05g §9): activated/charged sets plan, status, period end, source and gateway_ref; a replay applies once; an older event overtaking a newer one changes nothing yet is recorded", async () => {
  const r = rig();
  const { tenant } = seed(r);
  const end = new Date(T0.getTime() + 30 * DAY);

  const act = subBody({
    event: "subscription.activated",
    at: T0,
    tenant,
    plan: "family",
    ref: "sub_syn_1",
    periodEnd: end,
  });
  assertEquals(await (await handler(await post(r, act, "evt_a"), r.deps)).json(), {
    ok: true,
    duplicate: false,
    applied: true,
  });
  const s = sub(r, tenant);
  assertEquals(s.plan, "family");
  assertEquals(s.status, "active");
  assertEquals((s.current_period_end as Date).getTime(), end.getTime());
  assertEquals(s.source, "razorpay");
  assertEquals(s.gateway, "razorpay");
  assertEquals(s.gateway_ref, "sub_syn_1");
  assertEquals(r.db.billing_events.get("evt_a")?.applied_at, T0, "the event is marked applied");
  assertEquals(r.db.billing_events.get("evt_a")?.tenant_id, tenant);

  // Replay of the SAME event id: 08 §5 "webhook replay is idempotent" — and idempotent means it
  // does not even re-apply the same state, so a later out-of-order event is still judged against
  // the FIRST delivery's timestamp.
  const replay = await handler(await post(r, act, "evt_a"), r.deps);
  assertEquals(await replay.json(), { ok: true, duplicate: true, applied: false });
  assertEquals(r.db.billing_events.size, 1);

  // A NEWER event lands, then an OLDER one arrives late (the retry that overtook it).
  const later = new Date(T0.getTime() + 2 * DAY);
  const end2 = new Date(T0.getTime() + 60 * DAY);
  await handler(
    await post(
      r,
      subBody({
        event: "subscription.charged",
        at: later,
        tenant,
        ref: "sub_syn_1",
        periodEnd: end2,
      }),
      "evt_b",
    ),
    r.deps,
  );
  assertEquals((sub(r, tenant).current_period_end as Date).getTime(), end2.getTime());

  const before = { ...sub(r, tenant) };
  const stale = subBody({
    event: "subscription.charged",
    at: new Date(T0.getTime() + DAY), // older than evt_b
    tenant,
    plan: "personal", // the older event would DOWNGRADE the plan if it were applied
    ref: "sub_syn_1",
    periodEnd: new Date(T0.getTime() + 10 * DAY),
  });
  assertEquals(await (await handler(await post(r, stale, "evt_c"), r.deps)).json(), {
    ok: true,
    duplicate: false,
    applied: false,
  });
  assertEquals(sub(r, tenant), before, "an out-of-order event changes not one column");
  assert(r.db.billing_events.has("evt_c"), "…and is still recorded, never dropped");
  assertEquals(r.db.billing_events.get("evt_c")?.applied_at, null);

  // A `subscription.charged` whose payment failed is a failed renewal, not an activation (08 §3).
  const failed = subBody({
    event: "subscription.charged",
    at: new Date(T0.getTime() + 3 * DAY),
    tenant,
    ref: "sub_syn_1",
    paymentStatus: "failed",
  });
  await handler(await post(r, failed, "evt_d"), r.deps);
  assertEquals(sub(r, tenant).status, "past_due");
  assertEquals(sub(r, tenant).plan, "family", "a failed charge never changes the plan");
});

Deno.test("G-08-10 dunning 🔒 (08 §3, ADR 2026-09-05g §4): pending/halted/payment.failed → past_due, grace_kind 'dunning', grace_until = period_end + 7 days, nothing else touched; and updated_at moves on every applied change (05 §5 cursor)", async () => {
  const end = new Date(T0.getTime() + 30 * DAY);
  for (const event of ["subscription.pending", "subscription.halted", "payment.failed"]) {
    const r = rig();
    const { tenant } = seed(r, {
      plan: "family",
      status: "active",
      gateway: "razorpay",
      gateway_ref: "sub_syn_1",
      source: "razorpay",
      current_period_end: end,
      payer_user_id: null,
      seats_addon: 3,
      cancel_at_period_end: true,
    });
    const before = { ...sub(r, tenant) };
    r.clock.now = new Date(T0.getTime() + DAY);

    const res = await handler(
      await post(r, subBody({ event, at: r.clock.now, tenant, ref: "sub_syn_1" }), "evt_x"),
      r.deps,
    );
    assertEquals(await res.json(), { ok: true, duplicate: false, applied: true }, event);
    const s = sub(r, tenant);
    assertEquals(s.status, "past_due", event);
    assertEquals(s.grace_kind, "dunning", event);
    assertEquals(
      (s.grace_until as Date).getTime(),
      end.getTime() + 7 * DAY,
      "7 days from period_end, not from today (08 §3 🔒)",
    );
    // "Nothing else touched": a dunning tenant keeps the plan it is being dunned for, its period
    // end, its add-on seats and its cancel flag. Only the four columns above may differ.
    for (
      const k of [
        "plan",
        "current_period_end",
        "gateway",
        "gateway_ref",
        "source",
        "seats_addon",
        "cancel_at_period_end",
        "payer_user_id",
        "dispute_state",
        "trial_end",
        "original_transaction_id",
      ]
    ) {
      assertEquals(s[k], before[k], `${event} must not touch ${k}`);
    }
    // 05 §5's meta cursor is (updated_at, id): a plan change that does not move updated_at never
    // reaches a device. Every applied change moves it.
    assertNotEquals(s.updated_at, before.updated_at);
    assertEquals(s.updated_at, r.clock.now);

    // A dunning event on a subscription with no period_end has nothing to measure 7 days from:
    // recorded, not applied, rather than an invented grace window (⚠️ SPEC, 0013).
    const r2 = rig();
    const t2 = seed(r2).tenant;
    const res2 = await handler(
      await post(r2, subBody({ event, at: T0, tenant: t2 }), "evt_y"),
      r2.deps,
    );
    assertEquals(await res2.json(), { ok: true, duplicate: false, applied: false });
    assertEquals(sub(r2, t2).status, "active");
    assertEquals(sub(r2, t2).grace_kind, null);
    assert(r2.db.billing_events.has("evt_y"));
  }
});

Deno.test("G-08-11 refunds 🔒 (ADR 2026-09-05g §11): a refund or chargeback ends entitlement now, clears both grace columns, records dispute_state — and deletes no row anywhere", async () => {
  for (
    const [event, state] of [
      ["refund.processed", "refunded"],
      ["payment.dispute.lost", "chargeback"],
      ["payment.dispute.created", "disputed"],
    ] as const
  ) {
    const r = rig();
    const { tenant } = seed(r, {
      plan: "family",
      status: "past_due",
      gateway: "razorpay",
      gateway_ref: "sub_syn_1",
      source: "razorpay",
      current_period_end: new Date(T0.getTime() + 30 * DAY),
      grace_kind: "dunning",
      grace_until: new Date(T0.getTime() + 37 * DAY),
      seats_addon: 2,
    });
    const before = { ...sub(r, tenant) };
    const rows = r.db.subscriptions.length;

    const res = await handler(
      await post(r, refundBody({ event, at: T0, tenant }), `evt_${event}`),
      r.deps,
    );
    assertEquals(await res.json(), { ok: true, duplicate: false, applied: true }, event);
    const s = sub(r, tenant);
    assertEquals(s.status, "expired", event);
    assertEquals(s.grace_until, null, "entitlement ends NOW: no grace survives a refund");
    assertEquals(s.grace_kind, null);
    assertEquals(s.dispute_state, state);
    // "data untouched": the tenant keeps what it bought — plan, period, payer, seats — so read and
    // export stay complete forever (08 §1.4). Only status, the two graces and dispute_state move.
    for (
      const k of [
        "plan",
        "current_period_end",
        "gateway",
        "gateway_ref",
        "source",
        "seats_addon",
        "payer_user_id",
        "trial_end",
      ]
    ) {
      assertEquals(s[k], before[k], `${event} must not touch ${k}`);
    }
    assertEquals(r.db.subscriptions.length, rows, "no subscription row is deleted");
    assert(r.db.billing_events.has(`evt_${event}`));
  }
});

Deno.test("G-08-9 the apply path is content-blind: it reads no envelope, no blob and no book (08 §5, 06 §10 🔒)", async () => {
  const r = rig();
  const { tenant } = seed(r);
  const tenantB = r.db.addTenant();
  r.db.addSubscription(tenantB, { plan: "family" });
  r.db.envelopes.push({
    envelope_id: crypto.randomUUID(),
    tenant_id: tenant,
    book_id: crypto.randomUUID(),
    object_id: crypto.randomUUID(),
    object_type: "entry",
    key_version: 1,
    suite_version: 1,
    payload_schema: 1,
    author_device: crypto.randomUUID(),
    hlc: 1n,
    blob_hash: new Uint8Array(32),
    size: 8,
    blob: new Uint8Array(8),
    blob_ref: null,
    seq: 1n,
  });
  const envelopes = r.db.envelopes.length;

  const { deps, calls } = spied(r);
  const res = await handler(
    await post(
      r,
      subBody({
        event: "subscription.activated",
        at: T0,
        tenant,
        plan: "family_plus",
        periodEnd: new Date(T0.getTime() + 30 * DAY),
      }),
      "evt_blind",
      false,
      deps,
    ),
    deps,
  );
  assertEquals(await res.json(), { ok: true, duplicate: false, applied: true });
  assertEquals(
    calls,
    ["applyBillingEvent"],
    "one store call, and it is the billing one: no bookAccess, no envelope read, no quota count",
  );
  assertEquals(r.db.envelopes.length, envelopes);
  // A webhook for one tenant never reaches another tenant's subscription.
  assertEquals(sub(r, tenantB).plan, "family");
  assertEquals(sub(r, tenantB).status, "active");
});
