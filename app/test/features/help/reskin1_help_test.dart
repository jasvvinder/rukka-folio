// RESKIN1 round 2, slice R2C — audit captures for Help (ADR 2026-10-05 §2;
// ADR 2026-10-10b §1 phase 1 — an audit, not a build). Pair with
// `python3 scripts/design_match.py pair <S-id>`.
//
// S17   — canvas 10 *Help* (S17.1 is folded into S17, ADR 2026-09-02).
// S17.2 — canvas 10 *An article · iPhone* / *An article · Android*: the iOS
//         capture pairs with the first, the 360-wide Android capture with the
//         second. The article is `new_phone`, the one the frame draws.
// S17.3 — canvas 10 *Contact support*.
// S17.4 — canvas 10 *Send diagnostics*.
//
// TEST HONESTY: every screen is built with the constructor arguments
// help_routes.dart passes (`HelpScreen(onOpenArticle:, onOpenContact:,
// onOpenDiagnostics:)`, `FaqArticleScreen(id:, onBackToHub:,
// onOpenContact:)`, `ContactSupportScreen(mailer: const
// UrlLauncherSupportMailer(), onOpenDiagnostics:, onOpenArticle:)`, `const
// SendDiagnosticsScreen()`), pushed as the root-navigator `/help…` routes
// are, so each app bar carries its back button. S17.4 runs with the device
// facts production has today — none (`device: null`).
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/help/help_routes.dart';

import '../../shared/design_capture.dart';

class _PushBase extends StatelessWidget {
  const _PushBase({required this.child});

  static const door = Key('r2c-help-push-door');

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: door,
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => child)),
        child: const SizedBox.square(dimension: 48),
      ),
    ),
  );
}

Future<void> _snap(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  // The face check of rkDesignCapture (ADR 2026-10-05 §2 🔒), run on the
  // frame this PNG is written from, not on the deleted '-pre' frame.
  final unfaced = rkUnfacedText(view, allowed: rkDesignFaces);
  if (unfaced.isNotEmpty) {
    fail(
      'design capture $name draws text outside the design faces '
      "(ADR 2026-10-05 §2):\n${unfaced.join('\n')}",
    );
  }
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: rkDesignPixelRatio,
    );
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File('$rkDesignCaptureDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _shoot(
  WidgetTester tester, {
  required String sid,
  required Widget screen,
  required Type type,
}) async {
  for (final target in RkDesignTarget.values) {
    await rkDesignCapture(
      tester,
      sid: sid,
      state: 'default-pre',
      target: target,
      child: _PushBase(child: screen),
    );
    debugDefaultTargetPlatformOverride = target.platform;
    try {
      await tester.tap(find.byKey(_PushBase.door));
      await _settle(tester);
      expect(find.byType(type), findsOneWidget);
      await _snap(tester, '${sid}__default${target.suffix}');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    final pre = File(
      '$rkDesignCaptureDir/${sid}__default-pre${target.suffix}.png',
    );
    if (pre.existsSync()) pre.deleteSync();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('F1-1010r2C-17 design capture S17 help hub', (tester) async {
    await _shoot(
      tester,
      sid: 'S17',
      type: HelpScreen,
      screen: HelpScreen(
        onOpenArticle: (_) {},
        onOpenContact: () {},
        onOpenDiagnostics: () {},
      ),
    );
  });

  testWidgets('F1-1010r2C-18 design capture S17.2 an article (new phone)', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S17.2',
      type: FaqArticleScreen,
      screen: FaqArticleScreen(
        id: 'new_phone',
        onBackToHub: () {},
        onOpenContact: () {},
      ),
    );
  });

  testWidgets('F1-1010r2C-19 design capture S17.3 contact support', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S17.3',
      type: ContactSupportScreen,
      screen: ContactSupportScreen(
        mailer: const UrlLauncherSupportMailer(),
        onOpenDiagnostics: () {},
        onOpenArticle: (_) {},
      ),
    );
  });

  testWidgets('F1-1010r2C-20 design capture S17.4 send diagnostics', (
    tester,
  ) async {
    await _shoot(
      tester,
      sid: 'S17.4',
      type: SendDiagnosticsScreen,
      screen: const SendDiagnosticsScreen(),
    );
  });
}
