// Test rig for the edge functions: MemStore + fixed clock + FakeOtpProvider + libsodium keypairs.
// Fixtures are SYNTHETIC — random bytes stand in for ciphertext; no ledger content exists here.
import { b64url, concat, i64be, uuid16 } from "../_shared/bytes.ts";
import { type Claims, mintAccessToken } from "../_shared/claims.ts";
import type { Deps } from "../_shared/deps.ts";
import { FakeOtpProvider } from "../_shared/otp/provider.ts";
import { recordDigest } from "../_shared/records.ts";
import { blake2b256, sodium } from "../_shared/sodium.ts";
import type { SignedRecordRow } from "../_shared/store.ts";
import { MemDb, type MemDevice, MemStore } from "../_shared/store_mem.ts";

export const T0 = new Date("2026-09-07T09:00:00.000Z");
export const CLIENT_VERSION = "0.1.0";

export interface Rig {
  db: MemDb;
  deps: Deps;
  otp: FakeOtpProvider;
  clock: { now: Date };
}
export function rig(): Rig {
  const clock = { now: new Date(T0) };
  const db = new MemDb();
  db.now = () => new Date(clock.now);
  const otp = new FakeOtpProvider();
  const deps: Deps = {
    store: new MemStore(db),
    now: () => new Date(clock.now),
    jwtKey: new Uint8Array(32).fill(7),
    phoneHmacKey: new Uint8Array(32).fill(9),
    phoneKek: new Uint8Array(32).fill(11),
    otp,
    webhookSecret: new TextEncoder().encode("whsec_test"),
  };
  return { db, deps, otp, clock };
}
export function advance(r: Rig, ms: number): void {
  r.clock.now = new Date(r.clock.now.getTime() + ms);
}

export interface KeyPair {
  pub: Uint8Array;
  priv: Uint8Array;
}
export async function edKeypair(): Promise<KeyPair> {
  const s = await sodium();
  const k = s.crypto_sign_keypair();
  return { pub: k.publicKey, priv: k.privateKey };
}
export async function sign(msg: Uint8Array, priv: Uint8Array): Promise<Uint8Array> {
  return (await sodium()).crypto_sign_detached(msg, priv);
}
export async function random(n: number): Promise<Uint8Array> {
  return (await sodium()).randombytes_buf(n);
}

/** A certified member with a writer role on a book in a tenant. */
export interface Member {
  user: string;
  device: MemDevice;
  keys: KeyPair;
  xpub: Uint8Array;
  claims: Claims;
  token: string;
}
export async function member(
  r: Rig,
  tenant: string,
  book: string | null,
  role: string | null,
  opts: { status?: MemDevice["status"]; membership?: string } = {},
): Promise<Member> {
  const user = r.db.addUser().id;
  r.db.addMembership(tenant, user, opts.membership ?? "active");
  if (book && role) r.db.addRole(book, user, role);
  const keys = await edKeypair();
  const xpub = await random(32);
  const device = r.db.addDevice(user, keys.pub, xpub, opts.status ?? "certified");
  const claims = { user_id: user, device_id: device.id };
  const token = await mintAccessToken(
    r.deps.jwtKey,
    claims,
    Math.floor(r.clock.now.getTime() / 1000),
  );
  return { user, device, keys, xpub, claims, token };
}

export function hlcAt(ms: number, counter = 0): bigint {
  return (BigInt(ms) << 16n) | BigInt(counter);
}

/** Wire envelope as wire.dart emits it (base64url bytes, integer hlc). Blob is random bytes. */
export async function wireEnvelope(
  m: Member,
  tenant: string,
  book: string,
  over: Record<string, unknown> = {},
  blobLen = 96,
) {
  const blob = await random(blobLen);
  const e: Record<string, unknown> = {
    envelope_id: crypto.randomUUID(),
    tenant_id: tenant,
    book_id: book,
    object_id: crypto.randomUUID(),
    object_type: "entry",
    key_version: 1,
    suite_version: 1,
    payload_schema: 1,
    author_device: m.device.id,
    hlc: hlcAt(T0.getTime()),
    blob_hash: b64url.enc(await blake2b256(blob)),
    size: blob.length,
    blob: b64url.enc(blob),
    ...over,
  };
  return e;
}

export function req(
  url: string,
  init: RequestInit & { token?: string | null; version?: string | null } = {},
): Request {
  const headers = new Headers(init.headers);
  if (init.version !== null) headers.set("x-rukka-client-version", init.version ?? CLIENT_VERSION);
  if (init.token) headers.set("authorization", `Bearer ${init.token}`);
  if (init.body && !headers.has("content-type")) headers.set("content-type", "application/json");
  return new Request(`https://edge.local/functions/v1${url}`, { ...init, headers });
}
export function post(
  url: string,
  body: unknown,
  opts: { token?: string | null; version?: string | null } = {},
): Request {
  const text = typeof body === "string" ? body : jsonBigText(body);
  return req(url, {
    method: "POST",
    body: text,
    token: opts.token,
    version: opts.version,
    headers: { "content-length": String(text.length) },
  });
}
export function get(
  url: string,
  opts: { token?: string | null; version?: string | null } = {},
): Request {
  return req(url, { method: "GET", token: opts.token, version: opts.version });
}
export async function body(res: Response): Promise<any> {
  return JSON.parse(await res.text());
}
function jsonBigText(v: unknown): string {
  return JSON.stringify(v, (_k, x) => typeof x === "bigint" ? `‖big:${x}` : x).replace(
    /"‖big:(-?\d+)"/g,
    "$1",
  );
}

/** A signed record authored by `m`, byte-identical to core_crypto/signed_record.dart. */
export async function signedRecord(
  m: Member,
  tenant: string,
  kind: string,
  payload: Record<string, unknown>,
  over: Partial<SignedRecordRow> = {},
) {
  const payload_bytes = new TextEncoder().encode(JSON.stringify(payload));
  const row: SignedRecordRow = {
    id: crypto.randomUUID(),
    suite_version: 1,
    tenant_id: tenant,
    kind,
    payload_json: payload,
    payload_bytes,
    author_device: m.device.id,
    author_sig: new Uint8Array(64),
    hlc: hlcAt(T0.getTime()),
    ...over,
  };
  row.author_sig = await sign(await recordDigest(row), m.keys.priv);
  return {
    row,
    wire: {
      id: row.id,
      suite_version: row.suite_version,
      tenant_id: row.tenant_id,
      kind: row.kind,
      payload_json: b64url.enc(payload_bytes),
      author_device_id: row.author_device,
      author_sig: b64url.enc(row.author_sig),
      hlc: row.hlc,
    },
  };
}

/** Device certificate bytes exactly as core_crypto/device_cert.dart signs them. */
export function certBytes(
  deviceId: string,
  pubEd: Uint8Array,
  pubX: Uint8Array,
  issuedAtMs: number,
): Uint8Array {
  return concat([uuid16(deviceId), pubEd, pubX, i64be(issuedAtMs)]);
}
/** Challenge bytes: nonce ‖ uuid16(device_id) ‖ i64be(unix_ts). */
export function challengeBytes(nonce: Uint8Array, deviceId: string, unixTs: number): Uint8Array {
  return concat([nonce, uuid16(deviceId), i64be(unixTs)]);
}
