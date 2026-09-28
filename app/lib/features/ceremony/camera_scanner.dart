// The camera, behind a seam — so S9.3's tests never need a device, and so the
// camera-free path (design-system §3.1 rule 7 🔒) is not a fallback bolted on
// afterwards but the same screen with a different source of digits.
//
// ADR 2026-09-19 ruling 1 🔒: `mobile_scanner` enters the app **only** through
// this seam (`mobile_scanner_adapter.dart`); no screen imports the package.
// Its failures map onto this file's vocabulary — permission refused →
// [CameraStatus.denied], no camera or a busy one → [CameraStatus.unavailable]
// — and [NoCameraScanner] and [FakeCeremonyScanner] stay, so every widget test
// keeps running without a camera.
import 'dart:async';

import 'package:flutter/widgets.dart';

/// What the camera can do right now.
enum CameraStatus {
  /// Preview is running; QR text will arrive on [CeremonyScanner.codes].
  ready,

  /// No camera on this device, or it is held by something else.
  unavailable,

  /// The user has not granted camera permission.
  denied,
}

/// A QR source. Implementations must be safe to [dispose] twice.
///
/// A screen draws [buildPreview] **while [start] is in flight** (S9.3 and the
/// recovery scan both open on the viewfinder): the `mobile_scanner` adapter
/// can only start a camera whose view is mounted, and waits a moment for it.
abstract class CeremonyScanner {
  /// Starts the preview. Never throws — a problem is a [CameraStatus].
  Future<CameraStatus> start();

  /// Decoded QR text, one event per distinct read.
  Stream<String> get codes;

  /// What to draw inside the viewfinder frame. The frame itself belongs to
  /// the screen, so every implementation sits in the same box.
  Widget buildPreview(BuildContext context);

  /// Stops the camera while the screen that holds it stays open — S9.3's
  /// *Enter code instead* — so nothing is filmed or decoded behind a code
  /// field that no longer shows a preview. After [stop], [codes] emits
  /// nothing more until [start] runs again. Safe before [start] and after
  /// [dispose].
  Future<void> stop();

  /// Releases the camera.
  Future<void> dispose();
}

/// Makes a fresh scanner for one screen. A scanner is owned by the screen it
/// was handed to, which disposes it — so a scope that outlives screens carries
/// a factory, never one instance (a second S9.3 would get a released camera).
typedef CeremonyScannerFactory = CeremonyScanner Function();

/// The scanner for a build with no camera: honest about it, so S9.3 shows the
/// code path instead of a dead preview.
final class NoCameraScanner implements CeremonyScanner {
  /// Creates the scanner.
  NoCameraScanner();

  final _codes = StreamController<String>.broadcast();

  @override
  Future<CameraStatus> start() async => CameraStatus.unavailable;

  @override
  Stream<String> get codes => _codes.stream;

  @override
  Widget buildPreview(BuildContext context) => const SizedBox.expand();

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    if (!_codes.isClosed) await _codes.close();
  }
}

/// A scripted scanner for tests and for the design preview: [status] decides
/// which S9.3 state opens, [emit] plays a scan.
final class FakeCeremonyScanner implements CeremonyScanner {
  /// Opens with [status] (default [CameraStatus.ready]).
  FakeCeremonyScanner({this.status = CameraStatus.ready});

  /// What [start] reports.
  CameraStatus status;

  /// How many times [start] was called.
  int starts = 0;

  /// How many times [stop] was called.
  int stops = 0;

  /// True between a [stop] and the next [start]: a stopped camera films
  /// nothing, so [emit] then delivers nothing — which is what lets a test see
  /// that a screen stopped it rather than merely stopped listening.
  bool stopped = false;

  /// True once [dispose] ran.
  bool disposed = false;

  final _codes = StreamController<String>.broadcast();

  /// Plays a scan of [text].
  void emit(String text) {
    if (stopped || _codes.isClosed) return;
    _codes.add(text);
  }

  @override
  Future<CameraStatus> start() async {
    starts++;
    stopped = false;
    return status;
  }

  @override
  Future<void> stop() async {
    stops++;
    stopped = true;
  }

  @override
  Stream<String> get codes => _codes.stream;

  @override
  Widget buildPreview(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('ceremony.preview.fake'));

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!_codes.isClosed) await _codes.close();
  }
}

/// Takes one scanner for the life of this element and hands it to [builder].
///
/// The scanner is **not** disposed here: the screen [builder] returns owns it
/// (S9.3 and the recovery scan dispose theirs). What this adds is that a
/// rebuild — a scope notifying, a route re-running its builder — never takes
/// a second camera for a screen that already has one.
class CeremonyScannerOwner extends StatefulWidget {
  /// Takes with [take], builds with [builder].
  const CeremonyScannerOwner({
    super.key,
    required this.take,
    required this.builder,
  });

  /// Called once, in `initState`.
  final CeremonyScanner Function() take;

  /// Builds the screen that owns the scanner.
  final Widget Function(BuildContext context, CeremonyScanner scanner) builder;

  @override
  State<CeremonyScannerOwner> createState() => _CeremonyScannerOwnerState();
}

class _CeremonyScannerOwnerState extends State<CeremonyScannerOwner> {
  late final CeremonyScanner _scanner = widget.take();

  @override
  Widget build(BuildContext context) => widget.builder(context, _scanner);
}
