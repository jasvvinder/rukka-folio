// S0.8 Set your PIN (13 §3.2 row S0.8, 07 §3.1 step 5's chain, 06 §4.4 🔒).
// Six digits, typed once and confirmed, written to the one MPIN vault
// (features/devices/pin_vault.dart). The PIN is a local gate on the keystore —
// never a key, never sent anywhere (06 §4.4 🔒) — so this screen calls
// `setPin` and nothing else.
//
// The screen also carries the app-lock line that 07 §5.6 says is *stated at
// onboarding, not asked*: "Face ID keeps this app closed to everyone else — if
// a new face is added to this phone, the app asks for your PIN" (ADR
// 2026-09-05d §4). There is no toggle, because it cannot be turned off.
//
// States (13 §4.3): default · disabled-with-reason (fewer than 6 digits) ·
// error (the two entries differ; the vault refused) · loading (saving).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../lock/lock_scope.dart';
import '../../lock/widgets/pin_pad.dart';

/// Which half of the two-step set is showing.
enum SetPinStep {
  /// Type the new PIN.
  choose,

  /// Type it again so a typo cannot lock anyone out.
  confirm,
}

class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key, this.onDone});

  /// Called once the vault holds the new PIN — the next step of 07 §3.1
  /// (S0.5 keeping your books safe). Never called on a failure.
  final VoidCallback? onDone;

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  SetPinStep _step = SetPinStep.choose;
  String _first = '';
  String _typed = '';
  bool _saving = false;
  bool _mismatch = false;
  bool _saveFailed = false;

  void _digit(String d) {
    if (_saving || _typed.length >= pinLength) return;
    setState(() {
      _typed += d;
      _mismatch = false;
      _saveFailed = false;
    });
  }

  void _delete() {
    if (_saving || _typed.isEmpty) return;
    setState(() => _typed = _typed.substring(0, _typed.length - 1));
  }

  void _startOver() {
    setState(() {
      _step = SetPinStep.choose;
      _first = '';
      _typed = '';
      _mismatch = false;
      _saveFailed = false;
    });
  }

  Future<void> _continue() async {
    if (_typed.length != pinLength || _saving) return;
    if (_step == SetPinStep.choose) {
      setState(() {
        _first = _typed;
        _typed = '';
        _step = SetPinStep.confirm;
      });
      return;
    }
    if (_typed != _first) {
      setState(() {
        _step = SetPinStep.choose;
        _first = '';
        _typed = '';
        _mismatch = true;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      await LockScope.of(context).vault.setPin(_typed);
    } on Object {
      // Any refusal (InvalidPinFormat, a keychain write that failed) lands on
      // the error state with the pad still usable — never a dead end.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
        _step = SetPinStep.choose;
        _first = '';
        _typed = '';
      });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final confirming = _step == SetPinStep.confirm;
    final complete = _typed.length == pinLength;
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
                      Text(
                        confirming
                            ? l10n.onboardingSetPinConfirmTitle
                            : l10n.onboardingSetPinTitle,
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Text(
                        confirming
                            ? l10n.onboardingSetPinConfirmSubtitle
                            : l10n.onboardingSetPinSubtitle,
                        style: text.bodyLarge,
                      ),
                      if (!confirming) ...[
                        const SizedBox(height: RkSpace.s2),
                        Text(
                          l10n.onboardingSetPinWhy,
                          style: text.bodyMedium?.copyWith(color: status.muted),
                        ),
                      ],
                      const SizedBox(height: RkSpace.s6),
                      PinBoxes(filled: _typed.length, error: _mismatch),
                      const SizedBox(height: RkSpace.s3),
                      // Error state — icon + word + colour, never colour alone
                      // (07 §1 rule 3).
                      if (_mismatch || _saveFailed)
                        _Notice(
                          icon: Icons.error_outline,
                          color: status.debit,
                          text: _mismatch
                              ? l10n.onboardingSetPinMismatch
                              : l10n.onboardingSetPinSaveFailed,
                        )
                      else if (_saving)
                        _Notice(
                          icon: Icons.lock_outline,
                          color: status.muted,
                          text: l10n.onboardingSetPinSaving,
                        )
                      else
                        _Notice(
                          icon: Icons.face_outlined,
                          color: status.muted,
                          text: l10n.onboardingSetPinBiometricNote,
                        ),
                    ],
                  ),
                ),
              ),
              PinKeypad(
                onDigit: _saving ? null : _digit,
                onDelete: _saving || _typed.isEmpty ? null : _delete,
              ),
              const SizedBox(height: RkSpace.s3),
              // Disabled-with-reason (13 §4.3).
              if (!complete)
                Padding(
                  padding: const EdgeInsets.only(bottom: RkSpace.s2),
                  child: Text(
                    l10n.onboardingSetPinIncomplete,
                    style: text.bodySmall?.copyWith(color: status.muted),
                    textAlign: TextAlign.center,
                  ),
                ),
              FilledButton(
                onPressed: complete && !_saving ? _continue : null,
                child: Text(l10n.onboardingSetPinContinue),
              ),
              if (confirming)
                TextButton(
                  onPressed: _saving ? null : _startOver,
                  child: Text(l10n.onboardingSetPinStartOver),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: RkIcon.grid, color: color),
        const SizedBox(width: RkSpace.s2),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
