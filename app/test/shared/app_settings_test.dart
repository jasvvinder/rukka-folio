// F1 — settings drive the app (07 §16, 13 §3.2 row S13) and scope persists per
// tab (13 §2.2 🔒). S13 owns no state of its own: the shell holds it, writes it
// through [RkPrefs], and hands the live values back down.
@Tags(['F1'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/settings/settings_routes.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import 'test_app.dart';

void main() {
  Future<GoRouter> pumpApp(WidgetTester tester, AppSettings settings) async {
    final db = await openTestDb();
    final router = buildRouter(featureRoutes: settingsRoutes);
    await tester.pumpWidget(
      RukkaFolioApp(
        db: db,
        sync: FakeSyncClient(),
        auth: FakeAuthClient(),
        now: testNow,
        router: router,
        settings: settings,
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.push(SettingsPaths.root));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets(
    'F1-07-70 a language change and an Appearance change re-render the app and '
    'survive a restart',
    (tester) async {
      final prefs = MemoryPrefs();
      final settings = AppSettings(prefs: prefs);
      await settings.load();
      await pumpApp(tester, settings);
      expect(find.text('Settings'), findsOneWidget);

      // Language (07 §16): the row opens the sheet, the pick re-renders the
      // whole app — not just this screen.
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ਪੰਜਾਬੀ').last);
      await tester.pumpAndSettle();
      expect(find.text('ਸੈਟਿੰਗਾਂ'), findsOneWidget);
      expect(settings.locale, const Locale('pa'));

      // Appearance (ADR 2026-09-05f §H12) — icon-only segments, so the dark
      // segment is found by its icon.
      await tester.tap(find.byIcon(Icons.dark_mode));
      await tester.pumpAndSettle();
      expect(settings.appearance, ThemeMode.dark);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      // Restart: a second app over the same store reads both back.
      final restarted = AppSettings(prefs: prefs);
      await restarted.load();
      expect(restarted.locale, const Locale('pa'));
      expect(restarted.appearance, ThemeMode.dark);
      await pumpApp(tester, restarted);
      expect(find.text('ਸੈਟਿੰਗਾਂ'), findsOneWidget);
    },
  );

  testWidgets(
    'F1-07-70 the live auto-lock values reach S13, in minutes, not placeholders',
    (tester) async {
      final settings = AppSettings(prefs: MemoryPrefs());
      await settings.load();
      await settings.setAutoLock(
        idle: const Duration(minutes: 3),
        background: const Duration(minutes: 1),
      );
      await pumpApp(tester, settings);
      expect(
        find.text(
          'Locks after 3 minutes of no touch in the app\n'
          'Locks after 1 minute in the background',
        ),
        findsOneWidget,
      );
    },
  );

  test(
    'F1-07-70 scope persists per tab and defaults to the last used (13 §2.2)',
    () async {
      final prefs = MemoryPrefs();
      final settings = AppSettings(prefs: prefs);
      await settings.load();
      expect(settings.scopeOf(RkTab.home), isNull);

      await settings.setScope(RkTab.home, 'book:b1');
      expect(settings.scopeOf(RkTab.home), 'book:b1');
      // A tab that has never chosen one defaults to the last used.
      expect(settings.storedScopeOf(RkTab.ledger), isNull);
      expect(settings.scopeOf(RkTab.ledger), 'book:b1');

      // Once a tab chooses, it keeps its own — the other tab is untouched.
      await settings.setScope(RkTab.ledger, 'everything');
      expect(settings.scopeOf(RkTab.ledger), 'everything');
      expect(settings.scopeOf(RkTab.home), 'book:b1');

      final restarted = AppSettings(prefs: prefs);
      await restarted.load();
      expect(restarted.scopeOf(RkTab.home), 'book:b1');
      expect(restarted.scopeOf(RkTab.ledger), 'everything');
      expect(restarted.scopeOf(RkTab.inbox), 'everything');
    },
  );
}
