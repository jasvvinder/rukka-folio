// F1-07-313 · F1-07-314 · F1-07-315 — the recovery scans over the ceremony
// scanner, and the *Call* controls over the dialer (ADR 2026-09-19 🔒).
//
// Every scan here goes the whole real way: the screen asks its seam, the seam
// asks the scanner builder in `recovery_seams.dart`, that asks
// [RecoveryCamera], which pushes the real scan screen over a
// [FakeCeremonyScanner]; the payload is a real `core_crypto` encoding and the
// comparison is `core_crypto`'s. Only the camera hardware is fake. So a
// scanner that answered *unavailable*, or a comparison that answered
// *mismatch*, fails these tests — they are not green over a stub.
//
// Keys are synthetic public halves (CLAUDE.md rule 4); the recovery key is
// minted per test and never leaves the process.
import 'dart:io';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ceremony/camera_scanner.dart';
import 'package:rukka_folio/features/recovery/recovery_camera.dart';
import 'package:rukka_folio/features/recovery/screens/s11_2_ask_members_screen.dart';
import 'package:rukka_folio/features/recovery/screens/s11_3_sheet_screen.dart';
import 'package:rukka_folio/features/recovery/screens/s11_7_guardian_approval_screen.dart';
import 'package:rukka_folio/features/recovery/sheet_qr.dart';
import 'package:rukka_folio/features/recovery/widgets/recovery_parts.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/seams/dialer.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/widgets/rk_fit_text.dart';
import 'package:rukka_folio/shared/sync/recovery_seams.dart';

import '../../shared/test_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _user = '3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const _newDevice = '7a7b7c7d-1111-4222-8333-944455556666';

Uint8List _bytes(int seed, [int length = 32]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (seed + i * 7) % 256));

UmkPublic _umk(int seed) =>
    UmkPublic(x25519: _bytes(seed), ed25519: _bytes(seed + 1));

/// What a member's phone renders for this user's key (04 §6.1).
String _ownKeyQr(UmkPublic umk) =>
    QrPayload(userId: _user, umk: umk, nonce: _bytes(9, 16)).encode();

/// What the fresh phone renders for its candidate key (04 §9.1).
String _candidateQr(Uint8List x25519, {String deviceId = _newDevice}) =>
    DeviceQrPayload(
      device: DevicePublic(
        deviceId: deviceId,
        ed25519: _bytes(77),
        x25519: x25519,
      ),
      nonce: _bytes(5, 16),
    ).encode();

/// A camera whose scanners are recorded, so a test can play a read into the
/// one the scan screen is holding.
final class _Camera {
  _Camera({this.status = CameraStatus.ready});

  final CameraStatus status;
  final scanners = <FakeCeremonyScanner>[];

  late final camera = RecoveryCamera(
    newScanner: () {
      final s = FakeCeremonyScanner(status: status);
      scanners.add(s);
      return s;
    },
  );

  Future<void> read(WidgetTester tester, String text) async {
    scanners.last.emit(text);
    await tester.pumpAndSettle();
  }
}

/// S11.2's seam, with the attempt scripted and the **scan real**: the
/// ceremony goes to [scanner], the builder `bootstrap.dart` installs.
final class _ScanningRecovery implements GuardianRecovery {
  _ScanningRecovery(this.scanner)
    : _inner = FakeGuardianRecovery(initial: _attempt());

  final RecoveryScanner scanner;
  final FakeGuardianRecovery _inner;

  static GuardianRecoveryAttempt _attempt({String? phone = '98765 43211'}) =>
      GuardianRecoveryAttempt(
        requestId: 'req-1',
        k: 2,
        n: 3,
        state: RecoveryAttemptState.pending,
        approvers: [
          const TrustedApprover(
            memberId: 'm1',
            name: 'Sunita',
            state: TrustedApproverState.approved,
          ),
          TrustedApprover(
            memberId: 'm2',
            name: 'Harjit',
            state: TrustedApproverState.waiting,
            phone: phone,
          ),
        ],
      );

  @override
  Stream<GuardianRecoveryAttempt> watch() => _inner.watch();

  @override
  GuardianRecoveryAttempt? get current => _inner.current;

  @override
  Future<void> refresh() => _inner.refresh();

  @override
  Future<RecoveryScanOutcome> verifyOwnKeyByScan() => scanner(
    RecoveryCandidate(
      requestId: 'req-1',
      deviceId: _newDevice,
      candidatePubX: _bytes(40),
    ),
  );
}

/// The one route each producer reads, scripted.
final class _Api extends Fake implements RecoveryApi {
  _Api({this.ask, this.sheetWire});

  final RecoveryAskWire? ask;
  final RecoverySheetWire? sheetWire;

  @override
  Future<List<RecoveryAskWire>> asks() async => [?ask];

  @override
  Future<RecoverySheetWire?> sheet() async => sheetWire;
}

RecoveryAskWire _ask(Uint8List candidatePubX) => RecoveryAskWire(
  requestId: 'req-1',
  subjectUserId: _user,
  candidateDevice: _newDevice,
  candidatePubX: candidatePubX,
  shareSetVersion: 1,
  createdAtMs: 1000,
  expiresAtMs: 260200000,
);

HttpGuardianApprovals _approvals(
  RecoveryScanner scanner, {
  Uint8List? relayed,
  String? phone = '98765 43210',
  bool canReseal = true,
}) => HttpGuardianApprovals(
  api: _Api(ask: _ask(relayed ?? _bytes(40))),
  requesterNameOf: (_) => 'Asha',
  deviceNameOf: (_) => 'iPhone 13',
  fingerprintOf: (_) => 'AB12 CD34 EF56 7890',
  phoneOf: (_) => phone,
  scanner: scanner,
  // The re-seal is 04 §7.3 step 3, not built; a stand-in lets these tests
  // reach the scan at all — without one the seam refuses to open the camera
  // (review SCAN1 #4), which its own test below pins.
  resealer: canReseal ? (_) async => Uint8List(0) : null,
);

/// S11.2's **live** producer's routes, scripted: one open attempt of this
/// phone's, which [cancel] closes the way the server would.
final class _LiveApi extends Fake implements RecoveryApi {
  _LiveApi({this.refuseCancel = false});

  bool refuseCancel;
  final cancels = <String>[];
  var _state = 'pending';

  static final _pub = _bytes(40);

  @override
  Future<List<RecoveryRequestWire>> myRequests() async => [
    RecoveryRequestWire(
      requestId: 'req-1',
      candidateDevice: _newDevice,
      candidatePubX: _pub,
      shareSetVersion: 1,
      openedState: 'pending',
      createdAtMs: 1000,
      expiresAtMs: 260200000,
    ),
  ];

  @override
  Future<RecoveryProgressWire> progress(String requestId) async =>
      RecoveryProgressWire(
        requestId: requestId,
        shareSetVersion: 1,
        k: 2,
        n: 3,
        approvals: 0,
        denials: 0,
        openedState: 'pending',
        state: _state,
      );

  @override
  Future<void> cancel(String requestId) async {
    cancels.add(requestId);
    if (refuseCancel) {
      throw const RecoveryApiFailure(RecoveryRefusal.offline);
    }
    _state = 'cancelled';
  }
}

/// A dialer that records and answers [ok].
final class _Dialer implements Dialer {
  _Dialer({this.ok = true});

  final bool ok;
  final dialled = <String>[];

  @override
  Future<bool> dial(String number) async {
    dialled.add(number);
    return ok;
  }
}

Widget _hosted(_Camera camera, Widget screen, {Dialer? dialer}) {
  final hosted = RecoveryCameraHost(camera: camera.camera, child: screen);
  return dialer == null ? hosted : DialerScope(dialer: dialer, child: hosted);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  late CryptoSuite suite;
  setUpAll(() async => suite = await testSuite());

  // -------------------------------------------------------------------------
  group('F1-07-313 the recovery scans run over the ceremony scanner '
      '(ADR 2026-09-19 ruling 1 🔒)', () {
    testWidgets('F1-07-313 S11.2 reaches its verified state: a member’s '
        'screen showing this user’s own key passes the ceremony and the '
        'members appear', (tester) async {
      final camera = _Camera();
      final umk = _umk(1);
      final seam = _ScanningRecovery(
        ownKeyQrScanner(
          suite: suite,
          read: camera.camera.read,
          userId: _user,
          relayedOwnUmk: () async => umk,
        ),
      );
      await pumpRk(
        tester,
        _hosted(camera, AskTrustedMembersScreen(recovery: seam)),
        viewport: rkTallViewport,
      );
      expect(find.text('Sunita'), findsNothing);

      await _tapText(tester, 'Scan their screen');
      expect(find.text('Scan the square code'), findsOneWidget);
      // A stray QR is not an answer: the camera keeps looking, says so, and
      // nothing passes or fails.
      await camera.read(tester, 'upi://pay?pa=shop@bank');
      expect(find.textContaining('That is a different code'), findsOneWidget);
      expect(find.text('Sunita'), findsNothing);

      await camera.read(tester, _ownKeyQr(umk));
      expect(find.text('Scan the square code'), findsNothing);
      expect(find.text('Sunita'), findsOneWidget);
      expect(camera.scanners.single.disposed, isTrue);
    });

    testWidgets('F1-07-313 S11.2 fails closed when the key shown is not the '
        'relayed one — the comparison is real', (tester) async {
      final camera = _Camera();
      final seam = _ScanningRecovery(
        ownKeyQrScanner(
          suite: suite,
          read: camera.camera.read,
          userId: _user,
          relayedOwnUmk: () async => _umk(1),
        ),
      );
      await pumpRk(
        tester,
        _hosted(camera, AskTrustedMembersScreen(recovery: seam)),
        viewport: rkTallViewport,
      );
      await _tapText(tester, 'Scan their screen');
      await camera.read(tester, _ownKeyQr(_umk(2)));
      expect(
        find.textContaining('does not match this account'),
        findsOneWidget,
      );
      expect(find.text('Sunita'), findsNothing);
    });

    testWidgets('F1-13c-1 S11.2 on the live producer: a ceremony mismatch '
        'closes the attempt, and coming back cannot scan again — no override '
        '(ADR 2026-09-13c ruling 1 🔒)', (tester) async {
      final camera = _Camera();
      final api = _LiveApi();
      final seam = HttpGuardianRecovery(
        api: api,
        roster: (_) async => const [],
        ticker: (_) => const Stream.empty(),
        scanner: ownKeyQrScanner(
          suite: suite,
          read: camera.camera.read,
          userId: _user,
          relayedOwnUmk: () async => _umk(1),
        ),
      );
      await pumpRk(
        tester,
        _hosted(camera, AskTrustedMembersScreen(recovery: seam)),
        viewport: rkTallViewport,
      );
      await _tapText(tester, 'Scan their screen');
      await camera.read(tester, _ownKeyQr(_umk(2)));
      expect(
        find.textContaining('does not match this account'),
        findsOneWidget,
      );
      expect(api.cancels, ['req-1'], reason: 'the attempt is closed');
      expect(seam.current?.state, RecoveryAttemptState.cancelled);

      // Leave and come back: a new screen, the same producer.
      await pumpRk(tester, const SizedBox());
      await pumpRk(
        tester,
        _hosted(camera, AskTrustedMembersScreen(recovery: seam)),
        viewport: rkTallViewport,
      );
      await _tapText(tester, 'Scan their screen');
      expect(find.text('Scan the square code'), findsNothing);
      expect(camera.scanners, hasLength(1), reason: 'no second camera');
      expect(
        find.textContaining('does not match this account'),
        findsOneWidget,
      );
    });

    testWidgets('F1-13c-1 a close that did not reach the server leaves the '
        'verdict standing and is tried again on the next scan', (tester) async {
      final camera = _Camera();
      final api = _LiveApi(refuseCancel: true);
      final seam = HttpGuardianRecovery(
        api: api,
        roster: (_) async => const [],
        ticker: (_) => const Stream.empty(),
        scanner: ownKeyQrScanner(
          suite: suite,
          read: camera.camera.read,
          userId: _user,
          relayedOwnUmk: () async => _umk(1),
        ),
      );
      await pumpRk(
        tester,
        _hosted(camera, AskTrustedMembersScreen(recovery: seam)),
        viewport: rkTallViewport,
      );
      await _tapText(tester, 'Scan their screen');
      await camera.read(tester, _ownKeyQr(_umk(2)));
      expect(
        find.textContaining('does not match this account'),
        findsOneWidget,
      );
      expect(api.cancels, ['req-1']);
      expect(seam.current?.state, isNot(RecoveryAttemptState.cancelled));

      api.refuseCancel = false;
      await pumpRk(tester, const SizedBox());
      await pumpRk(
        tester,
        _hosted(camera, AskTrustedMembersScreen(recovery: seam)),
        viewport: rkTallViewport,
      );
      await _tapText(tester, 'Scan their screen');
      expect(camera.scanners, hasLength(1), reason: 'no second camera');
      expect(
        find.textContaining('does not match this account'),
        findsOneWidget,
      );
      expect(api.cancels, ['req-1', 'req-1'], reason: 'the close is retried');
      expect(seam.current?.state, RecoveryAttemptState.cancelled);
    });

    testWidgets('F1-07-313 S11.7 reaches its verified state: the new phone’s '
        'code matches the relayed request and the tick says so in words', (
      tester,
    ) async {
      final camera = _Camera();
      final candidate = _bytes(40);
      final approvals = _approvals(
        candidateQrScanner(suite: suite, read: camera.camera.read),
        relayed: candidate,
      );
      await pumpRk(
        tester,
        _hosted(
          camera,
          GuardianApprovalScreen(requestId: 'req-1', approvals: approvals),
        ),
        viewport: rkTallViewport,
      );
      expect(find.text('Their phone matched this request'), findsNothing);
      await _tapText(tester, 'Scan their new phone');
      await camera.read(tester, _candidateQr(candidate));
      expect(find.text('Their phone matched this request'), findsOneWidget);
    });

    testWidgets('F1-07-313 S11.7 with no resealer keeps its honest '
        'cannot-approve state and never opens the camera — a scan could only '
        'lead to an Approve that always fails (07 §1 rule 6 🔒)', (
      tester,
    ) async {
      final camera = _Camera();
      final approvals = _approvals(
        candidateQrScanner(suite: suite, read: camera.camera.read),
        canReseal: false,
      );
      await pumpRk(
        tester,
        _hosted(
          camera,
          GuardianApprovalScreen(requestId: 'req-1', approvals: approvals),
        ),
        viewport: rkTallViewport,
      );
      await _tapText(tester, 'Scan their new phone');
      expect(camera.scanners, isEmpty);
      expect(find.textContaining('so it cannot approve'), findsWidgets);
      expect(find.text('Their phone matched this request'), findsNothing);
      await expectLater(
        approvals.approve('req-1'),
        throwsA(isA<RecoveryCandidateUnverified>()),
      );
    });

    testWidgets('F1-07-313 S11.7 refuses a phone that is not the one the '
        'request names (the substitution the ruling exists to catch)', (
      tester,
    ) async {
      final camera = _Camera();
      final approvals = _approvals(
        candidateQrScanner(suite: suite, read: camera.camera.read),
        relayed: _bytes(40),
      );
      await pumpRk(
        tester,
        _hosted(
          camera,
          GuardianApprovalScreen(requestId: 'req-1', approvals: approvals),
        ),
        viewport: rkTallViewport,
      );
      await _tapText(tester, 'Scan their new phone');
      await camera.read(tester, _candidateQr(_bytes(41)));
      expect(
        find.textContaining('does not match this request'),
        findsOneWidget,
      );
      expect(find.text('Their phone matched this request'), findsNothing);
      await expectLater(
        approvals.approve('req-1'),
        throwsA(isA<RecoveryCandidateUnverified>()),
      );
    });

    testWidgets('F1-07-313 S11.3 reaches its verified state: the sheet’s QR '
        'becomes the typed code, one opener verdict, and the restore starts', (
      tester,
    ) async {
      final camera = _Camera();
      final rk = RecoveryKey.generate(suite);
      addTearDown(rk.dispose);
      final printedQr = recoverySheetQr(_user, rk);
      final printedTyped = recoverySheetTyped(suite, _user, rk);
      final opened = <String>[];
      final sheet = HttpRecoverySheet(
        api: _Api(
          sheetWire: RecoverySheetWire(
            userId: _user,
            sheetVersion: 1,
            blob: _bytes(3, 48),
          ),
        ),
        opener: (code, wire) async {
          opened.add(code.value);
          return true;
        },
        reader: camera.camera.read,
        codeOfQr: (qr) => recoverySheetCodeOfQr(suite, qr),
        restoreProgress: () => Stream.value(
          const RecoveryProgress(
            done: 3,
            total: 10,
            unit: RecoveryUnit.entries,
          ),
        ),
      );
      await pumpRk(
        tester,
        _hosted(camera, RecoverySheetScreen(sheet: sheet)),
        viewport: rkTallViewport,
      );
      await _tapText(tester, 'Scan the square code');
      await camera.read(tester, printedQr);

      expect(opened, [RecoverySheetCode.parse(printedTyped)!.value]);
      expect(find.text('3 of 10 entries restored'), findsOneWidget);
    });

    for (final status in [CameraStatus.unavailable, CameraStatus.denied]) {
      testWidgets('F1-07-313 no camera (${status.name}) keeps its meaning: '
          'each screen renders its stated way out, and no preview is left '
          'behind', (tester) async {
        final umk = _umk(1);
        final camera = _Camera(status: status);

        final s112 = _ScanningRecovery(
          ownKeyQrScanner(
            suite: suite,
            read: camera.camera.read,
            userId: _user,
            relayedOwnUmk: () async => umk,
          ),
        );
        await pumpRk(
          tester,
          _hosted(camera, AskTrustedMembersScreen(recovery: s112)),
          viewport: rkTallViewport,
        );
        await _tapText(tester, 'Scan their screen');
        expect(find.text('Scan the square code'), findsNothing);
        expect(find.text('This phone cannot scan a code yet.'), findsOneWidget);

        final approvals = _approvals(
          candidateQrScanner(suite: suite, read: camera.camera.read),
        );
        await pumpRk(
          tester,
          _hosted(
            camera,
            GuardianApprovalScreen(requestId: 'req-1', approvals: approvals),
          ),
          viewport: rkTallViewport,
        );
        await _tapText(tester, 'Scan their new phone');
        expect(find.textContaining('so it cannot approve'), findsWidgets);

        final sheet = HttpRecoverySheet(
          api: _Api(),
          opener: (_, _) async => true,
          reader: camera.camera.read,
          codeOfQr: (qr) => recoverySheetCodeOfQr(suite, qr),
        );
        await pumpRk(
          tester,
          _hosted(camera, RecoverySheetScreen(sheet: sheet)),
          viewport: rkTallViewport,
        );
        await _tapText(tester, 'Scan the square code');
        expect(find.textContaining('type the code in instead'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ceremony.preview.fake')),
          findsNothing,
        );
        for (final s in camera.scanners) {
          expect(s.disposed, isTrue);
        }
      });
    }

    testWidgets('F1-07-313 a scan asked for where no recovery screen lent the '
        'camera a navigator is unavailable — never a camera over the wrong '
        'screen', (tester) async {
      final camera = _Camera();
      final got = await camera.camera.read<String>((t) => t);
      expect(got, isA<RecoveryQrNoCamera<String>>());
      expect(camera.scanners, isEmpty);
    });

    test('F1-07-313 no screen imports package:mobile_scanner — only the '
        'adapter does (ADR 2026-09-19 ruling 1 🔒)', () {
      final importers = <String>[
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              f.readAsStringSync().contains("import 'package:mobile_scanner"))
            f.path,
      ];
      expect(importers, ['lib/features/ceremony/mobile_scanner_adapter.dart']);
    });
  });

  // -------------------------------------------------------------------------
  group('F1-07-314 a failed dial is not silence (ADR 2026-09-19 ruling 3 🔒, '
      '07 §1 rules 3 and 6 🔒)', () {
    for (final (locale, failed, copy) in [
      (
        const Locale('en'),
        'This phone could not start a call. Dial the number yourself.',
        'Copy the number',
      ),
      (
        const Locale('pa'),
        'ਇਹ ਫ਼ੋਨ ਕਾਲ ਸ਼ੁਰੂ ਨਹੀਂ ਕਰ ਸਕਿਆ। ਨੰਬਰ ਆਪ ਮਿਲਾਓ।',
        'ਨੰਬਰ ਕਾਪੀ ਕਰੋ',
      ),
      (
        const Locale('hi'),
        'यह फ़ोन कॉल शुरू नहीं कर सका। नंबर ख़ुद मिलाएँ।',
        'नंबर कॉपी करें',
      ),
    ]) {
      testWidgets('F1-07-314 [${locale.languageCode}] S11.7 dial → false: '
          'the stored digits went to the dialer unaltered, then the '
          'explanation, the number and Copy the number — at 200 % on '
          '360×800 with nothing overflowing', (tester) async {
        final camera = _Camera();
        final dialer = _Dialer(ok: false);
        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await pumpRk(
          tester,
          _hosted(
            camera,
            GuardianApprovalScreen(
              requestId: 'req-1',
              approvals: _approvals(
                candidateQrScanner(suite: suite, read: camera.camera.read),
                phone: '+91 98765-43210',
              ),
            ),
            dialer: dialer,
          ),
          locale: locale,
          textScale: 2,
          viewport: rkPhone360,
        );
        final call = find.byType(RecoveryCallControl);
        // At 200 % the caution card sits below the fold of a lazy list.
        await tester.scrollUntilVisible(
          call,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: call, matching: find.byType(TextButton)),
        );
        await tester.pumpAndSettle();

        expect(dialer.dialled, ['+91 98765-43210']);
        expect(find.text(failed), findsOneWidget);
        expect(find.text('+91 98765-43210'), findsOneWidget);
        expect(
          find.descendant(
            of: call,
            matching: find.byIcon(Icons.phone_disabled_outlined),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text(copy));
        await tester.tap(find.text(copy));
        await tester.pumpAndSettle();
        expect(copied, ['+91 98765-43210']);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('F1-07-314 S11.2 dial → false on a member row shows the same '
        'way on, and dial → true leaves the control as it was', (tester) async {
      for (final ok in [false, true]) {
        final camera = _Camera();
        final dialer = _Dialer(ok: ok);
        final seam = _ScanningRecovery(
          ownKeyQrScanner(
            suite: suite,
            read: camera.camera.read,
            userId: _user,
            relayedOwnUmk: () async => _umk(1),
          ),
        );
        await pumpRk(
          tester,
          _hosted(
            camera,
            AskTrustedMembersScreen(key: ValueKey(ok), recovery: seam),
            dialer: dialer,
          ),
          viewport: rkTallViewport,
        );
        await _tapText(tester, 'Scan their screen');
        await camera.read(tester, _ownKeyQr(_umk(1)));
        await _tapText(tester, 'Call · 98765 43211');
        expect(dialer.dialled, ['98765 43211']);
        expect(
          find.text(
            'This phone could not start a call. Dial the number yourself.',
          ),
          ok ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Copy the number'),
          ok ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Call · 98765 43211'),
          ok ? findsOneWidget : findsNothing,
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('F1-07-315 Call is a control where a number exists, and absent where '
      'none does (ADR 2026-09-19 ruling 3 🔒)', () {
    testWidgets('F1-07-315 S11.7: Call {name} is an enabled button with a '
        'number, and no call control at all without one', (tester) async {
      for (final phone in ['98765 43210', null]) {
        final camera = _Camera();
        await pumpRk(
          tester,
          _hosted(
            camera,
            GuardianApprovalScreen(
              key: ValueKey(phone),
              requestId: 'req-1',
              approvals: _approvals(
                candidateQrScanner(suite: suite, read: camera.camera.read),
                phone: phone,
              ),
            ),
            dialer: _Dialer(),
          ),
          viewport: rkTallViewport,
        );
        final call = find.byType(RecoveryCallControl);
        if (phone == null) {
          expect(call, findsNothing);
          expect(find.text('Call Asha'), findsNothing);
          expect(find.textContaining('98765'), findsNothing);
        } else {
          expect(call, findsOneWidget);
          final button = tester.widget<TextButton>(
            find.descendant(of: call, matching: find.byType(TextButton)),
          );
          expect(button.onPressed, isNotNull);
          expect(find.text('Call Asha'), findsOneWidget);
        }
      }
    });

    testWidgets('F1-07-315 S11.2: a waiting member with a number gets an '
        'enabled Call link; one with none gets nothing to tap', (tester) async {
      final attempt = GuardianRecoveryAttempt(
        requestId: 'req-1',
        k: 2,
        n: 3,
        state: RecoveryAttemptState.pending,
        approvers: const [
          TrustedApprover(
            memberId: 'm2',
            name: 'Harjit',
            state: TrustedApproverState.waiting,
            phone: '98765 43211',
          ),
          TrustedApprover(
            memberId: 'm3',
            name: 'Balwinder',
            state: TrustedApproverState.waiting,
          ),
        ],
      );
      await pumpRk(
        tester,
        DialerScope(
          dialer: _Dialer(),
          child: AskTrustedMembersScreen(
            recovery: FakeGuardianRecovery(initial: attempt),
          ),
        ),
        viewport: rkTallViewport,
      );
      await _tapText(tester, 'Scan their screen');
      final calls = find.byType(RecoveryCallControl);
      expect(calls, findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Balwinder'),
            matching: find.byType(TrustedApproverRow),
          ),
          matching: find.byType(RecoveryCallControl),
        ),
        findsNothing,
      );
      final button = tester.widget<TextButton>(
        find.descendant(of: calls, matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('F1-07-315 the failure line pairs its colour with an icon and '
        'words — the icon is not the only signal and the words are not tinted '
        'to carry it', (tester) async {
      await pumpRk(
        tester,
        Scaffold(
          body: RecoveryCallControl(
            label: 'Call Asha',
            number: '98765 43210',
            dialer: _Dialer(ok: false),
          ),
        ),
      );
      await tester.tap(find.text('Call Asha'));
      await tester.pumpAndSettle();
      final line = find.text(
        'This phone could not start a call. Dial the number yourself.',
      );
      expect(line, findsOneWidget);
      final row = find.ancestor(of: line, matching: find.byType(Row)).first;
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(Icons.phone_disabled_outlined),
        ),
        findsOneWidget,
      );
      // The explanation sits in the body colour, so nothing rests on a hue.
      final words = tester.widget<RkFitText>(
        find.ancestor(of: line, matching: find.byType(RkFitText)).first,
      );
      expect(
        words.style?.color,
        isNot(RkStatusColors.of(tester.element(line)).warning),
      );
    });
    for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
      testWidgets('F1-07-315 [${locale.languageCode}] S11.2 the Call control '
          'reads one ARB message with the number as its placeholder', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(locale);
        await pumpRk(
          tester,
          DialerScope(
            dialer: _Dialer(),
            child: AskTrustedMembersScreen(
              recovery: FakeGuardianRecovery(
                initial: _ScanningRecovery._attempt(),
              ),
            ),
          ),
          locale: locale,
          viewport: rkTallViewport,
        );
        await _tapText(tester, l10n.recoveryAskScanAction);
        expect(
          find.text(l10n.recoveryAskCallNumber('98765 43211')),
          findsOneWidget,
        );
      });
    }

    test('F1-07-315 no Call label is joined in code (01 §1 rule 7 🔒)', () {
      final path = [
        'lib/features/recovery/widgets/recovery_parts.dart',
        'app/lib/features/recovery/widgets/recovery_parts.dart',
      ].firstWhere((p) => File(p).existsSync());
      final code = File(path).readAsStringSync();
      expect(code, isNot(contains(r'$callLabel')));
      expect(RegExp(r"'[^'\n]*·\s*\$phone").hasMatch(code), isFalse);
    });
  });
}
