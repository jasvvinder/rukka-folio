// OTP delivery behind an interface (06 §2): WhatsApp first, SMS fallback, auto-failover.
// The provider is picked by OTP_PROVIDER at build; the fake is what `deno test` and local dev use.
export type OtpChannel = "whatsapp" | "sms";
export interface OtpProvider {
  /** Sends the code; returns the channel that accepted it, or null when every channel failed. */
  send(e164: string, code: string, preferred: OtpChannel): Promise<OtpChannel | null>;
}

/** Records what it would have sent. Test-only; never wired in a hosted build. */
export class FakeOtpProvider implements OtpProvider {
  sent: { e164: string; code: string; channel: OtpChannel }[] = [];
  failWhatsapp = false;
  failAll = false;
  send(e164: string, code: string, preferred: OtpChannel): Promise<OtpChannel | null> {
    if (this.failAll) return Promise.resolve(null);
    const channel: OtpChannel = preferred === "whatsapp" && this.failWhatsapp ? "sms" : preferred;
    this.sent.push({ e164, code, channel });
    return Promise.resolve(channel);
  }
}

/** MSG91-shaped HTTP provider (⚠️ pick by pricing at build — 06 §2). Template ids are DLT-registered. */
export class Msg91Provider implements OtpProvider {
  constructor(private apiKey: string, private dltEntity: string, private dltTemplate: string) {}
  async send(e164: string, code: string, preferred: OtpChannel): Promise<OtpChannel | null> {
    for (
      const channel of preferred === "whatsapp" ? ["whatsapp", "sms"] as const : ["sms"] as const
    ) {
      try {
        const res = await fetch(
          `https://control.msg91.com/api/v5/${
            channel === "sms" ? "otp" : "whatsapp/whatsapp-outbound-message"
          }`,
          {
            method: "POST",
            headers: { authkey: this.apiKey, "content-type": "application/json" },
            body: JSON.stringify({
              template_id: this.dltTemplate,
              mobile: e164.slice(1),
              otp: code,
              dlt_te_id: this.dltEntity,
            }),
          },
        );
        if (res.ok) return channel;
      } catch {
        // fall through to the next channel; nothing is logged (the body holds the number and the code)
      }
    }
    return null;
  }
}
