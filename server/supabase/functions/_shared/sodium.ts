// All crypto via libsodium (CLAUDE.md rule 7): BLAKE2b-256 for blob_hash / code hashes,
// Ed25519 detached verify for certs, records and challenges, HMAC-SHA256 for our JWT and phone_hmac.
import _sodium from "sodium";

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
