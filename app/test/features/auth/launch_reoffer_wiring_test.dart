@Tags(['F1'])
library;

// ADR 2026-09-24b §2, first bullet — *every installed device re-offers its
// UMK's X25519 half once per launch* — is a line in the composition root, and
// `http_auth_client_test.dart` can only call `reofferUmkPublic()` by hand. This
// pins the other half of the fact: that `bootstrap()` really makes the call,
// in the order that lets it do anything, and never in front of the user.
//
// Read the same way F1-06-90 reads the root (`recovery_ladder_source_test`):
// comments stripped, so prose that names the call cannot stand in for it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _bootstrapCode() {
  for (final path in ['lib/bootstrap.dart', 'app/lib/bootstrap.dart']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    expect(text, isNotEmpty, reason: 'the root was really read');
    return [
      for (final line in text.split('\n'))
        line.contains('//') ? line.substring(0, line.indexOf('//')) : line,
    ].join('\n');
  }
  fail('lib/bootstrap.dart not found from ${Directory.current.path}');
}

void main() {
  test('F1-24b-2 bootstrap fires the UMK re-offer once per launch, unawaited, '
      'after the session is restored and the ledger is bound as certifier — '
      'the two things without which it is skipped and posts nothing', () {
    final root = _bootstrapCode();
    expect(root, contains('Future<void> bootstrap() async {'));

    final fired = RegExp(r'unawaited\(\s*auth\.reofferUmkPublic\(\)\s*\)')
        .allMatches(root)
        .toList();
    expect(fired, hasLength(1), reason: 'one re-offer, fired and forgotten');
    expect(
      RegExp(r'reofferUmkPublic\(').allMatches(root),
      hasLength(1),
      reason:
          'and no second, awaited call — 07 §1.7 🔒: a round trip never '
          'stands in front of the user',
    );

    // Order. With no Active session, or no certifier holding the filed
    // certificate, `reofferUmkPublic()` returns `skipped` without a request —
    // so a call moved above either line would compile, run, and do nothing.
    final at = fired.single.start;
    final restored = root.indexOf('await auth.restore();');
    final bound = root.indexOf('auth.certifier = ledger;');
    expect(restored, isNonNegative, reason: 'the root restores the session');
    expect(bound, isNonNegative, reason: 'the root binds the ledger');
    expect(restored, lessThan(at), reason: 'restored before the re-offer');
    expect(bound, lessThan(at), reason: 'certifier bound before the re-offer');
  });
}
