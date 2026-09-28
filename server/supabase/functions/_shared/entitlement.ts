// The entitlement token's POLICY — which plan a subscription row means, which limits and extras
// that plan carries, and when a stored token has to be minted again. The crypto (canonical bytes,
// signature, wire format) lives in sodium.ts; the numbers live in the plan catalogue (0018), read
// per request into registry.ts's PlanCatalogue. Nothing here reads an envelope, a blob or a wrapped
// key: the server signs plan metadata it already holds (04 §8 rule 6 🔒, ADR 2026-09-05g §1 🔒).
//
// 🔒 sources, and the one rule each: 08 §3 + ADR 2026-09-05g §1 as amended by ADR 2026-09-24b §6
// and ADR 2026-09-25 §6 (the field set, now with `grace_until` and `features`; exp − iat ≤ 30 d;
// "a tenant with no valid token is *Free*, never *locked*"), ADR 2026-09-25 §6 (the numbers and
// extras are catalogue data; `plan` is a catalogue id), ADR 05g §4 (dunning grace is
// server-declared), §5 (lapsed = read-only, never Free), ADR 2026-09-24b §7 (lapsed ⇒ period_end =
// iat; unlimited = -1; no key id), ADR 2026-09-25 §5 (the trial runs on the entity type's popular
// plan — superseding 08 §2's "30 days of Family").
import { type CataloguePlan, type Feature, FEATURES, type PlanCatalogue } from "./registry.ts";
import {
  type EntitlementPayload,
  entitlementPayloadBytes,
  parseEntitlementToken,
  TOKEN_MAX_TTL_MS,
} from "./sodium.ts";
import type { EntitlementState } from "./store.ts";

/** Every token this server mints lives the full 30 days ADR 2026-09-05g §1 🔒 allows. It is a
 *  ceiling on staleness, not on entitlement: `period_end` says when the PLAN ends, `exp` only says
 *  when the client must have heard from us again, and 08 §3's offline grace runs from the last
 *  token seen — so a shorter life would put a phone off-network into read-only sooner than §4 🔒
 *  allows, and a longer one would breach §1. */
export const TOKEN_TTL_MS = TOKEN_MAX_TTL_MS;

/** The catalogue row a subscription row means, for the token. Never throws on a row and never
 *  guesses: no row, or a plan the catalogue does not hold, reads as the floor (`free`), which ADR
 *  §1 🔒 already names for a tenant with no token at all — it can never invent entitlement.
 *
 *  A trialling row is NOT special-cased. ADR 2026-09-25 §5 🔒: "The trial always runs on the entity
 *  type's **popular** plan" — and rf.start_trial (0018) writes that plan onto `subscriptions.plan`
 *  when it starts the trial, so the row's plan IS the trial's plan, and the token, the push quota
 *  and the device cap all read one row. (08 §2's "Trial: 30 days of Family", which this function
 *  used to hard-code whatever the row said, is superseded by ADR 25 §5.)
 *
 *  ⚠️ SPEC (open, owner — M11-CAT1 repair): a Family, Business or Trust tenant with NO subscription
 *  row reads as this floor too, i.e. Individual's permanent Free (`plan: "free"`, `period_end:
 *  null`). Two rulings meet here and neither names this case:
 *    - ADR 2026-09-05g §1 🔒: "a tenant with no valid token is *Free*, never *locked*" — the floor
 *      this function has always returned;
 *    - ADR 2026-09-25 §5 🔒 (newer): "Family, Business and Trust have **no Free plan** and a 30-day
 *      trial … When it ends unpaid, the shared books go read-only (08 §1)". It rules the
 *      trial-ENDED case (a row exists, status `trial`, `trial_end` passed) and not the tenant that
 *      never had a row.
 *  The case is reachable, not theoretical: G-25-3's karta is refused `trial_consumed` on his
 *  business tenant (once per person, ADR 05g §12), and a tenant exists without a row between its
 *  creation and its admin's first trial call. Reading ADR 25 §5 onto it would mean choosing a
 *  state it does not name — a read-only token for a plan the tenant never had, with a `plan` id
 *  the ruling does not supply — so this is left as it was and reported rather than picked
 *  (CLAUDE.md rule 11, § Precedence "do not pick one"). What the floor grants such a tenant is the
 *  least any seeded plan grants (1 member, the personal book only, no statement import, no PDF
 *  output) and never a paid plan or a trial — but it is WRITABLE and has no end, where ADR 25 §5's
 *  trial-ended reading would be read-only. That difference is the owner's call. The ruling
 *  replaces this branch; G-25-3's last step pins the present reading so the ruling flips a test. */
function planOf(state: EntitlementState, catalogue: PlanCatalogue): CataloguePlan {
  return catalogue.resolve(state.plan);
}

/** The row's extras in the token's one encoding — sorted, unique, and only names a plan may gate
 *  (ADR 2026-09-25 §5–§6). 0018's CHECK already refuses any other name; filtering again here means
 *  a hand-edited row can only ever LOSE an extra on its way into a signature, never gain one. */
function featuresOf(p: CataloguePlan): Feature[] {
  const held = new Set<string>(p.features);
  return FEATURES.filter((f) => held.has(f));
}

/** The `period_end` the token carries, in epoch ms, or null.
 *
 *  - trial            → `trial_end` (the trial IS the period; ADR 2026-09-25 §5's 30 days, set by
 *                       rf.start_trial)
 *  - dunning/past_due → `current_period_end`, unchanged. The grace's END is not derived from it:
 *                       the token declares it in `grace_until` (ADR 2026-09-24b §6 🔒).
 *  - expired/refunded → `current_period_end` clamped to `iat` — ADR 2026-09-24b §7 (a) 🔒: "a
 *                       lapsed tenant … is minted with `period_end` clamped to `iat`". 0013's
 *                       `end_now` leaves the column where it was (ADR 2026-09-05g §11 🔒 "data
 *                       untouched"), which can be in the future; the plan itself is never rewritten
 *                       to `free` (ADR 05g §5 🔒: lapsed is read-only, not Free).
 *  - expired with NO `current_period_end` → `iat`, never null: 08 §3 🔒 "lapsed ⇒ `period_end =
 *                       iat`" has no exception, and a null end would leave nothing in the token
 *                       saying the period is over. */
function periodEndOf(state: EntitlementState, iat: number): number | null {
  if (state.status === "trial") return state.trial_end?.getTime() ?? null;
  const end = state.current_period_end?.getTime() ?? null;
  if (state.status === "expired") return end === null ? iat : Math.min(end, iat);
  return end;
}

/** ADR 2026-09-05g §4 🔒: the dunning grace is "server-declared in the token (`grace_kind =
 *  dunning`, `grace_until`)", made literal by ADR 2026-09-24b §6 🔒. Any other value in the column
 *  reads as no grace (03 §2.4 🔒 names one kind). */
function graceKindOf(state: EntitlementState): "dunning" | null {
  return state.grace_kind === "dunning" ? "dunning" : null;
}

/** ADR 2026-09-24b §6 🔒: "`grace_until` is null unless `grace_kind = dunning`, in which case it
 *  is `subscriptions.grace_until`." The server declares the date and the client never derives
 *  `period_end + 7 d` (the 7 days are only the gateway default 0013 writes; a store-run channel
 *  may carry its own length), so the column is copied, never recomputed here. A dunning row whose
 *  column is null — 0013 always writes the two together, so only a hand edit makes one — is minted
 *  with `grace_until: null`: the server states what it holds, and §6's "in which case it is
 *  `subscriptions.grace_until`" is exactly that value. ⚠️ SPEC (M11-SRV1, still open): ADR 24b §6
 *  rules the server's value but not what the CLIENT does with dunning + null; kept as reported
 *  rather than filled with period_end + 7 d, the derivation §6 forbids. */
function graceUntilOf(state: EntitlementState): number | null {
  if (graceKindOf(state) !== "dunning") return null;
  return state.grace_until?.getTime() ?? null;
}

/** The token payload for one tenant, at one server instant. Pure: same state + same catalogue +
 *  same `now` → the same bytes. `iat` is the SERVER's clock (08 §3's clock floor is the CLIENT's
 *  problem, 🔒 §4). */
export function entitlementFor(
  state: EntitlementState,
  catalogue: PlanCatalogue,
  now: Date,
): EntitlementPayload {
  const iat = now.getTime();
  const plan = planOf(state, catalogue);
  return {
    tenant_id: state.tenant_id,
    plan: plan.id,
    limits: { ...plan.limits },
    features: featuresOf(plan),
    period_end: periodEndOf(state, iat),
    grace_kind: graceKindOf(state),
    grace_until: graceUntilOf(state),
    iat,
    exp: iat + TOKEN_TTL_MS,
  };
}

/** What a stored token signed: its canonical payload bytes and its `iat`, or null when the stored
 *  bytes are not a token this server can read (never trusted, only compared — the server does not
 *  need to verify its own signature to know what it wrote). */
function storedPayload(token: Uint8Array | null): { bytes: Uint8Array; iat: number } | null {
  if (token === null || token.length === 0) return null;
  try {
    const { payloadBytes, payload } = parseEntitlementToken(token);
    return Number.isSafeInteger(payload.iat) ? { bytes: payloadBytes, iat: payload.iat } : null;
  } catch {
    return null;
  }
}

function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

/** The re-mint rule (ADR 2026-09-05g §1 🔒 "refreshed on every meta pull" — refreshed, not
 *  re-signed: a token that is still current is served unchanged, so a replayed pull is byte-stable
 *  and 05 §5's `updated_at,id` cursor does not churn).
 *
 *  Mint when, and only when:
 *    1. nothing is stored for the tenant — including a brand-new tenant that has never paid, which
 *       still gets a signed Free token (ADR §1 🔒 "a tenant with no valid token is *Free*, never
 *       *locked*" — the client must be able to tell "Free" from "we heard nothing");
 *    2. the stored token has expired (exp is 30 d, so this fires at most monthly);
 *    3. `subscriptions.updated_at` is newer than the stored token's `created_at` — the plan moved
 *       (0013's apply path and 0018's rf.start_trial always touch `updated_at`); or
 *    4. the stored token no longer SAYS what this server would sign for the tenant at that token's
 *       own `iat`: its canonical payload bytes differ from `entitlementFor(state, catalogue, iat)`'s.
 *       ADR 2026-09-25 §6 🔒: "moving a feature between plans takes effect at the next sync".
 *
 *  Rule 4 compares CONTENT, never clocks. It used to compare `plan_catalogue.updated_at` with the
 *  token's `created_at`, and both are Postgres `now()` — the START of their transactions, not their
 *  commits. A pull that began after a catalogue change began, but read the catalogue before that
 *  change committed, signed the OLD features with a `created_at` later than the row's new
 *  `updated_at`, and the timestamp rule then never fired again until the 30-day expiry. Until the
 *  console exists a catalogue change is a migration, one transaction (ADR 25 §6), so that window
 *  was the migration's whole length. A byte comparison has no window: whatever a pull read, the
 *  first pull after the change commits sees a token that differs from what the row now means.
 *  The same comparison also closes rule 3's twin of that race (a billing or trial transaction
 *  still open while a pull reads the old subscription row), since every field the subscription
 *  row feeds — plan, period_end, grace_kind, grace_until — is in the bytes. Rule 3 is kept as the
 *  cheap early exit it always was. Re-minting at the stored `iat` is exact because
 *  `entitlementFor` is pure: an unchanged state and catalogue reproduce the stored bytes (the
 *  lapsed clamp `min(end, iat)` included), so a still-current token is never re-signed. A price,
 *  name or popular-flag edit does not reach the bytes and so, rightly, re-mints nothing. */
export function needsMint(state: EntitlementState, catalogue: PlanCatalogue, now: Date): boolean {
  if (!state.token_created_at || !state.token_expires_at) return true;
  if (state.token_expires_at.getTime() <= now.getTime()) return true;
  const minted = state.token_created_at.getTime();
  if (state.sub_updated_at !== null && state.sub_updated_at.getTime() > minted) return true;
  const stored = storedPayload(state.token);
  if (stored === null) return true;
  const expected = entitlementPayloadBytes(entitlementFor(state, catalogue, new Date(stored.iat)));
  return !sameBytes(stored.bytes, expected);
}
