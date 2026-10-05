// The logic of scripts/check_design_match.dart (ADR 2026-10-05 §4), kept apart
// so test/scripts/check_design_match_test.dart can run it over a fixture tree.
//
// Hashes must agree byte-for-byte with scripts/design_match.py `stamp`:
//   screens = sha256( for p in sorted(paths): "<p>\n<sha256hex(file bytes)>\n" )
//   frames  = sha256( "\n".join(sorted(frame sha256 hexes)) ), each named frame once
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

String sha256Hex(List<int> bytes) {
  final out = SHA256Digest().process(Uint8List.fromList(bytes));
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String screensHash(String root, List<String> paths) {
  final sorted = [...paths]..sort();
  final acc = StringBuffer();
  for (final p in sorted) {
    final f = File('$root/$p');
    if (!f.existsSync()) return 'missing:$p';
    acc.write('$p\n${sha256Hex(f.readAsBytesSync())}\n');
  }
  return sha256Hex(utf8.encode(acc.toString()));
}

String framesHash(List<String> shas) =>
    sha256Hex(utf8.encode(([...shas]..sort()).join('\n')));

/// `s0_6a1_business_owners_screen.dart` → `S0.6a1`; `s11_9_10_…` → `S11.9`;
/// `qr_scan_screen.dart` → null (not an inventory screen).
String? sidOfScreenFile(String path) {
  final name = path.split('/').last;
  final m = RegExp(r'^s(\d+)(?:_(\d+[a-z0-9]*))?_').firstMatch(name);
  if (m == null) return null;
  return m.group(2) == null ? 'S${m.group(1)}' : 'S${m.group(1)}.${m.group(2)}';
}

/// The S-ids of the 13 §3.2 inventory table (`| **S0.0** | …`), or null when
/// the doc or the section is not there.
Set<String>? inventorySids(String root) {
  final f = File('$root/docs/13-ux-architecture.md');
  if (!f.existsSync()) return null;
  final text = f.readAsStringSync();
  final start = text.indexOf(RegExp(r'^### 3\.2 ', multiLine: true));
  if (start < 0) return null;
  final next = text.indexOf(RegExp(r'^#{2,3} ', multiLine: true), start + 4);
  final section = text.substring(start, next < 0 ? text.length : next);
  return {
    for (final m in RegExp(
      r'^\| \*\*(S[0-9][0-9a-z.]*)\*\*',
      multiLine: true,
    ).allMatches(section))
      m.group(1)!,
  };
}

enum DesignIssueKind {
  /// Has a canvas frame and no record.
  missing,

  /// Screen files or canvas frames changed since the record was stamped, or
  /// the canvas holds a frame of the S-id the record does not cover.
  stale,

  /// A `deviates` record holds a difference without a reason or authority.
  unexplained,

  /// The record itself is malformed, or claims what the index contradicts.
  invalid,
}

class DesignIssue {
  DesignIssue(this.kind, this.sid, this.detail);
  final DesignIssueKind kind;
  final String sid;
  final String detail;
  @override
  String toString() => '${kind.name.padRight(11)} $sid — $detail';
}

class DesignMatchReport {
  final issues = <DesignIssue>[];
  final matched = <String>[];
  final deviates = <String>[];

  /// `no-canvas` records for S-ids the index really has no frame for: each is
  /// a design desk item (ADR 2026-10-05 §2), counted so none drops out.
  final noCanvas = <String>[];

  /// Built screens with no canvas frame and no `no-canvas` record: they need
  /// drawing (ADR 2026-10-05 §2), which is a design desk item, not a failure.
  final undrawn = <String>[];
}

const _verdicts = {'match', 'deviates', 'no-canvas'};

/// Thrown by the field readers below; becomes an `invalid` issue.
class _Bad implements Exception {
  _Bad(this.detail);
  final String detail;
}

List<String> _strings(Map<String, Object?> rec, String field) {
  final v = rec[field];
  if (v == null) return const [];
  if (v is List && v.every((e) => e is String)) return v.cast<String>();
  throw _Bad('"$field" must be a list of strings');
}

String _string(Map<String, Object?> m, String field, {String where = ''}) {
  final v = m[field];
  if (v == null) return '';
  if (v is String) return v.trim();
  throw _Bad('"$where$field" must be a string');
}

/// The canvas index, read defensively: a malformed index is one `invalid`
/// issue, never a crash of a warn-only step under `set -euo pipefail`.
class _Index {
  final frameSha = <String, String>{};

  /// Frame key → the S-id it is drawn for (variant frames have none).
  final owner = <String, String>{};

  /// S-id → its own frame keys, in index order.
  final own = <String, List<String>>{};
}

_Index _readIndex(File f) {
  final Object? decoded;
  try {
    decoded = jsonDecode(f.readAsStringSync());
  } on FormatException catch (e) {
    throw _Bad('not JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?>) throw _Bad('not a JSON object');
  final ix = _Index();
  for (final section in ['screens', 'variants']) {
    final m = decoded[section] ?? const <String, Object?>{};
    if (m is! Map<String, Object?>) throw _Bad('"$section" is not an object');
    for (final e in m.entries) {
      final list = e.value;
      if (list is! List) throw _Bad('"$section.${e.key}" is not a list');
      for (final f in list) {
        if (f is! Map<String, Object?> ||
            f['frame'] is! String ||
            f['sha256'] is! String) {
          throw _Bad('"$section.${e.key}" holds a frame without key/sha256');
        }
        final key = f['frame']! as String;
        ix.frameSha[key] = f['sha256']! as String;
        if (section == 'screens') {
          ix.owner[key] = e.key;
          (ix.own[e.key] ??= []).add(key);
        }
      }
    }
  }
  return ix;
}

DesignMatchReport checkDesignMatch(String root) {
  final report = DesignMatchReport();
  final indexFile = File('$root/design/match/canvas-index.json');
  if (!indexFile.existsSync()) {
    report.issues.add(
      DesignIssue(
        DesignIssueKind.invalid,
        '-',
        'design/match/canvas-index.json missing — run `python3 scripts/design_match.py index`',
      ),
    );
    return report;
  }
  final _Index ix;
  try {
    ix = _readIndex(indexFile);
  } on _Bad catch (e) {
    report.issues.add(
      DesignIssue(
        DesignIssueKind.invalid,
        '-',
        'design/match/canvas-index.json: ${e.detail}',
      ),
    );
    return report;
  }
  final canvasSids = ix.own.keys.toSet();

  // S-id → its s*_screen.dart files, from the tree.
  final screens = <String, List<String>>{};
  final features = Directory('$root/app/lib/features');
  if (features.existsSync()) {
    for (final f in features.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('_screen.dart')) continue;
      final rel = f.path.substring(root.length + 1);
      final sid = sidOfScreenFile(rel);
      if (sid != null) (screens[sid] ??= []).add(rel);
    }
  }

  // Records on disk, whether or not a screen file or a frame names them.
  final recorded = <String>{};
  final matchDir = Directory('$root/design/match');
  for (final f in matchDir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.json') && name != 'canvas-index.json') {
      recorded.add(name.substring(0, name.length - 5));
    }
  }

  // ADR 2026-10-05 §4: every s*_screen.dart, plus the 13 §3.2 inventory rows
  // the index names — many of those are built as sheets or widgets, with no
  // s*_screen.dart to find them by.
  final inventory = inventorySids(root) ?? canvasSids;
  final sids = <String>{
    ...screens.keys,
    ...canvasSids.where(inventory.contains),
    ...recorded,
  }.toList()..sort();

  for (final sid in sids) {
    final recFile = File('$root/design/match/$sid.json');
    if (!recFile.existsSync()) {
      if (canvasSids.contains(sid)) {
        report.issues.add(
          DesignIssue(
            DesignIssueKind.missing,
            sid,
            screens.containsKey(sid)
                ? 'has a canvas frame and no design/match/$sid.json'
                : 'has a canvas frame and no design/match/$sid.json '
                      '(no s*_screen.dart: the record names the files that draw it)',
          ),
        );
      } else {
        report.undrawn.add(sid);
      }
      continue;
    }
    try {
      _checkRecord(root, sid, recFile, ix, screens[sid] ?? const [], report);
    } on _Bad catch (e) {
      report.issues.add(DesignIssue(DesignIssueKind.invalid, sid, e.detail));
    }
  }
  return report;
}

void _checkRecord(
  String root,
  String sid,
  File recFile,
  _Index ix,
  List<String> screenFiles,
  DesignMatchReport report,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(recFile.readAsStringSync());
  } on FormatException catch (e) {
    throw _Bad('not JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?>) throw _Bad('not a JSON object');
  final rec = decoded;
  final verdict = rec['verdict'];
  if (!_verdicts.contains(verdict)) {
    throw _Bad('verdict "$verdict" is not one of $_verdicts');
  }
  final files = _strings(rec, 'screen_files');
  // A frame named twice is one frame: `stamp` hashes the set, so must we.
  final frames = _strings(rec, 'frames').toSet().toList();
  final rawHashes = rec['hashes'] ?? const <String, Object?>{};
  if (rawHashes is! Map<String, Object?>) {
    throw _Bad('"hashes" must be an object');
  }
  final hashes = rawHashes;
  final rawDevs = rec['deviations'] ?? const <Object?>[];
  if (rawDevs is! List || rawDevs.any((d) => d is! Map<String, Object?>)) {
    throw _Bad('"deviations" must be a list of objects');
  }
  final devs = rawDevs.cast<Map<String, Object?>>();
  final own = ix.own[sid] ?? const <String>[];

  if (files.isEmpty) throw _Bad('names no screen file');
  final uncovered = screenFiles.where((p) => !files.contains(p)).toList();
  if (uncovered.isNotEmpty) {
    report.issues.add(
      DesignIssue(
        DesignIssueKind.stale,
        sid,
        'screen file(s) not in the record: ${uncovered.join(', ')}',
      ),
    );
  }

  if (verdict == 'no-canvas') {
    // ADR 2026-10-05 §2: only for a screen the canvas has not drawn, and it
    // names the nearest drawn pattern it followed.
    if (own.isNotEmpty) {
      throw _Bad(
        '"no-canvas" but the canvas has ${own.length} frame(s) for $sid: '
        '${own.join(', ')}',
      );
    }
    if (_string(rec, 'nearest').isEmpty) {
      throw _Bad('"no-canvas" names no nearest drawn pattern ("nearest")');
    }
  } else {
    if (frames.isEmpty) throw _Bad('"$verdict" names no canvas frame');
    final foreign = [
      for (final k in frames)
        if (ix.owner[k] != null && ix.owner[k] != sid) '$k (${ix.owner[k]})',
    ];
    if (foreign.isNotEmpty) {
      throw _Bad("names another screen's frame(s): ${foreign.join(', ')}");
    }
  }

  final unknown = frames.where((k) => !ix.frameSha.containsKey(k)).toList();
  if (unknown.isNotEmpty) {
    report.issues.add(
      DesignIssue(
        DesignIssueKind.stale,
        sid,
        'frame(s) gone from the canvas index: ${unknown.join(', ')}',
      ),
    );
  } else if (hashes['frames'] !=
      framesHash([for (final k in frames) ix.frameSha[k]!])) {
    report.issues.add(
      DesignIssue(
        DesignIssueKind.stale,
        sid,
        'the canvas changed since the record was stamped',
      ),
    );
  }
  // Every frame the canvas draws for this S-id is matched (ADR §2: every
  // variant gets a capture), so a frame added later is reported, not ignored.
  final unnamed = own.where((k) => !frames.contains(k)).toList();
  if (verdict != 'no-canvas' && unnamed.isNotEmpty) {
    report.issues.add(
      DesignIssue(
        DesignIssueKind.stale,
        sid,
        'canvas frame(s) of $sid not in the record: ${unnamed.join(', ')}',
      ),
    );
  }
  if (hashes['screens'] != screensHash(root, files)) {
    report.issues.add(
      DesignIssue(
        DesignIssueKind.stale,
        sid,
        'the screen changed since the record was stamped',
      ),
    );
  }

  switch (verdict) {
    case 'deviates':
      if (devs.isEmpty) {
        report.issues.add(
          DesignIssue(
            DesignIssueKind.unexplained,
            sid,
            '"deviates" lists no difference',
          ),
        );
      }
      for (final d in devs) {
        final what = _string(d, 'what', where: 'deviations.');
        final reason = _string(d, 'reason', where: 'deviations.');
        final authority = _string(d, 'authority', where: 'deviations.');
        if (reason.isEmpty || authority.isEmpty) {
          report.issues.add(
            DesignIssue(
              DesignIssueKind.unexplained,
              sid,
              '"${what.isEmpty ? '?' : what}" has no ${reason.isEmpty ? 'reason' : 'authority'}',
            ),
          );
        }
      }
      report.deviates.add(sid);
    case 'match':
      report.matched.add(sid);
    case 'no-canvas':
      report.noCanvas.add(sid);
  }
}
