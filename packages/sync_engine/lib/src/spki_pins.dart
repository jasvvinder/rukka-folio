// SPKI pin set for the API host (05 §1; ADR 2026-09-05 §1). Pure: the TLS
// layer hands over the SHA-256 SPKI hashes of the presented chain and asks.
// Key, not certificate; two pins minimum (current + backup) so rotation is never
// an outage; pin failure is a hard fail with no fallback and no override.
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One pin: `sha256(SubjectPublicKeyInfo)`.
@immutable
final class SpkiPin {
  /// Creates a pin over a 32-byte digest.
  SpkiPin(Uint8List sha256, {this.label})
    : sha256 = Uint8List.fromList(sha256) {
    if (sha256.length != 32) {
      throw ArgumentError.value(sha256.length, 'sha256', 'must be 32 bytes');
    }
  }

  /// The digest.
  final Uint8List sha256;

  /// Human label for the runbook (`intermediate-2026`, `backup-ca`).
  final String? label;

  bool _same(Uint8List other) {
    if (other.length != 32) return false;
    var diff = 0;
    for (var i = 0; i < 32; i++) {
      diff |= sha256[i] ^ other[i];
    }
    return diff == 0;
  }

  @override
  bool operator ==(Object other) => other is SpkiPin && _same(other.sha256);

  @override
  int get hashCode => Object.hashAll(sha256);

  @override
  String toString() => 'SpkiPin(${label ?? '…'})';
}

/// Verdict of a chain check.
enum PinVerdict {
  /// Some SPKI in the chain matches a pin.
  matched,

  /// No SPKI matched — hard fail, no fallback.
  failed,

  /// Pinning disabled (local-dev build only).
  disabledLocalDev,
}

/// The pin set. Immutable; [rotate] returns the next set and refuses any set
/// that would leave fewer than two pins.
@immutable
final class SpkiPins {
  /// Creates a set of at least two pins.
  SpkiPins(Iterable<SpkiPin> pins, {this.localDevDisabled = false})
    : pins = List.unmodifiable(pins.toSet()) {
    if (!localDevDisabled && this.pins.length < minPins) {
      throw ArgumentError(
        'SPKI pin set needs at least $minPins pins (current + backup)',
      );
    }
  }

  /// A local-dev set with pinning off. Only a `--dart-define` local build may
  /// construct this; the release lane asserts it never does (ADR 2026-09-05 §1).
  const SpkiPins.localDev() : pins = const [], localDevDisabled = true;

  /// Current + backup.
  static const int minPins = 2;

  /// The pins.
  final List<SpkiPin> pins;

  /// Whether pinning is disabled (local-dev only).
  final bool localDevDisabled;

  /// Checks the presented chain's SPKI digests (leaf → root).
  PinVerdict check(Iterable<Uint8List> chainSpkiSha256) {
    if (localDevDisabled) return PinVerdict.disabledLocalDev;
    for (final spki in chainSpkiSha256) {
      for (final p in pins) {
        if (p._same(spki)) return PinVerdict.matched;
      }
    }
    return PinVerdict.failed;
  }

  /// Rotation step: add [add] and retire [retire]. Every intermediate set
  /// keeps ≥ 2 pins, so a client on either the old or the new set still
  /// matches during the changeover (runbook: add the new backup, ship, move
  /// traffic, then retire the old pin in a later release).
  SpkiPins rotate({
    Iterable<SpkiPin> add = const [],
    Iterable<SpkiPin> retire = const [],
  }) {
    if (localDevDisabled) {
      throw StateError('a local-dev set has no pins to rotate');
    }
    final next = {...pins, ...add}..removeAll(retire);
    if (next.length < minPins) {
      throw StateError(
        'rotation would leave ${next.length} pin(s); keep at least $minPins',
      );
    }
    return SpkiPins(next);
  }
}
