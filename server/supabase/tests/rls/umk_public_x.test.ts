// Hostile-query suite for the UMK's X25519 public half and for ceremony-session discovery —
// migration 0012, against 04 §3.1, 04 §6.1 🔒, 04 §6.3 🔒, 04 §6.4, 03 §2.1, 06 §9.3.
//
// Why the column exists at all: 04 §6.3 🔒 says "the verifier's device compares scanned public
// KEYS byte-for-byte against the server-relayed keys for that user … There is no override", and
// core_crypto's verifyQr (packages/core_crypto/lib/src/ceremony.dart:490-492) compares BOTH halves
// of an UmkPublic that cannot be constructed without both (keys.dart:57-65). `umk_public_keys`
// stored `pub_ed` alone (0001:48), so the relay could hand a verifier only half of what it must
// compare — and the missing half is not derivable from the ed half (its own seed, keys.dart:13).
//
// Why write-once is the security property: the server is the untrusted relay. If it could swap a
// stored x half, §6.3's byte-for-byte comparison would run against the attacker's own material and
// would PASS. So the three adversaries of this file are the ones that suite already names:
//
//   * a device of ANOTHER user reaching for someone else's UMK halves,
//   * the owner's OWN device offering different key material a second time,
//   * anything holding an UPDATE on the table — including the table owner.
//
// and for discovery: a certified device of ANOTHER tenant, a non-member, an UNCERTIFIED device.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-06-62 … E-06-67.
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — umk_public_x.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP umk_public_x.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;

async function asApi<T>(
  user: string | null,
  device: string | null,
  fn: (s: postgres.TransactionSql) => Promise<T>,
): Promise<T> {
  return await sql.begin(async (s) => {
    await s`set local role rf_api`;
    await s`select rf.set_claims(${user}::uuid, ${device}::uuid)`;
    return await fn(s);
  }) as T;
}
interface PgErr {
  code: string;
  message: string;
  detail: string;
}
async function pgErr(p: Promise<unknown>): Promise<PgErr> {
  try {
    await p;
    return { code: "ok", message: "", detail: "" };
  } catch (e) {
    const x = e as { code?: string; message?: string; detail?: string };
    return { code: x.code ?? "unknown", message: x.message ?? "", detail: x.detail ?? "" };
  }
}
const pgMsg = async (p: Promise<unknown>) => (await pgErr(p)).message;
const pgCode = async (p: Promise<unknown>) => (await pgErr(p)).code;
const bytes = (n: number, fill: number) => new Uint8Array(n).fill(fill);

/** rf.set_umk_pubs as the owner's own device. Casts are explicit so a NULL x half still binds. */
function setPubs(
  user: string,
  device: string,
  version: number,
  pubEd: Uint8Array,
  pubX: Uint8Array | null,
): Promise<unknown> {
  return asApi(
    user,
    device,
    (s) => s`select rf.set_umk_pubs(${user}::uuid, ${version}, ${pubEd}::bytea, ${pubX}::bytea)`,
  );
}

interface Fx {
  t1: string;
  t2: string;
  owner: string;
  member: string;
  outsider: string;
  stranger: string;
  dev: Record<string, string>;
}
let fx: Fx;

async function seed(): Promise<Fx> {
  const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
  const [t2] = await sql`insert into tenants (type) values ('business_group') returning id`;
  // fills 0xb1+: ceremony_sessions.test.ts owns 0xa1–0xa4 and invites.test.ts owns 11–15, 21, 31, 99
  const mk = async (fill: number) => {
    const [u] = await sql`insert into users (phone_hmac, phone_ct)
      values (${bytes(32, fill)}, ${bytes(40, fill)}) returning id`;
    return u.id as string;
  };
  const owner = await mk(0xb1),
    member = await mk(0xb2),
    outsider = await mk(0xb3),
    stranger = await mk(0xb4);

  const dev: Record<string, string> = {};
  for (
    const [name, user, status] of [
      ["owner", owner, "certified"],
      ["ownerraw", owner, "registered"], // the owner's UNCERTIFIED second device
      ["member", member, "certified"], // an active member of the owner's tenant
      ["outsider", outsider, "certified"], // certified, but in ANOTHER tenant
      ["stranger", stranger, "certified"], // in no tenant at all
    ] as const
  ) {
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${user}, ${bytes(32, 6)}, ${
      bytes(32, 7)
    }, ${status}) returning id`;
    dev[name] = d.id;
  }
  // Founders first (a tenant's first member needs no ceremony), then the second member of t1 —
  // which since 0008 is believed only where a signed record backs the verification (ADR 05d §7).
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${owner}, 'active'), (${t2.id}, ${outsider}, 'active')`;
  const vrec = crypto.randomUUID();
  await sql`insert into signed_records
    (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
    values (${vrec}, 1, ${t1.id}, 'verification_event', '{}'::jsonb, ${
    bytes(8, 1)
  }, ${dev.owner}, ${bytes(64, 2)}, 1)`;
  await sql`insert into verification_events
    (tenant_id, subject_user, verifier_user, method, result, source_record_id)
    values (${t1.id}, ${member}, ${owner}, 'qr_in_person', 'verified', ${vrec})`;
  await sql`insert into memberships (tenant_id, user_id, status)
    values (${t1.id}, ${member}, 'active')`;
  return { t1: t1.id, t2: t2.id, owner, member, outsider, stranger, dev };
}

Deno.test({
  name:
    "E-06-62 umk_public_keys.pub_x: a nullable 32-byte column, readable by rf_api through 0005's TABLE-level grant, with no INSERT/UPDATE/DELETE privilege anywhere in rf_api's reach and its immutability guard armed BEFORE the write (04 §6.3 🔒, migration 0012)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();

    const [col] = await sql<{ data_type: string; is_nullable: string }[]>`
      select data_type, is_nullable from information_schema.columns
      where table_name = 'umk_public_keys' and column_name = 'pub_x'`;
    assertEquals(col?.data_type, "bytea", "the x half is opaque bytes, like every other key here");
    assertEquals(
      col?.is_nullable,
      "YES",
      "nullable: a row for which no x half has been offered has none, and the server may not invent\n      one — today that is every row (no client sends umk_pub_x yet), not just the pre-0012 ones",
    );

    // 31 and 33 bytes are refused by the column CHECK itself — not only by the helper — so no
    // path, including a future migration or a maintenance statement, can land a wrong length.
    for (const n of [31, 33, 0, 64]) {
      assertEquals(
        await pgCode(
          sql`insert into umk_public_keys (user_id, key_version, pub_ed, pub_x)
              values (${fx.stranger}, 9, ${bytes(32, 1)}, ${bytes(n, 2)})`,
        ),
        "23514",
        `${n} bytes is not an X25519 public key`,
      );
    }

    // 0005:317 is `grant select on umk_public_keys to rf_api` — TABLE level, so it covers a column
    // added later. Asserted rather than assumed (CLAUDE.md rule 11): had it been column-scoped,
    // as `users`' grant is, 0012 would have needed its own `grant select (pub_x)`.
    await setPubs(fx.owner, fx.dev.owner, 1, bytes(32, 0xe1), bytes(32, 0x51));
    const seen = await asApi(
      fx.owner,
      fx.dev.owner,
      (s) => s`select pub_ed, pub_x from umk_public_keys where user_id = ${fx.owner}`,
    );
    assertEquals(seen.length, 1);
    assertEquals(new Uint8Array(seen[0].pub_x), bytes(32, 0x51), "both halves reach the API role");

    // The append-only shape of CLAUDE.md rule 2: rf_api may read this table and nothing else.
    const privs = await sql<{ privilege_type: string }[]>`
      select privilege_type from information_schema.table_privileges
      where grantee = 'rf_api' and table_name = 'umk_public_keys'`;
    assertEquals(
      privs.map((p) => p.privilege_type).sort(),
      ["SELECT"],
      "no INSERT, UPDATE or DELETE on umk_public_keys for the API role",
    );

    const trg = await sql<{ tgname: string; tgtype: number }[]>`
      select tgname, tgtype from pg_trigger t join pg_class c on c.oid = t.tgrelid
      where not t.tgisinternal and c.relname = 'umk_public_keys' and tgname like '%guard%'`;
    assertEquals(trg.length, 1, "umk_public_keys carries its immutability guard");
    assert((Number(trg[0].tgtype) & 2) !== 0, "the guard runs BEFORE the write");
  },
});

Deno.test({
  name:
    "E-06-63 rf.set_umk_pubs is write-once: identical material is a no-op, a different Ed25519 or X25519 half is refused umk_pub_conflict rather than overwritten, and a NULL x half is backfilled exactly once whenever that row was written (04 §6.3 🔒 — a substituted key is the attack, 0009's register_device the precedent)",
  ignore,
  async fn() {
    const ed = bytes(32, 0xe1), x = bytes(32, 0x51);

    // idempotent replay of exactly what is stored: the certify path re-offers its keys on every
    // POST /devices/certify, so this must not be an error.
    await setPubs(fx.owner, fx.dev.owner, 1, ed, x);
    const [row] = await sql`select * from umk_public_keys
      where user_id = ${fx.owner} and key_version = 1`;
    assertEquals(new Uint8Array(row.pub_ed), ed);
    assertEquals(new Uint8Array(row.pub_x), x);

    assertStringIncludes(
      await pgMsg(setPubs(fx.owner, fx.dev.owner, 1, bytes(32, 0xee), x)),
      "umk_pub_conflict",
      "a different Ed25519 half re-roots every device certificate of this user",
    );
    assertStringIncludes(
      await pgMsg(setPubs(fx.owner, fx.dev.owner, 1, ed, bytes(32, 0x5f))),
      "umk_pub_conflict",
      "a substituted X25519 half is precisely what 04 §6.3's comparison exists to catch",
    );
    // and neither attempt moved a byte
    const [after] = await sql`select * from umk_public_keys
      where user_id = ${fx.owner} and key_version = 1`;
    assertEquals(new Uint8Array(after.pub_ed), ed, "the stored ed half is untouched");
    assertEquals(new Uint8Array(after.pub_x), x, "the stored x half is untouched");

    // Offering NO x half leaves the stored one alone — it never nulls a key out.
    await setPubs(fx.owner, fx.dev.owner, 1, ed, null);
    const [kept] = await sql`select pub_x from umk_public_keys
      where user_id = ${fx.owner} and key_version = 1`;
    assertEquals(new Uint8Array(kept.pub_x), x, "an ed-only replay does not erase the x half");

    // A row with no x half — pre-0012, or written by any of today's clients, none of which send
    // umk_pub_x: pub_ed, no pub_x. The FIRST x half offered fills it; the second,
    // different one is refused. This is the whole migration path and the whole risk in it.
    await sql`insert into umk_public_keys (user_id, key_version, pub_ed)
      values (${fx.member}, 1, ${bytes(32, 0xe2)})`;
    await setPubs(fx.member, fx.dev.member, 1, bytes(32, 0xe2), bytes(32, 0x52));
    const [filled] = await sql`select pub_x from umk_public_keys
      where user_id = ${fx.member} and key_version = 1`;
    assertEquals(new Uint8Array(filled.pub_x), bytes(32, 0x52), "a NULL x half is backfilled once");
    assertStringIncludes(
      await pgMsg(setPubs(fx.member, fx.dev.member, 1, bytes(32, 0xe2), bytes(32, 0x5e))),
      "umk_pub_conflict",
      "backfilled once means once",
    );

    // A fresh registration writes both halves in one row.
    await setPubs(fx.stranger, fx.dev.stranger, 1, bytes(32, 0xe4), bytes(32, 0x54));
    const [fresh] = await sql`select pub_ed, pub_x from umk_public_keys
      where user_id = ${fx.stranger} and key_version = 1`;
    assertEquals(new Uint8Array(fresh.pub_ed), bytes(32, 0xe4));
    assertEquals(new Uint8Array(fresh.pub_x), bytes(32, 0x54));
  },
});

Deno.test({
  name:
    "E-06-64 rf.set_umk_pubs refuses anything that is not 32 bytes (31, 33, 0, 64) for either half, so nothing a verifier will later compare byte-for-byte can be the wrong length (04 §3.1, §6.3 🔒)",
  ignore,
  async fn() {
    for (const n of [31, 33, 0, 64]) {
      assertStringIncludes(
        await pgMsg(setPubs(fx.stranger, fx.dev.stranger, 2, bytes(32, 0xe4), bytes(n, 0x5a))),
        "umk_pub_malformed",
        `${n} bytes is refused as an x half`,
      );
      assertStringIncludes(
        await pgMsg(setPubs(fx.stranger, fx.dev.stranger, 2, bytes(n, 0xe4), bytes(32, 0x5a))),
        "umk_pub_malformed",
        `${n} bytes is refused as an ed half`,
      );
    }
    assertEquals(
      await pgCode(setPubs(fx.stranger, fx.dev.stranger, 2, bytes(32, 0xe4), null)),
      "ok",
      "…while a NULL x half is accepted: a client that sends no x half still registers its ed half",
    );
    assertEquals(
      (await sql`select 1 from umk_public_keys
        where user_id = ${fx.stranger} and key_version = 2 and pub_x is null`).length,
      1,
      "the ed-only row exists with a NULL x half, and the ceremony fails closed on the device",
    );
  },
});

Deno.test({
  name:
    "E-06-65 nobody reaches another user's UMK halves: rf.set_umk_pubs and rf.umk_pubs_for are both bounded to the caller's own user (not_owner), which also closes the enumeration oracle 0005's SECURITY DEFINER selector left open, while the relay path stays governed by umk_select",
  ignore,
  async fn() {
    // write for someone else
    for (
      const [u, d] of [["member", "member"], ["outsider", "outsider"], [
        "stranger",
        "stranger",
      ]] as const
    ) {
      assertStringIncludes(
        await pgMsg(
          asApi(
            (fx as unknown as Record<string, string>)[u],
            fx.dev[d],
            (s) =>
              s`select rf.set_umk_pubs(${fx.owner}::uuid, 1, ${bytes(32, 0xff)}::bytea, ${
                bytes(32, 0xff)
              }::bytea)`,
          ),
        ),
        "not_owner",
        `${u} cannot write the owner's UMK public key`,
      );
    }
    // read for someone else — including a fellow member of the same tenant, who gets these keys
    // through the RLS-checked relay instead (that is the path 04 §6.3 names).
    for (const [u, d] of [["member", "member"], ["outsider", "outsider"]] as const) {
      assertStringIncludes(
        await pgMsg(
          asApi(
            (fx as unknown as Record<string, string>)[u],
            fx.dev[d],
            (s) => s`select * from rf.umk_pubs_for(${fx.owner}::uuid, 1)`,
          ),
        ),
        "not_owner",
        `${u} cannot read the owner's halves through the definer helper`,
      );
    }
    // the relay path: umk_select (0005:318) still shows a fellow member both halves…
    const relayed = await asApi(
      fx.member,
      fx.dev.member,
      (s) => s`select pub_ed, pub_x from umk_public_keys where user_id = ${fx.owner}`,
    );
    assertEquals(relayed.length, 1, "a fellow member is relayed the owner's keys (04 §6.3)");
    assertEquals(
      new Uint8Array(relayed[0].pub_x).length,
      32,
      "both halves, so both can be compared",
    );
    // …and shows another tenant, and a user in no tenant, nothing at all.
    for (const [u, d] of [["outsider", "outsider"], ["stranger", "stranger"]] as const) {
      assertEquals(
        (await asApi(
          (fx as unknown as Record<string, string>)[u],
          fx.dev[d],
          (s) => s`select user_id from umk_public_keys where user_id = ${fx.owner}`,
        )).length,
        0,
        `${u} is relayed nothing`,
      );
    }
    // 0005's half-blind helpers are GONE, so an un-updated caller fails at bind time (0009:23).
    assertEquals(
      await pgCode(sql`select rf.umk_pub_for(${fx.owner}::uuid, 1)`),
      "42883",
      "rf.umk_pub_for no longer exists",
    );
    assertEquals(
      await pgCode(sql`select rf.set_umk_pub(${fx.owner}::uuid, 1, ${bytes(32, 1)}::bytea)`),
      "42883",
      "rf.set_umk_pub no longer exists",
    );
  },
});

Deno.test({
  name:
    "E-06-66 the immutability guard holds against an UPDATE from ANY role, including the table owner: pub_ed, user_id and key_version never change, a non-null pub_x is never replaced or nulled, and only superseded_at bookkeeping is allowed (04 §6.3 🔒, CLAUDE.md rule 2)",
  ignore,
  async fn() {
    const own = { user_id: fx.owner, key_version: 1 };
    assertStringIncludes(
      await pgMsg(sql`update umk_public_keys set pub_ed = ${bytes(32, 0xaa)}
        where user_id = ${own.user_id} and key_version = ${own.key_version}`),
      "umk_pub_immutable",
      "the ed half verifies every device certificate; replacing it re-roots trust",
    );
    assertStringIncludes(
      await pgMsg(sql`update umk_public_keys set pub_x = ${bytes(32, 0xaa)}
        where user_id = ${own.user_id} and key_version = ${own.key_version}`),
      "umk_pub_immutable",
      "a stored x half is final — this is the substitution 04 §6.3 exists to stop",
    );
    assertStringIncludes(
      await pgMsg(sql`update umk_public_keys set pub_x = null
        where user_id = ${own.user_id} and key_version = ${own.key_version}`),
      "umk_pub_immutable",
      "nor may it be nulled out, which would push a verifier back to comparing one key",
    );
    assertStringIncludes(
      await pgMsg(sql`update umk_public_keys set key_version = 7
        where user_id = ${own.user_id} and key_version = ${own.key_version}`),
      "umk_pub_immutable",
      "a row is identified by (user_id, key_version) for its lifetime",
    );
    assertStringIncludes(
      await pgMsg(sql`update umk_public_keys set user_id = ${fx.member}
        where user_id = ${own.user_id} and key_version = ${own.key_version}`),
      "umk_pub_immutable",
      "a key never changes owner",
    );
    const [still] = await sql`select pub_ed, pub_x from umk_public_keys
      where user_id = ${own.user_id} and key_version = ${own.key_version}`;
    assertEquals(new Uint8Array(still.pub_ed), bytes(32, 0xe1));
    assertEquals(new Uint8Array(still.pub_x), bytes(32, 0x51));

    // Rotation bookkeeping (04 §3.1 key_version) is still possible — the guard is about key bytes.
    await sql`update umk_public_keys set superseded_at = now()
      where user_id = ${own.user_id} and key_version = ${own.key_version}`;
    const [sup] = await sql`select superseded_at from umk_public_keys
      where user_id = ${own.user_id} and key_version = ${own.key_version}`;
    assert(sup.superseded_at !== null, "superseded_at may be stamped");
    await sql`update umk_public_keys set superseded_at = null
      where user_id = ${own.user_id} and key_version = ${own.key_version}`;
  },
});

Deno.test({
  name:
    "E-06-67 ceremony discovery by subject adds no authority: the subject and an active member of the tenant find the newest UNEXPIRED session, another tenant's certified device / a non-member / an uncertified device find nothing, and an expired session is never returned (04 §6.4 delegated, 0007:295's policy unchanged)",
  ignore,
  async fn() {
    // The owner is the subject of a ceremony in t1; `member` is the delegated verifier (04 §6.4).
    // `ago` backdates committed_at, which the guard stamps (0007:107-109), so the trigger comes
    // off for exactly that insert. ceremony_sessions_window (0007:59-60) pins expires_at to
    // committed_at + 10 min, so `ago` past ten minutes IS the expired case and nothing else.
    const mkSession = async (
      fill: number,
      ago: string | null,
      subject: string = fx.owner,
      device: string = fx.dev.owner,
    ) => {
      if (ago) await sql`alter table ceremony_sessions disable trigger ceremony_sessions_guard`;
      const [r] = ago
        ? await sql`insert into ceremony_sessions (tenant_id, subject_user, subject_device,
              commitment, committed_at, expires_at)
            values (${fx.t1}, ${subject}, ${device}, ${bytes(32, fill)},
              now() - ${ago}::interval, now() - ${ago}::interval + interval '10 minutes')
            returning id`
        : await asApi(
          subject,
          device,
          (s) =>
            s`insert into ceremony_sessions (tenant_id, subject_user, subject_device, commitment)
              values (${fx.t1}, ${subject}, ${device}, ${bytes(32, fill)}) returning id`,
        );
      if (ago) await sql`alter table ceremony_sessions enable trigger ceremony_sessions_guard`;
      return r.id as string;
    };
    const expired = await mkSession(0x71, "30 minutes");
    const older = await mkSession(0x72, null);
    const newest = await mkSession(0x73, null);

    const find = (user: string, device: string) =>
      asApi(user, device, (s) => s`select id from rf.live_ceremony_for(${fx.t1}, ${fx.owner})`);

    assertEquals(
      (await find(fx.owner, fx.dev.owner)).map((r) => r.id),
      [newest],
      "the subject finds its own newest live session",
    );
    assertEquals(
      (await find(fx.member, fx.dev.member)).map((r) => r.id),
      [newest],
      "the delegated verifier finds it from the scanned user_id alone (04 §6.1 carries no session id)",
    );
    assert(older !== newest && expired !== newest);

    // ---- the expiry predicate itself (0012:181 `and expires_at > now()`), asserted where it is
    // the ONLY thing that can decide the answer. Above it is not: `order by committed_at desc
    // limit 1` already hides `expired`, because ceremony_sessions_window makes "expired" mean
    // "committed more than ten minutes ago" — so an expired row can never out-sort a live one and
    // can only ever win when there is nothing live behind it. That is this subject: `member` is an
    // active member of t1 (a legal ceremony subject per rf.ceremony_subject_ok) and holds one
    // session, expired. Delete the predicate from rf.live_ceremony_for and this row comes back.
    const staleOnly = await mkSession(0x74, "30 minutes", fx.member, fx.dev.member);
    for (
      const [u, d, why] of [
        [fx.member, fx.dev.member, "the subject itself is told nothing is live"],
        [fx.owner, fx.dev.owner, "and neither is the delegated verifier"],
      ] as const
    ) {
      assertEquals(
        (await asApi(u, d, (s) => s`select id from rf.live_ceremony_for(${fx.t1}, ${fx.member})`))
          .length,
        0,
        `a subject whose ONLY session has expired discovers no session: ${why}`,
      );
    }
    // …and the row is still there and still readable BY ID to this very caller, so what excluded
    // it was the expiry filter and not RLS, a missing row or the subject_user narrowing.
    assertEquals(
      (await asApi(
        fx.owner,
        fx.dev.owner,
        (s) =>
          s`select id, expires_at < now() as stale from ceremony_sessions
                 where id = ${staleOnly}`,
      )).map((r) => [r.id, r.stale]),
      [[staleOnly, true]],
      "the expired row exists, is readable by id, and is genuinely past its window",
    );
    // The mixed case too: asking for it by id through the function returns nothing either.
    assertEquals(
      (await asApi(
        fx.member,
        fx.dev.member,
        (s) => s`select id from rf.live_ceremony_for(${fx.t1}, ${fx.owner}) where id = ${expired}`,
      )).length,
      0,
      "an expired session is never handed to a device that would poll it forever",
    );

    for (
      const [u, d, why] of [
        ["outsider", "outsider", "a certified device of ANOTHER tenant discovers nothing"],
        ["stranger", "stranger", "a non-member discovers nothing"],
        ["owner", "ownerraw", "an UNCERTIFIED device discovers nothing, not even its own user's"],
      ] as const
    ) {
      assertEquals(
        (await find((fx as unknown as Record<string, string>)[u], fx.dev[d])).length,
        0,
        why,
      );
    }
    // The route is SECURITY INVOKER, so it can return nothing the caller could not already have
    // fetched by id — the same policy, the same rows, only the id guess removed.
    assertEquals(
      (await asApi(
        fx.outsider,
        fx.dev.outsider,
        (s) => s`select id from ceremony_sessions where id = ${newest}`,
      )).length,
      0,
      "…and asking by id was already refused, which is what makes discovery no new power",
    );
    await sql.end();
  },
});
