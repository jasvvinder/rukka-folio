// F1-24b-7 — read-only blocks partner entries (ADR 2026-09-24b §13): S14.2's
// pay-out and partner-to-partner sheets and S14.1's distribution refuse to
// post under a server-declared lapse, raise the S12.5 read-only sheet and
// keep the draft; book full blocks only the book it names.
//
// Pumped over the fakes the S14 tests use: the port records every posting
// asked of it, so a gate that let the write through would leave a call behind
// and these tests would fail.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/partners/screens/s14_1_distribute_screen.dart';
import 'package:rukka_folio/features/partners/screens/s14_partner_positions_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../../shared/test_app.dart';
import '../entry/restriction_support.dart';
import 'fake_partners_port.dart';

const _book = 'kaur-farm';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

Future<void> _openSheetAndSave(
  WidgetTester tester, {
  required bool payOut,
  String amount = '20000',
}) async {
  final l10n = _l10n(tester);
  await tester.tap(
    find.text(
      payOut ? l10n.partnersDriftDoorPayout : l10n.partnersDriftDoorP2p,
    ),
  );
  await tester.pumpAndSettle();
  if (!payOut) await tester.tap(find.text('Harjit Kaur').last);
  await tester.enterText(find.byType(TextField), amount);
  await tester.tap(find.text(l10n.partnersSheetSave));
  await settleIo(tester);
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  for (final payOut in [true, false]) {
    final name = payOut ? 'pay-out' : 'partner-to-partner';
    testWidgets('F1-24b-7 partners $name under a lapse raises the read-only '
        'sheet, posts nothing, and keeps the amount', (tester) async {
      final port = FakePartnersPort(view: kaurView());
      await pumpUnderEntitlement(
        tester,
        PartnerPositionsScreen(bookId: _book, port: port),
        entitlement: lapsedSource(),
        viewport: rkTallViewport,
      );
      await _openSheetAndSave(tester, payOut: payOut);

      expectReadOnlySheet(tester);
      expect(port.payOuts, isEmpty);
      expect(port.settlements, isEmpty);

      await dismissRestrictionSheet(tester);
      expect(find.widgetWithText(TextField, '20000'), findsOneWidget);
      expect(find.text(_l10n(tester).partnersSheetSave), findsOneWidget);
      expect(port.payOuts, isEmpty);
      expect(port.settlements, isEmpty);
      await unmountTree(tester);
    });
  }

  testWidgets('F1-24b-7 partners book full blocks only the book it names', (
    tester,
  ) async {
    var port = FakePartnersPort(view: kaurView());
    await pumpUnderEntitlement(
      tester,
      PartnerPositionsScreen(bookId: _book, port: port),
      sync: FakeSyncClient()..fullBooks.add('some-other-book'),
      viewport: rkTallViewport,
    );
    await _openSheetAndSave(tester, payOut: true);
    expect(raisedSheetKind(tester), isNull);
    expect(port.payOuts, hasLength(1));
    await unmountTree(tester);

    port = FakePartnersPort(view: kaurView());
    await pumpUnderEntitlement(
      tester,
      PartnerPositionsScreen(bookId: _book, port: port),
      sync: FakeSyncClient()..fullBooks.add(_book),
      viewport: rkTallViewport,
    );
    await _openSheetAndSave(tester, payOut: true);
    expect(raisedSheetKind(tester), RkRestrictionKind.bookFull);
    expect(port.payOuts, isEmpty);
    await unmountTree(tester);
  });

  testWidgets('F1-24b-7 partners distribute under a lapse raises the '
      'read-only sheet, posts nothing, and stays on the confirm step', (
    tester,
  ) async {
    final port = FakeDistributionPort(preview: kaurDistribution());
    await pumpUnderEntitlement(
      tester,
      DistributeProfitScreen(bookId: _book, port: port),
      entitlement: lapsedSource(),
      viewport: rkTallViewport,
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(DistributeKeys.next));
      await settleIo(tester);
    }
    expectReadOnlySheet(tester);
    expect(port.distributions, isEmpty);

    await dismissRestrictionSheet(tester);
    expect(find.byType(DistributeProfitScreen), findsOneWidget);
    final next = tester.widget<FilledButton>(find.byKey(DistributeKeys.next));
    expect(next.onPressed, isNotNull, reason: 'still offered, not a dead end');
    expect(port.distributions, isEmpty);
    await unmountTree(tester);
  });
}
