// Money on screen (07 §1 rules 3–4; 11 §4.4; design-system §1 rules 0b, 1,
// 4, 5): integer paise in, one string out. ₹ prefixed, Indian grouping, Latin
// digits in every locale, paise hidden in the app and shown as two decimals
// only where a caller (statements, exports) asks. The engine's sign (+ = Dr,
// − = Cr) is never bent here — [MoneyText] only chooses the *word* beside the
// numerals from the vocabulary the surface belongs to (02 §10 🔒).
import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../theme.dart';
import '../tokens.dart';

/// The true minus sign (U+2212) — never a hyphen — in front of a negative
/// amount (07 §1 rule 3: sign always travels with a coloured numeral).
const String minusSign = '−';

/// The rupee sign that prefixes every amount (11 §4.4).
const String rupeeSign = '₹';

/// Formats [paise] as `₹1,24,500` (Indian grouping: three, then twos).
///
/// - `showPaise: false` (the app default — design-system §1 rule 5, ADR
///   2026-09-05f §H9) drops the paise: the whole-rupee part is shown, never
///   rounded up. `showPaise: true` (statements, exports) adds two decimals.
/// - Negative amounts always carry [minusSign]; `signed: true` also prefixes
///   `+` to a positive amount (consumer surfaces, 07 §1 rule 3). Zero is never
///   signed. On a Dr/Cr column pass the absolute value and never `signed`
///   (design-system §1 rule 0b 🔒).
/// - [locale] is accepted so call sites stay locale-aware, but digits are
///   Latin in every locale by rule (11 §4.4, ADR 2026-09-05f §H8) — Mukta has
///   no tabular Indic digits.
String formatPaise(
  int paise, {
  required Locale locale,
  bool showPaise = false,
  bool signed = false,
}) {
  final magnitude = paise.abs();
  final rupees = magnitude ~/ 100;
  final rest = magnitude % 100;
  final grouped = groupIndian(rupees.toString());
  final body = showPaise
      ? '$rupeeSign$grouped.${rest.toString().padLeft(2, '0')}'
      : '$rupeeSign$grouped';
  final shownIsZero = showPaise ? magnitude == 0 : rupees == 0;
  if (shownIsZero) return body;
  if (paise < 0) return '$minusSign$body';
  return signed ? '+$body' : body;
}

/// Indian digit grouping of a plain decimal string: the last three digits,
/// then groups of two (`1234567` → `12,34,567`). Pure string work — no floats.
String groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);
  final parts = <String>[];
  var i = head.length;
  while (i > 0) {
    final start = i - 2 < 0 ? 0 : i - 2;
    parts.insert(0, head.substring(start, i));
    i = start;
  }
  return '${parts.join(',')},$tail';
}

/// Which words a surface speaks (02 §10 🔒, CLAUDE.md rule 9). One engine,
/// two vocabularies; mixing them on one surface is a defect.
enum Vocabulary {
  /// Entry screens, day-book lists, Home, imports: *Money in / Money out*,
  /// signed amounts, credit/debit colour by sign.
  consumer,

  /// A/C statement, trial balance, exports: true ledger *Dr / Cr*, absolute
  /// figures with a side tag, never a `+` (design-system §1 rule 0b 🔒).
  professional,
}

/// The word that accompanies a signed amount under [vocabulary].
///
/// Consumer: `+` → *Money in*, `−` → *Money out* — the money account's own
/// view (Dr money = money came in, 02 §2 row 1). Professional: `+` → *Dr*,
/// `−` → *Cr* (the engine's sign convention, 02 §1.3). Zero has no word.
String? directionLabel(
  AppLocalizations strings,
  Vocabulary vocabulary,
  int paise,
) {
  if (paise == 0) return null;
  return switch ((vocabulary, paise > 0)) {
    (Vocabulary.consumer, true) => strings.moneyDirectionIn,
    (Vocabulary.consumer, false) => strings.moneyDirectionOut,
    (Vocabulary.professional, true) => strings.moneySideDr,
    (Vocabulary.professional, false) => strings.moneySideCr,
  };
}

/// How a professional figure moved the reader's position — decides its
/// colour under the approved option-A directional rule (design-system §5 🔒).
/// The caller knows the account class and the screen; the widget does not.
enum Favour {
  /// Favourable movement → `credit` token.
  favourable,

  /// Unfavourable movement → `debit` token.
  unfavourable,
}

/// An amount rendered by the rules: tabular figures, ₹ Indian grouping,
/// colour on the **numerals only** (07 §1 rule 3), the vocabulary word beside
/// them in plain ink.
///
/// Consumer vocabulary: [paise] is signed, `+` = money in (credit colour),
/// `−` = money out (debit colour), sign always shown. Professional vocabulary:
/// the figure is absolute and unsigned, tagged *Dr*/*Cr* by the engine sign,
/// coloured only when the caller says which way it moved them ([favour]);
/// otherwise ink. Zero renders muted in both.
class MoneyText extends StatelessWidget {
  /// Creates the widget.
  const MoneyText(
    this.paise, {
    super.key,
    this.vocabulary = Vocabulary.consumer,
    this.showPaise = false,
    this.showDirection = false,
    this.favour,
    this.style,
    this.textAlign,
  });

  /// Signed integer paise (+ = Dr, − = Cr; for a money account + is money in).
  final int paise;

  /// Which words this surface speaks.
  final Vocabulary vocabulary;

  /// Two decimals (statements/exports) instead of whole rupees.
  final bool showPaise;

  /// Append the vocabulary word (*Money in* / *Dr* …) after the numerals.
  final bool showDirection;

  /// Professional colour direction; ignored under [Vocabulary.consumer].
  final Favour? favour;

  /// Base style; defaults to the theme's `labelLarge` (RkType.amountRow).
  /// Tabular figures are always added.
  final TextStyle? style;

  /// Alignment for the text run (amount columns are right-aligned).
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final base =
        (style ?? Theme.of(context).textTheme.labelLarge ?? RkType.amountRow)
            .copyWith(fontFeatures: RkType.tabular);
    final locale = Localizations.localeOf(context);

    final String numerals;
    final Color? tint;
    switch (vocabulary) {
      case Vocabulary.consumer:
        numerals = formatPaise(
          paise,
          locale: locale,
          showPaise: showPaise,
          signed: true,
        );
        tint = paise > 0
            ? status.credit
            : paise < 0
            ? status.debit
            : status.muted;
      case Vocabulary.professional:
        numerals = formatPaise(
          paise.abs(),
          locale: locale,
          showPaise: showPaise,
        );
        tint = paise == 0
            ? status.muted
            : switch (favour) {
                Favour.favourable => status.credit,
                Favour.unfavourable => status.debit,
                null => null,
              };
    }
    final word = showDirection
        ? directionLabel(strings, vocabulary, paise)
        : null;
    final label = word == null ? numerals : '$numerals $word';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: numerals,
              style: tint == null ? null : TextStyle(color: tint),
            ),
            if (word != null) TextSpan(text: ' $word'),
          ],
        ),
        style: base,
        textAlign: textAlign,
        softWrap: false,
      ),
    );
  }
}
