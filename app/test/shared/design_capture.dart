// The app side of the design-match step (ADR 2026-10-05 §2, §3): pump a screen at
// the design canvas size with the faces a phone draws, write the frame as a PNG
// beside the canvas render, and, once the owner has approved the pair, hold it
// as a golden.
//
// A design test lives in app/test/features/<feature>/<screen>_design_test.dart and calls [rkDesignCapture]
// once per state the canvas draws. Then:
//   python3 scripts/design_match.py pair <S-id>
// lays the canvas frames beside these captures in build/design_match/pairs/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/tokens.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import 'test_app.dart';

/// The design canvas (13 §10 decision 9): every frame is drawn at 390×844.
const rkDesignCanvas = Size(390, 844);

/// Which phone a capture stands for (ADR 2026-10-05 §2 step 2).
///
/// A Flutter test runs as Android unless told otherwise
/// (`foundation/_platform_io.dart`: `FLUTTER_TEST` → `TargetPlatform.android`),
/// so the platform is always set explicitly here, never inherited.
enum RkDesignTarget {
  /// iOS at the canvas size. This is the render matched against the canvas
  /// frame (iOS ships first, 10 🔒). Every frame draws a 47 px status row and
  /// a home indicator inside its 390×844, as an iPhone at that size does
  /// (top 47, bottom 34), so the screen gets that safe area too.
  ios(
    TargetPlatform.iOS,
    rkDesignCanvas,
    '',
    EdgeInsets.only(top: 47, bottom: 34),
  ),

  /// Android at its floor, 360×800 (13 §10 decision 9). Reviewed for reflow
  /// and Android's platform defaults; it is not expected to match the
  /// 390-wide frame pixel for pixel. The insets are AOSP's defaults (24 dp
  /// status bar, 48 dp three-button navigation bar); not yet measured on the
  /// `rf_min` emulator.
  android(
    TargetPlatform.android,
    Size(360, 800),
    '__android360',
    EdgeInsets.only(top: 24, bottom: 48),
  );

  const RkDesignTarget(this.platform, this.size, this.suffix, this.safeArea);

  final TargetPlatform platform;
  final Size size;

  /// Appended to the capture name, so `pair` shows both side by side.
  final String suffix;

  /// The system bars the phone draws over the screen (logical pixels).
  final EdgeInsets safeArea;
}

/// Captures are written at 2× so a reviewer can read 11.5 px captions.
const rkDesignPixelRatio = 2.0;

/// Where captures land, relative to `app/` (the working directory of
/// `flutter test`). `scripts/design_match.py pair` reads them from here.
const rkDesignCaptureDir = 'build/design_match/app';

/// The faces [rkLoadDesignFonts] registers. Text in any other family is drawn
/// in the FlutterTest font's solid boxes here, and in the phone's system face
/// on a device: either way not the design's face.
const rkDesignFaces = {
  RkType.family,
  RkType.familyGurmukhi,
  RkType.familyFallback,
  'MaterialIcons',
};

/// Set by the harness's own test to exercise both branches of ruling 3.
@visibleForTesting
bool? rkDesignGoldensOverride;

/// Goldens are compared on macOS only: Flutter rasterises text differently on
/// Linux, and CI runs on ubuntu-latest (ADR 2026-10-05 §3).
bool get rkDesignGoldensEnabled => rkDesignGoldensOverride ?? Platform.isMacOS;

bool _fontsLoaded = false;

/// Registers Mukta, Mukta Mahee, Noto Sans and the Material icon font under the
/// families the theme names. Without it every glyph is the FlutterTest square
/// and every icon is a box, and a capture is useless for comparison. Each test
/// file is its own isolate, so this reaches no other test's measurements.
Future<void> rkLoadDesignFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    Future<void> load(String family, List<String> assets) async {
      final loader = FontLoader(family);
      for (final a in assets) {
        loader.addFont(rootBundle.load(a));
      }
      await loader.load();
    }

    await load(RkType.family, const [
      'assets/fonts/Mukta-Regular.ttf',
      'assets/fonts/Mukta-Medium.ttf',
      'assets/fonts/Mukta-SemiBold.ttf',
    ]);
    await load(RkType.familyGurmukhi, const [
      'assets/fonts/MuktaMahee-Regular.ttf',
      'assets/fonts/MuktaMahee-Medium.ttf',
      'assets/fonts/MuktaMahee-SemiBold.ttf',
    ]);
    await load(RkType.familyFallback, const [
      'assets/fonts/NotoSans[wdth,wght].ttf',
    ]);
    await load('MaterialIcons', const ['fonts/MaterialIcons-Regular.otf']);
  });
  _fontsLoaded = true;
}

/// What [rkDesignCapture] wrote.
class RkDesignCapture {
  RkDesignCapture({
    required this.file,
    required this.width,
    required this.height,
    required this.distinctColours,
    required this.platform,
    required this.layoutSize,
    required this.safeArea,
  });

  /// The platform the theme was built for when the frame was drawn.
  final TargetPlatform platform;

  /// The PNG on disk.
  final File file;

  /// Pixel size of the PNG: the view the screen was laid out in ×
  /// [rkDesignPixelRatio].
  final int width;
  final int height;

  /// The size the screen was laid out at (logical pixels).
  final Size layoutSize;

  /// The safe area the screen saw (`MediaQuery.paddingOf`).
  final EdgeInsets safeArea;

  /// Distinct colours in a sample of the frame. A blank or single-colour
  /// capture means the screen did not draw.
  final int distinctColours;
}

/// Pumps [child] as [target] (iOS at 390×844 by default, or Android at
/// 360×800) with the real faces and the phone's safe area, writes
/// `build/design_match/app/<sid>__<state>[__android360].png`, and, when
/// [golden] is set and goldens are enabled here, holds it against the same
/// name under `goldens/` beside the calling test.
///
/// Capture every state twice: once per [RkDesignTarget].
///
/// The capture **fails** when any drawn text is in a family outside
/// [rkDesignFaces]: that text is a box in the PNG, so the pair would compare
/// the canvas with a picture that is not the screen. A family a screen draws
/// in the phone's own face on purpose (`'monospace'` for a raw-file preview)
/// is named in [platformFaces].
///
/// [tab] mounts the screen as that tab's root inside the production shell
/// ([RkShell] via [buildRouter]: content above [RkTabBar], with the global
/// S12.5 banner slot), because every tab screen's canvas frame draws the tab
/// bar. Leave it null for a screen that sits above the shell (S2, onboarding,
/// sheets pushed on the root navigator).
///
/// Set [golden] only once `design/match/<sid>.json` says `match` and the owner
/// has seen the pair (ADR 2026-10-05 §3).
Future<RkDesignCapture> rkDesignCapture(
  WidgetTester tester, {
  required String sid,
  required Widget child,
  String state = 'default',
  RkDesignTarget target = RkDesignTarget.ios,
  RkTab? tab,
  LocalLedger? ledger,
  Locale? locale,
  Brightness brightness = Brightness.light,
  Set<String> platformFaces = const {},
  bool golden = false,
}) async {
  await rkLoadDesignFonts(tester);
  // The DEBUG ribbon is not part of any screen; the canvas has none.
  final banner = WidgetsApp.debugAllowBannerOverride;
  WidgetsApp.debugAllowBannerOverride = false;
  addTearDown(() => WidgetsApp.debugAllowBannerOverride = banner);
  // `rkViewport` (inside pumpRk) sets a ratio of 1, so physical == logical.
  final inset = target.safeArea;
  final pad = FakeViewPadding(top: inset.top, bottom: inset.bottom);
  tester.view
    ..padding = pad
    ..viewPadding = pad;
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final name = '${sid}__$state${target.suffix}';
  final boundary = GlobalKey(debugLabel: name);
  Widget screen = child;
  if (tab != null) {
    final router = buildRouter(
      featureRoutes: const [],
      initialLocation: RkPaths.of(tab),
      home: tab == RkTab.home ? RkTabRoot(builder: (_) => child) : null,
      ledger: tab == RkTab.ledger ? RkTabRoot(builder: (_) => child) : null,
      inbox: tab == RkTab.inbox ? RkTabRoot(builder: (_) => child) : null,
      menu: tab == RkTab.menu ? RkTabRoot(builder: (_) => child) : null,
    );
    addTearDown(router.dispose);
    screen = Router.withConfig(config: router);
  }

  // flutter_test fails a test that ends with the override still set, and a
  // throw below must not hand it to the next test in the file.
  debugDefaultTargetPlatformOverride = target.platform;
  try {
    await pumpRk(
      tester,
      RepaintBoundary(key: boundary, child: screen),
      ledger: ledger,
      locale: locale,
      brightness: brightness,
      viewport: target.size,
    );
    final at = tester.element(find.byKey(boundary));
    final drawnAs = Theme.of(at).platform;
    final safeArea = MediaQuery.paddingOf(at);
    final layoutSize = tester.getSize(find.byKey(boundary));

    // The root view's layer, not the screen's boundary, so a sheet or dialog
    // on the root navigator's overlay is in the picture too. Its bounds are
    // the view the tree was laid out in, never a constant.
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final out = await tester.runAsync(() async {
      final image = await layer.toImage(
        Offset.zero & view.size,
        pixelRatio: rkDesignPixelRatio,
      );
      final rgba = (await image.toByteData())!;
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final colours = <int>{};
      for (var i = 0; i < rgba.lengthInBytes; i += 4 * 97) {
        colours.add(rgba.getUint32(i));
      }
      final file = File('$rkDesignCaptureDir/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png.buffer.asUint8List());
      final result = RkDesignCapture(
        file: file,
        width: image.width,
        height: image.height,
        distinctColours: colours.length,
        platform: drawnAs,
        layoutSize: layoutSize,
        safeArea: safeArea,
      );
      image.dispose();
      return result;
    });

    final unfaced = rkUnfacedText(
      view,
      allowed: {...rkDesignFaces, ...platformFaces},
    );
    if (unfaced.isNotEmpty) {
      fail(
        'design capture $name draws text outside the design faces '
        '(ADR 2026-10-05 §2) — in the PNG it is a solid box, on a phone the '
        "system face, so the pair cannot be read:\n${unfaced.join('\n')}",
      );
    }

    if (golden) {
      if (rkDesignGoldensEnabled) {
        await expectLater(
          find.byKey(boundary),
          matchesGoldenFile('goldens/$name.png'),
        );
      } else {
        // ignore: avoid_print — the skip must be visible in the gate log
        print('design golden $name skipped: macOS only (ADR 2026-10-05 §3)');
      }
    }
    return out!;
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Every run of drawn text under [root] whose family is not in [allowed], as
/// `"text" in <family>`. Offstage subtrees are skipped: they paint nothing.
List<String> rkUnfacedText(RenderObject root, {required Set<String> allowed}) {
  final out = <String>[];
  void span(InlineSpan s, String? inherited) {
    final style = s.style;
    final family = style == null
        ? inherited
        : style.fontFamily ?? (style.inherit ? inherited : null);
    if (s is TextSpan) {
      final t = s.text?.trim() ?? '';
      if (t.isNotEmpty && !allowed.contains(family)) {
        out.add('  "$t" in ${family ?? 'no family (theme gap)'}');
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        span(c, family);
      }
    }
  }

  void visit(RenderObject o) {
    if (o is RenderOffstage && o.offstage) return;
    if (o is RenderParagraph) span(o.text, null);
    if (o is RenderEditable) {
      final t = o.text;
      if (t != null) span(t, null);
    }
    o.visitChildren(visit);
  }

  visit(root);
  return out;
}
