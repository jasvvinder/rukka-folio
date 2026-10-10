# ADR 2026-10-10 — A further device learns its tenant; a held engine disables nothing before S0.2

Two gaps left by ADR 2026-10-09 (late-bound device keys) and ADR 2026-10-04b §3 (a phone that already has an account):

- **The tenant id of a further device.** §3 discards the provisional `tenant_id` and names nothing in its place. M13-KEY168B
  minted a fresh placeholder (`local_ledger.dart` `adoptExistingAccount`). The research of 10 Oct (PLAN desk 185 (b))
  found that no spec lets a further device mint a tenant. 04b §4 mints a tenant id when a tenant is *created*, at S0.3,
  and ADR 2026-10-05c §3 routes a further device S0.2d → S0.8 → Home with no purpose picker. No sign-in route returns a
  tenant (`auth-challenge/index.ts`), and an uncertified device sees no memberships (ADR 2026-09-05d §2). The
  placeholder is inert while the device waits for its UMK, because nothing authors (ADR 2026-10-09 §1). But nothing
  replaces it when the UMK arrives (`adoptRecoveredUmk` leaves `tenantId` alone). From then on it would stamp the
  envelope AAD (04 §5), the outbox, the S11.1 roster, the members filter and the `device_added` record with an id the
  account does not have.
- **The sync status before S0.2.** SYNC168 holds the engine as `notRegistered` until S0.2 mints the keys. 05 §9 🔒 has no
  sixth state, so the engine reports `Offline` while held. S0.2 disables *Send* and *Resend* on `Offline`
  (`s0_2_phone_otp_screen.dart:705, :776`). Since 9 Oct a real install therefore cannot request a sign-in code. The tests
  missed it because they run on `FakeSyncClient`, which reports `Synced` (PLAN desk 181 (c)).

**Owner directed, 10 Oct 2026:** take the reading the specs and design support.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. A further device learns its tenant and never mints one 🔒 ⟦tests: C-1010-1, C-1010-2⟧
- A device that signs in to an existing account (ADR 2026-10-04b §3) holds **no usable tenant id**. Its tenant is
  *unknown*: neither a placeholder nor a fresh mint.
- While the tenant is unknown, every reader of the install's tenant answers *not known yet*, as it answers *not
  registered yet* before S0.2 (ADR 2026-10-09 §1). Nothing is stamped, filed, published or opened under a tenant, and
  nothing is silently filtered against one.
- The tenant is **learned from the account**, once the device is certified and its memberships are readable (05d §2,
  06 §3 step 3). If the account holds exactly one active membership, that membership's tenant becomes the install's
  tenant. ⚠️ SPEC (Open): an account with several active memberships.
- A first device is unchanged: it mints its tenant at S0.3 (ADR 2026-10-04b §4).

### 2. A held engine shows no sync chip and disables no control 🔒 ⟦tests: F1-1010-1, F1-1010-2⟧
- While the engine is held, whether *not registered* (ADR 2026-10-09 §1) or a further device's *tenant not known* (ruling 1), a screen that reads the sync status shows **no** sync
  chip. It does not show *Offline* either. This adds no state to 05 §9: showing nothing is not a sixth state.
- No control is disabled because of a held engine. S0.2's *Send* and *Resend* rest on the auth client's own answer
  (06 §2), never on sync status.
- Once the engine is registered, 05 §9 and 07 §1 rule 7 apply unchanged.

## Consequences
- Code, ruling 1: `app/lib/shared/ledger/local_ledger.dart` (`adoptExistingAccount`, the identity's tenant, the
  UMK-arrival path) and the tenant readers listed in the 10 Oct research. These are `bootstrap.dart`
  (`device_added` record, the S11.1 roster), `features/members/server_members_repository.dart` and the outbox stamp
  that SYNC168's identity provider supplies.
- Code, ruling 2: the `SyncClient` seam gains a *held* signal (`EngineSyncClient` reads `engine.hold`; `FakeSyncClient`
  answers not held). S0.2, S11.x, S19.1 and show-my-code treat *held* as no chip. S0.2 stops gating *Send* and
  *Resend* on sync status.
- Docs: a cross-reference line under ADR 2026-10-04b §3, and an Open line under 06 §5 (below).
- Milestone: M13.

## Open ⚠️
- ✅ **Resolved 10 Oct (owner: *decide from the design and specs*), on the conservative reading.**
  - **Several active memberships:** the device keeps its tenant *unknown* and fails closed, as built. 06 §1 lets a user
    belong to n tenants, and no spec names one as a further device's home, so the app does not guess. Revisit with
    desk 85 (the personal tenant).
  - **06 §5 *Every rung fails*:** the newer rulings govern. ADR 2026-10-04b §3 (the UMK arrives only by link, recovery
    or key sync), ADR 2026-10-09 §2 (an existing account never mints a UMK) and ADR 2026-09-13c (an unproven new root
    is the server's *ghost self* attack) all post-date the 06 §5 row and beat it by precedence. **0031 stands.** The
    row's *new UMK* remedy is not built and stays unbuildable until an ADR defines how a new root is registered *and
    proven*. Shared books are still re-wrappable once a UMK exists. Until then, a user for whom every rung fails sees
    the 06 §5 *vault empty* state and the guardian or sheet paths.
- **The stolen-phone copy overstates the spec.** S11's *This phone was stolen* string says the master key *is* replaced
  (`app_en.arb`, `devices.*`). 04 §9.2 and 06 §6 only *recommend* UMK rotation, which has no write path, and the
  devices repository is still a fake. The copy needs a design and copy pass.
