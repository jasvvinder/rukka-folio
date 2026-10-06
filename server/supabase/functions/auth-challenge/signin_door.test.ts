// The sign-in door (ADR 2026-10-05c §2 🔒, owner-ruled 5 Oct 2026; desk 129 for the sign-in path).
// Ids E-1005c-1 … E-1005c-10 — the route on MemStore. The database half (PgStore as rf_api, the
// concurrent double adopt, the hostile-role probes on the ticket table) is
// tests/rls/signin_door.test.ts, E-1005c-11 … E-1005c-13.
//
// The contract the app slice (SIGNIN1A) builds against:
//   POST /otp/verify   success gains `account: "existing" | "created" | "none"`.
//                      device_activation + a phone with NO account → 200
//                      {account: "none", signup_ticket, expires_in_s} — no `ticket`, no `user_id`,
//                      and nobody is signed up.
//   POST /signup/adopt {signup_ticket, user_id} → 200 {ticket, user_id, account: "created",
//                      expires_in_s}; 409 {error: user_id_taken} as verify; every ticket problem is
//                      ONE 400 {error: signup_ticket_invalid}; a phone that gained an account in
//                      between fails closed with that same error.
// What an attacker — or a confused client — wants here, and which test denies it:
//   * A SIGN-UP NOBODY CHOSE: a code verified on the sign-in path creating an account (E-1005c-1).
//   * A SECOND ACCOUNT FOR ONE PHONE: adopting twice, or after the phone gained one (-3, -6).
//   * ANOTHER PHONE'S ACCOUNT: steering a ticket at a number it was not issued for (-5).
//   * A CODE-FREE DOOR: /signup/adopt used to skip the code, the limits or the backoff (-9).
//   * AN ORACLE: any pre-code answer that differs for a number with books (-9).
// Fixtures are synthetic: random numbers, random bytes, no ledger content (CLAUDE.md rule 4).
import { assert, assertEquals, assertNotEquals } from "@std/assert";
import { b64url, bytesEqual } from "../_shared/bytes.ts";
import { decryptPhone, phoneHmac } from "../_shared/phone.ts";
import { blake2b256 } from "../_shared/sodium.ts";
import { advance, body, edKeypair, post, random, type Rig, rig, T0 } from "../_tests/harness.ts";
import { handler as auth, OTP_MAX_ATTEMPTS, SIGNUP_TICKET_TTL_S, TICKET_TTL_S } from "./index.ts";

const PHONE = "+919812345670";
const OTHER = "+919812345671";
const THIRD = "+919812345672";
const PURPOSES = ["signup", "device_activation", "phone_change", "account_deletion"] as const;
const INVALID = { error: "signup_ticket_invalid" };

const call = (r: Rig, path: string, b: unknown) => auth(post(`/auth-challenge${path}`, b), r.deps);
const verify = (r: Rig, b: Record<string, unknown>) => call(r, "/otp/verify", b);
const adopt = (r: Rig, b: unknown) => call(r, "/signup/adopt", b);
const keys = (o: Record<string, unknown>) => Object.keys(o).sort();
const hmacOf = (r: Rig, phone: string) => phoneHmac(r.deps.phoneHmacKey, phone);

/** A fresh code for `phone` on `purpose`, outside the last hour's backoff and caps. */
async function freshCode(r: Rig, phone = PHONE, purpose = "signup"): Promise<string> {
  advance(r, 61 * 60_000);
  const res = await call(r, "/otp/request", { phone, purpose });
  assertEquals(res.status, 200, "precondition: a code was issued");
  return r.otp.sent.at(-1)!.code;
}
/** The sign-in door with a number that has no books: a verified code, `account: "none"`. */
async function signupTicket(
  r: Rig,
  phone = PHONE,
  extra: Record<string, unknown> = {},
): Promise<string> {
  const code = await freshCode(r, phone, "device_activation");
  const res = await verify(r, { phone, purpose: "device_activation", code, ...extra });
  assertEquals(res.status, 200, "precondition: the code verifies");
  const out = await body(res);
  assertEquals(out.account, "none", "precondition: the number has no books");
  return out.signup_ticket as string;
}
/** An account for `phone`, made on the I'm-new path under a client-minted id. */
async function account(r: Rig, phone = PHONE): Promise<string> {
  const id = crypto.randomUUID();
  const code = await freshCode(r, phone, "signup");
  const out = await body(await verify(r, { phone, purpose: "signup", code, user_id: id }));
  assertEquals(out.user_id, id, "precondition: the account exists under its own id");
  return id;
}
async function registerUnder(r: Rig, ticket: string) {
  const dev = await edKeypair();
  return await call(r, "/devices", {
    device_id: crypto.randomUUID(),
    ticket,
    pub_ed: b64url.enc(dev.pub),
    pub_x: b64url.enc(await random(32)),
  });
}
/** The stored row of a sign-up ticket, found by the hash of its bytes (never by the ticket). */
async function rowOf(r: Rig, ticket: string) {
  const h = await blake2b256(b64url.dec(ticket));
  return r.db.activation_tickets.find((t) => bytesEqual(t.ticket_hash, h));
}
const usersWithPhone = async (r: Rig, phone: string) => {
  const h = await hmacOf(r, phone);
  return [...r.db.users.values()].filter((u) => u.phone_hmac && bytesEqual(u.phone_hmac, h))
    .map((u) => u.id);
};

// ---------------------------------------------------------------- E-1005c-1
Deno.test("E-1005c-1 otp/verify, device_activation, a number with NO books (ADR 2026-10-05c §2 🔒): 200 {account: none, signup_ticket, expires_in_s} and nothing else — no ticket, no user_id — nobody is signed up and the proposed id is recorded nowhere; the code is spent; the server keeps only the ticket's hash and the phone's HMAC (no phone, no ciphertext), the ticket lives ≤ 10 minutes, and it cannot register a device", async () => {
  const r = rig();
  const mine = crypto.randomUUID();
  const code = await freshCode(r, PHONE, "device_activation");
  const res = await verify(r, {
    phone: PHONE,
    purpose: "device_activation",
    code,
    user_id: mine,
    language: "pa",
  });
  assertEquals(res.status, 200);
  const out = await body(res);
  assertEquals(keys(out), ["account", "expires_in_s", "signup_ticket"], "exactly the contract");
  assertEquals(out.account, "none");
  assertEquals(out.expires_in_s, SIGNUP_TICKET_TTL_S);
  assert(SIGNUP_TICKET_TTL_S > 0 && SIGNUP_TICKET_TTL_S <= 600, "TTL ≤ 10 minutes");
  assertEquals(typeof out.signup_ticket, "string");

  assertEquals(r.db.users.size, 0, "NO sign-up: the person has not chosen 'Set up new books'");
  assert(!r.db.activation_tickets.some((t) => t.user_id === mine), "the proposal is not recorded");
  assert(r.db.otp_challenges.at(-1)!.consumed_at, "the code is spent");
  const replay = await verify(r, { phone: PHONE, purpose: "device_activation", code });
  assertEquals(replay.status, 400, "and cannot be verified twice");
  assertEquals((await body(replay)).error, "otp_invalid");

  // What the server keeps: one row, the hash of the ticket's bytes and the phone's HMAC.
  assertEquals(r.db.activation_tickets.length, 1);
  const row = (await rowOf(r, out.signup_ticket))!;
  assert(row, "stored under the hash of the ticket's bytes");
  assertEquals(row.user_id, null, "names no user: nobody was signed up");
  assert(bytesEqual(row.phone_hmac, await hmacOf(r, PHONE)), "bound to the phone's HMAC");
  assertEquals(row.consumed_at, null);
  assert(row.expires_at.getTime() - row.created_at.getTime() <= 600_000, "TTL ≤ 10 minutes");
  assert(!JSON.stringify(row).includes("9812345670"), "no phone in clear in the row");
  const raw = b64url.dec(out.signup_ticket);
  assert(!new TextDecoder().decode(raw).includes("9812345670"), "the ticket is opaque");
  assert(!out.signup_ticket.includes("9812345670"));

  // A sign-up ticket is not an activation ticket: /devices refuses it and it is not spent.
  const reg = await registerUnder(r, out.signup_ticket);
  assertNotEquals(reg.status, 200, "a sign-up ticket registers no device");
  assertEquals(r.db.devices.size, 0);
  assertEquals((await rowOf(r, out.signup_ticket))!.consumed_at, null, "and is not burned by it");
});

// ---------------------------------------------------------------- E-1005c-2
Deno.test("E-1005c-2 /signup/adopt — 'Set up new books' (S0.2e) — needs NO second code: it signs up exactly one user under the client-minted id (ADR 2026-10-04b §1), with the phone as HMAC + ciphertext and the language the verify carried, answers {ticket, user_id, account: created, expires_in_s}, and its ticket registers the first device; the phone then has books", async () => {
  const r = rig();
  const ticket = await signupTicket(r, PHONE, { language: "pa" });
  const sent = r.otp.sent.length, challenges = r.db.otp_challenges.length;
  const mine = crypto.randomUUID();
  const res = await adopt(r, { signup_ticket: ticket, user_id: mine });
  assertEquals(res.status, 200);
  const out = await body(res);
  assertEquals(keys(out), ["account", "expires_in_s", "ticket", "user_id"], "a signup's shape");
  assertEquals(out.account, "created");
  assertEquals(out.user_id, mine, "the id the ledger minted at first run");
  assertEquals(out.expires_in_s, TICKET_TTL_S);

  assertEquals([...r.db.users.keys()], [mine], "exactly one user, under the proposal");
  const u = r.db.users.get(mine)!;
  assert(bytesEqual(u.phone_hmac!, await hmacOf(r, PHONE)), "the ticket's phone, as HMAC");
  assertEquals(await decryptPhone(r.deps.phoneKek, u.phone_ct!), PHONE, "and as ciphertext");
  assert(!new TextDecoder().decode(u.phone_ct!).includes("9812345670"), "never in clear");
  assertEquals(u.language, "pa", "the language the verify carried");
  assertEquals(r.otp.sent.length, sent, "no second code was sent");
  assertEquals(r.db.otp_challenges.length, challenges, "or asked for");
  assert((await rowOf(r, ticket))!.consumed_at, "the sign-up ticket is spent");

  const reg = await registerUnder(r, out.ticket);
  assertEquals(reg.status, 200, "the activation ticket registers the first device");
  assertEquals((await body(reg)).user_id, mine);

  const code = await freshCode(r, PHONE, "device_activation");
  const later = await body(
    await verify(r, { phone: PHONE, purpose: "device_activation", code }),
  );
  assertEquals([later.account, later.user_id], ["existing", mine], "the number has books now");
});

// ---------------------------------------------------------------- E-1005c-3
Deno.test("E-1005c-3 a sign-up ticket is single-use: a second adopt — same id, a new id, or after the device registered — is 400 signup_ticket_invalid and creates nothing", async () => {
  const r = rig();
  const ticket = await signupTicket(r);
  const mine = crypto.randomUUID();
  const first = await body(await adopt(r, { signup_ticket: ticket, user_id: mine }));
  assertEquals(first.account, "created");
  for (const id of [mine, crypto.randomUUID()]) {
    const again = await adopt(r, { signup_ticket: ticket, user_id: id });
    assertEquals(again.status, 400);
    assertEquals(await body(again), INVALID, "one generic error");
  }
  assertEquals((await registerUnder(r, first.ticket)).status, 200);
  const late = await adopt(r, { signup_ticket: ticket, user_id: crypto.randomUUID() });
  assertEquals([late.status, await body(late)], [400, INVALID]);
  assertEquals([...r.db.users.keys()], [mine], "still exactly one user");
});

// ---------------------------------------------------------------- E-1005c-4
Deno.test("E-1005c-4 a sign-up ticket expires: good one second before its TTL, 400 signup_ticket_invalid at it, and an expired ticket creates nothing", async (t) => {
  await t.step("one second before the TTL: still good", async () => {
    const r = rig();
    const ticket = await signupTicket(r);
    advance(r, SIGNUP_TICKET_TTL_S * 1000 - 1000);
    const res = await adopt(r, { signup_ticket: ticket, user_id: crypto.randomUUID() });
    assertEquals(res.status, 200);
  });
  await t.step("at the TTL and after: invalid, nothing created", async () => {
    for (const late of [0, 1000, 3600_000]) {
      const r = rig();
      const ticket = await signupTicket(r);
      advance(r, SIGNUP_TICKET_TTL_S * 1000 + late);
      const res = await adopt(r, { signup_ticket: ticket, user_id: crypto.randomUUID() });
      assertEquals(res.status, 400, `+${late} ms`);
      assertEquals(await body(res), INVALID);
      assertEquals(r.db.users.size, 0);
    }
  });
});

// ---------------------------------------------------------------- E-1005c-5
Deno.test("E-1005c-5 a ticket is bound to its phone by HMAC: phone A's ticket signs up A and never B; a ticket spliced from A's and B's is invalid and spends neither; a stored row whose HMAC is not the sealed phone's refuses (the check is live, not decorative); a tampered ticket is invalid", async (t) => {
  await t.step("A's ticket makes A's account, never B's", async () => {
    const r = rig();
    // B first: each code is fetched an hour on (freshCode), so B's ticket has lapsed by the time
    // A's is used — the splices below fail on the lookup whatever their age.
    const b = await signupTicket(r, OTHER);
    const a = await signupTicket(r, PHONE);
    const ra = b64url.dec(a), rb = b64url.dec(b);
    for (
      const spliced of [
        new Uint8Array([...ra.slice(0, 32), ...rb.slice(32)]),
        new Uint8Array([...rb.slice(0, 32), ...ra.slice(32)]),
      ]
    ) {
      const res = await adopt(r, {
        signup_ticket: b64url.enc(spliced),
        user_id: crypto.randomUUID(),
      });
      assertEquals([res.status, await body(res)], [400, INVALID], "a splice is no ticket");
    }
    assertEquals(r.db.users.size, 0);
    assertEquals((await rowOf(r, a))!.consumed_at, null, "the splice spent neither ticket");
    assertEquals((await rowOf(r, b))!.consumed_at, null);

    const mine = crypto.randomUUID();
    assertEquals((await adopt(r, { signup_ticket: a, user_id: mine })).status, 200);
    assertEquals(await usersWithPhone(r, PHONE), [mine], "A's phone has the account");
    assertEquals(await usersWithPhone(r, OTHER), [], "B's has none");
  });
  await t.step("the row's HMAC must be the sealed phone's", async () => {
    const r = rig();
    const ticket = await signupTicket(r, PHONE);
    (await rowOf(r, ticket))!.phone_hmac = await hmacOf(r, THIRD);
    const res = await adopt(r, { signup_ticket: ticket, user_id: crypto.randomUUID() });
    assertEquals([res.status, await body(res)], [400, INVALID]);
    assertEquals(r.db.users.size, 0, "no account for either number");
  });
  await t.step("a tampered ticket is no ticket", async () => {
    const r = rig();
    const ticket = await signupTicket(r, PHONE);
    const raw = b64url.dec(ticket);
    for (const i of [0, 40, raw.length - 1]) {
      const bad = raw.slice();
      bad[i] ^= 1;
      const res = await adopt(r, { signup_ticket: b64url.enc(bad), user_id: crypto.randomUUID() });
      assertEquals([res.status, await body(res)], [400, INVALID], `byte ${i}`);
    }
    assertEquals(r.db.users.size, 0);
    assertEquals(
      (await adopt(r, { signup_ticket: ticket, user_id: crypto.randomUUID() })).status,
      200,
    );
  });
});

// ---------------------------------------------------------------- E-1005c-6
Deno.test("E-1005c-6 a number that gained books between the code and the choice FAILS CLOSED: adopt answers the same 400 signup_ticket_invalid — never `existing`, never the account's id — creates nothing, spends the ticket, and the client restarts at the code (which then answers existing)", async () => {
  const r = rig();
  const ticket = await signupTicket(r, PHONE);
  // Meanwhile the I'm-new path signs the number up — inside the ticket's life: 31 s on is past the
  // first resend backoff (06 §2) and well within the TTL, so adopt below meets a LIVE ticket and
  // the refusal is the account's, not the clock's (the spent ticket proves which branch ran).
  advance(r, 31_000);
  assertEquals((await call(r, "/otp/request", { phone: PHONE, purpose: "signup" })).status, 200);
  const owner = crypto.randomUUID();
  const made = await body(
    await verify(r, {
      phone: PHONE,
      purpose: "signup",
      code: r.otp.sent.at(-1)!.code,
      user_id: owner,
    }),
  );
  assertEquals([made.account, made.user_id], ["created", owner], "precondition: it has books now");
  assert((await rowOf(r, ticket))!.expires_at > r.clock.now, "precondition: the ticket is live");
  const tickets = r.db.activation_tickets.length;
  const res = await adopt(r, { signup_ticket: ticket, user_id: crypto.randomUUID() });
  assertEquals(res.status, 400);
  assertEquals(await body(res), INVALID, "the generic error: no user_id, no ticket, no account");
  assertEquals([...r.db.users.keys()], [owner], "no second account for the phone");
  assertEquals(r.db.activation_tickets.length, tickets, "no activation ticket issued");
  assert((await rowOf(r, ticket))!.consumed_at, "the dead ticket is spent");
  const again = await adopt(r, { signup_ticket: ticket, user_id: crypto.randomUUID() });
  assertEquals([again.status, await body(again)], [400, INVALID], "and stays dead");

  const code = await freshCode(r, PHONE, "device_activation");
  const restart = await body(
    await verify(r, { phone: PHONE, purpose: "device_activation", code }),
  );
  assertEquals([restart.account, restart.user_id], ["existing", owner], "the restart finds it");
});

// ---------------------------------------------------------------- E-1005c-7
Deno.test("E-1005c-7 adopt's refusals: a proposed id another user holds (live or erased) is 409 user_id_taken with NOTHING moved and the ticket NOT spent, so the client re-mints and retries once with the same ticket (ADR 2026-10-04b §2, as verify); a missing or malformed user_id is 400 bad_request before the ticket is read; and every ticket problem — absent, not a string, not base64, the wrong size, unknown, an ACTIVATION ticket — is one 400 signup_ticket_invalid that spends nothing", async (t) => {
  await t.step("409, nothing moves, the retry with the same ticket succeeds", async () => {
    for (const erased of [false, true]) {
      const r = rig();
      const holder = erased
        ? r.db.addUser({ erased_at: new Date(T0), phone_hmac: null, phone_ct: null })
        : r.db.addUser({ phone_hmac: await random(32), phone_ct: await random(40) });
      const ticket = await signupTicket(r);
      const tickets = r.db.activation_tickets.length, sent = r.otp.sent.length;
      const res = await adopt(r, { signup_ticket: ticket, user_id: holder.id });
      assertEquals(res.status, 409, `erased=${erased}`);
      assertEquals(await body(res), { error: "user_id_taken" });
      assertEquals([...r.db.users.keys()], [holder.id], "no row created");
      assertEquals(r.db.activation_tickets.length, tickets, "no activation ticket");
      assertEquals((await rowOf(r, ticket))!.consumed_at, null, "the ticket is NOT spent");
      const fresh = crypto.randomUUID();
      const again = await adopt(r, { signup_ticket: ticket, user_id: fresh });
      assertEquals(again.status, 200, "the one retry, same ticket");
      assertEquals((await body(again)).user_id, fresh);
      assertEquals(r.otp.sent.length, sent, "no new code was needed");
    }
  });
  await t.step("user_id missing or malformed: bad_request, the ticket untouched", async () => {
    const r = rig();
    const ticket = await signupTicket(r);
    const good = crypto.randomUUID();
    const bad: [string, Record<string, unknown>][] = [
      ["absent", { signup_ticket: ticket }],
      ["null", { signup_ticket: ticket, user_id: null }],
      ["upper case", { signup_ticket: ticket, user_id: good.toUpperCase() }],
      ["garbage", { signup_ticket: ticket, user_id: "not-a-uuid" }],
      ["a number", { signup_ticket: ticket, user_id: 42 }],
    ];
    for (const [label, b] of bad) {
      const res = await adopt(r, b);
      assertEquals([res.status, await body(res)], [400, { error: "bad_request" }], label);
      assertEquals((await rowOf(r, ticket))!.consumed_at, null, label);
    }
    assertEquals(r.db.users.size, 0);
    assertEquals((await adopt(r, { signup_ticket: ticket, user_id: good })).status, 200);
  });
  await t.step("every ticket problem is the one generic error", async () => {
    const r = rig();
    await account(r, OTHER);
    const activation = r.db.activation_tickets.length;
    // A real ACTIVATION ticket (a signup verify's), offered as a sign-up ticket.
    const code = await freshCode(r, OTHER, "device_activation");
    const act = await body(await verify(r, { phone: OTHER, purpose: "device_activation", code }));
    assertEquals(act.account, "existing");
    const bad: [string, unknown][] = [
      ["absent", undefined],
      ["null", null],
      ["a number", 7],
      ["an object", { t: "x" }],
      ["empty", ""],
      ["not base64", "!!!"],
      ["32 random bytes", b64url.enc(await random(32))],
      ["96 random bytes", b64url.enc(await random(96))],
      ["4 KiB", b64url.enc(await random(4096))],
      ["an activation ticket", act.ticket],
    ];
    for (const [label, signup_ticket] of bad) {
      const b: Record<string, unknown> = { user_id: crypto.randomUUID() };
      if (signup_ticket !== undefined) b.signup_ticket = signup_ticket;
      const res = await adopt(r, b);
      assertEquals([res.status, await body(res)], [400, INVALID], label);
    }
    assertEquals(r.db.users.size, 1, "nothing created");
    assertEquals(r.db.activation_tickets.length, activation + 1, "nothing issued");
    assertEquals((await registerUnder(r, act.ticket)).status, 200, "the activation ticket lives");
  });
});

// ---------------------------------------------------------------- E-1005c-8
Deno.test("E-1005c-8 every other verify keeps its behaviour and gains `account`: signup signs up an unknown number (created) and answers a known one with its id (existing); device_activation answers a known number existing with its ticket; phone_change and account_deletion are unchanged — an unknown number is still signed up (⚠️ desk 129 remainder, owner-open) and a known one answers existing", async () => {
  for (const purpose of PURPOSES) {
    // Unknown number.
    const r = rig();
    const mine = crypto.randomUUID();
    const code = await freshCode(r, PHONE, purpose);
    const res = await verify(r, { phone: PHONE, purpose, code, user_id: mine });
    assertEquals(res.status, 200, purpose);
    const out = await body(res);
    if (purpose === "device_activation") {
      assertEquals(out.account, "none", purpose);
      assertEquals(r.db.users.size, 0, purpose);
    } else {
      assertEquals(keys(out), ["account", "expires_in_s", "ticket", "user_id"], purpose);
      assertEquals([out.account, out.user_id], ["created", mine], purpose);
      assertEquals(out.expires_in_s, TICKET_TTL_S, purpose);
      assertEquals([...r.db.users.keys()], [mine], purpose);
    }
    // Known number.
    const k = rig();
    const owner = await account(k, PHONE);
    const before = k.db.users.size;
    const c2 = await freshCode(k, PHONE, purpose);
    const known = await verify(k, {
      phone: PHONE,
      purpose,
      code: c2,
      user_id: crypto.randomUUID(),
    });
    assertEquals(known.status, 200, purpose);
    const kout = await body(known);
    assertEquals(keys(kout), ["account", "expires_in_s", "ticket", "user_id"], purpose);
    assertEquals([kout.account, kout.user_id], ["existing", owner], purpose);
    assertEquals(k.db.users.size, before, `${purpose}: no row created`);
    assertEquals(k.db.activation_tickets.at(-1)!.user_id, owner, `${purpose}: the ticket`);
  }
});

// ---------------------------------------------------------------- E-1005c-9
Deno.test("E-1005c-9 before the code nothing tells a number with books from one without (06 §2, ADR 2026-10-05c §2): /otp/request, the backoff 429, a wrong code, a spent or missing challenge and a malformed body answer byte-identically for both on every purpose; and /signup/adopt is no door around the code — without a ticket only a verified code yields, it sends no SMS, opens no challenge, spends no attempt and creates no one", async () => {
  const known = rig(), unknown = rig();
  await account(known, PHONE);
  const pair = async (path: string, b: Record<string, unknown>) => {
    const a = await call(known, path, b), c = await call(unknown, path, b);
    return [[a.status, await a.text()], [c.status, await c.text()]];
  };
  for (const purpose of PURPOSES) {
    advance(known, 61 * 60_000);
    advance(unknown, 61 * 60_000);
    const [rk, ru] = await pair("/otp/request", { phone: PHONE, purpose });
    assertEquals(rk, ru, `${purpose}: request`);
    assertEquals(rk[0], 200);
    const [bk, bu] = await pair("/otp/request", { phone: PHONE, purpose });
    assertEquals(bk, bu, `${purpose}: backoff`);
    assertEquals(bk[0], 429);
    const wrong = known.otp.sent.at(-1)!.code === "000000" ? "111111" : "000000";
    const wrongU = unknown.otp.sent.at(-1)!.code === "000000" ? "111111" : "000000";
    for (let i = 1; i <= OTP_MAX_ATTEMPTS; i++) {
      const a = await verify(known, { phone: PHONE, purpose, code: wrong });
      const c = await verify(unknown, { phone: PHONE, purpose, code: wrongU });
      assertEquals(
        [a.status, await a.text()],
        [c.status, await c.text()],
        `${purpose}: wrong ${i}`,
      );
    }
    const [sk, su] = await pair("/otp/verify", { phone: PHONE, purpose, code: "123456" });
    assertEquals(sk, su, `${purpose}: spent`);
    const [mk, mu] = await pair("/otp/verify", { phone: OTHER, purpose, code: "123456" });
    assertEquals(mk, mu, `${purpose}: no challenge`);
    const [xk, xu] = await pair("/otp/verify", { phone: PHONE, purpose, code: "12345" });
    assertEquals(xk, xu, `${purpose}: malformed`);
    for (const [, text] of [rk, bk, sk, mk, xk]) {
      assert(!String(text).includes("account") && !String(text).includes("signup_ticket"));
    }
  }

  const r = rig();
  const code = await freshCode(r, PHONE, "device_activation");
  const sent = r.otp.sent.length, challenges = r.db.otp_challenges.length;
  for (let i = 0; i < 20; i++) {
    const res = await adopt(r, {
      signup_ticket: b64url.enc(await random(32 + (i % 3) * 40)),
      user_id: crypto.randomUUID(),
    });
    assertEquals([res.status, await body(res)], [400, INVALID]);
  }
  assertEquals(r.otp.sent.length, sent, "adopt sends no SMS");
  assertEquals(r.db.otp_challenges.length, challenges, "and opens no challenge");
  assertEquals(r.db.otp_challenges.at(-1)!.attempts, 0, "nor spends an attempt");
  assertEquals(r.db.users.size, 0, "and creates no one");
  const ok = await verify(r, { phone: PHONE, purpose: "device_activation", code });
  assertEquals((await body(ok)).account, "none", "the real code still works, once");
});

// ---------------------------------------------------------------- E-1005c-10
Deno.test("E-1005c-10 rule 4 on the sign-in door: no phone, code, sign-up ticket or activation ticket reaches console output across request → verify (none) → adopt → register", async () => {
  const r = rig();
  const lines: string[] = [];
  const names = ["log", "error", "warn", "info", "debug"] as const;
  const orig = Object.fromEntries(names.map((k) => [k, console[k]]));
  for (const k of names) {
    console[k] = (...a: unknown[]) => void lines.push(a.map(String).join(" "));
  }
  const seen: string[] = [];
  try {
    const ticket = await signupTicket(r, PHONE);
    seen.push(ticket);
    const out = await body(
      await adopt(r, { signup_ticket: ticket, user_id: crypto.randomUUID() }),
    );
    seen.push(out.ticket);
    await registerUnder(r, out.ticket);
    await adopt(r, { signup_ticket: ticket, user_id: crypto.randomUUID() });
    await adopt(r, { signup_ticket: "zz", user_id: "nope" });
  } finally {
    Object.assign(console, orig);
  }
  const joined = lines.join("\n");
  assert(!joined.includes("9812345670"), "no phone");
  for (const s of r.otp.sent) assert(!joined.includes(s.code), "no code");
  for (const s of seen) assert(!joined.includes(s), "no ticket");
});
