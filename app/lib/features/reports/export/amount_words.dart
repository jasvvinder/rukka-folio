// Amount in words — the 07 §14 🔒 content rule that ADR 2026-09-12 §3 deferred
// to M12, landed here: *"b/d–c/d rows on ledgers; amount-in-words"*, and the
// donation-receipt paragraph's *"the amount in figures and words"*.
//
// **Integer paise in, one string out** (CLAUDE.md rule 1). No double is
// constructed on the path: the rupee part is `paise ~/ 100` and the paise part
// `paise % 100`, both integer division, and every further split is `~/` and `%`
// on the rupee part.
//
// **The Indian scale, not the short scale** (07 §14, 11 §4.4): units · hundred
// · thousand · lakh (10⁵) · crore (10⁷). Above a crore the scale repeats —
// 10⁹ rupees is *one hundred crore*, 10¹⁵ is *ten crore crore* — so [
// AmountWords.rupeesInWords] recurses on the crore part rather than inventing
// a word the language does not have. That is what carries the largest amount
// the engine can hold: `Paise` is a Dart `int`, so the ceiling is 2⁶³−1 paise
// and nothing here overflows before it.
//
// **Not one word is a literal in Dart** (CLAUDE.md rule 8). Every numeral,
// every scale word and both sentence frames come from
// `app/lib/l10n/parts/reports_{en,pa,hi}.arb`; this file holds only the
// composition. Hindi and Punjabi do not build 21–99 out of a tens word and a
// units word the way English does — *ਇੱਕੀ* is not *ਵੀਹ ਇੱਕ* — so all hundred
// numerals are listed per language and the code never joins two of them.
//
// **A negative amount is refused, never rendered.** A cheque, a receipt and a
// ledger's amount-in-words line all state a magnitude; the side is carried by
// the Dr/Cr column beside it (02 §10 🔒, design-system §1 rule 0b 🔒). Passing
// a signed balance here is a caller's bug, so it throws rather than printing
// *minus four thousand*, which no reader of a receipt would know how to read.
import 'package:flutter/foundation.dart';

import '../../../l10n/gen/app_localizations.dart';

/// How many paise make a rupee.
const int _paisePerRupee = 100;

/// The Indian scale, largest first — each place and the ARB word that names
/// it. Below a crore the multiplier is looked up here; at and above a crore
/// the composition recurses (see [AmountWords.rupeesInWords]).
const int _crore = 10000000;
const int _lakh = 100000;
const int _thousand = 1000;
const int _hundred = 100;

/// The words one locale needs to say an amount, read off its ARB once.
///
/// Held as data rather than reached for through a `BuildContext`, so the
/// composition is a pure function of (integer paise, word table) and a test
/// can pump all three languages without a widget tree.
@immutable
final class AmountWords {
  /// Creates the table.
  ///
  /// [numerals] is exactly 100 long and indexed by the number it names:
  /// `numerals[0]` is *zero*, `numerals[99]` the language's own word for 99.
  const AmountWords({
    required this.numerals,
    required this.hundred,
    required this.thousand,
    required this.lakh,
    required this.crore,
    required this.rupeesOnly,
    required this.rupeesAndPaiseOnly,
  });

  /// Reads the table from the locale's strings.
  factory AmountWords.of(AppLocalizations strings) => AmountWords(
    numerals: [
      strings.reportsAmountWordsN0,
      strings.reportsAmountWordsN1,
      strings.reportsAmountWordsN2,
      strings.reportsAmountWordsN3,
      strings.reportsAmountWordsN4,
      strings.reportsAmountWordsN5,
      strings.reportsAmountWordsN6,
      strings.reportsAmountWordsN7,
      strings.reportsAmountWordsN8,
      strings.reportsAmountWordsN9,
      strings.reportsAmountWordsN10,
      strings.reportsAmountWordsN11,
      strings.reportsAmountWordsN12,
      strings.reportsAmountWordsN13,
      strings.reportsAmountWordsN14,
      strings.reportsAmountWordsN15,
      strings.reportsAmountWordsN16,
      strings.reportsAmountWordsN17,
      strings.reportsAmountWordsN18,
      strings.reportsAmountWordsN19,
      strings.reportsAmountWordsN20,
      strings.reportsAmountWordsN21,
      strings.reportsAmountWordsN22,
      strings.reportsAmountWordsN23,
      strings.reportsAmountWordsN24,
      strings.reportsAmountWordsN25,
      strings.reportsAmountWordsN26,
      strings.reportsAmountWordsN27,
      strings.reportsAmountWordsN28,
      strings.reportsAmountWordsN29,
      strings.reportsAmountWordsN30,
      strings.reportsAmountWordsN31,
      strings.reportsAmountWordsN32,
      strings.reportsAmountWordsN33,
      strings.reportsAmountWordsN34,
      strings.reportsAmountWordsN35,
      strings.reportsAmountWordsN36,
      strings.reportsAmountWordsN37,
      strings.reportsAmountWordsN38,
      strings.reportsAmountWordsN39,
      strings.reportsAmountWordsN40,
      strings.reportsAmountWordsN41,
      strings.reportsAmountWordsN42,
      strings.reportsAmountWordsN43,
      strings.reportsAmountWordsN44,
      strings.reportsAmountWordsN45,
      strings.reportsAmountWordsN46,
      strings.reportsAmountWordsN47,
      strings.reportsAmountWordsN48,
      strings.reportsAmountWordsN49,
      strings.reportsAmountWordsN50,
      strings.reportsAmountWordsN51,
      strings.reportsAmountWordsN52,
      strings.reportsAmountWordsN53,
      strings.reportsAmountWordsN54,
      strings.reportsAmountWordsN55,
      strings.reportsAmountWordsN56,
      strings.reportsAmountWordsN57,
      strings.reportsAmountWordsN58,
      strings.reportsAmountWordsN59,
      strings.reportsAmountWordsN60,
      strings.reportsAmountWordsN61,
      strings.reportsAmountWordsN62,
      strings.reportsAmountWordsN63,
      strings.reportsAmountWordsN64,
      strings.reportsAmountWordsN65,
      strings.reportsAmountWordsN66,
      strings.reportsAmountWordsN67,
      strings.reportsAmountWordsN68,
      strings.reportsAmountWordsN69,
      strings.reportsAmountWordsN70,
      strings.reportsAmountWordsN71,
      strings.reportsAmountWordsN72,
      strings.reportsAmountWordsN73,
      strings.reportsAmountWordsN74,
      strings.reportsAmountWordsN75,
      strings.reportsAmountWordsN76,
      strings.reportsAmountWordsN77,
      strings.reportsAmountWordsN78,
      strings.reportsAmountWordsN79,
      strings.reportsAmountWordsN80,
      strings.reportsAmountWordsN81,
      strings.reportsAmountWordsN82,
      strings.reportsAmountWordsN83,
      strings.reportsAmountWordsN84,
      strings.reportsAmountWordsN85,
      strings.reportsAmountWordsN86,
      strings.reportsAmountWordsN87,
      strings.reportsAmountWordsN88,
      strings.reportsAmountWordsN89,
      strings.reportsAmountWordsN90,
      strings.reportsAmountWordsN91,
      strings.reportsAmountWordsN92,
      strings.reportsAmountWordsN93,
      strings.reportsAmountWordsN94,
      strings.reportsAmountWordsN95,
      strings.reportsAmountWordsN96,
      strings.reportsAmountWordsN97,
      strings.reportsAmountWordsN98,
      strings.reportsAmountWordsN99,
    ],
    hundred: strings.reportsAmountWordsHundred,
    thousand: strings.reportsAmountWordsThousand,
    lakh: strings.reportsAmountWordsLakh,
    crore: strings.reportsAmountWordsCrore,
    rupeesOnly: strings.reportsAmountWordsRupeesOnly,
    rupeesAndPaiseOnly: strings.reportsAmountWordsRupeesPaiseOnly,
  );

  /// 0–99, indexed by the number. One hundred entries in every language
  /// because Hindi and Punjabi compose none of 21–99 (see the file header).
  final List<String> numerals;

  /// *hundred* (10²).
  final String hundred;

  /// *thousand* (10³).
  final String thousand;

  /// *lakh* (10⁵).
  final String lakh;

  /// *crore* (10⁷).
  final String crore;

  /// The whole sentence for a round amount — *Rupees … only*.
  final String Function(String amount) rupeesOnly;

  /// The whole sentence when there are paise — *Rupees … and paise … only*.
  final String Function(String rupees, String paise) rupeesAndPaiseOnly;

  /// [paise] as the sentence a receipt or a ledger foot prints.
  ///
  /// Throws [ArgumentError] on a negative amount: the words state a magnitude
  /// and the side is the column's job (see the file header). Callers pass
  /// `balance.abs()`.
  String call(int paise) {
    if (paise < 0) {
      throw ArgumentError.value(
        paise,
        'paise',
        'amount in words is a magnitude: pass abs(), the Dr/Cr side is the '
            "column's (02 §10 🔒)",
      );
    }
    final rupees = paise ~/ _paisePerRupee;
    final rest = paise % _paisePerRupee;
    if (rest == 0) return rupeesOnly(rupeesInWords(rupees));
    return rupeesAndPaiseOnly(rupeesInWords(rupees), numerals[rest]);
  }

  /// A whole number of rupees in words, on the Indian scale — the bare words,
  /// without the *Rupees … only* frame.
  ///
  /// Recurses on the crore part, which is what lets an amount past 99 crore
  /// read as *… crore … crore* rather than reaching for a word the language
  /// has not got.
  String rupeesInWords(int rupees) {
    if (rupees < 0) {
      throw ArgumentError.value(rupees, 'rupees', 'must not be negative');
    }
    if (rupees == 0) return numerals[0];
    final parts = <String>[];
    var rest = rupees;

    final crores = rest ~/ _crore;
    rest %= _crore;
    if (crores > 0) {
      parts.add(
        '${crores < 100 ? numerals[crores] : rupeesInWords(crores)} '
        '$crore',
      );
    }
    final lakhs = rest ~/ _lakh;
    rest %= _lakh;
    if (lakhs > 0) parts.add('${numerals[lakhs]} $lakh');

    final thousands = rest ~/ _thousand;
    rest %= _thousand;
    if (thousands > 0) parts.add('${numerals[thousands]} $thousand');

    final hundreds = rest ~/ _hundred;
    rest %= _hundred;
    if (hundreds > 0) parts.add('${numerals[hundreds]} $hundred');

    if (rest > 0) parts.add(numerals[rest]);
    return parts.join(' ');
  }
}
