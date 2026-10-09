// One registered UMK per user, and a device certifies under THAT key — ADR 2026-09-05d §2 🔒
// ("a certificate the server has verified under the user's REGISTERED UMK public key"), 06 §3 🔒
// steps 3–4 ("First device only: generate UMK, self-certify"), 04 §3.4 🔒 (every later device is
// certified by an existing certified device). Repair of the M13 RUNG3S review, finding 1.
//
// The hole this pins shut: /devices/certify reads the stored key at the `umk_key_version` the BODY
// names and treats "no row at that version" as "first device". So a registered, OTP-only phone of
// an account that already has a UMK at version 1 could post version 2 with a key it minted, sign
// its own certificate under it, be certified — and GET /recovery/sheet then relayed the minted key
// as the account's published UMK (it reads the newest key_version). E-06-7 proves the swap fails
// at the default version only. The rule now lives under the handler, in the store and the database
// (migration 0031): a NEW key_version is refused once the user has any registration, and a
// certificate is accepted only under the user's LIVE row at the version it names.
//
// MemStore through the real handlers (auth-challenge, sync-meta). The PgStore arm, on the rf_api
// login with 0031 applied, is E-05d-2 (tests/rls/umk_single_root.test.ts). Random bytes stand in for
// every key and blob — nothing financial. Ids E-05d-1.
import { assert, assertEquals, assertRejects } from "@std/assert";
import { b64url } from "../_shared/bytes.ts";
import { mintAccessToken } from "../_shared/claims.ts";
import { StoreDenied } from "../_shared/store.ts";
import { handler as auth } from "../auth-challenge/index.ts";
import { handler as meta } from "../sync-meta/index.ts";
import {
  body,
  certBytes,
  edKeypair,
  get,
  member,
  post,
  random,
  type Rig,
  rig,
  sign,
} from "./harness.ts";

/** A phone of `user`: its own device keys, a device row in `status`, and a session. */
async function phone(r: Rig, user: string, status: "registered" | "certified" = "registered") {
  const keys = await edKeypair();
  const xpub = await random(32);
  const device = r.db.addDevice(user, keys.pub, xpub, status);
  const token = await mintAccessToken(
    r.deps.jwtKey,
    { user_id: user, device_id: device.id },
    Math.floor(r.clock.now.getTime() / 1000),
  );
  return { user, device, keys, xpub, token };
}
type Phone = Awaited<ReturnType<typeof phone>>;

/** POST /auth-challenge/devices/certify for `p`, the certificate signed by `signer`. */
async function certify(
  r: Rig,
  p: Phone,
  signer: Uint8Array,
  extra: Record<string, unknown>,
) {
  const issued = r.clock.now.getTime();
  const sig = await sign(certBytes(p.device.id, p.keys.pub, p.xpub, issued), signer);
  return await auth(
    post("/auth-challenge/devices/certify", {
      ...extra,
      cert: { signature: b64url.enc(sig), issued_at_ms: issued },
    }, { token: p.token }),
    r.deps,
  );
}

const sheetGet = async (r: Rig, p: Phone) =>
  await meta(get("/sync-meta/recovery/sheet", { token: p.token }), r.deps);

Deno.test("E-05d-1 a registered phone cannot mint a second UMK root: /devices/certify at any umk_key_version other than the registered one is refused `umk_version_conflict`, nothing is written, the device stays registered, and GET /recovery/sheet still relays the REGISTERED key; a retired registration certifies nobody (`umk_unknown`) and still blocks a new version; the honest second device still certifies at version 1 (ADR 2026-09-05d §2 🔒; 06 §3 🔒 steps 3–4; 04 §3.4 🔒)", async (t) => {
  const r = rig();
  const tenant = r.db.addTenant();
  // ---- the account: its first device generates the UMK and self-certifies (06 §3 step 4)
  const first = await member(r, tenant, null, null, { status: "registered" });
  const umk = await edKeypair();
  const umkX = await random(32);
  const firstPhone: Phone = {
    user: first.user,
    device: first.device,
    keys: first.keys,
    xpub: first.xpub,
    token: first.token,
  };
  const reg = await certify(r, firstPhone, umk.priv, {
    umk_key_version: 1,
    umk_pub_ed: b64url.enc(umk.pub),
    umk_pub_x: b64url.enc(umkX),
  });
  assertEquals(
    reg.status,
    200,
    `precondition: the first device registers the UMK (${await reg.text()})`,
  );
  assertEquals(r.db.devices.get(first.device.id)!.status, "certified");
  const blob = await random(72);
  const put = await meta(
    post("/sync-meta/recovery/sheet", { blob: b64url.enc(blob) }, { token: first.token }),
    r.deps,
  );
  assertEquals(put.status, 200, `precondition: the sheet is published (${await put.text()})`);

  const rows = () => r.db.umk_public_keys.filter((k) => k.user_id === first.user);
  const certOf = (id: string) => r.db.device_certs.find((c) => c.device_id === id);

  // ---- the attacker: OTP passed, device registered, holds nothing (ADR 2026-09-05d §2)
  const intruder = await phone(r, first.user);

  for (const version of [2, 7]) {
    await t.step(
      `umk_key_version ${version} with a self-minted key and a cert it signed itself: refused, nothing written`,
      async () => {
        const evil = await edKeypair();
        const res = await certify(r, intruder, evil.priv, {
          umk_key_version: version,
          umk_pub_ed: b64url.enc(evil.pub),
          umk_pub_x: b64url.enc(await random(32)),
        });
        assertEquals(res.status, 400);
        assertEquals((await body(res)).error, "umk_version_conflict");
        assertEquals(r.db.devices.get(intruder.device.id)!.status, "registered", "not certified");
        assertEquals(certOf(intruder.device.id), undefined, "no certificate stored");
        assertEquals(rows().length, 1, "no second root registered");
        assertEquals(rows()[0].key_version, 1);
        assertEquals(rows()[0].pub_ed, umk.pub, "the registered Ed half is untouched");
        assertEquals(rows()[0].pub_x, umkX, "the registered X half is untouched");
      },
    );
  }

  await t.step(
    "the sheet relays the REGISTERED key — to the intruder's own phone too — never a minted one",
    async () => {
      for (const p of [intruder, firstPhone]) {
        const res = await sheetGet(r, p);
        assertEquals(res.status, 200);
        const got = await body(res);
        assertEquals(got.sealed_rk_blob, b64url.enc(blob));
        assertEquals(got.umk_pub_ed, b64url.enc(umk.pub));
        assertEquals(got.umk_pub_x, b64url.enc(umkX));
      }
    },
  );

  await t.step(
    "the store refuses the same two writes when called directly (the fake mirrors 0031)",
    async () => {
      const claims = { user_id: intruder.user, device_id: intruder.device.id };
      const denied = async (fn: () => Promise<unknown>, reason: string) => {
        const e = await assertRejects(fn, StoreDenied);
        assertEquals((e as StoreDenied).reason, reason);
      };
      await denied(
        () =>
          r.deps.store.withClaims(
            claims,
            async (tx) => tx.setUmkPubs(intruder.user, 2, await random(32), await random(32)),
          ),
        "umk_version_conflict",
      );
      await denied(
        () =>
          r.deps.store.withClaims(
            claims,
            async (tx) =>
              tx.certifyDevice(intruder.device.id, await random(64), r.clock.now, null, 2),
          ),
        "umk_unknown",
      );
      assertEquals(r.db.devices.get(intruder.device.id)!.status, "registered");
      assertEquals(certOf(intruder.device.id), undefined);
      assertEquals(rows().length, 1);
    },
  );

  await t.step(
    "no over-block: the honest second device, its cert issued under the registered UMK, certifies at version 1",
    async () => {
      const second = await phone(r, first.user);
      const res = await certify(r, second, umk.priv, { umk_key_version: 1 });
      assertEquals(res.status, 200, await res.clone().text());
      assertEquals((await body(res)).status, "certified");
      assertEquals(r.db.devices.get(second.device.id)!.status, "certified");
      assertEquals(certOf(second.device.id)?.umk_key_version, 1);
      assertEquals(rows().length, 1);
    },
  );

  await t.step(
    "a retired registration certifies nobody — not even under its own key — and still blocks a new version",
    async () => {
      // A row marked superseded (maintenance; rf_api holds no UPDATE) is a retired root: 04 §9.2's
      // "rotate UMK" is the only reason to retire one, and a key rotated away after a stolen phone
      // is exactly the key an attacker may hold.
      rows()[0].superseded_at = r.clock.now;
      const late = await phone(r, first.user);
      const old = await certify(r, late, umk.priv, { umk_key_version: 1 });
      assertEquals(old.status, 400);
      assertEquals((await body(old)).error, "umk_unknown");
      assertEquals(r.db.devices.get(late.device.id)!.status, "registered");
      assertEquals(certOf(late.device.id), undefined);
      const evil = await edKeypair();
      const fresh = await certify(r, late, evil.priv, {
        umk_key_version: 2,
        umk_pub_ed: b64url.enc(evil.pub),
      });
      assertEquals(fresh.status, 400);
      assertEquals((await body(fresh)).error, "umk_version_conflict");
      assertEquals(rows().length, 1, "a retired root is not a vacancy");
      assertEquals(r.db.devices.get(late.device.id)!.status, "registered");
    },
  );

  await t.step(
    "an account with NO registration still self-certifies its first device (06 §3 step 4)",
    async () => {
      const other = await member(r, tenant, null, null, { status: "registered" });
      const k = await edKeypair();
      const p: Phone = {
        user: other.user,
        device: other.device,
        keys: other.keys,
        xpub: other.xpub,
        token: other.token,
      };
      const res = await certify(r, p, k.priv, {
        umk_key_version: 1,
        umk_pub_ed: b64url.enc(k.pub),
      });
      assertEquals(res.status, 200, await res.clone().text());
      assert(r.db.umk_public_keys.some((x) => x.user_id === other.user && x.key_version === 1));
    },
  );
});
