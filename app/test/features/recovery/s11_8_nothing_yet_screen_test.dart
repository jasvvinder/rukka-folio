@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/recovery/screens/s11_8_nothing_yet_screen.dart';
import 'package:rukka_folio/features/recovery/widgets/recovery_parts.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

void main() {
  group('S11.8 Recovery — nothing worked yet (13 §3.2, design R2.5 🔒)', () {
    testWidgets(
      'F1-07-284 the heading is the pack\'s, word for word, and the screen is '
      'the three bordered rows in green / amber / grey — each carrying an '
      'icon and a status word beside its tint, because colour is never alone '
      '(07 §1 rule 3 🔒)',
      (tester) async {
        await pumpRk(
          tester,
          const NothingWorkedYetScreen(),
          viewport: rkTallViewport,
        );
        expect(
          find.text('We can’t open your private book on this phone yet.'),
          findsOneWidget,
        );

        final cards = tester
            .widgetList<RecoveryStatusCard>(find.byType(RecoveryStatusCard))
            .toList();
        expect(cards, hasLength(3));
        final status = RkStatusColors.light;
        expect(cards.map((c) => c.tone), [
          status.success,
          status.pending,
          status.muted,
        ]);
        // Every tone is carried by a word and an icon as well.
        expect(cards.map((c) => c.status), [
          'Ready to restore',
          'Still sealed',
          'If you kept one',
        ]);
        expect(find.text('Your family and business books'), findsOneWidget);
        expect(find.text('Your private book'), findsOneWidget);
        expect(find.text('A readable copy of your books'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-285 the private book is sealed, not lost: the row states it is '
      'still on the server exactly as it was left, and names both keys as '
      'things that will still work today, next week or next year (design '
      'R2.5 🔒, 04 §7.6 🔒)',
      (tester) async {
        await pumpRk(
          tester,
          const NothingWorkedYetScreen(),
          viewport: rkTallViewport,
        );
        expect(
          find.text(
            'It is still sealed on our server, exactly as you left it.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Two things will open it — today, next week or next year:'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Signing in to the Apple or Google account that held your key.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Finding your recovery sheet — the paper one, or the file you '
            'saved.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Your books are in that file, and you can start fresh books from '
            'those closing balances.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-07-286 the words the pack 🔒 forbids are absent — no "destroyed", '
      'no "lost", no "contact support", no retry — and the word the whole '
      'screen is built around is present',
      (tester) async {
        await pumpRk(
          tester,
          const NothingWorkedYetScreen(),
          viewport: rkTallViewport,
        );
        final all = _texts(tester).join(' ').toLowerCase();
        for (final banned in const [
          'destroyed',
          'lost',
          'gone',
          'contact support',
          'try again',
          'retry',
        ]) {
          expect(all.contains(banned), isFalse, reason: banned);
        }
        expect(all.contains('yet'), isTrue);
      },
    );

    testWidgets(
      'F1-07-287 one primary button and no second: "Continue and set up this '
      'phone", carried by the green row, reaching the caller (design R2.5 🔒)',
      (tester) async {
        var went = 0;
        await pumpRk(
          tester,
          NothingWorkedYetScreen(onContinue: () => went++),
          viewport: rkTallViewport,
        );
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.text('Continue and set up this phone'), findsOneWidget);

        // It belongs to the green row, not to the page foot.
        final card = tester.widget<RecoveryStatusCard>(
          find.ancestor(
            of: find.byType(FilledButton),
            matching: find.byType(RecoveryStatusCard),
          ),
        );
        expect(card.status, 'Ready to restore');

        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        expect(went, 1);
      },
    );

    testWidgets(
      'F1-07-288 no key material is ever rendered (04 §7.4, 07 §5.6 🔒): the '
      'screen names the two keys as things to do, never as bytes to read',
      (tester) async {
        await pumpRk(
          tester,
          const NothingWorkedYetScreen(),
          viewport: rkTallViewport,
        );
        final keyish = RegExp(r'^[0-9A-Za-z]{16,}$');
        for (final s in _texts(tester)) {
          for (final word in s.split(RegExp(r'\s+'))) {
            expect(keyish.hasMatch(word), isFalse, reason: s);
          }
        }
      },
    );

    testWidgets(
      'F1-07-289 the screen holds at 200 % text on 360×800 and 375×667 in all '
      'three languages, with no overflow and no silently cut word',
      (tester) async {
        for (final locale in rkLocales) {
          for (final size in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                const NothingWorkedYetScreen(),
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
      },
    );
  });
}
