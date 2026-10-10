// F1-183 — desk 183 (b): S2's *Saved ✓* toast leaves on its own.
//
// 13 §4.2 gives the toast *the 10 s Undo* — after which it goes. Flutter ≥
// 3.29 keeps a SnackBar that carries an action up until it is tapped
// (`persist` defaults to true when there is an action), so the toast sat over
// the keypad and Save with Undo as the only way out (07 §1 rules 1–2 🔒). The
// fix is the one SETUP174 made for S1's *Not needed* toast: `persist: false`.
//
// Both production save paths are driven: the single-entry Save and the
// between-books Save (02 §6), each through the real in-memory ledger.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';

import '../../shared/test_app.dart';
import 'restriction_support.dart';

Future<void> _typeAmount(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tester.tap(find.byKey(AddEntryKeys.pad(k)));
    await tester.pump();
  }
}

Future<void> _pick(WidgetTester tester, EntrySlot slot, String name) async {
  await tester.tap(find.byKey(AddEntryKeys.slot(slot)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

/// The toast is still up just inside its 10 seconds, and gone just after.
Future<void> _expectLeavesAfterTenSeconds(WidgetTester tester) async {
  expect(find.byKey(AddEntryKeys.savedMessage), findsOneWidget);
  expect(
    tester.widget<SnackBar>(find.byType(SnackBar)).persist,
    isFalse,
    reason: 'an action must not pin the toast (Flutter ≥ 3.29 default)',
  );
  await tester.pump(const Duration(seconds: 8));
  expect(
    find.byKey(AddEntryKeys.savedMessage),
    findsOneWidget,
    reason: 'Undo stays for its 10 seconds (13 §4.2)',
  );
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
  expect(find.byKey(AddEntryKeys.savedMessage), findsNothing);
  expect(find.byType(SnackBar), findsNothing);
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  testWidgets('F1-183-1 entry the Saved toast of a single entry leaves on '
      'its own after 10 seconds', (tester) async {
    final s = await seedSoloLedger();
    await pumpRk(
      tester,
      AddEntryScreen(bookId: s.bookId, kind: EntryKind.moneyOut),
      ledger: s.ledger,
    );
    await _typeAmount(tester, '2400');
    await _pick(tester, EntrySlot.money, 'Cash in hand');
    await _pick(tester, EntrySlot.ledger, 'Diesel');
    await tester.tap(find.byKey(AddEntryKeys.save));
    await settleIo(tester);
    await _expectLeavesAfterTenSeconds(tester);
    await unmountTree(tester);
  });

  testWidgets('F1-183-2 entry the Saved toast of a between-books movement '
      'leaves on its own after 10 seconds', (tester) async {
    final s = await seedSoloLedger();
    const familyCash = 'Family Cash';
    final familyId = (await tester.runAsync(
      () => s.ledger.createBook(
        name: 'Sharma Family',
        type: BookType.family,
        cashName: familyCash,
      ),
    ))!;
    await pumpRk(
      tester,
      AddEntryScreen(bookId: s.bookId, kind: EntryKind.transfer),
      ledger: s.ledger,
    );
    await _typeAmount(tester, '5000');
    await tester.tap(find.text('SBI Saving').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AddEntryKeys.book(familyId)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(familyCash).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AddEntryKeys.save));
    await settleIo(tester);
    await _expectLeavesAfterTenSeconds(tester);
    await unmountTree(tester);
  });
}
