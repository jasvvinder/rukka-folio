@Tags(['F1'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/widgets/rk_banner.dart';
import 'package:rukka_folio/shared/widgets/rk_connection_notice.dart';
import 'package:rukka_folio/shared/widgets/rk_connection_notice_copy.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction_copy.dart';

import 'test_app.dart';

/// A host shaped like any screen that will mount the notice: the notice on
/// top, the screen's own work — including an export — underneath.
Widget _host(ValueListenable<bool> offline, {VoidCallback? onExport}) =>
    Scaffold(
      body: SingleChildScrollView(
        child: Builder(
          builder: (context) => Column(
            children: [
              RkConnectionNoticeSlot(
                offline: offline,
                copy: rkConnectionNoticeCopy(context),
                onRetry: () {},
              ),
              TextButton(
                onPressed: onExport,
                child: const Text('Export this book'),
              ),
            ],
          ),
        ),
      ),
    );

void main() {
  group('S19.3 No connection (13 §3.2 row S19.3, 07 §24, 13 §4.2)', () {
    testWidgets(
      'F1-07-85 the notice states the fact with an icon beside the words, on the one banner atom — colour is never alone (07 §1 rule 3)',
      (tester) async {
        final offline = ValueNotifier(true);
        addTearDown(offline.dispose);
        await pumpRk(tester, _host(offline));

        final copy = rkConnectionNoticeCopy(
          tester.element(find.byType(RkConnectionNotice)),
        );
        expect(find.text(copy.title), findsOneWidget);
        expect(find.text(copy.body), findsOneWidget);
        // The same atom the restriction family uses — one banner, not three.
        expect(
          find.descendant(
            of: find.byType(RkConnectionNotice),
            matching: find.byType(RkBannerSurface),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(RkConnectionNotice),
            matching: find.byType(Icon),
          ),
          findsOneWidget,
          reason: 'tint would be carrying the meaning alone',
        );
      },
    );

    testWidgets(
      'F1-07-85 it is non-blocking: no modal, no barrier, the screen underneath stays live and export still runs (13 §3.2 row S19.3, 07 §20 🔒)',
      (tester) async {
        var exports = 0;
        final offline = ValueNotifier(true);
        addTearDown(offline.dispose);
        await pumpRk(tester, _host(offline, onExport: () => exports++));

        // Nothing was pushed over the screen: the notice is part of the
        // page, not a route, a sheet or a dialog, and it traps nothing.
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        expect(navigator.canPop(), isFalse, reason: 'it pushed a route');
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(PopScope), findsNothing);
        expect(find.byType(RkConnectionNotice).hitTestable(), findsOneWidget);

        // And the screen's own work is untouched — export above all
        // (ADR 2026-09-05g §3: exports are never blocked).
        await tester.tap(find.text('Export this book'));
        await tester.pumpAndSettle();
        expect(exports, 1);
      },
    );

    testWidgets(
      'F1-07-85 the connection coming back removes it, and it occupies no space when online',
      (tester) async {
        final offline = ValueNotifier(false);
        addTearDown(offline.dispose);
        await pumpRk(tester, _host(offline));
        expect(find.byType(RkConnectionNotice), findsNothing);
        expect(tester.getSize(find.byType(RkConnectionNoticeSlot)).height, 0);

        offline.value = true;
        await tester.pumpAndSettle();
        expect(find.byType(RkConnectionNotice), findsOneWidget);

        offline.value = false;
        await tester.pumpAndSettle();
        expect(find.byType(RkConnectionNotice), findsNothing);
      },
    );

    testWidgets(
      'F1-07-85 it never borrows the entitlement offline-grace copy — two graces, two copies (13 §5 🔒, ADR 2026-09-05g §4)',
      (tester) async {
        final offline = ValueNotifier(true);
        addTearDown(offline.dispose);
        await pumpRk(tester, _host(offline));
        final context = tester.element(find.byType(RkConnectionNotice));
        final notice = rkConnectionNoticeCopy(context);
        final grace = RkRestrictionKind.offlineGrace.copy(context);
        final readOnly = RkRestrictionKind.readOnly.copy(context);

        for (final line in [notice.title, notice.body, notice.retryLabel]) {
          expect(
            line.toLowerCase(),
            isNot(anyOf(contains('lapse'), contains('plan'))),
            reason: 'S19.3 is the radio being off, not an entitlement state',
          );
        }
        // Genuinely different words from both entitlement copies.
        expect(notice.title, isNot(grace.bannerTitle));
        expect(notice.body, isNot(grace.bannerBody));
        expect(notice.title, isNot(readOnly.bannerTitle));
        expect(find.text(grace.bannerTitle), findsNothing);

        // And there is no way to route it through the blocking family at
        // all: the notice is not a RkRestrictionKind.
        expect(
          RkRestrictionKind.values.map((k) => k.name),
          isNot(contains('noConnection')),
        );
      },
    );

    testWidgets(
      'F1-07-85 the optional check reaches the host; the notice is never the only way on',
      (tester) async {
        var checks = 0;
        final offline = ValueNotifier(true);
        addTearDown(offline.dispose);
        await pumpRk(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => RkConnectionNotice(
                copy: rkConnectionNoticeCopy(context),
                onRetry: () => checks++,
              ),
            ),
          ),
        );
        final copy = rkConnectionNoticeCopy(
          tester.element(find.byType(RkConnectionNotice)),
        );
        await tester.tap(find.text(copy.retryLabel));
        await tester.pumpAndSettle();
        expect(checks, 1);

        // With no callback the notice is pure information and still renders.
        await pumpRk(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) =>
                  RkConnectionNotice(copy: rkConnectionNoticeCopy(context)),
            ),
          ),
        );
        expect(find.byType(TextButton), findsNothing);
        expect(find.text(copy.title), findsOneWidget);
      },
    );

    // 07 §18: 200 % OS font scale on the smallest supported screens, in every
    // script (ADR 2026-09-05f §G, §H15).
    for (final size in const [Size(375, 667), Size(360, 800)]) {
      for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
        testWidgets(
          'F1-07-85 the notice survives 200% text scale at ${size.width.toInt()}x${size.height.toInt()} in ${locale.languageCode}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final offline = ValueNotifier(true);
            addTearDown(offline.dispose);
            await pumpRk(
              tester,
              MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
                child: _host(offline),
              ),
              locale: locale,
            );
            expect(tester.takeException(), isNull);
            final copy = rkConnectionNoticeCopy(
              tester.element(find.byType(RkConnectionNotice)),
            );
            // The words resolve in this script — nothing falls back to EN.
            expect(find.text(copy.title), findsOneWidget);
            expect(find.text(copy.body), findsOneWidget);
          },
        );
      }
    }
  });
}
