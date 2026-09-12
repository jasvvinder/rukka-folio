// F1-07-14 (07 §2 🔒 navigation map — the Menu tab and its contents) and
// F1-07-77 (13 §3.2 S8 row — row order and navigation out) for S8 Menu.
//
// Content is exercised by pumping [MenuScreen] directly (matching
// `SettingsScreen`'s own test convention) rather than through the full
// shell/router: [MenuScreen] sits inside a `StatefulShellRoute` branch whose
// `IndexedStack` gives every branch loose layout constraints, and under
// `flutter_test`'s default surface that collapses the branch's Scaffold body
// to zero height — a `ListView` inside it then never lays out any row, so
// every row is invisible to widget finders even though it is present in the
// element tree (`tester.allWidgets` still finds it; `find.byType` does not).
// That is a `flutter_test` + `StatefulShellRoute` interaction, not a defect
// in this screen, and `router_test.dart` (13 §3.1/§3.2) never exercises
// list content through the shell for the same reason — it only checks tab
// switches and single, non-scrolling placeholder text.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/menu/menu_routes.dart';
import 'package:rukka_folio/features/menu/screens/s8_menu_screen.dart';
import 'package:rukka_folio/features/reports/reports_routes.dart';
import 'package:rukka_folio/shared/router.dart';

import '../../shared/test_app.dart';

void main() {
  // 07 §2 🔒 Menu bullet order, the row order S8 must render in.
  const expectedOrder = [
    'Reports',
    'Close the month',
    'Books & members',
    'Backup',
    'Devices & security',
    'Subscription',
    'Settings',
    'Help',
    'Legal',
  ];

  Widget buildScreen({
    VoidCallback? onOpenReports,
    VoidCallback? onOpenBackup,
    VoidCallback? onOpenDevices,
    VoidCallback? onOpenSettings,
  }) => MenuScreen(
    onOpenReports: onOpenReports ?? () {},
    onOpenBackup: onOpenBackup ?? () {},
    onOpenDevices: onOpenDevices ?? () {},
    onOpenSettings: onOpenSettings ?? () {},
  );

  group('S8 Menu (07 §2 row order)', () {
    testWidgets('F1-07-14 S8 Menu screen renders (07 §2)', (tester) async {
      await pumpRk(tester, buildScreen());

      expect(find.text('Menu'), findsWidgets);
    });

    testWidgets(
      'F1-07-14 renders every row from 07 §2 in order, Reports first, Legal last',
      (tester) async {
        await pumpRk(tester, buildScreen());

        final titles = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .toList();
        var cursor = -1;
        for (final title in expectedOrder) {
          final at = titles.indexOf(title);
          expect(at, greaterThan(-1), reason: 'missing row: $title');
          expect(at, greaterThan(cursor), reason: '$title out of 07 §2 order');
          cursor = at;
        }
      },
    );

    for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
      testWidgets(
        'F1-07-14 Menu title and rows resolve in ${locale.languageCode} without overflow at 200%',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: buildScreen(),
            ),
            locale: locale,
          );

          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'F1-07-77 a row with no destination yet is disabled-with-reason, never a silently inert tap (07 §1 rule 6)',
      (tester) async {
        await pumpRk(tester, buildScreen());

        // 5 disabled rows: Close the month, Books & members, Subscription,
        // Help, Legal (07 §2) — each pairs the clock icon with a reason.
        expect(find.byIcon(Icons.schedule), findsNWidgets(5));
      },
    );

    testWidgets(
      'F1-07-77 the 4 rows with a destination today (Reports, Backup, Devices & security, Settings) each reach their own callback, never the wrong one',
      (tester) async {
        var reports = 0, backup = 0, devices = 0, settings = 0;
        await pumpRk(
          tester,
          buildScreen(
            onOpenReports: () => reports++,
            onOpenBackup: () => backup++,
            onOpenDevices: () => devices++,
            onOpenSettings: () => settings++,
          ),
        );

        await tester.tap(find.text('Reports'));
        await tester.tap(find.text('Backup'));
        await tester.tap(find.text('Devices & security'));
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        expect(reports, 1);
        expect(backup, 1);
        expect(devices, 1);
        expect(settings, 1);
      },
    );

    test('F1-07-77 S8.1 Reports composes at /menu/reports, one level below the S8 root (13 §3.2 depth rule)', () {
      expect(MenuPaths.root, RkPaths.menu);
      expect(MenuPaths.reports, '${RkPaths.menu}/${ReportsPaths.root}');
      // `features/menu` composes the routes it imports from
      // `features/reports` as the tab root's own nested routes (rather
      // than a root-navigator route that would cover the tab bar), so
      // Reports stays inside the Menu tab.
      expect(menuRoot.routes, same(reportsRoutes));
    });
  });
}
