// The F1 layout sweep the onboarding screen tests share (07 §1, 09 F1,
// design-system accessibility rules). Not a test file itself — it carries no
// `_test` suffix, so the runner only reaches it through an import.
//
// HARN2 review, findings 1 and 2: the four copies this replaces pumped once
// and looked only at scroll offset 0, so on a lazy [ListView] anything past
// viewport + cacheExtent was never built and could not fail; and they measured
// the FlutterTest square glyph, not Mukta or Mukta Mahee.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/tokens.dart';

import '../../shared/test_app.dart';

/// Registers the app's real faces under the families the theme names
/// ([RkType.family], [RkType.familyGurmukhi], [RkType.familyFallback]), so a
/// word is measured in the font a phone draws it in. Without this every
/// family resolves to the FlutterTest font, where each glyph is one em wide:
/// `iiii` and `MMMM` both measure 41 px at 10 px, against 10.8 and 33.4 px in
/// Mukta. Call it from `setUpAll`; each test file is its own isolate, so it
/// reaches no other file.
Future<void> loadRkFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await load(RkType.family, const [
    'Mukta-Regular.ttf',
    'Mukta-Medium.ttf',
    'Mukta-SemiBold.ttf',
  ]);
  await load(RkType.familyGurmukhi, const [
    'MuktaMahee-Regular.ttf',
    'MuktaMahee-Medium.ttf',
    'MuktaMahee-SemiBold.ttf',
  ]);
  await load(RkType.familyFallback, const ['NotoSans[wdth,wght].ttf']);

  // Proof the faces took: in the FlutterTest font every glyph is one em, so
  // a narrow and a wide run measure the same. A sweep that silently fell back
  // to it would be measuring squares again.
  double width(String family, String s) {
    final p = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: family, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = p.width;
    p.dispose();
    return w;
  }

  for (final (family, narrow, wide) in const [
    (RkType.family, 'iiii', 'MMMM'),
    (RkType.familyGurmukhi, 'ਿਿਿਿ', 'ਘਘਘਘ'),
  ]) {
    final n = width(family, narrow);
    final w = width(family, wide);
    if (w - n < 1) {
      throw StateError(
        '$family did not load: "$narrow" and "$wide" both measure '
        '${n.toStringAsFixed(1)} px — still the FlutterTest font',
      );
    }
  }
}

/// Fails on a thrown layout overflow or a silently cut word ([expectTextFits])
/// anywhere a reader can reach — at the top, and again at every half-viewport
/// step down each vertical [Scrollable] to its end. A lazy list builds only
/// what is within its viewport plus cache extent, so a check at offset 0 never
/// sees a row further down: it has no render object to overflow (test_app's
/// note on [rkTallViewport]; U3c, S8.1 rows 9–11).
Future<void> expectFitsWhileScrolling(
  WidgetTester tester, {
  required String reason,
}) async {
  void check(String where) {
    expect(tester.takeException(), isNull, reason: 'overflow: $reason $where');
    expectTextFits(tester, reason: '$reason $where');
  }

  check('at the top');
  final scrollables = tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where((s) => s.position.axis == Axis.vertical)
      .toList();
  for (final s in scrollables) {
    if (!s.mounted) continue;
    final pos = s.position;
    if (!pos.hasContentDimensions || pos.maxScrollExtent <= 0) continue;
    final step = math.max(1.0, pos.viewportDimension / 2);
    // maxScrollExtent is re-read each step: a lazy list's extent is an
    // estimate that grows as rows are built.
    for (var guard = 0; guard < 400; guard++) {
      if (pos.pixels >= pos.maxScrollExtent) break;
      pos.jumpTo(math.min(pos.pixels + step, pos.maxScrollExtent));
      await tester.pump();
      check(
        'scrolled to ${pos.pixels.toStringAsFixed(0)} of '
        '${pos.maxScrollExtent.toStringAsFixed(0)}',
      );
    }
    if (s.mounted) {
      pos.jumpTo(0);
      await tester.pump();
    }
  }
}

/// Pumps [build] on both F1 phones at 1.3x and 2x text scale in EN, PA and
/// HI and fails on any overflow or cut word, scrolled through end to end
/// ([expectFitsWhileScrolling]). Load the real faces first ([loadRkFonts]).
///
/// The scale goes to [pumpRk], never to a `MediaQuery(data: MediaQueryData(
/// textScaler: …))` wrapper: a fresh `MediaQueryData` carries `Size.zero`,
/// so the screen under such a wrapper had no area at all and nothing it did
/// could overflow. 1.3x matters as much as 2x — at 200 % a bar has usually
/// dropped its words for icons, so 1.3x is where a label is still drawn and
/// is widest.
Future<void> expectNoOverflowInEveryLocale(
  WidgetTester tester,
  Widget Function() build,
) async {
  for (final locale in rkLocales) {
    for (final vp in rkPhones) {
      for (final scale in rkTextScales) {
        await pumpRk(
          tester,
          build(),
          locale: locale,
          textScale: scale,
          viewport: vp,
        );
        await expectFitsWhileScrolling(
          tester,
          reason:
              '${locale.languageCode} @ $scale on '
              '${vp.width.toInt()}x${vp.height.toInt()}',
        );
      }
    }
  }
}
