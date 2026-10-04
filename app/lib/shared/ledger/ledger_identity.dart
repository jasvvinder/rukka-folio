// One device, one id (ADR 2026-09-16 §1 🔒).
//
// `LocalLedger._firstRun` mints the install's device, user and tenant ids once
// and stores them here, in the [KeyStore], as the identity record. The device
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
// rather than dropping them on a re-encode (rule 6).
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show Uuid16;

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
}

/// Whether `/otp/verify` has answered with the identity's own user id (ADR
/// 2026-10-04b §2 🔒). Bound to the user id it was written for: a record that
/// names any other id — a re-mint that died before its identity record
/// landed — never reads as confirmed.
final class IdentityState {
  /// Creates the record.
  const IdentityState({required this.userId, required this.confirmed});

  /// The user id the record speaks for.
  final String userId;

  /// True once signup echoed [userId].
  final bool confirmed;

  static const _provisional = 'provisional';
  static const _confirmed = 'confirmed';

  /// The stored form, UTF-8 JSON.
  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'user_id': userId,
        'state': confirmed ? _confirmed : _provisional,
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
    return IdentityState(userId: user, confirmed: state == _confirmed);
  }
}

/// Who this install is: the ids every envelope is stamped with (04 §4).
final class LedgerIdentity {
  /// Creates the identity.
  const LedgerIdentity({
    required this.deviceId,
    required this.userId,
    required this.tenantId,
  });

  /// `author_device_id` — canonical uuid (04 §3.3). Minted once, at first
  /// run, by the ledger (ADR 2026-09-16 §1).
  final String deviceId;

  /// `created_by_user` — canonical uuid.
  final String userId;

  /// `tenant_id` in every AAD (04 §4).
  final String tenantId;

  /// The stored form: UTF-8 JSON with the suite version the keys were made
  /// under (04 §2 — every stored artefact carries it).
  Uint8List encode({required int suiteVersion}) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'device_id': deviceId,
        'user_id': userId,
        'tenant_id': tenantId,
        'suite_version': suiteVersion,
      }),
    ),
  );

  /// Parses a stored record. Null when the bytes are not the record: not
  /// JSON, not an object, or any of the three ids missing or not a canonical
  /// uuid. Unknown fields are ignored, never an error.
  static LedgerIdentity? decode(Uint8List bytes) {
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    final device = j['device_id'], user = j['user_id'], tenant = j['tenant_id'];
    if (device is! String || user is! String || tenant is! String) return null;
    if (!Uuid16.isCanonical(device) ||
        !Uuid16.isCanonical(user) ||
        !Uuid16.isCanonical(tenant)) {
      return null;
    }
    return LedgerIdentity(deviceId: device, userId: user, tenantId: tenant);
  }
}

/// The identity `LocalLedger` wrote at first run, read without opening the
/// ledger. Null on an install that has never bootstrapped one — which is
/// every install until `LocalLedger.bootstrapSolo()` has run once.
Future<LedgerIdentity?> readStoredIdentity(KeyStore keys) async {
  final raw = await keys.read(LocalLedgerKeys.identity);
  return raw == null ? null : LedgerIdentity.decode(raw);
}
