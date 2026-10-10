// The numeric keypad that holds the lower region by default (07 §5 step 1):
// digits, `+` quick-sum (`120+80+40`), `.` for paise, and backspace. The keys
// are laid out in flexible rows so 200 % text on a 360×800 or 375×667 screen
// shrinks the keys rather than overflowing — this screen must not scroll.
//
// No amount-in-words key and no "Next": the amount is live in the preview
// line and Save is the only forward action (01 §1 rule 10 🔒).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// The `+` key's character.
const String keypadPlus = '+';

/// The `.` key's character.
const String keypadDot = '.';

/// The backspace key's identity (its widget key and [EntryKeypad.onKey]
/// value). Never drawn: U+232B is in none of the bundled faces (11 §4.4), so
/// the key shows [keypadBackspaceIcon] instead (PLAN desk 193 (e)).
const String keypadBackspace = '⌫';

/// What the backspace key draws — the canvas 2 keypad's delete-left glyph.
const IconData keypadBackspaceIcon = Icons.backspace_outlined;

/// Rows of the pad, in order.
const List<List<String>> keypadRows = [
  ['1', '2', '3', keypadPlus],
  ['4', '5', '6', keypadDot],
  ['7', '8', '9', keypadBackspace],
  ['0'],
];

/// The keypad.
class EntryKeypad extends StatelessWidget {
  /// Creates the pad.
  const EntryKeypad({super.key, required this.onKey, required this.keyOf});

  /// A key was pressed; the character is one of [keypadRows].
  final void Function(String key) onKey;

  /// Widget key for one pad key, so a test can drive the pad.
  final Key Function(String key) keyOf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.entryKeypadLabel,
      child: Column(
        children: [
          for (final row in keypadRows)
            Expanded(
              child: Row(
                children: [
                  for (final k in row)
                    Expanded(
                      child: _PadKey(
                        keyChar: k,
                        widgetKey: keyOf(k),
                        onTap: () => onKey(k),
                        label: switch (k) {
                          keypadPlus => l10n.entryKeypadAdd,
                          keypadDot => l10n.entryKeypadPaise,
                          keypadBackspace => l10n.entryKeypadBackspace,
                          _ => k,
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.keyChar,
    required this.widgetKey,
    required this.onTap,
    required this.label,
  });

  final String keyChar;
  final Key widgetKey;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(RkSpace.s1),
      // The spoken node carries the tap itself: with the InkWell excluded,
      // TalkBack / VoiceOver would otherwise find a button that does nothing.
      child: Semantics(
        button: true,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          key: widgetKey,
          color: status.sunk,
          borderRadius: BorderRadius.circular(RkRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(RkRadius.md),
            child: Center(
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RkSpace.s2),
                  child: keyChar == keypadBackspace
                      ? Icon(
                          keypadBackspaceIcon,
                          size: MediaQuery.textScalerOf(context)
                              .scale(RkType.page.fontSize ?? 28),
                          color: Theme.of(context).colorScheme.onSurface,
                        )
                      : Text(
                          keyChar,
                          style: RkType.page.copyWith(
                            fontFeatures: RkType.tabular,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
