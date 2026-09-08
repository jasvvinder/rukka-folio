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
/** 08 §2 (ADR 2026-09-05g §3): envelopes per book · tenant bytes. */
export const QUOTAS: Record<Plan, { envelopesPerBook: number; tenantBytes: number }> = {
  free: { envelopesPerBook: 10_000, tenantBytes: 250 * 1024 * 1024 },
  personal: { envelopesPerBook: 100_000, tenantBytes: 2 * 1024 ** 3 },
  family: { envelopesPerBook: 250_000, tenantBytes: 5 * 1024 ** 3 },
  family_plus: { envelopesPerBook: 1_000_000, tenantBytes: 15 * 1024 ** 3 },
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
