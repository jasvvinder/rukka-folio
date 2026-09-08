// GET  /sync-meta?after=<cursor>[&subject_user_id=] → every metadata table the client consumes (05 §5 🔒),
//      signed records after `seq`, guardian-set history by share_set_version, min-version, store_epoch.
// POST /sync-meta/records {records[]} → per-record {id, result, seq} — signed records authored on the
//      caller's certified device are verified under its Ed25519 key, stored, then projected onto rows
//      (ADR 2026-09-05b §1). The server never invents a record.
// Cursor: `after` is opaque — base64url JSON {tables: {table: {updated_at, id}}, records_seq}; each
// table's own cursor is (updated_at, id) as 05 §5 says. `next` is ALWAYS present (the resume point);
// `has_more` is true when any table or the records stream had more than a page (engine contract: wire.dart).
import { b64url, isUuid } from "../_shared/bytes.ts";
import { type Deps, serve } from "../_shared/deps.ts";
import { error, readJson, subPath } from "../_shared/http.ts";
import { applyRecord, parseRecord, type RecordResult, verifyRecord } from "../_shared/records.ts";
import { PULL_LIMIT_MAX } from "../_shared/registry.ts";
import { authenticate, gate, jsonBigResponse, recordToWire } from "../_shared/route.ts";
import {
  META_TABLES,
  type MetaCursors,
  type MetaTable,
  rowId,
  StoreDenied,
} from "../_shared/store.ts";

const PAGE = 200;
const RECORDS_BATCH_MAX = 50;
interface Cursor {
  tables: MetaCursors;
  records_seq: string;
}

export async function handler(req: Request, deps: Deps): Promise<Response> {
  const gated = await gate(req, deps, "sync");
  if (gated) return gated;
  const claims = await authenticate(req, deps);
  if (claims instanceof Response) return claims;
  const path = subPath(req, "sync-meta");
  if (req.method === "GET" && path === "/") return pull(req, deps, claims);
  if (req.method === "POST" && path === "/records") return postRecords(req, deps, claims);
  return error(404, "not_found");
}

async function pull(
  req: Request,
  deps: Deps,
  claims: { user_id: string; device_id: string },
): Promise<Response> {
  const q = new URL(req.url).searchParams;
  const cursor = decodeCursor(q.get("after"));
  if (cursor === undefined) return error(400, "bad_cursor");
  const subject = q.get("subject_user_id") ?? claims.user_id;
  if (!isUuid(subject)) return error(400, "bad_request");

  const out = await deps.store.withClaims(claims, async (tx) => {
    const body: Record<string, unknown> = { store_epoch: await tx.storeEpoch() };
    const next: Cursor = { tables: {}, records_seq: cursor?.records_seq ?? "0" };
    let more = false;
    for (const table of META_TABLES) {
      const page = await tx.metaPage(table, cursor?.tables[table] ?? null, PAGE);
      body[table] = page.rows.map((r) => shapeRow(table, r));
      if (page.next) {
        next.tables[table] = page.next;
        more = true;
      } else if (page.rows.length) {
        const last = page.rows[page.rows.length - 1];
        next.tables[table] = {
          updated_at: (last.updated_at as Date).toISOString(),
          id: rowId(table, last),
        };
      } else if (cursor?.tables[table]) {
        next.tables[table] = cursor.tables[table]; // drained: resume from the same place next time
      }
    }
    const records = await tx.signedRecordsAfter(BigInt(next.records_seq), PULL_LIMIT_MAX);
    body.signed_records = records.map(recordToWire);
    if (records.length) {
      next.records_seq = records[records.length - 1].seq!.toString();
      if (records.length === PULL_LIMIT_MAX) more = true;
    }
    body.guardian_sets = (await tx.guardianSetHistory(subject)).map((s) => ({
      subject_user_id: s.subject_user_id,
      share_set_version: s.share_set_version,
      k: s.k,
      n: s.n,
      guardian_user_ids: s.members.map((m) => m.guardian_user_id),
      guardians: s.members.map((m) => ({
        guardian_user_id: m.guardian_user_id,
        umk_pub_ed: b64url.enc(m.umk_pub_ed),
      })),
    }));
    body.min_client_version = {
      sync: await tx.appConfig("min_client_version.sync"),
      auth: await tx.appConfig("min_client_version.auth"),
    };
    body.has_more = more;
    body.next = encodeCursor(next); // always present — the resume point even when drained
    return body;
  });
  return jsonBigResponse(200, out);
}

async function postRecords(
  req: Request,
  deps: Deps,
  claims: { user_id: string; device_id: string },
): Promise<Response> {
  const body = await readJson(req, 1 << 20) as { records?: unknown[] } | null;
  if (!body || !Array.isArray(body.records)) return error(400, "bad_request");
  if (body.records.length > RECORDS_BATCH_MAX) return error(413, "batch_too_large");
  const out = await deps.store.withClaims(claims, async (tx) => {
    const store_epoch = await tx.storeEpoch();
    const me = await tx.deviceAuthRow(claims.device_id);
    const results: RecordResult[] = [];
    for (const raw of body.records!) {
      const parsed = parseRecord(raw);
      const id = typeof (raw as Record<string, unknown>)?.id === "string"
        ? (raw as Record<string, string>).id
        : "";
      if (!("kind" in parsed)) {
        results.push({ id, ...parsed });
        continue;
      }
      if (parsed.author_device !== claims.device_id) {
        results.push({ id, result: "rejected:shape", check: "author_device_id" });
        continue;
      }
      if (!me || me.status !== "certified") {
        results.push({ id, result: "rejected:unauthorized", check: "device_status" });
        continue;
      }
      if (!(await verifyRecord(parsed, me.pub_ed))) {
        results.push({ id, result: "rejected:shape", check: "author_sig" });
        continue;
      }
      try {
        const { seq, duplicate } = await tx.insertSignedRecord(parsed);
        if (duplicate) {
          results.push({ id, result: "acked", seq: seq.toString() });
          continue;
        }
        const note = await applyRecord(tx, { ...parsed, seq }, me.user_id);
        if (note.startsWith("rejected:")) {
          // Stored (append-only, it is a signed fact) but not applied; the note says why.
          await tx.markRecordApplied(parsed.id, note);
          results.push({ id, result: note, seq: seq.toString() });
          continue;
        }
        await tx.markRecordApplied(parsed.id, note);
        results.push({ id, result: "acked", seq: seq.toString() });
      } catch (e) {
        if (e instanceof StoreDenied) {
          results.push({
            id,
            result: e.reason === "fk" ? "rejected:unknown_tenant" : "rejected:unauthorized",
            check: e.reason,
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

function decodeCursor(s: string | null): Cursor | null | undefined {
  if (!s) return null;
  try {
    const c = JSON.parse(new TextDecoder().decode(b64url.dec(s)));
    if (
      !c || typeof c !== "object" || typeof c.tables !== "object" ||
      !/^\d+$/.test(String(c.records_seq))
    ) return undefined;
    return { tables: c.tables, records_seq: String(c.records_seq) };
  } catch {
    return undefined;
  }
}
function encodeCursor(c: Cursor): string {
  return b64url.enc(new TextEncoder().encode(JSON.stringify(c)));
}

const ms = (v: unknown): number | null =>
  v instanceof Date ? v.getTime() : v == null ? null : new Date(String(v)).getTime();
const bin = (v: unknown): string | null => v instanceof Uint8Array ? b64url.enc(v) : null;

/** Column rows → 05 §5 / wire.dart names. Timestamps as epoch ms; bytes base64url; money as integer paise. */
export function shapeRow(table: MetaTable, r: Record<string, unknown>): Record<string, unknown> {
  const id = rowId(table, r);
  switch (table) {
    case "memberships":
      return {
        id,
        tenant_id: r.tenant_id,
        user_id: r.user_id,
        status: r.status,
        source_record_id: r.source_record_id ?? null,
        updated_at: ms(r.updated_at),
      };
    case "book_roles":
      return {
        id,
        book_id: r.book_id,
        user_id: r.user_id,
        role: r.role,
        source_record_id: r.source_record_id ?? null,
        ...(r.auto_post_limit_paise != null
          ? { limits: { auto_post_limit_paise: BigInt(String(r.auto_post_limit_paise)) } }
          : {}),
        updated_at: ms(r.updated_at),
      };
    case "books":
      return {
        id,
        tenant_id: r.tenant_id,
        type: r.type,
        owner_user_id: r.owner_user_id ?? null,
        fy_start_month: r.fy_start_month,
        archived_at: ms(r.archived_at),
        updated_at: ms(r.updated_at),
      };
    case "devices":
      return {
        id,
        user_id: r.user_id,
        pub_ed: bin(r.pub_ed),
        pub_x: bin(r.pub_x),
        status: r.status,
        model: r.model ?? null,
        os: r.os ?? null,
        revoked_at: ms(r.revoked_at),
        updated_at: ms(r.updated_at),
      };
    case "device_certs":
      // ⚠️ WIRE: `cert` is 64 opaque bytes in 03; wire.dart reads it as the DeviceCert fields — user_id
      // comes from the devices row, which the same response carries, so we ship the signature + issued_at.
      return {
        device_id: r.device_id,
        issued_by_device: r.issued_by_device ?? null,
        umk_key_version: r.umk_key_version,
        cert: { suite_version: 1, issued_at_ms: ms(r.issued_at), signature: bin(r.cert) },
        updated_at: ms(r.updated_at),
      };
    case "wrapped_keys":
      return {
        id,
        kind: r.kind,
        user_id: r.user_id,
        device_id: r.device_id ?? null,
        book_id: r.book_id ?? null,
        key_version: r.key_version,
        share_set_version: r.share_set_version ?? null,
        blob: bin(r.blob),
        created_at: ms(r.created_at),
        revoked_at: ms(r.revoked_at),
        updated_at: ms(r.updated_at),
      };
    case "umk_public_keys":
      return {
        user_id: r.user_id,
        key_version: r.key_version,
        pub_ed: bin(r.pub_ed),
        superseded_at: ms(r.superseded_at),
        updated_at: ms(r.updated_at),
      };
    case "guardian_sets":
    case "guardian_set_members":
      return {
        ...r,
        umk_pub_ed: bin(r.umk_pub_ed) ?? undefined,
        created_at: ms(r.created_at),
        superseded_at: ms(r.superseded_at),
        updated_at: ms(r.updated_at),
      };
    case "invites":
      return {
        id,
        tenant_id: r.tenant_id,
        invitee_hmac: bin(r.invitee_hmac),
        roles: r.roles,
        status: r.status,
        expires_at: ms(r.expires_at),
        created_by: r.created_by,
        updated_at: ms(r.updated_at),
      };
    case "subscriptions":
      return {
        tenant_id: r.tenant_id,
        plan: r.plan,
        status: r.status,
        current_period_end: ms(r.current_period_end),
        trial_end: ms(r.trial_end),
        grace_until: ms(r.grace_until),
        updated_at: ms(r.updated_at),
      };
    case "entitlement_tokens":
      return {
        id,
        tenant_id: r.tenant_id,
        token: bin(r.token),
        expires_at: ms(r.expires_at),
        updated_at: ms(r.updated_at),
      };
    case "tenant_freezes":
      return {
        tenant_id: r.tenant_id,
        ground: r.ground,
        imposed_at: ms(r.imposed_at),
        expires_at: ms(r.expires_at),
        lifted_at: ms(r.lifted_at),
        updated_at: ms(r.updated_at),
      };
    default: {
      // verification_events, recovery_requests, escrow_policies: pass through with dates → ms
      const out: Record<string, unknown> = { id };
      for (const [k, v] of Object.entries(r)) {
        out[k] = v instanceof Date ? v.getTime() : v instanceof Uint8Array ? b64url.enc(v) : v;
      }
      return out;
    }
  }
}

if (import.meta.main) serve(handler);
