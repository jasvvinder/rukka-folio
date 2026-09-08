// F1-11 (continued): dates on screen — 07 §1 rule 5 🔒. Ids continue after
// money_format_test.dart (F1-11-9).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/format/date_format.dart';

void main() {
  late AppLocalizations en, pa, hi;
  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    pa = await AppLocalizations.delegate.load(const Locale('pa'));
    hi = await AppLocalizations.delegate.load(const Locale('hi'));
  });

  test('F1-11-10 EN abbreviates the month, DD zero-padded, Latin digits', () {
    expect(formatLedgerDate(LocalDate(2026, 8, 7), strings: en), '07 Aug 2026');
    expect(
      formatLedgerDate(LocalDate(2026, 12, 31), strings: en),
      '31 Dec 2026',
    );
    expect(formatLedgerDate(LocalDate(2027, 1, 1), strings: en), '01 Jan 2027');
  });

  test('F1-11-11 PA and HI use full month names, never abbreviations', () {
    expect(
      formatLedgerDate(LocalDate(2026, 8, 7), strings: pa),
      '07 ਅਗਸਤ 2026',
    );
    expect(
      formatLedgerDate(LocalDate(2026, 8, 7), strings: hi),
      '07 अगस्त 2026',
    );
    const paFull = [
      'ਜਨਵਰੀ', 'ਫ਼ਰਵਰੀ', 'ਮਾਰਚ', 'ਅਪ੍ਰੈਲ', 'ਮਈ', 'ਜੂਨ', //
      'ਜੁਲਾਈ', 'ਅਗਸਤ', 'ਸਤੰਬਰ', 'ਅਕਤੂਬਰ', 'ਨਵੰਬਰ', 'ਦਸੰਬਰ',
    ];
    const hiFull = [
      'जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून', //
      'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर',
    ];
    for (var m = 1; m <= 12; m++) {
      expect(monthName(pa, m), paFull[m - 1], reason: 'pa month $m');
      expect(monthName(hi, m), hiFull[m - 1], reason: 'hi month $m');
      expect(monthName(en, m).length, 3, reason: 'en month $m');
      expect(monthName(en, m).endsWith('.'), isFalse, reason: 'en month $m');
    }
  });

  test(
    'F1-11-12 Today / Yesterday against the injected now, else the date',
    () {
      final now = DateTime(2026, 9, 7, 10);
      expect(
        formatListDate(LocalDate(2026, 9, 7), strings: en, now: now),
        'Today',
      );
      expect(
        formatListDate(LocalDate(2026, 9, 6), strings: en, now: now),
        'Yesterday',
      );
      expect(
        formatListDate(LocalDate(2026, 9, 7), strings: pa, now: now),
        'ਅੱਜ',
      );
      expect(
        formatListDate(LocalDate(2026, 9, 6), strings: hi, now: now),
        'कल',
      );
      expect(
        formatListDate(LocalDate(2026, 9, 5), strings: en, now: now),
        '05 Sep 2026',
      );
      // Midnight boundary: 23:59 on the 7th is still "Today" for the 7th.
      final late = DateTime(2026, 9, 7, 23, 59);
      expect(
        formatListDate(LocalDate(2026, 9, 7), strings: en, now: late),
        'Today',
      );
      // Month boundary for yesterday.
      final first = DateTime(2026, 10, 1, 9);
      expect(
        formatListDate(LocalDate(2026, 9, 30), strings: en, now: first),
        'Yesterday',
      );
    },
  );

  test(
    'F1-11-13 localDateOf takes the calendar day of the injected moment',
    () {
      expect(localDateOf(DateTime(2026, 9, 7, 23, 59)), LocalDate(2026, 9, 7));
      expect(localDateOf(DateTime(2026, 9, 7, 0, 0)), LocalDate(2026, 9, 7));
    },
  );
}
