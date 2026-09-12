// S2.2 — the in-place date picker widget (07 §5 step 4 🔒, 13 §3.2 row S2.2).
//
//   F1-07-58  any date in an open period is selectable (backdating); a
//             future date is disabled with the exact tooltip; a locked date
//             is 🔒-greyed and explains the lock with *Fix an old entry*
//             rather than a dead error (07 §1 rule 6); month navigation never
//             reaches a future month.
//
// These drive [EntryDatePicker] directly against an injected [isLocked] —
// see the widget's file-level ⚠️ SPEC note: `LocalLedger` has no public
// period-lock query yet, so the screen that hosts it cannot exercise the
// locked branch against real data. The wiring through `AddEntryScreen`
// itself (today default, picking a date changes what Save posts) is covered
// in `s2_add_entry_screen_test.dart`.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/widgets/entry_date_picker.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(EntryDatePicker)));

Future<void> _pump(
  WidgetTester tester, {
  required LocalDate today,
  required LocalDate selected,
  ValueChanged<LocalDate>? onPick,
  VoidCallback? onFixOldEntry,
  PeriodLockLookup? isLocked,
  Locale? locale,
}) async {
  await pumpRk(
    tester,
    Scaffold(
      body: SizedBox(
        height: 500,
        child: EntryDatePicker(
          today: today,
          selected: selected,
          onPick: onPick ?? (_) {},
          onFixOldEntry: onFixOldEntry ?? () {},
          isLocked: isLocked ?? (_) => false,
        ),
      ),
    ),
    locale: locale,
  );
}

void main() {
  group('F1-07-58 S2.2 date picker (07 §5 step 4 🔒)', () {
    testWidgets('F1-07-58 any open-period day is selectable — backdating', (
      tester,
    ) async {
      final today = LocalDate(2026, 9, 10);
      LocalDate? picked;
      await _pump(
        tester,
        today: today,
        selected: today,
        onPick: (d) => picked = d,
      );
      await tester.tap(
        find.byKey(EntryDatePickerKeys.day(LocalDate(2026, 9, 3))),
      );
      await tester.pump();
      expect(picked, LocalDate(2026, 9, 3));
    });

    testWidgets(
      'F1-07-58 future dates are disabled with the recurring-entry tooltip',
      (tester) async {
        final today = LocalDate(2026, 9, 10);
        var pickedFuture = false;
        await _pump(
          tester,
          today: today,
          selected: today,
          onPick: (_) => pickedFuture = true,
        );
        final l10n = _l10n(tester);
        final future = LocalDate(2026, 9, 20);
        await tester.tap(find.byKey(EntryDatePickerKeys.day(future)));
        await tester.pump();
        expect(pickedFuture, isFalse, reason: 'a future date never posts');
        // 07 §5 step 4 🔒 exact wording.
        expect(
          find.byTooltip(l10n.entryDateFutureTooltip),
          findsWidgets,
          reason: 'every day after today carries the tooltip',
        );
      },
    );

    testWidgets(
      'F1-07-58 a locked day explains the lock and offers Fix an old entry '
      '— never a dead end (07 §1 rule 6)',
      (tester) async {
        final today = LocalDate(2026, 9, 10);
        final lockedMonth = YearMonth(2026, 8);
        var fixed = false;
        await _pump(
          tester,
          today: today,
          selected: today,
          onFixOldEntry: () => fixed = true,
          isLocked: (p) => p == lockedMonth,
        );
        // Step back a month into the locked one.
        await tester.tap(find.byKey(EntryDatePickerKeys.prevMonth));
        await tester.pump();
        final lockedDay = LocalDate(2026, 8, 15);
        await tester.tap(find.byKey(EntryDatePickerKeys.day(lockedDay)));
        await tester.pump();
        // Explains — never a silent no-op and never a bare error dialog.
        expect(find.byKey(EntryDatePickerKeys.lockedMessage), findsOneWidget);
        expect(find.byKey(EntryDatePickerKeys.fixOldEntry), findsOneWidget);
        await tester.tap(find.byKey(EntryDatePickerKeys.fixOldEntry));
        await tester.pump();
        expect(
          fixed,
          isTrue,
          reason: '02 §5 reversal flow offered, not blocked',
        );
      },
    );

    testWidgets('F1-07-58 Back to the calendar returns from the explanation', (
      tester,
    ) async {
      final today = LocalDate(2026, 9, 10);
      await _pump(
        tester,
        today: today,
        selected: today,
        isLocked: (p) => p == YearMonth(2026, 8),
      );
      await tester.tap(find.byKey(EntryDatePickerKeys.prevMonth));
      await tester.pump();
      await tester.tap(
        find.byKey(EntryDatePickerKeys.day(LocalDate(2026, 8, 5))),
      );
      await tester.pump();
      expect(find.byKey(EntryDatePickerKeys.lockedMessage), findsOneWidget);
      await tester.tap(find.byKey(EntryDatePickerKeys.lockedBack));
      await tester.pump();
      expect(find.byKey(EntryDatePickerKeys.lockedMessage), findsNothing);
      expect(
        find.byKey(EntryDatePickerKeys.day(LocalDate(2026, 8, 5))),
        findsOneWidget,
        reason: 'back to the grid, not a dead end',
      );
    });

    testWidgets('F1-07-58 month navigation never reaches a future month', (
      tester,
    ) async {
      final today = LocalDate(2026, 9, 10);
      await _pump(tester, today: today, selected: today);
      // Shown month is today's own — Next is disabled: the ledger never
      // books a future date, so browsing ahead has nothing to select.
      expect(
        tester
            .widget<IconButton>(find.byKey(EntryDatePickerKeys.nextMonth))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(EntryDatePickerKeys.prevMonth));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(EntryDatePickerKeys.nextMonth))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(EntryDatePickerKeys.nextMonth));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(EntryDatePickerKeys.nextMonth))
            .onPressed,
        isNull,
        reason: 'back to the current month — cannot go further',
      );
    });

    testWidgets('F1-07-58 EN/PA/HI at 200 % on 360×800 — no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
        await pumpRk(
          tester,
          Builder(
            builder: (c) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(2.0)),
              child: Scaffold(
                // A fresh key per locale: `tester.pumpWidget` otherwise
                // preserves the previous iteration's `_EntryDatePickerState`
                // (same widget shape at the same slot), so `_shown` would
                // carry the last locale's month-back navigation forward
                // instead of starting each locale over at today's month.
                body: EntryDatePicker(
                  key: ValueKey('dp-${locale.languageCode}'),
                  today: LocalDate(2026, 9, 10),
                  selected: LocalDate(2026, 9, 10),
                  onPick: (_) {},
                  onFixOldEntry: () {},
                  isLocked: (p) => p == YearMonth(2026, 8),
                ),
              ),
            ),
          ),
          locale: locale,
        );
        expect(tester.takeException(), isNull, reason: '$locale at 200 %');
        // Exercise the locked branch too, at scale.
        await tester.tap(find.byKey(EntryDatePickerKeys.prevMonth));
        await tester.pump();
        await tester.tap(
          find.byKey(EntryDatePickerKeys.day(LocalDate(2026, 8, 5))),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '$locale locked at 200 %',
        );
      }
    });
  });
}
