// Suite A — shrinking property tests (ADR 2026-09-05i §5; 09 §1).
//
// Pilot of `kiri_check` (v1.3.1, Dart 3, no Flutter dependency, maintained): a counter-example
// is shrunk to its smallest form before it is reported, unlike the seeded loops in
// `forEachSeed`. The seed is `PROPTEST_SEED` when set (same variable as the seeded loops),
// else kiri_check draws one and prints it on failure (`Random seed: …`) — pin it the same way.
// `forEachSeed` remains for generators the arbitrary combinators cannot express.
@Tags(['A', 'property'])
library;

import 'dart:io';

import 'package:core_ledger/core_ledger.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

int? get _seed => int.tryParse(Platform.environment['PROPTEST_SEED'] ?? '');

void main() {
  property('A-05i-1 splitByRatio: every share is its floor, the remainder (< n paise) sits on the '
      'largest ratio (earliest on ties), the sum is exact, and a loss is the exact mirror', () {
    forAll(
      combine2(
        integer(min: -(1 << 40), max: 1 << 40),
        list(integer(min: 1, max: 99), minLength: 2, maxLength: 6),
      ),
      (input) {
        final (totalRaw, ratios) = input;
        final total = Paise(totalRaw);
        final shares = splitByRatio(total, ratios);
        expect(shares.length, ratios.length);
        expect(Paise.sum(shares), total, reason: 'sum-to-zero of the split');
        expect(shares, splitByRatio(total, ratios), reason: 'deterministic');
        // Loss = mirror of the gain (ADR 2026-09-05e §8).
        expect(
          splitByRatio(-total, ratios).map((p) => p.raw),
          shares.map((p) => -p.raw),
        );
        final weight = ratios.fold<int>(0, (a, b) => a + b);
        var largest = 0;
        for (var k = 1; k < ratios.length; k++) {
          if (ratios[k] > ratios[largest]) largest = k;
        }
        final magnitude = totalRaw.abs();
        for (var k = 0; k < ratios.length; k++) {
          final floor =
              (BigInt.from(magnitude) *
                      BigInt.from(ratios[k]) ~/
                      BigInt.from(weight))
                  .toInt();
          final share = shares[k].raw.abs();
          expect(
            share - floor,
            k == largest ? inInclusiveRange(0, ratios.length - 1) : 0,
            reason: 'share $k of $total by $ratios',
          );
        }
      },
      maxExamples: 500,
      seed: _seed,
    );
  });
}
