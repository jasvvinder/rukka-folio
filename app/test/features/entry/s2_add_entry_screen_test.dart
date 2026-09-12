// S2 Add entry (keypad-first) — the 8-second flow (07 §5 🔒, 01 §2.1 🔒,
// 13 §3.2 rows S2/S2.1/S2.3, 13 §5 flow F2).
//
//   F1-07-17  the screen 07 §5 and 01 §2.1 name: amount-first keypad with
//             `+` quick-sum and `.` paise, the five-position pill, slot
//             labels by verb, the chip row rule, the live preview's five
//             states, Save through the engine, keypad stays zeroed, snackbar
//             with Undo, and EN/PA/HI at 200 % on 360×800 and 375×667.
//   F1-07-54  the in-place picker swap (S2.1): the lower region holds keypad
//             → account list → keypad, no sheet and no route push.
//   F1-07-55  inline create with the class inferred from the slot; the
//             two-chip question only where the slot is ambiguous.
//   F1-07-56  Move money — the pill's fifth position (ADR 2026-09-03b),
//             FROM chips → TO chips, within one book.
//   F1-07-58  S2.2 the date chip opens the in-place calendar (never a sheet,
//             never a route) and Save posts against the date it picked,
//             defaulting to today's when nothing was picked.
//   F1-07-59  S2.5 choosing the book's Drawings account as Money out's
//             ledger slot shows the one-line confirmation and posts through
//             the same `moneyOut` call the engine always uses (02 §10 🔒).
//   F1-07-13  07 §1's global design rules as they bind S2: nothing
//             pre-selected, no dead end in the screen or its pickers, colour
//             never alone, and the 8-second entry's F1 proxy — the ui-screen
//             contract's "tap sequence completes in ≤ 8 steps" for the
//             shortest complete Money in entry. This is an interaction-count
//             and no-blocking-step proxy; it does not and cannot honestly
//             measure eight wall-clock seconds — that stopwatch is F2, run at
//             RC on the device lab (09 §preamble suite F).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/entry_amount.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/entry/widgets/entry_chip_row.dart';
import 'package:rukka_folio/features/entry/widgets/entry_drawings_banner.dart';
import 'package:rukka_folio/features/entry/widgets/entry_preview_line.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

/// Bumped on every pump so each one gets a *fresh* [AddEntryScreen] state:
/// pumping the same widget type into the same slot otherwise updates the
/// existing State, which would carry the previous verb and book over.
int _pumpSeq = 0;

/// Pumps S2 for [kind] over a seeded book.
Future<SeededLedger> _pumpEntry(
  WidgetTester tester, {
  EntryKind kind = EntryKind.moneyIn,
  Locale? locale,
  double textScale = 1.0,
  Size? size,
  SeededLedger? seeded,
}) async {
  final s = seeded ?? await seedSoloLedger();
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await pumpRk(
    tester,
    Builder(
      builder: (c) => MediaQuery(
        data: MediaQuery.of(c)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: AddEntryScreen(
          key: ValueKey('entry-${_pumpSeq++}'),
          bookId: s.bookId,
          kind: kind,
        ),
      ),
    ),
    ledger: s.ledger,
    locale: locale,
  );
  return s;
}

/// Tears the tree down *inside* the test: cancelling drift's query stream
/// schedules a zero-duration timer, and only a pump inside the test fires it
/// before the binding's pending-timer invariant runs (the pattern S1 uses).
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AddEntryScreen)));

Future<void> _typeAmount(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tester.tap(find.byKey(AddEntryKeys.pad(k)));
    await tester.pump();
  }
}

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byKey(AddEntryKeys.save)).enabled;

Color? _previewColor(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(AddEntryKeys.previewText)).style?.color;

/// Reads balances from *outside* the fake-async zone. A drift query stream's
/// first event arrives on a zero-duration timer, and a bare `await` in a
/// widget test never lets the fake clock fire it — the test would hang.
/// `runAsync` is the supported escape hatch (the pattern S3.1 uses).
Future<Map<String, int>> _balances(WidgetTester tester, SeededLedger s) async {
  final rows = (await tester.runAsync(
    () => s.ledger.watchAccounts(s.bookId).first,
  ))!;
  return {for (final r in rows) r.account.id: r.balancePaise};
}

/// Lets the *real* event loop turn once. A ledger write started from a tap
/// (Save, Undo) is real sqlite I/O, and `pumpAndSettle` only turns the fake
/// clock — the write's future may still be outstanding when it returns, so a
/// read straight after would see the projection one write behind. `runAsync`
/// is the supported escape hatch (the same one [_balances] uses).
Future<void> _settleIo(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

/// Every entry's verb, newest first — the same escape hatch.
Future<List<String>> _kinds(WidgetTester tester, SeededLedger s) async {
  final rows = (await tester.runAsync(
    () => s.ledger.db
        .customSelect('SELECT kind FROM entries_p ORDER BY hlc DESC, id DESC')
        .get(),
  ))!;
  return rows.map((r) => r.read<String>('kind')).toList();
}

/// The book's accounts, outside the fake-async zone.
Future<List<AccountBalance>> _accountsOf(
  WidgetTester tester,
  SeededLedger s,
) async =>
    (await tester.runAsync(() => s.ledger.watchAccounts(s.bookId).first))!;

void main() {
  // A focused `EditableText` blinks its caret on a repeating timer — an
  // animation that never settles, so any `pumpAndSettle` after the picker's
  // search field takes focus would grind out ten simulated minutes of frames.
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  group('F1-07-17 S2 add entry — the 8-second flow (07 §5)', () {
    test('F1-07-17 amount: + quick-sum and . paise are integer paise', () {
      // `120+80+40` (07 §5 step 1) — three terms, one total, no float.
      var a = const AmountExpression.empty();
      for (final k in '120+80+40'.split('')) {
        a = k == '+' ? a.plus() : a.digit(k);
      }
      expect(a.paise, 24000);
      expect(a.hasSum, isTrue);

      // Paise via `.`, two digits maximum, never rounded through a double.
      var b = const AmountExpression.empty();
      for (final k in '80.50'.split('')) {
        b = k == '.' ? b.dot() : b.digit(k);
      }
      expect(b.paise, 8050);
      expect(b.digit('9').paise, 8050, reason: 'third paise digit ignored');
      expect(b.dot().paise, 8050, reason: 'second dot ignored');

      // Backspace walks back through the terms; empty is ₹0, never null.
      expect(const AmountExpression.empty().paise, 0);
      expect(const AmountExpression.empty().backspace().paise, 0);
      expect(b.backspace().paise, 8050, reason: '80.5 is still 8050 paise');
      expect(b.backspace().backspace().paise, 8000);
    });

    testWidgets('F1-07-17 nothing pre-selected on open (07 §5 🔒)', (
      tester,
    ) async {
      await _pumpEntry(tester);
      final l10n = _l10n(tester);
      expect(find.text(l10n.entrySlotChoose), findsNWidgets(2));
      expect(_saveEnabled(tester), isFalse);
      expect(
        tester.widget<EntryPreviewLine>(find.byType(EntryPreviewLine)).complete,
        isFalse,
      );
      // No chip is ticked (07 §5 🔒 / ADR 2026-09-05f §C).
      expect(
        tester
            .widgetList<EntryAccountChip>(find.byType(EntryAccountChip))
            .every((c) => !c.selected),
        isTrue,
      );
      await _unmount(tester);
    });

    testWidgets('F1-07-17 preview updates on every digit, Indian grouping', (
      tester,
    ) async {
      await _pumpEntry(tester);
      await _typeAmount(tester, '2');
      expect(find.textContaining('₹2'), findsWidgets);
      await _typeAmount(tester, '4');
      expect(find.textContaining('₹24'), findsWidgets);
      await _typeAmount(tester, '00');
      expect(find.textContaining('₹2,400'), findsWidgets);
      await _typeAmount(tester, '00');
      // Indian grouping: three, then twos (money_format.groupIndian).
      expect(find.textContaining('₹2,40,000'), findsWidgets);
      await _unmount(tester);
    });

    testWidgets('F1-07-17 slot labels come from the verb table (07 §5)', (
      tester,
    ) async {
      final seeded = await seedSoloLedger();
      for (final (kind, labels) in [
        (EntryKind.moneyIn, ['into', 'from']),
        (EntryKind.moneyOut, ['from', 'forWhat']),
        (EntryKind.gaveCredit, ['whatYouGave', 'toWhom']),
        (EntryKind.tookCredit, ['whatYouTook', 'fromWhom']),
        (EntryKind.transfer, ['moveFrom', 'moveTo']),
      ]) {
        await _pumpEntry(tester, kind: kind, seeded: seeded);
        final l10n = _l10n(tester);
        for (final name in labels) {
          final slot = SlotLabel.values.firstWhere((s) => s.name == name);
          expect(
            find.text(slotLabel(l10n, slot)),
            findsWidgets,
            reason: '${kind.wire} shows $name',
          );
        }
        // The money-account label is never a fixed "FROM" (07 §5 🔒): the
        // plan, not the widget, decides which label each slot carries.
        expect(VerbPlan.of(kind).money.label.name, labels[0]);
        expect(VerbPlan.of(kind).ledger.label.name, labels[1]);
      }
      await _unmount(tester);
    });

    testWidgets('F1-07-17 chip row: three most-used money A/Cs + More', (
      tester,
    ) async {
      final s = await seedSoloLedger();
      // A fourth money account nobody has used — it must fall behind the
      // three the book actually moves money through, and sit under + More.
      await s.ledger.addAccount(
        s.bookId,
        name: 'PNB Current',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.current,
      );
      await s.ledger.addAccount(
        s.bookId,
        name: 'Gollak',
        accountClass: AccountClass.money,
        subtype: MoneySubtype.cashCollection,
      );
      await _pumpEntry(tester, kind: EntryKind.moneyOut, seeded: s);
      final chips = tester
          .widgetList<EntryAccountChip>(find.byType(EntryAccountChip))
          .toList();
      expect(chips.length, 3, reason: 'three chips, never four');
      expect(
        chips.map((c) => c.name),
        containsAll(['Cash in hand', 'SBI Saving']),
      );
      expect(find.text(_l10n(tester).entryChipsMore), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('F1-07-17 chip row absent when no money A/C is involved', (
      tester,
    ) async {
      // Milk on khata (07 §5 🔒): Dr Milk Expense · Cr Vardhman Dairy — the
      // chip row is absent entirely rather than offering untappable chips.
      final s = await seedSoloLedger();
      await _pumpEntry(tester, kind: EntryKind.tookCredit, seeded: s);
      expect(find.byType(EntryAccountChip), findsWidgets);
      // Choose an expense category in the money-side slot. The list is
      // taller than the lower region, so reach the category the way 07 §5
      // step 3 says a user does — through search, not by scrolling.
      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.money)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(AddEntryKeys.search), 'Diesel');
      await tester.pumpAndSettle();
      // `.first` is the list row: the search field itself now also reads
      // *Diesel*, and it is the later of the two in the tree.
      await tester.tap(find.text('Diesel').first);
      await tester.pumpAndSettle();
      expect(find.byType(EntryAccountChip), findsNothing);
      expect(find.text(_l10n(tester).entryChipsMore), findsNothing);
      await _unmount(tester);
    });

    testWidgets('F1-07-17 preview: reserved height, muted → ink with Save', (
      tester,
    ) async {
      final s = await _pumpEntry(tester, kind: EntryKind.moneyOut);
      final empty = tester.getSize(find.byKey(AddEntryKeys.preview));
      final ctx = tester.element(find.byType(AddEntryScreen));
      final muted = RkStatusColors.of(ctx).muted;
      expect(_previewColor(tester), muted);
      expect(_saveEnabled(tester), isFalse);

      await _typeAmount(tester, '2400');
      expect(
        tester.getSize(find.byKey(AddEntryKeys.preview)),
        empty,
        reason: 'the line reserves its full height from the first frame 🔒',
      );
      expect(_previewColor(tester), muted);
      expect(_saveEnabled(tester), isFalse);

      await tester.tap(find.text('Cash in hand'));
      await tester.pump();
      // One side chosen: still muted, Save still grey, and no error anywhere.
      expect(_previewColor(tester), muted);
      expect(_saveEnabled(tester), isFalse);
      expect(find.textContaining('Cash in hand'), findsWidgets);
      expect(
        tester.getSize(find.byKey(AddEntryKeys.preview)),
        empty,
        reason: 'nothing below the line shifts as slots fill',
      );

      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diesel').last);
      await tester.pumpAndSettle();
      // Completion is the validation 🔒: full ink and a solid Save together.
      expect(_previewColor(tester), isNot(muted));
      expect(_saveEnabled(tester), isTrue);
      expect(tester.getSize(find.byKey(AddEntryKeys.preview)), empty);
      expect(s.bookId, isNotEmpty);
      await _unmount(tester);
    });

    testWidgets('F1-07-17 preview line renders its five states (01 §2.1)', (
      tester,
    ) async {
      Future<void> pumpLine(EntryPreviewLine line) =>
          pumpRk(tester, Scaffold(body: line));
      // Nothing yet · typing · one side chosen · complete · note appended.
      await pumpLine(const EntryPreviewLine(amountPaise: 0, complete: false));
      expect(find.textContaining('₹0'), findsOneWidget);
      expect(find.textContaining('⋯'), findsOneWidget);

      await pumpLine(
        const EntryPreviewLine(amountPaise: 240000, complete: false),
      );
      expect(find.textContaining('₹2,400'), findsOneWidget);

      await pumpLine(
        const EntryPreviewLine(
          amountPaise: 240000,
          creditName: 'Cash A/c',
          complete: false,
        ),
      );
      expect(find.textContaining('Cash A/c'), findsOneWidget);
      expect(find.textContaining('⋯'), findsOneWidget);

      await pumpLine(
        const EntryPreviewLine(
          amountPaise: 240000,
          creditName: 'Cash A/c',
          debitName: 'Diesel Expense A/c',
          complete: true,
        ),
      );
      expect(find.textContaining('→'), findsOneWidget);
      expect(find.textContaining('⋯'), findsNothing);

      await pumpLine(
        const EntryPreviewLine(
          amountPaise: 240000,
          creditName: 'Cash A/c',
          debitName: 'Diesel Expense A/c',
          note: 'for diesel in the Isuzu',
          complete: true,
        ),
      );
      expect(find.textContaining('for diesel in the Isuzu'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets(
      'F1-07-17 Save posts, zeroes the keypad and stays (07 §5.6/7)',
      (tester) async {
        final s = await seedSoloLedger();
        final before = await _balances(tester, s);
        await _pumpEntry(tester, kind: EntryKind.moneyOut, seeded: s);
        await _typeAmount(tester, '2400');
        await tester.tap(find.text('Cash in hand'));
        await tester.pump();
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Diesel').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.save));
        await tester.pumpAndSettle();

        // Posted through LocalLedger.moneyOut — Dr Diesel · Cr Cash, integer
        // paise, and the engine's own verb (02 §2), not a hand-built journal.
        final after = await _balances(tester, s);
        expect(after[s.cashId], before[s.cashId]! - 240000);
        expect(after[s.fuelId], before[s.fuelId]! + 240000);
        expect((await _kinds(tester, s)).first, 'money_out');

        // Stay on the keypad, zeroed, for the next entry (07 §5.7).
        expect(find.byType(AddEntryScreen), findsOneWidget);
        expect(find.byKey(AddEntryKeys.keypad), findsOneWidget);
        expect(
          tester
              .widget<EntryPreviewLine>(find.byType(EntryPreviewLine))
              .amountPaise,
          0,
        );
        expect(_saveEnabled(tester), isFalse);

        // Snackbar: `Saved ✓ (on phone)` with Undo (10 s).
        final l10n = _l10n(tester);
        expect(find.text(l10n.entrySaved), findsOneWidget);
        expect(find.text(l10n.entryUndo), findsOneWidget);
        final bar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(bar.duration, const Duration(seconds: 10));
        await _unmount(tester);
      },
    );

    testWidgets('F1-07-17 Undo appends a reversal, never a delete (02 §5)', (
      tester,
    ) async {
      final s = await seedSoloLedger();
      final before = await _balances(tester, s);
      final countBefore = (await _kinds(tester, s)).length;
      await _pumpEntry(tester, kind: EntryKind.moneyIn, seeded: s);
      await _typeAmount(tester, '500');
      await tester.tap(find.text('Cash in hand'));
      await tester.pump();
      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shop sales').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddEntryKeys.save));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n(tester).entryUndo));
      await _settleIo(tester);
      expect(find.text(_l10n(tester).entryUndone), findsOneWidget);

      final after = await _balances(tester, s);
      expect(after[s.cashId], before[s.cashId], reason: 'reversed to nil');
      expect(
        (await _kinds(tester, s)).length,
        countBefore + 2,
        reason: 'the entry and its mirror both stay in history (02 §5)',
      );
      await _unmount(tester);
    });

    testWidgets('F1-07-17 EN/PA/HI at 200 % — no overflow, never scrolls', (
      tester,
    ) async {
      final seeded = await seedSoloLedger();
      for (final size in [const Size(360, 800), const Size(375, 667)]) {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          for (final kind in EntryKind.values.where(
            (k) => k != EntryKind.adjustment,
          )) {
            await _pumpEntry(
              tester,
              kind: kind,
              locale: locale,
              textScale: 2.0,
              size: size,
              seeded: seeded,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$locale ${kind.wire} at 200 % on $size',
            );
            // 07 §5 🔒 "never scrolls": the verb pill and the chip row pan
            // horizontally; nothing on this screen scrolls vertically while
            // the keypad holds the lower region.
            expect(
              tester
                  .widgetList<Scrollable>(find.byType(Scrollable))
                  .every((s) => s.axisDirection == AxisDirection.right),
              isTrue,
              reason: 'a vertical scrollable appeared: $locale $kind $size',
            );
            expect(find.byKey(AddEntryKeys.save), findsOneWidget);
            expect(find.byKey(AddEntryKeys.preview), findsOneWidget);
          }
        }
      }
      await _unmount(tester);
    });
  });

  group('F1-07-54 S2.1 the picker swaps in place (07 §5 🔒)', () {
    testWidgets('F1-07-54 keypad → account list → keypad, same screen', (
      tester,
    ) async {
      await _pumpEntry(tester, kind: EntryKind.moneyOut);
      await _typeAmount(tester, '2400');
      expect(find.byKey(AddEntryKeys.keypad), findsOneWidget);
      expect(find.byKey(AddEntryKeys.picker), findsNothing);

      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      await tester.pumpAndSettle();
      // The list replaces the keypad in the same space.
      expect(find.byKey(AddEntryKeys.keypad), findsNothing);
      expect(find.byKey(AddEntryKeys.picker), findsOneWidget);
      // No modal sheet and no second screen 🔒.
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
      // Everything already entered stays visible.
      expect(find.byKey(AddEntryKeys.amount), findsOneWidget);
      expect(find.textContaining('₹2,400'), findsWidgets);
      expect(find.byKey(AddEntryKeys.verbPill), findsOneWidget);
      expect(find.byType(EntryAccountChip), findsWidgets);

      await tester.tap(find.text('Diesel').last);
      await tester.pumpAndSettle();
      // …and the keypad returns once an account is chosen.
      expect(find.byKey(AddEntryKeys.keypad), findsOneWidget);
      expect(find.byKey(AddEntryKeys.picker), findsNothing);
      expect(find.textContaining('₹2,400'), findsWidgets);
      await _unmount(tester);
    });

    testWidgets('F1-07-54 + More opens the money list in the same space', (
      tester,
    ) async {
      await _pumpEntry(tester, kind: EntryKind.moneyOut);
      await tester.tap(find.text(_l10n(tester).entryChipsMore));
      await tester.pumpAndSettle();
      expect(find.byKey(AddEntryKeys.picker), findsOneWidget);
      expect(find.byKey(AddEntryKeys.keypad), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
      // Money slot: money accounts only — a category is not offered here.
      expect(find.text('Diesel'), findsNothing);
      await tester.tap(find.text('SBI Saving').last);
      await tester.pumpAndSettle();
      expect(find.byKey(AddEntryKeys.keypad), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('F1-07-54 search-then-empty offers create, never a dead end', (
      tester,
    ) async {
      await _pumpEntry(tester, kind: EntryKind.moneyOut);
      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(AddEntryKeys.search), 'Langar');
      await tester.pumpAndSettle();
      expect(find.byKey(AddEntryKeys.create), findsOneWidget);
      await _unmount(tester);
    });
  });

  group(
    'F1-07-55 S2.1 inline create, class inferred from the slot (02 §1.2)',
    () {
      testWidgets('F1-07-55 unambiguous slot creates without a question', (
        tester,
      ) async {
        // Took on credit → FROM WHOM is a party and nothing else, so the one
        // two-chip question is not asked (07 §5 step 3 🔒).
        final s = await seedSoloLedger();
        await _pumpEntry(tester, kind: EntryKind.tookCredit, seeded: s);
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(AddEntryKeys.search),
          'Vardhman Dairy',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.create));
        await tester.pumpAndSettle();

        final rows = await _accountsOf(tester, s);
        final made = rows.firstWhere((r) => r.account.name == 'Vardhman Dairy');
        expect(made.account.accountClass, AccountClass.party);
        // Created and selected in one tap, keypad back.
        expect(find.byKey(AddEntryKeys.keypad), findsOneWidget);
        expect(find.textContaining('Vardhman Dairy'), findsWidgets);
        expect(VerbPlan.of(EntryKind.tookCredit).ledger.creatable, [
          AccountClass.party,
        ]);
        await _unmount(tester);
      });

      testWidgets('F1-07-55 ambiguous slot asks the one two-chip question', (
        tester,
      ) async {
        // Money out → FOR is an expense category *or* a person you are paying.
        final s = await seedSoloLedger();
        await _pumpEntry(tester, kind: EntryKind.moneyOut, seeded: s);
        final l10n = _l10n(tester);
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(AddEntryKeys.search), 'Langar');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.create));
        await tester.pumpAndSettle();
        expect(find.text(l10n.entryCreateAsk), findsOneWidget);
        expect(find.text(l10n.entryCreateExpense), findsOneWidget);
        expect(find.text(l10n.entryCreatePerson), findsOneWidget);
        await tester.tap(find.text(l10n.entryCreateExpense));
        await tester.pumpAndSettle();

        final rows = await _accountsOf(tester, s);
        final made = rows.firstWhere((r) => r.account.name == 'Langar');
        expect(made.account.accountClass, AccountClass.categoryExpense);
        expect(find.byKey(AddEntryKeys.keypad), findsOneWidget);
        await _unmount(tester);
      });
    },
  );

  group('F1-07-56 S2.3 Move money — the pill\'s fifth position', () {
    testWidgets('F1-07-56 five positions, Move money last (ADR 2026-09-03b)', (
      tester,
    ) async {
      await _pumpEntry(tester);
      final l10n = _l10n(tester);
      expect(find.byKey(AddEntryKeys.verbPill), findsOneWidget);
      for (final label in [
        l10n.entryVerbMoneyIn,
        l10n.entryVerbMoneyOut,
        l10n.entryVerbGaveCredit,
        l10n.entryVerbTookCredit,
        l10n.entryVerbMoveMoney,
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(entryVerbs.last, EntryKind.transfer);
      expect(entryVerbs.length, 5);
      await _unmount(tester);
    });

    testWidgets('F1-07-56 switching position keeps the amount (07 §5)', (
      tester,
    ) async {
      // The pill pans horizontally (07 §5 🔒) and its fifth position sits
      // past the right edge of the default 800-pt test surface; a phone-sized
      // surface plus a pan puts the tap target back on screen.
      await _pumpEntry(tester, size: const Size(360, 800));
      await _typeAmount(tester, '2400');
      final moveMoney = find.text(_l10n(tester).entryVerbMoveMoney);
      await tester.ensureVisible(moveMoney);
      await tester.pumpAndSettle();
      await tester.tap(moveMoney);
      await tester.pumpAndSettle();
      expect(find.textContaining('₹2,400'), findsWidgets);
      await _unmount(tester);
    });

    testWidgets('F1-07-56 FROM chips → TO chips, within one book', (
      tester,
    ) async {
      final s = await seedSoloLedger();
      final before = await _balances(tester, s);
      await _pumpEntry(tester, kind: EntryKind.transfer, seeded: s);
      final l10n = _l10n(tester);
      expect(find.text(slotLabel(l10n, SlotLabel.moveFrom)), findsOneWidget);
      expect(find.text(slotLabel(l10n, SlotLabel.moveTo)), findsOneWidget);
      // Both sides are chip rows (07 §5 table, row Transfer).
      expect(VerbPlan.of(EntryKind.transfer).ledger.showChips, isTrue);

      await _typeAmount(tester, '500');
      await tester.tap(find.text('Cash in hand').first);
      await tester.pump();
      // The chosen side is never offered on the other: no cash → cash.
      expect(find.text('Cash in hand'), findsWidgets);
      await tester.tap(find.text('SBI Saving').last);
      await tester.pump();
      expect(_saveEnabled(tester), isTrue);
      await tester.tap(find.byKey(AddEntryKeys.save));
      await tester.pumpAndSettle();

      final after = await _balances(tester, s);
      expect(after[s.cashId], before[s.cashId]! - 50000);
      expect(after[s.bankId], before[s.bankId]! + 50000);
      expect((await _kinds(tester, s)).first, 'transfer');
      // Total money is unchanged — one book, two money accounts (02 §2 v5).
      expect(
        after.values.fold(0, (a, b) => a + b),
        before.values.fold(0, (a, b) => a + b),
      );
      await _unmount(tester);
    });
  });

  group(
    'F1-07-59 S2.5 the drawings confirmation (07 §5 "Owner\'s drawings" 🔒)',
    () {
      /// [s] plus a book-chart Drawings account nothing else has claimed —
      /// the ADR 2026-09-09b seeding gap [drawingsAccountOf] documents, so
      /// this lane's own fixture supplies it (02 §7.1 *Just me*).
      Future<String> _addDrawings(SeededLedger s) async {
        final drawings = await s.ledger.addAccount(
          s.bookId,
          name: 'Drawings',
          accountClass: AccountClass.equitySystem,
          systemRole: SystemRole.drawings,
        );
        return drawings.id;
      }

      /// Opens [slot]'s picker, searches for [name] (the list is a
      /// `ListView.builder` — a name past the built extent is otherwise
      /// unfindable) and taps the one row it narrows to.
      ///
      /// The row is addressed as the `ListTile` inside the picker, never as
      /// `find.text(name)`: once the query has been typed, the search field's
      /// own `EditableText` carries that exact string too, so a bare text
      /// finder matches two widgets and `.last` taps the search box — which
      /// leaves the slot unanswered and the picker still open.
      Future<void> _pick(
        WidgetTester tester,
        EntrySlot slot,
        String name,
      ) async {
        await tester.tap(find.byKey(AddEntryKeys.slot(slot)));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(AddEntryKeys.search), name);
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(AddEntryKeys.picker),
                matching: find.text(name),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }

      testWidgets(
        'F1-07-59 absent until Money out\'s ledger slot is Drawings',
        (tester) async {
          final s = await seedSoloLedger();
          await _addDrawings(s);
          // A phone surface, not the 800×600 default: the in-place picker
          // lives in what the keypad leaves, and 600 pt of height leaves it
          // under 100 pt — a rendering artefact of the test surface, not of
          // the screen (07 §5 targets 360×800 and 375×667).
          await _pumpEntry(
            tester,
            kind: EntryKind.moneyOut,
            seeded: s,
            size: const Size(360, 800),
          );
          expect(find.byKey(EntryDrawingsBannerKeys.banner), findsNothing);

          // A non-Drawings pick still shows no banner.
          await _pick(tester, EntrySlot.ledger, 'Diesel');
          expect(find.byKey(EntryDrawingsBannerKeys.banner), findsNothing);

          await _pick(tester, EntrySlot.ledger, 'Drawings');
          expect(find.byKey(EntryDrawingsBannerKeys.banner), findsOneWidget);

          // Switching back off Drawings clears it again — it only ever
          // narrates the instant the slot answers to the account (02 §10).
          await _pick(tester, EntrySlot.ledger, 'Diesel');
          expect(find.byKey(EntryDrawingsBannerKeys.banner), findsNothing);
          await _unmount(tester);
        },
      );

      testWidgets('F1-07-59 EN/PA/HI copy, and Save is offered', (
        tester,
      ) async {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          final s = await seedSoloLedger();
          await _addDrawings(s);
          await _pumpEntry(
            tester,
            kind: EntryKind.moneyOut,
            seeded: s,
            locale: locale,
            size: const Size(360, 800),
          );
          final l10n = _l10n(tester);
          await _typeAmount(tester, '500');
          await tester.tap(find.text('Cash in hand').first);
          await tester.pump();
          await _pick(tester, EntrySlot.ledger, 'Drawings');

          expect(find.byKey(EntryDrawingsBannerKeys.banner), findsOneWidget);
          expect(
            find.text(l10n.entryDrawingsConfirmation),
            findsOneWidget,
            reason: '$locale banner copy resolves from ARB',
          );
          // A drawing is a complete Money out entry: the verb, the amount and
          // both slots are answered, so Save is live (07 §5 step 6).
          expect(_saveEnabled(tester), isTrue);
          await _unmount(tester);
        }
      });

      // The screen calls the one `ledger.moneyOut` every Money out entry uses
      // (s2_add_entry_screen.dart `_save`); `core_ledger` admits a
      // `SystemRole.drawings` debit on `money_out` on both the verb and the
      // `checkShape` side (A-09b-4, ADR 2026-09-09b §3).
      testWidgets(
        'F1-07-59 a drawing posts through moneyOut, unchanged (02 §10 🔒)',
        (tester) async {
          final s = await seedSoloLedger();
          await _addDrawings(s);
          final before = await _balances(tester, s);
          await _pumpEntry(
            tester,
            kind: EntryKind.moneyOut,
            seeded: s,
            size: const Size(360, 800),
          );
          await _typeAmount(tester, '500');
          await tester.tap(find.text('Cash in hand').first);
          await tester.pump();
          await _pick(tester, EntrySlot.ledger, 'Drawings');
          expect(_saveEnabled(tester), isTrue);
          await tester.tap(find.byKey(AddEntryKeys.save));
          await _settleIo(tester);

          // The same `moneyOut` verb every Money out entry uses — the banner
          // only narrates the posting, never changes it (02 §10 🔒).
          expect((await _kinds(tester, s)).first, 'money_out');
          final after = await _balances(tester, s);
          expect(after[s.cashId], before[s.cashId]! - 50000);
          await _unmount(tester);
        },
      );

      testWidgets('F1-07-59 EN/PA/HI at 200 % on 360×800 — no overflow', (
        tester,
      ) async {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          final s = await seedSoloLedger();
          await _addDrawings(s);
          await _pumpEntry(
            tester,
            kind: EntryKind.moneyOut,
            seeded: s,
            locale: locale,
            textScale: 2.0,
            size: const Size(360, 800),
          );
          await _pick(tester, EntrySlot.ledger, 'Drawings');
          expect(find.byKey(EntryDrawingsBannerKeys.banner), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '$locale drawings banner at 200 % on 360×800',
          );
          // 07 §5 🔒 "never scrolls" governs the *body* of the entry screen:
          // the amount, the verb pill and the slots stay put however far the
          // text scales. Regions that have always scrolled inside themselves
          // — the picker's account list, and at 200 % the banner's own
          // sentence — are not the screen moving, so the rule is asserted
          // where it is actually made: nothing scrolls the amount.
          expect(
            find.ancestor(
              of: find.byKey(AddEntryKeys.amount),
              matching: find.byType(Scrollable),
            ),
            findsNothing,
            reason: 'the entry body scrolled: $locale',
          );
          await _unmount(tester);
        }
      });
    },
  );

  group('F1-07-13 07 §1 global design rules, bound to S2', () {
    testWidgets(
      'F1-07-13 nothing pre-selected; an unmatched search still offers '
      'create, never a dead end (07 §1 rules 1 and 6)',
      (tester) async {
        await _pumpEntry(tester, kind: EntryKind.moneyIn);
        final l10n = _l10n(tester);
        // Rule 1 ("every design decision loses to this"): a fresh screen
        // asks nothing on your behalf — the ADR 2026-09-05f §C reading F1-07-17
        // already covers slot-by-slot; here it is the *screen-level* claim
        // 07 §1 makes, so it is asserted again under this id.
        expect(find.text(l10n.entrySlotChoose), findsNWidgets(2));
        expect(_saveEnabled(tester), isFalse);
        expect(
          tester
              .widgetList<EntryAccountChip>(find.byType(EntryAccountChip))
              .every((c) => !c.selected),
          isTrue,
        );

        // Rule 6, inside S2's own picker (S2.1): a search that matches
        // nothing never strands the user — it offers inline create.
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(AddEntryKeys.search),
          'Something nobody has',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(AddEntryKeys.create), findsOneWidget);
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-07-13 colour is never the only signal: the preview\'s muted/ink '
      'states pair with placeholder dots vs real account names (07 §1 rule 3)',
      (tester) async {
        await _pumpEntry(tester, kind: EntryKind.moneyOut);
        final ctx = tester.element(find.byType(AddEntryScreen));
        final muted = RkStatusColors.of(ctx).muted;

        // Incomplete: muted colour, and the sentence itself carries the gap
        // as written dots, never a blank colour swatch (07 §5.5 🔒).
        expect(_previewColor(tester), muted);
        expect(find.textContaining('⋯'), findsWidgets);

        await _typeAmount(tester, '500');
        await tester.tap(find.text('Cash in hand'));
        await tester.pump();
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Diesel').last);
        await tester.pumpAndSettle();

        // Complete: the colour changes, but never alone — the dots are
        // replaced by the real account names in the same instant (07 §5.5
        // "completion is the validation" 🔒).
        expect(_previewColor(tester), isNot(muted));
        expect(find.textContaining('⋯'), findsNothing);
        expect(find.textContaining('Diesel'), findsWidgets);
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-07-13 the shortest complete Money in entry reaches Save in ≤ 8 '
      'taps — the ui-screen contract\'s F1 proxy for the 8-second budget '
      '(07 §1 rule 1, 07 §5 🔒)',
      (tester) async {
        // What this proves and what it does not: a widget test has no clock
        // a person would recognise as honest, so this counts *interactions*
        // (taps) and confirms none of them is a blocking step (a modal, a
        // forced question, a route push) — never wall-clock seconds. The
        // ui-screen skill's own contract for S2 is "tap sequence completes in
        // ≤ 8 steps"; the actual stopwatch is F2, run on the device lab at
        // RC (09 §preamble suite F).
        final s = await seedSoloLedger();
        await _pumpEntry(tester, kind: EntryKind.moneyIn, seeded: s);
        var taps = 0;
        Future<void> tap(Finder finder) async {
          await tester.tap(finder);
          await tester.pump();
          taps++;
        }

        // ₹500 — 3 digit taps, no `+` or `.` needed for the shortest case.
        for (final k in '500'.split('')) {
          await tap(find.byKey(AddEntryKeys.pad(k)));
        }
        // INTO: a chip, no picker (07 §5 step 2 🔒).
        await tap(find.text('Cash in hand'));
        // FROM: opens in place (no sheet, no route — 07 §5 single-screen 🔒)
        // and the seeded income account is already a candidate row, so no
        // search is needed for the shortest path.
        await tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tap(find.text('Shop sales').last);
        await tester.pumpAndSettle();
        expect(_saveEnabled(tester), isTrue);
        await tap(find.byKey(AddEntryKeys.save));

        expect(
          taps,
          lessThanOrEqualTo(8),
          reason:
              '$taps taps for the shortest complete Money in entry — the '
              'ui-screen S2 contract caps this at 8',
        );
        await _unmount(tester);
      },
    );
  });
}
