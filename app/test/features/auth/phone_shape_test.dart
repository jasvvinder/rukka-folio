@Tags(['F1'])
library;

// The dev-only demo phone range (owner-directed, 4 Oct 2026): synthetic demo
// accounts on the dev project use 5XXXXXXXXX numbers, which no real Indian
// mobile can hold. The app accepts them only with RF_DEMO_PHONES on AND
// outside a release build; the release lane fails if a release build carries
// the define at all (scripts/check_release_flags.sh).
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/phone_shape.dart';

/// Runs a COPY of the real release-flags script inside a scratch repo whose
/// only release build is [buildLine]. The script `cd`s to its own parent's
/// parent and greps `.github` and `scripts` there, so the copy sees the
/// fixture and nothing of the real tree — no edit to its grep roots.
Future<ProcessResult> _runReleaseFlags(String buildLine) async {
  final root = await Directory.systemTemp.createTemp('rf_release_flags_');
  addTearDown(() => root.delete(recursive: true));
  final scripts = Directory('${root.path}/scripts')..createSync();
  final real = File('../scripts/check_release_flags.sh');
  expect(real.existsSync(), isTrue, reason: 'run from app/');
  real.copySync('${scripts.path}/check_release_flags.sh');
  Directory('${root.path}/.github/workflows').createSync(recursive: true);
  File(
    '${root.path}/.github/workflows/release.yml',
  ).writeAsStringSync('jobs:\n  ios:\n    steps:\n      - run: $buildLine\n');
  return Process.run(
    'bash',
    ['${scripts.path}/check_release_flags.sh'],
    environment: {'LANE': 'release'},
  );
}

/// Test numbers come from the reserved `+91 99999 xxxxx` block only
/// (ADR 2026-09-05i §7) — never a real-looking mobile.
String _reserved(String last5) => '99999$last5';

/// The first synthetic demo number (dev project, owner-directed 4 Oct 2026).
const _demo = '5000001001';

const _hardened =
    'flutter build ipa --release --obfuscate --split-debug-info=build/sym '
    '--dart-define=RF_SPKI_PINS=abc123';

void main() {
  group('Demo phone range (dev only, owner-directed 4 Oct 2026)', () {
    test('F1-DEMO-1 the predicate: [6-9] then nine digits always; 5 then nine '
        'digits only when demo is on AND release is off — the other three '
        'combinations refuse it', () {
      for (final demo in [false, true]) {
        for (final release in [false, true]) {
          bool ok(String s) =>
              isNationalPhoneShape(s, demoPhones: demo, releaseMode: release);
          final why = 'demo=$demo release=$release';
          // Real-shaped mobiles (reserved test block): always.
          for (final real in [_reserved('00001'), _reserved('12345')]) {
            expect(ok(real), isTrue, reason: '$real $why');
          }
          // The demo range: only demo-on + release-off.
          expect(ok(_demo), demo && !release, reason: '$_demo $why');
          // Never, in any combination: wrong length, other lead digits.
          for (final bad in [
            '500000100',
            '50000010011',
            '0123456789',
            '4123456789',
            '+91$_demo',
            '98765',
            '',
          ]) {
            expect(ok(bad), isFalse, reason: '$bad $why');
          }
        }
      }
    });

    test('F1-DEMO-2 the defaults are the build: without --dart-define='
        'RF_DEMO_PHONES this run is demo-off, so a 5-number is refused and a '
        '9-number accepted exactly as before the demo range existed', () {
      expect(rfDemoPhones, isFalse);
      expect(kReleaseMode, isFalse);
      expect(debugDemoPhonesOverride, isNull);
      expect(isNationalPhoneShape(_demo), isFalse);
      expect(isNationalPhoneShape(_reserved('00001')), isTrue);

      // The test seam turns the demo range on for a widget test, and still
      // cannot widen a release build.
      debugDemoPhonesOverride = true;
      addTearDown(() => debugDemoPhonesOverride = null);
      expect(isNationalPhoneShape(_demo), isTrue);
      expect(isNationalPhoneShape(_demo, releaseMode: true), isFalse);
      expect(isNationalPhoneShape(_demo, demoPhones: false), isFalse);
    });

    test('F1-DEMO-5 scripts/check_release_flags.sh fails a release build that '
        'carries --dart-define=RF_DEMO_PHONES=true (and =false), and passes '
        'the same build without it', () async {
      final control = await _runReleaseFlags(_hardened);
      expect(control.exitCode, 0, reason: '${control.stdout}');

      for (final v in ['true', 'false']) {
        final r = await _runReleaseFlags(
          '$_hardened --dart-define=RF_DEMO_PHONES=$v',
        );
        expect(r.exitCode, 1, reason: 'RF_DEMO_PHONES=$v: ${r.stdout}');
        expect('${r.stdout}', contains('RF_DEMO_PHONES'));
      }
    });

    test(
      'F1-DEMO-8 the same gate fails a release build that carries the '
      'hostile-client fixture define HOSTILE_ENVELOPES, whatever its value '
      '(09 §1, ADR 2026-09-05i §7: the release lane asserts it is absent)',
      () async {
        for (final v in ['true', 'false']) {
          final r = await _runReleaseFlags(
            '$_hardened --dart-define=HOSTILE_ENVELOPES=$v',
          );
          expect(r.exitCode, 1, reason: 'HOSTILE_ENVELOPES=$v: ${r.stdout}');
          expect('${r.stdout}', contains('HOSTILE_ENVELOPES'));
        }
      },
    );
  });
}
