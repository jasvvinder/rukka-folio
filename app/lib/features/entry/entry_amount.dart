// The amount as the keypad builds it (07 §5 step 1): `+` quick-sum
// (`120+80+40`) and paise via `.`.
//
// CLAUDE.md rule 1: money is integer paise end to end. The expression is held
// as the *digits the user typed* and summed as integers — no double ever
// touches the figure, so `80.50` is 8050 and not 80.5 × 100.
import '../../shared/format/money_format.dart';

/// Most rupees a single term may hold — long enough for any real entry, short
/// enough that the amount line cannot be pushed off a 360 px screen.
const int _maxRupeeDigits = 12;

/// One keypad amount: completed terms plus the term being typed.
final class AmountExpression {
  const AmountExpression._(this.terms, this.current);

  /// A fresh, empty amount — `₹0` in muted type (07 §5.5 state 1).
  const AmountExpression.empty() : terms = const [], current = '';

  /// Terms already closed with `+`, each the raw digits typed.
  final List<String> terms;

  /// The term being typed, raw (`80`, `80.`, `80.5`).
  final String current;

  /// Nothing typed at all.
  bool get isEmpty => terms.isEmpty && current.isEmpty;

  /// True once `+` has closed at least one term — the quick-sum is showing.
  bool get hasSum => terms.isNotEmpty;

  /// The total, in integer paise.
  int get paise =>
      terms.fold(0, (s, t) => s + _termPaise(t)) + _termPaise(current);

  /// Appends a digit; ignored past two paise digits or [_maxRupeeDigits].
  AmountExpression digit(String d) {
    final dot = current.indexOf('.');
    if (dot >= 0) {
      if (current.length - dot > 2) return this;
    } else if (current.length >= _maxRupeeDigits) {
      return this;
    }
    return AmountExpression._(terms, '$current$d');
  }

  /// Starts the paise of the current term; ignored if it already has some.
  AmountExpression dot() => current.contains('.')
      ? this
      : AmountExpression._(terms, '${current.isEmpty ? '0' : current}.');

  /// Closes the current term and starts another (the quick-sum key); ignored
  /// while the current term is empty.
  AmountExpression plus() =>
      current.isEmpty ? this : AmountExpression._([...terms, current], '');

  /// Removes the last thing typed, reopening the previous term when the
  /// current one is spent — so `⌫` walks back through a quick-sum.
  AmountExpression backspace() {
    if (current.isNotEmpty) {
      return AmountExpression._(
        terms,
        current.substring(0, current.length - 1),
      );
    }
    if (terms.isEmpty) return this;
    return AmountExpression._(terms.sublist(0, terms.length - 1), terms.last);
  }

  /// Back to `₹0` for the next entry (07 §5 step 7).
  AmountExpression get cleared => const AmountExpression.empty();

  /// What the big amount shows: the terms as typed, joined by `+`, each with
  /// Indian grouping on its rupee part. `0` while nothing is typed.
  String get display {
    if (isEmpty) return '0';
    final shown = [...terms, if (current.isNotEmpty) current];
    return shown.map(_groupTerm).join('+');
  }

  static String _groupTerm(String t) {
    final dot = t.indexOf('.');
    final rupees = dot < 0 ? t : t.substring(0, dot);
    final rest = dot < 0 ? '' : t.substring(dot);
    return '${groupIndian(rupees.isEmpty ? '0' : rupees)}$rest';
  }

  static int _termPaise(String t) {
    if (t.isEmpty) return 0;
    final dot = t.indexOf('.');
    final rupees = dot < 0 ? t : t.substring(0, dot);
    final paise = dot < 0 ? '' : t.substring(dot + 1);
    final r = rupees.isEmpty ? 0 : int.parse(rupees);
    final p = paise.isEmpty ? 0 : int.parse(paise.padRight(2, '0'));
    return r * 100 + p;
  }
}
