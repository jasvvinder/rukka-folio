// In-memory `Store` for `deno test`: the same seam as store_pg.ts with the 0005 row policies
// re-stated in TypeScript (certified-only, active membership, writer roles, projection-needs-record,
// append-only). Tests seed `MemDb` directly; functions only ever see `Tx`. Clock is injected.
import type { Claims } from "./claims.ts";
import { bytesEqual } from "./bytes.ts";
import type { Plan } from "./registry.ts";
import { WRITER_ROLES } from "./registry.ts";
import {
  type ActivationTicket,
  type BookAccess,
  DeviceCapError,
  type EnvelopeRow,
  type GuardianSet,
  META_TABLES,
  type MetaCursor,
  type MetaTable,
  type OtpChallenge,
  type RefreshToken,
  rowId,
  type SignedRecordRow,
  type Store,
  StoreDenied,
  type Tx,
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

export class MemDb {
  now: () => Date = () => new Date();
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
  recovery_requests: Row[] = [];
  escrow_policies: Row[] = [];
  subscriptions: Row[] = [];
  entitlement_tokens: Row[] = [];
  tenant_freezes: Row[] = [];
  envelopes: EnvelopeRow[] = [];
  signed_records: (SignedRecordRow & { apply_note?: string | null })[] = [];
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
  billing_events = new Set<string>();

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
    this.memberships.push({
      tenant_id,
      user_id,
      status,
      source_record_id: null,
      updated_at: this.now(),
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
  ): MemDevice {
    const t = this.now();
    const d: MemDevice = {
      id: uuid(),
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
  ): void {
    this.guardian_sets.push({
      subject_user_id: subject,
      share_set_version: version,
      n: guardians.length,
      k,
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
  setPlan(tenant_id: string, plan: Plan): void {
    this.subscriptions = this.subscriptions.filter((s) => s.tenant_id !== tenant_id);
    this.subscriptions.push({ tenant_id, plan, status: "active", updated_at: this.now() });
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
    const plan = (this.db.subscriptions.find((s) => s.tenant_id === t)?.plan as Plan) ?? "free";
    const count = this.db.envelopes.filter((e) => e.book_id === bookId).length;
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
        return r.user_id === this.me && (r.device_id === this.dev || this.isCertified());
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
    if (!this.isCertified() || row.author_device !== this.dev) throw new StoreDenied("rls");
    if (!this.db.tenants.has(row.tenant_id)) throw new StoreDenied("fk");
    const seq = ++this.db.seq;
    this.db.signed_records.push({ ...row, seq, applied_at: null, apply_note: null });
    return Promise.resolve({ seq, duplicate: false });
  }
  revocationRecordsFor(dev: string): Promise<SignedRecordRow[]> {
    return Promise.resolve(
      this.db.signed_records.filter((r) =>
        r.kind === "device_revocation" && r.payload_json.revoked_device_id === dev &&
        (this.activeInTenant(r.tenant_id) || r.author_device === this.dev)
      ),
    );
  }
  deviceAuthRow(deviceId: string) {
    const d = this.db.devices.get(deviceId);
    return Promise.resolve(d ? { user_id: d.user_id, pub_ed: d.pub_ed, status: d.status } : null);
  }
  isTenantAdmin(t: string): Promise<boolean> {
    return Promise.resolve(this.tenantAdmin(t));
  }
  membershipCount(t: string): Promise<number> {
    return Promise.resolve(this.db.memberships.filter((m) => m.tenant_id === t).length);
  }
  bookInfo(bookId: string) {
    const b = this.db.books.get(bookId);
    if (!b) return Promise.resolve(null);
    return Promise.resolve({
      tenant_id: b.tenant_id as string,
      owner_user_id: b.owner_user_id as string | null,
      type: b.type as string,
      role_count: this.db.book_roles.filter((r) => r.book_id === bookId).length,
    });
  }
  private requireRecord(record: string, tenant: string): void {
    if (
      !this.db.signed_records.some((r) =>
        r.id === record && r.tenant_id === tenant && r.author_device === this.dev
      )
    ) {
      throw new StoreDenied("no_record");
    }
  }
  projectMembership(record: string, tenant: string, user: string, status: string): Promise<void> {
    this.requireRecord(record, tenant);
    const m = this.db.memberships.find((x) => x.tenant_id === tenant && x.user_id === user);
    if (m) {
      m.status = status;
      m.source_record_id = record;
      m.updated_at = this.now;
    } else {this.db.memberships.push({
        tenant_id: tenant,
        user_id: user,
        status,
        source_record_id: record,
        updated_at: this.now,
      });}
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
    const t = this.db.books.get(book)?.tenant_id as string;
    this.requireRecord(record, t);
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
    const d = this.db.devices.get(device);
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
  projectVerificationEvent(
    record: string,
    tenant: string,
    subject: string,
    verifier: string,
    method: string,
    result: string,
  ): Promise<void> {
    this.requireRecord(record, tenant);
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
    user: string,
    pubEd: Uint8Array,
    pubX: Uint8Array,
    model: string | null,
    os: string | null,
    attestation: unknown,
  ): Promise<string> {
    const active =
      [...this.db.devices.values()].filter((d) => d.user_id === user && d.status !== "revoked")
        .length;
    const plans = this.db.memberships.filter((m) => m.user_id === user && m.status === "active")
      .map((m) =>
        (this.db.subscriptions.find((s) => s.tenant_id === m.tenant_id)?.plan as string) ?? "free"
      );
    const cap = Math.max(5, ...plans.map((p) => p === "family_plus" ? 15 : p === "family" ? 8 : 5));
    if (active >= cap) throw new DeviceCapError();
    const d = this.db.addDevice(user, pubEd, pubX, "registered");
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
  umkPubFor(user: string, version: number): Promise<Uint8Array | null> {
    return Promise.resolve(
      (this.db.umk_public_keys.find((k) => k.user_id === user && k.key_version === version)
        ?.pub_ed as Uint8Array) ?? null,
    );
  }
  setUmkPub(user: string, version: number, pub: Uint8Array): Promise<void> {
    if (user !== this.me) throw new StoreDenied("not_owner");
    if (!this.db.umk_public_keys.some((k) => k.user_id === user && k.key_version === version)) {
      this.db.umk_public_keys.push({
        user_id: user,
        key_version: version,
        pub_ed: pub,
        created_at: this.now,
        superseded_at: null,
        updated_at: this.now,
      });
    }
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
  recordBillingEvent(eventId: string): Promise<boolean> {
    if (this.db.billing_events.has(eventId)) return Promise.resolve(false);
    this.db.billing_events.add(eventId);
    return Promise.resolve(true);
  }
}
