// Design captures for S0.6 Opening balances · first run (ADR 2026-10-05 §2;
// desk 172). Pair with `python3 scripts/design_match.py pair S0.6`.
//
// default — canvas 1 frame S0.6 (and its nd/S0.6-individual copy): the
//           seeded Cash A/c at ₹0, both party groups empty.
// have    — canvas 11 O6a "what do you have": a figure typed into Cash A/c.
// owe     — canvas 11 O6c "do you owe anyone": people added through *Add an
//           account* on both sides, their figures already in the book.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';

import '../../shared/design_capture.dart';

const _cash = FirstRunRow(
  accountId: 'cash',
  name: 'Cash A/c',
  group: OpeningGroup.have,
  isCash: true,
);

void main() {
  testWidgets('F1-1006c-7 design capture S0.6 (default · have · owe)', (
    tester,
  ) async {
    Future<void> capture(
      String state,
      List<FirstRunRow> rows, {
      Map<String, String> typed = const {},
    }) async {
      for (final target in RkDesignTarget.values) {
        await rkDesignCapture(
          tester,
          sid: 'S0.6',
          state: state,
          target: target,
          child: OpeningBalancesScreen(
            rows: rows,
            asOn: LocalDate(2026, 9, 9),
            onFinish: (_) {},
            onAddAccount: () {},
            onBack: () {},
            debugTyped: typed,
          ),
        );
        await _unmount(tester);
      }
    }

    await capture('default', const [_cash]);
    await capture('have', const [_cash], typed: {'cash': '12400'});
    await capture('owe', const [
      _cash,
      FirstRunRow(
        accountId: 'p1',
        name: 'Ramesh',
        group: OpeningGroup.owedToYou,
        postedPaise: 500000,
      ),
      FirstRunRow(
        accountId: 'p2',
        name: 'Sunil Dairy',
        group: OpeningGroup.youOwe,
        postedPaise: -137000,
      ),
      FirstRunRow(
        accountId: 'p3',
        name: 'Gupta Cotton Mill',
        group: OpeningGroup.youOwe,
        postedPaise: -2738000,
      ),
    ]);
  });
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}
