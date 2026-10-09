import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium.dart';

import 'bytes.dart';
import 'keys.dart';
import 'suite.dart';
import 'wrapping.dart';

// Recovery rungs 3 and 4 (04 §7.4, §7.5). The recovery key RK is a
// full-entropy 256-bit key — there is no password and no KDF (04 §2). The
// server holds only `sealed_RK_blob = XChaCha20-Poly1305(RK, UMK_priv)`.
//
// String exception (ADR 2026-09-05 §8): the *sheet payload* is the one place
// key material is spec-mandated to become text (04 §7.4 — a printed QR and a
// typed fallback). Those functions are named `recoverySheet…`, live only here,
// and nothing else in the package renders a key as a `String`.
//
// 04 §7.6 "never backed up": this file serialises the UMK only inside the
// AEAD-sealed [SealedRecoveryBlob]; device private keys are never serialised.

/// File-scope alias — the artefact classes carry a `suiteVersion` field.
const int _currentSuite = suiteVersion;

/// Sheet payload format version, the leading byte of `version ‖ user_id ‖ RK`.
// ⚠️ SPEC: 04 §7.4 writes "version" without saying whether it is the crypto
// `suite_version` or a sheet-format version. Read as a sheet-format version
// (a re-laid-out sheet need not imply new primitives); it starts at 0x01 and
// currently coincides with the suite version.
const int recoverySheetVersion = 0x01;

/// Length of the RK in bytes (04 §7.4: "random 256-bit").
const int recoveryKeyBytes = 32;

/// Length of the sheet payload: `u8 ‖ uuid16 ‖ RK(32)`.
const int _sheetPayloadBytes = 1 + 16 + recoveryKeyBytes;

/// Crockford symbols in the checksum group (04 §7.4: "2-char checksum").
const int _checksumSymbols = 2;

/// The recovery key printed on the paper sheet (04 §7.4). Lives in guarded
/// memory; [dispose] when done.
final class RecoveryKey {
  /// Wraps an existing 32-byte key (after decoding a sheet).
  RecoveryKey(this.key) {
    if (key.length != recoveryKeyBytes) {
      throw ArgumentError.value(key.length, 'key', 'RK is 32 bytes');
    }
  }

  /// Generates a fresh RK from the suite's random source (signup, or sheet
  /// regeneration — which invalidates the old sheet, 04 §7.4).
  factory RecoveryKey.generate(CryptoSuite suite) =>
      RecoveryKey(suite.randomSecureKey(recoveryKeyBytes));

  /// The key.
  final SecureKey key;

  /// Zeroises and frees the key.
  void dispose() => key.dispose();
}

/// XChaCha20-Poly1305 nonce length (04 §2: "24-byte random nonce").
const int _recoveryNonceBytes = 24;

/// Poly1305 tag length.
const int _recoveryTagBytes = 16;

/// The sealed plaintext: the UMK's 64 secret bytes (`x25519_seed ‖
/// ed25519_seed`, [UmkKeyPair.exportSecretBytes]).
const int _umkSecretBytes = 64;

/// Wire length of a suite-1 [SealedRecoveryBlob]: `suite_version(1) ‖
/// nonce(24) ‖ ciphertext(64) ‖ tag(16)` = 105 bytes (ADR 2026-10-06d §1).
const int sealedRecoveryBlobBytes =
    1 + _recoveryNonceBytes + _umkSecretBytes + _recoveryTagBytes;

/// `sealed_RK_blob` (04 §7.4): XChaCha20-Poly1305 over the UMK's 64 secret
/// bytes under RK with a fresh 24-byte nonce. The server stores it opaquely.
///
/// Wire form (ADR 2026-10-06d §1 🔒, after `GuardianShare.encode`):
/// `suite_version(1) ‖ nonce(24) ‖ ciphertext ‖ tag(16)` — [encode] writes
/// it and [decode] reads it strictly. A later suite bumps the first byte
/// (04 §2); today's [decode] refuses anything but `0x01` rather than guess.
@immutable
final class SealedRecoveryBlob {
  /// Wraps the parts. [nonce] must be 24 bytes.
  SealedRecoveryBlob({
    required Uint8List nonce,
    required Uint8List ciphertext,
    this.suiteVersion = _currentSuite,
  }) : nonce = Uint8List.fromList(nonce),
       ciphertext = Uint8List.fromList(ciphertext) {
    if (nonce.length != _recoveryNonceBytes) {
      throw ArgumentError.value(
        nonce.length,
        'nonce',
        'recovery nonce is $_recoveryNonceBytes bytes',
      );
    }
  }

  /// Strict inverse of [encode]. Throws [RecoveryUnsealFailed] with reason
  /// `length` when [wire] is empty or not exactly [sealedRecoveryBlobBytes]
  /// (a truncated tag, a short or a long body all land here) and `suite`
  /// when the leading byte is not the current suite. It never infers a
  /// layout from the length and never returns a partial blob.
  static SealedRecoveryBlob decode(Uint8List wire) {
    if (wire.isEmpty) throw const RecoveryUnsealFailed('length');
    if (wire[0] != _currentSuite) throw const RecoveryUnsealFailed('suite');
    if (wire.length != sealedRecoveryBlobBytes) {
      throw const RecoveryUnsealFailed('length');
    }
    return SealedRecoveryBlob(
      suiteVersion: wire[0],
      nonce: Uint8List.sublistView(wire, 1, 1 + _recoveryNonceBytes),
      ciphertext: Uint8List.sublistView(wire, 1 + _recoveryNonceBytes),
    );
  }

  /// `suite_version` byte (04 §2).
  final int suiteVersion;

  /// 24-byte nonce.
  final Uint8List nonce;

  /// Ciphertext ‖ Poly1305 tag.
  final Uint8List ciphertext;

  /// Canonical wire bytes — what `publishSheet` stores and `GET
  /// recovery/sheet` hands back: `suite_version ‖ nonce ‖ ciphertext`.
  Uint8List encode() =>
      Bytes.concat([Bytes.u8(suiteVersion), nonce, ciphertext]);
}

/// The UMK a recovery blob opened to is not the one the account published
/// (ADR 2026-10-06d §2; 04 §7.3 step 4 — the same check as rung 2's
/// [GuardianShareMismatch]). Raised by [openUmkWithRecoveryKeyVerified] after
/// the derived pair has been disposed; nothing is handed back.
final class RecoveredUmkMismatch implements Exception {
  /// Creates the failure.
  const RecoveredUmkMismatch();

  @override
  String toString() =>
      'RecoveredUmkMismatch(recovered UMK does not match the expected public key)';
}

/// Opening a recovery blob failed: wrong RK, corrupt bytes, unknown suite or
/// a payload of the wrong shape.
final class RecoveryUnsealFailed implements Exception {
  /// Creates the failure.
  const RecoveryUnsealFailed(this.reason);

  /// Short machine-readable reason (`suite`, `aead`, `length`).
  final String reason;

  @override
  String toString() => 'RecoveryUnsealFailed($reason)';
}

/// Seals [umk]'s secret bytes under [rk] (04 §7.4). The plaintext copy is
/// zeroised in `finally`.
SealedRecoveryBlob sealUmkUnderRecoveryKey(
  CryptoSuite suite,
  RecoveryKey rk,
  UmkKeyPair umk,
) {
  final aead = suite.sodium.crypto.aeadXChaCha20Poly1305IETF;
  final nonce = suite.randomBytes(aead.nonceBytes);
  final secret = umk.exportSecretBytes();
  try {
    return SealedRecoveryBlob(
      nonce: nonce,
      ciphertext: aead.encrypt(message: secret, nonce: nonce, key: rk.key),
    );
  } finally {
    suite.zeroize(secret);
  }
}

/// Rung 3 recovery (04 §7.4 "decrypt UMK"): opens [blob] with [rk]. Throws
/// [RecoveryUnsealFailed] under a wrong key or corrupt bytes.
UmkKeyPair openUmkWithRecoveryKey(
  CryptoSuite suite,
  RecoveryKey rk,
  SealedRecoveryBlob blob,
) {
  if (blob.suiteVersion != _currentSuite) {
    throw const RecoveryUnsealFailed('suite');
  }
  final aead = suite.sodium.crypto.aeadXChaCha20Poly1305IETF;
  final Uint8List secret;
  try {
    secret = aead.decrypt(
      cipherText: blob.ciphertext,
      nonce: blob.nonce,
      key: rk.key,
    );
  } on SodiumException {
    throw const RecoveryUnsealFailed('aead');
  }
  try {
    if (secret.length != _umkSecretBytes) {
      throw const RecoveryUnsealFailed('length');
    }
    return UmkKeyPair.fromSecretBytes(suite, secret);
  } finally {
    suite.zeroize(secret);
  }
}

/// Rung 3 recovery, **checked against the account's published UMK** (ADR
/// 2026-10-06d §2 🔒; 04 §7.3 step 4): opens [blob] with [rk] as
/// [openUmkWithRecoveryKey] does, then hands the pair back only if both
/// public halves equal [expected] — the UMK the account registered (06 §3
/// item 3), as the server relays it.
///
/// Why [expected] is a plain [UmkPublic] here while rung 2's
/// `GuardianShareSet.reconstructVerified` demands a [VerifiedUmkPublic]: the
/// authenticator of this rung is the AEAD under RK, which lives on paper and
/// never on the server (ADR 2026-09-13c §1 — *"no other rung has this gap"*).
/// A blob the server forged or swapped fails to open; a server that lies
/// about the published key can only make a genuine blob be **refused**, which
/// is a denial it already has. The comparison therefore adds no trust in the
/// relayed key — it catches a sheet that opens to a key the account no longer
/// runs on (a stale print after a UMK rotation, 04 §9.2). Nothing is ever
/// wrapped to [expected] (CLAUDE.md rule 5): the recovered pair's own
/// verified public is produced from possession by the adopter, as at signup.
/// A solo user (04 §7.4: the sheet is mandatory for them) has nobody to run
/// a ceremony with, so a ceremony-typed parameter would make the rung
/// unusable for exactly its mandatory audience.
///
/// A wrong RK or corrupt bytes stay [RecoveryUnsealFailed]; a blob that
/// opens to another key is [RecoveredUmkMismatch] with the derived pair
/// disposed ([verifyRecoveredUmk]). The caller owns the returned
/// [UmkKeyPair] and disposes it. No randomness is drawn on either path.
UmkKeyPair openUmkWithRecoveryKeyVerified(
  CryptoSuite suite,
  RecoveryKey rk,
  SealedRecoveryBlob blob, {
  required UmkPublic expected,
}) => verifyRecoveredUmk(
  suite,
  openUmkWithRecoveryKey(suite, rk, blob),
  expected: expected,
);

/// The comparison half of [openUmkWithRecoveryKeyVerified], over a [pair]
/// the caller already holds: returns [pair] when both of its public halves
/// equal [expected] (constant time); otherwise **disposes [pair]** and throws
/// [RecoveredUmkMismatch]. Public so a test can hold the pair and observe the
/// disposal (ADR 2026-10-06d §2: *every buffer is zeroised*).
UmkKeyPair verifyRecoveredUmk(
  CryptoSuite suite,
  UmkKeyPair pair, {
  required UmkPublic expected,
}) {
  final ok =
      suite.constantTimeEquals(pair.public.x25519, expected.x25519) &&
      suite.constantTimeEquals(pair.public.ed25519, expected.ed25519);
  if (!ok) {
    pair.dispose();
    throw const RecoveredUmkMismatch();
  }
  return pair;
}

// ---------------------------------------------------------------------------
// Paper sheet encodings (04 §7.4)
// ---------------------------------------------------------------------------

/// The decoded contents of a sheet: whose key it is and the key itself.
final class RecoverySheet {
  /// Wraps the parts; [rk] is owned by the sheet — [dispose] frees it.
  const RecoverySheet({
    required this.version,
    required this.userId,
    required this.rk,
  });

  /// Sheet format version.
  final int version;

  /// The user the sheet belongs to.
  final String userId;

  /// The recovery key.
  final RecoveryKey rk;

  /// Frees the key.
  void dispose() => rk.dispose();
}

/// A typed sheet whose checksum group does not match its symbols (04 §7.4).
final class RecoverySheetChecksumFailed implements Exception {
  /// Creates the failure.
  const RecoverySheetChecksumFailed();

  @override
  String toString() => 'RecoverySheetChecksumFailed';
}

/// `version ‖ user_id ‖ RK` — the caller zeroises the returned buffer.
Uint8List _sheetPayload(String userId, RecoveryKey rk) {
  final out = Uint8List(_sheetPayloadBytes);
  out[0] = recoverySheetVersion;
  out.setRange(1, 17, Uuid16.toBytes(userId));
  rk.key.runUnlockedSync((b) => out.setRange(17, _sheetPayloadBytes, b));
  return out;
}

RecoverySheet _sheetFromPayload(CryptoSuite suite, Uint8List b) {
  if (b.length != _sheetPayloadBytes) {
    throw FormatException('sheet payload is $_sheetPayloadBytes bytes');
  }
  if (b[0] != recoverySheetVersion) {
    throw FormatException('unknown sheet version ${b[0]}');
  }
  return RecoverySheet(
    version: b[0],
    userId: Uuid16.fromBytes(Uint8List.sublistView(b, 1, 17)),
    rk: RecoveryKey(
      suite.sodium.secureCopy(Uint8List.sublistView(b, 17, _sheetPayloadBytes)),
    ),
  );
}

/// The sheet's QR text (04 §7.4): `base64url( version ‖ user_id ‖ RK )`.
/// This is the spec-mandated exception to "no key in a String" — render it
/// straight into the PDF/QR and drop it.
String recoverySheetQr(String userId, RecoveryKey rk) {
  final payload = _sheetPayload(userId, rk);
  try {
    return Bytes.base64Url(payload);
  } finally {
    // Best effort — the String itself cannot be zeroised (ADR 2026-09-05 §8).
    payload.fillRange(0, payload.length, 0);
  }
}

/// Decodes a scanned sheet QR. Throws [FormatException] on bad base64url,
/// wrong length or unknown version.
RecoverySheet recoverySheetFromQr(CryptoSuite suite, String encoded) {
  final Uint8List b;
  try {
    b = Bytes.fromBase64Url(encoded);
  } on FormatException {
    throw const FormatException('sheet qr is not base64url');
  }
  try {
    return _sheetFromPayload(suite, b);
  } finally {
    suite.zeroize(b);
  }
}

/// Crockford Base32 alphabet (no I, L, O, U).
const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Symbols the base payload occupies: ⌈392 / 5⌉.
const int _sheetSymbols = (_sheetPayloadBytes * 8 + 4) ~/ 5;

/// Crockford symbols of [bytes], MSB first, last symbol zero-padded.
String _crockfordEncode(Uint8List bytes) {
  final sb = StringBuffer();
  var acc = 0;
  var bits = 0;
  for (final byte in bytes) {
    acc = (acc << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      sb.writeCharCode(_crockford.codeUnitAt((acc >> bits) & 0x1f));
    }
    acc &= (1 << bits) - 1;
  }
  if (bits > 0) {
    sb.writeCharCode(_crockford.codeUnitAt((acc << (5 - bits)) & 0x1f));
  }
  return sb.toString();
}

/// Value of one Crockford symbol; accepts lower case and the O→0, I/L→1
/// aliases. Throws [FormatException] on anything else (including U).
int _crockfordValue(int codeUnit) {
  var c = codeUnit;
  if (c >= 0x61 && c <= 0x7a) c -= 0x20; // a-z → A-Z
  switch (c) {
    case 0x4f: // O
      return 0;
    case 0x49: // I
    case 0x4c: // L
      return 1;
  }
  final v = _crockford.indexOf(String.fromCharCode(c));
  if (v < 0) {
    throw FormatException('not a Crockford symbol', String.fromCharCode(c));
  }
  return v;
}

/// Decodes [symbols] (already normalised) into [byteCount] bytes; refuses
/// non-zero padding bits so every payload has exactly one encoding.
Uint8List _crockfordDecode(String symbols, int byteCount) {
  final out = Uint8List(byteCount);
  var acc = 0;
  var bits = 0;
  var o = 0;
  for (var i = 0; i < symbols.length; i++) {
    acc = (acc << 5) | _crockfordValue(symbols.codeUnitAt(i));
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      if (o >= byteCount) {
        throw const FormatException('typed sheet has too many symbols');
      }
      out[o++] = (acc >> bits) & 0xff;
      acc &= (1 << bits) - 1;
    }
  }
  if (o != byteCount) {
    throw const FormatException('typed sheet has too few symbols');
  }
  if (acc != 0) {
    throw const FormatException('typed sheet has non-zero padding bits');
  }
  return out;
}

/// The checksum group: the first two Crockford symbols (10 bits) of
/// BLAKE2b-256 over the payload bytes.
// ⚠️ SPEC: 04 §7.4 says "2-char checksum" without defining it. Implemented as
// the first 2 Crockford symbols of BLAKE2b-256(version ‖ user_id ‖ RK) —
// the suite's own hash, no new primitive (04 §2). Detects any single typo with
// probability 1 − 2⁻¹⁰ on top of the alphabet's own rejection of I/L/O/U.
String _sheetChecksum(CryptoSuite suite, Uint8List payload) =>
    _crockfordEncode(suite.blake2b256(payload)).substring(0, _checksumSymbols);

/// The sheet's typed fallback (04 §7.4): Crockford Base32 of
/// `version ‖ user_id ‖ RK` in groups of 4 separated by `-`, with the 2-char
/// checksum appended as the final group. Same String exception as
/// [recoverySheetQr].
String recoverySheetTyped(CryptoSuite suite, String userId, RecoveryKey rk) {
  final payload = _sheetPayload(userId, rk);
  try {
    final symbols = _crockfordEncode(payload);
    final groups = <String>[
      for (var i = 0; i < symbols.length; i += 4)
        symbols.substring(i, i + 4 > symbols.length ? symbols.length : i + 4),
      _sheetChecksum(suite, payload),
    ];
    return groups.join('-');
  } finally {
    suite.zeroize(payload);
  }
}

/// Decodes a typed sheet. Case-insensitive; accepts the Crockford aliases
/// (O→0, I/L→1); ignores hyphens and whitespace. Throws
/// [RecoverySheetChecksumFailed] when the final group does not match, and
/// [FormatException] on a foreign symbol, wrong length or unknown version.
RecoverySheet recoverySheetFromTyped(CryptoSuite suite, String typed) {
  final symbols = typed.replaceAll(RegExp(r'[-\s]'), '');
  if (symbols.length != _sheetSymbols + _checksumSymbols) {
    throw FormatException(
      'typed sheet is ${_sheetSymbols + _checksumSymbols} symbols, '
      'got ${symbols.length}',
    );
  }
  final body = symbols.substring(0, _sheetSymbols);
  final check = symbols.substring(_sheetSymbols);
  final payload = _crockfordDecode(body, _sheetPayloadBytes);
  try {
    final expected = _sheetChecksum(suite, payload);
    final typedCheck = String.fromCharCodes(
      check.codeUnits.map((c) => _crockford.codeUnitAt(_crockfordValue(c))),
    );
    if (typedCheck != expected) throw const RecoverySheetChecksumFailed();
    return _sheetFromPayload(suite, payload);
  } finally {
    suite.zeroize(payload);
  }
}

// ---------------------------------------------------------------------------
// Rung 4 — head escrow (04 §7.5)
// ---------------------------------------------------------------------------

/// Head escrow (04 §7.5): seals the member's **Personal-Book BK only** to the
/// ceremony-verified head. Never the UMK — the head may eventually read the
/// book; they can never *become* the member. The release policy (member
/// approval, or head request + 30-day veto window) is a server-side object
/// (M4) and is not modelled here. Revocation rotates the Personal BK
/// ([rotateBookKey]) rather than deleting anything.
WrappedBookKey sealPersonalBookKeyForHead(
  CryptoSuite suite,
  BookKey personal,
  VerifiedUmkPublic head,
) => wrapBookKey(suite, personal, head);
