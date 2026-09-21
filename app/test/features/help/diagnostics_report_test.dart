// The S17.4 payload's scrub contract (13 §3.2 row S17.4 "financial values
// scrubbed"; 07 §22 🔒; **CLAUDE.md rule 4** — no plaintext financial data in
// a diagnostics report, ever).
//
// These tests are written so that they FAIL if the scrub stopped working —
// if `buildDiagnosticsReport` returned what it was handed. Every case feeds
// it inputs that *do* carry amounts, account names and party names and then
// asserts those strings are **absent** from the payload, as well as asserting
// the allow-listed fields are present. A test that only checked the happy
// shape would pass over a report that leaked every one of them, which is the
// defect the S6 approvals fake shipped with for a week.
//
// Amounts here are synthetic (CLAUDE.md rule 4 again: never real entries).
@Tags(['F1'])
library;

import 'dart:ui' show Brightness, Locale;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/help/diagnostics_report.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

void main() {
  // Synthetic plaintext of exactly the three kinds rule 4 forbids: an amount
  // in paise, an amount as a person reads it, an account name and two party
  // names. Every assertion below looks for these.
  const forbidden = [
    '1860000',
    '18,600',
    '₹',
    'Cash in hand',
    'Diesel',
    'Ramesh',
    'Sunita',
    'Saturday sales',
  ];

  DiagnosticsReport build({
    DeviceFacts device = const DeviceFacts(),
    SyncStatus sync = const Synced(),
    Locale locale = const Locale('en'),
    double textScale = 1,
    Brightness brightness = Brightness.light,
    TargetPlatform platform = TargetPlatform.android,
    int schemaVersion = 4,
    DateTime? now,
  }) => buildDiagnosticsReport(
    device: device,
    sync: sync,
    locale: locale,
    textScale: textScale,
    brightness: brightness,
    platform: platform,
    schemaVersion: schemaVersion,
    now: now ?? DateTime.utc(2026, 9, 21, 4, 30, 59),
  );

  void expectNoPlaintext(DiagnosticsReport report, {required String because}) {
    for (final leak in forbidden) {
      expect(
        report.text,
        isNot(contains(leak)),
        reason: 'CLAUDE.md rule 4: "$leak" reached the payload — $because',
      );
    }
  }

  group('S17.4 the payload is an allow-list (CLAUDE.md rule 4)', () {
    test('F1-07-383 a report built from inputs stuffed with amounts, account '
        'names and party names carries none of them, and still carries every '
        'allowed field', () {
      final report = build(
        // Every optional input poisoned with the plaintext a leak would
        // show. A pass-through implementation prints all of it.
        device: const DeviceFacts(
          appVersion: 'Ramesh ₹18,600.00',
          osVersion: 'Cash in hand 15',
          problemCodes: [
            'AMOUNT ₹18,600.00',
            'projector failed on Ramesh: 1860000',
            'amount_1860000',
            'Saturday sales',
            // The one code shaped like a code: it must survive, or this
            // test would pass against a filter that simply dropped
            // everything.
            'sync_rejected_quota',
          ],
        ),
        sync: const WaitingFor('Sunita Kaur'),
        locale: const Locale('pa'),
        textScale: 1.3,
        brightness: Brightness.dark,
        platform: TargetPlatform.iOS,
        schemaVersion: 4,
      );

      expectNoPlaintext(report, because: 'the report is an allow-list');

      // The allowed side of the contract, field by field — the
      // `diag.field.*` / `diag.included` strings promise these to the
      // reader, so their absence is a defect too.
      expect(report.values[DiagField.platform], 'ios');
      expect(report.values[DiagField.language], 'pa');
      expect(report.values[DiagField.textScale], '1.30');
      expect(report.values[DiagField.theme], 'dark');
      expect(report.values[DiagField.syncState], 'waiting_for_author');
      expect(report.values[DiagField.outboxDepth], '0');
      expect(report.values[DiagField.schemaVersion], '4');
      expect(report.values[DiagField.generatedAt], '2026-09-21T04:30Z');
      expect(report.values[DiagField.codes], 'sync_rejected_quota');
      // The two poisoned ones are dropped outright rather than blanked.
      expect(report.values.containsKey(DiagField.appVersion), isFalse);
      expect(report.values.containsKey(DiagField.osVersion), isFalse);

      // Nothing outside the enum can be in the payload: every line is a
      // `DiagField.wire` and there are as many lines as fields.
      final lines = report.text.split('\n');
      expect(lines, hasLength(report.values.length));
      for (final line in lines) {
        expect(
          DiagField.values.map((f) => f.wire),
          contains(line.split(':').first),
        );
      }
    });

    test('F1-07-384 the member name WaitingFor carries never reaches the '
        'payload — the state word does (05 §9, diag.excluded.people)', () {
      final named = build(sync: const WaitingFor('Ramesh Kumar'));
      expect(named.text, isNot(contains('Ramesh')));
      expect(named.values[DiagField.syncState], 'waiting_for_author');

      // Every other status reduces to its own word, and nothing else.
      expect(build().values[DiagField.syncState], 'synced');
      expect(
        build(sync: const Offline()).values[DiagField.syncState],
        'offline',
      );
      expect(
        build(sync: const NeedsAttention()).values[DiagField.syncState],
        'needs_attention',
      );
      expect(
        build(sync: const SavedWillSync(7)).values[DiagField.syncState],
        'saved_will_sync',
      );
    });

    test(
      'F1-07-385 the outbox is a COUNT of entries, never a sum of money',
      () {
        // 18,600.00 in paise would be 1860000. What the report says is 7 —
        // the number of envelopes waiting.
        final report = build(sync: const SavedWillSync(7));
        expect(report.values[DiagField.outboxDepth], '7');
        expectNoPlaintext(report, because: 'the outbox is a count');
        // Every other state reports an empty outbox rather than omitting it.
        expect(build().values[DiagField.outboxDepth], '0');
      },
    );

    test('F1-07-386 a version, an OS version and a code that are not shaped '
        'like one are dropped; the well-shaped ones survive', () {
      final good = build(
        device: const DeviceFacts(
          appVersion: '0.1.0+1',
          osVersion: '18.5.1',
          problemCodes: ['key_wait', 'pull_cursor_reset', 'schema_v4'],
        ),
      );
      expect(good.values[DiagField.appVersion], '0.1.0+1');
      expect(good.values[DiagField.osVersion], '18.5.1');
      expect(
        good.values[DiagField.codes],
        'key_wait,pull_cursor_reset,schema_v4',
      );

      // `Android 15` is two words with a number after them, and so is
      // `Ramesh 15`; the field takes the number alone.
      expect(
        build(device: const DeviceFacts(osVersion: 'Android 15')).values
            .containsKey(DiagField.osVersion),
        isFalse,
      );

      // A long digit run is the shape an amount in paise has.
      expect(
        build(device: const DeviceFacts(problemCodes: ['paid_1860000'])).values
            .containsKey(DiagField.codes),
        isFalse,
      );

      // The list is capped, so a producer cannot turn `codes` into a
      // channel for free text by handing over hundreds of them.
      final many = build(
        device: DeviceFacts(
          problemCodes: [for (var i = 0; i < 40; i++) 'code_$i'],
        ),
      );
      expect(many.values[DiagField.codes]!.split(','), hasLength(diagMaxCodes));

      // No codes at all is an absent field, not an empty one.
      expect(build().values.containsKey(DiagField.codes), isFalse);
    });

    test(
      'F1-07-387 the report is built from the injected clock, in UTC, to the '
      'minute — never DateTime.now(), never to the second',
      () {
        // 10:00 IST on the test clock is 04:30 UTC. The seconds are dropped:
        // a to-the-second stamp is a weak identifier and support does not
        // need it.
        final report = build(now: DateTime.utc(2026, 9, 21, 4, 30, 59));
        expect(report.values[DiagField.generatedAt], '2026-09-21T04:30Z');
        expect(
          build(now: DateTime.utc(2026, 1, 2, 3, 4))
              .values[DiagField.generatedAt],
          '2026-01-02T03:04Z',
        );
      },
    );

    test('F1-07-407 the fields print in DiagField order, always', () {
      final report = build(
        device: const DeviceFacts(
          appVersion: '0.1.0+1',
          osVersion: '15',
          problemCodes: ['key_wait'],
        ),
      );
      expect(report.values.keys.toList(), DiagField.values);
    });
  });
}
