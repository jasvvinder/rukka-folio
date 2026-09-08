// POST /billing-webhook — gateway events (08; ADR 2026-09-05g §9). Stub until M13: verifies the
// HMAC-SHA256 signature over the raw body, dedupes by event id (billing_events.event_id), records a
// payload hash, and applies nothing yet. Idempotent replay answers 200 {duplicate: true}.
// Razorpay shape: header `x-razorpay-signature` = hex(HMAC-SHA256(secret, body)); event id in
// `x-razorpay-event-id`; body {event: "<type>", …}. Bodies are never logged (they carry payer data).
import { hex } from "../_shared/bytes.ts";
import { type Deps, serve } from "../_shared/deps.ts";
import { error, json } from "../_shared/http.ts";
import { blake2b256, constantTimeEqual, hmacSha256AnyKey } from "../_shared/sodium.ts";

const MAX_BODY = 256 * 1024;

export async function handler(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") return error(405, "method_not_allowed");
  if (deps.webhookSecret.length === 0) return error(503, "webhook_unconfigured");
  const raw = new Uint8Array(await req.arrayBuffer());
  if (raw.length > MAX_BODY) return error(413, "too_large");
  const sigHex = req.headers.get("x-razorpay-signature") ?? "";
  let sig: Uint8Array;
  try {
    sig = hex.dec(sigHex);
  } catch {
    return error(401, "bad_signature");
  }
  if (!(await constantTimeEqual(await hmacSha256AnyKey(deps.webhookSecret, raw), sig))) {
    return error(401, "bad_signature");
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return error(400, "bad_request");
  }
  const eventId = req.headers.get("x-razorpay-event-id") ??
    (typeof body.id === "string" ? body.id : null);
  const type = typeof body.event === "string" ? body.event : "unknown";
  if (!eventId) return error(400, "missing_event_id");

  const hash = await blake2b256(raw);
  const fresh = await deps.store.withClaims(
    null,
    (tx) => tx.recordBillingEvent(eventId, "razorpay", type, hash),
  );
  return json(200, { ok: true, duplicate: !fresh, applied: false }); // applied: false until M13 wires entitlements
}

if (import.meta.main) serve(handler);
