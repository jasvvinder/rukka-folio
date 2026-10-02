// OTP delivery behind an interface (06 §2 🔒, as amended by ADR 2026-09-25 §1): **SMS is the one
// channel**, sent by an Indian provider on the owner's own TRAI DLT registration (one OTP
// template). There is no channel preference and no failover: a send is one attempt, and a failed
// one returns null — auth-challenge then answers generically and stores nothing (06 §2). Adding
// WhatsApp later is a provider configuration under a new ruling, not a branch here (E-25-1).
// The provider is picked by OTP_PROVIDER at startup (otp/select.ts, called from deps.ts
// `depsFromEnv()`): `msg91` or an explicit `fake`, nothing else — unset or unknown refuses to start
// (PLAN desk 57, owner 28 Sep). The fake is what `deno test`, local dev and the hosted dev project use.
// The server sends nothing else through this seam — invitations go from the inviter's own phone
// (ADR 2026-09-25 §2, E-25-2).
/** The one channel (ADR 2026-09-25 §1). 0004's `channel in ('whatsapp','sms')` check is wider;
 *  only `sms` is ever written. */
export type OtpChannel = "sms";

declare const devFixedCode: unique symbol;
/** The fixed dev code (ADR 2026-09-25 §1). A distinct type so that only otp/select.ts — after its
 *  two-switch, project-bound check — can hand one to a provider (the same idea as CLAUDE.md rule 5's
 *  verified keys). Nothing else should cast to it. */
export type DevFixedCode = string & { readonly [devFixedCode]: true };

export interface OtpProvider {
  /** Sends the code by SMS, once; returns the channel that accepted it, or null when it failed.
   *  Never retried on another channel. */
  send(e164: string, code: string): Promise<OtpChannel | null>;
  /** The code auth-challenge must issue instead of a fresh random one. Only a FakeOtpProvider that
   *  otp/select.ts built for the dev project carries one; absent or null everywhere else. */
  readonly fixedCode?: DevFixedCode | null;
}

/** Delivers nothing. Used by `deno test`, local dev, and — until DLT clears — the hosted dev project
 *  (ADR 2026-09-25 §1: "the dev project uses fixed test codes (`FakeOtpProvider`)"); never a pilot
 *  or production project. otp/select.ts builds it only for an explicit `OTP_PROVIDER=fake`, and gives
 *  it a fixed code only when RF_DEV_PROJECT_REF names the project the platform says this is. Without
 *  that, the code is random and only its hash is stored, so the fake fails closed: no one signs in.
 *  `record` (tests) keeps what would have been sent; the hosted fake keeps nothing, so no phone
 *  number or code sits in an isolate's memory (rule 4). */
export class FakeOtpProvider implements OtpProvider {
  sent: { e164: string; code: string; channel: OtpChannel }[] = [];
  /** Every send() call, delivered or not — one per request is what "no failover" means. */
  attempts = 0;
  /** The SMS fails: nothing is recorded as sent, and send() answers null. */
  fail = false;
  readonly fixedCode: DevFixedCode | null;
  private readonly record: boolean;
  constructor(opts: { fixedCode?: DevFixedCode | null; record?: boolean } = {}) {
    this.fixedCode = opts.fixedCode ?? null;
    this.record = opts.record ?? true;
  }
  send(e164: string, code: string): Promise<OtpChannel | null> {
    this.attempts++;
    if (this.fail) return Promise.resolve(null);
    if (this.record) this.sent.push({ e164, code, channel: "sms" });
    return Promise.resolve("sms");
  }
}

/** MSG91-shaped HTTP provider, SMS only: one POST, no second channel (ADR 2026-09-25 §1).
 *  ⚠️ The endpoint and body are unverified against MSG91's current API; the real provider, and the
 *  choice between MSG91 and 2Factor, is row OTP3. Template ids are DLT-registered. */
export class Msg91Provider implements OtpProvider {
  /** A real provider never sends a fixed code: every send carries a fresh random one. */
  readonly fixedCode = null;
  constructor(private apiKey: string, private dltEntity: string, private dltTemplate: string) {}
  async send(e164: string, code: string): Promise<OtpChannel | null> {
    try {
      const res = await fetch("https://control.msg91.com/api/v5/otp", {
        method: "POST",
        headers: { authkey: this.apiKey, "content-type": "application/json" },
        body: JSON.stringify({
          template_id: this.dltTemplate,
          mobile: e164.slice(1),
          otp: code,
          dlt_te_id: this.dltEntity,
        }),
      });
      await res.body?.cancel();
      return res.ok ? "sms" : null;
    } catch {
      // Nothing is logged (the body holds the number and the code), and nothing is retried.
      return null;
    }
  }
}
