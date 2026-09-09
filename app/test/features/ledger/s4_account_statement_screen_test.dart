// F1 widget test for the S4 A/C statement (07 §6, 13 §3.2 row S4, §4.3
// states). S4 is a PROFESSIONAL surface (02 §10 🔒): it speaks true ledger
// Dr/Cr and must never show the consumer words Money in / Money out. The
// engine's signed paise are what the columns are derived from — the display
// language bends, the posting never does.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart' hide StatementRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/screens/s4_account_statement_screen.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/format/money_format.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

/// A viewport tall enough that the statement's `ListView` builds every row —
/// rows below the fold otherwise do not exist at all.
void tallViewport(WidgetTester tester, {double width = 500}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Tears the tree down *inside* the test. Cancelling drift's query stream
/// schedules a zero-duration cleanup timer, and only a pump inside the test
/// fires it before the binding's end-of-test pending-timer invariant runs.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Reads the engine's own statement rows from outside the fake-async zone.
/// A drift query stream's first event arrives on a zero-duration timer that a
/// bare `await` in a widget test never lets the fake clock fire; `runAsync`
/// is the supported escape hatch.
Future<List<StatementRow>> statementOf(
  WidgetTester tester,
  SeededLedger seed,
  String accountId,
) async =>
    (await tester.runAsync(() => seed.ledger.watchStatement(accountId).first))!;

/// Every [MoneyText] currently on screen, in tree order.
List<MoneyText> moneyOn(WidgetTester tester) =>
    tester.widgetList<MoneyText>(find.byType(MoneyText)).toList();

void main() {
  group('S4 A/C statement (07 §6, 13 §3.2)', () {
    testWidgets(
      'F1-07-44 speaks professional Dr/Cr, never the consumer Money in/out '
      '(02 §10)',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seed.partyId),
          ledger: seed.ledger,
        );

        // The three-column paper ledger: Dr | Cr | Balance.
        expect(find.text('Dr'), findsOneWidget);
        expect(find.text('Cr'), findsOneWidget);
        expect(find.text('Balance'), findsOneWidget);

        // 02 §10 🔒: the consumer vocabulary never appears on this surface.
        expect(find.textContaining('Money in'), findsNothing);
        expect(find.textContaining('Money out'), findsNothing);

        // …and it is not merely absent from the strings: every amount widget
        // is asked for the professional vocabulary explicitly.
        final money = moneyOn(tester);
        expect(money, isNotEmpty);
        expect(
          money.every((m) => m.vocabulary == Vocabulary.professional),
          isTrue,
          reason: 'a consumer-vocabulary amount leaked onto S4 (02 §10)',
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-44 rows carry b/f first and c/f last, with the counter account '
      'as particulars',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seed.partyId),
          ledger: seed.ledger,
        );

        expect(find.textContaining('Opening balance b/f'), findsOneWidget);
        expect(find.textContaining('Closing balance c/f'), findsOneWidget);
        // Ramesh's two entries both face Cash in hand — the particulars column
        // names the *other* account, never this one. (The account's own name
        // belongs in the app bar, and only there.)
        expect(find.widgetWithText(AppBar, 'Ramesh'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Cash in hand'), findsNWidgets(2));
        expect(find.widgetWithText(ListTile, 'Ramesh'), findsNothing);
        expect(find.text('part repayment'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-44 the running balance is the engine\'s integer paise, never a '
      'double',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        final rows = await statementOf(tester, seed, seed.cashId);
        await pumpRk(
          tester,
          AccountStatementScreen(accountId: seed.cashId),
          ledger: seed.ledger,
        );

        // Cash has five entries; the closing figure is the engine's last
        // running balance, to the paise (CLAUDE.md rule 1).
        expect(rows, hasLength(5));
        expect(rows.last.runningBalancePaise, 2_160_000);

        final money = moneyOn(tester);
        // Nothing on the way to the screen turned paise into rupees-as-double.
        for (final m in money) {
          expect(m.paise, isA<int>());
        }
        // The engine's running balances all reach the screen unaltered, and
        // the closing row repeats the last of them.
        final shown = money.map((m) => m.paise).toSet();
        for (final r in rows) {
          expect(
            shown,
            contains(r.runningBalancePaise),
            reason: 'running balance ${r.runningBalancePaise} never rendered',
          );
        }
        expect(money.last.paise, rows.last.runningBalancePaise);
        await unmount(tester);
      },
    );

    testWidgets('F1-07-44 empty state: an account with no entries (13 §4.3)', (
      tester,
    ) async {
      tallViewport(tester);
      final seed = await seedSoloLedger();
      final fresh = await seed.ledger.addAccount(
        seed.bookId,
        name: 'Unused A/C',
        accountClass: AccountClass.categoryExpense,
      );
      await pumpRk(
        tester,
        AccountStatementScreen(accountId: fresh.id),
        ledger: seed.ledger,
      );

      expect(find.text('No entries on this account yet'), findsOneWidget);
      // 07 §1 rule 6: never a dead end — the empty state points somewhere.
      expect(
        find.text('Add the first entry from the Ledger tab'),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('F1-07-44 error state: unresolvable book shows retry', (
      tester,
    ) async {
      final ledger = await openTestLedger();
      await pumpRk(
        tester,
        const AccountStatementScreen(accountId: 'no-such-account'),
        ledger: ledger,
      );

      expect(find.text("Couldn't load this statement"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('F1-07-44 loading state renders the ruled skeleton (11 §4.5)', (
      tester,
    ) async {
      final seed = await seedSoloLedger();
      await tester.pumpWidget(
        RkScope(
          db: seed.ledger.db,
          sync: FakeSyncClient(),
          auth: FakeAuthClient(),
          keys: seed.ledger.keys,
          now: seed.ledger.now,
          child: LedgerScope(
            ledger: seed.ledger,
            child: MaterialApp(
              supportedLocales: const [Locale('en')],
              localizationsDelegates: rkLocalizationsDelegates,
              theme: rkTheme(Brightness.light),
              home: AccountStatementScreen(accountId: seed.partyId),
            ),
          ),
        ),
      );
      // One frame — before the async book resolve completes. Matched on the
      // `Semantics` widget, not the semantics tree, which widget tests only
      // build while a handle is held (07 §1 rule 12).
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Loading statement',
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      await unmount(tester);
    });

    testWidgets(
      'F1-07-44 strings resolve in EN/PA/HI with no overflow at 200%',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          tallViewport(tester, width: 360);
          final seed = await seedSoloLedger();
          await pumpRk(
            tester,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: AccountStatementScreen(accountId: seed.partyId),
            ),
            ledger: seed.ledger,
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          await unmount(tester);
        }
      },
    );
  });
}
