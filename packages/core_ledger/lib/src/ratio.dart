import 'money.dart';

/// The rounding rule for every ratio split (02 §7.1 🔒): divide in integer
/// paise; assign each partner `floor(amount × ratio / Σratio)`; the remainder —
/// always fewer paise than there are partners — goes to the partner with the
/// **largest ratio**, ties broken by the earliest-created (lowest index).
/// Deterministic on every device, so a split can never break sum-to-zero or
/// diverge across the family's phones. [ratios] must be in creation order.
///
/// A **negative** total (a loss, ADR 2026-09-05e §8) is split as the exact
/// mirror of the positive case: the rule is applied to `|total|` and every share
/// is negated, so the remainder still lands on the largest ratio and the shares
/// still sum to the total. ⚠️ SPEC: 02 §7.1 states the rule for a positive
/// amount only; mirroring is the reading under which "the loss is shared by the
/// mirror posting … same ratio, same remainder rule" holds paisa for paisa.
List<Paise> splitByRatio(Paise total, List<int> ratios) {
  if (ratios.isEmpty) throw ArgumentError('at least one ratio');
  if (ratios.any((r) => r <= 0)) {
    throw ArgumentError.value(ratios, 'ratios', 'every ratio must be positive');
  }
  if (total.isCredit) {
    return [for (final s in splitByRatio(-total, ratios)) -s];
  }
  final sum = ratios.fold<int>(0, (a, b) => a + b);
  final shares = <int>[];
  var assigned = 0;
  for (final r in ratios) {
    // BigInt guards the product for large amounts; the result always fits an int.
    final share = (BigInt.from(total.raw) * BigInt.from(r) ~/ BigInt.from(sum))
        .toInt();
    shares.add(share);
    assigned += share;
  }
  var largest = 0;
  for (var k = 1; k < ratios.length; k++) {
    if (ratios[k] > ratios[largest]) largest = k;
  }
  shares[largest] += total.raw - assigned;
  return [for (final s in shares) Paise(s)];
}
