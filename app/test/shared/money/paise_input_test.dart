// F1-13-27: the one rupees→paise parser (01 §2, 02 §1, CLAUDE.md rule 1).
//
// `features/advances` and `features/partners` each carried a copy; this is
// the test for the single definition. Its whole point is that the value never
// passes through a double: `double.parse('0.07') * 100` is 7.000000000000001
// and truncates to 6 paise, and an amount a person typed must survive
// exactly.
@Tags(['F1'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/money/paise_input.dart';

void main() {
  group('paiseOf (01 §2, 02 §1)', () {
    test('F1-13-27 parses by string split, so no double path can round a '
        'typed amount away', () {
      // Whole rupees, one decimal, two decimals, a bare fraction.
      expect(paiseOf('1200'), 120000);
      expect(paiseOf('1200.5'), 120050);
      expect(paiseOf('1200.50'), 120050);
      expect(paiseOf('.5'), 50);
      // Grouped and spaced, as pasted.
      expect(paiseOf(' 1,14,600 '), 11460000);

      // The double path, pinned by value. Every one of these is exact here
      // and is *not* exact through `(double.parse(s) * 100).toInt()`.
      for (final (text, want) in [
        ('0.07', 7),
        ('0.29', 29),
        ('1.15', 115),
        ('8.87', 887),
        ('1.005', null),
      ]) {
        expect(paiseOf(text), want, reason: text);
      }
      // Stated as the property, not just the examples: for these the naive
      // double conversion is wrong, and the parser is right.
      expect((double.parse('1.15') * 100).toInt(), isNot(115));
      expect(paiseOf('1.15'), 115);

      // Refused: empty, zero, a negative, a third decimal, a non-digit.
      expect(paiseOf(''), isNull);
      expect(paiseOf('0'), isNull);
      expect(paiseOf('0.00'), isNull);
      expect(paiseOf('-5'), isNull);
      expect(paiseOf('12.345'), isNull);
      expect(paiseOf('12a'), isNull);
      expect(paiseOf('1e3'), isNull);
      expect(paiseOf('.'), isNull);
    });
  });
}
