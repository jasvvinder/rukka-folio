// Hostile-query suite for migration 0020: the server half of 04 §7.3 🔒 step 4. It releases the
// re-sealed shares to the phone that asked, and only once the attempt is approved.
//
// 0010 let guardians file a share re-sealed to the attempt's candidate key (`rf.recovery_decide` →
// a `wrapped_keys` row of kind `recovery_blob`). What decides whether that share may LEAVE the
// server is the rule 04 §7.3 step 6 and ADR 2026-09-05d §1 🔒 put on step 4: "if the user still has
// an active certified device, steps 4–6 wait 24 h behind a one-tap Cancel". 06 §10 states the
// acceptance: "nothing decrypts for 24 h". The server is the only party that can enforce that wait,
// because the shares are the only thing the new phone lacks. So every test below is about the
// release being exactly:
//
//   * THIS attempt's shares. They are joined through the attempt's own append-only decisions
//     (0010), never "every recovery_blob addressed to my device". One phone can have several
//     attempts open, and each attempt's shares are addressed to the same device.
//   * addressed to THIS attempt's candidate: the device and the key the attempt was opened with.
//   * released only in the state rf.recovery_derive calls `approved`. That means k approvals, the
//     24 h wait elapsed when the ladder is waiting_24h, not cancelled, and not closed by three
//     denials or by 72 h with fewer than k.
//   * released only to the caller that OPENED it: the (user, device) claim pair that 0005's insert
//     policy bound into the row, on a device that is still live and not suspended, for a user who is
//     not erased. That caller is uncertified by construction (06 §5, ADR 2026-09-05d §2).
//   * released through the function alone. The table itself no longer shows a recovery_blob row to
//     rf_api, so neither the meta pull nor a direct SELECT is a way around the wait.
//   * the same empty answer for every caller and every state that is not a release, so nothing
//     tells a caller that an attempt it does not own exists.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-06-70 … E-06-76 and E-06-80 (the database half; the route half is functions/_tests/recovery_shares.test.ts).
import { assert, assertEquals } from "@std/assert";
import postgres from "postgres";
import { apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — recovery_shares.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP recovery_shares.test.ts: ${why}`);
}
const ignore = !url;

let sql: postgres.Sql;
// Random, not fixed fills: every RLS file shares one database and users.phone_hmac is UNIQUE.
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));
const eq = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((x, i) => x === b[i]);

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
async function pgErr(p: Promise<unknown>): Promise<{ code: string; message: string }> {
  try {
    await p;
    return { code: "ok", message: "" };
  } catch (e) {
    const x = e as { code?: string; message?: string };
    return { code: x.code ?? "unknown", message: x.message ?? "" };
  }
}

const GUARDIANS = ["g1", "g2", "g3", "g4", "g5"] as const;
type G = typeof GUARDIANS[number];

interface Fx {
  t1: string;
  subject: string;
  bystander: string; // certified member of t1, NOT a guardian
  stranger: string; // certified member of another tenant
  g: Record<G, string>;
  dev: Record<string, string>;
}
let fx: Fx;

async function seed(): Promise<Fx> {
  const [t1] = await sql`insert into tenants (type) values ('family') returning id`;
  const [t2] = await sql`insert into tenants (type) values ('family') returning id`;
  const mk = async () => {
    const [u] = await sql`insert into users (phone_hmac, phone_ct)
      values (${rand(32)}, ${rand(40)}) returning id`;
    return u.id as string;
  };
  const subject = await mk(), bystander = await mk(), stranger = await mk();
  const g = {} as Record<G, string>;
  for (const k of GUARDIANS) g[k] = await mk();

  const dev: Record<string, string> = {};
  const devices: [string, string, string][] = [
    ["subjectOld", subject, "certified"], // the device that alarms and can Cancel
    ["candidate", subject, "registered"], // the fresh phone: UNCERTIFIED by construction
    ["candidate2", subject, "registered"], // a second fresh phone of the same user
    ["g1raw", g.g1, "registered"], // a guardian's UNCERTIFIED device
    ["bystander", bystander, "certified"],
    ["stranger", stranger, "certified"],
    ["strangerRaw", stranger, "registered"],
  ];
  for (const k of GUARDIANS) devices.push([k, g[k], "certified"]);
  for (const [name, user, status] of devices) {
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${user}, ${rand(32)}, ${rand(32)}, ${status}) returning id`;
    dev[name] = d.id;
  }

  // The subject founds t1. Everyone else reaches `active` only behind a signed verification event
  // (0008, ADR 2026-09-05d §7), the same fixture recovery.test.ts uses.
  await sql`insert into memberships (tenant_id, user_id, status) values (${t1.id}, ${subject}, 'active')`;
  for (const u of [...Object.values(g), bystander]) {
    const rec = crypto.randomUUID();
    await sql`insert into signed_records
      (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
      values (${rec}, 1, ${t1.id}, 'verification_event', '{}'::jsonb, ${rand(8)},
              ${dev.subjectOld}, ${rand(64)}, 1)`;
    await sql`insert into verification_events
      (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${t1.id}, ${u}, ${subject}, 'qr_in_person', 'verified', ${rec})`;
    await sql`insert into memberships (tenant_id, user_id, status) values (${t1.id}, ${u}, 'active')`;
  }
  await sql`insert into memberships (tenant_id, user_id, status) values (${t2.id}, ${stranger}, 'active')`;
  return { t1: t1.id, subject, bystander, stranger, g, dev };
}

/** 04 §7.3 Setup, the real path: the subject's own certified device publishes set v1. */
async function publishSet(guardians: G[]): Promise<void> {
  const n = guardians.length;
  await asApi(fx.subject, fx.dev.subjectOld, async (s) => {
    await s`insert into guardian_sets (subject_user_id, share_set_version, n, k)
      values (${fx.subject}, 1, ${n}, ${Math.ceil((n + 1) / 2)})`;
    for (const k of guardians) {
      const wk = crypto.randomUUID();
      await s`insert into wrapped_keys (id, kind, user_id, share_set_version, blob)
        values (${wk}, 'guardian_share', ${fx.g[k]}, 1, ${rand(80)})`;
      await s`insert into guardian_set_members
          (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed, wrapped_key_id)
        values (${fx.subject}, 1, ${fx.g[k]}, ${rand(32)}, ${wk})`;
    }
  });
}

/** ADR 2026-09-05d §1: with no active certified device left, the ladder is the immediate one. */
async function loseOldPhone(): Promise<void> {
  await sql`update devices set status = 'revoked', revoked_at = now()
    where user_id = ${fx.subject} and status = 'certified'`;
}

/** 04 §7.3 step 1: the fresh phone asks, for itself, with a candidate key it holds. */
async function open(device: string, pub: Uint8Array): Promise<string> {
  const [r] = await asApi(
    fx.subject,
    fx.dev[device],
    (s) =>
      s`insert into recovery_requests (user_id, candidate_device, candidate_pub_x, expires_at)
      values (${fx.subject}, ${fx.dev[device]}, ${pub}, now()) returning id`,
  );
  return r.id as string;
}

/** 04 §7.3 step 3 through rf.recovery_decide, the only writer. Returns the bytes the guardian sent. */
async function approve(k: G, request: string, pub: Uint8Array): Promise<Uint8Array> {
  const blob = rand(96);
  await asApi(
    fx.g[k],
    fx.dev[k],
    (s) => s`select rf.recovery_decide(${request}, 'approved', ${blob}, ${pub})`,
  );
  return blob;
}
async function deny(k: G, request: string): Promise<void> {
  await asApi(
    fx.g[k],
    fx.dev[k],
    (s) => s`select rf.recovery_decide(${request}, 'denied', null, null)`,
  );
}

interface Share {
  wrapped_key_id: string;
  guardian_user_id: string;
  candidate_device: string;
  sealed_to_pub_x: Uint8Array;
  share_set_version: number;
  blob: Uint8Array;
  approved_at: Date;
}
/** THE READ, as sync-meta makes it: rf_api, the caller's claims, the attempt's id. */
async function shares(user: string | null, device: string | null, request: string) {
  const rows = await asApi(
    user,
    device,
    (s) => s`select * from rf.recovery_shares(${request}::uuid)`,
  );
  return [...rows] as unknown as Share[];
}
async function state(request: string): Promise<string> {
  const [p] = await sql`select state from rf.recovery_derive(${request}::uuid)`;
  return p.state as string;
}
/** How many recovery_blob rows the server actually holds for this attempt. Read as the owner, so
 *  that an empty release is shown to be the gate at work and not a missing row. */
async function held(request: string): Promise<number> {
  const [c] = await sql`select count(*)::int as n from recovery_approvals a
    join wrapped_keys w on w.id = a.wrapped_key_id
    where a.request_id = ${request} and w.kind = 'recovery_blob'`;
  return c.n as number;
}
/** Fixture time travel. The append-only guards stamp created_at themselves, so the trigger is
 *  lifted for the backdate and restored at once (the recovery.test.ts manoeuvre). */
async function pastTheWait(request: string): Promise<void> {
  await sql`alter table recovery_approvals disable trigger recovery_approvals_guard`;
  await sql`update recovery_approvals set created_at = now() - interval '25 hours'
    where request_id = ${request}`;
  await sql`alter table recovery_approvals enable trigger recovery_approvals_guard`;
}
async function past72h(request: string): Promise<void> {
  await sql`alter table recovery_requests disable trigger recovery_requests_guard`;
  await sql`update recovery_requests set created_at = now() - interval '73 hours',
    expires_at = now() - interval '1 hour' where id = ${request}`;
  await sql`alter table recovery_requests enable trigger recovery_requests_guard`;
}

Deno.test({
  name:
    "E-06-70 the release is one SECURITY DEFINER function and nothing else: rf.recovery_shares(uuid) is stable, pins search_path, is EXECUTE-able by rf_api alone, returns exactly the seven share columns, writes nothing and computes nothing; rf_api still holds no UPDATE/DELETE on wrapped_keys, the recovery tables or envelopes; and two RESTRICTIVE policies take recovery_blob rows out of rf_api's reach on the table (04 §7.3 step 4; ADR 2026-09-05d §1; CLAUDE.md rule 2; 04 §8.6)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    try {
      const fns = await sql`select p.oid, p.pronargs, p.prosecdef, p.provolatile, p.proconfig,
          p.prosrc, pg_get_function_identity_arguments(p.oid) as args,
          pg_get_function_result(p.oid) as result
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'rf' and p.proname = 'recovery_shares'`;
      assertEquals(fns.length, 1, "one function, no overload to reach around it");
      const f = fns[0];
      assertEquals(
        f.args,
        "p_request uuid",
        "it takes the attempt and nothing else: no user, no device",
      );
      assertEquals(f.prosecdef, true, "SECURITY DEFINER: the caller holds no row access to read");
      assertEquals(f.provolatile, "s", "stable: a read");
      assert(
        (f.proconfig as string[] | null)?.includes("search_path=public, pg_temp"),
        "search_path pinned (the 0010/0016 pattern)",
      );
      assertEquals(
        f.result,
        "TABLE(wrapped_key_id uuid, guardian_user_id uuid, candidate_device uuid, sealed_to_pub_x bytea, share_set_version integer, blob bytea, approved_at timestamp with time zone)",
        "the shares and their addressing, nothing about the subject's books, keys or tenants",
      );
      const src = f.prosrc as string;
      for (const verb of [/\binsert\b/i, /\bupdate\b/i, /\bdelete\b/i, /\btruncate\b/i]) {
        assert(!verb.test(src), `rf.recovery_shares must not write (${verb})`);
      }
      assert(
        !/(digest|hmac|crypt|encode\(|decrypt|pgp_)/i.test(src),
        "no hash, no encoding, no decryption: bytes in, bytes out (04 §8.6)",
      );

      // EXECUTE: rf_api only. Not PUBLIC (the default for a new function), not maintenance.
      const [acl] = await sql`select
          has_function_privilege('rf_api', 'rf.recovery_shares(uuid)', 'execute') as api,
          has_function_privilege('rf_maintenance', 'rf.recovery_shares(uuid)', 'execute') as maint,
          has_function_privilege('rf_api', 'rf.recovery_derive(uuid)', 'execute') as derive,
          exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.oid = ${f.oid} and a.grantee = 0) as public_exec`;
      assertEquals(acl.api, true, "the route's role may call it");
      assertEquals(acl.maint, false, "nothing the maintenance role does needs a share");
      assertEquals(acl.public_exec, false, "revoked from PUBLIC");
      assertEquals(acl.derive, false, "the unscoped derivation stays owner-only (0010)");

      // CLAUDE.md rule 2 and 0010's decision: nothing here adds an UPDATE or DELETE anywhere.
      const writes = await sql`select table_name, privilege_type
        from information_schema.role_table_grants
        where grantee = 'rf_api' and table_schema = 'public'
          and table_name in ('wrapped_keys','recovery_requests','recovery_approvals',
                             'recovery_cancellations','envelopes')
          and privilege_type in ('UPDATE','DELETE','TRUNCATE')`;
      assertEquals(
        writes.length,
        0,
        "rf_api: no UPDATE/DELETE on wrapped_keys, recovery_*, envelopes",
      );
      const env = await sql`select grantee, privilege_type from information_schema.role_table_grants
        where table_schema = 'public' and table_name = 'envelopes'
          and privilege_type in ('UPDATE','DELETE')
          and grantee in ('rf_api','anon','authenticated','service_role')`;
      assertEquals(env.length, 0, "envelopes stay append-only for every API-facing role");

      // The table-level half: two RESTRICTIVE policies, for rf_api only. A restrictive policy can
      // only narrow what the permissive ones grant, so 0005's own policies stand untouched.
      const pols =
        await sql`select policyname, permissive, cmd, roles::text[] as roles, qual, with_check
        from pg_policies where schemaname = 'public' and tablename = 'wrapped_keys'
          and permissive = 'RESTRICTIVE' order by cmd`;
      assertEquals(pols.length, 2, "one for SELECT, one for INSERT");
      const bycmd = Object.fromEntries(pols.map((p) => [p.cmd, p]));
      assertEquals(bycmd.SELECT.roles, ["rf_api"]);
      assertEquals(bycmd.INSERT.roles, ["rf_api"]);
      assert(/kind\s*<>\s*'recovery_blob'/.test(bycmd.SELECT.qual), bycmd.SELECT.qual);
      assert(/kind\s*<>\s*'recovery_blob'/.test(bycmd.INSERT.with_check), bycmd.INSERT.with_check);
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-06-71 nothing leaves before approval, and exactly the guardians' bytes leave after it: on the immediate ladder the candidate phone reads no share at 0 or at k-1 approvals even though the sealed rows exist, and at k it reads exactly the k re-sealed shares byte-for-byte, each addressed to its own device and candidate key, through rf_api and through PgStore (04 §7.3 steps 3-4; ADR 2026-09-05d §1)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    try {
      fx = await seed();
      await publishSet(["g1", "g2", "g3"]); // 2-of-3
      await loseOldPhone(); // the genuine lost-phone case: no 24 h wait
      const pub = rand(32);
      const req = await open("candidate", pub);
      const [opened] = await sql`select state from recovery_requests where id = ${req}`;
      assertEquals(opened.state, "pending", "the immediate ladder (ADR 2026-09-05d §1)");

      assertEquals(await shares(fx.subject, fx.dev.candidate, req), [], "0 of 2: nothing");
      const b1 = await approve("g1", req, pub);
      assertEquals(await held(req), 1, "the first sealed share IS on the server…");
      assertEquals(
        await shares(fx.subject, fx.dev.candidate, req),
        [],
        "…and it does not leave: 1 of 2 is not approved (04 §7.3 step 4 'at k shares')",
      );
      assertEquals(await state(req), "pending");

      const b2 = await approve("g2", req, pub);
      assertEquals(await state(req), "approved");
      const got = await shares(fx.subject, fx.dev.candidate, req);
      assertEquals(got.length, 2, "exactly the k shares the guardians filed");
      const byG = new Map(got.map((s) => [s.guardian_user_id, s]));
      assert(eq(byG.get(fx.g.g1)!.blob, b1), "g1's share, byte-for-byte: opaque in, opaque out");
      assert(eq(byG.get(fx.g.g2)!.blob, b2), "g2's share, byte-for-byte");
      for (const s of got) {
        assertEquals(s.candidate_device, fx.dev.candidate, "addressed to THIS attempt's device");
        assert(eq(s.sealed_to_pub_x, pub), "declared sealed to THIS attempt's candidate key");
        assertEquals(s.share_set_version, 1, "the set the attempt was pinned to at open");
        assert(s.approved_at instanceof Date);
        const [w] = await sql`select kind, user_id, device_id from wrapped_keys
          where id = ${s.wrapped_key_id}`;
        assertEquals(w.kind, "recovery_blob");
        assertEquals(w.user_id, fx.subject);
        assertEquals(w.device_id, fx.dev.candidate);
      }
      assertEquals(
        got.map((s) => s.guardian_user_id),
        [fx.g.g1, fx.g.g2],
        "in the order they were approved",
      );
      // A third guardian cannot add to a closed attempt (0010 recovery_closed), so the release
      // holds exactly k rows on this ladder.
      const late = await pgErr(approve("g3", req, pub));
      assert(late.message.includes("recovery_closed"), late.message);

      // …and through PgStore, the call sync-meta makes, on the edge's rf_api login.
      const store = await apiStore(url!);
      try {
        const viaStore = await store.withClaims(
          { user_id: fx.subject, device_id: fx.dev.candidate },
          (tx) => tx.recoveryShares(req),
        );
        assertEquals(viaStore.length, 2);
        assert(eq(viaStore.find((s) => s.guardian_user_id === fx.g.g1)!.blob, b1));
        const nobody = await store.withClaims(
          { user_id: fx.stranger, device_id: fx.dev.stranger },
          (tx) => tx.recoveryShares(req),
        );
        assertEquals(nobody, [], "the store seam answers for the claims it carries");
      } finally {
        await store.end();
      }
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-06-72 the 24 h wait holds at the release: while the user still has an active certified device, k approvals put the attempt in waiting_24h and nothing leaves; past the wait it leaves; a one-tap Cancel before or after the wait closes it and nothing leaves again (04 §7.3 step 6; ADR 2026-09-05d §1; 06 §10 'nothing decrypts for 24 h')",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    try {
      fx = await seed();
      await publishSet(["g1", "g2", "g3"]);
      const pub = rand(32);
      const req = await open("candidate", pub); // subjectOld is certified: the waiting ladder
      await approve("g1", req, pub);
      await approve("g2", req, pub);
      assertEquals(await state(req), "waiting_24h");
      assertEquals(await held(req), 2, "k shares are on the server…");
      assertEquals(
        await shares(fx.subject, fx.dev.candidate, req),
        [],
        "…and none of them leaves during the wait",
      );
      // A guardian may still answer during the wait (0010 counts it), and it does not open the gate.
      await approve("g3", req, pub);
      assertEquals(await shares(fx.subject, fx.dev.candidate, req), []);

      await pastTheWait(req);
      assertEquals(await state(req), "approved");
      assertEquals(
        (await shares(fx.subject, fx.dev.candidate, req)).length,
        3,
        "past the wait, every share the guardians filed for this attempt",
      );

      // Cancel AFTER the wait: the next read is refused (the phone that already fetched is past
      // this server's reach, which is why the wait exists at all).
      await asApi(
        fx.subject,
        fx.dev.subjectOld,
        (s) =>
          s`insert into recovery_cancellations (request_id, cancelled_by_user, cancelled_by_device)
          values (${req}, ${fx.subject}, ${fx.dev.subjectOld})`,
      );
      assertEquals(await state(req), "cancelled");
      assertEquals(
        await shares(fx.subject, fx.dev.candidate, req),
        [],
        "a cancel closes the release",
      );

      // Cancel DURING the wait: nothing ever leaves, not even once the 24 h have passed.
      const pub2 = rand(32);
      const req2 = await open("candidate", pub2);
      await approve("g1", req2, pub2);
      await approve("g2", req2, pub2);
      await asApi(
        fx.subject,
        fx.dev.subjectOld,
        (s) =>
          s`insert into recovery_cancellations (request_id, cancelled_by_user, cancelled_by_device)
          values (${req2}, ${fx.subject}, ${fx.dev.subjectOld})`,
      );
      await pastTheWait(req2);
      assertEquals(await state(req2), "cancelled");
      assertEquals(await held(req2), 2);
      assertEquals(await shares(fx.subject, fx.dev.candidate, req2), [], "cancelled for good");
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-06-73 only the caller that opened the attempt reads it: on an approved attempt every other caller reads nothing through the function (another user, a tenant-mate, the guardian who sealed a share, a guardian's uncertified device, the subject's own certified device, the subject's other fresh phone, a claim pair that does not belong together, no claims), and nobody reads or writes a recovery_blob row through the table itself (ADR 2026-09-05d §2; 03 §2.5; ADR 2026-09-24b §3 precedent)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    try {
      fx = await seed();
      await publishSet(["g1", "g2", "g3"]);
      const pub = rand(32);
      const req = await open("candidate", pub); // waiting ladder: subjectOld stays certified
      await approve("g1", req, pub);
      await approve("g2", req, pub);
      await pastTheWait(req);
      assertEquals(await state(req), "approved");
      assertEquals((await shares(fx.subject, fx.dev.candidate, req)).length, 2, "the opener reads");

      const others: [string, string | null, string | null][] = [
        ["another user (a stranger, certified)", fx.stranger, fx.dev.stranger],
        ["another user (uncertified)", fx.stranger, fx.dev.strangerRaw],
        ["a tenant-mate who is not a guardian", fx.bystander, fx.dev.bystander],
        ["the guardian who sealed a share", fx.g.g1, fx.dev.g1],
        ["a guardian who did not answer", fx.g.g3, fx.dev.g3],
        ["a guardian's uncertified device", fx.g.g1, fx.dev.g1raw],
        ["the subject's own CERTIFIED device", fx.subject, fx.dev.subjectOld],
        ["the subject's other fresh phone", fx.subject, fx.dev.candidate2],
        ["the candidate device under another user's claim", fx.stranger, fx.dev.candidate],
        ["the subject's claim on a stranger's device", fx.subject, fx.dev.stranger],
        ["a user claim with no device", fx.subject, null],
        ["no claims at all", null, null],
      ];
      for (const [who, u, d] of others) {
        assertEquals(await shares(u, d, req), [], `${who} reads nothing`);
      }

      // The table: 0020's restrictive policy. Not the opener, not the subject's certified device,
      // not the guardian who sealed it. This is what closes the meta pull (sync-meta pages
      // wrapped_keys under these same policies), which served these rows before the wait was up.
      for (
        const [who, u, d] of [
          ["the opener", fx.subject, fx.dev.candidate],
          ["the subject's certified device", fx.subject, fx.dev.subjectOld],
          ["the sealing guardian", fx.g.g1, fx.dev.g1],
        ] as const
      ) {
        const [c] = await asApi(
          u,
          d,
          (s) => s`select count(*)::int as n from wrapped_keys where kind = 'recovery_blob'`,
        );
        assertEquals(c.n, 0, `${who} reads no recovery_blob row through the table`);
        const [j] = await asApi(
          u,
          d,
          (s) =>
            s`select count(*)::int as n from recovery_approvals a
              join wrapped_keys w on w.id = a.wrapped_key_id where a.request_id = ${req}`,
        );
        assertEquals(j.n, 0, `${who} cannot reach a share by joining through the decision rows`);
      }
      // …while the subject's certified device still reads its OTHER wrapped keys: the policy is
      // narrow, one kind, and 0005's key sync is untouched.
      const umkForDevice = crypto.randomUUID();
      await sql`insert into wrapped_keys (id, kind, user_id, device_id, blob)
        values (${umkForDevice}, 'umk_for_device', ${fx.subject}, ${fx.dev.subjectOld}, ${
        rand(80)
      })`;
      const [own] = await asApi(
        fx.subject,
        fx.dev.subjectOld,
        (s) => s`select count(*)::int as n from wrapped_keys where id = ${umkForDevice}`,
      );
      assertEquals(own.n, 1, "other kinds still sync (05 §5)");

      // Only rf.recovery_decide writes a recovery_blob. A certified device of the user cannot plant
      // one addressed to the candidate, and the candidate cannot plant one for itself.
      for (
        const [who, u, d] of [
          ["the subject's certified device", fx.subject, fx.dev.subjectOld],
          ["the candidate itself", fx.subject, fx.dev.candidate],
        ] as const
      ) {
        const e = await pgErr(asApi(
          u,
          d,
          (s) =>
            s`insert into wrapped_keys (id, kind, user_id, device_id, blob)
              values (gen_random_uuid(), 'recovery_blob', ${fx.subject}, ${fx.dev.candidate}, ${
              rand(96)
            })`,
        ));
        assertEquals(e.code, "42501", `${who} cannot write a recovery_blob row: ${e.message}`);
      }
      assertEquals(await held(req), 2, "and the attempt's release is still exactly its own two");
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-06-74 one attempt's shares, never another's: two attempts on the SAME phone share a device and are still released apart, an unapproved attempt releases nothing even when its sibling is approved, two phones of the same user never read each other's attempt, a sibling attempt that reuses the same candidate key stays out, and a decision row declared sealed to another key is never released (04 §7.3; ADR 2026-09-13c §3; ADR 2026-09-24b §1: one candidate pair per attempt)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    try {
      fx = await seed();
      await publishSet(["g1", "g2", "g3"]);
      await loseOldPhone();
      const pubA = rand(32), pubB = rand(32), pubC = rand(32);
      const reqA = await open("candidate", pubA);
      const reqB = await open("candidate", pubB); // same phone, a fresh attempt and key
      const a1 = await approve("g1", reqA, pubA);
      const a2 = await approve("g2", reqA, pubA);
      const bOnly = await approve("g3", reqB, pubB); // addressed to the SAME device as A's
      assertEquals(await state(reqA), "approved");
      assertEquals(await state(reqB), "pending");

      const gotA = await shares(fx.subject, fx.dev.candidate, reqA);
      assertEquals(gotA.length, 2, "A's two shares…");
      assert(gotA.some((s) => eq(s.blob, a1)) && gotA.some((s) => eq(s.blob, a2)));
      assert(
        !gotA.some((s) => eq(s.blob, bOnly)),
        "…and not B's, though B's is addressed to this phone",
      );
      assert(
        gotA.every((s) => eq(s.sealed_to_pub_x, pubA)),
        "every one declared sealed to A's key",
      );
      assertEquals(
        await shares(fx.subject, fx.dev.candidate, reqB),
        [],
        "B is not approved: its sibling's approval opens nothing for it",
      );

      const reqC = await open("candidate2", pubC);
      await approve("g1", reqC, pubC);
      await approve("g3", reqC, pubC);
      assertEquals(await state(reqC), "approved");
      assertEquals(await shares(fx.subject, fx.dev.candidate, reqC), [], "phone 1 cannot read C");
      assertEquals(await shares(fx.subject, fx.dev.candidate2, reqA), [], "phone 2 cannot read A");
      const gotC = await shares(fx.subject, fx.dev.candidate2, reqC);
      assertEquals(gotC.length, 2);
      assert(
        gotC.every((s) => s.candidate_device === fx.dev.candidate2 && eq(s.sealed_to_pub_x, pubC)),
      );

      // A sibling attempt that REUSES A's candidate key on the same phone. 0010 does not forbid it,
      // and a faulty or hostile client could do it. Its share is addressed to the same device and
      // declared sealed to the same key, so only the attempt join keeps it out of A's release.
      const reqD = await open("candidate", pubA);
      const dOnly = await approve("g3", reqD, pubA);
      assertEquals(await state(reqD), "pending");
      const againA = await shares(fx.subject, fx.dev.candidate, reqA);
      assertEquals(againA.length, 2, "still exactly A's two");
      assert(
        !againA.some((s) => eq(s.blob, dOnly)),
        "a same-key sibling's share never rides along",
      );
      assertEquals(await shares(fx.subject, fx.dev.candidate, reqD), [], "D is not approved");

      // A mis-filed decision row on A: a recovery_blob for the right device, attached to A, but
      // declared sealed to some OTHER key. rf.recovery_decide refuses to write one
      // (candidate_key_mismatch), so it is planted as the owner to show that the release's own key
      // join refuses it as well.
      const planted = crypto.randomUUID(), plantedBlob = rand(96);
      await sql`insert into wrapped_keys (id, kind, user_id, device_id, blob)
        values (${planted}, 'recovery_blob', ${fx.subject}, ${fx.dev.candidate}, ${plantedBlob})`;
      await sql`insert into recovery_approvals (request_id, guardian_user_id, guardian_device,
          share_set_version, decision, wrapped_key_id, sealed_to_pub_x)
        values (${reqA}, ${fx.g.g3}, ${fx.dev.g3}, 1, 'approved', ${planted}, ${rand(32)})`;
      const withPlant = await shares(fx.subject, fx.dev.candidate, reqA);
      assertEquals(withPlant.length, 2, "a row declared for another key is not released");
      assert(!withPlant.some((s) => eq(s.blob, plantedBlob)));
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-06-75 a closed attempt releases nothing: 72 h with fewer than k approvals and three denials both close it with sealed shares on the server, and none leaves; an attempt that REACHED approval is still released after its 72 h guardian window (the 0010 reading, pinned here so a ruling flips one assertion) (04 §7.3 step 7; 0010 ⚠️ SPEC)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    try {
      fx = await seed();
      await publishSet(["g1", "g2", "g3", "g4", "g5"]); // 3-of-5
      await loseOldPhone();

      // 72 h with fewer than k: expired.
      const pubX = rand(32);
      const reqX = await open("candidate", pubX);
      await approve("g1", reqX, pubX);
      await approve("g2", reqX, pubX);
      await past72h(reqX);
      assertEquals(await state(reqX), "expired");
      assertEquals(await held(reqX), 2);
      assertEquals(await shares(fx.subject, fx.dev.candidate, reqX), [], "expired: nothing leaves");
      const late = await pgErr(approve("g3", reqX, pubX));
      assert(late.message.includes("recovery_closed"), "and it cannot be pushed to k afterwards");

      // Three denials: closed (0010 surfaces it as expired; 03 §2.2 has no 'denied').
      const pubD = rand(32);
      const reqD = await open("candidate", pubD);
      await approve("g1", reqD, pubD);
      await approve("g2", reqD, pubD);
      await deny("g3", reqD);
      await deny("g4", reqD);
      await deny("g5", reqD);
      assertEquals(await state(reqD), "expired");
      assertEquals(await held(reqD), 2);
      assertEquals(await shares(fx.subject, fx.dev.candidate, reqD), [], "denied: nothing leaves");

      // ⚠️ SPEC (0020): 04 §7.3 sets no deadline for FETCHING an approved attempt's shares. 0010
      // reads 72 h as the guardians' window to respond; once k approvals exist the attempt is
      // approved for as long as the rows exist (retention, 03 §6). The release follows that
      // derivation rather than inventing a second timer.
      const pubA = rand(32);
      const reqA = await open("candidate", pubA);
      for (const g of ["g1", "g2", "g3"] as const) await approve(g, reqA, pubA);
      await past72h(reqA);
      assertEquals(await state(reqA), "approved");
      assertEquals((await shares(fx.subject, fx.dev.candidate, reqA)).length, 3);
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-06-76 the opener must still be live: a revoked candidate device, a suspended one and an erased user read nothing from an approved attempt, and a share row whose wrapped key was revoked is not released (ADR 2026-09-05d §2-§3; 06 §9.3; the rf.has_guardian_set liveness precedent, 0016)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    try {
      fx = await seed();
      await publishSet(["g1", "g2", "g3"]);
      await loseOldPhone();
      const pub = rand(32);
      const req = await open("candidate", pub);
      await approve("g1", req, pub);
      await approve("g2", req, pub);
      assertEquals((await shares(fx.subject, fx.dev.candidate, req)).length, 2, "live: released");

      // A share whose wrapped key was revoked (0005 rf.project_device_status stamps revoked_at).
      const [first] = await sql`select wrapped_key_id from recovery_approvals
        where request_id = ${req} and guardian_user_id = ${fx.g.g1}`;
      await sql`update wrapped_keys set revoked_at = now() where id = ${first.wrapped_key_id}`;
      const after = await shares(fx.subject, fx.dev.candidate, req);
      assertEquals(after.map((s) => s.guardian_user_id), [fx.g.g2], "a revoked row is not served");
      await sql`update wrapped_keys set revoked_at = null where id = ${first.wrapped_key_id}`;

      // ⚠️ SPEC (0020): suspended is withheld too (ADR 2026-09-05d §3: a device someone asked to
      // be revoked, pending its 24 h window). 0016 answers a suspended device; a share is not a bit.
      await sql`update devices set status = 'suspended' where id = ${fx.dev.candidate}`;
      assertEquals(await shares(fx.subject, fx.dev.candidate, req), [], "suspended: nothing");
      await sql`update devices set status = 'registered' where id = ${fx.dev.candidate}`;
      assertEquals(
        (await shares(fx.subject, fx.dev.candidate, req)).length,
        2,
        "restored: released",
      );

      await sql`update devices set status = 'revoked', revoked_at = now()
        where id = ${fx.dev.candidate}`;
      assertEquals(await shares(fx.subject, fx.dev.candidate, req), [], "revoked: nothing");
      await sql`update devices set status = 'registered', revoked_at = null
        where id = ${fx.dev.candidate}`;
      // revoked_at alone is enough (the rf.device_live_for predicate)
      await sql`update devices set revoked_at = now() where id = ${fx.dev.candidate}`;
      assertEquals(await shares(fx.subject, fx.dev.candidate, req), [], "revoked_at set: nothing");
      await sql`update devices set revoked_at = null where id = ${fx.dev.candidate}`;

      await sql`update users set erased_at = now() where id = ${fx.subject}`;
      assertEquals(await shares(fx.subject, fx.dev.candidate, req), [], "erased user: nothing");
    } finally {
      await sql.end();
    }
  },
});

Deno.test({
  name:
    "E-06-80 the 24 h wait is asked again when the shares leave, not only when the attempt opened: an attempt opened while the user had no certified device waits 24 h from the k-th approval once the user has one again, nothing leaves in that time, and the newly certified device can Cancel it; with no certified device the same shape releases at k (ADR 2026-09-05d §1; 04 §7.3 step 6; 0020 section 4 and ⚠️ SPEC (c))",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    try {
      fx = await seed();
      await publishSet(["g1", "g2", "g3"]); // 2 of 3
      await loseOldPhone(); // no certified device left: the immediate ladder
      const derived = async (request: string) => {
        const [p] = await sql`select opened_state, state, kth_approval_at, wait_until
          from rf.recovery_derive(${request}::uuid)`;
        return p;
      };

      // ---- the control. No certified device, k approvals, released at once (nobody to alarm).
      const pubC = rand(32);
      const control = await open("candidate", pubC);
      await approve("g1", control, pubC);
      await approve("g2", control, pubC);
      assertEquals((await derived(control)).opened_state, "pending");
      assertEquals(await state(control), "approved");
      assertEquals((await shares(fx.subject, fx.dev.candidate, control)).length, 2);

      // ---- the attack. A opens on a borrowed phone while the owner has no certified device…
      const pub = rand(32);
      const req = await open("candidate", pub);
      assertEquals(
        (await derived(req)).opened_state,
        "pending",
        "A opened on the immediate ladder",
      );
      // …the owner is certified again on another phone (rung 3, or a sibling attempt)…
      await sql`update devices set status = 'certified' where id = ${fx.dev.candidate2}`;
      assertEquals(
        await state(req),
        "waiting_24h",
        "the ladder a client acts on follows the device",
      );
      // …and two colluding guardians approve A.
      await approve("g1", req, pub);
      await approve("g2", req, pub);
      const p = await derived(req);
      assertEquals(p.opened_state, "pending", "the row's own ladder is untouched (0010)");
      assertEquals(p.state, "waiting_24h");
      assertEquals(
        (p.wait_until as Date).getTime() - (p.kth_approval_at as Date).getTime(),
        24 * 3600e3,
        "24 h from the k-th approval",
      );
      assertEquals(await held(req), 2, "k shares are on the server…");
      assertEquals(
        await shares(fx.subject, fx.dev.candidate, req),
        [],
        "…and none leaves behind the newly certified device's back",
      );

      // ---- ⚠️ SPEC (c): the control reached k seconds ago, so its kth + 24 h has not run either,
      //      and it is withheld from now on. The newly certified device holds the one-tap Cancel.
      assertEquals(await state(control), "waiting_24h");
      assertEquals(await shares(fx.subject, fx.dev.candidate, control), []);
      await asApi(
        fx.subject,
        fx.dev.candidate2,
        (s) =>
          s`insert into recovery_cancellations (request_id, cancelled_by_user, cancelled_by_device)
          values (${control}, ${fx.subject}, ${fx.dev.candidate2})`,
      );
      await pastTheWait(control);
      assertEquals(await state(control), "cancelled");
      assertEquals(await shares(fx.subject, fx.dev.candidate, control), [], "cancelled for good");

      // ---- past the wait, uncancelled, A leaves: the gate was the wait and nothing else.
      await pastTheWait(req);
      assertEquals(await state(req), "approved");
      assertEquals((await shares(fx.subject, fx.dev.candidate, req)).length, 2);
    } finally {
      await sql.end();
    }
  },
});
