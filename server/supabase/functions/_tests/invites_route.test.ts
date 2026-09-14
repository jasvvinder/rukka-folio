// The invite a second phone can actually accept — end to end over the edge routes (06 §7 🔒,
// ADR 2026-09-05d §9 🔒, ADR 2026-09-05c §4). Ids C-05d-9, E-06-30 … E-06-35.
//
// The wire this suite pins (0008's ⚠️ SPEC, the conservative reading of an open contract):
//   POST /sync-meta/invites        {record: signed `invite` {roles, nonce}, phone} → {invite_id}
//   GET  /sync-meta/invites                                → invites for MY OTP-verified number
//   POST /sync-meta/invites/accept {invite_id}              → joined_pending_verification
// The number travels once, is HMAC'd under the server key and is stored nowhere; the record never
// carries it, because the admin's device cannot compute the HMAC (the key is the server's).
import { assert, assertEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { mintAccessToken } from "../_shared/claims.ts";
import { phoneHmac } from "../_shared/phone.ts";
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

const INVITEE_PHONE = "+919876500011";
const OTHER_PHONE = "+919876500022";

/** A user who is not in `tenant` at all, with an OTP-verified number. */
async function joiner(r: Rig, phone: string): Promise<Member> {
  const elsewhere = r.db.addTenant();
  const m = await member(r, elsewhere, null, null);
  r.db.users.get(m.user)!.phone_hmac = await phoneHmac(r.deps.phoneHmacKey, phone);
  return m;
}

/** The admin's signed invite record: roles offered + the 128-bit ceremony nonce, and nothing else. */
async function inviteRecord(admin: Member, tenant: string, book: string, nonce?: Uint8Array) {
  return await signedRecord(admin, tenant, "invite", {
    roles: [{ book_id: book, role: "member" }],
    nonce: b64url.enc(nonce ?? await random(16)),
  });
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

async function issue(f: Fixture, phone = INVITEE_PHONE): Promise<Response> {
  const rec = await inviteRecord(f.admin, f.tenant, f.book);
  return await meta(
    post("/sync-meta/invites", { record: rec.wire, phone }, { token: f.admin.token }),
    f.r.deps,
  );
}

Deno.test("E-06-30 issue: an admin's signed `invite` record plus the invitee's number yields an invite whose only trace of the number is invitee_hmac — the plaintext is in no row, no record and no invite the wire hands back", async () => {
  const f = await fixture();
  const res = await issue(f);
  assertEquals(res.status, 200);
  const out = await body(res);

  const row = f.r.db.invites.find((i) => i.id === out.invite_id)!;
  assert(row, "the invite row exists");
  assertEquals(row.status, "sent");
  assertEquals(row.tenant_id, f.tenant);
  assertEquals(row.created_by, f.admin.user);
  assertEquals(row.source_record_id, out.record_id, "the row is a projection of the record");
  assertEquals((row.nonce as Uint8Array).length, 16, "06 §7: a 128-bit ceremony nonce");
  assertEquals(
    row.invitee_hmac,
    await phoneHmac(f.r.deps.phoneHmacKey, INVITEE_PHONE),
    "the number survives only as its server-keyed HMAC (ADR 2026-09-05c §4)",
  );
  assertEquals(
    (row.expires_at as Date).getTime() - (row.created_at as Date).getTime(),
    7 * 86400_000,
    "06 §7: a 7-day window, stamped server-side",
  );

  // rule 4: no plaintext number anywhere the server keeps — rows, signed records, or the response.
  const dump = JSON.stringify(
    [
      f.r.db.invites,
      f.r.db.signed_records.map((s) => ({ ...s, payload_bytes: undefined })),
      f.r.db.memberships,
      out,
    ],
    (_k, v) => typeof v === "bigint" ? v.toString() : v,
  );
  for (const shape of [INVITEE_PHONE, INVITEE_PHONE.slice(1), "9876500011"]) {
    assert(!dump.includes(shape), `the plaintext number reached the store as ${shape}`);
  }
  const record = f.r.db.signed_records.find((s) => s.id === out.record_id)!;
  assertEquals(Object.keys(record.payload_json).sort(), ["nonce", "roles"]);
});

Deno.test("E-06-31 issue is an admin power on a certified device: a plain member is refused not_admin, an uncertified admin device cannot author the record, and neither leaves an invite behind", async () => {
  const f = await fixture();
  const plain = await member(f.r, f.tenant, f.book, "member");
  const uncertified = await member(f.r, f.tenant, f.book, "admin", { status: "registered" });

  const asMember = await meta(
    post("/sync-meta/invites", {
      record: (await inviteRecord(plain, f.tenant, f.book)).wire,
      phone: INVITEE_PHONE,
    }, { token: plain.token }),
    f.r.deps,
  );
  assertEquals(asMember.status, 403);
  assertEquals((await body(asMember)).error, "not_admin");

  const asRaw = await meta(
    post("/sync-meta/invites", {
      record: (await inviteRecord(uncertified, f.tenant, f.book)).wire,
      phone: INVITEE_PHONE,
    }, { token: uncertified.token }),
    f.r.deps,
  );
  assertEquals(asRaw.status, 403);
  assertEquals((await body(asRaw)).error, "unauthorized");

  assertEquals(f.r.db.invites.length, 0);
  // the plain member's record was verified and stored (append-only, it is a signed fact) and says
  // why it was not applied; the uncertified device's never became a record at all
  const stored = f.r.db.signed_records;
  assertEquals(stored.length, 1);
  assertEquals(stored[0].author_device, plain.device.id);
  assertEquals(stored[0].apply_note, "rejected:not_admin");
});

Deno.test("E-06-32 a joiner is offered only the invites addressed to its OWN OTP-verified number; a second phone on the same tenant is offered nothing", async () => {
  const f = await fixture();
  await issue(f);
  const invitee = await joiner(f.r, INVITEE_PHONE);
  const other = await joiner(f.r, OTHER_PHONE);

  const mine = await body(
    await meta(get("/sync-meta/invites", { token: invitee.token }), f.r.deps),
  );
  assertEquals(mine.invites.length, 1);
  assertEquals(mine.invites[0].tenant_id, f.tenant);
  assertEquals(mine.invites[0].created_by, f.admin.user);
  assert(mine.invites[0].expires_at > 0);
  for (const leak of ["invitee_hmac", "nonce", "phone"]) {
    assert(!(leak in mine.invites[0]), `the offer leaks ${leak}`);
  }

  const theirs = await body(
    await meta(get("/sync-meta/invites", { token: other.token }), f.r.deps),
  );
  assertEquals(theirs.invites.length, 0, "a different number is offered nothing");
});

Deno.test("C-05d-9 the link alone admits nobody: a joiner with a different number on the same invite gets invite_not_for_you, byte-identical to the refusal for an invite id that does not exist; the matching number joins at joined_pending_verification (ADR 2026-09-05d §9)", async () => {
  const f = await fixture();
  const out = await body(await issue(f));
  const invitee = await joiner(f.r, INVITEE_PHONE);
  const wrongNumber = await joiner(f.r, OTHER_PHONE);

  // the same link, a different phone
  const refused = await meta(
    post("/sync-meta/invites/accept", { invite_id: out.invite_id }, {
      token: wrongNumber.token,
    }),
    f.r.deps,
  );
  assertEquals(refused.status, 403);
  const refusedBody = await refused.text();
  assertEquals(JSON.parse(refusedBody).error, "invite_not_for_you");

  // an invite that does not exist refuses identically — the route is no oracle for who was invited
  const unknown = await meta(
    post("/sync-meta/invites/accept", { invite_id: crypto.randomUUID() }, {
      token: wrongNumber.token,
    }),
    f.r.deps,
  );
  assertEquals(unknown.status, 403);
  assertEquals(await unknown.text(), refusedBody);

  // nothing moved: no membership for the wrong number, the invite is still live
  assertEquals(
    f.r.db.memberships.filter((m) => m.tenant_id === f.tenant && m.user_id === wrongNumber.user),
    [],
  );
  assertEquals(f.r.db.invites[0].status, "sent");

  // and the number the admin actually invited walks in
  const ok = await meta(
    post("/sync-meta/invites/accept", { invite_id: out.invite_id }, { token: invitee.token }),
    f.r.deps,
  );
  assertEquals(ok.status, 200);
  assertEquals((await body(ok)).status, "joined_pending_verification");
  const m = f.r.db.memberships.find((x) => x.tenant_id === f.tenant && x.user_id === invitee.user)!;
  assertEquals(m.status, "joined_pending_verification", "never active: the ceremony grants that");
  assertEquals(m.source_record_id, out.record_id, "the membership cites the admin's record");
});

Deno.test("E-06-33 an invite is spent once and lives 7 days: a second acceptance is invite_not_live, and an acceptance after the window is invite_expired with no membership", async () => {
  const f = await fixture();
  const out = await body(await issue(f));
  const invitee = await joiner(f.r, INVITEE_PHONE);
  const accept = (token: string) =>
    meta(
      post("/sync-meta/invites/accept", { invite_id: out.invite_id }, { token }),
      f.r.deps,
    );

  assertEquals((await accept(invitee.token)).status, 200);
  const again = await accept(invitee.token);
  assertEquals(again.status, 409);
  assertEquals((await body(again)).error, "invite_not_live");

  // a fresh invite, left to expire
  const second = await body(await issue(f));
  f.r.clock.now = new Date(f.r.clock.now.getTime() + 7 * 86400_000 + 1000);
  // a week later the joiner is on a fresh access token, so this is the invite's window expiring,
  // not the session's (06 §4)
  const later = await mintAccessToken(
    f.r.deps.jwtKey,
    invitee.claims,
    Math.floor(f.r.clock.now.getTime() / 1000),
  );
  const late = await meta(
    post("/sync-meta/invites/accept", { invite_id: second.invite_id }, { token: later }),
    f.r.deps,
  );
  assertEquals(late.status, 410);
  assertEquals((await body(late)).error, "invite_expired");
  assertEquals(
    f.r.db.invites.find((i) => i.id === second.invite_id)!.status,
    "expired",
    "lazy expiry binds at accept time, so a missed sweep never admits anyone",
  );
  // the expired offer is gone from the joiner's list too
  const offers = await body(
    await meta(get("/sync-meta/invites", { token: later }), f.r.deps),
  );
  assertEquals(offers.invites.length, 0);
});

Deno.test("E-06-34 the record is the authority: an `invite` record posted to /sync-meta/records is stored but not applied (rejected:invite_route), a replayed record does not mint a second invite, and a nonce that is not 128-bit is refused", async () => {
  const f = await fixture();
  const rec = await inviteRecord(f.admin, f.tenant, f.book);

  // the generic record route must not be a second way in — it has no number to HMAC
  const viaRecords = await body(
    await meta(
      post("/sync-meta/records", { records: [rec.wire] }, { token: f.admin.token }),
      f.r.deps,
    ),
  );
  assertEquals(viaRecords.results[0].result, "rejected:invite_route");
  assertEquals(f.r.db.invites.length, 0, "no invite without the invite route");
  assertEquals(f.r.db.signed_records.length, 1, "the signed fact is still kept (append-only)");

  // replaying that same record through the invite route does not mint an invite either
  const replay = await meta(
    post("/sync-meta/invites", { record: rec.wire, phone: INVITEE_PHONE }, {
      token: f.admin.token,
    }),
    f.r.deps,
  );
  assertEquals(replay.status, 409);
  assertEquals((await body(replay)).error, "record_replayed");
  assertEquals(f.r.db.invites.length, 0);

  // 06 §7: a 128-bit ceremony nonce, not whatever the client felt like
  const short = await inviteRecord(f.admin, f.tenant, f.book, new Uint8Array(32).fill(3));
  const bad = await meta(
    post("/sync-meta/invites", { record: short.wire, phone: INVITEE_PHONE }, {
      token: f.admin.token,
    }),
    f.r.deps,
  );
  assertEquals(bad.status, 400);
  assertEquals((await body(bad)).check, "payload_json");

  // and a number that is not E.164 never reaches the HMAC
  const rec2 = await inviteRecord(f.admin, f.tenant, f.book);
  const badPhone = await meta(
    post("/sync-meta/invites", { record: rec2.wire, phone: "98765" }, { token: f.admin.token }),
    f.r.deps,
  );
  assertEquals(badPhone.status, 400);
  assertEquals((await body(badPhone)).error, "bad_phone");
});

Deno.test("E-06-35 one-tap re-invite: issuing again to the same number revokes the live invite and mints a new one, so only the newest link can be accepted (06 §7)", async () => {
  const f = await fixture();
  const first = await body(await issue(f));
  const second = await body(await issue(f));
  const invitee = await joiner(f.r, INVITEE_PHONE);

  assertEquals(f.r.db.invites.find((i) => i.id === first.invite_id)!.status, "revoked");
  const stale = await meta(
    post("/sync-meta/invites/accept", { invite_id: first.invite_id }, { token: invitee.token }),
    f.r.deps,
  );
  assertEquals(stale.status, 409);
  assertEquals((await body(stale)).error, "invite_not_live");

  const fresh = await meta(
    post("/sync-meta/invites/accept", { invite_id: second.invite_id }, { token: invitee.token }),
    f.r.deps,
  );
  assertEquals(fresh.status, 200);
  assertEquals((await body(fresh)).status, "joined_pending_verification");
});
