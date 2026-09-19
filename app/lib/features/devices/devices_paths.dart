// Paths of this feature — aliases of `RkPaths` (features/README: never re-type
// a path). S11 is reached from Menu (S8); mounted on the root navigator.
import '../../shared/router.dart';

abstract final class DevicesPaths {
  /// S11 Devices & security.
  static const devices = RkPaths.devices;

  /// S11.4 Backup settings.
  static const backup = RkPaths.devicesBackup;

  /// S11.9 / S11.10 cancel window; `:id` is the window id.
  static const window = RkPaths.devicesWindow;
  static String windowFor(String id) => '${RkPaths.devices}/window/$id';

  /// S11.1 Guardian setup — the screen behind the S11 *Trusted members* row.
  ///
  /// ⚠️ WIRE — `RkPaths` gains `devicesGuardians` at integration (router.dart
  /// is the shell's file, not this lane's); until then the literal lives here,
  /// built from [devices] so the two can never drift.
  static const guardians = RkPaths.devicesGuardians;

  /// S15.4 Device suspended (global).
  static const suspended = RkPaths.suspended;

  /// S19.5 This phone has been modified (global, once per app version).
  static const modified = RkPaths.modifiedDevice;
}
