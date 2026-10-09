// Design captures for the branch opening-balances steps S0.6b, S0.6f and
// S0.6i (ADR 2026-10-05 §2), re-recorded because ADR 2026-10-07 ruling 1
// removed their *Skip for now*. Pair with `python3 scripts/design_match.py
// pair S0.6b` (and S0.6f, S0.6i).
//
// default — each screen over its book's seeded money accounts at ₹0, as the
//           sign-up chain shows it (no Skip).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';

import '../../shared/design_capture.dart';

final _start = LocalDate(2026, 9, 9);

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('F1-1007-1 design capture S0.6b · S0.6f · S0.6i (no Skip)', (
    tester,
  ) async {
    final screens = <String, Widget>{
      'S0.6b': BusinessOpeningBalancesScreen(
        rows: const [
          OpeningRow(
            accountId: 'cash',
            name: 'Business Cash A/c',
            group: OpeningGroup.have,
          ),
        ],
        startDate: _start,
        onSave: (_) {},
        onAddAccount: (_) {},
      ),
      'S0.6f': FamilySharedAccountsScreen(
        rows: const [
          OpeningRow(
            accountId: 'cash',
            name: 'Joint Cash A/c',
            group: OpeningGroup.have,
          ),
        ],
        startDate: _start,
        onSave: (_) {},
        onAddAccount: (_) {},
      ),
      'S0.6i': TrustAccountsScreen(
        rows: const [
          OpeningRow(accountId: 'cash', name: 'Cash', group: OpeningGroup.have),
          OpeningRow(
            accountId: 'gollak',
            name: 'Gollak Cash',
            group: OpeningGroup.have,
            isCollection: true,
          ),
        ],
        startDate: _start,
        onSave: (_) {},
        onAddAccount: (_) {},
      ),
    };
    for (final MapEntry(key: sid, value: screen) in screens.entries) {
      for (final target in RkDesignTarget.values) {
        await rkDesignCapture(tester, sid: sid, target: target, child: screen);
        // Ruling 1: the sign-up step offers no way past it but Save.
        expect(find.text('Skip for now'), findsNothing, reason: sid);
        await _unmount(tester);
      }
    }
  });
}
