// Late-bound identity and key material (ADR 2026-10-09 §1 🔒, desk 126/168).
//
// The device keys are minted inside S0.2 (ADR 2026-10-09 §2), after the
// composition root has already built the sync engine, and a C-04b-3 re-mint
// replaces ids in the same process. So nothing in this package captures an
// id or a key in a constructor any more: the engine, the guard and the trust
// store ask a source each time they use one.
//
// Before S0.2 a source answers [NotRegisteredYet] / [KeysNotRegisteredYet] —
// an explicit value, never a null key, a zero key or an empty id — and every
// reader fails closed on it: no push, no pull, no verify, no signing, and a
// typed [SyncHold] saying why. It is not *keys lost* (03 §5,
// `DeviceKeysMissing`) and not corruption, and nothing reads it as either.
//
// A further device of an existing account (ADR 2026-10-10 §1 🔒) is
// registered — its device keys exist — but holds no tenant: it never mints
// one, and learns it from its own account once it is certified and its
// memberships are readable. Until then its source answers
// [RegisteredAwaitingTenant] and the engine reads meta only — to learn —
// and pushes nothing, pulls nothing and opens nothing under a tenant
// ([SyncHold.tenantNotKnown]). What the read showed goes to a
// [TenantLearningSink]; the rule that turns it into the install's tenant is
// the identity owner's, not this package's.
import 'package:core_crypto/core_crypto.dart' show DeviceKeyPair, UmkKeyPair;
import 'package:meta/meta.dart';

import 'key_store.dart';
import 'trust.dart' show VerifiedUmkSource;

// ── identity ───────────────────────────────────────────────────────────────

/// Who this device syncs as, as its source answers **now**.
@immutable
sealed class DeviceIdentity {
  const DeviceIdentity();
}

/// The device has not been registered (S0.2 has not run its mint, ADR
/// 2026-10-09 §2). Provisional ids may exist on the phone; until the keys do,
/// the engine is told only this.
final class NotRegisteredYet extends DeviceIdentity {
  /// The one value.
  const NotRegisteredYet();

  @override
  bool operator ==(Object other) => other is NotRegisteredYet;

  @override
  int get hashCode => 0x1009;

  @override
  String toString() => 'NotRegisteredYet';
}

/// A registered device: its keys exist, so it has a device and a user it is
/// judged under (its own-device revocation, its own user's role and
/// removal). Whether it also knows its tenant is which subtype it is.
sealed class SignedInIdentity extends DeviceIdentity {
  const SignedInIdentity();

  /// This device.
  String get deviceId;

  /// This device's user.
  String get userId;
}

/// The ids this device pushes, pulls and is judged under (its own-device
/// revocation, its own user's role and removal, its own envelopes coming
/// back).
final class RegisteredIdentity extends SignedInIdentity {
  /// Creates the identity.
  const RegisteredIdentity({
    required this.deviceId,
    required this.userId,
    required this.tenantId,
  });

  /// This device.
  @override
  final String deviceId;

  /// This device's user.
  @override
  final String userId;

  /// The tenant the engine syncs.
  final String tenantId;

  @override
  bool operator ==(Object other) =>
      other is RegisteredIdentity &&
      other.deviceId == deviceId &&
      other.userId == userId &&
      other.tenantId == tenantId;

  @override
  int get hashCode => Object.hash(deviceId, userId, tenantId);

  @override
  String toString() => 'RegisteredIdentity($deviceId)';
}

/// A registered further device of an existing account whose tenant is not
/// known yet (ADR 2026-10-10 §1 🔒): it signed in to an account that already
/// had one, discarded its provisional tenant and minted none. The engine
/// reads meta under it — that is how the tenant is learned — and holds
/// everything that would carry a tenant: no push is stamped, no envelope is
/// pulled or opened ([SyncHold.tenantNotKnown]).
final class RegisteredAwaitingTenant extends SignedInIdentity {
  /// Creates the identity.
  const RegisteredAwaitingTenant({
    required this.deviceId,
    required this.userId,
  });

  @override
  final String deviceId;

  @override
  final String userId;

  @override
  bool operator ==(Object other) =>
      other is RegisteredAwaitingTenant &&
      other.deviceId == deviceId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(deviceId, userId, 0x1010);

  @override
  String toString() => 'RegisteredAwaitingTenant($deviceId)';
}

// ── the install's tenant (ADR 2026-10-10 §1 🔒) ────────────────────────────

/// The install's tenant as its holder answers **now**. Typed rather than a
/// nullable id, so that no reader can pass *unknown* on as if it were an id:
/// the only way to an id is to match [KnownTenant].
@immutable
sealed class InstallTenant {
  const InstallTenant();
}

/// The install holds this tenant: a first device minted it at S0.3 (ADR
/// 2026-10-04b §4), or a further device learned it from its account.
final class KnownTenant extends InstallTenant {
  /// Creates the answer.
  const KnownTenant(this.id);

  /// `tenant_id` — a canonical uuid.
  final String id;

  @override
  bool operator ==(Object other) => other is KnownTenant && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'KnownTenant';
}

/// A further device's tenant before it is learned (ADR 2026-10-10 §1 🔒).
/// Not a placeholder and not a fresh mint: nothing is stamped, filed,
/// published or opened under it, and nothing is filtered against it.
final class TenantNotKnownYet extends InstallTenant {
  /// The one value.
  const TenantNotKnownYet();

  @override
  bool operator ==(Object other) => other is TenantNotKnownYet;

  @override
  int get hashCode => 0x1010;

  @override
  String toString() => 'TenantNotKnownYet';
}

/// What one **complete** meta read showed of this device's own user's
/// memberships, handed to the identity owner while the install's tenant is
/// not known (ADR 2026-10-10 §1 🔒). Complete means every page, from the
/// start of the feed, read under [userId] with the binding unchanged — never
/// a delta, so a tenant that is merely absent from one page is never
/// mistaken for the only one.
@immutable
final class OwnMemberships {
  /// Creates the read.
  const OwnMemberships({required this.userId, required this.activeTenantIds});

  /// The user the read was made as.
  final String userId;

  /// The tenants of this user's `active` memberships as the server's rows
  /// state them, less any tenant where a verified record of this user's
  /// membership says otherwise (the record's value is the one kept, D-05b-1).
  final Set<String> activeTenantIds;

  @override
  String toString() => 'OwnMemberships(${activeTenantIds.length} active)';
}

/// Where the engine hands an [OwnMemberships] read. The rule that turns it
/// into the install's tenant — exactly one active membership, and only on a
/// certified device — is the holder's (the app's ledger), not the engine's.
abstract interface class TenantLearningSink {
  /// Takes [read]. Called at most once per round, after the meta read and
  /// before the round ends; the round re-reads its binding afterwards.
  Future<void> ownMembershipsRead(OwnMemberships read);
}

/// Where the engine reads its identity — at every round, never once.
abstract interface class DeviceIdentitySource {
  /// The identity as of this call. A reader must not keep the answer past
  /// the operation it asked for.
  DeviceIdentity currentIdentity();
}

/// A source that always answers [identity] — the shape every pre-ADR wiring
/// had, kept so `SyncEngine(deviceId:, userId:, tenantId:)` still builds.
final class FixedIdentity implements DeviceIdentitySource {
  /// Creates the source.
  const FixedIdentity(this.identity);

  /// The answer.
  final DeviceIdentity identity;

  @override
  DeviceIdentity currentIdentity() => identity;
}

// ── key material ───────────────────────────────────────────────────────────

/// The key material a guard may use, as its source answers **now**.
@immutable
sealed class GuardKeys {
  const GuardKeys();
}

/// No device keys exist yet (before S0.2). Not *keys lost*: a guard that sees
/// this verifies nothing, unwraps nothing and signs nothing, and says so with
/// its own verdicts rather than with a quarantine or a corruption.
final class KeysNotRegisteredYet extends GuardKeys {
  /// The one value.
  const KeysNotRegisteredYet();

  @override
  bool operator ==(Object other) => other is KeysNotRegisteredYet;

  @override
  int get hashCode => 0x1009 + 1;

  @override
  String toString() => 'KeysNotRegisteredYet';
}

/// One coherent set: this device's pair, this user's UMK (if held), the
/// **live** book-key store, and who this material vouches for. All of one
/// install or none of it — a guard built from half of another's would
/// decrypt nothing and verify everything.
///
/// Borrowed, not copied: the source hands over the holder's own objects, so
/// a disposed pair is detected ([DeviceKeyPair.isDisposed]) and refused
/// rather than used.
final class DeviceKeyMaterial extends GuardKeys {
  /// Creates the material.
  const DeviceKeyMaterial({
    required this.device,
    required this.bookKeys,
    this.umk,
    this.verifiedUmks,
  });

  /// This device's Ed25519 + X25519 pair (re-seals the device's own outbox).
  final DeviceKeyPair device;

  /// This user's UMK — opens `wrapped_keys` rows. Null on a device that holds
  /// none yet (a further device before link or recovery, ADR 2026-10-04b §3).
  final UmkKeyPair? umk;

  /// Unwrapped book keys, every version retained.
  final BookKeyStore bookKeys;

  /// The ceremony-verified UMKs this install believes (its own user's and
  /// the members a ceremony proved), read through by
  /// `RecordTrustStore.late`. Null believes nobody.
  final VerifiedUmkSource? verifiedUmks;
}

/// Where a guard reads its key material — at every use, never once.
abstract interface class KeyMaterialSource {
  /// The material as of this call. A reader must not keep the answer past
  /// the operation it asked for.
  GuardKeys currentKeys();
}

/// A source that always answers [keys] — what `CryptoGuard(me:, umk:,
/// keys:)` wraps, so every pre-ADR wiring still builds.
final class FixedKeyMaterial implements KeyMaterialSource {
  /// Creates the source.
  const FixedKeyMaterial(this.keys);

  /// The answer.
  final GuardKeys keys;

  @override
  GuardKeys currentKeys() => keys;
}

// ── the engine's answer ─────────────────────────────────────────────────────

/// Why a sync round did nothing (or stopped at a route boundary). Typed so
/// the app can tell *not registered yet* from every Inbox cause; it is not a
/// sixth status (05 §9 🔒 owns exactly five).
enum SyncHold {
  /// Before S0.2 (ADR 2026-10-09 §1 🔒): there is no identity, or the guard
  /// holds no key material for it. Nothing was pushed, pulled, verified or
  /// signed. Not keys lost and not corruption — nothing is wrong.
  notRegistered,

  /// The identity changed while a round ran (a registration, a C-04b-3
  /// re-mint, a tenant learned). The round stopped at the next route
  /// boundary, with every row it had already taken in kept; the next round
  /// runs under the new ids.
  bindingChanged,

  /// A registered further device whose tenant is not known yet (ADR
  /// 2026-10-10 §1 🔒, [RegisteredAwaitingTenant]). The round read meta —
  /// to learn the tenant — and nothing else: no push was stamped, no
  /// envelope pulled or opened. Not keys lost and not corruption.
  tenantNotKnown,
}
