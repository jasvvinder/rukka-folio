// ADR 2026-10-07 ruling 3 — the S0.7 checklist brings back what was skipped
// (canvas 1 frames O8, O8b–O8f; PLAN desk 174).
//
// F1-1007-4  the rows by path: *Opening balances* arrives ticked; *Check your
//            recovery sheet · Not scanned back yet* is amber with its icon;
//            family / trust get one *Finish <book name>* row naming the next
//            step while the invite step was skipped — on the family path it
//            replaces *Add your family*, a trust has no family row, and the
//            business path has no branch row.
// F1-1007-5  ⋮ → *Not needed* on the branch row only: hides it, deletes
//            nothing, no confirm, a toast with Undo that puts it back.
// F1-1007-6  the card leaves when every row is ticked or Not needed; the
//            optional *Add your family* never holds it open; a finished
//            branch row ticks and strikes through; the rows survive a cold
//            start because they are read from the device.
@Tags(['F1'])
library;

import 'dart:convert';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_scope.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

const _personal = 'Gurpreet Sandhu';

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// A personal book, plus a branch book of [type] named [branchName] when
/// given. Returns the ledger and (personal id, branch id).
Future<(LocalLedger, String, String?)> _books({
  BookType? type,
  String? branchName,
}) async {
  final ledger = await openTestLedger();
  await ledger.bootstrapSolo(
    firstBookName: _personal,
    startDate: ledger.today().addDays(-7),
  );
  final personal = (await ledger.mirror.bookIds()).single;
  String? branch;
  if (type != null) {
    branch = await ledger.createBook(
      name: branchName!,
      type: type,
      startDate: ledger.today(),
    );
  }
  return (ledger, personal, branch);
}

/// An ordinary entry in [bookId] — what ends the first run.
Future<void> _firstEntry(LocalLedger l, String bookId) async {
  final cash = (await l.chartOf(bookId)).byClass(AccountClass.money).first;
  final tea = await l.addAccount(
    bookId,
    name: 'Tea',
    accountClass: AccountClass.categoryExpense,
  );
  await l.moneyOut(
    bookId: bookId,
    from: cash.id,
    forWhat: tea.id,
    paise: 2000,
    date: l.today(),
  );
}

/// The device record sign-up leaves (what `setup_progress.dart` writes).
MemoryPrefs _prefs({
  required List<String> openingDone,
  String? purpose,
  String? branchState,
  String? branchBook,
  bool sheetVerified = false,
}) {
  final prefs = MemoryPrefs();
  for (final id in openingDone) {
    prefs.values[RkPrefKeys.openingBalancesOf(id)] = '1';
  }
  if (purpose != null) prefs.values[RkPrefKeys.setupPurpose] = purpose;
  if (branchState != null) {
    prefs.values[RkPrefKeys.setupBranch] = jsonEncode({
      'purpose': purpose,
      'state': branchState,
      'book': ?branchBook,
    });
  }
  if (sheetVerified) prefs.values[RkPrefKeys.recoverySheetVerified] = '1';
  return prefs;
}

Future<List<SetupStep>> _pump(
  WidgetTester tester,
  LocalLedger ledger,
  MemoryPrefs prefs, {
  required String bookInScope,
  Locale? locale,
  double textScale = 1,
  Size viewport = const Size(400, 2400),
}) async {
  final steps = <SetupStep>[];
  final settings = AppSettings(prefs: prefs);
  await settings.load();
  await pumpRk(
    tester,
    AppSettingsScope(
      settings: settings,
      child: HomeScreen(
        scopeController: HomeScopeController()
          ..select(HomeScope.book(bookInScope)),
        onSetupStep: steps.add,
      ),
    ),
    ledger: ledger,
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
  await tester.pumpAndSettle();
  return steps;
}

/// The checklist's row labels, top to bottom.
List<String> _rowLabels(WidgetTester tester) {
  final rows = find.descendant(
    of: find.byType(HomeSetupChecklist),
    matching: find.byWidgetPredicate(
      (w) =>
          w is InkWell &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('home.setup.row.'),
    ),
  );
  final found = rows.evaluate().toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byWidget(a.widget))
          .dy
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
    );
  return [
    for (final e in found)
      (e.widget.key! as ValueKey<String>).value.substring(
        'home.setup.row.'.length,
      ),
  ];
}

Finder get _more => find.byIcon(Icons.more_vert);

void main() {
  group('F1-1007-4 the rows by path (ruling 3)', () {
    testWidgets('F1-1007-4 myself: Opening balances ticked, first entry, the '
        'amber recovery-sheet row with its icon, then Add your family', (
      tester,
    ) async {
      final (ledger, personal, _) = await _books();
      final steps = await _pump(
        tester,
        ledger,
        _prefs(openingDone: [personal], purpose: 'myself'),
        bookInScope: personal,
      );
      expect(_rowLabels(tester), [
        'openingBalances',
        'firstEntry',
        'recoverySheet',
        'addFamily',
      ]);
      expect(
        tester.widget<Text>(find.text('Opening balances')).style?.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.text('Check your recovery sheet'), findsOneWidget);
      final hint = tester.widget<Text>(find.text('Not scanned back yet'));
      final context = tester.element(find.text('Not scanned back yet'));
      expect(hint.style?.color, RkStatusColors.of(context).pending);
      // Colour never alone (07 §1 rule 3): the warning icon rides with it.
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(_more, findsNothing);

      await tester.tap(find.text('Check your recovery sheet'));
      await tester.pump();
      expect(steps, [SetupStep.recoverySheet]);
      await _unmount(tester);
    });

    testWidgets('F1-1007-4 business: no branch row (its steps are required); '
        'Add your family stays', (tester) async {
      final (ledger, personal, shop) = await _books(
        type: BookType.business,
        branchName: 'Kaur Traders',
      );
      await _pump(
        tester,
        ledger,
        _prefs(openingDone: [personal, shop!], purpose: 'businesses'),
        bookInScope: personal,
      );
      expect(_rowLabels(tester), [
        'openingBalances',
        'firstEntry',
        'recoverySheet',
        'addFamily',
      ]);
      expect(find.textContaining('Finish '), findsNothing);
      expect(_more, findsNothing);
      await _unmount(tester);
    });

    testWidgets('F1-1007-4 family, invites skipped: "Finish Sandhu Family" '
        'second, naming the next step, in place of Add your family (O8b)', (
      tester,
    ) async {
      final (ledger, personal, fund) = await _books(
        type: BookType.family,
        branchName: 'Sandhu Family',
      );
      final steps = await _pump(
        tester,
        ledger,
        _prefs(
          openingDone: [personal, fund!],
          purpose: 'family',
          branchState: 'open',
          branchBook: fund,
        ),
        bookInScope: personal,
      );
      expect(_rowLabels(tester), [
        'openingBalances',
        'finishFamily',
        'firstEntry',
        'recoverySheet',
      ]);
      expect(find.text('Finish Sandhu Family'), findsOneWidget);
      expect(find.text('Next: invite the other heads'), findsOneWidget);
      expect(find.text('Add your family'), findsNothing);
      expect(_more, findsOneWidget);

      await tester.tap(find.text('Finish Sandhu Family'));
      await tester.pump();
      expect(steps, [SetupStep.finishFamily]);
      await _unmount(tester);
    });

    testWidgets('F1-1007-4 trust, invites skipped: "Finish <trust>" naming '
        'who runs it; a trust has no family row (O8c)', (tester) async {
      final (ledger, personal, trust) = await _books(
        type: BookType.organization,
        branchName: 'Gurdwara Sahib, Ballowal',
      );
      final steps = await _pump(
        tester,
        ledger,
        // The book id is not recorded yet: the one trust book is found.
        _prefs(
          openingDone: [personal, trust!],
          purpose: 'trust',
          branchState: 'open',
        ),
        bookInScope: personal,
      );
      expect(_rowLabels(tester), [
        'openingBalances',
        'finishTrust',
        'firstEntry',
        'recoverySheet',
      ]);
      expect(find.text('Finish Gurdwara Sahib, Ballowal'), findsOneWidget);
      expect(find.text('Next: invite who runs it'), findsOneWidget);
      await tester.tap(find.text('Finish Gurdwara Sahib, Ballowal'));
      await tester.pump();
      expect(steps, [SetupStep.finishTrust]);
      await _unmount(tester);
    });

    testWidgets('F1-1007-4 family, invites answered: no branch row and no '
        'family row', (tester) async {
      final (ledger, personal, fund) = await _books(
        type: BookType.family,
        branchName: 'Sandhu Family',
      );
      await _pump(
        tester,
        ledger,
        _prefs(openingDone: [personal, fund!], purpose: 'family'),
        bookInScope: personal,
      );
      expect(_rowLabels(tester), [
        'openingBalances',
        'firstEntry',
        'recoverySheet',
      ]);
      await _unmount(tester);
    });
  });

  group('F1-1007-5 ⋮ → Not needed (ruling 3)', () {
    testWidgets('F1-1007-5 hides the row with no confirm, deletes nothing, '
        'and the toast\'s Undo puts it back', (tester) async {
      final (ledger, personal, fund) = await _books(
        type: BookType.family,
        branchName: 'Sandhu Family',
      );
      final prefs = _prefs(
        openingDone: [personal, fund!],
        purpose: 'family',
        branchState: 'open',
        branchBook: fund,
      );
      await _pump(tester, ledger, prefs, bookInScope: personal);

      await tester.tap(_more);
      await tester.pumpAndSettle();
      expect(find.text('Not needed'), findsOneWidget);
      expect(
        find.text(
          'Takes it off this list. Nothing is deleted. Invite family from '
          'Menu › Members any time.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Not needed'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Finish Sandhu Family'), findsNothing);
      expect(
        find.text(
          'Family invites taken off your list. Invite from Menu any time.',
        ),
        findsOneWidget,
      );
      expect(
        jsonDecode(prefs.values[RkPrefKeys.setupBranch]!)['state'],
        'notNeeded',
      );
      // Nothing deleted: the joint fund book is still there.
      expect(await ledger.mirror.bookIds(), contains(fund));

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Finish Sandhu Family'), findsOneWidget);
      expect(
        jsonDecode(prefs.values[RkPrefKeys.setupBranch]!)['state'],
        'open',
      );
      await _unmount(tester);
    });

    testWidgets('F1-1007-5 the menu opens below the row it acts on, and '
        'the toast sits above the verb buttons and leaves on its own after '
        'its 10 s Undo window (13 §4.2; 07 §1 rules 1–2)', (tester) async {
      final (ledger, personal, fund) = await _books(
        type: BookType.family,
        branchName: 'Sandhu Family',
      );
      final prefs = _prefs(
        openingDone: [personal, fund!],
        purpose: 'family',
        branchState: 'open',
        branchBook: fund,
      );
      // A phone-sized window, so the list and the pinned verb bar share it.
      await _pump(
        tester,
        ledger,
        prefs,
        bookInScope: personal,
        viewport: const Size(390, 844),
      );
      final row = find.ancestor(
        of: find.text('Finish Sandhu Family'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is InkWell &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('home.setup.row.'),
        ),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();

      await tester.tap(_more);
      await tester.pumpAndSettle();
      // Canvas 1 O8e: the menu hangs under the row, which stays in view
      // (measured once open: a low row is first brought up the list).
      final menuCard = find
          .ancestor(
            of: find.text('Not needed'),
            matching: find.byType(Material),
          )
          .first;
      expect(
        tester.getTopLeft(menuCard).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(row).dy),
      );
      expect(
        tester.getTopLeft(row).dy,
        greaterThanOrEqualTo(0),
        reason: 'the row is on screen above the menu',
      );
      await tester.tap(find.text('Not needed'));
      await tester.pumpAndSettle();

      // Canvas 1 O8f: above the verb buttons, never over them.
      final toast = find.byType(SnackBar);
      expect(toast, findsOneWidget);
      final verbTop = tester.getTopLeft(find.text('Money in')).dy;
      // The card itself (the SnackBar's box also holds its outer margin).
      final card = find
          .descendant(of: toast, matching: find.byType(Material))
          .first;
      expect(tester.getBottomLeft(card).dy, lessThanOrEqualTo(verbTop));
      // The verbs stay tappable while it shows.
      expect(find.text('Money in').hitTestable(), findsOneWidget);

      // It leaves by itself once the Undo window closes; the choice stands.
      await tester.pump(const Duration(seconds: 9));
      expect(toast, findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(toast, findsNothing);
      expect(find.text('Finish Sandhu Family'), findsNothing);
      expect(
        jsonDecode(prefs.values[RkPrefKeys.setupBranch]!)['state'],
        'notNeeded',
      );
      await _unmount(tester);
    });

    testWidgets('F1-1007-5 only the branch row carries ⋮', (tester) async {
      final (ledger, personal, trust) = await _books(
        type: BookType.organization,
        branchName: 'Guru Nanak Sabha',
      );
      await _pump(
        tester,
        ledger,
        _prefs(
          openingDone: [personal, trust!],
          purpose: 'trust',
          branchState: 'open',
          branchBook: trust,
        ),
        bookInScope: personal,
      );
      expect(_more, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home.setup.row.finishTrust')),
          matching: _more,
        ),
        findsOneWidget,
      );
      await tester.tap(_more);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not needed'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Committee invites taken off your list. Invite from Menu any time.',
        ),
        findsOneWidget,
      );
      await _unmount(tester);
    });
  });

  group('F1-1007-6 the card leaves when every row is done (ruling 3)', () {
    testWidgets('F1-1007-6 myself: every required row ticked → the card '
        'leaves; Add your family never holds it open', (tester) async {
      final (ledger, personal, _) = await _books();
      await _firstEntry(ledger, personal);
      await _pump(
        tester,
        ledger,
        _prefs(openingDone: [personal], purpose: 'myself', sheetVerified: true),
        bookInScope: personal,
      );
      expect(find.byType(HomeSetupChecklist), findsNothing);
      expect(find.byType(HomePositionCard), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('F1-1007-6 the sheet not yet scanned back holds the card', (
      tester,
    ) async {
      final (ledger, personal, _) = await _books();
      await _firstEntry(ledger, personal);
      await _pump(
        tester,
        ledger,
        _prefs(openingDone: [personal], purpose: 'myself'),
        bookInScope: personal,
      );
      expect(find.byType(HomeSetupChecklist), findsOneWidget);
      await _unmount(tester);
    });

    for (final (state, leaves) in [
      ('open', false),
      ('done', true),
      ('notNeeded', true),
    ]) {
      testWidgets('F1-1007-6 family, everything else ticked, branch $state → '
          'the card ${leaves ? 'leaves' : 'stays'}', (tester) async {
        final (ledger, personal, fund) = await _books(
          type: BookType.family,
          branchName: 'Sandhu Family',
        );
        await _firstEntry(ledger, personal);
        await _pump(
          tester,
          ledger,
          _prefs(
            openingDone: [personal, fund!],
            purpose: 'family',
            branchState: state,
            branchBook: fund,
            sheetVerified: true,
          ),
          bookInScope: personal,
        );
        expect(
          find.byType(HomeSetupChecklist),
          leaves ? findsNothing : findsOneWidget,
        );
        await _unmount(tester);
      });
    }

    testWidgets('F1-1007-6 a finished branch row ticks and strikes through, '
        'with a chevron and no ⋮ (O8d)', (tester) async {
      final (ledger, personal, fund) = await _books(
        type: BookType.family,
        branchName: 'Sandhu Family',
      );
      await _pump(
        tester,
        ledger,
        _prefs(
          openingDone: [personal, fund!],
          purpose: 'family',
          branchState: 'done',
          branchBook: fund,
        ),
        bookInScope: personal,
      );
      expect(
        tester
            .widget<Text>(find.text('Finish Sandhu Family'))
            .style
            ?.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
      expect(_more, findsNothing);
      await _unmount(tester);
    });

    testWidgets('F1-1007-6 the rows survive a cold start — a new app over the '
        'same device store draws them again', (tester) async {
      final (ledger, personal, fund) = await _books(
        type: BookType.family,
        branchName: 'Sandhu Family',
      );
      final prefs = _prefs(
        openingDone: [personal, fund!],
        purpose: 'family',
        branchState: 'open',
        branchBook: fund,
      );
      await _pump(tester, ledger, prefs, bookInScope: personal);
      expect(find.text('Finish Sandhu Family'), findsOneWidget);
      await _unmount(tester);
      await _pump(tester, ledger, prefs, bookInScope: personal);
      expect(find.text('Finish Sandhu Family'), findsOneWidget);
      expect(find.text('Add your family'), findsNothing);
      await _unmount(tester);
    });

    // Layout sweep (07 §1 rule 11, 13 §8): the branch row and its ⋮ at 200 %
    // on both phones, in every language.
    for (final locale in rkLocales) {
      for (final size in rkPhones) {
        testWidgets('F1-1007-6 the family rows hold in ${locale.languageCode} '
            'at 200% on ${size.width.toInt()}x${size.height.toInt()}', (
          tester,
        ) async {
          final (ledger, personal, fund) = await _books(
            type: BookType.family,
            branchName: 'Sandhu Family',
          );
          await _pump(
            tester,
            ledger,
            _prefs(
              openingDone: [personal, fund!],
              purpose: 'family',
              branchState: 'open',
              branchBook: fund,
            ),
            bookInScope: personal,
            locale: locale,
            textScale: 2,
            viewport: size,
          );
          expect(tester.takeException(), isNull);
          await tester.dragUntilVisible(
            _more,
            find.byType(ListView),
            const Offset(0, -200),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expectTextFits(tester, reason: 'branch row at 200 %');
          expect(_more.hitTestable(), findsOneWidget);
          await _unmount(tester);
        });
      }
    }
  });
}
