// The device certificate this install holds, and the one seam it is issued
// through (04 §3.4 🔒 · 06 §3 step 3).
//
// The certificate is `Sign_UMK_ed(device_id ‖ device_pub_ed ‖ device_pub_x ‖
// issued_at)` — the root of the whole trust chain: without it `ChainVerifier`
// answers `certMissing` for every envelope this device authors and no other
// member can ever read them.
//
// Why the seam and not a getter on the key material: **the UMK secret never
// leaves the ledger.** `features/auth` has no business holding it, and holding
// it would mean two places could sign under the user's root key. So the ledger
// issues the certificate (it already has the device pair, the UMK and an
// injected clock) and hands out a [DeviceCertOffer] — a signature, a public
// key and an integer, all of which are already public by design. The auth
// client does the HTTP and nothing else.
//
// ⚠️ SPEC: 04 §3.4 does not name a UMK *key version*. The server's
// `devices/certify` takes one (`umk_key_version`, default 1) because 03 §2.2
// stores UMK public keys per version; this install has exactly one UMK and so
// always offers version [umkKeyVersionFirst]. When UMK rotation lands (04 §9.2)
// the version must come from the rotation record, not from this constant.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

/// The only UMK version this build mints or signs under (see the file note).
const int umkKeyVersionFirst = 1;

/// What `POST devices/certify` needs: the certificate, plus **both** public
/// halves of the UMK that signed it, so a server that has never seen this
/// user's UMK can record it (⚠️ WIRE `umk_pub_ed` / `umk_pub_x`,
/// auth-challenge `certifyWith`).
///
/// Both halves, because 04 §6.3 🔒 compares the scanned keys byte-for-byte
/// against the keys the server relays and `Ceremony.verifyQr` compares the
/// X25519 half as well as the Ed25519 one. The X25519 half comes from its own
/// seed (`core_crypto/lib/src/keys.dart`), so the server cannot derive it from
/// `pub_ed`: a device that never offers it leaves its user unverifiable by
/// anyone (ADR 2026-09-24b §2).
///
/// Nothing secret: a 64-byte signature and two 32-byte public keys.
final class DeviceCertOffer {
  /// Creates the offer.
  const DeviceCertOffer({
    required this.cert,
    required this.umkPubEd,
    required this.umkPubX,
    this.umkKeyVersion = umkKeyVersionFirst,
  });

  /// The certificate, signed under the user's UMK.
  final DeviceCert cert;

  /// The UMK's Ed25519 public half (32 bytes) — what verifies [cert].
  final Uint8List umkPubEd;

  /// The UMK's X25519 public half (32 bytes) — what a verifier's device
  /// compares against the scanned QR (04 §6.3 🔒). `rf.set_umk_pubs` fills a
  /// NULL once and refuses a different value (`umk_pub_conflict`), so offering
  /// it on every certify is idempotent.
  final Uint8List umkPubX;

  /// Which UMK version signed (03 §2.2; see the file note).
  final int umkKeyVersion;
}

/// The ledger, seen by the one caller that certifies this device.
///
/// `LocalLedger` is the only implementation; a test may script it. Every
/// method is about *this* install's own certificate — there is no path here to
/// issue a certificate for another device, because this build never links one
/// (04 §9.1 is M8).
abstract interface class DeviceCertifier {
  /// Issues a fresh certificate for this install's own device under its own
  /// UMK (04 §3.4 self-certification). Throws before the ledger is open.
  ///
  /// Issuing is cheap and stateless — the certificate is *filed* only when the
  /// server has accepted it ([installOwnCert]), so a refused upload leaves
  /// nothing behind.
  DeviceCertOffer issueOwnCert();

  /// Files the certificate the server accepted: verified once more under this
  /// install's own UMK, persisted, and handed to the trust store so this
  /// device's own chain verifies without waiting for a meta round trip.
  ///
  /// Throws [ArgumentError] if the certificate is not this device's or does
  /// not verify — a device never files a certificate it cannot check.
  Future<void> installOwnCert(DeviceCert cert);

  /// The filed certificate, or null while this device is uncertified.
  DeviceCert? get ownDeviceCert;

  /// The **filed** certificate, offered again with both UMK public halves —
  /// the launch-time re-offer of ADR 2026-09-24b §2. Null while this device
  /// is uncertified (activation carries both halves itself) or the ledger is
  /// closed.
  ///
  /// It issues nothing and signs nothing: the certificate is the one already
  /// on file, byte for byte, so a server that re-verifies it re-stores the
  /// same row. That is what makes the re-offer harmless to a device the
  /// server has already certified.
  DeviceCertOffer? reofferOwnCert();
}

/// The stored form of [DeviceCert]: UTF-8 JSON in the [KeyStore], beside the
/// identity record. Not secret (a signature and public keys), but the key
/// store is the only persistent shell store outside the ledger database.
///
/// Field names match the `device_certs` meta row (03 §2.2) so the two shapes
/// stay readable side by side; unknown fields are ignored on decode and the
/// record is never rewritten (the identity record's rule).
Uint8List encodeDeviceCert(DeviceCert cert) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'suite_version': cert.suiteVersion,
      'user_id': cert.userId,
      'device_id': cert.device.deviceId,
      'pub_ed': Bytes.base64Url(cert.device.ed25519),
      'pub_x': Bytes.base64Url(cert.device.x25519),
      'issued_at_ms': cert.issuedAtMs,
      'signature': Bytes.base64Url(cert.signature),
    }),
  ),
);

/// Parses [encodeDeviceCert]. Null on anything that is not the record — a
/// certificate that will not parse is a device that is not certified, which is
/// a state the app already has (06 §3 step 3), never an error to crash on.
DeviceCert? decodeDeviceCert(Uint8List bytes) {
  final Object? j;
  try {
    j = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return null;
  }
  if (j is! Map) return null;
  final userId = j['user_id'], deviceId = j['device_id'];
  final pubEd = j['pub_ed'], pubX = j['pub_x'];
  final issuedAt = j['issued_at_ms'], sig = j['signature'];
  final suite = j['suite_version'];
  if (userId is! String ||
      deviceId is! String ||
      pubEd is! String ||
      pubX is! String ||
      sig is! String ||
      issuedAt is! int ||
      suite is! int) {
    return null;
  }
  try {
    return DeviceCert(
      suiteVersion: suite,
      userId: userId,
      device: DevicePublic(
        deviceId: deviceId,
        ed25519: Bytes.fromBase64Url(pubEd),
        x25519: Bytes.fromBase64Url(pubX),
      ),
      issuedAtMs: issuedAt,
      signature: Bytes.fromBase64Url(sig),
    );
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}
