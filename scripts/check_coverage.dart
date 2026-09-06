// scripts/check_coverage.dart — 🔒 → test traceability + golden governance (ADR 2026-09-05i §1, §3, §4).
//
//   dart run scripts/check_coverage.dart [--strict] [--all] [--milestone M<n>]
//
// Job 1 — traceability. Every line in the normative docs carrying 🔒 must end with a
// `⟦tests: id, id⟧` marker (or `⟦tests: n/a — reason⟧`). A 🔒 heading covers its section: a
// marker on the heading excuses the lines beneath it up to the next heading. Ids are
// `<Suite>-<source>-<n>` (`A-02-9`, `D-05b-3`, `REL-05c-1`) and must appear as the first token of a
// `test(` / `group(` / `testWidgets(` / `property(` (kiri_check) name somewhere in the test trees.
//   fails on: (a) a 🔒 line with no marker  (b) a marker id no test declares
//   warns on: (c) an id a test declares that no marker names (orphan)  (d) a test without an id
//   also lists every live `superseded by ADR …; re-lands at M<n>` skip (§4); with --milestone M<n>,
//   a skip whose re-land milestone is ≤ n is a failure (09 §4 release gate).
// Job 2 — golden governance. docs/reference/worked-examples/README.md front-matter: when
// `approved_on` is set, `content_hash` must equal BLAKE2b-256 over the five example files
// (filename order, bytes concatenated). The current hash is always printed for sign-off.
//
// Phased (§1): warn-only until M4 exit — exit 0 unless --strict (or COVERAGE_STRICT=1). ci.sh
// flips to --strict at M4.
//
// What counts as a lock mark: 🔒 followed (after spaces) by end-of-line, punctuation, a
// bracket, `*`, a backtick, `⟦` or an uppercase word. A 🔒 followed by a lowercase word or
// `=` is a *mention* ("every 🔒 line", "🔒 = locked") and is ignored, as is a 🔒 inside a code span.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/blake2b.dart';

const _docRoots = ['docs', 'design', 'CLAUDE.md'];
const _docExcludes = [
  'docs/requirements-architecture.md', // ⛔ non-normative background (CLAUDE.md § Precedence 4)
  'design/canvas-mirror', // generated mirror of the design tool
  'docs/brand', // brand assets
];
const _testRoots = ['packages', 'app/test', 'testing', 'server'];
const _goldenDir = 'docs/reference/worked-examples';
const _goldenFiles = [
  'individual-rahul-sharma.md',
  'business-sharma-textile.md',
  'trust-singh-sabha-gurudwara.md',
  'joint-family-sharma.md',
  'joint-business-partnership.md',
];

final _idPattern = RegExp(r'^[A-Z]+[0-9]?-[0-9A-Za-z]+-[0-9]+$');
final _marker = RegExp(r'⟦tests:\s*([^⟧]*)⟧');
final _codeSpan = RegExp(r'`[^`]*`');
final _lockMark = RegExp(r'🔒\s*(?:$|[^a-z=\s])');
final _heading = RegExp(r'^#{1,6}\s');
final _testName = RegExp(
  r'''\b(test|group|testWidgets|property)\(\s*(?:r)?(['"])((?:\\.|(?!\2).)*)\2''',
  multiLine: true,
);
final _skipReason = RegExp(
  r'''(?:@Skip\(|skip:)\s*((?:\s*(?:r)?'(?:[^'\\]|\\.)*'\s*)+)''',
  multiLine: true,
);
final _supersededBy = RegExp(r'superseded by ADR\s+(\S+)');
final _reLandsAt = RegExp(r're-lands[^M]*\b(M\d+)');

class Finding {
  Finding(this.where, this.what);
  final String where;
  final String what;
  @override
  String toString() => '$where  $what';
}

void main(List<String> args) {
  final strict =
      args.contains('--strict') ||
      Platform.environment['COVERAGE_STRICT'] == '1';
  final showAll = args.contains('--all');
  final milestoneArg = args.indexOf('--milestone');
  final currentMilestone = milestoneArg >= 0 && milestoneArg + 1 < args.length
      ? int.tryParse(args[milestoneArg + 1].replaceFirst('M', ''))
      : null;

  final root = _workspaceRoot();
  Directory.current = root;

  // ---- docs: 🔒 lines and markers -------------------------------------------------------
  final unmarked = <Finding>[];
  final markerIds = <String, List<String>>{}; // id → where declared
  final naMarkers = <Finding>[];
  final badIds = <Finding>[];
  var lockedLines = 0;
  var lockedCoveredBySection = 0;

  for (final file in _markdownFiles()) {
    final rel = _rel(file);
    final lines = file.readAsLinesSync();
    var sectionMarked = false;
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final where = '$rel:${i + 1}';
      final isHeading = _heading.hasMatch(raw);
      final noCode = raw.replaceAll(_codeSpan, '');
      final marker = _marker.firstMatch(noCode);
      if (marker != null) {
        final body = marker.group(1)!.trim();
        if (body.startsWith('n/a')) {
          naMarkers.add(Finding(where, body));
        } else {
          for (final id in body.split(',').map((s) => s.trim())) {
            if (id.isEmpty) continue;
            if (!_idPattern.hasMatch(id)) {
              badIds.add(Finding(where, 'malformed id "$id"'));
              continue;
            }
            markerIds.putIfAbsent(id, () => []).add(where);
          }
        }
      }
      if (isHeading) sectionMarked = false;
      if (!_lockMark.hasMatch(noCode)) continue;
      lockedLines++;
      if (marker != null) {
        if (isHeading) sectionMarked = true;
        continue;
      }
      if (sectionMarked) {
        lockedCoveredBySection++;
        continue;
      }
      unmarked.add(Finding(where, _excerpt(raw)));
    }
  }

  // ---- tests: declared ids, tests without ids, live skips ---------------------------------
  final declared = <String, List<String>>{}; // id → where
  final testsWithoutId = <Finding>[];
  final skips = <Finding>[];
  final overdueSkips = <Finding>[];
  var testCount = 0;

  for (final file in _testFiles()) {
    final rel = _rel(file);
    final src = file.readAsStringSync();
    for (final m in _testName.allMatches(src)) {
      final kind = m.group(1)!;
      final name = m.group(3)!;
      final where = '$rel:${_lineOf(src, m.start)}';
      final first = name.split(RegExp(r'\s+')).first;
      if (_idPattern.hasMatch(first)) {
        declared.putIfAbsent(first, () => []).add(where);
      } else if (kind != 'group') {
        testsWithoutId.add(Finding(where, _excerpt(name)));
      }
      if (kind != 'group') testCount++;
    }
    for (final m in _skipReason.allMatches(src)) {
      final reason = _joinLiterals(m.group(1)!);
      final adr = _supersededBy.firstMatch(reason);
      if (adr == null) continue;
      final where = '$rel:${_lineOf(src, m.start)}';
      final reLand = _reLandsAt.firstMatch(reason)?.group(1);
      final f = Finding(
        where,
        'superseded by ADR ${adr.group(1)} · re-lands at ${reLand ?? '⚠️ unstated'}',
      );
      skips.add(f);
      if (currentMilestone != null && reLand != null) {
        final n = int.parse(reLand.substring(1));
        if (n <= currentMilestone) overdueSkips.add(f);
      }
    }
  }

  final dangling = <Finding>[
    for (final e in markerIds.entries)
      if (!declared.containsKey(e.key))
        for (final where in e.value)
          Finding(where, 'no test declares ${e.key}'),
  ];
  final orphans = <Finding>[
    for (final e in declared.entries)
      if (!markerIds.containsKey(e.key))
        Finding(e.value.first, '${e.key} is named by no ⟦tests⟧ marker'),
  ];

  // ---- goldens: front-matter + content hash ---------------------------------------------
  final golden = _checkGoldens();

  // ---- report ---------------------------------------------------------------------------
  final out = StringBuffer();
  void section(String title, List<Finding> items, {int limit = 12}) {
    if (items.isEmpty) return;
    out.writeln('\n$title (${items.length})');
    final shown = showAll ? items : items.take(limit);
    for (final f in shown) {
      out.writeln('  $f');
    }
    if (!showAll && items.length > limit) {
      out.writeln('  … ${items.length - limit} more (--all to list)');
    }
  }

  out.writeln('check_coverage — 🔒 → tests (ADR 2026-09-05i)');
  out.writeln(
    '  🔒 lines: $lockedLines · marked: ${lockedLines - unmarked.length - lockedCoveredBySection}'
    ' · covered by a marked heading: $lockedCoveredBySection · unmarked: ${unmarked.length}'
    ' · n/a: ${naMarkers.length}',
  );
  out.writeln(
    '  tests: $testCount · ids declared: ${declared.length} · ids named in markers: ${markerIds.length}'
    ' · tests without id: ${testsWithoutId.length}',
  );
  out.writeln('  golden content_hash (BLAKE2b-256): ${golden.hash}');
  out.writeln(
    '  goldens: ${golden.approvedOn == null ? 'PROVISIONAL — no approved_on' : 'approved ${golden.approvedOn} by ${golden.approvedBy}'}',
  );

  section('FAIL — 🔒 lines without a ⟦tests⟧ marker', unmarked);
  section('FAIL — marker ids no test declares', dangling);
  section('FAIL — malformed ids', badIds);
  section('FAIL — superseded skips past their re-land milestone', overdueSkips);
  if (golden.error != null) out.writeln('\nFAIL — goldens: ${golden.error}');
  section('warn — test ids named by no marker (orphans)', orphans);
  section('warn — tests without an id', testsWithoutId);
  section('live superseded skips (tracked debt, §4)', skips, limit: 50);

  final failures =
      unmarked.length +
      dangling.length +
      badIds.length +
      overdueSkips.length +
      (golden.error == null ? 0 : 1);
  if (failures == 0) {
    out.writeln('\ncoverage ok');
    stdout.write(out);
    return;
  }
  if (strict) {
    out.writeln('\ncoverage FAILED ($failures) — strict mode (M4+)');
    stdout.write(out);
    exit(1);
  }
  out.writeln(
    '\ncoverage: $failures finding(s) — warn-only until M4 exit (ADR 2026-09-05i §1); --strict to enforce',
  );
  stdout.write(out);
}

// ---- helpers ----------------------------------------------------------------------------

Directory _workspaceRoot() {
  var d = Directory.current.absolute;
  while (!File('${d.path}/CLAUDE.md').existsSync()) {
    final parent = d.parent;
    if (parent.path == d.path) {
      stderr.writeln('check_coverage: run from inside the repository');
      exit(2);
    }
    d = parent;
  }
  return d;
}

String _rel(File f) {
  final root = Directory.current.path;
  final p = f.absolute.path;
  return p.startsWith(root) ? p.substring(root.length + 1) : p;
}

Iterable<File> _markdownFiles() sync* {
  for (final r in _docRoots) {
    final entity = FileSystemEntity.typeSync(r);
    if (entity == FileSystemEntityType.file) {
      yield File(r);
      continue;
    }
    if (entity != FileSystemEntityType.directory) continue;
    for (final f in Directory(r).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.md')) continue;
      final rel = _rel(f);
      if (_docExcludes.any((x) => rel == x || rel.startsWith('$x/'))) continue;
      yield f;
    }
  }
}

Iterable<File> _testFiles() sync* {
  for (final r in _testRoots) {
    if (!Directory(r).existsSync()) continue;
    for (final f in Directory(r).listSync(recursive: true).whereType<File>()) {
      final rel = _rel(f);
      if (rel.contains('/.dart_tool/') || rel.contains('/build/')) continue;
      final isDartTest =
          rel.endsWith('_test.dart') &&
          (rel.contains('/test/') || rel.startsWith('app/test/'));
      final isDenoTest = rel.endsWith('.test.ts') || rel.endsWith('_test.ts');
      final isSql = rel.endsWith('.sql') && rel.contains('/tests/');
      if (isDartTest || isDenoTest || isSql) yield f;
    }
  }
}

int _lineOf(String src, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < src.length; i++) {
    if (src.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

String _joinLiterals(String literals) =>
    RegExp(r"'((?:[^'\\]|\\.)*)'")
        .allMatches(literals)
        .map((m) => m.group(1)!)
        .join();

String _excerpt(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= 96 ? t : '${t.substring(0, 93)}…';
}

class _GoldenStatus {
  _GoldenStatus({
    required this.hash,
    this.approvedBy,
    this.approvedOn,
    this.error,
  });
  final String hash;
  final String? approvedBy;
  final String? approvedOn;
  final String? error;
}

_GoldenStatus _checkGoldens() {
  final digest = Blake2bDigest(digestSize: 32);
  for (final name in _goldenFiles) {
    final f = File('$_goldenDir/$name');
    if (!f.existsSync()) {
      return _GoldenStatus(hash: '-', error: 'missing golden file $name');
    }
    final bytes = f.readAsBytesSync();
    digest.update(bytes, 0, bytes.length);
  }
  final out = Uint8List(32);
  digest.doFinal(out, 0);
  final hash = out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  final readme = File('$_goldenDir/README.md');
  if (!readme.existsSync()) {
    return _GoldenStatus(hash: hash, error: 'README.md missing');
  }
  final lines = const LineSplitter().convert(readme.readAsStringSync());
  if (lines.isEmpty || lines.first.trim() != '---') {
    return _GoldenStatus(
      hash: hash,
      error: 'README.md has no YAML front-matter (approved_by / approved_on / content_hash)',
    );
  }
  final fm = <String, String>{};
  for (var i = 1; i < lines.length && lines[i].trim() != '---'; i++) {
    final m = RegExp(r'^(\w+):\s*([^#]*)').firstMatch(lines[i]);
    if (m != null) fm[m.group(1)!] = m.group(2)!.trim();
  }
  final approvedOn = fm['approved_on'];
  final approvedBy = fm['approved_by'];
  final recorded = fm['content_hash'];
  if (approvedOn == null || approvedOn.isEmpty) {
    if (recorded != null && recorded.isNotEmpty && recorded != hash) {
      return _GoldenStatus(
        hash: hash,
        error:
            'content_hash set without approved_on and does not match the files',
      );
    }
    return _GoldenStatus(hash: hash);
  }
  if (approvedBy == null || approvedBy.isEmpty) {
    return _GoldenStatus(
      hash: hash,
      approvedOn: approvedOn,
      error: 'approved_on is set but approved_by is empty',
    );
  }
  if (recorded != hash) {
    return _GoldenStatus(
      hash: hash,
      approvedBy: approvedBy,
      approvedOn: approvedOn,
      error:
          'goldens changed after sign-off ($approvedOn): content_hash $recorded ≠ $hash — an ADR and a new hash are required (ADR 2026-09-05i §3)',
    );
  }
  return _GoldenStatus(
    hash: hash,
    approvedBy: approvedBy,
    approvedOn: approvedOn,
  );
}
