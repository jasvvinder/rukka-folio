# ADR 2026-09-16 — One device, one id: the ledger mints `device_id` at first run and the server records it

**Status: Proposed — escalation authorised by the owner in session, 16 Sep 2026 ("fix the device-ID
bug").** Ruled at the escalation tier because the fix touches a 🔒 line of the identity spec (06 §3
step 2) and the trust chain of 04 §3.4. **No numbered spec is edited by this ADR**: the exact edits
to 06 §3 and 04 §3.3/§3.4 are named in § Consequences for the owner to apply on ratification. The
client half is implemented in the same commit; the server half is specified in §6 and left for a
`lane-server` run.

Raised because one phone carries **two** device ids. `LocalLedger` mints one at first launch and
stamps every envelope with it; `HttpAuthClient` adopts a second one from the server at
registration and the signed-record author signs under *that*. Every other device resolves an
author's certificate by the id on the envelope, so every envelope this phone will ever author is
quarantined `certMissing` by every reader — and a revocation counted against one id never covers
the other.

## The evidence ⟦tests: n/a — findings, not behaviour⟧

Every row was read in session on 16 Sep 2026 at the line named, not recalled (CLAUDE.md rule 11).

| Source | What it says | Consequence |
|---|---|---|
| `app/lib/shared/ledger/local_ledger.dart:619` (`_firstRun`) | `final deviceId = newId();` — a v4 uuid from libsodium's CSPRNG; the device key pair is built **with this id baked in** (`_deviceFromSeeds(deviceId, …)` line 628); the UMK is wrapped to it (`WrappedUmk(deviceId: …)` line 685) | the id exists before the network does |
| `app/lib/shared/ledger/local_ledger.dart:1516-1539` | `mirror.nextAuthorSeq(bookId, id.deviceId)`, `authorDevice: id.deviceId`, `EnvelopeBuilder.seal(… author: device)` | **every envelope carries the ledger id** as `author_device_id`, and its per-author `seq` (ADR 2026-09-05b §3) counts under it |
| `app/lib/bootstrap.dart:196-239` | `auth.restore()` runs first, then `ledger.bootstrapSolo()` — at **every** launch, before any screen, before OTP | the ledger identity is minted on first launch; onboarding creates the first book and its opening balances under it before the user has ever signed in |
| `app/lib/features/auth/http_auth_client.dart:425-429` | `final deviceId = body['device_id']; … await _writeText(SessionItems.deviceId, deviceId);` — the id the server returned from `POST /devices` | the auth session, the challenge signature and `SessionItems.deviceId` hold the **server's** id |
| `app/lib/features/auth/http_auth_client.dart:609-635` (`_deviceKeys`) and `local_ledger.dart:715` (`_deviceFromSeeds`) | both derive the key pair from the **same** seeds, `KeyIds.deviceSigningKey` / `KeyIds.deviceAgreementKey` | it is **one key pair under two names**, not two devices |
| `app/lib/bootstrap.dart:258` vs `:329` | `DeviceRecordAuthor.ifAvailable(deviceIdOf: … SessionItems.deviceId …)` vs `SyncEngine(deviceId: identity.deviceId, …)` | signed records go out under the server id; envelopes under the ledger id |
| `server/supabase/migrations/0005_rls_and_grants.sql:151-152` and `0002_devices_keys_ceremonies.sql:3` | `insert into devices (user_id, pub_ed, pub_x, …) returning id`; `id uuid primary key default gen_random_uuid()` | the server mints; the client's id is never sent, never known to the server |
| `server/supabase/functions/auth-challenge/index.ts:200-215, 259` | first-device self-certification runs over `uuid16(c.device_id)` with `c.device_id = reg.device_id` — the **server's** id | the certificate the server will ever accept is over an id no envelope carries |
| `packages/core_crypto/lib/src/verify_chain.dart:164-170` | `trust.certOf(authorDeviceId)` → `certMissing`; `cert.deviceId != authorDeviceId` → `certInvalid` | a cert over id S can never vouch for an envelope under id L, and the check is deliberate (B-04-40) |
| `packages/core_crypto/lib/src/device_cert.dart:74-82` | signed bytes are `uuid16(device_id) ‖ pub_ed ‖ pub_x ‖ i64be(issued_at)` — 04 §3.4 🔒 order | the id is **inside the signature**; a cert cannot be relabelled after issue |
| `packages/core_crypto/lib/src/verify_chain.dart:184-186` | `trust.revocationSeqOf(authorDeviceId)` | a revocation of id S leaves envelopes under id L accepted for ever (ADR 2026-09-05b §5 cut-off never applies) |
| `04 §3.4` line 86 | *"At signup, the first device holds the UMK and **self-certifies**: `cert = Sign_UMK_ed(device_id ‖ …)`"* | the first device certifies **itself**, and it can only sign an id it already has |
| `06 §3` step 2, line 76 | *"`POST /devices` … → server issues `device_id`"* | the line this ADR supersedes |
| `06 §5` rows *Fresh signup*, *Reinstall, same iPhone* | signup: *OTP → §3 → UMK + self-cert*; iOS reinstall: *keys found → normal device, no recovery* | a Keychain-remnant device re-registers with the **same** keys; today that mints a second server row for one key pair |
| CLAUDE.md rule 2, 02 §5 | append-only — an envelope is never rewritten | an envelope already authored under id L can never be re-stamped with id S |
| `app/lib/features/auth/http_auth_client.dart:302-306` | `certifyDevice()` throws `UnimplementedError` — the app issues **no** `DeviceCert` today (`grep DeviceCert app/lib` is empty) | the cert-upload stub is where the ruling meets the wire next; it is out of this escalation's scope and is named in § Open |

## The tension, weighed ⟦tests: n/a — reasoning, not behaviour⟧

06 owns identity, so 06 §3's *"server issues `device_id`"* is where the reading starts (CLAUDE.md
§ Precedence 2b). Three shapes were costed against CLAUDE.md rule 2 (append-only) and 00's
offline-first before one was kept:

| Option | Rule 2 (append-only) | Offline-first / 04 §3.4 self-cert | Server trust | Cost |
|---|---|---|---|---|
| **A. The client mints; `POST /devices` carries it; the server records it or refuses** | ✓ nothing is ever rewritten | ✓ the id exists at first launch; the self-cert is over the id envelopes carry | unchanged — the server already trusts nothing about device identity except the key that signs the challenge (04 §3.4: *"Nothing rests on the server"*); the id is a label, uniqueness is the primary key | one migration, one route field, one 409 code |
| B. The ledger adopts the server id at registration | ✗ every envelope authored before registration — the first book, its opening balances, every offline entry — is stranded under an id no cert will ever name; a second identity for the same books | ✗ an offline first run has no server; a Keychain remnant would take a *new* id for the *same* keys | — | re-wrap the UMK, rewrite `rk.ledger.identity`, and still lose rule 2 |
| C. Two ids per device with a cert-side mapping (*"this cert also vouches for prior id L"*) | ✓ | ✓ | ✗ the id is inside the 04 §3.4 🔒 signature, so the mapping means a new cert format, a new verifier branch, a revocation that must cover a **set** of ids (05b §5), and a second id space on the meta channel — for ever, for every reader | the largest change, to buy nothing A does not |

A survives; B fails rule 2 outright; C pays the most to preserve a server convenience the specs
say the server must never be trusted for. The one thing 06 §3 step 2 actually needs from the
server — *uniqueness* — is exactly what a primary key gives.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. A device has exactly one id, minted once by the ledger at first run ⟦tests: F1-05-49, F1-05-50, F1-03-1⟧
`device_id` is the canonical v4 uuid `LocalLedger._firstRun` mints from the injected suite's CSPRNG
(rule 7) and stores in `rk.ledger.identity`. It is baked into the device key pair, the self-verified
device, the wrapped UMK, every envelope's `author_device_id` and per-author `seq`, every signed
record's `author_device_id`, the challenge signature of 06 §4 and the device certificate of 04 §3.4.
No other component mints, derives or adopts a device id. The **only** reader of the id outside the
ledger is `readStoredIdentity(keys)` over the same key store (`app/lib/shared/ledger/ledger_identity.dart`).

### 2. `POST /devices` carries the id; the server records it or refuses — it never issues one ⟦tests: C-06-24, E-06-40 @M7, E-06-41 @M7⟧
The registration body gains a required `device_id` (canonical uuid). The server inserts the row
**with that id**, echoes it, and refuses with `409 device_id_taken` when the id already exists
under a different key pair or user. When the id exists under the **same** user **and** the same
`pub_ed`/`pub_x` and is not revoked, registration is idempotent: the existing row is returned, no
second row is created and the device cap is not charged — this is 06 §5's *Reinstall, same
iPhone* and *sign-out then sign-in* on one phone, which today mints a second server device for one
key pair. `devices.id` loses its default: the server has no code path that mints a device id.

### 3. The client never adopts a different id; a disagreeing server fails closed ⟦tests: C-06-25, C-06-26⟧
`HttpAuthClient.activateDevice` reads the id through the injected source (default:
`readStoredIdentity` over its key store) **before** any request. No identity → `NoDeviceIdentity`
is thrown and nothing is sent — the ledger is bootstrapped before any screen (`bootstrap.dart:239`),
so this is an ordering bug surfaced, never a state to mint around. A `200` whose `device_id` is not
the one sent, and a `409 device_id_taken`, both surface as `AuthFailure(unavailable)` with the
fixed log events `device_id_mismatch` / `device_id_taken`; no session opens and nothing is written
to the key store. `409 device_cap` keeps its own `DeviceCapReached`.

### 4. A stored session under any other id is not restored ⟦tests: C-06-27⟧
`restore()` compares `rk.device.id` with the ledger identity when both exist; on disagreement it
logs `device_id_stale` and leaves the client `SignedOut` so the next activation registers the one
true id. Nothing is deleted (ADR 2026-09-05b §2 — a wipe needs a signed record; this is not one).
This is the migration path for every pre-ratification dev install; there are no production
installs.

### 5. Nothing is rewritten — envelopes authored before registration are covered ⟦tests: F1-05-50, B-04-92⟧
Because the id never changes, the first device's self-certificate (04 §3.4) vouches for every
envelope the device authored **before** it ever reached the server — the offline first book, its
opening balances, every entry made before sign-in — and a revocation of the id (ADR 2026-09-05b
§5) covers all of them from its `seq`. B-04-92 pins the fact that makes this necessary rather than
convenient: one key pair sealing under two ids is two devices to every verifier — the cert for one
never vouches for the other and a revocation of one never reaches the other.

### 6. The server change, specified for `lane-server` ⟦tests: E-06-40 @M7, E-06-41 @M7, E-06-42 @M7⟧
Not implemented here — `server/` is another lane's directory. Everything a `lane-server` run needs:

**Migration `0009_client_minted_device_id.sql`**
- `alter table devices alter column id drop default;` — structural: no server path mints an id.
- Replace `rf.register_device(p_user uuid, p_pub_ed bytea, p_pub_x bytea, p_model text, p_os text, p_attestation jsonb)` with the same name **plus a leading `p_device uuid`** (drop the old
  6-argument overload so a stale caller fails at bind time, not silently). Body, in order:
  1. `select … from devices where id = p_device` — if a row exists: when `user_id = p_user and
     pub_ed = p_pub_ed and pub_x = p_pub_x and status <> 'revoked'` → `return p_device` (idempotent,
     no cap check, no insert); otherwise `raise exception 'device_id_taken'`.
  2. Otherwise the existing cap check (`rf.device_cap`), then
     `insert into devices (id, user_id, pub_ed, pub_x, model, os, attestation) values (p_device, …)`.
     A concurrent duplicate surfaces as `unique_violation` on the primary key → re-raise as
     `device_id_taken`.
- `rf.device_auth_row`, the challenge/token/refresh functions and every RLS policy are unchanged.

**Edge function `auth-challenge` `POST /devices`** (`index.ts` `registerDevice`, header line 4)
- Body gains `device_id` — required, `isUuid` (the same check `/challenge` applies at line 274);
  missing or malformed → `400 bad_request` **before** the ticket is consumed.
- `Store.registerDevice(device, user, pubEd, pubX, model, os, attestation)` in `store.ts`,
  `store_pg.ts` (passes `${device}::uuid` first) and `store_mem.ts` (implements the same
  idempotent-or-taken rule over its map, and throws a new `DeviceIdTakenError` beside
  `DeviceCapError`).
- `DeviceIdTakenError` → `409 { "error": "device_id_taken" }`; `device_cap` keeps `409
  { "error": "device_cap" }`. The two must stay distinguishable by `error`, not by status — the
  client branches on the string (§3).
- The response `device_id` is the request's; `certifyWith` in the same call (first-device self-cert,
  line 200-213) therefore verifies over the id the client's certificate was issued for.

**RLS consequence** — none by construction, stated so it is tested rather than assumed: the JWT's
`device_id` claim is issued by `/token` from the row whose `pub_ed` verified the signed challenge
(`rf.device_auth_row`), never from anything the client says about itself, so a client-chosen id
buys no read beyond its own row under ADR 2026-09-05d §2. What **is** now security-relevant is the
primary key on `devices.id`: it is the only thing that stops one device from registering under
another's id. E-06-42 asserts both halves as hostile queries — a device registered with a chosen id
still sees only its own row, and an `insert` of a duplicate id as the server role fails.

**Tests to write** (server suite, planned here per ADR 2026-09-08): **E-06-40** the client's
`device_id` is recorded and echoed; missing / non-uuid → 400 and the ticket survives. **E-06-41**
an id held by another user or another key pair → 409 `device_id_taken`, no row, ticket consumed;
the same user + same keys → 200, the same row, no second row, the cap not charged. **E-06-42** the
RLS assertions above.

## Declined
- **A `pub_ed` uniqueness constraint on `devices`.** It would make the same-keys/different-id state
  (a pre-ratification dev install re-activating) a hard error instead of a second row. Not required
  by the ruling — a stale second row can neither sign a challenge nor be certified, because the
  device's certificate names one id — and it would forbid a legitimate key-reuse pattern no spec
  currently rules on. Revisit if 06 §6 device management wants "one row per key".
- **Skipping any existing test.** C-06-9 and C-06-12 assert what the client sends and signs, never
  where the id came from; with the fixture seeding a ledger identity whose id the scripted server
  echoes, every existing assertion holds unchanged. No test was green against the superseded line,
  so ADR 2026-09-05i §4 produces no `@Skip`.

## Consequences

Edits for the owner to apply on ratification (this ADR edits no numbered spec):

- **06 §3 step 2** (line 76) — replace *"→ server issues `device_id` and stores the record"* with:
  *"→ with the device's own `device_id` (minted once by the ledger at first run, ADR 2026-09-16 §1);
  the server **records** it — `409 device_id_taken` if another key pair holds it, idempotent for
  the same user and keys — and never issues one."* Append `C-06-24, C-06-25, C-06-26, C-06-27,
  E-06-40 @M7, E-06-41 @M7, E-06-42 @M7` to the §3 marker.
- **06 §5** row *Reinstall, same iPhone* — append: *"re-registration carries the same `device_id`
  and the same keys and is idempotent on the server (ADR 2026-09-16 §2)."*
- **04 §3.3** — append one sentence: *"The device's id is minted by the ledger at first run and is
  the one id the key pair, the certificate, every envelope and every signed record carry (ADR
  2026-09-16 §1)."* Append `F1-05-49, F1-05-50` to the §3.3 marker.
- **04 §3.4** first bullet — no wording change; append `B-04-92` to the marker (the cert binds one
  id; it is why the ids must be one).
- **`app/lib/bootstrap.dart`** (not this lane's directory) — `storedIdentity()` at line 145 now
  duplicates `readStoredIdentity()` from `shared/ledger/ledger_identity.dart`; a wiring lane should
  delete the copy. `DeviceRecordAuthor.ifAvailable(deviceIdOf: …)` may keep reading
  `SessionItems.deviceId` — after this ADR it holds the ledger id — or read the ledger identity
  directly; either is the one id.
- **CHANGELOG** (owner/orchestrator) — Decided: *"ADR 2026-09-16 (proposed): one device, one id —
  the ledger mints `device_id`, `POST /devices` carries it, the server records it or refuses."*

## Open ⚠️
- **`user_id` and `tenant_id` have the same split, unruled here.** Verified: `local_ledger.dart:620-621`
  mints both at first run; `http_auth_client.dart:370` and `:432` store the **server's** `user_id`
  under `SessionItems.userId`; `bootstrap.dart:329-331` hands the ledger's ids to the sync engine
  and to `ServerMembersRepository(userId: identity.userId)`. The device-id ruling does not settle
  these because a user spans devices — a linked device cannot mint the user's id, it must learn it
  (the ceremony `QrPayload` already carries `userId`, `local_ledger.dart:755`). Needs its own
  ruling before M7's members/sync integration is trusted end to end; the shape is likely
  *"the first device mints `user_id` and `tenant_id`; `otp/verify` at signup accepts them"*, but
  that is not verified and is not decided here.
- **The first-device certificate is still never issued or uploaded** (`certifyDevice()` stub,
  `http_auth_client.dart:302`). Until the ceremony lane lands it, every device is `certMissing` to
  every other regardless of this ADR. When it lands, the cert is `DeviceCert.issue(…, device:
  ledger.keyMaterial.device.public, …)` — the id is then the right one by construction.
- `DeviceKeyPair.fromSeeds` in `core_crypto` would delete the two seed-replay copies
  (`local_ledger.dart:715`, `device_record_author.dart:172`); not done here — adjacent, not the blocker.
