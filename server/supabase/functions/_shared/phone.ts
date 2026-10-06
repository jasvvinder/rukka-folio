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

// ---------------------------------------------------------------- sign-up tickets (ADR 2026-10-05c §2)
// A code verified on the SIGN-IN door for a number with no account signs nobody up: the person has
// not yet chosen *Set up new books* (S0.2e). The server hands back an opaque sign-up ticket instead,
// and /signup/adopt turns it into the sign-up without a second code. Adopt needs the number to
// write users.phone_ct, and the body carries none — but nothing recoverable about the phone may be
// KEPT for a person who did not sign up (ADR 2026-09-05c §4 🔒; E-03-17: ciphertext lives in users
// only). So the number travels INSIDE the ticket, sealed under the phone KEK, and the server keeps
// only the hash of the ticket's bytes and the phone's HMAC (the row, activation_tickets with no
// user). Layout: secret(32) ‖ nonce(24) ‖ XChaCha20-Poly1305(kek, {p: e164, l: language},
// ad = "rf.signup_ticket.v1" ‖ secret). The associated data domain-separates it from users.phone_ct
// (same KEK, no AD), so neither blob opens as the other.
const SIGNUP_AD = new TextEncoder().encode("rf.signup_ticket.v1");
const SIGNUP_SECRET = 32;
const LANGUAGES = new Set(["en", "pa", "hi"]);
/** The smallest and largest sealed ticket: anything outside is refused before any lookup. */
export const SIGNUP_TICKET_MIN_BYTES = SIGNUP_SECRET + 24 + 16 + 1;
export const SIGNUP_TICKET_MAX_BYTES = 160;

export async function sealSignupTicket(
  kek: Uint8Array,
  e164: string,
  language: string | null,
): Promise<Uint8Array> {
  const s = await sodium();
  const secret = s.randombytes_buf(SIGNUP_SECRET);
  const nonce = s.randombytes_buf(s.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES);
  const pt = new TextEncoder().encode(JSON.stringify({ p: e164, l: language }));
  const ct = s.crypto_aead_xchacha20poly1305_ietf_encrypt(
    pt,
    concat([SIGNUP_AD, secret]),
    null,
    nonce,
    kek,
  );
  return concat([secret, nonce, ct]);
}

/** The number (and verify-time language) sealed in a sign-up ticket, or null for anything that is
 *  not one this KEK sealed: wrong size, tampered, another blob, a malformed number. */
export async function openSignupTicket(
  kek: Uint8Array,
  ticket: Uint8Array,
): Promise<{ phone: string; language: string | null } | null> {
  if (ticket.length < SIGNUP_TICKET_MIN_BYTES || ticket.length > SIGNUP_TICKET_MAX_BYTES) {
    return null;
  }
  const s = await sodium();
  const n = s.crypto_aead_xchacha20poly1305_ietf_NPUBBYTES;
  try {
    const pt = s.crypto_aead_xchacha20poly1305_ietf_decrypt(
      null,
      ticket.slice(SIGNUP_SECRET + n),
      concat([SIGNUP_AD, ticket.slice(0, SIGNUP_SECRET)]),
      ticket.slice(SIGNUP_SECRET, SIGNUP_SECRET + n),
      kek,
    );
    const o = JSON.parse(new TextDecoder().decode(pt)) as { p?: unknown; l?: unknown };
    const phone = normaliseE164(o.p);
    if (!phone || phone !== o.p) return null;
    const language = typeof o.l === "string" && LANGUAGES.has(o.l) ? o.l : null;
    return { phone, language };
  } catch {
    return null;
  }
}
