// Every environment variable the functions read, in one place (.env.example lists the shared ones).
// Supabase injects SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_DB_URL into edge functions.
export const ENV = {
  DB_URL: "RF_API_DB_URL", // connection string for the rf_api login role (pooled, transaction mode)
  MAINT_DB_URL: "RF_MAINT_DB_URL", // rf_maintenance login — scheduled functions only
  JWT_KEY: "RF_JWT_HMAC_KEY", // 32+ bytes, base64 — our HS256 access-token key (06 §4)
  PHONE_HMAC_KEY: "RF_PHONE_HMAC_KEY", // base64 — phone_hmac (ADR 2026-09-05c §4); Vault-managed in hosted
  PHONE_KEK: "RF_PHONE_KEK", // base64 32 bytes — phone_ct key (Vault/KMS); rotation re-encrypts in place
  // base64 32 bytes — the Ed25519 SEED of the one server signing key, `entitlement_key` (04 §8.6 🔒,
  // ADR 2026-09-05g §1 🔒). It signs entitlement tokens and nothing else; the public half is derived
  // from it at startup and pinned in the app. Never logged, never returned, never in an error body.
  // ⚠️ SPEC (M13-TOK1, 22 Sep): where this seed LIVES — Supabase Vault or a cloud KMS — is ADR
  // 2026-09-05c's open item 2, undecided together with the phone key. Injected as an env var here
  // exactly as RF_JWT_HMAC_KEY is, so whichever the owner rules, only the injection changes. Annual
  // rotation with a 30-day overlap (04 §8 rule 6 🔒) is an ops procedure, not a code path: during
  // an overlap the app holds both pinned public keys (see sodium.ts's header).
  ENTITLEMENT_KEY: "RF_ENTITLEMENT_KEY",
  // msg91 | fake — nothing else (PLAN desk 57). Unset or unknown refuses to start; `2factor` is
  // named in otp/select.ts as row OTP3's extension point and refuses until it is built.
  OTP_PROVIDER: "OTP_PROVIDER",
  OTP_API_KEY: "OTP_PROVIDER_API_KEY",
  OTP_DLT_ENTITY: "OTP_DLT_ENTITY_ID",
  OTP_DLT_TEMPLATE: "OTP_DLT_TEMPLATE_ID",
  // The second switch for the fixed dev OTP code (ADR 2026-09-25 §1, desk 57): set ONLY on the dev
  // project, to that project's own ref. It works only with OTP_PROVIDER=fake and only when it equals
  // the ref in SUPABASE_URL (otp/select.ts). Never set it on a pilot or production project.
  DEV_PROJECT_REF: "RF_DEV_PROJECT_REF",
  // Platform-injected (`https://<ref>.supabase.co`); the operator cannot set a SUPABASE_-prefixed
  // secret. Read only to name the project the fixed dev code is bound to.
  SUPABASE_URL: "SUPABASE_URL",
  WEBHOOK_SECRET: "PAYMENT_GATEWAY_WEBHOOK_SECRET",
} as const;

/** A required variable is missing. It names the variable, never a value, so it is safe to log. */
export class MissingEnvError extends Error {
  constructor(readonly variable: string) {
    super(`missing env ${variable}`);
    this.name = "MissingEnvError";
  }
}

export function env(name: string): string | undefined {
  try {
    return Deno.env.get(name);
  } catch {
    return undefined;
  }
}
export function requireEnv(name: string): string {
  const v = env(name);
  if (!v) throw new MissingEnvError(name);
  return v;
}
