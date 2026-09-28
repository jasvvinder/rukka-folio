// OTP delivery behind an interface (06 §2 🔒, as amended by ADR 2026-09-25 §1): **SMS is the one
// channel**, sent by an Indian provider on the owner's own TRAI DLT registration (one OTP
// template). There is no channel preference and no failover: a send is one attempt, and a failed
// one returns null — auth-challenge then answers generically and stores nothing (06 §2). Adding
// WhatsApp later is a provider configuration under a new ruling, not a branch here (E-25-1).
// The provider is picked by OTP_PROVIDER at startup (deps.ts `liveDeps()`); the fake is what
// `deno test`, local dev and the hosted dev project use (see FakeOtpProvider below).
// The server sends nothing else through this seam — invitations go from the inviter's own phone
// (ADR 2026-09-25 §2, E-25-2).
/** The one channel (ADR 2026-09-25 §1). 0004's `channel in ('whatsapp','sms')` check is wider;
 *  only `sms` is ever written. */
export type OtpChannel = "sms";
export interface OtpProvider {
  /** Sends the code by SMS, once; returns the channel that accepted it, or null when it failed.
   *  Never retried on another channel. */
  send(e164: string, code: string): Promise<OtpChannel | null>;
}

/** Records what it would have sent; delivers nothing. Used by `deno test`, local dev, and — until
 *  DLT clears — the hosted dev project (ADR 2026-09-25 §1: "the dev project uses fixed test codes
 *  (`FakeOtpProvider`)"). It must never be wired in a pilot or production project.
 *  ⚠️ Nothing enforces that yet: `liveDeps()` (deps.ts) picks this class for every OTP_PROVIDER
 *  value except `msg91`, unset included, with no guard — so env.ts's `kaleyra | twilio` and the
 *  owner's chosen 2Factor all get it today. It fails closed (the code is random and only its hash
 *  is stored, so no one can sign in), not open. The fixed dev codes and the guard are row OTP2;
 *  the 2Factor provider is OTP3. */
export class FakeOtpProvider implements OtpProvider {
  sent: { e164: string; code: string; channel: OtpChannel }[] = [];
  /** Every send() call, delivered or not — one per request is what "no failover" means. */
  attempts = 0;
  /** The SMS fails: nothing is recorded as sent, and send() answers null. */
  fail = false;
  send(e164: string, code: string): Promise<OtpChannel | null> {
    this.attempts++;
    if (this.fail) return Promise.resolve(null);
    this.sent.push({ e164, code, channel: "sms" });
    return Promise.resolve("sms");
  }
}

/** MSG91-shaped HTTP provider, SMS only: one POST, no second channel (ADR 2026-09-25 §1).
 *  ⚠️ The endpoint and body are unverified against MSG91's current API; the real provider, and the
 *  choice between MSG91 and 2Factor, is row OTP3. Template ids are DLT-registered. */
export class Msg91Provider implements OtpProvider {
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
