// F1-13-20…26: the design-system atoms of 13 §4 and the two component states
// of 13 §4.3, pumped on their own rather than through a screen.
//
// Three lanes shipped copies of these widgets because no lane owned
// `shared/widgets`. These are the tests for the one definition: they hold the
// behaviour the copies were each re-deriving — a word never drawn past its
// box, a skeleton that announces itself, an error that is never a dead end —
// at 100 % and 200 % on the 360×800 phone, in EN, PA and HI.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/widgets/rk_fit_text.dart';
import 'package:rukka_folio/shared/widgets/rk_ruled_card.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../test_app.dart';

/// The longest unbreakable words the three languages give us. Gurmukhi and
/// Devanagari compounds have no break opportunity at all, which is exactly
/// the case a plain `Text` draws past its edge.
const _words = {
  'en': 'Uncategorised',
  'pa': 'ਪ੍ਰਵਿਸ਼ਟੀਆਂ',
  'hi': 'प्रविष्टियाँ',
};

void main() {
  group('RkFitText (13 §4, 07 §1 rule 11)', () {
    testWidgets(
      'F1-13-20 no word is drawn past its box, in EN/PA/HI at 100 % and '
      '200 % on 360×800',
      (tester) async {
        for (final locale in rkLocales) {
          for (final scale in [1.0, 2.0]) {
            await pumpRk(
              tester,
              Scaffold(
                body: Center(
                  // A box far narrower than the word: the squeeze that made a
                  // plain Text spill without throwing.
                  child: SizedBox(
                    width: 80,
                    child: RkFitText(_words[locale.languageCode]!),
                  ),
                ),
              ),
              locale: locale,
              textScale: scale,
              viewport: rkPhone360,
            );
            expect(tester.takeException(), isNull);
            expectTextFits(
              tester,
              reason: '${locale.languageCode} at ${scale}x',
            );
          }
        }
      },
    );

    testWidgets(
      'F1-13-21 text that already fits is drawn at exactly the scale the '
      'reader asked for',
      (tester) async {
        await pumpRk(
          tester,
          const Scaffold(body: SizedBox(width: 320, child: RkFitText('x'))),
          textScale: 2,
          viewport: rkPhone360,
        );
        final text = tester.widget<Text>(find.text('x'));
        expect(text.textScaler, TextScaler.linear(2));
      },
    );

    testWidgets(
      'F1-13-22 a word wider than its box is stepped down, never cut',
      (tester) async {
        await pumpRk(
          tester,
          const Scaffold(
            body: SizedBox(width: 40, child: RkFitText('Uncategorised')),
          ),
          viewport: rkPhone360,
        );
        final text = tester.widget<Text>(find.text('Uncategorised'));
        expect(text.textScaler!.scale(1), lessThan(1.0));
        expectTextFits(tester);
      },
    );
  });

  group('13 §4.3 component states', () {
    testWidgets(
      'F1-13-23 RkSkeleton draws ruled rows and announces the wait in words',
      (tester) async {
        for (final locale in rkLocales) {
          for (final scale in [1.0, 2.0]) {
            await pumpRk(
              tester,
              const Scaffold(body: RkSkeleton(label: 'Loading entries')),
              locale: locale,
              textScale: scale,
              viewport: rkPhone360,
            );
            // Never a spinner (11 §4.5).
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(find.byType(ListView), findsOneWidget);
            // The state is carried in words, not only by grey rules — so a
            // screen reader, and grayscale, both get it (07 §1 rule 3).
            final handle = tester.ensureSemantics();
            expect(
              find.bySemanticsLabel('Loading entries'),
              findsOneWidget,
              reason: '${locale.languageCode} at ${scale}x',
            );
            handle.dispose();
            expect(tester.takeException(), isNull);
          }
        }
      },
    );

    testWidgets(
      'F1-13-24 RkErrorState names the cause and always offers the way out',
      (tester) async {
        var retried = 0;
        await pumpRk(
          tester,
          Scaffold(
            body: RkErrorState(
              text: 'Could not read this book',
              retryLabel: 'Try again',
              onRetry: () => retried++,
            ),
          ),
          viewport: rkPhone360,
        );
        expect(find.text('Could not read this book'), findsOneWidget);
        // No dead ends (07 §1 rule 12): the retry is present and it fires.
        await tester.tap(find.text('Try again'));
        expect(retried, 1);
        // The icon is there beside the tint — colour is never alone.
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      },
    );

    testWidgets(
      'F1-13-25 RkErrorState keeps its message readable in EN/PA/HI at 200 % '
      'on 360×800',
      (tester) async {
        for (final locale in rkLocales) {
          await pumpRk(
            tester,
            Scaffold(
              body: RkErrorState(
                text:
                    '${_words[locale.languageCode]!} '
                    '${_words[locale.languageCode]!}',
                retryLabel: 'Try again',
                onRetry: () {},
              ),
            ),
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          expect(tester.takeException(), isNull);
          expectTextFits(tester, reason: locale.languageCode);
        }
      },
    );
  });

  group('RkRuledCard + RkLabelAmountRow (13 §4, design-system §3)', () {
    testWidgets(
      'F1-13-26 the rule runs the full height of a card of any height, and '
      'the label/amount row never loses a digit — EN/PA/HI at 100 % and '
      '200 % on 360×800',
      (tester) async {
        for (final locale in rkLocales) {
          for (final scale in [1.0, 2.0]) {
            await pumpRk(
              tester,
              Scaffold(
                body: ListView(
                  children: [
                    RkRuledCard(
                      child: Column(
                        children: [
                          RkLabelAmountRow(
                            label: RkFitText(_words[locale.languageCode]!),
                            // The figure that lost its last digits at 1.3×
                            // before the row was measured rather than
                            // thresholded.
                            amount: const Text('+₹1,14,600'),
                          ),
                          RkLabelAmountRow(
                            label: RkFitText(_words[locale.languageCode]!),
                            amount: const Text('−₹1,25,000'),
                            leading: const Icon(Icons.south_west),
                            meta: const Text('2 entries'),
                            onTap: () {},
                            semanticHint: 'Open',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              locale: locale,
              textScale: scale,
              viewport: rkPhone360,
            );
            expect(tester.takeException(), isNull);
            expectTextFits(
              tester,
              reason: '${locale.languageCode} at ${scale}x',
            );
            // The rule paints over the card's whole height, however tall the
            // contents made it.
            final card = tester.getRect(find.byType(RkRuledCard).first);
            final rule = tester
                .renderObjectList<RenderBox>(find.byType(ColoredBox))
                .first;
            expect(rule.size.height, greaterThan(card.height / 2));
          }
        }
      },
    );
  });
}
