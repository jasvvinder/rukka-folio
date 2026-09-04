// scripts/gen_l10n_arb.dart — bridge between the spec's ARB key style and gen_l10n.
//
// 01 §1 rule 9 🔒: keys are `screen.element.state` (dotted). Flutter's gen_l10n
// requires keys to be Dart identifiers. Rather than bend the spec, the dotted
// ARBs in app/lib/l10n/ stay canonical and this script writes identifier-keyed
// copies to app/lib/l10n/gen/ (git-ignored), which l10n.yaml points at.
//
//   app.name            → appName
//   home.money_in.label → homeMoneyInLabel
//
// Collisions (two dotted keys mapping to one identifier) are an error.
import 'dart:convert';
import 'dart:io';

const srcDir = 'app/lib/l10n';
const outDir = 'app/lib/l10n/gen';

void main() {
  final files =
      Directory(srcDir)
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'app_[a-z]{2}\.arb$').hasMatch(f.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stderr.writeln('no ARB files in $srcDir');
    exit(1);
  }
  Directory(outDir).createSync(recursive: true);
  for (final f in files) {
    final src = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final out = <String, dynamic>{};
    final seen = <String, String>{};
    for (final e in src.entries) {
      if (e.key.startsWith('@@')) {
        out[e.key] = e.value;
        continue;
      }
      final meta = e.key.startsWith('@');
      final dotted = meta ? e.key.substring(1) : e.key;
      final id = identifier(dotted);
      final prior = seen[id];
      if (prior != null && prior != dotted) {
        stderr.writeln('${f.path}: "$dotted" and "$prior" both map to "$id"');
        exit(1);
      }
      seen[id] = dotted;
      out[meta ? '@$id' : id] = e.value;
    }
    final name = f.uri.pathSegments.last;
    File(
      '$outDir/$name',
    ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  }
  stdout.writeln('wrote ${files.length} ARB file(s) to $outDir');
}

/// `home.money_in.label` → `homeMoneyInLabel`.
String identifier(String dotted) {
  final parts = dotted
      .split(RegExp(r'[._-]'))
      .where((p) => p.isNotEmpty)
      .toList();
  final b = StringBuffer(parts.first.toLowerCase());
  for (final p in parts.skip(1)) {
    b.write(p[0].toUpperCase());
    b.write(p.substring(1));
  }
  final id = b.toString();
  if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(id)) {
    stderr.writeln('key "$dotted" cannot become a Dart identifier');
    exit(1);
  }
  return id;
}
