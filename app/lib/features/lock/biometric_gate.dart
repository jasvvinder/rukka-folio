// The biometric seam (07 §5.6, 06 §4.4). Face ID / Touch ID is not a setting:
// it already guards the keystore item holding the device key, so it is *how*
// the app opens. This file is only the boundary — the platform call lives
// behind it, so every screen and every widget test speaks to the same small
// contract and no lock screen ever imports a plugin.
//
// The device passcode is never offered as a fallback (06 §4.4 🔒): in a joint
// family the passcode is common knowledge, which is the whole reason the MPIN
// exists. A gate implementation must therefore never ask for it.
import 'dart:async';

/// What a biometric attempt came back with.
enum BiometricOutcome {
  /// The person proved themselves; the keystore item is readable.
  success,

  /// The sensor ran and said no (wrong face, too many tries at the OS level).
  failed,

  /// The person dismissed the sheet themselves.
  cancelled,

  /// No usable biometric on this phone right now (none enrolled, hardware
  /// locked out, simulator). The MPIN carries the unlock instead.
  unavailable,

  /// The enrolled set changed, so the `biometryCurrentSet` item is no longer
  /// readable by biometrics: the app asks for the MPIN once and re-creates the
  /// item (ADR 2026-09-05d §4). A distinct outcome because it has its own copy.
  reenrolled,
}

/// Raises the platform biometric sheet.
abstract interface class BiometricGate {
  /// Prompts with [reason] as the platform's own reason string. Never throws
  /// for a refusal — a refusal is an outcome, so the caller always has a path
  /// (07 §1 rule 6, no dead ends).
  Future<BiometricOutcome> authenticate({required String reason});
}

/// A scripted gate for tests and for hosts with no biometric wired yet.
final class FakeBiometricGate implements BiometricGate {
  /// Answers [outcomes] in order, then repeats the last one forever.
  FakeBiometricGate([
    List<BiometricOutcome> outcomes = const [BiometricOutcome.success],
  ]) : _outcomes = List.of(outcomes);

  final List<BiometricOutcome> _outcomes;

  /// Reason strings seen, in order (for assertions).
  final List<String> prompts = [];

  @override
  Future<BiometricOutcome> authenticate({required String reason}) async {
    prompts.add(reason);
    if (_outcomes.isEmpty) return BiometricOutcome.unavailable;
    return _outcomes.length == 1 ? _outcomes.first : _outcomes.removeAt(0);
  }
}
