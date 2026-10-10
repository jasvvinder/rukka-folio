// RESKIN1 round 2, slice R2C — audit capture for Settings (ADR 2026-10-05 §2;
// ADR 2026-10-10b §1 phase 1 — an audit, not a build). Pair with
// `python3 scripts/design_match.py pair S13`.
//
// S13 — canvas 10 *Settings*.
//
// TEST HONESTY: the screen is built exactly as settings_routes.dart's builder
// builds it — every argument read from the `AppSettingsScope` production
// mounts above the router (main.dart, over `AppSettings`) — and pushed, as
// the root-navigator route `/settings` is from Menu, so the app bar carries
// its back button. English, light, the settings' own defaults.
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/settings/screens/s13_settings_screen.dart';
import 'package:rukka_folio/features/settings/settings_routes.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/prefs.dart';

import '../../shared/design_capture.dart';

/// settings_routes.dart's builder, verbatim in what it passes.
Widget _route(BuildContext context) {
  final settings = AppSettingsScope.maybeOf(context);
  return SettingsScreen(
    currentLocale: settings?.locale ?? Localizations.localeOf(context),
    onLanguageChanged: settings?.setLocale,
    appearance: settings?.appearance ?? ThemeMode.system,
    onAppearanceChanged: settings?.setAppearance,
    autoLockIdle: settings?.autoLockIdle ?? settingsDefaultAutoLockIdle,
    autoLockBackground:
        settings?.autoLockBackground ?? settingsDefaultAutoLockBackground,
    onOpenSubscription: () {},
  );
}

class _PushBase extends StatelessWidget {
  const _PushBase();

  static const door = Key('r2c-settings-push-door');

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: door,
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: _route)),
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

void main() {
  testWidgets('F1-1010r2C-16 design capture S13 settings', (tester) async {
    for (final target in RkDesignTarget.values) {
      final settings = AppSettings(prefs: MemoryPrefs());
      await rkDesignCapture(
        tester,
        sid: 'S13',
        state: 'default-pre',
        target: target,
        child: AppSettingsScope(settings: settings, child: const _PushBase()),
      );
      debugDefaultTargetPlatformOverride = target.platform;
      try {
        await tester.tap(find.byKey(_PushBase.door));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('Settings'), findsWidgets);
        await _snap(tester, 'S13__default${target.suffix}');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      final pre = File(
        '$rkDesignCaptureDir/S13__default-pre${target.suffix}.png',
      );
      if (pre.existsSync()) pre.deleteSync();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
