// billing-webhook stub (08; ADR 2026-09-05g §9). Id E-05-12.
import { assertEquals } from "@std/assert";
import { hex } from "../_shared/bytes.ts";
import { hmacSha256AnyKey } from "../_shared/sodium.ts";
import { handler } from "../billing-webhook/index.ts";
import { rig } from "./harness.ts";

async function signed(
  r: ReturnType<typeof rig>,
  bodyText: string,
  eventId: string,
  tamper = false,
) {
  const sig = hex.enc(
    await hmacSha256AnyKey(
      r.deps.webhookSecret,
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

Deno.test("E-05-12 billing-webhook: signature verified over the raw body; idempotent by event id; applies nothing yet", async () => {
  const r = rig();
  const text = JSON.stringify({
    event: "payment.captured",
    payload: { payment: { entity: { id: "pay_x", amount: 49900 } } },
  });
  const first = await handler(await signed(r, text, "evt_1"), r.deps);
  assertEquals(first.status, 200);
  assertEquals(await first.json(), { ok: true, duplicate: false, applied: false });
  const replay = await handler(await signed(r, text, "evt_1"), r.deps);
  assertEquals(await replay.json(), { ok: true, duplicate: true, applied: false });
  assertEquals(r.db.billing_events.size, 1);
  assertEquals((await handler(await signed(r, text, "evt_2", true), r.deps)).status, 401);
  assertEquals(r.db.billing_events.size, 1, "an unsigned event is not recorded");
  const noSig = new Request("https://edge.local/functions/v1/billing-webhook", {
    method: "POST",
    body: text,
  });
  assertEquals((await handler(noSig, r.deps)).status, 401);
  assertEquals(r.db.subscriptions.length, 0, "stub: no entitlement change until M13");
  const unconfigured = { ...r.deps, webhookSecret: new Uint8Array(0) };
  assertEquals((await handler(await signed(r, text, "evt_3"), unconfigured)).status, 503);
});
