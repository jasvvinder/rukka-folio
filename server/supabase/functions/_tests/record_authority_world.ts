// Desk 83 (🔴 SECURITY, owner said go 3 Oct 2026): WHO may file a signed record, and who a record's
// projection may come from, is decided by the edge from what the DATABASE answers — rf.may_file_record,
// rf.is_tenant_admin, rf.book_access (SECURITY DEFINER, 0005/0022) — never from a count of the rows
// the caller happens to be able to see. Desk 89 (ADR 2026-10-03b, 0026) closed the last exception:
// device_revocation's k-of-n COUNT is the database's too (rf.revocation_count, rf.guardian_may_revoke),
// over the approvals filed in the guardian set's tenant (E-03b-1 … E-03b-9; the ignored E-06-94
// disjoint-guardians case asserted the opposite and is gone). Before desk 83 `applyRecord` took a founder's bootstrap from
// `membershipCount`, which on PgStore counts only VISIBLE memberships — zero, for a stranger — so
// POST /sync-meta/records answered `acked` to a cross-tenant join (E-06-86); and it admitted a book
// role from an admin of ANY book, and a role-less book's first role for anyone.
//
// One set of scenarios, two worlds: `memWorld` (MemStore, this directory's
// edge_record_authority.test.ts) and the Postgres world of tests/rls/edge_record_authority.test.ts
// (PgStore on the rf_api login, built by tests/rls/_pg_api.ts). The SAME assertions run on both, so
// the two stores answer the same — and every refusal is checked for the edge's own fingerprint:
//   * refused at intake: nothing stored, and the edge never asked the store to file the record
//     (`insertSignedRecord` absent from the call log) — the database would refuse it too, so only
//     the call log can tell that the EDGE decided;
//   * refused at apply: the record is stored (a signed fact, append-only), noted, and answered WITH
//     its `seq` — a refusal the store raised instead carries no seq and leaves the record unapplied
//     (sync-meta's StoreDenied arm) — and no projection was asked for.
// Remove an edge check and keep 0022: the call log and the seq both change, so the test fails.
//
// Ids E-06-91 … E-06-95, E-03b-1 … E-03b-9, E-03b-11, E-03b-12 (E-03b-6 is PgStore-only; E-03b-10
// and E-03b-13 are database-only, tests/rls/revocation_at_seq.test.ts). Fixtures are synthetic:
// random keys and ids; payloads carry ids and role names only — no ledger content, no phone number
// (CLAUDE.md rule 4; a phone HMAC here is random bytes).
import { assert, assertEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import type { GuardianSet } from "../_shared/store.ts";
import type { Store, Tx } from "../_shared/store.ts";
import { StoreDenied } from "../_shared/store.ts";
import { handler as meta } from "../sync-meta/index.ts";
import {
  body,
  edKeypair,
  get,
  type Member,
  post,
  random,
  reissue,
  type Rig,
  rig,
  signedRecord,
} from "./harness.ts";

/** A tenant whose founder is active and admin of their own personal book and of one business book. */
export interface Tn {
  t: string;
  founder: Member;
  personal: string;
  business: string;
}
export type MemberStatus = "active" | "joined_pending_verification" | "blocked" | "removed";
export interface Stored {
  applied: boolean;
  note: string | null;
}
/** The fixtures a scenario needs, written past every policy (the schema owner / the MemDb), and the
 *  fresh reads it checks. `r.deps.store` is the store under test, wrapped by `spy`; `store` is the
 *  same store unwrapped, for the direct-Tx arm (E-06-95). */
export interface World {
  readonly r: Rig;
  readonly store: Store;
  /** Every Tx method the handler called since the scenario last cleared it. */
  readonly calls: string[];
  tenant(): Promise<Tn>;
  /** A tenant row and nothing else — the founder's moment (06 §5). */
  emptyTenant(): Promise<string>;
  /** A user with one certified device, in no tenant. */
  person(): Promise<Member>;
  /** A second certified device of `m`'s user. */
  device(m: Member): Promise<Member>;
  /** `who` (or a new person) at `status` in `tn` — `active` after a verified ceremony. */
  member(tn: Tn, status: MemberStatus, who?: Member): Promise<Member>;
  setStatus(t: string, user: string, status: MemberStatus): Promise<void>;
  book(t: string, type: "business" | "personal", owner?: string): Promise<string>;
  role(book: string, user: string, role: string): Promise<void>;
  /** One envelope in `book`, pushed long ago by the tenant's founder (synthetic bytes). */
  envelope(tn: Tn, book: string): Promise<void>;
  /** book_usage.envelope_count of `book` set to `count` with NO envelope row — what a deleted
   *  envelope leaves behind (03 §2 erasure; ADR 2026-10-03b §5). */
  usage(t: string, book: string, count: number): Promise<void>;
  /** A guardian set at `version`, set up in `tenant` (ADR 2026-10-03b §1). `null` is a version
   *  published before 0026 — written past 0026's guard, as such a row was. */
  guardians(
    subject: string,
    version: number,
    k: number,
    guardians: Member[],
    tenant: string | null,
  ): Promise<void>;
  statusOf(t: string, user: string): Promise<string | null>;
  /** `user`'s phone HMAC (random bytes, set if the user has none) — what the edge would compute
   *  from the number an admin types (ADR 2026-09-05c §4), for an invite to that user. */
  phoneOf(user: string): Promise<Uint8Array>;
  rolesOf(book: string): Promise<string[]>;
  deviceStatus(device: string): Promise<string>;
  stored(record: string): Promise<Stored | null>;
  recordsIn(t: string): Promise<number>;
}

/** The store, with every Tx method call written to `calls` (name only — never an argument). */
export function spy(store: Store, calls: string[]): Store {
  return {
    withClaims: (claims, fn) =>
      store.withClaims(claims, (tx) =>
        fn(
          new Proxy(tx, {
            get(target, prop) {
              const v = Reflect.get(target, prop, target);
              if (typeof v !== "function") return v;
              return (...args: unknown[]) => {
                calls.push(String(prop));
                return (v as (...a: unknown[]) => unknown).apply(target, args);
              };
            },
          }) as Tx,
        )),
  };
}

// ---------------------------------------------------------------- the MemStore world
export function memWorld(): World {
  const r = rig();
  const store = r.deps.store;
  const calls: string[] = [];
  r.deps.store = spy(store, calls);
  const db = r.db;
  /** A certified device of `user` (a new user when null), with a token at the rig's clock. */
  const deviceOf = async (user: string | null): Promise<Member> => {
    const u = user ?? db.addUser().id;
    const keys = await edKeypair();
    const xpub = await random(32);
    const device = db.addDevice(u, keys.pub, xpub, "certified");
    const m: Member = {
      user: u,
      device,
      keys,
      xpub,
      claims: { user_id: u, device_id: device.id },
      token: "",
    };
    await reissue(r, m);
    return m;
  };
  const person = () => deviceOf(null);
  const w: World = {
    r,
    store,
    calls,
    async tenant() {
      const t = db.addTenant();
      const founder = await person();
      db.addMembership(t, founder.user, "active");
      const personal = db.addBook(t, "personal", founder.user);
      const business = db.addBook(t, "business");
      db.addRole(personal, founder.user, "admin");
      db.addRole(business, founder.user, "admin");
      return { t, founder, personal, business };
    },
    emptyTenant: () => Promise.resolve(db.addTenant()),
    person,
    device: (m) => deviceOf(m.user),
    async member(tn, status, who) {
      const p = who ?? await person();
      db.addMembership(tn.t, p.user, status);
      return p;
    },
    setStatus(t, user, status) {
      // The owner's UPDATE, which 0027's trigger logs on PgStore.
      const m = db.memberships.find((x) => x.tenant_id === t && x.user_id === user)!;
      db.writeMembership(t, user, status, (m.source_record_id as string | null) ?? null);
      return Promise.resolve();
    },
    book(t, type, owner) {
      return Promise.resolve(db.addBook(t, type, type === "personal" ? owner! : null));
    },
    role(book, user, role) {
      db.addRole(book, user, role);
      return Promise.resolve();
    },
    async envelope(tn, book) {
      const blob = await random(8);
      db.envelopes.push({
        envelope_id: crypto.randomUUID(),
        seq: ++db.seq,
        tenant_id: tn.t,
        book_id: book,
        object_id: crypto.randomUUID(),
        object_type: "entry",
        key_version: 1,
        suite_version: 1,
        payload_schema: 1,
        author_device: tn.founder.device.id,
        hlc: 1n,
        blob_hash: await random(32),
        size: blob.length,
        blob,
        blob_ref: null,
      });
    },
    usage(_t, book, count) {
      db.book_usage.set(book, count);
      return Promise.resolve();
    },
    guardians(subject, version, k, gs, tenant) {
      db.addGuardianSet(
        subject,
        version,
        k,
        gs.map((g) => ({ user_id: g.user, umk_pub_ed: g.keys.pub })),
        tenant,
      );
      return Promise.resolve();
    },
    statusOf(t, user) {
      const m = db.memberships.find((x) => x.tenant_id === t && x.user_id === user);
      return Promise.resolve((m?.status as string) ?? null);
    },
    async phoneOf(user) {
      const u = db.users.get(user)!;
      if (!u.phone_hmac) u.phone_hmac = await random(32);
      return u.phone_hmac;
    },
    rolesOf(book) {
      return Promise.resolve(
        db.book_roles.filter((x) => x.book_id === book).map((x) => `${x.user_id}:${x.role}`)
          .sort(),
      );
    },
    deviceStatus: (d) => Promise.resolve(db.devices.get(d)!.status),
    stored(id) {
      const s = db.signed_records.find((x) => x.id === id);
      return Promise.resolve(s ? { applied: !!s.applied_at, note: s.apply_note ?? null } : null);
    },
    recordsIn: (t) => Promise.resolve(db.signed_records.filter((x) => x.tenant_id === t).length),
  };
  return w;
}

// ---------------------------------------------------------------- posting and the edge's fingerprint
export interface Answer {
  id: string;
  result: string;
  seq?: string;
  check?: string;
}
export async function postWire(w: World, m: Member, wire: unknown): Promise<Answer> {
  const res = await meta(
    post("/sync-meta/records", { records: [wire] }, { token: m.token }),
    w.r.deps,
  );
  assertEquals(res.status, 200, "a per-record refusal is never a route failure");
  const out = await body(res);
  assertEquals(out.results.length, 1);
  return out.results[0] as Answer;
}
/** Sign and post one record, the call log cleared first. */
export async function send(
  w: World,
  m: Member,
  tenant: string,
  kind: string,
  payload: Record<string, unknown>,
) {
  const rec = await signedRecord(m, tenant, kind, payload);
  w.calls.length = 0;
  return { rec, out: await postWire(w, m, rec.wire) };
}

const PROJECTIONS = [
  "projectMembership",
  "projectBookRole",
  "projectDeviceStatus",
  "projectVerificationEvent",
  "createInvite",
];

/** Refused by the EDGE before it filed anything: the database's own answer, nothing stored, and the
 *  store never asked to insert. */
export async function refusedAtIntake(w: World, id: string, out: Answer, why: string) {
  assertEquals(out, { id, result: "rejected:unauthorized", check: "rls" }, why);
  assert(w.calls.includes("mayFileRecord"), `${why}: the edge asked rf.may_file_record`);
  assert(
    !w.calls.includes("insertSignedRecord"),
    `${why}: the edge refused before it asked the store to file (calls: ${w.calls.join(",")})`,
  );
  assertEquals(await w.stored(id), null, `${why}: nothing was stored`);
}

/** Refused by the EDGE after filing: stored and noted, answered with its seq, no projection asked. */
export async function refusedAtApply(
  w: World,
  id: string,
  out: Answer,
  result: string,
  check: string | undefined,
  why: string,
) {
  const want: Answer = { id, result, seq: out.seq };
  if (check !== undefined) want.check = check;
  assertEquals(out, want, why);
  assert(typeof out.seq === "string" && /^\d+$/.test(out.seq), `${why}: answered with its seq`);
  assertEquals(await w.stored(id), { applied: true, note: result }, `${why}: stored, noted`);
  const asked = w.calls.filter((c) => PROJECTIONS.includes(c));
  assertEquals(asked, [], `${why}: the edge asked the store for no projection`);
}

export async function acked(w: World, id: string, out: Answer, why: string) {
  assertEquals(out.result, "acked", `${why}: ${JSON.stringify(out)}`);
  assert(typeof out.seq === "string", `${why}: acked with seq`);
  const s = await w.stored(id);
  assertEquals(s?.applied, true, `${why}: applied`);
}

const revocation = (dev: Member, version = 1) => ({
  revoked_device_id: dev.device.id,
  subject_user_id: dev.user,
  share_set_version: version,
});

/** The store's refusal, by name: the whole transaction is a probe and rolls back. */
async function deniedBy(w: World, m: Member, fn: (tx: Tx) => Promise<unknown>): Promise<string> {
  try {
    await w.store.withClaims(m.claims, fn);
    return "ok";
  } catch (e) {
    if (e instanceof StoreDenied) return e.reason;
    throw e;
  }
}
/** File one record straight into the store (no edge), returning its id. */
async function fileIn(
  tx: Tx,
  m: Member,
  t: string,
  kind: string,
  payload: Record<string, unknown>,
) {
  const rec = await signedRecord(m, t, kind, payload);
  await tx.insertSignedRecord(rec.row);
  return rec.row.id;
}
/** rf.revocation_count as `m` reads it (0026). */
const countAs = (w: World, m: Member, dev: Member) =>
  w.store.withClaims(m.claims, (tx) => tx.revocationCount(dev.device.id));

// ================================================================ the scenarios

/** E-06-91 — intake: the edge asks rf.may_file_record before it files anything. */
export async function intake(w: World) {
  const a = await w.tenant(), b = await w.tenant();
  const removed = await w.member(b, "removed");
  const blocked = await w.member(b, "blocked");
  const pending = await w.member(b, "joined_pending_verification");
  const victim = await w.member(b, "active");
  const empty = await w.emptyTenant();
  const nowhere = crypto.randomUUID();
  const recordsB = await w.recordsIn(b.t);
  const nonce = b64url.enc(await random(16));
  const cases: [string, Member, string, string, Record<string, unknown>][] = [
    ["A's founder walks itself into B", a.founder, b.t, "membership_status", {
      user_id: a.founder.user,
      status: "joined_pending_verification",
    }],
    ["A's founder claims B's membership at active", a.founder, b.t, "membership_status", {
      user_id: a.founder.user,
      status: "active",
    }],
    ["A's founder announces a device in B", a.founder, b.t, "device_added", {
      device_id: a.founder.device.id,
    }],
    ["A's founder grants itself admin of B's book", a.founder, b.t, "book_role", {
      book_id: b.business,
      user_id: a.founder.user,
      role: "admin",
    }],
    ["A's founder removes B's member", a.founder, b.t, "member_removal", { user_id: victim.user }],
    ["A's founder revokes a device of B's member", a.founder, b.t, "device_revocation", {
      ...revocation(victim),
    }],
    ["A's founder files an invite into B", a.founder, b.t, "invite", { roles: [], nonce }],
    ["B's REMOVED member", removed, b.t, "device_added", { device_id: removed.device.id }],
    ["B's BLOCKED member", blocked, b.t, "device_added", { device_id: blocked.device.id }],
    [
      "a tenant that does not exist (the same answer — no existence oracle)",
      a.founder,
      nowhere,
      "membership_status",
      {
        user_id: a.founder.user,
        status: "active",
      },
    ],
    [
      "a memberless tenant takes the founder's membership_status and nothing else",
      a.founder,
      empty,
      "device_added",
      {
        device_id: a.founder.device.id,
      },
    ],
  ];
  for (const [why, m, t, kind, payload] of cases) {
    const { rec, out } = await send(w, m, t, kind, payload);
    await refusedAtIntake(w, rec.row.id, out, why);
  }
  assertEquals(await w.recordsIn(b.t), recordsB, "B gained no record");
  assertEquals(await w.statusOf(b.t, a.founder.user), null, "A's founder holds nothing in B");
  assertEquals(await w.statusOf(empty, a.founder.user), null);
  assertEquals(await w.deviceStatus(victim.device.id), "certified");

  // A member at joined_pending_verification belongs to the tenant (0022 (a), 06 §5 "every tenant").
  const ann = await send(w, pending, b.t, "device_added", { device_id: pending.device.id });
  await acked(w, ann.rec.row.id, ann.out, "a pending member announces its device");
  const label = await send(w, b.founder, b.t, "designation", { user_id: victim.user, label: "x" });
  await acked(w, label.rec.row.id, label.out, "B's founder files a designation");

  // Desk 68(a): a record already stored is answered as stored — the author's later removal does not
  // turn its own applied record into a refusal on a retry, and nothing is filed twice.
  await w.setStatus(b.t, pending.user, "removed");
  w.calls.length = 0;
  const again = await postWire(w, pending, ann.rec.wire);
  assertEquals(again, { id: ann.rec.row.id, result: "acked", seq: ann.out.seq }, "replay");
  assert(!w.calls.includes("mayFileRecord"), "a stored record is not re-judged at intake");
  assertEquals(await w.recordsIn(b.t), recordsB + 2);
}

/** E-06-92 — the founder of a memberless tenant is decided by the database, and only at `active`. */
export async function founder(w: World) {
  const b = await w.tenant();
  const plain = await w.member(b, "active");
  const pending = await w.member(b, "joined_pending_verification");
  const newbie = await w.person();

  const e1 = await w.emptyTenant();
  const f = await w.person();
  const ok = await send(w, f, e1, "membership_status", { user_id: f.user, status: "active" });
  await acked(w, ok.rec.row.id, ok.out, "the founder's own first membership, at active");
  assertEquals(await w.statusOf(e1, f.user), "active");
  // Intake asks rf.may_file_record of every new record (E-06-91), so its presence in the log alone
  // proves nothing about the founder check. The founder's "no member at all" is asked AGAIN at
  // apply: after the record is filed.
  const filed = w.calls.indexOf("insertSignedRecord");
  assert(
    filed >= 0 && w.calls.lastIndexOf("mayFileRecord") > filed,
    `the founder is the database's answer at apply, not intake's borrowed (calls: ${
      w.calls.join(",")
    })`,
  );

  // …and that second asking decides on a path intake never sees: a record already STORED is not
  // re-judged at intake (desk 68(a)), and one stored but never applied is applied on its replay
  // (sync-meta's duplicate arm). `late` filed its founding record while the tenant was empty, and
  // it was never applied (the state sync-meta's StoreDenied arm leaves); `first` then founded the
  // tenant. Replayed, `late`'s record still meets "own row null, status active, own user" — only
  // rf.may_file_record, asked at apply, says the tenant is no longer memberless. The edge refuses
  // it by name (stored, noted, seq, no projection asked); without that conjunct the store refuses
  // instead (no seq, the record left unapplied).
  const e3 = await w.emptyTenant();
  const late = await w.person(), first = await w.person();
  const lateRec = await signedRecord(late, e3, "membership_status", {
    user_id: late.user,
    status: "active",
  });
  await w.store.withClaims(late.claims, (tx) => tx.insertSignedRecord(lateRec.row));
  const won = await send(w, first, e3, "membership_status", {
    user_id: first.user,
    status: "active",
  });
  await acked(w, won.rec.row.id, won.out, "the tenant's first founder");
  w.calls.length = 0;
  const replay = await postWire(w, late, lateRec.wire);
  assert(
    w.calls.indexOf("mayFileRecord") > w.calls.indexOf("insertSignedRecord"),
    `intake did not re-judge the stored record; only apply asked (calls: ${w.calls.join(",")})`,
  );
  await refusedAtApply(
    w,
    lateRec.row.id,
    replay,
    "rejected:unauthorized",
    "not_admin",
    "a stored founding record replayed after another founded the tenant",
  );
  assertEquals(await w.statusOf(e3, late.user), null, "the late founder holds nothing");
  assertEquals(await w.statusOf(e3, first.user), "active");

  const e2 = await w.emptyTenant();
  const g = await w.person();
  const forOther = await send(w, g, e2, "membership_status", {
    user_id: newbie.user,
    status: "active",
  });
  await refusedAtApply(
    w,
    forOther.rec.row.id,
    forOther.out,
    "rejected:unauthorized",
    "not_admin",
    "founding a tenant FOR someone else",
  );
  assertEquals(await w.statusOf(e2, newbie.user), null);
  assertEquals(await w.statusOf(e2, g.user), null);

  for (const status of ["joined_pending_verification", "removed", "invited"]) {
    const e = await w.emptyTenant();
    const h = await w.person();
    const s = await send(w, h, e, "membership_status", { user_id: h.user, status });
    await refusedAtApply(
      w,
      s.rec.row.id,
      s.out,
      "rejected:unauthorized",
      "not_admin",
      `the founder's exception is active, never ${status} (0022 (b))`,
    );
    assertEquals(await w.statusOf(e, h.user), null);
  }

  const byPlain = await send(w, plain, b.t, "membership_status", {
    user_id: newbie.user,
    status: "joined_pending_verification",
  });
  await refusedAtApply(
    w,
    byPlain.rec.row.id,
    byPlain.out,
    "rejected:unauthorized",
    "not_admin",
    "B's active non-admin member",
  );
  const selfActive = await send(w, pending, b.t, "membership_status", {
    user_id: pending.user,
    status: "active",
  });
  await refusedAtApply(
    w,
    selfActive.rec.row.id,
    selfActive.out,
    "rejected:unauthorized",
    "not_admin",
    "a pending member of a tenant with members is no founder",
  );
  const removal = await send(w, plain, b.t, "member_removal", { user_id: pending.user });
  await refusedAtApply(
    w,
    removal.rec.row.id,
    removal.out,
    "rejected:unauthorized",
    "not_admin",
    "remove members — admin only (06 §1.0)",
  );
  assertEquals(await w.statusOf(b.t, newbie.user), null);
  assertEquals(await w.statusOf(b.t, pending.user), "joined_pending_verification");

  const byAdmin = await send(w, b.founder, b.t, "membership_status", {
    user_id: newbie.user,
    status: "joined_pending_verification",
  });
  await acked(w, byAdmin.rec.row.id, byAdmin.out, "B's admin walks a new person in");
  assertEquals(await w.statusOf(b.t, newbie.user), "joined_pending_verification");
}

/** E-06-93 — book roles: an admin OF THAT BOOK; its creator is the first (06 §1.0 🔒, 0022 (c)(d)). */
export async function bookRoles(w: World) {
  const a = await w.tenant(), b = await w.tenant();
  const other = await w.book(b.t, "business");
  const otherAdmin = await w.member(b, "active");
  await w.role(other, otherAdmin.user, "admin");
  const plain = await w.member(b, "active");
  await w.role(b.business, plain.user, "member");
  const pending = await w.member(b, "joined_pending_verification");
  const newbie = await w.member(b, "active");
  const fresh0 = await w.book(b.t, "business");
  const fresh1 = await w.book(b.t, "business");
  const mine = await w.book(b.t, "personal", plain.user);
  const used = await w.book(b.t, "business");
  await w.envelope(b, used);
  const businessRoles = await w.rolesOf(b.business);

  const role = (book: string, user: string, r: string | null) => ({
    book_id: book,
    user_id: user,
    role: r,
  });
  const refused: [string, Member, Record<string, unknown>, string][] = [
    [
      "the admin of ANOTHER book of B (a tenant admin) grants a role on B's business book",
      otherAdmin,
      role(b.business, newbie.user, "viewer"),
      b.business,
    ],
    [
      "a member of the book grants itself admin",
      plain,
      role(b.business, plain.user, "admin"),
      b.business,
    ],
    [
      "a PENDING member claims a role-less book",
      pending,
      role(fresh0, pending.user, "admin"),
      fresh0,
    ],
    [
      "the first role on a role-less book, given to SOMEONE ELSE",
      plain,
      role(fresh1, newbie.user, "admin"),
      fresh1,
    ],
    [
      "the first role on a role-less book, not admin",
      plain,
      role(fresh1, plain.user, "member"),
      fresh1,
    ],
    [
      "the tenant's founder claims a member's role-less PERSONAL book",
      b.founder,
      role(mine, b.founder.user, "admin"),
      mine,
    ],
    [
      "a role-less book that holds envelopes is not being created",
      plain,
      role(used, plain.user, "admin"),
      used,
    ],
  ];
  for (const [why, m, payload, book] of refused) {
    const before = await w.rolesOf(book);
    const s = await send(w, m, b.t, "book_role", payload);
    await refusedAtApply(w, s.rec.row.id, s.out, "rejected:unauthorized", "not_admin", why);
    assertEquals(await w.rolesOf(book), before, `${why}: no role moved`);
  }
  assertEquals(await w.rolesOf(b.business), businessRoles);

  // A book outside the record's tenant answers like a book that does not exist.
  for (
    const [why, book] of [["A's book named in B", a.business], [
      "a book that does not exist",
      crypto.randomUUID(),
    ]] as const
  ) {
    const s = await send(w, b.founder, b.t, "book_role", role(book, newbie.user, "viewer"));
    await refusedAtApply(w, s.rec.row.id, s.out, "rejected:unknown_book", undefined, why);
  }
  assertEquals(await w.rolesOf(a.business), [`${a.founder.user}:admin`]);

  const grant = await send(w, b.founder, b.t, "book_role", role(b.business, newbie.user, "viewer"));
  await acked(w, grant.rec.row.id, grant.out, "the book's admin grants");
  assertEquals((await w.rolesOf(b.business)).includes(`${newbie.user}:viewer`), true);
  const revoke = await send(w, b.founder, b.t, "book_role", role(b.business, newbie.user, null));
  await acked(w, revoke.rec.row.id, revoke.out, "the book's admin revokes");
  assertEquals(await w.rolesOf(b.business), businessRoles);

  const first = await send(w, plain, b.t, "book_role", role(fresh1, plain.user, "admin"));
  await acked(w, first.rec.row.id, first.out, "a role-less business book: its creator's own admin");
  assertEquals(await w.rolesOf(fresh1), [`${plain.user}:admin`]);
  const own = await send(w, plain, b.t, "book_role", role(mine, plain.user, "admin"));
  await acked(w, own.rec.row.id, own.out, "a role-less personal book: its OWNER's own admin");
  assertEquals(await w.rolesOf(mine), [`${plain.user}:admin`]);
  const next = await send(w, plain, b.t, "book_role", role(fresh1, newbie.user, "member"));
  await acked(w, next.rec.row.id, next.out, "…who, now its admin, grants");
}

/** E-06-94 — a device is revoked by its user, or that user's guardians, inside a tenant the user is in. */
export async function revocations(w: World) {
  const a = await w.tenant(), b = await w.tenant();
  const victim = await w.member(b, "active");
  const g1 = await w.member(b, "active");
  await w.member(a, "active", g1);
  const g2 = await w.member(b, "active");
  await w.member(a, "active", g2);
  const bystander = await w.member(b, "active");
  await w.guardians(victim.user, 1, 2, [g1, g2], b.t);

  const by = await send(w, bystander, b.t, "device_revocation", revocation(victim));
  await refusedAtApply(
    w,
    by.rec.row.id,
    by.out,
    "rejected:unauthorized",
    "not_revoker",
    "a fellow member who is no guardian",
  );
  const first = await send(w, g1, b.t, "device_revocation", revocation(victim));
  await acked(
    w,
    first.rec.row.id,
    first.out,
    "the first guardian, in the subject's tenant, counted",
  );
  assertEquals(await w.deviceStatus(victim.device.id), "certified", "one of two is not enough");
  const elsewhere = await send(w, g2, a.t, "device_revocation", revocation(victim));
  await refusedAtApply(
    w,
    elsewhere.rec.row.id,
    elsewhere.out,
    "rejected:unauthorized",
    "not_revoker",
    "the completing guardian, on a record of a tenant the subject is NOT in (0022 (e)) — nor the set's (ADR 2026-10-03b §2)",
  );
  assertEquals(await w.deviceStatus(victim.device.id), "certified");
  const done = await send(w, g2, b.t, "device_revocation", revocation(victim));
  await acked(w, done.rec.row.id, done.out, "the completing guardian, in the subject's tenant");
  assertEquals(await w.deviceStatus(victim.device.id), "revoked", "k of n revoked");

  const second = await w.device(bystander);
  const mine = await send(w, bystander, b.t, "device_revocation", revocation(second));
  await acked(w, mine.rec.row.id, mine.out, "the owner revokes its own other device");
  assertEquals(await w.deviceStatus(second.device.id), "revoked");
}

/** E-06-95 — without the edge, the store itself holds 0022 — the same refusal on both stores. */
export async function storeHolds(w: World) {
  const a = await w.tenant(), b = await w.tenant();
  const plain = await w.member(b, "active");
  const pending = await w.member(b, "joined_pending_verification");
  const removed = await w.member(b, "removed");
  const otherAdmin = await w.member(b, "active");
  const other = await w.book(b.t, "business");
  await w.role(other, otherAdmin.user, "admin");
  const empty = await w.emptyTenant();
  const stranger = await w.person();

  // rf.may_file_record, asked directly (0022 §1).
  const may = async (m: Member, t: string, kind: string) =>
    await w.store.withClaims(m.claims, (tx) => tx.mayFileRecord(t, kind));
  const table: [string, Member, string, string, boolean][] = [
    ["B's active member", plain, b.t, "device_added", true],
    ["B's pending member", pending, b.t, "device_added", true],
    ["B's removed member", removed, b.t, "device_added", false],
    ["A's founder in B", a.founder, b.t, "membership_status", false],
    [
      "a stranger, memberless tenant, membership_status",
      stranger,
      empty,
      "membership_status",
      true,
    ],
    ["a stranger, memberless tenant, any other kind", stranger, empty, "device_added", false],
    ["a tenant that does not exist", stranger, crypto.randomUUID(), "membership_status", false],
  ];
  for (const [why, m, t, kind, want] of table) assertEquals(await may(m, t, kind), want, why);

  const denied = (m: Member, fn: (tx: Tx) => Promise<unknown>) => deniedBy(w, m, fn);
  const file = (tx: Tx, m: Member, t: string, kind: string) => fileIn(tx, m, t, kind, {});
  assertEquals(await denied(a.founder, (tx) => file(tx, a.founder, b.t, "device_added")), "rls");
  assertEquals(
    await denied(
      plain,
      async (tx) =>
        tx.projectMembership(
          await file(tx, plain, b.t, "membership_status"),
          b.t,
          a.founder.user,
          "joined_pending_verification",
        ),
    ),
    "not_admin",
    "a membership changes only on an admin's record",
  );
  assertEquals(
    await denied(
      otherAdmin,
      async (tx) =>
        tx.projectBookRole(
          await file(tx, otherAdmin, b.t, "book_role"),
          b.business,
          plain.user,
          "viewer",
          null,
        ),
    ),
    "not_admin",
    "a book role only by an admin of THAT book",
  );
  assertEquals(
    await denied(
      plain,
      async (tx) =>
        tx.projectDeviceStatus(
          await file(tx, plain, b.t, "device_revocation"),
          b.t,
          plain.device.id,
          "certified",
        ),
    ),
    "revoke_only",
    "a device record only ever revokes",
  );
  assertEquals(
    await denied(
      plain,
      async (tx) =>
        tx.projectDeviceStatus(
          await file(tx, plain, b.t, "device_revocation"),
          b.t,
          otherAdmin.device.id,
          "revoked",
        ),
    ),
    "not_revoker",
    "a fellow member is no revoker",
  );
  assertEquals(await w.deviceStatus(otherAdmin.device.id), "certified");
  assertEquals(await w.rolesOf(b.business), [`${b.founder.user}:admin`]);
  assertEquals(await w.statusOf(b.t, a.founder.user), null);
}

// ================================================================ desk 89 — ADR 2026-10-03b (0026)

/** E-03b-1 — an approval filed outside the set's tenant never counts (ADR 2026-10-03b §2): the
 *  subject, g1 and g2 are all in A and B and the set was set up in B. g1's approval in A — a tenant
 *  the subject IS in, which 0022 (e) alone would have admitted — is refused not_revoker, and the
 *  database's own count does not see it either: one approval in B is "1 of 2", and the store
 *  refuses to project on it. g1's approval in B completes the revocation. */
export async function filedElsewhere(w: World) {
  const a = await w.tenant(), b = await w.tenant();
  const subject = await w.member(a, "active");
  await w.member(b, "active", subject);
  const g1 = await w.member(a, "active");
  await w.member(b, "active", g1);
  const g2 = await w.member(a, "active");
  await w.member(b, "active", g2);
  await w.guardians(subject.user, 1, 2, [g1, g2], b.t);

  const inA = await send(w, g1, a.t, "device_revocation", revocation(subject));
  await refusedAtApply(
    w,
    inA.rec.row.id,
    inA.out,
    "rejected:unauthorized",
    "not_revoker",
    "g1's approval filed in A — a tenant the subject is in, not the one the set was set up in",
  );
  const inB = await send(w, g2, b.t, "device_revocation", revocation(subject));
  await acked(w, inB.rec.row.id, inB.out, "g2's approval, filed in the set's tenant");
  assertEquals(
    await w.stored(inB.rec.row.id),
    { applied: true, note: "counted 1 of 2" },
    "g1's approval in A is not counted toward k",
  );
  assertEquals(await w.deviceStatus(subject.device.id), "certified", "one of two is not enough");
  assertEquals(
    await countAs(w, subject, subject),
    { approvers: 1, k: 2, effective_seq: null },
    "rf.revocation_count over EVERY approval: the one in A is not among them",
  );

  // Without the edge, the database holds the same rule (0026 rf.project_device_status).
  assertEquals(
    await deniedBy(
      w,
      g1,
      (tx) => tx.projectDeviceStatus(inA.rec.row.id, a.t, subject.device.id, "revoked"),
    ),
    "not_revoker",
    "g1 projects on its record of A",
  );
  assertEquals(
    await deniedBy(
      w,
      g2,
      (tx) => tx.projectDeviceStatus(inB.rec.row.id, b.t, subject.device.id, "revoked"),
    ),
    "not_revoker",
    "one counted approval of two is not k — the database counts, it no longer trusts the caller",
  );
  assertEquals(await w.deviceStatus(subject.device.id), "certified");

  const done = await send(w, g1, b.t, "device_revocation", revocation(subject));
  await acked(w, done.rec.row.id, done.out, "g1's approval, filed in the set's tenant");
  assertEquals(
    await w.stored(done.rec.row.id),
    { applied: true, note: `revoked by guardians 2 of 2 at seq ${done.out.seq}` },
    "k distinct guardians, both filed in B; the cut-off is the k-th counted record's seq",
  );
  assertEquals(await w.deviceStatus(subject.device.id), "revoked");
}

/** E-03b-2 — guardians who file in different tenants do not complete (ADR 2026-10-03b §2; replaces
 *  the ignored E-06-94 disjoint-guardians case, which asserted the opposite). The subject is in A
 *  and B; the set was set up in A, where both guardians were; g2 has since left A. g1 files in A,
 *  g2 in B — a tenant the subject is in — and the revocation does NOT complete. A set published
 *  before 0026 (no tenant) counts nothing, wherever its guardians file (§1). */
export async function differentTenants(w: World) {
  const a = await w.tenant(), b = await w.tenant();
  const subject = await w.member(a, "active");
  await w.member(b, "active", subject);
  const g1 = await w.member(a, "active");
  const g2 = await w.member(a, "active");
  await w.member(b, "active", g2);
  await w.guardians(subject.user, 1, 2, [g1, g2], a.t);
  await w.setStatus(a.t, g2.user, "removed"); // g1 only in A, g2 only in B: the old disjoint layout

  const first = await send(w, g1, a.t, "device_revocation", revocation(subject));
  await acked(w, first.rec.row.id, first.out, "g1, in A, the set's tenant");
  assertEquals(await w.stored(first.rec.row.id), { applied: true, note: "counted 1 of 2" });
  const second = await send(w, g2, b.t, "device_revocation", revocation(subject));
  await refusedAtApply(
    w,
    second.rec.row.id,
    second.out,
    "rejected:unauthorized",
    "not_revoker",
    "g2 files in B — a tenant the subject is in, but not the set's",
  );
  assertEquals(await w.deviceStatus(subject.device.id), "certified", "no completion (§2)");
  assertEquals(await countAs(w, g1, subject), { approvers: 1, k: 2, effective_seq: null });

  const legacy = await w.member(a, "active");
  const h1 = await w.member(a, "active"), h2 = await w.member(a, "active");
  await w.guardians(legacy.user, 1, 2, [h1, h2], null);
  for (const h of [h1, h2]) {
    const s = await send(w, h, a.t, "device_revocation", revocation(legacy));
    await refusedAtApply(
      w,
      s.rec.row.id,
      s.out,
      "rejected:unauthorized",
      "not_revoker",
      "a guardian of a set with no tenant (published before 0026)",
    );
  }
  assertEquals(await w.deviceStatus(legacy.device.id), "certified");
  assertEquals(await countAs(w, legacy, legacy), { approvers: 0, k: null, effective_seq: null });
}

/** E-03b-3 — a guardian still pending in the set's tenant revokes (ADR 2026-10-03b §3): its
 *  approval counts and, as the k-th, completes the revocation — answered by the database, since it
 *  cannot see the subject's membership row. Hostile callers stay refused: a stranger and a guardian
 *  since removed from the tenant at intake (rls); a pending NON-guardian and a guardian of another
 *  subject at apply (not_revoker); and neither the stranger nor another subject's guardian reads the
 *  count. */
export async function pendingGuardian(w: World) {
  const t = await w.tenant();
  const subject = await w.member(t, "active");
  const g1 = await w.member(t, "active");
  const g2 = await w.member(t, "joined_pending_verification");
  const g3 = await w.member(t, "active");
  await w.guardians(subject.user, 1, 2, [g1, g2, g3], t.t); // n = 3, k = 2
  const other = await w.member(t, "active");
  const x = await w.member(t, "active"), y = await w.member(t, "active");
  await w.guardians(other.user, 1, 2, [x, y], t.t);
  const pendingStranger = await w.member(t, "joined_pending_verification");
  await w.setStatus(t.t, g3.user, "removed");
  const stranger = await w.person();

  for (
    const [why, m] of [["a stranger", stranger], [
      "a guardian removed from the tenant",
      g3,
    ]] as const
  ) {
    const s = await send(w, m, t.t, "device_revocation", revocation(subject));
    await refusedAtIntake(w, s.rec.row.id, s.out, why);
  }
  for (
    const [why, m] of [
      ["a pending member who is no guardian", pendingStranger],
      ["a guardian of ANOTHER subject", x],
    ] as const
  ) {
    const s = await send(w, m, t.t, "device_revocation", revocation(subject));
    await refusedAtApply(w, s.rec.row.id, s.out, "rejected:unauthorized", "not_revoker", why);
  }
  assertEquals(await w.deviceStatus(subject.device.id), "certified");

  const first = await send(w, g1, t.t, "device_revocation", revocation(subject));
  await acked(w, first.rec.row.id, first.out, "an active guardian");
  assertEquals(await w.stored(first.rec.row.id), { applied: true, note: "counted 1 of 2" });
  const done = await send(w, g2, t.t, "device_revocation", revocation(subject));
  await acked(w, done.rec.row.id, done.out, "the PENDING guardian completes k");
  assert(w.calls.includes("guardianMayRevoke"), "the edge asked the database, not the rows");
  assertEquals(
    await w.stored(done.rec.row.id),
    { applied: true, note: `revoked by guardians 2 of 2 at seq ${done.out.seq}` },
  );
  assertEquals(await w.deviceStatus(subject.device.id), "revoked");
  assertEquals(
    await countAs(w, g2, subject),
    { approvers: 2, k: 2, effective_seq: BigInt(done.out.seq!) },
    "a pending guardian reads the count",
  );
  for (const m of [stranger, x, pendingStranger]) {
    assertEquals(
      await countAs(w, m, subject),
      { approvers: 0, k: null, effective_seq: null },
      "the count is the device owner's and their guardians' — anyone else reads the empty count",
    );
  }
}

/** E-03b-7 — the SUBJECT's membership in the set's tenant is judged at each approval's own seq
 *  (ADR 2026-10-03b §6, owner-ruled 3 Oct 2026, desk 97; 0027 rf.subject_held_at over
 *  membership_facts) — the reading of the subject's own devices (sync_engine revocation.dart
 *  countRevocation, D-03b-5/7/8). k = 3 of 4. Two approvals are filed while the subject is in the
 *  set's tenant: 2 of 3. The tenant's admin then removes the subject on a signed record, and the two
 *  KEEP counting — a later removal never un-counts an approval already filed (ADR 2026-09-06 §3: the
 *  cut-off only moves earlier). Someone else then joins the tenant: the history is the subject's,
 *  so g3, filing next, files while the SUBJECT is removed — refused not_revoker, stored.
 *  The admin re-admits the subject: g3's approval still never counts, by the edge, by the count and
 *  by the store's own projection. A removal in ANOTHER tenant changes nothing, and neither does the
 *  newcomer's removal in this one. g3 files again after the re-admission — its earlier approval
 *  never counted, so it does not shadow this one — and completes k at this approval's seq.
 *  Mutants this kills: the subject's CURRENT membership (0026: the count reads empty after the
 *  removal, and g3's removed-time approval counts after the re-admission); no subject clause at all
 *  (g3's removed-time approval is acked and revokes); a history keyed by tenant but not by USER
 *  (desk 97 review, finding 3: the newcomer's join makes g3's first approval count, and the
 *  newcomer's removal refuses g3's second). */
export async function subjectRemoved(w: World) {
  const t = await w.tenant(), elsewhere = await w.tenant();
  const subject = await w.member(t, "active");
  await w.member(elsewhere, "active", subject); // the subject, and its device, live on elsewhere
  const g1 = await w.member(t, "active"), g2 = await w.member(t, "active");
  const g3 = await w.member(t, "active"), g4 = await w.member(t, "active");
  await w.guardians(subject.user, 1, 3, [g1, g2, g3, g4], t.t); // n = 4, k = 3

  for (const [g, n] of [[g1, 1], [g2, 2]] as const) {
    const s = await send(w, g, t.t, "device_revocation", revocation(subject));
    await acked(w, s.rec.row.id, s.out, `approval ${n}, the subject still in the set's tenant`);
    assertEquals(await w.stored(s.rec.row.id), { applied: true, note: `counted ${n} of 3` });
  }
  assertEquals(await countAs(w, g1, subject), { approvers: 2, k: 3, effective_seq: null });

  // The set's tenant removes the subject — a membership fact, at its own seq.
  const out = await send(w, t.founder, t.t, "member_removal", { user_id: subject.user });
  await acked(w, out.rec.row.id, out.out, "the set's tenant's admin removes the subject");
  assertEquals(await w.statusOf(t.t, subject.user), "removed");
  assertEquals(
    await countAs(w, g1, subject),
    { approvers: 2, k: 3, effective_seq: null },
    "a later removal never un-counts the approvals filed while the subject was there",
  );

  // Someone else joins the set's tenant: the latest change there, and not the subject's.
  const newcomer = await w.person();
  const joins = await send(w, t.founder, t.t, "membership_status", {
    user_id: newcomer.user,
    status: "joined_pending_verification",
  });
  await acked(w, joins.rec.row.id, joins.out, "a newcomer joins the set's tenant");

  const third = await send(w, g3, t.t, "device_revocation", revocation(subject));
  await refusedAtApply(
    w,
    third.rec.row.id,
    third.out,
    "rejected:unauthorized",
    "not_revoker",
    "an approval filed in the set's tenant while the subject is removed there",
  );
  assert(w.calls.includes("guardianMayRevoke"), "the edge asked the database, not the rows");
  assertEquals(
    await countAs(w, g1, subject),
    { approvers: 2, k: 3, effective_seq: null },
    "the removed-time approval is not counted",
  );

  // Re-admitted (06 §7: removed → joined_pending_verification, an admin's membership_status).
  const back = await send(w, t.founder, t.t, "membership_status", {
    user_id: subject.user,
    status: "joined_pending_verification",
  });
  await acked(w, back.rec.row.id, back.out, "the set's tenant's admin re-admits the subject");
  assertEquals(
    await countAs(w, g1, subject),
    { approvers: 2, k: 3, effective_seq: null },
    "g3's approval was filed while the subject was removed: it never counts, not after a re-admission either",
  );
  assertEquals(
    await deniedBy(
      w,
      g3,
      (tx) => tx.projectDeviceStatus(third.rec.row.id, t.t, subject.device.id, "revoked"),
    ),
    "not_revoker",
    "without the edge: the store's own count does not take the removed-time approval either",
  );
  assertEquals(await w.deviceStatus(subject.device.id), "certified");

  // A removal in another tenant bears on nothing here.
  const gone = await send(w, elsewhere.founder, elsewhere.t, "member_removal", {
    user_id: subject.user,
  });
  await acked(w, gone.rec.row.id, gone.out, "another tenant removes the subject");
  // …and neither does another member's removal in this one.
  const left = await send(w, t.founder, t.t, "member_removal", { user_id: newcomer.user });
  await acked(w, left.rec.row.id, left.out, "the newcomer is removed from the set's tenant");

  const again = await send(w, g3, t.t, "device_revocation", revocation(subject));
  await acked(w, again.rec.row.id, again.out, "g3 files again after the re-admission");
  assertEquals(
    await w.stored(again.rec.row.id),
    { applied: true, note: `revoked by guardians 3 of 3 at seq ${again.out.seq}` },
    "g1, g2 and g3's second approval: k at this approval's seq",
  );
  assertEquals(await countAs(w, g1, subject), {
    approvers: 3,
    k: 3,
    effective_seq: BigInt(again.out.seq!),
  });
  assertEquals(await w.deviceStatus(subject.device.id), "revoked");
}

/** E-03b-9 — a membership record the server REFUSED is not a membership fact (0027 §1; ⚠️ SPEC (a)
 *  in 0027's header). Only a write of the memberships row is a fact: the server stores and
 *  serves a refused record like any other, so reading the records would let a member who is not an
 *  admin — or a thief on the subject's own stolen device — file the subject's "removal", refused,
 *  and stop every later guardian approval from counting. Both are refused not_admin and stored; the
 *  subject stays active; the guardians' approvals filed after them count and revoke the device.
 *  (The subject's own devices still take a refused record as a fact — they cannot judge admin
 *  authority, M13-REV89C — so here they do not wipe; the server, the operative stop, revokes.) */
export async function refusedRemoval(w: World) {
  const t = await w.tenant();
  const subject = await w.member(t, "active");
  const plain = await w.member(t, "active"); // a member, not an admin of any book
  const g1 = await w.member(t, "active"), g2 = await w.member(t, "active");
  await w.guardians(subject.user, 1, 2, [g1, g2], t.t); // n = 2, k = 2

  const rm = await send(w, plain, t.t, "member_removal", { user_id: subject.user });
  await refusedAtApply(
    w,
    rm.rec.row.id,
    rm.out,
    "rejected:unauthorized",
    "not_admin",
    "a member who is not an admin files the subject's removal",
  );
  const self = await send(w, subject, t.t, "membership_status", {
    user_id: subject.user,
    status: "removed",
  });
  await refusedAtApply(
    w,
    self.rec.row.id,
    self.out,
    "rejected:unauthorized",
    "not_admin",
    "the subject's own (stolen) device files its own removal",
  );
  assertEquals(await w.statusOf(t.t, subject.user), "active", "neither was applied");

  const first = await send(w, g1, t.t, "device_revocation", revocation(subject));
  await acked(w, first.rec.row.id, first.out, "g1 files after the two refused removals");
  assertEquals(await w.stored(first.rec.row.id), { applied: true, note: "counted 1 of 2" });
  const done = await send(w, g2, t.t, "device_revocation", revocation(subject));
  await acked(w, done.rec.row.id, done.out, "g2 completes k");
  assertEquals(
    await w.stored(done.rec.row.id),
    { applied: true, note: `revoked by guardians 2 of 2 at seq ${done.out.seq}` },
  );
  assertEquals(await w.deviceStatus(subject.device.id), "revoked");
}

/** E-03b-11 — a membership change is a fact when it is APPLIED, never at its record's seq (desk 97
 *  review, finding 1; 0027 §1). A record can be applied long after it was filed: sync-meta's
 *  duplicate arm applies a stored record that was never applied when it is re-sent (`rec = stored`
 *  — the seat cap's refusal leaves one so, E-05g-16), and an admin can call the projection on any
 *  older record of its own device in the tenant (rf.require_record checks only device and tenant).
 *  Dated at the record, a late re-admission counts approvals refused not_revoker while the subject
 *  was removed — here 2 of 2 with the device left certified, since no request remains to revoke it
 *  — and a late removal un-counts an approval filed while the subject was there. Neither may.
 *  Mutant this kills: the fact stamped with the applying record's seq (0027 as first built). */
export async function lateApplication(w: World) {
  const t = await w.tenant();
  const subject = await w.member(t, "active");
  const g1 = await w.member(t, "active"), g2 = await w.member(t, "active");
  await w.guardians(subject.user, 1, 2, [g1, g2], t.t); // n = 2, k = 2

  const out = await send(w, t.founder, t.t, "member_removal", { user_id: subject.user });
  await acked(w, out.rec.row.id, out.out, "the set's tenant's admin removes the subject");
  // The admin's re-admission is filed and stored, never applied — the state sync-meta's StoreDenied
  // arm leaves (a full plan's seat_cap).
  const readmit = await signedRecord(t.founder, t.t, "membership_status", {
    user_id: subject.user,
    status: "joined_pending_verification",
  });
  await w.store.withClaims(t.founder.claims, (tx) => tx.insertSignedRecord(readmit.row));
  for (const [g, n] of [[g1, 1], [g2, 2]] as const) {
    const s = await send(w, g, t.t, "device_revocation", revocation(subject));
    await refusedAtApply(
      w,
      s.rec.row.id,
      s.out,
      "rejected:unauthorized",
      "not_revoker",
      `approval ${n}, filed while the subject is removed`,
    );
  }
  // A seat frees; the admin's device re-sends the record, and the duplicate arm applies it NOW.
  w.calls.length = 0;
  const replay = await postWire(w, t.founder, readmit.wire);
  await acked(w, readmit.row.id, replay, "the stored re-admission, applied on its re-send");
  assert(w.calls.includes("projectMembership"), "the re-send applied the stored record");
  assertEquals(await w.statusOf(t.t, subject.user), "joined_pending_verification");
  assertEquals(
    await countAs(w, g1, subject),
    { approvers: 0, k: null, effective_seq: null },
    "both approvals were filed while the subject was removed: the late re-admission counts neither",
  );
  assertEquals(await w.deviceStatus(subject.device.id), "certified");

  // The other way. A designation of the admin's own device, filed now, and the admin's removal of
  // the subject, filed and stored but never applied; then g1 files: counted.
  const label = await send(w, t.founder, t.t, "designation", { user_id: subject.user, label: "x" });
  await acked(w, label.rec.row.id, label.out, "a label (06 §1.0), not a membership record");
  const removal = await signedRecord(t.founder, t.t, "member_removal", { user_id: subject.user });
  await w.store.withClaims(t.founder.claims, (tx) => tx.insertSignedRecord(removal.row));
  const first = await send(w, g1, t.t, "device_revocation", revocation(subject));
  await acked(w, first.rec.row.id, first.out, "g1 files while the subject is re-admitted");
  assertEquals(await w.stored(first.rec.row.id), { applied: true, note: "counted 1 of 2" });
  // The removal, re-sent, is applied now: it never un-counts g1's approval.
  const rm = await postWire(w, t.founder, removal.wire);
  await acked(w, removal.row.id, rm, "the stored removal, applied on its re-send");
  assertEquals(await w.statusOf(t.t, subject.user), "removed");
  assertEquals(await countAs(w, g1, subject), { approvers: 1, k: 2, effective_seq: null });
  const back = await send(w, t.founder, t.t, "membership_status", {
    user_id: subject.user,
    status: "joined_pending_verification",
  });
  await acked(w, back.rec.row.id, back.out, "re-admitted");
  // Without the edge: the admin applies its own OLDER designation record as the removal.
  await w.store.withClaims(
    t.founder.claims,
    (tx) => tx.projectMembership(label.rec.row.id, t.t, subject.user, "removed"),
  );
  assertEquals(await w.statusOf(t.t, subject.user), "removed");
  assertEquals(
    await countAs(w, g1, subject),
    { approvers: 1, k: 2, effective_seq: null },
    "a removal applied on an older record is a fact when applied: g1's approval keeps counting",
  );
  const again = await send(w, t.founder, t.t, "membership_status", {
    user_id: subject.user,
    status: "joined_pending_verification",
  });
  await acked(w, again.rec.row.id, again.out, "re-admitted again");
  const done = await send(w, g2, t.t, "device_revocation", revocation(subject));
  await acked(w, done.rec.row.id, done.out, "g2 completes k");
  assertEquals(
    await w.stored(done.rec.row.id),
    { applied: true, note: `revoked by guardians 2 of 2 at seq ${done.out.seq}` },
  );
  assertEquals(await w.deviceStatus(subject.device.id), "revoked");
}

/** E-03b-12 — 06 §7's own re-admission is a membership fact on the server (desk 97 review, finding
 *  2; 0027 §1). A subject removed by record comes back through invite → accept (rf.accept_invite:
 *  joined_pending_verification) → ceremony (rf.project_verification_event: active). None of the
 *  three is a membership record. Guardian approvals filed after the acceptance count, and the set
 *  can revoke again — 0027 as first built logged only rf.project_membership's writes, so the
 *  subject stayed `removed` to the count for good, and every approval in that tenant was refused
 *  not_revoker. g1's approval filed while the subject was removed still never counts. */
export async function inviteReadmission(w: World) {
  const t = await w.tenant();
  const subject = await w.member(t, "active");
  const g1 = await w.member(t, "active"), g2 = await w.member(t, "active");
  await w.guardians(subject.user, 1, 2, [g1, g2], t.t); // n = 2, k = 2

  const out = await send(w, t.founder, t.t, "member_removal", { user_id: subject.user });
  await acked(w, out.rec.row.id, out.out, "the set's tenant's admin removes the subject");
  const early = await send(w, g1, t.t, "device_revocation", revocation(subject));
  await refusedAtApply(
    w,
    early.rec.row.id,
    early.out,
    "rejected:unauthorized",
    "not_revoker",
    "g1 files while the subject is removed",
  );

  // 06 §7: the admin invites the subject's number under a signed `invite` record; the subject's
  // device accepts.
  const nonce = await random(16);
  const issued = await signedRecord(t.founder, t.t, "invite", {
    roles: [],
    nonce: b64url.enc(nonce),
  });
  const hmac = await w.phoneOf(subject.user);
  const invite = await w.store.withClaims(t.founder.claims, async (tx) => {
    await tx.insertSignedRecord(issued.row);
    return await tx.createInvite(issued.row.id, t.t, hmac, [], nonce);
  });
  const accepted = await w.store.withClaims(subject.claims, (tx) => tx.acceptInvite(invite));
  assertEquals(accepted.status, "joined_pending_verification");
  assertEquals(await w.statusOf(t.t, subject.user), "joined_pending_verification");

  const second = await send(w, g2, t.t, "device_revocation", revocation(subject));
  await acked(w, second.rec.row.id, second.out, "g2 files after the acceptance");
  assertEquals(
    await w.stored(second.rec.row.id),
    { applied: true, note: "counted 1 of 2" },
    "the acceptance is a membership fact: the subject holds a membership there again",
  );

  // The ceremony: the admin's verification_event, which the edge projects (0006's flip to active).
  const cer = await send(w, t.founder, t.t, "verification_event", {
    subject_user_id: subject.user,
    verifier_user_id: t.founder.user,
    method: "qr_in_person",
    result: "verified",
  });
  await acked(w, cer.rec.row.id, cer.out, "the ceremony");
  assertEquals(await w.statusOf(t.t, subject.user), "active");

  const done = await send(w, g1, t.t, "device_revocation", revocation(subject));
  await acked(w, done.rec.row.id, done.out, "g1 files again after the ceremony");
  assertEquals(
    await w.stored(done.rec.row.id),
    { applied: true, note: `revoked by guardians 2 of 2 at seq ${done.out.seq}` },
    "g2's approval and g1's second: k at this seq (g1's removed-time approval never counted)",
  );
  assertEquals(await w.deviceStatus(subject.device.id), "revoked");
}

/** E-03b-8 — the server applies the k the subject's own devices apply (ADR 2026-10-03b §2 "count the
 *  same set"; ADR 2026-09-06 §3 earliest-k; desk 89 review, finding 3). A counted record is ONE per
 *  author — its lowest-seq approval — and k is the k of the earliest version among those records.
 *  v1 is n = 2, k = 2; v2 is n = 4, k = 3, same tenant. g1 approves naming v2, then g1's stale
 *  device re-files naming v1; that second record is not counted, so it cannot lower the bar to v1's
 *  k = 2. g2's approval is "2 of 3", not a revocation; g3's completes it. (Before the repair the
 *  server took k from EVERY approval, read 2 of 2 and revoked where the client would not.) */
export async function authorsFirstRecord(w: World) {
  const t = await w.tenant();
  const subject = await w.member(t, "active");
  const g1 = await w.member(t, "active"), g2 = await w.member(t, "active");
  const g3 = await w.member(t, "active"), g4 = await w.member(t, "active");
  await w.guardians(subject.user, 1, 2, [g1, g2], t.t);
  await w.guardians(subject.user, 2, 3, [g1, g2, g3, g4], t.t);

  const steps = [
    [g1, 2, "counted 1 of 3", "g1 names v2"],
    [g1, 1, "counted 1 of 3", "g1's stale device names v1 — the same author, not counted again"],
    [g2, 2, "counted 2 of 3", "g2 names v2: two authors of v2's k = 3, not v1's k = 2"],
  ] as const;
  for (const [g, version, note, why] of steps) {
    const s = await send(w, g, t.t, "device_revocation", revocation(subject, version));
    await acked(w, s.rec.row.id, s.out, why);
    assertEquals(await w.stored(s.rec.row.id), { applied: true, note }, why);
  }
  assertEquals(await w.deviceStatus(subject.device.id), "certified", "2 of 3 is not k");
  assertEquals(await countAs(w, subject, subject), { approvers: 2, k: 3, effective_seq: null });

  const done = await send(w, g3, t.t, "device_revocation", revocation(subject, 2));
  await acked(w, done.rec.row.id, done.out, "the third distinct author");
  assertEquals(
    await w.stored(done.rec.row.id),
    { applied: true, note: `revoked by guardians 3 of 3 at seq ${done.out.seq}` },
  );
  assertEquals(await w.deviceStatus(subject.device.id), "revoked");
}

/** E-03b-6 — two guardians filing the approvals that reach k at the same moment revoke the device
 *  (ADR 2026-10-03b §2; desk 89 review, finding 1). PgStore ONLY: MemStore has no concurrent
 *  transactions to race. Both requests are held at the edge's rf.revocation_count until BOTH have
 *  filed their approval in their own open transaction — the interleaving that, without 0026's
 *  per-device lock, let each count "1 of 2" without the other's uncommitted row and commit two
 *  counted approvals onto a device that stayed certified (nothing projects later). With the lock
 *  the second counter waits for the first's commit, counts both, and projects. */
export async function concurrentK(w: World) {
  const t = await w.tenant();
  const subject = await w.member(t, "active");
  const g1 = await w.member(t, "active"), g2 = await w.member(t, "active");
  await w.guardians(subject.user, 1, 2, [g1, g2], t.t); // n = 2, k = 2

  const inner = w.r.deps.store;
  let arrived = 0;
  let release!: () => void;
  const both = new Promise<void>((res) => (release = res));
  let timer: ReturnType<typeof setTimeout> | undefined;
  const stuck = new Promise<never>((_, rej) => {
    timer = setTimeout(
      () => rej(new Error("both requests never reached the count — check the scenario")),
      10_000,
    );
  });
  const held = (tx: Tx): Tx =>
    new Proxy(tx, {
      get(target, prop) {
        const v = Reflect.get(target, prop, target);
        if (prop !== "revocationCount" || typeof v !== "function") return v;
        return async (...args: unknown[]) => {
          if (++arrived === 2) release();
          await Promise.race([both, stuck]);
          return await (v as (...a: unknown[]) => Promise<unknown>).apply(target, args);
        };
      },
    });
  w.r.deps.store = { withClaims: (claims, fn) => inner.withClaims(claims, (tx) => fn(held(tx))) };
  const sent = await Promise.all([
    send(w, g1, t.t, "device_revocation", revocation(subject)),
    send(w, g2, t.t, "device_revocation", revocation(subject)),
  ]).finally(() => {
    clearTimeout(timer);
    w.r.deps.store = inner;
  });
  assertEquals(arrived, 2, "both requests counted");
  for (const s of sent) await acked(w, s.rec.row.id, s.out, "a concurrent approval");
  const seqs = sent.map((s) => BigInt(s.out.seq!)).sort((x, y) => (x < y ? -1 : x > y ? 1 : 0));
  const notes = (await Promise.all(sent.map((s) => w.stored(s.rec.row.id))))
    .map((x) => x?.note).sort();
  assertEquals(
    notes,
    ["counted 1 of 2", `revoked by guardians 2 of 2 at seq ${seqs[1]}`],
    "the second counter waited for the first's commit and counted both",
  );
  assertEquals(await w.deviceStatus(subject.device.id), "revoked", "k approvals, k counted");
  assertEquals(await countAs(w, g1, subject), { approvers: 2, k: 2, effective_seq: seqs[1] });
}

/** E-03b-4 — a book that ever held an envelope is never re-claimed (ADR 2026-10-03b §5): its
 *  book_usage says it held one, though no envelope row is left. The edge refuses the bootstrap and
 *  so — without the edge — does rf.project_book_role, which read `envelopes` until 0026. */
export async function usedBook(w: World) {
  const b = await w.tenant();
  const plain = await w.member(b, "active");
  const used = await w.book(b.t, "business");
  await w.usage(b.t, used, 1);
  const fresh = await w.book(b.t, "business");
  const claim = (book: string) => ({ book_id: book, user_id: plain.user, role: "admin" });

  const s = await send(w, plain, b.t, "book_role", claim(used));
  await refusedAtApply(
    w,
    s.rec.row.id,
    s.out,
    "rejected:unauthorized",
    "not_admin",
    "a role-less book whose envelopes are gone but whose book_usage counted one",
  );
  assertEquals(
    await deniedBy(
      w,
      plain,
      async (tx) =>
        tx.projectBookRole(
          await fileIn(tx, plain, b.t, "book_role", claim(used)),
          used,
          plain.user,
          "admin",
          null,
        ),
    ),
    "not_admin",
    "rf.project_book_role reads book_usage, not envelopes",
  );
  assertEquals(await w.rolesOf(used), []);

  const ok = await send(w, plain, b.t, "book_role", claim(fresh));
  await acked(
    w,
    ok.rec.row.id,
    ok.out,
    "a book that never held an envelope: its creator's own admin",
  );
  assertEquals(await w.rolesOf(fresh), [`${plain.user}:admin`]);
}

/** POST /sync-meta/recovery/guardians as `m`, naming `gs`, with `over` laid on top. */
async function publishAs(
  w: World,
  m: Member,
  gs: Member[],
  over: Record<string, unknown>,
): Promise<{ status: number; body: Record<string, unknown> }> {
  const guardians = [];
  for (const g of gs) {
    guardians.push({
      guardian_user_id: g.user,
      umk_pub_ed: b64url.enc(g.keys.pub),
      blob: b64url.enc(await random(80)),
    });
  }
  const res = await meta(
    post("/sync-meta/recovery/guardians", {
      share_set_version: 1,
      n: gs.length,
      k: Math.ceil((gs.length + 1) / 2),
      guardians,
      ...over,
    }, { token: m.token }),
    w.r.deps,
  );
  return { status: res.status, body: await body(res) };
}
const historyOf = (w: World, m: Member): Promise<GuardianSet[]> =>
  w.store.withClaims(m.claims, (tx) => tx.guardianSetHistory(m.user));

/** E-03b-5 — a set names its tenant (ADR 2026-10-03b §1): the publish route requires `tenant_id`;
 *  the publisher is active there (pending, absent, or an unknown tenant: one refusal); every guardian
 *  holds a membership there other than removed (a pending guardian may be chosen); the tenant is
 *  written once with the version and relayed on the meta channel; a re-split may name another. */
export async function publishTenant(w: World) {
  const t = await w.tenant(), u = await w.tenant(), x = await w.tenant();
  const subject = await w.member(t, "active");
  await w.member(u, "active", subject);
  const g1 = await w.member(t, "active");
  await w.member(u, "active", g1);
  const g2 = await w.member(t, "joined_pending_verification");
  const gone = await w.member(t, "active");
  await w.member(u, "active", gone);
  await w.setStatus(t.t, gone.user, "removed");
  const pendingPub = await w.member(t, "joined_pending_verification");

  for (const tenant of [undefined, "not-a-uuid", null]) {
    const r = await publishAs(w, subject, [g1, g2], { tenant_id: tenant });
    assertEquals([r.status, r.body.error], [400, "bad_request"], `tenant_id ${tenant}`);
  }
  const refusals: [string, Member, Member[], string, string][] = [
    ["a publisher only pending in the tenant", pendingPub, [g1, g2], t.t, "guardian_set_tenant"],
    ["a tenant the publisher is not in", subject, [g1, g2], x.t, "guardian_set_tenant"],
    [
      "a tenant that does not exist (the same answer)",
      subject,
      [g1, g2],
      crypto.randomUUID(),
      "guardian_set_tenant",
    ],
    ["a guardian removed from the tenant", subject, [g1, gone], t.t, "guardian_not_in_tenant"],
  ];
  for (const [why, m, gs, tenant, name] of refusals) {
    const r = await publishAs(w, m, gs, { tenant_id: tenant });
    assertEquals([r.status, r.body.error], [403, name], why);
  }
  assertEquals(await historyOf(w, subject), [], "no refused publish left a row");

  const ok = await publishAs(w, subject, [g1, g2], { tenant_id: t.t });
  assertEquals(
    [ok.status, ok.body.share_set_version],
    [200, 1],
    "a pending guardian may be chosen",
  );
  const h = await historyOf(w, subject);
  assertEquals(h.map((s) => [s.share_set_version, s.tenant_id]), [[1, t.t]]);
  const pulled = await body(await meta(get("/sync-meta", { token: subject.token }), w.r.deps));
  assertEquals(
    pulled.guardian_sets.map((s: Record<string, unknown>) => [s.share_set_version, s.tenant_id]),
    [[1, t.t]],
    "the meta channel relays the tenant on each guardian_sets element",
  );

  const again = await publishAs(w, subject, [g1, gone], { tenant_id: u.t });
  assertEquals(
    [again.status, again.body.error],
    [400, "share_set_version_out_of_order"],
    "a version is written once; its tenant with it",
  );
  const resplit = await publishAs(w, subject, [g1, gone], {
    share_set_version: 2,
    tenant_id: u.t,
  });
  assertEquals([resplit.status, resplit.body.share_set_version], [200, 2], "a re-split names u");
  assertEquals(
    (await historyOf(w, subject)).map((s) => [s.share_set_version, s.tenant_id]),
    [[1, t.t], [2, u.t]],
  );
}
