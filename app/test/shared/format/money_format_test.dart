// F1-11: money on screen — 11 §4.4, 07 §1 rules 3–4, design-system §1
// rules 0b/1/4/5. Ids mint upward from F1-11-1 (app/lib/features/README.md).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/format/money_format.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/tokens.dart';

import '../test_app.dart';

const _en = Locale('en');
const _pa = Locale('pa');
const _hi = Locale('hi');

void main() {
  group('formatPaise', () {
    test('F1-11-1 Indian grouping table, whole rupees, paise dropped', () {
      const table = <int, String>{
        0: '₹0',
        999: '₹9',
        1000: '₹10',
        99999: '₹999',
        100000: '₹1,000',
        12450000: '₹1,24,500',
        123456700: '₹12,34,567',
        12345678900: '₹12,34,56,789',
        100000000000: '₹1,00,00,00,000',
      };
      for (final MapEntry(key: paise, value: want) in table.entries) {
        expect(formatPaise(paise, locale: _en), want, reason: '$paise');
      }
    });

    test('F1-11-2 sign: U+2212 on negatives, + only when signed, zero bare', () {
      expect(formatPaise(-820000, locale: _en), '−₹8,200');
      expect(formatPaise(-820000, locale: _en).contains('-'), isFalse);
      expect(formatPaise(4500000, locale: _en), '₹45,000');
      expect(formatPaise(4500000, locale: _en, signed: true), '+₹45,000');
      expect(formatPaise(0, locale: _en, signed: true), '₹0');
      // −50 paise shows as ₹0 in the app: no sign on a figure that reads zero.
      expect(formatPaise(-50, locale: _en, signed: true), '₹0');
      expect(formatPaise(-50, locale: _en, showPaise: true), '−₹0.50');
    });

    test('F1-11-3 showPaise: two decimals for statements and exports', () {
      expect(
        formatPaise(12450075, locale: _en, showPaise: true),
        '₹1,24,500.75',
      );
      expect(formatPaise(999, locale: _en, showPaise: true), '₹9.99');
      expect(formatPaise(100000, locale: _en, showPaise: true), '₹1,000.00');
      expect(formatPaise(5, locale: _en, showPaise: true), '₹0.05');
      expect(formatPaise(0, locale: _en, showPaise: true), '₹0.00');
    });

    test('F1-11-4 Latin digits and identical output in EN, PA and HI', () {
      for (final paise in [0, 999, 123456700, -12345678900]) {
        final en = formatPaise(paise, locale: _en, showPaise: true);
        expect(formatPaise(paise, locale: _pa, showPaise: true), en);
        expect(formatPaise(paise, locale: _hi, showPaise: true), en);
        expect(en.runes.where((r) => r >= 0x30 && r <= 0x39), isNotEmpty);
        expect(RegExp(r'[०-९੦-੯]').hasMatch(en), isFalse);
      }
    });
  });

  group('directionLabel', () {
    test('F1-11-5 one sign, two vocabularies, three languages', () async {
      final en = await AppLocalizations.delegate.load(_en);
      final pa = await AppLocalizations.delegate.load(_pa);
      final hi = await AppLocalizations.delegate.load(_hi);
      expect(directionLabel(en, Vocabulary.consumer, 100), 'Money in');
      expect(directionLabel(en, Vocabulary.consumer, -100), 'Money out');
      expect(directionLabel(en, Vocabulary.professional, 100), 'Dr');
      expect(directionLabel(en, Vocabulary.professional, -100), 'Cr');
      expect(directionLabel(en, Vocabulary.consumer, 0), isNull);
      expect(directionLabel(pa, Vocabulary.consumer, 100), 'ਪੈਸੇ ਆਏ');
      expect(directionLabel(pa, Vocabulary.professional, -100), 'ਜਮ੍ਹਾਂ');
      expect(directionLabel(hi, Vocabulary.consumer, -100), 'पैसे गए');
      expect(directionLabel(hi, Vocabulary.professional, 100), 'नामे');
    });
  });

  group('MoneyText', () {
    Text richText(WidgetTester tester) =>
        tester.widget<Text>(find.byType(Text));

    List<TextSpan> spans(WidgetTester tester) =>
        (richText(tester).textSpan! as TextSpan).children!.cast<TextSpan>();

    testWidgets(
      'F1-11-6 consumer: sign shown, credit/debit colour on numerals only, '
      'tabular figures, word in ink',
      (tester) async {
        await pumpRk(
          tester,
          const Scaffold(body: MoneyText(1860000, showDirection: true)),
        );
        final s = spans(tester);
        expect(s.first.text, '+₹18,600');
        expect(s.first.style!.color, RkStatusColors.light.credit);
        expect(s.last.text, ' Money in');
        expect(s.last.style?.color, isNull, reason: 'word is not tinted');
        expect(richText(tester).style!.fontFeatures, RkType.tabular);

        await pumpRk(
          tester,
          const Scaffold(body: MoneyText(-240000, showDirection: true)),
        );
        final d = spans(tester);
        expect(d.first.text, '−₹2,400');
        expect(d.first.style!.color, RkStatusColors.light.debit);
        expect(d.last.text, ' Money out');
      },
    );

    testWidgets('F1-11-7 professional: absolute figure, never a +, Dr/Cr word, '
        'colour only by favour', (tester) async {
      await pumpRk(
        tester,
        const Scaffold(
          body: MoneyText(
            -2291500,
            vocabulary: Vocabulary.professional,
            showDirection: true,
          ),
        ),
      );
      var s = spans(tester);
      expect(s.first.text, '₹22,915');
      expect(s.first.style, isNull, reason: 'no favour → ink');
      expect(s.last.text, ' Cr');

      await pumpRk(
        tester,
        const Scaffold(
          body: MoneyText(
            4500000,
            vocabulary: Vocabulary.professional,
            showDirection: true,
            favour: Favour.favourable,
          ),
        ),
      );
      s = spans(tester);
      expect(s.first.text, '₹45,000');
      expect(s.first.text!.contains('+'), isFalse);
      expect(s.first.style!.color, RkStatusColors.light.credit);
      expect(s.last.text, ' Dr');
    });

    testWidgets('F1-11-8 zero is muted, unsigned, and has no word', (
      tester,
    ) async {
      await pumpRk(
        tester,
        const Scaffold(body: MoneyText(0, showDirection: true)),
      );
      final s = spans(tester);
      expect(s, hasLength(1));
      expect(s.first.text, '₹0');
      expect(s.first.style!.color, RkStatusColors.light.muted);
    });

    testWidgets('F1-11-9 dark theme takes the lifted credit/debit hues', (
      tester,
    ) async {
      await pumpRk(
        tester,
        const Scaffold(body: MoneyText(100)),
        brightness: Brightness.dark,
      );
      expect(spans(tester).first.style!.color, RkStatusColors.dark.credit);
    });
  });
}
