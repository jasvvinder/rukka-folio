// F1-24b-16 — S10.3 *Re-date to today* under read-only (ADR 2026-09-24b §13;
// 13 §3.2 row S12.5; 07 §13 🔒, 02 §8 🔒).
//
// A re-date is an **amend** (02 §5, 02 §8): a new envelope, so read-only
// refuses it with the same S12.5 sheet ENT2 raises for S4.1's amend, through
// the same `refuseIfEntryRestricted` gate. Book full keeps its narrower,
// per-book scope (ADR 2026-09-05b §7). Nothing moves, the card stays, and the
// sheet's way forward is S12.1 Plans (07 §1 rule 6).
//
// Test-honesty: the tray is [FakeLateArrivals], which records every re-date it
// is asked for. A gate that answered "allowed" unconditionally would let the
// tap reach `redateToToday`, and every `redated, isEmpty` below would fail;
// the untokened case proves the same tap does reach it when nothing blocks.
// Nothing here is a real number or name (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:async';

import 'package:core_ledger/core_ledger.dart' show LocalDate, YearMonth;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/late_arrivals.dart';
import 'package:rukka_folio/features/inbox/screens/s10_3_late_arrivals_screen.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../entry/restriction_support.dart';

LateArrivalItem _item() => LateArrivalItem(
  entryId: 'e1',
  bookId: 'b1',
  bookName: 'Test Book',
  lockedPeriod: YearMonth(2026, 8),
  date: LocalDate(2026, 8, 29),
  paise: 1_000_00,
  fromLabel: 'Sales',
  toLabel: 'Cash',
  note: null,
  lockedOn: LocalDate(2026, 9, 2),
  closedYear: null,
);

/// A slow entitlement read, so a second tap can land before the first tap's
/// sheet rises.
final class _HeldSource extends FakeEntitlementSource {
  _HeldSource({super.entitlement});

  final hold = Completer<void>();

  @override
  Future<Entitlement> read() async {
    await hold.future;
    return super.read();
  }
}

Future<FakeLateArrivals> _pump(
  WidgetTester tester, {
  EntitlementSource? entitlement,
  FakeSyncClient? sync,
}) async {
  final tray = FakeLateArrivals(initial: LateArrivalsTray(items: [_item()]));
  addTearDown(tray.dispose);
  await pumpUnderEntitlement(
    tester,
    LateArrivalsScope(
      tray: tray,
      child: LateArrivalsScreen(onDone: () {}),
    ),
    entitlement: entitlement,
    sync: sync,
  );
  return tray;
}

const _redate = 'Re-date to today';

void main() {
  group('F1-24b-16 S10.3 re-date is an amend: read-only refuses it', () {
    testWidgets('F1-24b-16 lapsed: the read-only sheet rises, nothing is '
        're-dated, and the card is still there with its action', (
      tester,
    ) async {
      final tray = await _pump(tester, entitlement: lapsedSource());

      await tester.tap(find.text(_redate));
      await settleIo(tester);

      expectReadOnlySheet(tester);
      expect(tray.redated, isEmpty);

      await dismissRestrictionSheet(tester);
      // No dead end (07 §1 rule 6): the card and its action are back, live.
      final button = find.ancestor(
        of: find.text(_redate),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(button, findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
      expect(tray.redated, isEmpty);
      await unmountTree(tester);
    });

    testWidgets('F1-24b-16 untokened (Free, never locked): the same tap '
        're-dates the entry', (tester) async {
      final tray = await _pump(tester);

      await tester.tap(find.text(_redate));
      await settleIo(tester);

      expect(raisedSheetKind(tester), isNull);
      expect(tray.redated, ['e1']);
      await unmountTree(tester);
    });

    testWidgets('F1-24b-16 the entry\'s own book is full: the book-full sheet, '
        'nothing re-dated', (tester) async {
      final sync = FakeSyncClient()..fullBooks.add('b1');
      final tray = await _pump(tester, sync: sync);

      await tester.tap(find.text(_redate));
      await settleIo(tester);

      expect(raisedSheetKind(tester), RkRestrictionKind.bookFull);
      expect(tray.redated, isEmpty);
      // Dismissed, still nothing written: the refusal is not a delay.
      await dismissRestrictionSheet(tester);
      expect(tray.redated, isEmpty);
      await unmountTree(tester);
    });

    testWidgets('F1-24b-16 another book being full does not block this one', (
      tester,
    ) async {
      final sync = FakeSyncClient()..fullBooks.add('some-other-book');
      final tray = await _pump(tester, sync: sync);

      await tester.tap(find.text(_redate));
      await settleIo(tester);

      expect(raisedSheetKind(tester), isNull);
      expect(tray.redated, ['e1']);
      await unmountTree(tester);
    });

    testWidgets('F1-24b-16 lapsed with a slow read: a double tap raises one '
        'sheet and re-dates nothing', (tester) async {
      final held = _HeldSource(entitlement: lapsedSource().entitlement);
      final tray = await _pump(tester, entitlement: held);

      // Two taps before any frame: the second lands on the same live button,
      // so only the tile's own busy guard stops a second sheet.
      await tester.tap(find.text(_redate));
      await tester.tap(find.text(_redate));
      await tester.pump();
      held.hold.complete();
      await settleIo(tester);

      expect(find.byType(RkBlockedEntrySheet), findsOneWidget);
      expect(tray.redated, isEmpty);
      // Dismissed, still nothing written: the refusal is not a delay.
      await dismissRestrictionSheet(tester);
      expect(tray.redated, isEmpty);
      await unmountTree(tester);
    });
  });
}
