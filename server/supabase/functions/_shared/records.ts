// Signed records (ADR 2026-09-05b §1): verify the author's Ed25519 signature over
// BLAKE2b-256(payload ‖ header) with header = u8(suite) ‖ uuid16(tenant) ‖ lenPrefixedUtf8(kind)
// ‖ uuid16(author_device) ‖ i64be(hlc) — byte-identical to core_crypto/signed_record.dart — then
// authorise (06 §1.0) and project onto rows. Guardian k-of-n device revocation is k separate
// records counted with the earliest-k rule (ADR 2026-09-06 §3); the server's row is a projection,
// the client recomputes the cut-off itself.
import {
  b64any,
  concat,
  i64be,
  isUuid,
  lengthPrefixedUtf8,
  parseBigint,
  u8,
  uuid16,
} from "./bytes.ts";
import { RECORD_KINDS } from "./registry.ts";
import { blake2b256, ed25519Verify } from "./sodium.ts";
import type { GuardianSet, SignedRecordRow, Tx } from "./store.ts";

export function recordHeader(
  r: Pick<SignedRecordRow, "suite_version" | "tenant_id" | "kind" | "author_device" | "hlc">,
): Uint8Array {
  return concat([
    u8(r.suite_version),
    uuid16(r.tenant_id),
    lengthPrefixedUtf8(r.kind),
    uuid16(r.author_device),
    i64be(r.hlc),
  ]);
}
export async function recordDigest(r: SignedRecordRow): Promise<Uint8Array> {
  return await blake2b256(concat([r.payload_bytes, recordHeader(r)]));
}
export async function verifyRecord(r: SignedRecordRow, authorPubEd: Uint8Array): Promise<boolean> {
  return await ed25519Verify(await recordDigest(r), r.author_sig, authorPubEd);
}

export type RecordResult = { id: string; result: string; seq?: string; check?: string };

/** Wire → row. `payload_json` travels as a base64 UTF-8 JSON string so its bytes are exactly what was signed. */
export function parseRecord(raw: unknown): SignedRecordRow | { result: string; check: string } {
  const e = raw as Record<string, unknown>;
  if (!e || typeof e !== "object") return { result: "rejected:shape", check: "record" };
  for (const f of ["id", "tenant_id", "author_device_id"]) {
    if (!isUuid(e[f])) return { result: "rejected:shape", check: f };
  }
  if (typeof e.kind !== "string" || !RECORD_KINDS.has(e.kind)) {
    return { result: "rejected:shape", check: "kind" };
  }
  if (typeof e.suite_version !== "number" || !Number.isInteger(e.suite_version)) {
    return { result: "rejected:shape", check: "suite_version" };
  }
  const hlc = parseBigint(e.hlc);
  if (hlc === null) return { result: "rejected:shape", check: "hlc" };
  const payload = b64any(e.payload_json), sig = b64any(e.author_sig);
  if (!payload) return { result: "rejected:shape", check: "payload_json" };
  if (!sig) return { result: "rejected:shape", check: "author_sig" };
  let json: Record<string, unknown>;
  try {
    json = JSON.parse(new TextDecoder().decode(payload));
    if (!json || typeof json !== "object" || Array.isArray(json)) throw new Error();
  } catch {
    return { result: "rejected:shape", check: "payload_json" };
  }
  if (sig.length !== 64) return { result: "rejected:shape", check: "author_sig" };
  return {
    id: e.id as string,
    suite_version: e.suite_version,
    tenant_id: e.tenant_id as string,
    kind: e.kind,
    payload_json: json,
    payload_bytes: payload,
    author_device: e.author_device_id as string,
    author_sig: sig,
    hlc,
  };
}

const MEMBERSHIP_STATUSES = new Set([
  "invited",
  "joined_pending_verification",
  "active",
  "blocked",
  "removed",
]);
const ROLES = new Set(["admin", "head", "member", "operator", "viewer"]);

/**
 * Apply one verified record authored by the *caller's* device. Returns the apply note, or a
 * refusal string beginning with "rejected:". Caller has already inserted the row (so `seq` is set)
 * — projection happens in the same transaction and rolls back with it.
 */
export async function applyRecord(
  tx: Tx,
  r: SignedRecordRow,
  authorUserId: string,
): Promise<string> {
  const p = r.payload_json;
  switch (r.kind) {
    case "membership_status": {
      const user = p.user_id, status = p.status;
      if (!isUuid(user) || typeof status !== "string" || !MEMBERSHIP_STATUSES.has(status)) {
        return "rejected:shape";
      }
      const bootstrap = user === authorUserId && (await tx.membershipCount(r.tenant_id)) === 0;
      if (!bootstrap && !(await tx.isTenantAdmin(r.tenant_id))) return "rejected:unauthorized";
      await tx.projectMembership(r.id, r.tenant_id, user, status);
      return `membership ${status}`;
    }
    case "member_removal": {
      const user = p.user_id;
      if (!isUuid(user)) return "rejected:shape";
      if (!(await tx.isTenantAdmin(r.tenant_id))) return "rejected:unauthorized";
      await tx.projectMembership(r.id, r.tenant_id, user, "removed");
      return "membership removed";
    }
    case "book_role": {
      const book = p.book_id, user = p.user_id, role = p.role ?? null;
      const limit = p.auto_post_limit_paise === undefined || p.auto_post_limit_paise === null
        ? null
        : parseBigint(p.auto_post_limit_paise);
      if (
        !isUuid(book) || !isUuid(user) ||
        (role !== null && (typeof role !== "string" || !ROLES.has(role)))
      ) return "rejected:shape";
      if (
        p.auto_post_limit_paise !== undefined && p.auto_post_limit_paise !== null && limit === null
      ) return "rejected:shape"; // money is integer paise
      const info = await tx.bookInfo(book);
      if (!info || info.tenant_id !== r.tenant_id) return "rejected:unknown_book";
      const bootstrap = info.role_count === 0 &&
        (info.owner_user_id === authorUserId || info.type !== "personal");
      if (!bootstrap && !(await tx.isTenantAdmin(r.tenant_id))) return "rejected:unauthorized";
      await tx.projectBookRole(r.id, book, user, role as string | null, limit);
      return role ? `role ${role}` : "role removed";
    }
    case "designation":
      // Labels, not capability (06 §1.0) — the record is the fact; the server keeps no column.
      return "label only";
    case "device_added":
    case "key_rotation":
      // Nothing to project: the device row / wrapped_keys rows are the server's copy already.
      return "no projection";
    case "verification_event": {
      const { subject_user_id: s, verifier_user_id: v, method, result } = p as Record<
        string,
        unknown
      >;
      if (!isUuid(s) || !isUuid(v) || typeof method !== "string" || typeof result !== "string") {
        return "rejected:shape";
      }
      if (v !== authorUserId) return "rejected:unauthorized";
      await tx.projectVerificationEvent(r.id, r.tenant_id, s, v, method, result);
      return "verification logged";
    }
    case "device_revocation": {
      const dev = p.revoked_device_id, subject = p.subject_user_id;
      if (!isUuid(dev) || !isUuid(subject)) return "rejected:shape";
      const target = await tx.deviceAuthRow(dev);
      if (!target || target.user_id !== subject) return "rejected:shape";
      if (authorUserId === subject) {
        await tx.projectDeviceStatus(r.id, r.tenant_id, dev, "revoked");
        return "revoked by owner";
      }
      const sets = await tx.guardianSetHistory(subject);
      const version = p.share_set_version;
      if (typeof version !== "number" || !sets.some((s) => s.share_set_version === version)) {
        return "rejected:unauthorized";
      }
      const records = [...(await tx.revocationRecordsFor(dev)), r];
      const counted = await countGuardianApprovals(tx, records, sets);
      if (!counted.authors.has(authorUserId)) return "rejected:unauthorized";
      if (counted.effectiveSeq !== null) {
        await tx.projectDeviceStatus(r.id, r.tenant_id, dev, "revoked");
        return `revoked by guardians ${counted.authors.size} of ${counted.k} at seq ${counted.effectiveSeq}`;
      }
      return `counted ${counted.authors.size} of ${counted.k}`;
    }
    default:
      return "rejected:shape";
  }
}

/** Earliest-k counting (ADR 2026-09-06 §3): distinct guardian authors valid at the version each record names. */
export async function countGuardianApprovals(
  tx: Tx,
  records: SignedRecordRow[],
  sets: GuardianSet[],
) {
  const byVersion = new Map(sets.map((s) => [s.share_set_version, s]));
  const authors = new Map<string, bigint>(); // guardian user → lowest seq of their approval
  let earliestVersion = Infinity;
  for (const rec of records) {
    const v = rec.payload_json.share_set_version;
    const set = typeof v === "number" ? byVersion.get(v) : undefined;
    if (!set) continue;
    const author = await tx.deviceAuthRow(rec.author_device);
    if (!author) continue;
    const member = set.members.find((m) => m.guardian_user_id === author.user_id);
    if (!member) continue;
    const seq = rec.seq ?? (1n << 62n);
    const prev = authors.get(author.user_id);
    if (prev === undefined || seq < prev) authors.set(author.user_id, seq);
    earliestVersion = Math.min(earliestVersion, set.share_set_version);
  }
  const k = earliestVersion === Infinity ? Infinity : byVersion.get(earliestVersion)!.k;
  const seqs = [...authors.values()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const effectiveSeq = authors.size >= k ? seqs[k - 1] : null;
  return { authors, k, effectiveSeq };
}
