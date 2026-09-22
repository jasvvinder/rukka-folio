// Plaintext registries the server may check (03 §2.3, ADR 2026-09-05c §5) and the numbers 05 §3 / 08 §2 fix.
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

export type Plan = "free" | "personal" | "family" | "family_plus";
export const PLANS: readonly Plan[] = ["free", "personal", "family", "family_plus"] as const;

/** No cap on this limit. ⚠️ SPEC: ADR 2026-09-05g §3 🔒 writes "∞" for business books on Personal
 *  and Family+ and fixes no wire form for it, and the entitlement token's field set (08 §3 line 35
 *  🔒) is exact, so a separate "unlimited" flag cannot be added. -1 is the sentinel this codebase
 *  uses; it is not a count, so a client that compares a count against it can never read it as a
 *  cap that is already exceeded. Reported for the owner. */
export const NO_CAP = -1;

/** The ONE table of 08 §2 / ADR 2026-09-05g §3 🔒 numbers, in the entitlement token's field names
 *  (ADR §1 `limits{members, business_books, devices, envelopes_per_book, tenant_bytes,
 *  attachment_bytes}`). Integers only — bytes are exact byte counts, never MB floats.
 *
 *  `devices` is the cap 06 §6 applies as the HIGHEST across a user's active tenants, so it is a
 *  per-user cap that this per-tenant token merely reports; the server's own device cap lives in
 *  rf.device_cap (0005). 08 §2's per-file cap (10 MB, plan-independent) is deliberately absent:
 *  the 🔒 field set names six limits and nothing more. */
export const PLAN_LIMITS: Record<Plan, {
  members: number;
  business_books: number;
  devices: number;
  envelopes_per_book: number;
  tenant_bytes: number;
  attachment_bytes: number;
}> = {
  free: {
    members: 1,
    business_books: 1,
    devices: 5,
    envelopes_per_book: 10_000,
    tenant_bytes: 250 * 1024 * 1024,
    attachment_bytes: 100 * 1024 * 1024,
  },
  personal: {
    members: 1,
    business_books: NO_CAP,
    devices: 5,
    envelopes_per_book: 100_000,
    tenant_bytes: 2 * 1024 ** 3,
    attachment_bytes: 2 * 1024 ** 3,
  },
  family: {
    members: 5,
    business_books: 3,
    devices: 8,
    envelopes_per_book: 250_000,
    tenant_bytes: 5 * 1024 ** 3,
    attachment_bytes: 5 * 1024 ** 3,
  },
  family_plus: {
    members: 15,
    business_books: NO_CAP,
    devices: 15,
    envelopes_per_book: 1_000_000,
    tenant_bytes: 15 * 1024 ** 3,
    attachment_bytes: 20 * 1024 ** 3,
  },
};

/** 08 §2 (ADR 2026-09-05g §3): envelopes per book · tenant bytes — the two the push path enforces.
 *  Derived from PLAN_LIMITS so the quota the server refuses on and the quota the token promises can
 *  never drift apart. */
export const QUOTAS: Record<Plan, { envelopesPerBook: number; tenantBytes: number }> = {
  free: {
    envelopesPerBook: PLAN_LIMITS.free.envelopes_per_book,
    tenantBytes: PLAN_LIMITS.free.tenant_bytes,
  },
  personal: {
    envelopesPerBook: PLAN_LIMITS.personal.envelopes_per_book,
    tenantBytes: PLAN_LIMITS.personal.tenant_bytes,
  },
  family: {
    envelopesPerBook: PLAN_LIMITS.family.envelopes_per_book,
    tenantBytes: PLAN_LIMITS.family.tenant_bytes,
  },
  family_plus: {
    envelopesPerBook: PLAN_LIMITS.family_plus.envelopes_per_book,
    tenantBytes: PLAN_LIMITS.family_plus.tenant_bytes,
  },
};
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
