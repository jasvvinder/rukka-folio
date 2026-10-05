// The MPIN pad: six boxes and a ten-key grid, shared by S0.8 (set the PIN) and
// S15.3 (enter it). One widget for both so the two screens cannot drift.
//
// Nothing here ever renders a digit that was typed — the boxes fill, they do
// not show the number (a shoulder-surfing gate is worthless if the PIN is on
// screen), and the screen-reader label counts digits rather than reading them.
//
// Tokens only (CLAUDE.md § Layout); colour is never the only signal — the
// error state pairs `debit` with words on the screen above (07 §1 rule 3).
// Drawn to the canvas (ADR 2026-10-05 §1): c3 S15 *PIN instead · six digits*
// for the boxes and the tiled keypad, c1 O4b / S15.3 for the same boxes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// How many digits an MPIN has (06 §4.4 🔒 — six, never four).
const pinLength = 6;

/// The canvas's box stroke (c3 S15 *PIN instead*, c1 O4b): 1.5 px, between
/// the 1 px hairline and the 2 px icon stroke.
const double _boxEdge = RkIcon.stroke * 0.75;

/// The six boxes (c3 S15 *PIN instead · six digits*, c1 S15.3, c1 O4b): bordered
/// squares on `surface`, a dot in each typed one, the rest in `hairline` —
/// with the next one edged in `primary` when [markNext] (c3 S15 draws it, c1
/// O4b does not). [filled] is how many digits are typed;
/// [error] edges all six in `debit` after a rejected attempt or a mismatch —
/// never the only signal, the screen above names the error in words.
class PinBoxes extends StatelessWidget {
  const PinBoxes({
    super.key,
    required this.filled,
    this.error = false,
    this.markNext = false,
  });

  /// Digits typed so far, 0..[pinLength].
  final int filled;

  /// Edge the next box in `primary` (c3 S15 *PIN instead · six digits*).
  final bool markNext;

  /// True after a wrong PIN — never the only signal.
  final bool error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.onSurface;
    Color edge(int i) {
      if (error) return status.debit;
      if (i < filled) return ink;
      if (markNext && i == filled) return scheme.primary;
      return status.hairline;
    }

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
                width: RkSpace.s10 + RkSpace.s1,
                height: RkSpace.rowMinHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border.all(color: edge(i), width: _boxEdge),
                ),
                child: i < filled
                    ? Container(
                        width: RkSpace.s3,
                        height: RkSpace.s3,
                        decoration: BoxDecoration(
                          color: ink,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
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
        style: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w500,
          fontFeatures: RkType.tabular,
        ),
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
            const Expanded(child: SizedBox(height: _keyHeight)),
            Expanded(child: key('0')),
            Expanded(
              child: _PadKey(
                onPressed: onDelete,
                semanticLabel: l10n.lockKeypadDelete,
                child: Icon(
                  Icons.backspace_outlined,
                  size: RkIcon.grid,
                  // The canvas draws ⌫ in `muted` (c3 S15 *PIN instead*);
                  // `locked` while there is nothing to delete.
                  color: onDelete == null ? status.locked : status.muted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The canvas's key tile height (c3 S15 *PIN instead*: 52 px).
const double _keyHeight = RkSpace.s12 + RkSpace.s1;

/// One key: a bordered tile on `surface` with square corners (c3 S15 *PIN
/// instead · six digits*). Still a [TextButton], so focus, ripple and the
/// disabled state come from the theme.
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
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(RkSpace.s1 * 0.75),
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
            minimumSize: const Size.fromHeight(_keyHeight),
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: status.hairline),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
