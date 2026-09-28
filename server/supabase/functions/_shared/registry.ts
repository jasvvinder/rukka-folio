// Plaintext registries the server may check (03 §2.3, ADR 2026-09-05c §5) and the numbers 05 §3 fixes.
// Plan numbers are NOT here: they live in the plan catalogue (0018, ADR 2026-09-25 §6).
export const SUITE_VERSIONS: ReadonlySet<number> = new Set([1]);
export const PAYLOAD_SCHEMAS: ReadonlySet<number> = new Set([1]);
export const OBJECT_TYPES: ReadonlySet<string> = new Set([
  "book_config",
  "account",
  "entry",
  "approval_decision",
  "period_lock",
  "year_close",
  "import_batch",
  "import_line",
  "rule",
  "attachment_meta",
  "cash_count",
  "period_unlock",
  "structural_approval",
  "business_setting",
]);
export const RECORD_KINDS: ReadonlySet<string> = new Set([
  "membership_status",
  "invite", // 06 §7: the admin's device authorises the invite; payload {roles, nonce} (0008 ⚠️ SPEC)
  "book_role",
  "member_removal",
  "device_revocation",
  "device_added",
  "key_rotation",
  "verification_event",
  "designation",
]);

export const ENVELOPE_MAX_BYTES = 256 * 1024; // ⚠️ 05 §3 cap 256 KB/envelope
export const INLINE_BLOB_MAX = 64 * 1024; // ⚠️ 03 §2.3 threshold; above → object storage (blob_ref)
export const PUSH_BATCH_MAX = 100; // 05 §3
export const PUSH_BATCH_BYTES = 1024 * 1024;
export const PULL_LIMIT_MAX = 500; // 05 §4
export const HLC_FUTURE_MS = 5 * 60 * 1000; // 05 §2
export const KEY_STALE_GRACE_MS = 48 * 3600 * 1000; // 04 §5.3

/** A plan is a CATALOGUE id — ADR 2026-09-25 §6 🔒: "The token's `plan` becomes a catalogue id,
 *  not one of four fixed names." The ids live in `plan_catalogue` (0018), whose CHECK is this
 *  pattern; `subscriptions.plan` is a foreign key onto it. */
export type PlanId = string;
export const PLAN_ID = /^[a-z][a-z0-9_]{0,31}$/;

/** The floor plan. ADR 2026-09-05g §1 🔒: "A tenant with no valid token is *Free*, never
 *  *locked*" — a tenant with no subscription row reads this row. 0018's guard keeps it in the
 *  catalogue, Individual, unpriced and without an extra (ADR 2026-09-25 §5 🔒). */
export const FLOOR_PLAN: PlanId = "free";

/** The ONLY extras a plan may include, and so the only `features` a token can ever carry — sorted,
 *  because the token encodes them sorted. ADR 2026-09-25 §5 🔒: plans "differ **only** by scale
 *  (books, people, devices, storage), statement import, and PDF output", and every other book-flow
 *  feature is "never restricted, on any plan including Free". 0018's CHECK on
 *  `plan_catalogue.features` is the same list, so neither the database nor the signer can gate
 *  anything else (G-25-1). Adding a name here needs an ADR and a client that understands it. */
export const FEATURES = ["pdf_output", "statement_import"] as const;
export type Feature = typeof FEATURES[number];

/** S0.3's cards as ADR 2026-09-25 §5's entity types (0018 `plan_catalogue.entity_type`). */
export const ENTITY_TYPES = ["individual", "family", "business", "trust"] as const;
export type EntityType = typeof ENTITY_TYPES[number];

/** No cap on this limit — ADR 2026-09-24b §7 (b) 🔒: "An unlimited limit … is **`-1`** on the
 *  wire." It is not a count, so every comparison goes through `withinCap`, and the token's field
 *  set is exact (08 §3 🔒 / ADR 2026-09-05g §1 as amended by ADR 2026-09-24b §6 and ADR
 *  2026-09-25 §6), so there is no separate "unlimited" flag. Since ADR 2026-09-25 §5 no seeded plan
 *  is unlimited in books; the sentinel stays the rule for any catalogue row that holds it. */
export const NO_CAP = -1;

/** `n` is allowed under `cap` (NO_CAP allows everything). */
export function withinCap(n: number, cap: number): boolean {
  return cap === NO_CAP || n <= cap;
}

/** A plan's limits, in the entitlement token's field names (ADR 2026-09-05g §1 🔒
 *  `limits{members, business_books, devices, envelopes_per_book, tenant_bytes, attachment_bytes}`)
 *  — 0018's columns carry exactly these names. Integers only; bytes are exact byte counts.
 *
 *  `devices` is the cap 06 §6 applies as the HIGHEST across a user's active tenants (rf.device_cap,
 *  0018), so this per-tenant token merely reports it. 08 §2's per-file cap (10 MB,
 *  plan-independent) is deliberately absent: the 🔒 field set names six limits and nothing more. */
export interface PlanLimits {
  members: number;
  business_books: number;
  devices: number;
  envelopes_per_book: number;
  tenant_bytes: number;
  attachment_bytes: number;
}

/** One `plan_catalogue` row as the edge reads it (0018). Prices are integer paise, GST-inclusive. */
export interface CataloguePlan {
  id: PlanId;
  entity_type: EntityType;
  name: string;
  sort_order: number;
  limits: PlanLimits;
  features: Feature[];
  price_yearly_paise: number;
  price_monthly_paise: number;
  popular: boolean;
  placeholder: boolean;
  updated_at: Date;
}

/** The catalogue the server's enforced limits are read from — ADR 2026-09-25 §6 🔒: "The server's
 *  enforced limits are read from it. `PLAN_LIMITS` in `registry.ts` stops being a hard-coded
 *  table." Built per request from `Tx.planCatalogue()`; nothing here holds a number of its own. */
export class PlanCatalogue {
  private readonly byId: ReadonlyMap<PlanId, CataloguePlan>;
  constructor(readonly plans: readonly CataloguePlan[]) {
    this.byId = new Map(plans.map((p) => [p.id, p]));
  }
  get(id: PlanId | null): CataloguePlan | null {
    return id === null ? null : this.byId.get(id) ?? null;
  }
  /** The plan a subscription row means. Never throws on a row and never guesses: an unknown or
   *  absent plan reads as the floor, which ADR 2026-09-05g §1 🔒 already names for a tenant with no
   *  token at all — it can never invent entitlement. (0018's FK means a stored plan is always
   *  known; the fallback is for the tenant with no row.) A catalogue without its floor is a server
   *  fault, loud rather than a guessed number. */
  resolve(id: PlanId | null): CataloguePlan {
    const p = this.get(id) ?? this.byId.get(FLOOR_PLAN);
    if (!p) {
      throw new Error(`plan_catalogue has no '${FLOOR_PLAN}' floor row (0018 guard bypassed)`);
    }
    return p;
  }
  /** ADR 2026-09-25 §5: the entity type's popular plan — the one a trial runs on. */
  popular(entity: EntityType): CataloguePlan | null {
    return this.plans.find((p) => p.entity_type === entity && p.popular) ?? null;
  }
}

/** 08 §2 (ADR 2026-09-05g §3 as amended by ADR 2026-09-25 §6): envelopes per book · tenant bytes —
 *  the two the push path enforces — read off the same row the token promises, so the quota the
 *  server refuses on and the quota the token states can never drift apart. */
export function quotaOf(p: CataloguePlan): { envelopesPerBook: number; tenantBytes: number } {
  return { envelopesPerBook: p.limits.envelopes_per_book, tenantBytes: p.limits.tenant_bytes };
}
export const WRITER_ROLES: ReadonlySet<string> = new Set(["admin", "head", "member", "operator"]);

/** semver "a.b.c" compare; true when client < min. */
export function belowMinVersion(client: string | null, min: string): boolean {
  if (!client) return true;
  const p = (s: string) => s.split(".").map((x) => parseInt(x, 10) || 0);
  const a = p(client), b = p(min);
  for (let i = 0; i < 3; i++) {
    if ((a[i] ?? 0) < (b[i] ?? 0)) return true;
    if ((a[i] ?? 0) > (b[i] ?? 0)) return false;
  }
  return false;
}
