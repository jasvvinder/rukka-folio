// The one place `package:mobile_scanner` enters the app (ADR 2026-09-19
// ruling 1 🔒). Everything else — S9.3, the recovery scans of S11.2, S11.3 and
// S11.7 — talks to [CeremonyScanner] and never learns which camera it got.
//
// What the adapter promises, and why each line is here:
//
//   * **Never throws from [start].** The plugin reports a failed start in two
//     ways (a thrown `MobileScannerException`, or the controller's
//     `value.error` after a swallowed one); both become a [CameraStatus].
//     Permission refused → [CameraStatus.denied]; no camera, a camera held by
//     something else, or anything the plugin cannot name → [CameraStatus
//     .unavailable]. The screens already draw both honestly: S9.3 opens on
//     *Enter code instead* (design-system §3.1 rule 7 🔒), a recovery scan
//     returns `RecoveryScanOutcome.unavailable`.
//   * **QR only.** `formats: [qrCode]` — the app renders exactly one kind of
//     code (04 §6.1, §7.4, §9.1) and has no reason to decode any other.
//   * **One event per distinct read.** `DetectionSpeed.noDuplicates`, plus a
//     last-text guard, because a code held in front of the lens is read many
//     times a second and each screen wants one answer.
//   * **Safe to dispose twice**, and safe to dispose before start finished —
//     a person backing out of the scanner while the permission prompt is up.
//
// The preview must be mounted for the plugin to start (v7 waits ~500 ms for
// its view to attach, then gives up), which is why the seam's screens draw
// [buildPreview] while [start] is in flight.
//
// Nothing here logs. A read QR is key material or names a user (CLAUDE.md
// rule 4); it goes to [codes] and nowhere else.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'camera_scanner.dart';

/// Maps a plugin failure onto the seam's vocabulary (ADR 2026-09-19 §1).
///
/// Null — no failure — is [CameraStatus.ready]. Only a refused permission is
/// [CameraStatus.denied]; every other code, including the ones a later plugin
/// version might add, is [CameraStatus.unavailable], because "this phone
/// cannot scan right now" is the one reading that never promises a camera.
CameraStatus cameraStatusOf(MobileScannerException? error) =>
    switch (error?.errorCode) {
      null => CameraStatus.ready,
      MobileScannerErrorCode.permissionDenied => CameraStatus.denied,
      _ => CameraStatus.unavailable,
    };

/// Makes the controller. Production is [qrOnlyController]; a test may pass
/// its own.
typedef MobileScannerControllerFactory = MobileScannerController Function();

/// The production controller: QR only, one event per distinct read, started
/// by the adapter (so a failure comes back through `start()`).
MobileScannerController qrOnlyController() => MobileScannerController(
  // The adapter starts it, so a failure comes back through `start()`.
  autoStart: false,
  formats: const [BarcodeFormat.qrCode],
  detectionSpeed: DetectionSpeed.noDuplicates,
);

/// [CeremonyScanner] over `mobile_scanner`.
///
/// One instance serves one screen: the screen that was handed it disposes it
/// (the [CeremonyScannerFactory] contract), and a disposed adapter stays
/// disposed — [start] then answers [CameraStatus.unavailable].
final class MobileScannerCeremonyScanner implements CeremonyScanner {
  /// Creates the adapter. The controller is made now, so [buildPreview] can
  /// mount its view before [start] runs.
  MobileScannerCeremonyScanner({
    MobileScannerControllerFactory controller = qrOnlyController,
  }) : _controller = controller();

  final MobileScannerController _controller;
  final _codes = StreamController<String>.broadcast();
  StreamSubscription<BarcodeCapture>? _reads;
  String? _last;
  bool _disposed = false;

  @override
  Future<CameraStatus> start() async {
    if (_disposed) return CameraStatus.unavailable;
    try {
      await _controller.start();
    } on MobileScannerException catch (e) {
      return cameraStatusOf(e);
    } on Object {
      // A platform we cannot name failing in a way it cannot name: still no
      // camera, never a crash (07 §1 rule 6).
      return CameraStatus.unavailable;
    }
    if (_disposed) return CameraStatus.unavailable;
    final status = cameraStatusOf(_controller.value.error);
    if (status != CameraStatus.ready) return status;
    _reads ??= _controller.barcodes.listen(_onCapture, onError: (_) {});
    return CameraStatus.ready;
  }

  void _onCapture(BarcodeCapture capture) {
    if (_codes.isClosed) return;
    for (final code in capture.barcodes) {
      final text = code.rawValue;
      if (text == null || text.isEmpty || text == _last) continue;
      _last = text;
      _codes.add(text);
    }
  }

  /// Stops the camera and the reads, keeping the adapter for a later
  /// [start]. This is not left to the plugin: with `autoStart: false` the
  /// `MobileScanner` widget stops only a controller it autostarted, and it
  /// watches the app lifecycle only for a controller it made itself — so a
  /// screen that leaves the preview (S9.3's *Enter code instead*) would
  /// otherwise leave the camera filming, and decoding, behind the code field.
  @override
  Future<void> stop() async {
    if (_disposed) return;
    unawaited(_reads?.cancel());
    _reads = null;
    try {
      await _controller.stop();
    } on Object {
      // A camera that never started, or a platform that cannot say: the
      // reads are already cut off above, which is the part that matters.
    }
  }

  @override
  Stream<String> get codes => _codes.stream;

  @override
  Widget buildPreview(BuildContext context) => _disposed
      ? const SizedBox.expand()
      : MobileScanner(
          controller: _controller,
          // The plugin's own placeholder and error boxes are black and carry
          // English text; the screen's frame and copy are the app's, so both
          // are replaced by an empty box that fills the viewfinder.
          placeholderBuilder: (_) => const SizedBox.expand(),
          errorBuilder: (_, _) => const SizedBox.expand(),
        );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Neither is awaited: a broadcast stream's `close` completes when its
    // done event is delivered, which a listener that has gone quiet can hold
    // up — and releasing the camera must never wait on a listener.
    unawaited(_reads?.cancel());
    _reads = null;
    if (!_codes.isClosed) unawaited(_codes.close());
    try {
      await _controller.dispose();
    } on Object {
      // Releasing a camera that never started is not a failure worth a
      // screen; the controller is unusable either way.
    }
  }
}
