// F1-24b-7 — read-only blocks every new envelope (ADR 2026-09-24b §13), and
// onboarding writes two kinds:
//
//   * **the book itself** — each host's commit step runs `createBook` (its
//     book_config and seeded chart). Under a lapse it is refused before any
//     envelope is written, with the S12.5 sheet and a *Try again* that is
//     never a dead end. This is the S9.5 *Add a business* path after
//     onboarding (books_routes → [BusinessOpeningHost]).
//   * **the opening balances** — S0.6b, S0.6f and S0.6i each refuse to post
//     under a lapse that lands after the book exists, raise the S12.5 sheet
//     once (a double tap stacks no second sheet), append nothing and keep the
//     typed figures; book full blocks only the book it names; and a double
//     tap on Save posts the balances once.
//
// Every "nothing appended" is a count of the real in-memory ledger's
// `envelopes_local`, so a gate that let the write through would fail here.
@Tags(['F1'])
library;

import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_flow.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a_business_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6d_family_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6g_trust_name_screen.dart';
import 'package:rukka_folio/features/onboarding/widgets/business_opening_host.dart';
import 'package:rukka_folio/features/onboarding/widgets/family_opening_host.dart';
import 'package:rukka_folio/features/onboarding/widgets/trust_opening_host.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../../shared/test_app.dart';
import '../entry/restriction_support.dart';

final _start = LocalDate(2026, 9, 7);

typedef _Branch = ({
  String name,
  Widget Function(OnboardingFlow flow, VoidCallback onDone) host,
  OnboardingFlow Function() flow,
  String? Function(OnboardingFlow flow) bookId,
});

final _branches = <_Branch>[
  (
    name: 'business S0.6b',
    flow: () => OnboardingFlow()
      ..setYourName('Amrit Kaur')
      ..setBusiness(
        const BusinessDraft(
          name: 'Amrit Kaur Agri',
          ownership: BusinessOwnershipChoice.justMe,
          fyStartMonth: 4,
        ),
      )
      ..setOwners(const []),
    host: (flow, onDone) =>
        BusinessOpeningHost(flow: flow, startDate: _start, onDone: onDone),
    bookId: (flow) => flow.businessBookId,
  ),
  (
    name: 'family S0.6f',
    flow: () => OnboardingFlow()
      ..setYourName('Amrit Kaur')
      ..setFamily(const FamilyDraft(name: 'Sharma Family')),
    host: (flow, onDone) =>
        FamilyOpeningHost(flow: flow, startDate: _start, onDone: onDone),
    bookId: (flow) => flow.familyBookId,
  ),
  (
    name: 'trust S0.6i',
    flow: () => OnboardingFlow()
      ..setYourName('Amrit Kaur')
      ..setTrust(
        const TrustDraft(
          name: 'Guru Nanak Gurudwara',
          type: TrustType.gurudwara,
        ),
      ),
    host: (flow, onDone) =>
        TrustOpeningHost(flow: flow, startDate: _start, onDone: onDone),
    bookId: (flow) => flow.trustBookId,
  ),
];

/// A fake whose [read] waits on [hold] while it is set — a slow entitlement
/// read, so a second tap can land before the first Save's sheet rises (the
/// Navigator absorbs pointers from the moment a sheet is pushed).
final class _HeldSource extends FakeEntitlementSource {
  Completer<void>? hold;

  @override
  Future<Entitlement> read() async {
    final h = hold;
    if (h != null) await h.future;
    return super.read();
  }
}

Future<void> _typeAndSave(
  WidgetTester tester, {
  int taps = 1,
  _HeldSource? held,
}) async {
  await tester.enterText(find.byType(TextField).first, '2500');
  await tester.pumpAndSettle();
  final hold = held == null ? null : (held.hold = Completer<void>());
  // A double tap is two taps before the first Save's await has let anything
  // settle.
  for (var i = 0; i < taps; i++) {
    await tester.tap(find.byType(FilledButton).first);
  }
  hold?.complete();
  if (held != null) held.hold = null;
  await settleIo(tester);
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  for (final b in _branches) {
    testWidgets('F1-24b-7 onboarding ${b.name} creating the book under a '
        'lapse raises the read-only sheet and appends nothing; Try again '
        'after renewal creates it', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo(firstBookName: 'Me');
      final before = await envelopeCount(tester, ledger);
      final flow = b.flow();
      final source = lapsedSource();
      await pumpUnderEntitlement(
        tester,
        b.host(flow, () {}),
        ledger: ledger,
        entitlement: source,
        viewport: const Size(420, 3200),
      );

      expectReadOnlySheet(tester);
      expect(b.bookId(flow), isNull, reason: 'createBook never ran');
      expect(await envelopeCount(tester, ledger), before);
      await dismissRestrictionSheet(tester);
      // Colour never alone: the lock and the words say why (07 §1).
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text(l10n.subscriptionBannerReadOnlyTitle), findsOneWidget);
      expect(await envelopeCount(tester, ledger), before);

      // The plan is renewed; *Try again* is the way on, never a dead end.
      source.entitlement = Entitlement.untokened();
      await tester.tap(find.byType(FilledButton).first);
      await settleIo(tester);
      expect(raisedSheetKind(tester), isNull);
      expect(b.bookId(flow), isNotNull);
      expect(await envelopeCount(tester, ledger), greaterThan(before));
      await unmountTree(tester);
    });

    testWidgets('F1-24b-7 onboarding ${b.name} opening balances under a lapse '
        'raise the read-only sheet once, post nothing, and keep the figures', (
      tester,
    ) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo(firstBookName: 'Me');
      final flow = b.flow();
      var done = 0;
      // Live while the book is created; the lapse lands before Save.
      final source = _HeldSource();
      await pumpUnderEntitlement(
        tester,
        b.host(flow, () => done++),
        ledger: ledger,
        entitlement: source,
        viewport: const Size(420, 3200),
      );
      expect(b.bookId(flow), isNotNull);
      source.entitlement = entitlementReading(EntitlementGraceKind.lapsed);
      final before = await envelopeCount(tester, ledger);
      await _typeAndSave(tester, taps: 2, held: source);

      expect(
        find.byType(RkBlockedEntrySheet),
        findsOneWidget,
        reason: 'a double tap raises one sheet, not two stacked',
      );
      expectReadOnlySheet(tester);
      expect(done, 0, reason: 'the step does not move on');
      expect(await envelopeCount(tester, ledger), before);
      await dismissRestrictionSheet(tester);
      expect(find.widgetWithText(TextField, '2500'), findsOneWidget);
      expect(await envelopeCount(tester, ledger), before);
      await unmountTree(tester);
    });
  }

  testWidgets('F1-24b-7 onboarding a double tap on Save posts the opening '
      'balances once', (tester) async {
    final deltas = <int>[];
    for (final b in _branches) {
      for (final taps in [1, 2]) {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = b.flow();
        var done = 0;
        await pumpUnderEntitlement(
          tester,
          b.host(flow, () => done++),
          ledger: ledger,
          viewport: const Size(420, 3200),
        );
        final before = await envelopeCount(tester, ledger);
        await _typeAndSave(tester, taps: taps);
        deltas.add(await envelopeCount(tester, ledger) - before);
        expect(done, 1, reason: '${b.name}: the step moves on once');
        await unmountTree(tester);
      }
    }
    for (var i = 0; i < deltas.length; i += 2) {
      expect(deltas[i], greaterThan(0));
      expect(deltas[i + 1], deltas[i], reason: 'two taps, one save');
    }
  });

  testWidgets('F1-24b-7 onboarding book full blocks only the book it names', (
    tester,
  ) async {
    final b = _branches.first;
    for (final fullHere in [false, true]) {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo(firstBookName: 'Me');
      final flow = b.flow();
      var done = 0;
      final sync = FakeSyncClient();
      await pumpUnderEntitlement(
        tester,
        b.host(flow, () => done++),
        ledger: ledger,
        sync: sync,
        viewport: const Size(420, 3200),
      );
      sync.fullBooks.add(fullHere ? b.bookId(flow)! : 'some-other-book');
      final before = await envelopeCount(tester, ledger);
      await _typeAndSave(tester);
      if (fullHere) {
        expect(raisedSheetKind(tester), RkRestrictionKind.bookFull);
        expect(await envelopeCount(tester, ledger), before);
        expect(done, 0);
      } else {
        expect(raisedSheetKind(tester), isNull);
        expect(await envelopeCount(tester, ledger), greaterThan(before));
        expect(done, 1);
      }
      await unmountTree(tester);
    }
  });
}
