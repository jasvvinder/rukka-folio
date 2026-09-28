// The entitlement token's POLICY — which plan a subscription row means, which limits that plan
// carries, and when a stored token has to be minted again. The crypto (canonical bytes, signature,
// wire format) lives in sodium.ts; the numbers live in registry.ts's PLAN_LIMITS. Nothing here
// reads an envelope, a blob or a wrapped key: the server signs plan metadata it already holds
// (04 §8 rule 6 🔒, ADR 2026-09-05g §1 🔒).
//
// 🔒 sources, and the one rule each: 08 §3 + ADR 2026-09-05g §1 as amended by ADR 2026-09-24b §6
// (the field set, now with `grace_until`; exp − iat ≤ 30 d; "a tenant with no valid token is
// *Free*, never *locked*"), ADR 05g §3 (the numbers), §4 (dunning grace is server-declared), §5
// (lapsed = read-only, never Free), ADR 2026-09-24b §7 (lapsed ⇒ period_end = iat; unlimited =
// -1; no key id), 08 §2 (trial = 30 days of Family).
import { type Plan, PLAN_LIMITS } from "./registry.ts";
import { type EntitlementPayload, TOKEN_MAX_TTL_MS } from "./sodium.ts";
import type { EntitlementState } from "./store.ts";

/** Every token this server mints lives the full 30 days ADR 2026-09-05g §1 🔒 allows. It is a
 *  ceiling on staleness, not on entitlement: `period_end` says when the PLAN ends, `exp` only says
 *  when the client must have heard from us again, and 08 §3's offline grace runs from the last
 *  token seen — so a shorter life would put a phone off-network into read-only sooner than §4 🔒
 *  allows, and a longer one would breach §1. */
export const TOKEN_TTL_MS = TOKEN_MAX_TTL_MS;

const PLAN_NAMES = new Set<string>(["free", "personal", "family", "family_plus"]);

/** The plan a subscription row means, for the token. Never throws and never guesses: a row whose
 *  `plan` this build does not know is read as `free`, which is the floor ADR §1 🔒 already names
 *  for a tenant with no token at all — it can never invent entitlement. */
function planOf(state: EntitlementState): Plan {
  // 08 §2 🔒: "Trial: 30 days of Family". A trialling tenant gets Family's limits whatever its row
  // says its plan is, because the row's `plan` on trial is whatever the signup wrote there.
  if (state.status === "trial") return "family";
  const p = state.plan ?? "free";
  return PLAN_NAMES.has(p) ? p as Plan : "free";
}

/** The `period_end` the token carries, in epoch ms, or null.
 *
 *  - trial            → `trial_end` (the trial IS the period; 08 §2 🔒)
 *  - dunning/past_due → `current_period_end`, unchanged. The grace's END is not derived from it:
 *    the token declares it in `grace_until` (ADR 2026-09-24b §6 🔒; see graceUntilOf).
 *  - expired/refunded → `current_period_end`, CLAMPED to `iat` — ADR 2026-09-24b §7 (a) 🔒: "a
 *    lapsed tenant (`subscriptions.status = 'expired'`, refund or chargeback included) is minted
 *    with `period_end` clamped to `iat`, so a refunded tenant can never read as paid". 0013's
 *    `end_now` leaves `current_period_end` where it was (ADR 2026-09-05g §11 🔒 "data untouched"),
 *    which can be in the FUTURE. The plan itself is never rewritten to `free` (ADR 05g §5 🔒:
 *    lapsed is read-only, not Free).
 *  - expired with NO `current_period_end` → `iat`, never null. 08 §3 🔒 reads "lapsed ⇒
 *    `period_end = iat`" with no exception, and 0013's `end_now` neither requires nor sets the
 *    column, so a row that never had a period (a trial ended by `end_now`) lapses with it null.
 *    Passing that null through would mint the lapsed tenant's plan with no end at all, so nothing
 *    in the token would say the period is over (period_end ≤ iat is how the client reads
 *    read-only); §7 (a) exists to rule that out. */
function periodEndOf(state: EntitlementState, iat: number): number | null {
  if (state.status === "trial") return state.trial_end?.getTime() ?? null;
  const end = state.current_period_end?.getTime() ?? null;
  if (state.status === "expired") return end === null ? iat : Math.min(end, iat);
  return end;
}

/** ADR 2026-09-05g §4 🔒: the dunning grace is "server-declared in the token (`grace_kind =
 *  dunning`, `grace_until`)" — which ADR 2026-09-24b §6 🔒 made literal by adding `grace_until` to
 *  the field set. Any other value in the column reads as no grace (03 §2.4 🔒 names one kind). */
function graceKindOf(state: EntitlementState): "dunning" | null {
  return state.grace_kind === "dunning" ? "dunning" : null;
}

/** ADR 2026-09-24b §6 🔒: "`grace_until` is null unless `grace_kind = dunning`, in which case it
 *  is `subscriptions.grace_until`." The server DECLARES the date and the client never derives
 *  `period_end + 7 d`: the 7 days are only the gateway default 0013 writes, and a store-run
 *  channel (IAP) may carry its own grace length. So the column is copied, never recomputed here.
 *
 *  A dunning row whose `grace_until` is null (0013 always writes both together, so only a hand
 *  edit produces one) is minted with `grace_until: null` — the server states what it holds and
 *  invents no date. ⚠️ SPEC (M11-SRV1): ADR 24b §6 does not say what the client does with dunning
 *  + null; reported rather than filled with period_end + 7 d, which is the derivation §6 forbids. */
function graceUntilOf(state: EntitlementState): number | null {
  if (graceKindOf(state) !== "dunning") return null;
  return state.grace_until?.getTime() ?? null;
}

/** The token payload for one tenant, at one server instant. Pure: same state + same `now` → the
 *  same bytes. `iat` is the SERVER's clock (08 §3's clock floor is the CLIENT's problem, 🔒 §4). */
export function entitlementFor(state: EntitlementState, now: Date): EntitlementPayload {
  const iat = now.getTime();
  const plan = planOf(state);
  return {
    tenant_id: state.tenant_id,
    plan,
    limits: { ...PLAN_LIMITS[plan] },
    period_end: periodEndOf(state, iat),
    grace_kind: graceKindOf(state),
    grace_until: graceUntilOf(state),
    iat,
    exp: iat + TOKEN_TTL_MS,
  };
}

/** The re-mint rule (ADR 2026-09-05g §1 🔒 "refreshed on every meta pull" — refreshed, not
 *  re-signed: a token that is still current is served unchanged, so a replayed pull is byte-stable
 *  and 05 §5's `updated_at,id` cursor does not churn).
 *
 *  Mint when, and only when:
 *    1. nothing is stored for the tenant — including a brand-new tenant that has never paid, which
 *       still gets a signed Free token (ADR §1 🔒 "a tenant with no valid token is *Free*, never
 *       *locked*" — the client must be able to tell "Free" from "we heard nothing");
 *    2. the stored token has expired (exp is 30 d, so this fires at most monthly); or
 *    3. `subscriptions.updated_at` is newer than the stored token's `created_at` — the plan moved
 *       (0013's apply path always touches `updated_at`), so what we signed is out of date.
 *  Both clocks in rule 3 are the DATABASE's, because `created_at` and `subscriptions.updated_at`
 *  are both written by Postgres `now()`; mixing in the edge clock would make the rule flap. */
export function needsMint(state: EntitlementState, now: Date): boolean {
  if (!state.token_created_at || !state.token_expires_at) return true;
  if (state.token_expires_at.getTime() <= now.getTime()) return true;
  return state.sub_updated_at !== null &&
    state.sub_updated_at.getTime() > state.token_created_at.getTime();
}
