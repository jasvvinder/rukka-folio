// The unlock method by name (ADR 2026-10-08 §3 🔒, desk 166).
//
// The app names the method the phone actually uses — Face ID · Touch ID on an
// iPhone, Fingerprint · Face unlock on Android. These are four separate terms,
// never translations of one another, and an Android fingerprint phone is never
// told *Face ID*. The name comes from two facts: the platform the app runs on
// ([TargetPlatform], from the theme — the design captures and the widget tests
// set it) and which biometric is enrolled ([BiometricModality], from the gate
// when it can say).
//
// ⚠️ SPEC: no seam in this build reports the enrolled biometric's modality —
// [BiometricGate.qualifyingBiometricEnrolled] answers yes/no only, and the
// native halves of `rukka_folio/keystore` (features/devices, ios/, android/)
// have no method for it. Until one is wired ([BiometricModalitySource]), the
// method is named neutrally (*Fingerprint or face*), which names nothing the
// phone may not have; the platform still picks the glyph. Owner / devices item
// in the WORDS179 lane report.
import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import 'widgets/face_id_glyph.dart';

/// Which kind of biometric is enrolled — the body part, not the platform.
enum BiometricModality {
  /// A face (iPhone Face ID; an Android Class 3 face).
  face,

  /// A fingerprint (iPhone Touch ID; an Android fingerprint).
  fingerprint,
}

/// The method as the phone names it (ADR 2026-10-08 §3).
enum BiometricKind {
  /// iPhone face.
  faceId,

  /// iPhone fingerprint.
  touchId,

  /// Android fingerprint.
  fingerprint,

  /// Android face.
  faceUnlock;

  /// Whether this method reads a fingerprint (its glyph, its failed line).
  bool get isFingerprint =>
      this == BiometricKind.touchId || this == BiometricKind.fingerprint;
}

/// The kind for [platform] and [modality]; null when either is not known —
/// the caller then names the method neutrally, never by guess.
BiometricKind? biometricKindFor(
  TargetPlatform platform,
  BiometricModality? modality,
) {
  if (modality == null) return null;
  return switch (platform) {
    TargetPlatform.iOS =>
      modality == BiometricModality.face
          ? BiometricKind.faceId
          : BiometricKind.touchId,
    TargetPlatform.android =>
      modality == BiometricModality.face
          ? BiometricKind.faceUnlock
          : BiometricKind.fingerprint,
    _ => null,
  };
}

/// A gate that can say which biometric is enrolled. Optional: a gate that
/// cannot say leaves the method named neutrally.
abstract interface class BiometricModalitySource {
  /// The enrolled modality, or null when the platform will not say. Never
  /// prompts and never throws.
  Future<BiometricModality?> enrolledModality();
}

/// Asks [gate] for its modality when it can say; null otherwise (or on any
/// failure — the neutral name is the safe side).
Future<BiometricModality?> enrolledModalityOf(Object? gate) async {
  if (gate is! BiometricModalitySource) return null;
  try {
    return await gate.enrolledModality();
  } on Object {
    return null;
  }
}

/// The words and glyph for one phone's unlock method.
final class BiometricWords {
  /// The words for [kind] (null: not known) on [platform].
  const BiometricWords(this.l10n, this.kind, this.platform);

  /// Reads the platform from [context]'s theme.
  factory BiometricWords.of(BuildContext context, BiometricModality? modality) {
    final platform = Theme.of(context).platform;
    return BiometricWords(
      AppLocalizations.of(context),
      biometricKindFor(platform, modality),
      platform,
    );
  }

  final AppLocalizations l10n;
  final BiometricKind? kind;
  final TargetPlatform platform;

  /// The method's name on its own — the S15.3 button, and the `{method}` of
  /// a line that names it as a noun.
  String get name => switch (kind) {
    BiometricKind.faceId => l10n.lockMethodFaceId,
    BiometricKind.touchId => l10n.lockMethodTouchId,
    BiometricKind.fingerprint => l10n.lockMethodFingerprint,
    BiometricKind.faceUnlock => l10n.lockMethodFaceUnlock,
    null => l10n.lockMethodAny,
  };

  /// The method inside a sentence (*You'll use your fingerprint …*).
  String get inline => switch (kind) {
    BiometricKind.fingerprint => l10n.lockMethodFingerprintInline,
    null => l10n.lockMethodAnyInline,
    _ => name,
  };

  /// The S15 line after the sensor said no.
  String get failed => switch (kind) {
    null => l10n.lockBiometricFailedAny,
    final k when k.isFingerprint => l10n.lockBiometricFailedFingerprint,
    _ => l10n.lockBiometricFailed,
  };

  /// Whether the glyph is a fingerprint: the kind's own, or — not known —
  /// the platform's drawn frame (c3 S15 *waiting for fingerprint · Android*).
  bool get fingerprintGlyph =>
      kind?.isFingerprint ?? platform == TargetPlatform.android;

  /// The method's glyph at [size] in [color].
  Widget glyph({
    required double size,
    required Color color,
    bool compact = false,
    String? semanticLabel,
  }) => fingerprintGlyph
      ? Icon(
          Icons.fingerprint,
          size: size,
          color: color,
          semanticLabel: semanticLabel,
        )
      : FaceIdGlyph(
          size: size,
          color: color,
          compact: compact,
          semanticLabel: semanticLabel,
        );
}
