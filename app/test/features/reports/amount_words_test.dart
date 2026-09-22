// F1-07-423 … F1-07-430 — amount in words (07 §14 🔒 *amount-in-words*, and
// the donation-receipt paragraph's *"the amount in figures and words"*;
// ADR 2026-09-12 §3 deferred this to M12 and it lands here).
//
// What these cases hold down:
//
//   • **The Indian scale, in all three languages.** Units · hundred ·
//     thousand · lakh · crore, read off the real ARB of each locale — not a
//     fixture — so a wrong or missing word in `reports_{en,pa,hi}.arb` fails
//     here rather than on someone's printed receipt.
//   • **Integer paise in, one string out.** Every case passes paise, never
//     rupees and never a double (CLAUDE.md rule 1).
//   • **The ceiling.** `Paise` is a Dart `int`, so the largest amount the
//     engine can hold is 2⁶³−1 paise; the scale repeats above a crore and the
//     case below spells that amount out in full.
//   • **A negative amount is refused, not rendered.** The words are a
//     magnitude; the side belongs to the Dr/Cr column beside them (02 §10 🔒).
@Tags(['F1'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/reports/export/amount_words.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/gen/app_localizations_en.dart';
import 'package:rukka_folio/l10n/gen/app_localizations_hi.dart';
import 'package:rukka_folio/l10n/gen/app_localizations_pa.dart';

final _en = AmountWords.of(AppLocalizationsEn());
final _pa = AmountWords.of(AppLocalizationsPa());
final _hi = AmountWords.of(AppLocalizationsHi());

/// One crore twenty-three lakh forty-five thousand six hundred seventy-eight
/// rupees — the figure that exercises every place of the Indian scale at once.
const int _everyPlacePaise = 12345678 * 100;

void main() {
  group('amount in words (07 §14 🔒)', () {
    test('F1-07-423 EN spells the Indian scale — units, hundred, thousand, '
        'lakh and crore, from integer paise', () {
      expect(_en(0), 'Rupees zero only');
      expect(_en(700), 'Rupees seven only');
      expect(_en(78 * 100), 'Rupees seventy-eight only');
      expect(_en(100 * 100), 'Rupees one hundred only');
      expect(_en(4500 * 100), 'Rupees four thousand five hundred only');
      expect(_en(100000 * 100), 'Rupees one lakh only');
      expect(_en(10000000 * 100), 'Rupees one crore only');
      expect(
        _en(_everyPlacePaise),
        'Rupees one crore twenty-three lakh forty-five thousand six hundred '
        'seventy-eight only',
      );
      // Above a crore the scale repeats rather than reaching for a word
      // English on the Indian scale has not got — 10⁹ is one hundred crore.
      expect(_en(1000000000 * 100), 'Rupees one hundred crore only');
    });

    test('F1-07-424 PA spells the same figure in Gurmukhi, from its own ARB — '
        '21–99 are single words, never a tens word joined to a units word', () {
      expect(_pa(0), 'ਰੁਪਏ ਸਿਫ਼ਰ ਪੂਰੇ');
      expect(_pa(4500 * 100), 'ਰੁਪਏ ਚਾਰ ਹਜ਼ਾਰ ਪੰਜ ਸੌ ਪੂਰੇ');
      expect(
        _pa(_everyPlacePaise),
        'ਰੁਪਏ ਇੱਕ ਕਰੋੜ ਤੇਈ ਲੱਖ ਪੰਜਤਾਲੀ ਹਜ਼ਾਰ ਛੇ ਸੌ ਅਠੱਤਰ ਪੂਰੇ',
      );
      // 21 is ਇੱਕੀ, which is not ਵੀਹ ਇੱਕ — the composition never joins two
      // numerals, which is why all hundred are in the ARB.
      expect(_pa.numerals[21], 'ਇੱਕੀ');
      expect(_pa(21 * 100), 'ਰੁਪਏ ਇੱਕੀ ਪੂਰੇ');
    });

    test('F1-07-425 HI spells the same figure in Devanagari, from its own '
        'ARB', () {
      expect(_hi(0), 'रुपये शून्य पूरे');
      expect(_hi(4500 * 100), 'रुपये चार हज़ार पाँच सौ पूरे');
      expect(
        _hi(_everyPlacePaise),
        'रुपये एक करोड़ तेईस लाख पैंतालीस हज़ार छह सौ अठहत्तर पूरे',
      );
      expect(_hi.numerals[21], 'इक्कीस');
    });

    test('F1-07-426 zero rupees is a sentence, never an empty string — a '
        'receipt for nothing still reads (07 §1 rule 6)', () {
      for (final words in [_en, _pa, _hi]) {
        expect(words(0), isNotEmpty);
        expect(words(0), contains(words.numerals[0]));
      }
    });

    test('F1-07-427 the paise part is spelled out beside the rupees, in all '
        'three languages', () {
      expect(
        _en(_everyPlacePaise + 50),
        'Rupees one crore twenty-three lakh forty-five thousand six hundred '
        'seventy-eight and paise fifty only',
      );
      expect(_en(5), 'Rupees zero and paise five only');
      expect(_pa(4500 * 100 + 50), 'ਰੁਪਏ ਚਾਰ ਹਜ਼ਾਰ ਪੰਜ ਸੌ ਅਤੇ ਪੈਸੇ ਪੰਜਾਹ ਪੂਰੇ');
      expect(_hi(4500 * 100 + 50), 'रुपये चार हज़ार पाँच सौ और पैसे पचास पूरे');
      // 99 paise is the largest paise part there is, and it is one word in
      // every language — nothing here rounds or carries into the rupees.
      expect(_en(99), 'Rupees zero and paise ninety-nine only');
      expect(_en(100), 'Rupees one only');
    });

    test('F1-07-428 the largest amount the engine can hold spells out in '
        'full — the scale repeats above a crore, nothing overflows', () {
      // `Paise` is a Dart int, so this is the ceiling: 2⁶³−1 paise.
      const largest = 9223372036854775807;
      expect(
        _en(largest),
        'Rupees nine hundred twenty-two crore thirty-three lakh seventy-two '
        'thousand thirty-six crore eighty-five lakh forty-seven thousand '
        'seven hundred fifty-eight and paise seven only',
      );
      // Two crore words, because the scale is applied twice — not one word
      // invented for 10¹⁴.
      expect(
        _en(largest).split(' ${_en.crore}').length - 1,
        2,
        reason: 'the Indian scale repeats above a crore',
      );
      for (final words in [_pa, _hi]) {
        expect(words(largest), isNotEmpty);
        expect(words(largest).split(' ${words.crore}').length - 1, 2);
      }
    });

    test('F1-07-429 a negative amount is refused, never rendered — the words '
        'are a magnitude and the side is the column\'s (02 §10 🔒)', () {
      for (final words in [_en, _pa, _hi]) {
        expect(() => words(-1), throwsArgumentError);
        expect(() => words(-4500 * 100), throwsArgumentError);
        expect(() => words.rupeesInWords(-1), throwsArgumentError);
      }
      // The caller's contract: pass the magnitude, which is what the exported
      // statement does with a Cr closing balance.
      expect(
        _en((-4500 * 100).abs()),
        'Rupees four thousand five hundred only',
      );
    });

    test('F1-07-430 every language carries all hundred numerals, each one a '
        'distinct non-empty word — a copy-paste in a draft fails here', () {
      for (final MapEntry(key: lang, value: words) in {
        'en': _en,
        'pa': _pa,
        'hi': _hi,
      }.entries) {
        expect(words.numerals, hasLength(100), reason: lang);
        for (var n = 0; n < 100; n++) {
          expect(words.numerals[n].trim(), isNotEmpty, reason: '$lang $n');
        }
        expect(words.numerals.toSet(), hasLength(100), reason: lang);
        for (final scale in [
          words.hundred,
          words.thousand,
          words.lakh,
          words.crore,
        ]) {
          expect(scale.trim(), isNotEmpty, reason: lang);
        }
      }
    });

    test('F1-07-431 the sentence frame comes from ARB, so the words a locale '
        'has not got cannot leak from another', () {
      // Sanity on the seam itself: three distinct tables, no shared state.
      final tables = <AmountWords>[_en, _pa, _hi];
      expect(tables.map((t) => t.crore).toSet(), hasLength(3));
      expect(tables.map((t) => t(0)).toSet(), hasLength(3));
      // And the factory reads a *supplied* AppLocalizations, never a context.
      final AppLocalizations strings = AppLocalizationsEn();
      expect(AmountWords.of(strings)(100), 'Rupees one only');
    });
  });
}
