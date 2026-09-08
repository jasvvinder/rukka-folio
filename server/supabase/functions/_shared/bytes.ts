// Byte layouts shared with packages/core_crypto (bytes.dart, signed_record.dart, device_cert.dart).
import { decodeBase64, encodeBase64 } from "@std/encoding/base64";
import { decodeBase64Url, encodeBase64Url } from "@std/encoding/base64url";
import { decodeHex, encodeHex } from "@std/encoding/hex";

export const b64 = { enc: encodeBase64, dec: decodeBase64 };
export const b64url = { enc: encodeBase64Url, dec: decodeBase64Url };
export const hex = { enc: encodeHex, dec: decodeHex };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function isUuid(s: unknown): s is string {
  return typeof s === "string" && UUID_RE.test(s);
}
/** Canonical lowercase uuid → 16 bytes (Uuid16.toBytes). */
export function uuid16(id: string): Uint8Array {
  if (!isUuid(id)) throw new TypeError("uuid must be canonical lowercase");
  return decodeHex(id.replaceAll("-", ""));
}
export function u8(v: number): Uint8Array {
  if (v < 0 || v > 255) throw new RangeError("u8");
  return new Uint8Array([v]);
}
export function u32be(v: number): Uint8Array {
  if (v < 0 || v > 0xffffffff) throw new RangeError("u32");
  const out = new Uint8Array(4);
  new DataView(out.buffer).setUint32(0, v);
  return out;
}
/** Signed 64-bit big-endian (HLCs, issued_at milliseconds). */
export function i64be(v: bigint | number): Uint8Array {
  const out = new Uint8Array(8);
  new DataView(out.buffer).setBigInt64(0, BigInt(v));
  return out;
}
export function lengthPrefixedUtf8(s: string): Uint8Array {
  const b = new TextEncoder().encode(s);
  return concat([u32be(b.length), b]);
}
export function concat(parts: Uint8Array[]): Uint8Array {
  let n = 0;
  for (const p of parts) n += p.length;
  const out = new Uint8Array(n);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}
export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}
/** HLC (03 §1): 48-bit physical ms + 16-bit counter, carried as a decimal string on the wire. */
export function hlcPhysicalMs(hlc: bigint): number {
  return Number(hlc >> 16n);
}
export function parseBigint(v: unknown): bigint | null {
  if (typeof v === "number" && Number.isSafeInteger(v)) return BigInt(v);
  if (typeof v === "string" && /^-?\d{1,20}$/.test(v)) return BigInt(v);
  return null;
}

/** Accepts base64 OR base64url, padded or not (wire.dart emits base64url; 03/05 fix no alphabet). */
export function b64any(v: unknown): Uint8Array | null {
  if (typeof v !== "string") return null;
  const std = v.replaceAll("-", "+").replaceAll("_", "/").replace(/=+$/, "");
  if (!/^[A-Za-z0-9+/]*$/.test(std)) return null;
  try {
    return decodeBase64(std + "=".repeat((4 - (std.length % 4)) % 4));
  } catch {
    return null;
  }
}

/** JSON.stringify that renders BigInt as a bare integer literal (an HLC exceeds 2^53; Dart reads i64). */
export function jsonBig(v: unknown): string {
  return JSON.stringify(v, (_k, x) => typeof x === "bigint" ? `‖big:${x.toString()}` : x)
    .replace(/"‖big:(-?\d+)"/g, "$1");
}
