// auth-challenge (06 §2–§4 🔒; ADR 2026-09-05d §2, ADR 2026-09-16 §2). Ids E-06-1 … E-06-8,
// E-06-40, E-06-41, E-06-68.
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
async function registered(r: Rig, opts: { umk?: boolean; deviceId?: string } = {}) {
  const t = await otpTicket(r);
  const dev = await edKeypair(), xpub = await random(32), umk = await edKeypair();
  // The ledger minted this id at first run (ADR 2026-09-16 §1); registration carries it.
  const deviceId = opts.deviceId ?? crypto.randomUUID();
  const req: Record<string, unknown> = {
    device_id: deviceId,
    ticket: t.ticket,
    pub_ed: b64url.enc(dev.pub),
    pub_x: b64url.enc(xpub),
    model: "Pixel 8a",
    os: "Android 15",
  };
  const res = await body(await call(r, "/devices", req));
  if (opts.umk) {
    // cert is over the device's own id, which the server echoed; self-certification is a second call
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
    device_id: crypto.randomUUID(),
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
    device_id: crypto.randomUUID(),
    ticket: t.ticket,
    pub_ed: b64url.enc((await edKeypair()).pub),
    pub_x: b64url.enc(await random(32)),
  });
  assertEquals(res.status, 409);
  assertEquals((await body(res)).error, "device_cap");
  assertEquals([...r.db.devices.values()].filter((x) => x.user_id === first.user_id).length, 5);
});

// ADR 2026-09-16 §2, §6 🔒 — one device, one id: the ledger mints it, the server records it.
Deno.test("E-06-40 devices: the client's device_id is recorded and echoed; missing or non-uuid → 400 bad_request before the ticket is consumed", async () => {
  const r = rig();
  const t = await otpTicket(r);
  const dev = await edKeypair(), xpub = await random(32);
  const base = {
    ticket: t.ticket,
    pub_ed: b64url.enc(dev.pub),
    pub_x: b64url.enc(xpub),
    model: "Pixel 8a",
    os: "Android 15",
  };
  const id = crypto.randomUUID();
  // absent, empty, unhyphenated, uppercase, not a string, not a scalar: all bad_request.
  for (
    const bad of [
      undefined,
      null,
      "",
      "not-a-uuid",
      id.replaceAll("-", ""),
      id.toUpperCase(),
      42,
      {},
    ]
  ) {
    const req: Record<string, unknown> = { ...base };
    if (bad !== undefined) req.device_id = bad;
    const res = await call(r, "/devices", req);
    assertEquals(res.status, 400, `device_id ${JSON.stringify(bad)}`);
    assertEquals((await body(res)).error, "bad_request");
    assertEquals(r.db.devices.size, 0, "a malformed id writes nothing");
  }
  // Every refusal above happened BEFORE the ticket was consumed: a typo must not cost the ticket.
  const ok = await body(await call(r, "/devices", { ...base, device_id: id }));
  assertEquals(ok.device_id, id, "the id the client minted is the id the server echoes");
  assertEquals(ok.user_id, t.user_id);
  assertEquals([...r.db.devices.keys()], [id], "the row carries the client's id, not a minted one");
  const row = r.db.devices.get(id)!;
  assertEquals(row.user_id, ok.user_id);
  assertEquals(row.status, "registered");
  assertEquals(row.model, "Pixel 8a");
});

Deno.test("E-06-41 devices: an id held by another user or under other keys → 409 device_id_taken; the same user with the same keys is idempotent and is not charged the cap", async (t) => {
  const r = rig();
  const first = await registered(r);
  const id = first.device_id as string;
  const mine = {
    device_id: id,
    pub_ed: b64url.enc(first.dev.pub),
    pub_x: b64url.enc(first.xpub),
    model: "Pixel 8a",
    os: "Android 15",
  };

  await t.step(
    "another user claiming the id: 409 device_id_taken, no row, ticket consumed",
    async () => {
      advance(r, 61 * 60_000);
      const other = await otpTicket(r, "+919876500001");
      const req = {
        device_id: id,
        ticket: other.ticket,
        pub_ed: b64url.enc((await edKeypair()).pub),
        pub_x: b64url.enc(await random(32)),
      };
      const res = await call(r, "/devices", req);
      assertEquals(res.status, 409);
      // device_cap and device_id_taken share the status; the client branches on the string (§3).
      assertEquals((await body(res)).error, "device_id_taken");
      assertEquals(r.db.devices.size, 1);
      assertEquals(
        r.db.devices.get(id)!.user_id,
        first.user_id,
        "the id still belongs to its owner",
      );
      // The ticket WAS consumed: the refusal is a refusal, not a free retry.
      assertEquals((await call(r, "/devices", req)).status, 401);
    },
  );

  await t.step("the same user under a different key pair: still taken", async () => {
    advance(r, 61 * 60_000);
    const t2 = await otpTicket(r);
    const res = await call(r, "/devices", {
      device_id: id,
      ticket: t2.ticket,
      pub_ed: b64url.enc((await edKeypair()).pub),
      pub_x: b64url.enc(await random(32)),
    });
    assertEquals(res.status, 409);
    assertEquals((await body(res)).error, "device_id_taken");
    assertEquals(r.db.devices.size, 1);
  });

  await t.step("the same user with the same keys: 200, the same row, no second row", async () => {
    advance(r, 61 * 60_000);
    const t3 = await otpTicket(r);
    const before = r.db.devices.get(id)!;
    const res = await body(await call(r, "/devices", { ...mine, ticket: t3.ticket }));
    assertEquals(res.device_id, id);
    assertEquals(res.user_id, first.user_id);
    assertEquals(res.status, "registered");
    assertEquals(r.db.devices.size, 1, "reinstall on one phone is one device (06 §5)");
    assertEquals(r.db.devices.get(id), before, "the row is returned, not rewritten");
  });

  await t.step("re-registration is not charged against the device cap", async () => {
    for (let i = 0; i < 4; i++) {
      advance(r, 61 * 60_000);
      await registered(r); // the Free cap of 5 is now full
    }
    assertEquals([...r.db.devices.values()].filter((d) => d.user_id === first.user_id).length, 5);
    advance(r, 61 * 60_000);
    const t5 = await otpTicket(r);
    const res = await call(r, "/devices", { ...mine, ticket: t5.ticket });
    assertEquals(res.status, 200, "an id the user already holds needs no cap headroom");
    assertEquals((await body(res)).device_id, id);
    assertEquals(r.db.devices.size, 5);
  });
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

Deno.test("E-06-68 both UMK public halves: /devices/certify records umk_pub_ed AND umk_pub_x and the meta channel relays both (04 §6.1/§6.3 🔒, migration 0012); a wrong-length x half is refused umk_pub_malformed with nothing stored; a second, different x half is umk_pub_conflict and moves no byte; a row with no x half (today: every row — no client sends umk_pub_x) still relays with pub_x null", async () => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);

  // 04 §6.3 🔒 compares the scanned public KEYS byte-for-byte against the server-relayed keys, and
  // core_crypto's verifyQr (ceremony.dart:490-492) compares BOTH halves of an UmkPublic that
  // cannot exist without both (keys.dart:57-65). The x half is its own seed (keys.dart:13), so the
  // server cannot derive it — it has to be carried, which is what this test is about.
  const dev = await registered(r);
  const umkX = await random(32);
  const tok = await session(r, dev.device_id, dev.dev.priv);
  const issued = r.clock.now.getTime();
  const sig = await sign(certBytes(dev.device_id, dev.dev.pub, dev.xpub, issued), dev.umk.priv);
  const certBody = (over: Record<string, unknown> = {}) => ({
    umk_pub_ed: b64url.enc(dev.umk.pub),
    umk_pub_x: b64url.enc(umkX),
    umk_key_version: 1,
    cert: { signature: b64url.enc(sig), issued_at_ms: issued },
    ...over,
  });

  // ---- nothing may accept an x half that is not 32 bytes: it would be stored, relayed, and then
  // compared byte-for-byte against a real scanned key — a hard-fail the user cannot correct.
  for (const n of [31, 33, 0, 64]) {
    const bad = await call(
      r,
      "/devices/certify",
      certBody({ umk_pub_x: b64url.enc(await random(n)) }),
      tok.access_token,
    );
    assertEquals(bad.status, 400);
    assertEquals((await body(bad)).error, "umk_pub_malformed", `${n} bytes is refused`);
  }
  assertEquals(r.db.umk_public_keys.length, 0, "a refused length stores nothing at all");
  assertEquals(r.db.devices.get(dev.device_id)!.status, "registered", "…and certifies nothing");

  // ---- the honest call: both halves land, and the device is certified under the ed half
  const ok = await call(r, "/devices/certify", certBody(), tok.access_token);
  assertEquals(ok.status, 200);
  assertEquals(r.db.devices.get(dev.device_id)!.status, "certified");
  assertEquals(r.db.umk_public_keys.length, 1);
  assertEquals(r.db.umk_public_keys[0].pub_ed, dev.umk.pub);
  assertEquals(r.db.umk_public_keys[0].pub_x, umkX, "the X25519 half is stored, not dropped");

  // ---- write-once: a DIFFERENT x half is a named refusal, and the stored bytes do not move.
  // A substituted x half is precisely the attack 04 §6.3 exists to stop, and the server is the
  // untrusted relay, so this is refused on the wire as well as by 0012's guard in the database.
  const swapped = await call(
    r,
    "/devices/certify",
    certBody({ umk_pub_x: b64url.enc(await random(32)) }),
    tok.access_token,
  );
  assertEquals(swapped.status, 400);
  assertEquals((await body(swapped)).error, "umk_pub_conflict");
  assertEquals(r.db.umk_public_keys[0].pub_x, umkX, "not one byte moved");
  // replaying exactly what is stored stays idempotent — every certify call re-offers its keys
  assertEquals((await call(r, "/devices/certify", certBody(), tok.access_token)).status, 200);
  assertEquals(r.db.umk_public_keys.length, 1);

  // ---- the relay: a fellow member of the tenant is handed BOTH halves, which is the only way
  // 04 §6.3's comparison can run at all.
  r.db.addMembership(tenant, dev.user_id);
  r.db.addRole(book, dev.user_id, "admin");
  const verifier = await member(r, tenant, book, "member");
  const relayed = await body(await meta(get("/sync-meta", { token: verifier.token }), r.deps));
  const mine = relayed.umk_public_keys.find((k: any) => k.user_id === dev.user_id);
  assert(mine, "the verifier is relayed the subject's UMK row");
  assertEquals(mine.pub_ed, b64url.enc(dev.umk.pub));
  assertEquals(mine.pub_x, b64url.enc(umkX), "both halves reach the verifier's device");

  // ---- a row written before migration 0012 has no x half. It still relays — `pub_x: null`, never
  // a substitute — and the device then hard-fails the ceremony (04 §6.3 "There is no override"),
  // which is the correct closed failure.
  const legacyEd = await random(32);
  r.db.umk_public_keys.push({
    user_id: verifier.user,
    key_version: 1,
    pub_ed: legacyEd,
    created_at: r.clock.now,
    superseded_at: null,
    updated_at: r.clock.now,
  });
  const again = await body(await meta(get("/sync-meta", { token: verifier.token }), r.deps));
  const legacy = again.umk_public_keys.find((k: any) => k.user_id === verifier.user);
  assertEquals(legacy.pub_ed, b64url.enc(legacyEd));
  assertEquals(legacy.pub_x, null, "no x half, and nothing invented in its place");
});
