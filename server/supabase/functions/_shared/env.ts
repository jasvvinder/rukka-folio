// Every environment variable the functions read, in one place (.env.example lists the shared ones).
// Supabase injects SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_DB_URL into edge functions.
export const ENV = {
  DB_URL: "RF_API_DB_URL", // connection string for the rf_api login role (pooled, transaction mode)
  MAINT_DB_URL: "RF_MAINT_DB_URL", // rf_maintenance login — scheduled functions only
  JWT_KEY: "RF_JWT_HMAC_KEY", // 32+ bytes, base64 — our HS256 access-token key (06 §4)
  PHONE_HMAC_KEY: "RF_PHONE_HMAC_KEY", // base64 — phone_hmac (ADR 2026-09-05c §4); Vault-managed in hosted
  PHONE_KEK: "RF_PHONE_KEK", // base64 32 bytes — phone_ct key (Vault/KMS); rotation re-encrypts in place
  OTP_PROVIDER: "OTP_PROVIDER", // msg91 | kaleyra | twilio | fake
  OTP_API_KEY: "OTP_PROVIDER_API_KEY",
  OTP_DLT_ENTITY: "OTP_DLT_ENTITY_ID",
  OTP_DLT_TEMPLATE: "OTP_DLT_TEMPLATE_ID",
  WEBHOOK_SECRET: "PAYMENT_GATEWAY_WEBHOOK_SECRET",
} as const;

export function env(name: string): string | undefined {
  try {
    return Deno.env.get(name);
  } catch {
    return undefined;
  }
}
export function requireEnv(name: string): string {
  const v = env(name);
  if (!v) throw new Error(`missing env ${name}`);
  return v;
}
