// F1-24b-7 — read-only blocks advances (ADR 2026-09-24b §13): S5's *Add spend*
// and *Return remaining* sheets refuse to post under a server-declared lapse,
// raise the S12.5 read-only sheet, append no envelope, and keep the typed
// amount; book full blocks only the book it names. Amounts are synthetic
// (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/advances/screens/s5_advances_screen.dart';
import 'package:rukka_folio/features/advances/widgets/advance_entry_sheet.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../entry/restriction_support.dart';
import 's5_advances_test.dart' show seedAdvances;

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  Future<void> openAndSave(
    WidgetTester tester,
    String door,
    String amount,
  ) async {
    await tester.tap(find.text(door));
    await tester.pumpAndSettle();
    expect(find.byType(AdvanceEntrySheet), findsOneWidget);
    await tester.enterText(find.byType(TextField), amount);
    await tester.tap(find.text('Save'));
    await settleIo(tester);
  }

  for (final door in ['Add spend', 'Return remaining']) {
    testWidgets('F1-24b-7 advances $door under a lapse raises the read-only '
        'sheet, appends nothing, and keeps the amount', (tester) async {
      final f = await seedAdvances();
      await pumpUnderEntitlement(
        tester,
        AdvancesScreen(bookId: f.bookId),
        ledger: f.ledger,
        entitlement: lapsedSource(),
      );
      final before = await envelopeCount(tester, f.ledger);
      await openAndSave(tester, door, '100');

      expectReadOnlySheet(tester);
      expect(await envelopeCount(tester, f.ledger), before);

      await dismissRestrictionSheet(tester);
      expect(find.byType(AdvanceEntrySheet), findsOneWidget);
      expect(find.widgetWithText(TextField, '100'), findsOneWidget);
      expect(await envelopeCount(tester, f.ledger), before);
      await unmountTree(tester);
    });
  }

  testWidgets('F1-24b-7 advances book full blocks only the book it names', (
    tester,
  ) async {
    final f = await seedAdvances();
    final elsewhere = FakeSyncClient()..fullBooks.add('some-other-book');
    await pumpUnderEntitlement(
      tester,
      AdvancesScreen(bookId: f.bookId),
      ledger: f.ledger,
      sync: elsewhere,
    );
    var before = await envelopeCount(tester, f.ledger);
    await openAndSave(tester, 'Add spend', '100');
    expect(raisedSheetKind(tester), isNull);
    expect(find.byType(AdvanceEntrySheet), findsNothing, reason: 'posted');
    expect(await envelopeCount(tester, f.ledger), greaterThan(before));
    await unmountTree(tester);

    final here = FakeSyncClient()..fullBooks.add(f.bookId);
    await pumpUnderEntitlement(
      tester,
      AdvancesScreen(bookId: f.bookId),
      ledger: f.ledger,
      sync: here,
    );
    before = await envelopeCount(tester, f.ledger);
    await openAndSave(tester, 'Add spend', '100');
    expect(raisedSheetKind(tester), RkRestrictionKind.bookFull);
    expect(await envelopeCount(tester, f.ledger), before);
    await unmountTree(tester);
  });
}
