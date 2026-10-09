// Rung 3, the making half — ADR 2026-10-06d ruling 3 🔒, ADR 2026-10-07
// ruling 1, 04 §7.4 🔒, 07 §3.1 step 6, canvas c1/O5b.
//
// F1-1006d-1  S0.5b makes the sheet — fresh RK, UMK sealed, blob published —
//             and only then shows it: nothing is printable before the server
//             holds the blob; a failed publish shows its reason and keeps
//             *Skip for now*; otherwise the step has no Skip (07-ruling 1).
// F1-1006d-2  the page is 04 §7.4's: the QR and the typed Crockford code of
//             `version ‖ user_id ‖ RK` (groups of 4, 2-char checksum last),
//             one A4 page, instructions in English plus the user's language
//             in faces that can draw them; *I've kept it safe* wakes once the
//             page has been opened (O5b).
// F1-1006d-3  checking a printed sheet back — scanned or typed — passes only
//             when it opens THIS account's published blob, and ticks the S0.7
//             row's pref; a regenerated sheet voids the old page and reopens
//             the row.
//
// Every test runs the production [LiveRecoverySheetService] over a real test
// ledger (real libsodium); only the server, the renderer's output sink and
// the print sheet are fakes, so a service that published nothing, sealed the
// wrong key or showed a page early fails here.
@Tags(['F1'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rukka_folio/features/home/home_routes.dart' show homeRoot;
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/features/onboarding/recovery_sheet/recovery_sheet_pdf.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart'
    show OnboardingPurpose;
import 'package:rukka_folio/features/reports/export/pdf_report.dart'
    show ReportFonts;
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/sync/recovery_api.dart';
import 'package:rukka_folio/shared/sync/recovery_seams.dart';
import 'package:rukka_folio/shared/tokens.dart' show RkColorsLight;

import '../../shared/design_capture.dart' show rkLoadDesignFonts;
import '../../shared/test_app.dart';
import 'onboarding_router_harness.dart' show resetOnboardingFlow;

/// The server's half of `/recovery/sheet`, recording the order of events.
final class _Server implements RecoveryApi {
  _Server(this.events);

  final List<String> events;
  RecoverySheetWire? held;
  RecoveryApiFailure? failPublish;
  Completer<void>? holdPublish;
  bool failGet = false;
  int gets = 0;
  final published = <Uint8List>[];

  @override
  Future<int> publishSheet(Uint8List blob) async {
    events.add('publish');
    if (holdPublish != null) await holdPublish!.future;
    if (failPublish != null) throw failPublish!;
    published.add(Uint8List.fromList(blob));
    final v = (held?.sheetVersion ?? 0) + 1;
    held = RecoverySheetWire(
      userId: 'server-relays-it',
      sheetVersion: v,
      blob: Uint8List.fromList(blob),
    );
    return v;
  }

  @override
  Future<RecoverySheetWire?> sheet() async {
    gets++;
    if (failGet) throw const RecoveryApiFailure(RecoveryRefusal.offline);
    return held;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The live service with a capturing renderer and printer.
final class _Rig {
  _Rig(this.ledger, {RecoveryQrReader? read}) {
    server = _Server(events);
    service = LiveRecoverySheetService(
      ledger: ledger,
      api: server,
      printer: (pdf, name) async {
        events.add('print');
        printed.add(Uint8List.fromList(pdf));
        // Printed or saved — unless the test cancels the print sheet.
        return !cancelPrint;
      },
      render: (content, locale) async {
        events.add('render');
        contents.add(content);
        final page = Uint8List.fromList(utf8.encode('%PDF-fake'));
        pages.add(page);
        return page;
      },
      read: read,
    );
  }

  final LocalLedger ledger;
  final events = <String>[];
  final contents = <RecoverySheetContent>[];
  final pages = <Uint8List>[];
  final printed = <Uint8List>[];

  /// The person cancels the platform's print sheet.
  bool cancelPrint = false;
  late final _Server server;
  late final LiveRecoverySheetService service;

  /// The typed code the last page printed.
  String get lastCode => contents.last.groups.join('-');
}

Future<LocalLedger> _solo() async {
  final ledger = await openTestLedger();
  await ledger.bootstrapSolo();
  return ledger;
}

Future<GoRouter> _pump(
  WidgetTester tester,
  LocalLedger ledger,
  RecoverySheetService? service, {
  required MemoryPrefs prefs,
  bool onboarded = false,
}) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (onboarded) prefs.values[RkPrefKeys.onboarded] = '1';
  final settings = AppSettings(prefs: prefs);
  await settings.load();
  final router = buildRouter(
    featureRoutes: onboardingRoutes,
    home: homeRoot,
    initialLocation: OnboardingPaths.recoverySheet,
  );
  final app = RukkaFolioApp(
    db: ledger.db,
    sync: FakeSyncClient(),
    auth: FakeAuthClient(),
    keys: ledger.keys as FakeKeyStore,
    now: testNow,
    locale: const Locale('en'),
    router: router,
    ledger: ledger,
    settings: settings,
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    service == null
        ? app
        : RecoverySheetServiceScope(service: service, child: app),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

final _en = lookupAppLocalizations(const Locale('en'));

ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );

bool _enabled(WidgetTester tester, String label) =>
    _button(tester, label).onPressed != null;

/// What a `package:pdf` page actually draws, read back from the bytes: the
/// text runs (decoded through each font's ToUnicode map), the filled
/// rectangles, and how many images are placed. A renderer that ignored its
/// content cannot pass a test over this.
final class _PdfPage {
  _PdfPage(Uint8List pdf) {
    final raw = latin1.decode(pdf);
    final dicts = <int, String>{};
    final streams = <int, Uint8List>{};
    final head = RegExp(r'(\d+) 0 obj');
    var at = 0;
    while (true) {
      final m = head.allMatches(raw, at).firstOrNull;
      if (m == null) break;
      final id = int.parse(m.group(1)!);
      final streamAt = raw.indexOf('stream', m.end);
      final endAt = raw.indexOf('endobj', m.end);
      if (streamAt < 0 || streamAt > endAt) {
        dicts[id] = raw.substring(m.end, endAt);
        at = endAt;
        continue;
      }
      final dict = raw.substring(m.end, streamAt);
      dicts[id] = dict;
      var start = streamAt + 'stream'.length;
      if (raw[start] == '\r') start++;
      if (raw[start] == '\n') start++;
      final length = int.parse(
        RegExp(r'/Length\s*(\d+)').firstMatch(dict)!.group(1)!,
      );
      final bytes = Uint8List.sublistView(pdf, start, start + length);
      streams[id] = dict.contains('FlateDecode')
          ? Uint8List.fromList(zlib.decode(bytes))
          : bytes;
      at = raw.indexOf('endobj', start + length);
    }

    // `/F1 5 0 R` → the font's ToUnicode map (`<cid> <unicode>`).
    final cmaps = <String, Map<int, int>>{};
    for (final d in dicts.values) {
      for (final f in RegExp(r'/(F\d+)\s*(\d+)\s+0\s+R').allMatches(d)) {
        final font = dicts[int.parse(f.group(2)!)] ?? '';
        final ref = RegExp(r'/ToUnicode\s*(\d+)\s+0\s+R').firstMatch(font);
        if (ref == null) continue;
        final cmap = latin1.decode(streams[int.parse(ref.group(1)!)]!);
        cmaps['/${f.group(1)}'] = {
          for (final e in RegExp(
            r'<([0-9A-Fa-f]{4})> <([0-9A-Fa-f]+)>',
          ).allMatches(cmap.substring(cmap.indexOf('beginbfchar'))))
            int.parse(e.group(1)!, radix: 16): int.parse(
              e.group(2)!,
              radix: 16,
            ),
        };
      }
    }

    final op = RegExp(
      r'(/F\d+)\s+[-\d.]+\s+Tf'
      r'|\[<([0-9A-Fa-f]*)>\]TJ'
      r'|([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+) re'
      r'|/\w+ Do',
    );
    for (final content in streams.values) {
      final text = latin1.decode(content);
      if (!text.contains(' Tf ') && !text.contains(' re ')) continue;
      Map<int, int>? cmap;
      for (final m in op.allMatches(text)) {
        if (m.group(1) != null) {
          cmap = cmaps[m.group(1)];
        } else if (m.group(2) != null) {
          final hex = m.group(2)!;
          runs.add(
            String.fromCharCodes([
              for (var i = 0; i + 4 <= hex.length; i += 4)
                cmap![int.parse(hex.substring(i, i + 4), radix: 16)]!,
            ]),
          );
        } else if (m.group(3) != null) {
          rects.add([for (var g = 3; g <= 6; g++) double.parse(m.group(g)!)]);
        } else {
          images++;
        }
      }
    }
  }

  /// Every text run, decoded — `package:pdf` sets one word per run.
  final runs = <String>[];

  /// Every `x y w h re`.
  final rects = <List<double>>[];

  /// Images placed (`Do`).
  var images = 0;

  /// All the page's text, runs joined by spaces.
  String get text => runs.join(' ');

  /// Whether [data]'s QR, as `package:pdf` draws it at [side], is on the
  /// page — every black module, at one offset.
  bool hasQr(String data, double side) {
    final bars = pw.Barcode.qrCode(errorCorrectLevel: recoverySheetQrCorrection)
        .make(data, width: side, height: side)
        .whereType<pw.BarcodeBar>()
        .where((b) => b.black)
        .toList();
    bool near(double a, double b) => (a - b).abs() < 0.01;
    // The widget draws (box.left + left, box.top - top - height, w, h).
    final first = bars.first;
    for (final r in rects) {
      if (!near(r[2], first.width) || !near(r[3], first.height)) continue;
      final dx = r[0] - first.left;
      final dy = r[1] + first.top + first.height;
      final all = bars.every(
        (b) => rects.any(
          (q) =>
              near(q[0], dx + b.left) &&
              near(q[1], dy - b.top - b.height) &&
              near(q[2], b.width) &&
              near(q[3], b.height),
        ),
      );
      if (all) return true;
    }
    return false;
  }
}

bool _indic(String s) => s.runes.any(
  (r) => (r >= 0x0900 && r <= 0x097F) || (r >= 0x0A00 && r <= 0x0A7F),
);

void main() {
  setUp(resetOnboardingFlow);

  group('F1-1006d-1 make → publish → only then show (ADR 2026-10-06d §3)', () {
    test('F1-1006d-1 the blob is published before anything is printable, '
        'and it is the UMK sealed under the printed RK', () async {
      final ledger = await _solo();
      final rig = _Rig(ledger);

      final printout = await rig.service.make(const Locale('en'));
      expect(rig.events, ['render', 'publish']);
      expect(rig.printed, isEmpty, reason: 'made is not shown');
      expect(printout.version, 1);

      // The published bytes are ruling 1's framing, and they open under the
      // RK the page carries to this install's own UMK — not merely bytes.
      final blob = rig.server.published.single;
      expect(blob.length, sealedRecoveryBlobBytes);
      final sheet = recoverySheetFromTyped(ledger.suite, rig.lastCode);
      final umk = openUmkWithRecoveryKeyVerified(
        ledger.suite,
        sheet.rk,
        SealedRecoveryBlob.decode(blob),
        expected: ledger.keyMaterial.umk.public,
      );
      umk.dispose();
      sheet.dispose();

      await printout.open();
      expect(rig.events, ['render', 'publish', 'print']);
      expect(utf8.decode(rig.printed.single), '%PDF-fake');

      printout.discard();
      expect(rig.pages.single.every((b) => b == 0), isTrue);
      expect(printout.open, throwsStateError);
    });

    test('F1-1006d-1 a failed publish names its reason, wipes the page and '
        'leaves nothing to print', () async {
      final ledger = await _solo();
      for (final (refusal, reason) in [
        (RecoveryRefusal.offline, RecoverySheetNotMadeReason.offline),
        (RecoveryRefusal.unauthorized, RecoverySheetNotMadeReason.notSignedIn),
        (RecoveryRefusal.flood, RecoverySheetNotMadeReason.tooMany),
        (
          RecoveryRefusal.upgradeRequired,
          RecoverySheetNotMadeReason.needsUpdate,
        ),
        (RecoveryRefusal.server, RecoverySheetNotMadeReason.server),
      ]) {
        final rig = _Rig(ledger);
        rig.server.failPublish = RecoveryApiFailure(refusal);
        await expectLater(
          rig.service.make(const Locale('en')),
          throwsA(
            isA<RecoverySheetNotMade>().having(
              (e) => e.reason,
              'reason',
              reason,
            ),
          ),
        );
        expect(rig.printed, isEmpty);
        expect(rig.server.held, isNull);
        expect(
          rig.pages.single.every((b) => b == 0),
          isTrue,
          reason: 'the rendered page carries RK; it is zeroed on failure',
        );
      }
    });

    testWidgets('F1-1006d-1 sign-up: no Skip; nothing opens while the publish '
        'is in flight; once held, the print sheet opens and Kept safe wakes '
        'and carries on', (tester) async {
      final ledger = await _solo();
      final rig = _Rig(ledger);
      final prefs = MemoryPrefs();
      onboardingFlow.setPurpose(OnboardingPurpose.myself);
      final router = await _pump(tester, ledger, rig.service, prefs: prefs);

      // Required (ADR 2026-10-07 ruling 1): no way past but making it.
      expect(find.text(_en.onboardingRecoverySheetSkip), findsNothing);
      expect(_enabled(tester, _en.onboardingRecoverySheetKeptSafe), isFalse);
      expect(find.text(_en.onboardingRecoverySheetKeptSafeAsleep), findsOne);

      rig.server.holdPublish = Completer<void>();
      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pump();
      await tester.pump();
      expect(rig.events, ['render', 'publish']);
      expect(rig.printed, isEmpty, reason: 'never a sheet the server lacks');
      expect(_enabled(tester, _en.onboardingRecoverySheetKeptSafe), isFalse);
      expect(find.text(_en.onboardingRecoverySheetGenerating), findsOne);

      rig.server.holdPublish!.complete();
      await tester.pumpAndSettle();
      expect(rig.events, ['render', 'publish', 'print']);
      expect(_enabled(tester, _en.onboardingRecoverySheetKeptSafe), isTrue);
      expect(
        find.text(_en.onboardingRecoverySheetKeptSafeAsleep),
        findsNothing,
      );

      // Opening it again re-opens the same page — it never rotates RK.
      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();
      expect(rig.events, ['render', 'publish', 'print', 'print']);
      expect(rig.server.published, hasLength(1));

      await tester.tap(find.text(_en.onboardingRecoverySheetKeptSafe));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, OnboardingPaths.openingBalances);
      expect(
        prefs.values[RkPrefKeys.recoverySheetVerified],
        isNull,
        reason: 'made is not checked: the S0.7 row stays open',
      );
      // Leaving the step wipes the held page (it carries RK).
      expect(rig.pages.single.every((b) => b == 0), isTrue);
      await _unmount(tester);
    });

    testWidgets('F1-1006d-1 Back into S0.5b keeps the printed page: Kept '
        'safe is awake, nothing is remade, and Print or save warns before a '
        'new sheet voids it (04 §7.4 🔒)', (tester) async {
      final ledger = await _solo();
      final rig = _Rig(ledger);
      onboardingFlow.setPurpose(OnboardingPurpose.myself);
      final router = await _pump(
        tester,
        ledger,
        rig.service,
        prefs: MemoryPrefs(),
      );

      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();
      expect(onboardingFlow.recoverySheetPrinted, isTrue);
      await tester.tap(find.text(_en.onboardingRecoverySheetKeptSafe));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, OnboardingPaths.openingBalances);

      // S0.6's own Back (onboarding_gate.dart: S0.5b is its Back target).
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, OnboardingPaths.recoverySheet);
      expect(rig.server.published, hasLength(1), reason: 'nothing remade');
      expect(_enabled(tester, _en.onboardingRecoverySheetKeptSafe), isTrue);
      expect(
        find.text(_en.onboardingRecoverySheetKeptSafeAsleep),
        findsNothing,
      );

      // Print or save would rotate RK: it asks first; Cancel changes nothing.
      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();
      expect(
        find.text(_en.onboardingRecoverySheetCheckMakeNewWarning),
        findsOne,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(rig.server.published, hasLength(1));
      expect(rig.printed, hasLength(1));

      // Going on makes, publishes and opens a new page.
      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(
            FilledButton,
            _en.onboardingRecoverySheetCheckMakeNew,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(rig.server.published, hasLength(2));
      expect(rig.printed, hasLength(2));
      expect(_enabled(tester, _en.onboardingRecoverySheetKeptSafe), isTrue);

      // Opening that page again does not ask: it is the one held here.
      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(rig.server.published, hasLength(2));
      expect(rig.printed, hasLength(3));
      await _unmount(tester);
    });

    testWidgets('F1-1006d-1 a cancelled print sheet is not an opened page: '
        'Kept safe stays asleep until it is printed or saved', (tester) async {
      final ledger = await _solo();
      final rig = _Rig(ledger)..cancelPrint = true;
      onboardingFlow.setPurpose(OnboardingPurpose.myself);
      await _pump(tester, ledger, rig.service, prefs: MemoryPrefs());

      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();
      expect(rig.printed, hasLength(1), reason: 'the print sheet did open');
      expect(_enabled(tester, _en.onboardingRecoverySheetKeptSafe), isFalse);
      expect(find.text(_en.onboardingRecoverySheetKeptSafeAsleep), findsOne);
      expect(find.text(_en.onboardingRecoverySheetOpenFailed), findsNothing);
      expect(onboardingFlow.recoverySheetPrinted, isFalse);

      rig.cancelPrint = false;
      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();
      expect(rig.server.published, hasLength(1), reason: 'same page reopened');
      expect(_enabled(tester, _en.onboardingRecoverySheetKeptSafe), isTrue);
      expect(onboardingFlow.recoverySheetPrinted, isTrue);
      await _unmount(tester);
    });

    testWidgets('F1-1006d-1 at 390×844 a failed make shows its reason on '
        'screen, directly above Try again (ADR 2026-10-06d ruling 3)', (
      tester,
    ) async {
      final ledger = await _solo();
      final rig = _Rig(ledger);
      rig.server.failPublish = const RecoveryApiFailure(
        RecoveryRefusal.offline,
      );
      const screen = Size(390, 844);
      await pumpRk(
        tester,
        RecoverySheetScreen(service: rig.service, onBack: () {}, onSkip: () {}),
        viewport: screen,
      );
      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();

      final reason = find.text(_en.onboardingRecoverySheetErrorOffline);
      expect(reason, findsOne);
      final box = tester.getRect(reason);
      expect(box.top, greaterThanOrEqualTo(0));
      expect(box.bottom, lessThanOrEqualTo(screen.height));
      final retry = tester.getRect(find.text(_en.onboardingRecoverySheetRetry));
      expect(box.bottom, lessThanOrEqualTo(retry.top));
      expect(find.text(_en.onboardingRecoverySheetSkip), findsOne);
      await _unmount(tester);
    });

    testWidgets('F1-1006d-1 a failed publish: its reason, a retry, and Skip '
        'for now (07 §1 rule 6)', (tester) async {
      final ledger = await _solo();
      final rig = _Rig(ledger);
      rig.server.failPublish = const RecoveryApiFailure(
        RecoveryRefusal.offline,
      );
      onboardingFlow.setPurpose(OnboardingPurpose.myself);
      final router = await _pump(
        tester,
        ledger,
        rig.service,
        prefs: MemoryPrefs(),
      );

      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();
      expect(find.text(_en.onboardingRecoverySheetErrorOffline), findsOne);
      expect(rig.printed, isEmpty);
      expect(_enabled(tester, _en.onboardingRecoverySheetKeptSafe), isFalse);
      expect(_enabled(tester, _en.onboardingRecoverySheetRetry), isTrue);
      expect(find.text(_en.onboardingRecoverySheetSkip), findsOne);

      // A retry that succeeds takes the Skip away again.
      rig.server.failPublish = null;
      await tester.tap(find.text(_en.onboardingRecoverySheetRetry));
      await tester.pumpAndSettle();
      expect(rig.printed, hasLength(1));
      expect(find.text(_en.onboardingRecoverySheetSkip), findsNothing);
      expect(find.text(_en.onboardingRecoverySheetErrorOffline), findsNothing);

      // And the Skip, when it was there, carried on.
      rig.server.failPublish = const RecoveryApiFailure(RecoveryRefusal.server);
      await _unmount(tester);
      resetOnboardingFlow();
      onboardingFlow.setPurpose(OnboardingPurpose.myself);
      final rig2 = _Rig(ledger)
        ..server.failPublish = const RecoveryApiFailure(RecoveryRefusal.server);
      final router2 = await _pump(
        tester,
        ledger,
        rig2.service,
        prefs: MemoryPrefs(),
      );
      await tester.tap(find.text(_en.onboardingRecoverySheetPrint));
      await tester.pumpAndSettle();
      expect(find.text(_en.onboardingRecoverySheetErrorServer), findsOne);
      await tester.tap(find.text(_en.onboardingRecoverySheetSkip));
      await tester.pumpAndSettle();
      expect(router2.state.uri.path, OnboardingPaths.openingBalances);
      expect(router.state.uri.path, isNotEmpty);
      await _unmount(tester);
    });

    testWidgets('F1-1006d-1 no sheet maker on this phone: the reason sits '
        'under the sleeping button and Skip for now carries on (re-lands '
        'F1-1006c-5)', (tester) async {
      final ledger = await _solo();
      onboardingFlow.setPurpose(OnboardingPurpose.myself);
      final router = await _pump(tester, ledger, null, prefs: MemoryPrefs());
      expect(_enabled(tester, _en.onboardingRecoverySheetPrint), isFalse);
      final reason = find.text(_en.onboardingRecoverySheetUnavailable);
      expect(reason, findsOne);
      expect(
        tester.getTopLeft(reason).dy,
        greaterThan(
          tester.getBottomLeft(find.text(_en.onboardingRecoverySheetPrint)).dy,
        ),
      );
      await tester.tap(find.text(_en.onboardingRecoverySheetSkip));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, OnboardingPaths.openingBalances);
      await _unmount(tester);
    });
  });

  group('F1-1006d-2 the page is 04 §7.4 🔒', () {
    test('F1-1006d-2 QR and typed code carry version ‖ user_id ‖ RK; groups '
        'of 4 with the 2-char checksum last', () async {
      final ledger = await _solo();
      final rig = _Rig(ledger);
      (await rig.service.make(const Locale('pa'))).discard();
      final content = rig.contents.single;

      final groups = content.groups;
      expect(groups.last, hasLength(2), reason: 'the checksum group');
      for (final g in groups.sublist(0, groups.length - 2)) {
        expect(g, hasLength(4));
      }
      expect(groups[groups.length - 2].length, inInclusiveRange(1, 4));

      final typed = recoverySheetFromTyped(ledger.suite, rig.lastCode);
      final scanned = recoverySheetFromQr(ledger.suite, content.qr);
      expect(typed.userId, ledger.identity.userId);
      expect(scanned.userId, ledger.identity.userId);
      typed.dispose();
      scanned.dispose();
    });

    testWidgets('F1-1006d-2 one A4 page, English plus the user\'s language, '
        'in faces that draw every rune', (tester) async {
      final ledger = await _solo();
      final rig = _Rig(ledger);
      (await rig.service.make(const Locale('en'))).discard();
      final content = rig.contents.single;

      final fonts = (await tester.runAsync(ReportFonts.load))!;
      Future<Uint8List> page(String lang) async => (await tester.runAsync(
        () => recoverySheetPdf(
          content,
          en: _en,
          local: lookupAppLocalizations(Locale(lang)),
          fonts: fonts,
        ),
      ))!;

      final en = await page('en');
      final pa = await page('pa');
      final hi = await page('hi');
      for (final pdf in [en, pa, hi]) {
        final raw = latin1.decode(pdf);
        expect(raw.startsWith('%PDF'), isTrue);
        expect(
          RegExp(r'/Type\s*/Page(?![s\w])').allMatches(raw),
          hasLength(1),
          reason: 'one page (04 §7.4)',
        );
        expect(
          raw.contains(_en.onboardingRecoverySheetPdfTitle),
          isTrue,
          reason: 'the document title, nothing else, in the metadata',
        );
        expect(
          raw.contains(ledger.identity.userId),
          isFalse,
          reason: 'no user id in the metadata (rule 4)',
        );
      }
      // The second language is a second block, not a translation swap.
      expect(pa.length, greaterThan(en.length));
      expect(hi.length, greaterThan(en.length));

      for (final lang in ['en', 'pa', 'hi']) {
        final l = lookupAppLocalizations(Locale(lang));
        for (final s in recoverySheetPageStrings(l)) {
          expect(fonts.unsupportedRunes(s), isEmpty, reason: '$lang: $s');
        }
        expect(recoverySheetInstructions(l), hasLength(5));
      }
    });
  });

  group('F1-1006d-2 the printed page, read back from its bytes', () {
    testWidgets('F1-1006d-2 renderRecoverySheet (what bootstrap binds) draws '
        'THIS content: the QR of its text and every typed group; the '
        'user\'s language is shaped, never set unshaped by package:pdf', (
      tester,
    ) async {
      await rkLoadDesignFonts(tester);
      final ledger = await _solo();
      final rig = _Rig(ledger);
      (await tester.runAsync(
        () async => (await rig.service.make(const Locale('en'))).discard(),
      ));
      final content = rig.contents.single;
      final fonts = (await tester.runAsync(ReportFonts.load))!;

      for (final lang in ['en', 'pa', 'hi']) {
        final pdf = (await tester.runAsync(
          () => renderRecoverySheet(content, Locale(lang), fonts: fonts),
        ))!;
        final page = _PdfPage(pdf);

        expect(
          page.hasQr(content.qr, recoverySheetQrSide),
          isTrue,
          reason: '$lang: the QR is of content.qr',
        );
        for (final g in content.groups) {
          expect(page.runs, contains(g), reason: '$lang: typed group $g');
        }
        // Order too: the groups read in sequence.
        final at = page.runs.indexOf(content.groups.first);
        expect(
          page.runs.sublist(at, at + content.groups.length),
          content.groups,
        );
        // English instructions are set as text, word for word.
        for (final s in recoverySheetInstructions(_en)) {
          for (final word in s.split(RegExp(r'\s+'))) {
            expect(page.runs, contains(word), reason: '$lang: "$s"');
          }
        }

        // 04 §7.4: the user's language too — and never through pdf 3.13's
        // unshaped text path (it misspells Gurmukhi and Devanagari).
        expect(_indic(page.text), isFalse, reason: '$lang: no unshaped Indic');
        final l = lookupAppLocalizations(Locale(lang));
        expect(
          page.images,
          lang == 'en' ? 0 : 4 + recoverySheetInstructions(l).length,
          reason: '$lang: one shaped line per second-language string',
        );
        expect(
          page.hasQr('${content.qr}x', recoverySheetQrSide),
          isFalse,
          reason: 'the check can fail',
        );
      }
    });

    testWidgets('F1-1006d-2 a shaped line is drawn by the engine in the app '
        'faces: ink on the page, sized in points', (tester) async {
      await rkLoadDesignFonts(tester);
      for (final lang in ['pa', 'hi']) {
        final l = lookupAppLocalizations(Locale(lang));
        final s = l.onboardingRecoverySheetPdfHow2;
        final line = (await tester.runAsync(
          () => shapeRecoverySheetLine(s, size: 10, color: RkColorsLight.text),
        ))!;
        expect(line.width, greaterThan(0));
        expect(line.height, greaterThan(10));
        final inked = (await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(line.png);
          final frame = await codec.getNextFrame();
          final px = (await frame.image.toByteData())!;
          expect(
            frame.image.width,
            (line.width * ShapedLine.rasterScale).ceil(),
          );
          var n = 0;
          for (var i = 3; i < px.lengthInBytes; i += 4) {
            if (px.getUint8(i) > 0) n++;
          }
          frame.image.dispose();
          return n;
        }))!;
        expect(inked, greaterThan(500), reason: '$lang: text was drawn');
      }
    });

    test('F1-1006d-2 step 1 quotes the sign-in button exactly as S0.06 '
        'shows it, in every language', () {
      for (final lang in ['en', 'pa', 'hi']) {
        final l = lookupAppLocalizations(Locale(lang));
        expect(
          l.onboardingRecoverySheetPdfHow1,
          contains('“${l.onboardingStartSignIn}”'),
          reason: lang,
        );
      }
    });
  });

  group('F1-1006d-3 checking the printed sheet back (04 §7.4 🔒)', () {
    test('F1-1006d-3 only a code that opens THIS account\'s published blob '
        'passes; a regenerated sheet voids the old page', () async {
      final ledger = await _solo();
      final rig = _Rig(ledger);

      expect(await rig.service.sheetOnServer(), isFalse);
      (await rig.service.make(const Locale('en'))).discard();
      expect(await rig.service.sheetOnServer(), isTrue);
      final first = rig.lastCode;
      expect(
        await rig.service.checkTyped(first),
        RecoverySheetCheckResult.opens,
      );
      // Typed as a person would: lower case, spaces for the hyphens.
      expect(
        await rig.service.checkTyped(first.toLowerCase().replaceAll('-', ' ')),
        RecoverySheetCheckResult.opens,
      );

      // A mistype is caught by the checksum, on the phone, for nothing.
      final gets = rig.server.gets;
      final i = first.indexOf(RegExp('[2-9]'));
      final wrong =
          '${first.substring(0, i)}${first[i] == '2' ? '3' : '2'}'
          '${first.substring(i + 1)}';
      expect(
        await rig.service.checkTyped(wrong),
        RecoverySheetCheckResult.didNotOpen,
      );
      expect(rig.server.gets, gets);

      // Regenerate: the new page opens, the old one no longer does.
      (await rig.service.make(const Locale('en'))).discard();
      expect(
        await rig.service.checkTyped(rig.lastCode),
        RecoverySheetCheckResult.opens,
      );
      expect(
        await rig.service.checkTyped(first),
        RecoverySheetCheckResult.didNotOpen,
      );

      // Somebody else's sheet.
      final other = await _solo();
      final otherRig = _Rig(other);
      (await otherRig.service.make(const Locale('en'))).discard();
      expect(other.identity.userId, isNot(ledger.identity.userId));
      expect(
        await rig.service.checkTyped(otherRig.lastCode),
        RecoverySheetCheckResult.otherAccount,
      );

      // The server holds nothing / cannot be asked.
      final empty = _Rig(ledger);
      expect(
        await empty.service.checkTyped(first),
        RecoverySheetCheckResult.noSheet,
      );
      rig.server.failGet = true;
      expect(
        await rig.service.checkTyped(rig.lastCode),
        RecoverySheetCheckResult.couldNotCheck,
      );
    });

    test('F1-1006d-3 a scanned square reaches the same verdict as the typed '
        'code; backing out or no camera is no verdict', () async {
      final ledger = await _solo();
      late String qr;
      var answer = 'scan';
      Future<RecoveryQrRead<T>> read<T extends Object>(
        T? Function(String) decode,
      ) async => switch (answer) {
        'cancel' => RecoveryQrCancelled<T>(),
        'none' => RecoveryQrNoCamera<T>(),
        _ => RecoveryQrValue<T>(decode(qr)!),
      };
      final rig = _Rig(ledger, read: read);
      (await rig.service.make(const Locale('en'))).discard();
      qr = rig.contents.single.qr;

      expect(await rig.service.scan(), RecoverySheetCheckResult.opens);
      answer = 'cancel';
      expect(await rig.service.scan(), RecoverySheetCheckResult.cancelled);
      answer = 'none';
      expect(await rig.service.scan(), RecoverySheetCheckResult.noCamera);
      expect(
        recoverySheetCodeOfQrText(ledger.suite, 'upi://pay?pa=shop@bank'),
        isNull,
        reason: 'a stray QR is not an answer',
      );
      expect(
        await _Rig(ledger).service.scan(),
        RecoverySheetCheckResult.noCamera,
      );
    });

    testWidgets('F1-1006d-3 reopened from S0.7: the sheet on the server is '
        'checked, not remade; a typed code that opens it ticks the row', (
      tester,
    ) async {
      final ledger = await _solo();
      final rig = _Rig(ledger);
      (await tester.runAsync(
        () async => (await rig.service.make(const Locale('en'))).discard(),
      ));
      final code = rig.lastCode;
      final prefs = MemoryPrefs();
      final router = await _pump(
        tester,
        ledger,
        rig.service,
        prefs: prefs,
        onboarded: true,
      );

      expect(find.text(_en.onboardingRecoverySheetCheckHeading), findsOne);
      expect(find.text(_en.onboardingRecoverySheetPrint), findsNothing);
      expect(rig.server.published, hasLength(1), reason: 'nothing remade');

      // A wrong code first: both R2.4b causes, and the row stays open.
      await tester.tap(find.text(_en.onboardingRecoverySheetCheckType));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('s0_5b.code')),
        code.replaceRange(0, 1, code[0] == 'A' ? 'B' : 'A'),
      );
      await tester.pump();
      await tester.tap(find.text(_en.onboardingRecoverySheetCheckSubmit));
      await tester.pumpAndSettle();
      expect(find.text(_en.onboardingRecoverySheetCheckFailedTitle), findsOne);
      expect(find.text(_en.onboardingRecoverySheetCheckFailedNewer), findsOne);
      expect(prefs.values[RkPrefKeys.recoverySheetVerified], isNull);

      await tester.enterText(find.byKey(const ValueKey('s0_5b.code')), code);
      await tester.pump();
      await tester.tap(find.text(_en.onboardingRecoverySheetCheckSubmit));
      await tester.pumpAndSettle();
      expect(find.text(_en.onboardingRecoverySheetCheckVerified), findsOne);
      // What S1's checklist reads for *Check your recovery sheet*
      // (s1_home_screen.dart: SetupProgress.recoverySheetVerified).
      expect(prefs.values[RkPrefKeys.recoverySheetVerified], '1');
      expect(await SetupProgress.recoverySheetVerified(prefs), isTrue);

      await tester.tap(find.text(_en.onboardingRecoverySheetDone));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, isNot(OnboardingPaths.recoverySheet));
      await _unmount(tester);
    });

    testWidgets('F1-1006d-3 Make a new sheet warns first; going on rotates RK '
        'and opens the row again', (tester) async {
      final ledger = await _solo();
      final rig = _Rig(ledger);
      (await tester.runAsync(
        () async => (await rig.service.make(const Locale('en'))).discard(),
      ));
      final prefs = MemoryPrefs()
        ..values[RkPrefKeys.recoverySheetVerified] = '1';
      await _pump(tester, ledger, rig.service, prefs: prefs, onboarded: true);

      await tester.tap(find.text(_en.onboardingRecoverySheetCheckMakeNew));
      await tester.pumpAndSettle();
      expect(
        find.text(_en.onboardingRecoverySheetCheckMakeNewWarning),
        findsOne,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        rig.server.published,
        hasLength(1),
        reason: 'cancel changes nothing',
      );

      await tester.tap(find.text(_en.onboardingRecoverySheetCheckMakeNew));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(
            FilledButton,
            _en.onboardingRecoverySheetCheckMakeNew,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(rig.server.published, hasLength(2));
      expect(rig.printed, hasLength(1));
      expect(
        prefs.values[RkPrefKeys.recoverySheetVerified],
        isNull,
        reason: 'the checked page no longer works (04 §7.4)',
      );
      expect(_enabled(tester, _en.onboardingRecoverySheetKeptSafe), isTrue);
      await _unmount(tester);
    });
  });
}
