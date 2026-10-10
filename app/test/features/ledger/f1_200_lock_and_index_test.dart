// FIX200 slice L — PLAN desk 200 (a) and (b), found by the RESKIN1 round-2
// audit (design/match/S4.1.json, design/match/S3.json).
//
// (a) S4.1 in a locked month. 02 §5 🔒: *"Locked period: amendment is
//     forbidden by rule. The only path: reversal — an auto-built mirror entry
//     dated in the open period … One guided flow: 'Fix an old entry'."* So an
//     entry dated in a locked month offers *Fix this entry* (the reversal,
//     dated today) and shows *Correct this* disabled with its reason
//     (13 §4.3 disabled-with-reason; 07 §1 rule 6 no dead ends).
// (b) S3 ledger index. The filter chips are not cut (13 §8, 07 §1 rule 9 —
//     200 % on 360×800, EN/PA/HI), and every balance carries its true side in
//     words: S3 is a ledger, a professional surface, so Dr/Cr is shown plainly
//     (ADR 2026-10-10b §4 🔒) — never by colour alone (07 §1 rule 3 🔒).
//
// TEST HONESTY: S4.1 is built exactly as `ledgerRoutes` builds it
// (`EntryDetailScreen(entryId:, onOpenEntry:)` under the real LedgerScope) and
// the lock is a real `lockMonth` envelope on a real ledger — nothing hands the
// screen a `canAmend`. Remove the lock lookup from `loadEntryDetail` and
// F1-200-1 fails. S3 is built as `ledgerRoot` builds it.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' show GoRouterState;
import 'package:rukka_folio/features/ledger/entry_detail.dart';
import 'package:rukka_folio/features/ledger/ledger_routes.dart';
import 'package:rukka_folio/features/ledger/screens/s3_ledger_index_screen.dart';
import 'package:rukka_folio/features/ledger/screens/s4_1_entry_detail_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/format/money_format.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// The book's start is 31 Aug (testNow 7 Sep − 7 days): an entry on that day,
/// in August, which then closes.
Future<(SeededLedger, Entry)> _augustEntry({bool lock = true}) async {
  final seed = await seedSoloLedger();
  final l = seed.ledger;
  final august = await l.moneyOut(
    bookId: seed.bookId,
    from: seed.cashId,
    forWhat: seed.fuelId,
    paise: 240_000,
    date: l.today().addDays(-7),
    note: 'Isuzu, full tank',
  );
  if (lock) {
    await l.lockMonth(
      seed.bookId,
      YearMonth(2026, 8),
      declaredBalances: const {},
    );
  }
  return (seed, august);
}

/// What `ledgerRoutes` builds for `LedgerPaths.entry`: both callbacks
/// wired. [onEnterAgain] records the verb S2 would open on; F1-200-7 drives
/// the real router instead.
Widget _s41(String id, {void Function(EntryKind kind)? onEnterAgain}) =>
    EntryDetailScreen(
      entryId: id,
      onOpenEntry: (_) {},
      onEnterAgain: onEnterAgain ?? (_) {},
    );

/// Exactly what `ledgerRoot` builds for the Ledger tab.
Widget _s3() => LedgerIndexScreen(onOpenAccount: (_) {}, onOpenSearch: () {});

FilledButton _filled(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

OutlinedButton _outlined(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label));

/// Fails when a chip's label is drawn outside the strip that shows it, or is
/// laid out shorter than its own line — the vertical cut `expectTextFits`
/// (which measures width) does not see.
void _expectChipsUncut(WidgetTester tester, String where) {
  final chips = find.byType(ChoiceChip);
  expect(chips, findsNWidgets(LedgerFilter.values.length));
  final strip = tester.renderObject<RenderBox>(
    find.ancestor(of: chips.first, matching: find.byType(Scrollable)).first,
  );
  final stripTop = strip.localToGlobal(Offset.zero).dy;
  final stripBottom = stripTop + strip.size.height;
  for (final e in chips.evaluate()) {
    final para = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byWidget(e.widget),
        matching: find.byType(RichText),
      ),
    );
    final top = para.localToGlobal(Offset.zero).dy;
    final bottom = top + para.size.height;
    final label = para.text.toPlainText();
    expect(
      para.size.height + 0.5 >= para.getMinIntrinsicHeight(para.size.width),
      isTrue,
      reason: '$where: chip "$label" laid out shorter than its line',
    );
    expect(
      top >= stripTop - 0.5 && bottom <= stripBottom + 0.5,
      isTrue,
      reason:
          '$where: chip "$label" spans ${top.toStringAsFixed(1)}–'
          '${bottom.toStringAsFixed(1)}, strip shows '
          '${stripTop.toStringAsFixed(1)}–${stripBottom.toStringAsFixed(1)}',
    );
  }
}

/// Every paragraph is laid out at least as tall as its own lines (the
/// letter bands included) — a fixed-height box cuts text at 200 %.
void _expectNoParagraphShortened(WidgetTester tester, String where) {
  final cut = <String>[];
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.hasSize && o.size.width > 0) {
      final need = o.getMinIntrinsicHeight(o.size.width);
      if (o.size.height + 0.5 < need) {
        cut.add('"${o.text.toPlainText()}" ${o.size.height} < $need');
      }
    }
    o.visitChildren(visit);
  }

  visit(tester.binding.rootElement!.renderObject!);
  expect(cut, isEmpty, reason: '$where: text cut vertically');
}

void main() {
  group('FIX200 (a) S4.1 in a locked month (02 §5 🔒, 02 §8 🔒)', () {
    testWidgets(
      'F1-200-1 an entry in a locked month offers Fix this entry and shows '
      'Correct this disabled with the reason; an open month offers both',
      (tester) async {
        rkViewport(tester, const Size(500, 2400));
        // Control: the same entry before August closes — both actions live.
        final (open, openEntry) = await _augustEntry(lock: false);
        await pumpRk(tester, _s41(openEntry.id), ledger: open.ledger);
        expect(_filled(tester, 'Correct this').onPressed, isNotNull);
        expect(_outlined(tester, 'Reverse this').onPressed, isNotNull);
        expect(find.text('Fix this entry'), findsNothing);
        expect(find.textContaining('is closed'), findsNothing);
        await _unmount(tester);

        // Locked: the real lock envelope, read through the production loader.
        final (seed, august) = await _augustEntry();
        await pumpRk(tester, _s41(august.id), ledger: seed.ledger);
        final detail = await tester.runAsync(
          () => loadEntryDetail(seed.ledger, august.id),
        );
        expect((detail! as EntryDetailPosted).inLockedPeriod, isTrue);

        expect(_filled(tester, 'Correct this').onPressed, isNull);
        // Disabled-with-reason (13 §4.3): the greyed button never stands
        // alone, and the reason names the month and the way out. EN months
        // are abbreviated (07 §1 rule 5 🔒), as on Home's close card.
        expect(
          find.text(
            'Aug is closed, so this entry can’t be changed. '
            'Fix it: reverse it today, then enter it again.',
          ),
          findsOneWidget,
        );
        // The frame's lock line (c2 *Locked period · Fix this entry*).
        expect(find.textContaining('Aug is closed ·'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        // The one path 02 §5 leaves open — never a dead end (07 §1 rule 6).
        expect(_outlined(tester, 'Fix this entry').onPressed, isNotNull);
        expect(find.text('Reverse this'), findsNothing);
        expect(
          find.text(
            'It is reversed today and you enter it again. '
            'Aug is not rewritten.',
          ),
          findsOneWidget,
        );
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-200-2 Fix this entry posts the reversal dated today in the open '
      'period, then hands the re-entry to the entry flow; the August entry '
      'is not rewritten',
      (tester) async {
        rkViewport(tester, const Size(500, 2400));
        final (seed, august) = await _augustEntry();
        final reentered = <EntryKind>[];
        await pumpRk(
          tester,
          _s41(august.id, onEnterAgain: reentered.add),
          ledger: seed.ledger,
        );

        await tester.tap(find.widgetWithText(OutlinedButton, 'Fix this entry'));
        await tester.pumpAndSettle();
        // The guided sheet names the flow and what it does (02 §5).
        expect(find.text('Fix this entry'), findsWidgets);
        expect(
          find.textContaining('Aug stays as it was closed'),
          findsOneWidget,
        );
        // 02 §5 🔒: the reversal *plus* the corrected re-entry — the sheet
        // says both steps, and its button does both.
        expect(
          find.textContaining('Then you enter it again with the right figures'),
          findsOneWidget,
        );
        expect(reentered, isEmpty);
        await tester.tap(find.text('Reverse it, then enter again'));
        await tester.pumpAndSettle();
        expect(reentered, [EntryKind.moneyOut]);

        final row = (await tester.runAsync(
          () => seed.ledger.db
              .customSelect(
                'SELECT id, accounting_date FROM entries_p WHERE reverses = ?',
                variables: [Variable.withString(august.id)],
              )
              .getSingle(),
        ))!;
        final reversal = (await tester.runAsync(
          () => seed.ledger.entry(row.read<String>('id')),
        ))!;
        expect(reversal.date, seed.ledger.today());
        // Integer paise, every line the mirror of the original's.
        final original = (await tester.runAsync(
          () => seed.ledger.entry(august.id),
        ))!;
        expect(original.date, LocalDate(2026, 8, 31));
        expect(
          {for (final l in reversal.lines) l.accountId: l.amount.raw},
          {for (final l in original.lines) l.accountId: -l.amount.raw},
        );
        await tester.pumpAndSettle();
        expect(find.text('Reversed'), findsOneWidget);
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-200-3 the engine itself refuses an amendment into a locked month '
      '(LocalLedger.amend → amendInLockedPeriod)',
      (tester) async {
        final (seed, august) = await _augustEntry();
        final refused = await tester.runAsync(() async {
          try {
            await seed.ledger.amend(august.id, note: 'changed');
            return null;
          } on PostRejected catch (e) {
            return e;
          }
        });
        expect(refused, isNotNull);
        expect(
          refused!.violations.map((v) => v.kind),
          contains(ViolationKind.amendInLockedPeriod),
        );
      },
    );

    testWidgets(
      'F1-200-7 through the real router: Fix this entry posts the reversal '
      'and opens S2 on the entry\'s own verb; back on S4.1 the reversed '
      'entry keeps the way to enter it again (02 §5 🔒, 07 §1 rule 6)',
      (tester) async {
        // ledgerRoutes supplies onEnterAgain; drop it and the push below never
        // happens, and this goes red.
        rkViewport(tester, const Size(500, 2400));
        final (seed, august) = await _augustEntry();
        final router = buildRouter(
          featureRoutes: ledgerRoutes,
          ledger: ledgerRoot,
          // A stand-in for S2 that shows the verb it was opened on.
          entry: (context) => Scaffold(
            body: Text(
              'S2 ${GoRouterState.of(context).uri.queryParameters['verb']}',
            ),
          ),
          initialLocation: LedgerPaths.entryOf(august.id),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          RkScope(
            db: seed.ledger.db,
            sync: FakeSyncClient(),
            auth: FakeAuthClient(),
            keys: seed.ledger.keys as FakeKeyStore,
            now: seed.ledger.now,
            child: LedgerScope(
              ledger: seed.ledger,
              child: MaterialApp.router(
                routerConfig: router,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: rkLocalizationsDelegates,
                theme: rkTheme(Brightness.light),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(EntryDetailScreen), findsOneWidget);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Fix this entry'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reverse it, then enter again'));
        await tester.pumpAndSettle();
        expect(
          router.state.uri.toString(),
          '${RkPaths.entry}?verb=${EntryKind.moneyOut.wire}',
        );
        expect(find.text('S2 money_out'), findsOneWidget);
        final reversals = (await tester.runAsync(
          () => seed.ledger.db
              .customSelect(
                'SELECT id FROM entries_p WHERE reverses = ?',
                variables: [Variable.withString(august.id)],
              )
              .get(),
        ))!;
        expect(reversals, hasLength(1));

        // The user backs out of S2: the reversed August entry is not a dead
        // end — it says what happened and offers the re-entry again.
        router.pop();
        await tester.pumpAndSettle();
        expect(find.byType(EntryDetailScreen), findsOneWidget);
        expect(
          find.textContaining(
            'If it still belongs in the books, enter it again',
          ),
          findsOneWidget,
        );
        final again = find.widgetWithText(OutlinedButton, 'Enter it again');
        expect(tester.widget<OutlinedButton>(again).onPressed, isNotNull);
        await tester.tap(again);
        await tester.pumpAndSettle();
        expect(
          router.state.uri.toString(),
          '${RkPaths.entry}?verb=${EntryKind.moneyOut.wire}',
        );
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      },
    );
  });

  group('FIX200 repair — S4.1 amend sheet dates (07 §5 step 4 🔒, 13 §8)', () {
    /// A September entry (open) in a book whose August is closed.
    Future<(SeededLedger, Entry)> septemberEntry({
      bool lockAugust = true,
    }) async {
      final seed = await seedSoloLedger();
      final l = seed.ledger;
      final september = await l.moneyOut(
        bookId: seed.bookId,
        from: seed.cashId,
        forWhat: seed.fuelId,
        paise: 120_000,
        date: l.today().addDays(-2),
        note: 'Diesel',
      );
      if (lockAugust) {
        await l.lockMonth(
          seed.bookId,
          YearMonth(2026, 8),
          declaredBalances: const {},
        );
      }
      return (seed, september);
    }

    testWidgets(
      'F1-200-8 the date picker greys closed months and future dates, and '
      'says why',
      (tester) async {
        rkViewport(tester, const Size(500, 2400));
        final (seed, september) = await septemberEntry();
        await pumpRk(tester, _s41(september.id), ledger: seed.ledger);
        await tester.tap(find.widgetWithText(FilledButton, 'Correct this'));
        await tester.pumpAndSettle();
        expect(
          find.text('Closed months and future dates can’t be picked.'),
          findsOneWidget,
        );
        await tester.tap(find.byIcon(Icons.event_outlined));
        await tester.pumpAndSettle();
        final picker = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        final today = seed.ledger.today();
        // Future dates disabled (07 §5 step 4 🔒; the engine refuses them).
        expect(picker.lastDate, DateTime(today.year, today.month, today.day));
        // Nothing before the books begin (ADR 2026-09-09d §4).
        expect(
          picker.firstDate.isBefore(DateTime(2026, 8, 31)),
          isFalse,
          reason: '${picker.firstDate}',
        );
        final selectable = picker.selectableDayPredicate!;
        // August is closed: greyed.
        expect(selectable(DateTime(2026, 8, 31)), isFalse);
        // September is open.
        expect(selectable(DateTime(2026, 9, 1)), isTrue);
        expect(
          selectable(DateTime(today.year, today.month, today.day)),
          isTrue,
        );
        await _unmount(tester);
      },
    );

    testWidgets(
      'F1-200-9 a date whose month closed while the sheet was open is refused '
      'with its named cause and the way out, never the generic error',
      (tester) async {
        rkViewport(tester, const Size(500, 2400));
        final (seed, september) = await septemberEntry(lockAugust: false);
        await pumpRk(tester, _s41(september.id), ledger: seed.ledger);
        await tester.tap(find.widgetWithText(FilledButton, 'Correct this'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.event_outlined));
        await tester.pumpAndSettle();
        // August is still open: 31 Aug is offered.
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('31'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        // Another device closes August meanwhile.
        await tester.runAsync(
          () => seed.ledger.lockMonth(
            seed.bookId,
            YearMonth(2026, 8),
            declaredBalances: const {},
          ),
        );
        await tester.tap(find.text('Save the correction'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Aug is closed, so nothing can be dated in it. '
            'Pick a date in an open month.',
          ),
          findsOneWidget,
        );
        expect(find.text("Couldn't save this correction"), findsNothing);
        // The entry itself is in an open month: the way out is another date,
        // not the locked-month reversal.
        expect(find.text('Fix an old entry'), findsNothing);
        // Nothing was posted.
        final head = (await tester.runAsync(
          () => seed.ledger.entry(september.id),
        ))!;
        expect(head.supersededBy, isNull);
        await _unmount(tester);
      },
    );
  });

  for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
    testWidgets(
      'F1-200-6 the locked-month footers (Fix this entry; Enter it again) '
      'fit at 200 % on 360×800 '
      '(${locale.languageCode})',
      (tester) async {
        final (seed, august) = await _augustEntry();
        await pumpRk(
          tester,
          _s41(august.id),
          ledger: seed.ledger,
          locale: locale,
          textScale: 2,
          viewport: const Size(360, 800),
        );
        expect(tester.takeException(), isNull);
        expectTextFits(tester, reason: locale.languageCode);
        // The footer's action is on screen without scrolling (07 §1 rule 2).
        final fix = find.byType(OutlinedButton).last;
        expect(fix, findsOneWidget);
        expect(tester.getRect(fix).bottom, lessThanOrEqualTo(800));
        expect(tester.widget<OutlinedButton>(fix).onPressed, isNotNull);
        await _unmount(tester);

        // After the fix: the re-entry footer (c2 *Reversed*) fits too.
        await tester.runAsync(
          () => seed.ledger.reverse(august.id, date: seed.ledger.today()),
        );
        await pumpRk(
          tester,
          _s41(august.id),
          ledger: seed.ledger,
          locale: locale,
          textScale: 2,
          viewport: const Size(360, 800),
        );
        expect(tester.takeException(), isNull);
        expectTextFits(tester, reason: '${locale.languageCode} re-entry');
        final again = find.byType(OutlinedButton).last;
        expect(tester.getRect(again).bottom, lessThanOrEqualTo(800));
        expect(tester.widget<OutlinedButton>(again).onPressed, isNotNull);
        await _unmount(tester);
      },
    );
  }

  group('FIX200 (b) S3 ledger index chips and sides (07 §1 🔒, ADR '
      '2026-10-10b §4 🔒)', () {
    for (final (locale, scale, size) in [
      (const Locale('en'), 1.0, const Size(390, 844)),
      (const Locale('en'), 2.0, const Size(360, 800)),
      (const Locale('pa'), 2.0, const Size(360, 800)),
      (const Locale('hi'), 2.0, const Size(360, 800)),
    ]) {
      final where = '${locale.languageCode} ${scale}x ${size.width.toInt()}';
      testWidgets('F1-200-4 the filter chips are never cut ($where)', (
        tester,
      ) async {
        final seed = await seedSoloLedger();
        await pumpRk(
          tester,
          _s3(),
          ledger: seed.ledger,
          locale: locale,
          textScale: scale,
          viewport: size,
        );
        _expectChipsUncut(tester, where);
        _expectNoParagraphShortened(tester, where);
        expectTextFits(tester, reason: where);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      });
    }

    testWidgets(
      'F1-200-5 every balance on S3 carries its true side in words — Dr or '
      'Cr — not colour alone',
      (tester) async {
        rkViewport(tester, const Size(400, 2400));
        final seed = await seedSoloLedger();
        final l = seed.ledger;
        final bharat = await l.addAccount(
          seed.bookId,
          name: 'Bharat Power',
          accountClass: AccountClass.party,
        );
        await l.tookCredit(
          bookId: seed.bookId,
          fromWhom: bharat.id,
          took: seed.fuelId,
          paise: 245_000,
          date: l.today().addDays(-4),
        );
        await pumpRk(tester, _s3(), ledger: l);

        // A supplier we owe: a Cr balance, written as such.
        expect(find.text('₹2,450 Cr'), findsOneWidget);
        final money = tester
            .widgetList<MoneyText>(find.byType(MoneyText))
            .toList();
        expect(money, isNotEmpty);
        for (final m in money) {
          expect(m.vocabulary, Vocabulary.professional);
          expect(
            m.showDirection,
            isTrue,
            reason: '₹${m.paise} is tinted by side, so its side is in words',
          );
        }
        // Every non-zero figure on the list has its word, Dr or Cr.
        final figures = tester
            .widgetList<RichText>(
              find.descendant(
                of: find.byType(MoneyText),
                matching: find.byType(RichText),
              ),
            )
            .map((r) => r.text.toPlainText())
            .where((t) => t != '₹0');
        expect(figures, isNotEmpty);
        expect(
          figures.every((t) => t.endsWith(' Dr') || t.endsWith(' Cr')),
          isTrue,
          reason: '$figures',
        );
        await _unmount(tester);
      },
    );
  });
}
