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
//
// PIN-only variant (ADR 2026-10-05b §1): when the gate answers
// [BiometricOutcome.pinOnly] the phone has no biometric that can guard a
// hardware key, so the screen is the canvas's *PIN instead · six digits*
// frame from the first answer on — boxes and keypad, no biometric button, no
// biometric line, and one muted line saying why (⚠️ SPEC: design desk 148
// owns the final copy and placement). The cooldown panel then offers no face
// either: the wait is the only way forward, and *Forgot PIN* stays.
//
// Re-enrolled variant (ADR 2026-10-06 §4): the gate was invalidated — a face
// or fingerprint added or removed, or every one removed — so no biometric can
// open the app until the MPIN has minted a new gate. The screen asks for the
// MPIN with the reason line and draws **no** Face ID button (a tap could only
// answer re-enrolled again, GATE1 review finding 3). Its forgot door cannot
// lean on the biometric either: a set that changed since the PIN was set is
// exactly the 06 §4.4 relative-enrols-a-face case, so the reset is the S11
// recovery ladder, as on a PIN-only phone (⚠️ SPEC: conservative reading of
// desk 147, owner to rule). Where no ladder door exists yet (the cold start,
// [LockScreen.onForgotPinPinOnly] null) the page says only the PIN opens and
// offers no button that would do nothing (GATE1 review finding 2).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/tokens.dart';
import '../../devices/pin_vault.dart';
import '../../onboarding/widgets/sealed_mark.dart';
import '../biometric_gate.dart';
import '../lock_scope.dart';
import '../widgets/face_id_glyph.dart';
import '../widgets/pin_pad.dart';

/// Why the PIN pad is being asked for, which changes one line of copy.
enum LockReason {
  /// Cold start, background timeout (default 2 min) or 5 min idle
  /// (06 §4.5, ADR 2026-09-05 §7).
  routine,

  /// A face or fingerprint was added to (or removed from) this phone, so the
  /// gate item is no longer readable by biometrics: the MPIN, once, then a new
  /// gate (ADR 2026-10-06 §4).
  biometricReenrolled,

  /// Cold start on an install whose device keys still sit in the legacy
  /// biometric-bound class (before ADR 2026-10-06's migration, ruling 5),
  /// after the PIN was accepted: those keys open only to the biometric
  /// (06 §4.4 🔒 — the MPIN is never a key), so the screen says so and offers
  /// the biometric again (cold_start_gate.dart). Unreachable once migrated.
  keysNeedBiometric,
}

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.onUnlocked,
    required this.onForgotPin,
    this.reason = LockReason.routine,
    this.onForgotPinPinOnly,
    this.forgotOpensWithBiometric = false,
    @visibleForTesting this.debugTyped = '',
    @visibleForTesting this.debugWrong = false,
    @visibleForTesting this.debugForgotDoor = false,
  });

  /// Design captures only (ADR 2026-10-05 §2): the capture helper pumps a
  /// fresh tree and cannot type, so these seed the drawn state — digits in the
  /// boxes, the wrong-PIN line, the forgot door. Never set by the app.
  final String debugTyped;
  final bool debugWrong;
  final bool debugForgotDoor;

  /// The S11 recovery-ladder door: the forgot path on a **PIN-only** phone
  /// (desk 147) and on one whose biometric set changed since the PIN was set
  /// (ADR 2026-10-06 §4). 06 §4.4's reset is "OTP plus biometric", and neither
  /// phone has a biometric that proves the person; OTP alone is a SIM swap
  /// away. ⚠️ SPEC: owner to rule (ADR 2026-10-05b *Open*); until then the
  /// conservative reading (c) — the S11 recovery ladder — which the host
  /// wires here. Null (the cold start, where nothing behind the ladder is
  /// composed yet) leaves that page with its explanation and no action —
  /// never a button that does nothing, and never [onForgotPin], which there
  /// is the biometric.
  final VoidCallback? onForgotPinPinOnly;

  /// The cold-start S15 of a biometric phone (cold_start_gate.dart): no code
  /// can be sent before the app is composed, so its forgot door opens the
  /// books with the biometric — and the page says exactly that, never "We'll
  /// send a code" (KEY145B review finding 6). ⚠️ SPEC: 07 §5.6's "OTP +
  /// biometric, then a new PIN" is not reachable before the app is open.
  final bool forgotOpensWithBiometric;

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

  /// A biometric attempt is in flight. Kept apart from [_busy] (a PIN being
  /// checked) so the PIN pad works while a platform sheet is still pending:
  /// flutter_secure_storage 11.2.0 never answers when its BiometricPrompt's
  /// negative button is pressed (FlutterSecureStorage.java:1281-1282 sets a
  /// no-op listener, and the framework then calls no error callback), so an
  /// attempt can stay pending for good — *Use PIN instead* must still work
  /// (ADR 2026-10-05b §4: a cancelled prompt never ends at a dead end).
  bool _prompting = false;
  bool _forgotDoor = false;
  bool _pinOnly = false;
  BiometricOutcome? _biometric;

  /// The gate was invalidated (ADR 2026-10-06 §4): only the MPIN opens now.
  bool get _reenrolled => _biometric == BiometricOutcome.reenrolled;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _typed = widget.debugTyped;
    _wrong = widget.debugWrong;
    _forgotDoor = widget.debugForgotDoor;
    // ADR 2026-10-06 §3 🔒: S15 is the only door, so the device keys close the
    // moment it covers the app (the background timeout, the idle lock) and
    // stay closed until the gate or the MPIN. Synchronous, before the first
    // frame: a resume's sync nudge waits for that frame (bootstrap).
    final gate = context.getInheritedWidgetOfExactType<LockScope>()?.biometrics;
    if (gate is SealingBiometricGate) gate.sealBehindLock();
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
    if (widget.reason == LockReason.keysNeedBiometric) return;
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

  // The vault's own clock: the cooldown it set is measured on the clock that
  // set it, and the cold-start gate mounts this screen before any RkScope.
  Duration _remaining(PinCooldown status) =>
      status.until.difference(LockScope.of(context).vault.now());

  /// Each attempt's number; an answer to an older attempt is ignored, so a
  /// tap after a sheet that never answered starts a fresh one.
  int _attempt = 0;

  Future<void> _promptBiometric() async {
    final attempt = ++_attempt;
    setState(() => _prompting = true);
    final l10n = AppLocalizations.of(context);
    final outcome = await LockScope.of(context).biometrics
        .authenticate(reason: l10n.lockBiometricPrompt);
    if (!mounted || attempt != _attempt) return;
    setState(() {
      _prompting = false;
      _biometric = outcome;
      if (outcome == BiometricOutcome.pinOnly) _pinOnly = true;
      // c3 S15 *Face not recognised*: a refused face stays on the face
      // page with *Try again*, and *Use PIN instead* beneath (07 §5.6). Any
      // other refusal has nothing to retry, so the pad comes up.
      if (outcome != BiometricOutcome.success &&
          outcome != BiometricOutcome.failed) {
        _showPad = true;
      }
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
    final scheme = Theme.of(context).colorScheme;
    final vaultStatus = _status;

    // c1 S15.3 *Forgot PIN · a code, not a lockout*: its own page, back
    // chevron, no mark.
    if (_forgotDoor) {
      final ladder = widget.onForgotPinPinOnly;
      final opensWithBiometric = widget.forgotOpensWithBiometric;
      return _ForgotPage(
        body: _pinOnly
            ? l10n.lockForgotBodyPinOnly
            : _reenrolled
            ? (ladder == null
                  ? l10n.lockForgotBodyReenrolledBeforeOpen
                  : l10n.lockForgotBodyReenrolled)
            : opensWithBiometric
            ? l10n.lockForgotBodyBeforeOpen
            : l10n.lockForgotBody,
        action: _pinOnly || _reenrolled
            ? (ladder == null ? null : (l10n.lockForgotStartLadder, ladder))
            : (
                opensWithBiometric
                    ? l10n.lockForgotStartBeforeOpen
                    : l10n.lockForgotStart,
                widget.onForgotPin,
              ),
        onBack: () => setState(() => _forgotDoor = false),
      );
    }

    final title = RkFitText(
      l10n.lockTitle,
      style: text.titleLarge,
      textAlign: TextAlign.center,
    );
    final forgotFoot = _FootLink(
      label: l10n.lockForgotAction,
      color: status.muted,
      onPressed: () => setState(() => _forgotDoor = true),
    );
    final usePinFoot = _FootLink(
      label: l10n.lockPinUseInstead,
      color: scheme.primary,
      strong: true,
      onPressed: () => setState(() => _showPad = true),
    );

    if (vaultStatus == null) {
      // Loading: the vault item has not been read yet (13 §4.3).
      return _LockPage(
        markSize: _LockPage.markFace,
        body: [title, const LinearProgressIndicator()],
      );
    }
    if (vaultStatus is PinDisabled) {
      return _LockPage(
        markSize: _LockPage.markPinS153,
        body: [
          _DisabledPanel(onReset: () => setState(() => _forgotDoor = true)),
        ],
      );
    }
    if (vaultStatus is PinCooldown) {
      return _LockPage(
        markSize: _LockPage.markPinS153,
        body: [
          _CooldownPanel(
            remaining: _remaining(vaultStatus),
            noBiometric: _pinOnly || _reenrolled,
            onBiometric: _promptBiometric,
          ),
        ],
        foot: forgotFoot,
      );
    }
    if (_showPad && vaultStatus is PinReady) {
      // c3 S15 *PIN instead · six digits* / c1 S15.3 *Enter PIN* · *Wrong
      // PIN*: from the top, boxes, the Face ID button, keypad at the foot.
      return _LockPage(
        centred: false,
        markSize: _LockPage.markPin,
        body: [
          _PinPanel(
            typed: _typed,
            wrong: _wrong,
            busy: _busy,
            attemptsLeft: vaultStatus.attemptsLeft,
            warn: vaultStatus.inPenaltyBand,
            biometric: _biometric,
            pinOnly: _pinOnly,
            onRetryBiometric: _busy ? null : _promptBiometric,
          ),
        ],
        keypad: PinKeypad(
          onDigit: _busy ? null : _digit,
          onDelete: _busy || _typed.isEmpty ? null : _delete,
        ),
        foot: forgotFoot,
      );
    }

    // The face states (c3 S15 *waiting for Face ID*, *Face not recognised*).
    final failed = !_prompting && _biometric == BiometricOutcome.failed;
    final glyph = _FaceGlyph(
      prompting: _prompting,
      failed: failed,
      onPressed: _prompting ? null : _promptBiometric,
    );
    if (widget.reason == LockReason.keysNeedBiometric) {
      return _LockPage(
        markSize: _LockPage.markFace,
        body: [
          title,
          glyph,
          _Line(
            icon: Icons.fingerprint,
            color: status.muted,
            text: l10n.lockKeysNeedBiometric,
          ),
          _InkButton(
            label: l10n.lockBiometricRetry,
            onPressed: _prompting ? null : _promptBiometric,
          ),
        ],
        foot: forgotFoot,
      );
    }
    return _LockPage(
      markSize: _LockPage.markFace,
      body: [
        title,
        glyph,
        if (failed)
          Text(
            l10n.lockBiometricFailed,
            style: text.bodyMedium?.copyWith(color: status.debit),
            textAlign: TextAlign.center,
          ),
        // ⚠️ SPEC: a locked app with no PIN set (PinNotSet) is not a state 07
        // §5.6 or 13 §3.2 names. Conservative reading: biometric is then the
        // only gate — *Use PIN instead* would open a pad that can never
        // accept anything — so the retry path is shown and the pad is not.
        if (failed || vaultStatus is! PinReady)
          _InkButton(
            label: l10n.lockBiometricRetry,
            onPressed: _prompting ? null : _promptBiometric,
          ),
      ],
      foot: vaultStatus is PinReady ? usePinFoot : null,
    );
  }
}

/// The lock family's page (c3 S15, c1 S15.3): the sealed mark at the size its
/// frame draws ([markSize]) over [body], either centred in the space (the face
/// states) or from the top with [keypad] anchored above [foot] (the PIN
/// states). One scroll view holds it all, so 200 % text scrolls rather than
/// overflows (13 §8).
class _LockPage extends StatelessWidget {
  const _LockPage({
    required this.body,
    required this.markSize,
    this.keypad,
    this.foot,
    this.centred = true,
  });

  /// c3 *App lock · waiting for Face ID* / *Face not recognised*: 60 px.
  static const markFace = RkSpace.s12 + RkSpace.s3;

  /// c3 *PIN instead · six digits*: 48 px — the frame the PIN states are
  /// built to (the c1 S15.3 *Enter PIN* / *Wrong PIN* frames draw the same
  /// state at 52 px without the keypad; design/match/S15.3.json).
  static const markPin = RkSpace.s12;

  /// c1 S15.3 (cooldown and disabled, nearest drawn: *Enter PIN · Face ID
  /// above the boxes*, *Wrong PIN · tries remaining*): 52 px.
  static const markPinS153 = RkSpace.s12 + RkSpace.s1;

  final double markSize;
  final List<Widget> body;
  final Widget? keypad;
  final Widget? foot;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.only(top: centred ? 0 : RkSpace.s10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RkSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: SealedMark(size: markSize)),
            for (final w in body) ...[const SizedBox(height: RkSpace.s5), w],
          ],
        ),
      ),
    );
    final bottom = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (keypad != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.s3,
              RkSpace.s5,
              RkSpace.s3,
              0,
            ),
            child: keypad,
          ),
        if (foot != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.s5,
              RkSpace.s2,
              RkSpace.s5,
              RkSpace.s4,
            ),
            child: Center(child: foot),
          )
        else
          const SizedBox(height: RkSpace.s4),
      ],
    );
    return Scaffold(
      body: SafeArea(
        // No intrinsics (RkFitText measures in a LayoutBuilder): the column
        // is at least the viewport tall, and `spaceBetween` spreads the room
        // — an empty lead keeps the face states centred above the foot.
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (centred) const SizedBox.shrink(),
                  content,
                  bottom,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The face glyph of c3 S15: `primary` while the sheet is up or idle,
/// `debit` once the face was not recognised (with the words beside it — never
/// colour alone, 07 §1 rule 3), painted as the canvas draws it
/// ([FaceIdGlyph]). Tappable when no sheet is up, so a
/// dismissed sheet is one tap from coming back.
class _FaceGlyph extends StatelessWidget {
  const _FaceGlyph({
    required this.prompting,
    required this.failed,
    required this.onPressed,
  });

  final bool prompting;
  final bool failed;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = failed
        ? RkStatusColors.of(context).debit
        : Theme.of(context).colorScheme.primary;
    final icon = FaceIdGlyph(
      size: RkIcon.grid * 2,
      color: color,
      semanticLabel: prompting ? l10n.lockBiometricPrompt : null,
    );
    if (onPressed == null) return Center(child: icon);
    return Center(
      child: IconButton(
        onPressed: onPressed,
        tooltip: l10n.lockBiometricButton,
        icon: icon,
      ),
    );
  }
}

/// The canvas's outlined button (c3 S15 *Try again*, c1 S15.3 *Face ID*):
/// an ink edge, square corners, sized to its label rather than the row.
class _InkButton extends StatelessWidget {
  const _InkButton({required this.label, this.glyph = false, this.onPressed});

  final String label;

  /// Leads with the compact Face ID glyph (c1 S15.3 *Face ID*).
  final bool glyph;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final text = Theme.of(context).textTheme;
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(RkSpace.s12, RkSpace.s10 + RkSpace.s1),
      padding: const EdgeInsets.symmetric(horizontal: RkSpace.s5),
      foregroundColor: ink,
      side: BorderSide(color: ink, width: RkIcon.stroke * 0.75),
      shape: const RoundedRectangleBorder(),
      textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final child = !glyph
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: FaceIdGlyph(
              size: RkSpace.s5,
              color: onPressed == null ? Theme.of(context).disabledColor : ink,
              compact: true,
            ),
            label: Text(label),
          );
    return Center(child: child);
  }
}

/// The foot link: *Use PIN instead* (`primary`, heavier) on the face states,
/// *Forgot PIN* (`muted`) on the PIN states (c3 S15, c1 S15.3).
class _FootLink extends StatelessWidget {
  const _FootLink({
    required this.label,
    required this.color,
    required this.onPressed,
    this.strong = false,
  });

  final String label;
  final Color color;
  final bool strong;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(RkSpace.s12, RkSpace.s12),
        foregroundColor: color,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: text.bodyLarge?.copyWith(
          color: color,
          fontWeight: strong ? FontWeight.w600 : null,
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
    required this.pinOnly,
    required this.onRetryBiometric,
  });

  final bool pinOnly;
  final String typed;
  final bool wrong;
  final bool busy;
  final int attemptsLeft;
  final bool warn;
  final BiometricOutcome? biometric;
  final VoidCallback? onRetryBiometric;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final biometricLine = switch (biometric) {
      BiometricOutcome.unavailable => l10n.lockBiometricUnavailable,
      BiometricOutcome.reenrolled => l10n.lockBiometricReenrolled,
      _ => null,
    };
    // The tries row's next step is a code to the number — except on a
    // PIN-only phone, whose reset is not (ADR 2026-10-05b, desk 147).
    final triesLine = attemptsLeft <= 1
        ? (pinOnly ? l10n.lockPinOneTryLeftPinOnly : l10n.lockPinOneTryLeft)
        : (pinOnly
              ? l10n.lockPinTriesLeftPinOnly(attemptsLeft)
              : l10n.lockPinTriesLeft(attemptsLeft));
    const gap = SizedBox(height: RkSpace.s5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // c1 S15.3 *Wrong PIN*: the title itself names the error, and the
        // six boxes stay edged in `debit` until the next digit — words and
        // colour, never colour alone (07 §1 rule 3).
        Semantics(
          liveRegion: wrong,
          child: RkFitText(
            wrong ? l10n.lockPinWrong : l10n.lockPinLabel,
            style: text.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
        gap,
        PinBoxes(
          filled: wrong && typed.isEmpty ? pinLength : typed.length,
          error: wrong,
          markNext: true,
        ),
        // The warning row only appears once the free attempts are spent —
        // before that it would be a threat, not a help (ADR 2026-09-05d §5).
        if (warn) ...[
          gap,
          Text(
            triesLine,
            style: text.bodyMedium?.copyWith(color: status.debit),
            textAlign: TextAlign.center,
          ),
        ],
        if (biometricLine != null && !pinOnly) ...[
          gap,
          _Line(
            icon: Icons.face_unlock_outlined,
            color: status.muted,
            text: biometricLine,
          ),
        ],
        gap,
        // ADR 2026-10-05b §1: a PIN-only phone has no biometric to retry, so
        // the button gives way to one muted line saying why. ADR 2026-10-06
        // §4: nor does one whose gate was invalidated — the reason line above
        // already says why, and a tap could only answer re-enrolled again.
        if (pinOnly)
          _Line(
            icon: Icons.info_outline,
            color: status.muted,
            text: l10n.lockPinOnlyNote,
          )
        else if (biometric != BiometricOutcome.reenrolled)
          _InkButton(
            label: l10n.lockBiometricButton,
            glyph: true,
            onPressed: onRetryBiometric,
          ),
      ],
    );
  }
}

class _CooldownPanel extends StatelessWidget {
  const _CooldownPanel({
    required this.remaining,
    required this.noBiometric,
    required this.onBiometric,
  });

  /// PIN-only, or the gate was invalidated: no face can open the app now.
  final bool noBiometric;
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
        RkFitText(
          l10n.lockCooldownTitle,
          style: text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: RkSpace.s2),
        RkFitText(
          l10n.lockCooldownBody,
          style: text.bodyLarge?.copyWith(color: status.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: RkSpace.s4),
        _Line(
          icon: Icons.hourglass_empty,
          color: status.pending,
          text: l10n.lockCooldownCountdown(formatCountdown(remaining)),
        ),
        // The wait is the PIN's policy alone — the face still opens the app,
        // unless the phone is PIN-only (ADR 2026-10-05b §1) or its gate was
        // invalidated (ADR 2026-10-06 §4).
        if (!noBiometric) ...[
          const SizedBox(height: RkSpace.s4),
          _InkButton(
            label: l10n.lockBiometricButton,
            glyph: true,
            onPressed: onBiometric,
          ),
        ],
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
        RkFitText(
          l10n.lockDisabledBody,
          style: text.bodyLarge?.copyWith(color: status.muted),
        ),
        const SizedBox(height: RkSpace.s4),
        FilledButton(onPressed: onReset, child: Text(l10n.lockForgotStart)),
      ],
    );
  }
}

/// c1 S15.3 *Forgot PIN · a code, not a lockout*: back chevron, the page
/// title, the muted explanation, and the one action at the foot.
///
/// ⚠️ SPEC: the frame also shows the registered number in a field. The lock
/// mounts before any session (cold_start_gate.dart) and [LockScope] carries
/// no number, so the field is left out rather than invented; the reset flow
/// behind [onStart] owns the number. Owner item (lane M13-KEY145B).
class _ForgotPage extends StatelessWidget {
  const _ForgotPage({
    required this.body,
    required this.action,
    required this.onBack,
  });

  /// The explanation for this phone's state (routine, before open, PIN-only,
  /// re-enrolled).
  final String body;

  /// The one action at the foot, or null where none can work yet (the
  /// ladder before the app is composed) — the page then explains and the
  /// back chevron returns to the PIN.
  final (String label, VoidCallback onPressed)? action;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
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
                child: IconButton(
                  onPressed: onBack,
                  tooltip: l10n.lockForgotCancel,
                  color: status.muted,
                  icon: const Icon(Icons.chevron_left, size: RkIcon.grid),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  RkSpace.s6,
                  RkSpace.s2,
                  RkSpace.s6,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RkFitText(l10n.lockForgotTitle, style: text.headlineMedium),
                    const SizedBox(height: RkSpace.s4),
                    RkFitText(
                      body,
                      style: text.bodyLarge?.copyWith(color: status.muted),
                    ),
                  ],
                ),
              ),
            ),
            if (action case (final label, final onPressed))
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RkSpace.s5,
                  RkSpace.s3,
                  RkSpace.s5,
                  RkSpace.s4,
                ),
                child: FilledButton(
                  onPressed: onPressed,
                  child: Text(
                    label,
                    // A longer label wraps at 200 % rather than clipping
                    // (13 §8).
                    softWrap: true,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              const SizedBox(height: RkSpace.s4),
          ],
        ),
      ),
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
