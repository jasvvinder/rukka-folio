// Our own JWT (06 §4): HS256 via libsodium HMAC-SHA256, 15-minute access token {user_id, device_id}.
// Not the platform's auth. Verified here, then carried into the DB transaction with SET LOCAL.
import { b64url, isUuid } from "./bytes.ts";
import { hmacSha256, hmacSha256Verify } from "./sodium.ts";

export interface Claims {
  user_id: string;
  device_id: string;
}
export const ACCESS_TTL_S = 15 * 60;
const HEADER = b64url.enc(new TextEncoder().encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));

export async function mintAccessToken(key: Uint8Array, c: Claims, nowS: number): Promise<string> {
  const payload = b64url.enc(new TextEncoder().encode(JSON.stringify({
    user_id: c.user_id,
    device_id: c.device_id,
    iat: nowS,
    exp: nowS + ACCESS_TTL_S,
  })));
  const signing = new TextEncoder().encode(`${HEADER}.${payload}`);
  return `${HEADER}.${payload}.${b64url.enc(await hmacSha256(key, signing))}`;
}

export async function verifyAccessToken(
  key: Uint8Array,
  token: string,
  nowS: number,
): Promise<Claims | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  let tag: Uint8Array;
  try {
    tag = b64url.dec(parts[2]);
  } catch {
    return null;
  }
  const ok = await hmacSha256Verify(key, new TextEncoder().encode(`${parts[0]}.${parts[1]}`), tag);
  if (!ok) return null;
  try {
    const body = JSON.parse(new TextDecoder().decode(b64url.dec(parts[1])));
    if (typeof body.exp !== "number" || body.exp <= nowS) return null;
    if (!isUuid(body.user_id) || !isUuid(body.device_id)) return null;
    return { user_id: body.user_id, device_id: body.device_id };
  } catch {
    return null;
  }
}

export function bearer(req: Request): string | null {
  const h = req.headers.get("authorization") ?? "";
  return h.startsWith("Bearer ") ? h.slice(7) : null;
}
