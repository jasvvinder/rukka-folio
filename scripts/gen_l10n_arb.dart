// scripts/gen_l10n_arb.dart — ARB parts → merged app_<lang>.arb → gen_l10n input.
//
// Stage 1 — MERGE (P0 tooling, PLAN.md §2): every UI lane owns its own
//   app/lib/l10n/parts/<feature>_{en,pa,hi}.arb. This script merges them into
//   app/lib/l10n/app_{en,pa,hi}.arb, which are GENERATED (marked `@@x-generated`)
//   — edit the parts, never app_*.arb. Fails on: a key in two parts; a key in
//   one language of a feature but not the other two; a malformed ARB.
// Stage 2 — IDENTIFIERS: 01 §1 rule 9 🔒 keeps keys `screen.element.state`
//   (dotted); gen_l10n needs Dart identifiers, so identifier-keyed copies are
//   written to app/lib/l10n/gen/ (git-ignored), which l10n.yaml points at.
//
//   app.name            → appName
//   home.money_in.label → homeMoneyInLabel
//
//   dart run scripts/gen_l10n_arb.dart
//
// Logic lives in scripts/src/arb_merge.dart (tested from test/scripts/).
import 'dart:io';

import 'src/arb_merge.dart';

const partsDir = 'app/lib/l10n/parts';
const mergedDir = 'app/lib/l10n';
const outDir = 'app/lib/l10n/gen';

void main() {
  try {
    run();
  } on ArbError catch (e) {
    stderr.writeln('gen_l10n_arb: $e');
    exit(1);
  }
}

void run() {
  final parts = readParts(Directory(partsDir));
  if (parts.isEmpty) throw ArbError('no *_<lang>.arb files in $partsDir');
  final merged = mergeParts(parts);
  Directory(outDir).createSync(recursive: true);
  for (final lang in languages) {
    final canonical = merged.byLanguage[lang]!;
    File('$mergedDir/app_$lang.arb').writeAsStringSync(encodeArb(canonical));
    File(
      '$outDir/app_$lang.arb',
    ).writeAsStringSync(encodeArb(toIdentifierArb('app_$lang.arb', canonical)));
  }
  final features = parts.map((p) => p.feature).toSet().length;
  stdout.writeln(
    'merged $features feature(s) → $mergedDir/app_{en,pa,hi}.arb; '
    'wrote identifier copies to $outDir',
  );
}

/// Every `*.arb` in [dir], sorted by path so output is deterministic.
List<ArbPart> readParts(Directory dir) {
  if (!dir.existsSync()) return const [];
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files) ArbPart(path: f.path, text: f.readAsStringSync()),
  ];
}
