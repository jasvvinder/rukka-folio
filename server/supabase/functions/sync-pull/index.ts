// GET /sync-pull?book_id=&after_seq=&limit=500[&fy=][&object_types=a,b] → {store_epoch, envelopes[], next_seq}
// (05 §4 🔒). Cursor is the server `seq`, never the HLC; the read is `seq > after order by seq`, so
// an envelope is visible only after commit. Row policies decide what the caller may see.
import { isUuid, parseBigint } from "../_shared/bytes.ts";
import { type Deps, serve } from "../_shared/deps.ts";
import { error } from "../_shared/http.ts";
import { OBJECT_TYPES, PULL_LIMIT_MAX } from "../_shared/registry.ts";
import { authenticate, envelopeToWire, gate, jsonBigResponse } from "../_shared/route.ts";

export async function handler(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "GET") return error(405, "method_not_allowed");
  const gated = await gate(req, deps, "sync");
  if (gated) return gated;
  const claims = await authenticate(req, deps);
  if (claims instanceof Response) return claims;

  const q = new URL(req.url).searchParams;
  const bookId = q.get("book_id");
  const after = parseBigint(q.get("after_seq") ?? "0");
  const limitRaw = Number(q.get("limit") ?? PULL_LIMIT_MAX);
  if (!isUuid(bookId) || after === null || after < 0n) return error(400, "bad_request");
  const limit = Number.isInteger(limitRaw) && limitRaw > 0
    ? Math.min(limitRaw, PULL_LIMIT_MAX)
    : PULL_LIMIT_MAX;
  const types = q.get("object_types")?.split(",").filter((t) => OBJECT_TYPES.has(t)) ?? null;
  // ⚠️ SPEC 05 §8: `fy` selects a closed year "from warm or cold storage" — the server cannot map
  // ciphertext to a financial year, so today every FY is served from the hot store and `fy` is
  // accepted and ignored. Cold-storage tiering is an ops concern (03 §6), not a wire change.

  const out = await deps.store.withClaims(claims, async (tx) => {
    const store_epoch = await tx.storeEpoch();
    const access = await tx.bookAccess(bookId);
    // No membership in the book's tenant answers exactly like no book: no existence oracle across tenants.
    if (!access || access.archived || access.membership_status === null) {
      return { status: 404, body: { error: "unknown_book" } };
    }
    if (access.membership_status !== "active" || !access.role) {
      return { status: 403, body: { error: "no_role" } };
    }
    const rows = await tx.pullEnvelopes(bookId, after, limit, types && types.length ? types : null);
    const next_seq = rows.length ? rows[rows.length - 1].seq! : after;
    return { status: 200, body: { store_epoch, envelopes: rows.map(envelopeToWire), next_seq } };
  });
  return jsonBigResponse(out.status, out.body);
}

if (import.meta.main) serve(handler);
