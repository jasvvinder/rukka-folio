// F1-07-399 … F1-07-405 — S17.4 Send diagnostics (13 §3.2 row S17.4
// "user-triggered, financial values scrubbed, **shown before sending**";
// 07 §22 🔒; **CLAUDE.md rule 4**).
//
// S17.4 is a state machine (13 §4.3) and every one of its states is drawn
// and asserted here: skeleton → payload shown → sending → sent, the collect
// error, the send error, and the two disabled-with-reason states (no channel,
// offline).
//
// F1-07-404 is the one that matters most: the payload is shown before it is
// sent, so the scrub is visible behaviour. It pumps the screen over a seeded
// ledger full of amounts, account names and party names, with a device seam
// and a sync status poisoned with the same, and asserts none of it reaches
// the screen — and that what the sender receives is byte-for-byte what the
// screen showed.
@Tags(['F1'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/help/diagnostics_report.dart';
import 'package:rukka_folio/features/help/diagnostics_seams.dart';
import 'package:rukka_folio/features/help/screens/s17_4_diagnostics_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../../shared/test_app.dart';

/// A device seam under the test's control: it can be held open (to see the
/// skeleton), made to throw (to see the collect error), and counted.
final class _FakeDevice implements DiagnosticsDevice {
  _FakeDevice({this.facts = const DeviceFacts(), this.gate, this.fail = false});

  DeviceFacts facts;
  Completer<void>? gate;
  bool fail;
  int reads = 0;

  @override
  Future<DeviceFacts> read() async {
    reads++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (fail) throw StateError('cannot read the phone');
    return facts;
  }
}

/// A sender that records exactly what it was handed.
final class _FakeSender implements DiagnosticsSender {
  _FakeSender({this.gate, this.fail = false});

  Completer<void>? gate;
  bool fail;
  final sent = <String>[];

  @override
  Future<void> send(String payload) async {
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (fail) throw StateError('no channel');
    sent.add(payload);
  }
}

void main() {
  /// Every `label: value` line the screen draws in its payload block.
  List<String> payloadLines(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .where((s) => DiagField.values.any((f) => s.startsWith('${f.wire}: ')))
      .toList();

  /// Every string drawn anywhere in the tree.
  List<String> allText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .toList();

  group('S17.4 Send diagnostics', () {
    testWidgets(
      'F1-07-399 the skeleton comes first, then the report whole: the fields '
      'it says it carries, the exclusions, and the payload as it will be sent',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final gate = Completer<void>();
        final device = _FakeDevice(
          gate: gate,
          facts: const DeviceFacts(appVersion: '0.1.0+1', osVersion: '18.5'),
        );
        await pumpRk(
          tester,
          SendDiagnosticsScreen(device: device),
          viewport: rkTallViewport,
        );

        // Collecting: a ruled skeleton with the wait stated in words
        // (11 §4.5, 13 §4.3) — never a spinner, never a blank page.
        expect(find.byType(RkSkeleton), findsOneWidget);
        expect(find.text(l10n.diagActionSend), findsNothing);

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(RkSkeleton), findsNothing);
        expect(find.text(l10n.diagIntro), findsOneWidget);
        expect(find.text(l10n.diagIncludedHeading), findsOneWidget);
        expect(find.text(l10n.diagPayloadHeading), findsOneWidget);

        // Every field the report carries has its label beside its value,
        // and the payload block prints the same field on its own line.
        expect(find.text(l10n.diagFieldAppVersion), findsOneWidget);
        expect(find.text(l10n.diagFieldSyncState), findsOneWidget);
        expect(payloadLines(tester), contains('app_version: 0.1.0+1'));
        expect(payloadLines(tester), contains('os_version: 18.5'));
        expect(payloadLines(tester), contains('sync_state: synced'));
        expect(payloadLines(tester), contains('platform: android'));

        // The exclusions are stated on the screen, each carried by an icon as
        // well as its words (07 §1 rule 3), with the by-construction
        // footnote.
        expect(find.text(l10n.diagExcludedHeading), findsOneWidget);
        for (final line in [
          l10n.diagExcludedAmounts,
          l10n.diagExcludedNames,
          l10n.diagExcludedNotes,
          l10n.diagExcludedPeople,
        ]) {
          expect(find.text(line), findsOneWidget, reason: 'missing: $line');
        }
        expect(find.text(l10n.diagExcludedFootnote), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-400 a collect failure is a state with a retry, never a red '
      'screen — and the retry reads the phone again (13 §4.3)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final device = _FakeDevice(fail: true);
        await pumpRk(
          tester,
          SendDiagnosticsScreen(device: device),
          viewport: rkTallViewport,
        );

        expect(find.text(l10n.diagCollectError), findsOneWidget);
        expect(find.text(l10n.diagErrorRetry), findsOneWidget);
        expect(find.text(l10n.diagActionSend), findsNothing);
        expect(tester.takeException(), isNull);
        expect(device.reads, 1);

        device.fail = false;
        device.facts = const DeviceFacts(appVersion: '0.1.0+1');
        await tester.tap(find.text(l10n.diagErrorRetry));
        await tester.pumpAndSettle();

        expect(device.reads, 2);
        expect(find.text(l10n.diagCollectError), findsNothing);
        expect(payloadLines(tester), contains('app_version: 0.1.0+1'));
      },
    );

    testWidgets(
      'F1-07-401 with no device seam at all the report is still built, from '
      'what the app knows about itself — the unreadable fields are OMITTED, '
      'never guessed',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        // This is the production wiring in `helpRoutes`: device null.
        await pumpRk(
          tester,
          const SendDiagnosticsScreen(),
          viewport: rkTallViewport,
        );

        final lines = payloadLines(tester);
        expect(lines, contains('platform: android'));
        expect(lines, contains('language: en'));
        expect(lines, contains('schema_version: 4'));
        expect(lines, contains('sync_state: synced'));
        expect(lines, contains('outbox_depth: 0'));

        // Absent, not "unknown" — a placeholder would read like a fact.
        expect(
          lines.where((l) => l.startsWith('app_version')),
          isEmpty,
          reason: 'no producer for the app version: the field must be absent',
        );
        expect(find.text(l10n.diagFieldAppVersion), findsNothing);
        expect(find.text(l10n.diagFieldOsVersion), findsNothing);
        expect(find.text(l10n.diagFieldCodes), findsNothing);
      },
    );

    testWidgets(
      'F1-07-402 sending → sent, and what the sender receives is exactly the '
      'payload the person read (07 §22 🔒: shown before sending)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final gate = Completer<void>();
        final sender = _FakeSender(gate: gate);
        await pumpRk(
          tester,
          SendDiagnosticsScreen(
            device: _FakeDevice(
              facts: const DeviceFacts(appVersion: '0.1.0+1'),
            ),
            sender: sender,
          ),
          viewport: rkTallViewport,
        );

        final shown = payloadLines(tester);
        expect(shown, isNotEmpty);

        await tester.tap(find.text(l10n.diagActionSend));
        await tester.pump();

        // Sending: the wait is stated and both actions are held.
        expect(find.text(l10n.diagSending), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text(l10n.diagSentTitle), findsOneWidget);
        expect(find.text(l10n.diagSentBody), findsOneWidget);
        // The payload stays on screen after sending, so the person can always
        // see what went (`diag.sent.body`).
        expect(payloadLines(tester), shown);

        // Byte-for-byte: the sender got the lines the screen drew, in order.
        expect(sender.sent, hasLength(1));
        expect(sender.sent.single.split('\n'), shown);
      },
    );

    testWidgets(
      'F1-07-403 a send failure says nothing was sent, keeps the payload, '
      'and offers the retry (13 §4.3)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final sender = _FakeSender(fail: true);
        await pumpRk(
          tester,
          SendDiagnosticsScreen(device: _FakeDevice(), sender: sender),
          viewport: rkTallViewport,
        );
        final shown = payloadLines(tester);

        await tester.tap(find.text(l10n.diagActionSend));
        await tester.pumpAndSettle();

        expect(find.text(l10n.diagErrorTitle), findsOneWidget);
        expect(find.text(l10n.diagErrorBody), findsOneWidget);
        expect(sender.sent, isEmpty);
        expect(payloadLines(tester), shown, reason: 'the report is unchanged');
        expect(tester.takeException(), isNull);

        sender.fail = false;
        await tester.tap(find.text(l10n.diagErrorRetry));
        await tester.pumpAndSettle();
        expect(find.text(l10n.diagSentTitle), findsOneWidget);
        expect(sender.sent.single.split('\n'), shown);
      },
    );

    testWidgets('F1-07-404 with no channel and when offline the send is '
        'disabled-with-reason, and Copy is the way on (07 §1 rules 6, 7 🔒)', (
      tester,
    ) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // No sender: the standing case while ADR 2026-09-19 is unratified.
      await pumpRk(
        tester,
        SendDiagnosticsScreen(device: _FakeDevice()),
        viewport: rkTallViewport,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text(l10n.diagSendReasonChannel), findsOneWidget);
      // The reason is carried by an icon as well as its words.
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      // And the way on works: the payload reaches the clipboard.
      final clipboard = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final shown = payloadLines(tester);
      await tester.tap(find.text(l10n.diagActionCopy));
      await tester.pumpAndSettle();
      expect(clipboard, hasLength(1));
      expect(
        (clipboard.single.arguments as Map)['text'].toString().split('\n'),
        shown,
      );
      expect(find.text(l10n.diagCopied), findsOneWidget);

      // Offline with a channel: the send waits, quietly, and says why —
      // offline is a state, never a block (07 §1 rule 7 🔒).
      final sync = FakeSyncClient(initial: const Offline());
      await pumpRk(
        tester,
        SendDiagnosticsScreen(device: _FakeDevice(), sender: _FakeSender()),
        sync: sync,
        viewport: rkTallViewport,
      );
      expect(find.text(l10n.diagOffline), findsOneWidget);
      expect(find.text(l10n.diagSendReasonOffline), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(payloadLines(tester), contains('sync_state: offline'));

      // The connection comes back and the door opens, with no reason left
      // on screen.
      sync.current = const Synced();
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagSendReasonOffline), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets(
      'F1-07-405 the payload shown to the person carries NO amount, account '
      'name or party name, even over a seeded ledger and a device seam '
      'stuffed with them (CLAUDE.md rule 4)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        // A real book with real postings sits above the screen, and the
        // waiting-for status carries a member name (05 §9). If anything on
        // S17.4 reached for ledger data, or printed what it was handed, these
        // strings would be on screen.
        final seeded = await seedSoloLedger();
        final sync = FakeSyncClient(initial: const WaitingFor('Sunita Kaur'));
        final sender = _FakeSender();
        await pumpRk(
          tester,
          SendDiagnosticsScreen(
            device: _FakeDevice(
              facts: const DeviceFacts(
                appVersion: 'Ramesh ₹18,600.00',
                osVersion: 'Cash in hand 15',
                problemCodes: [
                  'projector failed on Ramesh: 1860000',
                  'amount_1860000',
                  'Saturday sales',
                  'sync_rejected_quota',
                ],
              ),
            ),
            sender: sender,
          ),
          ledger: seeded.ledger,
          sync: sync,
          viewport: rkTallViewport,
        );

        await tester.tap(find.text(l10n.diagActionSend));
        await tester.pumpAndSettle();
        expect(find.text(l10n.diagSentTitle), findsOneWidget);

        final onScreen = allText(tester).join('\n');
        final payload = sender.sent.single;
        for (final leak in [
          '1860000',
          '18,600',
          '₹',
          'Ramesh',
          'Sunita',
          'Cash in hand',
          'Diesel',
          'Saturday sales',
          'SBI Saving',
        ]) {
          expect(
            payload,
            isNot(contains(leak)),
            reason: 'CLAUDE.md rule 4: "$leak" was SENT',
          );
          expect(
            onScreen,
            isNot(contains(leak)),
            reason: 'CLAUDE.md rule 4: "$leak" was shown on S17.4',
          );
        }

        // The allowed side: the state word stands in for the member name,
        // and the one well-shaped code survived — so this test cannot pass
        // by the report being empty.
        expect(payload, contains('sync_state: waiting_for_author'));
        expect(payload, contains('codes: sync_rejected_quota'));
        expect(payload, contains('platform: '));
        expect(payload, contains('schema_version: '));
      },
    );

    testWidgets(
      'F1-07-410 strings resolve in EN, PA and HI and nothing is cut at '
      '130 % or 200 % on either phone, scrolled to the actions',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                SendDiagnosticsScreen(
                  device: _FakeDevice(
                    facts: const DeviceFacts(
                      appVersion: '0.1.0+1',
                      osVersion: '18.5.1',
                      problemCodes: ['key_wait', 'pull_cursor_reset'],
                    ),
                  ),
                ),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expect(
                find.text(l10n.diagTitle),
                findsWidgets,
                reason: '${locale.languageCode} title missing',
              );
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'above the fold',
              );
              await tester.scrollUntilVisible(
                find.text(l10n.diagActionCopy),
                300,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'scrolled to the actions',
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
