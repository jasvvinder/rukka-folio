// Typed rupees → integer paise. Money never becomes a double on the way in
// (CLAUDE.md rule 1): the string is split on the decimal mark and each half
// parsed as an `int`.
//
// Accepts what people actually type — `1250`, `1,250`, `₹1,250`, `12.5`,
// `12.50` — and refuses anything else by returning null, so the field can say
// so rather than silently counting a wrong figure.
int? paiseFromRupeeInput(String input) {
  final cleaned = input
      .replaceAll('₹', '')
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .replaceAll(' ', '')
      .trim();
  if (cleaned.isEmpty) return null;
  final parts = cleaned.split('.');
  if (parts.length > 2) return null;
  final rupeeText = parts[0].isEmpty ? '0' : parts[0];
  if (!_digits.hasMatch(rupeeText)) return null;
  final rupees = int.tryParse(rupeeText);
  if (rupees == null) return null;
  if (parts.length == 1) return rupees * 100;
  final fraction = parts[1];
  if (fraction.isEmpty) return rupees * 100;
  if (fraction.length > 2 || !_digits.hasMatch(fraction)) return null;
  final paise = int.parse(fraction.padRight(2, '0'));
  return rupees * 100 + paise;
}

final _digits = RegExp(r'^[0-9]+$');
