# 05 — Sync Protocol

**Status:** Draft 1 for build. 🔒 = locked. ⚠️ = decide before the affected milestone.
**Companions:** 02 (ordering rules & quarantine), 03 (envelope store, projections, cursors), 04 (what the server may see), 06 (sessions, min-version).

**Guarantees 🔒:** delivery is **at-least-once**; envelopes are idempotent by `envelope_id`; therefore application is effectively exactly-once. The server orders *receipt* (`seq`); clients order *meaning* (HLC). The server never validates content — it checks membership, shape, size, and HLC sanity only. Convergence claim: any two clients holding the same envelope set and keys produce byte-identical projections (03 §3.3).

---

## 1. Transport & sessions 🔒

- HTTPS + JSON; auth per 06 §4 (15-min JWT, signed refresh). Every write carries `envelope_id` as the idempotency key — no separate header needed.
- **Min-version gate:** any sync route may answer `426` (06 §4.5); the client stops syncing and shows the update screen. Half-synced state is safe by construction (idempotent, append-only).
- Compression: gzip request/response. Payloads are ciphertext (incompressible); gzip earns its keep on metadata and batching overhead only — don't expect ratio miracles.

## 2. HLC discipline 🔒

- On every local event: `hlc = max(wall_ms, last_hlc.physical) , counter++ if equal`. Tiebreak `device_id` (03 §1).
- **Server sanity check (plaintext, allowed):** reject any envelope whose HLC physical part exceeds `server_now + 5 min` → `hlc_future`. The client re-stamps (new envelope_id, same object) and marks its clock skewed. This exists so a wrong-clock phone cannot stamp entries "after" a period lock it has already seen (02 §8 depends on honest-ish HLCs; readers still quarantine independently).
- Clients also clamp: if wall clock < last seen HLC by > 24 h, warn the user (*"Phone date looks wrong"*) and keep issuing monotone HLCs.

## 3. Push — the outbox 🔒

- Source: `outbox` (03 §3.1), per-book FIFO in local creation order. Batch ≤ 100 envelopes or 1 MB.

**Key-sync precedes outbox drain 🔒 (ordering rule):** on **every** reconnect — not only bootstrap (§8) — the client completes the meta/key channel (§5) for a book **before** pushing that book's outbox. This is what makes the next rule possible.

**Re-seal before push 🔒 — the long-offline case.** A device offline across a key rotation (04 §5.3) holds queued envelopes sealed under a superseded `BK(v)`. It cannot have learned of the rotation while offline, so it must fix them on the way back:

> For each queued envelope whose `key_version` is below the highest version the client now holds for that book: **decrypt with `BK(v)` (still in `key_cache`, which retains all versions), re-encrypt the identical plaintext under the highest `BK`, recompute the AAD and re-sign.** Preserve `envelope_id`, `object_id`, `hlc` and payload **byte-for-byte** — only `key_version`, `nonce`, `ciphertext` and `author_sig` change.

Preserving `envelope_id` keeps idempotency intact: if the pre-rotation copy did land inside the grace window, the server dedupes and the re-sealed copy is a no-op. Preserving `hlc` keeps ordering and the Late Arrivals rule (02 §8) unchanged — re-sealing is a **re-wrapping, not a re-authoring**, and must never alter what the entry means. This is not an append-only violation: an envelope in the outbox has never been stored, so nothing is being mutated.

A device that cannot unwrap the new `BK` is not a member any more; it will receive `membership_not_active` and follow that row instead.
- `POST /sync/push {envelopes[]}` → per-envelope result:

| result | meaning | client action |
|---|---|---|
| `acked` | stored (or duplicate — same thing) | mark acked; prune |
| `rejected:no_role` / `membership_not_active` | not authorized for this book *now* | move to Inbox ("couldn't send — ask your admin"), stop pushing that book |
| `rejected:unknown_book` | book archived/deleted | Inbox, guided resolution |
| `rejected:hlc_future` | §2 | re-stamp, retry |
| `rejected:too_large` | > size cap | shrink attachment / split ⚠️ cap: 256 KB/envelope |
| `rejected:key_version_stale` | envelope sealed under a `BK` version superseded > 48 h ago (04 §5.3) | **not terminal:** run the re-seal above, retry **once**; if it fails again (new `BK` unavailable), surface in Inbox as *"couldn't send — waiting for a new key"* |
| `rejected:version` | payload_schema above server registry | force-update path |

- The server **never** rejects on content — a hostile client's unbalanced entry is stored and then quarantined by every honest reader (02 §11). This keeps the server dumb and the trust model clean.
- Retry: exponential backoff with jitter (1 s → 2 → 4 → … cap 10 min), reset on connectivity change. Rejections are terminal per envelope — no blind retry loops. **The one exception is `key_version_stale`**, which permits exactly one re-seal-and-retry (bounded, so it cannot loop).

## 4. Pull — server-sequence cursors 🔒

**The subtle rule that prevents silent data loss:** cursors run on the server-assigned **`seq`** (global `bigserial` stamped at receipt), *never* on HLC. A device offline for a month uploads envelopes whose HLCs are weeks old; an HLC cursor on other clients would already be past them and skip them forever. `seq` is monotone by receipt, so nothing is skippable.

- `GET /sync/pull?book_id=&after_seq=&limit=500` → ordered page + `next_seq`. Gap-free under concurrent writers because `seq` insertion is serialized per the DB sequence and the read is `where seq > $after order by seq` — an envelope is visible to pulls only after commit. ⚠️ Verify with an interleaved-commit test; if the chosen Postgres setup can expose out-of-order visibility, switch to a per-book counter assigned in a serialized txn.
- Per-book cursor rows: `sync_cursors(book_id, last_seq)` (03 amended). Pull all books round-robin, active-scope book first.
- **Applying pulls:** decrypt, verify signature chain (04 §8.3), store in `envelopes_local`, then project. If the envelope's HLC ≥ the book's applied-HLC watermark → apply incrementally. If **lower** (a late arrival), mark the book dirty and **replay** the projection from the latest certified year vector (03 §3.3.3) — cheap because the replay window is at most one FY, and correctness beats cleverness here. (This replay is the mechanical twin of the *Late Arrivals tray*: 02 §8 governs what humans see; this section governs what the math does.)
- Undecryptable envelopes (key not yet arrived) queue in `key_wait`; retried whenever §5 delivers keys. Not an error state for 24 h; after that, surface in Inbox.

## 5. Metadata & key sync 🔒

Separate channel from envelopes, `GET /sync/meta?after=cursor` (cursor = `updated_at,id` on each table): memberships, book_roles, devices+certs, wrapped_keys, invites, verification_events, subscriptions, escrow/recovery states, tombstones.

- New `wrapped_keys` → unwrap, refresh `key_cache`, drain `key_wait`.
- Revocations: own-device revoked → local wipe (best-effort; also triggered by push notification and by next auth failure); membership removed → drop that book's keys and projections, keep nothing but the row saying it existed.
- Key-rotation notices (04 §5.3): client learns `BK(v+1)` exists; new outbox envelopes must use the highest version — a client still writing `v` after the 48 h grace gets reader-side quarantine, so the client hard-checks version on every save. **Envelopes already queued under `v` are not lost:** because this channel drains before the outbox does (§3 ordering rule), they are re-sealed under the highest version and pushed unchanged in every other respect.

## 6. Attachments 🔒

1. Entry saves instantly; `attachment_meta` envelope carries the file hash + wrapped file key; the ciphertext file (and its pre-generated ciphertext thumbnail) upload afterward via signed URLs, resumable, Wi-Fi-preferred setting ⚠️ default on/off.
2. States on the entry detail: `uploading / uploaded / waiting for Wi-Fi / failed (retry)`. Never blocks the ledger.
3. Download lazily: thumbnails prefetched per current scope; full images on tap; LRU cache cap ⚠️ size.

## 7. Triggers & cadence 🔒

Content-free FCM (*"book X has news"*) → pull that book; foreground pull on app open and scope switch; backstop poll every 6 h on unmetered networks. FCM is a hint, never a dependency — correctness comes from cursors alone.

## 8. Bootstrap (fresh install / post-recovery) 🔒

Order: profile+meta+keys (§5) → per book: `book_config`, `account`, `rule` objects (all-time; low volume) + latest `year_close` vector + all envelopes of the **open FY** (hot set) → project → app usable. Closed FYs fetch on demand (`?fy=2024-25`) behind the same pull API from warm or cold storage (03 §6) — opening a 3-year-old statement shows a one-time *"fetching old year…"* spinner, everything else is instant.

## 9. Status surface (feeds 07 §1.7) 🔒

`Synced ✓` (outbox empty, cursors fresh) · `Saved on phone · will sync (N)` · `Offline` · `Needs attention` → Inbox (rejections, quarantines, key_wait > 24 h, clock warning). No other states; no spinners on entry save, ever.

---

## 10. Acceptance tests (excerpt)

- **30-day offline device** syncs 400 queued entries: all acked once, every other device converges to identical balance hashes, and each affected locked month shows them in Late Arrivals — none silently posted, none lost.
- **Rotation across the offline window (04 §5.3 × §3):** a device goes offline; on day 2 a member is removed and every book rotates to `BK(v+1)`; the device reconnects on day 30 with 400 queued envelopes sealed under `BK(v)`. **Then:** key sync completes first, all 400 are re-sealed under `BK(v+1)`, all are acked, `envelope_id`/`object_id`/`hlc`/payload are byte-identical to the pre-seal versions, every reader verifies the new signatures, balance hashes converge — and **zero envelopes remain readable under `BK(v)`**.
- **Grace-window race:** an envelope pushed under `BK(v)` within 48 h of rotation is accepted; the same envelope pushed at 48 h + 1 min returns `key_version_stale`, is re-sealed and accepted on the single permitted retry, yielding one stored row, not two.
- **Interleaved writers:** two devices entering into one book while both online converge to identical projections regardless of push order.
- **Late lower-HLC envelope** triggers FY replay and the resulting projection equals a from-scratch rebuild.
- **Cursor gap test:** concurrent pushes during a paginated pull never yield a skipped `seq` (fuzzed, 10k iterations).
- **Duplicate push** of a batch (network retry after lost ack) results in zero new rows and `acked` for all.
- **hlc_future:** a device with clock +2 days gets rejections, re-stamps, succeeds, and its user sees the clock warning.
- **Key-later:** envelopes pulled before their BK arrives decrypt automatically once §5 delivers it; nothing surfaces to the user under 24 h.
- **Removed member's device** gets `membership_not_active` on push, loses keys via §5, and its local shared-book projections are gone after wipe handling.
- **Attachment resume:** an upload interrupted at 60% resumes, and the file hash verifies end-to-end.

## 11. Open items ⚠️
1. `seq` visibility under concurrency: bigserial + commit-visibility test vs per-book serialized counter (§4). 2. Envelope size cap (256 KB proposed) and blob-offload threshold alignment with 03 §8.1. 3. Attachment Wi-Fi default and cache cap. 4. Backstop poll interval on metered connections. 5. Whether pull should be multiplexed (one call, many books) at v1 or later.
