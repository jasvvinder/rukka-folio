// S0.1 Language picker (13 §3.2, 07 §3.1 step 1) — the first screen ever
// shown after the splash. Three launch languages (01 §1 rule 1). Nothing is
// pre-selected: this is the one moment before the app knows anything about
// the user, so guessing would be a bias, not a convenience (⚠️ SPEC: 07 §3.1
// does not rule on a default here — the conservative reading is "the user
// picks", matching the entry screen's nothing-pre-selected posture,
// ADR 2026-09-05f §C). Every option is always rendered in its own script,
// regardless of the current app locale (design-system §3.1 rule 1 — `lang`
// per option). Selection is shown by an outline + check, never colour alone
// (07 §1 rule 3).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

class LanguagePickerScreen extends StatefulWidget {
  const LanguagePickerScreen({super.key, this.onSelected});

  /// Called with the chosen locale when Continue is pressed.
  final void Function(Locale locale)? onSelected;

  @override
  State<LanguagePickerScreen> createState() => _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends State<LanguagePickerScreen> {
  Locale? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final options = <(Locale, String)>[
      (const Locale('en'), l10n.onboardingLanguageOptionEn),
      (const Locale('pa'), l10n.onboardingLanguageOptionPa),
      (const Locale('hi'), l10n.onboardingLanguageOptionHi),
    ];
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
                        l10n.onboardingLanguageTitle,
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Text(
                        l10n.onboardingLanguageSubtitle,
                        style: text.bodyLarge,
                      ),
                      const SizedBox(height: RkSpace.s6),
                      for (final (locale, label) in options) ...[
                        _LanguageOption(
                          locale: locale,
                          label: label,
                          selected: _picked == locale,
                          onTap: () => setState(() => _picked = locale),
                        ),
                        const SizedBox(height: RkSpace.s3),
                      ],
                    ],
                  ),
                ),
              ),
              FilledButton(
                onPressed: _picked == null
                    ? null
                    : () => widget.onSelected?.call(_picked!),
                child: Text(l10n.onboardingLanguageContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.locale,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Locale locale;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RkRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.s4,
            vertical: RkSpace.s3,
          ),
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            border: Border.all(
              color: selected ? scheme.primary : status.hairline,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(RkRadius.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: text.bodyLarge,
                  textDirection: TextDirection.ltr,
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: scheme.primary)
              else
                Icon(Icons.radio_button_unchecked, color: status.muted),
            ],
          ),
        ),
      ),
    );
  }
}
