// RESKIN1 round 2, slice R2A — audit captures for the Ledger tab (ADR
// 2026-10-05 §2; ADR 2026-10-10b §1 phase 1: an audit, not a build). Pair with
// `python3 scripts/design_match.py pair <S-id>`.
//
// S3   — canvas 7 *Ledger index* and *Ledger index · opening balance not set*.
// S3.1 — canvas 7 *Quick add · a sheet, from the Ledger tab*.
// S4   — canvas 7 *A/C statement*, *· opening balance not set* and *· add the
//        opening balance* (ADR 2026-10-07b, OPEN177).
// S4.1 — canvas 11 / 2 *Entry detail* and its states (amended, locked period,
//        reversed; *imported entry* is not built — see design/match/S4.1.json).
// S21  — canvas 7 *Search · recent, before typing* and *Search · results*.
//
// TEST HONESTY: every screen is built with exactly the arguments its
// production route passes (ledger_routes.dart): S3 as the Ledger tab root with
// onOpenAccount + onOpenSearch; S4 with accountId + onOpenEntry + onCountCash;
// S4.1 with entryId + onOpenEntry; S21 with a null bookId + both doors. The
// ledger state behind each is posted through the same LocalLedger verbs the
// app uses. Synthetic names and sums only (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/screens/s21_search_screen.dart';
import 'package:rukka_folio/features/ledger/screens/s3_1_quick_add_sheet.dart';
import 'package:rukka_folio/features/ledger/screens/s3_ledger_index_screen.dart';
import 'package:rukka_folio/features/ledger/screens/s4_1_entry_detail_screen.dart';
import 'package:rukka_folio/features/ledger/screens/s4_account_statement_screen.dart';
import 'package:rukka_folio/features/ledger/widgets/opening_prompt.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

/// Writes the screen as it stands now — the same root-layer picture
/// [rkDesignCapture] takes, for a state a tap reached.
Future<void> _snap(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: rkDesignPixelRatio,
    );
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File('$rkDesignCaptureDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png.buffer.asUint8List());
    image.dispose();
  });
}

void _drop(String name) {
  final f = File('$rkDesignCaptureDir/$name.png');
  if (f.existsSync()) f.deleteSync();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Lets the drift streams behind a tap land, then settles the frame.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

/// The seeded solo book plus the canvas's cast: a supplier with a Cr balance
/// (Bharat Power, as c7 S3 draws), a milk supplier with a week of bills and a
/// part payment (Sunil Dairy, c7 S4), and a person created without an opening
/// balance — the way an entry-picker account is created (ADR 2026-10-07b) —
/// with one loan against him (Ramesh Kumar, c7 *opening balance not set*).
final class _Shop {
  _Shop(this.seed, this.sunilId, this.rameshKumarId, this.milkId);
  final SeededLedger seed;
  final String sunilId;
  final String rameshKumarId;
  final String milkId;
}

Future<_Shop> _shop() async {
  final seed = await seedSoloLedger();
  final l = seed.ledger;
  final today = l.today();
  final bharat = await l.addAccount(
    seed.bookId,
    name: 'Bharat Power',
    accountClass: AccountClass.party,
  );
  // Bharat Power and Sunil Dairy were set up the way S3.1 sets an account up
  // — with their opening answered — so, as in the frames, neither carries
  // the ADR 2026-10-07b prompt. (An opening of zero cannot be recorded yet:
  // see design/match/S4.json and the OPEN177 lane report.) The seed's own
  // Ramesh is answered too, leaving Ramesh Kumar the one person the entry
  // picker made, as c7 *opening balance not set* draws.
  await l.openingBalances(
    seed.bookId,
    balances: {bharat.id: -245_000, seed.partyId: 50_000},
  );
  final milk = await l.addAccount(
    seed.bookId,
    name: 'Milk Expense',
    accountClass: AccountClass.categoryExpense,
  );
  final sunil = await l.addAccount(
    seed.bookId,
    name: 'Sunil Dairy',
    accountClass: AccountClass.party,
  );
  await l.tookCredit(
    bookId: seed.bookId,
    fromWhom: sunil.id,
    took: milk.id,
    paise: 42_000,
    date: today.addDays(-3),
    note: 'Milk taken on credit',
  );
  await l.tookCredit(
    bookId: seed.bookId,
    fromWhom: sunil.id,
    took: milk.id,
    paise: 53_000,
    date: today.addDays(-2),
    note: 'Extra 2 litres for guests',
  );
  await l.moneyOut(
    bookId: seed.bookId,
    from: seed.cashId,
    forWhat: sunil.id,
    paise: 50_000,
    date: today.addDays(-1),
    note: "Paid part of last week's milk",
  );
  await l.tookCredit(
    bookId: seed.bookId,
    fromWhom: sunil.id,
    took: milk.id,
    paise: 42_000,
    date: today,
    note: 'Milk taken on credit',
  );
  await l.openingBalances(seed.bookId, balances: {sunil.id: -30_000});
  final rk = await l.addAccount(
    seed.bookId,
    name: 'Ramesh Kumar',
    accountClass: AccountClass.party,
  );
  await l.gaveCredit(
    bookId: seed.bookId,
    toWhom: rk.id,
    gave: seed.cashId,
    paise: 50_000,
    date: today,
    note: 'Lent for the tractor repair',
  );
  return _Shop(seed, sunil.id, rk.id, milk.id);
}

LedgerIndexScreen _index() =>
    LedgerIndexScreen(onOpenAccount: (_) {}, onOpenSearch: () {});

AccountStatementScreen _statement(String accountId) => AccountStatementScreen(
  accountId: accountId,
  onOpenEntry: (_) {},
  onCountCash: (_) {},
);

EntryDetailScreen _detail(String entryId) => EntryDetailScreen(
  entryId: entryId,
  onOpenEntry: (_) {},
  onEnterAgain: (_) {},
);

LedgerSearchScreen _search() =>
    LedgerSearchScreen(onOpenAccount: (_) {}, onOpenEntry: (_) {});

/// A blank route with one door that pushes [child] — S4 is never a root: it
/// is pushed from S3 (ledger_routes.dart), so its app bar carries a back
/// button that a root mount would not draw.
class _PushBase extends StatelessWidget {
  const _PushBase({required this.child});

  static const door = Key('push-base-door');

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: door,
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => child)),
        child: const SizedBox.square(dimension: 48),
      ),
    ),
  );
}

void main() {
  testWidgets('F1-1010r2A-1 design capture S3 (ledger index; the account '
      'created without an opening balance)', (tester) async {
    for (final target in RkDesignTarget.values) {
      final shop = await _shop();
      await rkDesignCapture(
        tester,
        sid: 'S3',
        target: target,
        tab: RkTab.ledger,
        ledger: shop.seed.ledger,
        child: _index(),
      );
      expect(find.text('Bharat Power'), findsOneWidget);
      // Scrolled to R, where c7 *opening balance not set* puts Ramesh Kumar.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(find.text('Ramesh Kumar'), findsOneWidget);
      // ADR 2026-10-07b §1: the one marker, on the entry-picker person.
      expect(find.byKey(OpeningPromptKeys.marker), findsOneWidget);
      await _snap(tester, 'S3__opening-not-set${target.suffix}');
      await _unmount(tester);
    }
  });

  testWidgets('F1-1010r2A-2 design capture S3.1 (quick add sheet from the '
      'Ledger tab FAB)', (tester) async {
    for (final target in RkDesignTarget.values) {
      final shop = await _shop();
      await rkDesignCapture(
        tester,
        sid: 'S3.1',
        state: 'pre',
        target: target,
        tab: RkTab.ledger,
        ledger: shop.seed.ledger,
        child: _index(),
      );
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(QuickAddSheet), findsOneWidget);
      await _snap(tester, 'S3.1__sheet${target.suffix}');
      _drop('S3.1__pre${target.suffix}');
      await _unmount(tester);
    }
  });

  testWidgets('F1-1010r2A-3 design capture S4 (supplier statement; a person '
      'whose opening balance was never asked), pushed over a base route as '
      'production pushes it', (tester) async {
    for (final target in RkDesignTarget.values) {
      final shop = await _shop();
      for (final (state, id, name) in [
        ('default', shop.sunilId, 'Sunil Dairy'),
        ('opening-not-set', shop.rameshKumarId, 'Ramesh Kumar'),
      ]) {
        await rkDesignCapture(
          tester,
          sid: 'S4',
          state: 'pre',
          target: target,
          ledger: shop.seed.ledger,
          child: _PushBase(child: _statement(id)),
        );
        await tester.tap(find.byKey(_PushBase.door));
        await _settle(tester);
        // ledger_routes.dart pushes S4 on the root navigator, so the app bar
        // draws its leading back button; the capture has to show it.
        expect(find.byType(BackButton), findsOneWidget);
        expect(find.text(name), findsWidgets);
        // ADR 2026-10-07b §1: only the entry-picker person carries the prompt.
        expect(
          find.byKey(OpeningPromptKeys.card),
          state == 'opening-not-set' ? findsOneWidget : findsNothing,
        );
        await _snap(tester, 'S4__$state${target.suffix}');
        if (state == 'opening-not-set') {
          // c7 *A/C statement · add the opening balance*: the sheet, side
          // *They owe you*, ₹2,000 typed.
          await tester.tap(find.byKey(OpeningPromptKeys.add));
          await _settle(tester);
          await tester.enterText(find.byKey(OpeningPromptKeys.amount), '2000');
          await _settle(tester);
          expect(find.text('You will get ₹2,500 in all.'), findsOneWidget);
          await _snap(tester, 'S4__add-opening${target.suffix}');
        }
        _drop('S4__pre${target.suffix}');
        await _unmount(tester);
      }
    }
  });

  testWidgets('F1-1010r2A-4 design capture S4.1 (default, amended twice, '
      'locked period, reversed)', (tester) async {
    for (final target in RkDesignTarget.values) {
      final seed = await seedSoloLedger();
      final l = seed.ledger;
      final today = l.today();
      // Default: cash → diesel with a note.
      final plain = await l.moneyOut(
        bookId: seed.bookId,
        from: seed.cashId,
        forWhat: seed.fuelId,
        paise: 240_000,
        date: today.addDays(-1),
        note: 'Isuzu, full tank',
      );
      // Amended twice: the amount, then the note — the head is shown.
      final first = await l.moneyOut(
        bookId: seed.bookId,
        from: seed.cashId,
        forWhat: seed.fuelId,
        paise: 240_000,
        date: today.addDays(-1),
        note: 'Isuzu, full tank',
      );
      final chart = await l.chartOf(seed.bookId);
      final second = await l.amend(
        first.id,
        lines: Verbs.moneyOut(
          from: chart.account(seed.cashId),
          forWhat: chart.account(seed.fuelId),
          amount: const Paise(260_000),
        ),
      );
      final head = await l.amend(second.id, note: 'Isuzu, full tank + oil');
      // Locked period: an August entry, August then closed (testNow is
      // 7 Sep 2026; the book starts 31 Aug).
      final august = await l.moneyOut(
        bookId: seed.bookId,
        from: seed.cashId,
        forWhat: seed.fuelId,
        paise: 240_000,
        date: today.addDays(-7),
        note: 'Isuzu, full tank',
      );
      // Reversed, with a reason: c2 *Reversed* draws an August entry fixed
      // after August closed (*August stays as it was counted*), so this one
      // is dated in August too and reversed today by *Fix this entry*.
      final wrong = await l.moneyOut(
        bookId: seed.bookId,
        from: seed.cashId,
        forWhat: seed.fuelId,
        paise: 240_000,
        date: today.addDays(-7),
        note: 'Isuzu, full tank',
      );
      await l.lockMonth(
        seed.bookId,
        YearMonth(2026, 8),
        declaredBalances: const {},
      );
      await l.reverse(wrong.id, date: today, note: 'Wrong khata chosen');

      for (final (state, id) in [
        ('default', plain.id),
        ('amended', head.id),
        ('locked', august.id),
        ('reversed', wrong.id),
      ]) {
        await rkDesignCapture(
          tester,
          sid: 'S4.1',
          state: state,
          target: target,
          ledger: l,
          child: _detail(id),
        );
        expect(find.byType(EntryDetailScreen), findsOneWidget);
        await _unmount(tester);
      }
    }
  });

  testWidgets('F1-1010r2A-5 design capture S21 (before typing; results)', (
    tester,
  ) async {
    for (final target in RkDesignTarget.values) {
      final shop = await _shop();
      await rkDesignCapture(
        tester,
        sid: 'S21',
        state: 'before-typing',
        target: target,
        ledger: shop.seed.ledger,
        child: _search(),
      );
      await tester.enterText(find.byType(TextField), 'milk');
      await _settle(tester);
      expect(find.text('Milk Expense'), findsWidgets);
      await _snap(tester, 'S21__results${target.suffix}');
      await _unmount(tester);
    }
  });
}
