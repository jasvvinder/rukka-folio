// F1-07-312 — the `mobile_scanner` adapter behind `CeremonyScanner`
// (ADR 2026-09-19 ruling 1 🔒).
//
// The plugin's platform side is replaced by a scripted [MobileScannerPlatform]
// — the plugin's own seam for exactly this — so the controller, the widget
// and the adapter are the real ones and only the camera hardware is fake.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rukka_folio/features/ceremony/camera_scanner.dart';
import 'package:rukka_folio/features/ceremony/ceremony_repository.dart';
import 'package:rukka_folio/features/ceremony/mobile_scanner_adapter.dart';
import 'package:rukka_folio/features/ceremony/screens/s9_3_verify_member_screen.dart';
import 'package:rukka_folio/features/ceremony/widgets/code_boxes.dart';

import '../../shared/test_app.dart';

/// The camera hardware, scripted. [fails] is what `start` throws.
final class _FakeCamera extends MobileScannerPlatform {
  _FakeCamera({this.fails});

  final MobileScannerErrorCode? fails;
  final reads = StreamController<BarcodeCapture?>.broadcast();
  int starts = 0;
  int disposes = 0;
  List<BarcodeFormat>? formats;

  @override
  Stream<BarcodeCapture?> get barcodesStream => reads.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    starts++;
    formats = startOptions.formats;
    final code = fails;
    if (code != null) throw MobileScannerException(errorCode: code);
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(64, 64),
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => disposes++;

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Widget buildCameraView() =>
      const SizedBox.expand(key: ValueKey('camera.view'));

  void read(String text) =>
      reads.add(BarcodeCapture(barcodes: [Barcode(rawValue: text)]));
}

/// A controller whose camera started, for the one path the plugin's widget
/// cannot drive in a widget test (its running preview never settles there).
final class _ReadyController extends MobileScannerController {
  _ReadyController() : super(autoStart: false);

  final _reads = StreamController<BarcodeCapture>.broadcast();
  int starts = 0;
  int disposes = 0;

  @override
  Stream<BarcodeCapture> get barcodes => _reads.stream;

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async => starts++;

  int stops = 0;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {
    disposes++;
    await super.dispose();
  }

  void read(String text) =>
      _reads.add(BarcodeCapture(barcodes: [Barcode(rawValue: text)]));
}

/// A camera that ignores [stop] and keeps decoding — the plugin's behaviour
/// for a controller it did not autostart. Lets a test see that S9.3 itself
/// refuses reads once it has left the camera, not only that it asked.
final class _LeakyCamera implements CeremonyScanner {
  final _codes = StreamController<String>.broadcast();
  int stops = 0;

  void emit(String text) => _codes.add(text);

  @override
  Future<CameraStatus> start() async => CameraStatus.ready;

  @override
  Stream<String> get codes => _codes.stream;

  @override
  Widget buildPreview(BuildContext context) => const SizedBox.expand();

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {
    if (!_codes.isClosed) await _codes.close();
  }
}

/// Mounts [scanner]'s preview (the plugin needs its view attached to start),
/// then starts it.
Future<CameraStatus> _start(
  WidgetTester tester,
  CeremonyScanner scanner,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 64,
        height: 64,
        child: Builder(builder: scanner.buildPreview),
      ),
    ),
  );
  final status = scanner.start();
  await tester.pumpAndSettle();
  return status;
}

void main() {
  late MobileScannerPlatform original;
  setUp(() => original = MobileScannerPlatform.instance);
  tearDown(() => MobileScannerPlatform.instance = original);

  group('F1-07-312 mobile_scanner behind CeremonyScanner '
      '(ADR 2026-09-19 ruling 1 🔒)', () {
    test('F1-07-312 the failure map: refused permission is denied, every '
        'other code — no camera, busy, unknown — is unavailable, none is '
        'ready', () {
      expect(cameraStatusOf(null), CameraStatus.ready);
      for (final code in MobileScannerErrorCode.values) {
        expect(
          cameraStatusOf(MobileScannerException(errorCode: code)),
          code == MobileScannerErrorCode.permissionDenied
              ? CameraStatus.denied
              : CameraStatus.unavailable,
          reason: code.name,
        );
      }
    });

    testWidgets('F1-07-312 a refused permission reaches the seam as denied, '
        'and dispose is safe twice', (tester) async {
      final camera = _FakeCamera(
        fails: MobileScannerErrorCode.permissionDenied,
      );
      MobileScannerPlatform.instance = camera;
      final scanner = MobileScannerCeremonyScanner();
      expect(await _start(tester, scanner), CameraStatus.denied);
      expect(camera.starts, 1);
      await scanner.dispose();
      await scanner.dispose();
      expect(await scanner.start(), CameraStatus.unavailable);
    });

    testWidgets('F1-07-312 an absent camera reaches the seam as unavailable, '
        'and dispose is safe twice', (tester) async {
      MobileScannerPlatform.instance = _FakeCamera(
        fails: MobileScannerErrorCode.unsupported,
      );
      final scanner = MobileScannerCeremonyScanner();
      expect(await _start(tester, scanner), CameraStatus.unavailable);
      await scanner.dispose();
      await scanner.dispose();
    });

    test('F1-07-312 the production controller asks for QR only, reads each '
        'code once, and is started by the adapter', () async {
      MobileScannerPlatform.instance = _FakeCamera();
      final c = qrOnlyController();
      expect(c.formats, [BarcodeFormat.qrCode]);
      expect(c.detectionSpeed, DetectionSpeed.noDuplicates);
      expect(c.autoStart, isFalse);
      await c.dispose();
    });

    test('F1-07-312 a working camera is ready and hands each distinct read '
        'to the seam exactly once; dispose releases it once', () async {
      MobileScannerPlatform.instance = _FakeCamera();
      final controller = _ReadyController();
      final scanner = MobileScannerCeremonyScanner(
        controller: () => controller,
      );
      final seen = <String>[];
      final sub = scanner.codes.listen(seen.add);
      expect(await scanner.start(), CameraStatus.ready);
      expect(controller.starts, 1);

      controller
        ..read('first')
        ..read('first')
        ..read('second');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['first', 'second']);

      await sub.cancel();
      await scanner.dispose();
      await scanner.dispose();
      expect(controller.disposes, 1);
      expect(await scanner.start(), CameraStatus.unavailable);
      expect(controller.starts, 1, reason: 'a disposed adapter stays disposed');
    });

    for (final (fails, line) in [
      (
        MobileScannerErrorCode.permissionDenied,
        'This app hasn’t been given the camera',
      ),
      (
        MobileScannerErrorCode.unsupported,
        'The camera isn’t available on this phone',
      ),
    ]) {
      testWidgets('F1-07-312 S9.3 over the real adapter, ${fails.name}: it '
          'opens on the code path, states why, and draws no preview', (
        tester,
      ) async {
        MobileScannerPlatform.instance = _FakeCamera(fails: fails);
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: FakeVerifyMemberRepository(),
            scanner: MobileScannerCeremonyScanner(),
          ),
          viewport: rkPhone360,
        );
        expect(find.textContaining(line), findsOneWidget);
        expect(find.byType(RkCodeField), findsOneWidget);
        expect(find.byType(MobileScanner), findsNothing);
        expect(find.byKey(const ValueKey('camera.view')), findsNothing);
      });
    }
  });
  group('F1-07-312 leaving the camera stops it (review SCAN1 #5)', () {
    test('F1-07-312 stop() stops the controller and cuts the reads off; a '
        'later start() reads again', () async {
      MobileScannerPlatform.instance = _FakeCamera();
      final controller = _ReadyController();
      final scanner = MobileScannerCeremonyScanner(
        controller: () => controller,
      );
      final seen = <String>[];
      final sub = scanner.codes.listen(seen.add);
      expect(await scanner.start(), CameraStatus.ready);

      await scanner.stop();
      expect(controller.stops, 1, reason: 'the plugin will not stop it');
      controller.read('behind the code field');
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty, reason: 'nothing decoded after stop');

      expect(await scanner.start(), CameraStatus.ready);
      controller.read('again');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['again']);

      await sub.cancel();
      await scanner.dispose();
      await scanner.stop(); // safe after dispose
      expect(controller.stops, 1);
    });

    testWidgets('F1-07-312 S9.3 Enter code instead stops the camera, and a '
        'read still in the pipe is never checked', (tester) async {
      final camera = _LeakyCamera();
      final repository = FakeVerifyMemberRepository();
      await pumpRk(
        tester,
        VerifyMemberScreen(repository: repository, scanner: camera),
        viewport: rkPhone360,
      );
      expect(camera.stops, 0, reason: 'the camera runs while it is shown');

      await tester.tap(find.text('Enter code instead'));
      await tester.pumpAndSettle();
      expect(find.byType(RkCodeField), findsOneWidget);
      expect(camera.stops, 1);

      camera.emit('a code filmed after the switch');
      await tester.pumpAndSettle();
      expect(repository.scanned, isEmpty);
      expect(find.byType(RkCodeField), findsOneWidget);
    });

    testWidgets('F1-07-312 S9.3 over the fake camera: the switch leaves it '
        'stopped, so it films nothing', (tester) async {
      final camera = FakeCeremonyScanner();
      await pumpRk(
        tester,
        VerifyMemberScreen(
          repository: FakeVerifyMemberRepository(),
          scanner: camera,
        ),
        viewport: rkPhone360,
      );
      expect(camera.stopped, isFalse);
      await tester.tap(find.text('Enter code instead'));
      await tester.pumpAndSettle();
      expect(camera.stopped, isTrue);
      expect(camera.stops, 1);
    });
  });
}
