// scripts/check_design_match.dart — the design-match gate (ADR 2026-10-05 §4).
//
// For every app/lib/features/**/s*_screen.dart, every 13 §3.2 inventory row the
// canvas index names, and every record in design/match/, reports:
//   missing      the S-id has a canvas frame (design/match/canvas-index.json) and no record
//   stale        the screen files or the canvas frames changed since the record was stamped,
//                or the canvas holds a frame of the S-id the record does not name
//   unexplained  a `deviates` record holds a difference with no reason or authority
//   invalid      the record is malformed, names another screen's frame, or says
//                `no-canvas` for an S-id the canvas has drawn
// and lists built screens with no canvas (undrawn) and `no-canvas` records — both
// design desk items, not failures.
//
// Warn-only until the owner closes the re-skin; then ci.sh passes --strict
// (ADR 2026-10-05 §4, like check_coverage's M4 flip).
//
//   dart run scripts/check_design_match.dart [--strict]
import 'dart:io';

import 'src/design_match.dart';

void main(List<String> args) {
  final strict = args.contains('--strict');
  final r = checkDesignMatch(Directory.current.path);
  for (final i in r.issues) {
    stdout.writeln('  ${strict ? '✗' : '⚠'} $i');
  }
  if (r.undrawn.isNotEmpty) {
    stdout.writeln(
      '  · undrawn (no canvas frame, no record): ${r.undrawn.join(' ')}',
    );
  }
  if (r.noCanvas.isNotEmpty) {
    stdout.writeln(
      '  · no-canvas (built on the nearest drawn pattern): ${r.noCanvas.join(' ')}',
    );
  }
  stdout.writeln(
    'design match: ${r.matched.length} match · ${r.deviates.length} deviate (explained) · '
    '${r.noCanvas.length} no-canvas · '
    '${r.issues.length} issue(s) · ${r.undrawn.length} undrawn'
    '${strict ? '' : '  [warn-only, ADR 2026-10-05 §4]'}',
  );
  if (strict && r.issues.isNotEmpty) exitCode = 1;
}
