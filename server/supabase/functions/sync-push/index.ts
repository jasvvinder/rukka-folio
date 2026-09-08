// POST /sync-push {envelopes[]} → {store_epoch, results[]} (05 §3 🔒). Idempotent by envelope_id;
// the eight shape checks (ADR 2026-09-05c §5) refuse with the check named; quotas, rate limits and
// freezes are the server's only other powers (ADR 2026-09-05b §7). Never content: the blob is bytes.
import { b64any } from "../_shared/bytes.ts";
import { type Deps, serve } from "../_shared/deps.ts";
import { error, readJson } from "../_shared/http.ts";
import { PUSH_BATCH_BYTES, PUSH_BATCH_MAX, QUOTAS, WRITER_ROLES } from "../_shared/registry.ts";
import { authenticate, gate, jsonBigResponse } from "../_shared/route.ts";
import { checkShape, isRefusal, parseEnvelope } from "../_shared/shape.ts";
import { type BookAccess, StoreDenied, type Tx } from "../_shared/store.ts";

type Result = {
  envelope_id: string;
  result: string;
  seq?: bigint;
  check?: string;
  retry_after_ms?: number;
};
const RATE_RETRY_MS = 60_000;

export async function handler(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") return error(405, "method_not_allowed");
  const gated = await gate(req, deps, "sync");
  if (gated) return gated;
  const claims = await authenticate(req, deps);
  if (claims instanceof Response) return claims;

  const body = await readJson(req, PUSH_BATCH_BYTES * 2) as { envelopes?: unknown[] } | null; // base64 overhead
  if (!body || !Array.isArray(body.envelopes)) return error(400, "bad_request");
  if (body.envelopes.length > PUSH_BATCH_MAX) {
    return error(413, "batch_too_large", `max ${PUSH_BATCH_MAX} envelopes`);
  }

  // Decode blobs first so the byte total can be checked against the 1 MB batch cap.
  const parsed = body.envelopes.map((raw) => {
    const e = raw as Record<string, unknown>;
    const blob = e && typeof e === "object" && "blob" in e ? b64any(e.blob) : null;
    if (e && typeof e === "object" && "blob" in e && !blob) {
      return { result: "rejected:shape", check: "blob" };
    }
    return parseEnvelope(raw, blob);
  });
  const totalBytes = parsed.reduce((n, p) => n + (isRefusal(p) ? 0 : p.size), 0);
  if (totalBytes > PUSH_BATCH_BYTES) {
    return error(413, "batch_too_large", `max ${PUSH_BATCH_BYTES} bytes`);
  }

  const nowMs = deps.now().getTime();
  const out = await deps.store.withClaims(claims, async (tx) => {
    const store_epoch = await tx.storeEpoch();
    const results: Result[] = [];
    const allowed = await tx.pushRateCheck(claims.device_id, parsed.length, totalBytes);
    if (!allowed) {
      for (const [i, p] of parsed.entries()) {
        results.push({
          envelope_id: idOf(body.envelopes![i], p),
          result: "rejected:rate_limited",
          retry_after_ms: RATE_RETRY_MS,
        });
      }
      return { store_epoch, results };
    }
    const access = new Map<string, BookAccess | null>();
    const highest = new Map<string, Awaited<ReturnType<Tx["highestKeyVersion"]>>>();
    for (const [i, p] of parsed.entries()) {
      const envelope_id = idOf(body.envelopes![i], p);
      if (isRefusal(p)) {
        results.push({ envelope_id, ...p });
        continue;
      }
      if (!access.has(p.book_id)) access.set(p.book_id, await tx.bookAccess(p.book_id));
      const a = access.get(p.book_id)!;
      if (!a || a.archived || a.membership_status === null) {
        // no membership in that tenant = the book does not exist for this caller (no cross-tenant oracle)
        results.push({ envelope_id, result: "rejected:unknown_book" });
        continue;
      }
      if (a.membership_status !== "active") {
        results.push({ envelope_id, result: "membership_not_active" });
        continue;
      }
      if (!a.role || !WRITER_ROLES.has(a.role)) {
        results.push({ envelope_id, result: "rejected:no_role" });
        continue;
      }
      if (a.frozen) {
        results.push({ envelope_id, result: "rejected:tenant_frozen" });
        continue;
      }
      const q = QUOTAS[a.plan];
      if (a.envelope_count >= q.envelopesPerBook || a.tenant_bytes + p.size > q.tenantBytes) {
        results.push({ envelope_id, result: "rejected:quota" });
        continue;
      }
      if (!highest.has(p.book_id)) highest.set(p.book_id, await tx.highestKeyVersion(p.book_id));
      const refusal = await checkShape(p, {
        jwtDeviceId: claims.device_id,
        bookTenantId: a.tenant_id,
        highest: highest.get(p.book_id)!,
        nowMs,
      });
      if (refusal) {
        results.push({ envelope_id, ...refusal });
        continue;
      }
      try {
        const { seq, duplicate } = await tx.insertEnvelope(p);
        if (!duplicate) {
          a.envelope_count += 1;
          a.tenant_bytes += p.size;
        }
        results.push({ envelope_id, result: "acked", seq });
      } catch (e) {
        if (e instanceof StoreDenied) {
          // The row policy disagreed with what we computed — refuse, never store half a batch.
          results.push({
            envelope_id,
            result: e.reason === "fk" ? "rejected:unknown_book" : "rejected:no_role",
          });
          continue;
        }
        throw e;
      }
    }
    return { store_epoch, results };
  });
  return jsonBigResponse(200, out);
}

function idOf(raw: unknown, p: unknown): string {
  const own = (p as { envelope_id?: unknown })?.envelope_id;
  if (typeof own === "string") return own;
  const id = (raw as Record<string, unknown>)?.envelope_id;
  return typeof id === "string" ? id : "";
}

if (import.meta.main) serve(handler);
