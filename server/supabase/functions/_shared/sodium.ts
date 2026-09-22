// All crypto via libsodium (CLAUDE.md rule 7): BLAKE2b-256 for blob_hash / code hashes,
// Ed25519 detached verify for certs, records and challenges, HMAC-SHA256 for our JWT and phone_hmac.
import _sodium from "sodium";
import { b64url } from "./bytes.ts";
import { NO_CAP, type Plan } from "./registry.ts";

export type Sodium = typeof _sodium;
let ready: Promise<Sodium> | null = null;
export function sodium(): Promise<Sodium> {
  const p = ready ?? _sodium.ready.then(() => _sodium);
  ready = p;
  return p;
}

export async function blake2b256(data: Uint8Array): Promise<Uint8Array> {
  const s = await sodium();
  return s.crypto_generichash(32, data);
}
export async function ed25519Verify(
  msg: Uint8Array,
  sig: Uint8Array,
  pub: Uint8Array,
): Promise<boolean> {
  if (sig.length !== 64 || pub.length !== 32) return false;
  const s = await sodium();
  try {
    return s.crypto_sign_verify_detached(sig, msg, pub);
  } catch {
    return false;
  }
}
export async function hmacSha256(key: Uint8Array, msg: Uint8Array): Promise<Uint8Array> {
  const s = await sodium();
  return s.crypto_auth_hmacsha256(msg, key);
}
/** HMAC-SHA256 with a key of any length (gateway webhook secrets); the one-shot API needs 32 bytes. */
export async function hmacSha256AnyKey(key: Uint8Array, msg: Uint8Array): Promise<Uint8Array> {
  const s = await sodium();
  const state = s.crypto_auth_hmacsha256_init(key);
  s.crypto_auth_hmacsha256_update(state, msg);
  return s.crypto_auth_hmacsha256_final(state);
}
export async function hmacSha256Verify(
  key: Uint8Array,
  msg: Uint8Array,
  tag: Uint8Array,
): Promise<boolean> {
  const s = await sodium();
  if (tag.length !== 32) return false;
  return s.crypto_auth_hmacsha256_verify(tag, msg, key);
}
export async function randomBytes(n: number): Promise<Uint8Array> {
  const s = await sodium();
  return s.randombytes_buf(n);
}
export async function constantTimeEqual(a: Uint8Array, b: Uint8Array): Promise<boolean> {
  if (a.length !== b.length) return false;
  const s = await sodium();
  return s.memcmp(a, b);
}

// ---------------------------------------------------------------- entitlement tokens (08 §3 🔒)
//
// THE WIRE FORMAT, in one place, because the client implements the verifier from this header and
// nothing else (the token is opaque bytes to every other layer). ADR 2026-09-05g §1 🔒; 04 §8
// rule 6 🔒 — this key "signs plan metadata the server already holds and nothing else", which is
// why the only signing function this file exposes takes `EntitlementPayload` and no byte string.
// There is deliberately no generic `ed25519Sign` here: a caller cannot ask this key to sign an
// envelope, a challenge, a record or anything else, because the type system will not let it.
//
//   token bytes (what `entitlement_tokens.token` stores, and what sync-meta relays base64url'd)
//     = UTF-8 of   <payload_b64url> "." <sig_b64url>
//   payload_b64url = base64url, UNPADDED, of the canonical JSON payload bytes below
//   sig_b64url     = base64url, UNPADDED, of the 64-byte Ed25519 DETACHED signature over exactly
//                    those canonical payload bytes (crypto_sign_detached; no prehash, no context)
//
// Canonical JSON payload bytes: UTF-8, no whitespace, keys in THIS fixed order (not sorted — the
// order below is the order of ADR 2026-09-05g §1's field list), every number a JSON integer
// literal, `period_end` and `grace_kind` null when absent:
//
//   {"tenant_id":"…","plan":"…","limits":{"members":N,"business_books":N,"devices":N,
//    "envelopes_per_book":N,"tenant_bytes":N,"attachment_bytes":N},
//    "period_end":N|null,"grace_kind":"dunning"|null,"iat":N,"exp":N}
//
// `iat`/`exp`/`period_end` are epoch MILLISECONDS (the unit every other value on the meta wire
// uses — sync-meta's shapeRow renders every timestamp with Date.getTime()). exp − iat ≤ 30 d
// (ADR §1 🔒). A verifier MUST re-encode nothing: it verifies the signature over the payload bytes
// exactly as received, then parses them. Unknown fields do not exist by construction — the field
// set is 🔒 and `entitlementPayloadBytes` refuses anything else.
//
// ⚠️ SPEC (M13-TOK1, 22 Sep): ADR 2026-09-05g §1 🔒 rotates `entitlement_key` annually "with a
// 30-day overlap" but the token carries NO key id, and the field set is exact, so one cannot be
// added. During an overlap the client therefore has to try BOTH pinned public keys and accept a
// token that verifies under either. Reported to the owner rather than decided here.
export interface EntitlementLimits {
  members: number;
  business_books: number;
  devices: number;
  envelopes_per_book: number;
  tenant_bytes: number;
  attachment_bytes: number;
}
/** The 🔒 field set of 08 §3 line 35 / ADR 2026-09-05g §1, and nothing else. */
export interface EntitlementPayload {
  tenant_id: string;
  plan: Plan;
  limits: EntitlementLimits;
  period_end: number | null; // epoch ms; null when the tenant has never had a period
  grace_kind: "dunning" | null;
  iat: number; // epoch ms, the SERVER's clock
  exp: number; // epoch ms; exp − iat ≤ 30 d
}

export const TOKEN_MAX_TTL_MS = 30 * 24 * 60 * 60 * 1000; // ADR 2026-09-05g §1 🔒 "exp − iat ≤ 30 d"
const LIMIT_KEYS = [
  "members",
  "business_books",
  "devices",
  "envelopes_per_book",
  "tenant_bytes",
  "attachment_bytes",
] as const;

function int(v: unknown, what: string): number {
  // CLAUDE.md rule 1's shape: a float in a limit or a timestamp is a bug, never a rounding.
  if (typeof v !== "number" || !Number.isSafeInteger(v)) {
    throw new TypeError(`entitlement ${what} must be a safe integer`);
  }
  return v;
}

/** The canonical bytes that are signed and that a verifier checks the signature over. */
export function entitlementPayloadBytes(p: EntitlementPayload): Uint8Array {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(p.tenant_id)) {
    throw new TypeError("entitlement tenant_id must be a canonical uuid");
  }
  if (p.grace_kind !== null && p.grace_kind !== "dunning") {
    throw new TypeError("entitlement grace_kind is 'dunning' or null (03 §2.4 🔒)");
  }
  const iat = int(p.iat, "iat"), exp = int(p.exp, "exp");
  if (exp <= iat || exp - iat > TOKEN_MAX_TTL_MS) {
    throw new RangeError("entitlement exp − iat must be > 0 and ≤ 30 d (ADR 2026-09-05g §1 🔒)");
  }
  const limits: string[] = [];
  for (const k of LIMIT_KEYS) {
    const v = int(p.limits[k], `limits.${k}`);
    if (v < 0 && v !== NO_CAP) {
      throw new RangeError(`entitlement limits.${k} must be ≥ 0 or NO_CAP`);
    }
    limits.push(`${JSON.stringify(k)}:${v}`);
  }
  const periodEnd = p.period_end === null ? "null" : String(int(p.period_end, "period_end"));
  const json = "{" +
    `"tenant_id":${JSON.stringify(p.tenant_id)},` +
    `"plan":${JSON.stringify(p.plan)},` +
    `"limits":{${limits.join(",")}},` +
    `"period_end":${periodEnd},` +
    `"grace_kind":${p.grace_kind === null ? "null" : JSON.stringify(p.grace_kind)},` +
    `"iat":${iat},"exp":${exp}` +
    "}";
  return new TextEncoder().encode(json);
}

/** The Ed25519 public half of the server's `entitlement_key`, derived from its 32-byte seed. The
 *  seed never leaves this module's callers and neither half is ever logged (04 §8 rule 1 🔒). */
export async function entitlementPublicKey(seed: Uint8Array): Promise<Uint8Array> {
  const s = await sodium();
  if (seed.length !== 32) throw new TypeError("entitlement_key seed must be 32 bytes");
  return s.crypto_sign_seed_keypair(seed).publicKey;
}

/** Sign ONE entitlement payload. The only thing this key may ever sign (04 §8 rule 6 🔒). */
export async function signEntitlementToken(
  payload: EntitlementPayload,
  seed: Uint8Array,
): Promise<Uint8Array> {
  const s = await sodium();
  if (seed.length !== 32) throw new TypeError("entitlement_key seed must be 32 bytes");
  const msg = entitlementPayloadBytes(payload);
  const kp = s.crypto_sign_seed_keypair(seed);
  const sig = s.crypto_sign_detached(msg, kp.privateKey);
  try {
    return new TextEncoder().encode(`${b64url.enc(msg)}.${b64url.enc(sig)}`);
  } finally {
    s.memzero(kp.privateKey); // zeroize after use (CLAUDE.md rule 7)
  }
}

/** Split stored token bytes back into the signed message and its signature. The server never needs
 *  to verify its own token; this exists so a test (and the client's port of this header) reads the
 *  REAL bytes rather than a re-encoding of what it expected. */
export function parseEntitlementToken(
  token: Uint8Array,
): { payloadBytes: Uint8Array; sig: Uint8Array; payload: EntitlementPayload } {
  const parts = new TextDecoder().decode(token).split(".");
  if (parts.length !== 2) throw new TypeError("entitlement token is <payload>.<sig>");
  const payloadBytes = b64url.dec(parts[0]);
  const sig = b64url.dec(parts[1]);
  return {
    payloadBytes,
    sig,
    payload: JSON.parse(new TextDecoder().decode(payloadBytes)) as EntitlementPayload,
  };
}
