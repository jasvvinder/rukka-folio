// The camera the three recovery scans read through (ADR 2026-09-19 ruling 1
// 🔒) — S11.2's own key, S11.3's sheet, S11.7's candidate.
//
// The scan seams (`shared/sync/recovery_seams.dart`) are context-free on
// purpose: the screen asks *verify*, and only an outcome comes back, so no
// payload or key ever reaches a widget. But a camera needs a screen to draw
// its preview on. [RecoveryCamera] is the bridge, and it is deliberately
// small:
//
//   * The recovery routes wrap S11.2, S11.3 and S11.7 in a
//     [RecoveryCameraHost], which lends the camera **that route's
//     navigator** for as long as it is mounted.
//   * [RecoveryCamera.read] pushes [QrScanScreen] on the navigator lent last,
//     with a fresh scanner from [newScanner] (each screen disposes its own),
//     and maps how it ended onto [RecoveryQrRead].
//   * With no navigator lent — a scan asked for from somewhere no recovery
//     screen is showing — the answer is [RecoveryQrNoCamera], i.e.
//     `RecoveryScanOutcome.unavailable`: the honest *this phone cannot scan
//     here*, never a camera opened over a screen that did not ask for one.
import 'package:flutter/material.dart';

import '../../shared/sync/recovery_seams.dart';
import '../ceremony/camera_scanner.dart';
import '../ceremony/screens/qr_scan_screen.dart';

/// The recovery scans' camera. One per app; installed with
/// [RecoveryCameraScope] and handed, as [read], to the scan seams.
final class RecoveryCamera {
  /// Opens scanners with [newScanner].
  RecoveryCamera({required this.newScanner});

  /// One scanner per read; the scan screen disposes it.
  final CeremonyScannerFactory newScanner;

  final List<NavigatorState> _lent = [];

  /// Called by [RecoveryCameraHost] while a recovery screen is mounted.
  void lend(NavigatorState navigator) {
    _lent
      ..remove(navigator)
      ..add(navigator);
  }

  /// The inverse of [lend].
  void giveBack(NavigatorState navigator) => _lent.remove(navigator);

  /// A [RecoveryQrReader]: one read, decoded by [decode].
  Future<RecoveryQrRead<T>> read<T extends Object>(
    T? Function(String text) decode,
  ) async {
    NavigatorState? navigator;
    for (final n in _lent.reversed) {
      if (n.mounted) {
        navigator = n;
        break;
      }
    }
    if (navigator == null) return RecoveryQrNoCamera<T>();
    final result = await navigator.push<QrScanResult<T>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => QrScanScreen<T>(scanner: newScanner(), decode: decode),
      ),
    );
    return switch (result) {
      null => RecoveryQrCancelled<T>(),
      QrScanNoCamera() => RecoveryQrNoCamera<T>(),
      QrScanned(:final value) => RecoveryQrValue<T>(value),
    };
  }
}

/// Installs the [RecoveryCamera] above the app.
class RecoveryCameraScope extends InheritedWidget {
  /// Installs [camera].
  const RecoveryCameraScope({
    super.key,
    required this.camera,
    required super.child,
  });

  /// The one camera.
  final RecoveryCamera camera;

  /// The nearest camera, or null.
  static RecoveryCamera? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RecoveryCameraScope>()?.camera;

  @override
  bool updateShouldNotify(RecoveryCameraScope old) => camera != old.camera;
}

/// Lends this route's navigator to the scope's [RecoveryCamera] while
/// mounted. With no scope it is a pass-through, and a scan then answers
/// *unavailable* — the honest state, never a red screen.
class RecoveryCameraHost extends StatefulWidget {
  /// Wraps [child].
  const RecoveryCameraHost({super.key, this.camera, required this.child});

  /// Wins over the scope's (tests).
  final RecoveryCamera? camera;

  /// The recovery screen.
  final Widget child;

  @override
  State<RecoveryCameraHost> createState() => _RecoveryCameraHostState();
}

class _RecoveryCameraHostState extends State<RecoveryCameraHost> {
  RecoveryCamera? _camera;
  NavigatorState? _navigator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(RecoveryCameraHost old) {
    super.didUpdateWidget(old);
    if (widget.camera != old.camera) _bind();
  }

  void _bind() {
    final camera = widget.camera ?? RecoveryCameraScope.maybeOf(context);
    final navigator = Navigator.maybeOf(context);
    if (camera == _camera && navigator == _navigator) return;
    _release();
    _camera = camera;
    _navigator = navigator;
    if (camera != null && navigator != null) camera.lend(navigator);
  }

  void _release() {
    final n = _navigator;
    if (n != null) _camera?.giveBack(n);
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
