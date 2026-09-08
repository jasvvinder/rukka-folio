// Identity without platform auth (06 §2–§4 🔒; ADR 2026-09-05c §7, 05d §2). Sub-routes:
//   POST /otp/request   {phone, purpose, channel?, language?}      → {ok, resend_after_s}   (generic: no oracle)
//   POST /otp/verify    {phone, purpose, code}                     → {ticket, user_id, expires_in_s}
//   POST /devices       {ticket, pub_ed, pub_x, model?, os?, attestation?, umk?} → {device_id, user_id, status}
//   POST /devices/certify  (Bearer) {cert:{signature, issued_at_ms, issued_by_device?}, umk_key_version?, umk_pub_ed?}
//   POST /challenge     {device_id}                                → {nonce, expires_in_s}
//   POST /token         {device_id, nonce, unix_ts, signature}     → {access_token, expires_in, refresh_token, …}
//   POST /refresh       {device_id, refresh_token, nonce, unix_ts, signature} → same, rotated family
// Signed challenge bytes: nonce(32) ‖ uuid16(device_id) ‖ i64be(unix_ts seconds) — ⚠️ WIRE (06 §4 fixes the
// order, not the encoding). Certificates verify under the user's UMK exactly as core_crypto/device_cert.dart.
// Nothing here logs a body, a phone or a code (CLAUDE.md rule 4).
import { b64any, b64url, concat, i64be, isUuid, uuid16 } from "../_shared/bytes.ts";
import { ACCESS_TTL_S, type Claims, mintAccessToken } from "../_shared/claims.ts";
import { type Deps, serve } from "../_shared/deps.ts";
import { clientIp, error, json, readJson, subPath } from "../_shared/http.ts";
import { encryptPhone, normaliseE164, phoneHmac } from "../_shared/phone.ts";
import type { OtpChannel } from "../_shared/otp/provider.ts";
import { authenticate, gate } from "../_shared/route.ts";
import {
  blake2b256,
  constantTimeEqual,
  ed25519Verify,
  hmacSha256,
  randomBytes,
} from "../_shared/sodium.ts";
import { DeviceCapError, type RefreshToken, StoreDenied } from "../_shared/store.ts";

export const OTP_TTL_S = 5 * 60;
export const OTP_MAX_ATTEMPTS = 3;
export const OTP_RESEND_BACKOFF_S = [30, 60, 300]; // 06 §2: 30 s → 60 s → 5 min
export const OTP_PER_NUMBER = { hour: 5, day: 10 };
export const OTP_PER_IP_HOUR = 30; // ⚠️ 06 §3: numbers M6
export const TICKET_TTL_S = 10 * 60;
export const NONCE_TTL_S = 60;
export const SKEW_S = 90;
export const REFRESH_IDLE_S = 30 * 86400;
const PURPOSES = new Set(["signup", "device_activation", "phone_change", "account_deletion"]);
const MAX_BODY = 64 * 1024;

export async function handler(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== "POST") return error(405, "method_not_allowed");
  const gated = await gate(req, deps, "auth");
  if (gated) return gated;
  const body = await readJson(req, MAX_BODY) as Record<string, unknown> | null;
  if (!body || typeof body !== "object") return error(400, "bad_request");
  switch (subPath(req, "auth-challenge")) {
    case "/otp/request":
      return otpRequest(req, deps, body);
    case "/otp/verify":
      return otpVerify(deps, body);
    case "/devices":
      return registerDevice(deps, body);
    case "/devices/certify":
      return certify(req, deps, body);
    case "/challenge":
      return challenge(deps, body);
    case "/token":
      return token(deps, body);
    case "/refresh":
      return refresh(deps, body);
    default:
      return error(404, "not_found");
  }
}

// ---------------------------------------------------------------- OTP (06 §2)
async function otpRequest(req: Request, deps: Deps, b: Record<string, unknown>): Promise<Response> {
  const phone = normaliseE164(b.phone);
  const purpose = typeof b.purpose === "string" && PURPOSES.has(b.purpose) ? b.purpose : null;
  if (!phone || !purpose) return error(400, "bad_request");
  const preferred: OtpChannel = b.channel === "sms" ? "sms" : "whatsapp";
  const now = deps.now();
  const hmac = await phoneHmac(deps.phoneHmacKey, phone);
  const ipHash = await hmacSha256(deps.phoneHmacKey, new TextEncoder().encode(clientIp(req)));

  const decision = await deps.store.withClaims(null, async (tx) => {
    const day = await tx.otpChallengesSince(hmac, new Date(now.getTime() - 86400e3));
    const hour = day.filter((d) => d.getTime() >= now.getTime() - 3600e3);
    const ip = await tx.otpChallengesByIpSince(ipHash, new Date(now.getTime() - 3600e3));
    if (
      hour.length >= OTP_PER_NUMBER.hour || day.length >= OTP_PER_NUMBER.day ||
      ip >= OTP_PER_IP_HOUR
    ) {
      return { status: 429 as const, resend_after_s: 3600 };
    }
    const last = hour.sort((a, c) => c.getTime() - a.getTime())[0];
    const backoff = OTP_RESEND_BACKOFF_S[Math.min(hour.length, OTP_RESEND_BACKOFF_S.length) - 1] ??
      0;
    if (last && now.getTime() - last.getTime() < backoff * 1000) {
      return {
        status: 429 as const,
        resend_after_s: Math.ceil((backoff * 1000 - (now.getTime() - last.getTime())) / 1000),
      };
    }
    return {
      status: 200 as const,
      resend_after_s: OTP_RESEND_BACKOFF_S[Math.min(hour.length, OTP_RESEND_BACKOFF_S.length - 1)],
    };
  });
  if (decision.status === 429) {
    return json(429, { error: "too_many_requests", resend_after_s: decision.resend_after_s });
  }

  const code = await sixDigits();
  const codeHash = await blake2b256(new TextEncoder().encode(code)); // the code itself is never stored
  const channel = await deps.otp.send(phone, code, preferred);
  // Provider failure and unknown numbers both answer the same way: the response never says whether
  // the number exists or whether a message left (06 §2 "generic error messages").
  if (channel) {
    await deps.store.withClaims(null, (tx) =>
      tx.createOtpChallenge({
        phone_hmac: hmac,
        purpose,
        code_hash: codeHash,
        attempts: 0,
        channel,
        ip_hash: ipHash,
        created_at: now,
        expires_at: new Date(now.getTime() + OTP_TTL_S * 1000),
        consumed_at: null,
      }));
  }
  return json(200, { ok: true, resend_after_s: decision.resend_after_s });
}

async function otpVerify(deps: Deps, b: Record<string, unknown>): Promise<Response> {
  const phone = normaliseE164(b.phone);
  const purpose = typeof b.purpose === "string" && PURPOSES.has(b.purpose) ? b.purpose : null;
  const code = typeof b.code === "string" && /^\d{6}$/.test(b.code) ? b.code : null;
  if (!phone || !purpose || !code) return error(400, "bad_request");
  const now = deps.now();
  const hmac = await phoneHmac(deps.phoneHmacKey, phone);
  const codeHash = await blake2b256(new TextEncoder().encode(code));
  const language = typeof b.language === "string" && ["en", "pa", "hi"].includes(b.language)
    ? b.language
    : null;

  const out = await deps.store.withClaims(null, async (tx) => {
    const c = await tx.latestOtpChallenge(hmac, purpose);
    if (!c || c.consumed_at || c.expires_at <= now || c.attempts >= OTP_MAX_ATTEMPTS) {
      return { status: 400 as const };
    }
    if (!(await constantTimeEqual(c.code_hash, codeHash))) {
      const n = await tx.bumpOtpAttempts(c.id);
      return { status: 400 as const, attempts_left: OTP_MAX_ATTEMPTS - n };
    }
    await tx.consumeOtpChallenge(c.id);
    let user = await tx.findUserByPhoneHmac(hmac);
    if (!user) user = await tx.signupUser(hmac, await encryptPhone(deps.phoneKek, phone), language);
    const ticket = await randomBytes(32);
    await tx.createActivationTicket({
      ticket_hash: await blake2b256(ticket),
      phone_hmac: hmac,
      purpose,
      user_id: user,
      created_at: now,
      expires_at: new Date(now.getTime() + TICKET_TTL_S * 1000),
      consumed_at: null,
    });
    return { status: 200 as const, ticket: b64url.enc(ticket), user_id: user };
  });
  if (out.status !== 200) {
    return json(400, {
      error: "otp_invalid",
      ...(out.attempts_left !== undefined ? { attempts_left: out.attempts_left } : {}),
    });
  }
  return json(200, { ticket: out.ticket, user_id: out.user_id, expires_in_s: TICKET_TTL_S });
}

// ---------------------------------------------------------------- devices (06 §3)
async function registerDevice(deps: Deps, b: Record<string, unknown>): Promise<Response> {
  const ticket = b64any(b.ticket), pubEd = b64any(b.pub_ed), pubX = b64any(b.pub_x);
  if (
    !ticket || ticket.length !== 32 || !pubEd || pubEd.length !== 32 || !pubX || pubX.length !== 32
  ) return error(400, "bad_request");
  const now = deps.now();
  const model = typeof b.model === "string" ? b.model.slice(0, 64) : null;
  const os = typeof b.os === "string" ? b.os.slice(0, 64) : null;
  const attestation = b.attestation && typeof b.attestation === "object" ? b.attestation : null;
  const hash = await blake2b256(ticket);

  const reg = await deps.store.withClaims(null, async (tx) => {
    const t = await tx.consumeActivationTicket(hash, now);
    if (!t || !t.user_id) return { status: 401 as const };
    try {
      return {
        status: 200 as const,
        user_id: t.user_id,
        device_id: await tx.registerDevice(t.user_id, pubEd, pubX, model, os, attestation),
      };
    } catch (e) {
      if (e instanceof DeviceCapError) return { status: 409 as const };
      throw e;
    }
  });
  if (reg.status === 401) return error(401, "ticket_invalid");
  if (reg.status === 409) return error(409, "device_cap");

  let status = "registered";
  if (b.umk && typeof b.umk === "object") {
    // First device self-certifies (04 §3.4; 06 §3 step 4) in the same call — fewer round trips, same rule.
    const r = await certifyWith(
      deps,
      { user_id: reg.user_id, device_id: reg.device_id },
      pubEd,
      pubX,
      b.umk as Record<string, unknown>,
    );
    if (r !== "certified") {
      return json(200, { device_id: reg.device_id, user_id: reg.user_id, status, cert_error: r });
    }
    status = "certified";
  }
  return json(200, { device_id: reg.device_id, user_id: reg.user_id, status });
}

async function certify(req: Request, deps: Deps, b: Record<string, unknown>): Promise<Response> {
  const claims = await authenticate(req, deps);
  if (claims instanceof Response) return claims;
  const dev = await deps.store.withClaims(claims, (tx) => tx.deviceAuthRow(claims.device_id));
  if (!dev) return error(401, "unauthenticated");
  const pubX = await deps.store.withClaims(claims, async (tx) => {
    const page = await tx.metaPage("devices", null, 500);
    return page.rows.find((r) => r.id === claims.device_id)?.pub_x as Uint8Array | undefined;
  });
  if (!pubX) return error(401, "unauthenticated");
  const r = await certifyWith(deps, claims, dev.pub_ed, pubX, b);
  return r === "certified"
    ? json(200, { device_id: claims.device_id, status: "certified" })
    : error(400, r);
}

/** Verifies cert = Sign_UMK_ed(uuid16(device) ‖ pub_ed ‖ pub_x ‖ i64be(issued_at_ms)) and flips status. */
async function certifyWith(
  deps: Deps,
  c: Claims,
  pubEd: Uint8Array,
  pubX: Uint8Array,
  b: Record<string, unknown>,
): Promise<string> {
  const cert = b.cert as Record<string, unknown> | undefined;
  const sig = b64any(cert?.signature);
  const issuedAt = typeof cert?.issued_at_ms === "number" && Number.isSafeInteger(cert.issued_at_ms)
    ? cert.issued_at_ms
    : null;
  const issuedBy = isUuid(cert?.issued_by_device) ? cert!.issued_by_device as string : null;
  const version = typeof b.umk_key_version === "number" && b.umk_key_version >= 1
    ? b.umk_key_version
    : 1;
  const offered = b64any(b.umk_pub_ed);
  if (!sig || sig.length !== 64 || issuedAt === null) return "cert_malformed";
  return await deps.store.withClaims(c, async (tx) => {
    let umk = await tx.umkPubFor(c.user_id, version);
    if (!umk) {
      if (!offered || offered.length !== 32) return "umk_unknown";
      umk = offered; // first device: the UMK public key it registers is the one it self-certifies under
    }
    const msg = concat([uuid16(c.device_id), pubEd, pubX, i64be(issuedAt)]);
    if (!(await ed25519Verify(msg, sig, umk))) return "cert_invalid";
    try {
      if (offered && offered.length === 32) await tx.setUmkPub(c.user_id, version, umk);
      await tx.certifyDevice(c.device_id, sig, new Date(issuedAt), issuedBy, version);
    } catch (e) {
      if (e instanceof StoreDenied) return e.reason;
      throw e;
    }
    return "certified";
  });
}

// ---------------------------------------------------------------- sessions (06 §4)
async function challenge(deps: Deps, b: Record<string, unknown>): Promise<Response> {
  if (!isUuid(b.device_id)) return error(400, "bad_request");
  const now = deps.now();
  const nonce = await randomBytes(32);
  const ok = await deps.store.withClaims(null, async (tx) => {
    const d = await tx.deviceAuthRow(b.device_id as string);
    if (!d) return false;
    await tx.createNonce(
      nonce,
      b.device_id as string,
      new Date(now.getTime() + NONCE_TTL_S * 1000),
    );
    return true;
  });
  // Unknown device still gets a nonce-shaped answer: no enumeration oracle.
  return json(200, {
    nonce: b64url.enc(ok ? nonce : await randomBytes(32)),
    expires_in_s: NONCE_TTL_S,
  });
}

async function verifyChallenge(
  deps: Deps,
  b: Record<string, unknown>,
  tx: Parameters<Parameters<Deps["store"]["withClaims"]>[1]>[0],
) {
  const nonce = b64any(b.nonce), sig = b64any(b.signature);
  const ts = typeof b.unix_ts === "number" && Number.isSafeInteger(b.unix_ts) ? b.unix_ts : null;
  if (
    !isUuid(b.device_id) || !nonce || nonce.length !== 32 || !sig || sig.length !== 64 ||
    ts === null
  ) return null;
  const now = deps.now();
  if (Math.abs(now.getTime() / 1000 - ts) > SKEW_S) return null;
  const d = await tx.deviceAuthRow(b.device_id as string);
  if (!d || d.status === "revoked" || d.status === "suspended") return null;
  if (!(await tx.consumeNonce(nonce, b.device_id as string, now))) return null;
  const msg = concat([nonce, uuid16(b.device_id as string), i64be(ts)]);
  if (!(await ed25519Verify(msg, sig, d.pub_ed))) return null;
  return { user_id: d.user_id, device_id: b.device_id as string, status: d.status };
}

async function issueTokens(
  deps: Deps,
  tx: Parameters<Parameters<Deps["store"]["withClaims"]>[1]>[0],
  c: Claims,
  family: string,
  status: string,
  rotateFrom: Uint8Array | null,
) {
  const now = deps.now();
  const refreshRaw = await randomBytes(32);
  const row: RefreshToken = {
    token_hash: await blake2b256(refreshRaw),
    family_id: family,
    device_id: c.device_id,
    user_id: c.user_id,
    created_at: now,
    expires_at: new Date(now.getTime() + REFRESH_IDLE_S * 1000),
    rotated_at: null,
    revoked_at: null,
  };
  if (rotateFrom) await tx.rotateRefreshToken(rotateFrom, row);
  else await tx.insertRefreshToken(row);
  return {
    access_token: await mintAccessToken(deps.jwtKey, c, Math.floor(now.getTime() / 1000)),
    expires_in: ACCESS_TTL_S,
    refresh_token: b64url.enc(refreshRaw),
    refresh_expires_at: row.expires_at.getTime(),
    user_id: c.user_id,
    device_id: c.device_id,
    device_status: status,
  };
}

async function token(deps: Deps, b: Record<string, unknown>): Promise<Response> {
  const out = await deps.store.withClaims(null, async (tx) => {
    const v = await verifyChallenge(deps, b, tx);
    if (!v) return null;
    return await issueTokens(
      deps,
      tx,
      { user_id: v.user_id, device_id: v.device_id },
      crypto.randomUUID(),
      v.status,
      null,
    );
  });
  return out ? json(200, out) : error(401, "challenge_failed");
}

async function refresh(deps: Deps, b: Record<string, unknown>): Promise<Response> {
  const raw = b64any(b.refresh_token);
  if (!raw || raw.length !== 32) return error(401, "refresh_invalid");
  const hash = await blake2b256(raw);
  const out = await deps.store.withClaims(null, async (tx) => {
    const t = await tx.findRefreshToken(hash);
    if (!t || t.revoked_at || t.expires_at <= deps.now() || t.device_id !== b.device_id) {
      return { error: "refresh_invalid" };
    }
    if (t.rotated_at) {
      await tx.revokeRefreshFamily(t.family_id); // reuse of a rotated token = theft signal (06 §4)
      return { error: "refresh_reused" };
    }
    const v = await verifyChallenge(deps, b, tx); // every refresh needs a fresh signature
    if (!v || v.user_id !== t.user_id) return { error: "challenge_failed" };
    return await issueTokens(
      deps,
      tx,
      { user_id: t.user_id, device_id: t.device_id },
      t.family_id,
      v.status,
      hash,
    );
  });
  return "error" in out ? error(401, out.error as string) : json(200, out);
}

async function sixDigits(): Promise<string> {
  // Rejection sampling over 4 random bytes keeps the distribution uniform (libsodium RNG only, rule 7).
  for (;;) {
    const r = await randomBytes(4);
    const n = new DataView(r.buffer).getUint32(0);
    if (n < 4_294_000_000) return String(n % 1_000_000).padStart(6, "0");
  }
}

if (import.meta.main) serve(handler);
