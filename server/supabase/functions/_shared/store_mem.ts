// In-memory `Store` for `deno test`: the same seam as store_pg.ts with the 0005 row policies
// re-stated in TypeScript (certified-only, active membership, writer roles, projection-needs-record,
// append-only). Tests seed `MemDb` directly; functions only ever see `Tx`. Clock is injected.
import type { Claims } from "./claims.ts";
import { bytesEqual } from "./bytes.ts";
import {
  type CataloguePlan,
  type EntityType,
  NO_CAP,
  PlanCatalogue,
  type PlanId,
  WRITER_ROLES,
} from "./registry.ts";
import {
  type ActivationTicket,
  type BillingApplyResult,
  type BillingEventApply,
  type BookAccess,
  type CeremonySession,
  DeviceCapError,
  DeviceIdTakenError,
  type EntitlementState,
  type EnvelopeRow,
  type GuardianSet,
  type GuardianSetDraft,
  type InviteAccepted,
  type InviteOffer,
  META_TABLES,
  type MetaCursor,
  type MetaTable,
  type OtpChallenge,
  type RecoveryAsk,
  type RecoveryProgress,
  type RecoveryRequest,
  type RecoveryShare,
  type RecoverySheet,
  type RefreshToken,
  type RevocationCount,
  rowId,
  type SignedRecordRow,
  type Store,
  StoreDenied,
  type Tx,
  type UmkPublicRow,
} from "./store.ts";

type Row = Record<string, unknown>;
const uuid = () => crypto.randomUUID();

export interface MemUser {
  id: string;
  phone_hmac: Uint8Array | null;
  phone_ct: Uint8Array | null;
  language: string | null;
  display_name: string | null;
  erased_at: Date | null;
  trial_consumed_at?: Date | null; // 0001; set once by rf.start_trial (0018)
  created_at: Date;
  updated_at: Date;
}
export interface MemDevice {
  id: string;
  user_id: string;
  pub_ed: Uint8Array;
  pub_x: Uint8Array;
  model: string | null;
  os: string | null;
  attestation: unknown;
  status: "registered" | "certified" | "suspended" | "revoked";
  created_at: Date;
  revoked_at: Date | null;
  updated_at: Date;
}

/** 0018's seed, restated for the fake — ADR 2026-09-25 §5's working-price table. The REAL catalogue
 *  is the database's; E-25-3's PgStore test asserts that `PgStore.planCatalogue()` returns exactly
 *  these rows, so the fake cannot drift from the migration unnoticed. `updated_at` is the epoch:
 *  the seed predates every token a test mints. */
const GiB = 1024 ** 3, MiB = 1024 ** 2;
const BOTH: CataloguePlan["features"] = ["statement_import", "pdf_output"];
function seedPlan(
  id: string,
  entity_type: EntityType,
  name: string,
  sort_order: number,
  [members, business_books, devices, envelopes_per_book, tenant_bytes, attachment_bytes]: number[],
  features: CataloguePlan["features"],
  price_yearly_paise: number,
  popular = false,
): CataloguePlan {
  return {
    id,
    entity_type,
    name,
    sort_order,
    limits: {
      members,
      business_books,
      devices,
      envelopes_per_book,
      tenant_bytes,
      attachment_bytes,
    },
    features,
    price_yearly_paise,
    price_monthly_paise: price_yearly_paise / 10,
    popular,
    placeholder: true,
    updated_at: new Date(0),
  };
}
const FAMILY_Q = [8, 250_000, 5 * GiB, 5 * GiB], TOP_Q = [15, 1_000_000, 15 * GiB, 20 * GiB];
export const CATALOGUE_SEED: readonly CataloguePlan[] = [
  seedPlan("shop", "business", "Shop", 1, [2, 1, ...FAMILY_Q], [], 249_900),
  seedPlan("business", "business", "Business", 2, [10, 5, ...FAMILY_Q], BOTH, 299_900, true),
  seedPlan("business_plus", "business", "Business+", 3, [30, 15, ...TOP_Q], BOTH, 699_900),
  seedPlan("family_lite", "family", "Family Lite", 1, [4, 2, ...FAMILY_Q], [], 199_900),
  seedPlan("family", "family", "Family", 2, [12, 8, ...FAMILY_Q], BOTH, 249_900, true),
  seedPlan("family_plus", "family", "Family+", 3, [30, 20, ...TOP_Q], BOTH, 599_900),
  seedPlan("free", "individual", "Free", 1, [1, 0, 5, 10_000, 250 * MiB, 100 * MiB], [], 0),
  seedPlan(
    "personal",
    "individual",
    "Personal",
    2,
    [1, 3, 5, 100_000, 2 * GiB, 2 * GiB],
    BOTH,
    99_000,
  ),
  seedPlan("trust", "trust", "Trust", 1, [15, 3, ...FAMILY_Q], BOTH, 199_900, true),
  seedPlan("trust_plus", "trust", "Trust+", 2, [40, 10, ...TOP_Q], BOTH, 399_900),
];
const clonePlan = (p: CataloguePlan): CataloguePlan => ({
  ...p,
  limits: { ...p.limits },
  features: [...p.features],
  updated_at: new Date(p.updated_at),
});

export class MemDb {
  now: () => Date = () => new Date();
  /** 0018 `plan_catalogue`. Tests change it only through `setCataloguePlan`, which moves
   *  `updated_at` the way 0018's touch trigger does. */
  plan_catalogue: CataloguePlan[] = CATALOGUE_SEED.map(clonePlan);
  epoch = uuid();
  config = new Map<string, unknown>([
    ["min_client_version.sync", "0.1.0"],
    ["min_client_version.auth", "0.1.0"],
    ["min_client_version.billing", "0.1.0"],
  ]);
  users = new Map<string, MemUser>();
  umk_public_keys: Row[] = [];
  tenants = new Map<string, Row>();
  memberships: Row[] = [];
  books = new Map<string, Row>();
  book_roles: Row[] = [];
  devices = new Map<string, MemDevice>();
  device_certs: Row[] = [];
  wrapped_keys: Row[] = [];
  guardian_sets: Row[] = [];
  guardian_set_members: Row[] = [];
  invites: Row[] = [];
  verification_events: Row[] = [];
  ceremony_sessions: CeremonySession[] = [];
  recovery_requests: Row[] = [];
  recovery_approvals: Row[] = [];
  recovery_cancellations: Row[] = [];
  recovery_sheets: Row[] = [];
  escrow_policies: Row[] = [];
  subscriptions: Row[] = [];
  entitlement_tokens: Row[] = [];
  tenant_freezes: Row[] = [];
  envelopes: EnvelopeRow[] = [];
  /** 0003 `book_usage.envelope_count` — bumped on every envelope insert and never lowered, so a
   *  book whose envelope rows are gone still reads as having held them (ADR 2026-10-03b §5). Tests
   *  that push rows straight into `envelopes` bypass the bump, so the count read is never below the
   *  rows — `envelopeCount`. */
  book_usage = new Map<string, number>();
  signed_records: (SignedRecordRow & { apply_note?: string | null })[] = [];
  /** 0027 `membership_facts` — the history of every membership row, stamped when the row changed
   *  (ADR 2026-10-03b §6; desk 97 review, findings 1-2). Appended only by `logMembership`, the
   *  mirror of the `memberships_facts_log` trigger, which every write of a row's status calls —
   *  seeding included, as an owner's INSERT fires the trigger on PgStore. */
  membership_facts: {
    at_seq: bigint;
    tenant_id: string;
    user_id: string;
    status: string;
    source_record_id: string | null;
  }[] = [];
  seq = 0n;
  push_rate = new Map<string, { m: Date; mc: number; h: Date; hc: number; d: Date; db: number }>();
  otp_challenges: OtpChallenge[] = [];
  activation_tickets: ActivationTicket[] = [];
  auth_nonces: {
    nonce: Uint8Array;
    device_id: string;
    expires_at: Date;
    consumed_at: Date | null;
  }[] = [];
  refresh_tokens: RefreshToken[] = [];
  /** event_id → the recorded row. 0013 widened the table with `tenant_id` and `event_at`: the
   *  out-of-order guard of ADR 2026-09-05g §9 needs to know which subscription an event belongs to
   *  and when the GATEWAY raised it. `payload_hash` is all we keep of the body (rule 4). */
  billing_events = new Map<string, Row>();

  /** book_usage.envelope_count as the database keeps it: the counter, never below the live rows. */
  envelopeCount(book: string): number {
    return Math.max(
      this.book_usage.get(book) ?? 0,
      this.envelopes.filter((e) => e.book_id === book).length,
    );
  }
  // ---- seeding helpers (tests only)
  addUser(u: Partial<MemUser> = {}): MemUser {
    const t = this.now();
    const row: MemUser = {
      id: uuid(),
      phone_hmac: null,
      phone_ct: null,
      language: null,
      display_name: null,
      erased_at: null,
      created_at: t,
      updated_at: t,
      ...u,
    };
    this.users.set(row.id, row);
    return row;
  }
  addTenant(type = "family"): string {
    const id = uuid();
    this.tenants.set(id, { id, type, created_at: this.now(), updated_at: this.now() });
    return id;
  }
  addMembership(tenant_id: string, user_id: string, status = "active"): void {
    const row: Row = {
      tenant_id,
      user_id,
      status,
      source_record_id: null,
      updated_at: this.now(),
    };
    this.memberships.push(row);
    this.logMembership(row);
  }
  /** A membership row written to `status` — inserted, or its status changed — past every policy,
   *  as the schema owner's INSERT/UPDATE is on PgStore, and logged as the trigger logs it. An
   *  unchanged status is no change and logs nothing. Returns the row. */
  writeMembership(
    tenant_id: string,
    user_id: string,
    status: string,
    source_record_id: string | null = null,
  ): Row {
    const m = this.memberships.find((x) => x.tenant_id === tenant_id && x.user_id === user_id);
    if (!m) {
      const row: Row = { tenant_id, user_id, status, source_record_id, updated_at: this.now() };
      this.memberships.push(row);
      this.logMembership(row);
      return row;
    }
    const was = m.status;
    m.status = status;
    m.source_record_id = source_record_id;
    m.updated_at = this.now();
    if (was !== status) this.logMembership(m);
    return m;
  }
  /** 0027 `memberships_facts_log` (rf.membership_fact_log), the AFTER trigger, mirrored: called after
   *  every write that inserts a membership row or changes its status. PgStore stamps the fact with a
   *  FRESH store_seq value; here it takes the last seq handed out (`seq`) without consuming one, so
   *  the record and envelope seqs other MemStore tests read stay as they were. Both order the fact
   *  after every record already filed and before every later one, which is all subjectHeldAt reads
   *  (`at_seq < seq`; equal stamps resolve to the later write). Never the applying record's seq: a
   *  record applied late must not be dated under approvals already filed (finding 1). */
  logMembership(row: Row): void {
    this.membership_facts.push({
      at_seq: this.seq,
      tenant_id: String(row.tenant_id).toLowerCase(), // uuid columns: case-blind
      user_id: String(row.user_id).toLowerCase(),
      status: row.status as string,
      source_record_id: (row.source_record_id as string | null) ?? null,
    });
  }
  addBook(tenant_id: string, type = "family", owner_user_id: string | null = null): string {
    const id = uuid();
    this.books.set(id, {
      id,
      tenant_id,
      type,
      owner_user_id,
      fy_start_month: 4,
      archived_at: null,
      created_at: this.now(),
      updated_at: this.now(),
    });
    return id;
  }
  addRole(book_id: string, user_id: string, role: string, limit: bigint | null = null): void {
    this.book_roles.push({
      book_id,
      user_id,
      role,
      auto_post_limit_paise: limit,
      source_record_id: null,
      updated_at: this.now(),
    });
  }
  addDevice(
    user_id: string,
    pub_ed: Uint8Array,
    pub_x: Uint8Array,
    status: MemDevice["status"] = "certified",
    id: string = uuid(),
  ): MemDevice {
    const t = this.now();
    const d: MemDevice = {
      id,
      user_id,
      pub_ed,
      pub_x,
      model: null,
      os: null,
      attestation: null,
      status,
      created_at: t,
      revoked_at: null,
      updated_at: t,
    };
    this.devices.set(d.id, d);
    return d;
  }
  addWrappedKey(r: Partial<Row> & { kind: string; user_id: string }): string {
    const id = uuid();
    this.wrapped_keys.push({
      id,
      device_id: null,
      book_id: null,
      key_version: 1,
      share_set_version: null,
      blob: new Uint8Array(48),
      created_at: this.now(),
      revoked_at: null,
      updated_at: this.now(),
      ...r,
    });
    return id;
  }
  addGuardianSet(
    subject: string,
    version: number,
    k: number,
    guardians: { user_id: string; umk_pub_ed: Uint8Array }[],
    /** ADR 2026-10-03b §1; null seeds a version published before 0026 (it counts no revocation). */
    tenant_id: string | null = null,
  ): void {
    this.guardian_sets.push({
      subject_user_id: subject,
      share_set_version: version,
      n: guardians.length,
      k,
      tenant_id,
      created_at: this.now(),
      superseded_at: null,
      source_record_id: null,
      updated_at: this.now(),
    });
    for (const g of guardians) {
      this.guardian_set_members.push({
        subject_user_id: subject,
        share_set_version: version,
        guardian_user_id: g.user_id,
        umk_pub_ed: g.umk_pub_ed,
        wrapped_key_id: null,
        updated_at: this.now(),
      });
    }
  }
  /** A catalogue DATA change (ADR 2026-09-25 §6: "a catalogue change is a data change plus a server
   *  deploy, still with no app release"): patch one row and move its `updated_at` as 0018's
   *  plan_catalogue_touch trigger would. */
  setCataloguePlan(
    id: string,
    patch: Partial<Omit<CataloguePlan, "id" | "limits">> & {
      limits?: Partial<CataloguePlan["limits"]>;
    },
  ): CataloguePlan {
    const row = this.plan_catalogue.find((p) => p.id === id);
    if (!row) throw new Error(`no catalogue plan ${id}`);
    const { limits, ...rest } = patch;
    Object.assign(row, rest);
    if (limits) Object.assign(row.limits, limits);
    row.updated_at = this.now();
    return row;
  }
  setPlan(tenant_id: string, plan: PlanId): void {
    this.subscriptions = this.subscriptions.filter((s) => s.tenant_id !== tenant_id);
    this.subscriptions.push({ tenant_id, plan, status: "active", updated_at: this.now() });
  }
  /** A subscription row with every 03 §2.4 🔒 column present, the way 0004 creates it — so a
   *  billing test can assert that a state change touched the columns it should and left the rest
   *  alone, which `setPlan`'s three-column row cannot show. */
  addSubscription(tenant_id: string, row: Row = {}): Row {
    this.subscriptions = this.subscriptions.filter((s) => s.tenant_id !== tenant_id);
    const r: Row = {
      tenant_id,
      plan: "free",
      status: "active",
      gateway: null,
      gateway_ref: null,
      current_period_end: null,
      source: null,
      original_transaction_id: null,
      payer_user_id: null,
      trial_end: null,
      grace_until: null,
      grace_kind: null,
      cancel_at_period_end: false,
      seats_addon: 0,
      dispute_state: null,
      ...row,
      updated_at: this.now(),
    };
    this.subscriptions.push(r);
    return r;
  }
  freeze(tenant_id: string, days = 7): void {
    const t = this.now();
    this.tenant_freezes.push({
      tenant_id,
      ground: "abuse",
      imposed_by: "s1",
      approved_by: "s2",
      imposed_at: t,
      expires_at: new Date(t.getTime() + days * 86400e3),
      lifted_at: null,
      updated_at: t,
    });
  }
  bumpEpoch(): void {
    this.epoch = uuid();
  }
}

export class MemStore implements Store {
  constructor(public db: MemDb) {}
  withClaims<T>(claims: Claims | null, fn: (tx: Tx) => Promise<T>): Promise<T> {
    return fn(new MemTx(this.db, claims));
  }
}

class MemTx implements Tx {
  constructor(private db: MemDb, private c: Claims | null) {}
  private get now() {
    return this.db.now();
  }
  private get me() {
    return this.c?.user_id ?? null;
  }
  private get dev() {
    return this.c?.device_id ?? null;
  }
  // ---- policy helpers (0005 rf.*)
  private isCertified(): boolean {
    if (!this.c) return false;
    const d = this.db.devices.get(this.c.device_id);
    return !!d && d.user_id === this.c.user_id && d.status === "certified";
  }
  private activeInTenant(t: string): boolean {
    return this.isCertified() &&
      this.db.memberships.some((m) =>
        m.tenant_id === t && m.user_id === this.me && m.status === "active"
      );
  }
  private sharesTenant(other: string): boolean {
    if (!this.isCertified()) return false;
    const mine = this.db.memberships.filter((m) => m.user_id === this.me && m.status === "active")
      .map((m) => m.tenant_id);
    return this.db.memberships.some((m) =>
      mine.includes(m.tenant_id as string) && m.user_id === other && m.status !== "removed"
    );
  }
  private bookRole(book: string): string | null {
    const b = this.db.books.get(book);
    if (!b || b.archived_at || !this.activeInTenant(b.tenant_id as string)) return null;
    return (this.db.book_roles.find((r) => r.book_id === book && r.user_id === this.me)
      ?.role as string) ?? null;
  }
  private deviceVisible(id: string): boolean {
    if (id === this.dev) return true;
    const d = this.db.devices.get(id);
    return !!d && this.isCertified() && (d.user_id === this.me || this.sharesTenant(d.user_id));
  }
  private tenantAdmin(t: string): boolean {
    return this.activeInTenant(t) &&
      this.db.book_roles.some((r) =>
        r.user_id === this.me && r.role === "admin" &&
        this.db.books.get(r.book_id as string)?.tenant_id === t
      );
  }
  /** 0022 §1 rf.may_file_record: a filing member (active or pending), or the founder's
   *  membership_status into an existing tenant with no member at all. Reads every row, like the
   *  SECURITY DEFINER function it mirrors. */
  private mayFile(t: string, kind: string): boolean {
    return this.isCertified() && (
      this.db.memberships.some((m) =>
        m.tenant_id === t && m.user_id === this.me &&
        (m.status === "active" || m.status === "joined_pending_verification")
      ) ||
      (kind === "membership_status" && this.db.tenants.has(t) &&
        !this.db.memberships.some((m) => m.tenant_id === t))
    );
  }

  storeEpoch(): Promise<string> {
    return Promise.resolve(this.db.epoch);
  }
  appConfig(key: string): Promise<unknown> {
    return Promise.resolve(this.db.config.get(key));
  }
  bookAccess(bookId: string): Promise<BookAccess | null> {
    const b = this.db.books.get(bookId);
    if (!b || !this.isCertified()) return Promise.resolve(null);
    const t = b.tenant_id as string, now = this.now;
    const plan = (this.db.subscriptions.find((s) => s.tenant_id === t)?.plan as PlanId) ?? "free";
    const count = this.db.envelopeCount(bookId); // 0005 rf.book_access reads book_usage
    const bytes = this.db.envelopes.filter((e) => e.tenant_id === t).reduce(
      (n, e) => n + e.size,
      0,
    );
    return Promise.resolve({
      tenant_id: t,
      archived: b.archived_at != null,
      role: (this.db.book_roles.find((r) =>
        r.book_id === bookId && r.user_id === this.me
      )?.role as string) ?? null,
      membership_status: (this.db.memberships.find((m) =>
        m.tenant_id === t && m.user_id === this.me
      )?.status as string) ?? null,
      frozen: this.db.tenant_freezes.some((f) =>
        f.tenant_id === t && f.lifted_at == null && (f.expires_at as Date) > now
      ),
      plan,
      envelope_count: count,
      tenant_bytes: bytes,
    });
  }
  highestKeyVersion(bookId: string) {
    if (this.bookRole(bookId) === null) return Promise.resolve(null);
    const ks = this.db.wrapped_keys.filter((w) => w.book_id === bookId && w.kind === "bk_for_user");
    if (!ks.length) return Promise.resolve(null);
    const v = Math.max(...ks.map((w) => w.key_version as number));
    const issued = ks.filter((w) => w.key_version === v).map((w) =>
      (w.created_at as Date).getTime()
    );
    return Promise.resolve({ key_version: v, issued_at: new Date(Math.min(...issued)) });
  }
  pushRateCheck(deviceId: string, count: number, bytes: number): Promise<boolean> {
    if (deviceId !== this.dev) return Promise.resolve(false);
    const t = this.now;
    const r = this.db.push_rate.get(deviceId) ?? { m: t, mc: 0, h: t, hc: 0, d: t, db: 0 };
    if (r.m.getTime() < t.getTime() - 60e3) {
      r.m = t;
      r.mc = 0;
    }
    if (r.h.getTime() < t.getTime() - 3600e3) {
      r.h = t;
      r.hc = 0;
    }
    if (r.d.getTime() < t.getTime() - 86400e3) {
      r.d = t;
      r.db = 0;
    }
    if (r.mc + count > 600 || r.hc + count > 5000 || r.db + bytes > 52428800) {
      this.db.push_rate.set(deviceId, r);
      return Promise.resolve(false);
    }
    r.mc += count;
    r.hc += count;
    r.db += bytes;
    this.db.push_rate.set(deviceId, r);
    return Promise.resolve(true);
  }
  insertEnvelope(row: EnvelopeRow): Promise<{ seq: bigint; duplicate: boolean }> {
    const existing = this.db.envelopes.find((e) => e.envelope_id === row.envelope_id);
    if (existing) return Promise.resolve({ seq: existing.seq!, duplicate: true });
    const role = this.bookRole(row.book_id);
    const b = this.db.books.get(row.book_id);
    if (
      !role || !WRITER_ROLES.has(role) || row.tenant_id !== b?.tenant_id ||
      row.author_device !== this.dev
    ) {
      throw new StoreDenied("rls");
    }
    if (row.blob && row.blob.length !== row.size) throw new StoreDenied("rejected:shape");
    if ((row.blob === null) === (row.blob_ref === null)) throw new StoreDenied("check");
    const seq = ++this.db.seq;
    this.db.envelopes.push({ ...row, seq });
    this.db.book_usage.set(row.book_id, (this.db.book_usage.get(row.book_id) ?? 0) + 1); // 0003 trigger
    return Promise.resolve({ seq, duplicate: false });
  }
  pullEnvelopes(
    bookId: string,
    afterSeq: bigint,
    limit: number,
    objectTypes: string[] | null,
  ): Promise<EnvelopeRow[]> {
    if (this.bookRole(bookId) === null) return Promise.resolve([]);
    const rows = this.db.envelopes
      .filter((e) =>
        e.book_id === bookId && e.seq! > afterSeq &&
        (!objectTypes || objectTypes.includes(e.object_type))
      )
      .sort((a, b) => (a.seq! < b.seq! ? -1 : 1))
      .slice(0, limit);
    return Promise.resolve(rows);
  }
  private visible(table: MetaTable, r: Row): boolean {
    switch (table) {
      case "memberships":
        return this.activeInTenant(r.tenant_id as string) ||
          (this.isCertified() && r.user_id === this.me);
      case "book_roles":
        return this.activeInTenant(this.db.books.get(r.book_id as string)?.tenant_id as string);
      case "books":
        return this.activeInTenant(r.tenant_id as string);
      case "devices":
        return this.deviceVisible(r.id as string);
      case "device_certs":
        return this.deviceVisible(r.device_id as string);
      case "wrapped_keys":
        // 0020's restrictive policy: a recovery_blob is never visible on the table, to anyone. It
        // leaves only through recoveryShares, once its attempt is approved.
        // ⚠️ SPEC (0020 header (d)): 05 §5 🔒 lists wrapped_keys on the meta channel with no such
        // exception. The doc line is the owner's to write.
        return r.kind !== "recovery_blob" && r.user_id === this.me &&
          (r.device_id === this.dev || this.isCertified());
      case "invites":
      case "verification_events":
      case "subscriptions":
      case "entitlement_tokens":
      case "tenant_freezes":
        return this.activeInTenant(r.tenant_id as string);
      case "recovery_requests":
        return r.candidate_device === this.dev || (this.isCertified() && r.user_id === this.me);
      case "escrow_policies":
        return this.isCertified() && (r.member_user === this.me || r.head_user === this.me);
      case "guardian_sets":
        return this.isCertified() &&
          (r.subject_user_id === this.me || this.sharesTenant(r.subject_user_id as string));
      case "guardian_set_members":
        return this.isCertified() &&
          (r.subject_user_id === this.me || r.guardian_user_id === this.me ||
            this.sharesTenant(r.subject_user_id as string));
      case "umk_public_keys":
        return r.user_id === this.me || this.sharesTenant(r.user_id as string);
    }
  }
  private tableRows(table: MetaTable): Row[] {
    switch (table) {
      case "books":
        return [...this.db.books.values()];
      case "devices":
        return [...this.db.devices.values()] as unknown as Row[];
      default:
        return (this.db as unknown as Record<string, Row[]>)[table];
    }
  }
  metaPage(table: MetaTable, after: MetaCursor | null, limit: number) {
    if (!META_TABLES.includes(table)) throw new Error(`unknown meta table ${table}`);
    const rows = this.tableRows(table).filter((r) => this.visible(table, r))
      .map((r) => ({ row: r, ts: (r.updated_at as Date).toISOString(), id: rowId(table, r) }))
      .filter((x) =>
        !after || x.ts > after.updated_at || (x.ts === after.updated_at && x.id > after.id)
      )
      .sort((a, b) => a.ts < b.ts ? -1 : a.ts > b.ts ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
      .slice(0, limit);
    const last = rows.at(-1);
    return Promise.resolve({
      rows: rows.map((x) => x.row),
      next: rows.length === limit && last ? { updated_at: last.ts, id: last.id } : null,
    });
  }
  /** Mirrors store_pg's join, including the `activeInTenant` filter that keeps an uncertified
   *  device out (0005's memberships policy alone would not). */
  entitlementStates(): Promise<EntitlementState[]> {
    const out: EntitlementState[] = [];
    for (const m of this.db.memberships) {
      if (m.user_id !== this.me || m.status !== "active") continue;
      const t = m.tenant_id as string;
      if (!this.activeInTenant(t)) continue;
      const s = this.db.subscriptions.find((x) => x.tenant_id === t) ?? null;
      const e = this.db.entitlement_tokens.find((x) => x.tenant_id === t) ?? null;
      out.push({
        tenant_id: t,
        plan: (s?.plan as string | null) ?? null,
        status: (s?.status as string | null) ?? null,
        current_period_end: (s?.current_period_end as Date | null) ?? null,
        trial_end: (s?.trial_end as Date | null) ?? null,
        grace_kind: (s?.grace_kind as string | null) ?? null,
        grace_until: (s?.grace_until as Date | null) ?? null,
        sub_updated_at: (s?.updated_at as Date | null) ?? null,
        token_created_at: (e?.created_at as Date | null) ?? null,
        token_expires_at: (e?.expires_at as Date | null) ?? null,
        token: (e?.token as Uint8Array | null) ?? null,
      });
    }
    out.sort((a, b) => a.tenant_id < b.tenant_id ? -1 : a.tenant_id > b.tenant_id ? 1 : 0);
    return Promise.resolve(out);
  }
  /** 0018 `plan_catalogue_select`: any authenticated caller, never a claims-less transaction. */
  planCatalogue(): Promise<CataloguePlan[]> {
    if (!this.me) return Promise.resolve([]);
    const order = (p: CataloguePlan) =>
      `${p.entity_type}\u0000${String(p.sort_order).padStart(6, "0")}\u0000${p.id}`;
    return Promise.resolve(
      this.db.plan_catalogue.map(clonePlan).sort((a, b) => order(a) < order(b) ? -1 : 1),
    );
  }
  /** rf.start_trial (0018) in TypeScript, same order of refusals. Divergence is a bug in whichever
   *  is not 0018. */
  startTrial(tenantId: string, entity: EntityType): Promise<{ plan: PlanId; trial_end: Date }> {
    const refuse = (why: string) => Promise.reject(new StoreDenied(why));
    if (!this.tenantAdmin(tenantId)) return refuse("not_admin");
    if (!["individual", "family", "business", "trust"].includes(entity)) {
      return refuse("bad_entity_type");
    }
    if (entity === "individual") return refuse("no_trial");
    const type = this.db.tenants.get(tenantId)?.type;
    if ((entity === "trust") !== (type === "organization")) return refuse("entity_mismatch");
    const me = this.db.users.get(this.me!);
    if (!me || me.trial_consumed_at) return refuse("trial_consumed");
    const plan = new PlanCatalogue(this.db.plan_catalogue).popular(entity);
    if (!plan) return refuse("no_popular_plan");
    const t = this.now;
    const trial_end = new Date(t.getTime() + 30 * 86400e3);
    const sub = this.db.subscriptions.find((s) => s.tenant_id === tenantId);
    if (sub) {
      if (
        sub.trial_end != null || sub.current_period_end != null || sub.gateway_ref != null ||
        sub.status !== "active"
      ) return refuse("trial_unavailable");
      Object.assign(sub, { plan: plan.id, status: "trial", trial_end, updated_at: t });
    } else {
      this.db.addSubscription(tenantId, { plan: plan.id, status: "trial", trial_end });
    }
    me.trial_consumed_at = t;
    return Promise.resolve({ plan: plan.id, trial_end });
  }
  /** rf.mint_entitlement_token (0014) in TypeScript: one row per tenant, the membership re-checked
   *  here rather than trusted from the caller, `created_at` moved because the row now holds a
   *  NEWLY minted token, and `updated_at` moved because 05 §5's cursor must carry it to the
   *  device. A row for a tenant the caller is not active in is refused, not silently skipped. */
  putEntitlementToken(tenantId: string, token: Uint8Array, expiresAt: Date): Promise<void> {
    if (!this.activeInTenant(tenantId)) {
      return Promise.reject(new StoreDenied("not_entitled"));
    }
    const t = this.now;
    const row = this.db.entitlement_tokens.find((x) => x.tenant_id === tenantId);
    if (row) {
      row.token = token;
      row.expires_at = expiresAt;
      row.created_at = t;
      row.updated_at = t;
    } else {
      this.db.entitlement_tokens.push({
        id: crypto.randomUUID(),
        tenant_id: tenantId,
        token,
        expires_at: expiresAt,
        created_at: t,
        updated_at: t,
      });
    }
    return Promise.resolve();
  }
  signedRecordsAfter(afterSeq: bigint, limit: number): Promise<SignedRecordRow[]> {
    return Promise.resolve(
      this.db.signed_records
        .filter((r) =>
          r.seq! > afterSeq && (this.activeInTenant(r.tenant_id) || r.author_device === this.dev)
        )
        .sort((a, b) => (a.seq! < b.seq! ? -1 : 1)).slice(0, limit),
    );
  }
  guardianSetHistory(subjectUserId: string): Promise<GuardianSet[]> {
    const sets = this.db.guardian_sets.filter((s) =>
      s.subject_user_id === subjectUserId && this.visible("guardian_sets", s)
    );
    return Promise.resolve(
      sets.map((s) => ({
        subject_user_id: subjectUserId,
        share_set_version: s.share_set_version as number,
        n: s.n as number,
        k: s.k as number,
        tenant_id: (s.tenant_id as string | null) ?? null,
        members: this.db.guardian_set_members
          .filter((m) =>
            m.subject_user_id === subjectUserId && m.share_set_version === s.share_set_version
          )
          .map((m) => ({
            guardian_user_id: m.guardian_user_id as string,
            umk_pub_ed: m.umk_pub_ed as Uint8Array,
          })),
      })).sort((a, b) => a.share_set_version - b.share_set_version),
    );
  }
  insertSignedRecord(row: SignedRecordRow): Promise<{ seq: bigint; duplicate: boolean }> {
    const ex = this.db.signed_records.find((r) => r.id === row.id);
    if (ex) return Promise.resolve({ seq: ex.seq!, duplicate: true });
    // signed_records_insert as 0022 §1 wrote it. Postgres checks the policy before the foreign key,
    // so a tenant that does not exist answers `rls` like one with members (E-06-82).
    if (
      !this.isCertified() || row.author_device !== this.dev ||
      !this.mayFile(row.tenant_id, row.kind)
    ) throw new StoreDenied("rls");
    if (!this.db.tenants.has(row.tenant_id)) throw new StoreDenied("fk");
    const seq = ++this.db.seq;
    this.db.signed_records.push({ ...row, seq, applied_at: null, apply_note: null });
    return Promise.resolve({ seq, duplicate: false });
  }
  /** 0027 rf.subject_held_at — `user`'s membership in `tenant` as of `seq`, from the history of the
   *  membership row (ADR 2026-10-03b §6): held when the latest fact strictly before `seq` is anything
   *  but removed, and NOT held with no fact (no membership row there yet — the log is complete).
   *  Keyed by tenant AND user. A membership row as it stands now is never read, and neither is a
   *  membership RECORD (a refused one is stored like any other). */
  private subjectHeldAt(tenant: string, user: string, seq: bigint): boolean {
    let latest: { at_seq: bigint; status: string } | undefined;
    for (const f of this.db.membership_facts) {
      if (
        f.tenant_id !== tenant.toLowerCase() || f.user_id !== user.toLowerCase() ||
        f.at_seq >= seq
      ) continue;
      if (latest === undefined || f.at_seq >= latest.at_seq) latest = f; // a tie: the later write
    }
    return latest !== undefined && latest.status !== "removed";
  }
  /** 0027 rf.revocation_approvals — every COUNTED approval of a device, read over every row as the
   *  SECURITY DEFINER function reads it (ADR 2026-10-03b §2, §6): a device_revocation naming the
   *  device and its owner, by a guardian at the version it names, filed in that version's tenant (a
   *  version with no tenant counts nothing), while the owner held a membership there other than
   *  removed AT THE APPROVAL'S OWN SEQ — a later removal never un-counts it, a re-admission never
   *  counts one filed while removed. */
  private revocationApprovals(dev: string) {
    const d = this.db.devices.get(dev.toLowerCase()); // a uuid column: case-blind
    if (!d) return [];
    const out: { record: string; author: string; version: number; k: number; seq: bigint }[] = [];
    for (const r of this.db.signed_records) {
      const p = r.payload_json;
      if (
        r.kind !== "device_revocation" ||
        String(p.revoked_device_id ?? "").toLowerCase() !== d.id ||
        String(p.subject_user_id ?? "").toLowerCase() !== d.user_id ||
        typeof p.share_set_version !== "number"
      ) continue;
      const author = this.db.devices.get(r.author_device)?.user_id;
      const set = this.db.guardian_sets.find((g) =>
        g.subject_user_id === d.user_id && g.share_set_version === p.share_set_version &&
        g.tenant_id != null && g.tenant_id === r.tenant_id
      );
      if (
        !author || !set ||
        !this.db.guardian_set_members.some((m) =>
          m.subject_user_id === d.user_id && m.share_set_version === set.share_set_version &&
          m.guardian_user_id === author
        ) ||
        !this.subjectHeldAt(r.tenant_id, d.user_id, r.seq!)
      ) continue;
      out.push({
        record: r.id,
        author,
        version: set.share_set_version as number,
        k: set.k as number,
        seq: r.seq!,
      });
    }
    return out;
  }
  /** 0026 rf.revocation_tally — earliest-k (ADR 2026-09-06 §3) over the counted approvals: ONE record
   *  per distinct author (its lowest-seq approval), and k of the earliest version among THOSE records
   *  — never among an author's later ones (desk 89 review, finding 3; the client's countRevocation). */
  private revocationTally(dev: string): RevocationCount {
    const a = this.revocationApprovals(dev);
    const per = new Map<string, (typeof a)[number]>();
    for (const x of a) {
      const prev = per.get(x.author);
      if (prev === undefined || x.seq < prev.seq) per.set(x.author, x);
    }
    const counted = [...per.values()];
    const first =
      [...counted].sort((x, y) =>
        x.version - y.version || (x.seq < y.seq ? -1 : x.seq > y.seq ? 1 : 0)
      )[0];
    const k = first?.k ?? null;
    const seqs = counted.map((x) => x.seq).sort((x, y) => (x < y ? -1 : x > y ? 1 : 0));
    return {
      approvers: per.size,
      k,
      effective_seq: k !== null && per.size >= k ? seqs[k - 1] : null,
    };
  }
  guardianMayRevoke(dev: string, tenant: string, version: number): Promise<boolean> {
    // 0027 rf.guardian_may_revoke: reads every row, like the SECURITY DEFINER function it mirrors.
    // The subject is judged at the seq of the caller device's latest approval of this device filed
    // in `tenant` naming `version` — the record the edge has just filed — or as of now without one.
    const d = this.db.devices.get(dev.toLowerCase()); // a uuid column: case-blind
    let at: bigint | null = null;
    if (d) {
      for (const r of this.db.signed_records) {
        const p = r.payload_json;
        if (
          r.kind === "device_revocation" && r.author_device === this.dev &&
          r.tenant_id === tenant &&
          String(p.revoked_device_id ?? "").toLowerCase() === d.id &&
          String(p.subject_user_id ?? "").toLowerCase() === d.user_id &&
          typeof p.share_set_version === "number" && p.share_set_version === version &&
          (at === null || r.seq! > at)
        ) at = r.seq!;
      }
    }
    const ok = !!d && this.mayFile(tenant, "device_revocation") &&
      this.db.guardian_sets.some((g) =>
        g.subject_user_id === d.user_id && g.share_set_version === version &&
        g.tenant_id != null && g.tenant_id === tenant
      ) &&
      this.db.guardian_set_members.some((m) =>
        m.subject_user_id === d.user_id && m.share_set_version === version &&
        m.guardian_user_id === this.me
      ) &&
      this.subjectHeldAt(tenant, d.user_id, at ?? BigInt("9223372036854775807"));
    return Promise.resolve(ok);
  }
  revocationCount(dev: string): Promise<RevocationCount> {
    // 0026 rf.revocation_count: the device's own user and that user's guardians; anyone else reads
    // the empty count, as for a device with no approval.
    const d = this.db.devices.get(dev.toLowerCase()); // a uuid column: case-blind
    const gated = this.isCertified() && !!d &&
      (d.user_id === this.me ||
        this.db.guardian_set_members.some((m) =>
          m.subject_user_id === d.user_id && m.guardian_user_id === this.me
        ));
    return Promise.resolve(
      gated ? this.revocationTally(dev) : { approvers: 0, k: null, effective_seq: null },
    );
  }
  deviceAuthRow(deviceId: string) {
    const d = this.db.devices.get(deviceId);
    return Promise.resolve(d ? { user_id: d.user_id, pub_ed: d.pub_ed, status: d.status } : null);
  }
  isTenantAdmin(t: string): Promise<boolean> {
    return Promise.resolve(this.tenantAdmin(t));
  }
  mayFileRecord(t: string, kind: string): Promise<boolean> {
    return Promise.resolve(this.mayFile(t, kind));
  }
  storedRecordSeq(id: string): Promise<bigint | null> {
    // signed_records_select (0005): the caller's own device's records, and its active tenants'.
    const r = this.db.signed_records.find((x) =>
      x.id === id && (this.activeInTenant(x.tenant_id) || x.author_device === this.dev)
    );
    return Promise.resolve(r?.seq ?? null);
  }
  membershipStatus(t: string, u: string): Promise<string | null> {
    // memberships_select, as PgStore's read meets it: never a row the caller cannot see.
    const m = this.db.memberships.find((x) =>
      x.tenant_id === t && x.user_id === u && this.visible("memberships", x)
    );
    return Promise.resolve((m?.status as string) ?? null);
  }
  bookInfo(bookId: string) {
    // books_select and book_roles_select (0005): only an active member of the book's tenant sees
    // the book, and then every role on it.
    const b = this.db.books.get(bookId);
    if (!b || !this.visible("books", b)) return Promise.resolve(null);
    return Promise.resolve({
      tenant_id: b.tenant_id as string,
      owner_user_id: b.owner_user_id as string | null,
      type: b.type as string,
      role_count: this.db.book_roles.filter((r) =>
        r.book_id === bookId && this.visible("book_roles", r)
      ).length,
    });
  }
  private requireRecord(record: string, tenant: string, kind?: string): void {
    if (
      !this.db.signed_records.some((r) =>
        r.id === record && r.tenant_id === tenant && r.author_device === this.dev &&
        (kind === undefined || r.kind === kind)
      )
    ) {
      throw new StoreDenied("no_record");
    }
  }
  projectMembership(record: string, tenant: string, user: string, status: string): Promise<void> {
    this.requireRecord(record, tenant);
    // 0022 §2: a tenant admin, or the founder's own first membership at active (06 §5).
    const founder = status === "active" && user === this.me && this.isCertified() &&
      !this.db.memberships.some((x) => x.tenant_id === tenant);
    if (!this.tenantAdmin(tenant) && !founder) throw new StoreDenied("not_admin");
    // 0027: logged, as the trigger logs it, when the row changes — never at the record's seq.
    this.db.writeMembership(tenant, user, status, record);
    if (status === "removed") {
      this.db.book_roles = this.db.book_roles.filter((r) =>
        !(r.user_id === user && this.db.books.get(r.book_id as string)?.tenant_id === tenant)
      );
    }
    return Promise.resolve();
  }
  projectBookRole(
    record: string,
    book: string,
    user: string,
    role: string | null,
    limit: bigint | null,
  ): Promise<void> {
    const b = this.db.books.get(book);
    const t = b?.tenant_id as string;
    this.requireRecord(record, t);
    // 0022 §3: an admin of THAT book; on a book with no role and no envelope, the caller's own
    // admin role — its creator's (06 §1.0 🔒) — and on a personal book only its owner's.
    let ok = false;
    if (b && this.activeInTenant(t)) {
      if (
        this.db.book_roles.some((r) =>
          r.book_id === book && r.user_id === this.me && r.role === "admin"
        )
      ) ok = true;
      else if (
        user === this.me && role === "admin" &&
        (b.type !== "personal" || b.owner_user_id === this.me)
      ) {
        // ADR 2026-10-03b §5: never held an envelope — book_usage, which only counts up.
        ok = !this.db.book_roles.some((r) => r.book_id === book) &&
          this.db.envelopeCount(book) === 0;
      }
    }
    if (!ok) throw new StoreDenied("not_admin");
    this.db.book_roles = this.db.book_roles.filter((r) =>
      !(r.book_id === book && r.user_id === user)
    );
    if (role) {
      this.db.book_roles.push({
        book_id: book,
        user_id: user,
        role,
        auto_post_limit_paise: limit,
        source_record_id: record,
        updated_at: this.now,
      });
    }
    return Promise.resolve();
  }
  projectDeviceStatus(
    record: string,
    tenant: string,
    device: string,
    status: string,
  ): Promise<void> {
    this.requireRecord(record, tenant);
    // 0026 (0022 §4 as amended by ADR 2026-10-03b §2): revoke only; by the device's own user on a
    // record of a tenant that user is in, or — for a guardian — only when the caller's own record
    // is a COUNTED approval, the caller may still file in that tenant, and the count over every
    // approval has reached k. One refusal for every miss.
    if (status !== "revoked") throw new StoreDenied("revoke_only");
    const d = this.db.devices.get(device);
    const owner = d?.user_id;
    let ok = false;
    if (owner && this.isCertified()) {
      ok = owner === this.me
        ? this.db.memberships.some((m) =>
          m.tenant_id === tenant && m.user_id === owner && m.status !== "removed"
        )
        : this.mayFile(tenant, "device_revocation") &&
          this.revocationApprovals(device).some((a) => a.record === record) &&
          this.revocationTally(device).effective_seq !== null;
    }
    if (!ok) throw new StoreDenied("not_revoker");
    if (d) {
      d.status = status as MemDevice["status"];
      d.updated_at = this.now;
      if (status === "revoked") {
        d.revoked_at = this.now;
        for (const w of this.db.wrapped_keys) {
          if (w.device_id === device && w.revoked_at == null) {
            w.revoked_at = this.now;
            w.updated_at = this.now;
          }
        }
      }
    }
    return Promise.resolve();
  }
  // ---- ADR 2026-09-13d ruling 4: the ceremony session relay, with 0007's guard re-stated here.
  // The rules are the security property, so the in-memory seam enforces the same four: who writes
  // what, write-once, ordering, and ten minutes from the commitment's server timestamp. Nothing in
  // this block hashes or compares a ceremony value — the server relays opaque bytes.
  ceremonyCommit(tenant: string, commitment: Uint8Array): Promise<CeremonySession> {
    if (!this.isCertified() || !this.me) throw new StoreDenied("rls");
    const st = this.db.memberships.find((x) => x.tenant_id === tenant && x.user_id === this.me)
      ?.status;
    if (st !== "joined_pending_verification" && st !== "active") {
      throw new StoreDenied("subject_not_in_tenant");
    }
    if (commitment.length !== 32) throw new StoreDenied("check");
    const live = this.db.ceremony_sessions.filter((x) =>
      x.tenant_id === tenant && x.subject_user === this.me && x.expires_at > this.now
    );
    if (live.length >= 10) throw new StoreDenied("ceremony_flood");
    const committed = this.now;
    const row: CeremonySession = {
      id: uuid(),
      tenant_id: tenant,
      subject_user: this.me,
      commitment,
      committed_at: committed,
      expires_at: new Date(committed.getTime() + 10 * 60_000),
      verifier_user: null,
      verifier_random: null,
      verifier_random_at: null,
      opening: null,
      opened_at: null,
    };
    (row as unknown as Row).subject_device = this.dev;
    this.db.ceremony_sessions.push(row);
    return Promise.resolve(row);
  }
  ceremonyContribute(session: string, verifierRandom: Uint8Array): Promise<CeremonySession> {
    if (verifierRandom.length !== 16) throw new StoreDenied("ceremony_shape");
    const row = this.db.ceremony_sessions.find((x) => x.id === session);
    if (!row || !this.activeInTenant(row.tenant_id)) throw new StoreDenied("unknown_session");
    if (row.subject_user === this.me) throw new StoreDenied("self_verification");
    if (row.expires_at <= this.now) throw new StoreDenied("ceremony_expired");
    if (row.verifier_random) throw new StoreDenied("ceremony_spent");
    row.verifier_random = verifierRandom;
    row.verifier_random_at = this.now;
    row.verifier_user = this.me;
    return Promise.resolve(row);
  }
  ceremonyOpen(session: string, opening: Uint8Array): Promise<CeremonySession> {
    if (opening.length !== 16) throw new StoreDenied("ceremony_shape");
    const row = this.db.ceremony_sessions.find((x) => x.id === session);
    if (
      !row || !this.isCertified() || row.subject_user !== this.me ||
      (row as unknown as Row).subject_device !== this.dev
    ) throw new StoreDenied("unknown_session");
    if (!row.verifier_random) throw new StoreDenied("ceremony_order");
    if (row.expires_at <= this.now) throw new StoreDenied("ceremony_expired");
    if (row.opening) throw new StoreDenied("ceremony_spent");
    row.opening = opening;
    row.opened_at = this.now;
    return Promise.resolve(row);
  }
  ceremonySession(session: string): Promise<CeremonySession | null> {
    const row = this.db.ceremony_sessions.find((x) => x.id === session);
    if (!row || !this.visibleSession(row)) return Promise.resolve(null);
    return Promise.resolve(row);
  }
  // 04 §6.4 *delegated*: the newest UNEXPIRED session for a subject, found by user_id because a
  // scanned QR (04 §6.1) carries no session id. The SAME visibility test as a lookup by id — this
  // seam may not see one row more than `ceremonySession` would.
  liveCeremonyFor(tenant: string, subject: string): Promise<CeremonySession | null> {
    const live = this.db.ceremony_sessions
      .filter((x) =>
        x.tenant_id === tenant && x.subject_user === subject && x.expires_at > this.now &&
        this.visibleSession(x)
      )
      .sort((a, b) => b.committed_at.getTime() - a.committed_at.getTime());
    return Promise.resolve(live[0] ?? null);
  }
  /** 0007:295 restated: a certified device, and either the subject itself or an active member. */
  private visibleSession(row: CeremonySession): boolean {
    if (!this.isCertified()) return false;
    return row.subject_user === this.me || this.activeInTenant(row.tenant_id);
  }
  // ---- 04 §7.3 the guardian recovery ladder (0010 in the database; mirrored here, because a fake
  // that is laxer than the guards is a test that proves nothing). The shape that matters most is
  // the one this block keeps: NOTHING below updates a request row. A decision and a cancellation
  // are their own rows and the state is derived, exactly as rf.recovery_derive derives it.
  private currentGuardianSet(subject: string): Row | null {
    const sets = this.db.guardian_sets.filter((g) =>
      g.subject_user_id === subject && g.superseded_at == null
    ).sort((a, b) => (a.share_set_version as number) - (b.share_set_version as number));
    return sets.at(-1) ?? null;
  }
  publishGuardianSet(d: GuardianSetDraft): Promise<number> {
    if (!this.isCertified() || !this.me) throw new StoreDenied("rls");
    if (d.n < 2 || d.n > 5) throw new StoreDenied("guardian_set_size");
    if (d.k !== Math.ceil((d.n + 1) / 2)) throw new StoreDenied("guardian_quorum"); // 04 §7.3
    if (d.guardians.length !== d.n) throw new StoreDenied("guardian_set_size");
    if (d.guardians.some((g) => g.guardian_user_id === this.me)) {
      throw new StoreDenied("guardian_is_subject");
    }
    // 0026 rf.guardian_set_guard (ADR 2026-10-03b §1): the set names its tenant and the publisher
    // is active there — one refusal whether the tenant is missing, unknown, or not theirs.
    if (
      !d.tenant_id ||
      !this.db.memberships.some((m) =>
        m.tenant_id === d.tenant_id && m.user_id === this.me && m.status === "active"
      )
    ) throw new StoreDenied("guardian_set_tenant");
    const hi = this.db.guardian_sets.filter((g) => g.subject_user_id === this.me)
      .reduce((m, g) => Math.max(m, g.share_set_version as number), 0);
    if (d.share_set_version !== hi + 1) throw new StoreDenied("share_set_version_out_of_order");
    for (const g of d.guardians) {
      // 0005: a guardian_share for somebody else needs a shared tenant.
      if (!this.sharesTenant(g.guardian_user_id)) throw new StoreDenied("rls");
      // 0026 rf.guardian_set_member_guard: every guardian holds a membership other than removed in
      // the set's tenant.
      if (
        !this.db.memberships.some((m) =>
          m.tenant_id === d.tenant_id && m.user_id === g.guardian_user_id && m.status !== "removed"
        )
      ) throw new StoreDenied("guardian_not_in_tenant");
    }
    this.db.guardian_sets.push({
      subject_user_id: this.me,
      share_set_version: d.share_set_version,
      n: d.n,
      k: d.k,
      tenant_id: d.tenant_id,
      created_at: this.now,
      superseded_at: null,
      source_record_id: null,
      updated_at: this.now,
    });
    for (const g of d.guardians) {
      const wk = this.db.addWrappedKey({
        kind: "guardian_share",
        user_id: g.guardian_user_id,
        share_set_version: d.share_set_version,
        blob: g.blob,
      });
      this.db.guardian_set_members.push({
        subject_user_id: this.me,
        share_set_version: d.share_set_version,
        guardian_user_id: g.guardian_user_id,
        umk_pub_ed: g.umk_pub_ed,
        wrapped_key_id: wk,
        updated_at: this.now,
      });
    }
    return Promise.resolve(d.share_set_version);
  }
  openRecovery(candidatePubX: Uint8Array): Promise<RecoveryRequest> {
    if (!this.me || !this.dev) throw new StoreDenied("no_claims");
    if (candidatePubX.length !== 32) throw new StoreDenied("recovery_shape");
    const d = this.db.devices.get(this.dev);
    // 0005's INSERT policy is the one that does NOT require a certified device — 04 §7.3 step 1 is
    // a fresh phone (ADR 2026-09-05d §2). It still has to be the caller's own live device — live as
    // rf.device_live_for (0010) reads it, `status <> 'revoked' and revoked_at is null`, the same
    // predicate hasGuardianSet uses, so the bit and the open refuse the same callers (E-24b-4).
    if (!d || d.user_id !== this.me || d.status === "revoked" || d.revoked_at) {
      throw new StoreDenied("unknown_candidate_device");
    }
    const set = this.currentGuardianSet(this.me);
    if (!set) throw new StoreDenied("no_guardian_set");
    const members = this.db.guardian_set_members.filter((m) =>
      m.subject_user_id === this.me && m.share_set_version === set.share_set_version
    );
    if (members.length !== set.n) throw new StoreDenied("guardian_set_incomplete");
    if (
      this.db.recovery_requests.filter((r) =>
        r.user_id === this.me && (r.expires_at as Date) > this.now
      ).length >= 5
    ) throw new StoreDenied("recovery_flood");
    // ADR 2026-09-05d §1 — the ladder is the SERVER's to choose, from one fact.
    const alarms = [...this.db.devices.values()].some((x) =>
      x.user_id === this.me && x.id !== this.dev && x.status === "certified" && !x.revoked_at
    );
    const row: Row = {
      id: uuid(),
      user_id: this.me,
      candidate_device: this.dev,
      candidate_pub_x: candidatePubX,
      share_set_version: set.share_set_version,
      state: alarms ? "waiting_24h" : "pending",
      approvals: 0,
      created_at: this.now,
      expires_at: new Date(this.now.getTime() + 72 * 3600_000),
      updated_at: this.now,
    };
    this.db.recovery_requests.push(row);
    return Promise.resolve(this.recoveryRow(row));
  }
  recoveryDecide(
    request: string,
    decision: "approved" | "denied",
    blob: Uint8Array | null,
    sealedTo: Uint8Array | null,
  ): Promise<string | null> {
    const r = this.db.recovery_requests.find((x) => x.id === request);
    const guardian = r &&
      this.db.guardian_set_members.some((m) =>
        m.subject_user_id === r.user_id && m.share_set_version === r.share_set_version &&
        m.guardian_user_id === this.me
      );
    // An unknown attempt and a caller who is not its guardian refuse identically: no oracle.
    if (!r || !this.isCertified() || !guardian) throw new StoreDenied("unknown_request");
    const p = this.derive(r);
    if (p.state !== "pending" && p.state !== "waiting_24h") {
      throw new StoreDenied("recovery_closed");
    }
    if (
      this.db.recovery_approvals.some((a) =>
        a.request_id === request && a.guardian_user_id === this.me
      )
    ) throw new StoreDenied("already_decided");
    let wk: string | null = null;
    if (decision === "approved") {
      if (!sealedTo || sealedTo.length !== 32) throw new StoreDenied("recovery_shape");
      // ADR 2026-09-13c §3: the re-seal goes to THIS attempt's candidate key, and only to it.
      if (!bytesEqual(sealedTo, r.candidate_pub_x as Uint8Array)) {
        throw new StoreDenied("candidate_key_mismatch");
      }
      if (!blob || blob.length === 0 || blob.length > 4096) throw new StoreDenied("recovery_shape");
      wk = this.db.addWrappedKey({
        kind: "recovery_blob",
        user_id: r.user_id as string,
        device_id: r.candidate_device as string,
        blob,
      });
    }
    this.db.recovery_approvals.push({
      request_id: request,
      guardian_user_id: this.me,
      guardian_device: this.dev,
      share_set_version: r.share_set_version,
      decision,
      wrapped_key_id: wk,
      sealed_to_pub_x: decision === "approved" ? sealedTo : null,
      created_at: this.now,
      updated_at: this.now,
    });
    return Promise.resolve(wk);
  }
  /** rf.recovery_derive, in TypeScript. Counts come from rows; nothing is read from `approvals`. */
  private derive(r: Row): RecoveryProgress {
    const set = this.db.guardian_sets.find((g) =>
      g.subject_user_id === r.user_id && g.share_set_version === r.share_set_version
    )!;
    const decisions = this.db.recovery_approvals.filter((a) => a.request_id === r.id)
      .sort((a, b) =>
        (a.created_at as Date).getTime() - (b.created_at as Date).getTime() ||
        String(a.guardian_user_id).localeCompare(String(b.guardian_user_id))
      );
    const approved = decisions.filter((a) => a.decision === "approved")
      .sort((a, b) => (a.created_at as Date).getTime() - (b.created_at as Date).getTime());
    const denials = decisions.filter((a) => a.decision === "denied").length;
    const cancelled = this.db.recovery_cancellations.find((c) => c.request_id === r.id);
    const k = set.k as number;
    const kth = approved.length >= k ? (approved[k - 1].created_at as Date) : null;
    // 0020 (ADR 2026-09-05d §1 🔒, 04 §7.3 step 6 🔒, asked at completion): the wait applies when
    // the attempt opened behind a live certified device OR the user has one NOW. Only tightened.
    const alarmsNow = [...this.db.devices.values()].some((x) =>
      x.user_id === r.user_id && x.id !== r.candidate_device && x.status === "certified" &&
      !x.revoked_at
    );
    const ladder = r.state === "waiting_24h" || alarmsNow ? "waiting_24h" : r.state as string;
    const wait = ladder === "waiting_24h" && kth ? new Date(kth.getTime() + 24 * 3600_000) : null;
    let state: string;
    if (cancelled) state = "cancelled";
    else if (denials >= 3) state = "expired"; // 04 §7.3 step 7
    else if (approved.length >= k) {
      state = !wait || this.now >= wait ? "approved" : "waiting_24h";
    } else if (this.now >= (r.expires_at as Date)) state = "expired";
    else state = ladder;
    return {
      request_id: r.id as string,
      user_id: r.user_id as string,
      candidate_device: r.candidate_device as string,
      share_set_version: r.share_set_version as number,
      k,
      n: set.n as number,
      approvals: approved.length,
      denials,
      opened_state: r.state as string,
      state,
      kth_approval_at: kth,
      wait_until: wait,
      expires_at: r.expires_at as Date,
      cancelled_at: (cancelled?.created_at as Date) ?? null,
      // 0010's recovery_approvals SELECT policy shows these rows to the requester and to the
      // candidate device, and `recoveryProgress` below has already refused everybody else. A
      // denial is a ROW here, which is what makes it distinguishable from silence.
      decisions: decisions.map((a) => ({
        guardian_user_id: a.guardian_user_id as string,
        decision: a.decision as "approved" | "denied",
        created_at: a.created_at as Date,
      })),
    };
  }
  recoveryProgress(request: string): Promise<RecoveryProgress | null> {
    const r = this.db.recovery_requests.find((x) => x.id === request);
    if (!r) return Promise.resolve(null);
    if (
      r.candidate_device !== this.dev && !(this.isCertified() && r.user_id === this.me)
    ) return Promise.resolve(null);
    return Promise.resolve(this.derive(r));
  }
  recoveryAsks(): Promise<RecoveryAsk[]> {
    if (!this.isCertified()) return Promise.resolve([]);
    const rows = this.db.recovery_requests.filter((r) =>
      r.user_id !== this.me && (r.expires_at as Date) > this.now &&
      this.db.guardian_set_members.some((m) =>
        m.subject_user_id === r.user_id && m.share_set_version === r.share_set_version &&
        m.guardian_user_id === this.me
      )
    );
    return Promise.resolve(rows.map((r) => ({
      request_id: r.id as string,
      subject_user_id: r.user_id as string,
      candidate_device: r.candidate_device as string,
      candidate_pub_x: r.candidate_pub_x as Uint8Array,
      share_set_version: r.share_set_version as number,
      created_at: r.created_at as Date,
      expires_at: r.expires_at as Date,
      my_decision: (this.db.recovery_approvals.find((a) =>
        a.request_id === r.id && a.guardian_user_id === this.me
      )?.decision as string) ?? null,
    })));
  }
  recoveryCancel(request: string): Promise<void> {
    const r = this.db.recovery_requests.find((x) => x.id === request);
    // ADR 2026-09-05d §1: the Cancel is on the devices that ALARM — an existing certified device of
    // the user. The candidate device cannot cancel the alarm raised against it.
    if (
      !r || !this.isCertified() || r.user_id !== this.me || r.candidate_device === this.dev
    ) throw new StoreDenied("rls");
    if (this.db.recovery_cancellations.some((c) => c.request_id === request)) {
      return Promise.resolve(); // first cancel wins; a second is the same outcome
    }
    this.db.recovery_cancellations.push({
      request_id: request,
      cancelled_by_user: this.me,
      cancelled_by_device: this.dev,
      created_at: this.now,
      updated_at: this.now,
    });
    return Promise.resolve();
  }
  myRecoveryRequests(): Promise<RecoveryRequest[]> {
    return Promise.resolve(
      this.db.recovery_requests
        .filter((r) =>
          r.candidate_device === this.dev || (this.isCertified() && r.user_id === this.me)
        )
        .map((r) => this.recoveryRow(r)),
    );
  }
  /** rf.recovery_shares (0020) in TypeScript — 04 §7.3 step 4. WHO: the caller that opened the
   *  attempt (user AND candidate device), on a device that is live and not suspended, for a user who
   *  is not erased. WHEN: the derived state is `approved`. WHAT: this attempt's own approvals,
   *  declared sealed to its candidate key, joined to recovery_blob rows addressed to its candidate
   *  device and not revoked. Everything else is the same empty array. */
  recoveryShares(request: string): Promise<RecoveryShare[]> {
    const none = Promise.resolve([] as RecoveryShare[]);
    const r = this.db.recovery_requests.find((x) => x.id === request);
    if (!r || !this.me || !this.dev) return none;
    if (r.user_id !== this.me || r.candidate_device !== this.dev) return none;
    const u = this.db.users.get(this.me);
    const d = this.db.devices.get(this.dev);
    if (!u || u.erased_at || !d || d.user_id !== this.me) return none;
    if (d.status === "revoked" || d.status === "suspended" || d.revoked_at) return none;
    if (this.derive(r).state !== "approved") return none;
    const out: RecoveryShare[] = [];
    const approvals = this.db.recovery_approvals
      .filter((a) =>
        a.request_id === r.id && a.decision === "approved" &&
        a.share_set_version === r.share_set_version &&
        bytesEqual(a.sealed_to_pub_x as Uint8Array, r.candidate_pub_x as Uint8Array)
      )
      .sort((a, b) =>
        (a.created_at as Date).getTime() - (b.created_at as Date).getTime() ||
        String(a.guardian_user_id).localeCompare(String(b.guardian_user_id))
      );
    for (const a of approvals) {
      const w = this.db.wrapped_keys.find((k) => k.id === a.wrapped_key_id);
      if (
        !w || w.kind !== "recovery_blob" || w.user_id !== r.user_id ||
        w.device_id !== r.candidate_device || w.revoked_at
      ) continue;
      out.push({
        wrapped_key_id: w.id as string,
        guardian_user_id: a.guardian_user_id as string,
        candidate_device: w.device_id as string,
        sealed_to_pub_x: a.sealed_to_pub_x as Uint8Array,
        share_set_version: a.share_set_version as number,
        blob: w.blob as Uint8Array,
        approved_at: a.created_at as Date,
      });
    }
    return Promise.resolve(out);
  }
  /** rf.has_guardian_set (0016) in TypeScript — ADR 2026-09-24b §3 🔒. Deliberately NOT gated on
   *  isCertified(); bounded instead to the caller's own user, a LIVE device of that user (0010's
   *  rf.device_live_for: not revoked, no revoked_at) and a user that is not erased. "Current" is
   *  currentGuardianSet — the same set openRecovery pins — so the bit and the open never disagree. */
  hasGuardianSet(): Promise<boolean> {
    // 0016 + 0025 (desk 45): a caller whose device claim is not a live device of its own live
    // user is REFUSED — one name for every such case, the open's own — never answered `false`,
    // which rung 2 would render as "you set nobody up" (04 §7.3 🔒). Live = rf.device_live_for:
    // not `revoked` and `revoked_at` null, so a SUSPENDED device is answered (reading (c)).
    const u = this.me ? this.db.users.get(this.me) : undefined;
    const d = this.dev ? this.db.devices.get(this.dev) : undefined;
    if (
      !u || u.erased_at || !d || d.user_id !== this.me || d.status === "revoked" || d.revoked_at
    ) {
      // A rejection, not a synchronous throw: PgStore's refusal arrives as a rejected promise.
      return Promise.reject(new StoreDenied("unknown_candidate_device"));
    }
    return Promise.resolve(this.currentGuardianSet(this.me!) !== null);
  }
  // ---- 04 §7.4 🔒 rung 3, the paper sheet (0011 in the database; mirrored here).
  publishRecoverySheet(blob: Uint8Array): Promise<number> {
    if (!this.isCertified()) throw new StoreDenied("rls"); // 0011 recovery_sheets_insert
    if (blob.length === 0 || blob.length > 4096) throw new StoreDenied("recovery_shape");
    const mine = this.db.recovery_sheets.filter((s) => s.user_id === this.me);
    const last = mine.at(-1);
    if (last && (last.created_at as Date).getTime() > this.now.getTime() - 60_000) {
      throw new StoreDenied("sheet_flood"); // ADR 2026-09-05b §7
    }
    const version = mine.reduce((m, s) => Math.max(m, s.sheet_version as number), 0) + 1;
    this.db.recovery_sheets.push({
      user_id: this.me,
      sheet_version: version,
      blob,
      created_at: this.now,
      updated_at: this.now,
    });
    return Promise.resolve(version);
  }
  recoverySheet(): Promise<RecoverySheet | null> {
    // The caller's OWN current sheet — certified or not, because the fresh phone of 06 §5 is the
    // one caller rung 3 exists for (0011 ⚠️ SPEC on ADR 2026-09-05d §2).
    const mine = this.db.recovery_sheets.filter((s) => s.user_id === this.me)
      .sort((a, b) => (a.sheet_version as number) - (b.sheet_version as number));
    const cur = mine.at(-1);
    return Promise.resolve(
      cur
        ? {
          user_id: cur.user_id as string,
          sheet_version: cur.sheet_version as number,
          blob: cur.blob as Uint8Array,
          created_at: cur.created_at as Date,
        }
        : null,
    );
  }
  private recoveryRow(r: Row): RecoveryRequest {
    return {
      id: r.id as string,
      user_id: r.user_id as string,
      candidate_device: r.candidate_device as string,
      candidate_pub_x: r.candidate_pub_x as Uint8Array,
      share_set_version: r.share_set_version as number,
      state: r.state as string,
      created_at: r.created_at as Date,
      expires_at: r.expires_at as Date,
    };
  }
  // ---- 06 §7 invites (0006/0008 in the database; mirrored here so the fake refuses what Postgres
  // refuses — a fake that is laxer than the row policies is a test that proves nothing).
  createInvite(
    record: string,
    tenant: string,
    inviteeHmac: Uint8Array,
    roles: unknown,
    nonce: Uint8Array,
  ): Promise<string> {
    if (!this.tenantAdmin(tenant)) throw new StoreDenied("not_admin");
    this.requireRecord(record, tenant, "invite");
    if (nonce.length !== 16) throw new StoreDenied("check"); // 06 §7: a 128-bit ceremony nonce
    for (const i of this.db.invites) {
      if (
        i.tenant_id === tenant && i.status === "sent" &&
        bytesEqual(i.invitee_hmac as Uint8Array, inviteeHmac)
      ) {
        i.status = "revoked"; // 06 §7 one-tap re-invite supersedes the live one
        i.updated_at = this.now;
      }
    }
    const id = uuid();
    this.db.invites.push({
      id,
      tenant_id: tenant,
      invitee_hmac: inviteeHmac,
      roles: roles ?? [],
      nonce,
      status: "sent",
      created_by: this.me,
      created_at: this.now,
      expires_at: new Date(this.now.getTime() + 7 * 24 * 3600 * 1000),
      accepted_by: null,
      accepted_at: null,
      source_record_id: record,
      updated_at: this.now,
    });
    return Promise.resolve(id);
  }
  // rf.my_invites as 0015 widened it (ADR 2026-09-25b §2): the caller's own number at `sent`, or
  // accepted by the caller, inside the 7-day window. Keyed on the user claim only, as in Postgres.
  // Each row carries its status and the live ones come first, in 0015's order (status <> 'sent',
  // expires_at, id) — insertion order would put an older, spent invite ahead of a live offer.
  myInvites(): Promise<InviteOffer[]> {
    const u = this.me ? this.db.users.get(this.me) : undefined;
    if (!u || u.erased_at) return Promise.resolve([]);
    const h = u.phone_hmac ?? null;
    const rank = (i: Row) => i.status === "sent" ? 0 : 1;
    return Promise.resolve(
      this.db.invites.filter((i) =>
        (i.expires_at as Date) > this.now &&
        ((i.status === "sent" && !!h && bytesEqual(i.invitee_hmac as Uint8Array, h)) ||
          (i.status === "accepted" && i.accepted_by === this.me))
      ).sort((x, y) =>
        rank(x) - rank(y) ||
        (x.expires_at as Date).getTime() - (y.expires_at as Date).getTime() ||
        ((x.id as string) < (y.id as string) ? -1 : (x.id as string) > (y.id as string) ? 1 : 0)
      ).map((i) => ({
        invite_id: i.id as string,
        tenant_id: i.tenant_id as string,
        roles: i.roles,
        expires_at: i.expires_at as Date,
        created_by: i.created_by as string,
        status: i.status as "sent" | "accepted",
        nonce: new Uint8Array(i.nonce as Uint8Array),
      })),
    );
  }
  acceptInvite(invite: string): Promise<InviteAccepted> {
    if (!this.me || !this.dev) throw new StoreDenied("no_claims");
    const u = this.db.users.get(this.me);
    const i = this.db.invites.find((x) => x.id === invite);
    // An unknown invite and a wrong number refuse identically: neither tells the caller which it was.
    if (!i) throw new StoreDenied("unknown_invite");
    if (
      !u?.phone_hmac || u.erased_at || !bytesEqual(i.invitee_hmac as Uint8Array, u.phone_hmac)
    ) throw new StoreDenied("phone_mismatch");
    if ((i.expires_at as Date) <= this.now) {
      if (i.status === "sent") i.status = "expired";
      throw new StoreDenied("invite_expired");
    }
    if (i.status !== "sent") throw new StoreDenied("invite_not_live");
    // 0006's upsert; 0027's trigger logs it (06 §7's re-admission is a membership change).
    this.db.writeMembership(
      i.tenant_id as string,
      this.me,
      "joined_pending_verification",
      (i.source_record_id as string | null) ?? null,
    );
    i.status = "accepted";
    i.accepted_by = this.me;
    i.accepted_at = this.now;
    i.updated_at = this.now;
    // ADR 2026-09-25b §2: the nonce comes back beside the status — the inviter's bytes, as stored.
    return Promise.resolve({
      status: "joined_pending_verification",
      nonce: new Uint8Array(i.nonce as Uint8Array),
    });
  }
  projectVerificationEvent(
    record: string,
    tenant: string,
    subject: string,
    verifier: string,
    method: string,
    result: string,
  ): Promise<void> {
    // ADR 2026-09-05d §7 / 0008: the row exists only as the copy of a signed `verification_event`.
    this.requireRecord(record, tenant, "verification_event");
    const m = this.db.memberships.find((x) => x.tenant_id === tenant && x.user_id === subject);
    if (!m || m.status === "removed") throw new StoreDenied("subject_not_in_tenant");
    this.db.verification_events.push({
      id: uuid(),
      tenant_id: tenant,
      subject_user: subject,
      verifier_user: verifier,
      method,
      result,
      at: this.now,
      source_record_id: record,
      updated_at: this.now,
    });
    // 06 §7's flip, as 0006 performs it in the database.
    if (m.status === "joined_pending_verification") {
      if (result === "verified") {
        m.status = "active";
        m.verified_by = verifier;
        m.verified_method = method;
        m.verified_at = this.now;
        m.updated_at = this.now;
        this.db.logMembership(m); // 0027's trigger: the ceremony's flip is a membership change
      } else if (result === "mismatch") {
        m.status = "blocked";
        m.updated_at = this.now;
        this.db.logMembership(m);
      }
    }
    return Promise.resolve();
  }
  markRecordApplied(record: string, note: string): Promise<void> {
    const r = this.db.signed_records.find((x) =>
      x.id === record && x.author_device === this.dev && !x.applied_at
    );
    if (r) {
      r.applied_at = this.now;
      r.apply_note = note;
    }
    return Promise.resolve();
  }
  // ---- auth
  findUserByPhoneHmac(h: Uint8Array): Promise<string | null> {
    for (const u of this.db.users.values()) {
      if (u.phone_hmac && bytesEqual(u.phone_hmac, h) && !u.erased_at) return Promise.resolve(u.id);
    }
    return Promise.resolve(null);
  }
  phoneCtForOtp(userId: string): Promise<Uint8Array | null> {
    return Promise.resolve(this.db.users.get(userId)?.phone_ct ?? null);
  }
  signupUser(hmac: Uint8Array, ct: Uint8Array, language: string | null): Promise<string> {
    return Promise.resolve(this.db.addUser({ phone_hmac: hmac, phone_ct: ct, language }).id);
  }
  otpChallengesSince(h: Uint8Array, since: Date): Promise<Date[]> {
    return Promise.resolve(
      this.db.otp_challenges.filter((c) => bytesEqual(c.phone_hmac, h) && c.created_at >= since)
        .map((c) => c.created_at),
    );
  }
  otpChallengesByIpSince(ip: Uint8Array, since: Date): Promise<number> {
    return Promise.resolve(
      this.db.otp_challenges.filter((c) =>
        c.ip_hash && bytesEqual(c.ip_hash, ip) && c.created_at >= since
      ).length,
    );
  }
  createOtpChallenge(c: Omit<OtpChallenge, "id">): Promise<string> {
    const id = uuid();
    this.db.otp_challenges.push({ id, ...c });
    return Promise.resolve(id);
  }
  latestOtpChallenge(h: Uint8Array, purpose: string): Promise<OtpChallenge | null> {
    const rows = this.db.otp_challenges.filter((c) =>
      bytesEqual(c.phone_hmac, h) && c.purpose === purpose
    )
      .sort((a, b) => b.created_at.getTime() - a.created_at.getTime());
    return Promise.resolve(rows[0] ?? null);
  }
  bumpOtpAttempts(id: string): Promise<number> {
    const c = this.db.otp_challenges.find((x) => x.id === id)!;
    c.attempts = Math.min(3, c.attempts + 1);
    return Promise.resolve(c.attempts);
  }
  consumeOtpChallenge(id: string): Promise<void> {
    const c = this.db.otp_challenges.find((x) => x.id === id);
    if (c) c.consumed_at = this.now;
    return Promise.resolve();
  }
  createActivationTicket(t: Omit<ActivationTicket, "id">): Promise<string> {
    const id = uuid();
    this.db.activation_tickets.push({ id, ...t });
    return Promise.resolve(id);
  }
  consumeActivationTicket(hash: Uint8Array, now: Date): Promise<ActivationTicket | null> {
    const t = this.db.activation_tickets.find((x) => bytesEqual(x.ticket_hash, hash));
    if (!t || t.consumed_at || t.expires_at <= now) return Promise.resolve(null);
    t.consumed_at = now;
    return Promise.resolve(t);
  }
  registerDevice(
    device: string,
    user: string,
    pubEd: Uint8Array,
    pubX: Uint8Array,
    model: string | null,
    os: string | null,
    attestation: unknown,
  ): Promise<string> {
    // ADR 2026-09-16 §2: the id is the client's. Same user + same keys on a live row is the
    // reinstall of 06 §5 — the row is returned, nothing is written, the cap is not charged.
    const held = this.db.devices.get(device);
    if (held) {
      if (
        held.user_id === user && bytesEqual(held.pub_ed, pubEd) && bytesEqual(held.pub_x, pubX) &&
        held.status !== "revoked"
      ) return Promise.resolve(held.id);
      throw new DeviceIdTakenError();
    }
    const active =
      [...this.db.devices.values()].filter((d) => d.user_id === user && d.status !== "revoked")
        .length;
    // rf.device_cap (0018): the highest `devices` among the user's active tenants' catalogue rows,
    // the floor's with none; NO_CAP sorts above every count (06 §6, ADR 2026-09-05g §7).
    const catalogue = new PlanCatalogue(this.db.plan_catalogue);
    const capOf = (plan: string | null) => {
      const d = catalogue.resolve(plan).limits.devices;
      return d === NO_CAP ? Infinity : d;
    };
    const caps = this.db.memberships.filter((m) => m.user_id === user && m.status === "active")
      .map((m) =>
        capOf(
          (this.db.subscriptions.find((s) => s.tenant_id === m.tenant_id)?.plan as string) ?? null,
        )
      );
    const cap = caps.length ? Math.max(...caps) : capOf(null);
    if (active >= cap) throw new DeviceCapError();
    const d = this.db.addDevice(user, pubEd, pubX, "registered", device);
    d.model = model;
    d.os = os;
    d.attestation = attestation;
    return Promise.resolve(d.id);
  }
  createNonce(nonce: Uint8Array, device: string, expires: Date): Promise<void> {
    this.db.auth_nonces.push({ nonce, device_id: device, expires_at: expires, consumed_at: null });
    return Promise.resolve();
  }
  consumeNonce(nonce: Uint8Array, device: string, now: Date): Promise<boolean> {
    const n = this.db.auth_nonces.find((x) => bytesEqual(x.nonce, nonce) && x.device_id === device);
    if (!n || n.consumed_at || n.expires_at <= now) return Promise.resolve(false);
    n.consumed_at = now;
    return Promise.resolve(true);
  }
  insertRefreshToken(t: RefreshToken): Promise<void> {
    this.db.refresh_tokens.push({ ...t });
    return Promise.resolve();
  }
  findRefreshToken(hash: Uint8Array): Promise<RefreshToken | null> {
    return Promise.resolve(
      this.db.refresh_tokens.find((t) => bytesEqual(t.token_hash, hash)) ?? null,
    );
  }
  rotateRefreshToken(oldHash: Uint8Array, next: RefreshToken): Promise<void> {
    const t = this.db.refresh_tokens.find((x) => bytesEqual(x.token_hash, oldHash));
    if (t) t.rotated_at = this.now;
    this.db.refresh_tokens.push({ ...next });
    return Promise.resolve();
  }
  revokeRefreshFamily(family: string): Promise<void> {
    for (const t of this.db.refresh_tokens) {
      if (t.family_id === family && !t.revoked_at) t.revoked_at = this.now;
    }
    return Promise.resolve();
  }
  // ---- 04 §3.1 / §6.3 🔒 both halves of the UMK public key. 0012's guards are re-stated here,
  // because a fake that is laxer than the database is a test that proves nothing: bounded to the
  // caller's own user, 32 bytes or nothing, and write-once with a one-time NULL → x backfill.
  umkPubs(user: string, version: number): Promise<UmkPublicRow | null> {
    if (user !== this.me) throw new StoreDenied("not_owner");
    const k = this.db.umk_public_keys.find((k) => k.user_id === user && k.key_version === version);
    return Promise.resolve(
      k ? { pub_ed: k.pub_ed as Uint8Array, pub_x: (k.pub_x as Uint8Array) ?? null } : null,
    );
  }
  setUmkPubs(
    user: string,
    version: number,
    pubEd: Uint8Array,
    pubX: Uint8Array | null,
  ): Promise<void> {
    if (user !== this.me) throw new StoreDenied("not_owner");
    if (pubEd.length !== 32) throw new StoreDenied("umk_pub_malformed");
    if (pubX && pubX.length !== 32) throw new StoreDenied("umk_pub_malformed");
    const k = this.db.umk_public_keys.find((k) => k.user_id === user && k.key_version === version);
    if (!k) {
      this.db.umk_public_keys.push({
        user_id: user,
        key_version: version,
        pub_ed: pubEd,
        pub_x: pubX,
        created_at: this.now,
        superseded_at: null,
        updated_at: this.now,
      });
      return Promise.resolve();
    }
    if (!bytesEqual(k.pub_ed as Uint8Array, pubEd)) throw new StoreDenied("umk_pub_conflict");
    if (!pubX) return Promise.resolve();
    if (!k.pub_x) { // a row written before 0012: fill it, once
      k.pub_x = pubX;
      k.updated_at = this.now;
      return Promise.resolve();
    }
    if (!bytesEqual(k.pub_x as Uint8Array, pubX)) throw new StoreDenied("umk_pub_conflict");
    return Promise.resolve();
  }
  certifyDevice(
    device: string,
    cert: Uint8Array,
    issuedAt: Date,
    issuedBy: string | null,
    umkVersion: number,
  ): Promise<void> {
    if (device !== this.dev) throw new StoreDenied("not_owner");
    this.db.device_certs = this.db.device_certs.filter((c) => c.device_id !== device);
    this.db.device_certs.push({
      device_id: device,
      cert,
      issued_by_device: issuedBy,
      issued_at: issuedAt,
      umk_key_version: umkVersion,
      updated_at: this.now,
    });
    const d = this.db.devices.get(device);
    if (d && d.status === "registered") {
      d.status = "certified";
      d.updated_at = this.now;
    }
    return Promise.resolve();
  }
  recordBillingEvent(
    eventId: string,
    gateway: string,
    type: string,
    hash: Uint8Array,
  ): Promise<boolean> {
    if (this.db.billing_events.has(eventId)) return Promise.resolve(false);
    this.db.billing_events.set(eventId, {
      event_id: eventId,
      gateway,
      type,
      payload_hash: hash,
      tenant_id: null,
      event_at: null,
      received_at: this.now,
      applied_at: null,
    });
    return Promise.resolve(true);
  }
  /** rf.apply_billing_event (migration 0013) restated in TypeScript, same order of decisions:
   *  resolve the tenant, record, then dedupe → action → tenant → ordering key → row → out-of-order
   *  → the one state change. Divergence between the two is a bug in whichever is not 0013. */
  applyBillingEvent(e: BillingEventApply): Promise<BillingApplyResult> {
    const byRef = e.gatewayRef == null
      ? undefined
      : this.db.subscriptions.find((s) =>
        s.gateway_ref === e.gatewayRef && (s.gateway == null || s.gateway === e.gateway)
      );
    const tenant = (byRef?.tenant_id as string | undefined) ?? e.tenantId;

    if (this.db.billing_events.has(e.eventId)) {
      return Promise.resolve({ fresh: false, applied: false, outcome: "duplicate" });
    }
    const rec: Row = {
      event_id: e.eventId,
      gateway: e.gateway,
      type: e.type,
      payload_hash: e.hash,
      tenant_id: tenant ?? null,
      event_at: e.eventAt,
      received_at: this.now,
      applied_at: null,
    };
    this.db.billing_events.set(e.eventId, rec);

    const done = (outcome: BillingApplyResult["outcome"]) =>
      Promise.resolve({ fresh: true, applied: false, outcome });
    if (e.action === "record_only") return done("not_applicable");
    if (!tenant) return done("unknown_tenant");
    if (!e.eventAt) return done("no_event_at");
    if (
      e.action === "activate" && e.plan != null &&
      !this.db.plan_catalogue.some((p) => p.id === e.plan)
    ) return done("unknown_plan"); // 0018: recorded, not applied
    const sub = this.db.subscriptions.find((s) => s.tenant_id === tenant);
    if (!sub) return done("unknown_tenant");

    let last: number | null = null;
    for (const b of this.db.billing_events.values()) {
      if (b.tenant_id !== tenant || b.applied_at == null || b.event_at == null) continue;
      const t = (b.event_at as Date).getTime();
      if (last === null || t > last) last = t;
    }
    if (last !== null && e.eventAt.getTime() <= last) return done("out_of_order");

    if (e.action === "activate") {
      sub.plan = e.plan ?? sub.plan;
      sub.status = "active";
      sub.current_period_end = e.periodEnd ?? sub.current_period_end;
      sub.gateway = e.gateway ?? sub.gateway;
      sub.gateway_ref = e.gatewayRef ?? sub.gateway_ref;
      sub.source = e.source ?? sub.source;
      sub.original_transaction_id = e.originalTransactionId ?? sub.original_transaction_id;
      sub.grace_until = null;
      sub.grace_kind = null;
    } else if (e.action === "dunning") {
      const base = (e.periodEnd ?? sub.current_period_end) as Date | null;
      if (!base) return done("no_period_end");
      sub.status = "past_due";
      sub.grace_kind = "dunning";
      sub.grace_until = new Date(base.getTime() + 7 * 86400e3);
    } else {
      sub.status = "expired";
      sub.grace_until = null;
      sub.grace_kind = null;
      sub.dispute_state = e.disputeState ?? sub.dispute_state;
    }
    sub.updated_at = this.now; // the subscriptions_touch trigger, 0004:21 — 05 §5's meta cursor
    rec.applied_at = this.now;
    return Promise.resolve({ fresh: true, applied: true, outcome: e.action });
  }
}
