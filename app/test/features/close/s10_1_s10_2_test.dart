// F1-07-143…148: **S10.1** the family close status and **S10.2** the month
// summary card (07 §13 🔒 bullets 4 and 6; 13 §3.2 rows S10.1 and S10.2;
// 13 §4.3 states).
//
// Both are parts of S10, so both are pumped through the wizard over the
// feature-local [FakeCloseSource] — the same seam the real implementation
// satisfies, so what these assert is the contract and not a stub's habits.
//
// The two rules easiest to break silently are asserted **structurally**:
//
//   * S10.1 is **multi-book only** (07 §13 🔒). A one-entry list draws no
//     section at all, which is asserted by the absence of the section key —
//     not by the absence of a string that might simply have scrolled.
//   * S10.2 is a **reward, not a receipt** (07 §13 🔒). Once the lock lands
//     the declared-balances table is gone, which is asserted by the absence
//     of `CloseKeys.declared`.
//
// Consumer vocabulary throughout: *Money in / Money out*, never Dr/Cr
// (02 §10 🔒, CLAUDE.md rule 9). Every amount is synthetic (rule 4) and
// integer paise (rule 1).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/close/close_routes.dart';
import 'package:rukka_folio/features/close/widgets/close_parts.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/format/date_format.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../../shared/test_app.dart';

// ---- fixtures ---------------------------------------------------------------

final august = YearMonth(2026, 8);
final july = YearMonth(2026, 7);

const galla = CloseCashAccount(
  accountId: 'galla',
  name: 'Galla',
  bookBalance: Paise(250000),
  countedInPeriod: true,
);

const sbi = CloseBankAccount(
  accountId: 'sbi',
  name: 'SBI Saving',
  bookBalance: Paise(11460000),
);

CloseView view({CloseTray tray = const CloseTray()}) => CloseView(
  bookId: 'book-1',
  bookName: 'Kirana',
  period: august,
  cashAccounts: const [galla],
  bankAccounts: const [sbi],
  tray: tray,
  progress: const CloseProgress(step: CloseStep.confirmAndLock),
);

/// The 07 §13 🔒 line itself: *"Kirana closed ✓ · Agriculture waiting on
/// Pankaj · Joint pool not started"*, plus the in-progress state the
/// *Resumable* rule implies.
final family = <BookCloseStatus>[
  BookCloseStatus(
    bookId: 'book-1',
    bookName: 'Kirana',
    period: august,
    state: BookCloseState.closed,
  ),
  BookCloseStatus(
    bookId: 'book-2',
    bookName: 'Agriculture',
    period: august,
    state: BookCloseState.waiting,
    waitingOn: 'Pankaj’s phone',
  ),
  BookCloseStatus(
    bookId: 'book-3',
    bookName: 'Joint pool',
    period: august,
    state: BookCloseState.notStarted,
  ),
  BookCloseStatus(
    bookId: 'book-4',
    bookName: 'Dairy',
    period: august,
    state: BookCloseState.inProgress,
    step: CloseStep.clearTray,
  ),
];

MonthSummary summary({
  Paise moneyIn = const Paise(17500000),
  Paise moneyOut = const Paise(13820000),
  List<MonthSummaryExpense> top = const [],
  List<SubFamilyTotal> families = const [],
}) => MonthSummary(
  bookId: 'book-1',
  bookName: 'Kirana',
  period: august,
  moneyIn: moneyIn,
  moneyOut: moneyOut,
  topExpenses: top,
  subFamilies: families,
);

int _pumpSeq = 0;

Future<void> pumpClose(
  WidgetTester tester,
  FakeCloseSource source, {
  Locale? locale,
  double textScale = 1,
  Size viewport = rkTallViewport,
}) async {
  await pumpRk(
    tester,
    MonthCloseScreen(
      key: ValueKey('s10-1-2-${_pumpSeq++}'),
      bookId: 'book-1',
      period: august,
      source: source,
      onDone: () {},
    ),
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
}

AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MonthCloseScreen)));

/// Takes the lock on step 4 and settles the summary that follows.
///
/// The action is scrolled to first: at 200 % on a 375 px phone step 4 is
/// taller than the screen, and a test that tapped a point outside the render
/// tree would report a layout defect as a missing widget.
Future<void> lock(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(CloseKeys.lock));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(CloseKeys.lock));
  await tester.pumpAndSettle();
}

void main() {
  // ── F1-07-143 · S10.1, the family's state, not just yours ──────────────────

  testWidgets(
    'F1-07-143 S10.1 gives every book of the family its own state, and a '
    'single-book tenant never sees the section at all',
    (tester) async {
      final source = FakeCloseSource(view: view())..statuses = family;
      await pumpClose(tester, source);
      final l = stringsOf(tester);

      expect(find.byKey(CloseKeys.family), findsOneWidget);
      expect(find.text(l.closeFamilyTitle), findsOneWidget);
      for (final name in const [
        'Kirana',
        'Agriculture',
        'Joint pool',
        'Dairy',
      ]) {
        expect(find.text(name), findsWidgets, reason: '$name has no row');
      }
      // Each state carries its own **word** — the tick and the tint are never
      // the only carriers (07 §1 rule 3).
      expect(find.text(l.closeFamilyStateClosed), findsOneWidget);
      expect(
        find.text(l.closeFamilyStateWaiting('Pankaj’s phone')),
        findsOneWidget,
      );
      expect(find.text(l.closeFamilyStateNotStarted), findsOneWidget);
      expect(find.text(l.closeFamilyStateInProgress), findsOneWidget);
      // Every row is one labelled node for a screen reader.
      for (final id in const ['book-1', 'book-2', 'book-3', 'book-4']) {
        expect(find.byKey(FamilyCloseKeys.row(id)), findsOneWidget);
      }

      // Single-book tenant: no section, no heading, no apology.
      final solo = FakeCloseSource(view: view())..statuses = [family.last];
      await pumpClose(tester, solo);
      expect(find.byKey(CloseKeys.family), findsNothing);
      expect(find.text(l.closeFamilyTitle), findsNothing);
      // The wizard itself is untouched.
      expect(find.byKey(CloseKeys.declared), findsOneWidget);
    },
  );

  // ── F1-07-144 · S10.1 never prints a device id; months lock in order ───────

  testWidgets(
    'F1-07-144 S10.1 says “another phone” rather than a device id, and names '
    'the month when a book is behind',
    (tester) async {
      final source = FakeCloseSource(view: view())
        ..statuses = [
          BookCloseStatus(
            bookId: 'book-1',
            bookName: 'Kirana',
            period: august,
            state: BookCloseState.notStarted,
          ),
          // No device name: `author_gaps.author_device` is an id and nothing
          // labels it (04 §3.4) — a uuid must never reach a shopkeeper.
          BookCloseStatus(
            bookId: 'book-2',
            bookName: 'Agriculture',
            period: july,
            state: BookCloseState.waiting,
          ),
        ];
      await pumpClose(tester, source);
      final l = stringsOf(tester);

      expect(
        find.text(l.closeFamilyStateWaiting(l.closeBlockedUnknownDevice)),
        findsOneWidget,
      );
      expect(find.textContaining('book-2'), findsNothing);
      // Months lock in order (02 §8.1 🔒): the book still on July says so, and
      // the book on this month does not repeat it.
      expect(
        find.text(l.closeFamilyMonth('${monthName(l, 7)} 2026')),
        findsOneWidget,
      );
      expect(
        find.text(l.closeFamilyMonth('${monthName(l, 8)} 2026')),
        findsNothing,
      );
    },
  );

  // ── F1-07-145 · S10.2 lands the moment the lock does ───────────────────────

  testWidgets(
    'F1-07-145 S10.2 replaces step 4 the moment the lock lands: three figures '
    'in consumer words, and no declared-balance table under them',
    (tester) async {
      final source = FakeCloseSource(view: view())
        ..summary = summary(
          moneyIn: const Paise(17500000),
          moneyOut: const Paise(13820000),
        );
      await pumpClose(tester, source);
      final l = stringsOf(tester);
      expect(find.byKey(CloseKeys.declared), findsOneWidget);

      await lock(tester);

      // The seam was asked for this book's month, once.
      expect(source.summariesAsked, ['book-1/2026-08']);
      expect(find.byKey(CloseKeys.summary), findsOneWidget);
      expect(find.byType(MonthSummaryCard), findsOneWidget);
      // A reward, not a receipt (07 §13 🔒).
      expect(find.byKey(CloseKeys.declared), findsNothing);
      // …and not a dead end either: the wizard's step footer is gone and the
      // one way out is on the card (07 §1 rule 6).
      expect(find.byKey(CloseKeys.next), findsNothing);
      expect(find.byKey(CloseKeys.back), findsNothing);
      expect(find.byKey(MonthSummaryKeys.done), findsOneWidget);

      // Consumer vocabulary, and the three figures 07 §13 🔒 names.
      expect(find.text(l.closeSummaryIn), findsOneWidget);
      expect(find.text(l.closeSummaryOut), findsOneWidget);
      expect(find.text(l.closeSummarySaved), findsOneWidget);
      expect(find.text('Dr'), findsNothing);
      expect(find.text('Cr'), findsNothing);
      // Integer paise, formatted by the house rule: in 1,75,000 · out
      // 1,38,200 · saved 36,800.
      expect(find.text('₹1,75,000'), findsOneWidget);
      expect(find.text('₹1,38,200'), findsOneWidget);
      expect(find.text('₹36,800'), findsOneWidget);
      // The month is still reported as locked — the reward replaces the
      // receipt, it does not hide the fact.
      expect(
        find.text(l.closeLockDone('${monthName(l, 8)} 2026')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'F1-07-145 a month that spent more than it earned says so in words, not '
    'in the minus sign alone',
    (tester) async {
      final source = FakeCloseSource(view: view())
        ..summary = summary(
          moneyIn: const Paise(1000000),
          moneyOut: const Paise(1500000),
        );
      await pumpClose(tester, source);
      final l = stringsOf(tester);
      await lock(tester);
      expect(find.text(l.closeSummaryOverspent), findsOneWidget);
      expect(find.text('−₹5,000'), findsOneWidget);
    },
  );

  // ── F1-07-146 · the three largest, and the joint family ────────────────────

  testWidgets(
    'F1-07-146 S10.2 carries the three largest expenses and, in a joint '
    'family, each sub-family’s total',
    (tester) async {
      final source = FakeCloseSource(view: view())
        ..summary = summary(
          top: const [
            MonthSummaryExpense(
              accountId: 'a',
              name: 'School Fees',
              amount: Paise(4500000),
            ),
            MonthSummaryExpense(
              accountId: 'b',
              name: 'Kirana',
              amount: Paise(2800000),
            ),
            MonthSummaryExpense(
              accountId: 'c',
              name: 'Diesel',
              amount: Paise(1200000),
            ),
          ],
          families: const [
            SubFamilyTotal(
              bookId: 'f1',
              name: 'Pankaj’s family',
              moneyIn: Paise(8000000),
              moneyOut: Paise(6500000),
            ),
            SubFamilyTotal(
              bookId: 'f2',
              name: 'Sunita’s family',
              moneyIn: Paise(9500000),
              moneyOut: Paise(7320000),
            ),
          ],
        );
      await pumpClose(tester, source);
      final l = stringsOf(tester);
      await lock(tester);

      expect(find.byKey(MonthSummaryKeys.top), findsOneWidget);
      expect(find.text(l.closeSummaryTop), findsOneWidget);
      expect(find.text('School Fees'), findsOneWidget);
      expect(find.text('₹45,000'), findsOneWidget);
      expect(find.text('₹28,000'), findsOneWidget);
      expect(find.text('₹12,000'), findsOneWidget);

      expect(find.byKey(MonthSummaryKeys.families), findsOneWidget);
      expect(find.text(l.closeSummaryFamilies), findsOneWidget);
      expect(find.text('Pankaj’s family'), findsOneWidget);
      expect(find.text('Sunita’s family'), findsOneWidget);
      expect(find.text('₹80,000'), findsOneWidget);
      expect(find.text('₹73,200'), findsOneWidget);

      // Not a joint family, nothing bought: both lists state their own empty
      // rather than leaving a blank heading (13 §4.3).
      final bare = FakeCloseSource(view: view())..summary = summary();
      await pumpClose(tester, bare);
      await lock(tester);
      expect(find.text(l.closeSummaryTopEmpty), findsOneWidget);
      expect(find.byKey(MonthSummaryKeys.families), findsNothing);
    },
  );

  // ── F1-07-147 · the share door, and the two other 13 §4.3 states ───────────

  testWidgets(
    'F1-07-147 the share door is disabled with its reason, and a summary that '
    'cannot be read never reads as a close that did not happen',
    (tester) async {
      final source = FakeCloseSource(view: view())..summary = summary();
      await pumpClose(tester, source);
      final l = stringsOf(tester);
      await lock(tester);

      // 07 §13 🔒 wants an image; `ReportFile` carries `ReportFormat` —
      // pdf | csv | xlsx — so no PNG can pass the app's one share sink. The
      // door says so rather than doing nothing (13 §4.3, 07 §1 rule 6).
      expect(find.byKey(MonthSummaryKeys.share), findsOneWidget);
      expect(find.text(l.closeSummaryShare), findsOneWidget);
      expect(find.text(l.closeSummaryShareUnavailable), findsOneWidget);
      expect(find.byType(CloseDisabledAction), findsWidgets);

      // Error: the month **is** locked, and the card says so beside the retry.
      final broken = FakeCloseSource(view: view())..failSummary = true;
      await pumpClose(tester, broken);
      await lock(tester);
      expect(find.text(l.closeSummaryError), findsOneWidget);
      expect(find.text(l.closeSummaryLockedAnyway), findsOneWidget);
      expect(
        find.text(l.closeLockDone('${monthName(l, 8)} 2026')),
        findsOneWidget,
      );
      expect(find.byType(RkErrorState), findsOneWidget);
      // Retrying reaches the seam again.
      broken.failSummary = false;
      broken.summary = summary();
      await tester.tap(find.text(l.closeRetry));
      await tester.pumpAndSettle();
      expect(find.byType(MonthSummaryCard), findsOneWidget);
    },
  );

  testWidgets('F1-07-147 S10.2 ships the ruled skeleton while it adds up', (
    tester,
  ) async {
    final source = FakeCloseSource(view: view())..holdSummary = true;
    await pumpClose(tester, source);
    final l = stringsOf(tester);
    await lock(tester);
    // The month is locked and the card is still being added up: the ruled
    // skeleton, never a spinner (11 §4.5, 13 §4.3).
    expect(find.byType(RkSkeleton), findsOneWidget);
    // The label is the screen-reader announcement, not drawn text.
    expect(
      tester.widget<RkSkeleton>(find.byType(RkSkeleton)).label,
      l.closeSummarySkeleton,
    );
    expect(find.byType(MonthSummaryCard), findsNothing);
  });

  // ── F1-07-148 · every language, both phones, both scales ───────────────────

  for (final locale in rkLocales) {
    for (final scale in rkTextScales) {
      for (final phone in rkPhones) {
        testWidgets(
          'F1-07-148 S10.1 and S10.2 hold at ${(scale * 100).round()} % in '
          '${locale.languageCode} on ${phone.width.toInt()}×'
          '${phone.height.toInt()}',
          (tester) async {
            final source = FakeCloseSource(view: view())
              ..statuses = family
              ..summary = summary(
                top: const [
                  MonthSummaryExpense(
                    accountId: 'a',
                    name: 'School Fees',
                    amount: Paise(4500000),
                  ),
                ],
                families: const [
                  SubFamilyTotal(
                    bookId: 'f1',
                    name: 'ਪੰਕਜ ਦਾ ਪਰਿਵਾਰ',
                    moneyIn: Paise(8000000),
                    moneyOut: Paise(6500000),
                  ),
                  SubFamilyTotal(
                    bookId: 'f2',
                    name: 'ਸੁਨੀਤਾ ਦਾ ਪਰਿਵਾਰ',
                    moneyIn: Paise(9500000),
                    moneyOut: Paise(7320000),
                  ),
                ],
              );
            // S10.1 first, on step 4 as the wizard draws it.
            await pumpClose(
              tester,
              source,
              locale: locale,
              textScale: scale,
              viewport: phone,
            );
            expect(tester.takeException(), isNull);
            expectTextFits(
              tester,
              reason:
                  'S10.1, ${locale.languageCode} at $scale on '
                  '${phone.width}×${phone.height}',
            );

            // Then S10.2, which replaces it.
            await lock(tester);
            expect(tester.takeException(), isNull);
            expectTextFits(
              tester,
              reason:
                  'S10.2, ${locale.languageCode} at $scale on '
                  '${phone.width}×${phone.height}',
            );
            expect(find.byType(MonthSummaryCard), findsOneWidget);
          },
        );
      }
    }
  }
}
