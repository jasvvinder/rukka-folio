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

/** One tenant's entitlement facts, as the meta pull reads them: the caller's active tenant, the
 *  subscription row it has (or no row at all), and the freshness markers of whatever token is
 *  stored. Nothing here comes from an envelope, a blob, a wrapped key or an attachment — the mint
 *  path is content-blind by construction (06 §10 🔒, 08 §5). */
export interface EntitlementState {
  tenant_id: string;
  plan: string | null; // null when the tenant has no subscriptions row at all → Free
  status: string | null;
  current_period_end: Date | null;
  trial_end: Date | null;
  grace_kind: string | null;
  sub_updated_at: Date | null;
  token_created_at: Date | null; // null when nothing is stored yet
  token_expires_at: Date | null;
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

/** 04 §3.1 — the UMK's two public halves. 04 §6.3 🔒 compares BOTH byte-for-byte, so both travel.
 *  `pub_x` is NULL on any row whose writer offered no x half. That is not only the rows written
 *  before migration 0012: as of this milestone NO client sends `umk_pub_x` at all (the app's
 *  /devices/certify body carries `umk_key_version` + `umk_pub_ed` only), so every row is ed-only
 *  and 04 §6's MANDATORY ceremony stays unpassable until the client offers the half. The server
 *  side is ready; the wire is not yet driven. See the lane report's CLIENT GAP item. */
export interface UmkPublicRow {
  pub_ed: Uint8Array;
  pub_x: Uint8Array | null;
}

/** ADR 2026-09-13d ruling 4: commitment 32 B, verifier_random 16 B, opening 16 B + server times. */
export interface CeremonySession {
  id: string;
  tenant_id: string;
  subject_user: string;
  commitment: Uint8Array;
  committed_at: Date;
  expires_at: Date;
  verifier_user: string | null;
  verifier_random: Uint8Array | null;
  verifier_random_at: Date | null;
  opening: Uint8Array | null;
  opened_at: Date | null;
}

/** 04 §7.3 Setup — one publication of a guardian set: the set, its members and one sealed share
 *  per guardian. The server stores what the client sealed and computes nothing (04 §8.6). */
export interface GuardianSetDraft {
  share_set_version: number;
  k: number;
  n: number;
  guardians: { guardian_user_id: string; umk_pub_ed: Uint8Array; blob: Uint8Array }[];
}

/** 04 §7.3 step 1 — the fresh phone's ask. `candidate_pub_x` is the *candidate* X25519 public key
 *  every guardian re-seals to and compares against the scanned QR (ADR 2026-09-13c §3). */
export interface RecoveryRequest {
  id: string;
  user_id: string;
  candidate_device: string;
  candidate_pub_x: Uint8Array;
  share_set_version: number;
  /** The LADDER the attempt opened on, not the live state — read `RecoveryProgress.state` for that. */
  state: string;
  created_at: Date;
  expires_at: Date;
}

/** One guardian's decision, as the append-only row records it (0010 `recovery_approvals`).
 *
 *  A count is not an attribution: `approvals: 2` cannot say *which* two, and S11.2 has to tick the
 *  members it names (ADR 2026-09-06 § Consequences), a cancel has to notify "the guardians who
 *  approved" (ADR 2026-09-05d §1), and a DENIAL has to be distinguishable from SILENCE (04 §7.3
 *  step 7: three denials close the attempt). The rows answer all three; the counter answers none.
 *
 *  Nothing here is a share and nothing here is financial: a user id, a word, and a time. */
export interface RecoveryDecision {
  guardian_user_id: string;
  decision: "approved" | "denied";
  created_at: Date;
}

/** The derived state (0010 `rf.recovery_progress`): counts come from the append-only decision rows,
 *  never from `recovery_requests.approvals`, which is vestigial. */
export interface RecoveryProgress {
  request_id: string;
  user_id: string;
  candidate_device: string;
  share_set_version: number;
  k: number;
  n: number;
  approvals: number;
  denials: number;
  opened_state: string;
  state: string;
  kth_approval_at: Date | null;
  wait_until: Date | null;
  expires_at: Date;
  cancelled_at: Date | null;
  /** Who decided, and which way — the rows the counts above were derived from. Readable by the
   *  requester and by its candidate device, under the SELECT policy 0010 already wrote; a caller
   *  who cannot read the progress reads no decision either (ADR 2026-09-05d §2). */
  decisions: RecoveryDecision[];
}

/** 04 §7.4 🔒 rung 3 — the paper sheet's server half. `sealed_rk_blob = XChaCha20(RK, UMK_priv)`:
 *  opaque bytes the server stores and returns and can never open, because RK lives on paper and
 *  never on this server. A new sheet is a NEW VERSION, never a rewrite (0011, CLAUDE.md rule 2). */
export interface RecoverySheet {
  user_id: string;
  sheet_version: number;
  blob: Uint8Array;
  created_at: Date;
}

/** 04 §7.3 step 2 — what a guardian is pushed: who, which new device, and its candidate key.
 *  Nothing financial; there is no book, tenant or amount anywhere in this shape. */
export interface RecoveryAsk {
  request_id: string;
  subject_user_id: string;
  candidate_device: string;
  candidate_pub_x: Uint8Array;
  share_set_version: number;
  created_at: Date;
  expires_at: Date;
  /** This guardian's own decision, or null while the ask is open. Never another guardian's. */
  my_decision: string | null;
}

/** 06 §7: what a joining device may learn about an invite addressed to its OWN number. */
export interface InviteOffer {
  invite_id: string;
  tenant_id: string;
  roles: unknown;
  expires_at: Date;
  created_by: string;
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
  // 08 §3 🔒 / ADR 2026-09-05g §1 🔒 — the entitlement token, refreshed on every meta pull.
  /** The caller's OWN active tenants and their entitlement facts. Never another tenant's. */
  entitlementStates(): Promise<EntitlementState[]>;
  /** Store the freshly minted token for one of the caller's active tenants. rf_api holds no INSERT
   *  or UPDATE grant on `entitlement_tokens`; this goes through rf.mint_entitlement_token (0014),
   *  which re-checks the membership itself. */
  putEntitlementToken(tenantId: string, token: Uint8Array, expiresAt: Date): Promise<void>;
  guardianSetHistory(subjectUserId: string): Promise<GuardianSet[]>;
  // signed records
  insertSignedRecord(row: SignedRecordRow): Promise<{ seq: bigint; duplicate: boolean }>;
  revocationRecordsFor(revokedDeviceId: string): Promise<SignedRecordRow[]>;
  deviceAuthRow(
    deviceId: string,
  ): Promise<{ user_id: string; pub_ed: Uint8Array; status: string } | null>;
  isTenantAdmin(tenantId: string): Promise<boolean>;
  membershipCount(tenantId: string): Promise<number>;
  /** Current membership status, or null when there is no row yet (06 §7's starting state). */
  membershipStatus(tenantId: string, userId: string): Promise<string | null>;
  bookInfo(
    bookId: string,
  ): Promise<
    { tenant_id: string; owner_user_id: string | null; type: string; role_count: number } | null
  >;
  // ADR 2026-09-13d ruling 4 — the ceremony session relay. Three opaque values, no computation:
  // the server neither derives nor checks a code, it only forwards bytes in a fixed order.
  ceremonyCommit(tenant: string, commitment: Uint8Array): Promise<CeremonySession>;
  ceremonyContribute(session: string, verifierRandom: Uint8Array): Promise<CeremonySession>;
  ceremonyOpen(session: string, opening: Uint8Array): Promise<CeremonySession>;
  ceremonySession(session: string): Promise<CeremonySession | null>;
  /** 04 §6.4 *delegated* — the newest UNEXPIRED session for a subject in a tenant, for a verifier
   *  that has just scanned a QR and holds a user_id but no session id (04 §6.1 carries none).
   *  Adds no authority: 0007's select policy filters it exactly as it filters a lookup by id. */
  liveCeremonyFor(tenant: string, subject: string): Promise<CeremonySession | null>;
  // 06 §7 invites. `inviteeHmac` is computed at the edge from a number that is never stored
  // (ADR 2026-09-05c §4); the record is the admin's signed `invite` (0008 ⚠️ SPEC).
  createInvite(
    record: string,
    tenant: string,
    inviteeHmac: Uint8Array,
    roles: unknown,
    nonce: Uint8Array,
  ): Promise<string>;
  /** Invites addressed to the CALLER's OTP-verified number. Never a list of anyone else's. */
  myInvites(): Promise<InviteOffer[]>;
  /** Phone-bound acceptance (ADR 2026-09-05d §9); returns the membership status it landed on. */
  acceptInvite(invite: string): Promise<string>;
  // ---- 04 §7.3 the guardian recovery ladder, write side (0010). Every rule is the database's;
  // these are the calls. No method here updates a row: a decision, a cancellation and a request are
  // each their own append-only row, and the state a client acts on is derived (CLAUDE.md rule 2).
  /** 04 §7.3 Setup: publish a set at a NEW share_set_version with one sealed share per guardian. */
  publishGuardianSet(draft: GuardianSetDraft): Promise<number>;
  /** 04 §7.3 step 1: the caller's own device asks, carrying its candidate X25519 public key. */
  openRecovery(candidatePubX: Uint8Array): Promise<RecoveryRequest>;
  /** 04 §7.3 steps 3 and 7: one guardian, one decision, written once. Returns the sealed share's id. */
  recoveryDecide(
    request: string,
    decision: "approved" | "denied",
    blob: Uint8Array | null,
    sealedTo: Uint8Array | null,
  ): Promise<string | null>;
  /** k-of-n for the requester (and for its candidate device); null when it is not theirs to read. */
  recoveryProgress(request: string): Promise<RecoveryProgress | null>;
  /** The pending asks addressed to the CALLER as a guardian. Never anyone else's. */
  recoveryAsks(): Promise<RecoveryAsk[]>;
  /** ADR 2026-09-05d §1: the one-tap Cancel, from an existing certified device of the user. */
  recoveryCancel(request: string): Promise<void>;
  /** The caller's own attempts — what the candidate device polls. */
  myRecoveryRequests(): Promise<RecoveryRequest[]>;
  // ---- 04 §7.4 🔒 rung 3, the paper sheet (0011). Write-once and versioned: regenerating a sheet
  // rotates RK, so it publishes the NEXT version and the old blob stops being served.
  /** 04 §7.4: upload `sealed_RK_blob` for the caller's own user. Returns the version it landed on. */
  publishRecoverySheet(blob: Uint8Array): Promise<number>;
  /** 04 §7.4 Recovery: the caller's OWN current sealed blob, or null when no sheet was ever made. */
  recoverySheet(): Promise<RecoverySheet | null>;
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
  /** ADR 2026-09-16 §2: the client's `device` id is recorded, never minted here. Idempotent for
   *  the same user with the same keys on a live row; any other holder → DeviceIdTakenError. */
  registerDevice(
    device: string,
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
  /** Both halves of the caller's own UMK public key (04 §3.1, §6.3 🔒) — `pub_x` is NULL whenever
   *  no writer has yet offered an x half for this (user, version), which today is EVERY row (no
   *  client sends `umk_pub_x`; see UmkPublicRow). Bounded to the caller's own user by
   *  rf.umk_pubs_for. */
  umkPubs(user: string, version: number): Promise<UmkPublicRow | null>;
  /** Write-once, per 0012: same material → no-op, different material → StoreDenied('umk_pub_conflict'),
   *  a NULL x half → backfilled exactly once, whenever that row was written. Nothing but 32 bytes
   *  is accepted. */
  setUmkPubs(
    user: string,
    version: number,
    pubEd: Uint8Array,
    pubX: Uint8Array | null,
  ): Promise<void>;
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
  /** Record AND apply one gateway webhook in the same transaction (08 §4 🔒, ADR 2026-09-05g §9).
   *  Dedupe, the out-of-order guard and the state change cannot come apart, because a handler that
   *  recorded first and applied second would apply twice on a retry that crashed in between. */
  applyBillingEvent(e: BillingEventApply): Promise<BillingApplyResult>;
}

/** What the handler decided a gateway event MEANS. The gateway's own vocabulary stays in
 *  billing-webhook/index.ts; the store and the database see only these four (08 §3, ADR
 *  2026-09-05g §4, §11). `record_only` is an event we understood well enough to log and not well
 *  enough to act on — an unknown type, a malformed body — and is never a silent drop. */
export type BillingAction = "activate" | "dunning" | "end_now" | "record_only";

/** Why an event did not change anything, for the caller's own bookkeeping. Never returned on the
 *  wire: the gateway learns `applied`, not our reasoning. */
export type BillingOutcome =
  | BillingAction
  | "duplicate"
  | "not_applicable"
  | "unknown_tenant"
  | "no_event_at"
  | "no_period_end"
  | "out_of_order";

export interface BillingEventApply {
  eventId: string;
  gateway: string;
  type: string;
  /** BLAKE2b-256 of the raw body. The body itself is never stored and never logged (rule 4): it
   *  carries payer name, instrument and amount. */
  hash: Uint8Array;
  action: BillingAction;
  /** The tenant the signed body names, when it names one. Null is normal — the gateway ref is the
   *  primary resolution (08 §4 🔒 "we hold reference IDs only"). */
  tenantId: string | null;
  /** The GATEWAY's timestamp for the event: the ordering key of ADR 2026-09-05g §9's guard. */
  eventAt: Date | null;
  plan: string | null;
  periodEnd: Date | null;
  gatewayRef: string | null;
  source: string | null;
  originalTransactionId: string | null;
  disputeState: string | null;
}
export interface BillingApplyResult {
  /** False on a replay: this event_id was already recorded (08 §5 "webhook replay is idempotent"). */
  fresh: boolean;
  applied: boolean;
  outcome: BillingOutcome;
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

/** The device id is already held by another user, another key pair, or a revoked row
 *  (ADR 2026-09-16 §2). 409 like the cap, but a different `error` string: the client branches
 *  on the string, not the status. */
export class DeviceIdTakenError extends Error {
  constructor() {
    super("device_id_taken");
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
  // insufficient_privilege. Postgres' own message is a sentence ("permission denied for table
  // invites"); a bare token is one of OUR guards raising a named refusal with errcode 42501
  // (rf.accept_invite's `phone_mismatch`, rf.create_invite's `not_admin`…). Pass the name through:
  // 05c says a refusal is always named, never a silent or generic drop.
  if (code === "42501" || code === "28000") {
    const m = msg.trim();
    return new StoreDenied(/^[a-z][a-z0-9_]*$/.test(m) ? m : "rls");
  }
  if (code === "P0001") return new StoreDenied(msg.split(/\s/)[0]); // raise exception '<reason>'
  // check_violation: a bare-token message is one of our own guards raising a named reason
  // (rf.membership_guard / rf.invite_guard, 06 §7); anything else is a column CHECK.
  if (code === "23514") {
    return new StoreDenied(/^[a-z][a-z0-9_]*$/.test(msg.trim()) ? msg.trim() : "check");
  }
  if (code === "23503") return new StoreDenied("fk"); // unknown book / tenant / device
  return null;
}
