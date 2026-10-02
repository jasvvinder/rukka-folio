// OTP provider selection (06 §2 🔒 as amended by ADR 2026-09-25 §1; PLAN desk 57, owner-ruled
// 28 Sep, option 1 "strict"). Called once per isolate from deps.ts `depsFromEnv()`, before
// anything else is built.
//
//   OTP_PROVIDER = msg91 → Msg91Provider (needs OTP_PROVIDER_API_KEY, OTP_DLT_ENTITY_ID,
//                          OTP_DLT_TEMPLATE_ID)
//                = fake  → FakeOtpProvider: sends nothing. Random codes, unless the second switch
//                          below binds a fixed dev code to this project.
//   unset, empty, or any other value → OtpConfigError: the function refuses to start and every
//   call answers 503 `unconfigured` (deps.ts `entry`). Never a silent 200 with nothing sent.
//
// The fixed dev code (ADR 2026-09-25 §1: "Until DLT clears, the dev project uses fixed test codes
// … A fixed code never exists in a pilot or production project") needs BOTH switches:
//   1. OTP_PROVIDER=fake, and
//   2. RF_DEV_PROJECT_REF=<this project's ref>, which must equal the ref inside the platform-injected
//      SUPABASE_URL (`https://<ref>.supabase.co`).
// The operator cannot set SUPABASE_URL: the Supabase CLI's secrets API refuses any name with the
// SUPABASE_ prefix ("Secret name must not start with the SUPABASE_ prefix", supabase CLI 2.116.0),
// and the platform injects it itself (env.ts header). So the dev project's secrets copied wholesale
// onto the pilot carry the DEV ref, which does not match the pilot's own SUPABASE_URL: the pilot
// refuses to start rather than issue a fixed code. One mistyped variable cannot do it either: a
// switch that is set but does not match refuses to start too, and a missing switch gives random
// codes.
// ⚠️ SPEC (OTP2, 1 Oct 2026): conservative reading of "a fixed code never exists in a pilot or
// production project". (a) The project is identified by the ref the PLATFORM injects, never by a
// value the operator writes; the env exposes nothing else that tells dev from pilot. (b) What this
// cannot stop is a person who deliberately writes the pilot's own ref into a variable named
// RF_DEV_PROJECT_REF on the pilot as well as setting OTP_PROVIDER=fake: two deliberate acts, not a
// mistype. A stricter form pins the dev ref in source, as a reviewed commit; that is an owner call
// (lane report). (c) "fixed test codes" is read as ONE fixed code for every number, since the fake
// delivers nothing and every tester needs some code. (d) Local `supabase functions serve` injects
// SUPABASE_URL=http://kong:8000 (supabase CLI 2.116.0), which names no project, so the fixed code is
// impossible locally as well. (e) The hosted value's exact form `https://<20-char ref>.supabase.co`
// is taken from .env.example and is not verified against a live project. If it differs, a set
// switch refuses to start and the log says `otp_fixed_code_unbound`. That fails closed.
import { ENV } from "../env.ts";
import { type DevFixedCode, FakeOtpProvider, Msg91Provider, type OtpProvider } from "./provider.ts";

export type EnvGet = (name: string) => string | undefined;

export type OtpConfigReason =
  | "otp_provider_unset"
  | "otp_provider_unknown"
  | "otp_provider_not_built"
  | "otp_provider_credentials_missing"
  | "otp_fixed_code_unbound";

/** A configuration the functions refuse to start under. The message is the reason and nothing else.
 *  It never holds the configured value, which could be a key pasted into the wrong variable. */
export class OtpConfigError extends Error {
  constructor(readonly reason: OtpConfigReason) {
    super(reason);
    this.name = "OtpConfigError";
  }
}

/** The fixed dev code. Public on purpose: it exists only on the dev project, which holds synthetic
 *  data only (docs/ops/lead-times.md §1). Like every code, it is stored only as its hash and is
 *  never logged (rule 4). */
export const DEV_FIXED_OTP_CODE = "123456";

/** Every value OTP_PROVIDER may take. Exact match: no case-folding and no trimming. A Map, so no
 *  inherited key (`constructor`, `__proto__`) can be looked up as a provider. */
const BUILT: ReadonlyMap<string, (get: EnvGet) => OtpProvider> = new Map<
  string,
  (get: EnvGet) => OtpProvider
>([
  ["msg91", (get: EnvGet) =>
    new Msg91Provider(
      need(get, ENV.OTP_API_KEY),
      need(get, ENV.OTP_DLT_ENTITY),
      need(get, ENV.OTP_DLT_TEMPLATE),
    )],
  ["fake", (get: EnvGet) => new FakeOtpProvider({ fixedCode: devFixedCode(get), record: false })],
]);

/** EXTENSION POINT (row OTP3): `2factor` is the owner's pick (docs/ops/lead-times.md §3). Its HTTP
 *  API is in no local doc and must not be guessed, so no adapter exists. Until OTP3 adds a
 *  `TwoFactorProvider` to BUILT (and removes it here), the value refuses to start with its own
 *  reason, so the log says it is "not built" rather than "unknown". */
const NOT_BUILT: ReadonlySet<string> = new Set(["2factor"]);

export function selectOtpProvider(get: EnvGet): OtpProvider {
  const name = get(ENV.OTP_PROVIDER);
  if (!name) throw new OtpConfigError("otp_provider_unset");
  const build = BUILT.get(name);
  if (build) return build(get);
  if (NOT_BUILT.has(name)) throw new OtpConfigError("otp_provider_not_built");
  throw new OtpConfigError("otp_provider_unknown");
}

/** The ref in a hosted project's URL, `https://<ref>.supabase.co` (an optional trailing slash). Any
 *  other shape gives null: http, a port, a path, credentials, a custom domain, a look-alike suffix,
 *  or local `http://kong:8000`. */
export function projectRefOf(url: string | undefined): string | null {
  const m = /^https:\/\/([a-z0-9]{20})\.supabase\.co\/?$/.exec(url ?? "");
  return m ? m[1] : null;
}

/** The second switch. Unset or empty → null (random codes). Set → it must name the project the
 *  platform says this is, or the function refuses to start. */
function devFixedCode(get: EnvGet): DevFixedCode | null {
  const sw = get(ENV.DEV_PROJECT_REF);
  if (!sw) return null;
  const ref = projectRefOf(get(ENV.SUPABASE_URL));
  if (ref === null || ref !== sw) throw new OtpConfigError("otp_fixed_code_unbound");
  return DEV_FIXED_OTP_CODE as DevFixedCode;
}

function need(get: EnvGet, name: string): string {
  const v = get(name);
  if (!v) throw new OtpConfigError("otp_provider_credentials_missing");
  return v;
}
