// Signing structural facts on this device (ADR 2026-09-05b §1 🔒: *every
// transition and every role/limit/designation change is a signed record
// authored on a certified admin device*; ADR 2026-09-05d §7 for verification
// and device events).
//
// `ServerMembersRepository` declares [MembersRecordAuthor] and deliberately
// takes it as nullable: with no author it refuses `invite()`, `reinvite()` and
// `setAutoPostLimit()` with [MembersRefusal.unauthorized] rather than pretend
// to write. This file is the author that makes those calls possible — and
// [DeviceRecordAuthor.ifAvailable] is how the refusal stays reachable: it
// returns **null** when this device holds no Ed25519 signing key or no device
// id, so a device that cannot sign is wired with no author at all rather than
// with one that throws halfway through an invite.
//
// The payload is encoded here and the exact bytes encoded are the exact bytes
// signed and the exact bytes sent (rule 6: nothing re-serialises them, so a
// field a newer build adds survives this one).
//
// Nothing here logs: a payload carries roles, limits and user ids.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart' show Hlc;

import '../../features/members/members_repository.dart'
    show MembersFailure, MembersRefusal;
import '../../features/members/server_members_repository.dart'
    show MembersRecordAuthor;
import '../seams/key_store.dart';

/// This device's id, as `features/auth` stored it after registration
/// (06 §3). Null before the device has registered.
typedef DeviceIdSource = Future<String?> Function();

/// A monotone HLC for the records this device authors (05 §2).
///
/// ⚠️ SPEC 05 §2: the spec describes **one** per-device clock, and
/// `LocalLedger` already keeps one for envelopes (seeded from the highest
/// stored envelope HLC). This author keeps its own, because `LocalLedger`
/// exposes neither its clock nor a tick, and `app/lib/shared/ledger` is not
/// this lane's to change. The conservative reading is taken: the two clocks
/// are each monotone and each seeded from the wall clock, so no record and no
/// envelope this device writes ever goes backwards — but a record and an
/// envelope written in the same millisecond can share an HLC, which the
/// single-clock reading would prevent. [RecordHlcClock.seed] exists so the
/// integrator can hand the ledger's clock over the day it is exposed.
final class RecordHlcClock {
  /// Creates the clock over an injected wall clock.
  RecordHlcClock(this.now, {Hlc seed = const Hlc(0)}) : _value = seed;

  /// Injected wall clock (never `DateTime.now` from inside a package).
  final DateTime Function() now;

  Hlc _value;

  /// The last value issued.
  Hlc get value => _value;

  /// Raises the clock to at least [other] — for seeding from another clock on
  /// the same device.
  void seed(Hlc other) {
    if (other > _value) _value = other;
  }

  /// The next HLC: wall clock when it has moved on, else counter + 1.
  Hlc tick() => _value = _value.tick(physicalMs: now().millisecondsSinceEpoch);
}

/// [MembersRecordAuthor] over the device's Ed25519 key (04 §3.3) and
/// `core_crypto`'s [SignedRecord.sign] (04 §8.3).
final class DeviceRecordAuthor implements MembersRecordAuthor {
  /// Creates the author. Prefer [ifAvailable], which keeps the
  /// no-signing-device refusal reachable.
  DeviceRecordAuthor({
    required this.suite,
    required this.keys,
    required this.deviceIdOf,
    required this.clock,
    IdSource? newRecordId,
  }) : _newId = newRecordId ?? ((s) => uuidV4(s));

  /// Builds an author, or null when this device cannot sign: no device id, a
  /// device id that is not a canonical uuid, or no Ed25519 seed in the key
  /// store. Null is the input `ServerMembersRepository` turns into
  /// [MembersRefusal.unauthorized].
  static Future<DeviceRecordAuthor?> ifAvailable({
    required CryptoSuite suite,
    required KeyStore keys,
    required DeviceIdSource deviceIdOf,
    required RecordHlcClock clock,
  }) async {
    final deviceId = await deviceIdOf();
    if (deviceId == null || !Uuid16.isCanonical(deviceId)) return null;
    if (!await keys.contains(KeyIds.deviceSigningKey)) return null;
    if (!await keys.contains(KeyIds.deviceAgreementKey)) return null;
    return DeviceRecordAuthor(
      suite: suite,
      keys: keys,
      deviceIdOf: deviceIdOf,
      clock: clock,
    );
  }

  /// libsodium + the platform CSPRNG (rule 7).
  final CryptoSuite suite;

  /// Where the device keys rest (04 §3.3).
  final KeyStore keys;

  /// This device's id.
  final DeviceIdSource deviceIdOf;

  /// The record clock (05 §2).
  final RecordHlcClock clock;

  final IdSource _newId;

  @override
  Uint8List nonce16() => suite.randomBytes(16);

  @override
  Future<Map<String, Object?>> sign({
    required String tenantId,
    required String kind,
    required Map<String, Object?> payload,
  }) async {
    final deviceId = await deviceIdOf();
    if (deviceId == null || !Uuid16.isCanonical(deviceId)) {
      throw const MembersFailure(
        'no signing device',
        MembersRefusal.unauthorized,
      );
    }
    final device = await _device(deviceId);
    if (device == null) {
      throw const MembersFailure(
        'no signing device',
        MembersRefusal.unauthorized,
      );
    }
    try {
      // Encoded once. These bytes are what is signed and what travels.
      final payloadJson = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
      final record = SignedRecord.sign(
        suite,
        tenantId: tenantId,
        kind: kind,
        payloadJson: payloadJson,
        hlc: clock.tick().raw,
        author: device,
      );
      // ⚠️ WIRE `server/supabase/functions/_shared/records.ts` `parseRecord`:
      // `id`, `tenant_id` and `author_device_id` must be uuids, `payload_json`
      // and `author_sig` base64 (`b64any` takes either alphabet, any
      // padding), `hlc` a bigint. `seq` is the server's and is never sent.
      return {
        'id': _newId(suite),
        'suite_version': record.suiteVersion,
        'tenant_id': record.tenantId,
        'kind': record.kind,
        'payload_json': _b64url(record.payloadJson),
        'author_device_id': record.authorDeviceId,
        'author_sig': _b64url(record.authorSig),
        'hlc': record.hlc,
      };
    } finally {
      device.dispose();
    }
  }

  /// Rebuilds the device key pair from its stored seeds. ⚠️ SPEC: this is the
  /// second copy of the replay trick in the app (`shared/ledger/local_ledger
  /// .dart` `_deviceFromSeeds` is the first) — a `DeviceKeyPair.fromSeeds`
  /// factory in `core_crypto` would delete both. Kept byte-identical to that
  /// one on purpose: the two must produce the same device or this device
  /// would sign records under a key its envelopes do not use.
  Future<DeviceKeyPair?> _device(String deviceId) async {
    final ed = await keys.read(KeyIds.deviceSigningKey);
    final x = await keys.read(KeyIds.deviceAgreementKey);
    if (ed == null || x == null) {
      if (ed != null) zeroise(ed);
      if (x != null) zeroise(x);
      return null;
    }
    try {
      final queue = <Uint8List>[Uint8List.fromList(ed), Uint8List.fromList(x)];
      final replay = CryptoSuite(
        suite.sodium,
        random: (int n) {
          if (queue.isEmpty) throw StateError('device seed replay exhausted');
          final next = queue.removeAt(0);
          if (next.length != n) {
            throw StateError('device seed is ${next.length} bytes, need $n');
          }
          return next;
        },
      );
      return DeviceKeyPair.generate(replay, deviceId: deviceId);
    } on Object {
      return null;
    } finally {
      zeroise(ed);
      zeroise(x);
    }
  }

  static String _b64url(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}

/// Mints a record id. Injected only so a test can pin one.
typedef IdSource = String Function(CryptoSuite suite);

/// A canonical uuid (v4 layout) from libsodium's CSPRNG — the same shape
/// `LocalLedger.newId()` mints, because the server checks both with the same
/// `isUuid`.
String uuidV4(CryptoSuite suite) {
  final b = suite.randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  return Uuid16.fromBytes(b);
}
