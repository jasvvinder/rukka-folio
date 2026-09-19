// GET  /sync-meta?after=<cursor>[&subject_user_id=] → every metadata table the client consumes (05 §5 🔒),
//      signed records after `seq`, guardian-set history by share_set_version, min-version, store_epoch.
// POST /sync-meta/records {records[]} → per-record {id, result, seq} — signed records authored on the
//      caller's certified device are verified under its Ed25519 key, stored, then projected onto rows
//      (ADR 2026-09-05b §1). The server never invents a record.
// POST /sync-meta/invites {record, phone} → {invite_id}  · GET /sync-meta/invites → my invites
// POST /sync-meta/invites/accept {invite_id} → {status}  (06 §7, ADR 2026-09-05d §9)
// /sync-meta/recovery… → the guardian ladder's WRITE side (04 §7.3; see the block above `recovery`)
// Cursor: `after` is opaque — base64url JSON {tables: {table: {updated_at, id}}, records_seq}; each
// table's own cursor is (updated_at, id) as 05 §5 says. `next` is ALWAYS present (the resume point);
// `has_more` is true when any table or the records stream had more than a page (engine contract: wire.dart).
import { b64any, b64url, isUuid } from "../_shared/bytes.ts";
import { type Deps, serve } from "../_shared/deps.ts";
import { error, readJson, subPath } from "../_shared/http.ts";
import {
  applyRecord,
  parseInvitePayload,
  parseRecord,
  type RecordResult,
  verifyRecord,
} from "../_shared/records.ts";
import { normaliseE164, phoneHmac } from "../_shared/phone.ts";
import { PULL_LIMIT_MAX } from "../_shared/registry.ts";
import { authenticate, gate, jsonBigResponse, recordToWire } from "../_shared/route.ts";
import {
  type CeremonySession,
  type GuardianSetDraft,
  META_TABLES,
  type MetaCursors,
  type MetaTable,
  type RecoveryProgress,
  type RecoveryRequest,
  rowId,
  type SignedRecordRow,
  StoreDenied,
  type Tx,
} from "../_shared/store.ts";

const PAGE = 200;
const RECORDS_BATCH_MAX = 50;
interface Cursor {
  tables: MetaCursors;
  records_seq: string;
}

export async function handler(req: Request, deps: Deps): Promise<Response> {
  const gated = await gate(req, deps, "sync");
  if (gated) return gated;
  const claims = await authenticate(req, deps);
  if (claims instanceof Response) return claims;
  const path = subPath(req, "sync-meta");
  if (req.method === "GET" && path === "/") return pull(req, deps, claims);
  if (req.method === "POST" && path === "/records") return postRecords(req, deps, claims);
  if (path.startsWith("/ceremony")) return ceremony(req, deps, claims, path);
  if (path.startsWith("/invites")) return invites(req, deps, claims, path);
  if (path.startsWith("/recovery")) return recovery(req, deps, claims, path);
  return error(404, "not_found");
}

async function pull(
  req: Request,
  deps: Deps,
  claims: { user_id: string; device_id: string },
): Promise<Response> {
  const q = new URL(req.url).searchParams;
  const cursor = decodeCursor(q.get("after"));
  if (cursor === undefined) return error(400, "bad_cursor");
  const subject = q.get("subject_user_id") ?? claims.user_id;
  if (!isUuid(subject)) return error(400, "bad_request");

  const out = await deps.store.withClaims(claims, async (tx) => {
    const body: Record<string, unknown> = { store_epoch: await tx.storeEpoch() };
    const next: Cursor = { tables: {}, records_seq: cursor?.records_seq ?? "0" };
    let more = false;
    for (const table of META_TABLES) {
      const page = await tx.metaPage(table, cursor?.tables[table] ?? null, PAGE);
      body[table] = page.rows.map((r) => shapeRow(table, r));
      if (page.next) {
        next.tables[table] = page.next;
        more = true;
      } else if (page.rows.length) {
        const last = page.rows[page.rows.length - 1];
        next.tables[table] = {
          updated_at: (last.updated_at as Date).toISOString(),
          id: rowId(table, last),
        };
      } else if (cursor?.tables[table]) {
        next.tables[table] = cursor.tables[table]; // drained: resume from the same place next time
      }
    }
    const records = await tx.signedRecordsAfter(BigInt(next.records_seq), PULL_LIMIT_MAX);
    body.signed_records = records.map(recordToWire);
    if (records.length) {
      next.records_seq = records[records.length - 1].seq!.toString();
      if (records.length === PULL_LIMIT_MAX) more = true;
    }
    body.guardian_sets = (await tx.guardianSetHistory(subject)).map((s) => ({
      subject_user_id: s.subject_user_id,
      share_set_version: s.share_set_version,
      k: s.k,
      n: s.n,
      guardian_user_ids: s.members.map((m) => m.guardian_user_id),
      guardians: s.members.map((m) => ({
        guardian_user_id: m.guardian_user_id,
        umk_pub_ed: b64url.enc(m.umk_pub_ed),
      })),
    }));
    body.min_client_version = {
      sync: await tx.appConfig("min_client_version.sync"),
      auth: await tx.appConfig("min_client_version.auth"),
    };
    body.has_more = more;
    body.next = encodeCursor(next); // always present — the resume point even when drained
    return body;
  });
  return jsonBigResponse(200, out);
}

// ---------------------------------------------------------------- ceremony session relay
// ADR 2026-09-13d ruling 4 🔒. Three opaque values and their server timestamps; the server does not
// derive, compare or validate a code (04 §8.6) — grep this block for a hash and you will not find
// one. Delivery is SHORT POLLING (ADR Open 2, decided here): the two devices GET the session while a
// ceremony screen is open. Realtime was declined because it authorises from the platform's
// `authenticated` role, which 0005 strips of every grant; a second authorisation path over the table
// that carries the trust root is the wrong trade for a two-round-trip exchange at human pace.
//
//   POST /sync-meta/ceremony            {tenant_id, commitment}      → the session (invitee)
//   POST /sync-meta/ceremony/verifier   {session_id, verifier_random}→ the session (active member)
//   POST /sync-meta/ceremony/opening    {session_id, opening}        → the session (invitee)
//   GET  /sync-meta/ceremony?session_id=…                            → the session (either side)
//
// Every rule is enforced by 0007's guard and its policies, in the database. This handler shapes
// JSON; it cannot loosen anything, which is the point.
async function ceremony(
  req: Request,
  deps: Deps,
  claims: { user_id: string; device_id: string },
  path: string,
): Promise<Response> {
  if (req.method === "GET" && path === "/ceremony") {
    const id = new URL(req.url).searchParams.get("session_id");
    if (!isUuid(id)) return error(400, "bad_request");
    const row = await deps.store.withClaims(claims, (tx) => tx.ceremonySession(id));
    return row ? jsonBigResponse(200, sessionToWire(row)) : error(404, "not_found");
  }
  if (req.method !== "POST") return error(404, "not_found");
  const body = await readJson(req, 4096) as Record<string, unknown> | null;
  if (!body) return error(400, "bad_request");

  try {
    const out = await deps.store.withClaims(claims, (tx) => {
      if (path === "/ceremony") {
        const c = b64any(body.commitment);
        if (!isUuid(body.tenant_id) || !c || c.length !== 32) throw new StoreDenied("bad_request");
        return tx.ceremonyCommit(body.tenant_id, c);
      }
      if (!isUuid(body.session_id)) throw new StoreDenied("bad_request");
      if (path === "/ceremony/verifier") {
        const r = b64any(body.verifier_random);
        if (!r || r.length !== 16) throw new StoreDenied("bad_request");
        return tx.ceremonyContribute(body.session_id, r);
      }
      if (path === "/ceremony/opening") {
        const o = b64any(body.opening);
        if (!o || o.length !== 16) throw new StoreDenied("bad_request");
        return tx.ceremonyOpen(body.session_id, o);
      }
      throw new StoreDenied("not_found");
    });
    return jsonBigResponse(200, sessionToWire(out));
  } catch (e) {
    if (!(e instanceof StoreDenied)) throw e;
    if (e.reason === "not_found") return error(404, "not_found");
    if (e.reason === "bad_request") return error(400, "bad_request");
    // The database named the refusal; pass the name through unchanged (05c: never a silent drop).
    const forbidden = ["rls", "unknown_session", "self_verification", "subject_not_in_tenant"];
    const status = forbidden.includes(e.reason) ? 403 : e.reason === "ceremony_flood" ? 429 : 409;
    return error(status, e.reason);
  }
}

// ---------------------------------------------------------------- 04 §7.3 the guardian ladder
// The write side of rung 2. 0002 declared the tables, 0005 granted SELECT + INSERT, and this GET
// route already returned the guardian-set history — but nothing could ever be written. These are
// the five writes and the two reads 04 §7.3 needs, and every rule behind them is 0010's, in the
// database, so this handler cannot loosen one:
//
//   POST /sync-meta/recovery/guardians {share_set_version, k, n, guardians:[{guardian_user_id,
//                                       umk_pub_ed, blob}]} → {share_set_version}   (Setup)
//   POST /sync-meta/recovery           {candidate_pub_x}    → the request           (step 1)
//   POST /sync-meta/recovery/approve   {request_id, sealed_to_pub_x, blob}          (step 3)
//   POST /sync-meta/recovery/deny      {request_id}                                 (step 7)
//   POST /sync-meta/recovery/cancel    {request_id}         (ADR 2026-09-05d §1, one tap)
//   GET  /sync-meta/recovery[?request_id=…]                 → k-of-n for the requester
//   GET  /sync-meta/recovery/asks                           → the pending ask, for a guardian
//
// Three things this handler deliberately does NOT do. It never computes k (0010 enforces
// 04 §7.3's ⌈(n+1)/2⌉). It never chooses a state: the 24 h ladder of ADR 2026-09-05d §1 is set by
// the database from one fact — whether the user still holds an active certified device — so a body
// that says `"state": "approved"` is not an attack, it is an ignored field. And it never opens,
// hashes or re-seals a share: `blob` arrives base64url and reaches the store as bytes (04 §8.6).
//
// The route for step 1 is the ONE sync route a caller reaches without a certified device, because
// 04 §7.3 step 1 is a fresh phone holding nothing but its own keys and ADR 2026-09-05d §2 names
// "its own recovery_requests" among the four things such a device may see.
async function recovery(
  req: Request,
  deps: Deps,
  claims: { user_id: string; device_id: string },
  path: string,
): Promise<Response> {
  if (req.method === "GET") {
    if (path === "/recovery/asks") {
      const asks = await deps.store.withClaims(claims, (tx) => tx.recoveryAsks());
      return jsonBigResponse(200, {
        asks: asks.map((a) => ({
          request_id: a.request_id,
          subject_user_id: a.subject_user_id,
          candidate_device: a.candidate_device,
          // ADR 2026-09-13c §3: the guardian's device compares this against the DeviceQrPayload it
          // scans from the requester before it re-seals anything.
          candidate_pub_x: b64url.enc(a.candidate_pub_x),
          share_set_version: a.share_set_version,
          created_at: a.created_at.getTime(),
          expires_at: a.expires_at.getTime(),
          my_decision: a.my_decision,
        })),
      });
    }
    if (path !== "/recovery") return error(404, "not_found");
    const id = new URL(req.url).searchParams.get("request_id");
    if (id === null) {
      const rows = await deps.store.withClaims(claims, (tx) => tx.myRecoveryRequests());
      return jsonBigResponse(200, { requests: rows.map(requestToWire) });
    }
    if (!isUuid(id)) return error(400, "bad_request");
    const p = await deps.store.withClaims(claims, (tx) => tx.recoveryProgress(id));
    // An attempt that is not the caller's and one that does not exist answer identically.
    return p ? jsonBigResponse(200, progressToWire(p)) : error(404, "not_found");
  }
  if (req.method !== "POST") return error(404, "not_found");
  const body = await readJson(req, 1 << 16) as Record<string, unknown> | null;
  if (!body) return error(400, "bad_request");

  try {
    if (path === "/recovery/guardians") {
      const draft = parseGuardianDraft(body);
      if (!draft) return error(400, "bad_request");
      const v = await deps.store.withClaims(claims, (tx) => tx.publishGuardianSet(draft));
      return jsonBigResponse(200, { share_set_version: v });
    }
    if (path === "/recovery") {
      const pub = b64any(body.candidate_pub_x);
      if (!pub || pub.length !== 32) return error(400, "bad_request");
      const r = await deps.store.withClaims(claims, (tx) => tx.openRecovery(pub));
      return jsonBigResponse(200, requestToWire(r));
    }
    if (path === "/recovery/approve" || path === "/recovery/deny") {
      if (!isUuid(body.request_id)) return error(400, "bad_request");
      const approve = path === "/recovery/approve";
      const blob = approve ? b64any(body.blob) : null;
      const sealed = approve ? b64any(body.sealed_to_pub_x) : null;
      if (approve && (!blob || !sealed || sealed.length !== 32)) return error(400, "bad_request");
      const wk = await deps.store.withClaims(claims, (tx) =>
        tx.recoveryDecide(
          body.request_id as string,
          approve ? "approved" : "denied",
          blob,
          sealed,
        ));
      return jsonBigResponse(200, {
        request_id: body.request_id,
        decision: approve ? "approved" : "denied",
        // The id of the sealed row, never the blob: the share leaves this server only to the
        // candidate device it was addressed to, through the wrapped_keys meta pull.
        wrapped_key_id: wk,
      });
    }
    if (path === "/recovery/cancel") {
      if (!isUuid(body.request_id)) return error(400, "bad_request");
      await deps.store.withClaims(claims, (tx) => tx.recoveryCancel(body.request_id as string));
      return jsonBigResponse(200, { request_id: body.request_id, state: "cancelled" });
    }
    return error(404, "not_found");
  } catch (e) {
    if (!(e instanceof StoreDenied)) throw e;
    return recoveryError(e.reason);
  }
}

/** The database named the refusal; the wire name is the client's, and never an oracle. */
function recoveryError(reason: string): Response {
  switch (reason) {
    // ADR 2026-09-05d §2 / 0010: an unknown attempt and a caller who is not its guardian are the
    // same answer, so nobody learns whose recovery is in flight by asking.
    case "unknown_request":
    case "unknown_candidate_device":
      return error(403, "unknown_request");
    case "no_guardian_set":
    case "guardian_set_incomplete":
      return error(409, reason); // fall through the ladder to 04 §7.4's paper sheet
    case "recovery_closed":
      return error(409, "recovery_closed");
    case "already_decided":
      return error(409, "already_decided");
    case "candidate_key_mismatch":
      return error(409, "candidate_key_mismatch");
    case "guardian_quorum":
    case "guardian_set_size":
    case "guardian_is_subject":
    case "share_set_version_out_of_order":
    case "recovery_shape":
    case "check":
      return error(400, reason);
    case "recovery_flood":
      return error(429, "recovery_flood");
    case "fk":
      return error(404, "not_found");
    default:
      return error(403, reason === "rls" ? "forbidden" : reason);
  }
}

/** 04 §7.3 Setup, as it arrives on the wire. Shape only — k and n are checked in the database. */
function parseGuardianDraft(body: Record<string, unknown>): GuardianSetDraft | null {
  const v = body.share_set_version, k = body.k, n = body.n;
  if (!Number.isInteger(v) || (v as number) < 1) return null;
  if (!Number.isInteger(k) || !Number.isInteger(n)) return null;
  if (!Array.isArray(body.guardians) || body.guardians.length === 0) return null;
  const guardians = [];
  for (const raw of body.guardians) {
    const g = raw as Record<string, unknown>;
    const pub = b64any(g.umk_pub_ed), blob = b64any(g.blob);
    if (!isUuid(g.guardian_user_id) || !pub || pub.length !== 32 || !blob || !blob.length) {
      return null;
    }
    guardians.push({ guardian_user_id: g.guardian_user_id as string, umk_pub_ed: pub, blob });
  }
  return { share_set_version: v as number, k: k as number, n: n as number, guardians };
}

function requestToWire(r: RecoveryRequest): Record<string, unknown> {
  return {
    request_id: r.id,
    user_id: r.user_id,
    candidate_device: r.candidate_device,
    candidate_pub_x: b64url.enc(r.candidate_pub_x),
    share_set_version: r.share_set_version,
    // The ladder it opened on. `GET /sync-meta/recovery?request_id=` carries the live one.
    opened_state: r.state,
    created_at: r.created_at.getTime(),
    expires_at: r.expires_at.getTime(),
  };
}

function progressToWire(p: RecoveryProgress): Record<string, unknown> {
  return {
    request_id: p.request_id,
    share_set_version: p.share_set_version,
    k: p.k,
    n: p.n,
    approvals: p.approvals,
    denials: p.denials,
    opened_state: p.opened_state,
    state: p.state,
    kth_approval_at: p.kth_approval_at?.getTime() ?? null,
    wait_until: p.wait_until?.getTime() ?? null,
    expires_at: p.expires_at.getTime(),
    cancelled_at: p.cancelled_at?.getTime() ?? null,
  };
}

/** Opaque bytes out, base64url, exactly as they went in. */
function sessionToWire(s: CeremonySession): Record<string, unknown> {
  return {
    session_id: s.id,
    tenant_id: s.tenant_id,
    subject_user_id: s.subject_user,
    commitment: b64url.enc(s.commitment),
    committed_at: new Date(s.committed_at).toISOString(),
    expires_at: new Date(s.expires_at).toISOString(),
    verifier_user_id: s.verifier_user,
    verifier_random: s.verifier_random ? b64url.enc(s.verifier_random) : null,
    verifier_random_at: s.verifier_random_at ? new Date(s.verifier_random_at).toISOString() : null,
    opening: s.opening ? b64url.enc(s.opening) : null,
    opened_at: s.opened_at ? new Date(s.opened_at).toISOString() : null,
  };
}

// ---------------------------------------------------------------- 06 §7 invites
// The invite a second phone can actually accept, and the one place a phone number passes through
// this server (ADR 2026-09-05c §4, 06 §7): the admin's device sends the E.164 number with the
// signed `invite` record, the edge HMACs it under the server key, and the number is never written
// anywhere — not the invites row, not signed_records, not a log line (deps.serve logs error NAMES
// only). The admin's device cannot compute the HMAC itself, which is exactly why the number has to
// travel; 06 §7 already allows that ("the plaintext goes into the outbound message job and is gone
// once sent"). Delivery of the link is ⚠️ not wired: no invite-message provider exists yet (the
// OtpProvider seam is code-shaped), so today the admin's own phone sends it.
//
//   POST /sync-meta/invites         {record, phone}   → {invite_id, seq}     (tenant admin)
//   GET  /sync-meta/invites                           → {invites: [...]}     (the joiner, own number)
//   POST /sync-meta/invites/accept  {invite_id}       → {invite_id, status}  (the joiner)
//
// Refusals are the database's, passed through by name. A wrong number and an unknown id both come
// back `invite_not_for_you` (C-05d-9) — identical, so the route is not an oracle for who was
// invited.
async function invites(
  req: Request,
  deps: Deps,
  claims: { user_id: string; device_id: string },
  path: string,
): Promise<Response> {
  if (req.method === "GET" && path === "/invites") {
    const rows = await deps.store.withClaims(claims, (tx) => tx.myInvites());
    return jsonBigResponse(200, {
      invites: rows.map((i) => ({
        invite_id: i.invite_id,
        tenant_id: i.tenant_id,
        roles: i.roles,
        expires_at: i.expires_at.getTime(),
        created_by: i.created_by,
      })),
    });
  }
  if (req.method !== "POST") return error(404, "not_found");
  const body = await readJson(req, 1 << 16) as Record<string, unknown> | null;
  if (!body) return error(400, "bad_request");

  if (path === "/invites/accept") {
    if (!isUuid(body.invite_id)) return error(400, "bad_request");
    try {
      const status = await deps.store.withClaims(
        claims,
        (tx) => tx.acceptInvite(body.invite_id as string),
      );
      return jsonBigResponse(200, { invite_id: body.invite_id, status });
    } catch (e) {
      if (!(e instanceof StoreDenied)) throw e;
      return inviteError(e.reason);
    }
  }
  if (path !== "/invites") return error(404, "not_found");

  // The number: normalised, HMAC'd, dropped. It is a local const and reaches no store call.
  const e164 = normaliseE164(body.phone);
  if (!e164) return error(400, "bad_phone");
  const hmac = await phoneHmac(deps.phoneHmacKey, e164);

  try {
    const out = await deps.store.withClaims(claims, async (tx) => {
      const me = await tx.deviceAuthRow(claims.device_id);
      const taken = await intakeRecord(tx, body.record, claims, me);
      if ("result" in taken) return taken; // a named refusal, not a record
      const { record, seq, duplicate } = taken;
      if (record.kind !== "invite") {
        return { id: record.id, result: "rejected:shape", check: "kind" };
      }
      const payload = parseInvitePayload(record.payload_json);
      if (!payload) return { id: record.id, result: "rejected:shape", check: "payload_json" };
      if (duplicate) {
        // The record is the action. A replay is the same invite, already issued — the admin's
        // device finds it in the meta pull by `source_record_id`; re-issuing would mint a second
        // row and revoke the first (06 §7's one-tap re-invite), which a retry must not do.
        return { id: record.id, result: "rejected:record_replayed" };
      }
      try {
        const invite_id = await tx.createInvite(
          record.id,
          record.tenant_id,
          hmac,
          payload.roles,
          payload.nonce,
        );
        await tx.markRecordApplied(record.id, "invite issued");
        return { invite_id, record_id: record.id, seq: seq.toString() };
      } catch (e) {
        if (!(e instanceof StoreDenied)) throw e;
        // As on /records: the record is a signed fact and stays stored (append-only); the note says
        // why it was not applied. Keeping it inside the transaction is what makes that true — a
        // throw here would roll the record back with it.
        await tx.markRecordApplied(record.id, `rejected:${e.reason}`);
        return { denied: e.reason };
      }
    });
    if ("denied" in out) return inviteError(out.denied as string);
    if ("result" in out) {
      const r = out as RecordResult;
      return r.result === "rejected:record_replayed"
        ? error(409, "record_replayed")
        : r.result === "rejected:unauthorized"
        ? error(403, "unauthorized")
        : jsonBigResponse(400, { error: "bad_record", check: r.check ?? r.result });
    }
    return jsonBigResponse(200, out);
  } catch (e) {
    if (!(e instanceof StoreDenied)) throw e;
    return inviteError(e.reason);
  }
}

/** The database named the refusal; the wire name is the client's, and never an oracle. */
function inviteError(reason: string): Response {
  switch (reason) {
    // ADR 2026-09-05d §9 🔒 — the link alone admits nobody. An unknown invite refuses identically:
    // a joiner with the wrong number learns nothing about whether that invite exists.
    case "unknown_invite":
    case "phone_mismatch":
      return error(403, "invite_not_for_you");
    case "invite_expired":
      return error(410, "invite_expired"); // 06 §7: 7 days, then one-tap re-invite
    case "invite_not_live":
      return error(409, "invite_not_live");
    case "not_admin":
      return error(403, "not_admin");
    case "no_record":
      return error(409, "no_record");
    case "fk":
      return error(404, "unknown_tenant");
    case "check":
      return error(400, "bad_request");
    default:
      return error(403, reason === "rls" ? "forbidden" : reason);
  }
}

/**
 * Verify one signed record authored by the caller's certified device and store it (ADR 2026-09-05b
 * §1) — the intake both /records and /invites share, so neither can be the lax one.
 */
async function intakeRecord(
  tx: Tx,
  raw: unknown,
  claims: { user_id: string; device_id: string },
  me: { user_id: string; pub_ed: Uint8Array; status: string } | null,
): Promise<
  { record: SignedRecordRow; seq: bigint; duplicate: boolean } | RecordResult
> {
  const parsed = parseRecord(raw);
  const id = typeof (raw as Record<string, unknown>)?.id === "string"
    ? (raw as Record<string, string>).id
    : "";
  if (!("kind" in parsed)) return { id, ...parsed };
  if (parsed.author_device !== claims.device_id) {
    return { id, result: "rejected:shape", check: "author_device_id" };
  }
  if (!me || me.status !== "certified") {
    return { id, result: "rejected:unauthorized", check: "device_status" };
  }
  if (!(await verifyRecord(parsed, me.pub_ed))) {
    return { id, result: "rejected:shape", check: "author_sig" };
  }
  const { seq, duplicate } = await tx.insertSignedRecord(parsed);
  return { record: { ...parsed, seq }, seq, duplicate };
}

async function postRecords(
  req: Request,
  deps: Deps,
  claims: { user_id: string; device_id: string },
): Promise<Response> {
  const body = await readJson(req, 1 << 20) as { records?: unknown[] } | null;
  if (!body || !Array.isArray(body.records)) return error(400, "bad_request");
  if (body.records.length > RECORDS_BATCH_MAX) return error(413, "batch_too_large");
  const out = await deps.store.withClaims(claims, async (tx) => {
    const store_epoch = await tx.storeEpoch();
    const me = await tx.deviceAuthRow(claims.device_id);
    const results: RecordResult[] = [];
    for (const raw of body.records!) {
      const id = typeof (raw as Record<string, unknown>)?.id === "string"
        ? (raw as Record<string, string>).id
        : "";
      try {
        const taken = await intakeRecord(tx, raw, claims, me);
        if ("result" in taken) {
          results.push(taken);
          continue;
        }
        const { record: parsed, seq, duplicate } = taken;
        if (duplicate) {
          results.push({ id, result: "acked", seq: seq.toString() });
          continue;
        }
        const note = await applyRecord(tx, parsed, me!.user_id);
        if (note.startsWith("rejected:")) {
          // Stored (append-only, it is a signed fact) but not applied; the note says why.
          await tx.markRecordApplied(parsed.id, note);
          results.push({ id, result: note, seq: seq.toString() });
          continue;
        }
        await tx.markRecordApplied(parsed.id, note);
        results.push({ id, result: "acked", seq: seq.toString() });
      } catch (e) {
        if (e instanceof StoreDenied) {
          results.push({
            id,
            result: e.reason === "fk" ? "rejected:unknown_tenant" : "rejected:unauthorized",
            check: e.reason,
          });
          continue;
        }
        throw e;
      }
    }
    return { store_epoch, results };
  });
  return jsonBigResponse(200, out);
}

function decodeCursor(s: string | null): Cursor | null | undefined {
  if (!s) return null;
  try {
    const c = JSON.parse(new TextDecoder().decode(b64url.dec(s)));
    if (
      !c || typeof c !== "object" || typeof c.tables !== "object" ||
      !/^\d+$/.test(String(c.records_seq))
    ) return undefined;
    return { tables: c.tables, records_seq: String(c.records_seq) };
  } catch {
    return undefined;
  }
}
function encodeCursor(c: Cursor): string {
  return b64url.enc(new TextEncoder().encode(JSON.stringify(c)));
}

const ms = (v: unknown): number | null =>
  v instanceof Date ? v.getTime() : v == null ? null : new Date(String(v)).getTime();
const bin = (v: unknown): string | null => v instanceof Uint8Array ? b64url.enc(v) : null;

/** Column rows → 05 §5 / wire.dart names. Timestamps as epoch ms; bytes base64url; money as integer paise. */
export function shapeRow(table: MetaTable, r: Record<string, unknown>): Record<string, unknown> {
  const id = rowId(table, r);
  switch (table) {
    case "memberships":
      return {
        id,
        tenant_id: r.tenant_id,
        user_id: r.user_id,
        status: r.status,
        source_record_id: r.source_record_id ?? null,
        updated_at: ms(r.updated_at),
      };
    case "book_roles":
      return {
        id,
        book_id: r.book_id,
        user_id: r.user_id,
        role: r.role,
        source_record_id: r.source_record_id ?? null,
        ...(r.auto_post_limit_paise != null
          ? { limits: { auto_post_limit_paise: BigInt(String(r.auto_post_limit_paise)) } }
          : {}),
        updated_at: ms(r.updated_at),
      };
    case "books":
      return {
        id,
        tenant_id: r.tenant_id,
        type: r.type,
        owner_user_id: r.owner_user_id ?? null,
        fy_start_month: r.fy_start_month,
        archived_at: ms(r.archived_at),
        updated_at: ms(r.updated_at),
      };
    case "devices":
      return {
        id,
        user_id: r.user_id,
        pub_ed: bin(r.pub_ed),
        pub_x: bin(r.pub_x),
        status: r.status,
        model: r.model ?? null,
        os: r.os ?? null,
        revoked_at: ms(r.revoked_at),
        updated_at: ms(r.updated_at),
      };
    case "device_certs":
      // ⚠️ WIRE: `cert` is 64 opaque bytes in 03; wire.dart reads it as the DeviceCert fields — user_id
      // comes from the devices row, which the same response carries, so we ship the signature + issued_at.
      return {
        device_id: r.device_id,
        issued_by_device: r.issued_by_device ?? null,
        umk_key_version: r.umk_key_version,
        cert: { suite_version: 1, issued_at_ms: ms(r.issued_at), signature: bin(r.cert) },
        updated_at: ms(r.updated_at),
      };
    case "wrapped_keys":
      return {
        id,
        kind: r.kind,
        user_id: r.user_id,
        device_id: r.device_id ?? null,
        book_id: r.book_id ?? null,
        key_version: r.key_version,
        share_set_version: r.share_set_version ?? null,
        blob: bin(r.blob),
        created_at: ms(r.created_at),
        revoked_at: ms(r.revoked_at),
        updated_at: ms(r.updated_at),
      };
    case "umk_public_keys":
      return {
        user_id: r.user_id,
        key_version: r.key_version,
        pub_ed: bin(r.pub_ed),
        superseded_at: ms(r.superseded_at),
        updated_at: ms(r.updated_at),
      };
    case "guardian_sets":
    case "guardian_set_members":
      return {
        ...r,
        umk_pub_ed: bin(r.umk_pub_ed) ?? undefined,
        created_at: ms(r.created_at),
        superseded_at: ms(r.superseded_at),
        updated_at: ms(r.updated_at),
      };
    case "invites":
      return {
        id,
        tenant_id: r.tenant_id,
        // NO invitee_hmac on the wire (ADR 2026-09-05c §4): the row says that an invite exists and
        // who sent it. The inviting device already holds the contact card it picked; nobody else
        // gets to learn whom the family invited — not even a second admin.
        roles: r.roles,
        status: r.status,
        expires_at: ms(r.expires_at),
        created_by: r.created_by,
        accepted_by: r.accepted_by ?? null,
        accepted_at: ms(r.accepted_at),
        source_record_id: r.source_record_id ?? null,
        updated_at: ms(r.updated_at),
      };
    case "subscriptions":
      return {
        tenant_id: r.tenant_id,
        plan: r.plan,
        status: r.status,
        current_period_end: ms(r.current_period_end),
        trial_end: ms(r.trial_end),
        grace_until: ms(r.grace_until),
        updated_at: ms(r.updated_at),
      };
    case "entitlement_tokens":
      return {
        id,
        tenant_id: r.tenant_id,
        token: bin(r.token),
        expires_at: ms(r.expires_at),
        updated_at: ms(r.updated_at),
      };
    case "tenant_freezes":
      return {
        tenant_id: r.tenant_id,
        ground: r.ground,
        imposed_at: ms(r.imposed_at),
        expires_at: ms(r.expires_at),
        lifted_at: ms(r.lifted_at),
        updated_at: ms(r.updated_at),
      };
    default: {
      // verification_events, recovery_requests, escrow_policies: pass through with dates → ms
      const out: Record<string, unknown> = { id };
      for (const [k, v] of Object.entries(r)) {
        out[k] = v instanceof Date ? v.getTime() : v instanceof Uint8Array ? b64url.enc(v) : v;
      }
      return out;
    }
  }
}

if (import.meta.main) serve(handler);
