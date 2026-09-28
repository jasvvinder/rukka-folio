// F1-24b-7 — read-only blocks amend, reverse and S3.1's opening balance (ADR
// 2026-09-24b §13): each refuses under a server-declared lapse, raises the
// S12.5 read-only sheet, appends **no envelope** to the real ledger, and
// keeps what the person typed; book full blocks only the book it names.
//
// Every "nothing appended" is a count of the real in-memory ledger's
// `envelopes_local`, so a gate that let the write through would fail here.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ledger/screens/s3_1_quick_add_sheet.dart';
import 'package:rukka_folio/features/ledger/screens/s4_1_entry_detail_screen.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../../shared/test_app.dart';
import '../entry/restriction_support.dart';

Entry _moneyOut(SeededLedger seed) =>
    seed.entries.firstWhere((e) => e.kind == EntryKind.moneyOut);

Future<void> _pumpDetail(
  WidgetTester tester,
  SeededLedger seed, {
  bool lapsed = true,
  FakeSyncClient? sync,
}) => pumpUnderEntitlement(
  tester,
  EntryDetailScreen(entryId: _moneyOut(seed).id),
  ledger: seed.ledger,
  entitlement: lapsed ? lapsedSource() : null,
  sync: sync,
  viewport: const Size(500, 2400),
);

Future<void> _pumpQuickAdd(
  WidgetTester tester,
  SeededLedger seed, {
  bool lapsed = true,
  FakeSyncClient? sync,
}) async {
  await pumpUnderEntitlement(
    tester,
    Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => QuickAddSheet(bookId: seed.bookId),
          ),
          child: const Text('open'),
        ),
      ),
    ),
    ledger: seed.ledger,
    entitlement: lapsed ? lapsedSource() : null,
    sync: sync,
    viewport: const Size(400, 1600),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// S3.1 step 2 for a bank: name + opening balance, then Save.
Future<void> _quickAddBank(WidgetTester tester) async {
  await tester.tap(find.text('Bank'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Name'), 'PNB Saving');
  await tester.enterText(
    find.widgetWithText(TextField, 'Opening balance'),
    '1200',
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await settleIo(tester);
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  testWidgets('F1-24b-7 ledger reverse under a lapse raises the read-only '
      'sheet, appends nothing, and keeps the typed reason', (tester) async {
    final seed = await seedSoloLedger();
    await _pumpDetail(tester, seed);
    final before = await envelopeCount(tester, seed.ledger);

    await tester.tap(find.text('Reverse this'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Typed twice');
    await tester.tap(find.text('Post the reversal'));
    await settleIo(tester);

    expectReadOnlySheet(tester);
    expect(await envelopeCount(tester, seed.ledger), before);
    await dismissRestrictionSheet(tester);
    expect(find.text('Reverse this entry'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Typed twice'), findsOneWidget);
    expect(await envelopeCount(tester, seed.ledger), before);
    await unmountTree(tester);
  });

  testWidgets('F1-24b-7 ledger amend under a lapse raises the read-only '
      'sheet, appends nothing, and keeps the edited note', (tester) async {
    final seed = await seedSoloLedger();
    await _pumpDetail(tester, seed);
    final before = await envelopeCount(tester, seed.ledger);

    await tester.tap(find.text('Correct this'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Diesel for the tractor',
    );
    await tester.tap(find.text('Save the correction'));
    await settleIo(tester);

    expectReadOnlySheet(tester);
    expect(await envelopeCount(tester, seed.ledger), before);
    await dismissRestrictionSheet(tester);
    expect(find.text('Correct this entry'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Diesel for the tractor'),
      findsOneWidget,
    );
    expect(await envelopeCount(tester, seed.ledger), before);
    await unmountTree(tester);
  });

  testWidgets('F1-24b-7 ledger reverse under book full blocks only the book '
      'it names', (tester) async {
    var seed = await seedSoloLedger();
    await _pumpDetail(
      tester,
      seed,
      lapsed: false,
      sync: FakeSyncClient()..fullBooks.add('some-other-book'),
    );
    var before = await envelopeCount(tester, seed.ledger);
    await tester.tap(find.text('Reverse this'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post the reversal'));
    await settleIo(tester);
    expect(raisedSheetKind(tester), isNull);
    expect(await envelopeCount(tester, seed.ledger), greaterThan(before));
    await unmountTree(tester);

    seed = await seedSoloLedger();
    await _pumpDetail(
      tester,
      seed,
      lapsed: false,
      sync: FakeSyncClient()..fullBooks.add(seed.bookId),
    );
    before = await envelopeCount(tester, seed.ledger);
    await tester.tap(find.text('Reverse this'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post the reversal'));
    await settleIo(tester);
    expect(raisedSheetKind(tester), RkRestrictionKind.bookFull);
    expect(await envelopeCount(tester, seed.ledger), before);
    await unmountTree(tester);
  });

  testWidgets('F1-24b-7 ledger S3.1 opening balance under a lapse raises the '
      'read-only sheet, creates neither account nor balance, and keeps the '
      'name and amount', (tester) async {
    final seed = await seedSoloLedger();
    await _pumpQuickAdd(tester, seed);
    final before = await envelopeCount(tester, seed.ledger);
    await _quickAddBank(tester);

    expectReadOnlySheet(tester);
    expect(await envelopeCount(tester, seed.ledger), before);
    await dismissRestrictionSheet(tester);
    expect(find.widgetWithText(TextField, 'PNB Saving'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1200'), findsOneWidget);
    expect(await envelopeCount(tester, seed.ledger), before);
    await unmountTree(tester);
  });

  testWidgets('F1-24b-7 ledger S3.1 under book full blocks only the book it '
      'names', (tester) async {
    var seed = await seedSoloLedger();
    await _pumpQuickAdd(
      tester,
      seed,
      lapsed: false,
      sync: FakeSyncClient()..fullBooks.add('some-other-book'),
    );
    var before = await envelopeCount(tester, seed.ledger);
    await _quickAddBank(tester);
    expect(raisedSheetKind(tester), isNull);
    expect(await envelopeCount(tester, seed.ledger), greaterThan(before));
    await unmountTree(tester);

    seed = await seedSoloLedger();
    await _pumpQuickAdd(
      tester,
      seed,
      lapsed: false,
      sync: FakeSyncClient()..fullBooks.add(seed.bookId),
    );
    before = await envelopeCount(tester, seed.ledger);
    await _quickAddBank(tester);
    expect(raisedSheetKind(tester), RkRestrictionKind.bookFull);
    expect(await envelopeCount(tester, seed.ledger), before);
    await unmountTree(tester);
  });
}
