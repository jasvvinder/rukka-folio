// Everything a handler needs, injected: store, clock, keys, OTP provider. `depsFromEnv()` builds the
// hosted set from env; `liveDeps()` caches it once per isolate for each index.ts. Tests build their
// own around `MemStore` with a fixed clock and the `FakeOtpProvider`.
import { b64 } from "./bytes.ts";
import { ENV, env, MissingEnvError } from "./env.ts";
import { error } from "./http.ts";
import { type EnvGet, OtpConfigError, selectOtpProvider } from "./otp/select.ts";
import type { OtpProvider } from "./otp/provider.ts";
import type { Store } from "./store.ts";
import { PgStore } from "./store_pg.ts";

export interface Deps {
  store: Store;
  now: () => Date;
  jwtKey: Uint8Array;
  phoneHmacKey: Uint8Array;
  phoneKek: Uint8Array;
  /** 32-byte Ed25519 seed of `entitlement_key` (04 §8.6 🔒). Only sodium.ts's
   *  `signEntitlementToken` may take it, and it signs only an `EntitlementPayload`. */
  entitlementSeed: Uint8Array;
  otp: OtpProvider;
  webhookSecret: Uint8Array;
}

/** The hosted dependency set, read through `get`. The OTP provider is selected FIRST (desk 57,
 *  owner 28 Sep): an unset or unknown OTP_PROVIDER, or a fixed-code switch that does not name this
 *  project, throws `OtpConfigError` before a store or a key is built (otp/select.ts). A missing
 *  required secret throws `MissingEnvError`. Either way the isolate serves only 503s (`entry`). */
export function depsFromEnv(get: EnvGet): Deps {
  const otp = selectOtpProvider(get);
  const need = (name: string): string => {
    const v = get(name);
    if (!v) throw new MissingEnvError(name);
    return v;
  };
  return {
    store: new PgStore(need(ENV.DB_URL)),
    now: () => new Date(),
    jwtKey: b64.dec(need(ENV.JWT_KEY)),
    phoneHmacKey: b64.dec(need(ENV.PHONE_HMAC_KEY)),
    phoneKek: b64.dec(need(ENV.PHONE_KEK)),
    entitlementSeed: b64.dec(need(ENV.ENTITLEMENT_KEY)),
    otp,
    webhookSecret: new TextEncoder().encode(get(ENV.WEBHOOK_SECRET) ?? ""),
  };
}

let live: Deps | null = null;
/** Cached per isolate. A refusal is not cached: it throws again on every call, so every call errors. */
export function liveDeps(): Deps {
  if (live) return live;
  live = depsFromEnv(env);
  return live;
}

type Handler = (req: Request, deps: Deps) => Promise<Response>;
type Listen = (h: (req: Request) => Promise<Response>) => unknown;

/** What a refusal logs: a fixed reason or a variable NAME, never a message or a value (rule 4; a
 *  value could be a key pasted into the wrong variable). */
function refusal(e: unknown): string {
  if (e instanceof OtpConfigError) return e.reason;
  if (e instanceof MissingEnvError) return `missing_env ${e.variable}`;
  return (e as Error)?.constructor?.name ?? "Error";
}

/** The per-request wrapper. Deps that cannot be built → 503 `{error: "unconfigured"}`, and the
 *  handler is never reached. A handler that throws → 500 `{error: "internal"}`. No request body,
 *  phone or blob ever reaches a log line (rule 4). */
export function entry(handler: Handler, depsFn: () => Deps): (req: Request) => Promise<Response> {
  return async (req) => {
    let deps: Deps;
    try {
      deps = depsFn();
    } catch (e) {
      console.error("refused", refusal(e));
      return error(503, "unconfigured");
    }
    try {
      return await handler(req, deps);
    } catch (e) {
      // Name only: never the message (it could quote a request field).
      console.error("unhandled", (e as Error)?.constructor?.name ?? "Error");
      return error(500, "internal");
    }
  };
}

/** Starts a function. The deps are checked once at startup, so a bad configuration is logged at boot
 *  rather than at the first request ("refuses to start", desk 57). The isolate still listens, but
 *  only to answer every call with 503 `unconfigured`. A platform boot error has an unverified status
 *  and body; this answer is ours and is tested (E-25-4, E-25-5, E-25-9). The other half is tested
 *  too: a valid configuration starts, and every call reaches the handler with the provider the
 *  hosted builder selected — through `depsFromEnv` (E-25-6, E-25-7, E-25-8) and through the default
 *  `liveDeps` reading Deno.env, as `serve()` runs it (E-25-6). */
export function start(
  handler: Handler,
  depsFn: () => Deps = liveDeps,
  listen: Listen = (h) => Deno.serve(h),
): void {
  try {
    depsFn();
  } catch (e) {
    console.error("startup refused", refusal(e));
  }
  listen(entry(handler, depsFn));
}

/** Wraps a handler for Deno.serve (each index.ts, under `import.meta.main`). */
export function serve(handler: Handler): void {
  start(handler);
}
