// Desk 83 (🔴 SECURITY, owner said go 3 Oct 2026): WHO may file a signed record, and who a record's
// projection may come from, is decided by the edge from what the DATABASE answers — rf.may_file_record,
// rf.is_tenant_admin, rf.book_access (SECURITY DEFINER, 0005/0022) — never from a count of the rows
// the caller happens to be able to see (one exception remains, reported: device_revocation's k-of-n
// COUNT, which 0022 (e) leaves to the edge, still reads only the approvals the caller can see —
// `disjointGuardians`, registered ignored). Before this desk `applyRecord` took a founder's bootstrap from
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
// Ids E-06-91 … E-06-95. Fixtures are synthetic: random keys and ids; payloads carry ids and role
// names only — no ledger content, no phone number (CLAUDE.md rule 4).
import { assert, assertEquals } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import type { Store, Tx } from "../_shared/store.ts";
import { StoreDenied } from "../_shared/store.ts";
import { handler as meta } from "../sync-meta/index.ts";
import {
  body,
  edKeypair,
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
  guardians(subject: string, version: number, k: number, guardians: Member[]): Promise<void>;
  statusOf(t: string, user: string): Promise<string | null>;
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
      const m = db.memberships.find((x) => x.tenant_id === t && x.user_id === user)!;
      m.status = status;
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
    guardians(subject, version, k, gs) {
      db.addGuardianSet(
        subject,
        version,
        k,
        gs.map((g) => ({ user_id: g.user, umk_pub_ed: g.keys.pub })),
      );
      return Promise.resolve();
    },
    statusOf(t, user) {
      const m = db.memberships.find((x) => x.tenant_id === t && x.user_id === user);
      return Promise.resolve((m?.status as string) ?? null);
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
  await w.guardians(victim.user, 1, 2, [g1, g2]);

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
    "the completing guardian, on a record of a tenant the subject is NOT in (0022 (e))",
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

/** E-06-94, the case the edge cannot meet yet — registered IGNORED on both stores until a migration
 *  gives the edge every approval of a device (EDGE83 review finding 2, an owner item). 06 §6 🔒
 *  "Revoke: … k guardians": the subject is in A and in B, guardian g1 only in A, g2 only in B, k = 2.
 *  Each files in a tenant the subject is in, as 0022 (e) asks — so the second approval completes
 *  the revocation. Today each guardian's count sees only its own approval (signed_records_select),
 *  both are acked "counted 1 of 2", and the device stays certified. */
export async function disjointGuardians(w: World) {
  const a = await w.tenant(), b = await w.tenant();
  const subject = await w.member(a, "active");
  await w.member(b, "active", subject);
  const g1 = await w.member(a, "active");
  const g2 = await w.member(b, "active");
  await w.guardians(subject.user, 1, 2, [g1, g2]);

  const first = await send(w, g1, a.t, "device_revocation", revocation(subject));
  await acked(w, first.rec.row.id, first.out, "g1, in A, a tenant the subject is in");
  assertEquals(await w.deviceStatus(subject.device.id), "certified", "one of two is not enough");
  const second = await send(w, g2, b.t, "device_revocation", revocation(subject));
  await acked(w, second.rec.row.id, second.out, "g2, in B, a tenant the subject is in");
  assertEquals(
    await w.stored(second.rec.row.id),
    { applied: true, note: `revoked by guardians 2 of 2 at seq ${second.out.seq}` },
    "the second approval completes k = 2, though g2 cannot see g1's record",
  );
  assertEquals(await w.deviceStatus(subject.device.id), "revoked", "k guardians revoke (06 §6)");
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

  /** The store's refusal, by name: the whole transaction is a probe and rolls back. */
  const denied = async (m: Member, fn: (tx: Tx) => Promise<unknown>): Promise<string> => {
    try {
      await w.store.withClaims(m.claims, fn);
      return "ok";
    } catch (e) {
      if (e instanceof StoreDenied) return e.reason;
      throw e;
    }
  };
  const file = async (tx: Tx, m: Member, t: string, kind: string) => {
    const rec = await signedRecord(m, t, kind, {});
    await tx.insertSignedRecord(rec.row);
    return rec.row.id;
  };
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
