// The parts the S0.2 family draws with (canvas 1b L1–L5, L8; canvas 1 O2a/O2b):
// the back chevron row, the +91 number on its rule, the six code boxes, the
// keypad dock, the two full-width actions, the plain avatar and the inline
// error line. One file so S0.2, S0.2a, S0.2b and S0.2e cannot drift apart.
//
// Tokens only (CLAUDE.md § Layout). Colour is never the only signal (07 §1
// rule 3): the wrong-code edge always comes with the words of [AuthErrorLine].
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../lock/widgets/pin_pad.dart';

/// Digits in an OTP (06 §2: six).
const otpLength = 6;

/// The canvas's box and rule stroke (c1b L2/L3: 1.5 px, between the 1 px
/// hairline and the 2 px icon stroke) — the same value [PinBoxes] uses.
const double authEdge = RkIcon.stroke * 0.75;

/// The canvas's full-width action height (c1b L0/L1/L8: 52 px).
const double authActionHeight = RkSpace.s12 + RkSpace.s1;

/// The page side margin the canvas draws (c1b: 21 px → the s5 step).
const double authSide = RkSpace.s5;

/// The smallest tap target any way out may have (design-system §3.1 rule 9:
/// ≥ 44 pt; 13 §8: ≥ 44 dp). The canvas draws the inline links as bare text;
/// it decides how they look, never how small their hit area is (ADR
/// 2026-10-05 §1).
const double authMinTarget = RkSpace.s10 + RkSpace.s1;

/// The error line's icon (c1b L4: 18 px beside 14.5 px words).
const double authErrorIcon = RkSpace.s4 + RkSpace.s1 / 2;

/// What the code field keeps of an edit: six digits at most. A paste or the
/// platform's one-time-code autofill can bring the whole SMS ("Your code is
/// 482913. Valid 10 min."); a standalone run of six digits in it wins,
/// otherwise the digits are kept in order and cut at six.
class OtpCodeFormatter extends TextInputFormatter {
  const OtpCodeFormatter();

  static final _standalone = RegExp(r'(?<![0-9])[0-9]{6}(?![0-9])');
  static final _nonDigit = RegExp(r'[^0-9]');

  /// The code [raw] carries, as the field would keep it.
  static String extract(String raw) {
    final digits =
        _standalone.firstMatch(raw)?.group(0) ?? raw.replaceAll(_nonDigit, '');
    return digits.length > otpLength ? digits.substring(0, otpLength) : digits;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final code = extract(newValue.text);
    return TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
  }
}

/// `98765 43210` — the national number grouped 5 + 5 the way the canvas
/// writes it. Anything that is not ten digits comes back grouped as far as it
/// goes (`98765 43` while typing, c1 O2a).
String groupNational(String digits) => digits.length <= 5
    ? digits
    : '${digits.substring(0, 5)} ${digits.substring(5)}';

/// `+91 98765 43210` for an E.164 Indian number; anything else unchanged.
String displayPhone(String e164) =>
    e164.startsWith('+91') ? '+91 ${groupNational(e164.substring(3))}' : e164;

/// The back chevron row every step but the front door draws (c1b L1–L5, L8).
/// A null [onBack] keeps the row's height with no button, so a step that has
/// nowhere to go back to does not shift its heading.
class AuthBackRow extends StatelessWidget {
  const AuthBackRow({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: RkSpace.s1, bottom: RkSpace.s2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: RkSpace.s12,
          child: onBack == null
              ? null
              : IconButton(
                  onPressed: onBack,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  color: status.muted,
                  icon: const Icon(Icons.chevron_left, size: RkIcon.grid),
                ),
        ),
      ),
    );
  }
}

/// `+91  98765 43210` on a primary rule (c1b L2, c1 O2a): the prefix muted,
/// the digits large and tabular, a caret after them while [focused].
class PhoneNumberLine extends StatelessWidget {
  const PhoneNumberLine({
    super.key,
    required this.digits,
    this.focused = true,
    this.error = false,
  });

  /// The national digits typed so far (0–10).
  final String digits;
  final bool focused;

  /// Edge the rule in `danger` — never alone; the error line says why.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final big = Theme.of(context).textTheme.headlineMedium
        ?.copyWith(fontFeatures: RkType.tabular, letterSpacing: RkSpace.s1 / 2);
    return Semantics(
      label: l10n.authPhoneFieldLabel,
      value: '${l10n.authPhoneCountryCode} ${groupNational(digits)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.only(bottom: RkSpace.s3),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: error ? status.danger : scheme.primary,
              width: authEdge,
            ),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.authPhoneCountryCode,
                style: big?.copyWith(
                  color: status.muted,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: RkSpace.s3),
              Text(groupNational(digits), style: big),
              if (focused)
                Container(
                  width: RkIcon.stroke,
                  height: RkSpace.s8,
                  margin: const EdgeInsets.only(left: RkSpace.s1 / 2),
                  color: scheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The six code boxes (c1b L3/L4, c1 O2b): rounded squares on `surface` that
/// show the typed digit — a one-time code is not a secret to hide the way the
/// PIN is. The next box is edged in `primary` with a caret; [error] edges
/// all six in `danger` (c1b L4) beside the words of [AuthErrorLine].
class OtpBoxes extends StatelessWidget {
  const OtpBoxes({super.key, required this.code, this.error = false});

  final String code;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final digit = Theme.of(context).textTheme.headlineMedium
        ?.copyWith(fontFeatures: RkType.tabular);
    return Semantics(
      label: l10n.authOtpBoxesLabel(code.length),
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < otpLength; i++) ...[
            if (i > 0) const SizedBox(width: RkSpace.s2),
            Expanded(
              child: AspectRatio(
                aspectRatio: 5 / 6,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(RkRadius.md),
                    border: Border.all(
                      color: error
                          ? status.danger
                          : (i == code.length
                                ? scheme.primary
                                : status.hairline),
                      width: error || i == code.length ? authEdge : 1,
                    ),
                  ),
                  child: i < code.length
                      ? FittedBox(child: Text(code[i], style: digit))
                      : (i == code.length && !error
                            ? Container(
                                width: RkIcon.stroke,
                                height: RkSpace.s6,
                                color: scheme.primary,
                              )
                            : null),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The keypad on its recessed dock (c1b L2–L4, c1 O2a/O2b): the shared
/// [PinKeypad] the lock and S0.8 use, so the three cannot drift.
class AuthKeypadDock extends StatelessWidget {
  const AuthKeypadDock({super.key, this.onDigit, this.onDelete});

  final void Function(String digit)? onDigit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.sunk,
        border: Border(top: BorderSide(color: status.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.s1,
          RkSpace.s2,
          RkSpace.s1,
          RkSpace.s2,
        ),
        child: PinKeypad(onDigit: onDigit, onDelete: onDelete),
      ),
    );
  }
}

/// The primary full-width action (c1b L0/L1/L8: 52 px, primary fill).
class AuthPrimaryAction extends StatelessWidget {
  const AuthPrimaryAction({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(authActionHeight),
      textStyle: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    ),
    child: Text(label, textAlign: TextAlign.center),
  );
}

/// The secondary full-width action (c1b L0/L1/L8): outlined in `primary`,
/// the label in `primary` — the canvas edges it in ink, not the hairline the
/// theme's outlined button uses.
class AuthSecondaryAction extends StatelessWidget {
  const AuthSecondaryAction({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(authActionHeight),
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary, width: authEdge),
        textStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// A plain avatar: a primary disc with a person glyph. The canvas draws the
/// person's initials (c1b L1/L5); `otp/verify` does not carry the display
/// name, so the glyph stands in (see the S0.2a / S0.2b ⚠️ SPEC notes).
class AuthAvatar extends StatelessWidget {
  const AuthAvatar({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person_outline,
          size: size / 2,
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}

/// The inline error: icon + words in `danger` (c1b L4: 14.5 px words → the
/// body-small role, an 18 px icon), announced live.
class AuthErrorLine extends StatelessWidget {
  const AuthErrorLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: RkSpace.s1 / 2),
          child: Icon(
            Icons.error_outline,
            size: authErrorIcon,
            color: status.danger,
          ),
        ),
        const SizedBox(width: RkSpace.s3),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: status.danger),
            ),
          ),
        ),
      ],
    );
  }
}

/// A screen of the S0.2 family: the back row, a scrolling body and, pinned
/// to the foot, [footer] (actions or the keypad dock). At 200 % the whole
/// page scrolls rather than clipping (07 §1 rule 9).
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.body,
    this.onBack,
    this.footer,
    this.top,
    this.footerPadded = true,
  });

  final VoidCallback? onBack;

  /// Above the back row (the offline chip).
  final Widget? top;
  final Widget body;
  final Widget? footer;

  /// Whether [footer] sits inside the side margins (actions) or bleeds to
  /// the edges (the keypad dock).
  final bool footerPadded;

  @override
  Widget build(BuildContext context) {
    final foot = footer;
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
                      ?top,
                      AuthBackRow(onBack: onBack),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: authSide,
                        ),
                        child: body,
                      ),
                    ],
                  ),
                  if (foot != null)
                    Padding(
                      padding: footerPadded
                          ? const EdgeInsets.fromLTRB(
                              authSide,
                              RkSpace.s6,
                              authSide,
                              RkSpace.s4,
                            )
                          : const EdgeInsets.only(top: RkSpace.s6),
                      child: foot,
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
