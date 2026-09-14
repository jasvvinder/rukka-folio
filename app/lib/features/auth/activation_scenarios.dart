// The 06 §5 activation table, as a pure function — no widgets, no clock, no
// I/O. 06 §5 🔒 lists seven scenarios and the flow each one takes; this file
// is a transcription of that table and nothing more. It invents no rung, no
// ordering of its own beyond what the table and ADR 2026-09-05d §1 state, and
// it does not decide *how* a screen looks — only which screen the scenario is
// designated to reach (13 §3.2 S-ids).
//
// Why it exists: until M7 the mapping lived only in prose, so C-06-17 ("every
// activation scenario reaches its designated screen") had nothing to assert
// against. The router binding is asserted in the test, not here, so this file
// stays free of cross-feature imports (features/README: paths come from
// `RkPaths`, and the onboarding paths are owned by that feature).
//
// ⚠️ SPEC: 13 §3.2 gives **no S-id of its own** to the device-link ceremony
// that 06 §5 row "New phone, has old device" continues into — its S9.2–S9.4
// ceremony screens are *member verification*, not device linking. The
// conservative reading taken here is that every link-or-recover path enters at
// **S11.6**, the fork ("choose the path: old phone · guardians · paper sheet",
// 13 §3.2), which ADR 2026-09-05d §1 also says is where the app tells a user
// who still has a phone to link instead. Reported as an open item rather than
// resolved here.

/// Which phone platform the activation is happening on. 06 §5 splits the
/// reinstall row by it: iOS keeps the Keychain, Android's keystore was wiped.
enum ActivationPlatform {
  /// Keychain survives a reinstall — "on iOS-first this is the common path".
  ios(keystoreSurvivesReinstall: true),

  /// "Reinstall, same Android | Keystore was wiped → treat as **new phone**".
  android(keystoreSurvivesReinstall: false);

  const ActivationPlatform({required this.keystoreSurvivesReinstall});

  final bool keystoreSurvivesReinstall;
}

/// The screen an activation scenario is designated to reach, by 13 §3.2 S-id.
///
/// [built] records whether that screen exists in `app/lib/features/` today.
/// It is documentation of a **gap**, not a behaviour switch: nothing in this
/// file branches on it. See the lane's open items — S11.2, S11.3, S11.5,
/// S11.6 and S11.8 are listed in 13 §3.2 with "activation" as their entry
/// point and have no Dart file yet.
enum ActivationDestination {
  /// S0.3 "What will you use this for?" — the onboarding branch a fresh
  /// signup continues into after S0.2 (07 §3.1 step 3).
  onboardingPurpose('S0.3', built: true),

  /// S11.5 Recovery — silent restore: "key returns from the platform
  /// keychain; the books open by themselves" (13 §3.2, 04 §7.0).
  silentRestore('S11.5', built: false),

  /// S1 Home — a normal device, no recovery (06 §5 "Reinstall, same iPhone").
  home('S1', built: true),

  /// S11.6 Recovery — the fork: old phone · guardians · paper sheet.
  recoveryFork('S11.6', built: false),

  /// S11.8 Recovery — nothing worked yet: "the honest empty-vault screen +
  /// path forward". 06 §5 🔒 is emphatic that this screen must not tell the
  /// user their data is destroyed when it is not.
  emptyVault('S11.8', built: false);

  const ActivationDestination(this.screenId, {required this.built});

  /// The 13 §3.2 row this destination is.
  final String screenId;

  /// Whether a Dart screen for [screenId] exists today (see the class doc).
  final bool built;
}

/// The seven rows of the 06 §5 table, in the order the table lists them.
enum ActivationScenario {
  freshSignup(ActivationDestination.onboardingPurpose),

  /// "New phone, same Apple/Google account — platform key sync (04 §7.0)
  /// restores silently — the common case; no guardians, no sheet."
  platformKeySync(ActivationDestination.silentRestore),

  /// "Reinstall, same iPhone — Keychain intact? → keys found → normal
  /// device, no recovery."
  reinstallSameIphone(ActivationDestination.home),

  /// "Reinstall, same Android — keystore was wiped → treat as new phone."
  reinstallSameAndroid(ActivationDestination.recoveryFork),

  /// "New phone, has old device — OTP → §3 → link via ceremony (04 §9.1)."
  /// Guardian recovery on this row completes only after a 24 h window
  /// (ADR 2026-09-05d §1) — see [guardianRecoveryIsWindowed].
  newPhoneHasOldDevice(ActivationDestination.recoveryFork),

  /// "New phone, no old device — OTP → §3 → recovery ladder (04 §7):
  /// guardians → paper sheet. **Immediate** only if the user has no active
  /// certified device" — which is this row.
  newPhoneNoOldDevice(ActivationDestination.recoveryFork),

  /// "Every rung fails — login succeeds, vault empty."
  everyRungFailed(ActivationDestination.emptyVault);

  const ActivationScenario(this.destination);

  /// The screen 06 §5 + 13 §3.2 designate for this row.
  final ActivationDestination destination;

  /// ADR 2026-09-05d §1 🔒: guardian recovery completes immediately only when
  /// the user has **no active certified device**; otherwise it waits 24 h and
  /// every existing device alarms with one-tap Cancel (S11.9).
  bool get guardianRecoveryIsWindowed =>
      this == ActivationScenario.newPhoneHasOldDevice;
}

/// What the client knows at the moment OTP succeeded (06 §2 → §3). Every
/// field is an observation, never a decision.
final class ActivationSignals {
  const ActivationSignals({
    required this.platform,
    this.knownAccount = false,
    this.reinstall = false,
    this.platformKeysRestored = false,
    this.localKeysFound = false,
    this.hasOtherCertifiedDevice = false,
    this.everyRungFailed = false,
  });

  final ActivationPlatform platform;

  /// The number already has an account (the OTP verify named a `user_id`).
  /// False is a fresh signup.
  final bool knownAccount;

  /// This install is a reinstall on the same handset rather than a new one.
  final bool reinstall;

  /// 04 §7.0 platform key sync handed the keys back silently.
  final bool platformKeysRestored;

  /// Device keys were still in the platform store (06 §3: an existing seed is
  /// reused, so a reinstall on the same iPhone is the same device).
  final bool localKeysFound;

  /// The user still has another **certified** device (06 §6 device list).
  final bool hasOtherCertifiedDevice;

  /// The ladder was walked and every rung failed (06 §5 last row).
  final bool everyRungFailed;
}

/// Which 06 §5 row [signals] is. Pure; total — every combination lands on a
/// row, because 06 §5's last row is the catch-all and its first row is the
/// case where there is no account yet.
ActivationScenario resolveActivationScenario(ActivationSignals signals) {
  // The ladder has already been walked and exhausted; nothing below can undo
  // that, so it is tested first.
  if (signals.everyRungFailed) return ActivationScenario.everyRungFailed;
  if (!signals.knownAccount) return ActivationScenario.freshSignup;
  // "the common case; no guardians, no sheet" — before any ladder rung.
  if (signals.platformKeysRestored) return ActivationScenario.platformKeySync;
  // Keys in the local store only count where the platform keeps them across a
  // reinstall; on Android 06 §5 says the keystore was wiped and the install is
  // treated as a new phone regardless.
  if (signals.localKeysFound && signals.platform.keystoreSurvivesReinstall) {
    return ActivationScenario.reinstallSameIphone;
  }
  if (signals.reinstall && !signals.platform.keystoreSurvivesReinstall) {
    return ActivationScenario.reinstallSameAndroid;
  }
  if (signals.hasOtherCertifiedDevice) {
    return ActivationScenario.newPhoneHasOldDevice;
  }
  return ActivationScenario.newPhoneNoOldDevice;
}
