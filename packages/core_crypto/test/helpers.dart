// Shared helpers for suite B (09 §2 B). Test code may use the clock and
// dart:math — the purity rule (CLAUDE.md rule 3) binds lib/, not test/.
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:sodium/sodium.dart';

Sodium? _sodium;

/// The process-wide libsodium binding (built by the `sodium` package's build
/// hook under `dart test`).
Future<Sodium> sodium() async => _sodium ??= await SodiumInit.init();

/// A deterministic random source: bytes are `BLAKE2b(seed ‖ counter)` blocks,
/// so a given [seed] yields the same keys, nonces and ciphertexts every run
/// (09 §1 — suite B is deterministic via injected RNG).
RandomBytes deterministicRandom(Sodium s, int seed) {
  var counter = 0;
  final seedBytes = Bytes.i64be(seed);
  return (int length) {
    final out = Uint8List(length);
    var o = 0;
    while (o < length) {
      final block = s.crypto.genericHash(
        message: Bytes.concat([seedBytes, Bytes.i64be(counter++)]),
        outLen: 32,
      );
      final n = length - o < 32 ? length - o : 32;
      out.setRange(o, o + n, block);
      o += n;
    }
    return out;
  };
}

/// A suite over the shared binding with a deterministic random source.
Future<CryptoSuite> testSuite({int seed = 1}) async {
  final s = await sodium();
  return CryptoSuite(s, random: deterministicRandom(s, seed));
}

/// A suite that uses libsodium's real CSPRNG.
Future<CryptoSuite> liveSuite() async => CryptoSuite(await sodium());

/// Fixed uuids for fixtures (synthetic — never real ids).
const String tenantA = '11111111-1111-4111-8111-111111111111';
const String bookA = '22222222-2222-4222-8222-222222222222';
const String deviceA = '33333333-3333-4333-8333-333333333331';
const String deviceB = '33333333-3333-4333-8333-333333333332';
const String userA = '44444444-4444-4444-8444-444444444441';
const String userB = '44444444-4444-4444-8444-444444444442';

/// Runs the QR ceremony (04 §6.3) over [u]'s own public keys so tests obtain
/// a [VerifiedUmkPublic] through the real path — there is no other way.
VerifiedUmkPublic verifiedUmk(
  CryptoSuite s,
  UmkKeyPair u, {
  String userId = userA,
}) {
  final r = Ceremony.verifyQr(
    s,
    scanned: QrPayload(userId: userId, umk: u.public, nonce: s.randomBytes(16)),
    relayed: u.public,
    relayedUserId: userId,
  );
  return (r as CeremonyVerified).verified;
}

/// A minimal in-memory [TrustStore] for one tenant.
final class MapTrustStore implements TrustStore {
  /// Creates the store.
  MapTrustStore({
    Map<String, VerifiedUmkPublic>? umks,
    Map<String, DeviceCert>? certs,
    Map<String, int>? revocations,
  }) : umks = umks ?? {},
       certs = certs ?? {},
       revocations = revocations ?? {};

  /// user id → verified UMK.
  final Map<String, VerifiedUmkPublic> umks;

  /// device id → certificate.
  final Map<String, DeviceCert> certs;

  /// device id → revocation seq.
  final Map<String, int> revocations;

  @override
  VerifiedUmkPublic? verifiedUmkOf(String userId) => umks[userId];

  @override
  DeviceCert? certOf(String deviceId) => certs[deviceId];

  @override
  int? revocationSeqOf(String deviceId) => revocations[deviceId];
}
