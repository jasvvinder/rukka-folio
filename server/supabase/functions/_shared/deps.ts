// Everything a handler needs, injected: store, clock, keys, OTP provider. `liveDeps()` builds the
// hosted set from env (called once per isolate by each index.ts); tests build their own around
// `MemStore` with a fixed clock and the `FakeOtpProvider`.
import { b64 } from "./bytes.ts";
import { ENV, env, requireEnv } from "./env.ts";
import { FakeOtpProvider, Msg91Provider, type OtpProvider } from "./otp/provider.ts";
import type { Store } from "./store.ts";
import { PgStore } from "./store_pg.ts";

export interface Deps {
  store: Store;
  now: () => Date;
  jwtKey: Uint8Array;
  phoneHmacKey: Uint8Array;
  phoneKek: Uint8Array;
  otp: OtpProvider;
  webhookSecret: Uint8Array;
}

let live: Deps | null = null;
export function liveDeps(): Deps {
  if (live) return live;
  const provider = env(ENV.OTP_PROVIDER) ?? "fake";
  const otp: OtpProvider = provider === "msg91"
    ? new Msg91Provider(
      requireEnv(ENV.OTP_API_KEY),
      requireEnv(ENV.OTP_DLT_ENTITY),
      requireEnv(ENV.OTP_DLT_TEMPLATE),
    )
    : new FakeOtpProvider(); // ⚠️ hosted builds must set OTP_PROVIDER (06 §2); the fake sends nothing
  live = {
    store: new PgStore(requireEnv(ENV.DB_URL)),
    now: () => new Date(),
    jwtKey: b64.dec(requireEnv(ENV.JWT_KEY)),
    phoneHmacKey: b64.dec(requireEnv(ENV.PHONE_HMAC_KEY)),
    phoneKek: b64.dec(requireEnv(ENV.PHONE_KEK)),
    otp,
    webhookSecret: new TextEncoder().encode(env(ENV.WEBHOOK_SECRET) ?? ""),
  };
  return live;
}

/** Wraps a handler for Deno.serve: no request body, phone or blob ever reaches a log line (rule 4). */
export function serve(handler: (req: Request, deps: Deps) => Promise<Response>): void {
  Deno.serve(async (req) => {
    try {
      return await handler(req, liveDeps());
    } catch (e) {
      // Name only: never the message (it could quote a request field).
      console.error("unhandled", (e as Error)?.constructor?.name ?? "Error");
      return new Response(JSON.stringify({ error: "internal" }), {
        status: 500,
        headers: { "content-type": "application/json; charset=utf-8" },
      });
    }
  });
}
