// F1-07-197: the certified-years seam (ADR 2026-09-09 §4 🔒).
//
// The seam is what makes *no switcher at all until the first year close* true
// **by construction**: the shipped source answers *no year has closed*, so
// every surface that wears the switcher draws plain text until S10.4 publishes
// a real one. [ClosedYearsScope] is the other half — the one place the shell
// installs that source once, above the router, so S4, S8.2 and S10.4 do not
// each grow a constructor argument the day the real source arrives.
//
// Reading the scope is deliberately optional, so a missing scope is never an
// error and never a red screen (07 §1 rule 6); this asserts that too.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/closed_years.dart';

void main() {
  testWidgets('F1-07-197 ClosedYearsScope.maybeOf is the shell’s one place to '
      'install a certified-years source, and its absence is not an error', (
    tester,
  ) async {
    ClosedYearsSource? seen;
    Widget probe() => Builder(
      builder: (context) {
        seen = ClosedYearsScope.maybeOf(context);
        return const SizedBox.shrink();
      },
    );

    // No scope: null, so the caller keeps whatever it was built with.
    await tester.pumpWidget(probe());
    expect(seen, isNull);

    // With a scope: the installed source, unchanged.
    Future<List<ClosedYear>> certified(String bookId, String accountId) async =>
        [ClosedYear(year: FinancialYear(2026), carriedForwardPaise: 11710000)];
    await tester.pumpWidget(
      ClosedYearsScope(source: certified, child: probe()),
    );
    expect(seen, same(certified));

    final years = await seen!('book-1', 'galla');
    expect(years, hasLength(1));
    expect(years.single.year, FinancialYear(2026));
    // Integer paise, never a double (CLAUDE.md rule 1).
    expect(years.single.carriedForwardPaise, isA<int>());
    expect(years.single.carriedForwardPaise, 11710000);

    // Swapping the source notifies; re-installing the same one does not.
    expect(
      ClosedYearsScope(
        source: certified,
        child: const SizedBox.shrink(),
      ).updateShouldNotify(
        ClosedYearsScope(source: noClosedYears, child: const SizedBox.shrink()),
      ),
      isTrue,
    );
    expect(
      ClosedYearsScope(
        source: certified,
        child: const SizedBox.shrink(),
      ).updateShouldNotify(
        ClosedYearsScope(source: certified, child: const SizedBox.shrink()),
      ),
      isFalse,
    );
  });

  test('F1-07-197 the shipped source says no year has closed, which is what '
      'makes *no switcher until the first year close* structural', () async {
    expect(await noClosedYears('book-1', 'galla'), isEmpty);
    expect(await noClosedYears('book-2', 'sbi'), isEmpty);

    // Two records are equal iff the year and the figure it hands on are, so a
    // switcher rebuild on an unchanged list is a no-op.
    expect(
      ClosedYear(year: FinancialYear(2026), carriedForwardPaise: 100),
      ClosedYear(year: FinancialYear(2026), carriedForwardPaise: 100),
    );
    expect(
      ClosedYear(year: FinancialYear(2026), carriedForwardPaise: 100),
      isNot(ClosedYear(year: FinancialYear(2026), carriedForwardPaise: 101)),
    );
    expect(
      ClosedYear(year: FinancialYear(2026), carriedForwardPaise: 100),
      isNot(
        ClosedYear(
          year: FinancialYear(2026, startMonth: 1),
          carriedForwardPaise: 100,
        ),
      ),
    );
  });
}
