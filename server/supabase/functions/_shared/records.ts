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

/**
 * 06 §7's invite payload: the roles the invitee is being offered and the 128-bit ceremony nonce.
 * **No identifier of the invitee** — the admin's device cannot compute `invitee_hmac` (the HMAC key
 * is the server's, ADR 2026-09-05c §4) and the plaintext number is never stored (0008 ⚠️ SPEC).
 */
export function parseInvitePayload(
  p: Record<string, unknown>,
): { roles: unknown[]; nonce: Uint8Array } | null {
  const roles = p.roles ?? [];
  if (!Array.isArray(roles)) return null;
  const nonce = b64any(p.nonce);
  if (!nonce || nonce.length !== 16) return null;
  return { roles, nonce };
}

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
 * 06 §7's membership graph, mirrored from `rf.membership_transition_ok` so the function answers
 * with a named refusal instead of letting the database's guard surface as a generic denial. The
 * database stays the authority — an edge function is just another client — but the client asking
 * deserves to be told which edge it tried to walk.
 */
const MEMBERSHIP_EDGES: Record<string, string[]> = {
  // no row yet: an admin record may invite or record a join, never grant `active` — that edge
  // belongs to the ceremony. The one exception is the tenant's founder, who has nobody to verify
  // them (06 §5); `bootstrap` below is that exception, and the database's guard agrees.
  "-": ["invited", "joined_pending_verification", "removed"],
  invited: ["invited", "joined_pending_verification", "removed"],
  joined_pending_verification: ["joined_pending_verification", "active", "blocked", "removed"],
  active: ["active", "removed"],
  blocked: ["blocked", "removed"],
  removed: ["removed", "invited", "joined_pending_verification"],
};
export function membershipTransitionOk(
  from: string | null,
  to: string,
  bootstrap = false,
): boolean {
  if (from === null && bootstrap && to === "active") return true;
  return (MEMBERSHIP_EDGES[from ?? "-"] ?? []).includes(to);
}

/** What applying one record came to: a note ("membership active", "acked"-worthy) or a refusal
 *  beginning with "rejected:", with the name of the rule that refused it in `check` — the same
 *  name 0022 raises for that rule (`not_admin`, `not_revoker`), so the client reads one vocabulary
 *  whichever layer said no. Nothing here is a new wire result (05, wire.dart RecordAck). */
export interface Applied {
  note: string;
  check?: string;
}
const refuse = (note: string, check?: string): Applied => check ? { note, check } : { note };

/**
 * Apply one verified record authored by the *caller's* device. Caller has already inserted the
 * row (so `seq` is set) — projection happens in the same transaction and rolls back with it.
 *
 * Authority (06 §1.0 🔒, §5, §6 🔒, §7 🔒; 0022's owner-accepted readings, 3 Oct 2026) over
 * membership_status, member_removal and book_role is decided from what the DATABASE answers —
 * rf.is_tenant_admin, rf.may_file_record, rf.book_access, each SECURITY DEFINER over the caller's
 * own standing — never from a count of rows the caller happens to see (desk 83: on PgStore a
 * stranger sees no membership of another tenant, so "nobody is a member yet" was true for every
 * stranger). A row the caller can see is read only where the policy shows it in full: the caller's
 * own membership row, and a tenant's rows to its active member. The database re-checks every
 * projection (0022 §2–§4); this is the same rule, asked first, so the refusal is named and the
 * record is kept with its note rather than surfacing as a store denial.
 *
 * ⚠️ SPEC (EDGE83 review, reported — needs a migration this directory does not own): the ONE
 * exception is device_revocation's k-of-n COUNT, which 0022 (e) leaves to the edge ("the database
 * cannot recount it and does not try"). It is still taken from the approvals the caller can see
 * (revocationRecordsFor under signed_records_select; guardianSetHistory under guardian_sets_select),
 * so k guardians who each file in a tenant the subject is in, but share no tenant with each other,
 * each see only their own approval and never complete the revocation 06 §6 🔒 gives them. That
 * errs narrower (a revocation withheld), never wider (no device is revoked by a count the database
 * would not bound: 0022 §4 still checks WHO and WHERE). Closing it needs a SECURITY DEFINER answer
 * over every approval of one device, gated to its owner and their guardians.
 */
export async function applyRecord(
  tx: Tx,
  r: SignedRecordRow,
  authorUserId: string,
): Promise<Applied> {
  const p = r.payload_json;
  switch (r.kind) {
    case "membership_status": {
      const user = p.user_id, status = p.status;
      if (!isUuid(user) || typeof status !== "string" || !MEMBERSHIP_STATUSES.has(status)) {
        return refuse("rejected:shape");
      }
      // 0022 §2: a tenant admin, or the founder (06 §5) — the caller's OWN first membership, at
      // `active` only (0022 (b)), in a tenant with no member at all. "No member at all" is
      // rf.may_file_record's to say: with no row of the caller's own in the tenant (that row is
      // always visible to it), it admits a membership_status only into an existing tenant with
      // no member.
      const admin = await tx.isTenantAdmin(r.tenant_id);
      const founder = !admin && status === "active" && user === authorUserId &&
        (await tx.membershipStatus(r.tenant_id, authorUserId)) === null &&
        (await tx.mayFileRecord(r.tenant_id, "membership_status"));
      if (!admin && !founder) return refuse("rejected:unauthorized", "not_admin");
      // 06 §7: the graph, not the admin, decides what the next state may be. `active` in particular
      // is the ceremony's to grant (rf.membership_guard refuses it without one, even to us). An
      // admin sees every membership row of its tenant, so `from` is exact.
      const from = await tx.membershipStatus(r.tenant_id, user);
      if (!membershipTransitionOk(from, status, founder)) {
        return refuse("rejected:membership_transition");
      }
      await tx.projectMembership(r.id, r.tenant_id, user, status);
      return { note: `membership ${status}` };
    }
    case "member_removal": {
      const user = p.user_id;
      if (!isUuid(user)) return refuse("rejected:shape");
      // 06 §1.0: "Invite / remove members … admin only" (0022 §2).
      if (!(await tx.isTenantAdmin(r.tenant_id))) {
        return refuse("rejected:unauthorized", "not_admin");
      }
      await tx.projectMembership(r.id, r.tenant_id, user, "removed");
      return { note: "membership removed" };
    }
    case "book_role": {
      const book = p.book_id, user = p.user_id, role = p.role ?? null;
      const limit = p.auto_post_limit_paise === undefined || p.auto_post_limit_paise === null
        ? null
        : parseBigint(p.auto_post_limit_paise);
      if (
        !isUuid(book) || !isUuid(user) ||
        (role !== null && (typeof role !== "string" || !ROLES.has(role)))
      ) return refuse("rejected:shape");
      if (
        p.auto_post_limit_paise !== undefined && p.auto_post_limit_paise !== null && limit === null
      ) return refuse("rejected:shape"); // money is integer paise
      // rf.book_access (0005, SECURITY DEFINER): the book's tenant and the CALLER's own role on it
      // and standing in that tenant. A book of another tenant answers exactly like one that does
      // not exist — the same refusal the database gives (`no_record`), never a hint of where.
      const acc = await tx.bookAccess(book);
      if (!acc || acc.tenant_id !== r.tenant_id) return refuse("rejected:unknown_book");
      // 06 §1.0 🔒 "granted, changed and revoked only by an admin of that book (its creator is the
      // first admin)" — 0022 (c): an admin of THIS book, not of any book in the tenant; both arms
      // need an active member (0022 §3).
      let ok = acc.membership_status === "active" && acc.role === "admin";
      if (!ok && acc.membership_status === "active" && user === authorUserId && role === "admin") {
        // 0022 (d): a role-less book's first role is its creator's — the caller's own admin role,
        // on a book that has never held an envelope (book_usage only ever counts up), and on a
        // personal book only its owner's. The caller is active in the book's tenant, so
        // books_select and book_roles_select show it the book and every role on it: the count is
        // exact (bookInfo).
        const info = await tx.bookInfo(book);
        ok = acc.envelope_count === 0 && info !== null && info.role_count === 0 &&
          (info.type !== "personal" || info.owner_user_id === authorUserId);
      }
      if (!ok) return refuse("rejected:unauthorized", "not_admin");
      await tx.projectBookRole(r.id, book, user, role as string | null, limit);
      return { note: role ? `role ${role}` : "role removed" };
    }
    case "invite":
      // Issued through POST /sync-meta/invites, never here: the route needs the invitee's number in
      // the same request (it alone can compute `invitee_hmac` — ADR 2026-09-05c §4), and the number
      // must not be part of anything the server stores. The record is still stored and signed.
      return refuse("rejected:invite_route");
    case "designation":
      // Labels, not capability (06 §1.0) — the record is the fact; the server keeps no column.
      return { note: "label only" };
    case "device_added":
    case "key_rotation":
      // Nothing to project: the device row / wrapped_keys rows are the server's copy already.
      return { note: "no projection" };
    case "verification_event": {
      const { subject_user_id: s, verifier_user_id: v, method, result } = p as Record<
        string,
        unknown
      >;
      if (!isUuid(s) || !isUuid(v) || typeof method !== "string" || typeof result !== "string") {
        return refuse("rejected:shape");
      }
      if (v !== authorUserId) return refuse("rejected:unauthorized");
      await tx.projectVerificationEvent(r.id, r.tenant_id, s, v, method, result);
      return { note: "verification logged" };
    }
    case "device_revocation": {
      const dev = p.revoked_device_id, subject = p.subject_user_id;
      if (!isUuid(dev) || !isUuid(subject)) return refuse("rejected:shape");
      const target = await tx.deviceAuthRow(dev);
      if (!target || target.user_id !== subject) return refuse("rejected:shape");
      // 06 §6 🔒 "any certified device of the same user, k guardians", and 0022 (e): the revocation
      // lands only on a record of a tenant that user is in (any membership but `removed`). The
      // owner reads its own row; a guardian reads the subject's as an active member of the
      // record's tenant. ⚠️ SPEC (desk 83, reported): a guardian who is only PENDING in the
      // record's tenant cannot see the subject's row, so the edge refuses where 0022 §4 would
      // project — narrower, never wider; closing it needs a SECURITY DEFINER answer the database
      // does not offer yet.
      const inTenant = async () => {
        const st = await tx.membershipStatus(r.tenant_id, subject);
        return st !== null && st !== "removed";
      };
      if (authorUserId === subject) {
        if (!(await inTenant())) return refuse("rejected:unauthorized", "not_revoker");
        await tx.projectDeviceStatus(r.id, r.tenant_id, dev, "revoked");
        return { note: "revoked by owner" };
      }
      const sets = await tx.guardianSetHistory(subject);
      const version = p.share_set_version;
      if (typeof version !== "number" || !sets.some((s) => s.share_set_version === version)) {
        return refuse("rejected:unauthorized", "not_revoker");
      }
      // ⚠️ SPEC (see the header): the approvals counted are the ones the CALLER can see — a
      // guardian sharing no tenant with an earlier approver does not see that approval, so the
      // count is short and the revocation waits (E-06-94's ignored disjoint-guardians case).
      const records = [...(await tx.revocationRecordsFor(dev)), r];
      const counted = await countGuardianApprovals(tx, records, sets);
      if (!counted.authors.has(authorUserId)) {
        return refuse("rejected:unauthorized", "not_revoker");
      }
      if (counted.effectiveSeq !== null) {
        // The completing record (0022 (e)): the count is ADR 2026-09-06 §3's, unchanged; the
        // projection it triggers must come from a tenant the subject is in.
        if (!(await inTenant())) return refuse("rejected:unauthorized", "not_revoker");
        await tx.projectDeviceStatus(r.id, r.tenant_id, dev, "revoked");
        return {
          note:
            `revoked by guardians ${counted.authors.size} of ${counted.k} at seq ${counted.effectiveSeq}`,
        };
      }
      return { note: `counted ${counted.authors.size} of ${counted.k}` };
    }
    default:
      return refuse("rejected:shape");
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
