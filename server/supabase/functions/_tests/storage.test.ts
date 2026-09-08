// E-05b-8 (ADR 2026-09-05b §8): signed-URL lifetimes — upload PUT-only, single object, 15 min; download 5 min.
// The live check (a GET on an upload URL is refused, a request at 15 min + 1 s is refused) needs the
// hosted bucket and runs in the nightly lane; this pins the parameters every minting call must use.
import { assertEquals, assertMatch } from "@std/assert";
import {
  ATTACHMENT_MAX_BYTES,
  ATTACHMENTS_BUCKET,
  DOWNLOAD_URL_TTL_S,
  objectKey,
  UPLOAD_URL_TTL_S,
  uploadSpec,
} from "../_shared/storage.ts";

Deno.test("E-05b-8 signed-URL parameters: PUT-only, single object under the tenant prefix, 15 min up / 5 min down", () => {
  assertEquals(UPLOAD_URL_TTL_S, 15 * 60);
  assertEquals(DOWNLOAD_URL_TTL_S, 5 * 60);
  assertEquals(ATTACHMENT_MAX_BYTES, 10 * 1024 * 1024);
  assertEquals(ATTACHMENTS_BUCKET, "attachments");
  const t = "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f",
    b = "1a1a1a1a-1a1a-4a1a-8a1a-1a1a1a1a1a1a",
    a = "2b2b2b2b-2b2b-4b2b-8b2b-2b2b2b2b2b2b";
  const spec = uploadSpec(t, b, a);
  assertEquals(spec.method, "PUT");
  assertEquals(spec.expires_in_s, 900);
  assertEquals(spec.key, objectKey(t, b, a));
  assertMatch(
    spec.key,
    new RegExp(`^${t}/${b}/${a}$`),
    "one object, per-tenant prefix (ADR 05c §8)",
  );
});
