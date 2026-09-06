import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sodium/sodium.dart';

import 'bytes.dart';
import 'suite.dart';

// ⚠️ SPEC (M3 interpretation): 04 §3 names the UMK as "X25519 pair + Ed25519
// pair" and treats `UMK_priv` as one blob (split by Shamir, sealed under RK,
// wrapped to devices). libsodium regenerates both pairs deterministically from
// 32-byte seeds, so `UMK_priv` is represented as the 64 bytes
// `x25519_seed ‖ ed25519_seed`; the same shape serves device keys. The public
// halves are always re-derived from the seeds, never stored beside them.

/// The user's fingerprint (04 §3.1): `BLAKE2b-256(UMK_pub_x25519 ‖ UMK_pub_ed25519)`.
/// This is the value the ceremony confirms and the trust chain roots on.
@immutable
final class Fingerprint {
  /// Wraps 32 hash bytes.
  Fingerprint(Uint8List bytes) : bytes = Uint8List.fromList(bytes) {
    if (bytes.length != 32) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'fingerprint is 32 bytes',
      );
    }
  }

  /// Computes the fingerprint of [umk].
  factory Fingerprint.of(CryptoSuite suite, UmkPublic umk) =>
      Fingerprint(suite.blake2b256(Bytes.concat([umk.x25519, umk.ed25519])));

  /// The 32 bytes.
  final Uint8List bytes;

  /// Lower-case hex, for logs of *fingerprints* (never keys) and for equality
  /// in maps.
  String get hex => Bytes.hex(bytes);

  @override
  bool operator ==(Object other) =>
      other is Fingerprint && Bytes.equal(bytes, other.bytes);

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => 'Fingerprint(${hex.substring(0, 8)}…)';
}

/// UMK public halves **as relayed by the server** (04 §3.1). Not yet bound to
/// a human: nothing may be sealed to this type. The ceremony (04 §6) turns it
/// into a [VerifiedUmkPublic].
@immutable
final class UmkPublic {
  /// Wraps the two 32-byte public keys.
  UmkPublic({required Uint8List x25519, required Uint8List ed25519})
    : x25519 = Uint8List.fromList(x25519),
      ed25519 = Uint8List.fromList(ed25519) {
    if (x25519.length != 32 || ed25519.length != 32) {
      throw ArgumentError('UMK public halves are 32 bytes each');
    }
  }

  /// X25519 public key — receives wrapped book keys.
  final Uint8List x25519;

  /// Ed25519 public key — verifies device certificates.
  final Uint8List ed25519;

  @override
  bool operator ==(Object other) =>
      other is UmkPublic &&
      Bytes.equal(x25519, other.x25519) &&
      Bytes.equal(ed25519, other.ed25519);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(x25519), Object.hashAll(ed25519));
}

/// How a fingerprint was bound to a human (04 §6.4), recorded on every
/// verification event.
enum VerificationMethod {
  /// QR scanned in person (default).
  qrInPerson,

  /// 8-digit code read over voice/video and typed.
  codeRemote,
}

/// A UMK public key whose fingerprint **a human confirmed by ceremony**
/// (04 §6). The only type a book key, guardian share or UMK may be sealed to
/// (04 §5.1, §8.2). Constructed solely by `ceremony.dart` — there is no public
/// constructor, which is what makes rule 8.2 structural.
@immutable
final class VerifiedUmkPublic {
  /// Internal: produced by the ceremony after a byte-for-byte or code match.
  @internal
  const VerifiedUmkPublic.internal(this.public, this.fingerprint, this.method);

  /// The verified keys.
  final UmkPublic public;

  /// Their fingerprint.
  final Fingerprint fingerprint;

  /// How they were verified.
  final VerificationMethod method;
}

/// A UMK with its private halves (04 §3.1) — exists only on the user's own
/// devices. Secrets live in [SecureKey]; call [dispose] when done.
final class UmkKeyPair {
  UmkKeyPair._(this.public, this._xSeed, this._edSeed, this._x, this._ed);

  /// Generates a fresh UMK from the suite's random source (signup, 04 §3.1;
  /// UMK rotation, 04 §9.2).
  factory UmkKeyPair.generate(CryptoSuite suite) {
    final seed = suite.randomBytes(64);
    try {
      return UmkKeyPair.fromSecretBytes(suite, seed);
    } finally {
      suite.zeroize(seed);
    }
  }

  /// Rebuilds the UMK from its 64 secret bytes (`x25519_seed ‖ ed25519_seed`)
  /// — the shape Shamir splits, RK seals and devices hold wrapped. [secret] is
  /// copied; the caller zeroises its own buffer.
  factory UmkKeyPair.fromSecretBytes(CryptoSuite suite, Uint8List secret) {
    if (secret.length != 64) {
      throw ArgumentError.value(
        secret.length,
        'secret',
        'UMK secret is 64 bytes',
      );
    }
    final s = suite.sodium;
    final xSeed = s.secureCopy(Uint8List.sublistView(secret, 0, 32));
    final edSeed = s.secureCopy(Uint8List.sublistView(secret, 32, 64));
    final x = s.crypto.box.seedKeyPair(xSeed);
    final ed = s.crypto.sign.seedKeyPair(edSeed);
    return UmkKeyPair._(
      UmkPublic(x25519: x.publicKey, ed25519: ed.publicKey),
      xSeed,
      edSeed,
      x,
      ed,
    );
  }

  /// Public halves.
  final UmkPublic public;
  final SecureKey _xSeed;
  final SecureKey _edSeed;
  final KeyPair _x;
  final KeyPair _ed;
  bool _disposed = false;

  /// True once [dispose] ran; every secret accessor then throws [StateError]
  /// (reading freed guarded memory would otherwise crash the VM).
  bool get isDisposed => _disposed;

  void _live() {
    if (_disposed) throw StateError('UmkKeyPair used after dispose()');
  }

  /// X25519 secret key (unseals book keys wrapped to this UMK).
  SecureKey get x25519Secret {
    _live();
    return _x.secretKey;
  }

  /// Ed25519 secret key (signs device certificates, 04 §3.4).
  SecureKey get ed25519Secret {
    _live();
    return _ed.secretKey;
  }

  /// Copies the 64 secret bytes out for splitting or sealing. The returned
  /// buffer is the caller's to zeroise.
  Uint8List exportSecretBytes() {
    _live();
    final out = Uint8List(64);
    _xSeed.runUnlockedSync((b) => out.setRange(0, 32, b));
    _edSeed.runUnlockedSync((b) => out.setRange(32, 64, b));
    return out;
  }

  /// Zeroises and frees every secret. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _xSeed.dispose();
    _edSeed.dispose();
    _x.dispose();
    _ed.dispose();
  }

  @override
  String toString() => 'UmkKeyPair(secret)';
}

/// A device's public keys (04 §3.3) plus its id — what a certificate binds.
@immutable
final class DevicePublic {
  /// Wraps the id and the two 32-byte public keys.
  DevicePublic({
    required this.deviceId,
    required Uint8List ed25519,
    required Uint8List x25519,
  }) : ed25519 = Uint8List.fromList(ed25519),
       x25519 = Uint8List.fromList(x25519) {
    if (!Uuid16.isCanonical(deviceId)) {
      throw FormatException('device_id must be a canonical uuid', deviceId);
    }
    if (ed25519.length != 32 || x25519.length != 32) {
      throw ArgumentError('device public halves are 32 bytes each');
    }
  }

  /// Device id (uuid).
  final String deviceId;

  /// Ed25519 public key — verifies entry signatures and auth challenges.
  final Uint8List ed25519;

  /// X25519 public key — receives the wrapped UMK (linking, 04 §9.1).
  final Uint8List x25519;

  @override
  bool operator ==(Object other) =>
      other is DevicePublic &&
      deviceId == other.deviceId &&
      Bytes.equal(ed25519, other.ed25519) &&
      Bytes.equal(x25519, other.x25519);

  @override
  int get hashCode =>
      Object.hash(deviceId, Object.hashAll(ed25519), Object.hashAll(x25519));
}

/// A device's key pairs (04 §3.3). On a phone the Ed25519 half lives in the
/// hardware keystore and the X25519 half rests under a hardware-backed AES
/// key; here both are libsodium [SecureKey]s the platform layer feeds in.
final class DeviceKeyPair {
  DeviceKeyPair._(this.public, this._ed, this._x);

  /// Generates a fresh device from the suite's random source.
  factory DeviceKeyPair.generate(
    CryptoSuite suite, {
    required String deviceId,
  }) {
    final s = suite.sodium;
    final edSeed = suite.randomSecureKey(s.crypto.sign.seedBytes);
    final xSeed = suite.randomSecureKey(s.crypto.box.seedBytes);
    try {
      final ed = s.crypto.sign.seedKeyPair(edSeed);
      final x = s.crypto.box.seedKeyPair(xSeed);
      return DeviceKeyPair._(
        DevicePublic(
          deviceId: deviceId,
          ed25519: ed.publicKey,
          x25519: x.publicKey,
        ),
        ed,
        x,
      );
    } finally {
      edSeed.dispose();
      xSeed.dispose();
    }
  }

  /// Public halves and id.
  final DevicePublic public;
  final KeyPair _ed;
  final KeyPair _x;
  bool _disposed = false;

  /// True once [dispose] ran; secret accessors then throw [StateError].
  bool get isDisposed => _disposed;

  void _live() {
    if (_disposed) throw StateError('DeviceKeyPair used after dispose()');
  }

  /// Device id.
  String get deviceId => public.deviceId;

  /// Ed25519 secret key (signs envelopes and signed records).
  SecureKey get ed25519Secret {
    _live();
    return _ed.secretKey;
  }

  /// X25519 secret key (unseals the UMK wrapped to this device).
  SecureKey get x25519Secret {
    _live();
    return _x.secretKey;
  }

  /// Zeroises and frees every secret. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ed.dispose();
    _x.dispose();
  }

  @override
  String toString() => 'DeviceKeyPair($deviceId)';
}

/// Identity of a book key: `(book_id, key_version)` (04 §3.2).
@immutable
final class BookKeyRef {
  /// Creates the reference.
  const BookKeyRef({required this.bookId, required this.keyVersion});

  /// Book.
  final String bookId;

  /// Version, from 1; new entries always use the highest.
  final int keyVersion;

  @override
  bool operator ==(Object other) =>
      other is BookKeyRef &&
      bookId == other.bookId &&
      keyVersion == other.keyVersion;

  @override
  int get hashCode => Object.hash(bookId, keyVersion);

  @override
  String toString() => 'BookKeyRef($bookId v$keyVersion)';
}

/// A book's symmetric content key (04 §3.2): XChaCha20-Poly1305, one per
/// `(book_id, key_version)`. Lives in guarded memory; [dispose] when done.
final class BookKey {
  /// Wraps an existing key (after unsealing a wrapped copy).
  BookKey(this.ref, SecureKey key) : _key = key {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'book key is 32 bytes');
    }
  }

  /// Generates version [keyVersion] of [bookId]'s key.
  factory BookKey.generate(
    CryptoSuite suite, {
    required String bookId,
    required int keyVersion,
  }) => BookKey(
    BookKeyRef(bookId: bookId, keyVersion: keyVersion),
    suite.randomSecureKey(
      suite.sodium.crypto.aeadXChaCha20Poly1305IETF.keyBytes,
    ),
  );

  /// Identity.
  final BookKeyRef ref;

  final SecureKey _key;
  bool _disposed = false;

  /// The key; throws [StateError] after [dispose].
  SecureKey get key {
    if (_disposed) throw StateError('BookKey $ref used after dispose()');
    return _key;
  }

  /// True once [dispose] ran.
  bool get isDisposed => _disposed;

  /// Zeroises and frees the key. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _key.dispose();
  }

  @override
  String toString() => 'BookKey($ref)';
}
