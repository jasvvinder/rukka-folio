import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/gen/app_localizations.dart';
import 'shared/tokens.dart';

void main() {
  runApp(const RukkaFolioApp());
}

/// M0 hello-world shell. Real screens arrive at M5 (07, 13); this proves the
/// wiring: tokens only, ARB strings in EN/PA/HI, brand fonts, light + dark.
class RukkaFolioApp extends StatelessWidget {
  const RukkaFolioApp({super.key, this.locale});

  /// Forced locale (tests, previews); null follows the device.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const _HelloScreen(),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final light = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: RkType.family,
      fontFamilyFallback: const [RkType.familyGurmukhi, RkType.familyFallback],
      scaffoldBackgroundColor: light ? RkColorsLight.bg : RkColorsDark.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: light ? RkColorsLight.primary : RkColorsDark.primary,
        onPrimary: light ? RkColorsLight.onPrimary : RkColorsDark.onPrimary,
        secondary: light ? RkColorsLight.accent : RkColorsDark.accent,
        onSecondary: light ? RkColorsLight.onPrimary : RkColorsDark.onPrimary,
        error: light ? RkColorsLight.debit : RkColorsDark.debit,
        onError: light ? RkColorsLight.onPrimary : RkColorsDark.onPrimary,
        surface: light ? RkColorsLight.surface : RkColorsDark.surface,
        onSurface: light ? RkColorsLight.text : RkColorsDark.text,
      ),
    );
  }
}

class _HelloScreen extends StatelessWidget {
  const _HelloScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.appName,
                style: RkType.page.copyWith(color: scheme.primary),
              ),
              const SizedBox(height: RkSpace.s2),
              Text(
                l10n.splashOpening,
                style: RkType.body.copyWith(color: scheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
