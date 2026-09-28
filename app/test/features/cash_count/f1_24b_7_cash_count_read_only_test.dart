// F1-24b-7 — read-only blocks a cash count (ADR 2026-09-24b §13): S5.5's Save
// refuses under a server-declared lapse, before the difference wizard, raises
// the S12.5 read-only sheet, records nothing, and keeps every counted figure;
// book full blocks only the book it names.
//
// The fake source records every save asked of it, so a gate that let the
// write through would leave a draft behind and these tests would fail.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/cash_count/cash_count_fake.dart';
import 'package:rukka_folio/features/cash_count/screens/s5_5_cash_count_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../../shared/test_app.dart';
import '../entry/restriction_support.dart';
import 's5_5_cash_count_test.dart' show verifyTarget;

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first));

Future<void> _pump(
  WidgetTester tester,
  FakeCashCountSource source, {
  String accountId = 'galla',
  FakeSyncClient? sync,
  bool lapsed = true,
}) => pumpUnderEntitlement(
  tester,
  CashCountScreen(accountId: accountId, source: source),
  entitlement: lapsed ? lapsedSource() : null,
  sync: sync,
  viewport: rkTallViewport,
);

Future<void> _typeAndSave(WidgetTester tester, String rupees) async {
  await tester.enterText(find.byType(TextField).first, rupees);
  await tester.pumpAndSettle();
  await tester.tap(find.text(_l10n(tester).countSave));
  await settleIo(tester);
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  testWidgets('F1-24b-7 cash count under a lapse raises the read-only sheet '
      'before the difference wizard, records nothing, and keeps the count', (
    tester,
  ) async {
    final source = FakeCashCountSource(target: verifyTarget());
    await _pump(tester, source);
    await _typeAndSave(tester, '2270');

    expectReadOnlySheet(tester);
    final l10n = _l10n(tester);
    expect(find.text(l10n.countConfirmTitle), findsNothing);
    expect(source.saved, isEmpty);
    expect(source.posted, isEmpty);

    await dismissRestrictionSheet(tester);
    expect(find.widgetWithText(TextField, '2270'), findsOneWidget);
    expect(find.text(l10n.countDifferenceLess('₹230')), findsOneWidget);
    expect(source.saved, isEmpty);
    await unmountTree(tester);
  });

  testWidgets('F1-24b-7 cash count book full blocks only the book it names', (
    tester,
  ) async {
    var source = FakeCashCountSource(target: verifyTarget());
    await _pump(
      tester,
      source,
      lapsed: false,
      sync: FakeSyncClient()..fullBooks.add('some-other-book'),
    );
    await _typeAndSave(tester, '2500');
    expect(raisedSheetKind(tester), isNull);
    expect(source.saved, hasLength(1), reason: 'a match records the count');
    await unmountTree(tester);

    source = FakeCashCountSource(target: verifyTarget());
    await _pump(
      tester,
      source,
      lapsed: false,
      sync: FakeSyncClient()..fullBooks.add('book-1'),
    );
    await _typeAndSave(tester, '2500');
    expect(raisedSheetKind(tester), RkRestrictionKind.bookFull);
    expect(source.saved, isEmpty);
    await unmountTree(tester);
  });
}
