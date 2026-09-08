// The narrow database seam every function talks to. `store_pg.ts` implements it against Postgres
// under the rf_api role with SET LOCAL claims; `store_mem.ts` is the fake for `deno test`.
// The server never parses a payload: blobs are opaque bytes, payload_json of signed records is
// plaintext by design (03 §4).
import type { Claims } from "./claims.ts";
import type { Plan } from "./registry.ts";

export interface BookAccess {
  tenant_id: string;
  archived: boolean;
  role: string | null;
  membership_status: string | null;
  frozen: boolean;
  plan: Plan;
  envelope_count: number;
  tenant_bytes: number;
}
export interface EnvelopeRow {
  envelope_id: string;
  seq?: bigint;
  tenant_id: string;
  book_id: string;
  object_id: string;
  object_type: string;
  key_version: number;
  suite_version: number;
  payload_schema: number;
  author_device: string;
  hlc: bigint;
  blob_hash: Uint8Array;
  size: number;
  blob: Uint8Array | null;
  blob_ref: string | null;
}
export interface SignedRecordRow {
  id: string;
  seq?: bigint;
  suite_version: number;
  tenant_id: string;
  kind: string;
  payload_json: Record<string, unknown>;
  payload_bytes: Uint8Array;
  author_device: string;
  author_sig: Uint8Array;
  hlc: bigint;
  applied_at?: Date | null;
}
export interface GuardianSet {
  subject_user_id: string;
  share_set_version: number;
  n: number;
  k: number;
  members: { guardian_user_id: string; umk_pub_ed: Uint8Array }[];
}
export interface MetaCursor {
  updated_at: string; // ISO-8601
  id: string; // primary key rendered as text ('a:b' for composite keys)
}
export type MetaCursors = Record<string, MetaCursor>;
export const META_TABLES = [
  "memberships",
  "book_roles",
  "books",
  "devices",
  "device_certs",
  "wrapped_keys",
  "invites",
  "verification_events",
  "subscriptions",
  "entitlement_tokens",
  "recovery_requests",
  "escrow_policies",
  "guardian_sets",
  "guardian_set_members",
  "tenant_freezes",
  "umk_public_keys",
] as const;
export type MetaTable = typeof META_TABLES[number];

/** Primary key as text — composite keys joined with ':' (05 §5 cursor id; wire `id` for composite rows). */
export function rowId(table: MetaTable, r: Record<string, unknown>): string {
  switch (table) {
    case "memberships":
      return `${r.tenant_id}:${r.user_id}`;
    case "book_roles":
      return `${r.book_id}:${r.user_id}`;
    case "device_certs":
      return r.device_id as string;
    case "subscriptions":
    case "tenant_freezes":
      return r.tenant_id as string;
    case "guardian_sets":
      return `${r.subject_user_id}:${r.share_set_version}`;
    case "guardian_set_members":
      return `${r.subject_user_id}:${r.share_set_version}:${r.guardian_user_id}`;
    case "umk_public_keys":
      return `${r.user_id}:${r.key_version}`;
    default:
      return r.id as string;
  }
}

export interface OtpChallenge {
  id: string;
  phone_hmac: Uint8Array;
  purpose: string;
  code_hash: Uint8Array;
  attempts: number;
  channel: "whatsapp" | "sms";
  ip_hash: Uint8Array | null;
  created_at: Date;
  expires_at: Date;
  consumed_at: Date | null;
}
export interface ActivationTicket {
  id: string;
  ticket_hash: Uint8Array;
  phone_hmac: Uint8Array;
  purpose: string;
  user_id: string | null;
  created_at: Date;
  expires_at: Date;
  consumed_at: Date | null;
}
export interface RefreshToken {
  token_hash: Uint8Array;
  family_id: string;
  device_id: string;
  user_id: string;
  created_at: Date;
  expires_at: Date;
  rotated_at: Date | null;
  revoked_at: Date | null;
}

export interface Tx {
  storeEpoch(): Promise<string>;
  appConfig(key: string): Promise<unknown>;
  // sync
  bookAccess(bookId: string): Promise<BookAccess | null>;
  highestKeyVersion(bookId: string): Promise<{ key_version: number; issued_at: Date } | null>;
  pushRateCheck(deviceId: string, count: number, bytes: number): Promise<boolean>;
  insertEnvelope(row: EnvelopeRow): Promise<{ seq: bigint; duplicate: boolean }>;
  pullEnvelopes(
    bookId: string,
    afterSeq: bigint,
    limit: number,
    objectTypes: string[] | null,
  ): Promise<EnvelopeRow[]>;
  metaPage(
    table: MetaTable,
    after: MetaCursor | null,
    limit: number,
  ): Promise<{ rows: Record<string, unknown>[]; next: MetaCursor | null }>;
  signedRecordsAfter(afterSeq: bigint, limit: number): Promise<SignedRecordRow[]>;
  guardianSetHistory(subjectUserId: string): Promise<GuardianSet[]>;
  // signed records
  insertSignedRecord(row: SignedRecordRow): Promise<{ seq: bigint; duplicate: boolean }>;
  revocationRecordsFor(revokedDeviceId: string): Promise<SignedRecordRow[]>;
  deviceAuthRow(
    deviceId: string,
  ): Promise<{ user_id: string; pub_ed: Uint8Array; status: string } | null>;
  isTenantAdmin(tenantId: string): Promise<boolean>;
  membershipCount(tenantId: string): Promise<number>;
  bookInfo(
    bookId: string,
  ): Promise<
    { tenant_id: string; owner_user_id: string | null; type: string; role_count: number } | null
  >;
  projectMembership(record: string, tenant: string, user: string, status: string): Promise<void>;
  projectBookRole(
    record: string,
    book: string,
    user: string,
    role: string | null,
    limit: bigint | null,
  ): Promise<void>;
  projectDeviceStatus(
    record: string,
    tenant: string,
    device: string,
    status: string,
  ): Promise<void>;
  projectVerificationEvent(
    record: string,
    tenant: string,
    subject: string,
    verifier: string,
    method: string,
    result: string,
  ): Promise<void>;
  markRecordApplied(record: string, note: string): Promise<void>;
  // auth (pre-JWT paths go through security-definer functions in Postgres)
  findUserByPhoneHmac(hmac: Uint8Array): Promise<string | null>;
  phoneCtForOtp(userId: string): Promise<Uint8Array | null>;
  signupUser(hmac: Uint8Array, ct: Uint8Array, language: string | null): Promise<string>;
  otpChallengesSince(phoneHmac: Uint8Array, since: Date): Promise<Date[]>;
  otpChallengesByIpSince(ipHash: Uint8Array, since: Date): Promise<number>;
  createOtpChallenge(c: Omit<OtpChallenge, "id">): Promise<string>;
  latestOtpChallenge(phoneHmac: Uint8Array, purpose: string): Promise<OtpChallenge | null>;
  bumpOtpAttempts(id: string): Promise<number>;
  consumeOtpChallenge(id: string): Promise<void>;
  createActivationTicket(t: Omit<ActivationTicket, "id">): Promise<string>;
  consumeActivationTicket(ticketHash: Uint8Array, now: Date): Promise<ActivationTicket | null>;
  registerDevice(
    user: string,
    pubEd: Uint8Array,
    pubX: Uint8Array,
    model: string | null,
    os: string | null,
    attestation: unknown,
  ): Promise<string>;
  createNonce(nonce: Uint8Array, device: string, expires: Date): Promise<void>;
  consumeNonce(nonce: Uint8Array, device: string, now: Date): Promise<boolean>;
  insertRefreshToken(t: RefreshToken): Promise<void>;
  findRefreshToken(hash: Uint8Array): Promise<RefreshToken | null>;
  rotateRefreshToken(oldHash: Uint8Array, next: RefreshToken): Promise<void>;
  revokeRefreshFamily(familyId: string): Promise<void>;
  umkPubFor(user: string, version: number): Promise<Uint8Array | null>;
  setUmkPub(user: string, version: number, pub: Uint8Array): Promise<void>;
  certifyDevice(
    device: string,
    cert: Uint8Array,
    issuedAt: Date,
    issuedBy: string | null,
    umkVersion: number,
  ): Promise<void>;
  // billing
  recordBillingEvent(
    eventId: string,
    gateway: string,
    type: string,
    hash: Uint8Array,
  ): Promise<boolean>;
}

export interface Store {
  /** One transaction; claims become SET LOCAL settings inside it (null = pre-JWT path). */
  withClaims<T>(claims: Claims | null, fn: (tx: Tx) => Promise<T>): Promise<T>;
}

export class DeviceCapError extends Error {
  constructor() {
    super("device_cap");
  }
}

/** A write the row policies refused (RLS `with check`, `rf.require_record`, `not_owner`…). Never content. */
export class StoreDenied extends Error {
  constructor(public readonly reason: string) {
    super(reason);
  }
}

/** Maps a Postgres error raised by 0003/0005 onto StoreDenied; anything else is rethrown. */
export function denialFromPg(e: unknown): StoreDenied | null {
  const msg = (e as { message?: string })?.message ?? "";
  const code = (e as { code?: string })?.code ?? "";
  if (code === "42501" || code === "28000") return new StoreDenied("rls"); // insufficient_privilege
  if (code === "P0001") return new StoreDenied(msg.split(/\s/)[0]); // raise exception '<reason>'
  if (code === "23514") return new StoreDenied("check"); // check_violation (caps, enums)
  if (code === "23503") return new StoreDenied("fk"); // unknown book / tenant / device
  return null;
}
