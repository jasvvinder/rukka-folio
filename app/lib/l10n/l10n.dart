// The localisation delegates every MaterialApp in this repo installs.
//
// Here rather than in `main.dart` (moved 13 Sep 2026) so the test harness and
// per-screen tests can take them without importing the composition root: a
// widget test needs EN/PA/HI, not the whole object graph.
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'gen/app_localizations.dart';

/// The l10n delegates every MaterialApp in this repo installs.
const rkLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
