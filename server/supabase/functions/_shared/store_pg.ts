// Postgres `Store` under the rf_api login (ADR 2026-09-05c §7): every call is ONE transaction that
// first runs rf.set_claims(...) — set_config(..., is_local => true), i.e. SET LOCAL — so pooled
// connections never carry claims across requests. Row policies (0005) do the authorisation; this
// file only shapes rows. It never reads a blob's content and never logs a row.
import postgres from "postgres";
import type { Claims } from "./claims.ts";
import type { Plan } from "./registry.ts";
import {
  type ActivationTicket,
  type BookAccess,
  denialFromPg,
  DeviceCapError,
  type EnvelopeRow,
  type GuardianSet,
  META_TABLES,
  type MetaCursor,
  type MetaTable,
  type OtpChallenge,
  type RefreshToken,
  type SignedRecordRow,
  type Store,
  StoreDenied,
  type Tx,
} from "./store.ts";

type Sql = postgres.Sql | postgres.TransactionSql;
type Row = Record<string, unknown>;

const PK: Record<MetaTable, string[]> = {
  memberships: ["tenant_id", "user_id"],
  book_roles: ["book_id", "user_id"],
  books: ["id"],
  devices: ["id"],
  device_certs: ["device_id"],
  wrapped_keys: ["id"],
  invites: ["id"],
  verification_events: ["id"],
  subscriptions: ["tenant_id"],
  entitlement_tokens: ["id"],
  recovery_requests: ["id"],
  escrow_policies: ["id"],
  guardian_sets: ["subject_user_id", "share_set_version"],
  guardian_set_members: ["subject_user_id", "share_set_version", "guardian_user_id"],
  tenant_freezes: ["tenant_id"],
  umk_public_keys: ["user_id", "key_version"],
};

export class PgStore implements Store {
  private sql: postgres.Sql;
  constructor(url: string) {
    this.sql = postgres(url, {
      max: 4,
      prepare: false, // transaction-mode pooler (config.toml [db.pooler])
      types: { bigint: postgres.BigInt },
      onnotice: () => {},
    });
  }
  async withClaims<T>(claims: Claims | null, fn: (tx: Tx) => Promise<T>): Promise<T> {
    try {
      return await this.sql.begin(async (sql) => {
        await sql`select rf.set_claims(${claims?.user_id ?? null}::uuid, ${
          claims?.device_id ?? null
        }::uuid)`;
        return await fn(new PgTx(sql));
      }) as T;
    } catch (e) {
      throw denialFromPg(e) ?? e;
    }
  }
  end(): Promise<void> {
    return this.sql.end();
  }
}

const big = (v: unknown): bigint => typeof v === "bigint" ? v : BigInt(String(v));
const bytes = (v: unknown): Uint8Array =>
  v instanceof Uint8Array ? new Uint8Array(v) : new Uint8Array();

class PgTx implements Tx {
  constructor(private sql: Sql) {}
  private async guarded<T>(fn: () => Promise<T>): Promise<T> {
    // A refused write inside the batch must not poison the whole transaction: savepoint per write.
    const tx = this.sql as postgres.TransactionSql;
    try {
      return await tx.savepoint(() => fn()) as T;
    } catch (e) {
      const d = denialFromPg(e);
      if (d) throw d;
      throw e;
    }
  }

  async storeEpoch(): Promise<string> {
    const [r] = await this.sql`select epoch from store_epoch where id`;
    if (!r) throw new Error("store_epoch row missing (seed.sql / README §5)");
    return r.epoch as string;
  }
  async appConfig(key: string): Promise<unknown> {
    const [r] = await this.sql`select value from app_config where key = ${key}`;
    return r?.value;
  }
  async bookAccess(bookId: string): Promise<BookAccess | null> {
    const [r] = await this.sql`select * from rf.book_access(${bookId}::uuid)`;
    if (!r) return null;
    return {
      tenant_id: r.tenant_id as string,
      archived: r.archived as boolean,
      role: (r.role as string) ?? null,
      membership_status: (r.membership_status as string) ?? null,
      frozen: r.frozen as boolean,
      plan: r.plan as Plan,
      envelope_count: Number(r.envelope_count),
      tenant_bytes: Number(r.tenant_bytes),
    };
  }
  async highestKeyVersion(bookId: string) {
    const [r] = await this.sql`select * from rf.highest_key_version(${bookId}::uuid)`;
    return r ? { key_version: r.key_version as number, issued_at: r.issued_at as Date } : null;
  }
  async pushRateCheck(deviceId: string, count: number, bytes: number): Promise<boolean> {
    const [r] = await this
      .sql`select rf.push_rate_check(${deviceId}::uuid, ${count}, ${bytes}) as ok`;
    return r.ok as boolean;
  }
  insertEnvelope(row: EnvelopeRow): Promise<{ seq: bigint; duplicate: boolean }> {
    return this.guarded(async () => {
      const [dup] = await this
        .sql`select seq from envelopes where envelope_id = ${row.envelope_id}`;
      if (dup) return { seq: big(dup.seq), duplicate: true };
      const [ins] = await this.sql`insert into envelopes
        (envelope_id, tenant_id, book_id, object_id, object_type, key_version, suite_version, payload_schema,
         author_device, hlc, blob_hash, size, blob, blob_ref)
        values (${row.envelope_id}, ${row.tenant_id}, ${row.book_id}, ${row.object_id}, ${row.object_type},
                ${row.key_version}, ${row.suite_version}, ${row.payload_schema}, ${row.author_device},
                ${row.hlc.toString()}::bigint, ${row.blob_hash}, ${row.size}, ${row.blob}, ${row.blob_ref})
        returning seq`;
      return { seq: big(ins.seq), duplicate: false };
    });
  }
  async pullEnvelopes(
    bookId: string,
    afterSeq: bigint,
    limit: number,
    objectTypes: string[] | null,
  ): Promise<EnvelopeRow[]> {
    const rows = await this.sql`select * from envelopes
      where book_id = ${bookId} and seq > ${afterSeq.toString()}::bigint
        ${objectTypes ? this.sql`and object_type = any(${objectTypes})` : this.sql``}
      order by seq limit ${limit}`;
    return rows.map((r) => ({
      envelope_id: r.envelope_id as string,
      seq: big(r.seq),
      tenant_id: r.tenant_id as string,
      book_id: r.book_id as string,
      object_id: r.object_id as string,
      object_type: r.object_type as string,
      key_version: r.key_version as number,
      suite_version: r.suite_version as number,
      payload_schema: r.payload_schema as number,
      author_device: r.author_device as string,
      hlc: big(r.hlc),
      blob_hash: bytes(r.blob_hash),
      size: r.size as number,
      blob: r.blob ? bytes(r.blob) : null,
      blob_ref: (r.blob_ref as string) ?? null,
    }));
  }
  async metaPage(table: MetaTable, after: MetaCursor | null, limit: number) {
    if (!META_TABLES.includes(table)) throw new Error(`unknown meta table ${table}`);
    const pk = PK[table];
    const idExpr = pk.map((c) => `${c}::text`).join(" || ':' || ");
    const rows = await this.sql.unsafe(
      `select *, (${idExpr}) as __id from ${table}
       where ($1::timestamptz is null or updated_at > $1 or (updated_at = $1 and (${idExpr}) > $2))
       order by updated_at, (${idExpr}) limit $3`,
      [after?.updated_at ?? null, after?.id ?? "", limit],
    ) as unknown as Row[];
    const last = rows.at(-1);
    const out = rows.map(({ __id: _drop, ...r }) => r);
    return {
      rows: out,
      next: rows.length === limit && last
        ? { updated_at: (last.updated_at as Date).toISOString(), id: last.__id as string }
        : null,
    };
  }
  async signedRecordsAfter(afterSeq: bigint, limit: number): Promise<SignedRecordRow[]> {
    const rows = await this
      .sql`select * from signed_records where seq > ${afterSeq.toString()}::bigint order by seq limit ${limit}`;
    return rows.map(recordRow);
  }
  async guardianSetHistory(subject: string): Promise<GuardianSet[]> {
    const sets = await this
      .sql`select * from guardian_sets where subject_user_id = ${subject} order by share_set_version`;
    const members = await this
      .sql`select * from guardian_set_members where subject_user_id = ${subject}`;
    return sets.map((s) => ({
      subject_user_id: subject,
      share_set_version: s.share_set_version as number,
      n: s.n as number,
      k: s.k as number,
      members: members.filter((m) => m.share_set_version === s.share_set_version)
        .map((m) => ({
          guardian_user_id: m.guardian_user_id as string,
          umk_pub_ed: bytes(m.umk_pub_ed),
        })),
    }));
  }
  insertSignedRecord(row: SignedRecordRow): Promise<{ seq: bigint; duplicate: boolean }> {
    return this.guarded(async () => {
      const [dup] = await this.sql`select seq from signed_records where id = ${row.id}`;
      if (dup) return { seq: big(dup.seq), duplicate: true };
      const [ins] = await this.sql`insert into signed_records
        (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
        values (${row.id}, ${row.suite_version}, ${row.tenant_id}, ${row.kind}, ${
        this.sql.json(row.payload_json as postgres.JSONValue)
      },
                ${row.payload_bytes}, ${row.author_device}, ${row.author_sig}, ${row.hlc.toString()}::bigint)
        returning seq`;
      return { seq: big(ins.seq), duplicate: false };
    });
  }
  async revocationRecordsFor(dev: string): Promise<SignedRecordRow[]> {
    const rows = await this.sql`select * from signed_records
      where kind = 'device_revocation' and payload_json->>'revoked_device_id' = ${dev} order by seq`;
    return rows.map(recordRow);
  }
  async deviceAuthRow(deviceId: string) {
    const [r] = await this.sql`select * from rf.device_auth_row(${deviceId}::uuid)`;
    return r
      ? { user_id: r.user_id as string, pub_ed: bytes(r.pub_ed), status: r.status as string }
      : null;
  }
  async isTenantAdmin(t: string): Promise<boolean> {
    const [r] = await this.sql`select rf.is_tenant_admin(${t}::uuid) as ok`;
    return r.ok as boolean;
  }
  async membershipCount(t: string): Promise<number> {
    // visible rows only — bootstrap is "no membership exists yet", which the caller can see when true
    const [r] = await this.sql`select count(*)::int as n from memberships where tenant_id = ${t}`;
    return r.n as number;
  }
  async bookInfo(bookId: string) {
    const [r] = await this.sql`select b.tenant_id, b.owner_user_id, b.type,
      (select count(*)::int from book_roles r where r.book_id = b.id) as role_count from books b where b.id = ${bookId}`;
    return r
      ? {
        tenant_id: r.tenant_id as string,
        owner_user_id: (r.owner_user_id as string) ?? null,
        type: r.type as string,
        role_count: r.role_count as number,
      }
      : null;
  }
  projectMembership(record: string, tenant: string, user: string, status: string): Promise<void> {
    return this.guarded(async () => {
      await this.sql`select rf.project_membership(${record}, ${tenant}, ${user}, ${status})`;
    });
  }
  projectBookRole(
    record: string,
    book: string,
    user: string,
    role: string | null,
    limit: bigint | null,
  ): Promise<void> {
    return this.guarded(async () => {
      await this.sql`select rf.project_book_role(${record}, ${book}, ${user}, ${role}, ${
        limit === null ? null : limit.toString()
      }::bigint)`;
    });
  }
  projectDeviceStatus(
    record: string,
    tenant: string,
    device: string,
    status: string,
  ): Promise<void> {
    return this.guarded(async () => {
      await this.sql`select rf.project_device_status(${record}, ${tenant}, ${device}, ${status})`;
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
    return this.guarded(async () => {
      await this
        .sql`select rf.project_verification_event(${record}, ${tenant}, ${subject}, ${verifier}, ${method}, ${result})`;
    });
  }
  async markRecordApplied(record: string, note: string): Promise<void> {
    await this.sql`select rf.mark_record_applied(${record}, ${note})`;
  }
  // ---- auth (security-definer functions: the only path to phone_hmac / phone_ct)
  async findUserByPhoneHmac(h: Uint8Array): Promise<string | null> {
    const [r] = await this.sql`select rf.find_user_by_phone_hmac(${h}) as id`;
    return (r?.id as string) ?? null;
  }
  async phoneCtForOtp(userId: string): Promise<Uint8Array | null> {
    const [r] = await this.sql`select rf.phone_ct_for_otp(${userId}::uuid) as ct`;
    return r?.ct ? bytes(r.ct) : null;
  }
  async signupUser(h: Uint8Array, ct: Uint8Array, language: string | null): Promise<string> {
    const [r] = await this.sql`select rf.signup_user(${h}, ${ct}, ${language}) as id`;
    return r.id as string;
  }
  async otpChallengesSince(h: Uint8Array, since: Date): Promise<Date[]> {
    const rows = await this
      .sql`select created_at from otp_challenges where phone_hmac = ${h} and created_at >= ${since}`;
    return rows.map((r) => r.created_at as Date);
  }
  async otpChallengesByIpSince(ip: Uint8Array, since: Date): Promise<number> {
    const [r] = await this
      .sql`select count(*)::int as n from otp_challenges where ip_hash = ${ip} and created_at >= ${since}`;
    return r.n as number;
  }
  async createOtpChallenge(c: Omit<OtpChallenge, "id">): Promise<string> {
    const [r] = await this
      .sql`insert into otp_challenges (phone_hmac, purpose, code_hash, attempts, channel, ip_hash, created_at, expires_at)
      values (${c.phone_hmac}, ${c.purpose}, ${c.code_hash}, ${c.attempts}, ${c.channel}, ${c.ip_hash}, ${c.created_at}, ${c.expires_at}) returning id`;
    return r.id as string;
  }
  async latestOtpChallenge(h: Uint8Array, purpose: string): Promise<OtpChallenge | null> {
    const [r] = await this
      .sql`select * from otp_challenges where phone_hmac = ${h} and purpose = ${purpose} order by created_at desc limit 1`;
    return r
      ? {
        ...r,
        phone_hmac: bytes(r.phone_hmac),
        code_hash: bytes(r.code_hash),
        ip_hash: r.ip_hash ? bytes(r.ip_hash) : null,
      } as OtpChallenge
      : null;
  }
  async bumpOtpAttempts(id: string): Promise<number> {
    const [r] = await this
      .sql`update otp_challenges set attempts = least(attempts + 1, 3) where id = ${id} returning attempts`;
    return r.attempts as number;
  }
  async consumeOtpChallenge(id: string): Promise<void> {
    await this.sql`update otp_challenges set consumed_at = now() where id = ${id}`;
  }
  async createActivationTicket(t: Omit<ActivationTicket, "id">): Promise<string> {
    const [r] = await this
      .sql`insert into activation_tickets (ticket_hash, phone_hmac, purpose, user_id, created_at, expires_at)
      values (${t.ticket_hash}, ${t.phone_hmac}, ${t.purpose}, ${t.user_id}, ${t.created_at}, ${t.expires_at}) returning id`;
    return r.id as string;
  }
  async consumeActivationTicket(hash: Uint8Array, now: Date): Promise<ActivationTicket | null> {
    const [r] = await this.sql`update activation_tickets set consumed_at = ${now}
      where ticket_hash = ${hash} and consumed_at is null and expires_at > ${now} returning *`;
    return r
      ? {
        ...r,
        ticket_hash: bytes(r.ticket_hash),
        phone_hmac: bytes(r.phone_hmac),
      } as ActivationTicket
      : null;
  }
  async registerDevice(
    user: string,
    pubEd: Uint8Array,
    pubX: Uint8Array,
    model: string | null,
    os: string | null,
    attestation: unknown,
  ): Promise<string> {
    try {
      const [r] = await this
        .sql`select rf.register_device(${user}::uuid, ${pubEd}, ${pubX}, ${model}, ${os},
        ${
        attestation === undefined || attestation === null
          ? null
          : this.sql.json(attestation as postgres.JSONValue)
      }) as id`;
      return r.id as string;
    } catch (e) {
      if (denialFromPg(e)?.reason === "device_cap") throw new DeviceCapError();
      throw e;
    }
  }
  async createNonce(nonce: Uint8Array, device: string, expires: Date): Promise<void> {
    await this
      .sql`insert into auth_nonces (nonce, device_id, expires_at) values (${nonce}, ${device}, ${expires})`;
  }
  async consumeNonce(nonce: Uint8Array, device: string, now: Date): Promise<boolean> {
    const rows = await this.sql`update auth_nonces set consumed_at = ${now}
      where nonce = ${nonce} and device_id = ${device} and consumed_at is null and expires_at > ${now} returning nonce`;
    return rows.length === 1;
  }
  async insertRefreshToken(t: RefreshToken): Promise<void> {
    await this
      .sql`insert into refresh_tokens (token_hash, family_id, device_id, user_id, created_at, expires_at)
      values (${t.token_hash}, ${t.family_id}, ${t.device_id}, ${t.user_id}, ${t.created_at}, ${t.expires_at})`;
  }
  async findRefreshToken(hash: Uint8Array): Promise<RefreshToken | null> {
    const [r] = await this.sql`select * from refresh_tokens where token_hash = ${hash}`;
    return r ? { ...r, token_hash: bytes(r.token_hash) } as RefreshToken : null;
  }
  async rotateRefreshToken(oldHash: Uint8Array, next: RefreshToken): Promise<void> {
    await this
      .sql`update refresh_tokens set rotated_at = ${next.created_at} where token_hash = ${oldHash}`;
    await this.insertRefreshToken(next);
  }
  async revokeRefreshFamily(family: string): Promise<void> {
    await this
      .sql`update refresh_tokens set revoked_at = now() where family_id = ${family} and revoked_at is null`;
  }
  async umkPubFor(user: string, version: number): Promise<Uint8Array | null> {
    const [r] = await this.sql`select rf.umk_pub_for(${user}::uuid, ${version}) as pub`;
    return r?.pub ? bytes(r.pub) : null;
  }
  setUmkPub(user: string, version: number, pub: Uint8Array): Promise<void> {
    return this.guarded(async () => {
      await this.sql`select rf.set_umk_pub(${user}::uuid, ${version}, ${pub})`;
    });
  }
  certifyDevice(
    device: string,
    cert: Uint8Array,
    issuedAt: Date,
    issuedBy: string | null,
    umkVersion: number,
  ): Promise<void> {
    return this.guarded(async () => {
      await this
        .sql`select rf.certify_device(${device}::uuid, ${cert}, ${issuedAt}, ${issuedBy}::uuid, ${umkVersion})`;
    });
  }
  async recordBillingEvent(
    eventId: string,
    gateway: string,
    type: string,
    hash: Uint8Array,
  ): Promise<boolean> {
    const [r] = await this
      .sql`select rf.record_billing_event(${eventId}, ${gateway}, ${type}, ${hash}) as fresh`;
    return r.fresh as boolean;
  }
}

function recordRow(r: Row): SignedRecordRow {
  return {
    id: r.id as string,
    seq: big(r.seq),
    suite_version: r.suite_version as number,
    tenant_id: r.tenant_id as string,
    kind: r.kind as string,
    payload_json: r.payload_json as Record<string, unknown>,
    payload_bytes: bytes(r.payload_bytes),
    author_device: r.author_device as string,
    author_sig: bytes(r.author_sig),
    hlc: big(r.hlc),
    applied_at: (r.applied_at as Date) ?? null,
  };
}
export { StoreDenied };
