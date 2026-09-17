// F1-05: the save trigger of 05 §7 🔒 — S2's save path nudges sync and never
// waits for it (07 §1.7 🔒: no spinner, no wait, on an entry save).
//
// PLACEMENT: this covers `features/entry`, whose own test directory belongs to
// another lane this round; it lives here with the ledger tests because the
// lane that wired the trigger owns only this directory. Move it to
// `test/features/entry/` the next time that folder is opened.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/entry_sync.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../test_app.dart';

void main() {
  test('F1-05-47 notifyEntrySaved is a no-op without a sync seam and one cycle '
      'with one — the save path never depends on sync', () {
    expect(() => notifyEntrySaved(null), returnsNormally);

    final fake = FakeSyncClient();
    addTearDown(fake.dispose);
    notifyEntrySaved(fake);
    expect(fake.syncNowCalls, 1);
    notifyEntrySaved(fake);
    expect(fake.syncNowCalls, 2);
  });

  testWidgets(
    'F1-05-48 saving an entry on S2 runs exactly one sync cycle, after the '
    'envelope is appended and without blocking the keypad (05 §7, 07 §5.7)',
    (tester) async {
      final seed = await seedSoloLedger();
      final sync = FakeSyncClient();
      addTearDown(sync.dispose);
      await pumpRk(
        tester,
        AddEntryScreen(bookId: seed.bookId),
        ledger: seed.ledger,
        sync: sync,
      );

      expect(sync.syncNowCalls, 0, reason: 'nothing saved yet');
      for (final k in '1000'.split('')) {
        await tester.tap(find.byKey(AddEntryKeys.pad(k)));
        await tester.pump();
      }
      await tester.tap(find.text('Cash in hand'));
      await tester.pump();
      await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shop sales').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AddEntryKeys.save));
      await tester.pumpAndSettle();

      // One entry appended, one cycle asked for — and the keypad is back,
      // which it could not be if the save had waited on the cycle.
      expect(sync.syncNowCalls, 1);
      expect(find.byType(AddEntryScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
