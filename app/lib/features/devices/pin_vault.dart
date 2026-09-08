// The MPIN vault — 06 §4.4 and ADR 2026-09-05d §5, verbatim:
//
//   "5 free attempts, then 30 s, 1 min, 5 min, 15 min, 1 h between attempts;
//    after 10 failures the PIN is disabled and reset requires OTP to the
//    registered number plus biometric. Storage: a 32-byte random key in the
//    hardware-backed keychain (this-device-only) and HMAC(key, pin) compared
//    in constant time; the attempt counter and lockout-until timestamp live in
//    the same protected item so they survive reinstall on iOS and cannot be
//    reset by clearing app data. Never a KDF input (04 §2)."
//
// The PIN is a local gate on the keystore — never a key, never sent to the
// server, never wraps anything (06 §4.4 🔒). This class therefore only ever
// answers "did the person type the PIN they set?" and enforces the attempt
// policy. Everything else — Face ID as the fast path, the S0.8 set-PIN and
// S15.3 unlock screens — sits on top of the small API below (lane U1).
//
// Pure with respect to time and randomness: the clock and the libsodium suite
// are injected (CLAUDE.md rule 3, rule 7). Nothing here logs.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

import '../../shared/seams/key_store.dart';

/// Where the vault stands right now (ADR 2026-09-05d §5).
sealed class PinStatus {
  const PinStatus();
}

/// No PIN has been set on this phone yet (fresh install without a Keychain
/// remnant, or after [PinVault.clear]). S0.8 sets one.
final class PinNotSet extends PinStatus {
  const PinNotSet();
}

/// A PIN is set and an attempt may be made now. [failures] is the running
/// count since the last success (0–9); [attemptsLeft] counts down to the
/// disabled state so a screen can warn before the last one.
final class PinReady extends PinStatus {
  const PinReady({required this.failures});

  final int failures;

  /// Attempts remaining before the PIN is disabled.
  int get attemptsLeft => PinVault.maxFailures - failures;

  /// True once the free attempts are spent — every further miss costs a wait.
  bool get inPenaltyBand => failures >= PinVault.freeAttempts;
}

/// Too many misses: no attempt is accepted until [until] (S15.3 shows the
/// countdown atom). Attempts during the cooldown are refused and **do not**
/// count.
final class PinCooldown extends PinStatus {
  const PinCooldown({required this.until, required this.failures});

  final DateTime until;
  final int failures;
}

/// Ten failures: the PIN is disabled until the person re-verifies by OTP to
/// the registered number **plus** biometric, then sets a new PIN
/// ([PinVault.resetAfterReverification]). Forgetting the PIN is never data
/// loss — nothing is re-encrypted (06 §4.4).
final class PinDisabled extends PinStatus {
  const PinDisabled();
}

/// Outcome of [PinVault.verify].
sealed class PinVerifyResult {
  const PinVerifyResult();
}

/// The PIN matched; the failure counter is back to zero.
final class PinAccepted extends PinVerifyResult {
  const PinAccepted();
}

/// The PIN did not match (or none is set / it is disabled / in cooldown);
/// [status] is the vault's state after this attempt.
final class PinRejected extends PinVerifyResult {
  const PinRejected(this.status);

  final PinStatus status;
}

/// Thrown by [PinVault.setPin] for anything but exactly six ASCII digits.
final class InvalidPinFormat implements Exception {
  const InvalidPinFormat();

  @override
  String toString() => 'InvalidPinFormat: the MPIN is exactly 6 digits';
}

/// The MPIN gate. One instance per app; cheap to construct.
///
/// ```dart
/// final vault = PinVault(keys: RkScope.of(context).keys, suite: suite, now: scope.now);
/// switch (await vault.status()) { PinReady() => …, PinCooldown(:final until) => …, … }
/// final r = await vault.verify(typed);
/// ```
final class PinVault {
  PinVault({required this.keys, required this.suite, required this.now});

  /// Secrets at rest; the whole vault is ONE item so counter, lockout and key
  /// share the item's protection and cannot be reset separately.
  final KeyStore keys;

  /// libsodium (HMAC-SHA512-256 via `crypto_auth`, CSPRNG, `sodium_memcmp`).
  final CryptoSuite suite;

  /// Injected clock.
  final DateTime Function() now;

  /// The one protected item. Not in `KeyIds` (shell-owned); stable forever.
  static const itemId = 'rk.pin.vault';

  /// Free attempts before the first wait (ADR 2026-09-05d §5).
  static const freeAttempts = 5;

  /// Failures at which the PIN is disabled.
  static const maxFailures = 10;

  /// Wait after the 5th, 6th, 7th, 8th and 9th failure respectively.
  static const cooldowns = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  /// Cooldown that follows [failures] misses; null when none applies.
  static Duration? cooldownAfter(int failures) {
    if (failures < freeAttempts || failures >= maxFailures) return null;
    return cooldowns[failures - freeAttempts];
  }

  static final _sixDigits = RegExp(r'^[0-9]{6}$');

  /// Current state, from the stored item and the clock.
  Future<PinStatus> status() async {
    final item = await _load();
    if (item == null) return const PinNotSet();
    try {
      return _statusOf(item);
    } finally {
      item.dispose();
    }
  }

  PinStatus _statusOf(_VaultItem item) {
    if (item.failures >= maxFailures) return const PinDisabled();
    final until = item.lockedUntil;
    if (until != null && now().isBefore(until)) {
      return PinCooldown(until: until, failures: item.failures);
    }
    return PinReady(failures: item.failures);
  }

  /// Sets (or replaces) the PIN: a fresh 32-byte random HMAC key, the tag over
  /// [pin], counter 0, no lockout. Replacing requires the caller to have just
  /// verified the old PIN or completed the reverification path — this class
  /// does not police that, S15.x does.
  Future<void> setPin(String pin) async {
    if (!_sixDigits.hasMatch(pin)) throw const InvalidPinFormat();
    final key = suite.randomBytes(_keyBytes);
    final mac = _mac(key, pin);
    final item = _VaultItem(key: key, mac: mac, failures: 0, lockedUntil: null);
    try {
      await _store(item);
    } finally {
      item.dispose();
    }
  }

  /// Checks [pin]. A miss increments the counter and, from the 5th miss on,
  /// sets the lockout; the 10th disables. During a cooldown or when disabled
  /// nothing is compared and nothing is counted.
  Future<PinVerifyResult> verify(String pin) async {
    final item = await _load();
    if (item == null) return const PinRejected(PinNotSet());
    try {
      final before = _statusOf(item);
      if (before is! PinReady) return PinRejected(before);

      final expected = _mac(item.key, pin);
      final ok = suite.constantTimeEquals(expected, item.mac);
      suite.zeroize(expected);
      if (ok) {
        if (item.failures != 0 || item.lockedUntil != null) {
          final reset = item.copyWith(failures: 0, clearLock: true);
          try {
            await _store(reset);
          } finally {
            reset.dispose();
          }
        }
        return const PinAccepted();
      }

      final failures = item.failures + 1;
      final wait = cooldownAfter(failures);
      final next = item.copyWith(
        failures: failures,
        lockedUntil: wait == null ? null : now().add(wait),
        clearLock: wait == null,
      );
      try {
        await _store(next);
        return PinRejected(_statusOf(next));
      } finally {
        next.dispose();
      }
    } finally {
      item.dispose();
    }
  }

  /// The forgot-PIN / disabled path (06 §4.4): the caller has completed OTP to
  /// the registered number **and** biometric; a new PIN is set and the counter
  /// cleared. Nothing else changes — no key material is touched.
  Future<void> resetAfterReverification(String newPin) => setPin(newPin);

  /// Removes the vault entirely (sign-out with local wipe, 04 §9.2 verified
  /// record). Never called on the server's bare word (ADR 2026-09-05b §2).
  Future<void> clear() => keys.delete(itemId);

  // --- storage -------------------------------------------------------------

  static const _version = 1;
  static const _keyBytes = 32;
  static const _macBytes = 32;
  // version(1) ‖ key(32) ‖ mac(32) ‖ failures u32be(4) ‖ lockedUntil ms i64be(8)
  static const _itemBytes = 1 + _keyBytes + _macBytes + 4 + 8;

  Uint8List _mac(Uint8List key, String pin) {
    final k = suite.sodium.secureCopy(key);
    try {
      return suite.sodium.crypto.auth(
        message: Uint8List.fromList(ascii.encode(pin)),
        key: k,
      );
    } finally {
      k.dispose();
    }
  }

  Future<_VaultItem?> _load() async {
    final raw = await keys.read(itemId);
    if (raw == null) return null;
    try {
      if (raw.length != _itemBytes || raw[0] != _version) {
        // Unknown layout: treat as absent rather than guess (conservative).
        return null;
      }
      final bd = ByteData.sublistView(raw);
      var o = 1;
      final key = Uint8List.fromList(raw.sublist(o, o += _keyBytes));
      final mac = Uint8List.fromList(raw.sublist(o, o += _macBytes));
      final failures = bd.getUint32(o);
      o += 4;
      final lockMs = bd.getInt64(o);
      return _VaultItem(
        key: key,
        mac: mac,
        failures: failures,
        lockedUntil: lockMs == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lockMs, isUtc: true),
      );
    } finally {
      zeroise(raw);
    }
  }

  Future<void> _store(_VaultItem item) async {
    final out = Uint8List(_itemBytes);
    final bd = ByteData.sublistView(out);
    var o = 0;
    out[o++] = _version;
    out.setRange(o, o += _keyBytes, item.key);
    out.setRange(o, o += _macBytes, item.mac);
    bd.setUint32(o, item.failures);
    o += 4;
    bd.setInt64(
      o,
      item.lockedUntil == null
          ? 0
          : item.lockedUntil!.toUtc().millisecondsSinceEpoch,
    );
    try {
      await keys.write(itemId, out);
    } finally {
      zeroise(out);
    }
  }
}

final class _VaultItem {
  _VaultItem({
    required this.key,
    required this.mac,
    required this.failures,
    required this.lockedUntil,
  });

  final Uint8List key;
  final Uint8List mac;
  final int failures;
  final DateTime? lockedUntil;

  _VaultItem copyWith({
    required int failures,
    DateTime? lockedUntil,
    bool clearLock = false,
  }) => _VaultItem(
    key: Uint8List.fromList(key),
    mac: Uint8List.fromList(mac),
    failures: failures,
    lockedUntil: clearLock ? lockedUntil : (lockedUntil ?? this.lockedUntil),
  );

  void dispose() {
    zeroise(key);
    zeroise(mac);
  }
}
