// Static schema assertions over the migrations — parsed with libpg-query, NO database needed, so the
// push lane can run them. 03 §2.3/§2.5 🔒, ADR 2026-09-05b §1/§5/§8, 05c §4/§7, 05d §2.
// Ids E-03-15 … E-03-21, E-05c-8 (static half).
import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { parse } from "libpg-query";

const HERE = new URL(".", import.meta.url);
const MIGRATIONS = new URL("../../migrations/", HERE);
const CONFIG = new URL("../../config.toml", HERE);

interface Policy {
  name: string;
  table: string;
  cmd: string;
  roles: string[];
  source: string;
}
interface Grant {
  is_grant: boolean;
  tables: string[];
  privileges: string[]; // [] = ALL
  columns: string[];
  grantees: string[];
  objtype: string;
}
interface Fn {
  name: string;
  body: string;
}
interface Column {
  table: string;
  name: string;
  type: string;
}

const files = [...Deno.readDirSync(MIGRATIONS)].map((e) => e.name).filter((n) => n.endsWith(".sql"))
  .sort();
const tables = new Set<string>();
const columns: Column[] = [];
const policies: Policy[] = [];
const grants: Grant[] = [];
const fns: Fn[] = [];
const doBodies: string[] = [];
const alters: { table: string; subtypes: string[] }[] = [];
const triggers: { table: string; fn: string; events: string[]; timing: number }[] = [];
let allSql = "";

const str = (n: any): string => n?.String?.sval ?? "";
const names = (arr: any[] | undefined): string => (arr ?? []).map(str).join(".");
function fnBody(opts: any[]): string {
  const as = (opts ?? []).find((o) => o.DefElem?.defname === "as")?.DefElem?.arg;
  if (!as) return "";
  if (as.String) return as.String.sval;
  if (as.List) return as.List.items.map(str).join("\n");
  return "";
}
for (const f of files) {
  const sql = await Deno.readTextFile(new URL(f, MIGRATIONS));
  allSql += `\n-- ${f}\n${sql}`;
  const res = await parse(sql);
  for (const s of res.stmts) {
    const src = sql.slice(
      s.stmt_location ?? 0,
      (s.stmt_location ?? 0) + (s.stmt_len ?? sql.length),
    );
    const st: any = s.stmt;
    if (st.CreateStmt) {
      const t = st.CreateStmt.relation.relname;
      tables.add(t);
      for (const el of st.CreateStmt.tableElts ?? []) {
        if (el.ColumnDef) {
          columns.push({
            table: t,
            name: el.ColumnDef.colname,
            type: names(el.ColumnDef.typeName?.names),
          });
        }
      }
    } else if (st.CreatePolicyStmt) {
      const p = st.CreatePolicyStmt;
      policies.push({
        name: p.policy_name,
        table: p.table.relname,
        cmd: p.cmd_name ?? "all",
        roles: (p.roles ?? []).map((r: any) => r.RoleSpec.rolename),
        source: src,
      });
    } else if (st.GrantStmt) {
      const g = st.GrantStmt;
      grants.push({
        is_grant: !!g.is_grant,
        objtype: g.objtype,
        tables: (g.objects ?? []).map((o: any) =>
          o.RangeVar?.relname ?? o.ObjectWithArgs?.objname?.map(str).join(".") ?? ""
        ).filter(Boolean),
        privileges: (g.privileges ?? []).map((p: any) => p.AccessPriv.priv_name),
        columns: (g.privileges ?? []).flatMap((p: any) => (p.AccessPriv.cols ?? []).map(str)),
        grantees: (g.grantees ?? []).map((r: any) => r.RoleSpec.rolename ?? r.RoleSpec.roletype),
      });
    } else if (st.CreateFunctionStmt) {
      fns.push({
        name: names(st.CreateFunctionStmt.funcname),
        body: fnBody(st.CreateFunctionStmt.options),
      });
    } else if (st.DoStmt) {
      doBodies.push(fnBody(st.DoStmt.args));
    } else if (st.AlterTableStmt) {
      alters.push({
        table: st.AlterTableStmt.relation.relname,
        subtypes: (st.AlterTableStmt.cmds ?? []).map((c: any) => c.AlterTableCmd.subtype),
      });
    } else if (st.CreateTrigStmt) {
      const t = st.CreateTrigStmt;
      triggers.push({
        table: t.relation.relname,
        fn: names(t.funcname),
        events: [],
        timing: t.timing,
      });
    }
  }
}
const fn = (name: string) => fns.find((f) => f.name === name)?.body ?? "";
const policiesOn = (t: string) => policies.filter((p) => p.table === t);
const grantsOn = (t: string, who: string) =>
  grants.filter((g) => g.is_grant && g.tables.includes(t) && g.grantees.includes(who));
const privsOf = (t: string, who: string) =>
  new Set(grantsOn(t, who).flatMap((g) => g.privileges.length ? g.privileges : ["ALL"]));

// Tables that deliberately have NO rf_api/rf_maintenance path (console/M13 or function-only access).
const NO_ACCESS = new Set(["billing_events", "promo_codes", "promo_redemptions", "push_rate"]);
// Tables whose rows are tenant data: every policy must be certified-gated (ADR 05d §2).
const TENANT_TABLES = [
  "tenants",
  "memberships",
  "books",
  "book_roles",
  "device_certs",
  "wrapped_keys",
  "guardian_sets",
  "guardian_set_members",
  "invites",
  "verification_events",
  "escrow_policies",
  "envelopes",
  "signed_records",
  "attachments",
  "book_usage",
  "subscriptions",
  "entitlement_tokens",
  "tenant_freezes",
  "umk_public_keys",
];
const CERT_HELPERS = [
  "rf.is_certified",
  "rf.active_in_tenant",
  "rf.is_tenant_admin",
  "rf.shares_tenant",
  "rf.book_role",
  "rf.device_visible",
  "rf.book_tenant",
];

Deno.test("E-03-15 every table: RLS enabled + FORCEd, and a policy or an explicit no-access listing", () => {
  assert(tables.size >= 30, `parsed ${tables.size} tables`);
  const rls = doBodies.find((b) =>
    b.includes("enable row level security") && b.includes("force row level security")
  );
  assert(rls, "one DO block enables + forces RLS");
  assertStringIncludes(rls!, "pg_tables where schemaname = 'public'");
  assert(!/disable row level security/i.test(allSql));
  assert(!/no force row level security/i.test(allSql));
  for (const t of tables) {
    const has = policiesOn(t).length > 0 || NO_ACCESS.has(t);
    assert(has, `${t} has no policy and is not listed as no-access`);
    if (NO_ACCESS.has(t)) {
      assertEquals(grantsOn(t, "rf_api").length, 0, `${t} must have no rf_api grant`);
    }
  }
});

Deno.test("E-03-16 append-only store: rf_api holds SELECT/INSERT only on envelopes + signed_records; nobody holds UPDATE; maintenance may only DELETE", () => {
  for (const t of ["envelopes", "signed_records"]) {
    const api = privsOf(t, "rf_api");
    assertEquals([...api].sort(), ["insert", "select"], `${t} rf_api grants`);
    for (const g of grants.filter((g) => g.is_grant && g.tables.includes(t))) {
      assert(
        !g.privileges.includes("update") && g.privileges.length > 0,
        `${t}: UPDATE/ALL granted to ${g.grantees}`,
      );
    }
    for (const p of policiesOn(t)) {
      assert(["select", "insert", "delete"].includes(p.cmd), `${t} policy ${p.name} cmd ${p.cmd}`);
    }
    assert(
      !policiesOn(t).some((p) => p.cmd === "delete" && p.roles.includes("rf_api")),
      `${t}: rf_api delete policy`,
    );
  }
  assertEquals([...privsOf("envelopes", "rf_maintenance")].sort(), ["delete", "select"]);
  assertEquals(grantsOn("signed_records", "rf_maintenance").length, 0);
  // belt and braces: triggers refuse UPDATE and guard DELETE even for a role that somehow gets the grant
  assert(triggers.some((t) => t.table === "envelopes" && t.fn === "rf.refuse_update"));
  assert(triggers.some((t) => t.table === "envelopes" && t.fn === "rf.guard_envelope_delete"));
  assertStringIncludes(fn("rf.guard_envelope_delete"), "'personal'");
  assertStringIncludes(fn("rf.guard_envelope_delete"), "erased_at");
  // no dynamic grant sneaks UPDATE in
  assert(
    !/grant\s+(all|update)[^;]*on\s+(all tables|envelopes|signed_records)/i.test(
      allSql.replace(/revoke[^;]*;/gi, ""),
    ),
  );
});

Deno.test("E-03-28 one sequence for envelopes and signed records (ADR 05b §5)", () => {
  const seqCols = columns.filter((c) => c.name === "seq");
  assertEquals(seqCols.map((c) => c.table).sort(), ["envelopes", "signed_records"]);
  const m = allSql.match(/seq bigint not null unique default nextval\('store_seq'\)/g) ?? [];
  assertEquals(m.length, 2);
  assertStringIncludes(allSql, "create sequence store_seq as bigint");
});

Deno.test("E-03-17 phone numbers: only phone_ct/phone_hmac (bytea) exist; invites keep invitee_hmac; rf_api's users column grant excludes both", () => {
  const phoneish = columns.filter((c) => /phone|mobile|msisdn|e164/i.test(c.name));
  for (const c of phoneish) {
    assert(
      ["phone_ct", "phone_hmac"].includes(c.name),
      `${c.table}.${c.name} is neither phone_ct nor phone_hmac`,
    );
    assertEquals(c.type, "bytea", `${c.table}.${c.name}`);
  }
  assertEquals(
    phoneish.filter((c) => c.name === "phone_ct").map((c) => c.table),
    ["users"],
    "ciphertext lives in users only",
  );
  assertEquals(phoneish.filter((c) => c.name === "phone_hmac").map((c) => c.table).sort(), [
    "activation_tickets",
    "otp_challenges",
    "users",
  ]);
  assertEquals(
    columns.find((c) => c.table === "invites" && c.name === "invitee_hmac")?.type,
    "bytea",
  );
  assert(!columns.some((c) => c.table === "invites" && /phone/i.test(c.name)));
  const userGrants = grantsOn("users", "rf_api");
  assert(
    userGrants.length > 0 && userGrants.every((g) => g.columns.length > 0),
    "users grants are column lists",
  );
  for (const g of userGrants) {
    assert(
      !g.columns.includes("phone_ct") && !g.columns.includes("phone_hmac"),
      `users grant leaks ${g.columns}`,
    );
  }
  // the only readers are security-definer functions used before a claim exists
  for (const name of ["rf.find_user_by_phone_hmac", "rf.phone_ct_for_otp", "rf.signup_user"]) {
    assert(fn(name).length > 0, name);
  }
});

Deno.test("E-03-18 certified-only: every policy on a tenant-scoped table is gated by a helper that requires devices.status = 'certified'", () => {
  const certified = new Set<string>();
  const direct = (body: string) =>
    /d\.status = 'certified'/.test(body) || /rf\.is_certified\(\)/.test(body);
  // transitive closure over helper bodies
  let changed = true;
  while (changed) {
    changed = false;
    for (const h of CERT_HELPERS) {
      if (certified.has(h)) continue;
      const body = fn(h);
      if (direct(body) || [...certified].some((c) => body.includes(`${c}(`))) {
        certified.add(h);
        changed = true;
      }
    }
  }
  assert(
    certified.has("rf.is_certified") && certified.has("rf.active_in_tenant") &&
      certified.has("rf.book_role") && certified.has("rf.device_visible"),
  );
  assert(!certified.has("rf.book_tenant"), "book_tenant is a plain lookup, not a gate");
  for (const t of TENANT_TABLES) {
    const ps = policiesOn(t);
    assert(ps.length > 0, `${t} has policies`);
    for (const p of ps) {
      if (p.roles.includes("rf_maintenance")) continue;
      const gated = [...certified].some((h) => p.source.includes(`${h}(`));
      assert(gated, `${t}.${p.name} is not certified-gated: ${p.source}`);
    }
  }
  // and the uncertified allowances of ADR 05d §2 are exactly: own user row, own device, keys addressed to it, own recovery request
  assertStringIncludes(policiesOn("users")[0].source, "id = rf.user_id()");
  assertStringIncludes(fn("rf.device_visible"), "p_device = rf.device_id()");
  assertStringIncludes(
    policiesOn("wrapped_keys").find((p) => p.cmd === "select")!.source,
    "device_id = rf.device_id()",
  );
  assertStringIncludes(
    policiesOn("recovery_requests").find((p) => p.cmd === "select")!.source,
    "candidate_device = rf.device_id()",
  );
});

Deno.test("E-03-19 rows are projections of signed records: every rf.project_* demands the record; rf_api cannot write memberships/book_roles directly", () => {
  const projectors = fns.filter((f) => f.name.startsWith("rf.project_"));
  assert(projectors.length >= 4, "membership, book_role, device_status, verification_event");
  for (const p of projectors) assertStringIncludes(p.body, "rf.require_record(", p.name);
  assertStringIncludes(fn("rf.require_record"), "author_device = rf.device_id()");
  assertStringIncludes(fn("rf.mark_record_applied"), "author_device = rf.device_id()");
  for (const t of ["memberships", "book_roles", "verification_events"]) {
    assertEquals([...privsOf(t, "rf_api")], ["select"], `${t} is read-only for rf_api`);
    assert(policiesOn(t).every((p) => p.cmd === "select"), `${t} has a write policy`);
  }
  // devices.status is never writable by rf_api either: only rf.certify_device / rf.project_device_status
  assertEquals([...privsOf("devices", "rf_api")], ["select"]);
});

Deno.test("E-03-20 claims are SET LOCAL and read from our settings; platform roles keep nothing; maintenance-only powers are revoked from rf_api", () => {
  assertStringIncludes(
    fn("rf.set_claims"),
    "set_config('request.user_id', coalesce(p_user::text, ''), true)",
  );
  assertStringIncludes(
    fn("rf.set_claims"),
    "set_config('request.device_id', coalesce(p_device::text, ''), true)",
  );
  assertStringIncludes(fn("rf.user_id"), "current_setting('request.user_id', true)");
  assertStringIncludes(fn("rf.device_id"), "current_setting('request.device_id', true)");
  assert(!/auth\.uid\(\)|auth\.jwt\(\)/.test(allSql), "no platform-auth claims anywhere");
  const revokes = doBodies.find((b) =>
    b.includes("'anon','authenticated','service_role'") && b.includes("revoke all on all tables")
  );
  assert(revokes, "platform roles revoked");
  assertStringIncludes(allSql, "revoke execute on function rf.bump_store_epoch(text) from rf_api");
  // `revoke ... from public` is NOT enough: `grant execute on all functions in schema rf to rf_api`
  // hands the function to rf_api afterwards, and a PUBLIC revoke does not take it back from a role
  // holding an explicit grant. Both maintenance-only functions need the rf_api revoke by name —
  // asserting only the PUBLIC revoke is what let the live suite's E-03-26 catch this instead.
  assertStringIncludes(
    allSql,
    "revoke execute on function rf.purge_ephemeral_auth() from rf_api",
  );
  assertEquals(
    grantsOn("push_rate", "rf_api").length,
    0,
    "rate windows only via rf.push_rate_check",
  );
  assertStringIncludes(fn("rf.push_rate_check"), "600");
  assertStringIncludes(fn("rf.push_rate_check"), "5000");
  assertStringIncludes(fn("rf.push_rate_check"), "52428800");
});

Deno.test("E-03-21 registries and caps in the schema match 03 §2.3 / 05 §3", () => {
  const objectTypes = [
    "book_config",
    "account",
    "entry",
    "approval_decision",
    "period_lock",
    "year_close",
    "import_batch",
    "import_line",
    "rule",
    "attachment_meta",
    "cash_count",
    "period_unlock",
    "structural_approval",
    "business_setting",
  ];
  const envelopeDdl = allSql.slice(
    allSql.indexOf("create table envelopes"),
    allSql.indexOf("create index envelopes_book_seq_idx"),
  );
  for (const t of objectTypes) assertStringIncludes(envelopeDdl, `'${t}'`);
  assertStringIncludes(envelopeDdl, "size <= 262144");
  assertStringIncludes(envelopeDdl, "octet_length(blob_hash) = 32");
  assertStringIncludes(envelopeDdl, "(blob is null) <> (blob_ref is null)");
  assertStringIncludes(allSql, "create index envelopes_book_seq_idx on envelopes (book_id, seq)");
  assertEquals(
    columns.find((c) => c.table === "book_roles" && c.name === "auto_post_limit_paise")?.type,
    "pg_catalog.int8",
    "money is BIGINT paise",
  );
  assert(
    !columns.some((c) => /float|numeric|decimal|money/i.test(c.type)),
    "no float/decimal columns anywhere",
  );
});

Deno.test("E-05c-8 (static) private bucket, 10 MB cap, 24 h auth-row purge, 90 d revoked-key purge, freeze ≤ 30 d", async () => {
  const toml = await Deno.readTextFile(CONFIG);
  const bucket = toml.slice(toml.indexOf("[storage.buckets.attachments]"));
  assertStringIncludes(bucket.split("\n").slice(0, 4).join("\n"), "public = false");
  assertStringIncludes(bucket, 'file_size_limit = "10MiB"');
  assertStringIncludes(toml, "[auth]\nenabled = false");
  const purge = fn("rf.purge_ephemeral_auth");
  for (const t of ["otp_challenges", "activation_tickets", "auth_nonces"]) {
    assertStringIncludes(purge, `delete from ${t} where created_at < now() - interval '24 hours'`);
  }
  assertStringIncludes(
    purge,
    "delete from wrapped_keys where revoked_at is not null and revoked_at < now() - interval '90 days'",
  );
  assertStringIncludes(allSql, "expires_at <= imposed_at + interval '30 days'");
  assertStringIncludes(allSql, "approved_by <> imposed_by");
  // ⚠️ the 24-month audit_events aggregation and the orphan sweeper are scheduled jobs (README §5), not schema.
});
