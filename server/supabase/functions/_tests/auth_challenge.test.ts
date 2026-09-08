// auth-challenge (06 §2–§4 🔒; ADR 2026-09-05d §2). Ids E-06-1 … E-06-8.
import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { verifyAccessToken } from "../_shared/claims.ts";
import { handler as auth, NONCE_TTL_S, OTP_MAX_ATTEMPTS, SKEW_S } from "../auth-challenge/index.ts";
import { handler as meta } from "../sync-meta/index.ts";
import {
  advance,
  body,
  certBytes,
  challengeBytes,
  edKeypair,
  get,
  member,
  post,
  random,
  type Rig,
  rig,
  sign,
} from "./harness.ts";

const PHONE = "+919876543210";
const call = (r: Rig, path: string, b: unknown, token?: string) =>
  auth(post(`/auth-challenge${path}`, b, { token }), r.deps);

async function otpTicket(r: Rig, phone = PHONE, purpose = "signup") {
  await call(r, "/otp/request", { phone, purpose });
  const code = r.otp.sent.at(-1)!.code;
  return await body(await call(r, "/otp/verify", { phone, purpose, code }));
}
async function registered(r: Rig, opts: { umk?: boolean } = {}) {
  const t = await otpTicket(r);
  const dev = await edKeypair(), xpub = await random(32), umk = await edKeypair();
  const req: Record<string, unknown> = {
    ticket: t.ticket,
    pub_ed: b64url.enc(dev.pub),
    pub_x: b64url.enc(xpub),
    model: "Pixel 8a",
    os: "Android 15",
  };
  const res = await body(await call(r, "/devices", req));
  if (opts.umk) {
    // cert is over the device id the server just issued, so self-certification is a second call
    const tok = await session(r, res.device_id, dev.priv);
    const issued = r.clock.now.getTime();
    const sig = await sign(certBytes(res.device_id, dev.pub, xpub, issued), umk.priv);
    const c = await body(
      await call(r, "/devices/certify", {
        umk_pub_ed: b64url.enc(umk.pub),
        umk_key_version: 1,
        cert: { signature: b64url.enc(sig), issued_at_ms: issued },
      }, tok.access_token),
    );
    assertEquals(c.status, "certified");
  }
  return { ...res, dev, xpub, umk, user_id: t.user_id as string };
}
async function session(r: Rig, deviceId: string, priv: Uint8Array) {
  const ch = await body(await call(r, "/challenge", { device_id: deviceId }));
  const nonce = b64url.dec(ch.nonce);
  const ts = Math.floor(r.clock.now.getTime() / 1000);
  const signature = b64url.enc(await sign(challengeBytes(nonce, deviceId, ts), priv));
  return await body(
    await call(r, "/token", { device_id: deviceId, nonce: ch.nonce, unix_ts: ts, signature }),
  );
}

Deno.test("E-06-1 otp/request: generic answers (no registration oracle), WhatsApp→SMS failover, per-number 5/h 10/day, resend backoff", async (t) => {
  const r = rig();
  await t.step(
    "unknown and known numbers answer identically; the code never appears in the response",
    async () => {
      const a = await call(r, "/otp/request", { phone: PHONE, purpose: "signup" });
      assertEquals(a.status, 200);
      const text = await a.text();
      assertEquals(JSON.parse(text).ok, true);
      assert(!text.includes(r.otp.sent[0].code));
      assert(!text.includes(PHONE));
      assertEquals(r.otp.sent[0].channel, "whatsapp");
      assertEquals(r.db.otp_challenges[0].code_hash.length, 32, "hash stored, never the code");
      assertEquals(r.db.otp_challenges[0].phone_hmac.length, 32, "phone only as HMAC");
    },
  );
  await t.step("resend inside the 30 s backoff → 429 with resend_after_s", async () => {
    const res = await call(r, "/otp/request", { phone: PHONE, purpose: "signup" });
    assertEquals(res.status, 429);
    assert((await body(res)).resend_after_s > 0);
  });
  await t.step(
    "failover to SMS when WhatsApp fails; nothing stored when every channel fails",
    async () => {
      advance(r, 31_000);
      r.otp.failWhatsapp = true;
      await call(r, "/otp/request", { phone: PHONE, purpose: "signup" });
      assertEquals(r.otp.sent.at(-1)!.channel, "sms");
      advance(r, 61_000);
      r.otp.failAll = true;
      const n = r.db.otp_challenges.length;
      const res = await call(r, "/otp/request", { phone: PHONE, purpose: "signup" });
      assertEquals(res.status, 200, "still generic");
      assertEquals(r.db.otp_challenges.length, n);
      r.otp.failAll = false;
      r.otp.failWhatsapp = false;
    },
  );
  await t.step("5 per hour per number, then 429; 10 per day", async () => {
    const r2 = rig();
    for (let i = 0; i < 5; i++) {
      assertEquals(
        (await call(r2, "/otp/request", { phone: PHONE, purpose: "signup" })).status,
        200,
        `send ${i}`,
      );
      advance(r2, 6 * 60_000);
    }
    assertEquals((await call(r2, "/otp/request", { phone: PHONE, purpose: "signup" })).status, 429);
    advance(r2, 60 * 60_000);
    for (let i = 0; i < 5; i++) {
      assertEquals(
        (await call(r2, "/otp/request", { phone: PHONE, purpose: "signup" })).status,
        200,
        `send ${5 + i}`,
      );
      advance(r2, 6 * 60_000);
    }
    advance(r2, 60 * 60_000);
    assertEquals(
      (await call(r2, "/otp/request", { phone: PHONE, purpose: "signup" })).status,
      429,
      "10/day",
    );
  });
  await t.step("bad input", async () => {
    assertEquals(
      (await call(r, "/otp/request", { phone: "98765", purpose: "signup" })).status,
      400,
    );
    assertEquals(
      (await call(r, "/otp/request", { phone: PHONE, purpose: "login" })).status,
      400,
      "OTP never fires at routine login (06 §2)",
    );
  });
});

Deno.test("E-06-2 otp/verify: 3 attempts then a new code; 5-min expiry; ticket single-use; user created with phone_ct + phone_hmac only", async () => {
  const r = rig();
  await call(r, "/otp/request", { phone: PHONE, purpose: "signup" });
  const code = r.otp.sent[0].code;
  const wrong = code === "000000" ? "111111" : "000000";
  for (let i = 1; i <= OTP_MAX_ATTEMPTS; i++) {
    const res = await body(
      await call(r, "/otp/verify", { phone: PHONE, purpose: "signup", code: wrong }),
    );
    assertEquals(res.error, "otp_invalid");
    assertEquals(res.attempts_left, OTP_MAX_ATTEMPTS - i);
  }
  const spent = await body(await call(r, "/otp/verify", { phone: PHONE, purpose: "signup", code }));
  assertEquals(spent.error, "otp_invalid", "right code after 3 wrong ones needs a new code");
  advance(r, 31_000);
  await call(r, "/otp/request", { phone: PHONE, purpose: "signup" });
  advance(r, 5 * 60_000 + 1000);
  assertEquals(
    (await call(r, "/otp/verify", {
      phone: PHONE,
      purpose: "signup",
      code: r.otp.sent.at(-1)!.code,
    })).status,
    400,
    "expired",
  );
  advance(r, 60_000);
  await call(r, "/otp/request", { phone: PHONE, purpose: "signup" });
  const ok = await body(
    await call(r, "/otp/verify", {
      phone: PHONE,
      purpose: "signup",
      code: r.otp.sent.at(-1)!.code,
    }),
  );
  assertEquals(typeof ok.ticket, "string");
  assertEquals(r.db.users.size, 1);
  const u = [...r.db.users.values()][0];
  assertEquals(u.id, ok.user_id);
  assert(u.phone_ct && u.phone_ct.length > 24 && u.phone_hmac?.length === 32);
  assert(!new TextDecoder().decode(u.phone_ct).includes("9876543210"), "phone_ct is ciphertext");
  // same phone again → same user (activation), not a second row (after the 5-min resend backoff)
  advance(r, 5 * 60_000 + 1000);
  const again = await otpTicket(r);
  assertEquals(again.user_id, ok.user_id);
  assertEquals(r.db.users.size, 1);
  // a ticket is consumable exactly once
  const dev = await edKeypair();
  const reg = {
    ticket: ok.ticket,
    pub_ed: b64url.enc(dev.pub),
    pub_x: b64url.enc(await random(32)),
  };
  assertEquals((await call(r, "/devices", reg)).status, 200);
  assertEquals((await call(r, "/devices", reg)).status, 401);
});

Deno.test("E-06-3 devices: registration stores keys + metadata as `registered`; cap 5 on Free → 409 device_cap", async () => {
  const r = rig();
  const first = await registered(r);
  assertEquals(first.status, "registered");
  const d = r.db.devices.get(first.device_id)!;
  assertEquals(d.model, "Pixel 8a");
  assertEquals(d.status, "registered");
  for (let i = 0; i < 4; i++) {
    advance(r, 61 * 60_000); // the OTP per-number cap (5/h) is a different limit from the device cap
    await registered(r);
  }
  advance(r, 61 * 60_000);
  const t = await otpTicket(r);
  const res = await call(r, "/devices", {
    ticket: t.ticket,
    pub_ed: b64url.enc((await edKeypair()).pub),
    pub_x: b64url.enc(await random(32)),
  });
  assertEquals(res.status, 409);
  assertEquals((await body(res)).error, "device_cap");
  assertEquals([...r.db.devices.values()].filter((x) => x.user_id === first.user_id).length, 5);
});

Deno.test("E-06-4 sessions: nonce single-use + 60 s TTL, ±90 s skew, signature under the registered key, JWT {user_id, device_id} 15 min", async (t) => {
  const r = rig();
  const dev = await registered(r);
  await t.step("happy path", async () => {
    const s = await session(r, dev.device_id, dev.dev.priv);
    assertEquals(s.expires_in, 900);
    const claims = await verifyAccessToken(
      r.deps.jwtKey,
      s.access_token,
      Math.floor(r.clock.now.getTime() / 1000),
    );
    assertEquals(claims, { user_id: dev.user_id, device_id: dev.device_id });
    assertEquals(s.device_status, "registered");
    assertEquals(b64url.dec(s.refresh_token).length, 32);
  });
  await t.step("nonce cannot be replayed", async () => {
    const ch = await body(await call(r, "/challenge", { device_id: dev.device_id }));
    const ts = Math.floor(r.clock.now.getTime() / 1000);
    const sig = b64url.enc(
      await sign(challengeBytes(b64url.dec(ch.nonce), dev.device_id, ts), dev.dev.priv),
    );
    assertEquals(
      (await call(r, "/token", {
        device_id: dev.device_id,
        nonce: ch.nonce,
        unix_ts: ts,
        signature: sig,
      })).status,
      200,
    );
    assertEquals(
      (await call(r, "/token", {
        device_id: dev.device_id,
        nonce: ch.nonce,
        unix_ts: ts,
        signature: sig,
      })).status,
      401,
    );
  });
  await t.step("nonce expires after 60 s; unix_ts outside ±90 s refused", async () => {
    const ch = await body(await call(r, "/challenge", { device_id: dev.device_id }));
    advance(r, (NONCE_TTL_S + 1) * 1000);
    const ts = Math.floor(r.clock.now.getTime() / 1000);
    const sig = b64url.enc(
      await sign(challengeBytes(b64url.dec(ch.nonce), dev.device_id, ts), dev.dev.priv),
    );
    assertEquals(
      (await call(r, "/token", {
        device_id: dev.device_id,
        nonce: ch.nonce,
        unix_ts: ts,
        signature: sig,
      })).status,
      401,
    );
    const ch2 = await body(await call(r, "/challenge", { device_id: dev.device_id }));
    const skewed = Math.floor(r.clock.now.getTime() / 1000) - SKEW_S - 5;
    const sig2 = b64url.enc(
      await sign(challengeBytes(b64url.dec(ch2.nonce), dev.device_id, skewed), dev.dev.priv),
    );
    assertEquals(
      (await call(r, "/token", {
        device_id: dev.device_id,
        nonce: ch2.nonce,
        unix_ts: skewed,
        signature: sig2,
      })).status,
      401,
    );
  });
  await t.step("wrong key, wrong device, revoked device", async () => {
    const other = await edKeypair();
    const ch = await body(await call(r, "/challenge", { device_id: dev.device_id }));
    const ts = Math.floor(r.clock.now.getTime() / 1000);
    const bad = b64url.enc(
      await sign(challengeBytes(b64url.dec(ch.nonce), dev.device_id, ts), other.priv),
    );
    assertEquals(
      (await call(r, "/token", {
        device_id: dev.device_id,
        nonce: ch.nonce,
        unix_ts: ts,
        signature: bad,
      })).status,
      401,
    );
    const unknown = await call(r, "/challenge", { device_id: crypto.randomUUID() });
    assertEquals(unknown.status, 200, "unknown device gets a nonce-shaped answer, no oracle");
    r.db.devices.get(dev.device_id)!.status = "revoked";
    const s = await call(r, "/challenge", { device_id: dev.device_id });
    const ch3 = await body(s);
    const sig3 = b64url.enc(
      await sign(challengeBytes(b64url.dec(ch3.nonce), dev.device_id, ts), dev.dev.priv),
    );
    assertEquals(
      (await call(r, "/token", {
        device_id: dev.device_id,
        nonce: ch3.nonce,
        unix_ts: ts,
        signature: sig3,
      })).status,
      401,
    );
  });
});

Deno.test("E-06-5 refresh: rotation needs a fresh signature; reuse of a rotated token revokes the family; 30-day idle cap", async () => {
  const r = rig();
  const dev = await registered(r);
  const s1 = await session(r, dev.device_id, dev.dev.priv);
  const refreshWith = async (refresh_token: string) => {
    const ch = await body(await call(r, "/challenge", { device_id: dev.device_id }));
    const ts = Math.floor(r.clock.now.getTime() / 1000);
    const signature = b64url.enc(
      await sign(challengeBytes(b64url.dec(ch.nonce), dev.device_id, ts), dev.dev.priv),
    );
    return await call(r, "/refresh", {
      device_id: dev.device_id,
      refresh_token,
      nonce: ch.nonce,
      unix_ts: ts,
      signature,
    });
  };
  const s2 = await body(await refreshWith(s1.refresh_token));
  assertNotEquals(s2.refresh_token, s1.refresh_token);
  assertEquals(r.db.refresh_tokens.length, 2);
  assertEquals(r.db.refresh_tokens[0].family_id, r.db.refresh_tokens[1].family_id);
  // reuse of the rotated token: theft signal → whole family dead, including the fresh one
  const reuse = await refreshWith(s1.refresh_token);
  assertEquals(reuse.status, 401);
  assertEquals((await body(reuse)).error, "refresh_reused");
  assertEquals((await refreshWith(s2.refresh_token)).status, 401);
  assert(r.db.refresh_tokens.every((t) => t.revoked_at));
  // a refresh without a valid signature never rotates
  const s3 = await session(r, dev.device_id, dev.dev.priv);
  const bad = await call(r, "/refresh", {
    device_id: dev.device_id,
    refresh_token: s3.refresh_token,
    nonce: b64url.enc(await random(32)),
    unix_ts: 1,
    signature: b64url.enc(new Uint8Array(64)),
  });
  assertEquals(bad.status, 401);
  advance(r, 31 * 86400e3);
  assertEquals((await refreshWith(s3.refresh_token)).status, 401, "idle cap");
});

Deno.test("E-06-6 min-version and OTP-only visibility: 426 on the auth group; a registered-but-uncertified device authenticates yet sees no tenant metadata", async () => {
  const r = rig();
  const dev = await registered(r);
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  r.db.addMembership(tenant, dev.user_id);
  r.db.addRole(book, dev.user_id, "admin");
  const peer = await member(r, tenant, book, "member");
  const s = await session(r, dev.device_id, dev.dev.priv);
  const m = await body(await meta(get("/sync-meta", { token: s.access_token }), r.deps));
  assertEquals(m.memberships, [], "own membership row hidden until certified (ADR 05d §2)");
  assertEquals(m.book_roles, []);
  assertEquals(
    m.devices.map((d: any) => d.id),
    [dev.device_id],
    `peer ${peer.device.id} invisible`,
  );
  assertEquals(m.verification_events, []);
  r.db.config.set("min_client_version.auth", "9.0.0");
  const gated = await call(r, "/challenge", { device_id: dev.device_id });
  assertEquals(gated.status, 426);
  assertEquals((await body(gated)).min_client_version, "9.0.0");
});

Deno.test("E-06-7 certify: a cert verified under the user's UMK flips status to certified; a bad cert changes nothing; UMK cannot be swapped", async () => {
  const r = rig();
  const dev = await registered(r, { umk: true });
  assertEquals(r.db.devices.get(dev.device_id)!.status, "certified");
  assertEquals(r.db.umk_public_keys.length, 1);
  assertEquals(r.db.device_certs[0].device_id, dev.device_id);
  // second device of the same user, certified by a cert under the SAME UMK; an attacker's UMK is refused
  advance(r, 60_000);
  const second = await registered(r);
  const tok = await session(r, second.device_id, second.dev.priv);
  const issued = r.clock.now.getTime();
  const attacker = await edKeypair();
  const badSig = await sign(
    certBytes(second.device_id, second.dev.pub, second.xpub, issued),
    attacker.priv,
  );
  const bad = await call(r, "/devices/certify", {
    umk_pub_ed: b64url.enc(attacker.pub),
    cert: { signature: b64url.enc(badSig), issued_at_ms: issued },
  }, tok.access_token);
  assertEquals(bad.status, 400);
  assertEquals((await body(bad)).error, "cert_invalid");
  assertEquals(r.db.devices.get(second.device_id)!.status, "registered");
  assertEquals(r.db.umk_public_keys.length, 1, "the registered UMK is the only one");
  const goodSig = await sign(
    certBytes(second.device_id, second.dev.pub, second.xpub, issued),
    dev.umk.priv,
  );
  const good = await call(r, "/devices/certify", {
    cert: { signature: b64url.enc(goodSig), issued_at_ms: issued, issued_by_device: dev.device_id },
  }, tok.access_token);
  assertEquals(good.status, 200);
  assertEquals(r.db.devices.get(second.device_id)!.status, "certified");
  assertEquals(
    r.db.device_certs.find((c) => c.device_id === second.device_id)!.issued_by_device,
    dev.device_id,
  );
});

Deno.test("E-06-8 rule 4: no request body, phone or code ever reaches console output", async () => {
  const r = rig();
  const lines: string[] = [];
  const orig = {
    log: console.log,
    error: console.error,
    warn: console.warn,
    info: console.info,
    debug: console.debug,
  };
  for (const k of Object.keys(orig) as (keyof typeof orig)[]) {
    (console as any)[k] = (...a: unknown[]) => lines.push(a.map(String).join(" "));
  }
  try {
    await registered(r, { umk: true });
    await call(r, "/otp/verify", { phone: PHONE, purpose: "signup", code: "123456" });
    await call(r, "/devices", { ticket: "zz", pub_ed: "x" });
    await call(r, "/token", { device_id: "nope" });
  } finally {
    Object.assign(console, orig);
  }
  const joined = lines.join("\n");
  assertEquals(joined.includes("9876543210"), false);
  for (const s of r.otp.sent) assertEquals(joined.includes(s.code), false);
  assertStringIncludes("", ""); // keep assert import shape stable
});
