// S19-shaped fail-closed screen: shown when the ledger cannot be opened
// (03 §5 🔒). No data, no error codes, one plain sentence (07 §1 rule 12).
//
// A widget, so it lives in `shared/widgets/` rather than in the composition
// root (moved 13 Sep 2026).
import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../theme.dart';
import '../tokens.dart';

/// Shown when the ledger cannot be opened (03 §5 fail-closed). No data, no
/// codes on screen — one sentence.
class RukkaFolioBlocked extends StatelessWidget {
  /// Creates the blocked screen.
  const RukkaFolioBlocked({super.key, this.locale});

  /// Forced locale (tests); null follows the device.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: rkLocalizationsDelegates,
      theme: rkTheme(Brightness.light),
      darkTheme: rkTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(RkSpace.gutter),
              child: Center(
                child: Text(
                  AppLocalizations.of(context).appOpenFailedBody,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
