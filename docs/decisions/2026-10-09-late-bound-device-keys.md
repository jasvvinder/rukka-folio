# ADR 2026-10-09 — The device keys are minted at S0.2 and the composition root binds them late

ADR 2026-10-06 ruling 1 🔒 says the device keys are *"minted when the device is first registered (S0.2)"*. The build
mints them at first launch (`local_ledger.dart _firstRun` ~2258; ⚠️ SPEC notes there and at `bootstrap.dart` ~507,
PLAN desk 168). Lane M13-KEY168 (9 Oct) checked whether the mint can move:
- No screen before S0.2 uses the keys. S0.0–S0.06 do not touch them, S0.2's `/otp/verify` sends only the ledger's user
  id, the cold-start gate runs only once an MPIN exists, and the demo builder runs after sign-in.
- The composition root needs them at launch. `bootstrap.dart:897` reads `ledger.keyMaterial`, which force-unwraps
  `_device!`/`_umk!` (`local_ledger.dart:2056-2057`). That value feeds the following, so a launch without keys cannot
  build the sync engine:
  - `CryptoGuard(me: …)`, a non-nullable `DeviceKeyPair` (`packages/sync_engine/lib/src/guard.dart:212/227`);
  - `RecordTrustStore(umks: …)`;
  - `keyMaterial.umk.public` (`bootstrap.dart:1282`);
  - `DeviceRecordAuthor.ifAvailable` (`bootstrap.dart:573`).

It offered three ways: (a) a two-phase root, (b) relaunch after registration with a first session that does not sync, (c)
late-bound key material and ids.

**Owner ruled, 9 Oct 2026: option (c).**

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Key material and identity are late-bound in the composition root 🔒 ⟦tests: D-1009-1, C-1009-1⟧
- The parts that today capture the device key pair, the UMK or the user/tenant ids at launch read them through a
  provider when they use them. They no longer capture them in a constructor:
  - `sync_engine` (`SyncEngine`, `CryptoGuard`, `RecordTrustStore`);
  - `ServerMembersRepository`, the S11.1 roster, `GuardianStandingHost` and `DeviceRecordAuthor`.
- Before the keys exist, a reader gets an explicit *not registered yet* answer. It never gets a null key or a zero key.
  The sync engine does not push, pull or verify, and says why. Nothing is signed.
- A C-04b-3 re-mint, or the S0.2 registration, takes effect without a relaunch. This closes PLAN desk 126.

### 2. The mint happens inside S0.2, through the ledger 🔒 ⟦tests: C-1006-1, C-1009-2⟧
- S0.2 creates the following in one ledger step, immediately before `POST /devices`:
  - the signing seed and the agreement seed;
  - for a **new account only**, the UMK and its local wrap.

  They go straight into the non-biometric class (ADR 2026-10-06 §1). The step is idempotent for a retried POST, so a
  retry reuses the seeds the ledger already holds.
- A device that signs in to an **existing** account mints only its device seeds, never a UMK (ADR 2026-10-04b §3). Its
  UMK arrives later, by linking a phone or by recovery.
- `HttpAuthClient` stops minting seeds of its own (`http_auth_client.dart:1222-1233`, C-06-9 re-read). It asks the ledger
  instead, so no key exists that the UMK was never wrapped to.
- `remintProvisionalIdentity` re-mints ids only. Before S0.2 there is no UMK to re-wrap.
- First launch mints ids (device id, user id, tenant id per ADR 2026-09-16 §1) and no key material.

## Open ⚠️
- ✅ **Not registered yet vs keys lost (fail-closed rule) — owner confirmed 9 Oct 2026 (PLAN desk 185 (a)), as written below.** Today, an identity
  with no seeds means *keys lost*: `DeviceKeysMissing` (`local_ledger.dart:2320`) ends at `RukkaFolioBlocked` (03 §5).
  After this change, a relaunch before S0.2, or a kill between the OTP confirm and `POST /devices`, is in the same state.
  The build reads a phone as **not registered yet** (S0.2 may mint) only when all three hold:
  - nothing has been authored;
  - there is no device certificate;
  - `SessionItems.deviceId` is absent.

  Anything else stays blocked, as today.
  Built in M13-KEY168B (`local_ledger.dart`, `features/lock/cold_start_gate.dart`); both sides tested at the ledger and
  through the real cold-start gate. ⟦tests: C-1009-2⟧

## Consequences
- Two device-local items are new; both live in the platform key store, not the Drift schema, so 03 has no section for
  them. Owner approved 9 Oct 2026 (PLAN desk 185 (c)).
  - `rk.ledger.device_keys` (`LocalLedgerKeys.deviceKeysState`: `none` · `minting` · `minted`; no prompt). It records that
    an ids-only install has no device keys yet, so a device-key read is not sent to the legacy biometric class and the
    phone does not ask for a biometric on every launch before S0.2. An absent marker means an install from before this
    ADR and is read as before.
  - `IdentityState.existing_account`: a fresh install signing in to an existing account (ADR 2026-10-04b §3, C-04b-4).
    Older builds ignore it.
- The composition root still re-arms `RootRelaunch` on `onIdentityReminted` beside `onUmkAdopted`, as a stopgap: the
  ceremony builder (`features/ceremony` `buildLiveCeremonySessions`) is not in ruling 1's list and still takes the ids
  at launch. When it reads them late, the re-mint relaunch comes out (PLAN desk 184 (b)).

