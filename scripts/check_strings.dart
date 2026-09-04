// scripts/check_strings.dart — the string gate (CLAUDE.md rule 8; 01 §1 rule 9 🔒).
//
// Fails when:
//   1. a key present in one language is missing in another (EN/PA/HI);
//   2. a translation has different ICU placeholders from the template (01 §1 rule 7);
//   3. an EN string uses forbidden jargon as a common noun (01 §1 rule 4):
//      journal, voucher, contra, accrual, folio, narration.
//      Whitelisted keys (rule 4 carve-outs): app.name, app.name.short, about.*
//      — the product name is exempt; bank column headers quoted on S7.0b are
//      data, not UI labels, and never live in ARB.
//   4. a key is not `screen.element.state`-shaped (lowercase, dot-separated).
//
//   dart run scripts/check_strings.dart
import 'dart:convert';
import 'dart:io';

const dir = 'app/lib/l10n';
const languages = ['en', 'pa', 'hi'];
const template = 'en';

final forbidden = RegExp(
  r'\b(journal|voucher|contra|accrual|folio|narration)s?\b',
  caseSensitive: false,
);
bool whitelisted(String key) =>
    key == 'app.name' || key == 'app.name.short' || key.startsWith('about.');
final keyShape = RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9_]*)+$');
final placeholder = RegExp(r'\{([a-zA-Z_][a-zA-Z0-9_]*)');

void main() {
  final errors = <String>[];
  final strings = <String, Map<String, String>>{};
  for (final lang in languages) {
    final f = File('$dir/app_$lang.arb');
    if (!f.existsSync()) {
      errors.add('missing file ${f.path}');
      continue;
    }
    final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    if (m['@@locale'] != lang) {
      errors.add('app_$lang.arb: @@locale must be "$lang"');
    }
    strings[lang] = {
      for (final e in m.entries)
        if (!e.key.startsWith('@')) e.key: e.value as String,
    };
  }
  if (errors.isNotEmpty) fail(errors);

  final all = strings.values.expand((m) => m.keys).toSet().toList()..sort();
  for (final key in all) {
    if (!keyShape.hasMatch(key)) {
      errors.add('"$key": keys are screen.element.state (lowercase, dotted)');
    }
    for (final lang in languages) {
      if (!strings[lang]!.containsKey(key)) {
        errors.add('"$key": missing in $lang');
      }
    }
    final en = strings[template]![key];
    if (en == null) continue;
    final want = placeholder.allMatches(en).map((m) => m[1]).toSet();
    for (final lang in languages) {
      final s = strings[lang]![key];
      if (s == null) continue;
      if (s.trim().isEmpty) errors.add('"$key": empty in $lang');
      final got = placeholder.allMatches(s).map((m) => m[1]).toSet();
      if (got.length != want.length || !got.containsAll(want)) {
        errors.add(
          '"$key": placeholders differ in $lang (en: $want, $lang: $got)',
        );
      }
    }
    if (!whitelisted(key)) {
      final hit = forbidden.firstMatch(en);
      if (hit != null) {
        errors.add('"$key": forbidden jargon "${hit[0]}" (01 §1 rule 4)');
      }
    }
  }
  if (errors.isNotEmpty) fail(errors);
  stdout.writeln(
    'strings ok: ${all.length} keys × ${languages.length} languages',
  );
}

Never fail(List<String> errors) {
  errors.forEach(stderr.writeln);
  exit(1);
}
