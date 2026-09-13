// The camera, behind a seam — so S9.3's tests never need a device, and so the
// camera-free path (design-system §3.1 rule 7 🔒) is not a fallback bolted on
// afterwards but the same screen with a different source of digits.
//
// ⚠️ WIRE — no camera plugin is in `app/pubspec.yaml` yet (pubspec is the shell
// lane's file). Until one lands, [NoCameraScanner] reports `unavailable` and
// S9.3 opens on the code path, which is a complete way through: a phone with
// no camera has always had to join this way.
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
abstract class CeremonyScanner {
  /// Starts the preview. Never throws — a problem is a [CameraStatus].
  Future<CameraStatus> start();

  /// Decoded QR text, one event per distinct read.
  Stream<String> get codes;

  /// What to draw inside the viewfinder frame. The frame itself belongs to
  /// the screen, so every implementation sits in the same box.
  Widget buildPreview(BuildContext context);

  /// Releases the camera.
  Future<void> dispose();
}

/// The scanner the app ships with until a camera plugin lands: honest about
/// having no camera, so S9.3 shows the code path instead of a dead preview.
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

  /// True once [dispose] ran.
  bool disposed = false;

  final _codes = StreamController<String>.broadcast();

  /// Plays a scan of [text].
  void emit(String text) => _codes.add(text);

  @override
  Future<CameraStatus> start() async {
    starts++;
    return status;
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
