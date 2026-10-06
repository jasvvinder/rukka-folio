// The resume sync nudge, held behind the relock (ADR 2026-10-06 §3 🔒, 05 §7).
//
// 05 §7 makes a resume a foreground pull. After the background timeout
// (07 §5.6) the same resume puts S15 up, and ruling 3 says nothing that needs
// the device keys runs until the gate or the MPIN — a pull whose access token
// has lapsed refreshes it by signing with the device key. S15 seals the store
// as it mounts ([SealingBiometricGate.sealBehindLock]), which happens in the
// first frame after the resume, so the nudge waits for that frame and then
// runs only if the store is still open. When S15 was put up, the unlock that
// reopens the store is the nudge instead ([KeychainKeyStore.onReopened],
// wired by bootstrap).
import 'package:flutter/widgets.dart';

/// Nudges sync on every resume, after the frame that may have sealed the
/// device keys, and only while they are open. Register it with
/// `WidgetsBinding.instance.addObserver(...)` in place of a bare resume
/// observer.
class RelockAwareSyncNudge with WidgetsBindingObserver {
  /// [sealed] reads the device-key store; [nudge] is the sync trigger.
  RelockAwareSyncNudge({required this.sealed, required this.nudge});

  /// Whether the device-key store is closed right now.
  final bool Function() sealed;

  /// The foreground pull (`EngineSyncClient.onAppForeground`).
  final void Function() nudge;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (!sealed()) nudge();
    });
    binding.scheduleFrame();
  }
}
