// The MPIN pad: six boxes and a ten-key grid, shared by S0.8 (set the PIN) and
// S15.3 (enter it). One widget for both so the two screens cannot drift.
//
// Nothing here ever renders a digit that was typed — the boxes fill, they do
// not show the number (a shoulder-surfing gate is worthless if the PIN is on
// screen), and the screen-reader label counts digits rather than reading them.
//
// Tokens only (CLAUDE.md § Layout); colour is never the only signal — the
// error state pairs `debit` with an icon and a line of text on the screen
// above (07 §1 rule 3).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// How many digits an MPIN has (06 §4.4 🔒 — six, never four).
const pinLength = 6;

/// The six boxes. [filled] is how many digits are typed; [error] tints and
/// marks them after a rejected attempt.
class PinBoxes extends StatelessWidget {
  const PinBoxes({super.key, required this.filled, this.error = false});

  /// Digits typed so far, 0..[pinLength].
  final int filled;

  /// True after a wrong PIN — never the only signal.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final edge = error ? status.debit : status.hairline;
    return Semantics(
      label: l10n.lockPinEntered(filled),
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < pinLength; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RkSpace.s1),
              child: Container(
                width: RkSpace.s5,
                height: RkSpace.s5,
                decoration: BoxDecoration(
                  color: i < filled
                      ? (error ? status.debit : scheme.primary)
                      : status.sunk,
                  shape: BoxShape.circle,
                  border: Border.all(color: edge, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The ten-key grid. [onDigit] receives '0'–'9'; [onDelete] removes the last
/// digit. Both are null while the pad is disabled (cooldown, saving), which is
/// the disabled state of 13 §4.3 — the screen above always says why.
class PinKeypad extends StatelessWidget {
  const PinKeypad({super.key, this.onDigit, this.onDelete});

  /// Called with a single ASCII digit.
  final void Function(String digit)? onDigit;

  /// Called for the backspace key.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    Widget key(String digit) => _PadKey(
      onPressed: onDigit == null ? null : () => onDigit!(digit),
      semanticLabel: digit,
      child: Text(
        digit,
        style: text.headlineSmall?.copyWith(fontFeatures: RkType.tabular),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) Expanded(child: key(d))]),
        Row(
          children: [
            const Expanded(child: SizedBox(height: RkSpace.s12)),
            Expanded(child: key('0')),
            Expanded(
              child: _PadKey(
                onPressed: onDelete,
                semanticLabel: l10n.lockKeypadDelete,
                child: Icon(
                  Icons.backspace_outlined,
                  size: RkIcon.grid,
                  color: onDelete == null ? status.locked : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.child,
    required this.semanticLabel,
    this.onPressed,
  });

  final Widget child;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(RkSpace.s1),
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: TextButton(
          onPressed: onPressed == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onPressed!();
                },
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(RkSpace.s12),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(RkRadius.lg)),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
