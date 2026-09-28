// The invite nonce is the inviter's, and the invitee is handed it (ADR 2026-09-25b §1–§2 🔒,
// 04 §6.1 as amended). Id E-25b-1 — the route + MemStore half; the PgStore half and the hostile
// queries (E-25b-2) live in tests/rls/invite_nonce.test.ts.
//
// The wire this suite pins:
//   GET  /sync-meta/invites        → {invites: [{invite_id, tenant_id, roles, expires_at, created_by,
//                                     status, nonce}]} — the caller's own invites at `sent`, or
//                                     accepted by the caller, inside the invite's 7-day window; every
//                                     row says which (`status` "sent" | "accepted") and the live ones
//                                     come first (⚠️ SPEC, repair of M11-INV1 review finding 1)
//   POST /sync-meta/invites/accept → {invite_id, status, nonce}
// `nonce` is base64url (unpadded, as every byte field on this wire), 16 bytes, and is exactly what
// the admin's device drew and signed into its `invite` record — the server stores and relays it
// and never chooses one.
import { assert, assertEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { phoneHmac } from "../_shared/phone.ts";
import { handler as meta } from "../sync-meta/index.ts";
import {
  advance,
  body,
  get,
  type Member,
  member,
  post,
  random,
  reissue,
  type Rig,
  rig,
  signedRecord,
} from "./harness.ts";

const INVITEE_PHONE = "+919876500031";
const OTHER_PHONE = "+919876500032";
const STRANGER_PHONE = "+919876500033";
const DAY = 86400_000;
const B64URL_16 = /^[A-Za-z0-9_-]{22}$/;

/** A user who is not in the inviting tenant, with an OTP-verified number. */
async function joiner(
  r: Rig,
  phone: string,
  status: "registered" | "certified" = "certified",
): Promise<Member> {
  const m = await member(r, r.db.addTenant(), null, null, { status });
  r.db.users.get(m.user)!.phone_hmac = await phoneHmac(r.deps.phoneHmacKey, phone);
  return m;
}

interface Fixture {
  r: Rig;
  tenant: string;
  book: string;
  admin: Member;
}
async function fixture(): Promise<Fixture> {
  const r = rig();
  const tenant = r.db.addTenant();
  const book = r.db.addBook(tenant);
  const admin = await member(r, tenant, book, "admin");
  return { r, tenant, book, admin };
}

/** The admin's device draws the nonce and signs it into the record (§1); the route relays it. */
async function issue(
  f: Fixture,
  nonce: Uint8Array | null,
  phone = INVITEE_PHONE,
  admin = f.admin,
  tenant = f.tenant,
  book = f.book,
): Promise<Response> {
  const payload: Record<string, unknown> = { roles: [{ book_id: book, role: "member" }] };
  if (nonce) payload.nonce = b64url.enc(nonce);
  const rec = await signedRecord(admin, tenant, "invite", payload);
  return await meta(
    post("/sync-meta/invites", { record: rec.wire, phone }, { token: admin.token }),
    f.r.deps,
  );
}

const offers = async (f: Fixture, m: Member) =>
  (await body(await meta(get("/sync-meta/invites", { token: m.token }), f.r.deps))).invites;
const accept = (f: Fixture, m: Member, id: string) =>
  meta(post("/sync-meta/invites/accept", { invite_id: id }, { token: m.token }), f.r.deps);

Deno.test("E-25b-1 GET /sync-meta/invites hands the invitee its invite's nonce — base64url, 16 bytes, byte-equal to what the inviter's device drew and signed, and to the stored row", async () => {
  const f = await fixture();
  const drawn = await random(16);
  const res = await issue(f, drawn);
  assertEquals(res.status, 200);
  const out = await body(res);

  // the server stored the inviter's nonce, not one of its own
  const row = f.r.db.invites.find((i) => i.id === out.invite_id)!;
  assertEquals(row.nonce, drawn, "stored as drawn");
  const rec = f.r.db.signed_records.find((s) => s.id === out.record_id)!;
  assertEquals(rec.payload_json.nonce, b64url.enc(drawn), "signed by the inviter's own key");

  const invitee = await joiner(f.r, INVITEE_PHONE);
  const list = await offers(f, invitee);
  assertEquals(list.length, 1);
  assertEquals(list[0].invite_id, out.invite_id);
  assertEquals(list[0].tenant_id, f.tenant);
  assert(B64URL_16.test(list[0].nonce), `nonce on the wire is ${list[0].nonce}`);
  assertEquals(b64url.dec(list[0].nonce), drawn, "relayed as drawn");
  assertEquals(list[0].nonce, rec.payload_json.nonce);
  // scope of the row is unchanged: the number and its HMAC still never travel (ADR 2026-09-05c §4)
  assertEquals(
    Object.keys(list[0]).sort(),
    ["created_by", "expires_at", "invite_id", "nonce", "roles", "status", "tenant_id"],
  );
  assertEquals(list[0].status, "sent", "a live offer says it is live");
});

Deno.test("E-25b-1 the server never chooses a nonce: an invite record without one is refused and mints no invite; two invites carry their own inviter-drawn nonces, never a shared or server one", async () => {
  const f = await fixture();
  const none = await issue(f, null);
  assertEquals(none.status, 400);
  assertEquals((await body(none)).check, "payload_json");
  assertEquals(f.r.db.invites.length, 0, "no invite without the inviter's nonce");

  // a second tenant invites the same number with its own nonce: each offer carries its own
  const other = f.r.db.addTenant();
  const otherBook = f.r.db.addBook(other);
  const otherAdmin = await member(f.r, other, otherBook, "admin");
  const n1 = await random(16), n2 = await random(16);
  const a = await body(await issue(f, n1));
  const b = await body(await issue(f, n2, INVITEE_PHONE, otherAdmin, other, otherBook));

  const invitee = await joiner(f.r, INVITEE_PHONE);
  const byId = new Map<string, string>(
    (await offers(f, invitee)).map((i: { invite_id: string; nonce: string }) => [
      i.invite_id,
      i.nonce,
    ]),
  );
  assertEquals(byId.size, 2);
  assertEquals(b64url.dec(byId.get(a.invite_id)!), n1);
  assertEquals(b64url.dec(byId.get(b.invite_id)!), n2);
});

Deno.test("E-25b-1 POST /sync-meta/invites/accept returns nonce beside invite_id and status — the same bytes the invite was issued with", async () => {
  const f = await fixture();
  const drawn = await random(16);
  const out = await body(await issue(f, drawn));
  const invitee = await joiner(f.r, INVITEE_PHONE);

  const res = await accept(f, invitee, out.invite_id);
  assertEquals(res.status, 200);
  const got = await body(res);
  assertEquals(Object.keys(got).sort(), ["invite_id", "nonce", "status"]);
  assertEquals(got.invite_id, out.invite_id);
  assertEquals(got.status, "joined_pending_verification", "never active: the ceremony grants that");
  assert(B64URL_16.test(got.nonce));
  assertEquals(b64url.dec(got.nonce), drawn);
});

Deno.test("E-25b-1 an accepted invite stays in the invitee's GET /sync-meta/invites with its nonce for the rest of its 7-day window — S9.2 survives a restart without a device copy — and drops out when the window closes", async () => {
  const f = await fixture();
  const drawn = await random(16);
  const out = await body(await issue(f, drawn));
  const invitee = await joiner(f.r, INVITEE_PHONE);
  assertEquals((await accept(f, invitee, out.invite_id)).status, 200);

  // "after a restart": a fresh session, nothing kept on the device, six days on
  advance(f.r, 6 * DAY);
  await reissue(f.r, invitee);
  const later = await offers(f, invitee);
  assertEquals(later.map((i: { invite_id: string }) => i.invite_id), [out.invite_id]);
  assertEquals(b64url.dec(later[0].nonce), drawn);
  assertEquals(later[0].status, "accepted", "the spent invite says so: it is not an offer");

  // past issue + 7 d the window is closed, for an accepted invite as for a live one
  advance(f.r, DAY + 1000);
  await reissue(f.r, invitee);
  assertEquals((await offers(f, invitee)).length, 0);
});

Deno.test("E-25b-1 a live offer is told from a spent one and comes first: a joiner who accepted tenant A's invite and holds tenant B's live one is offered B first (status sent), then A (status accepted) — so a screen that takes the first row with no invite id reaches B, and B accepts", async () => {
  const f = await fixture();
  const nA = await random(16), nB = await random(16);
  // A is issued, and accepted, first: it is the older row and its window closes first, so an
  // order by insertion or by expires_at alone would put the spent A ahead of the live B.
  const a = await body(await issue(f, nA));
  const invitee = await joiner(f.r, INVITEE_PHONE);
  assertEquals((await accept(f, invitee, a.invite_id)).status, 200);

  advance(f.r, DAY);
  await reissue(f.r, invitee);
  const tB = f.r.db.addTenant();
  const bookB = f.r.db.addBook(tB);
  const adminB = await member(f.r, tB, bookB, "admin");
  const b = await body(await issue(f, nB, INVITEE_PHONE, adminB, tB, bookB));

  const list = await offers(f, invitee);
  assertEquals(
    list.map((i: { invite_id: string; status: string }) => [i.invite_id, i.status]),
    [[b.invite_id, "sent"], [a.invite_id, "accepted"]],
    "the live offer first, each row marked",
  );
  assertEquals(b64url.dec(list[0].nonce), nB);
  assertEquals(b64url.dec(list[1].nonce), nA, "A keeps its nonce for S9.2");

  // what S0.9 does with no invite id — take the first row — now lands on the live one
  const res = await accept(f, invitee, list[0].invite_id);
  assertEquals(res.status, 200);
  assertEquals(b64url.dec((await body(res)).nonce), nB);

  // and once both are spent, no row claims to be an offer
  const spent = await offers(f, invitee);
  assertEquals(spent.length, 2);
  assert(spent.every((i: { status: string }) => i.status === "accepted"));
});

Deno.test("E-25b-1 only a live or self-accepted invite is offered: a superseded (revoked) invite and an expired one are not, and a spent re-accept returns no nonce", async () => {
  const f = await fixture();
  const first = await body(await issue(f, await random(16)));
  const n2 = await random(16);
  const second = await body(await issue(f, n2)); // 06 §7 one-tap re-invite revokes the first
  const invitee = await joiner(f.r, INVITEE_PHONE);

  const list = await offers(f, invitee);
  assertEquals(list.map((i: { invite_id: string }) => i.invite_id), [second.invite_id]);
  assert(!list.some((i: { invite_id: string }) => i.invite_id === first.invite_id));

  // the revoked one refuses at accept with no nonce in the body
  const stale = await accept(f, invitee, first.invite_id);
  assertEquals(stale.status, 409);
  assert(!("nonce" in await body(stale)));

  assertEquals((await accept(f, invitee, second.invite_id)).status, 200);
  const again = await accept(f, invitee, second.invite_id);
  assertEquals(again.status, 409);
  const againBody = await body(again);
  assertEquals(againBody.error, "invite_not_live");
  assert(!("nonce" in againBody), "a refusal never carries a nonce");

  // an invite the sweep expired is not offered, even to its own number
  const third = await body(await issue(f, await random(16), OTHER_PHONE));
  const other = await joiner(f.r, OTHER_PHONE);
  f.r.db.invites.find((i) => i.id === third.invite_id)!.status = "expired";
  assertEquals((await offers(f, other)).length, 0);
});

Deno.test("E-25b-1 scope is unchanged: a second phone, a co-admin of the inviting tenant, another tenant's admin and an uncertified stranger are offered nothing before or after acceptance, and a wrong-number accept is refused without a nonce", async () => {
  const f = await fixture();
  const drawn = await random(16);
  const out = await body(await issue(f, drawn));
  const invitee = await joiner(f.r, INVITEE_PHONE);
  const secondPhone = await joiner(f.r, OTHER_PHONE);
  const coAdmin = await member(f.r, f.tenant, f.book, "admin");
  const otherTenant = f.r.db.addTenant();
  const otherAdmin = await member(f.r, otherTenant, f.r.db.addBook(otherTenant), "admin");
  const rawStranger = await joiner(f.r, STRANGER_PHONE, "registered");
  const others = [secondPhone, coAdmin, otherAdmin, rawStranger, f.admin];

  const leaks = async (when: string) => {
    for (const m of others) {
      const res = await meta(get("/sync-meta/invites", { token: m.token }), f.r.deps);
      assertEquals(res.status, 200);
      const text = await res.text();
      assertEquals(JSON.parse(text).invites, [], `${when}: someone else is offered the invite`);
      assert(!text.includes(b64url.enc(drawn)), `${when}: the nonce leaked`);
    }
  };
  await leaks("before acceptance");

  const wrong = await accept(f, secondPhone, out.invite_id);
  assertEquals(wrong.status, 403);
  const wrongText = await wrong.text();
  assertEquals(JSON.parse(wrongText).error, "invite_not_for_you");
  assert(!wrongText.includes(b64url.enc(drawn)), "a refused accept carries no nonce");

  assertEquals((await accept(f, invitee, out.invite_id)).status, 200);
  await leaks("after acceptance");

  // and no claims at all: the route is closed before any store call
  const anon = await meta(get("/sync-meta/invites", {}), f.r.deps);
  assertEquals(anon.status, 401);
});
