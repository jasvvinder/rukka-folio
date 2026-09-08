@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/features/devices/cancel_window.dart';
import 'package:rukka_folio/features/devices/devices_repository.dart';
import 'package:rukka_folio/features/devices/screens/s11_4_backup_screen.dart';
import 'package:rukka_folio/features/devices/screens/s11_9_10_cancel_window_screen.dart';
import 'package:rukka_folio/features/devices/screens/s11_devices_screen.dart';
import 'package:rukka_folio/features/devices/screens/s15_4_suspended_screen.dart';
import 'package:rukka_folio/features/devices/screens/s19_5_modified_device_screen.dart';
import 'package:rukka_folio/features/devices/widgets/countdown.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

final class _Clock {
  DateTime now = DateTime(2026, 9, 7, 10);
  DateTime call() => now;
}

final _thisPhone = LinkedDevice(
  id: 'd-this',
  name: 'My phone',
  model: 'Pixel 8',
  addedOn: DateTime(2026, 8, 1),
  lastActive: DateTime(2026, 9, 7, 9),
  status: DeviceStatus.certified,
  isThisDevice: true,
);
final _other = LinkedDevice(
  id: 'd-2',
  name: 'Papa’s phone',
  model: 'Redmi Note 12',
  addedOn: DateTime(2026, 9, 6),
  lastActive: DateTime(2026, 9, 6, 20),
  status: DeviceStatus.uncertified,
);

Widget _scoped(DevicesRepository repo, Widget child) =>
    DevicesRepositoryScope(repository: repo, child: child);

void main() {
  group('S11 Devices & security (13 §3.2, 07 §15, 06 §6)', () {
    testWidgets(
      'F1-06-8 populated: backup row first, this phone badged, other phone with model, added/last-active dates, certified state, Remove + stolen entry points; the integrity row appears when set',
      (tester) async {
        final repo = FakeDevicesRepository(
          initial: DevicesSnapshot(
            devices: [_thisPhone, _other],
            integrityDetectedOn: DateTime(2026, 9, 6),
          ),
        );
        var backupOpened = 0;
        await pumpRk(
          tester,
          _scoped(repo, DevicesScreen(onOpenBackup: () => backupOpened++)),
        );
        expect(find.text('Devices & security'), findsOneWidget);
        expect(find.text('Backup'), findsOneWidget);
        expect(find.text('This phone'), findsOneWidget);
        expect(find.text('Papa’s phone'), findsOneWidget);
        expect(find.text('Redmi Note 12'), findsOneWidget);
        expect(find.textContaining('Added Yesterday'), findsOneWidget);
        expect(find.textContaining('Last active Today'), findsOneWidget);
        expect(find.text('Verified'), findsOneWidget);
        expect(find.text('Not yet verified'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        expect(find.text('This phone was stolen'), findsOneWidget);
        await tester.tap(find.text('Backup'));
        expect(backupOpened, 1);
        await tester.scrollUntilVisible(
          find.text('Phone integrity'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Phone integrity'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-06-9 Remove opens a confirm sheet and revokes through the repository; the stolen path states the four 04 §9.2 consequences before confirm and passes stolen: true',
      (tester) async {
        final repo = FakeDevicesRepository(
          initial: DevicesSnapshot(devices: [_thisPhone, _other]),
        );
        await pumpRk(tester, _scoped(repo, const DevicesScreen()));
        await tester.tap(find.text('This phone was stolen'));
        await tester.pumpAndSettle();
        expect(
          find.text('Before you confirm, this is what will happen:'),
          findsOneWidget,
        );
        expect(find.textContaining('Papa’s phone is removed'), findsOneWidget);
        expect(
          find.textContaining('Every book you can read gets a new key'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Your master key is replaced too'),
          findsOneWidget,
        );
        expect(
          find.textContaining('anything it sends after this is set aside'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repo.revoked, isEmpty);
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(find.text('Remove Papa’s phone?'), findsOneWidget);
        await tester.tap(find.text('Remove phone'));
        await tester.pumpAndSettle();
        expect(repo.revoked, [(id: 'd-2', stolen: false)]);
        expect(find.text('Papa’s phone'), findsNothing);
        expect(find.text('Only this phone is linked.'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-06-10 loading skeleton, error-with-retry, empty (one next action) and offline chip',
      (tester) async {
        final repo = FakeDevicesRepository()
          ..failNext = const DevicesFailure('boom');
        final sync = FakeSyncClient(initial: const Offline());
        await pumpRk(tester, _scoped(repo, const DevicesScreen()), sync: sync);
        expect(find.text('Couldn’t load your phones.'), findsOneWidget);
        repo.onRefresh = DevicesSnapshot(devices: [_thisPhone]);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Only this phone is linked.'), findsOneWidget);
        expect(find.text('Link another phone'), findsOneWidget);
        expect(
          find.text('Offline — showing what this phone last saw.'),
          findsOneWidget,
        );

        // A fresh key: the same widget type at the same slot would keep the
        // previous State (and StreamBuilder's last data) across pumps.
        final slow = FakeDevicesRepository();
        await pumpRk(tester, _scoped(slow, DevicesScreen(key: UniqueKey())));
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics && w.properties.label == 'Loading your phones',
          ),
          findsOneWidget,
        );
        expect(find.text('Only this phone is linked.'), findsNothing);
        expect(find.text('Devices & security'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-06-11 an open 24 h window shows as a card at the top with countdown and one-tap Cancel; a cancelled or completed one leaves the list; PA renders',
      (tester) async {
        final clock = _Clock();
        final w = CancelWindow(
          id: 'rec-1',
          kind: CancelWindowKind.recovery,
          openedAt: clock.now.subtract(const Duration(minutes: 1)),
          requesterName: 'Sunita',
          newDeviceFingerprint: 'K7Q2-M9XA',
        );
        final repo = FakeDevicesRepository(
          initial: DevicesSnapshot(devices: [_thisPhone], windows: [w]),
        );
        await pumpRk(
          tester,
          _scoped(repo, const DevicesScreen()),
          now: clock.call,
        );
        expect(find.text('Needs your attention'), findsOneWidget);
        expect(find.text('Recovery in progress'), findsOneWidget);
        expect(
          find.textContaining('Sunita is restoring your account'),
          findsOneWidget,
        );
        expect(find.text('New phone’s code: K7Q2-M9XA'), findsOneWidget);
        expect(find.text('Completes in 23 h 59 min'), findsOneWidget);
        await tester.tap(find.text('Cancel this'));
        await tester.pumpAndSettle();
        expect(repo.cancelled, ['rec-1']);
        expect(find.text('Recovery in progress'), findsNothing);

        await pumpRk(
          tester,
          _scoped(
            FakeDevicesRepository(
              initial: DevicesSnapshot(devices: [_thisPhone]),
            ),
            const DevicesScreen(),
          ),
          locale: const Locale('pa'),
        );
        expect(find.text('ਡਿਵਾਈਸ ਤੇ ਸੁਰੱਖਿਆ'), findsOneWidget);
      },
    );
  });

  group('S11.4 Backup settings (04 §7.6, ADR 2026-09-05f §G)', () {
    testWidgets(
      'F1-06-12 four rows with their risk lines verbatim, toggles reach the repository, a failed save shows the error and the switch keeps the stored value, read-only disables everything, offline shows the saved chip',
      (tester) async {
        final repo = FakeDevicesRepository(initial: const DevicesSnapshot());
        await pumpRk(tester, _scoped(repo, const BackupScreen()));
        expect(
          find.textContaining('a phone backup does not carry your books'),
          findsOneWidget,
        );
        expect(
          find.text(
            'This file is readable. Anyone with your Drive can read your books.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Anyone who opens this file can open your books.'),
          findsOneWidget,
        );
        expect(find.text('Save or print'), findsOneWidget);
        expect(find.byType(Switch), findsNWidgets(3));
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        expect(repo.current!.backup[BackupSetting.platformKeySync], isFalse);

        repo.failNext = const DevicesFailure();
        await tester.tap(find.byType(Switch).at(1));
        await tester.pumpAndSettle();
        expect(
          find.text('Couldn’t save that change. Try again.'),
          findsOneWidget,
        );
        expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);

        final ro = FakeDevicesRepository(
          initial: const DevicesSnapshot(readOnly: true),
        );
        await pumpRk(tester, _scoped(ro, const BackupScreen()));
        expect(
          find.text(
            'Read only on this phone — these settings can’t be changed here.',
          ),
          findsOneWidget,
        );
        for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
          expect(s.onChanged, isNull);
        }

        final off = FakeDevicesRepository(initial: const DevicesSnapshot());
        await pumpRk(
          tester,
          _scoped(off, const BackupScreen()),
          sync: FakeSyncClient(initial: const Offline()),
        );
        await tester.tap(find.byType(Switch).last);
        await tester.pumpAndSettle();
        expect(find.text('Saved on phone · will sync'), findsOneWidget);

        await pumpRk(
          tester,
          _scoped(
            FakeDevicesRepository(initial: const DevicesSnapshot()),
            const BackupScreen(),
          ),
          locale: const Locale('hi'),
        );
        expect(find.text('बैकअप'), findsOneWidget);
      },
    );
  });

  group('S11.9 / S11.10 cancel windows (ADR 2026-09-05d §1, §3; 05i §9)', () {
    testWidgets(
      'F1-06-13 S11.10 support action: verbatim body, countdown ticks against the injected clock, Cancel at 23 h 59 works and shows Cancelled; a failed cancel shows the error and keeps the button',
      (tester) async {
        final clock = _Clock();
        final w = CancelWindow(
          id: 'sup-1',
          kind: CancelWindowKind.support,
          openedAt: clock.now,
          targetDeviceName: 'Papa’s phone',
        );
        final repo = FakeDevicesRepository(
          initial: DevicesSnapshot(windows: [w]),
        );
        await pumpRk(
          tester,
          _scoped(repo, const CancelWindowScreen(windowId: 'sup-1')),
          now: clock.call,
        );
        expect(find.text('Support action pending'), findsOneWidget);
        expect(
          find.text(
            'Support removed Papa’s phone at your request. Not you? Cancel.',
          ),
          findsOneWidget,
        );
        expect(find.text('Completes in 24 h 0 min'), findsOneWidget);
        clock.now = clock.now.add(const Duration(hours: 23, minutes: 59));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Completes in 1 min'), findsOneWidget);
        repo.failNext = const DevicesFailure();
        await tester.tap(find.text('Cancel this'));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Couldn’t cancel. Try again.'), findsOneWidget);
        expect(find.text('Cancel this'), findsOneWidget);
        await tester.tap(find.text('Cancel this'));
        await tester.pump(const Duration(seconds: 1));
        expect(repo.cancelled, ['sup-1']);
        expect(find.text('Cancelled.'), findsOneWidget);
        expect(find.text('Cancel this'), findsNothing);
      },
    );

    testWidgets(
      'F1-06-14 S11.9 recovery window: at exactly 24 h the card reads completed and Cancel is gone (clock jump, ADR 05i §9); countdown formats <1 h and <1 min',
      (tester) async {
        final clock = _Clock();
        final w = CancelWindow(
          id: 'rec-1',
          kind: CancelWindowKind.recovery,
          openedAt: clock.now,
          requesterName: 'Sunita',
        );
        final repo = FakeDevicesRepository(
          initial: DevicesSnapshot(windows: [w]),
        );
        await pumpRk(
          tester,
          _scoped(repo, const CancelWindowScreen(windowId: 'rec-1')),
          now: clock.call,
        );
        expect(find.text('Recovery in progress'), findsOneWidget);
        clock.now = clock.now.add(
          const Duration(hours: 23, minutes: 59, seconds: 20),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Completes in 40 s'), findsOneWidget);
        clock.now = clock.now.add(const Duration(seconds: 40));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('The waiting period has ended.'), findsOneWidget);
        expect(find.text('Cancel this'), findsNothing);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(Scaffold).first),
        );
        expect(
          formatCountdown(l10n, const Duration(minutes: 12, seconds: 5)),
          '12 min',
        );
      },
    );
  });

  group('S15.4 Device suspended · S19.5 Modified device', () {
    testWidgets(
      'F1-06-15 S15.4: persistent banner + read-only explanation, Retry shows Checking… and reaches the repository, Devices & security path present; HI renders',
      (tester) async {
        final repo = FakeDevicesRepository(initial: const DevicesSnapshot());
        var opened = 0;
        await pumpRk(
          tester,
          _scoped(repo, SuspendedScreen(onOpenDevices: () => opened++)),
        );
        expect(
          find.text('This phone is paused — read only. Sync has stopped.'),
          findsOneWidget,
        );
        expect(find.text('This phone is paused'), findsOneWidget);
        expect(
          find.textContaining('Nothing has been deleted from this phone.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Try again'));
        await tester.pump();
        expect(repo.retries, 1);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Devices & security'));
        expect(opened, 1);
        await pumpRk(
          tester,
          _scoped(repo, const SuspendedScreen()),
          locale: const Locale('hi'),
        );
        expect(find.text('यह फ़ोन रोका गया है'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-06-16 S19.5: the 07 §24 notice verbatim, a path to Devices & security and a dismiss — never blocks; PA renders',
      (tester) async {
        var opened = 0;
        var dismissed = 0;
        await pumpRk(
          tester,
          ModifiedDeviceScreen(
            onOpenDevices: () => opened++,
            onDismiss: () => dismissed++,
          ),
        );
        expect(find.text('This phone has been modified'), findsOneWidget);
        expect(
          find.text(
            'Your books are still encrypted, but anyone who controls this phone can see what you see. Make sure your backups are set.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Devices & security'));
        await tester.tap(find.text('Got it'));
        expect(opened, 1);
        expect(dismissed, 1);
        expect(find.byType(PopScope), findsNothing);
        await pumpRk(
          tester,
          const ModifiedDeviceScreen(),
          locale: const Locale('pa'),
        );
        expect(find.text('ਇਸ ਫ਼ੋਨ ਵਿੱਚ ਬਦਲਾਅ ਕੀਤਾ ਗਿਆ ਹੈ'), findsOneWidget);
      },
    );
  });
}
