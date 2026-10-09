// Hostile-query arm for "one registered UMK per user" — ADR 2026-09-05d §2 🔒 (the server verifies a
// certificate under the user's REGISTERED UMK public key), 06 §3 🔒 steps 3–4 ("First device only:
// generate UMK, self-certify"), 04 §3.4 🔒. Repair of the M13 RUNG3S review, finding 1; migration
// 0031. The MemStore arm through the real handlers is E-05d-1 (_tests/umk_single_root.test.ts).
//
// Before 0031, rf.set_umk_pubs (0012) checked only p_user = rf.user_id() and rf.certify_device
// (0005) only p_device = rf.device_id(). So a registered, OTP-only device could write a UMK of its
// own at key_version 2 beside the account's version 1, certify itself under it, and the sheet read
// (newest key_version) relayed it as the account's published UMK. Measured on HEAD as rf_api:
// tx.setUmkPubs(user, 2, evil) + tx.certifyDevice(…, 2) → devices.status = 'certified', and
// tx.recoverySheet().umk.pub_ed == evil. This file is that probe, run against the database.
//
// Fixture rows a hostile caller could not write (users, devices, key rows, sheet rows) go in on the
// owner's connection; every arm under test runs on the rf_api login (_pg_api.ts), so 0005's policies
// and 0031's guards are real. Random bytes stand in for every key and blob — nothing financial.
//
// "Refused by name" means what the WIRE answers, not what the message text says. A guard's token
// reaches the client only if its errcode is one denialFromPg (store.ts) maps: PgStore.guarded()
// turns those into StoreDenied, certifyWith (auth-challenge) answers a StoreDenied's reason as a
// 400, and anything else leaves entry() (_shared/deps.ts) as `500 internal`. So every arm here is
// judged on that path: the auth-challenge handler over this PgStore behind entry(), as deployed;
// PgStore calls count only a StoreDenied; raw rf_api calls count only what denialFromPg names. A
// guard re-raised with an errcode the edge does not map fails this file (review UMK0031, finding 1).
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Id E-05d-2.
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";
import { b64url } from "../../functions/_shared/bytes.ts";
import { mintAccessToken } from "../../functions/_shared/claims.ts";
import { entry } from "../../functions/_shared/deps.ts";
import { denialFromPg, StoreDenied } from "../../functions/_shared/store.ts";
import { handler as auth } from "../../functions/auth-challenge/index.ts";
import { body, certBytes, edKeypair, post, rig, sign } from "../../functions/_tests/harness.ts";
import { apiSql, apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — umk_single_root.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP umk_single_root.test.ts: ${why}`);
}
const ignore = !url;

const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

/** What the edge makes of an error it did not name: entry() answers it `500 internal`. The code and
 *  message are kept so a failing assertion says which guard escaped the mapping. */
const unnamed = (e: unknown) => {
  const x = e as { code?: string; message?: string };
  return `500 internal (unmapped ${x?.code ?? "?"}: ${String(x?.message ?? e).trim()})`;
};

/** A PgStore call's verdict: a StoreDenied's reason — the only refusal certifyWith answers by
 *  name — or the 500 anything else becomes. A raw PostgresError is NEVER read as a name here. */
async function storeRefusal(p: Promise<unknown>): Promise<string> {
  try {
    await p;
  } catch (e) {
    return e instanceof StoreDenied ? e.reason : unnamed(e);
  }
  return "ACCEPTED";
}

/** A raw rf_api call's verdict, judged by the mapping PgStore.guarded() applies (denialFromPg):
 *  the name the edge would answer, or the 500 it would answer instead. */
async function rawRefusal(p: Promise<unknown>): Promise<string> {
  try {
    await p;
  } catch (e) {
    return denialFromPg(e)?.reason ?? unnamed(e);
  }
  return "ACCEPTED";
}

Deno.test({
  name:
    "E-05d-2 through the auth-challenge handler over PgStore (behind entry(), as deployed), PgStore itself and raw SQL on the rf_api login — each refusal judged by what the edge answers, a StoreDenied or a code denialFromPg maps, never by message text: a registered device cannot register a UMK at a second key_version (`umk_version_conflict`) nor be certified under a version with no live row (`umk_unknown`) — the RUNG3S probe leaves the device registered and the sheet relaying the REGISTERED key; a retired registration certifies nobody and still blocks a new version; the owner itself cannot hold two live rows (umk_public_keys_one_live); two first registrations racing at different versions leave exactly one, the loser refused by name; the honest second device still certifies at version 1 (ADR 2026-09-05d §2 🔒; 06 §3 🔒; 04 §3.4 🔒; 0031)",
  ignore,
  async fn() {
    const sql = postgres(url!, { max: 1, onnotice: () => {} });
    const store = await apiStore(url!);
    const racers: postgres.Sql[] = [];
    try {
      // ---- fixtures, on the owner's connection
      const mk = async () => {
        const [u] = await sql`insert into users (phone_hmac, phone_ct)
          values (${rand(32)}, ${rand(40)}) returning id`;
        return u.id as string;
      };
      const dev = async (user: string, status: string) => {
        const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
          values (gen_random_uuid(), ${user}, ${rand(32)}, ${rand(32)}, ${status}) returning id`;
        return d.id as string;
      };
      const u = await mk(), retired = await mk(), racer = await mk();
      const oldRoot = await edKeypair(); // the retired registration's key, so its holder can sign
      const d = {
        first: await dev(u, "certified"),
        intruder: await dev(u, "registered"), // OTP passed, holds nothing (ADR 05d §2)
        honest: await dev(u, "registered"),
        retired: await dev(retired, "registered"),
        r1: await dev(racer, "registered"),
        r2: await dev(racer, "registered"),
      };
      const realEd = rand(32), realX = rand(32);
      await sql`insert into umk_public_keys (user_id, key_version, pub_ed, pub_x)
        values (${u}, 1, ${realEd}, ${realX})`;
      await sql`insert into umk_public_keys (user_id, key_version, pub_ed, pub_x, superseded_at)
        values (${retired}, 1, ${oldRoot.pub}, ${rand(32)}, now())`;
      const blob = rand(72);
      await sql`insert into recovery_sheets (user_id, sheet_version, blob) values (${u}, 1, ${blob})`;

      const status = async (id: string) =>
        (await sql`select status from devices where id = ${id}`)[0].status as string;
      const certs = async (id: string) =>
        (await sql`select count(*)::int as n from device_certs where device_id = ${id}`)[0]
          .n as number;
      const rowsOf = async (user: string) =>
        await sql`select key_version, pub_ed, pub_x from umk_public_keys
          where user_id = ${user} order by key_version`;
      const as = (user: string, device: string) => ({ user_id: user, device_id: device });

      // ---- the wire: POST /auth-challenge/devices/certify, the handler over this PgStore, behind
      // entry() — so an unmapped guard error is the 500 production would answer, not a pass.
      const r = rig();
      r.deps.store = store;
      const edge = entry(auth, () => r.deps);
      const phone = async (user: string) => {
        const keys = await edKeypair(), xpub = rand(32);
        const [row] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
          values (gen_random_uuid(), ${user}, ${keys.pub}, ${xpub}, 'registered') returning id`;
        const id = row.id as string;
        const nowS = Math.floor(r.clock.now.getTime() / 1000);
        const token = await mintAccessToken(r.deps.jwtKey, { user_id: user, device_id: id }, nowS);
        return { id, keys, xpub, token };
      };
      const wire = async (
        p: Awaited<ReturnType<typeof phone>>,
        signer: Uint8Array,
        extra: Record<string, unknown>,
      ) => {
        const issued = r.clock.now.getTime();
        const sig = await sign(certBytes(p.id, p.keys.pub, p.xpub, issued), signer);
        const res = await edge(post("/auth-challenge/devices/certify", {
          ...extra,
          cert: { signature: b64url.enc(sig), issued_at_ms: issued },
        }, { token: p.token }));
        const b = await body(res);
        return `${res.status} ${b.error ?? b.status}`; // "400 <reason>" · "500 internal" · "200 certified"
      };

      // ---- 1. the RUNG3S probe, verbatim, through PgStore: both writes refused by name
      const evilEd = rand(32), evilX = rand(32);
      const probe = await store.withClaims(as(u, d.intruder), async (tx) => {
        const set = await storeRefusal(tx.setUmkPubs(u, 2, evilEd, evilX));
        const cert = await storeRefusal(
          tx.certifyDevice(d.intruder, rand(64), new Date(), null, 2),
        );
        return { set, cert, sheet: await tx.recoverySheet() };
      });
      assertEquals(probe.set, "umk_version_conflict", "a second root is not registered");
      assertEquals(probe.cert, "umk_unknown", "no certificate under a version with no live row");
      assertEquals(await status(d.intruder), "registered", "the intruder is NOT certified");
      assertEquals(await certs(d.intruder), 0, "no certificate stored");
      const after = await rowsOf(u);
      assertEquals(after.length, 1, "the account still has exactly one UMK row");
      assertEquals(after[0].key_version, 1);
      assertEquals(new Uint8Array(after[0].pub_ed), realEd);
      assert(probe.sheet?.umk, "the sheet still carries the published key");
      assertEquals(probe.sheet.blob, blob);
      assertEquals(probe.sheet.umk.pub_ed, realEd, "the REGISTERED Ed half, never the minted one");
      assertEquals(probe.sheet.umk.pub_x, realX, "the REGISTERED X half, never the minted one");

      // ---- 1b. the same probe as the client sends it: a self-made root at version 2, its
      // certificate signed by that root. The handler verifies the signature and asks the store to
      // register the key; 0031 refuses, and the client is TOLD so — a 400 by name, not a 500.
      const minted = await edKeypair();
      const caller = await phone(u);
      assertEquals(
        await wire(caller, minted.priv, {
          umk_key_version: 2,
          umk_pub_ed: b64url.enc(minted.pub),
          umk_pub_x: b64url.enc(rand(32)),
        }),
        "400 umk_version_conflict",
        "the wire names the refusal",
      );
      assertEquals(await status(caller.id), "registered", "the caller is NOT certified");
      assertEquals(await certs(caller.id), 0);
      assertEquals((await rowsOf(u)).length, 1, "the minted root was not written");

      // ---- 2. raw rf_api, around the store: the database holds the rule itself
      const api = await apiSql(url!);
      racers.push(api);
      const raw = (fn: (s: postgres.TransactionSql) => Promise<unknown>) =>
        rawRefusal(api.begin(async (s) => {
          await s`select rf.set_claims(${u}::uuid, ${d.intruder}::uuid)`;
          return await fn(s);
        }));
      for (const v of [2, 7]) {
        assertEquals(
          await raw((s) => s`select rf.set_umk_pubs(${u}::uuid, ${v}, ${rand(32)}::bytea, null)`),
          "umk_version_conflict",
          `rf.set_umk_pubs at version ${v}`,
        );
        assertEquals(
          await raw((s) =>
            s`select rf.certify_device(${d.intruder}::uuid, ${rand(64)}, now(), null, ${v})`
          ),
          "umk_unknown",
          `rf.certify_device at version ${v}`,
        );
      }
      assertEquals(await status(d.intruder), "registered");
      assertEquals((await rowsOf(u)).length, 1);

      // ---- 3. no over-block: the registered root still works
      const honest = await store.withClaims(as(u, d.honest), async (tx) => {
        const same = await storeRefusal(tx.setUmkPubs(u, 1, realEd, realX)); // idempotent re-offer
        const cert = await storeRefusal(
          tx.certifyDevice(d.honest, rand(64), new Date(), d.first, 1),
        );
        return { same, cert };
      });
      assertEquals(honest.same, "ACCEPTED", "re-offering the registered key is a no-op");
      assertEquals(honest.cert, "ACCEPTED", "certify at the registered version");
      assertEquals(await status(d.honest), "certified");

      // ---- 4. a retired registration certifies nobody and is not a vacancy
      const ret = await store.withClaims(as(retired, d.retired), async (tx) => ({
        cert: await storeRefusal(tx.certifyDevice(d.retired, rand(64), new Date(), null, 1)),
        set: await storeRefusal(tx.setUmkPubs(retired, 2, rand(32), rand(32))),
      }));
      assertEquals(ret.cert, "umk_unknown", "a superseded row is no root");
      assertEquals(ret.set, "umk_version_conflict", "a retired root does not free the account");
      assertEquals(await status(d.retired), "registered");
      assertEquals((await rowsOf(retired)).length, 1);
      // On the wire: a certificate that VERIFIES under the retired key (the handler reads the row
      // by version and checks the signature) is refused by the database's root check, by name.
      const holder = await phone(retired);
      assertEquals(
        await wire(holder, oldRoot.priv, { umk_key_version: 1 }),
        "400 umk_unknown",
        "a valid signature under a retired root certifies nobody, and says so",
      );
      assertEquals(
        await wire(holder, minted.priv, { umk_key_version: 2, umk_pub_ed: b64url.enc(minted.pub) }),
        "400 umk_version_conflict",
        "a retired root is not a vacancy on the wire either",
      );
      assertEquals(await status(holder.id), "registered");
      assertEquals(await certs(holder.id), 0);
      assertEquals((await rowsOf(retired)).length, 1);

      // ---- 5. structural: not even the owner can hold two live rows for one user
      type PgErr = { code?: string; constraint_name?: string };
      const ix: PgErr | null = await sql`insert into umk_public_keys (user_id, key_version, pub_ed)
          values (${u}, 2, ${rand(32)})`.then(() => null, (e: PgErr) => e);
      assertEquals(ix?.code, "23505", "a second LIVE row is a unique violation");
      assertEquals(ix?.constraint_name, "umk_public_keys_one_live");

      // ---- 6. the race the explicit check cannot see: two FIRST registrations at once
      const s1 = await apiSql(url!), s2 = await apiSql(url!);
      racers.push(s1, s2);
      const k1 = rand(32), k2 = rand(32);
      let release!: () => void;
      const gate = new Promise<void>((r) => (release = r));
      let wrote!: () => void;
      const t1Wrote = new Promise<void>((r) => (wrote = r));
      const t1 = s1.begin(async (s) => {
        await s`select rf.set_claims(${racer}::uuid, ${d.r1}::uuid)`;
        await s`select rf.set_umk_pubs(${racer}::uuid, 1, ${k1}::bytea, null)`;
        wrote();
        await gate; // hold the uncommitted live row while T2 runs
      });
      await t1Wrote;
      const t2 = rawRefusal(s2.begin(async (s) => {
        await s`select rf.set_claims(${racer}::uuid, ${d.r2}::uuid)`;
        await s`select rf.set_umk_pubs(${racer}::uuid, 2, ${k2}::bytea, null)`;
      }));
      // T2's "any other registration?" check cannot see T1's uncommitted row; it must be waiting on
      // umk_public_keys_one_live, not past it, before T1 commits — else this arm proves nothing.
      for (let i = 0;; i++) {
        const [w] = await sql`select count(*)::int as n from pg_stat_activity
          where datname = current_database() and wait_event_type = 'Lock'
            and query like '%set_umk_pubs%'`;
        if (w.n >= 1) break;
        if (i > 200) throw new Error("precondition: T2 never blocked on T1's live row");
        await new Promise((r) => setTimeout(r, 25));
      }
      release();
      await t1;
      assertEquals(
        await t2,
        "umk_version_conflict",
        "the race loser is refused BY NAME, not a 500",
      );
      const won = await rowsOf(racer);
      assertEquals(won.length, 1, "exactly one root registered");
      assertEquals(won[0].key_version, 1);
      assertEquals(new Uint8Array(won[0].pub_ed), k1);
    } finally {
      for (const s of racers) await s.end();
      await store.end();
      await sql.end();
    }
  },
});
