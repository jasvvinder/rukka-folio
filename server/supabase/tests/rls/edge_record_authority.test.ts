// Desk 83 on the REAL store (🔴 SECURITY, owner said go 3 Oct 2026): the edge's record authority,
// run over PgStore on the rf_api login (tests/rls/_pg_api.ts) — the store the edge holds, under
// 0005's row policies and 0022's checks. Ids E-06-91 … E-06-95, the same scenarios as
// functions/_tests/edge_record_authority.test.ts on MemStore (record_authority_world.ts), so the two
// stores are held to one set of answers.
//
// What this arm adds to MemStore's: on PgStore the edge reads only what rf_api is shown, which is
// where the bug lived — `applyRecord` took "no member yet" from a count of the memberships the
// CALLER could see, zero for a stranger, and answered `acked` to a cross-tenant join (E-06-86).
// Every refusal here must be a NAMED one (`rejected:unauthorized` with check rls / not_admin /
// not_revoker, or `rejected:unknown_book`), never `acked`, and must carry the edge's fingerprint
// (no insert asked for; or stored, noted and answered with its seq, no projection asked for) — the
// database would refuse each of them too (E-06-82 … E-06-89), so only the fingerprint shows the
// edge decided from the database's answer rather than leaning on it.
//
// Fixtures are written by the schema owner without claims (users, devices, tenants, memberships,
// books, roles, one envelope, guardian sets — what a hostile caller could not write); every request
// runs as rf_api. Synthetic bytes only: no ledger content, no phone number (CLAUDE.md rule 4).
//
// Needs RF_TEST_DB_URL (`eval "$(scripts/rls_db.sh)"`); without it every test is SKIPPED and says
// why, and RLS_REQUIRE=1 makes that a failure.
import postgres from "postgres";
import type { PgStore } from "../../functions/_shared/store_pg.ts";
import { edKeypair, type Member, reissue, rig } from "../../functions/_tests/harness.ts";
import {
  authorsFirstRecord,
  bookRoles,
  concurrentK,
  differentTenants,
  filedElsewhere,
  founder,
  intake,
  inviteReadmission,
  lateApplication,
  type MemberStatus,
  pendingGuardian,
  publishTenant,
  refusedRemoval,
  revocations,
  spy,
  storeHolds,
  subjectRemoved,
  type Tn,
  usedBook,
  type World,
} from "../../functions/_tests/record_authority_world.ts";
import { apiStore } from "./_pg_api.ts";

const url = Deno.env.get("RF_TEST_DB_URL");
const required = Deno.env.get("RLS_REQUIRE") === "1";
if (!url) {
  const why =
    "RF_TEST_DB_URL not set — edge_record_authority.test.ts needs a Postgres with the migrations applied (scripts/rls_db.sh)";
  if (required) throw new Error(`RLS_REQUIRE=1 but ${why}`);
  console.log(`SKIP edge_record_authority.test.ts: ${why}`);
}
const ignore = !url;
const rand = (n: number) => crypto.getRandomValues(new Uint8Array(n));

/** A seat- and book-unlimited family plan, so no cap ever stands in for the refusal under test;
 *  removed after every test. */
const PLAN = "zz_edge83_many";

function pgWorld(sql: postgres.Sql, store: PgStore): World {
  const r = rig();
  const calls: string[] = [];
  r.deps.store = spy(store, calls);
  const deviceOf = async (user: string): Promise<Member> => {
    const keys = await edKeypair();
    const [d] = await sql`insert into devices (id, user_id, pub_ed, pub_x, status)
      values (gen_random_uuid(), ${user}, ${keys.pub}, ${rand(32)}, 'certified') returning id`;
    const m = {
      user,
      device: { id: d.id as string },
      keys,
      xpub: rand(32),
      claims: { user_id: user, device_id: d.id as string },
      token: "",
    } as unknown as Member;
    await reissue(r, m);
    return m;
  };
  const person = async (): Promise<Member> => {
    const [u] = await sql`insert into users (phone_hmac, phone_ct) values (${rand(32)}, ${rand(40)})
      returning id`;
    return await deviceOf(u.id as string);
  };
  const tenantRow = async (): Promise<string> => {
    const [row] = await sql`insert into tenants (type) values ('family') returning id`;
    await sql`insert into subscriptions (tenant_id, plan) values (${row.id}, ${PLAN})`;
    return row.id as string;
  };
  const book = async (t: string, type: string, owner: string | null = null) => {
    const id = crypto.randomUUID();
    await sql`insert into books (id, tenant_id, type, owner_user_id)
      values (${id}, ${t}, ${type}, ${owner})`;
    return id;
  };
  const ceremony = async (tn: Tn, p: Member, result: "verified" | "mismatch") => {
    const rec = crypto.randomUUID();
    await sql`insert into signed_records
      (id, suite_version, tenant_id, kind, payload_json, payload_bytes, author_device, author_sig, hlc)
      values (${rec}, 1, ${tn.t}, 'verification_event', '{}'::jsonb, ${rand(8)},
              ${tn.founder.device.id}, ${rand(64)}, 1)`;
    await sql`insert into verification_events
      (tenant_id, subject_user, verifier_user, method, result, source_record_id)
      values (${tn.t}, ${p.user}, ${tn.founder.user}, 'qr_in_person', ${result}, ${rec})`;
  };
  return {
    r,
    store,
    calls,
    async tenant(): Promise<Tn> {
      const t = await tenantRow();
      const founder = await person();
      // The founding member: the one `active` 0006's guard grants without a ceremony.
      await sql`insert into memberships (tenant_id, user_id, status)
        values (${t}, ${founder.user}, 'active')`;
      const personal = await book(t, "personal", founder.user);
      const business = await book(t, "business");
      await sql`insert into book_roles (book_id, user_id, role)
        values (${personal}, ${founder.user}, 'admin'), (${business}, ${founder.user}, 'admin')`;
      return { t, founder, personal, business };
    },
    emptyTenant: tenantRow,
    person,
    device: (m) => deviceOf(m.user),
    async member(tn: Tn, status: MemberStatus, who?: Member) {
      const p = who ?? await person();
      // 0006/0008: `active` only after a verified ceremony and `blocked` only after a mismatch,
      // each a verification event on a signed record of the verifier's.
      if (status === "active") await ceremony(tn, p, "verified");
      if (status === "blocked") await ceremony(tn, p, "mismatch");
      const first = status === "blocked" ? "joined_pending_verification" : status;
      await sql`insert into memberships (tenant_id, user_id, status)
        values (${tn.t}, ${p.user}, ${first})`;
      if (status === "blocked") {
        await sql`update memberships set status = 'blocked'
          where tenant_id = ${tn.t} and user_id = ${p.user}`;
      }
      return p;
    },
    async setStatus(t, user, status) {
      await sql`update memberships set status = ${status} where tenant_id = ${t} and user_id = ${user}`;
    },
    book: (t, type, owner) => book(t, type, type === "personal" ? owner! : null),
    async role(b, user, role) {
      await sql`insert into book_roles (book_id, user_id, role) values (${b}, ${user}, ${role})`;
    },
    async envelope(tn, b) {
      const blob = rand(8);
      await sql`insert into envelopes (envelope_id, tenant_id, book_id, object_id, object_type,
          key_version, suite_version, payload_schema, author_device, hlc, blob_hash, size, blob)
        values (gen_random_uuid(), ${tn.t}, ${b}, gen_random_uuid(), 'entry', 1, 1, 1,
                ${tn.founder.device.id}, 1, ${rand(32)}, ${blob.length}, ${blob})`;
    },
    async usage(t, b, count) {
      await sql`insert into book_usage (book_id, tenant_id, envelope_count, bytes)
        values (${b}, ${t}, ${count}, 0)
        on conflict (book_id) do update set envelope_count = excluded.envelope_count`;
    },
    async guardians(subject, version, k, gs, tenant) {
      // A set with a tenant goes through 0010/0026's guards like any insert. A set WITHOUT one is
      // a row published before 0026, which the guard now refuses to write: it is seeded with
      // triggers off for this one transaction (session_replication_role, superuser), as it was.
      await sql.begin(async (s) => {
        if (tenant === null) await s`set local session_replication_role = replica`;
        await s`insert into guardian_sets (subject_user_id, share_set_version, n, k, tenant_id)
          values (${subject}, ${version}, ${gs.length}, ${k}, ${tenant})`;
        for (const g of gs) {
          await s`insert into guardian_set_members
              (subject_user_id, share_set_version, guardian_user_id, umk_pub_ed)
            values (${subject}, ${version}, ${g.user}, ${g.keys.pub})`;
        }
      });
    },
    async statusOf(t, user) {
      const [m] =
        await sql`select status from memberships where tenant_id = ${t} and user_id = ${user}`;
      return (m?.status as string) ?? null;
    },
    async phoneOf(user) {
      const [u] = await sql`select phone_hmac from users where id = ${user}`;
      return new Uint8Array(u.phone_hmac as Uint8Array);
    },
    async rolesOf(b) {
      const rows = await sql`select user_id, role from book_roles where book_id = ${b}`;
      return rows.map((x) => `${x.user_id}:${x.role}`).sort();
    },
    async deviceStatus(d) {
      const [x] = await sql`select status from devices where id = ${d}`;
      return x.status as string;
    },
    async stored(id) {
      const [x] = await sql`select applied_at, apply_note from signed_records where id = ${id}`;
      return x ? { applied: x.applied_at !== null, note: (x.apply_note as string) ?? null } : null;
    },
    async recordsIn(t) {
      const [x] = await sql`select count(*)::int as n from signed_records where tenant_id = ${t}`;
      return x.n as number;
    },
  };
}

/** `pending`: the scenario states 🔒 behaviour the server does not meet yet (an owner item) — it is
 *  registered IGNORED, never green, until the change it waits on lands. */
function test(name: string, scenario: (w: World) => Promise<void>, pending = false) {
  Deno.test({
    name,
    ignore: ignore || pending,
    async fn() {
      const sql = postgres(url!, { max: 2, onnotice: () => {} });
      let store: PgStore | null = null;
      try {
        await sql`insert into plan_catalogue (id, entity_type, name, sort_order, members,
            business_books, devices, envelopes_per_book, tenant_bytes, attachment_bytes, features,
            price_yearly_paise, price_monthly_paise)
          values (${PLAN}, 'family', 'Edge83 many', 97, -1, -1, 5, 1000, 1000000, 1000, '{}', 0, 0)
          on conflict (id) do nothing`;
        store = await apiStore(url!);
        await scenario(pgWorld(sql, store));
      } finally {
        await store?.end();
        await sql`update subscriptions set plan = 'free' where plan = ${PLAN}`;
        await sql`delete from plan_catalogue where id = ${PLAN}`;
        await sql.end();
      }
    },
  });
}

test(
  "E-06-91 [PgStore rf_api] intake: the edge asks rf.may_file_record before it stores anything — tenant A's admin filing membership_status / device_added / book_role / member_removal / device_revocation / invite into B, B's removed and blocked members, an unknown tenant and a memberless tenant offered anything but the founder's membership_status each answer rejected:unauthorized check rls — never acked — with no insert asked of the store and no row in B; a pending member's device_added and an admin's designation are acked; a stored record re-sent after its author's removal is answered as stored",
  intake,
);
test(
  "E-06-92 [PgStore rf_api] the founder is the database's answer (rf.may_file_record over every membership row), never a count of the memberships rf_api can see: a memberless tenant's founder takes its own membership at active; founding it for someone else, or at joined_pending_verification / removed / invited, and a non-admin's membership_status or member_removal, are refused by the edge (not_admin, stored, noted, seq, no projection asked for); rf.may_file_record is asked again at apply, so a founding record stored while the tenant was empty and replayed after another founded it is refused not_admin by the edge (a stored record's replay skips intake, desk 68(a))",
  founder,
);
test(
  "E-06-93 [PgStore rf_api] a book role needs an admin OF THAT BOOK, decided from rf.book_access: another book's admin, a member and a pending member are refused not_admin by the edge; a role-less book's first role is only the caller's own admin role, on a book that never held an envelope, a personal book's only its owner's; a book of another tenant answers rejected:unknown_book like one that does not exist; the book's admin grants and revokes",
  bookRoles,
);
test(
  "E-06-94 [PgStore rf_api] a device is revoked by its user or that user's guardians inside a tenant the user is in: a non-guardian and a completing guardian on a record of a tenant the subject is not in are refused not_revoker by the edge (never acked, no projection asked for); k guardians in the set's tenant (the subject's) revoke it; an owner revokes its own other device",
  revocations,
);
test(
  "E-06-95 [PgStore rf_api] the store's own answers match MemStore's: rf.may_file_record's table, a stranger's insert rls, a non-admin's membership not_admin, another book's admin's book role not_admin, a certifying device record revoke_only, a fellow member's revocation not_revoker",
  storeHolds,
);

// Desk 89 — ADR 2026-10-03b (0026) on the real store: the count is rf.revocation_count's, over every
// row, so it holds where signed_records_select shows the caller only its own tenants' approvals.
test(
  "E-03b-1 [PgStore rf_api] an approval filed outside the guardian set's tenant never counts: g1's approval in A (a tenant the subject is in; the set was set up in B) is refused not_revoker; g2's in B is \"counted 1 of 2\" and rf.revocation_count agrees; rf.project_device_status refuses g1's A record and one counted approval alike (not_revoker); g1's approval in B completes the revocation",
  filedElsewhere,
);
test(
  "E-03b-2 [PgStore rf_api] guardians who file in different tenants do not complete (replaces the ignored E-06-94 disjoint-guardians case): set up in A, g1 files in A (counted 1 of 2), g2 — gone from A — files in B and is refused not_revoker; the device stays certified; a pre-0026 set with no tenant counts nothing",
  differentTenants,
);
test(
  "E-03b-3 [PgStore rf_api] a guardian at joined_pending_verification in the set's tenant — who cannot see the subject's membership row — revokes through rf.guardian_may_revoke and rf.project_device_status's definer count, and reads the count; a stranger and a removed guardian are refused at intake, a pending non-guardian and another subject's guardian not_revoker, and none of them reads the count",
  pendingGuardian,
);
test(
  'E-03b-6 [PgStore rf_api] two guardians filing the approvals that reach k at the same moment revoke the device: both requests are held at rf.revocation_count until both have filed in their own open transaction; 0026\'s per-device advisory lock makes the second counter wait for the first\'s commit and count both in a fresh snapshot, so one reads "counted 1 of 2" and the other projects "revoked by guardians 2 of 2" at the later seq — never two "1 of 2" and a device left certified',
  concurrentK,
);
test(
  "E-03b-7 [PgStore rf_api] the subject's membership in the set's tenant is judged at each approval's own seq (ADR 2026-10-03b §6, 0027 rf.subject_held_at over membership_facts): two of a k = 3 set's approvals filed while the subject is there count 2 of 3 and KEEP counting after its admin removes the subject (the memberships trigger logs the removal when it is applied); g3's approval filed while the subject is removed — a newcomer having joined since — is refused not_revoker by the edge (rf.guardian_may_revoke) and never counts — not after the re-admission either, and rf.project_device_status refuses it; a removal in another tenant, and the newcomer's removal in this one, change nothing (the history is the subject's); g3 files again after the re-admission and completes k at that approval's seq",
  subjectRemoved,
);
test(
  "E-03b-11 [PgStore rf_api] a membership change is a fact when it is applied, never at its record's seq (desk 97 review, finding 1; 0027 memberships_facts_log at a fresh store_seq): a re-admission stored unapplied and applied on its re-send (sync-meta's duplicate arm) counts neither approval refused not_revoker while the subject was removed — the count stays empty and the device certified; a removal stored unapplied and applied on its re-send, and the admin's own older designation record applied through rf.project_membership as a removal, never un-count the approval filed before them; the guardians then complete k",
  lateApplication,
);
test(
  "E-03b-12 [PgStore rf_api] 06 §7's own re-admission is a membership fact (desk 97 review, finding 2; 0027's trigger logs rf.accept_invite and rf.project_verification_event): a subject removed by record and re-admitted through rf.create_invite → rf.accept_invite (joined_pending_verification) → the ceremony's verification_event (active) is held again — g2's approval filed after the acceptance counts, and g1's after the ceremony completes k; g1's approval filed while the subject was removed never counts",
  inviteReadmission,
);
test(
  "E-03b-9 [PgStore rf_api] a membership record the server refused is not a membership fact (0027 §1 — rf_api writes signed_records and its apply_note itself, so only a write of the memberships row counts): a non-admin member's member_removal of the subject and the subject's own device's membership_status removed are refused not_admin and stored, the subject stays active, and the guardians' approvals filed after them count and revoke the device",
  refusedRemoval,
);
test(
  "E-03b-8 [PgStore rf_api] rf.revocation_tally applies the k the subject's own devices apply — one counted record per author (its lowest seq), k of the earliest version among those: g1 names v2 (k = 3), g1's stale device re-files naming v1 (k = 2) and is not counted again, g2 makes 2 of 3 — no revocation; g3 completes it",
  authorsFirstRecord,
);
test(
  "E-03b-4 [PgStore rf_api] a book whose book_usage.envelope_count is 1 with no envelope row is not bootstrapped: refused not_admin by the edge (rf.book_access) and by rf.project_book_role itself, which read `envelopes` before 0026; a book that never held one is claimed",
  usedBook,
);
test(
  "E-03b-5 [PgStore rf_api] POST /sync-meta/recovery/guardians requires tenant_id; rf.guardian_set_guard refuses a publisher not active there (guardian_set_tenant, one answer for pending, absent and unknown tenants) and rf.guardian_set_member_guard a guardian removed there (guardian_not_in_tenant, the whole publish rolled back); a pending guardian may be chosen; the tenant is written once with the version, relayed on GET /sync-meta, and a re-split may name another",
  publishTenant,
);
