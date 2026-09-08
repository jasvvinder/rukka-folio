// The devices feature's seam to the server-side device list (06 §6), the
// cancel windows (ADR 2026-09-05d §1, §3), the backup settings (04 §7.6) and
// the device-integrity flag (ADR 2026-09-05 §6). Phase A: screens run against
// [FakeDevicesRepository]; the real one lands with the sync/server lanes.
//
// ⚠️ WIRE — the whole interface is this lane's; the server's device rows and
// `recovery_requests` shape it at integration. Nothing here holds money.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'cancel_window.dart';

/// 13 §6 device state model (ADR 2026-09-05f §B).
enum DeviceStatus { uncertified, certified, suspended, revoked }

/// One row on S11 (06 §6: name, model, last active, certified state).
@immutable
final class LinkedDevice {
  const LinkedDevice({
    required this.id,
    required this.name,
    required this.model,
    required this.addedOn,
    required this.lastActive,
    required this.status,
    this.isThisDevice = false,
  });

  final String id;
  final String name;
  final String model;
  final DateTime addedOn;
  final DateTime lastActive;
  final DeviceStatus status;
  final bool isThisDevice;
}

/// S11.4 rows (04 §7.6). Defaults: key sync ON, vault ON, readable ON; the
/// sheet is an explicit action, never a toggle.
enum BackupSetting { platformKeySync, encryptedVault, readableMonthly }

/// What S11 / S11.4 render.
@immutable
final class DevicesSnapshot {
  const DevicesSnapshot({
    this.devices = const [],
    this.windows = const [],
    this.backup = const {
      BackupSetting.platformKeySync: true,
      BackupSetting.encryptedVault: true,
      BackupSetting.readableMonthly: true,
    },
    this.integrityDetectedOn,
    this.readOnly = false,
  });

  final List<LinkedDevice> devices;
  final List<CancelWindow> windows;
  final Map<BackupSetting, bool> backup;

  /// Set once a modified device was detected (S19.5) — the S11 row is
  /// permanent (ADR 2026-09-05 §6).
  final DateTime? integrityDetectedOn;

  /// S12.5 pattern: settings cannot be changed (e.g. suspended device).
  final bool readOnly;

  DevicesSnapshot copyWith({
    List<LinkedDevice>? devices,
    List<CancelWindow>? windows,
    Map<BackupSetting, bool>? backup,
    DateTime? integrityDetectedOn,
    bool? readOnly,
  }) => DevicesSnapshot(
    devices: devices ?? this.devices,
    windows: windows ?? this.windows,
    backup: backup ?? this.backup,
    integrityDetectedOn: integrityDetectedOn ?? this.integrityDetectedOn,
    readOnly: readOnly ?? this.readOnly,
  );
}

/// Thrown by repository calls that failed; screens show the error state and
/// keep the retry path (07 §1 rule 6).
final class DevicesFailure implements Exception {
  const DevicesFailure([this.message = '']);

  final String message;

  @override
  String toString() => 'DevicesFailure($message)';
}

/// What the screens need.
abstract class DevicesRepository {
  /// Current snapshot, then every change. Emits the current value on listen.
  Stream<DevicesSnapshot> watch();

  /// Latest snapshot without subscribing; null until the first load.
  DevicesSnapshot? get current;

  /// (Re)loads from the server; throws [DevicesFailure].
  Future<void> refresh();

  /// Revokes [deviceId] (06 §6). [stolen] takes the 04 §9.2 stolen path:
  /// BK rotation + recommended UMK rotation. Lands as a signed record from
  /// this device (ADR 2026-09-05d §7).
  Future<void> revoke(String deviceId, {bool stolen = false});

  /// One-tap Cancel on S11.9 / S11.10 (ADR 2026-09-05d §1, §3).
  Future<void> cancelWindow(String windowId);

  /// S11.4 toggles (04 §7.6).
  Future<void> setBackup(BackupSetting setting, bool enabled);

  /// S15.4 Retry: re-checks the revocation with the server (ADR 05b §2).
  Future<void> retrySuspended();
}

/// In-memory fake for tests and the Phase A shell.
class FakeDevicesRepository implements DevicesRepository {
  FakeDevicesRepository({DevicesSnapshot? initial}) : _current = initial;

  final _controller = StreamController<DevicesSnapshot>.broadcast();
  DevicesSnapshot? _current;

  /// Next call to any method throws this once, then clears.
  DevicesFailure? failNext;

  /// Ids passed to [revoke], with the stolen flag.
  final revoked = <({String id, bool stolen})>[];

  /// Ids passed to [cancelWindow].
  final cancelled = <String>[];

  /// Times [retrySuspended] ran.
  int retries = 0;

  /// What [refresh] loads when it runs (null keeps the current snapshot).
  DevicesSnapshot? onRefresh;

  @override
  DevicesSnapshot? get current => _current;

  set current(DevicesSnapshot? s) {
    _current = s;
    if (s != null) _controller.add(s);
  }

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Stream<DevicesSnapshot> watch() async* {
    final c = _current;
    if (c != null) yield c;
    yield* _controller.stream;
  }

  @override
  Future<void> refresh() async {
    _maybeFail();
    final next = onRefresh;
    if (next != null) current = next;
  }

  @override
  Future<void> revoke(String deviceId, {bool stolen = false}) async {
    _maybeFail();
    revoked.add((id: deviceId, stolen: stolen));
    final c = _current;
    if (c != null) {
      current = c.copyWith(
        devices: c.devices.where((d) => d.id != deviceId).toList(),
      );
    }
  }

  @override
  Future<void> cancelWindow(String windowId) async {
    _maybeFail();
    cancelled.add(windowId);
    final c = _current;
    if (c != null) {
      current = c.copyWith(
        windows: [
          for (final w in c.windows)
            w.id == windowId ? w.copyWith(cancelled: true) : w,
        ],
      );
    }
  }

  @override
  Future<void> setBackup(BackupSetting setting, bool enabled) async {
    _maybeFail();
    final c = _current ?? const DevicesSnapshot();
    current = c.copyWith(backup: {...c.backup, setting: enabled});
  }

  @override
  Future<void> retrySuspended() async {
    _maybeFail();
    retries++;
  }

  Future<void> dispose() => _controller.close();
}

/// Provides the repository to the devices screens. Integration wraps the app
/// in one; absent, screens fall back to an empty [FakeDevicesRepository].
class DevicesRepositoryScope extends InheritedWidget {
  const DevicesRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final DevicesRepository repository;

  static final _fallback = FakeDevicesRepository(
    initial: const DevicesSnapshot(),
  );

  static DevicesRepository of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DevicesRepositoryScope>()
          ?.repository ??
      _fallback;

  @override
  bool updateShouldNotify(DevicesRepositoryScope old) =>
      repository != old.repository;
}
