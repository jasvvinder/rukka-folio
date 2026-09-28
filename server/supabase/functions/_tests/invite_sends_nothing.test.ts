// ADR 2026-09-25 §2 🔒 — the inviter sends the invitation from their own phone through the share
// sheet; **the server sends nothing** (amends 06 §7 and ADR 2026-09-05c §4). Id E-25-2.
//
// Creating an invite is watched three ways, and each watcher fails the test on its own:
//   1. deps.otp is a spy whose send() throws — no code, no link, no message of any kind leaves;
//   2. globalThis.fetch is a spy that throws — no provider is reached over the network either;
//   3. every store call is watched (the Tx behind withClaims is a Proxy): none may carry the
//      plaintext number in any shape and none may be a message/queue/notify call. The number
//      reaches the store only as `invitee_hmac`, beside the inviter's nonce — "the invitee's
//      number reaches the server once, only to be hashed".
// Fixtures are SYNTHETIC: a made-up number, random bytes for the nonce; no ledger content.
import { assert, assertEquals, assertFalse } from "@std/assert";
import { b64url, bytesEqual } from "../_shared/bytes.ts";
import type { OtpProvider } from "../_shared/otp/provider.ts";
import { phoneHmac } from "../_shared/phone.ts";
import type { Store, Tx } from "../_shared/store.ts";
import { handler as meta } from "../sync-meta/index.ts";
import {
  body,
  get,
  type Member,
  member,
  post,
  random,
  type Rig,
  rig,
  signedRecord,
} from "./harness.ts";

const INVITEE_PHONE = "+919876500033";
/** Every shape the plaintext could take on its way to a row: E.164, without the +, national. */
const SHAPES = [INVITEE_PHONE, INVITEE_PHONE.slice(1), INVITEE_PHONE.slice(3)];

/** True when `v` holds any of `shapes` — as a string, a number, or UTF-8 bytes — at any depth. */
function carries(v: unknown, shapes: string[], seen = new Set<unknown>()): boolean {
  if (v === null || v === undefined || typeof v === "function" || typeof v === "boolean") {
    return false;
  }
  if (typeof v === "string") return shapes.some((s) => v.includes(s));
  if (typeof v === "number" || typeof v === "bigint") return carries(String(v), shapes, seen);
  if (v instanceof Date) return false;
  if (v instanceof Uint8Array) {
    return carries(new TextDecoder("utf-8", { fatal: false }).decode(v), shapes, seen);
  }
  if (typeof v !== "object" || seen.has(v)) return false;
  seen.add(v);
  const items = v instanceof Map
    ? [...v.keys(), ...v.values()]
    : v instanceof Set
    ? [...v]
    : Array.isArray(v)
    ? v
    : Object.values(v);
  return items.some((x) => carries(x, shapes, seen));
}

interface Watch {
  calls: { method: string; args: unknown[] }[];
  otpSends: number;
  fetched: string[];
}

/** Puts the three watchers of the header on `r` and returns what they saw. */
function watch(r: Rig): Watch {
  const w: Watch = { calls: [], otpSends: 0, fetched: [] };
  const spyOtp: OtpProvider = {
    send() {
      w.otpSends++;
      throw new Error("E-25-2: the server asked a provider to send something");
    },
  };
  r.deps.otp = spyOtp;
  const inner = r.deps.store;
  const spyStore: Store = {
    withClaims(claims, fn) {
      w.calls.push({ method: "withClaims", args: [claims] });
      return inner.withClaims(claims, (tx) =>
        fn(
          new Proxy(tx, {
            get(target, prop) {
              const v = Reflect.get(target, prop);
              if (typeof v !== "function") return v;
              return (...args: unknown[]) => {
                w.calls.push({ method: String(prop), args });
                return v.apply(target, args);
              };
            },
          }) as Tx,
        ));
    },
  };
  r.deps.store = spyStore;
  return w;
}

async function withFetchSpy<T>(w: Watch, fn: () => Promise<T>): Promise<T> {
  const realFetch = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL) => {
    w.fetched.push(input instanceof Request ? input.url : String(input));
    return Promise.reject(new Error("E-25-2: an outbound network call"));
  }) as typeof fetch;
  try {
    return await fn();
  } finally {
    globalThis.fetch = realFetch;
  }
}

async function inviteRecord(admin: Member, tenant: string, book: string, nonce: Uint8Array) {
  return await signedRecord(admin, tenant, "invite", {
    roles: [{ book_id: book, role: "member" }],
    nonce: b64url.enc(nonce),
  });
}

const OUTBOUND = /send|message|outbound|notify|enqueue|queue|deliver|sms|whatsapp|link/i;

Deno.test("E-25-2 creating an invite sends nothing: no OTP or message provider call and no network call of any kind; the store is handed invitee_hmac and the inviter's nonce, never the number, and the number is in no row, record or response — on a first invite and on the one-tap re-invite", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const admin = await member(r, tenant, book, "admin");
  const hmac = await phoneHmac(r.deps.phoneHmacKey, INVITEE_PHONE);

  await t.step(
    "the watchers are not vacuous: the scanner finds the number in every shape it guards",
    () => {
      for (const s of SHAPES) {
        assert(carries({ a: [s] }, SHAPES), `string ${s}`);
        assert(carries(new Map([["k", new TextEncoder().encode(`x${s}x`)]]), SHAPES), `bytes ${s}`);
      }
      assert(carries(Number(INVITEE_PHONE.slice(3)), SHAPES), "as a number");
      assertFalse(carries({ hmac }, SHAPES), "the HMAC is not the number");
    },
  );

  const w = watch(r);
  let firstInvite = "";
  for (const round of ["first invite", "one-tap re-invite to the same number"]) {
    await t.step(round, async () => {
      const nonce = await random(16);
      const rec = await inviteRecord(admin, tenant, book, nonce);
      const from = w.calls.length;
      const res = await withFetchSpy(w, () =>
        meta(
          post("/sync-meta/invites", { record: rec.wire, phone: INVITEE_PHONE }, {
            token: admin.token,
          }),
          r.deps,
        ));
      assertEquals(res.status, 200);
      const text = await res.text();
      const out = JSON.parse(text);

      // 1 + 2: nothing was sent, by any provider, over any wire
      assertEquals(w.otpSends, 0, "no provider call");
      assertEquals(w.fetched, [], "no network call");

      // 3: what the store was handed
      const calls = w.calls.slice(from);
      const create = calls.filter((c) => c.method === "createInvite");
      assertEquals(create.length, 1, "the invite went through the watched store");
      const [recordId, inTenant, inHmac, , inNonce] = create[0].args as [
        string,
        string,
        Uint8Array,
        unknown,
        Uint8Array,
      ];
      assertEquals(recordId, out.record_id);
      assertEquals(inTenant, tenant);
      assert(bytesEqual(inHmac, hmac), "the number arrives as its server-keyed HMAC");
      assert(bytesEqual(inNonce, nonce), "and the nonce is the inviter's own");
      for (const c of calls) {
        assertFalse(OUTBOUND.test(c.method), `${c.method}: a store call that would send`);
        assertFalse(carries(c.args, SHAPES), `${c.method} was handed the plaintext number`);
      }

      // the row keeps the HMAC and the nonce, and nothing about delivery
      const row = r.db.invites.find((i) => i.id === out.invite_id)!;
      assert(row, "the invite row exists");
      assertEquals(row.status, "sent");
      assert(bytesEqual(row.invitee_hmac as Uint8Array, hmac));
      assert(bytesEqual(row.nonce as Uint8Array, nonce));
      for (const k of Object.keys(row)) {
        assertFalse(/phone|message|deliver|channel|outbound|sms|whatsapp|link|sent_at/i.test(k), k);
      }

      // and the number is nowhere the server keeps, nor in what it answered
      assertFalse(carries(text, SHAPES), "the response");
      assertFalse(carries(r.db, SHAPES), "a row, a record, a queue — anything in the database");

      if (!firstInvite) firstInvite = out.invite_id;
      else {
        assertEquals(
          r.db.invites.find((i) => i.id === firstInvite)!.status,
          "revoked",
          "06 §7: the re-invite supersedes the first — and still sent nothing",
        );
      }
    });
  }

  await t.step("the invitee finding and accepting it sends nothing either", async () => {
    const elsewhere = r.db.addTenant();
    const invitee = await member(r, elsewhere, null, null);
    r.db.users.get(invitee.user)!.phone_hmac = hmac;
    const offered = await withFetchSpy(
      w,
      async () =>
        await body(await meta(get("/sync-meta/invites", { token: invitee.token }), r.deps)),
    );
    assertEquals(offered.invites.length, 1);
    const accepted = await withFetchSpy(w, () =>
      meta(
        post("/sync-meta/invites/accept", { invite_id: offered.invites[0].invite_id }, {
          token: invitee.token,
        }),
        r.deps,
      ));
    assertEquals(accepted.status, 200);
    assertEquals((await body(accepted)).status, "joined_pending_verification");
    assertEquals(w.otpSends, 0);
    assertEquals(w.fetched, []);
    assertFalse(carries(r.db, SHAPES));
  });
});
