// F1-07-314 — the `Dialer` seam (ADR 2026-09-19 ruling 2 🔒).
//
// `UrlLauncherDialer` is handed a recorder in place of `launchUrl`, so the
// exact URI is pinned. `canLaunchUrl` has no way in: the seam's only
// collaborator is the one-method launcher, and the file that implements it is
// read here to show it never names `canLaunchUrl` at all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/dialer.dart';

void main() {
  group('F1-07-314 the Dialer seam (ADR 2026-09-19 ruling 2 🔒)', () {
    test('F1-07-314 dial hands launchUrl tel:<the stored number>, its bytes '
        'unaltered — spaces, a leading +, a dash all survive', () async {
      for (final number in [
        '98765 43210',
        '+91-98765-43210',
        '011 2345 6789',
      ]) {
        final handed = <Uri>[];
        final dialer = UrlLauncherDialer(
          launch: (uri) async {
            handed.add(uri);
            return true;
          },
        );
        expect(await dialer.dial(number), isTrue);
        expect(handed, hasLength(1));
        expect(handed.single.scheme, 'tel');
        // Exactly the URI the ADR names; a space travels percent-encoded, as
        // URI syntax requires, and decodes back to the stored bytes.
        expect(handed.single, Uri(scheme: 'tel', path: number));
        expect(
          Uri.decodeComponent(handed.single.path),
          number,
          reason: 'never parsed, trimmed or reformatted',
        );
        expect(handed.single.hasQuery, isFalse);
      }
    });

    test(
      'F1-07-314 a refused or throwing launch is false, never a throw',
      () async {
        expect(
          await UrlLauncherDialer(launch: (_) async => false).dial('1'),
          isFalse,
        );
        expect(
          await UrlLauncherDialer(
            launch: (_) async => throw StateError('no handler'),
          ).dial('1'),
          isFalse,
        );
      },
    );

    test('F1-07-314 canLaunchUrl is never called, and no query-scheme config '
        'exists for it to need', () {
      final src = File('lib/shared/seams/dialer.dart').readAsStringSync();
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('canLaunchUrl(')));
      expect(code, contains('launchUrl(uri)'));
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        isNot(contains('LSApplicationQueriesSchemes')),
      );
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, isNot(contains('android:scheme="tel"')));
    });
  });
}
