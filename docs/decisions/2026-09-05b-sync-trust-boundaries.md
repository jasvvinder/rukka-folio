# ADR 2026-09-05b — Sync trust boundaries: the server relays, it never rules

Follow-on to ADR 2026-09-05 (client hardening). The owner asked for the same review of the sync
protocol (05). Its core — `seq` cursors, idempotent envelopes, key-sync-before-drain with re-seal,
a content-blind server behind append-only grants, cross-client hash checks at month and year close
— stands. Every gap found is one shape: **05 still trusts the server for things it should only
relay**, and it has no story for a server that lies by omission, forks, or is restored from backup.
Owner confirmed 5 Sep 2026 ("add these as an ADR, do whatever is best").

## Rulings 🔒

### 1. Structural facts are signed records; server rows are their projection
Membership status, per-book roles and limits, designations, device revocation, member removal and
key-rotation notices are authored on a **certified device** and travel as **signed records**:

```
SignedRecord { suite_version, tenant_id, kind, payload_json (plaintext),
               author_device_id, author_sig = Ed25519(BLAKE2b(payload ‖ header)), hlc, seq }
```

Payloads are plaintext because the server must read them for RLS — roles and memberships are
already plaintext (03 §4), so nothing new leaks. The server **applies** each record to
`memberships` / `book_roles` / `devices` on receipt; clients **verify the record** (sig → cert →
ceremony-verified UMK, 04 §3.4) and treat the rows only as the server's copy. Row ≠ record → the
client believes the record and logs `meta_mismatch`. Who may author what follows 06 §1.0 (admin for
roles/limits/removal; any certified device of the same user or k guardians for device revocation,
04 §9.2; any remaining member for rotation, 04 §5.3). The server still enforces the rows at push
and pull — a lie there can only *deny* service, which 04 §1.2 already accepts.

### 2. A device never wipes on the server's word
Local wipe of keys and projections happens only on (a) a **verified** signed revocation or removal
record, or (b) the user's own action. An **unsigned** server assertion of revocation — a 401
`device_revoked`, a bare row — puts the device into **suspended**: syncing stops, ciphertext and
keys stay, the lock screen explains, and the state resolves when a signed record arrives or auth
succeeds again. Fail-safe, never fail-destructive. 04 §9.2's best-effort remote wipe is carried by
the signed record's push notification, not by the notification alone.

### 3. Per-author sequence inside the ciphertext — omission becomes visible
Each device keeps a monotone `author_seq` per book, starting at 1, written **inside the encrypted
payload** (`{author_seq, object}`), so the server can neither see nor alter it. Readers track the
highest contiguous `author_seq` per `(book, author_device)`:
- A gap → the book shows **"waiting for entries from Ramesh's phone"** (status surface, 05 §9);
  the projection is marked *provisional*; **month-close and year-close are blocked** while any gap
  is open (nobody certifies a balance with entries missing). Not an error for 24 h; then Inbox.
- Re-seal (05 §3) preserves the payload byte-for-byte, so `author_seq` survives rotation.
- This is the v1 stand-in for the key-transparency log (04 §11.4) on the content side: a server
  that withholds one reversal is now caught by every reader, not by the next year-close.

### 4. Dangling references are held, not counted
An envelope whose `refs.amends`, `refs.reverses` or decision target is **not present** is placed
in **`held`** — not projected, not quarantined — until the target arrives. If every author's
`author_seq` is contiguous and the target is still absent, the target never existed: quarantine
`target_missing`. The projector stays a pure function of the envelope set (held is part of its
output). This replaces the current M1 behaviour of counting an orphan amendment as a fresh entry,
which double-counts when the original arrives later. 02 §5 amended.

### 5. Revocation cut-off is the server `seq`, never the HLC
An envelope from device D is accepted only if its `seq` is **below the `seq` of D's signed
revocation record** (or of the member's removal). HLC is author-controlled — a stolen phone can
backdate it; `seq` is stamped by the server at receipt and cannot be. Consequence: every stored
envelope carries its `seq` (`envelopes_local` gains the column) and signed records share the same
sequence space as envelopes so the comparison is meaningful. An offline legitimate member's queued
entries are already refused at push (`membership_not_active`); this rule closes the read side.

### 6. Store epoch and read-your-writes
- Every push ack, pull and meta response carries **`store_epoch`** (uuid, changes only when the
  server store is restored or rebuilt). A client seeing a new epoch resets **all** cursors to 0 and
  re-pulls; `envelopes_local` is idempotent so nothing duplicates.
- The outbox gains a state after `acked`: **`observed`** — set when the envelope comes back in
  the device's own pull. The blob is pruned only at `observed`. If the pull cursor passes the
  `seq` returned in the ack and the envelope was not seen, the client **re-pushes** and logs
  `write_lost` as a security event. Cap: 30 days un-observed → Inbox.

### 7. Rate limits and quotas — the server's only new powers
`rejected:rate_limited` (per-device push: ⚠️ proposal 600 envelopes / min and 50 MB / day) →
backoff and retry, never Inbox. `rejected:quota` (per-book envelope count and bytes by plan — 08
owns the numbers ⚠️) → Inbox *"This book is full — upgrade the plan"*, book still readable and
pullable. Membership `blocked` is refused at push exactly like `membership_not_active`. Stated
honestly in 05: garbage pushed before a block is **permanent** (append-only) — readers quarantine
it, quotas bound its cost, and that is the whole defence.

### 8. Smaller rulings
- **Padding.** Plaintext is padded (libsodium `sodium_pad`) to 1 KiB buckets up to 16 KiB, then
  4 KiB steps, before encryption; sizes stop leaking note length or attachment presence.
- **Signed URLs.** Upload URLs: single object, PUT-only, 15 min. Download URLs: 5 min. Leakage
  exposes ciphertext only.
- **Observability without content.** Server metrics are plaintext counters only: rejections by
  type, push/pull latency, cursor lag distribution, `key_wait` age, epoch changes, `write_lost`
  and `meta_mismatch` counts. No per-user log line ever joins an envelope id to a phone number.
- **Deletion job.** The API role has no DELETE grant (03 §2.5). User deletion runs under a separate
  `maintenance` role reachable only from the scheduled function, limited to personal-book
  envelopes and wrapped keys of the erased user, and audited. 03 §2.5 amended.

## Declined / deferred
- Full key-transparency log stays v2 (04 §11.4); ruling 3 is the v1 substitute for content.
- Multiplexed pull stays open (05 §11.5).
- Server-side content validation of any kind — still forbidden (ADR 2026-09-05 § Rejected).

## What changed where
05 §1 (epoch), §3 (push table: `rate_limited`, `quota`; observed state), §4 (`seq` stored, held
refs, gap rule), §5 (signed records; suspended, not wiped), §9 (new status), §10 tests, §11 open
items · 03 §2.5 (rows are projections; maintenance role), §3.1 (`seq`, `observed`, `author_seq`
counters, `held`) · 04 §1.2 (withholding now detected), §9.2 (cut-off by `seq`) · 02 §5 (held) ·
06 §7 (state machine driven by signed records) · 09 §2 suite D additions · 10 M2/M3/M4 rows.
Code: projector `held` state (M2, fixes the M1 orphan-amend behaviour), `author_seq` and padding
in `core_crypto` envelope builder (M3), signed records, epoch, quotas, maintenance role (M4).

## Open ⚠️
1. Rate-limit and quota numbers per plan (08 owner).
2. Whether guardians' k-of-n device revocation (04 §9.2) is a multi-signature record or k separate
   records the client counts — decide at M3 with the Shamir choice.
3. `seq` space for signed records vs envelopes: one `bigserial` for both (simplest, ruling 5
   assumes it) — confirm with the visibility test already open in 05 §11.1.
