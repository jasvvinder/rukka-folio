// F1-1005-1 — scripts/check_design_match.dart (ADR 2026-10-05 §2, §4). Runs the
// gate over a fixture tree: a screen with a canvas and no record is missing, a
// stamped record goes stale when the screen or the canvas moves, a deviation
// without a reason is unexplained, a record must cover its own S-id's frames
// and no other screen's, `no-canvas` is only for a screen the canvas has not
// drawn, inventory rows built as widgets are checked too, a malformed record is
// reported rather than crashing the gate, and the hashes agree with design_match.py.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../scripts/src/design_match.dart';

const home = 'app/lib/features/home/screens/s1_home_screen.dart';
const drill =
    'app/lib/features/home/screens/s1_1_position_drilldown_screen.dart';
const frameKey = 'c2/S1/Home · the baseline';
const emptyKey = 'c2/S1/Home · empty';
const variantKey = 'c2/E2/Home · error';
const sheet = 'app/lib/features/entry/widgets/entry_account_picker.dart';

late Directory dir;
String get root => dir.path;

void write(String rel, String content) {
  File('$root/$rel')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

Map<String, Object?> frame(String key, String sha) => {
  'frame': key,
  'design_id': key.split('/')[1],
  'caption': key.split('/').last,
  'sha256': sha,
};

void writeIndex({String frameSha = 'aa', bool withEmpty = false}) => write(
  'design/match/canvas-index.json',
  jsonEncode({
    'screens': {
      'S1': [frame(frameKey, frameSha), if (withEmpty) frame(emptyKey, 'ee')],
      'S1.2': [frame('c2/S1.2/picker', 'dd')],
      'S2.1': [frame('c3/S2.1/account picker', 'ff')],
      'S1.1': [
        {
          'frame': 'c2/S1.1/drill',
          'design_id': 'S1.1',
          'caption': 'y',
          'sha256': 'cc',
        },
      ],
    },
    'variants': {
      'E2': [frame(variantKey, 'e2')],
    },
  }),
);

/// 13 §3.2 as the gate reads it: S1.2 is an inventory row, S2.1 is not.
void writeInventory() => write(
  'docs/13-ux-architecture.md',
  '### 3.2 Complete screen inventory\n\n'
      '| ID | Screen |\n|---|---|\n'
      '| **S1** | Home |\n| **S1.1** | Drill-down |\n| **S1.2** | Picker |\n'
      '\n### 3.3 Design ↔ doc id map\n\n| **S2.1** | not inventory |\n',
);

void writeRecord(String sid, Map<String, Object?> rec) =>
    write('design/match/$sid.json', jsonEncode(rec));

/// A record stamped against the tree as it is now.
Map<String, Object?> stamped({
  String verdict = 'match',
  List<Map<String, Object?>> deviations = const [],
  List<String> frames = const [frameKey],
  List<String> shas = const ['aa'],
  List<String> files = const [home],
}) => {
  'sid': 'S1',
  'verdict': verdict,
  'frames': frames,
  'screen_files': files,
  'deviations': deviations,
  'hashes': {'screens': screensHash(root, files), 'frames': framesHash(shas)},
};

Iterable<DesignIssue> issuesFor(String sid) =>
    checkDesignMatch(root).issues.where((i) => i.sid == sid);

void main() {
  setUp(() {
    dir = Directory.systemTemp.createTempSync('design_match_');
    write(home, '// home\n');
    write(drill, '// drill\n');
    write(sheet, '// sheet\n');
    writeIndex();
    writeInventory();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('F1-1005-1 the design-match gate', () {
    test('F1-1005-1 hashes agree byte-for-byte with design_match.py stamp', () {
      // Both values were computed by scripts/design_match.py (screens_hash,
      // frames_hash) over this exact input; a drift here means stamp and the
      // gate disagree and every record reads stale.
      expect(
        screensHash(root, [home, drill]),
        'd5aee5eec7474086e47ce75811ebed5f896df0cb75234423ce65da32b6d07f7a',
      );
      expect(
        framesHash(['bb', 'aa']),
        '80c0d5c7137871baa75af2038f350bf60a4d45a131a653d0eb93f3cda3d28609',
      );
    });

    test('F1-1005-1 a screen with a canvas and no record is missing', () {
      final kinds = {
        for (final i in checkDesignMatch(root).issues) i.sid: i.kind,
      };
      expect(kinds['S1'], DesignIssueKind.missing);
      expect(kinds['S1.1'], DesignIssueKind.missing);
    });

    test('F1-1005-1 a freshly stamped match is clean', () {
      writeRecord('S1', stamped());
      final r = checkDesignMatch(root);
      expect(r.issues.where((i) => i.sid == 'S1'), isEmpty);
      expect(r.matched, ['S1']);
    });

    test('F1-1005-1 the record goes stale when the screen changes', () {
      writeRecord('S1', stamped());
      write(home, '// home, re-laid out\n');
      expect(
        issuesFor('S1').map((i) => (i.kind, i.detail)),
        contains((
          DesignIssueKind.stale,
          'the screen changed since the record was stamped',
        )),
      );
    });

    test('F1-1005-1 the record goes stale when the canvas changes', () {
      writeRecord('S1', stamped());
      writeIndex(frameSha: 'a-new-pull');
      expect(
        issuesFor('S1').map((i) => (i.kind, i.detail)),
        contains((
          DesignIssueKind.stale,
          'the canvas changed since the record was stamped',
        )),
      );
    });

    test('F1-1005-1 a new screen file for a recorded S-id is stale', () {
      writeRecord('S1', stamped());
      write('app/lib/features/home/screens/s1_scope_screen.dart', '// new\n');
      expect(
        issuesFor('S1').map((i) => i.kind),
        contains(DesignIssueKind.stale),
      );
    });

    test('F1-1005-1 a deviation needs a reason and an authority', () {
      writeRecord(
        'S1',
        stamped(
          verdict: 'deviates',
          deviations: [
            {
              'what': 'verbs wrap to two rows',
              'reason': '',
              'authority': '07 §1 rule 11',
            },
            {
              'what': 'no bell',
              'reason': 'S6 badge carries it',
              'authority': '',
            },
            {
              'what': 'hero at 28 px',
              'reason': '7-figure total at 200 %',
              'authority': '⚠️ SPEC home_cards.dart:68',
            },
          ],
        ),
      );
      final unexplained = issuesFor('S1')
          .where((i) => i.kind == DesignIssueKind.unexplained)
          .toList();
      expect(unexplained.map((i) => i.detail), [
        '"verbs wrap to two rows" has no reason',
        '"no bell" has no authority',
      ]);
    });

    test('F1-1005-1 a screen with no canvas is undrawn, not missing', () {
      write(
        'app/lib/features/legal/screens/s18_1_terms_screen.dart',
        '// terms\n',
      );
      final r = checkDesignMatch(root);
      expect(r.undrawn, contains('S18.1'));
      expect(r.issues.where((i) => i.sid == 'S18.1'), isEmpty);
    });

    test('F1-1005-1 an unknown verdict is invalid', () {
      writeRecord('S1', {...stamped(), 'verdict': 'close enough'});
      expect(issuesFor('S1').single.kind, DesignIssueKind.invalid);
    });

    test('F1-1005-1 no-canvas for an S-id the canvas has drawn is invalid', () {
      writeRecord('S1', {
        ...stamped(verdict: 'no-canvas', frames: const [], shas: const []),
        'nearest': 'S1.1',
      });
      final r = checkDesignMatch(root);
      expect(
        r.issues.where((i) => i.sid == 'S1').single.kind,
        DesignIssueKind.invalid,
      );
      expect(r.noCanvas, isNot(contains('S1')));
    });

    test(
      'F1-1005-1 no-canvas names the nearest drawn pattern, and is counted',
      () {
        const terms = 'app/lib/features/legal/screens/s18_1_terms_screen.dart';
        write(terms, '// terms\n');
        final base = {
          'sid': 'S18.1',
          'verdict': 'no-canvas',
          'frames': <String>[],
          'screen_files': [terms],
          'hashes': {
            'screens': screensHash(root, [terms]),
            'frames': framesHash([]),
          },
        };
        writeRecord('S18.1', base);
        expect(issuesFor('S18.1').single.detail, contains('nearest'));
        writeRecord('S18.1', {...base, 'nearest': 'S11.6 settings list'});
        final r = checkDesignMatch(root);
        expect(r.issues.where((i) => i.sid == 'S18.1'), isEmpty);
        expect(r.noCanvas, ['S18.1']);
        expect(r.undrawn, isNot(contains('S18.1')));
      },
    );

    test("F1-1005-1 a record naming another screen's frame is invalid", () {
      writeRecord(
        'S1',
        stamped(frames: const ['c2/S1.2/picker'], shas: const ['dd']),
      );
      final issues = issuesFor('S1').toList();
      expect(issues.map((i) => i.kind), contains(DesignIssueKind.invalid));
      expect(issues.first.detail, contains('S1.2'));
      expect(checkDesignMatch(root).matched, isEmpty);
    });

    test(
      'F1-1005-1 every frame of the S-id is named, so a new one is stale',
      () {
        writeRecord('S1', stamped());
        writeIndex(withEmpty: true);
        expect(
          issuesFor('S1').map((i) => (i.kind, i.detail)),
          contains((
            DesignIssueKind.stale,
            'canvas frame(s) of S1 not in the record: $emptyKey',
          )),
        );
      },
    );

    test('F1-1005-1 a variant frame is matched beside, never instead of, '
        "the S-id's own", () {
      writeRecord(
        'S1',
        stamped(frames: const [variantKey], shas: const ['e2']),
      );
      expect(
        issuesFor('S1').map((i) => i.kind),
        contains(DesignIssueKind.stale),
      );
      writeRecord(
        'S1',
        stamped(frames: const [frameKey, variantKey], shas: const ['aa', 'e2']),
      );
      expect(issuesFor('S1'), isEmpty);
    });

    test('F1-1005-1 a frame listed twice hashes as stamp does', () {
      // design_match.py stamp hashes set(frames).
      writeRecord(
        'S1',
        stamped(frames: const [frameKey, frameKey], shas: const ['aa']),
      );
      expect(issuesFor('S1'), isEmpty);
      expect(checkDesignMatch(root).matched, ['S1']);
    });

    test('F1-1005-1 an inventory row built as a widget is checked too', () {
      // S1.2 has a frame and no s*_screen.dart; S2.1 has a frame and is not
      // a 13 §3.2 inventory row.
      final r = checkDesignMatch(root);
      final s12 = r.issues.where((i) => i.sid == 'S1.2').single;
      expect(s12.kind, DesignIssueKind.missing);
      expect(s12.detail, contains('no s*_screen.dart'));
      expect(r.issues.where((i) => i.sid == 'S2.1'), isEmpty);

      // Its record is read and validated like any other.
      writeRecord('S1.2', {
        ...stamped(
          frames: const ['c2/S1.2/picker'],
          shas: const ['dd'],
          files: const [sheet],
        ),
        'sid': 'S1.2',
      });
      expect(checkDesignMatch(root).matched, contains('S1.2'));
      write(sheet, '// sheet, re-laid out\n');
      expect(
        issuesFor('S1.2').map((i) => i.detail),
        contains('the screen changed since the record was stamped'),
      );
    });

    test('F1-1005-1 a wrong-typed field is invalid, never a crash', () {
      for (final bad in <Map<String, Object?>>[
        {
          'screen_files': [1],
        },
        {'hashes': 'x'},
        {
          'deviations': ['x'],
        },
        {'frames': 'c2/S1/Home'},
        {
          'verdict': 'deviates',
          'deviations': [
            {'what': 'x', 'reason': 3, 'authority': 'y'},
          ],
        },
      ]) {
        writeRecord('S1', {...stamped(), ...bad});
        expect(issuesFor('S1').map((i) => i.kind), [
          DesignIssueKind.invalid,
        ], reason: '$bad');
      }
      write('design/match/S1.json', '[1, 2]');
      expect(issuesFor('S1').single.kind, DesignIssueKind.invalid);
    });

    test('F1-1005-1 a malformed canvas index is invalid, never a crash', () {
      write(
        'design/match/canvas-index.json',
        '{"screens": {"S1": [{"frame": 1}]}}',
      );
      final r = checkDesignMatch(root);
      expect(r.issues.single.kind, DesignIssueKind.invalid);
      expect(r.issues.single.detail, contains('canvas-index.json'));
    });
  });

  test('F1-1005-1 screen file names map to inventory S-ids', () {
    expect(sidOfScreenFile('x/s0_6a1_business_owners_screen.dart'), 'S0.6a1');
    expect(sidOfScreenFile('x/s0_05_welcome_screen.dart'), 'S0.05');
    expect(sidOfScreenFile('x/s11_9_10_cancel_window_screen.dart'), 'S11.9');
    expect(sidOfScreenFile('x/s1_home_screen.dart'), 'S1');
    expect(sidOfScreenFile('x/qr_scan_screen.dart'), isNull);
  });
}
