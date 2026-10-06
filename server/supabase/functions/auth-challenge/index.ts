// Identity without platform auth (06 §2–§4 🔒; ADR 2026-09-05c §7, 05d §2). Sub-routes:
//   POST /otp/request   {phone, purpose, channel?, language?}      → {ok, resend_after_s}   (generic: no oracle)
//                       SMS is the one channel (ADR 2026-09-25 §1, amending 06 §2): `channel` is
//                       accepted and ignored — never a 400, since an app build that still asks for
//                       `whatsapp` must get its code — and the answer never names a channel (E-25-1).
//   POST /otp/verify    {phone, purpose, code, user_id?, language?}
//                         → {ticket, user_id, account: "existing" | "created", expires_in_s}
//                         | {account: "none", signup_ticket, expires_in_s}
//                       `user_id` is the id the ledger minted at first run (ADR 2026-10-04b §1 🔒).
//                       A phone that has an account answers `existing` with ITS id and the proposal
//                       is ignored (§3), on every purpose. A phone with none:
//                         * device_activation — the SIGN-IN door (ADR 2026-10-05c §2 🔒): nobody is
//                           signed up. The answer is `none` with an opaque, single-use sign-up
//                           ticket (≤ 10 min) and NO ticket or user_id; /signup/adopt turns it into
//                           the sign-up if the person chooses *Set up new books* (S0.2e).
//                         * signup, phone_change, account_deletion — signed up UNDER the proposal,
//                           never under an id minted here: `created`.
//                       Present but not a canonical lowercase uuid → 400 bad_request, before the
//                       challenge is read. Held by any user (an erased one too) → 409
//                       `{error: user_id_taken}`, nothing created, and the challenge NOT consumed and
//                       its attempts not bumped, so the client re-mints and retries once with the
//                       same code (§2). Absent → the id is minted here, so an older client still
//                       signs up.
//   POST /signup/adopt  {signup_ticket, user_id} → {ticket, user_id, account: "created", expires_in_s}
//                       ADR 2026-10-05c §2: the sign-up the person chose after a `none`, with NO
//                       second code — the ticket is what only a verified code yields. user_id is
//                       required (no client predates this route) and shape-checked first: missing
//                       or malformed → 400 bad_request, ticket untouched. 409 user_id_taken exactly
//                       as verify: nothing created, ticket NOT spent, one retry with a fresh id.
//                       Every ticket problem — absent, malformed, unknown, spent, expired, not the
//                       sealed phone's — is ONE 400 `{error: signup_ticket_invalid}`; so is a phone
//                       that gained an account since the code (fail closed: the ticket is spent and
//                       the client restarts at the code, which then answers `existing`).
//   POST /devices       {device_id, ticket, pub_ed, pub_x, model?, os?, attestation?, umk?} → {device_id, user_id, status}
//                       `umk` is the /devices/certify body below (incl. umk_pub_ed + umk_pub_x), so
//                       the first device self-certifies in the same call (04 §3.4, 06 §3 step 4).
//                       device_id is the ledger's own id (ADR 2026-09-16 §2 🔒) — recorded, echoed,
//                       never issued here; already held → 409 device_id_taken (409 device_cap keeps its string)
//   POST /devices/certify  (Bearer) {cert:{signature, issued_at_ms, issued_by_device?}, umk_key_version?,
//                                     umk_pub_ed?, umk_pub_x?}
//                       BOTH UMK public halves are recorded (04 §6.1/§6.3 🔒, migration 0012): the
//                       ed half verifies the certificate, the x half is what a verifier's device
//                       compares byte-for-byte in the ceremony. Either half offered a second time
//                       with different bytes → 400 `{error: umk_pub_conflict}`, never an overwrite;
//                       an x half that is not 32 bytes → 400 `{error: umk_pub_malformed}`.
//   POST /challenge     {device_id}                                → {nonce, expires_in_s}
//   POST /token         {device_id, nonce, unix_ts, signature}     → {access_token, expires_in, refresh_token, …}
//   POST /refresh       {device_id, refresh_token, nonce, unix_ts, signature} → same, rotated family
// Signed challenge bytes: nonce(32) ‖ uuid16(device_id) ‖ i64be(unix_ts seconds) — ⚠️ WIRE (06 §4 fixes the
// order, not the encoding). Certificates verify under the user's UMK exactly as core_crypto/device_cert.dart.
// Nothing here logs a body, a phone or a code (CLAUDE.md rule 4).
import { b64any, b64url, bytesEqual, concat, i64be, isUuid, uuid16 } from "../_shared/bytes.ts";
import { ACCESS_TTL_S, type Claims, mintAccessToken } from "../_shared/claims.ts";
import { type Deps, serve } from "../_shared/deps.ts";
import { clientIp, error, json, readJson, subPath } from "../_shared/http.ts";
import {
  encryptPhone,
  normaliseE164,
  openSignupTicket,
  phoneHmac,
  sealSignupTicket,
  SIGNUP_TICKET_MAX_BYTES,
  SIGNUP_TICKET_MIN_BYTES,
} from "../_shared/phone.ts";
import { authenticate, gate } from "../_shared/route.ts";
import {
  blake2b256,
  constantTimeEqual,
  ed25519Verify,
  hmacSha256,
  randomBytes,
} from "../_shared/sodium.ts";
import {
  DeviceCapError,
  DeviceIdTakenError,
  type RefreshToken,
  StoreDenied,
  type Tx,
  UserIdTakenError,
} from "../_shared/store.ts";

export const OTP_TTL_S = 5 * 60;
export const OTP_MAX_ATTEMPTS = 3;
export const OTP_RESEND_BACKOFF_S = [30, 60, 300]; // 06 §2: 30 s → 60 s → 5 min
export const OTP_PER_NUMBER = { hour: 5, day: 10 };
export const OTP_PER_IP_HOUR = 30; // ⚠️ 06 §3: numbers M6
export const TICKET_TTL_S = 10 * 60;
/** ADR 2026-10-05c §2: a sign-up ticket lives no longer than an activation ticket (≤ 10 min). */
export const SIGNUP_TICKET_TTL_S = 10 * 60;
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
    case "/signup/adopt":
      return adoptSignup(deps, body);
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

  // A fresh random code, unless the provider carries the fixed dev code. Only a FakeOtpProvider that
  // otp/select.ts bound to the dev project has one (ADR 2026-09-25 §1, desk 57; E-25-8, E-25-9).
  // Either way only the hash is stored, and nothing here logs the code or the phone (rule 4).
  const code = deps.otp.fixedCode ?? await sixDigits();
  const codeHash = await blake2b256(new TextEncoder().encode(code)); // the code itself is never stored
  // One SMS, one attempt: no preference, no failover to another channel (ADR 2026-09-25 §1).
  const channel = await deps.otp.send(phone, code);
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
  // ADR 2026-10-04b §1 🔒: the client's proposed user id. Shape-checked here, BEFORE the challenge
  // is read, so a malformed id costs no attempt and spends no code. Any value present — null
  // included — must be a canonical lowercase uuid: a request that carried something is never
  // quietly given a server-minted id.
  const proposed = Object.hasOwn(b, "user_id") ? b.user_id : undefined;
  if (proposed !== undefined && !isUuid(proposed)) return error(400, "bad_request");
  const now = deps.now();
  const hmac = await phoneHmac(deps.phoneHmacKey, phone);
  const codeHash = await blake2b256(new TextEncoder().encode(code));
  const language = typeof b.language === "string" && ["en", "pa", "hi"].includes(b.language)
    ? b.language
    : null;

  const out = await deps.store.withClaims(null, async (tx) => {
    // One verify per phone at a time, held to commit. The account is resolved BEFORE the code is
    // consumed (below), so the consume no longer serialises two verifies in flight together; this
    // does, and for every purpose. The second one then reads what the first committed: the same
    // challenge spent (400 otp_invalid, as a replay a moment later gets), or — on another purpose —
    // the account just created, whose id it answers. It never races into a second signup for the
    // phone, which answered 409 user_id_taken for the phone's own id, or 500 without one.
    await tx.lockPhoneForVerify(hmac);
    const c = await tx.latestOtpChallenge(hmac, purpose);
    if (!c || c.consumed_at || c.expires_at <= now || c.attempts >= OTP_MAX_ATTEMPTS) {
      return { status: 400 as const };
    }
    if (!(await constantTimeEqual(c.code_hash, codeHash))) {
      const n = await tx.bumpOtpAttempts(c.id);
      return { status: 400 as const, attempts_left: OTP_MAX_ATTEMPTS - n };
    }
    // The account is resolved BEFORE the code is consumed. A phone with an account answers with its
    // id whatever was proposed and whatever the purpose — no purpose re-keys a user (§1, §3). Only
    // a phone with none is signed up, under the proposal when there is one; a proposal some row
    // already holds is refused with nothing written and the challenge untouched (ADR 04b §2: the
    // client re-mints and retries ONCE with the same code). The code was proven first, so the 409
    // is no oracle to anyone who does not hold the phone.
    let user = await tx.findUserByPhoneHmac(hmac);
    let account: "existing" | "created" = "existing";
    if (!user && purpose === "device_activation") {
      // The SIGN-IN door with a number that has no books (ADR 2026-10-05c §2 🔒, desk 129 for this
      // path): the code is proven, but a sign-up happens only when the person chooses *Set up new
      // books* (S0.2e) — so nobody is signed up here and the proposal is recorded nowhere. The code
      // is spent; what carries forward is a single-use sign-up ticket that /signup/adopt accepts
      // without a second code. It names no user, is bound to the phone's HMAC, and the number
      // itself travels sealed inside it (phone.ts: nothing recoverable is kept for a person who has
      // not signed up, ADR 2026-09-05c §4 🔒).
      await tx.consumeOtpChallenge(c.id);
      const sealed = await sealSignupTicket(deps.phoneKek, phone, language);
      await tx.createActivationTicket({
        ticket_hash: await blake2b256(sealed),
        phone_hmac: hmac,
        purpose,
        user_id: null,
        created_at: now,
        expires_at: new Date(now.getTime() + SIGNUP_TICKET_TTL_S * 1000),
        consumed_at: null,
      });
      return { status: 200 as const, account: "none" as const, signup_ticket: b64url.enc(sealed) };
    }
    if (!user) {
      // ⚠️ SPEC: desk 129 remainder (ADR 2026-10-05c § Open, owner-open) — whether a verified code
      // for an unknown number on `phone_change` or `account_deletion` should sign it up is not
      // ruled. Unchanged until it is: those purposes, and `signup` itself, sign up here.
      try {
        user = await tx.signupUser(
          hmac,
          await encryptPhone(deps.phoneKek, phone),
          language,
          proposed ?? null,
        );
      } catch (e) {
        if (e instanceof UserIdTakenError) return { status: 409 as const };
        throw e;
      }
      account = "created";
    }
    await tx.consumeOtpChallenge(c.id);
    return {
      status: 200 as const,
      account,
      ...await issueActivationTicket(tx, now, hmac, purpose, user),
    };
  });
  if (out.status === 409) return error(409, "user_id_taken");
  if (out.status !== 200) {
    return json(400, {
      error: "otp_invalid",
      ...(out.attempts_left !== undefined ? { attempts_left: out.attempts_left } : {}),
    });
  }
  if (out.account === "none") {
    return json(200, {
      account: "none",
      signup_ticket: out.signup_ticket,
      expires_in_s: SIGNUP_TICKET_TTL_S,
    });
  }
  return json(200, {
    ticket: out.ticket,
    user_id: out.user_id,
    account: out.account,
    expires_in_s: TICKET_TTL_S,
  });
}

/** The activation ticket /devices consumes once (06 §2–§3), naming `user`. */
async function issueActivationTicket(
  tx: Tx,
  now: Date,
  hmac: Uint8Array,
  purpose: string,
  user: string,
): Promise<{ ticket: string; user_id: string }> {
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
  return { ticket: b64url.enc(ticket), user_id: user };
}

// ---------------------------------------------------------------- sign-up by choice (ADR 2026-10-05c §2)
async function adoptSignup(deps: Deps, b: Record<string, unknown>): Promise<Response> {
  // The client-minted id (ADR 2026-10-04b §1 🔒) is required here — no client predates this route —
  // and checked BEFORE the ticket is read, so a malformed id never touches the ticket.
  if (!isUuid(b.user_id)) return error(400, "bad_request");
  const proposed = b.user_id;
  const invalid = () => error(400, "signup_ticket_invalid");
  // Every ticket problem is the same answer (no oracle): a size no sealed ticket has is refused
  // before any lookup; anything else is decided on the stored row.
  const raw = b64any(b.signup_ticket);
  if (!raw || raw.length < SIGNUP_TICKET_MIN_BYTES || raw.length > SIGNUP_TICKET_MAX_BYTES) {
    return invalid();
  }
  const now = deps.now();
  const hash = await blake2b256(raw);

  const out = await deps.store.withClaims(null, async (tx) => {
    // Held to commit: a second adopt of this ticket decides on what the first committed.
    const t = await tx.lockSignupTicket(hash, now);
    if (!t) return { status: 400 as const };
    // Bound to the phone by HMAC: the number sealed in the ticket must be the one whose code was
    // verified. Lookup by the hash of the whole ticket already ties the two; this is the check that
    // no row and no ticket can be steered at another number.
    const sealed = await openSignupTicket(deps.phoneKek, raw);
    if (
      !sealed ||
      !(await constantTimeEqual(await phoneHmac(deps.phoneHmacKey, sealed.phone), t.phone_hmac))
    ) return { status: 400 as const };
    // The same per-phone serialisation as /otp/verify: a verify and an adopt for one number never
    // both decide "no account" and both sign up.
    await tx.lockPhoneForVerify(t.phone_hmac);
    if (await tx.findUserByPhoneHmac(t.phone_hmac)) {
      // The number gained books since the code. Fail CLOSED — never `existing` on a ticket that was
      // issued for a sign-up — and spend the ticket, which can never succeed now; the client
      // restarts at the code, whose verify answers `existing` (S0.2a / S0.2b).
      await tx.consumeSignupTicket(t.id, now);
      return { status: 400 as const };
    }
    let user: string;
    try {
      user = await tx.signupUser(
        t.phone_hmac,
        await encryptPhone(deps.phoneKek, sealed.phone),
        sealed.language,
        proposed,
      );
    } catch (e) {
      // As verify (ADR 2026-10-04b §2): nothing written, the ticket NOT spent, so the client
      // re-mints and retries once with the same ticket.
      if (e instanceof UserIdTakenError) return { status: 409 as const };
      throw e;
    }
    await tx.consumeSignupTicket(t.id, now);
    return {
      status: 200 as const,
      ...await issueActivationTicket(tx, now, t.phone_hmac, "signup", user),
    };
  });
  if (out.status === 409) return error(409, "user_id_taken");
  if (out.status !== 200) return invalid();
  return json(200, {
    ticket: out.ticket,
    user_id: out.user_id,
    account: "created",
    expires_in_s: TICKET_TTL_S,
  });
}

// ---------------------------------------------------------------- devices (06 §3)
async function registerDevice(deps: Deps, b: Record<string, unknown>): Promise<Response> {
  const ticket = b64any(b.ticket), pubEd = b64any(b.pub_ed), pubX = b64any(b.pub_x);
  // ADR 2026-09-16 §2 🔒: the ledger minted this id at first run; we record it, we never issue one.
  // The shape check is BEFORE the ticket is consumed — a typo must not cost the user their ticket.
  if (!isUuid(b.device_id)) return error(400, "bad_request");
  const device = b.device_id;
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
        device_id: await tx.registerDevice(device, t.user_id, pubEd, pubX, model, os, attestation),
      };
    } catch (e) {
      // Both are 409; the client branches on the `error` string, never the status (ADR §3).
      if (e instanceof DeviceCapError) {
        return { status: 409 as const, error: "device_cap" as const };
      }
      if (e instanceof DeviceIdTakenError) {
        return { status: 409 as const, error: "device_id_taken" as const };
      }
      throw e;
    }
  });
  if (reg.status === 401) return error(401, "ticket_invalid");
  if (reg.status === 409) return error(409, reg.error);

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
  const offeredEd = b64any(b.umk_pub_ed);
  const offeredX = b64any(b.umk_pub_x);
  if (!sig || sig.length !== 64 || issuedAt === null) return "cert_malformed";
  // Nothing may accept an x half that is not 32 bytes (04 §3.1): a short or long value would be
  // stored, relayed, and then compared byte-for-byte against a real scanned key (04 §6.3) — a
  // guaranteed hard-fail for the user with no way to correct it. Refuse it at the door. 0012's
  // CHECK and rf.set_umk_pubs refuse it again; this is the named wire refusal.
  if (b.umk_pub_x !== undefined && (!offeredX || offeredX.length !== 32)) {
    return "umk_pub_malformed";
  }
  if (b.umk_pub_ed !== undefined && (!offeredEd || offeredEd.length !== 32)) {
    return "umk_pub_malformed";
  }
  return await deps.store.withClaims(c, async (tx) => {
    let stored;
    try {
      stored = await tx.umkPubs(c.user_id, version);
    } catch (e) {
      if (e instanceof StoreDenied) return e.reason; // rf.umk_pubs_for is bounded to the caller
      throw e;
    }
    let umk = stored?.pub_ed;
    if (!umk) {
      if (!offeredEd) return "umk_unknown";
      umk = offeredEd; // first device: the UMK public key it registers is the one it self-certifies under
    }
    // The ED half keeps its pre-0012 answer on purpose: an offered key that differs from the
    // stored one is IGNORED and the certificate is then verified under the stored key, so the swap
    // fails as `cert_invalid` — what E-06-7 asserts, and the better refusal, because it says
    // nothing about what the server holds. The X half has no such history and gets a named
    // refusal: it is write-once (0012), and an honest client holding different bytes has a real
    // integrity problem it should be told about rather than have quietly dropped (05c).
    if (offeredX && stored?.pub_x && !bytesEqual(offeredX, stored.pub_x)) {
      return "umk_pub_conflict";
    }
    const msg = concat([uuid16(c.device_id), pubEd, pubX, i64be(issuedAt)]);
    if (!(await ed25519Verify(msg, sig, umk))) return "cert_invalid";
    try {
      // A row holding no x half — a pre-0012 row, or any row written by a client that did not
      // offer one, which today is all of them — is filled exactly once by the first offer. Nothing
      // is written when the caller offers neither half: the certificate alone certifies the device.
      if (offeredEd || (offeredX && !stored?.pub_x)) {
        await tx.setUmkPubs(c.user_id, version, umk, offeredX ?? stored?.pub_x ?? null);
      }
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
