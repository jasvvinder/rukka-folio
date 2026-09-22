// In-memory `Store` for `deno test`: the same seam as store_pg.ts with the 0005 row policies
// re-stated in TypeScript (certified-only, active membership, writer roles, projection-needs-record,
// append-only). Tests seed `MemDb` directly; functions only ever see `Tx`. Clock is injected.
import type { Claims } from "./claims.ts";
import { bytesEqual } from "./bytes.ts";
import type { Plan } from "./registry.ts";
import { WRITER_ROLES } from "./registry.ts";
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
  type InviteOffer,
  META_TABLES,
  type MetaCursor,
  type MetaTable,
  type OtpChallenge,
  type RecoveryAsk,
  type RecoveryProgress,
  type RecoveryRequest,
  type RecoverySheet,
  type RefreshToken,
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
  /** event_id → the recorded row. 0013 widened the table with `tenant_id` and `event_at`: the
   *  out-of-order guard of ADR 2026-09-05g §9 needs to know which subscription an event belongs to
   *  and when the GATEWAY raised it. `payload_hash` is all we keep of the body (rule 4). */
  billing_events = new Map<string, Row>();

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
        sub_updated_at: (s?.updated_at as Date | null) ?? null,
        token_created_at: (e?.created_at as Date | null) ?? null,
        token_expires_at: (e?.expires_at as Date | null) ?? null,
      });
    }
    out.sort((a, b) => a.tenant_id < b.tenant_id ? -1 : a.tenant_id > b.tenant_id ? 1 : 0);
    return Promise.resolve(out);
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
  membershipStatus(t: string, u: string): Promise<string | null> {
    const m = this.db.memberships.find((x) => x.tenant_id === t && x.user_id === u);
    return Promise.resolve((m?.status as string) ?? null);
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
    const hi = this.db.guardian_sets.filter((g) => g.subject_user_id === this.me)
      .reduce((m, g) => Math.max(m, g.share_set_version as number), 0);
    if (d.share_set_version !== hi + 1) throw new StoreDenied("share_set_version_out_of_order");
    for (const g of d.guardians) {
      // 0005: a guardian_share for somebody else needs a shared tenant.
      if (!this.sharesTenant(g.guardian_user_id)) throw new StoreDenied("rls");
    }
    this.db.guardian_sets.push({
      subject_user_id: this.me,
      share_set_version: d.share_set_version,
      n: d.n,
      k: d.k,
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
    // a fresh phone (ADR 2026-09-05d §2). It still has to be the caller's own live device.
    if (!d || d.user_id !== this.me || d.status === "revoked") {
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
    const wait = r.state === "waiting_24h" && kth ? new Date(kth.getTime() + 24 * 3600_000) : null;
    let state: string;
    if (cancelled) state = "cancelled";
    else if (denials >= 3) state = "expired"; // 04 §7.3 step 7
    else if (approved.length >= k) {
      state = !wait || this.now >= wait ? "approved" : "waiting_24h";
    } else if (this.now >= (r.expires_at as Date)) state = "expired";
    else state = r.state as string;
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
  myInvites(): Promise<InviteOffer[]> {
    const h = this.me ? this.db.users.get(this.me)?.phone_hmac ?? null : null;
    if (!h) return Promise.resolve([]);
    return Promise.resolve(
      this.db.invites.filter((i) =>
        i.status === "sent" && (i.expires_at as Date) > this.now &&
        bytesEqual(i.invitee_hmac as Uint8Array, h)
      ).map((i) => ({
        invite_id: i.id as string,
        tenant_id: i.tenant_id as string,
        roles: i.roles,
        expires_at: i.expires_at as Date,
        created_by: i.created_by as string,
      })),
    );
  }
  acceptInvite(invite: string): Promise<string> {
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
    const m = this.db.memberships.find((x) => x.tenant_id === i.tenant_id && x.user_id === this.me);
    if (m) {
      m.status = "joined_pending_verification";
      m.source_record_id = i.source_record_id;
      m.updated_at = this.now;
    } else {
      this.db.memberships.push({
        tenant_id: i.tenant_id,
        user_id: this.me,
        status: "joined_pending_verification",
        source_record_id: i.source_record_id,
        updated_at: this.now,
      });
    }
    i.status = "accepted";
    i.accepted_by = this.me;
    i.accepted_at = this.now;
    i.updated_at = this.now;
    return Promise.resolve("joined_pending_verification");
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
      } else if (result === "mismatch") {
        m.status = "blocked";
        m.updated_at = this.now;
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
    const plans = this.db.memberships.filter((m) => m.user_id === user && m.status === "active")
      .map((m) =>
        (this.db.subscriptions.find((s) => s.tenant_id === m.tenant_id)?.plan as string) ?? "free"
      );
    const cap = Math.max(5, ...plans.map((p) => p === "family_plus" ? 15 : p === "family" ? 8 : 5));
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
