// S13 Settings (13 §3.2 row S13, 07 §16 🔒). Row order is normative — do not
// reorder without a doc change: Language (per member) · Appearance (system ·
// light · dark, ADR 2026-09-05f §H12) · Your books → Book management, →
// Opening balances (the correction-wizard door, ADR 2026-09-03b ruling 2) ·
// Categories · Notifications · Auto-lock (both values, 06 §4.5 + ADR
// 2026-09-05 §7) · Export everything (06 §9.2, always available,
// plan-independent) · Subscription (07 §20) · About & support (07 §22).
//
// Only Language and Appearance land as working controls in this milestone;
// every other row's destination has not been built yet, so it renders
// disabled-with-reason (07 §1 rule 6) — dimmed, paired with an icon and a
// sentence, never a silently inert tap and never simply removed from the
// list (that would be a dead end of a different kind: a door nobody can
// find).
//
// Appearance and Language are handed up through constructor callbacks —
// this screen owns no theme or locale state itself (that lives where
// `RukkaFolioApp` is built); a null callback still shows the current value,
// it only drops the ability to change it, matching the EntryDetailScreen
// nullable-callback convention. Auto-lock is read-only display here: the
// lock feature (a concurrent lane, `features/lock`/`features/devices`) owns
// changing it, so this screen only ever reads the two values it is given.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../widgets/settings_row.dart';

/// S13 — the Settings hub, reached from Menu (S8).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.currentLocale,
    this.onLanguageChanged,
    this.appearance = ThemeMode.system,
    this.onAppearanceChanged,
    required this.autoLockIdle,
    required this.autoLockBackground,
  });

  /// The app's current locale (en/pa/hi) — shown as the Language row's value.
  final Locale currentLocale;

  /// Handed the chosen locale when a user picks a language. Null leaves the
  /// row showing the current value with no way to change it here (this
  /// screen owns no locale state of its own).
  final void Function(Locale locale)? onLanguageChanged;

  /// The app's current appearance (ADR 2026-09-05f §H12: system/light/dark).
  final ThemeMode appearance;

  /// Handed the chosen mode when a user picks one. Null leaves the control
  /// showing the current value with no way to change it here.
  final void Function(ThemeMode mode)? onAppearanceChanged;

  /// Foreground inactivity value (default 5 min, ADR 2026-09-05 §7).
  final Duration autoLockIdle;

  /// Background timeout value (default 2 min, 06 §4.5).
  final Duration autoLockBackground;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSectionHeader(l10n.settingsSectionGeneral),
              SettingsRow(
                title: l10n.settingsLanguageRowTitle,
                subtitle: _languageLabel(l10n, currentLocale),
                onTap: () => _pickLanguage(context, l10n),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: RkSpace.gutter,
                  vertical: RkSpace.s3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsAppearanceRowTitle,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    _AppearanceControl(
                      value: appearance,
                      onChanged: onAppearanceChanged,
                      l10n: l10n,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: status.hairline),
              SettingsSectionHeader(l10n.settingsSectionBooks),
              SettingsDisabledRow(
                title: l10n.settingsBooksManageRowTitle,
                subtitle: l10n.settingsBooksManageRowSubtitle,
                reason: l10n.settingsBooksManageRowReason,
              ),
              SettingsDisabledRow(
                title: l10n.settingsOpeningBalancesRowTitle,
                subtitle: l10n.settingsOpeningBalancesRowSubtitle,
                reason: l10n.settingsOpeningBalancesRowReason,
              ),
              Divider(height: 1, color: status.hairline),
              SettingsDisabledRow(
                title: l10n.settingsCategoriesRowTitle,
                reason: l10n.settingsCategoriesRowReason,
              ),
              SettingsDisabledRow(
                title: l10n.settingsNotificationsRowTitle,
                reason: l10n.settingsNotificationsRowReason,
              ),
              SettingsDisabledRow(
                title: l10n.settingsAutolockRowTitle,
                subtitle:
                    '${l10n.settingsAutolockRowIdle(autoLockIdle.inMinutes)}\n'
                    '${l10n.settingsAutolockRowBackground(autoLockBackground.inMinutes)}',
                reason: l10n.settingsAutolockRowReason,
              ),
              Divider(height: 1, color: status.hairline),
              SettingsDisabledRow(
                title: l10n.settingsExportRowTitle,
                subtitle: l10n.settingsExportRowSubtitle,
                reason: l10n.settingsExportRowReason,
              ),
              SettingsDisabledRow(
                title: l10n.settingsSubscriptionRowTitle,
                reason: l10n.settingsSubscriptionRowReason,
              ),
              SettingsDisabledRow(
                title: l10n.settingsAboutRowTitle,
                reason: l10n.settingsAboutRowReason,
              ),
              const SizedBox(height: RkSpace.s6),
            ],
          ),
        ),
      ),
    );
  }

  String _languageLabel(AppLocalizations l10n, Locale locale) =>
      switch (locale.languageCode) {
        'pa' => l10n.settingsLanguageOptionPa,
        'hi' => l10n.settingsLanguageOptionHi,
        _ => l10n.settingsLanguageOptionEn,
      };

  Future<void> _pickLanguage(BuildContext context, AppLocalizations l10n) {
    final onChanged = onLanguageChanged;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _LanguageSheet(
        title: l10n.settingsLanguageSheetTitle,
        current: currentLocale,
        onPicked: onChanged == null
            ? null
            : (locale) {
                Navigator.of(sheetContext).pop();
                onChanged(locale);
              },
      ),
    );
  }
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({
    required this.title,
    required this.current,
    this.onPicked,
  });

  final String title;
  final Locale current;
  final void Function(Locale locale)? onPicked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    // Every option always renders in its own script, regardless of the
    // current app locale — matches S0.1 (design-system §3.1 rule 1).
    final options = <(Locale, String)>[
      (const Locale('en'), l10n.settingsLanguageOptionEn),
      (const Locale('pa'), l10n.settingsLanguageOptionPa),
      (const Locale('hi'), l10n.settingsLanguageOptionHi),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s2,
          RkSpace.gutter,
          RkSpace.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleLarge),
            const SizedBox(height: RkSpace.s3),
            for (final (locale, label) in options)
              Semantics(
                button: true,
                selected: locale.languageCode == current.languageCode,
                label: label,
                child: InkWell(
                  onTap: onPicked == null ? null : () => onPicked!(locale),
                  borderRadius: BorderRadius.circular(RkRadius.md),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: RkSpace.rowMinHeight,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: RkSpace.s3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: text.bodyLarge,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                        if (locale.languageCode == current.languageCode)
                          Icon(Icons.check_circle, color: status.credit)
                        else
                          Icon(
                            Icons.radio_button_unchecked,
                            color: status.muted,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The Appearance three-way control (ADR 2026-09-05f §H12: system · light ·
/// dark). Selection is shown by an outline + icon change, never colour
/// alone (07 §1 rule 3).
class _AppearanceControl extends StatelessWidget {
  const _AppearanceControl({
    required this.value,
    required this.onChanged,
    required this.l10n,
  });

  final ThemeMode value;
  final void Function(ThemeMode mode)? onChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // Icon-only segments (labels carried by `tooltip`, not on-screen text):
    // three text labels next to icons would overflow a 360dp row at 200%
    // font scale (07 §18), and the icon alone already tells system/light/dark
    // apart without relying on colour (07 §1 rule 3) — selection adds an
    // outline + a filled icon on top of that.
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<ThemeMode>(
        segments: [
          ButtonSegment(
            value: ThemeMode.system,
            tooltip: l10n.settingsAppearanceOptionSystem,
            label: Semantics(
              label: l10n.settingsAppearanceOptionSystem,
              child: const Icon(Icons.brightness_auto),
            ),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            tooltip: l10n.settingsAppearanceOptionLight,
            label: Semantics(
              label: l10n.settingsAppearanceOptionLight,
              child: const Icon(Icons.light_mode),
            ),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            tooltip: l10n.settingsAppearanceOptionDark,
            label: Semantics(
              label: l10n.settingsAppearanceOptionDark,
              child: const Icon(Icons.dark_mode),
            ),
          ),
        ],
        selected: {value},
        onSelectionChanged: onChanged == null
            ? null
            : (selection) => onChanged!(selection.first),
      ),
    );
  }
}
