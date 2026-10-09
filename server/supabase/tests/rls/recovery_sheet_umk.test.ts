// Hostile-query arm for rung 3's `expected` — ADR 2026-10-06d ruling 2 🔒, ADR 2026-09-13c §1
// (ratified), 04 §7.4 🔒, ADR 2026-09-05d §2, 0005 `umk_select`, 0011, 0012.
//
// GET /recovery/sheet hands the restoring phone its OWN account's published UMK (both public
// halves) beside the sealed blob, so the phone can compare the key it recovers with the paper RK
// against "the account's published UMK" before adopting it. The read needs no new SQL: rf_api
// already holds SELECT on `umk_public_keys` (0005:317) and `umk_select` (0005:318) admits the
// caller's own rows WITHOUT a certification gate — which is what lets the uncertified, wiped phone
// read them at all.
//
// What this file pins is the thing RLS does NOT give for free. `umk_select` is
// `user_id = rf.user_id() or rf.shares_tenant(user_id)`: a CERTIFIED, active tenant-mate may read
// the subject's key rows through it (that is the verifier relay of 04 §6.3). A sheet read that
// leaned on RLS alone would therefore hand a tenant-mate who has a sheet but no registered key
// SOMEBODY ELSE's UMK as its `expected`. PgStore.recoverySheet must filter on the caller itself;
// E-1006d-4 proves the leak is reachable under RLS and that PgStore does not take it.
//
// Fixture rows a hostile caller could not write (users, devices, memberships, key rows, sheet rows)
// go in on the owner's connection; the arm under test is PgStore on the rf_api login (_pg_api.ts),
// so 0005's policies are real. Random bytes stand in for every key and blob — nothing financial.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Id E-1006d-4.
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";
import { apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — recovery_sheet_umk.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP recovery_sheet_umk.test.ts: ${why}`);
}
const ignore = !url;

const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

/** The raw read a hostile caller can make, as rf_api under its own claims. */
async function asApi<T>(
  sql: postgres.Sql,
  user: string,
  device: string,
  fn: (s: postgres.TransactionSql) => Promise<T>,
): Promise<T> {
  return await sql.begin(async (s) => {
    await s`set local role rf_api`;
    await s`select rf.set_claims(${user}::uuid, ${device}::uuid)`;
    return await fn(s);
  }) as T;
}

Deno.test({
  name:
    "E-1006d-4 through PgStore on the rf_api login: the wiped phone (uncertified) reads its OWN published UMK, both halves, byte-equal to the stored row; a certified tenant-mate whom `umk_select` WOULD let read the subject's key gets null for itself, never the subject's; Ed-only relays a null X; the newest key_version wins; a superseded newest row is null, not the older key; a stranger with no sheet reads no sheet (ADR 2026-10-06d ruling 2 🔒; 0005 umk_select; 0012)",
  ignore,
  async fn() {
    const sql = postgres(url!, { max: 1, onnotice: () => {} });
    const store = await apiStore(url!);
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
      const subject = await mk(), mate = await mk(), stranger = await mk();
      const edOnly = await mk(), rotated = await mk(), retired = await mk();
      const d = {
        subjectOld: await dev(subject, "certified"),
        candidate: await dev(subject, "registered"), // the wiped phone: never certified
        mate: await dev(mate, "certified"),
        stranger: await dev(stranger, "certified"),
        edOnly: await dev(edOnly, "registered"),
        rotated: await dev(rotated, "registered"),
        retired: await dev(retired, "registered"),
      };
      // The mate FOUNDS t1 (active, nobody to verify it — 06 §5) and the subject is a member of it
      // that is not `removed`: exactly what rf.shares_tenant (0005:41) needs to admit the mate to
      // the subject's key rows under `umk_select`.
      const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
      const [t2] = await sql`insert into tenants (type) values ('family') returning id`;
      await sql`insert into memberships (tenant_id, user_id, status) values
        (${t1.id}, ${mate}, 'active'), (${t2.id}, ${stranger}, 'active')`;
      await sql`insert into memberships (tenant_id, user_id, status)
        values (${t1.id}, ${subject}, 'joined_pending_verification')`;

      const sEd = rand(32), sX = rand(32);
      await sql`insert into umk_public_keys (user_id, key_version, pub_ed, pub_x)
        values (${subject}, 1, ${sEd}, ${sX})`;
      const eEd = rand(32);
      await sql`insert into umk_public_keys (user_id, key_version, pub_ed, pub_x)
        values (${edOnly}, 1, ${eEd}, null)`;
      const r1Ed = rand(32), r2Ed = rand(32), r2X = rand(32);
      // A rotation as maintenance would leave it: version 1 retired, version 2 the one live row.
      // Two LIVE rows is a state 0031's umk_public_keys_one_live refuses even to the owner (E-05d-2).
      await sql`insert into umk_public_keys (user_id, key_version, pub_ed, pub_x, superseded_at)
        values (${rotated}, 1, ${r1Ed}, ${
        rand(32)
      }, now()), (${rotated}, 2, ${r2Ed}, ${r2X}, null)`;
      await sql`insert into umk_public_keys (user_id, key_version, pub_ed, pub_x, superseded_at)
        values (${retired}, 1, ${rand(32)}, ${rand(32)}, null),
               (${retired}, 2, ${rand(32)}, ${rand(32)}, now())`;
      // the mate registers NO key; every user but the stranger holds a sheet
      const blob: Record<string, Uint8Array> = {};
      for (const [name, user] of Object.entries({ subject, mate, edOnly, rotated, retired })) {
        blob[name] = rand(72);
        await sql`insert into recovery_sheets (user_id, sheet_version, blob)
          values (${user}, 1, ${blob[name]})`;
      }

      const read = (user: string, device: string) =>
        store.withClaims({ user_id: user, device_id: device }, (tx) => tx.recoverySheet());

      // ---- the subject's wiped phone: its own key, both halves, byte-equal
      const own = await read(subject, d.candidate);
      assert(own, "the subject's own sheet is served to its uncertified phone");
      assertEquals(own.user_id, subject);
      assertEquals(own.blob, blob.subject);
      assert(own.umk, "the published UMK rides with it");
      assertEquals(own.umk.pub_ed, sEd, "Ed25519 half byte-equal to the stored row");
      assertEquals(own.umk.pub_x, sX, "X25519 half byte-equal to the stored row");
      const viaCert = await read(subject, d.subjectOld);
      assertEquals(viaCert?.umk?.pub_ed, sEd, "the certified device reads the same key");

      // ---- the hostile half: RLS WOULD let the mate read the subject's key…
      const leak = await asApi(
        sql,
        mate,
        d.mate,
        (s) => s`select pub_ed from umk_public_keys where user_id = ${subject}::uuid`,
      );
      assertEquals(
        leak.length,
        1,
        "precondition: under umk_select a certified tenant-mate CAN read the subject's key row — " +
          "so only PgStore's own-user filter keeps it out of the mate's `expected`",
      );
      // …and PgStore does not hand it over.
      const mates = await read(mate, d.mate);
      assert(mates, "the mate's own sheet is served");
      assertEquals(mates.user_id, mate);
      assertEquals(mates.blob, blob.mate);
      assertEquals(mates.umk, null, "no key registered for the mate → null, never the subject's");

      // ---- a stranger reaches neither the subject's key nor any sheet
      const strangerRaw = await asApi(
        sql,
        stranger,
        d.stranger,
        (s) => s`select pub_ed from umk_public_keys where user_id = ${subject}::uuid`,
      );
      assertEquals(strangerRaw.length, 0, "umk_select: another tenant's member reads no key row");
      assertEquals(
        await read(stranger, d.stranger),
        null,
        "no sheet → null (the route's no_sheet)",
      );

      // ---- shapes that must not invent a key
      const e = await read(edOnly, d.edOnly);
      assertEquals(e?.umk?.pub_ed, eEd, "an Ed-only row relays its Ed half");
      assertEquals(e?.umk?.pub_x, null, "…and a null X half (0012), never made up");
      const rot = await read(rotated, d.rotated);
      assertEquals(rot?.umk?.pub_ed, r2Ed, "the NEWEST key_version is the published key");
      assertEquals(rot?.umk?.pub_x, r2X);
      const ret = await read(retired, d.retired);
      assert(ret, "the blob is still served");
      assertEquals(ret.blob, blob.retired);
      assertEquals(ret.umk, null, "a superseded newest row is null — no fallback to version 1");
    } finally {
      await store.end();
      await sql.end();
    }
  },
});
