// S15 App lock + S15.3 MPIN cooldown / disabled (13 §3.2, 07 §5.6 🔒).
//
// The mark, "Unlock to open your books", biometric prompting **automatically
// without a tap**, and *Use PIN instead* beneath for a failed or unavailable
// sensor. The fallback is the 6-digit MPIN and never the phone's passcode
// (06 §4.4 🔒, ADR 2026-09-01): in a joint family the passcode is common
// knowledge, which is the whole reason the MPIN exists.
//
// S15.3 is not a separate screen but this screen's other states (ADR
// 2026-09-05f §B, 13 §4.3): 5 free attempts, then 30 s · 1 min · 5 min ·
// 15 min · 1 h with a countdown row, and after 10 failures the PIN is switched
// off until OTP to the registered number plus biometric (ADR 2026-09-05d §5).
// The attempt policy itself lives in [PinVault] — this screen only renders
// whatever [PinStatus] it is given, so the ladder cannot drift between the two.
//
// Forgetting the PIN is never data loss (06 §4.4): the forgot door explains
// that nothing is re-encrypted and hands off to the reset flow.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../devices/pin_vault.dart';
import '../../onboarding/widgets/sealed_mark.dart';
import '../biometric_gate.dart';
import '../lock_scope.dart';
import '../widgets/pin_pad.dart';

/// Why the PIN pad is being asked for, which changes one line of copy.
enum LockReason {
  /// Cold start, background timeout (default 2 min) or 5 min idle
  /// (06 §4.5, ADR 2026-09-05 §7).
  routine,

  /// A face or fingerprint was added to this phone, so the keystore item is no
  /// longer readable by biometrics (ADR 2026-09-05d §4).
  biometricReenrolled,
}

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.onUnlocked,
    required this.onForgotPin,
    this.reason = LockReason.routine,
  });

  /// Called the moment the person proves themselves, by face or by PIN.
  final VoidCallback onUnlocked;

  /// Opens the reset path — OTP to the registered number **plus** biometric,
  /// then S0.8 for a new PIN (07 §5.6). Required, because the disabled state
  /// has no other exit and 07 §1 rule 6 forbids a dead end.
  final VoidCallback onForgotPin;

  /// Which copy variant to show.
  final LockReason reason;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  PinStatus? _status;
  String _typed = '';
  bool _showPad = false;
  bool _wrong = false;
  bool _busy = false;
  bool _forgotDoor = false;
  BiometricOutcome? _biometric;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Biometric prompts automatically, without a tap (07 §5.6). It runs after
    // the first frame so the mark is already on screen behind the sheet.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    await _refresh();
    if (!mounted) return;
    if (widget.reason == LockReason.biometricReenrolled) {
      // A changed biometric set is exactly the case where the sensor cannot
      // open the item, so asking is noise: go straight to the PIN, once.
      setState(() {
        _showPad = true;
        _biometric = BiometricOutcome.reenrolled;
      });
      return;
    }
    await _promptBiometric();
  }

  Future<void> _refresh() async {
    final status = await LockScope.of(context).vault.status();
    if (!mounted) return;
    setState(() {
      _status = status;
      // A PIN that is in cooldown or switched off shows its own state rather
      // than an unusable pad.
      if (status is! PinReady) _typed = '';
    });
    _retick();
  }

  void _retick() {
    _ticker?.cancel();
    if (_status is! PinCooldown) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final status = _status;
      if (status is PinCooldown && !_remaining(status).isNegative) {
        setState(() {});
      } else {
        unawaited(_refresh());
      }
    });
  }

  Duration _remaining(PinCooldown status) =>
      status.until.difference(RkScope.of(context).now());

  Future<void> _promptBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final outcome = await LockScope.of(context).biometrics
        .authenticate(reason: l10n.lockBiometricPrompt);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _biometric = outcome;
      if (outcome != BiometricOutcome.success) _showPad = true;
    });
    if (outcome == BiometricOutcome.success) widget.onUnlocked();
  }

  void _digit(String d) {
    if (_busy || _typed.length >= pinLength) return;
    setState(() {
      _typed += d;
      _wrong = false;
    });
    if (_typed.length == pinLength) unawaited(_verify());
  }

  void _delete() {
    if (_busy || _typed.isEmpty) return;
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    final result = await LockScope.of(context).vault.verify(_typed);
    if (!mounted) return;
    switch (result) {
      case PinAccepted():
        setState(() => _busy = false);
        widget.onUnlocked();
      case PinRejected(:final status):
        setState(() {
          _busy = false;
          _status = status;
          _typed = '';
          _wrong = true;
        });
        _retick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final vaultStatus = _status;

    Widget body;
    if (_forgotDoor) {
      body = _ForgotDoor(
        onStart: widget.onForgotPin,
        onCancel: () => setState(() => _forgotDoor = false),
      );
    } else if (vaultStatus == null) {
      // Loading: the vault item has not been read yet (13 §4.3).
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: RkSpace.s6),
        child: LinearProgressIndicator(),
      );
    } else if (vaultStatus is PinDisabled) {
      body = _DisabledPanel(onReset: () => setState(() => _forgotDoor = true));
    } else if (vaultStatus is PinCooldown) {
      body = _CooldownPanel(
        remaining: _remaining(vaultStatus),
        onBiometric: _busy ? null : _promptBiometric,
      );
    } else if (_showPad && vaultStatus is PinReady) {
      body = _PinPanel(
        typed: _typed,
        wrong: _wrong,
        busy: _busy,
        attemptsLeft: vaultStatus.attemptsLeft,
        warn: vaultStatus.inPenaltyBand,
        biometric: _biometric,
        onDigit: _busy ? null : _digit,
        onDelete: _busy || _typed.isEmpty ? null : _delete,
        onRetryBiometric: _busy ? null : _promptBiometric,
      );
    } else {
      // ⚠️ SPEC: a locked app with no PIN set (PinNotSet) is not a state 07
      // §5.6 or 13 §3.2 names. Conservative reading: biometric is then the
      // only gate — *Use PIN instead* would open a pad that can never accept
      // anything — so the retry path is shown and the pad is not.
      body = Column(
        children: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: RkSpace.s4),
              child: LinearProgressIndicator(),
            ),
          if (vaultStatus is PinReady)
            TextButton(
              onPressed: () => setState(() => _showPad = true),
              child: Text(l10n.lockPinUseInstead),
            )
          else
            TextButton(
              onPressed: _busy ? null : _promptBiometric,
              child: Text(l10n.lockBiometricRetry),
            ),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: RkSpace.s6),
                      const Center(child: SealedMark()),
                      const SizedBox(height: RkSpace.s4),
                      Text(
                        l10n.lockTitle,
                        style: text.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: RkSpace.s6),
                      body,
                    ],
                  ),
                ),
              ),
              if (!_forgotDoor && vaultStatus is! PinDisabled)
                TextButton(
                  onPressed: () => setState(() => _forgotDoor = true),
                  child: Text(
                    l10n.lockForgotAction,
                    style: text.bodyMedium?.copyWith(color: status.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinPanel extends StatelessWidget {
  const _PinPanel({
    required this.typed,
    required this.wrong,
    required this.busy,
    required this.attemptsLeft,
    required this.warn,
    required this.biometric,
    required this.onDigit,
    required this.onDelete,
    required this.onRetryBiometric,
  });

  final String typed;
  final bool wrong;
  final bool busy;
  final int attemptsLeft;
  final bool warn;
  final BiometricOutcome? biometric;
  final void Function(String)? onDigit;
  final VoidCallback? onDelete;
  final VoidCallback? onRetryBiometric;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final biometricLine = switch (biometric) {
      BiometricOutcome.failed => l10n.lockBiometricFailed,
      BiometricOutcome.unavailable => l10n.lockBiometricUnavailable,
      BiometricOutcome.reenrolled => l10n.lockBiometricReenrolled,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.lockPinLabel,
          style: text.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: RkSpace.s4),
        PinBoxes(filled: typed.length, error: wrong),
        const SizedBox(height: RkSpace.s3),
        if (wrong)
          _Line(
            icon: Icons.error_outline,
            color: status.debit,
            text: l10n.lockPinWrong,
          ),
        // The warning row only appears once the free attempts are spent —
        // before that it would be a threat, not a help (ADR 2026-09-05d §5).
        if (warn)
          _Line(
            icon: Icons.timer_outlined,
            color: status.pending,
            text: attemptsLeft <= 1
                ? l10n.lockPinOneTryLeft
                : l10n.lockPinTriesLeft(attemptsLeft),
          ),
        if (biometricLine != null)
          _Line(
            icon: Icons.face_outlined,
            color: status.muted,
            text: biometricLine,
          ),
        const SizedBox(height: RkSpace.s3),
        PinKeypad(onDigit: onDigit, onDelete: onDelete),
        TextButton(
          onPressed: onRetryBiometric,
          child: Text(l10n.lockBiometricRetry),
        ),
      ],
    );
  }
}

class _CooldownPanel extends StatelessWidget {
  const _CooldownPanel({required this.remaining, required this.onBiometric});

  final Duration remaining;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.lockCooldownTitle,
          style: text.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: RkSpace.s2),
        Text(
          l10n.lockCooldownBody,
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: RkSpace.s4),
        _Line(
          icon: Icons.hourglass_empty,
          color: status.pending,
          text: l10n.lockCooldownCountdown(formatCountdown(remaining)),
        ),
        const SizedBox(height: RkSpace.s4),
        // The wait is the PIN's policy alone — the face still opens the app.
        TextButton(
          onPressed: onBiometric,
          child: Text(l10n.lockBiometricRetry),
        ),
      ],
    );
  }
}

class _DisabledPanel extends StatelessWidget {
  const _DisabledPanel({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(
          icon: Icons.lock_outline,
          color: status.pending,
          text: l10n.lockDisabledTitle,
        ),
        const SizedBox(height: RkSpace.s2),
        Text(l10n.lockDisabledBody, style: text.bodyMedium),
        const SizedBox(height: RkSpace.s4),
        FilledButton(onPressed: onReset, child: Text(l10n.lockForgotStart)),
      ],
    );
  }
}

class _ForgotDoor extends StatelessWidget {
  const _ForgotDoor({required this.onStart, required this.onCancel});

  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.lockForgotTitle, style: text.titleMedium),
        const SizedBox(height: RkSpace.s2),
        Text(l10n.lockForgotBody, style: text.bodyMedium),
        const SizedBox(height: RkSpace.s4),
        FilledButton(onPressed: onStart, child: Text(l10n.lockForgotStart)),
        TextButton(onPressed: onCancel, child: Text(l10n.lockForgotCancel)),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: RkIcon.grid, color: color),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// `m:ss` for a cooldown that is under an hour, `h:mm:ss` above it. Clamped at
/// zero so a tick that lands after the wait never renders a negative row.
String formatCountdown(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
  return h > 0
      ? '$h:$mm:${s.toString().padLeft(2, '0')}'
      : '$mm:${s.toString().padLeft(2, '0')}';
}
