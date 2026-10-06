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
// Setting the PIN here is O4b, the moment ADR 2026-10-06 §2 🔒 mints the
// biometric **gate** — through the vault's `afterPinProven`, wired at the
// composition root (bootstrap.dart), not by this screen. The gate guards the
// app; the device keys are never bound to the biometric (§1).
//
// On a phone with no biometric that can guard a hardware key (ADR 2026-10-05b
// §1) the line has a PIN-only form: the PIN alone keeps the app closed, and
// a gate is minted at the next PIN once a biometric is added (ADR 2026-10-06
// §4).
// The question is asked of the platform once, without a prompt; until it
// answers the Face ID form shows (the canvas's). ⚠️ SPEC: the PIN-only copy is
// a draft — design desk 148.
//
// Drawn to c1 O4b (ADR 2026-10-05 §1): back chevron, page title, the muted
// *why* paragraph, six bordered boxes and *Six digits*. Each step advances by
// itself at the sixth digit — the frame has no Continue button — and a
// mismatch shows the frame's *Mismatch on confirm*: *Type it again* over six
// `debit` boxes and *Those two didn't match. Start again.*, with both entries
// already cleared (the canvas note: half a remembered PIN is worse than none).
// The frame draws no keypad; the six boxes take the c3 S15 *PIN instead*
// keypad, the same [PinKeypad] the lock uses, so the two cannot drift.
//
// States (13 §4.3): default · error (the two entries differ; the vault
// refused) · loading (saving).
import 'package:flutter/material.dart';

import '../onboarding_gate.dart' show OnboardingBack;
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../lock/lock_scope.dart';
import '../../lock/widgets/face_id_glyph.dart';
import '../../lock/widgets/pin_pad.dart';

/// Which half of the two-step set is showing.
enum SetPinStep {
  /// Type the new PIN.
  choose,

  /// Type it again so a typo cannot lock anyone out.
  confirm,
}

class SetPinScreen extends StatefulWidget {
  const SetPinScreen({
    super.key,
    this.onDone,
    this.onBack,
    @visibleForTesting this.debugTyped = '',
    @visibleForTesting this.debugMismatch = false,
  });

  /// Design captures only (ADR 2026-10-05 §2): seed the drawn state the
  /// capture helper cannot type its way to. Never set by the app.
  final String debugTyped;
  final bool debugMismatch;

  /// Called once the vault holds the new PIN — the next step of 07 §3.1
  /// (S0.5 keeping your books safe). Never called on a failure.
  final VoidCallback? onDone;

  /// The back chevron on the first step (c1 O4b): back to S0.4. On the
  /// confirm step the chevron starts the PIN over instead.
  final VoidCallback? onBack;

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

  /// Null until the platform answers; true ⇒ the Face ID line.
  bool? _enrolled;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _typed = widget.debugTyped;
    _mismatch = widget.debugMismatch;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    final gate = LockScope.maybeOf(context)?.biometrics;
    if (gate == null) return;
    _asked = true;
    gate.qualifyingBiometricEnrolled().then((v) {
      if (mounted) setState(() => _enrolled = v);
    });
  }

  void _digit(String d) {
    if (_saving || _typed.length >= pinLength) return;
    setState(() {
      _typed += d;
      _mismatch = false;
      _saveFailed = false;
    });
    // c1 O4b draws no Continue: the sixth digit is the step.
    if (_typed.length == pinLength) _continue();
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

  /// System Back (ADR 2026-10-06b ruling 3) does exactly what the back
  /// button does: the confirm step starts over, the choose step takes
  /// [SetPinScreen.onBack], and a save in flight holds its place. Read at the
  /// moment of the press, so it never acts on a stale step.
  void _systemBack() {
    if (_saving) return;
    if (_step == SetPinStep.confirm || _mismatch) {
      _startOver();
    } else {
      widget.onBack?.call();
    }
  }

  @override
  Widget build(BuildContext context) => OnboardingBack(
    onBack: _systemBack,
    // With no [SetPinScreen.onBack] (the screen pushed outside the chain)
    // the choose step leaves Back to the navigator, as before.
    exits:
        widget.onBack == null &&
        !_saving &&
        _step != SetPinStep.confirm &&
        !_mismatch,
    child: _body(context),
  );

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    // A mismatch has already cleared both entries, but it is drawn as the
    // confirm step that failed (c1 O4b *Mismatch on confirm*) until the next
    // digit starts the PIN over.
    final confirming = _step == SetPinStep.confirm || _mismatch;
    final showBack = confirming || widget.onBack != null;
    final Widget below;
    if (_mismatch || _saveFailed) {
      // Error state — icon + words + colour, never colour alone (07 §1 rule 3).
      below = _Notice(
        icon: Icons.error_outline,
        color: status.debit,
        centred: true,
        text: _mismatch
            ? l10n.onboardingSetPinMismatch
            : l10n.onboardingSetPinSaveFailed,
      );
    } else if (_saving) {
      below = _Notice(
        icon: Icons.lock_outline,
        color: status.muted,
        centred: true,
        text: l10n.onboardingSetPinSaving,
      );
    } else {
      below = Text(
        l10n.onboardingSetPinHint,
        style: text.bodyMedium?.copyWith(color: status.muted),
        textAlign: TextAlign.center,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          RkSpace.s1,
                          0,
                          RkSpace.s4,
                          RkSpace.s2,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox.square(
                            dimension: RkSpace.s12,
                            child: showBack
                                ? IconButton(
                                    onPressed: _saving
                                        ? null
                                        : (confirming
                                              ? _startOver
                                              : widget.onBack),
                                    tooltip: MaterialLocalizations.of(context)
                                        .backButtonTooltip,
                                    color: status.muted,
                                    icon: const Icon(
                                      Icons.chevron_left,
                                      size: RkIcon.grid,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          RkSpace.s6,
                          RkSpace.s2,
                          RkSpace.s6,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            RkFitText(
                              confirming
                                  ? l10n.onboardingSetPinConfirmTitle
                                  : l10n.onboardingSetPinTitle,
                              style: text.headlineMedium,
                            ),
                            const SizedBox(height: RkSpace.s3),
                            // ADR 2026-10-05b §1: a PIN-only phone drops the
                            // "You'll use Face ID" sentence (⚠️ SPEC: draft copy,
                            // design desk 148).
                            RkFitText(
                              confirming
                                  ? l10n.onboardingSetPinConfirmSubtitle
                                  : (_enrolled == false
                                        ? l10n.onboardingSetPinWhy
                                        : l10n.onboardingSetPinSubtitle),
                              style: text.bodyLarge?.copyWith(
                                color: status.muted,
                              ),
                            ),
                            const SizedBox(height: RkSpace.s6),
                            PinBoxes(
                              filled: _mismatch && _typed.isEmpty
                                  ? pinLength
                                  : _typed.length,
                              error: _mismatch,
                            ),
                            const SizedBox(height: RkSpace.s6),
                            below,
                            // 07 §5.6 🔒 — the app-lock line is stated at
                            // onboarding, not asked; on the first step only.
                            if (!confirming && !_saving && !_saveFailed) ...[
                              const SizedBox(height: RkSpace.s6),
                              _Notice(
                                icon: Icons.lock_outline,
                                faceId: _enrolled != false,
                                color: status.muted,
                                text: _enrolled == false
                                    ? l10n.onboardingSetPinBiometricNotePinOnly
                                    : l10n.onboardingSetPinBiometricNote,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RkSpace.s3,
                      RkSpace.s5,
                      RkSpace.s3,
                      RkSpace.s4,
                    ),
                    child: PinKeypad(
                      onDigit: _saving ? null : _digit,
                      onDelete: _saving || _typed.isEmpty ? null : _delete,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.text,
    this.centred = false,
    this.faceId = false,
  });

  final IconData icon;

  /// Lead with the canvas's Face ID glyph instead of [icon].
  final bool faceId;
  final Color color;
  final String text;

  /// The error line sits centred under the boxes (c1 O4b *Mismatch on
  /// confirm*); the app-lock line reads as a paragraph.
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: color);
    final label = RkFitText(
      text,
      style: style,
      textAlign: centred ? TextAlign.center : TextAlign.start,
    );
    return Row(
      mainAxisAlignment: centred
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (faceId)
          FaceIdGlyph(size: RkIcon.grid, color: color, compact: true)
        else
          Icon(icon, size: centred ? RkSpace.s4 : RkIcon.grid, color: color),
        const SizedBox(width: RkSpace.s2),
        if (centred) Flexible(child: label) else Expanded(child: label),
      ],
    );
  }
}
