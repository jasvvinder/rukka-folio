# ADR 2026-10-03b — A guardian set belongs to a tenant; guardian revocations are filed and counted there

**Status:** accepted (owner-ruled, 3 Oct 2026, clearing PLAN desk 89; revised the same day after a
re-check against the app's trust model, before anything was built).
**Amends:** ADR 2026-09-06 §3, owner-locked (which approvals count) · 04 §7.3 *Setup* · 04 §9.2 · 06 §6 ·
07 (Devices & security). **Narrows:** `0022` §3 (book bootstrap). **Adds:** `guardian_sets.tenant_id`
(the server schema of 03 §2).

EDGE83 (3 Oct) left the edge narrower than `0022` in three places (desk 89). The owner first ruled that
approvals count "per tenant". A re-check against the code before any build then found:

- **Trust in this app is rooted per tenant, and per person.** A reader accepts a signed record only if
  the author's UMK was verified by ceremony *for that tenant* (04 §3.4, owner-locked; `verify_chain.dart:45-47`
  `authorUnverified`).
- **An install believes only ceremonies its own user performed.** The directory is keyed by tenant
  (`verified_members.dart:199-201, 320`), and delegated verification is not believed
  (`verified_members.dart:50-55`).
- **S11.1 picks guardians from one tenant.** It offers the members of the current tenant
  (`bootstrap.dart:858-861`), and save refuses anyone unverified.
- **The saved set records no tenant** (`guardian_sets`, `0002:51-73`).
- **Nothing yet files a `device_revocation` record** (none in `app/` or `packages/data`), so nothing
  decides where a guardian files.

Two consequences follow. Counting across tenants on the server would revoke a device that no client
could verify. Counting "per tenant" without a filing rule fails as well: two guardians who share two
tenants with the subject can file in different ones and never complete. One fact closes both gaps. A
set belongs to the tenant it was set up in, and guardians file and are counted there. The subject
verified every guardian of the set in exactly that tenant, so **the server and the subject's own
devices count the same set**. The subject's devices include the stolen one, which wipes only on a
verified record (ADR 2026-09-05b §2).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. A guardian set belongs to the tenant it was set up in ⟦tests: E-03b-5⟧
- `guardian_sets` gains `tenant_id`, written once at S11.1 save (04 §7.3 *Setup*). It names the tenant
  whose members the set was chosen from and in which the subject verified every guardian. The publisher
  is an active member of it, and every guardian of the version holds a membership there other than
  `removed`. The column is write-once with the rest of the version (`0010` guard), and a re-split may
  name a different tenant.
- Recovery (04 §7.3) does not read the column. A guardian helps recover whatever tenants they are in.
- A set published before this ADR has no tenant. It still recovers, but cannot revoke, until the next
  re-split (no pilot data exists; `rukka-folio-dev` only).

### 2. Guardians file in the set's tenant, and only approvals filed there count ⟦tests: D-03b-1, D-03b-2, D-03b-3, E-03b-1, E-03b-2⟧
- A guardian's `device_revocation` approval is filed in the `tenant_id` of the `share_set_version` it
  names. It counts toward k only if it is filed there and the subject holds a membership there other
  than `removed` (0022 §4's WHERE). Everything else in ADR 2026-09-06 §3 is unchanged:
  - distinct guardian authors, each valid at the version they name;
  - earliest-k;
  - the cut-off is the `seq` of the k-th counted record and can only move earlier;
  - a re-split does not reset the count. Approvals carry across versions, each judged by the tenant of
    the version it names.
- The server counts in the database. `rf.project_device_status` gains a SECURITY DEFINER count over
  every approval of the device that meets the rule above. The edge asks it, never the rows the caller
  can see. The client's `RevocationRecord` and `GuardianSetVersion` carry the tenant, and counting
  applies the same rule.
- **Who agrees, stated exactly:** the server and the subject's own devices count the same set. Another
  member of the tenant counts only the guardians *they* verified (delegated verification is not
  believed, `verified_members.dart:50-55`). For them the operative stop is the server, which refuses
  the revoked device's pushes and withdraws its wrapped keys. Their own cut-off is best-effort.
- Consequence, accepted: approvals filed anywhere else never count. Disjoint guardians cannot arise
  from S11.1, because every chosen guardian shares the set's tenant.

### 3. A guardian still pending in the set's tenant may revoke ⟦tests: E-03b-3⟧
- Authority comes from the guardian set (06 §6). The subject verified the guardian at setup, so a
  guardian at `joined_pending_verification` in the set's tenant files an approval that counts. The
  edge asks this through a SECURITY DEFINER helper, because a pending member cannot see the subject's
  membership row. It stops refusing these approvals as `not_revoker`.

### 4. Devices & security says when the set can no longer revoke ⟦tests: F1-03b-1⟧
- When fewer than k guardians of the current version still hold a membership in the set's tenant, the
  guardians row in Menu → Devices & security says so in plain words. The same applies when the
  subject no longer does, or when the set has no tenant (§1). Suggested EN copy: *"Your guardians can
  still help you recover, but can no longer switch off a lost phone together — choose guardians
  again."* The row's action opens S11.1. The copy goes through ARB (EN/PA/HI) and is never a dead end
  (07 §1).

### 5. A book that ever held an envelope is never re-claimed ⟦tests: E-03b-4⟧
- A role-less book can be bootstrapped by its creator (0022 §3 reading (d)) only if it **never** held an
  envelope: `book_usage.envelope_count = 0`, a counter that only goes up. The database is narrowed to
  the edge's reading. In practice the only envelopes ever deleted are an erased user's personal-book
  envelopes (03 §2), whose book only that user could claim. This ruling therefore also guards the
  cold-archive offload (03 open 4) before it exists.

## Consequences
- **Server** (`lane-server`, one migration slice):
  - `0026`: `guardian_sets.tenant_id` with its publish checks. `rf.project_device_status` gains the
    definer count over set-tenant approvals and the pending-guardian helper the edge asks.
    `project_book_role` reads `book_usage`.
  - The S11.1 publish route takes the tenant.
  - `_shared/records.ts` counts through the database. It drops the three ⚠️ SPEC notes
    (`records.ts:154`, `:273`, `:291`).
  - **Supersession:** the ignored E-06-94 disjoint-guardians case (`_tests/edge_record_authority.test.ts:42`,
    `tests/rls/edge_record_authority.test.ts:226`, `record_authority_world.ts:662`) asserts the opposite
    of §2. Delete it and replace it with E-03b-2, which asserts no completion.
- **Client** (`lane-sync`): `RevocationRecord.tenantId` and `GuardianSetVersion.tenantId`, with the §2
  rule in `revocation.dart` and in `engine.dart:766`. Tests D-03b-1…3 run on the two-client harness.
  The meta channel relays the column (`sync-meta/index.ts:183`).
- **App** (`lane-ui`): S11.1 save passes the current tenant. The §4 status row, F1-03b-1. The guardian's
  revoke action (not yet built) files in the set's tenant.
- **Docs:** cross-reference lines in 04 §7.3, 04 §9.2, 06 §6 and 07 (Devices & security).
- **Milestone:** M13, in one round of three slices.

## Open ⚠️
- No app path yet authors any `device_revocation`, whether own-device or guardian. The guardian's
  revoke screen and the owner's own-device revoke are unbuilt; §2 fixes only where the guardian files.
