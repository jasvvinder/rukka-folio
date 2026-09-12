// Settings feature routes (features/README "Routes"). Mounted on the root
// navigator; reached by pushing [SettingsPaths.root] from Menu (S8, not
// built in this lane).
//
// `SettingsScreen` takes locale/appearance/auto-lock as constructor
// parameters rather than reading any live app state itself (07 §16 lane
// brief): Language and Appearance are real controls whose changes are
// handed up through `onLanguageChanged`/`onAppearanceChanged`, and
// Auto-lock is read-only display of two values owned by the lock feature.
// That state lives in the shell: `AppSettings` (app/lib/shared) holds the
// locale, the appearance mode and the two live auto-lock values, persists
// them, and hands them down through `AppSettingsScope`. This builder reads
// that scope, so a pick here re-renders the whole app and survives a
// restart. With no scope mounted (a shell-only test) the row still shows
// the device locale and the ADR-default auto-lock values, with no way to
// change them from here.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/app_settings.dart';
import 'screens/s13_settings_screen.dart';
import 'settings_paths.dart';

export 'settings_paths.dart';

/// Default auto-lock values (ADR 2026-09-05 §7 · 06 §4.5) shown until the
/// lock feature's live values are wired in at integration.
const settingsDefaultAutoLockIdle = Duration(minutes: 5);
const settingsDefaultAutoLockBackground = Duration(minutes: 2);

final List<RouteBase> settingsRoutes = [
  GoRoute(
    path: SettingsPaths.root,
    builder: (context, state) {
      final settings = AppSettingsScope.maybeOf(context);
      return SettingsScreen(
        currentLocale: settings?.locale ?? Localizations.localeOf(context),
        onLanguageChanged: settings?.setLocale,
        appearance: settings?.appearance ?? ThemeMode.system,
        onAppearanceChanged: settings?.setAppearance,
        autoLockIdle: settings?.autoLockIdle ?? settingsDefaultAutoLockIdle,
        autoLockBackground:
            settings?.autoLockBackground ?? settingsDefaultAutoLockBackground,
      );
    },
  ),
];
