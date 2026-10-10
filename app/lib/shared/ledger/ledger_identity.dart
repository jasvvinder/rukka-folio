// One device, one id (ADR 2026-09-16 §1 🔒).
//
// `LocalLedger._firstRun` mints the install's device, user and tenant ids once
// (ids only — the keys are minted inside S0.2, ADR 2026-10-09 §2) and stores
// them here, in the [KeyStore], as the identity record. The device
// id is baked into the device key pair, the wrapped UMK, every envelope's
// `author_device_id`, every signed record and — since the ADR — the id
// `features/auth` registers with the server and signs challenges under.
// Nothing else mints, derives or adopts a device id; the only reader outside
// the ledger is [readStoredIdentity], over the same store.
//
// The record is not secret (three uuids) but the seam is the only persistent
// store the shell offers outside the ledger database. It is written once and
// never rewritten — with one exception, a provisional identity re-minted on
// `409 user_id_taken` before anything was authored under it (ADR 2026-10-04b
// §2): [LedgerIdentity.decode] ignores fields it does not know
// rather than dropping them on a re-encode (rule 6) — and with one more, a
// further device's tenant: unknown when it adopts an existing account, and
// written once when it is learned from that account (ADR 2026-10-10 §1 🔒).
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show Uuid16;
import 'package:sync_engine/sync_engine.dart'
    show InstallTenant, KnownTenant, TenantNotKnownYet;

import '../seams/key_store.dart';

/// Ids the ledger facade keeps in the [KeyStore] beside [KeyIds].
abstract final class LocalLedgerKeys {
  /// JSON `{device_id, user_id, tenant_id, suite_version}` (all uuids).
  static const identity = 'rk.ledger.identity';

  /// This device's own certificate (04 §3.4), JSON — see
  /// `device_certification.dart`. Absent until the server has accepted one
  /// (06 §3 step 3); its presence is what lets the trust store root this
  /// device's own chain on a cold start, without a meta round trip.
  static const deviceCert = 'rk.ledger.device_cert';

  /// Other devices' certificates this install has seen prove a signature
  /// (04 §3.4), JSON — see `encodeRetainedCerts`. Public material only. Kept
  /// because the server stops serving a removed member's certificate
  /// (`rf.device_visible`) while their signed records stay in every book: the
  /// signature chain must still verify them on this phone at every later
  /// launch (03 *Deletion mechanics* 🔒 — *the signature chain still verifies
  /// on every device*). Promptless, like [deviceCert].
  ///
  /// ⚠️ SPEC (03 §3.1 🔒, for the 03 owner): the client schema has no table
  /// for other devices' certificates, so they sit in the key store beside
  /// this device's own (public material, a few hundred bytes per device). A
  /// `device_certs_local` table in the mirror would be the natural home; that
  /// is a 🔒 schema change, not made here (review TRUSTWIRE-1).
  static const peerCerts = 'rk.ledger.peer_certs';

  /// The server holds this UMK's x half (ADR 2026-09-24b §2), JSON — see
  /// `encodeUmkPubsAccepted`. Its presence stops the launch-time re-offer
  /// (owner ruling 25 Sep, PLAN desk 33).
  static const umkPubsAccepted = 'rk.ledger.umk_pubs_accepted';

  /// Where signup stands for the identity (ADR 2026-10-04b §2 🔒), JSON
  /// `{user_id, state}` — see [IdentityState]. Written by `_firstRun`
  /// *before* the identity record, so a first run that dies half-way leaves
  /// nothing that reads as confirmed. **Absent** means the identity was
  /// stored before the guard existed: it reads as confirmed, because an
  /// existing install is never locked out of its own books.
  static const identityState = 'rk.ledger.identity_state';

  /// The device id `features/auth` stores once `POST /devices` has answered
  /// (06 §3; `SessionItems.deviceId`, pinned equal by C-1009-2). Read by the
  /// ledger only as evidence for the fail-closed rule of ADR 2026-10-09
  /// *Open*: an install the server has registered is never read as *not
  /// registered yet*. The ledger never writes it.
  static const sessionDeviceId = 'rk.device.id';

  /// Where this install's device keys stand (ADR 2026-10-09 §2), UTF-8:
  /// [DeviceKeysState.none] from an ids-only first launch until S0.2's mint,
  /// [DeviceKeysState.minting] while it runs, [DeviceKeysState.minted] after.
  /// **Absent** means an install from before the ADR, whose keys were minted
  /// at its first launch. It exists so a phone that has never held a device
  /// key is not made to look for one: with no device-key class recorded, a
  /// device-key read goes to the legacy biometric class
  /// (`keychain_key_store.dart`), and the person would be asked for a
  /// biometric to read a key that was never written. Not secret; promptless.
  static const deviceKeysState = 'rk.ledger.device_keys';
}

/// The values of [LocalLedgerKeys.deviceKeysState].
abstract final class DeviceKeysState {
  /// Ids only: no device key has ever been written on this install.
  static const none = 'none';

  /// S0.2's mint began; seeds may be partly written.
  static const minting = 'minting';

  /// S0.2's mint finished.
  static const minted = 'minted';
}

/// Whether `/otp/verify` has answered with the identity's own user id (ADR
/// 2026-10-04b §2 🔒). Bound to the user id it was written for: a record that
/// names any other id — a re-mint that died before its identity record
/// landed — never reads as confirmed.
final class IdentityState {
  /// Creates the record.
  const IdentityState({
    required this.userId,
    required this.confirmed,
    this.existingAccount = false,
    this.umkAdopted = false,
  });

  /// The user id the record speaks for.
  final String userId;

  /// True once signup echoed [userId].
  final bool confirmed;

  /// True when [userId] was adopted from `/otp/verify` naming an account the
  /// phone number already has (ADR 2026-10-04b §3, C-04b-4): this install is
  /// a further device of that account, so S0.2's mint makes device seeds
  /// only and never a UMK (ADR 2026-10-09 §2). Stored as an extra field, so
  /// a build that predates it reads the record exactly as before.
  final bool existingAccount;

  /// True once a further device of an existing account ([existingAccount])
  /// has adopted that account's UMK (rung 3 today; link and key sync at M8).
  /// From then on its wrapped UMK is something it *had*: a reopen that
  /// finds it (or a device seed) missing is keys lost, never *not
  /// registered yet* (ADR 2026-10-09 *Open*; review finding KEY168B-3). The
  /// [existingAccount] flag itself stays, so S0.2's mint can never make a
  /// second UMK for the account. Stored as an extra field, as that one is.
  final bool umkAdopted;

  static const _provisional = 'provisional';
  static const _confirmed = 'confirmed';

  /// The stored form, UTF-8 JSON.
  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'user_id': userId,
        'state': confirmed ? _confirmed : _provisional,
        if (existingAccount) 'existing_account': true,
        if (umkAdopted) 'umk_adopted': true,
      }),
    ),
  );

  /// Parses a stored record; null when it is not one. A record that will
  /// not parse is treated by the ledger as *provisional* — never as the
  /// absent (legacy, confirmed) case.
  static IdentityState? decode(Uint8List bytes) {
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    final user = j['user_id'], state = j['state'];
    if (user is! String || !Uuid16.isCanonical(user)) return null;
    if (state != _provisional && state != _confirmed) return null;
    return IdentityState(
      userId: user,
      confirmed: state == _confirmed,
      existingAccount: j['existing_account'] == true,
      umkAdopted: j['umk_adopted'] == true,
    );
  }
}

/// The install's tenant is not known yet (ADR 2026-10-10 §1 🔒): a further
/// device of an existing account learns its tenant from that account once it
/// is certified, and authors nothing that would carry one before then — no
/// book, no envelope. Thrown before any write.
final class LedgerTenantNotKnown implements Exception {
  /// Creates the refusal.
  const LedgerTenantNotKnown();

  @override
  String toString() =>
      'LedgerTenantNotKnown: this device has not learned its tenant yet';
}

/// Who this install is: the ids every envelope is stamped with (04 §4).
final class LedgerIdentity {
  /// Creates the identity of an install that holds its tenant.
  const LedgerIdentity({
    required this.deviceId,
    required this.userId,
    required String tenantId,
  }) : _tenantId = tenantId; // ignore: prefer_initializing_formals

  /// A further device of an existing account (ADR 2026-10-04b §3) whose
  /// tenant is not known yet (ADR 2026-10-10 §1 🔒): it discarded its
  /// provisional tenant, mints none, and learns its account's.
  const LedgerIdentity.tenantNotKnown({
    required this.deviceId,
    required this.userId,
  }) : _tenantId = null;

  /// `author_device_id` — canonical uuid (04 §3.3). Minted once, at first
  /// run, by the ledger (ADR 2026-09-16 §1).
  final String deviceId;

  /// `created_by_user` — canonical uuid.
  final String userId;

  final String? _tenantId;

  /// `tenant_id` in every AAD (04 §4) — or, on a further device that has
  /// not learned it yet, [TenantNotKnownYet] (ADR 2026-10-10 §1 🔒). Typed,
  /// so a reader reaches an id only by matching [KnownTenant].
  InstallTenant get tenant => switch (_tenantId) {
    final String id => KnownTenant(id),
    null => const TenantNotKnownYet(),
  };

  /// The marker an identity whose tenant is not known is stored with. An
  /// absent `tenant_id` alone is not enough: it reads as no record at all.
  static const _tenantNotKnown = 'not_known';

  /// The stored form: UTF-8 JSON with the suite version the keys were made
  /// under (04 §2 — every stored artefact carries it).
  Uint8List encode({required int suiteVersion}) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'device_id': deviceId,
        'user_id': userId,
        if (_tenantId != null)
          'tenant_id': _tenantId
        else
          'tenant': _tenantNotKnown,
        'suite_version': suiteVersion,
      }),
    ),
  );

  /// Parses a stored record. Null when the bytes are not the record: not
  /// JSON, not an object, the device or user id missing or not a canonical
  /// uuid, or a tenant that is neither a canonical uuid nor the explicit
  /// *not known* marker (ADR 2026-10-10 §1 🔒). Unknown fields are ignored,
  /// never an error.
  static LedgerIdentity? decode(Uint8List bytes) {
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    final device = j['device_id'], user = j['user_id'], tenant = j['tenant_id'];
    if (device is! String || user is! String) return null;
    if (!Uuid16.isCanonical(device) || !Uuid16.isCanonical(user)) return null;
    if (tenant == null && j['tenant'] == _tenantNotKnown) {
      return LedgerIdentity.tenantNotKnown(deviceId: device, userId: user);
    }
    if (tenant is! String || !Uuid16.isCanonical(tenant)) return null;
    return LedgerIdentity(deviceId: device, userId: user, tenantId: tenant);
  }
}

/// The identity `LocalLedger` wrote at first run, read without opening the
/// ledger. Null on an install that has never opened one — which is every
/// install until `LocalLedger.openIdentity()` (or `bootstrapSolo()`) has run
/// once.
Future<LedgerIdentity?> readStoredIdentity(KeyStore keys) async {
  final raw = await keys.read(LocalLedgerKeys.identity);
  return raw == null ? null : LedgerIdentity.decode(raw);
}
