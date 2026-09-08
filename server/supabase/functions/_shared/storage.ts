// Attachment object storage (05 §6; ADR 2026-09-05b §8; ADR 2026-09-05c §8): private bucket,
// per-tenant key prefix, signed URLs — upload PUT-only / single object / 15 min, download 5 min.
// The URL minting itself goes through Supabase Storage's signed-URL API at M7 (attachments lane);
// these are the parameters every caller must use, asserted by E-05b-8.
export const ATTACHMENTS_BUCKET = "attachments";
export const UPLOAD_URL_TTL_S = 15 * 60;
export const DOWNLOAD_URL_TTL_S = 5 * 60;
export const ATTACHMENT_MAX_BYTES = 10 * 1024 * 1024; // 08 §2

export interface SignedUploadSpec {
  bucket: string;
  key: string;
  method: "PUT";
  expires_in_s: number;
}
/** `<tenant_id>/<book_id>/<attachment_id>` — the per-tenant prefix RLS and the orphan sweeper rely on. */
export function objectKey(tenantId: string, bookId: string, attachmentId: string): string {
  return `${tenantId}/${bookId}/${attachmentId}`;
}
export function uploadSpec(
  tenantId: string,
  bookId: string,
  attachmentId: string,
): SignedUploadSpec {
  return {
    bucket: ATTACHMENTS_BUCKET,
    key: objectKey(tenantId, bookId, attachmentId),
    method: "PUT",
    expires_in_s: UPLOAD_URL_TTL_S,
  };
}
