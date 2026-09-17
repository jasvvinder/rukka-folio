// F1-07-22 + F1-07-95…99: S5 Advances (07 §8 🔒, 13 §3.2 row S5) over the real
// `LocalLedger` — both sections read 02 §7's `advance` balances, so these
// tests seed postings rather than view models. Amounts are synthetic
// (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/advances/advances_routes.dart';
import 'package:rukka_folio/features/advances/screens/s5_advances_screen.dart';
import 'package:rukka_folio/features/advances/widgets/advance_entry_sheet.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

/// A book with one advance the user holds and one the book has out with
/// somebody else, both released by an approval (02 §7).
final class Fixture {
  const Fixture({
    required this.ledger,
    required this.bookId,
    required this.cashId,
    required this.fuelId,
    required this.mineId,
    required this.theirsId,
  });

  final LocalLedger ledger;
  final String bookId;
  final String cashId;
  final String fuelId;

  /// `Advance – me` — the signed-in user is the holder.
  final String mineId;

  /// `Advance – Ramesh` — out with another member, 40 days old.
  final String theirsId;
}

/// Posts a pending request authored by [user] and approves it. The requester
/// is never this device's user: 02 §7.2 item 1 🔒 forbids deciding on your own
/// entry, so an approval that actually moves money needs two people.
Future<void> releaseAdvance(
  LocalLedger ledger, {
  required String bookId,
  required String user,
  required String advanceId,
  required String fromId,
  required int paise,
  required LocalDate date,
  required String purpose,
}) async {
  final chart = await ledger.chartOf(bookId);
  final request = await ledger.post(
    Entry(
      id: '',
      bookId: bookId,
      kind: EntryKind.moneyOut,
      status: EntryStatus.pending,
      reviewRequired: false,
      accountingDate: date,
      lines: Verbs.advanceRequest(
        advance: chart.account(advanceId),
        from: chart.account(fromId),
        amount: Paise(paise),
      ),
      note: purpose,
      advanceId: advanceId,
      reviewApprover: ledger.identity.userId,
      createdByUser: user,
      createdByDevice: 'device-of-$user',
      hlc: const Hlc(0),
    ),
  );
  await ledger.approveAdvance(request.id);
}

Future<Fixture> seedAdvances({
  bool withMine = true,
  bool withGiven = true,
}) async {
  final ledger = await openTestLedger();
  final start = LocalDate(2026, 6, 1);
  await ledger.bootstrapSolo(firstBookName: 'Me', startDate: start);
  final bookId = (await ledger.mirror.bookIds()).single;
  final cash = await ledger.addAccount(
    bookId,
    name: 'Cash in hand',
    accountClass: AccountClass.money,
    subtype: MoneySubtype.cash,
  );
  final fuel = await ledger.addAccount(
    bookId,
    name: 'Diesel',
    accountClass: AccountClass.categoryExpense,
  );
  await ledger.openingBalances(
    bookId,
    balances: {cash.id: 5_000_000},
    date: start,
  );
  final mine = await ledger.addAccount(
    bookId,
    name: 'Advance – me',
    accountClass: AccountClass.advance,
    memberId: ledger.identity.userId,
  );
  final theirs = await ledger.addAccount(
    bookId,
    name: 'Advance – Ramesh',
    accountClass: AccountClass.advance,
    memberId: 'user-ramesh',
  );
  final today = ledger.today();
  if (withGiven) {
    await releaseAdvance(
      ledger,
      bookId: bookId,
      user: 'user-ramesh',
      advanceId: theirs.id,
      fromId: cash.id,
      paise: 300_000,
      date: today.addDays(-40),
      purpose: 'Mandi trip',
    );
  }
  if (withMine) {
    await releaseAdvance(
      ledger,
      bookId: bookId,
      user: 'user-manager',
      advanceId: mine.id,
      fromId: cash.id,
      paise: 500_000,
      date: today.addDays(-3),
      purpose: 'Transport',
    );
    await ledger.spendAgainstAdvance(
      bookId: bookId,
      advance: mine.id,
      forWhat: fuel.id,
      paise: 150_000,
      date: today.addDays(-1),
    );
  }
  return Fixture(
    ledger: ledger,
    bookId: bookId,
    cashId: cash.id,
    fuelId: fuel.id,
    mineId: mine.id,
    theirsId: theirs.id,
  );
}

/// Tears the tree down inside the test so drift's zero-duration stream
/// cleanup timer fires before the binding's pending-timer invariant runs
/// (the house pattern, S3.1's test).
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// A pump that does **not** settle — the only way to see the first frame,
/// where neither stream has delivered yet and the screen must draw its
/// skeleton (13 §4.3 loading).
Future<void> pumpUnsettled(
  WidgetTester tester,
  Widget child, {
  required LocalLedger ledger,
}) => tester.pumpWidget(
  RkScope(
    db: ledger.db,
    sync: FakeSyncClient(),
    auth: FakeAuthClient(),
    keys: ledger.keys as FakeKeyStore,
    now: ledger.now,
    child: LedgerScope(
      ledger: ledger,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: rkLocalizationsDelegates,
        theme: rkTheme(Brightness.light),
        home: child,
      ),
    ),
  ),
);

void main() {
  // The spend/return sheet autofocuses its amount field, and a focused
  // `EditableText` blinks its caret on a repeating timer — an animation that
  // never settles, so every `pumpAndSettle` past the sheet opening would grind
  // out ten simulated minutes of frames before giving up.
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  testWidgets('F1-07-22 S5 draws both sections off the ledger: the card the '
      'holder sees and the aged row the book sees (07 §8 🔒)', (tester) async {
    final f = await seedAdvances();
    await pumpRk(
      tester,
      AdvancesScreen(bookId: f.bookId),
      ledger: f.ledger,
      viewport: const Size(400, 1200),
    );

    // Section 1 — *Advance with you* (02 §7: money you are holding).
    expect(find.text('Advance with you'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget, reason: 'the purpose');
    expect(find.text('Taken 04 Sep 2026'), findsOneWidget);
    // Spent vs remaining in words beside the bar — colour never alone.
    expect(find.text('₹1,500 spent · ₹3,500 left'), findsOneWidget);
    expect(find.text('Add spend'), findsOneWidget);
    expect(find.text('Return remaining'), findsOneWidget);

    // Section 2 — *Advance out*, aged (02 §7 ageing).
    expect(find.text('Advance out'), findsOneWidget);
    expect(find.text('Advance – Ramesh · 40 days'), findsOneWidget);
    expect(
      find.text('Not settled'),
      findsNWidgets(2),
      reason: 'both open advances are the book\u2019s money out with people',
    );
    // The overdue row pairs its tint with an icon and the word (07 §1 rule 3).
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    // S5.1 is another lane's: nothing here offers a request door (07 §1 r6).
    expect(find.text('Request an advance'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    await unmount(tester);
  });

  testWidgets('F1-07-95 the empty state says what an advance is and offers no '
      'door that leads nowhere (07 §1 rules 6 and 12)', (tester) async {
    final f = await seedAdvances(withMine: false, withGiven: false);
    await pumpRk(tester, AdvancesScreen(bookId: f.bookId), ledger: f.ledger);

    expect(find.text('No advance is out right now.'), findsOneWidget);
    expect(
      find.textContaining('cash handed to someone for a job'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    await unmount(tester);
  });

  testWidgets('F1-07-96 the first frame draws the ruled skeleton — the '
      'loading state of 13 §4.3, announced', (tester) async {
    final f = await seedAdvances();
    await pumpUnsettled(
      tester,
      AdvancesScreen(bookId: f.bookId),
      ledger: f.ledger,
    );
    expect(
      find.bySemanticsLabel('Loading your advances'),
      findsOneWidget,
      reason: 'before either stream has delivered',
    );
    await unmount(tester);
  });

  testWidgets('F1-07-96 a book that will not resolve draws the error with its '
      'retry — never a blank white (07 §1 rule 12)', (tester) async {
    final bare = await openTestLedger();
    await pumpRk(tester, const AdvancesScreen(), ledger: bare);
    expect(find.text('Couldn\u2019t load your advances.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn\u2019t load your advances.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('F1-07-97 Add spend and Return remaining reach the engine in '
      'integer paise and the card follows (02 §7)', (tester) async {
    final f = await seedAdvances();
    await pumpRk(
      tester,
      AdvancesScreen(bookId: f.bookId),
      ledger: f.ledger,
      viewport: const Size(400, 1200),
    );

    await tester.tap(find.text('Add spend'));
    await tester.pumpAndSettle();
    expect(find.byType(AdvanceEntrySheet), findsOneWidget);
    await tester.enterText(find.byType(TextField), '100');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.byType(AdvanceEntrySheet),
      findsNothing,
      reason: 'a saved entry closes the sheet',
    );
    var open = await f.ledger.openAdvances(f.bookId);
    var mine = open.firstWhere((a) => a.accountId == f.mineId);
    expect(mine.spentPaise, 160_000, reason: '₹100 is 10 000 paise, exactly');
    expect(mine.remainingPaise, 340_000);
    expect(find.text('₹1,600 spent · ₹3,400 left'), findsOneWidget);

    await tester.tap(find.text('Return remaining'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '50.50');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    open = await f.ledger.openAdvances(f.bookId);
    mine = open.firstWhere((a) => a.accountId == f.mineId);
    expect(mine.returnedPaise, 5_050);
    expect(mine.remainingPaise, 334_950);

    // More than is left is refused before anything is authored.
    await tester.tap(find.text('Return remaining'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '99999');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('more than the'), findsOneWidget);
    open = await f.ledger.openAdvances(f.bookId);
    expect(
      open.firstWhere((a) => a.accountId == f.mineId).remainingPaise,
      334_950,
    );
    await unmount(tester);
  });

  testWidgets('F1-07-98 Remind and Write off render disabled with the reason '
      'on screen — never a dead tap (13 §4.3, 07 §1 rule 6)', (tester) async {
    final f = await seedAdvances(withMine: false);
    await pumpRk(
      tester,
      AdvancesScreen(bookId: f.bookId),
      ledger: f.ledger,
      viewport: const Size(400, 1200),
    );

    for (final label in ['Remind', 'Write off']) {
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull, reason: '$label cannot act yet');
    }
    expect(
      find.text('Reminders switch on when this phone can send them.'),
      findsOneWidget,
    );
    expect(find.textContaining('guided correction'), findsOneWidget);

    // A member who cannot approve is not shown the approver's actions at all.
    await pumpRk(
      tester,
      AdvancesScreen(bookId: f.bookId, canApprove: false),
      ledger: f.ledger,
      viewport: const Size(400, 1200),
    );
    expect(find.text('Remind'), findsNothing);
    expect(find.text('Write off'), findsNothing);
    await unmount(tester);
  });

  testWidgets('F1-07-99 EN, ਪੰਜਾਬੀ and हिन्दी all resolve, and nothing is cut '
      'at 200 % text scale on 360×800 (07 §1 rules 9 and 11)', (tester) async {
    for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
      final f = await seedAdvances();
      await pumpRk(
        tester,
        AdvancesScreen(bookId: f.bookId),
        ledger: f.ledger,
        locale: locale,
        textScale: 2,
        viewport: const Size(360, 800),
      );
      expect(tester.takeException(), isNull, reason: '$locale overflowed');
      expectTextFits(tester, reason: 'at 200 % in $locale');
      // Every string on screen came from the ARB — no untranslated key leaked.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s.isNotEmpty);
      expect(texts, isNotEmpty);
      expect(texts.every((s) => !s.startsWith('advances.')), isTrue);
      await unmount(tester);
    }
  });

  test('F1-07-22 the feature exports one route for S5 and declares none for '
      'S5.1 — the next lane owns the request form', () {
    expect(advancesRoutes, hasLength(1));
    expect(AdvancesPaths.index, '/advances');
  });
}
