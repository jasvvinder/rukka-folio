// The design-capture harness itself (ADR 2026-10-05 §2, §3). If this goes red,
// every design-match pair is comparing the canvas with a broken picture.
//
// It captures a probe of its own under `HARNESS`, never a real S-id, so
// `design_match.py pair S1` never shows these pictures as S1's states.
@Tags(['F1'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/tokens.dart';
import 'package:rukka_folio/shared/widgets/rk_entitlement_banner.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import 'design_capture.dart';

const _sid = 'HARNESS';
const _wide = 'MMMMMMMM';
const _narrow = 'iiiiiiii';

/// A screen drawn the way the app draws: theme styles, an icon, a card.
class _Probe extends StatelessWidget {
  const _Probe({this.extra});

  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(RkSpace.s4),
          children: [
            Text(_wide, style: text.bodyLarge),
            Text(_narrow, style: text.bodyLarge),
            const Icon(Icons.home_outlined),
            const Card(
              child: ListTile(title: Text('Probe'), subtitle: Text('₹1,200')),
            ),
            // A band blended between two token colours: hundreds of distinct
            // pixel colours that do not depend on typography, so the
            // blank-capture guards (`distinctColours`) keep their margin when
            // a type token (tracking, size) changes — desk 193 (j) took the
            // text-only probe to exactly the threshold.
            const SizedBox(
              height: RkSpace.s12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [RkColorsLight.primary, RkColorsLight.accent],
                  ),
                ),
              ),
            ),
            ?extra,
          ],
        ),
      ),
    );
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets(
    'F1-1005-2 a capture is the screen laid out at the canvas size, at 2×, '
    'inside the safe area the frame draws',
    (tester) async {
      final shot = await rkDesignCapture(
        tester,
        sid: _sid,
        state: 'size',
        child: const _Probe(),
      );

      expect(shot.file.existsSync(), isTrue);
      // Laid out at 390×844 — not flutter_test's 800×600 — and the PNG is
      // that view, not a fixed rectangle.
      expect(shot.layoutSize, rkDesignCanvas);
      expect(shot.width, (shot.layoutSize.width * rkDesignPixelRatio).round());
      expect(
        shot.height,
        (shot.layoutSize.height * rkDesignPixelRatio).round(),
      );
      // The frame's 47 px status row and home indicator.
      expect(shot.safeArea, const EdgeInsets.only(top: 47, bottom: 34));
      expect(tester.getTopLeft(find.text(_wide)).dy, greaterThanOrEqualTo(47));
      // A blank or single-ground frame samples a handful of colours.
      expect(shot.distinctColours, greaterThan(10));
      await _unmount(tester);
    },
  );

  testWidgets('F1-1005-2 the captured screen draws in the real faces', (
    tester,
  ) async {
    await rkDesignCapture(
      tester,
      sid: _sid,
      state: 'faces',
      child: const _Probe(),
    );
    // Measured on the screen that was captured, not on a painter of our own:
    // in the FlutterTest font every glyph is one em wide, so a run of M and a
    // run of i would measure the same.
    // (Intrinsic width: in a list the paragraph's box is the row's width.)
    double width(String s) => tester
        .renderObject<RenderParagraph>(find.text(s))
        .getMaxIntrinsicWidth(double.infinity);
    final wide = width(_wide);
    final narrow = width(_narrow);
    expect(wide - narrow, greaterThan(40));
    await _unmount(tester);
  });

  testWidgets(
    'F1-1005-2 text outside the design faces fails the capture and names it',
    (tester) async {
      // The shape of a theme gap: an app-bar title style with no family.
      final gap = AppBar(
        title: const Text('Gap title'),
        titleTextStyle: RkType.section,
      );
      await expectLater(
        rkDesignCapture(
          tester,
          sid: _sid,
          state: 'unfaced',
          child: Scaffold(appBar: gap, body: const _Probe()),
        ),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('"Gap title"'), isNot(contains(_wide))),
          ),
        ),
      );
      // A face the screen asks of the phone on purpose is named, and passes.
      await rkDesignCapture(
        tester,
        sid: _sid,
        state: 'platform_face',
        platformFaces: const {'monospace'},
        child: const _Probe(
          extra: Text('a,b', style: TextStyle(fontFamily: 'monospace')),
        ),
      );
      await _unmount(tester);
    },
  );

  testWidgets(
    'F1-1005-3 a tab screen is captured in the production shell, above the '
    'tab bar',
    (tester) async {
      await rkDesignCapture(
        tester,
        sid: _sid,
        state: 'shell',
        tab: RkTab.ledger,
        child: const _Probe(),
      );

      expect(find.byType(RkShell), findsOneWidget);
      // S12.5 is global under every tab (router.dart RkShell).
      expect(find.byType(RkEntitlementBanner), findsOneWidget);
      final bar = find.byType(RkTabBar);
      expect(tester.widget<RkTabBar>(bar).selected, RkTab.ledger);
      // Above, not over: the screen ends where the bar begins, and the bar
      // runs to the bottom edge, over the home indicator.
      final barRect = tester.getRect(bar);
      expect(
        tester.getRect(find.byType(_Probe)).bottom,
        lessThanOrEqualTo(barRect.top + 0.5),
      );
      expect(barRect.bottom, rkDesignCanvas.height);
      expect(barRect.top, greaterThan(rkDesignCanvas.height / 2));
      await _unmount(tester);
    },
  );

  testWidgets(
    'F1-1005-4 each state is captured as iOS at 390×844 and Android at 360×800',
    (tester) async {
      final ios = await rkDesignCapture(
        tester,
        sid: _sid,
        state: 'target',
        tab: RkTab.home,
        child: const _Probe(),
      );
      final android = await rkDesignCapture(
        tester,
        sid: _sid,
        state: 'target',
        target: RkDesignTarget.android,
        tab: RkTab.home,
        child: const _Probe(),
      );

      // The theme was built for the platform asked for: a test runs as
      // Android by default, so an iOS capture that inherited it would say so.
      expect(ios.platform, TargetPlatform.iOS);
      expect(android.platform, TargetPlatform.android);
      expect(ios.layoutSize, const Size(390, 844));
      expect(android.layoutSize, const Size(360, 800));
      expect((ios.width, ios.height), (780, 1688));
      expect((android.width, android.height), (720, 1600));
      expect(android.safeArea, const EdgeInsets.only(top: 24, bottom: 48));
      expect(ios.file.path, endsWith('${_sid}__target.png'));
      expect(android.file.path, endsWith('${_sid}__target__android360.png'));
      expect(android.distinctColours, greaterThan(50));
      // The override never outlives the capture.
      expect(debugDefaultTargetPlatformOverride, isNull);
      await _unmount(tester);
    },
  );

  testWidgets('F1-1005-4 a failed capture still clears the platform override', (
    tester,
  ) async {
    await expectLater(
      rkDesignCapture(
        tester,
        sid: _sid,
        state: 'fails',
        target: RkDesignTarget.ios,
        child: const _Probe(
          extra: Text('boxed', style: TextStyle(fontFamily: 'NotLoaded')),
        ),
      ),
      throwsA(isA<TestFailure>()),
    );
    expect(debugDefaultTargetPlatformOverride, isNull);
    await _unmount(tester);
  });

  group('F1-1005-5 an approved capture is a golden, on macOS only', () {
    late Directory tmp;
    late GoldenFileComparator saved;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('rk_design_golden_');
      saved = goldenFileComparator;
      // Goldens resolve beside a test file in a scratch folder, so this test
      // never writes into the repo.
      goldenFileComparator = LocalFileComparator(
        Uri.file('${tmp.path}/probe_test.dart'),
      );
    });
    tearDown(() {
      goldenFileComparator = saved;
      autoUpdateGoldenFiles = false;
      rkDesignGoldensOverride = null;
      tmp.deleteSync(recursive: true);
    });

    testWidgets('F1-1005-5 drift from the approved golden fails the capture', (
      tester,
    ) async {
      rkDesignGoldensOverride = true;
      autoUpdateGoldenFiles = true;
      await rkDesignCapture(
        tester,
        sid: _sid,
        state: 'golden',
        golden: true,
        child: const _Probe(),
      );
      autoUpdateGoldenFiles = false;
      expect(
        File('${tmp.path}/goldens/${_sid}__golden.png').existsSync(),
        isTrue,
      );
      // Unchanged: holds.
      await rkDesignCapture(
        tester,
        sid: _sid,
        state: 'golden',
        golden: true,
        child: const _Probe(),
      );
      expect(tester.takeException(), isNull);
      // Drifted: fails. The comparator runs inside `runAsync`, which reports
      // its error to the test rather than through the returned future.
      await rkDesignCapture(
        tester,
        sid: _sid,
        state: 'golden',
        golden: true,
        child: const _Probe(extra: Text('drift')),
      );
      expect(
        tester.takeException().toString(),
        contains('Golden "goldens/${_sid}__golden.png": Pixel test failed'),
      );
      expect(debugDefaultTargetPlatformOverride, isNull);
      await _unmount(tester);
    });

    testWidgets(
      'F1-1005-5 off macOS the golden is skipped out loud and the capture runs',
      (tester) async {
        rkDesignGoldensOverride = false;
        final printed = <String>[];
        // No golden exists in the scratch folder: a comparison would fail.
        final shot = await runZoned(
          () => rkDesignCapture(
            tester,
            sid: _sid,
            state: 'golden_off',
            golden: true,
            child: const _Probe(),
          ),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => printed.add(line),
          ),
        );
        expect(shot.file.existsSync(), isTrue);
        expect(printed, [
          'design golden ${_sid}__golden_off skipped: macOS only '
              '(ADR 2026-10-05 §3)',
        ]);
        await _unmount(tester);
      },
    );
  });
}
