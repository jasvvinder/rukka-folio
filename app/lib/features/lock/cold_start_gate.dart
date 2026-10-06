// The cold-start door (ADR 2026-10-06 §3 🔒, 07 §5.6, 13 §3.2 S15).
//
// On any install with an MPIN, bootstrap mounts this gate **before** the
// ledger opens: the device-key store is sealed (keychain_key_store.dart), and
// nothing that needs the device keys — the reopen's unwrap, signing, sync —
// runs until the person is through S15 by one of two doors:
//   • the gate read with the biometric ([attempt] → the platform prompt over
//     the gate item; its success opens the store); or
//   • the MPIN (the vault's `onPinProven` opens the store; attempt policy ADR
//     2026-09-05d §5 unchanged).
// Only then does [open] read the device keys. A cancelled or failed biometric
// leaves *Use PIN instead* on S15 — never RukkaFolioBlocked. An invalidated gate
// (a fingerprint or face added or removed) is [BiometricOutcome.reenrolled]:
// S15 asks for the MPIN once; the PIN's `afterPinProven` mints a new gate and
// the device keys, the UMK copy and the books are untouched (ruling 4).
//
// Legacy installs (ruling 5) whose device keys still sit in the biometric-bound
// class have no gate yet: [attempt] answers `null`, and the device-key read in
// [open] raises the platform prompt itself, as before ADR 2026-10-06. If that
// class was invalidated the material is gone ([KeyStoreInvalidated]); nothing
// is deleted (ruling 4: no error path removes a device-key item) and the host
// goes to recovery ([ColdStartResult.keysLost]).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../l10n/gen/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../shared/ledger/local_ledger.dart' show DeviceKeysMissing;
import '../../shared/theme.dart';
import '../devices/keychain_key_store.dart';
import '../devices/pin_vault.dart';
import 'biometric_gate.dart';
import 'lock_scope.dart';
import 'screens/s15_lock_screen.dart';

/// How the cold start ended.
enum ColdStartResult {
  /// The person is through and the ledger is open.
  opened,

  /// The device keys are absent, or a legacy biometric-bound class was
  /// invalidated: nothing was removed, and the books need the recovery ladder.
  keysLost,

  /// The device keys opened, but the wrapped UMK they unwrap is gone; nothing
  /// was removed, and the books need the recovery ladder.
  umkMissing,
}

/// The bare app the gate runs in: theme, the person's language and the three
/// locales — nothing composed yet, because nothing is open yet.
class ColdStartApp extends StatelessWidget {
  const ColdStartApp({
    super.key,
    required this.child,
    this.locale,
    this.themeMode = ThemeMode.system,
  });

  final Widget child;
  final Locale? locale;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context).appName,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: rkLocalizationsDelegates,
    theme: rkTheme(Brightness.light),
    darkTheme: rkTheme(Brightness.dark),
    themeMode: themeMode,
    home: child,
  );
}

/// S15 in front of the cold-start ledger open.
class ColdStartGate extends StatefulWidget {
  const ColdStartGate({
    super.key,
    required this.vault,
    required this.attempt,
    required this.open,
    required this.onDone,
  });

  /// The MPIN vault — the same one the app uses. Its `onPinProven` must open
  /// the device-key store (bootstrap wires it).
  final PinVault vault;

  /// The biometric door ([KeystoreBiometricGate.openAtColdStart]): the gate
  /// read; [BiometricOutcome.pinOnly] when there is no gate; `null` when the
  /// device-key read itself prompts (a legacy biometric-bound install).
  final Future<BiometricOutcome?> Function(String reason) attempt;

  /// Opens the ledger, which reads the device keys.
  final Future<void> Function() open;

  /// Called once, when the person is through (or the books need recovery).
  final void Function(ColdStartResult result) onDone;

  @override
  State<ColdStartGate> createState() => _ColdStartGateState();
}

class _ColdStartGateState extends State<ColdStartGate> {
  late final _gate = _OpeningGate(this);
  LockReason _reason = LockReason.routine;
  int _round = 0;
  bool _opened = false;
  bool _legacy = false;
  bool _legacyLost = false;
  bool _done = false;

  Future<BiometricOutcome> _attempt(String reason) async {
    if (_opened) return BiometricOutcome.success;
    final o = await widget.attempt(reason);
    if (o == null) {
      _legacy = true;
      return _tryOpen();
    }
    if (o != BiometricOutcome.success) return o;
    return _tryOpen();
  }

  Future<BiometricOutcome> _tryOpen() async {
    if (_opened) return BiometricOutcome.success;
    try {
      await widget.open();
      _opened = true;
      return BiometricOutcome.success;
    } on DeviceKeysSealed {
      // Neither door has opened the store: stay on S15.
      return BiometricOutcome.unavailable;
    } on KeyStoreInvalidated {
      // A legacy biometric-bound class the platform dropped: the material is
      // gone. The PIN first (06 §4.4 — never reveal more before it), then
      // recovery; nothing is removed.
      _legacyLost = true;
      return BiometricOutcome.reenrolled;
    } on DeviceKeysMissing catch (e) {
      _finish(
        e.deviceKeys ? ColdStartResult.keysLost : ColdStartResult.umkMissing,
      );
      return BiometricOutcome.success;
    } on PlatformException catch (e) {
      return _cancelled(e)
          ? BiometricOutcome.cancelled
          : BiometricOutcome.failed;
    }
  }

  /// Android BiometricPrompt: ERROR_CANCELED 5, ERROR_USER_CANCELED 10,
  /// ERROR_NEGATIVE_BUTTON 13 (the plugin's "Biometric authentication error
  /// [n]", FlutterSecureStorage.java:1305-1308). iOS: errSecUserCanceled -128.
  static bool _cancelled(PlatformException e) {
    final text = '${e.message ?? ''} ${e.details ?? ''}';
    return text.contains('error [5]') ||
        text.contains('error [10]') ||
        text.contains('error [13]') ||
        text.contains('-128');
  }

  void _finish(ColdStartResult r) {
    if (_done) return;
    _done = true;
    widget.onDone(r);
  }

  /// LockScreen's `onUnlocked`: by the gate (the ledger is open) or by the
  /// PIN (the store is open; the ledger may not be yet).
  Future<void> _unlocked() async {
    if (_done) return;
    if (_opened) return _finish(ColdStartResult.opened);
    if (_legacyLost) return _finish(ColdStartResult.keysLost);
    await _tryOpen();
    if (_done) return;
    if (_opened) return _finish(ColdStartResult.opened);
    if (_legacyLost) return _finish(ColdStartResult.keysLost);
    if (!mounted) return;
    setState(() {
      // A legacy biometric-bound class still opens only to the biometric
      // (06 §4.4: the MPIN is never a key), so the screen says so. The
      // ruling-1 class needs no second proof; a read that failed there is
      // offered again from the start.
      _reason = _legacy ? LockReason.keysNeedBiometric : LockReason.routine;
      _round++;
    });
  }

  @override
  Widget build(BuildContext context) => LockScope(
    vault: widget.vault,
    biometrics: _gate,
    child: LockScreen(
      key: ValueKey(_round),
      reason: _reason,
      onUnlocked: _unlocked,
      // ⚠️ SPEC: the forgot path ("OTP + biometric, then a new PIN", 07 §5.6)
      // does not exist before the app is composed. On a phone with a gate the
      // biometric alone opens the books, so the forgot door asks for it — and
      // says so ([LockScreen.forgotOpensWithBiometric]; S15 turns it off on a
      // PIN-only phone); the code is sent from the in-app Forgot PIN.
      // Once the gate answers re-enrolled (or pin-only) no biometric can open
      // the books, and no ladder door exists before the app is composed
      // (`onForgotPinPinOnly` is left null): S15 then explains that only the
      // PIN opens and offers no button that would do nothing (GATE1 review
      // finding 2). ⚠️ SPEC: an S11 entry from the cold-start S15 is not
      // built — the same gap as [ColdStartResult.keysLost]; owner item.
      forgotOpensWithBiometric: true,
      onForgotPin: () async {
        final reason = AppLocalizations.of(context).lockBiometricPrompt;
        final o = await _attempt(reason);
        if (o == BiometricOutcome.success && _opened) {
          _finish(ColdStartResult.opened);
        }
      },
    ),
  );
}

final class _OpeningGate implements BiometricGate {
  _OpeningGate(this._state);

  final _ColdStartGateState _state;

  @override
  Future<BiometricOutcome> authenticate({required String reason}) =>
      _state._attempt(reason);

  @override
  Future<bool> qualifyingBiometricEnrolled() async => true;
}
