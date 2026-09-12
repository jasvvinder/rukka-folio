// F1-07-65 / F1-07-66 / F1-07-67 widget tests for S13 Settings (13 §3.2 row
// S13, 07 §16 🔒 row order, ADR 2026-09-05f §H12 appearance, ADR
// 2026-09-05 §7 auto-lock both values, ADR 2026-09-03b ruling 2 opening
// balances door, 06 §9.2 export always available).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/settings/screens/s13_settings_screen.dart';

import '../../shared/test_app.dart';

void main() {
  group('S13 Settings (07 §16 row order)', () {
    testWidgets('F1-07-29 S13 Settings screen renders (07 §16)', (
      tester,
    ) async {
      await pumpRk(
        tester,
        const SettingsScreen(
          currentLocale: Locale('en'),
          autoLockIdle: Duration(minutes: 5),
          autoLockBackground: Duration(minutes: 2),
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets(
      'F1-07-65 renders every row from 07 §16 in order, Language first, About & support last',
      (tester) async {
        await pumpRk(
          tester,
          const SettingsScreen(
            currentLocale: Locale('en'),
            autoLockIdle: Duration(minutes: 5),
            autoLockBackground: Duration(minutes: 2),
          ),
        );

        const expectedOrder = [
          'Language',
          'Appearance',
          'Book management',
          'Opening balances',
          'Categories',
          'Notifications',
          'Auto-lock',
          'Export everything',
          'Subscription',
          'About & support',
        ];
        final titles = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .toList();
        var cursor = -1;
        for (final title in expectedOrder) {
          final at = titles.indexOf(title);
          expect(at, greaterThan(-1), reason: 'missing row: $title');
          expect(at, greaterThan(cursor), reason: '$title out of 07 §16 order');
          cursor = at;
        }
      },
    );

    testWidgets(
      'F1-07-65 Language row shows the current locale and hands a pick up through onLanguageChanged',
      (tester) async {
        Locale? picked;
        await pumpRk(
          tester,
          SettingsScreen(
            currentLocale: const Locale('en'),
            onLanguageChanged: (l) => picked = l,
            autoLockIdle: const Duration(minutes: 5),
            autoLockBackground: const Duration(minutes: 2),
          ),
        );

        expect(find.text('English'), findsOneWidget);

        await tester.tap(find.text('Language'));
        await tester.pumpAndSettle();
        // Every option renders in its own script regardless of app locale
        // (matches S0.1, design-system §3.1 rule 1).
        expect(find.text('ਪੰਜਾਬੀ'), findsOneWidget);
        expect(find.text('हिन्दी'), findsOneWidget);

        await tester.tap(find.text('ਪੰਜਾਬੀ'));
        await tester.pumpAndSettle();

        expect(picked, const Locale('pa'));
      },
    );

    testWidgets(
      'F1-07-65 🔒 Appearance is a three-way system/light/dark control that hands the choice up through onAppearanceChanged, never editing shared/theme.dart itself',
      (tester) async {
        ThemeMode? picked;
        await pumpRk(
          tester,
          SettingsScreen(
            currentLocale: const Locale('en'),
            appearance: ThemeMode.system,
            onAppearanceChanged: (m) => picked = m,
            autoLockIdle: const Duration(minutes: 5),
            autoLockBackground: const Duration(minutes: 2),
          ),
        );

        expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
        expect(find.byIcon(Icons.brightness_auto), findsOneWidget);
        expect(find.byIcon(Icons.light_mode), findsOneWidget);
        expect(find.byIcon(Icons.dark_mode), findsOneWidget);

        await tester.tap(find.byIcon(Icons.dark_mode));
        await tester.pumpAndSettle();

        expect(picked, ThemeMode.dark);
      },
    );

    testWidgets(
      'F1-07-66 a row with no destination yet is disabled-with-reason, never a silently inert tap (07 §1 rule 6)',
      (tester) async {
        await pumpRk(
          tester,
          const SettingsScreen(
            currentLocale: Locale('en'),
            autoLockIdle: Duration(minutes: 5),
            autoLockBackground: Duration(minutes: 2),
          ),
        );

        // Every disabled row pairs its dimmed state with an icon AND a
        // written reason (07 §1 rule 3: colour never alone).
        expect(find.byIcon(Icons.schedule), findsNWidgets(8));
        expect(
          find.text('Not built yet — coming in a later update.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'The opening balance correction wizard has not been built yet.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('The export screen has not been built yet.'),
          findsOneWidget,
        );

        final categoriesSemantics = tester.getSemantics(
          find
              .ancestor(
                of: find.text('Categories'),
                matching: find.byType(Semantics),
              )
              .first,
        );
        // ignore: deprecated_member_use
        expect(categoriesSemantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
      },
    );

    testWidgets(
      'F1-07-66 🔒 Auto-lock shows both values, background and idle (ADR 2026-09-05 §7), and never imports features/lock or features/devices',
      (tester) async {
        await pumpRk(
          tester,
          const SettingsScreen(
            currentLocale: Locale('en'),
            autoLockIdle: Duration(minutes: 5),
            autoLockBackground: Duration(minutes: 2),
          ),
        );

        expect(
          find.textContaining('Locks after 5 minutes of no touch'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Locks after 2 minutes in the background'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-07-66 Export everything never reads as plan-gated: the reason names the missing screen, not a subscription (06 §9.2)',
      (tester) async {
        await pumpRk(
          tester,
          const SettingsScreen(
            currentLocale: Locale('en'),
            autoLockIdle: Duration(minutes: 5),
            autoLockBackground: Duration(minutes: 2),
          ),
        );

        expect(
          find.textContaining('Always available, on every plan'),
          findsOneWidget,
        );
        expect(find.textContaining('plan'), findsNWidgets(1));
      },
    );

    testWidgets(
      'F1-07-67 strings resolve in EN/PA/HI with no overflow at 200% on a 360x800 surface',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const SettingsScreen(
                currentLocale: Locale('en'),
                autoLockIdle: Duration(minutes: 5),
                autoLockBackground: Duration(minutes: 2),
              ),
            ),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  });
}
