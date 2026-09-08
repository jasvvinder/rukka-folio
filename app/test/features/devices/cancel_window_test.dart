@Tags(['C'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/cancel_window.dart';
import 'package:rukka_folio/features/devices/devices_repository.dart';

void main() {
  final opened = DateTime.utc(2026, 9, 7, 4, 30);

  group('24 h cancel windows (ADR 2026-09-05d §1, §3; 05i §9 clock jumps)', () {
    test('C-05d-8 support-initiated revocation: window completes at exactly 24 h, cancel at 23 h 59 still works, and the cancel reaches the repository as the one-tap action', () async {
      final w = CancelWindow(
        id: 'sup-1',
        kind: CancelWindowKind.support,
        openedAt: opened,
        targetDeviceName: 'Papa’s phone',
      );
      expect(w.remaining(opened), const Duration(hours: 24));
      final almost = opened.add(const Duration(hours: 23, minutes: 59));
      expect(w.canCancel(almost), isTrue);
      expect(w.isComplete(almost), isFalse);
      expect(w.remaining(almost), const Duration(minutes: 1));
      final at24 = opened.add(const Duration(hours: 24));
      expect(w.isComplete(at24), isTrue);
      expect(w.canCancel(at24), isFalse);
      expect(w.remaining(at24.add(const Duration(hours: 5))), Duration.zero);

      final repo = FakeDevicesRepository(
        initial: DevicesSnapshot(windows: [w]),
      );
      await repo.cancelWindow('sup-1');
      expect(repo.cancelled, ['sup-1']);
      expect(repo.current!.windows.single.cancelled, isTrue);
      expect(repo.current!.windows.single.canCancel(opened), isFalse);
    });

    test('C-05d-10 guardian recovery while a device is active: the window carries requester name + new-device fingerprint, waits 24 h, and a cancel closes it; a failed cancel leaves it open for retry', () async {
      final w = CancelWindow(
        id: 'rec-1',
        kind: CancelWindowKind.recovery,
        openedAt: opened,
        requesterName: 'Sunita',
        newDeviceFingerprint: 'K7Q2-M9XA',
      );
      expect(w.requesterName, 'Sunita');
      expect(w.newDeviceFingerprint, 'K7Q2-M9XA');
      expect(w.completesAt, opened.add(const Duration(hours: 24)));

      final repo = FakeDevicesRepository(initial: DevicesSnapshot(windows: [w]))
        ..failNext = const DevicesFailure('offline');
      await expectLater(
        repo.cancelWindow('rec-1'),
        throwsA(isA<DevicesFailure>()),
      );
      expect(repo.current!.windows.single.canCancel(opened), isTrue);
      await repo.cancelWindow('rec-1');
      expect(repo.current!.windows.single.cancelled, isTrue);
    });
  });
}
