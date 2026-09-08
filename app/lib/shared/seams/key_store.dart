// Key-material seam (04 §3.3, 06 §3, ADR 2026-09-05d §4): where the device
// keeps secrets at rest — device private keys, the wrapped UMK, the SQLCipher
// database key. The interface is bytes-in, bytes-out by a stable id; the real
// implementation is the platform keystore (iOS Keychain / Android StrongBox,
// lane C at M6) and the fake is memory. Never a `String` key (B-04-8), never
// the database, never SharedPreferences.
//
// Callers zeroise what they read as soon as they are done with it; the store
// zeroises its own copies on `delete`. Nothing here logs.
import 'dart:typed_data';

/// Stable ids for the secrets the app keeps (one item each).
abstract final class KeyIds {
  /// SQLCipher key for the local ledger database (03 §3; 32 bytes).
  static const databaseKey = 'rk.db.key';

  /// This device's Ed25519 signing key (04 §3.3).
  static const deviceSigningKey = 'rk.device.sign';

  /// This device's X25519 key-agreement key (04 §3.3).
  static const deviceAgreementKey = 'rk.device.agree';

  /// The user's master key, wrapped to this device (04 §3.1, §3.4).
  static const wrappedUmk = 'rk.umk.wrapped';
}

/// Secrets at rest. Implementations must be hardware-backed where the
/// platform allows and bound to the current biometric set (ADR 2026-09-05d §4).
abstract class KeyStore {
  /// Returns a fresh copy of the bytes stored under [id], or null.
  Future<Uint8List?> read(String id);

  /// Stores a copy of [bytes] under [id], replacing any previous value.
  Future<void> write(String id, Uint8List bytes);

  /// Removes [id]; a no-op when absent. Zeroises the stored copy.
  Future<void> delete(String id);

  /// Whether [id] is present, without reading it.
  Future<bool> contains(String id);
}

/// Overwrites [bytes] with zeros in place.
void zeroise(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

/// In-memory store for tests and the Phase A shell. Not persistent; never
/// ships as the production store.
class FakeKeyStore implements KeyStore {
  final Map<String, Uint8List> _items = {};

  /// Ids written so far, in order (for assertions).
  final List<String> writes = [];

  @override
  Future<Uint8List?> read(String id) async {
    final v = _items[id];
    return v == null ? null : Uint8List.fromList(v);
  }

  @override
  Future<void> write(String id, Uint8List bytes) async {
    final old = _items[id];
    if (old != null) zeroise(old);
    _items[id] = Uint8List.fromList(bytes);
    writes.add(id);
  }

  @override
  Future<void> delete(String id) async {
    final old = _items.remove(id);
    if (old != null) zeroise(old);
  }

  @override
  Future<bool> contains(String id) async => _items.containsKey(id);
}
