// GET /sync-meta over the REAL store (PgStore as rf_api, via _pg_api.ts) on a page carrying every
// bytea column the meta channel serves (desk 99).
//
// postgres.js hands a bytea column back as a node Buffer: a view into a pooled ArrayBuffer that
// cannot be detached. @std/encoding's base64url encoder transfers its input's buffer, so encoding
// that view directly threw "ArrayBuffer is not detachable" and failed EVERY meta page carrying bytes
// on the real store — `sync-meta/index.ts`'s `bin` copies first since M13-REV89S. MemStore holds
// plain Uint8Arrays, so the functions/_tests suite could never see it, and no PgStore test had run
// GET /sync-meta before this one.
//
// E-05-20: one pull, as the subject, over a tenant set up so that every bytea-bearing table of 05 §5
// has a visible row — devices (pub_ed, pub_x), device_certs (cert), wrapped_keys (blob),
// umk_public_keys (pub_ed, pub_x), guardian_set_members (umk_pub_ed), recovery_requests
// (candidate_pub_x — the shapeRow default arm), entitlement_tokens (token, minted by this very
// pull), and the signed records (payload_bytes, author_sig). The answer is 200 and every value
// base64url-decodes to exactly the bytes the database holds — so an empty or dropped value fails as
// surely as a crash does.
//
// Fixtures are written by the schema owner without claims; every byte is random — no ledger content
// and no real key exists here. Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`); without it the
// test is SKIPPED and says why, and RLS_REQUIRE=1 makes that a failure.
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";
import { b64url } from "../../functions/_shared/bytes.ts";
import { handler as meta } from "../../functions/sync-meta/index.ts";
import {
  body,
  edKeypair,
  get,
  type KeyPair,
  type Member,
  reissue,
  type Rig,
  rig,
} from "../../functions/_tests/harness.ts";
import { apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — meta_pull_bytea.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP meta_pull_bytea.test.ts: ${why}`);
}

const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));
const dec = (v: unknown): Uint8Array => {
  assert(typeof v === "string" && v.length > 0, `a base64url string, got ${JSON.stringify(v)}`);
  return b64url.dec(v);
};

interface P {
  user: string;
  dev: string;
  keys: KeyPair;
  pubX: Uint8Array;
}

Deno.test({
  name:
    "E-05-20 GET /sync-meta over the real store (PgStore as rf_api, desk 99): a page carrying every bytea column the meta channel serves — devices pub_ed/pub_x, device_certs cert, wrapped_keys blob, umk_public_keys pub_ed/pub_x, guardian_set_members umk_pub_ed, recovery_requests candidate_pub_x, entitlement_tokens token, signed records payload/author_sig — answers 200, and every value base64url-decodes to exactly the bytes the database holds",
  ignore: !url,
  async fn() {
    const sql = postgres(url!, { max: 2, onnotice: () => {} });
    try {
      const person = async (): Promise<P> => {
        const keys = await edKeypair();
        const pubX = rand(32);
        const [u] = await sql`insert into users (phone_hmac, phone_ct)
          values (${rand(32)}, ${rand(40)}) returning id`;
        const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
          values (gen_random_uuid(), ${u.id}, ${keys.pub}, ${pubX}, 'certified') returning id`;
        return { user: u.id as string, dev: d.id as string, keys, pubX };
      };
      // A family tenant on the Free floor; the subject is its active founder, the two guardians
      // active members of it (0026: a set names the tenant its publisher is active in).
      const [tr] = await sql`insert into tenants (type) values ('family') returning id`;
      const t = tr.id as string;
      const subject = await person(), g1 = await person(), g2 = await person();
      await sql`insert into memberships (tenant_id, user_id, status)
        values (${t}, ${subject.user}, 'active')`;
      for (const g of [g1, g2]) {
        // Active only after a signed ceremony (0006/0008's guards), as tests/rls places members.
        const vr = crypto.randomUUID();
        await sql`insert into signed_records
            (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device,
             author_sig, hlc)
          values (${vr}, 1, ${t}, 'verification_event', '{}'::jsonb, ${rand(8)}, ${subject.dev},
                  ${rand(64)}, 1)`;
        await sql`insert into verification_events
            (tenant_id, subject_user, verifier_user, method, result, source_record_id)
          values (${t}, ${g.user}, ${subject.user}, 'qr_in_person', 'verified', ${vr})`;
        await sql`insert into memberships (tenant_id, user_id, status)
          values (${t}, ${g.user}, 'active')`;
      }
      const cert = rand(64);
      await sql`insert into device_certs (device_id, cert, issued_at, umk_key_version)
        values (${subject.dev}, ${cert}, now(), 1)`;
      const umkEd = rand(32), umkX = rand(32);
      await sql`insert into umk_public_keys (user_id, key_version, pub_ed, pub_x)
        values (${subject.user}, 1, ${umkEd}, ${umkX})`;
      const wrappedId = crypto.randomUUID(), wrapped = rand(80);
      await sql`insert into wrapped_keys (id, kind, user_id, device_id, key_version, blob)
        values (${wrappedId}, 'umk_for_device', ${subject.user}, ${subject.dev}, 1, ${wrapped})`;
      await sql`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
        values (${subject.user}, 1, 2, 2, ${t})`;
      const gPub = new Map([[g1.user, rand(32)], [g2.user, rand(32)]]);
      for (const [g, pub] of gPub) {
        await sql`insert into guardian_set_members
            (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
          values (${subject.user}, 1, ${g}, ${pub})`;
      }
      const candidateX = rand(32);
      const [rq] = await sql`insert into recovery_requests
          (user_id, candidate_device, candidate_pub_x, expires_at)
        values (${subject.user}, ${subject.dev}, ${candidateX}, now()) returning id`;
      const recId = crypto.randomUUID(), payload = rand(24), sig = rand(64);
      await sql`insert into signed_records
          (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device,
           author_sig, hlc)
        values (${recId}, 1, ${t}, 'designation', '{}'::jsonb, ${payload}, ${subject.dev},
                ${sig}, 1)`;

      const r: Rig = rig();
      const m = {
        user: subject.user,
        device: { id: subject.dev },
        keys: subject.keys,
        xpub: subject.pubX,
        claims: { user_id: subject.user, device_id: subject.dev },
        token: "",
      } as unknown as Member;
      await reissue(r, m);
      const store = await apiStore(url!);
      r.deps.store = store;
      let out: Record<string, any>;
      try {
        const res = await meta(get("/sync-meta", { token: m.token }), r.deps);
        assertEquals(res.status, 200, "a page with bytes is served, not a 500");
        out = await body(res);
      } finally {
        await store.end();
      }
      assertEquals(out.has_more, false, "one page holds the subject's whole world");
      const one = (table: string, pred: (x: Record<string, any>) => boolean) => {
        const rows = (out[table] as Record<string, any>[]).filter(pred);
        assertEquals(rows.length, 1, `${table}: exactly the one row under test is on the page`);
        return rows[0];
      };

      const dev = one("devices", (x) => x.id === subject.dev);
      assertEquals(dec(dev.pub_ed), subject.keys.pub, "devices.pub_ed");
      assertEquals(dec(dev.pub_x), subject.pubX, "devices.pub_x");
      for (const g of [g1, g2]) {
        const gd = one("devices", (x) => x.id === g.dev);
        assertEquals(dec(gd.pub_ed), g.keys.pub, "a co-member's devices.pub_ed");
      }
      assertEquals(
        dec(one("device_certs", (x) => x.device_id === subject.dev).cert.signature),
        cert,
        "device_certs.cert",
      );
      assertEquals(dec(one("wrapped_keys", (x) => x.id === wrappedId).blob), wrapped, "blob");
      const umk = one("umk_public_keys", (x) => x.user_id === subject.user);
      assertEquals(dec(umk.pub_ed), umkEd, "umk_public_keys.pub_ed");
      assertEquals(dec(umk.pub_x), umkX, "umk_public_keys.pub_x");
      for (const [g, pub] of gPub) {
        const gm = one(
          "guardian_set_members",
          (x) => x.subject_user_id === subject.user && x.guardian_user_id === g,
        );
        assertEquals(dec(gm.umk_pub_ed), pub, "guardian_set_members.umk_pub_ed");
      }
      assertEquals(
        dec(one("recovery_requests", (x) => x.id === rq.id).candidate_pub_x),
        candidateX,
        "recovery_requests.candidate_pub_x (shapeRow's default arm)",
      );
      const [tok] = await sql`select token from entitlement_tokens where tenant_id = ${t}`;
      assert(tok, "precondition: this pull minted the tenant's entitlement token");
      assertEquals(
        dec(one("entitlement_tokens", (x) => x.tenant_id === t).token),
        new Uint8Array(tok.token),
        "entitlement_tokens.token",
      );
      const rec = one("signed_records", (x) => x.id === recId);
      assertEquals(dec(rec.payload_json), payload, "signed record payload bytes");
      assertEquals(dec(rec.author_sig), sig, "signed record author_sig");
    } finally {
      await sql.end();
    }
  },
});
