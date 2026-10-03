// The connection the edge holds, for the RLS suite: rf_api, never the owner (desk 76).
//
// ADR 2026-09-05d §2 treats rf_api as hostile and makes RLS the boundary; ADR 2026-09-05c §7 puts
// every edge function on the rf_api login. RF_TEST_DB_URL is the SCHEMA OWNER's URL — a superuser
// on a local cluster — and a superuser bypasses every row policy, FORCE or not. A PgStore built on
// that URL therefore tests only triggers and SECURITY DEFINER guards; 0005's row policies never run.
// Every PgStore arm in tests/rls/ is built here instead, so the store under test runs as rf_api and
// the policies are real.
//
// The role is set at connection startup (`options=-c role=rf_api`, a libpq startup parameter that
// postgres.js passes through from the URL), so it holds for every query on every pooled connection,
// inside and outside a transaction. Both builders assert the precondition on the very pool they
// hand back — current_user is rf_api, and rf_api is neither superuser nor BYPASSRLS — and refuse to
// return a client that would silently test nothing.
//
// Fixture setup a hostile caller could not write (users, devices, tenants, a plan row) stays on the
// owner's connection in each file; only the arm under test moves here. Not a test file (no
// `.test.ts`), so `deno test` does not collect it.
import { assertEquals } from "@std/assert";
import postgres from "postgres";
import { PgStore } from "../../functions/_shared/store_pg.ts";

/** `url` with the startup parameter that makes the session's role rf_api. */
export function apiUrl(url: string): string {
  const sep = url.includes("?") ? "&" : "?";
  return `${url}${sep}options=${encodeURIComponent("-c role=rf_api")}`;
}

/** Precondition for every arm: `sql` runs as rf_api and rf_api cannot bypass RLS. */
export async function assertApiRole(
  sql: postgres.Sql | postgres.TransactionSql,
  what: string,
): Promise<void> {
  const [r] = await sql`select current_user::text as u, r.rolsuper as su, r.rolbypassrls as by
    from pg_roles r where r.rolname = current_user`;
  assertEquals(
    r?.u,
    "rf_api",
    `precondition: ${what} runs as rf_api, so 0005's row policies apply`,
  );
  assertEquals(r.su, false, `precondition: rf_api is not a superuser (${what})`);
  assertEquals(r.by, false, `precondition: rf_api does not hold BYPASSRLS (${what})`);
}

/** A postgres.js client as rf_api (default one connection), precondition asserted. The caller
 *  ends it. */
export async function apiSql(
  url: string,
  options: postgres.Options<Record<string, postgres.PostgresType>> = {},
): Promise<postgres.Sql> {
  const sql = postgres(apiUrl(url), { max: 1, onnotice: () => {}, ...options });
  try {
    await assertApiRole(sql, "the rf_api client");
  } catch (e) {
    await sql.end();
    throw e;
  }
  return sql;
}

/** The REAL store as the edge builds it — PgStore on the rf_api login — with the precondition
 *  asserted on the store's OWN pool, not on a sibling connection. The caller ends it. */
export async function apiStore(url: string): Promise<PgStore> {
  const store = new PgStore(apiUrl(url));
  try {
    // PgStore keeps its pool private; the suite reads it only to prove which role it runs as.
    const pool = (store as unknown as { sql?: postgres.Sql }).sql;
    if (typeof pool !== "function") {
      throw new Error("_pg_api.ts: PgStore no longer keeps its pool on `sql`; update apiStore()");
    }
    await assertApiRole(pool, "the PgStore under test");
  } catch (e) {
    await store.end();
    throw e;
  }
  return store;
}
