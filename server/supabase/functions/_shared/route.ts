// Per-request preamble shared by the sync routes: 426 min-version gate (06 §4.5, 05 §1) from
// app_config, then our JWT → Claims (06 §4). Also the envelope → wire shaping (05 §3/§4 names,
// bytes base64url as wire.dart reads them, hlc/seq as bare integer literals via jsonBig).
import { b64url, jsonBig } from "./bytes.ts";
import { bearer, type Claims, verifyAccessToken } from "./claims.ts";
import type { Deps } from "./deps.ts";
import { error, json, minVersionGate } from "./http.ts";
import { belowMinVersion } from "./registry.ts";
import type { EnvelopeRow, SignedRecordRow } from "./store.ts";

export type RouteGroup = "sync" | "auth" | "billing";

/** 426 when the client is below the route group's minimum. Reads app_config without claims. */
export async function gate(req: Request, deps: Deps, group: RouteGroup): Promise<Response | null> {
  const min = await deps.store.withClaims(
    null,
    (tx) => tx.appConfig(`min_client_version.${group}`),
  );
  return minVersionGate(req, typeof min === "string" ? min : "0.0.0", belowMinVersion);
}

export async function authenticate(req: Request, deps: Deps): Promise<Claims | Response> {
  const token = bearer(req);
  if (!token) return error(401, "unauthenticated");
  const claims = await verifyAccessToken(
    deps.jwtKey,
    token,
    Math.floor(deps.now().getTime() / 1000),
  );
  return claims ?? error(401, "unauthenticated");
}

/** JSON response whose BigInt fields render as integers. */
export function jsonBigResponse(status: number, body: unknown): Response {
  return new Response(jsonBig(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export function envelopeToWire(e: EnvelopeRow): Record<string, unknown> {
  return {
    envelope_id: e.envelope_id,
    seq: e.seq,
    tenant_id: e.tenant_id,
    book_id: e.book_id,
    object_id: e.object_id,
    object_type: e.object_type,
    key_version: e.key_version,
    suite_version: e.suite_version,
    payload_schema: e.payload_schema,
    author_device: e.author_device,
    hlc: e.hlc,
    blob_hash: b64url.enc(e.blob_hash),
    size: e.size,
    ...(e.blob ? { blob: b64url.enc(e.blob) } : { blob_ref: e.blob_ref }),
  };
}

export function recordToWire(r: SignedRecordRow): Record<string, unknown> {
  return {
    id: r.id,
    seq: r.seq,
    suite_version: r.suite_version,
    tenant_id: r.tenant_id,
    kind: r.kind,
    payload_json: b64url.enc(r.payload_bytes),
    author_device_id: r.author_device,
    author_sig: b64url.enc(r.author_sig),
    hlc: r.hlc,
  };
}

export { error, json };
