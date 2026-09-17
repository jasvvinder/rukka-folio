// S1 Home's *In transit* line (07 §4 🔒, 07 §10 🔒, 02 §6 🔒, 13 §3.2 row S1).
//
//   F1-07-122 the line carries `Position.inTransitPaise` always, and the
//             07 §10 label with its ⏳ chip only while a reconciliation pair
//             touching this book is in transit — no pair, no label, the
//             figure alone.
//   F1-07-123 tapping the label opens S8.3 Family reconciliation while the
//             row keeps its own S1.1 drill-down, colour is never alone, and
//             both hold in EN/PA/HI at 200 % on 360×800.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_data.dart';
import 'package:rukka_folio/features/home/home_paths.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';
import 's1_home_screen_test.dart' show tallViewport, unmount;

/// A ledger holding two books with a posted inter-book movement between them
/// — 02 §6's pair, both halves present.
Future<({SeededLedger seed, String familyId})> _moved({
  required bool inTransit,
}) async {
  final seed = await seedSoloLedger();
  final familyId = await seed.ledger.createBook(
    name: 'Sharma Family',
    type: BookType.family,
    cashName: 'Family Cash',
  );
  final familyCash = (await seed.ledger.chartOf(familyId))
      .byClass(AccountClass.money)
      .firstWhere((a) => a.name == 'Family Cash');
  await seed.ledger.transferBetweenBooks(
    fromBookId: seed.bookId,
    fromAccountId: seed.bankId,
    toBookId: familyId,
    toAccountId: familyCash.id,
    paise: 5_000_00,
    date: seed.ledger.today(),
    // 02 §6 🔒: the half whose actor lacks posting rights carries the review
    // flag for that book's approver, and the pair reads *in transit* until it
    // is cleared. The flag is the engine's, not this screen's.
    reviewRequiredIn: (from: false, to: inTransit),
  );
  return (seed: seed, familyId: familyId);
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(HomeScreen)));

void main() {
  group('F1-07-122 the In transit line (07 §4 🔒 → 07 §10 🔒)', () {
    testWidgets(
      'F1-07-122 an in-transit pair draws the 07 §10 label with its ⏳ chip '
      'beside the figure, and the words are the ones S8.3 uses',
      (tester) async {
        tallViewport(tester);
        final m = await _moved(inTransit: true);
        await pumpRk(tester, const HomeScreen(), ledger: m.seed.ledger);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        // The figure is always the position's (02 §9) …
        expect(find.text(l10n.homePositionInTransit), findsOneWidget);
        // … and the label is the pair's.
        expect(find.byKey(HomeCardKeys.inTransitChip), findsOneWidget);
        expect(
          find.text(l10n.reportsReconciliationInTransitDetail),
          findsOneWidget,
          reason: 'one vocabulary on Home and on S8.3',
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-122 no pair in transit: the figure alone, no label (07 §4)',
      (tester) async {
        tallViewport(tester);
        final m = await _moved(inTransit: false);
        await pumpRk(tester, const HomeScreen(), ledger: m.seed.ledger);
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        expect(find.text(l10n.homePositionInTransit), findsOneWidget);
        expect(find.byKey(HomeCardKeys.inTransitChip), findsNothing);
        expect(
          find.text(l10n.reportsReconciliationInTransitDetail),
          findsNothing,
        );
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-122 a book with no movement at all has no label either',
      (tester) async {
        tallViewport(tester);
        final seed = await seedSoloLedger();
        await pumpRk(tester, const HomeScreen(), ledger: seed.ledger);
        await tester.pumpAndSettle();
        expect(find.byKey(HomeCardKeys.inTransitChip), findsNothing);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-122 the snapshot carries only the pairs touching this book, and '
      'only while they are in transit (02 §6 🔒)',
      (tester) async {
        final m = await _moved(inTransit: true);
        final snap = (await tester.runAsync(
          () => watchHome(
            m.seed.ledger,
            m.seed.bookId,
            today: m.seed.ledger.today(),
            month: m.seed.ledger.today().yearMonth,
          ).firstWhere((s) => s.hasInTransitPair),
        ))!;
        expect(snap.inTransitPairs, hasLength(1));
        final pair = snap.inTransitPairs.single;
        expect(pair.inTransit, isTrue);
        expect([
          pair.bookId,
          pair.counterpartBookId,
        ], containsAll([m.seed.bookId, m.familyId]));
        // The figure and the label are two different facts: the label comes
        // from the pair, the figure from the position (02 §9).
        expect(snap.position.inTransitPaise, isNot(0));
      },
    );
  });

  group('F1-07-123 the label is a door, the row keeps its own', () {
    testWidgets(
      'F1-07-123 tapping the label opens S8.3 while the row still drills to '
      'S1.1 (07 §10 🔒, 07 §4 🔒)',
      (tester) async {
        tallViewport(tester);
        final m = await _moved(inTransit: true);
        var reconciliation = 0;
        PositionLine? drilled;
        await pumpRk(
          tester,
          HomeScreen(
            onOpenReconciliation: () => reconciliation++,
            onOpenPosition: (line) => drilled = line,
          ),
          ledger: m.seed.ledger,
        );
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        await tester.tap(find.byKey(HomeCardKeys.inTransitChip));
        await tester.pumpAndSettle();
        expect(reconciliation, 1);
        expect(drilled, isNull);

        await tester.tap(find.text(l10n.homePositionInTransit));
        await tester.pumpAndSettle();
        expect(drilled, PositionLine.inTransit);
        expect(reconciliation, 1, reason: 'one row, two labelled destinations');
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-123 colour is never alone: the ⏳ icon and the words carry the '
      'state, and the tint is the pending token (07 §1 rule 3 🔒)',
      (tester) async {
        tallViewport(tester);
        final m = await _moved(inTransit: true);
        await pumpRk(
          tester,
          HomeScreen(onOpenReconciliation: () {}),
          ledger: m.seed.ledger,
        );
        await tester.pumpAndSettle();
        final l10n = _l10n(tester);

        final chip = find.byKey(HomeCardKeys.inTransitChip);
        expect(
          find.descendant(
            of: chip,
            matching: find.byIcon(Icons.hourglass_empty),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: chip,
            matching: find.text(l10n.reportsReconciliationInTransitDetail),
          ),
          findsOneWidget,
        );
        final status = RkStatusColors.of(
          tester.element(find.byType(HomeScreen)),
        );
        final word = tester.widget<Text>(
          find.descendant(
            of: chip,
            matching: find.text(l10n.reportsReconciliationInTransitDetail),
          ),
        );
        expect(word.style?.color, status.pending);
        // The pair is announced to a screen reader as a button with its
        // destination, not as a colour.
        final semantics = tester.widget<Semantics>(
          find.descendant(of: chip, matching: find.byType(Semantics)).first,
        );
        expect(semantics.properties.button, isTrue);
        expect(semantics.properties.hint, l10n.homePositionInTransitAction);
        await unmount(tester);
      },
    );

    testWidgets(
      'F1-07-123 EN, PA and HI at 200 % on 360×800: the label wraps and '
      'nothing is cut (07 §1 rules 9 and 11)',
      (tester) async {
        for (final locale in rkLocales) {
          final m = await _moved(inTransit: true);
          await pumpRk(
            tester,
            const HomeScreen(),
            ledger: m.seed.ledger,
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expectTextFits(
            tester,
            reason: '${locale.languageCode} · In transit at 200 %',
          );
          await unmount(tester);
        }
      },
    );
  });
}
