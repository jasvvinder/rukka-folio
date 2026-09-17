// Rupees a person typed → integer paise. CLAUDE.md rule 1 / 01 §2 / 02 §1:
// money is integer paise and a float touching money is a bug, so this is
// string work throughout — `int.parse` on the two halves, never
// `double.parse`.
//
// One parser for the whole app. `features/advances` had it as `paiseOf` and
// `features/partners` as an identical `partnersPaiseOf`; both now import
// this.
library;

/// Integer paise for [text], or null when it is not an amount this app will
/// post: empty, more than two decimal places, a non-digit, or zero.
///
/// Accepts `1200`, `1200.5`, `1200.50`, `.5` and stray spaces or commas
/// (people paste grouped figures). Rejects a negative — an advance, a
/// settlement or a spend is always a positive movement, and the sign is the
/// posting's job (02 §7.1), never the user's.
int? paiseOf(String text) {
  final cleaned = text.replaceAll(',', '').replaceAll(' ', '').trim();
  if (cleaned.isEmpty) return null;
  final dot = cleaned.indexOf('.');
  final rupees = dot < 0 ? cleaned : cleaned.substring(0, dot);
  final paise = dot < 0 ? '' : cleaned.substring(dot + 1);
  if (paise.length > 2) return null;
  if (rupees.isEmpty && paise.isEmpty) return null;
  if (!_digits(rupees) || !_digits(paise)) return null;
  final r = rupees.isEmpty ? 0 : int.parse(rupees);
  final p = paise.isEmpty ? 0 : int.parse(paise.padRight(2, '0'));
  final total = r * 100 + p;
  return total == 0 ? null : total;
}

bool _digits(String s) => s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
