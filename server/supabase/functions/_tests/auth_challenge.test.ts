// auth-challenge (06 §2–§4 🔒; ADR 2026-09-05d §2, ADR 2026-09-16 §2, ADR 2026-09-25 §1,
// ADR 2026-10-04b §1, §3). Ids E-06-1 … E-06-8, E-06-40, E-06-41, E-06-68, E-25-1, E-25-4 … E-25-9,
// E-04b-1 … E-04b-4.
import {
  assert,
  assertEquals,
  assertNotEquals,
  assertStringIncludes,
  assertThrows,
} from "@std/assert";
import { b64, b64url } from "../_shared/bytes.ts";
import { verifyAccessToken } from "../_shared/claims.ts";
import { type Deps, depsFromEnv, liveDeps, start } from "../_shared/deps.ts";
import { ENV } from "../_shared/env.ts";
import { FakeOtpProvider, Msg91Provider } from "../_shared/otp/provider.ts";
import { DEV_FIXED_OTP_CODE, OtpConfigError, selectOtpProvider } from "../_shared/otp/select.ts";
import { blake2b256 } from "../_shared/sodium.ts";
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
  T0,
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

Deno.test("E-06-1 otp/request: generic answers (no registration oracle), nothing stored on total failure, per-number 5/h 10/day, resend backoff", async (t) => {
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
      // E-25-1 (ADR 2026-09-25 §1): SMS is the one channel — the default request goes by SMS,
      // in exactly one attempt, and the challenge row says so.
      assertEquals(r.otp.attempts, 1);
      assertEquals(r.otp.sent[0].channel, "sms");
      assertEquals(r.db.otp_challenges[0].channel, "sms");
      assertEquals(r.db.otp_challenges[0].code_hash.length, 32, "hash stored, never the code");
      assertEquals(r.db.otp_challenges[0].phone_hmac.length, 32, "phone only as HMAC");
      // The oracle half (06 §2 "no 'number not registered' oracle"): a number with a user and a
      // certified device and a number never seen before get byte-identical answers, for every
      // purpose — including the three that only make sense for an existing account. Each side
      // runs in its own rig so `r`'s history (the steps below) is untouched. resend_after_s
      // follows the number's own last-hour requests, which an unknown number has too, so both
      // sides are taken past the hour: registration is then the only thing that differs.
      for (const purpose of ["signup", "device_activation", "phone_change", "account_deletion"]) {
        const known = rig(), unknown = rig();
        await registered(known, { umk: true });
        assertEquals(known.db.users.size, 1, "precondition: the number is registered");
        assertEquals(known.db.devices.size, 1, "precondition: it has a device");
        assertEquals(unknown.db.users.size, 0, "precondition: the number was never seen");
        advance(known, 61 * 60_000);
        advance(unknown, 61 * 60_000);
        const k = await call(known, "/otp/request", { phone: PHONE, purpose });
        const u = await call(unknown, "/otp/request", { phone: PHONE, purpose });
        assertEquals(k.status, 200, `known, ${purpose}`);
        assertEquals(u.status, k.status, `status, ${purpose}`);
        assertEquals(u.headers.get("content-type"), k.headers.get("content-type"), purpose);
        assertEquals(await u.text(), await k.text(), `body, ${purpose}`);
      }
    },
  );
  await t.step("resend inside the 30 s backoff → 429 with resend_after_s", async () => {
    const res = await call(r, "/otp/request", { phone: PHONE, purpose: "signup" });
    assertEquals(res.status, 429);
    assert((await body(res)).resend_after_s > 0);
  });
  await t.step(
    "nothing stored when the SMS fails — and no second attempt on another channel",
    async () => {
      // E-25-1 (ADR 2026-09-25 §1): there is no failover path. One failed SMS is one attempt, not
      // a retry by WhatsApp; the answer stays generic and nothing is stored (06 §2).
      advance(r, 31_000);
      r.otp.fail = true;
      const n = r.db.otp_challenges.length;
      const attempts = r.otp.attempts, sent = r.otp.sent.length;
      const res = await call(r, "/otp/request", { phone: PHONE, purpose: "signup" });
      assertEquals(res.status, 200, "still generic");
      assertEquals(r.db.otp_challenges.length, n);
      assertEquals(r.otp.attempts - attempts, 1, "one attempt, no failover");
      assertEquals(r.otp.sent.length, sent, "nothing went out");
      r.otp.fail = false;
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

Deno.test("E-25-1 otp/request: SMS is the one channel (ADR 2026-09-25 §1) — a request that asks for whatsapp still goes out by SMS in one attempt, a failed SMS is never retried on another channel, the answer never names a channel, and the live provider makes one SMS call and no WhatsApp call", async (t) => {
  const OTHER = "+919876543211";
  await t.step("asking for whatsapp: one SMS, the row records sms", async () => {
    const r = rig();
    const res = await call(r, "/otp/request", {
      phone: PHONE,
      purpose: "signup",
      channel: "whatsapp",
    });
    assertEquals(res.status, 200);
    assertEquals(r.otp.attempts, 1, "one send, no preference branch");
    assertEquals(r.otp.sent.length, 1);
    assertEquals(r.otp.sent[0].channel, "sms");
    assertEquals(r.otp.sent[0].e164, PHONE);
    assertEquals(r.db.otp_challenges.length, 1);
    assertEquals(r.db.otp_challenges[0].channel, "sms");
    // The body says nothing about the channel, so no screen can claim a WhatsApp→SMS fallback that
    // never happened; and it stays generic (06 §2).
    assertEquals(Object.keys(await body(res)).sort(), ["ok", "resend_after_s"]);
    // the SMS'd code verifies — the request did not just record "sms", it delivered by it
    const v = await body(
      await call(r, "/otp/verify", { phone: PHONE, purpose: "signup", code: r.otp.sent[0].code }),
    );
    assertEquals(typeof v.ticket, "string");
  });
  await t.step(
    "sms, a channel the server has never heard of, or none: SMS, never a 400",
    async () => {
      // The field is ignored, not refused: today's app build still sends `whatsapp` by default
      // (M6-OTP1's UI half), and refusing it would lock that build out of signup.
      for (const channel of ["sms", "telegram", 42, null, undefined]) {
        const r = rig();
        const res = await call(r, "/otp/request", { phone: OTHER, purpose: "signup", channel });
        assertEquals(res.status, 200, `channel ${String(channel)}`);
        assertEquals(r.otp.attempts, 1);
        assertEquals(r.otp.sent.map((s) => s.channel), ["sms"]);
        assertEquals(r.db.otp_challenges.map((c) => c.channel), ["sms"]);
      }
    },
  );
  await t.step(
    "asking for whatsapp while SMS fails: one attempt, nothing sent, nothing stored, generic 200",
    async () => {
      const r = rig();
      r.otp.fail = true;
      const res = await call(r, "/otp/request", {
        phone: PHONE,
        purpose: "signup",
        channel: "whatsapp",
      });
      assertEquals(res.status, 200);
      assertEquals(Object.keys(await body(res)).sort(), ["ok", "resend_after_s"]);
      assertEquals(r.otp.attempts, 1, "no failover path");
      assertEquals(r.otp.sent, []);
      assertEquals(r.db.otp_challenges, []);
    },
  );
  await t.step(
    "the live provider: one SMS POST per send — never a WhatsApp endpoint, never a second call — whether it is accepted, refused or unreachable",
    async () => {
      const realFetch = globalThis.fetch;
      const calls: string[] = [];
      let answer: "ok" | "refused" | "throw" = "ok";
      globalThis.fetch = ((input: RequestInfo | URL) => {
        calls.push(input instanceof Request ? input.url : String(input));
        if (answer === "throw") return Promise.reject(new TypeError("network"));
        return Promise.resolve(new Response("{}", { status: answer === "ok" ? 200 : 500 }));
      }) as typeof fetch;
      try {
        const p = new Msg91Provider("key", "entity", "template");
        for (const [a, want] of [["ok", "sms"], ["refused", null], ["throw", null]] as const) {
          answer = a;
          calls.length = 0;
          assertEquals(await p.send(PHONE, "123456"), want, a);
          assertEquals(calls.length, 1, `${a}: one call, no failover`);
          assert(!/whatsapp/i.test(calls[0]), `${a}: ${calls[0]} is not an SMS endpoint`);
        }
      } finally {
        globalThis.fetch = realFetch;
      }
    },
  );
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

// ---------------------------------------------------------------- OTP2: provider selection + the fixed dev code
// Desk 57 (owner, 28 Sep, option 1 strict) and ADR 2026-09-25 §1: OTP_PROVIDER takes only a
// provider that exists (`msg91`) or an explicit `fake`; unset or unknown refuses to start and every
// call errors — never a silent 200. The fixed dev code needs a SECOND switch, RF_DEV_PROJECT_REF,
// whose value must equal the project ref in the platform-injected SUPABASE_URL, so the dev
// project's secrets copied onto another project can never put a fixed code there. Refs, keys and
// URLs below are SYNTHETIC.
const DEV_REF = "devdevdevdevdevdevde"; // 20 chars, the shape of a Supabase project ref
const PILOT_REF = "pilotpilotpilotpilot";
const projectUrl = (ref: string) => `https://${ref}.supabase.co`;
const MSG91_CREDS = {
  OTP_PROVIDER_API_KEY: "synthetic-key",
  OTP_DLT_ENTITY_ID: "synthetic-entity",
  OTP_DLT_TEMPLATE_ID: "synthetic-template",
};
/** Every secret `depsFromEnv` needs except the OTP ones — so the OTP check is the only thing that
 *  can refuse. Synthetic, in the standard base64 `depsFromEnv` decodes. The DB URL points nowhere
 *  and is never dialled: a refusal throws before the store is built, and on the hosted path below
 *  the handler is given the rig's MemStore (PgStore connects lazily, on its first query). */
const OTHER_SECRETS = {
  RF_API_DB_URL: "postgres://rf_api_login:x@127.0.0.1:1/none",
  RF_JWT_HMAC_KEY: b64.enc(new Uint8Array(32).fill(1)),
  RF_PHONE_HMAC_KEY: b64.enc(new Uint8Array(32).fill(2)),
  RF_PHONE_KEK: b64.enc(new Uint8Array(32).fill(3)),
  RF_ENTITLEMENT_KEY: b64.enc(new Uint8Array(32).fill(4)),
};
const envOf = (vars: Record<string, string>) => (name: string): string | undefined => vars[name];

/** Captures every console line written while `fn` runs (rule 4: none may carry a phone or a code). */
async function consoleLines<T>(fn: () => Promise<T>): Promise<{ out: T; lines: string[] }> {
  const lines: string[] = [];
  const keep = { error: console.error, warn: console.warn, log: console.log, info: console.info };
  const sink = (...a: unknown[]) => void lines.push(a.map(String).join(" "));
  Object.assign(console, { error: sink, warn: sink, log: sink, info: sink });
  try {
    return { out: await fn(), lines };
  } finally {
    Object.assign(console, keep);
  }
}

/** The HOSTED path — what a deployed function runs (review OTP2, findings 1 and 2). `depsFn` is
 *  `() => depsFromEnv(...)`'s result over synthetic secrets, or omitted, so that `start` falls back to
 *  its default, `liveDeps`, which reads Deno.env exactly as `serve()` does. `start` checks it at boot
 *  and `entry` hands its result to the real auth-challenge handler on every call. Only the store and
 *  the clock are swapped for the rig's (there is no database here); the OTP provider, and every key
 *  the handler signs or hashes with, are the ones the hosted builder made. `handed` is every Deps the
 *  handler was given, so a test can prove which provider served it. */
async function hosted(r: Rig, depsFn?: () => Deps) {
  const handed: Deps[] = [];
  const box: { serve?: (q: Request) => Promise<Response> } = {};
  const { lines } = await consoleLines(() => {
    start(
      (q, d) => {
        handed.push(d);
        return auth(q, { ...d, store: r.deps.store, now: r.deps.now });
      },
      depsFn,
      (h) => {
        box.serve = h;
      },
    );
    return Promise.resolve();
  });
  assertEquals(lines.filter((l) => l.includes("refused")), [], "a valid configuration starts");
  const serveFn = box.serve!;
  assert(serveFn, "the isolate listens");
  return {
    handed,
    call: (path: string, b: unknown) => serveFn(post(`/auth-challenge${path}`, b)),
  };
}

/** Runs `fn` with Deno.env holding exactly `vars` for every name the functions read (ENV): the
 *  others, RF_DEV_PROJECT_REF included, are removed, so the developer's own shell cannot leak in. The
 *  previous values come back afterwards. */
async function withEnv<T>(vars: Record<string, string>, fn: () => Promise<T>): Promise<T> {
  const names = new Set<string>([...Object.values(ENV), ...Object.keys(vars)]);
  const saved = new Map([...names].map((n) => [n, Deno.env.get(n)] as const));
  for (const n of names) Deno.env.delete(n);
  for (const [k, v] of Object.entries(vars)) Deno.env.set(k, v);
  try {
    return await fn();
  } finally {
    for (const [n, v] of saved) v === undefined ? Deno.env.delete(n) : Deno.env.set(n, v);
  }
}

/** Three sign-up requests through the hosted path with fetch stubbed (no network): each must be ONE
 *  POST to MSG91 carrying the configured (synthetic) credentials and a fresh random code that is
 *  never the fixed dev code, stored only as its hash — and every request must have been served by
 *  `expected`, the Deps the hosted builder made. */
async function assertMsg91Sends(label: string, depsFn: (() => Deps) | undefined, expected: Deps) {
  const r = rig();
  const h = await hosted(r, depsFn);
  const realFetch = globalThis.fetch;
  const posts: { url: string; authkey: string | null; body: Record<string, string> }[] = [];
  globalThis.fetch = ((i: RequestInfo | URL, init?: RequestInit) => {
    posts.push({
      url: String(i),
      authkey: new Headers(init?.headers).get("authkey"),
      body: JSON.parse(String(init?.body)),
    });
    return Promise.resolve(new Response("{}", { status: 200 }));
  }) as typeof fetch;
  try {
    for (const phone of ["+919876500001", "+919876500002", "+919876500003"]) {
      const res = await h.call("/otp/request", { phone, purpose: "signup" });
      assertEquals(res.status, 200, `${label}: the hosted entry serves a valid configuration`);
      await res.body?.cancel();
    }
  } finally {
    globalThis.fetch = realFetch;
  }
  assertEquals(h.handed.length, 3, `${label}: every request reached the handler`);
  assert(h.handed.every((d) => d === expected), `${label}: served by the hosted builder's Deps`);
  assertEquals(posts.length, 3, `${label}: one MSG91 POST per request`);
  for (const [i, p] of posts.entries()) {
    assertEquals(new URL(p.url).host, "control.msg91.com", label);
    assertEquals(p.authkey, MSG91_CREDS.OTP_PROVIDER_API_KEY, `${label}: the configured key`);
    assertEquals(p.body.template_id, MSG91_CREDS.OTP_DLT_TEMPLATE_ID, label);
    assertEquals(p.body.dlt_te_id, MSG91_CREDS.OTP_DLT_ENTITY_ID, label);
    assert(/^\d{6}$/.test(p.body.otp), label);
    assertNotEquals(p.body.otp, DEV_FIXED_OTP_CODE, `${label} send ${i}: never the fixed code`);
    assertEquals(
      r.db.otp_challenges[i].code_hash,
      await blake2b256(new TextEncoder().encode(p.body.otp)),
      `${label}: the code sent is the code whose hash is stored`,
    );
  }
}

/** Asserts that `vars` refuses to start: selection throws `reason`; the startup check logs it once,
 *  before any request, without echoing a value; and every call — on every route — answers 503
 *  `unconfigured` without reaching the handler. */
async function assertRefuses(vars: Record<string, string>, reason: string, label: string) {
  assertThrows(() => selectOtpProvider(envOf(vars)), OtpConfigError, reason, label);
  let reached = 0;
  const counted = (q: Request, d: Deps) => (reached++, auth(q, d));
  const box: { serve?: (q: Request) => Promise<Response> } = {};
  const { lines } = await consoleLines(() => {
    start(counted, () => depsFromEnv(envOf({ ...OTHER_SECRETS, ...vars })), (h) => {
      box.serve = h;
    });
    return Promise.resolve();
  });
  const serveFn = box.serve!;
  assert(serveFn, `${label}: the isolate still answers, so a caller gets an error, not a hang`);
  assert(lines.some((l) => l.includes(reason)), `${label}: the startup refusal is logged`);
  for (const l of lines) {
    for (const v of Object.values(vars)) {
      // Short values ("1", "on", "dev") are substrings of ordinary words; the long ones — refs,
      // URLs, a pasted key — are what an echo would leak.
      if (v.length >= 5 && !["fake", "msg91"].includes(v)) {
        assert(!l.includes(v), `${label}: the log never echoes a configured value`);
      }
    }
  }
  for (
    const [path, b] of [
      ["/otp/request", { phone: PHONE, purpose: "signup" }],
      ["/otp/verify", { phone: PHONE, purpose: "signup", code: DEV_FIXED_OTP_CODE }],
      ["/challenge", { device_id: crypto.randomUUID() }],
    ] as const
  ) {
    const { out: res, lines: callLines } = await consoleLines(() =>
      serveFn(post(`/auth-challenge${path}`, b))
    );
    const text = await res.text();
    assertEquals(res.status, 503, `${label} ${path}: refused, never a silent 200`);
    assertEquals(JSON.parse(text), { error: "unconfigured" }, `${label} ${path}`);
    assert(!text.includes(PHONE) && !callLines.some((l) => l.includes(PHONE)), `${label}: rule 4`);
  }
  assertEquals(reached, 0, `${label}: no request reaches the handler`);
}

Deno.test("E-25-4 OTP_PROVIDER unset (or empty) refuses to start: the startup check logs it, and every call on every route answers 503 unconfigured, never a silent 200 (desk 57, ADR 2026-09-25 §1)", async () => {
  await assertRefuses({}, "otp_provider_unset", "unset");
  await assertRefuses({ OTP_PROVIDER: "" }, "otp_provider_unset", "empty");
  // Unset with the dev switch on the dev project is still unset: the second switch is never a provider.
  await assertRefuses(
    { RF_DEV_PROJECT_REF: DEV_REF, SUPABASE_URL: projectUrl(DEV_REF) },
    "otp_provider_unset",
    "unset + dev switch",
  );
});

Deno.test("E-25-5 an OTP_PROVIDER that names no built provider refuses to start — kaleyra and twilio do not exist, 2factor is OTP3, and matching is exact (no case-folding, no trimming, no prototype keys); the refusal never echoes the value", async () => {
  for (
    const v of [
      "kaleyra",
      "twilio",
      "MSG91",
      "Msg91",
      " msg91",
      "msg91 ",
      "msg91\n",
      "Fake",
      "FAKE",
      "fake ",
      "none",
      "sms",
      "whatsapp",
      "true",
      "constructor",
      "__proto__",
      "toString",
      "hasOwnProperty",
      "sk_live_pasted_by_mistake_0123456789",
    ]
  ) {
    await assertRefuses(
      { OTP_PROVIDER: v, ...MSG91_CREDS },
      "otp_provider_unknown",
      JSON.stringify(v),
    );
  }
  // The named extension point: 2factor is the owner's pick (docs/ops/lead-times.md §3) but its HTTP
  // API is in no local doc, so no adapter exists. It refuses with its own reason until OTP3 builds it.
  await assertRefuses(
    { OTP_PROVIDER: "2factor", ...MSG91_CREDS },
    "otp_provider_not_built",
    "2factor",
  );
});

Deno.test("E-25-6 OTP_PROVIDER=msg91 selects the MSG91 provider, which never carries a fixed code — not even with both dev switches set on the dev project — and the HOSTED path (depsFromEnv, liveDeps over Deno.env, start → entry) hands exactly that provider to the handler, so a pilot sends a fresh random code by MSG91; msg91 without its credentials refuses to start", async () => {
  const p = selectOtpProvider(envOf({ OTP_PROVIDER: "msg91", ...MSG91_CREDS }));
  assert(p instanceof Msg91Provider, "msg91 → Msg91Provider");
  assertEquals(p.fixedCode ?? null, null);
  const PILOT = { OTP_PROVIDER: "msg91", ...MSG91_CREDS, SUPABASE_URL: projectUrl(PILOT_REF) };
  const cases = [
    ["the pilot", PILOT],
    ["msg91 with both dev switches on the dev project", {
      OTP_PROVIDER: "msg91",
      ...MSG91_CREDS,
      RF_DEV_PROJECT_REF: DEV_REF,
      SUPABASE_URL: projectUrl(DEV_REF),
    }],
  ] as const;
  for (const [label, vars] of cases) {
    // What a deployed function builds: depsFromEnv over the project's secrets.
    const built = depsFromEnv(envOf({ ...OTHER_SECRETS, ...vars }));
    assert(built.otp instanceof Msg91Provider, `${label}: depsFromEnv hands the handler MSG91`);
    assertEquals(
      built.otp.fixedCode ?? null,
      null,
      `${label}: a real provider, never a fixed code`,
    );
    await assertMsg91Sends(label, () => built, built);
  }
  // What `serve()` runs: start's default deps, liveDeps, reading Deno.env. (The one liveDeps call in
  // this module that succeeds, since liveDeps caches per isolate.)
  await withEnv({ ...OTHER_SECRETS, ...PILOT }, async () => {
    const live = liveDeps();
    assert(live.otp instanceof Msg91Provider, "liveDeps reads OTP_PROVIDER from Deno.env");
    assertEquals(live.otp.fixedCode ?? null, null, "liveDeps on the pilot: no fixed code");
    assertEquals(live.jwtKey, new Uint8Array(32).fill(1), "liveDeps reads the keys from Deno.env");
    await assertMsg91Sends("liveDeps on the pilot", undefined, live);
  });
  for (const k of Object.keys(MSG91_CREDS)) {
    const missing: Record<string, string> = { OTP_PROVIDER: "msg91", ...MSG91_CREDS };
    delete missing[k];
    await assertRefuses(missing, "otp_provider_credentials_missing", `msg91 without ${k}`);
  }
});

Deno.test("E-25-7 OTP_PROVIDER=fake WITHOUT the second switch issues random codes on the hosted path (depsFromEnv → start → entry → handler): the fixed code is refused at verify, no stored hash is the fixed code's, and the hosted fake keeps no phone number in memory", async () => {
  const fixedHash = await blake2b256(new TextEncoder().encode(DEV_FIXED_OTP_CODE));
  for (
    const [label, vars] of [
      ["fake alone", { OTP_PROVIDER: "fake" }],
      ["fake on the dev project, switch missing", {
        OTP_PROVIDER: "fake",
        SUPABASE_URL: projectUrl(DEV_REF),
      }],
      ["fake, switch empty", {
        OTP_PROVIDER: "fake",
        RF_DEV_PROJECT_REF: "",
        SUPABASE_URL: projectUrl(DEV_REF),
      }],
    ] as const
  ) {
    const built = depsFromEnv(envOf({ ...OTHER_SECRETS, ...vars }));
    const p = built.otp;
    assert(p instanceof FakeOtpProvider, `${label}: depsFromEnv hands the handler the fake`);
    assertEquals(p.fixedCode ?? null, null, `${label}: no fixed code`);
    const r = rig();
    const h = await hosted(r, () => built);
    const phones = ["+919876500011", "+919876500012", "+919876500013", "+919876500014"];
    for (const phone of phones) {
      const res = await h.call("/otp/request", { phone, purpose: "signup" });
      assertEquals(res.status, 200, `${label}: the hosted entry serves a valid configuration`);
      await res.body?.cancel();
    }
    const hashes = r.db.otp_challenges.map((c) => b64url.enc(c.code_hash));
    assertEquals(hashes.length, phones.length, `${label}: a challenge per request`);
    assert(!hashes.includes(b64url.enc(fixedHash)), `${label}: no stored hash is the fixed code's`);
    assert(new Set(hashes).size > 1, `${label}: codes differ between requests (random)`);
    const res = await h.call("/otp/verify", {
      phone: phones[0],
      purpose: "signup",
      code: DEV_FIXED_OTP_CODE,
    });
    assertEquals(res.status, 400, `${label}: the fixed code does not sign anyone in`);
    assertEquals((await body(res)).error, "otp_invalid");
    assertEquals(p.sent, [], `${label}: the hosted fake records no number and no code`);
    assertEquals(
      p.attempts,
      phones.length,
      `${label}: the hosted builder's provider did the sends`,
    );
    assertEquals(h.handed.length, phones.length + 1, `${label}: every request reached the handler`);
    assert(h.handed.every((d) => d === built), `${label}: served by the hosted builder's Deps`);
  }
});

Deno.test("E-25-8 OTP_PROVIDER=fake plus RF_DEV_PROJECT_REF equal to this project's ref issues the fixed dev code on the hosted path (depsFromEnv → start → entry → handler): any number signs in with it, only its hash is stored, it is never in a body or a log line, and 06 §2's attempt limit still binds", async () => {
  const vars = {
    OTP_PROVIDER: "fake",
    RF_DEV_PROJECT_REF: DEV_REF,
    SUPABASE_URL: projectUrl(DEV_REF),
  };
  const built = depsFromEnv(envOf({ ...OTHER_SECRETS, ...vars }));
  const p = built.otp;
  assert(p instanceof FakeOtpProvider, "depsFromEnv hands the handler the fake");
  assertEquals(p.fixedCode, DEV_FIXED_OTP_CODE, "…bound to this project, with the fixed code");
  assertEquals(
    depsFromEnv(envOf({ ...OTHER_SECRETS, ...vars, SUPABASE_URL: `${projectUrl(DEV_REF)}/` }))
      .otp.fixedCode,
    DEV_FIXED_OTP_CODE,
    "a trailing slash is the same URL",
  );
  const r = rig();
  const h = await hosted(r, () => built);
  const fixedHash = await blake2b256(new TextEncoder().encode(DEV_FIXED_OTP_CODE));
  const { lines } = await consoleLines(async () => {
    for (const [i, phone] of ["+919876500021", "+919876500022"].entries()) {
      const req = await h.call("/otp/request", { phone, purpose: "signup" });
      const text = await req.text();
      assertEquals(req.status, 200);
      assertEquals(Object.keys(JSON.parse(text)).sort(), ["ok", "resend_after_s"]);
      assert(!text.includes(DEV_FIXED_OTP_CODE), "the code is never in the body");
      const row = r.db.otp_challenges[i];
      assertEquals(row.code_hash, fixedHash, "the fixed code is stored as its hash");
      assertEquals(row.code_hash.length, 32);
      assert(
        !JSON.stringify(row, (_k, v) => v instanceof Uint8Array ? b64url.enc(v) : v)
          .includes(DEV_FIXED_OTP_CODE),
        "no stored field holds the code in clear",
      );
      const v = await body(
        await h.call("/otp/verify", { phone, purpose: "signup", code: DEV_FIXED_OTP_CODE }),
      );
      assert(typeof v.ticket === "string" && typeof v.user_id === "string", `number ${i} signs in`);
    }
    // 3 attempts, then the challenge is spent even for the right code (06 §2 stands).
    const phone = "+919876500023";
    await h.call("/otp/request", { phone, purpose: "signup" });
    for (let i = 0; i < OTP_MAX_ATTEMPTS; i++) {
      await h.call("/otp/verify", { phone, purpose: "signup", code: "000001" });
    }
    assertEquals(
      (await h.call("/otp/verify", { phone, purpose: "signup", code: DEV_FIXED_OTP_CODE })).status,
      400,
    );
  });
  assertEquals(p.sent, [], "the hosted fake keeps no number and no code in memory");
  assertEquals(p.attempts, 3, "the hosted builder's provider did the sends");
  assert(
    h.handed.every((d) => d === built),
    "every request was served by the hosted builder's Deps",
  );
  for (const l of lines) {
    assert(!l.includes(DEV_FIXED_OTP_CODE) && !l.includes("98765000"), "rule 4: nothing logged");
  }
});

Deno.test("E-25-9 the fixed code is impossible on any project the switch does not name, even with OTP_PROVIDER=fake and RF_DEV_PROJECT_REF both set: the dev secrets copied onto the pilot, a missing/local/custom-domain/look-alike SUPABASE_URL, or a boolean-shaped switch all refuse to start", async () => {
  const fake = { OTP_PROVIDER: "fake" };
  const cases: [string, Record<string, string>][] = [
    ["dev secrets copied onto the pilot", {
      ...fake,
      RF_DEV_PROJECT_REF: DEV_REF,
      SUPABASE_URL: projectUrl(PILOT_REF),
    }],
    ["SUPABASE_URL missing", { ...fake, RF_DEV_PROJECT_REF: DEV_REF }],
    ["SUPABASE_URL empty", { ...fake, RF_DEV_PROJECT_REF: DEV_REF, SUPABASE_URL: "" }],
    ["local serve (kong)", {
      ...fake,
      RF_DEV_PROJECT_REF: "kong",
      SUPABASE_URL: "http://kong:8000",
    }],
    ["local serve (loopback)", {
      ...fake,
      RF_DEV_PROJECT_REF: "127.0.0.1",
      SUPABASE_URL: "http://127.0.0.1:54321",
    }],
    ["custom domain", {
      ...fake,
      RF_DEV_PROJECT_REF: "api",
      SUPABASE_URL: "https://api.rukkafolio.com",
    }],
    ["custom domain, dev ref", {
      ...fake,
      RF_DEV_PROJECT_REF: DEV_REF,
      SUPABASE_URL: "https://api.rukkafolio.com",
    }],
    ["http, not https", {
      ...fake,
      RF_DEV_PROJECT_REF: DEV_REF,
      SUPABASE_URL: `http://${DEV_REF}.supabase.co`,
    }],
    ["look-alike suffix", {
      ...fake,
      RF_DEV_PROJECT_REF: DEV_REF,
      SUPABASE_URL: `https://${DEV_REF}.supabase.co.example.net`,
    }],
    ["sub-label", {
      ...fake,
      RF_DEV_PROJECT_REF: DEV_REF,
      SUPABASE_URL: `https://x.${DEV_REF}.supabase.co`,
    }],
    ["with a port", {
      ...fake,
      RF_DEV_PROJECT_REF: DEV_REF,
      SUPABASE_URL: `${projectUrl(DEV_REF)}:8443`,
    }],
    ["with a path", {
      ...fake,
      RF_DEV_PROJECT_REF: DEV_REF,
      SUPABASE_URL: `${projectUrl(DEV_REF)}/x`,
    }],
    ["with credentials", {
      ...fake,
      RF_DEV_PROJECT_REF: DEV_REF,
      SUPABASE_URL: `https://u@${DEV_REF}.supabase.co`,
    }],
    ["switch upper-cased", {
      ...fake,
      RF_DEV_PROJECT_REF: DEV_REF.toUpperCase(),
      SUPABASE_URL: projectUrl(DEV_REF),
    }],
    ["switch padded", {
      ...fake,
      RF_DEV_PROJECT_REF: ` ${DEV_REF}`,
      SUPABASE_URL: projectUrl(DEV_REF),
    }],
    ...["true", "1", "yes", "on", "dev"].map((v): [string, Record<string, string>] => [
      `boolean-shaped switch ${v}`,
      { ...fake, RF_DEV_PROJECT_REF: v, SUPABASE_URL: projectUrl(PILOT_REF) },
    ]),
  ];
  for (const [label, vars] of cases) {
    await assertRefuses(vars, "otp_fixed_code_unbound", label);
  }
});

// ---------------------------------------------------------------- ADR 2026-10-04b §1, §3 (desk 107)
// The first device mints `user_id`; /otp/verify records it or refuses. What each test denies:
//   * a SERVER-MINTED SECOND IDENTITY for an install that proposed one (E-04b-1),
//   * an EXISTING ACCOUNT'S ID MOVING because a request proposed another, on any purpose (E-04b-2),
//   * a TAKEN ID being handed to a second person — and a refusal that SPENDS the user's code, which
//     would leave the client's one retry (ADR §2, C-04b-3) with nothing to retry with (E-04b-3),
//   * an OLDER CLIENT locked out, or a malformed id costing an attempt or minting anyway (E-04b-4).
// The PgStore half — rf.signup_user's 4-argument overload (0030) and the savepoint that keeps the
// 409's transaction committable — is tests/rls/client_minted_user_id.test.ts.

/** Requests a fresh code for `phone`/`purpose`, past any backoff, and returns it. */
async function freshCode(r: Rig, phone = PHONE, purpose = "signup"): Promise<string> {
  advance(r, 61 * 60_000); // out of the last hour: no resend backoff, no hourly cap
  const res = await call(r, "/otp/request", { phone, purpose });
  assertEquals(res.status, 200, "precondition: a code was issued");
  return r.otp.sent.at(-1)!.code;
}
const verify = (r: Rig, b: Record<string, unknown>) => call(r, "/otp/verify", b);
/** The challenge /otp/verify reads for this phone + purpose: the newest one. */
const lastChallenge = (r: Rig) => r.db.otp_challenges.at(-1)!;
async function registerUnder(r: Rig, ticket: string) {
  const dev = await edKeypair();
  return await body(
    await call(r, "/devices", {
      device_id: crypto.randomUUID(),
      ticket,
      pub_ed: b64url.enc(dev.pub),
      pub_x: b64url.enc(await random(32)),
    }),
  );
}

Deno.test("E-04b-1 otp/verify records the client's user_id (ADR 2026-10-04b §1 🔒): a phone with no account that proposes a canonical uuid gets ONE users row WITH that id — echoed, carried by the activation ticket, the user /devices registers under — and the server mints no second id; the proposal is honoured wherever signup would otherwise mint, whatever the purpose", async (t) => {
  await t.step("signup: the row, the echo, the ticket, the device", async () => {
    const r = rig();
    const mine = crypto.randomUUID();
    const code = await freshCode(r);
    const res = await verify(r, { phone: PHONE, purpose: "signup", code, user_id: mine });
    assertEquals(res.status, 200);
    const ok = await body(res);
    assertEquals(ok.user_id, mine, "echoed: the id the ledger minted at first run");
    assertEquals([...r.db.users.keys()], [mine], "one row, under the proposed id — none minted");
    const u = r.db.users.get(mine)!;
    assert(u.phone_hmac?.length === 32, "phone only as HMAC");
    assert(u.phone_ct && u.phone_ct.length > 24, "and as ciphertext");
    assert(!new TextDecoder().decode(u.phone_ct).includes("9876543210"), "never in clear");
    assertEquals(r.db.activation_tickets.length, 1);
    assertEquals(r.db.activation_tickets[0].user_id, mine, "the ticket names the proposed user");
    assert(lastChallenge(r).consumed_at, "the code is spent");
    const reg = await registerUnder(r, ok.ticket);
    assertEquals(reg.user_id, mine, "the device is registered under the proposed user");
    assertEquals([...r.db.devices.values()].map((d) => d.user_id), [mine]);
  });
  await t.step("the language is still recorded alongside the proposed id", async () => {
    const r = rig();
    const mine = crypto.randomUUID();
    const code = await freshCode(r);
    const ok = await body(
      await verify(r, { phone: PHONE, purpose: "signup", code, user_id: mine, language: "pa" }),
    );
    assertEquals(ok.user_id, mine);
    assertEquals(r.db.users.get(mine)!.language, "pa");
  });
  await t.step(
    "an unknown phone on phone change or account deletion: the server would sign it up, so the proposal is what it records",
    async () => {
      // ADR 04b §1: "honoured only where the server would otherwise call signupUser" — and
      // "the server never mints a user id for a request that carried one". A phone with no account
      // is still signed up on these two purposes (desk 129 remainder, owner-open). device_activation
      // no longer signs up an unknown phone — it answers account "none" + a signup ticket
      // (ADR 2026-10-05c §2; E-1005c-*), so it is not in this list.
      for (const purpose of ["phone_change", "account_deletion"]) {
        const r = rig();
        const mine = crypto.randomUUID();
        const code = await freshCode(r, PHONE, purpose);
        const ok = await body(await verify(r, { phone: PHONE, purpose, code, user_id: mine }));
        assertEquals(ok.user_id, mine, purpose);
        assertEquals([...r.db.users.keys()], [mine], purpose);
      }
    },
  );
});

Deno.test("E-04b-2 a phone that already has an account answers with ITS user id and ignores the proposal (ADR 2026-10-04b §1, §3 🔒): on every purpose — signup, device activation, phone change, account deletion — and whether the proposal is fresh, another user's, or the account's own (a retry after a lost answer), no row is created, no id moves, and the ticket names the account", async () => {
  for (const purpose of ["signup", "device_activation", "phone_change", "account_deletion"]) {
    const r = rig();
    const owner = crypto.randomUUID();
    const first = await body(
      await verify(r, {
        phone: PHONE,
        purpose: "signup",
        code: await freshCode(r),
        user_id: owner,
      }),
    );
    assertEquals(first.user_id, owner, "precondition: the account exists under its own id");
    const other = r.db.addUser({ phone_hmac: await random(32), phone_ct: await random(40) }).id;
    const otherHmac = r.db.users.get(other)!.phone_hmac;
    const before = [...r.db.users.keys()].sort();
    for (
      const [label, proposal] of [
        ["fresh", crypto.randomUUID()],
        ["another user's", other],
        ["the account's own", owner],
      ] as const
    ) {
      const code = await freshCode(r, PHONE, purpose);
      const res = await verify(r, { phone: PHONE, purpose, code, user_id: proposal });
      assertEquals(res.status, 200, `${purpose}, ${label}: never a 409 for a known phone`);
      const ok = await body(res);
      assertEquals(ok.user_id, owner, `${purpose}, ${label}: the account's id, not the proposal`);
      assertEquals([...r.db.users.keys()].sort(), before, `${purpose}, ${label}: no row created`);
      assertEquals(r.db.activation_tickets.at(-1)!.user_id, owner, `${purpose}, ${label}: ticket`);
      assert(lastChallenge(r).consumed_at, `${purpose}, ${label}: the code is spent as usual`);
    }
    assertEquals(r.db.users.get(other)!.phone_hmac, otherHmac, "the other user is untouched");
    assert(r.db.users.has(owner), "the account's id never moved");
  }
});

Deno.test("E-04b-3 a proposed user_id another user holds → 409 {error: user_id_taken} and NOTHING moves: no users row, no ticket, the OTP challenge left unconsumed with its attempts unbumped — so the client's one retry with a freshly minted id and the SAME code answers 200 under the new id (ADR 2026-10-04b §1, §2 🔒; C-04b-3's contract); an erased user's id is taken too; a wrong code with a taken id is an ordinary otp_invalid, never a 409", async (t) => {
  await t.step("held by a live user: 409, nothing created, the code still good", async () => {
    const r = rig();
    const holder = r.db.addUser({ phone_hmac: await random(32), phone_ct: await random(40) });
    const holderHmac = holder.phone_hmac;
    const code = await freshCode(r);
    const res = await verify(r, { phone: PHONE, purpose: "signup", code, user_id: holder.id });
    assertEquals(res.status, 409);
    assertEquals(await body(res), { error: "user_id_taken" }, "named; says nothing of the holder");
    assertEquals([...r.db.users.keys()], [holder.id], "no row created");
    assertEquals(r.db.users.get(holder.id)!.phone_hmac, holderHmac, "the holder is untouched");
    assertEquals(r.db.activation_tickets.length, 0, "no ticket");
    assertEquals(lastChallenge(r).consumed_at, null, "the challenge is NOT consumed");
    assertEquals(lastChallenge(r).attempts, 0, "and NO attempt is spent");

    // The client discards its provisional identity, mints a fresh one and retries ONCE with the
    // same code (ADR 04b §2) — no second OTP request, no new SMS.
    const sent = r.otp.sent.length;
    const fresh = crypto.randomUUID();
    const again = await verify(r, { phone: PHONE, purpose: "signup", code, user_id: fresh });
    assertEquals(again.status, 200, "the retry with the same code succeeds");
    const ok = await body(again);
    assertEquals(ok.user_id, fresh, "under the freshly minted id");
    assertEquals([...r.db.users.keys()].sort(), [holder.id, fresh].sort());
    assertEquals(r.db.activation_tickets.at(-1)!.user_id, fresh);
    assertEquals(r.otp.sent.length, sent, "no new code was needed");
    assert(lastChallenge(r).consumed_at, "now the code is spent");
    const spent = await verify(r, {
      phone: PHONE,
      purpose: "signup",
      code,
      user_id: crypto.randomUUID(),
    });
    assertEquals(spent.status, 400, "and cannot be used a third time");
    assertEquals((await body(spent)).error, "otp_invalid");
  });
  await t.step("held by an erased user: still taken — an id is never reused", async () => {
    const r = rig();
    const erased = r.db.addUser({ erased_at: new Date(T0), phone_hmac: null, phone_ct: null });
    const code = await freshCode(r);
    const res = await verify(r, { phone: PHONE, purpose: "signup", code, user_id: erased.id });
    assertEquals(res.status, 409);
    assertEquals((await body(res)).error, "user_id_taken");
    assertEquals(r.db.users.size, 1);
    assertEquals(r.db.users.get(erased.id)!.phone_hmac, null, "the erased row gains no phone");
    assertEquals(lastChallenge(r).consumed_at, null);
    assertEquals(lastChallenge(r).attempts, 0);
  });
  await t.step(
    "no oracle before the code is proven: a wrong code with a taken id is otp_invalid and costs an attempt",
    async () => {
      const r = rig();
      const holder = r.db.addUser({ phone_hmac: await random(32), phone_ct: await random(40) });
      const code = await freshCode(r);
      const wrong = code === "000000" ? "111111" : "000000";
      const res = await verify(r, {
        phone: PHONE,
        purpose: "signup",
        code: wrong,
        user_id: holder.id,
      });
      assertEquals(res.status, 400, "the code is checked first");
      assertEquals(await body(res), { error: "otp_invalid", attempts_left: OTP_MAX_ATTEMPTS - 1 });
      assertEquals(r.db.users.size, 1);
    },
  );
  await t.step(
    "two refusals in a row spend nothing either: the retry rule holds however the collision repeats",
    async () => {
      const r = rig();
      const a = r.db.addUser().id, b = r.db.addUser().id;
      const code = await freshCode(r);
      for (const held of [a, b]) {
        const res = await verify(r, { phone: PHONE, purpose: "signup", code, user_id: held });
        assertEquals(res.status, 409);
      }
      assertEquals(lastChallenge(r).attempts, 0);
      assertEquals(lastChallenge(r).consumed_at, null);
      assertEquals(r.db.users.size, 2);
    },
  );
});

Deno.test("E-04b-4 user_id is optional and shape-checked first (ADR 2026-10-04b §1 🔒): absent → today's behaviour, the server mints the id, so an older client still signs up; present but not a canonical lowercase uuid → 400 bad_request before the challenge is read — no attempt spent, nothing consumed, no user, no ticket — and the same code then still verifies", async (t) => {
  await t.step("absent: the server mints, exactly as before ADR 04b", async () => {
    const r = rig();
    const code = await freshCode(r);
    const res = await verify(r, { phone: PHONE, purpose: "signup", code });
    assertEquals(res.status, 200);
    const ok = await body(res);
    assert(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(ok.user_id),
      "a canonical uuid",
    );
    assertEquals([...r.db.users.keys()], [ok.user_id]);
    assertEquals(r.db.activation_tickets[0].user_id, ok.user_id);
    assertEquals((await registerUnder(r, ok.ticket)).user_id, ok.user_id);
  });
  await t.step("malformed: 400 bad_request, and the challenge is not touched", async () => {
    const r = rig();
    const code = await freshCode(r);
    const good = crypto.randomUUID();
    const malformed: [string, unknown][] = [
      ["garbage", "not-a-uuid"],
      ["upper case", good.toUpperCase()],
      ["braces", `{${good}}`],
      ["no hyphens", good.replaceAll("-", "")],
      ["trailing space", `${good} `],
      ["too short", good.slice(0, 35)],
      ["empty", ""],
      ["null", null],
      ["a number", 42],
      ["a boolean", true],
      ["an object", { id: good }],
      ["an array", [good]],
    ];
    for (const [label, user_id] of malformed) {
      const res = await verify(r, { phone: PHONE, purpose: "signup", code, user_id });
      assertEquals(res.status, 400, label);
      assertEquals(await body(res), { error: "bad_request" }, label);
      assertEquals(r.db.users.size, 0, `${label}: no user`);
      assertEquals(r.db.activation_tickets.length, 0, `${label}: no ticket`);
      assertEquals(lastChallenge(r).attempts, 0, `${label}: no attempt spent`);
      assertEquals(lastChallenge(r).consumed_at, null, `${label}: not consumed`);
    }
    const ok = await body(
      await verify(r, { phone: PHONE, purpose: "signup", code, user_id: good }),
    );
    assertEquals(ok.user_id, good, "the same code still verifies once the id is well formed");
  });
});
