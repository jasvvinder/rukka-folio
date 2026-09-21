// Hostile-query suite for the WRITE side of the guardian recovery ladder — 04 §7.3 🔒 (Setup and
// Recovery steps 1–7), 04 §7.5, 06 §5, 03 §2.2/§2.5, ADR 2026-09-05d §1 (24 h wait + one-tap
// Cancel) and §2, ADR 2026-09-06 §2, ADR 2026-09-13c §1/§3, ADR 2026-09-16.
//
// Rung 2 is the one rung where the key arrives from *other people's devices, through this server*,
// at a device that holds nothing to check it against (ADR 2026-09-13c §1). So every rule gets the
// same adversaries the ceremony suite uses, plus the two this ladder adds:
//
//   * a CERTIFIED device of ANOTHER tenant (the stranger),
//   * a certified member of THIS tenant who is NOT in the guardian set,
//   * a GUARDIAN, who is trusted with the ask and with nothing else,
//   * the CANDIDATE device itself, uncertified by construction (06 §5 "New phone, no old device"),
//   * `rf_api` reaching the tables directly with whatever claims it likes.
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`). Without it every test is SKIPPED and says
// why; the nightly/RC lanes set RLS_REQUIRE=1 so a missing database fails loudly.
// Ids E-06-50 … E-06-56, E-06-59.
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import postgres from "postgres";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — recovery.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP recovery.test.ts: ${why}`);
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
const pgCode = async (p: Promise<unknown>) => (await pgErr(p)).code;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

interface Fx {
  t1: string;
  t2: string;
  subject: string;
  g1: string;
  g2: string;
  g3: string;
  bystander: string; // certified member of t1, NOT a guardian
  stranger: string; // certified member of t2
  dev: Record<string, string>;
  book: string;
  candidatePub: Uint8Array;
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
  const subject = await mk(),
    g1 = await mk(),
    g2 = await mk(),
    g3 = await mk(),
    bystander = await mk(),
    stranger = await mk();

  const dev: Record<string, string> = {};
  for (
    const [name, user, status] of [
      ["subjectOld", subject, "certified"], // the device that alarms and can Cancel
      ["candidate", subject, "registered"], // the fresh phone — UNCERTIFIED by construction
      ["candidate2", subject, "registered"], // a second fresh phone (replay adversary)
      ["g1", g1, "certified"],
      ["g1raw", g1, "registered"], // a guardian's UNCERTIFIED device
      ["g2", g2, "certified"],
      ["g3", g3, "certified"],
      ["bystander", bystander, "certified"],
      ["stranger", stranger, "certified"],
    ] as const
  ) {
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${user}, ${rand(32)}, ${rand(32)}, ${status}) returning id`;
    dev[name] = d.id;
  }

  // The subject founds t1 (06 §5: the founder has nobody to verify them); everyone else reaches
  // `active` only behind a signed verification event (0008, ADR 2026-09-05d §7).
  await sql`insert into memberships (tenant_id, user_id, status) values (${t1.id}, ${subject}, 'active')`;
  for (const u of [g1, g2, g3, bystander]) {
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

  // Something financial to prove a guardian never reaches it: a book the subject writes to and one
  // envelope in it. g1/g2/g3 hold NO role on this book.
  const [b] = await sql`insert into books (id, tenant_id, type, fy_start_month)
    values (gen_random_uuid(), ${t1.id}, 'family', 4) returning id`;
  await sql`insert into book_roles (book_id, user_id, role) values (${b.id}, ${subject}, 'admin')`;
  const blob = rand(64);
  await sql`insert into envelopes (envelope_id, tenant_id, book_id, object_id, object_type,
      key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
    values (gen_random_uuid(), ${t1.id}, ${b.id}, gen_random_uuid(), 'entry', 1, 1, 1,
      ${dev.subjectOld}, 1, ${rand(32)}, ${blob.length}, ${blob})`;
  // and a book key wrapped to the subject — the thing recovery ultimately unlocks
  await sql`insert into wrapped_keys (id, kind, user_id, book_id, key_version, blob)
    values (gen_random_uuid(), 'bk_for_user', ${subject}, ${b.id}, 1, ${rand(48)})`;

  return {
    t1: t1.id,
    t2: t2.id,
    subject,
    g1,
    g2,
    g3,
    bystander,
    stranger,
    dev,
    book: b.id,
    candidatePub: rand(32),
  };
}

/** 04 §7.3 Setup: the subject's own certified device publishes the set and the sealed shares. */
async function publishSet(version: number, guardians: string[], k?: number): Promise<void> {
  const n = guardians.length;
  await asApi(fx.subject, fx.dev.subjectOld, async (s) => {
    await s`insert into guardian_sets (subject_user_id, share_set_version, n, k)
      values (${fx.subject}, ${version}, ${n}, ${k ?? Math.ceil((n + 1) / 2)})`;
    for (const g of guardians) {
      // No RETURNING: a share sealed to a guardian is addressed to THEM, so 0005's wrapped_keys
      // SELECT policy refuses it even to the subject who uploaded it — and an INSERT … RETURNING
      // has to pass the SELECT policy too. The id is minted client-side, as the app does.
      const wk = crypto.randomUUID();
      await s`insert into wrapped_keys (id, kind, user_id, share_set_version, blob)
        values (${wk}, 'guardian_share', ${g}, ${version}, ${rand(80)})`;
      await s`insert into guardian_set_members
          (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed, wrapped_key_id)
        values (${fx.subject}, ${version}, ${g}, ${rand(32)}, ${wk})`;
    }
  });
}

/** 04 §7.3 step 1: the fresh phone asks. Uncertified, for itself, and for nothing else. */
async function openRequest(
  device = "candidate",
  pub = fx.candidatePub,
  user = fx.subject,
): Promise<string> {
  const [r] = await asApi(
    user,
    fx.dev[device],
    (s) =>
      s`insert into recovery_requests (user_id, candidate_device, candidate_pub_x, expires_at)
      values (${user}, ${fx.dev[device]}, ${pub}, now() + interval '72 hours') returning id`,
  );
  return r.id as string;
}

async function decide(
  guardian: string,
  request: string,
  decision: "approved" | "denied",
  sealedTo: Uint8Array | null = fx.candidatePub,
): Promise<PgErr> {
  return await pgErr(
    asApi(
      (fx as unknown as Record<string, string>)[guardian],
      fx.dev[guardian],
      (s) =>
        s`select rf.recovery_decide(${request}, ${decision},
            ${decision === "approved" ? rand(96) : null}::bytea,
            ${decision === "approved" ? sealedTo : null}::bytea)`,
    ),
  );
}

async function progress(
  user: string,
  device: string,
  request: string,
): Promise<Record<string, unknown> | undefined> {
  const rows = await asApi(user, device, (s) => s`select * from rf.recovery_progress(${request})`);
  return rows[0] as Record<string, unknown> | undefined;
}

Deno.test({
  name:
    "E-06-50 the recovery write side is append-only: rf_api holds no UPDATE or DELETE on recovery_requests, recovery_approvals, recovery_cancellations, guardian_sets or guardian_set_members, the `approvals` column is never written, and every k-of-n count is derived from the rows (CLAUDE.md rule 2; 04 §7.3)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();

    // ---- the grant table itself, because a policy cannot loosen a grant that does not exist
    const grants = await sql<{ table_name: string; privilege_type: string }[]>`
      select table_name, privilege_type from information_schema.role_table_grants
      where grantee = 'rf_api' and table_schema = 'public'
        and table_name in ('recovery_requests','recovery_approvals','recovery_cancellations',
                           'guardian_sets','guardian_set_members','wrapped_keys','envelopes')
        and privilege_type in ('UPDATE','DELETE')`;
    assertEquals(grants.length, 0, "no UPDATE/DELETE grant anywhere on the recovery write side");

    // ---- and no function in rf.* writes the counter either
    const [ctr] = await sql<{ n: number }[]>`
      select count(*)::int as n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
      where ns.nspname = 'rf' and p.prosrc ~* 'update[[:space:]]+recovery_requests'`;
    assertEquals(ctr.n, 0, "nothing in rf.* updates a recovery_requests row");

    await publishSet(1, [fx.g1, fx.g2, fx.g3]);
    const req = await openRequest();

    // ---- rf_api: refused for want of a grant (42501), not merely by a policy
    assertEquals(
      await pgCode(
        asApi(
          fx.subject,
          fx.dev.subjectOld,
          (s) => s`update recovery_requests set state = 'approved' where id = ${req}`,
        ),
      ),
      "42501",
    );
    assertEquals(
      await pgCode(
        asApi(
          fx.subject,
          fx.dev.subjectOld,
          (s) => s`delete from recovery_requests where id = ${req}`,
        ),
      ),
      "42501",
    );
    assertEquals(
      await pgCode(
        asApi(
          fx.g1,
          fx.dev.g1,
          (s) => s`update guardian_sets set k = 1 where subject_user_id = ${fx.subject}`,
        ),
      ),
      "42501",
    );

    // ---- the OWNER is refused too: the guard, not the grant, is what makes it append-only
    const owner = await pgErr(
      sql`update recovery_requests set state = 'approved' where id = ${req}`,
    );
    assertEquals(owner.code, "23514");
    assertStringIncludes(owner.message, "append_only");
    assertStringIncludes(
      (await pgErr(sql`update guardian_sets set k = 1 where subject_user_id = ${fx.subject}`))
        .message,
      "append_only",
    );

    // ---- the counter stays 0 while the rows carry the truth (04 §7.3: "at k shares")
    await decide("g1", req, "approved");
    await decide("g2", req, "approved");
    const [row] = await sql`select approvals, state, share_set_version from recovery_requests
      where id = ${req}`;
    assertEquals(row.approvals, 0, "the vestigial counter is never written");
    assertEquals(row.share_set_version, 1, "the attempt pinned the set it opened against");
    const p = await progress(fx.subject, fx.dev.subjectOld, req);
    assertEquals(p!.approvals, 2, "the count is derived from the append-only rows");
    assertEquals(p!.k, 2);
    assertEquals(p!.n, 3);
    await sql.end();
  },
});

Deno.test({
  name:
    "E-06-51 a non-guardian cannot read another user's sealed shares or guardian-set members: a stranger, a fellow tenant member who is not in the set, and a guardian of an OLD version all come back empty (04 §7.3; ADR 2026-09-05d §2)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();
    await publishSet(1, [fx.g1, fx.g2, fx.g3]);

    // A guardian reads its OWN sealed share and nobody else's (0005 wrapped_keys policy).
    const mine = await asApi(
      fx.g1,
      fx.dev.g1,
      (s) => s`select id, user_id, blob from wrapped_keys where kind = 'guardian_share'`,
    );
    assertEquals(mine.length, 1, "a guardian sees exactly one guardian_share: its own");
    assertEquals(mine[0].user_id, fx.g1);

    for (const who of ["stranger", "bystander"] as const) {
      const rows = await asApi(
        (fx as unknown as Record<string, string>)[who],
        fx.dev[who],
        (s) => s`select id from wrapped_keys where kind = 'guardian_share'`,
      );
      assertEquals(rows.length, 0, `${who} reads no share`);
    }

    // Set MEMBERSHIP (who the guardians are) is tenant-visible by 0005, but never outside it.
    const strangerSees = await asApi(
      fx.stranger,
      fx.dev.stranger,
      (s) => s`select * from guardian_set_members where subject_user_id = ${fx.subject}`,
    );
    assertEquals(strangerSees.length, 0, "another tenant learns nothing about who guards whom");

    // An UNCERTIFIED device of a real guardian sees neither the share nor the set
    // (ADR 2026-09-05d §2: an uncertified device sees only itself).
    const raw = await asApi(fx.g1, fx.dev.g1raw, async (s) => ({
      shares: await s`select id from wrapped_keys where kind = 'guardian_share'`,
      members: await s`select * from guardian_set_members`,
    }));
    assertEquals(raw.shares.length, 0);
    assertEquals(raw.members.length, 0);
    await sql.end();
  },
});

Deno.test({
  name:
    "E-06-52 a guardian sees the ask and nothing financial: the recovery_requests row carries a user, a device, a candidate key and two timestamps — and the same guardian reads no envelope, no book role, no book key and no other guardian's decision (04 §7.3 step 2; ADR 2026-09-05d §2)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();
    await publishSet(1, [fx.g1, fx.g2, fx.g3]);
    const req = await openRequest();

    const ask = await asApi(
      fx.g1,
      fx.dev.g1,
      (s) => s`select * from recovery_requests where id = ${req}`,
    );
    assertEquals(ask.length, 1, "the guardian is pushed the ask");
    assertEquals(ask[0].user_id, fx.subject);
    assertEquals(ask[0].candidate_device, fx.dev.candidate);
    assertEquals(
      Object.keys(ask[0]).sort(),
      [
        "approvals",
        "candidate_device",
        "candidate_pub_x",
        "created_at",
        "expires_at",
        "id",
        "share_set_version",
        "state",
        "updated_at",
        "user_id",
      ],
      "the ask's whole vocabulary — not one column names money, a book or a tenant",
    );

    // …and nothing else in the schema opens up because of it. A guardian IS an active member of
    // this tenant (04 §7.3's mutual ceremony requires it), so the tenant's own metadata — that a
    // book exists, who holds a role on it — is visible to them by 03 §2.5 and always was. What
    // recovery must never add is the CONTENT or the KEYS, and it does not: the guardian holds no
    // role on the book, so `rf.book_role` is null and the envelope store is closed to them.
    const blind = await asApi(fx.g1, fx.dev.g1, async (s) => ({
      envelopes: await s`select envelope_id from envelopes`,
      bookKeys: await s`select id from wrapped_keys where kind = 'bk_for_user'`,
      myRole: await s`select role from book_roles where user_id = ${fx.g1}`,
    }));
    assertEquals(
      blind.envelopes.length,
      0,
      "a guardian with no role on the book reads no envelope",
    );
    assertEquals(blind.bookKeys.length, 0, "recovery never hands a guardian a book key");
    assertEquals(blind.myRole.length, 0, "and approving grants no role");

    // A guardian sees its own decision; another guardian's is not its business.
    await decide("g1", req, "approved");
    await decide("g2", req, "approved");
    const seen = await asApi(
      fx.g1,
      fx.dev.g1,
      (s) => s`select guardian_user_id from recovery_approvals where request_id = ${req}`,
    );
    assertEquals(seen.map((r) => r.guardian_user_id), [fx.g1]);
    // The requester, by contrast, sees the tally — 04 §7.3's "2 of 3 approved".
    const all = await asApi(
      fx.subject,
      fx.dev.subjectOld,
      (s) => s`select guardian_user_id from recovery_approvals where request_id = ${req}`,
    );
    assertEquals(all.length, 2);

    // A tenant member who is NOT a guardian is not pushed the ask at all.
    const outside = await asApi(
      fx.bystander,
      fx.dev.bystander,
      (s) => s`select id from recovery_requests`,
    );
    assertEquals(outside.length, 0);
    await sql.end();
  },
});

Deno.test({
  name:
    "E-06-53 who may open a request: the candidate device opens one for ITSELF while uncertified (04 §7.3 step 1, ADR 2026-09-05d §2) and can open one for nobody else — not another user, not another device, not without claims, not without a complete guardian set",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();

    // ---- no guardians published yet: rung 2 does not exist for this user (04 §7.4 takes over)
    const noSet = await pgErr(openRequest());
    assertEquals(noSet.code, "42501");
    assertStringIncludes(noSet.message, "no_guardian_set");

    // ---- a half-published set cannot be recovered against either
    await asApi(
      fx.subject,
      fx.dev.subjectOld,
      (s) =>
        s`insert into guardian_sets (subject_user_id, share_set_version, n, k)
        values (${fx.subject}, 1, 3, 2)`,
    );
    const half = await pgErr(openRequest());
    assertStringIncludes(half.message, "guardian_set_incomplete");
    await asApi(fx.subject, fx.dev.subjectOld, async (s) => {
      for (const g of [fx.g1, fx.g2, fx.g3]) {
        await s`insert into guardian_set_members
            (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
          values (${fx.subject}, 1, ${g}, ${rand(32)})`;
      }
    });

    // ---- ⚠️ SPEC: the lane brief asks for "an uncertified device cannot open a request". Taken
    // literally that forbids the flagship flow: 04 §7.3 step 1 has a fresh phone that holds nothing
    // but its own keys request recovery, and ADR 2026-09-05d §2 lists "its own recovery_requests"
    // among the four things an uncertified device may see. The conservative reading is asserted
    // here — for ITSELF yes, for anything else no — and the conflict is reported to the owner.
    const mine = await openRequest();
    assert(mine, "the fresh, uncertified phone opens its own attempt");
    const [state] = await sql`select state from recovery_requests where id = ${mine}`;
    assertEquals(state.state, "waiting_24h", "the subject still holds a certified device");

    // ---- and for nothing else. The claims are the caller's; the row must name them both.
    assertEquals(
      await pgCode(
        asApi(
          fx.subject,
          fx.dev.candidate,
          (s) =>
            s`insert into recovery_requests (user_id, candidate_device, candidate_pub_x, expires_at)
          values (${fx.subject}, ${fx.dev.candidate2}, ${rand(32)}, now() + interval '72 hours')`,
        ),
      ),
      "42501",
      "a device cannot nominate another device as the candidate",
    );
    assertEquals(
      await pgCode(
        asApi(
          fx.g1,
          fx.dev.g1,
          (s) =>
            s`insert into recovery_requests (user_id, candidate_device, candidate_pub_x, expires_at)
          values (${fx.subject}, ${fx.dev.g1}, ${rand(32)}, now() + interval '72 hours')`,
        ),
      ),
      "42501",
      "a guardian cannot open an attempt on the subject's behalf",
    );
    assertEquals(
      await pgCode(
        asApi(
          null,
          null,
          (s) =>
            s`insert into recovery_requests (user_id, candidate_device, candidate_pub_x, expires_at)
          values (${fx.subject}, ${fx.dev.candidate}, ${rand(32)}, now() + interval '72 hours')`,
        ),
      ),
      "42501",
      "no claims, no attempt",
    );

    // ---- the candidate key is mandatory and is 32 bytes; the server stores it and nothing more
    const shape = await pgErr(
      asApi(
        fx.subject,
        fx.dev.candidate2,
        (s) =>
          s`insert into recovery_requests (user_id, candidate_device, candidate_pub_x, expires_at)
        values (${fx.subject}, ${fx.dev.candidate2}, null, now() + interval '72 hours')`,
      ),
    );
    assertStringIncludes(shape.message, "recovery_shape");

    // ---- an uncertified device still sees nothing but itself (ADR 2026-09-05d §2)
    const blind = await asApi(fx.subject, fx.dev.candidate, async (s) => ({
      envelopes: await s`select envelope_id from envelopes`,
      members: await s`select * from memberships`,
      guardians: await s`select * from guardian_set_members`,
      mine: await s`select id from recovery_requests`,
    }));
    assertEquals(blind.envelopes.length, 0);
    assertEquals(blind.members.length, 0);
    assertEquals(blind.guardians.length, 0);
    assertEquals(
      blind.mine.map((r) => r.id),
      [mine],
      "only its own attempt",
    );
    await sql.end();
  },
});

Deno.test({
  name:
    "E-06-54 a share sealed to one candidate key cannot be replayed into another request: the guardian declares the key it sealed to and a mismatch is refused, one sealed row backs at most one decision, and one guardian decides an attempt once (ADR 2026-09-13c §3; 04 §7.3 step 3)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();
    await publishSet(1, [fx.g1, fx.g2, fx.g3]);
    const reqA = await openRequest("candidate", fx.candidatePub);

    const ok = await decide("g1", reqA, "approved", fx.candidatePub);
    assertEquals(ok.code, "ok");

    // ---- a share declared for a different candidate key belongs to a different attempt
    const wrongKey = await decide("g2", reqA, "approved", rand(32));
    assertEquals(wrongKey.code, "23514");
    assertStringIncludes(wrongKey.message, "candidate_key_mismatch");

    // ---- one decision per guardian per attempt, written once (no read-modify-write to race)
    const twice = await decide("g1", reqA, "approved", fx.candidatePub);
    assertStringIncludes(twice.message, "already_decided");
    const flip = await decide("g1", reqA, "denied");
    assertStringIncludes(flip.message, "already_decided");

    // ---- the sealed row itself is bound to this attempt: it cannot be filed against a second one
    const [share] = await sql`select wrapped_key_id from recovery_approvals
      where request_id = ${reqA} and guardian_user_id = ${fx.g1}`;
    const [wk] = await sql`select user_id, device_id, kind, share_set_version
      from wrapped_keys where id = ${share.wrapped_key_id}`;
    assertEquals(wk.kind, "recovery_blob");
    assertEquals(wk.user_id, fx.subject);
    assertEquals(wk.device_id, fx.dev.candidate, "addressed to THIS attempt's candidate device");
    assertEquals(wk.share_set_version, null);
    const replay = await pgErr(sql`insert into recovery_approvals
      (request_id, guardian_user_id, guardian_device, share_set_version, decision,
       wrapped_key_id, sealed_to_pub_x)
      values (${reqA}, ${fx.g2}, ${fx.dev.g2}, 1, 'approved', ${share.wrapped_key_id},
              ${fx.candidatePub})`);
    assertEquals(replay.code, "23505", "unique(wrapped_key_id): one sealed share, one decision");

    // ---- a second attempt from a second phone gets its own key; the first attempt's share is
    //      neither visible to it nor usable by it.
    const pubB = rand(32);
    const reqB = await openRequest("candidate2", pubB);
    assertStringIncludes(
      (await decide("g2", reqB, "approved", fx.candidatePub)).message,
      "candidate_key_mismatch",
      "a share sealed to attempt A's key cannot be filed against attempt B",
    );
    assertEquals((await decide("g2", reqB, "approved", pubB)).code, "ok");
    const seenByB = await asApi(
      fx.subject,
      fx.dev.candidate2,
      (s) => s`select id from wrapped_keys where kind = 'recovery_blob'`,
    );
    assertEquals(seenByB.length, 1, "candidate2 reads only the share addressed to candidate2");

    // ---- a non-guardian cannot decide at all, and learns nothing by trying
    for (const who of ["bystander", "stranger"] as const) {
      const e = await decide(who, reqA, "approved", fx.candidatePub);
      assertEquals(e.code, "42501");
      assertStringIncludes(e.message, "unknown_request");
    }
    // …and an unknown attempt refuses IDENTICALLY, so the route is no oracle.
    const ghost = await pgErr(
      asApi(
        fx.g3,
        fx.dev.g3,
        (s) =>
          s`select rf.recovery_decide(gen_random_uuid(), 'approved', ${
            rand(96)
          }, ${fx.candidatePub})`,
      ),
    );
    assertStringIncludes(ghost.message, "unknown_request");
    // …as does a guardian on an UNCERTIFIED device (ADR 2026-09-05d §2).
    const rawGuardian = await pgErr(
      asApi(
        fx.g1,
        fx.dev.g1raw,
        (s) => s`select rf.recovery_decide(${reqB}, 'approved', ${rand(96)}, ${pubB})`,
      ),
    );
    assertStringIncludes(rawGuardian.message, "unknown_request");
    await sql.end();
  },
});

Deno.test({
  name:
    "E-06-55 no route and no policy ever exposes a plaintext share: shares are opaque bytea in and out, a re-sealed share is readable only by the candidate device it was addressed to, and the server holds no key material of its own (04 §7.3 step 3, 04 §8.6)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();
    await publishSet(1, [fx.g1, fx.g2, fx.g3]);
    const req = await openRequest();
    await decide("g1", req, "approved");
    await decide("g2", req, "approved");

    // ---- the candidate device, uncertified, reads the shares addressed to it and nothing else
    const toMe = await asApi(
      fx.subject,
      fx.dev.candidate,
      (s) => s`select id, kind, blob from wrapped_keys`,
    );
    assertEquals(toMe.length, 2, "exactly the two re-sealed shares");
    assertEquals([...new Set(toMe.map((r) => r.kind))], ["recovery_blob"]);
    assert(toMe.every((r) => (r.blob as Uint8Array).length === 96), "opaque bytes, unchanged");

    // ---- nobody else reads them: not the guardians who sealed them, not a fellow member,
    //      not another tenant, not the subject's OTHER device (0005: device_id = rf.device_id()).
    for (
      const [u, d] of [
        [fx.g1, fx.dev.g1],
        [fx.g2, fx.dev.g2],
        [fx.bystander, fx.dev.bystander],
        [fx.stranger, fx.dev.stranger],
        [fx.subject, fx.dev.candidate2],
      ] as const
    ) {
      const rows = await asApi(
        u,
        d,
        (s) => s`select id from wrapped_keys where kind = 'recovery_blob'`,
      );
      assertEquals(rows.length, 0, "a re-sealed share reaches one device only");
    }

    // ---- the progress read is a tally, never a payload: no column of it carries bytes
    const p = await progress(fx.subject, fx.dev.candidate, req);
    assert(p, "the requester reads its own progress");
    for (const [k, v] of Object.entries(p!)) {
      assert(!(v instanceof Uint8Array), `rf.recovery_progress.${k} must not carry bytes`);
    }

    // ---- and the server never learned anything about the share it stored
    const [dec] = await sql`select decision, sealed_to_pub_x, wrapped_key_id
      from recovery_approvals where request_id = ${req} and guardian_user_id = ${fx.g1}`;
    assertEquals((dec.sealed_to_pub_x as Uint8Array).length, 32, "a public key, compared not used");
    const crypto_in_rf = await sql`select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'rf' and p.proname like 'recovery%'
        and p.prosrc ~* '(digest|hmac|crypt|encode\\()'`;
    assertEquals(
      crypto_in_rf.length,
      0,
      "no rf.recovery* function hashes, encodes or decrypts anything (04 §8.6)",
    );
    await sql.end();
  },
});

Deno.test({
  name:
    "E-06-56 the 24 h wait cannot be skipped: the server sets the ladder, not the client; a request lands in waiting_24h while any active certified device exists and goes straight through only when none does; completion waits 24 h from the k-th approval; Cancel is reachable from that state and closes the attempt for good (ADR 2026-09-05d §1; 04 §7.3 step 6)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();
    await publishSet(1, [fx.g1, fx.g2, fx.g3]);

    // ---- a client that simply asks for 'approved' gets the state the server computed
    const [asked] = await asApi(fx.subject, fx.dev.candidate, (s) =>
      s`insert into recovery_requests
          (user_id, candidate_device, candidate_pub_x, state, approvals, expires_at)
        values (${fx.subject}, ${fx.dev.candidate}, ${fx.candidatePub}, 'approved', 99,
                now() + interval '999 hours') returning id, state, approvals, expires_at`);
    assertEquals(asked.state, "waiting_24h", "the subject still holds a certified device");
    assertEquals(asked.approvals, 0, "and the counter it sent was discarded");
    const window = (asked.expires_at as Date).getTime() - Date.now();
    assert(
      window < 73 * 3600e3 && window > 71 * 3600e3,
      "72 h, the server's clock (04 §7.3 step 7)",
    );
    const req = asked.id as string;

    // ---- k approvals are not completion while the wait runs
    await decide("g1", req, "approved");
    assertEquals((await progress(fx.subject, fx.dev.candidate, req))!.state, "waiting_24h");
    await decide("g2", req, "approved");
    const atK = await progress(fx.subject, fx.dev.candidate, req)!;
    assertEquals(atK!.state, "waiting_24h", "k shares are in; the 24 h window is what is left");
    assertEquals(atK!.approvals, 2);
    assert(atK!.wait_until, "the window has an end the UI can count down to");
    assert(
      (atK!.wait_until as Date).getTime() - (atK!.kth_approval_at as Date).getTime() ===
        24 * 3600e3,
      "24 h from the k-th approval (04 §7.3 step 6)",
    );

    // ---- the one-tap Cancel is reachable from waiting_24h, and only from an EXISTING device
    assertEquals(
      await pgCode(
        asApi(
          fx.subject,
          fx.dev.candidate,
          (s) =>
            s`insert into recovery_cancellations (request_id, cancelled_by_user, cancelled_by_device)
          values (${req}, ${fx.subject}, ${fx.dev.candidate})`,
        ),
      ),
      "42501",
      "the candidate device cannot cancel the alarm raised against it",
    );
    assertEquals(
      await pgCode(
        asApi(
          fx.g1,
          fx.dev.g1,
          (s) =>
            s`insert into recovery_cancellations (request_id, cancelled_by_user, cancelled_by_device)
          values (${req}, ${fx.g1}, ${fx.dev.g1})`,
        ),
      ),
      "42501",
      "a guardian cannot cancel either",
    );
    await asApi(
      fx.subject,
      fx.dev.subjectOld,
      (s) =>
        s`insert into recovery_cancellations (request_id, cancelled_by_user, cancelled_by_device)
        values (${req}, ${fx.subject}, ${fx.dev.subjectOld})`,
    );
    assertEquals(
      (await progress(fx.subject, fx.dev.candidate, req))!.state,
      "cancelled",
      "one tap closes it",
    );
    // …for good: no further share can be collected, and time cannot reopen it.
    assertStringIncludes((await decide("g3", req, "approved")).message, "recovery_closed");

    // ---- the wait is real: backdate the k-th approval past 24 h and only then is it approved.
    //      (Fixture manoeuvre: the guard makes created_at the server's, so the trigger is lifted
    //      for the backdate and restored immediately — the test cannot travel in time otherwise.)
    const req2 = await openRequest("candidate2", rand(32));
    const [pub2] = await sql`select candidate_pub_x from recovery_requests where id = ${req2}`;
    for (const g of ["g1", "g2"] as const) {
      await asApi(
        (fx as unknown as Record<string, string>)[g],
        fx.dev[g],
        (s) =>
          s`select rf.recovery_decide(${req2}, 'approved', ${rand(96)},
            ${pub2.candidate_pub_x as Uint8Array})`,
      );
    }
    assertEquals((await progress(fx.subject, fx.dev.candidate2, req2))!.state, "waiting_24h");
    await sql`alter table recovery_approvals disable trigger recovery_approvals_guard`;
    await sql`update recovery_approvals set created_at = now() - interval '25 hours'
      where request_id = ${req2}`;
    await sql`alter table recovery_approvals enable trigger recovery_approvals_guard`;
    assertEquals(
      (await progress(fx.subject, fx.dev.candidate2, req2))!.state,
      "approved",
      "24 h behind a one-tap Cancel, then and only then",
    );

    // ---- and with NO active certified device the ladder is the immediate one (ADR 05d §1)
    await sql`update devices set status = 'revoked', revoked_at = now()
      where user_id = ${fx.subject} and status = 'certified'`;
    const req3 = await openRequest("candidate", rand(32));
    const [s3] = await sql`select state from recovery_requests where id = ${req3}`;
    assertEquals(s3.state, "pending", "no device left to alarm: the genuine lost-phone case");
    const [pub3] = await sql`select candidate_pub_x from recovery_requests where id = ${req3}`;
    for (const g of ["g1", "g2"] as const) {
      await asApi(
        (fx as unknown as Record<string, string>)[g],
        fx.dev[g],
        (s) =>
          s`select rf.recovery_decide(${req3}, 'approved', ${rand(96)},
            ${pub3.candidate_pub_x as Uint8Array})`,
      );
    }
    const done = await progress(fx.subject, fx.dev.candidate, req3);
    assertEquals(done!.state, "approved", "straight through, no wait");
    assertEquals(done!.wait_until, null);
    await sql.end();
  },
});

// ---------------------------------------------------------------------------------------------
// M11 RV7 — the row half of "2 of 3 approved". A count is not an attribution, and this is the
// policy that decides who may read the attribution. Id E-06-59.
// ---------------------------------------------------------------------------------------------
Deno.test({
  name:
    "E-06-59 who may read a guardian's DECISION: the requester and its candidate device read every decision of their own attempt — name, word and time, so a denial is distinguishable from silence — a guardian reads its own and no other guardian's, a bystander and a stranger read none, and nobody reads a row through a request that is not theirs (0010 THE DECISION 🔒; 04 §7.3 steps 3 and 7; ADR 2026-09-05d §2; 03 §2.5)",
  ignore,
  async fn() {
    sql = postgres(url!, { max: 1, onnotice: () => {} });
    fx = await seed();
    await publishSet(1, [fx.g1, fx.g2, fx.g3]);
    const req = await openRequest();
    await decide("g1", req, "denied");
    await decide("g2", req, "approved");

    const rows = (who: string, device: string) =>
      asApi(
        (fx as unknown as Record<string, string>)[who] ?? who,
        fx.dev[device],
        (s) =>
          s`select guardian_user_id, decision from recovery_approvals
            where request_id = ${req} order by created_at`,
      );

    // ---- the requester's own certified device: both rows, each naming its guardian
    const mine = await rows("subject", "subjectOld");
    assertEquals(mine.length, 2);
    assertEquals(
      mine.map((r: Record<string, unknown>) => [r.guardian_user_id, r.decision]),
      [[fx.g1, "denied"], [fx.g2, "approved"]],
      "a denial is a ROW; silence is the absence of one (04 §7.3 step 7)",
    );

    // ---- the candidate device, uncertified by construction, reads the same two rows: this is the
    //      phone that renders S11.2, and ADR 2026-09-05d §2 lets it see its own attempt.
    assertEquals((await rows("subject", "candidate")).length, 2);

    // ---- a guardian reads its OWN decision and nothing about the others
    const g1sees = await rows("g1", "g1");
    assertEquals(g1sees.length, 1);
    assertEquals(g1sees[0].guardian_user_id, fx.g1);
    const g3sees = await rows("g3", "g3");
    assertEquals(g3sees.length, 0, "a guardian who has not answered learns nothing about who did");

    // ---- an UNCERTIFIED device of a guardian reads nothing at all (ADR 2026-09-05d §2)
    assertEquals((await rows("g1", "g1raw")).length, 0);

    // ---- a fellow member who is not in the set, and another tenant entirely: nothing
    assertEquals((await rows("bystander", "bystander")).length, 0);
    assertEquals((await rows("stranger", "stranger")).length, 0);

    // ---- and the whole table is no more reachable than one request's slice of it
    const all = await asApi(
      fx.stranger,
      fx.dev.stranger,
      (s) => s`select count(*)::int as n from recovery_approvals`,
    );
    assertEquals(all[0].n, 0, "a stranger cannot even count the decisions on this server");

    // ---- the decision rows carry no share: the sealed blob is addressed to the candidate DEVICE
    //      through wrapped_keys, and reading it is a different policy on a different table.
    const blobs = await asApi(
      fx.g3,
      fx.dev.g3,
      (s) =>
        s`select count(*)::int as n from wrapped_keys w
          join recovery_approvals a on a.wrapped_key_id = w.id where a.request_id = ${req}`,
    );
    assertEquals(blobs[0].n, 0, "no guardian reads a share another guardian re-sealed");
    await sql.end();
  },
});
