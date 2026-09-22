// POST /billing-webhook — gateway events (08 §4 🔒; ADR 2026-09-05g §4, §9, §11).
//
// One request does four things, in this order and in ONE transaction (migration 0013):
//   1. verify the HMAC-SHA256 signature over the RAW body — before parsing anything;
//   2. read the event's type, its gateway timestamp and the subscription it names;
//   3. decide what that type MEANS in our vocabulary (`activate` / `dunning` / `end_now` /
//      `record_only` — the four of 08 §3 and ADR 2026-09-05g §4, §11, and no fifth);
//   4. hand the decision to rf.apply_billing_event, which dedupes on `event_id`, runs the
//      out-of-order guard and makes the one state change, or records and does nothing.
//
// Rule 4, and the reason this file has no logging at all: the body carries payer name, instrument
// and amount. It is hashed (BLAKE2b-256) for the audit trail and then dropped. Nothing about it
// reaches a log line, an error message or the response — the gateway learns `applied`, never WHY.
//
// The apply path touches `subscriptions` and `billing_events`. It never reads an envelope, a blob
// or a book: 08 §5 / 06 §10 🔒 "No API path counts, sums, or gates on envelope contents."
//
// ⚠️ SPEC — the gateway is NOT chosen. 08 §4 🔒 still reads "Razorpay or Cashfree (⚠️ pick by
// current UPI Autopay support + fees)". This file keeps the Razorpay shape the M4 stub had, but
// every gateway-specific string is a named constant below, so the pick is an edit to that block
// and to the event map — not to the state machine, which is ours and gateway-independent. Do not
// read this file as the decision having been made.
import { hex } from "../_shared/bytes.ts";
import { type Deps, serve } from "../_shared/deps.ts";
import { error, json } from "../_shared/http.ts";
import type { BillingAction, BillingEventApply } from "../_shared/store.ts";
import { blake2b256, constantTimeEqual, hmacSha256AnyKey } from "../_shared/sodium.ts";

const MAX_BODY = 256 * 1024;

// ---------------------------------------------------------------- gateway shape (⚠️ see above)
const GATEWAY = "razorpay";
/** `subscriptions.source` (03 §2.4 check: razorpay | apple | google | manual). Apple and Google
 *  events are the IAP path of ADR 2026-09-05g §8 and do not come through this route. */
const SOURCE = "razorpay";
const SIG_HEADER = "x-razorpay-signature";
const EVENT_ID_HEADER = "x-razorpay-event-id";
/** Razorpay stamps seconds since the epoch; ours is `Date`. */
const EVENT_AT_FIELD = "created_at";
const SUBSCRIPTION_ENTITY = "subscription";
const PAYMENT_ENTITY = "payment";
const REFUND_ENTITY = "refund";
/** `notes` is the only place a gateway-agnostic payload can carry OUR identifiers: the plan id and
 *  customer id at the gateway mean nothing here. Checkout writes both (08 §3.1). */
const NOTES_TENANT = "tenant_id";
const NOTES_PLAN = "plan";
/** Razorpay's end of the current cycle, seconds. */
const PERIOD_END_FIELD = "current_end";
const PAYMENT_OK = "captured";

/** Event type → what it means to us. Anything absent is `record_only`: recorded, never applied,
 *  never dropped. `subscription.updated` is deliberately absent — an update event does not say
 *  whether the change was an upgrade, a downgrade or a note edit, and guessing a plan from it
 *  would be exactly the invention CLAUDE.md rule 11 forbids; the daily reconciliation poll (ADR
 *  2026-09-05g §9) is what closes that gap. */
const EVENT_ACTIONS: Record<string, BillingAction> = {
  "subscription.activated": "activate",
  "subscription.charged": "activate", // downgraded to `dunning` below if the payment itself failed
  "subscription.resumed": "activate",
  "subscription.pending": "dunning", // Razorpay's failed-renewal state
  "subscription.halted": "dunning", // retries exhausted
  "payment.failed": "dunning",
  "refund.created": "end_now",
  "refund.processed": "end_now",
  "payment.dispute.created": "end_now",
  "payment.dispute.lost": "end_now",
};
/** `subscriptions.dispute_state` — what ended the entitlement. 03 §2.4 leaves the column free-text,
 *  so these three strings are ours; they are the only values this route ever writes. */
const DISPUTE_STATE: Record<string, string> = {
  "refund.created": "refunded",
  "refund.processed": "refunded",
  "payment.dispute.created": "disputed",
  "payment.dispute.lost": "chargeback",
};

const PLANS = new Set(["free", "personal", "family", "family_plus"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Obj = Record<string, unknown>;
const obj = (v: unknown): Obj | null =>
  typeof v === "object" && v !== null && !Array.isArray(v) ? v as Obj : null;
const str = (v: unknown): string | null => typeof v === "string" && v.length > 0 ? v : null;
/** Seconds since the epoch → Date. Refuses anything that is not a finite integer in a sane range,
 *  so a garbled field becomes "no timestamp" (recorded, not applied) rather than year 1970. */
function epochSeconds(v: unknown): Date | null {
  if (typeof v !== "number" || !Number.isFinite(v) || !Number.isInteger(v)) return null;
  if (v < 1_000_000_000 || v > 4_000_000_000) return null;
  return new Date(v * 1000);
}
/** `payload.<name>.entity`, the shape every Razorpay webhook uses. */
const entity = (body: Obj, name: string): Obj | null => obj(obj(obj(body.payload)?.[name])?.entity);

/** Everything the apply path needs, read from a body that has ALREADY been signature-verified.
 *  A field we cannot read becomes null; null narrows what the apply path will do (it refuses to
 *  apply without a tenant or a timestamp) and never widens it. */
function read(body: Obj, eventId: string, type: string, hash: Uint8Array): BillingEventApply {
  const sub = entity(body, SUBSCRIPTION_ENTITY);
  const pay = entity(body, PAYMENT_ENTITY);
  // A refund or dispute delivery carries no subscription entity at all — only the payment and the
  // refund. Razorpay copies a subscription's `notes` onto both, so `notes.tenant_id` is the one
  // identifier present on EVERY shape; without reading all three, ADR 2026-09-05g §11's "refund →
  // entitlement ends now" would silently resolve to no tenant and apply nothing (G-08-11).
  const notes = obj(sub?.notes) ?? obj(pay?.notes) ?? obj(entity(body, REFUND_ENTITY)?.notes);

  let action: BillingAction = EVENT_ACTIONS[type] ?? "record_only";
  // A `subscription.charged` whose payment did not succeed is a FAILED renewal, which 08 §3 🔒
  // puts in dunning grace — not an activation. Absent payment entity = the ordinary success shape.
  if (action === "activate" && pay && str(pay.status) !== null && str(pay.status) !== PAYMENT_OK) {
    action = "dunning";
  }

  const tenant = str(notes?.[NOTES_TENANT]);
  const plan = str(notes?.[NOTES_PLAN]);
  return {
    eventId,
    gateway: GATEWAY,
    type,
    hash,
    action,
    tenantId: tenant && UUID.test(tenant) ? tenant : null,
    eventAt: epochSeconds(body[EVENT_AT_FIELD]),
    plan: plan && PLANS.has(plan) ? plan : null,
    periodEnd: epochSeconds(sub?.[PERIOD_END_FIELD]),
    gatewayRef: str(sub?.id),
    source: SOURCE,
    // An Apple/Google original_transaction_id (03 §2.4) has no counterpart at a gateway; the IAP
    // route of ADR 2026-09-05g §8 is what fills that column, not this one.
    originalTransactionId: null,
    disputeState: action === "end_now" ? DISPUTE_STATE[type] ?? "disputed" : null,
  };
}

export async function handler(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") return error(405, "method_not_allowed");
  if (deps.webhookSecret.length === 0) return error(503, "webhook_unconfigured");
  const raw = new Uint8Array(await req.arrayBuffer());
  if (raw.length > MAX_BODY) return error(413, "too_large");
  const sigHex = req.headers.get(SIG_HEADER) ?? "";
  let sig: Uint8Array;
  try {
    sig = hex.dec(sigHex);
  } catch {
    return error(401, "bad_signature");
  }
  if (!(await constantTimeEqual(await hmacSha256AnyKey(deps.webhookSecret, raw), sig))) {
    return error(401, "bad_signature");
  }

  // Signature first, parse second: nothing below this line acts on bytes we have not authenticated.
  const hash = await blake2b256(raw);
  let body: Obj | null = null;
  try {
    body = obj(JSON.parse(new TextDecoder().decode(raw)));
  } catch {
    body = null;
  }
  const eventId = req.headers.get(EVENT_ID_HEADER) ?? str(body?.id);
  // No event id, no idempotency key — and an event we cannot dedupe must not be applied at all
  // (08 §4 🔒 "deduped on `event_id`"). Refused, so the gateway retries with one.
  if (!eventId) return error(400, "missing_event_id");
  const type = str(body?.event) ?? "unknown";

  // A signed body we could not parse is still a real delivery: record it (never a silent drop) and
  // apply nothing. Same for a type we do not know.
  const ev: BillingEventApply = body === null
    ? {
      eventId,
      gateway: GATEWAY,
      type: "malformed",
      hash,
      action: "record_only",
      tenantId: null,
      eventAt: null,
      plan: null,
      periodEnd: null,
      gatewayRef: null,
      source: SOURCE,
      originalTransactionId: null,
      disputeState: null,
    }
    : read(body, eventId, type, hash);

  const r = await deps.store.withClaims(null, (tx) => tx.applyBillingEvent(ev));
  // `outcome` stays server-side: telling the gateway "unknown_tenant" or "out_of_order" would tell
  // an attacker holding the webhook secret which tenants exist and how far their state has moved.
  return json(200, { ok: true, duplicate: !r.fresh, applied: r.applied });
}

if (import.meta.main) serve(handler);
