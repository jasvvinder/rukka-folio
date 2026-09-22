// The entitlement token's POLICY — which plan a subscription row means, which limits that plan
// carries, and when a stored token has to be minted again. The crypto (canonical bytes, signature,
// wire format) lives in sodium.ts; the numbers live in registry.ts's PLAN_LIMITS. Nothing here
// reads an envelope, a blob or a wrapped key: the server signs plan metadata it already holds
// (04 §8 rule 6 🔒, ADR 2026-09-05g §1 🔒).
//
// 🔒 sources, and the one rule each: 08 §3 line 35 + ADR 2026-09-05g §1 (the field set, exp − iat
// ≤ 30 d, "a tenant with no valid token is *Free*, never *locked*"), §3 (the numbers), §4 (dunning
// grace is server-declared: 7 days from period_end), §5 (lapsed = read-only, never Free), 08 §2
// (trial = 30 days of Family).
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
 *  - dunning/past_due → `current_period_end`, unchanged. ADR 2026-09-05g §4 🔒 measures the 7-day
 *    dunning grace "from `period_end`", and the token says `grace_kind = 'dunning'`, so the client
 *    computes period_end + 7 d itself. (See the ⚠️ SPEC below on `grace_until`.)
 *  - expired/refunded → `current_period_end`, CLAMPED to `iat`. ADR 2026-09-05g §11 🔒 is explicit
 *    that a refund or chargeback means "entitlement ends now", and 0013's `end_now` deliberately
 *    leaves `current_period_end` where it was so 08 §1.4's read-only + export forever still knows
 *    what the tenant bought. Emitting that untouched future date would tell the client the tenant
 *    is still inside its paid period — the one reading that grants MORE entitlement than the docs
 *    do. The plan itself is never rewritten to `free` (ADR §5 🔒: lapsed is read-only, not Free).
 *    ⚠️ SPEC (M13-TOK1, 22 Sep): the 🔒 field set carries no `status`, so "lapsed" reaches the
 *    client only as a `period_end` in the past. Reported. */
function periodEndOf(state: EntitlementState, iat: number): number | null {
  if (state.status === "trial") return state.trial_end?.getTime() ?? null;
  const end = state.current_period_end?.getTime() ?? null;
  if (state.status === "expired" && end !== null) return Math.min(end, iat);
  return end;
}

/** ⚠️ SPEC (M13-TOK1, 22 Sep): ADR 2026-09-05g §4 🔒 says the dunning grace is "server-declared in
 *  the token (`grace_kind = dunning`, `grace_until`)", but the 🔒 field set in the SAME ADR §1 and
 *  in 08 §3 line 35 — the normative field list — has no `grace_until`. Conservative reading
 *  (CLAUDE.md § Workflow): emit the field set exactly as 🔒 specified, and let the client derive
 *  period_end + 7 d, which §4 🔒 fixes as the window. Reported to the owner; adding a field to a
 *  signed 🔒 payload is not a lane's call. */
function graceKindOf(state: EntitlementState): "dunning" | null {
  return state.grace_kind === "dunning" ? "dunning" : null;
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
