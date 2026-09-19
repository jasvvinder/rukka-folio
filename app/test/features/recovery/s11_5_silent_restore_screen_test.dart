@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/recovery/screens/s11_5_silent_restore_screen.dart';
import 'package:rukka_folio/features/recovery/widgets/recovery_parts.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/tokens.dart';

import '../../shared/test_app.dart';

/// Rung 0 part-way through, and still running.
FakeRecoveryLadder _running() => FakeRecoveryLadder(
  keepRunning: true,
  progress: {
    RecoveryRung.platformKeySync: const [
      RecoveryProgress(done: 1, total: 3, unit: RecoveryUnit.books),
    ],
  },
);

/// Rung 0 finished: three books came back.
FakeRecoveryLadder _finished() => FakeRecoveryLadder(
  progress: {
    RecoveryRung.platformKeySync: const [
      RecoveryProgress(done: 1, total: 3, unit: RecoveryUnit.books),
      RecoveryProgress(
        done: 3,
        total: 3,
        unit: RecoveryUnit.books,
        finished: true,
      ),
    ],
  },
);

/// Every string drawn in the tree right now.
List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

void main() {
  group('S11.5 Recovery — silent restore (13 §3.2, design R2.0, 04 §7.0)', () {
    testWidgets(
      'F1-07-279 while the count runs it is the determinate loader rule and '
      'nothing else — a 2 px loader-track with a loader-segment, a value that '
      'is never null, a count rather than a percentage, and no spinner '
      'anywhere (11 §4.5 🔒, DESIGN-PACK loader-rule paragraph)',
      (tester) async {
        await pumpRk(
          tester,
          SilentRestoreScreen(ladder: _running()),
          viewport: rkPhone360,
        );
        expect(find.text('Getting your books back'), findsOneWidget);
        expect(find.text('1 of 3 books restored'), findsOneWidget);

        expect(find.byType(CircularProgressIndicator), findsNothing);
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, isNotNull);
        expect(bar.value, closeTo(1 / 3, 0.001));
        expect(bar.minHeight, RkMotion.loaderTrackHeight);
        final status = RkStatusColors.light;
        expect(bar.backgroundColor, status.loaderTrack);
        expect(bar.color, status.loaderSegment);
        for (final s in _texts(tester)) {
          expect(s.contains('%'), isFalse, reason: s);
        }
      },
    );

    testWidgets(
      'F1-07-280 the common case ends in a tick, "Your books are back", the '
      'number of books restored and one way on to Home — no choices and no '
      'cryptography (design R2.0)',
      (tester) async {
        var home = 0;
        await pumpRk(
          tester,
          SilentRestoreScreen(ladder: _finished(), onDone: () => home++),
          viewport: rkPhone360,
        );
        expect(find.text('Your books are back'), findsOneWidget);
        expect(find.text('3 books restored'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

        // One button, so there is nothing to choose between.
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(RecoveryLoaderRule), findsNothing);
        await tester.tap(find.text('Go to my books'));
        await tester.pump();
        expect(home, 1);

        // No cryptography reaches the reader.
        for (final s in _texts(tester).map((s) => s.toLowerCase())) {
          for (final word in const ['key', 'encrypt', 'decrypt', 'keychain']) {
            expect(s.contains(word), isFalse, reason: s);
          }
        }
      },
    );

    testWidgets(
      'F1-07-281 when the key store had nothing the screen says so plainly '
      'and hands the person the ladder — never a dead end, never an alarm '
      '(07 §1 rule 6, 04 §7.0 limits)',
      (tester) async {
        var forked = 0;
        await pumpRk(
          tester,
          SilentRestoreScreen(
            ladder: FakeRecoveryLadder(),
            onNeedsFork: () => forked++,
          ),
          viewport: rkPhone360,
        );
        expect(
          find.text('This phone’s key store had nothing for us.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Get your books back another way'));
        await tester.pump();
        expect(forked, 1);
      },
    );

    testWidgets(
      'F1-07-282 no key material is ever rendered (04 §7.4, 07 §5.6 🔒): every '
      'string on the screen is localised copy or a count, and none of them is '
      'long enough or random enough to be a key',
      (tester) async {
        for (final ladder in [_running(), _finished()]) {
          await pumpRk(
            tester,
            SilentRestoreScreen(ladder: ladder),
            viewport: rkPhone360,
          );
          // A key would reach a screen as one unbroken token — Crockford
          // Base32 or hex, 16 characters or more. Ordinary copy has no such
          // word in any of the three scripts.
          final keyish = RegExp(r'^[0-9A-Za-z]{16,}\$');
          for (final s in _texts(tester)) {
            for (final word in s.split(RegExp(r'\s+'))) {
              expect(keyish.hasMatch(word), isFalse, reason: s);
            }
          }
        }
      },
    );

    testWidgets(
      'F1-07-283 both states hold at 200 % text on 360×800 and 375×667 in all '
      'three languages, with no overflow and no silently cut word',
      (tester) async {
        for (final locale in rkLocales) {
          for (final size in rkPhones) {
            for (final scale in rkTextScales) {
              for (final ladder in [_running(), _finished()]) {
                await pumpRk(
                  tester,
                  SilentRestoreScreen(ladder: ladder),
                  locale: locale,
                  textScale: scale,
                  viewport: size,
                );
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$locale $size ×$scale',
                );
                expectTextFits(tester, reason: '$locale $size ×$scale');
              }
            }
          }
        }
      },
    );
  });
}
