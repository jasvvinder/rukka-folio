// Small HTTP helpers. Every response is JSON; 426 is the min-version gate (06 §4.5, 05 §1).
export const CLIENT_VERSION_HEADER = "x-rukka-client-version";

export function json(status: number, body: unknown, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...extra },
  });
}
export function error(status: number, code: string, detail?: string): Response {
  return json(status, detail ? { error: code, detail } : { error: code });
}
export async function readJson(req: Request, maxBytes: number): Promise<unknown | null> {
  const len = Number(req.headers.get("content-length") ?? "0");
  if (len > maxBytes) return null;
  const text = await req.text();
  if (text.length > maxBytes) return null;
  try {
    return parseJsonBig(text);
  } catch {
    return null;
  }
}
/**
 * JSON.parse that keeps integers beyond 2^53 exact: an HLC is 48-bit ms ‖ 16-bit counter and
 * arrives as a bare integer literal (wire.dart `int`). The reviver's `context.source` (V8) hands
 * back the literal text, which parseBigint() then reads. Safe integers stay numbers.
 */
export function parseJsonBig(text: string): unknown {
  type Reviver = (
    this: unknown,
    key: string,
    value: unknown,
    context?: { source?: string },
  ) => unknown;
  const reviver: Reviver = function (_k, v, ctx) {
    if (
      typeof v === "number" && !Number.isSafeInteger(v) && ctx?.source && /^-?\d+$/.test(ctx.source)
    ) return ctx.source;
    return v;
  };
  return JSON.parse(text, reviver as (key: string, value: unknown) => unknown);
}
/** Returns a 426 response when the client is below the route group's minimum, else null. */
export function minVersionGate(
  req: Request,
  minVersion: string,
  below: (c: string | null, m: string) => boolean,
): Response | null {
  const v = req.headers.get(CLIENT_VERSION_HEADER);
  return below(v, minVersion)
    ? json(426, { error: "upgrade_required", min_client_version: minVersion })
    : null;
}
export function subPath(req: Request, fnName: string): string {
  const p = new URL(req.url).pathname;
  const i = p.indexOf(`/${fnName}`);
  const rest = i >= 0 ? p.slice(i + fnName.length + 1) : p;
  return rest.replace(/\/+$/, "") || "/";
}
export function clientIp(req: Request): string {
  return (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "0.0.0.0";
}
