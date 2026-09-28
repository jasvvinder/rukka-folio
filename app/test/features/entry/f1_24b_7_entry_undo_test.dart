// F1-24b-7 — the one exception (ADR 2026-09-24b §13): the 10-second Undo of
// an entry this phone just saved is **not** blocked by read-only. An entry is
// saved while the tenant is live, the server then declares the lapse, and
// Undo still appends its reversal — while a fresh Save on the same screen is
// refused with the S12.5 sheet, which proves the lapse really is in force.
//
// Both arms of that exception are pinned: the single-entry Undo and the
// between-books Undo, which reverses both halves of the pair (02 §6).
//
// And the other side of the line: S2's inline *new A/C* appends an envelope,
// so it is **not** the exception — read-only refuses it with the same sheet
// S3.1 raises for the same `addAccount` write.
//
// Counted in the real in-memory ledger (`entries_p`, `envelopes_local`): the
// reversal is an appended envelope, never a delete (02 §5).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../../shared/test_app.dart';
import 'restriction_support.dart';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AddEntryScreen)));

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

Future<void> _fillMoneyOut(WidgetTester tester) async {
  await _typeAmount(tester, '2400');
  await _pick(tester, EntrySlot.money, 'Cash in hand');
  await _pick(tester, EntrySlot.ledger, 'Diesel');
}

Future<int> _entryCount(WidgetTester tester, SeededLedger s) async =>
    (await tester.runAsync(
      () => s.ledger.db.customSelect('SELECT id FROM entries_p').get(),
    ))!.length;

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  testWidgets('F1-24b-7 entry the 10-second Undo still appends its reversal '
      'after the lapse lands, while a new Save is refused', (tester) async {
    final s = await seedSoloLedger();
    final source = FakeEntitlementSource(); // live: untokened, Free
    await pumpRk(
      tester,
      EntitlementScope(
        source: source,
        child: AddEntryScreen(bookId: s.bookId, kind: EntryKind.moneyOut),
      ),
      ledger: s.ledger,
    );
    final l10n = _l10n(tester);
    final before = await _entryCount(tester, s);
    await _fillMoneyOut(tester);
    await tester.tap(find.byKey(AddEntryKeys.save));
    await settleIo(tester);
    expect(await _entryCount(tester, s), before + 1, reason: 'saved live');
    expect(find.text(l10n.entryUndo), findsOneWidget);

    // Seconds later the server declares the lapse (a fresh token).
    source.entitlement = entitlementReading(EntitlementGraceKind.lapsed);

    // A new entry is refused with the S12.5 sheet — the lapse is in force.
    // Both sides are kept after a save (07 §5 step 7), so only the amount is
    // typed; Save is pressed through the button itself because the Undo
    // snackbar sits over it for the 10 seconds this test lives inside.
    await _typeAmount(tester, '2400');
    tester.widget<ElevatedButton>(find.byKey(AddEntryKeys.save)).onPressed!();
    await settleIo(tester);
    expect(raisedSheetKind(tester), RkRestrictionKind.readOnly);
    expect(await _entryCount(tester, s), before + 1);
    await dismissRestrictionSheet(tester);

    // …but the Undo of the entry this phone just saved still works.
    final reads = source.reads;
    await tester.tap(find.text(l10n.entryUndo));
    await settleIo(tester);
    expect(raisedSheetKind(tester), isNull, reason: 'Undo raises no sheet');
    expect(find.text(l10n.entryUndone), findsOneWidget);
    expect(
      await _entryCount(tester, s),
      before + 2,
      reason: 'the reversal is appended, the original kept (02 §5)',
    );
    expect(source.reads, reads, reason: 'Undo never consults the gate');
    await unmountTree(tester);
  });

  testWidgets('F1-24b-7 entry the between-books Undo still reverses both '
      'halves after the lapse lands', (tester) async {
    final s = await seedSoloLedger();
    const familyCash = 'Family Cash';
    final familyId = (await tester.runAsync(
      () => s.ledger.createBook(
        name: 'Sharma Family',
        type: BookType.family,
        cashName: familyCash,
      ),
    ))!;
    final source = FakeEntitlementSource(); // live: untokened, Free
    await pumpRk(
      tester,
      EntitlementScope(
        source: source,
        child: AddEntryScreen(bookId: s.bookId, kind: EntryKind.transfer),
      ),
      ledger: s.ledger,
    );
    final l10n = _l10n(tester);
    final before = await _entryCount(tester, s);
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
    expect(
      await _entryCount(tester, s),
      before + 2,
      reason: 'saved live: one envelope per book (02 §6)',
    );
    expect(find.text(l10n.entryUndo), findsOneWidget);

    // Seconds later the server declares the lapse (a fresh token).
    source.entitlement = entitlementReading(EntitlementGraceKind.lapsed);
    final reads = source.reads;

    await tester.tap(find.text(l10n.entryUndo));
    await settleIo(tester);
    expect(raisedSheetKind(tester), isNull, reason: 'Undo raises no sheet');
    expect(find.text(l10n.entryUndone), findsOneWidget);
    expect(
      await _entryCount(tester, s),
      before + 4,
      reason: 'both halves reversed, never one (02 §6); originals kept',
    );
    expect(source.reads, reads, reason: 'Undo never consults the gate');
    await unmountTree(tester);
  });

  testWidgets('F1-24b-7 entry S2 inline new A/C is refused under a lapse: '
      'no envelope, the picker and the typed name kept', (tester) async {
    final s = await seedSoloLedger();
    await pumpRk(
      tester,
      EntitlementScope(
        source: lapsedSource(),
        child: AddEntryScreen(bookId: s.bookId, kind: EntryKind.tookCredit),
      ),
      ledger: s.ledger,
    );
    final before = await envelopeCount(tester, s.ledger);
    await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AddEntryKeys.search), 'Vardhman Dairy');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AddEntryKeys.create));
    await settleIo(tester);

    expectReadOnlySheet(tester);
    expect(
      await envelopeCount(tester, s.ledger),
      before,
      reason: 'a new A/C is an envelope; read-only appends none (§13)',
    );
    await dismissRestrictionSheet(tester);
    expect(find.byKey(AddEntryKeys.create), findsOneWidget);
    expect(find.text('Vardhman Dairy'), findsWidgets);
    await unmountTree(tester);
  });
}
