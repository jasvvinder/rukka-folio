# ADR 2026-10-04b — The first device mints `user_id` and `tenant_id`; the server records them or refuses (desk 107)

**Status: shape ruled by the owner, 4 Oct 2026** (*"Client mints"* — desk 107, ADR 2026-09-16 § Open
first bullet). §1 is that ruling. §2–§4 are the consequences the ruling forces, read from the code on
4 Oct; the owner **confirmed** them on 4 Oct 2026 (*"Confirm §2–§4"*). Resolves
ADR 2026-09-16 § Open, first bullet.

One install carries two user ids today. `LocalLedger._firstRun` mints `userId` and `tenantId` at first
launch (`app/lib/shared/ledger/local_ledger.dart:2061-2062`), before OTP; `POST /otp/verify` creates a
**separate** server user (`server/supabase/functions/auth-challenge/index.ts:168-169`,
`signupUser(hmac, …)`, `users.id default gen_random_uuid()` at `0001:27`) and the client files it apart
under `SessionItems.userId`. Bootstrap hands the ledger's ids to the sync engine and every repository,
while the engine files `guardian_sets` by the wire's server-minted `subject_user_id`
(`packages/sync_engine/lib/src/engine.dart:623-635`): the S11 guardians row (desk 103) never finds a
set, `_ownCount` (`engine.dart:747`) has the same blind spot, and S11.1 publishes under a tenant id
the server never registered.

## Why the client's id, not the server's ⟦tests: n/a — reasoning, not behaviour⟧

The user id is inside signed and encrypted content, exactly as the device id was (ADR 2026-09-16
§ The tension, option B): every entry carries `createdByUser` / `byUser`
(`local_ledger.dart:2873`, `:3117`, `:3389` …), the ceremony `QrPayload` signs a canonical `userId`
(`packages/core_crypto/lib/src/ceremony.dart:55-61`), and a device certificate is checked against
`identity.userId` (`local_ledger.dart:1955`, `:2014`). Adopting a server id after the fact would mean
rewriting identity under content already sealed: a CLAUDE.md rule 2 violation. Recording the client's
id costs one request field and one refusal code, and is already the device-id shape (`/devices`
records the ledger's `device_id` or answers `409 device_id_taken`, `auth-challenge/index.ts:7-11`,
`:217-222`).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The first device of a new account mints `user_id`; signup records it or refuses ⟦tests: E-04b-1, E-04b-2, E-04b-3, E-04b-4, C-04b-1⟧
- `POST /otp/verify` takes an optional `user_id` (canonical uuid). When the phone has **no** user,
  the server creates the `users` row **with that id**; when the id is already held by another user it
  answers `409 {error: user_id_taken}` and creates nothing. A malformed id is `400 bad_request`.
- The server never mints a user id for a request that carried one. A request without `user_id` keeps
  today's behaviour, so an older client still signs up. ⟦tests: E-04b-1, E-04b-3, E-04b-4⟧
- The proposal is honoured **only** where the server would otherwise call `signupUser`. A phone that
  already has an account answers with **its** user id and ignores the proposal (§3). No other purpose
  (device activation, phone change, deletion) ever changes a user's id. ⟦tests: E-04b-2⟧
- The client sends `identity.userId` and, on a 200, checks that the echoed `user_id` equals it before
  it stores anything under `SessionItems.userId`. ⟦tests: C-04b-1⟧

### 2. The first-run identity is provisional until signup answers ⟦tests: C-04b-2, C-04b-3⟧ — owner-confirmed 4 Oct 2026
- `_firstRun` mints the device id, user id, tenant id, device keys and a UMK before the network is
  reached (`local_ledger.dart:2059-2092`). Until `/otp/verify` has answered with that same `user_id`,
  the install **authors nothing** under them: no envelope, no signed record, no book key, no device
  certificate, no UMK public key uploaded. ⟦tests: C-04b-2⟧
- Verified for today: `bootstrap.dart:372` calls `bootstrapSolo()` with no `firstBookName`, so no
  book is created before onboarding, and onboarding reaches S0.2 (OTP) before any book step (13 §5
  F1). The rule makes that ordering a guard instead of a coincidence: `createBook` and every other
  envelope-writing path refuse while the identity is provisional. ⟦tests: C-04b-2⟧
- On `409 user_id_taken`, which happens only by collision or by a client choosing someone else's id,
  the install discards its provisional identity, mints a fresh one and retries once. That is safe only
  because nothing has been authored under it. ⟦tests: C-04b-3⟧

### 3. A phone that already has an account takes that account's id ⟦tests: E-04b-2, C-04b-4 @M8⟧ — owner-confirmed 4 Oct 2026
- When `/otp/verify` answers with a `user_id` different from the install's proposal, the install is a
  **further device** of an existing user (06 §5: *new phone, has old device* / *no old device* /
  *platform key sync* / *Keychain remnant*). It discards its provisional `user_id`, `tenant_id` and
  UMK, adopts the answered `user_id`, and obtains the UMK only through link, recovery or key sync
  (04 §9.1, §7, §7.0). Its `device_id` and device keys stay, per ADR 2026-09-16 §1: nothing has been
  signed under them yet either. ⟦tests: C-04b-4 @M8⟧
- No oracle opens up: the answer comes only after a correct OTP, which proves the person holds the
  phone (06 §2's generic-error rule governs `otp/request`, unchanged).

### 4. `tenant_id` is minted by the client and recorded by the tenant-register route, not at OTP ⟦tests: E-04b-5 @M13⟧ — owner-confirmed 4 Oct 2026
- `tenants.type` (`0001:61`: `family | business_group | organization`) is chosen at S0.3, **after**
  OTP, so a tenant cannot be recorded at signup. The client mints each tenant's id. The route that
  registers a tenant (desk 85's book-create route, which also ends `rejected:unknown_book`, desk 117
  B1) records that id with its type, or answers `409 {error: tenant_id_taken}`, the same shape as §1.
- This ADR does not lift the one-tenant-per-install limit (`local_ledger.dart:2319`, `:2398`; desk 117
  B3). A second tenant on one install is separate work.

## Consequences
- **Server** (`lane-server`, xhigh, three-lens verify): `auth-challenge` `otp/verify` takes `user_id`;
  `Store.signupUser(…, id)` inserts with it; `409 user_id_taken`; no schema change, one function overload — `0030_client_minted_user_id.sql` adds a 4-argument `rf.signup_user`, because the insert lives in that SECURITY DEFINER function (`0005:127`) and `rf_api` holds no INSERT on `users` (the default stays for
  old clients). `E-04b-1…4`. `E-04b-5` lands with desk 85.
- **Client** (`lane-ui-hard`: auth + bootstrap are foundation): `HttpAuthClient` sends
  `identity.userId` on verify and checks the echo; the provisional-identity guard on `LocalLedger`'s
  writing paths; the re-mint on `user_id_taken`; adopt-and-discard on a known phone (§3). Only the
  **first-device** half is buildable now. The further-device half depends on link and recovery
  delivering the UMK (device linking is M8, `device_certification.dart:72`), so `C-04b-4` is reserved
  `@M8`.
- **Unblocks** desk 103's S11 guardians row and the engine's `_ownCount`, once bootstrap and the
  server agree on one user id; desk 89/100 end to end.
- **Docs**: a cross-reference line under 06 §2 and 06 §3 (step 2 already superseded for `device_id`
  by ADR 2026-09-16); ADR 2026-09-16 § Open first bullet → *resolved by ADR 2026-10-04b*.
- **Milestone**: M13 (server + first-device client), M8 for `C-04b-4`.

## Open ⚠️
- **The personal book's tenant has no type.** `tenants.type` allows `family | business_group |
  organization`, and the ledger files a *Myself* user's personal book under `identity.tenantId`. Rule
  whether a personal tenant is registered (a new type value, a migration) or the personal book needs
  no tenant row. Decide this with desk 85.
- **Tenant-register route**: path, wire shape and refusal names stay with desk 85; §4 fixes only
  who mints the id.
