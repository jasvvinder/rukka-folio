/// Money is integer paise (02 §1.4 rule 2; CLAUDE.md rule 1).
///
/// `Paise` is an extension type over `int` that exposes only integer arithmetic:
/// there is no `/`, no `toDouble`, no way to reach a float without leaving the
/// type on purpose. Signed: **+ is a debit, − is a credit** (02 §1.3).
extension type const Paise(int raw) {
  /// Whole rupees → paise.
  const Paise.rupees(int rupees) : raw = rupees * 100;

  /// Zero.
  static const Paise zero = Paise(0);

  /// Adds.
  Paise operator +(Paise other) => Paise(raw + other.raw);

  /// Subtracts.
  Paise operator -(Paise other) => Paise(raw - other.raw);

  /// Negates (flips the side).
  Paise operator -() => Paise(-raw);

  /// Scales by an integer.
  Paise operator *(int factor) => Paise(raw * factor);

  /// Less than.
  bool operator <(Paise other) => raw < other.raw;

  /// Less than or equal.
  bool operator <=(Paise other) => raw <= other.raw;

  /// Greater than.
  bool operator >(Paise other) => raw > other.raw;

  /// Greater than or equal.
  bool operator >=(Paise other) => raw >= other.raw;

  /// Orders by value.
  int compareTo(Paise other) => raw.compareTo(other.raw);

  /// Magnitude.
  Paise abs() => Paise(raw.abs());

  /// True when exactly zero.
  bool get isZero => raw == 0;

  /// True when positive (a debit).
  bool get isDebit => raw > 0;

  /// True when negative (a credit).
  bool get isCredit => raw < 0;

  /// The side of a signed amount; `null` for zero (placement is by sign, 02 §1.2).
  Side? get side => raw > 0 ? Side.dr : (raw < 0 ? Side.cr : null);

  /// Sums; empty → zero.
  static Paise sum(Iterable<Paise> amounts) {
    var total = 0;
    for (final a in amounts) {
      total += a.raw;
    }
    return Paise(total);
  }
}

/// Ledger side. Professional surfaces show absolute value + side, never a minus
/// sign (reference standards §2, §9); consumer surfaces say Money in / Money out.
enum Side {
  /// Debit — ਨਾਮੇ / नामे.
  dr,

  /// Credit — ਜਮ੍ਹਾਂ / जमा.
  cr,
}

/// Floor division for integers (Dart's `~/` truncates toward zero).
int floorDiv(int a, int b) {
  final q = a ~/ b;
  return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
}

/// `numerator / denominator` rounded half-up (toward +∞ at exactly .5), in integers.
/// Used for interest on capital (02 §7.1: "rounded half-up to the nearest paisa").
int roundHalfUp({required int numerator, required int denominator}) {
  if (denominator <= 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must be positive');
  }
  return floorDiv(2 * numerator + denominator, 2 * denominator);
}
