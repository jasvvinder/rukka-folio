# ADR 2026-09-05c — Storage: durability, residency, blob integrity, projector versioning, and the plaintext we keep about people

Third review of the day (after 2026-09-05 client hardening and 2026-09-05b sync trust boundaries),
this time of the data model (03). Its spine stands: envelopes are the truth, every table is a
disposable projection, integer paise, client-minted time-ordered ids, one enumerated plaintext
boundary, append-only by grant. The gaps are at the edges 03 had not yet looked at — where the
store lives and how it survives, whether a stored blob is intact, whether two app versions agree,
and what we hold about people who never signed up. Owner confirmed 5 Sep 2026 ("do whatever is best").

## Rulings 🔒

### 1. Residency and durability of the server store
- **Everything lives in India:** Postgres, object storage, backups, logs. Supabase region
  `ap-south-1` (Mumbai) or equivalent; a provider without an Indian region is disqualified.
  Backups never leave the region. Stated once, here and in 03 §6.
- **Point-in-time recovery on** (⚠️ 7 days proposed), **daily encrypted snapshots kept 35 days**,
  monthly kept 12 months. Backups contain ciphertext envelopes plus the plaintext boundary (03 §4),
  so backup access is a privileged, audited path (12) — never the API role.
- **Quarterly restore drill** into an isolated project, measured against a written RTO/RPO
  (⚠️ proposal: RPO ≤ 5 min via PITR, RTO ≤ 4 h). The drill's report is a release artefact from M4.
- **Every restore bumps `store_epoch`** (ADR 2026-09-05b §6) so clients re-pull and re-push lost
  writes. A restore without an epoch bump is a runbook violation.

### 2. Blob integrity hash — corruption is not tampering
Every envelope carries `blob_hash = BLAKE2b-256(blob)` as a **plaintext column**, computed by the
authoring client. The server recomputes on write and refuses a mismatch (`rejected:shape`). Every
reader recomputes on read: hash mismatch → **corruption** — re-fetch (server) or re-bootstrap
(local), `blob_corrupt` telemetry counter, **no security event and no quarantine**; hash intact but
signature failing → **tampering** — quarantine and security event as today (04 §8.3). Without this
column a flipped bit in object storage files an honest author as hostile. The same column verifies
offloaded blobs and gives the local mirror a cheap integrity check. `size` is verified the same way.

### 3. Projector version — determinism across app versions
The projector is pure (03 §3.3), but purity is per implementation. A bug fix changes results, and
then a month close certified on the newer app fails verification on the older, or passes wrongly.
- `core_ledger` exports a `projectorVersion` integer. **Every `period_lock` and `year_close`
  envelope records it** beside the balance-vector hash (02 §8 step 4, §8.1).
- A reader whose projector is **older** than the certifier's does not alarm: it shows *"Update the
  app to verify this close"* and keeps the close as *unverified-by-you*. A reader that is **newer**
  re-verifies with the recorded version if it can reproduce it, otherwise the same message
  inverted for the certifier.
- Any projector change that alters results for any existing envelope set **bumps
  `projectorVersion` and the minimum client version together** (06 §4.5), and the app runs a full
  Recompute on first launch after upgrade. Changes that provably cannot alter results (performance,
  new object types) do not bump. The golden replay (09 suite A) is the proof either way.

### 4. Phone numbers — encrypted at rest, and never kept for people who did not sign up
- `users.phone_e164` becomes **`phone_ct`** (application-level encryption under a server KMS/Vault
  key, needed only to *send* one-time codes) plus **`phone_hmac`** (keyed hash, unique index) for
  lookup. A database dump yields no phone list. The KMS key is the one server-side secret with a
  rotation schedule (⚠️ annual proposed; re-encrypt in place).
- **Invites store no plaintext number.** `invites.phone_e164` → `invitee_hmac` for matching when
  the person arrives; the plaintext goes only into the outbound OTP/WhatsApp message job and is
  gone once sent. Invitees consented to nothing; we hold nothing recoverable about them. Display of
  *whom* an admin invited comes from the admin's own device (the contact card it picked), never
  from the server.
- Display names and photos remain plaintext as 03 §4 says — they are shown in approvals and
  ceremonies and the user chose them for that purpose.

### 5. Server shape checks, enumerated
The server "checks shape" (05 preamble). It checks exactly: `author_device == jwt.device_id` ·
`tenant_id == books.tenant_id` for `book_id` · `blob_hash` and `size` recompute · `suite_version`
and `payload_schema` within the registry · `key_version` ≤ highest issued for the book · HLC
sanity (05 §2) · caps and quotas (05 §3). Nothing else — never content. Failure →
`rejected:shape` with the failing check named; the client treats it as terminal and logs it.

### 6. Local corruption has a path
On every open the client runs SQLCipher `quick_check`. Projection tables corrupt → drop and
Recompute from `envelopes_local` (the user sees the determinate loader, 11 §4.5). Envelope mirror
corrupt (row fails `blob_hash`) → re-bootstrap that book from the server (05 §8); outbox rows are
never dropped without the user seeing them in Inbox. **A book is never shown as whole while any of
its envelopes is missing or unverified** — `books_p.integrity_ok` gates the Home card.

### 7. Row-level security with our own claims
Sessions are challenge-response with our own JWT (06 §4), not the platform's default auth. RLS
policies read **our** `user_id` / `device_id` claims; the per-transaction setting is `SET LOCAL`
so a pooled connection can never carry it across transactions. Suite E gains a test that two
interleaved requests on one pooled connection never see each other's claims.

### 8. Smaller rulings
- **Platform backups excluded.** iOS: the local database and key cache carry the
  excluded-from-backup attribute (the keystore key does not travel, so the copy would be useless
  and would spend the user's iCloud quota). Android: `allowBackup=false`, backup rules empty.
- **Object storage:** private bucket, per-tenant key prefix, write the object *before* the row,
  nightly orphan sweeper for objects whose row never landed, lifecycle rules only for orphans.
- **Audit retention:** `audit_events` 24 months then aggregated; `verification_events` permanent
  (they are the tenant's trust history). `otp_challenges`/`activation_tickets` 24 h as today.
- **`object_id` reuse across amendments** tells the server "this object changed N times". Accepted
  and recorded in 03 §4's footnote; the alternative (fresh ids + encrypted linkage) breaks
  idempotent replacement and is not worth it.

## Declined
- Per-tenant encryption of the plaintext boundary itself — the boundary is already minimal, and
  RLS is the control; KMS-encrypting roles and memberships would break RLS predicates.
- Fresh `object_id` per amendment (see 8).

## What changed where
03 §1 (projector version), §2.1 (`phone_ct`/`phone_hmac`, `invitee_hmac`), §2.3 (`blob_hash`,
shape checks), §2.5 (RLS with our claims, `SET LOCAL`), §3.1 (`blob_hash` local), §3.3 (rule 6:
projector version), §5 (bump rule), §6 (residency, backups, audit retention), §7 tests, §8 open ·
02 §8 step 4 + §8.1 (close records `projector_version`) · 04 §4 plaintext list (phone → encrypted)
· 05 §3 (`rejected:shape`), §8 (re-bootstrap on corruption) · 06 §7 (invites hold no number),
§9.3 (phone erasure = key drop) · 09 suite E · 10 M2/M4 rows.

## Open ⚠️
1. PITR window, snapshot retention, RTO/RPO numbers — confirm against the hosting plan at M4.
2. KMS/Vault choice for the phone key (Supabase Vault vs cloud KMS) and rotation cadence.
3. Whether `projectorVersion` bumps ride the same `min_client_version` route group as crypto/sync
   breaks or get their own — decide at M2 when the registry is written.
