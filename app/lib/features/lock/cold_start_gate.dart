// Cold start on a phone whose device keys are biometric-bound (ADR 2026-10-05b
// §4 🔒, 07 §5.6, 13 §3.2 S15).
//
// Reading a biometric-bound device key *is* the platform's biometric prompt
// (Android BiometricPrompt through flutter_secure_storage; iOS Keychain with
// biometryCurrentSet). Bootstrap used to do that read before `runApp`, so the
// system sheet came up over a blank window and a cancel ended at the
// dead-end RukkaFolioBlocked (desk 145 review finding 3). Now bootstrap mounts
// this gate first: S15 is on screen, its automatic biometric attempt *is* the
// ledger opening, and anything but success leaves the person on S15 with
// *Use PIN instead* — never on a blocked screen.
//
// After a correct PIN:
//   • the device keys were invalidated (Android's [KeyStoreInvalidated], or a
//     device-key item that reads back as absent — iOS answers an unreadable
//     `biometryCurrentSet` item that way) → ruling 3: the invalidated items
//     are removed and the binding re-chosen ([dropInvalidated]); the key
//     material itself is gone, so the host goes on to recovery
//     ([ColdStartResult.keysLost]).
//   • a failed or refused prompt (iOS `errSecAuthFailed` / `…NotAllowed`
//     included — keychain_key_store.dart `_looksInvalidated`) is never an
//     invalidation and removes nothing (KEY145B review finding 1).
//   • the device keys read back but the promptless wrapped UMK is gone → the
//     person is proved by that read, nothing is removed, and the host goes
//     on to recovery ([ColdStartResult.umkMissing]).
//   • otherwise the keys still open only to the biometric — the MPIN is a gate,
//     never a key (06 §4.4 🔒) — so the gate asks for it once more, saying why
//     ([LockReason.keysNeedBiometric]). ⚠️ SPEC: KEY145 finding 2(b), which ADR
//     2026-10-05b did not rule on; owner.
//
// A PIN-only phone never reaches this gate: its keys open without a person, so
// bootstrap opens the ledger directly and the in-app S15 asks for the PIN.
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
  /// The device keys were read: the ledger is open.
  opened,

  /// The biometric-bound keys were unreadable for good and have been
  /// removed after the PIN (ADR 2026-10-05b §3); the books need the recovery
  /// ladder.
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
    required this.open,
    required this.dropInvalidated,
    required this.onDone,
  });

  /// The MPIN vault — the same one the app uses.
  final PinVault vault;

  /// Opens the ledger, which reads the device keys (the biometric prompt).
  final Future<void> Function() open;

  /// Ruling 3, after a correct PIN: remove the invalidated items.
  final Future<void> Function() dropInvalidated;

  /// Called once, when the person is through.
  final void Function(ColdStartResult result) onDone;

  @override
  State<ColdStartGate> createState() => _ColdStartGateState();
}

class _ColdStartGateState extends State<ColdStartGate> {
  late final _gate = _OpeningGate(this);
  LockReason _reason = LockReason.routine;
  int _round = 0;
  bool _opened = false;
  bool _invalidated = false;
  bool _done = false;

  Future<BiometricOutcome> _tryOpen() async {
    if (_opened) return BiometricOutcome.success;
    try {
      await widget.open();
      _opened = true;
      return BiometricOutcome.success;
    } on KeyStoreInvalidated {
      _invalidated = true;
      return BiometricOutcome.reenrolled;
    } on DeviceKeysMissing catch (e) {
      if (!e.deviceKeys) {
        // The device keys read back — the biometric proved the person — and
        // must not be touched; only the UMK copy is gone.
        _finish(ColdStartResult.umkMissing);
        return BiometricOutcome.success;
      }
      _invalidated = true;
      return BiometricOutcome.reenrolled;
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

  /// LockScreen's `onUnlocked`: by the biometric (the ledger is open) or by
  /// the PIN (it may not be).
  Future<void> _unlocked() async {
    if (_done) return;
    if (_opened) return _finish(ColdStartResult.opened);
    if (!_invalidated) await _tryOpen();
    if (_done) return;
    if (_opened) return _finish(ColdStartResult.opened);
    if (_invalidated) {
      await widget.dropInvalidated();
      return _finish(ColdStartResult.keysLost);
    }
    if (!mounted) return;
    setState(() {
      _reason = LockReason.keysNeedBiometric;
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
      // does not exist before the app is composed. On a biometric phone the
      // biometric alone opens the keys, so the forgot door asks for it — and
      // says so ([LockScreen.forgotOpensWithBiometric]: no code is promised
      // here, KEY145B review finding 6); the code is sent from the in-app
      // Forgot PIN (main.dart `_onForgotPin`).
      forgotOpensWithBiometric: true,
      onForgotPin: () async {
        final o = await _tryOpen();
        if (o == BiometricOutcome.success) _finish(ColdStartResult.opened);
      },
    ),
  );
}

final class _OpeningGate implements BiometricGate {
  _OpeningGate(this._state);

  final _ColdStartGateState _state;

  @override
  Future<BiometricOutcome> authenticate({required String reason}) =>
      _state._tryOpen();

  @override
  Future<bool> qualifyingBiometricEnrolled() async => true;
}
