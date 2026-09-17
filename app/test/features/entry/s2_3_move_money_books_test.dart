// S2.3 Move money **between books** (07 §5 🔒 → 07 §10 🔒, 02 §6 🔒,
// 13 §3.2 row S2.3 *Transfer (within/between books)*, ADR 2026-09-03b).
//
//   F1-07-118 the TO chooser offers the other books this device holds beside
//             this book's money accounts; choosing one keeps the amount and
//             lists that book's money accounts; no other verb or slot is
//             offered a book, and a solo install is offered none.
//   F1-07-119 Save posts BOTH halves through `transferBetweenBooks` — two
//             envelopes, one `refs.transfer_group`, the `Due to/from` pair
//             auto-created with the localised name, integer paise — while the
//             within-book transfer still posts its single entry unchanged.
//   F1-07-120 a refusal is shown in words, never as a raw enum, and the draft
//             (amount and both sides) survives it.
//   F1-07-121 the stopwatch: the between-books path costs exactly one tap
//             more than the within-book one, and the whole flow holds in
//             EN/PA/HI at 200 % on 360×800 — 13 §4.3's states included.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/entry_books.dart';
import 'package:rukka_folio/features/entry/entry_refusal.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/entry/widgets/entry_date_picker.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

int _pumpSeq = 0;

/// A seeded solo book plus a second book this device also holds — the only
/// case 02 §6 calls reconcilable, and the one the chooser is built for.
final class _TwoBooks {
  const _TwoBooks(this.s, this.familyId, this.familyCashId, this.familyName);

  final SeededLedger s;
  final String familyId;
  final String familyCashId;
  final String familyName;

  /// The destination book's cash A/C, named apart from the source book's so a
  /// tap in the test can only mean one of them.
  static const familyCashName = 'Family Cash';
}

Future<_TwoBooks> _seedTwoBooks() async {
  final s = await seedSoloLedger();
  const name = 'Sharma Family';
  final familyId = await s.ledger.createBook(
    name: name,
    type: BookType.family,
    cashName: _TwoBooks.familyCashName,
  );
  final cash = (await s.ledger.chartOf(familyId))
      .byClass(AccountClass.money)
      .firstWhere((a) => a.name == _TwoBooks.familyCashName);
  return _TwoBooks(s, familyId, cash.id, name);
}

Future<void> _pumpEntry(
  WidgetTester tester,
  SeededLedger s, {
  EntryKind kind = EntryKind.transfer,
  Locale? locale,
  double textScale = 1,
  Size? viewport,
}) async {
  await pumpRk(
    tester,
    AddEntryScreen(
      key: ValueKey('move-${_pumpSeq++}'),
      bookId: s.bookId,
      kind: kind,
    ),
    ledger: s.ledger,
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
}

/// Tears the tree down *inside* the test: cancelling drift's query streams
/// schedules zero-duration timers, and only a pump inside the test fires them
/// before the binding's pending-timer invariant runs.
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

/// A tap that also counts: the stopwatch of F1-07-121 is an interaction
/// count, the honest F1 proxy for 07 §1 rule 1's eight seconds.
final class _Taps {
  int count = 0;

  Future<void> tap(WidgetTester tester, Finder f) async {
    count++;
    await tester.tap(f);
    await tester.pumpAndSettle();
  }
}

/// Real event-loop turns: a ledger write started from a tap is sqlite I/O and
/// `pumpAndSettle` only turns the fake clock.
Future<void> _settleIo(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<List<QueryRowLike>> _entries(WidgetTester tester, SeededLedger s) async {
  final rows = (await tester.runAsync(
    () => s.ledger.db
        .customSelect(
          'SELECT id, book_id, kind, transfer_group FROM entries_p '
          'ORDER BY hlc DESC, id DESC',
        )
        .get(),
  ))!;
  return [
    for (final r in rows)
      QueryRowLike(
        r.read<String>('id'),
        r.read<String>('book_id'),
        r.read<String>('kind'),
        r.read<String?>('transfer_group'),
      ),
  ];
}

final class QueryRowLike {
  const QueryRowLike(this.id, this.bookId, this.kind, this.transferGroup);

  final String id;
  final String bookId;
  final String kind;
  final String? transferGroup;
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  group('F1-07-118 the TO chooser offers books beside accounts', () {
    testWidgets(
      'F1-07-118 Move money lists the other books this device holds under '
      'their own heading, and choosing one keeps the amount and swaps the '
      'list to that book\'s money accounts (13 §3.2 row S2.3, 07 §10 🔒)',
      (tester) async {
        final two = await _seedTwoBooks();
        await _pumpEntry(tester, two.s);
        final l10n = _l10n(tester);

        await _typeAmount(tester, '5000');
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();

        // This book's money accounts AND the other book, side by side.
        expect(find.text('Cash in hand'), findsWidgets);
        expect(find.text(l10n.entryMoveBooksHeader), findsOneWidget);
        expect(find.byKey(AddEntryKeys.book(two.familyId)), findsOneWidget);

        await tester.tap(find.byKey(AddEntryKeys.book(two.familyId)));
        await tester.pumpAndSettle();

        // The amount survives the switch (07 §5: the pill and the chooser
        // never cost the member the digits already typed).
        expect(find.textContaining('₹5,000'), findsWidgets);
        // The list is now the destination book's, and says so.
        expect(find.byKey(AddEntryKeys.bookBack), findsOneWidget);
        expect(find.text(two.familyName), findsWidgets);
        expect(find.byKey(AddEntryKeys.book(two.familyId)), findsNothing);
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-07-118 a book is offered on Move money\'s TO slot alone — never on '
      'FROM, never on another verb, and never on a solo install',
      (tester) async {
        final two = await _seedTwoBooks();

        // FROM, on the same verb: money accounts only.
        await _pumpEntry(tester, two.s);
        final l10n = _l10n(tester);
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.money)));
        await tester.pumpAndSettle();
        expect(find.text(l10n.entryMoveBooksHeader), findsNothing);
        expect(find.byKey(AddEntryKeys.book(two.familyId)), findsNothing);
        await _unmount(tester);

        // Another verb's ledger slot: a category or a person, never a book.
        for (final kind in [
          EntryKind.moneyIn,
          EntryKind.moneyOut,
          EntryKind.gaveCredit,
          EntryKind.tookCredit,
        ]) {
          await _pumpEntry(tester, two.s, kind: kind);
          await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
          await tester.pumpAndSettle();
          expect(
            find.byKey(AddEntryKeys.book(two.familyId)),
            findsNothing,
            reason: '${kind.wire} has no book destination',
          );
          await _unmount(tester);
        }

        // Solo install: one book, so nothing to offer and S2.3 is exactly the
        // within-book transfer it has always been.
        final solo = await seedSoloLedger();
        await _pumpEntry(tester, solo);
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        expect(find.text(_l10n(tester).entryMoveBooksHeader), findsNothing);
        await _unmount(tester);
      },
    );

    test(
      'F1-07-118 the chooser\'s book list is every held book but this one',
      () {
        const all = [
          EntryBook(id: 'b1', name: 'Me'),
          EntryBook(id: 'b2', name: 'Sharma Family'),
          EntryBook(id: 'b3', name: 'Kirana Store'),
        ];
        expect(otherBooks(all, 'b1').map((b) => b.id), ['b2', 'b3']);
        expect(otherBooks(all, 'b2').map((b) => b.id), ['b1', 'b3']);
        expect(
          otherBooks(const [EntryBook(id: 'b1', name: 'Me')], 'b1'),
          isEmpty,
        );
        expect(bookOf(all, 'b2')?.name, 'Sharma Family');
        expect(bookOf(all, null), isNull);
        expect(bookOf(all, 'gone'), isNull);
      },
    );
  });

  group('F1-07-119 both halves post (02 §6 🔒, 07 §10 🔒)', () {
    testWidgets('F1-07-119 Save appends one envelope per book sharing one '
        'refs.transfer_group, with the Due to/from pair auto-created on first '
        'use and the amount in integer paise', (tester) async {
      final two = await _seedTwoBooks();
      await _pumpEntry(tester, two.s);

      await _typeAmount(tester, '5000');
      // The FROM side from its chip row — 07 §5 step 2's three most-used
      // money accounts, the one-tap path the shopkeeper takes.
      await tester.tap(find.text('SBI Saving').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddEntryKeys.book(two.familyId)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_TwoBooks.familyCashName).last);
      await tester.pumpAndSettle();

      expect(_saveEnabled(tester), isTrue);
      await tester.tap(find.byKey(AddEntryKeys.save));
      await _settleIo(tester);

      final rows = await _entries(tester, two.s);
      final pair = [
        for (final r in rows)
          if (r.transferGroup != null) r,
      ];
      expect(pair, hasLength(2), reason: 'one action, two envelopes');
      expect(pair.first.transferGroup, pair.last.transferGroup);
      expect({for (final r in pair) r.bookId}, {two.s.bookId, two.familyId});

      // The figures, straight off the projection — integer paise, both
      // sides, and the `Due to/from` pair carrying the localised default.
      final mine = (await tester.runAsync(
        () => two.s.ledger.watchAccounts(two.s.bookId).first,
      ))!;
      final theirs = (await tester.runAsync(
        () => two.s.ledger.watchAccounts(two.familyId).first,
      ))!;
      final myDue = mine.firstWhere(
        (a) => a.account.systemRole == SystemRole.dueToFrom,
      );
      final theirDue = theirs.firstWhere(
        (a) => a.account.systemRole == SystemRole.dueToFrom,
      );
      expect(myDue.balancePaise, 5_000_00);
      expect(theirDue.balancePaise, -5_000_00);
      expect(myDue.account.name, contains(two.familyName));
      expect(theirDue.account.name, contains('Me'));
      expect(
        theirs.firstWhere((a) => a.account.id == two.familyCashId).balancePaise,
        5_000_00,
      );
      await _unmount(tester);
    });

    testWidgets(
      'F1-07-119 the within-book transfer keeps its own path: one entry, one '
      'book, no transfer group, no Due to/from account minted',
      (tester) async {
        final two = await _seedTwoBooks();
        await _pumpEntry(tester, two.s);

        await _typeAmount(tester, '100000');
        // The FROM side from its chip row — 07 §5 step 2's three most-used
        // money accounts, the one-tap path the shopkeeper takes.
        await tester.tap(find.text('SBI Saving').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cash in hand').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.save));
        await _settleIo(tester);

        final rows = await _entries(tester, two.s);
        expect(rows.where((r) => r.transferGroup != null), isEmpty);
        expect(rows.first.bookId, two.s.bookId);
        expect(rows.first.kind, EntryKind.transfer.wire);
        final mine = (await tester.runAsync(
          () => two.s.ledger.watchAccounts(two.s.bookId).first,
        ))!;
        expect(
          mine.where((a) => a.account.systemRole == SystemRole.dueToFrom),
          isEmpty,
        );
        await _unmount(tester);
      },
    );
  });

  group('F1-07-120 a refusal in words, and the draft survives', () {
    test(
      'F1-07-120 every InterBookRefusal has a sentence in EN, PA and HI, and '
      'none of them is the engine\'s symbol (07 §1 rule 6 🔒)',
      () async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final refusal in InterBookRefusal.values) {
            final message = interBookRefusalMessage(l10n, refusal);
            expect(message.trim(), isNotEmpty);
            expect(
              message.toLowerCase(),
              isNot(contains(refusal.name.toLowerCase())),
              reason: '${locale.languageCode}: ${refusal.name} is not a word',
            );
            expect(message, isNot(contains('InterBook')));
          }
        }
      },
    );

    testWidgets(
      'F1-07-120 the chooser cannot build a movement the engine refuses: '
      'every book row is a book this device holds and every destination row '
      'is a money account of it (02 §6 🔒, 04 §5.2)',
      (tester) async {
        final two = await _seedTwoBooks();
        await _pumpEntry(tester, two.s);

        await _typeAmount(tester, '5000');
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();

        // The rows come from `books_p`, which is the projection of the books
        // whose envelopes this device holds — so `bookNotHeld` has no row to
        // come from, and this book is not among them, so neither has
        // `sameBook`.
        final held = (await tester.runAsync(
          () => two.s.ledger.mirror.bookIds(),
        ))!;
        expect(held, contains(two.familyId));
        expect(find.byKey(AddEntryKeys.book(two.s.bookId)), findsNothing);

        await tester.tap(find.byKey(AddEntryKeys.book(two.familyId)));
        await tester.pumpAndSettle();
        final chart = (await tester.runAsync(
          () => two.s.ledger.chartOf(two.familyId),
        ))!;
        for (final a in chart.accounts) {
          if (a.accountClass == AccountClass.money) continue;
          expect(
            find.text(a.name).evaluate(),
            isEmpty,
            reason: '${a.name} is not a money A/C (07 §10)',
          );
        }
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-07-120 a save the engine refuses keeps the whole draft and appends '
      'nothing — a sentence, never an exception (07 §1 rule 6 🔒)',
      (tester) async {
        final two = await _seedTwoBooks();
        final before = await _entries(tester, two.s);
        // A viewport tall enough that the whole calendar renders: the lower
        // region is deliberately short on a phone, and this case is about the
        // save path, not about the calendar's own layout (F1-07-58 owns that).
        await _pumpEntry(tester, two.s, viewport: rkTallViewport);

        await _typeAmount(tester, '5000');
        // The FROM side from its chip row — 07 §5 step 2's three most-used
        // money accounts, the one-tap path the shopkeeper takes.
        await tester.tap(find.text('SBI Saving').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.book(two.familyId)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_TwoBooks.familyCashName).last);
        await tester.pumpAndSettle();

        // A day before this book's own books begin (ADR 2026-09-09d §4): the
        // paying half is refused first, so nothing at all is appended.
        await tester.tap(find.byKey(AddEntryKeys.dateChip));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(EntryDatePickerKeys.prevMonth));
        await tester.pumpAndSettle();
        final beforeStart = two.s.ledger.today().addDays(-8);
        await tester.tap(find.byKey(EntryDatePickerKeys.day(beforeStart)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.save));
        await _settleIo(tester);

        final l10n = _l10n(tester);
        final snack = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data ?? '')
            .join(' ');
        expect(snack, contains(l10n.entrySaveError));
        expect(snack, isNot(contains('Exception')));
        expect(snack, isNot(contains('InterBook')));
        expect(snack, isNot(contains('PostRejected')));

        // The draft is whole: the amount, both sides and the date chip.
        expect(find.textContaining('₹5,000'), findsWidgets);
        expect(find.text('SBI Saving'), findsWidgets);
        expect(find.textContaining(two.familyName), findsWidgets);
        expect(_saveEnabled(tester), isTrue);

        // And nothing was written — neither half of the pair.
        final after = await _entries(tester, two.s);
        expect(after.length, before.length);
        expect(after.where((r) => r.transferGroup != null), isEmpty);
        await _unmount(tester);
      },
    );
  });

  group('F1-07-121 the stopwatch, and 200 % on 360×800', () {
    testWidgets(
      'F1-07-121 the between-books path costs exactly one tap more than the '
      'within-book one (07 §1 rule 1, the F1 interaction-count proxy)',
      (tester) async {
        final two = await _seedTwoBooks();

        // Within one book: TO slot → account.
        await _pumpEntry(tester, two.s);
        await _typeAmount(tester, '5000');
        // The FROM side from its chip row — 07 §5 step 2's three most-used
        // money accounts, the one-tap path the shopkeeper takes.
        await tester.tap(find.text('SBI Saving').first);
        await tester.pumpAndSettle();
        final within = _Taps();
        await within.tap(
          tester,
          find.byKey(AddEntryKeys.slot(EntrySlot.ledger)),
        );
        await within.tap(tester, find.text('Cash in hand').last);
        expect(_saveEnabled(tester), isTrue);
        await _unmount(tester);

        // Between books: TO slot → book → account.
        await _pumpEntry(tester, two.s);
        await _typeAmount(tester, '5000');
        // The FROM side from its chip row — 07 §5 step 2's three most-used
        // money accounts, the one-tap path the shopkeeper takes.
        await tester.tap(find.text('SBI Saving').first);
        await tester.pumpAndSettle();
        final between = _Taps();
        await between.tap(
          tester,
          find.byKey(AddEntryKeys.slot(EntrySlot.ledger)),
        );
        await between.tap(tester, find.byKey(AddEntryKeys.book(two.familyId)));
        await between.tap(tester, find.text(_TwoBooks.familyCashName).last);
        expect(_saveEnabled(tester), isTrue);

        expect(
          between.count - within.count,
          1,
          reason: '07 §10 costs one more tap than the within-book transfer',
        );
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-07-121 EN, PA and HI at 200 % on 360×800: the chooser, the book '
      'list and both slot values fit, and nothing is cut',
      (tester) async {
        for (final locale in rkLocales) {
          final two = await _seedTwoBooks();
          await _pumpEntry(
            tester,
            two.s,
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expectTextFits(
            tester,
            reason: '${locale.languageCode} · book chooser at 200 %',
          );
          await tester.tap(find.byKey(AddEntryKeys.book(two.familyId)));
          await tester.pumpAndSettle();
          await tester.tap(find.text(_TwoBooks.familyCashName).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expectTextFits(
            tester,
            reason: '${locale.languageCode} · book + A/C slot at 200 %',
          );
          await _unmount(tester);
        }
      },
    );

    testWidgets(
      'F1-07-121 13 §4.3 states: leaving the chosen book is one tap and '
      'clears the destination, and switching the pill drops it entirely — no '
      'dead end, nothing carried over (07 §1 rule 6 🔒, 07 §5 🔒)',
      (tester) async {
        final two = await _seedTwoBooks();
        await _pumpEntry(tester, two.s);
        final l10n = _l10n(tester);

        await _typeAmount(tester, '5000');
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.book(two.familyId)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_TwoBooks.familyCashName).last);
        await tester.pumpAndSettle();
        expect(find.textContaining(two.familyName), findsWidgets);

        // Back out of the book: the destination goes, the amount stays.
        await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(AddEntryKeys.bookBack));
        await tester.pumpAndSettle();
        expect(find.byKey(AddEntryKeys.book(two.familyId)), findsOneWidget);
        expect(find.textContaining('₹5,000'), findsWidgets);
        expect(_saveEnabled(tester), isFalse);

        // Switching the pill drops the destination with the slots.
        await tester.tap(find.text(verbLabel(l10n, EntryKind.moneyOut)));
        await tester.pumpAndSettle();
        expect(find.text(l10n.entrySlotChoose), findsNWidgets(2));
        expect(find.textContaining(two.familyName), findsNothing);
        await _unmount(tester);
      },
    );
  });
}
