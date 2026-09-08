// The eight named shape checks (ADR 2026-09-05c §5; 03 §2.3) and the caps of 05 §3.
// Refusal = {result, check}: `result` is the 05 §3 code when a specific one exists
// (rejected:hlc_future, rejected:version, rejected:key_version_stale, rejected:too_large) and
// rejected:shape otherwise; `check` always names the failing check. Never content.
import { b64any, bytesEqual, hlcPhysicalMs, isUuid, parseBigint } from "./bytes.ts";
import { blake2b256 } from "./sodium.ts";
import {
  ENVELOPE_MAX_BYTES,
  HLC_FUTURE_MS,
  KEY_STALE_GRACE_MS,
  OBJECT_TYPES,
  PAYLOAD_SCHEMAS,
  SUITE_VERSIONS,
} from "./registry.ts";
import type { EnvelopeRow } from "./store.ts";

export const SHAPE_CHECKS = [
  "author_device",
  "tenant_id",
  "blob_hash",
  "size",
  "suite_version",
  "payload_schema",
  "key_version",
  "hlc",
] as const;
export type ShapeCheck = typeof SHAPE_CHECKS[number];

export type Refusal = { result: string; check?: string };

/** Field-level parse of one wire envelope (05 §3 names). Returns a row or a shape refusal. */
export function parseEnvelope(raw: unknown, blob: Uint8Array | null): EnvelopeRow | Refusal {
  const e = raw as Record<string, unknown>;
  if (!e || typeof e !== "object") return { result: "rejected:shape", check: "envelope" };
  for (const f of ["envelope_id", "tenant_id", "book_id", "object_id", "author_device"]) {
    if (!isUuid(e[f])) return { result: "rejected:shape", check: f };
  }
  if (typeof e.object_type !== "string" || !OBJECT_TYPES.has(e.object_type)) {
    return { result: "rejected:shape", check: "object_type" };
  }
  const ints = ["key_version", "suite_version", "payload_schema", "size"] as const;
  for (const f of ints) {
    if (typeof e[f] !== "number" || !Number.isInteger(e[f]) || (e[f] as number) < 0) {
      return { result: "rejected:shape", check: f };
    }
  }
  const hlc = parseBigint(e.hlc);
  if (hlc === null || hlc < 0n) return { result: "rejected:shape", check: "hlc" };
  const hash = b64any(e.blob_hash);
  if (!hash || hash.length !== 32) return { result: "rejected:shape", check: "blob_hash" };
  const blobRef = typeof e.blob_ref === "string" ? e.blob_ref : null;
  if ((blob === null) === (blobRef === null)) return { result: "rejected:shape", check: "blob" };
  return {
    envelope_id: e.envelope_id as string,
    tenant_id: e.tenant_id as string,
    book_id: e.book_id as string,
    object_id: e.object_id as string,
    object_type: e.object_type,
    key_version: e.key_version as number,
    suite_version: e.suite_version as number,
    payload_schema: e.payload_schema as number,
    author_device: e.author_device as string,
    hlc,
    blob_hash: hash,
    size: e.size as number,
    blob,
    blob_ref: blobRef,
  };
}
export function isRefusal(x: unknown): x is Refusal {
  return !!x && typeof x === "object" && "result" in (x as Record<string, unknown>) &&
    !("envelope_id" in (x as Record<string, unknown>));
}

export interface ShapeContext {
  jwtDeviceId: string;
  bookTenantId: string;
  highest: { key_version: number; issued_at: Date } | null;
  nowMs: number;
}

/** Runs the eight checks in the documented order; the first failure wins. */
export async function checkShape(row: EnvelopeRow, ctx: ShapeContext): Promise<Refusal | null> {
  if (row.author_device !== ctx.jwtDeviceId) {
    return { result: "rejected:shape", check: "author_device" };
  }
  if (row.tenant_id !== ctx.bookTenantId) return { result: "rejected:shape", check: "tenant_id" };
  if (row.size > ENVELOPE_MAX_BYTES) return { result: "rejected:too_large", check: "size" };
  if (row.blob) {
    if (row.blob.length !== row.size) return { result: "rejected:shape", check: "size" };
    if (!bytesEqual(await blake2b256(row.blob), row.blob_hash)) {
      return { result: "rejected:shape", check: "blob_hash" };
    }
  }
  if (!SUITE_VERSIONS.has(row.suite_version)) {
    return { result: "rejected:shape", check: "suite_version" };
  }
  if (!PAYLOAD_SCHEMAS.has(row.payload_schema)) {
    const max = Math.max(...PAYLOAD_SCHEMAS);
    return {
      result: row.payload_schema > max ? "rejected:version" : "rejected:shape",
      check: "payload_schema",
    };
  }
  if (ctx.highest) {
    if (row.key_version > ctx.highest.key_version) {
      return { result: "rejected:shape", check: "key_version" };
    }
    if (
      row.key_version < ctx.highest.key_version &&
      ctx.nowMs - ctx.highest.issued_at.getTime() > KEY_STALE_GRACE_MS
    ) {
      return { result: "rejected:key_version_stale", check: "key_version" };
    }
  } else if (row.key_version !== 1) {
    return { result: "rejected:shape", check: "key_version" };
  }
  if (hlcPhysicalMs(row.hlc) > ctx.nowMs + HLC_FUTURE_MS) {
    return { result: "rejected:hlc_future", check: "hlc" };
  }
  return null;
}
