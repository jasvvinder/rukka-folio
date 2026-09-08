// Phone numbers at rest (ADR 2026-09-05c §4): phone_hmac = HMAC-SHA256(key, e164) for lookup;
// phone_ct = XChaCha20-Poly1305(kek, e164) — decrypted only to send a one-time code. Both keys come
// from Vault/KMS in the hosted project (server/README.md §4). Never logged, never in a dump.
import { concat } from "./bytes.ts";
import { hmacSha256, sodium } from "./sodium.ts";

const E164 = /^\+[1-9]\d{7,14}$/;
export function normaliseE164(s: unknown): string | null {
  if (typeof s !== "string") return null;
  const t = s.replace(/[\s-]/g, "");
  return E164.test(t) ? t : null;
}
export function phoneHmac(key: Uint8Array, e164: string): Promise<Uint8Array> {
  return hmacSha256(key, new TextEncoder().encode(e164));
}
export async function encryptPhone(kek: Uint8Array, e164: string): Promise<Uint8Array> {
  const s = await sodium();
  const nonce = s.randombytes_buf(s.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES);
  const ct = s.crypto_aead_xchacha20poly1305_ietf_encrypt(
    new TextEncoder().encode(e164),
    null,
    null,
    nonce,
    kek,
  );
  return concat([nonce, ct]);
}
export async function decryptPhone(kek: Uint8Array, blob: Uint8Array): Promise<string | null> {
  const s = await sodium();
  const n = s.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES;
  try {
    const pt = s.crypto_aead_xchacha20poly1305_ietf_decrypt(
      null,
      blob.slice(n),
      null,
      blob.slice(0, n),
      kek,
    );
    return new TextDecoder().decode(pt);
  } catch {
    return null;
  }
}
