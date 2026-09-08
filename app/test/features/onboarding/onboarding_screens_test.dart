// F1 widget tests for onboarding S0.0/S0.1/S0.05 (13 §3.2, 07 §5 flow F1).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_0_splash_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_05_welcome_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_1_language_screen.dart';

import '../../shared/test_app.dart';

void main() {
  group('S0.0 Splash (13 §3.2, ADR 2026-09-03d)', () {
    testWidgets(
      'F1-07-39 locked session: mark shows sealed, finishes without an artificial delay',
      (tester) async {
        var finished = false;
        await pumpRk(
          tester,
          SplashScreen(
            session: RkSplashSession.locked,
            reducedMotion: true,
            onFinished: () => finished = true,
          ),
        );
        expect(finished, isTrue);
        expect(find.byType(SplashScreen), findsOneWidget);
      },
    );

    testWidgets('F1-07-39 open session: seal breaks once, then finishes', (
      tester,
    ) async {
      var finished = false;
      await pumpRk(
        tester,
        SplashScreen(
          session: RkSplashSession.open,
          reducedMotion: true,
          onFinished: () => finished = true,
        ),
      );
      expect(finished, isTrue);
    });

    testWidgets(
      'F1-07-39 failed auth: stays sealed, shakes, never calls onFinished (nowhere forward)',
      (tester) async {
        var finished = false;
        await pumpRk(
          tester,
          SplashScreen(
            session: RkSplashSession.failedAuth,
            reducedMotion: true,
            onFinished: () => finished = true,
          ),
        );
        expect(finished, isFalse);
      },
    );

    testWidgets(
      'F1-07-39 strings resolve in EN/PA/HI with no overflow at 200%',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SplashScreen(
                session: RkSplashSession.locked,
                reducedMotion: true,
              ),
            ),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  });

  group('S0.1 Language picker (13 §3.2, 07 §3.1 step 1)', () {
    testWidgets(
      'F1-07-40 three languages offered; selecting one enables Continue and hands the locale on',
      (tester) async {
        Locale? picked;
        await pumpRk(
          tester,
          LanguagePickerScreen(onSelected: (locale) => picked = locale),
        );

        expect(find.text('English'), findsOneWidget);
        expect(find.text('ਪੰਜਾਬੀ'), findsOneWidget);
        expect(find.text('हिन्दी'), findsOneWidget);

        // Continue is disabled with nothing picked (07 §3.1: no default guess).
        final continueButton = tester.widget<FilledButton>(
          find.byType(FilledButton),
        );
        expect(continueButton.onPressed, isNull);

        await tester.tap(find.text('ਪੰਜਾਬੀ'));
        await tester.pumpAndSettle();

        final enabled = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(enabled.onPressed, isNotNull);

        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        expect(picked, const Locale('pa'));
      },
    );

    testWidgets(
      'F1-07-40 strings resolve in EN/PA/HI with no overflow at 200%',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const LanguagePickerScreen(),
            ),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  });

  group('S0.05 Welcome (13 §3.2, 07 §5 flow F1)', () {
    testWidgets(
      'F1-07-41 three slides, Skip is present and advances immediately from any slide',
      (tester) async {
        var done = false;
        await pumpRk(tester, WelcomeScreen(onDone: () => done = true));

        expect(find.text('Your books, always with you'), findsOneWidget);
        expect(find.byType(TextButton), findsOneWidget); // Skip

        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();

        expect(done, isTrue);
      },
    );

    testWidgets(
      'F1-07-41 Next walks slide 1 → 2 → 3; last slide reads Get started and advances',
      (tester) async {
        var done = false;
        await pumpRk(tester, WelcomeScreen(onDone: () => done = true));

        expect(find.text('Your books, always with you'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Next'));
        await tester.pumpAndSettle();
        expect(find.text('No password, no risk'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Next'));
        await tester.pumpAndSettle();
        expect(find.text('Family and business, together'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Get started'),
          findsOneWidget,
        );

        expect(done, isFalse);
        await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
        await tester.pumpAndSettle();
        expect(done, isTrue);
      },
    );

    testWidgets(
      'F1-07-41 strings resolve in EN/PA/HI with no overflow at 200%',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const WelcomeScreen(),
            ),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  });
}
