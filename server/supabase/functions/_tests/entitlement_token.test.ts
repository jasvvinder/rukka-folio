// The entitlement token on the meta channel — 08 §3 🔒 (Enforcement) and its line 35 🔒 (the token
// itself), ADR 2026-09-05g §1, §2, §4, §5, 04 §4 + §8 rule 6 🔒, 05 §5 🔒 (delivery).
//
// What these tests hold the server to, and why each one exists:
//
//   * A pull MINTS. Until 0014 nothing ever wrote an `entitlement_tokens` row: the relay path was
//     complete and every tenant was tokenless, which reads exactly like a working feature from the
//     wire. Every assertion below therefore starts from a real pull through the real handler and
//     reads the REAL stored bytes — never a payload the test built for itself.
//   * The payload is EXACTLY the 🔒 field set. An extra field in a signed payload is a new
//     protocol the client must be told about; a missing one silently disables enforcement.
//   * The signature is checked with `ed25519Verify` under the PINNED public half, and must fail
//     under another key, a flipped payload byte and a flipped signature byte — otherwise the test
//     would pass against an unsigned token.
//   * No tenant is ever locked out (ADR §1 🔒 "a tenant with no valid token is *Free*, never
//     *locked*") and no lapsed tenant is silently demoted to Free (ADR §5 🔒 "lapsed = read-only").
//   * A replayed pull is byte-stable, so 05 §5's `updated_at,id` cursor does not churn.
//
// Ids G-08-4, G-08-5, E-05-14 … E-05-18.
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { TOKEN_TTL_MS } from "../_shared/entitlement.ts";
import { PLAN_LIMITS } from "../_shared/registry.ts";
import {
  ed25519Verify,
  type EntitlementPayload,
  entitlementPublicKey,
  parseEntitlementToken,
  sodium,
} from "../_shared/sodium.ts";
import { handler as meta } from "../sync-meta/index.ts";
import { advance, body, ENTITLEMENT_SEED, get, member, reissue, type Rig, rig } from "./harness.ts";

const DAY = 86_400_000;

interface WireToken {
  id: string;
  tenant_id: string;
  token: string;
  expires_at: number;
  updated_at: number;
}
/** One real meta pull, through the handler, as a certified device. */
async function pull(r: Rig, token: string, after?: string): Promise<Record<string, unknown>> {
  return await body(
    await meta(
      get(`/sync-meta${after ? `?after=${encodeURIComponent(after)}` : ""}`, { token }),
      r.deps,
    ),
  );
}
/** The token rows the wire carried, decoded from base64url back to the stored bytes. */
function wireTokens(res: Record<string, unknown>): WireToken[] {
  return (res.entitlement_tokens ?? []) as WireToken[];
}
const tokenBytes = (w: WireToken) => b64url.dec(w.token);

Deno.test("G-08-4 08 §3 🔒 enforcement is server-attested: a meta pull by a certified device mints one entitlement token per active tenant, and the relay carries the signed bytes and their expiry and nothing about the key", async () => {
  const r = rig();
  const t1 = r.db.addTenant(), t2 = r.db.addTenant("business_group");
  const b1 = r.db.addBook(t1);
  const me = await member(r, t1, b1, "admin");
  r.db.addMembership(t2, me.user, "active");

  // Precondition, stated rather than assumed: nothing has ever written a token.
  assertEquals(r.db.entitlement_tokens.length, 0, "the store starts tokenless (0004 + 0005 alone)");

  const res = await pull(r, me.token);
  const rows = wireTokens(res);
  assertEquals(
    rows.map((w) => w.tenant_id).sort(),
    [t1, t2].sort(),
    "one token per ACTIVE tenant of the caller — 08 §3's 'server-attested plan state'",
  );
  for (const w of rows) {
    assertEquals(
      Object.keys(w).sort(),
      ["expires_at", "id", "tenant_id", "token", "updated_at"],
      "the relayed row is the token, its tenant, its expiry and the cursor — no key, no public half",
    );
    assert(tokenBytes(w).length > 0, "the token is real bytes, not an empty placeholder");
    assertEquals(
      w.expires_at,
      parseEntitlementToken(tokenBytes(w)).payload.exp,
      "the row's expires_at is the token's own exp — a row that outlives its token is a lie",
    );
  }
  // 04 §4 🔒 lists the public half as plaintext material PINNED IN THE APP; the response must not
  // contain it, or the pin is worthless.
  const pub = await entitlementPublicKey(ENTITLEMENT_SEED);
  const text = JSON.stringify(res);
  assert(!text.includes(b64url.enc(pub)), "the verification key is never served beside the token");
  assert(!text.includes(b64url.enc(ENTITLEMENT_SEED)), "and the seed appears nowhere at all");
});

Deno.test("G-08-5 08 §3 line 35 🔒: the payload is EXACTLY {tenant_id, plan, limits, period_end, grace_kind, iat, exp}, exp − iat ≤ 30 d, iat is the server's clock — and the Ed25519 signature verifies under the pinned public half and under nothing else", async () => {
  const r = rig();
  const t1 = r.db.addTenant();
  const me = await member(r, t1, r.db.addBook(t1), "admin");
  r.db.addSubscription(t1, {
    plan: "family",
    status: "active",
    current_period_end: new Date(r.clock.now.getTime() + 40 * DAY),
  });

  const [w] = wireTokens(await pull(r, me.token));
  const { payloadBytes, sig, payload } = parseEntitlementToken(tokenBytes(w));

  assertEquals(
    Object.keys(payload).sort(),
    ["exp", "grace_kind", "iat", "limits", "period_end", "plan", "tenant_id"],
    "exactly the 🔒 field set — no status, no grace_until, no key id, no issuer",
  );
  assertEquals(
    Object.keys(payload.limits).sort(),
    [
      "attachment_bytes",
      "business_books",
      "devices",
      "envelopes_per_book",
      "members",
      "tenant_bytes",
    ],
    "exactly ADR 2026-09-05g §1 🔒's six limits — 08 §2's per-file cap is not one of them",
  );
  assertEquals(payload.tenant_id, t1);
  assertEquals(payload.iat, r.clock.now.getTime(), "iat is the SERVER's clock, not the device's");
  assert(payload.exp > payload.iat, "a token that expires when it is minted is no token");
  assert(payload.exp - payload.iat <= 30 * DAY, "exp − iat ≤ 30 d (ADR 2026-09-05g §1 🔒)");
  assertEquals(payload.exp - payload.iat, TOKEN_TTL_MS);
  for (
    const v of [payload.iat, payload.exp, payload.period_end, ...Object.values(payload.limits)]
  ) {
    assert(v === null || Number.isSafeInteger(v), `integer everywhere, got ${v}`);
  }

  // The signature, checked the way the app will check it: detached, over the payload bytes as
  // received, under the PINNED public key.
  const pub = await entitlementPublicKey(ENTITLEMENT_SEED);
  assertEquals(pub.length, 32);
  assertEquals(sig.length, 64, "a 64-byte detached Ed25519 signature");
  assert(await ed25519Verify(payloadBytes, sig, pub), "verifies under the pinned public half");

  // …and fails everywhere else. Without these three the test above would pass on an unsigned blob.
  const other = (await sodium()).crypto_sign_seed_keypair(new Uint8Array(32).fill(99)).publicKey;
  assertEquals(
    await ed25519Verify(payloadBytes, sig, other),
    false,
    "another Ed25519 key must not verify this token",
  );
  const flippedPayload = new Uint8Array(payloadBytes);
  flippedPayload[flippedPayload.length - 3] ^= 0x01; // inside "exp": the number a forger would move
  assertEquals(
    await ed25519Verify(flippedPayload, sig, pub),
    false,
    "one flipped payload byte breaks the signature",
  );
  const flippedSig = new Uint8Array(sig);
  flippedSig[0] ^= 0x01;
  assertEquals(
    await ed25519Verify(payloadBytes, flippedSig, pub),
    false,
    "one flipped signature byte breaks the signature",
  );

  // The bytes on the wire are the canonical encoding sodium.ts's header documents, because the
  // client's verifier is written from that header alone.
  const wire = new TextDecoder().decode(tokenBytes(w));
  assertEquals(wire.split(".").length, 2, "<payload_b64url>.<sig_b64url>");
  assert(!wire.includes("="), "base64url, UNPADDED");
  assert(!/[+/]/.test(wire), "base64url alphabet, not standard base64");
  const json = new TextDecoder().decode(payloadBytes);
  assert(!/\s/.test(json), "canonical JSON: no whitespace");
  assert(
    json.startsWith('{"tenant_id":') &&
      json.endsWith(`,"iat":${payload.iat},"exp":${payload.exp}}`),
    `fixed key order, ADR 2026-09-05g §1's field order: ${json}`,
  );
});

Deno.test("E-05-14 plan state 🔒: no subscriptions row is a SIGNED Free token (never a lock, ADR 2026-09-05g §1), trial is 30 days of Family ending at trial_end (08 §2), and every plan carries 08 §2's own numbers", async (t) => {
  const r = rig();
  const free = r.db.addTenant(), trial = r.db.addTenant(), paid = r.db.addTenant();
  const me = await member(r, free, r.db.addBook(free), "admin");
  r.db.addMembership(trial, me.user, "active");
  r.db.addMembership(paid, me.user, "active");
  // `free` deliberately gets NO subscriptions row at all.
  const trialEnd = new Date(r.clock.now.getTime() + 21 * DAY);
  r.db.addSubscription(trial, { plan: "free", status: "trial", trial_end: trialEnd });
  r.db.addSubscription(paid, {
    plan: "family_plus",
    status: "active",
    current_period_end: new Date(r.clock.now.getTime() + 300 * DAY),
  });

  const rows = wireTokens(await pull(r, me.token));
  const by = new Map(
    rows.map((w) => [w.tenant_id, parseEntitlementToken(tokenBytes(w)).payload]),
  );
  assertEquals(by.size, 3);

  await t.step("a tenant with no subscription row is Free — and SIGNED, never silent", () => {
    const p = by.get(free)!;
    assertEquals(p.plan, "free");
    assertEquals(p.period_end, null, "no period was ever bought, so there is none to state");
    assertEquals(p.grace_kind, null);
    assertEquals(p.limits, PLAN_LIMITS.free);
    assertEquals(p.limits.envelopes_per_book, 10_000, "08 §2 🔒 Free");
    assertEquals(p.limits.tenant_bytes, 250 * 1024 * 1024);
    assertEquals(p.limits.attachment_bytes, 100 * 1024 * 1024);
    assertEquals(p.limits.devices, 5);
    assertEquals(p.limits.members, 1);
    assertEquals(p.limits.business_books, 1);
  });

  await t.step("trial = 30 days of Family, period_end = trial_end (08 §2 🔒)", () => {
    const p = by.get(trial)!;
    assertEquals(p.plan, "family", "the trial's LIMITS are Family's, whatever the row's plan says");
    assertEquals(p.limits, PLAN_LIMITS.family);
    assertEquals(p.limits.members, 5);
    assertEquals(p.limits.business_books, 3);
    assertEquals(p.limits.devices, 8);
    assertEquals(
      p.period_end,
      trialEnd.getTime(),
      "the trial IS the period: current_period_end is null on a trialling row",
    );
    assertEquals(p.grace_kind, null);
  });

  await t.step("Family+ carries Family+'s numbers, and ∞ is a sentinel, not a count", () => {
    const p = by.get(paid)!;
    assertEquals(p.plan, "family_plus");
    assertEquals(p.limits, PLAN_LIMITS.family_plus);
    assertEquals(p.limits.members, 15);
    assertEquals(p.limits.devices, 15);
    assertEquals(p.limits.envelopes_per_book, 1_000_000);
    assertEquals(p.limits.tenant_bytes, 15 * 1024 ** 3);
    assertEquals(p.limits.attachment_bytes, 20 * 1024 ** 3);
    assertEquals(p.limits.business_books, -1, "ADR §3 🔒 writes ∞; -1 is this codebase's sentinel");
  });
});

Deno.test("E-05-15 grace and lapse 🔒: a dunning row declares grace_kind 'dunning' with the row's period_end so the client can compute the 7 days (ADR 2026-09-05g §4), and an expired or refunded tenant keeps its PLAN — read-only, never silently Free (ADR §5 🔒)", async (t) => {
  const r = rig();
  const dunned = r.db.addTenant(), lapsed = r.db.addTenant(), refunded = r.db.addTenant();
  const me = await member(r, dunned, r.db.addBook(dunned), "admin");
  r.db.addMembership(lapsed, me.user, "active");
  r.db.addMembership(refunded, me.user, "active");

  const periodEnd = new Date(r.clock.now.getTime() - 2 * DAY); // renewal failed two days ago
  r.db.addSubscription(dunned, {
    plan: "family",
    status: "past_due",
    current_period_end: periodEnd,
    grace_kind: "dunning",
    grace_until: new Date(periodEnd.getTime() + 7 * DAY),
  });
  const lapsedEnd = new Date(r.clock.now.getTime() - 90 * DAY);
  r.db.addSubscription(lapsed, {
    plan: "personal",
    status: "expired",
    current_period_end: lapsedEnd,
  });
  // A refund inside a paid period: 0013's `end_now` leaves current_period_end in the FUTURE.
  const futureEnd = new Date(r.clock.now.getTime() + 25 * DAY);
  r.db.addSubscription(refunded, {
    plan: "family_plus",
    status: "expired",
    current_period_end: futureEnd,
    dispute_state: "refunded",
  });

  const by = new Map(
    wireTokens(await pull(r, me.token)).map((w) => [
      w.tenant_id,
      parseEntitlementToken(tokenBytes(w)).payload,
    ]),
  );

  await t.step(
    "dunning: grace_kind + the row's period_end, and the plan it is being dunned for",
    () => {
      const p = by.get(dunned)!;
      assertEquals(p.grace_kind, "dunning");
      assertEquals(p.plan, "family", "a dunned tenant keeps the plan it is being dunned for");
      assertEquals(p.limits, PLAN_LIMITS.family);
      assertEquals(
        p.period_end,
        periodEnd.getTime(),
        "the client computes period_end + 7 d itself — ADR §4 🔒 fixes the window, not the server",
      );
      assert(
        !JSON.stringify(p).includes("grace_until"),
        "grace_until is NOT in the 🔒 field set (08 §3 line 35); reported as an ADR §1 vs §4 conflict",
      );
    },
  );

  await t.step("lapsed: the row's plan and its past period_end, never 'free'", () => {
    const p = by.get(lapsed)!;
    assertEquals(p.plan, "personal", "ADR §5 🔒 lapsed = read-only + export forever, not Free");
    assertNotEquals(p.plan, "free");
    assertEquals(p.limits, PLAN_LIMITS.personal);
    assertEquals(p.period_end, lapsedEnd.getTime());
    assert(p.period_end! < p.iat, "the period is over: that is how the client sees read-only");
    assertEquals(p.grace_kind, null, "a lapse is not a grace");
  });

  await t.step(
    "a refund inside a paid period ends entitlement NOW (ADR §11 🔒), keeping the plan",
    () => {
      const p = by.get(refunded)!;
      assertEquals(p.plan, "family_plus", "what the tenant bought stays on the record");
      assertEquals(
        p.period_end,
        p.iat,
        "clamped to iat: emitting the untouched future period_end would tell the client a refunded tenant is still inside its paid period",
      );
      assert(p.period_end! <= p.iat);
    },
  );
});

Deno.test("E-05-16 refresh 🔒 (ADR 2026-09-05g §1): a token is minted when none is stored, when the stored one has expired, and when the subscription moved after it was signed — and is otherwise served UNCHANGED, so a replayed pull is byte-stable and 05 §5's cursor does not churn", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const me = await member(r, tenant, r.db.addBook(tenant), "admin");
  r.db.addSubscription(tenant, {
    plan: "personal",
    status: "active",
    current_period_end: new Date(r.clock.now.getTime() + 200 * DAY),
  });

  const [first] = wireTokens(await pull(r, me.token));
  const firstBytes = tokenBytes(first);

  await t.step(
    "a second pull moments later re-serves the SAME bytes and the same cursor",
    async () => {
      advance(r, 60_000);
      const [again] = wireTokens(await pull(r, me.token));
      assertEquals(again.token, first.token, "not re-signed: a fresh iat every pull is churn");
      assertEquals(again.updated_at, first.updated_at, "05 §5's cursor stood still");
      assertEquals(
        again.id,
        first.id,
        "one row per tenant, replaced in place — never a second row",
      );
      assertEquals(r.db.entitlement_tokens.length, 1);
    },
  );

  await t.step("a plan change re-mints, because what we signed is now out of date", async () => {
    advance(r, DAY);
    const sub = r.db.subscriptions.find((s) => s.tenant_id === tenant)!;
    sub.plan = "family";
    sub.updated_at = r.clock.now; // 0013's apply path always touches it (the subscriptions_touch trigger)
    advance(r, 1000);

    const [fresh] = wireTokens(await pull(r, await reissue(r, me)));
    assertNotEquals(fresh.token, first.token);
    const p = parseEntitlementToken(tokenBytes(fresh)).payload;
    assertEquals(p.plan, "family");
    assertEquals(p.limits, PLAN_LIMITS.family);
    assertEquals(p.iat, r.clock.now.getTime());
    assert(fresh.updated_at > first.updated_at, "the cursor moved, so the device will pull it");
    assertEquals(r.db.entitlement_tokens.length, 1, "replaced, not appended");
  });

  await t.step("an expired stored token is re-minted even with nothing else changed", async () => {
    const before = wireTokens(await pull(r, me.token))[0];
    advance(r, TOKEN_TTL_MS + 1000); // past exp
    const after = wireTokens(await pull(r, await reissue(r, me)))[0];
    assertNotEquals(after.token, before.token, "an expired token is no token (ADR §1 🔒)");
    const p = parseEntitlementToken(tokenBytes(after)).payload;
    assertEquals(p.iat, r.clock.now.getTime());
    assert(p.exp > p.iat);
  });

  await t.step("and the very first pull really did mint — the store was empty before it", () => {
    assert(firstBytes.length > 0);
    assertEquals(parseEntitlementToken(firstBytes).payload.plan, "personal");
  });
});

Deno.test("E-05-17 isolation 🔒 (05 §5, ADR 2026-09-05d §2): a device of tenant B never receives tenant A's token, and an UNCERTIFIED device is minted nothing at all", async (t) => {
  const r = rig();
  const a = r.db.addTenant(), b = r.db.addTenant();
  const alice = await member(r, a, r.db.addBook(a), "admin");
  const bob = await member(r, b, r.db.addBook(b), "admin");
  r.db.addSubscription(a, {
    plan: "family_plus",
    status: "active",
    current_period_end: new Date(r.clock.now.getTime() + 100 * DAY),
  });

  const mine = wireTokens(await pull(r, alice.token));
  assertEquals(mine.map((w) => w.tenant_id), [a]);

  await t.step("tenant B's certified device sees only its own", async () => {
    const theirs = wireTokens(await pull(r, bob.token));
    assertEquals(theirs.map((w) => w.tenant_id), [b], "B gets B's, and B's alone");
    assertNotEquals(theirs[0].token, mine[0].token);
    assertEquals(parseEntitlementToken(tokenBytes(theirs[0])).payload.tenant_id, b);
    assertEquals(parseEntitlementToken(tokenBytes(theirs[0])).payload.plan, "free");
  });

  await t.step("an uncertified device of tenant A is minted nothing (05d §2 🔒)", async () => {
    const stored = r.db.entitlement_tokens.length;
    const pending = await member(r, a, null, null, { status: "registered" });
    const res = await pull(r, pending.token);
    assertEquals(wireTokens(res).length, 0, "no token reaches a device the server does not trust");
    assertEquals(
      r.db.entitlement_tokens.length,
      stored,
      "and none was minted for it either — a token is an entitlement statement, not a greeting",
    );
  });

  await t.step("nothing about the ledger reached the mint path", () => {
    // The whole pull ran with an empty envelope store and a book the caller can write: the token
    // is plan metadata (04 §4 🔒), so no envelope, blob or wrapped key can have been read.
    assertEquals(r.db.envelopes.length, 0);
  });
});

Deno.test("E-05-18 the signer is the 04 §8 rule-6 🔒 guard: it refuses a payload that is not a 30-day entitlement, and refuses a seed that is not the 32-byte entitlement_key", async () => {
  const { signEntitlementToken } = await import("../_shared/sodium.ts");
  const base: EntitlementPayload = {
    tenant_id: "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    plan: "family",
    limits: { ...PLAN_LIMITS.family },
    period_end: 1_760_000_000_000,
    grace_kind: null,
    iat: 1_759_000_000_000,
    exp: 1_759_000_000_000 + TOKEN_TTL_MS,
  };
  assert((await signEntitlementToken(base, ENTITLEMENT_SEED)).length > 0);

  const rejects = async (p: EntitlementPayload, why: string) => {
    let threw = false;
    try {
      await signEntitlementToken(p, ENTITLEMENT_SEED);
    } catch {
      threw = true;
    }
    assert(threw, why);
  };
  await rejects({ ...base, exp: base.iat + TOKEN_TTL_MS + 1 }, "exp − iat > 30 d (ADR §1 🔒)");
  await rejects({ ...base, exp: base.iat }, "a token that expires at issue");
  await rejects({ ...base, iat: base.iat + 0.5 }, "a float timestamp (CLAUDE.md rule 1)");
  await rejects(
    { ...base, limits: { ...base.limits, members: 5.5 } },
    "a float limit",
  );
  await rejects({ ...base, tenant_id: "not-a-uuid" }, "a tenant_id that is not a uuid");
  await rejects(
    { ...base, grace_kind: "offline" as unknown as "dunning" },
    "a grace_kind 03 §2.4 🔒 does not allow",
  );

  let threw = false;
  try {
    await signEntitlementToken(base, new Uint8Array(16).fill(1));
  } catch {
    threw = true;
  }
  assert(threw, "a seed that is not 32 bytes is not entitlement_key");
});
