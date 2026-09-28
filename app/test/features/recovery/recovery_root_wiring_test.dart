// F1-07-313 · F1-07-314 — how **production** wires the recovery scans and the
// dialer (ADR 2026-09-19 🔒; review SCAN1 #1).
//
// `scan_and_call_test.dart` mounts every screen through its own host, so it
// stays green if the root stops lending a camera or a dialer. These pin the
// two places that decide what production actually does:
//
//   1. `recoveryRoutes()` — each of S11.2, S11.3 and S11.7 is mounted inside a
//      [RecoveryCameraHost], so a scan opens over the screen that asked. Run
//      for real, through go_router, over the scopes the root installs.
//   2. `bootstrap.dart` — which scanner, reader and dialer each producer is
//      handed. `bootstrap()` needs a keychain, a database and a socket, so its
//      one construction of each is pinned by shape, the way F1-24b-1 pins
//      `candidateKeys:` (`test/shared/sync/recovery_candidate_test.dart`).
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/ceremony/camera_scanner.dart';
import 'package:rukka_folio/features/recovery/recovery_routes.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/sync/recovery_seams.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

const _user = '3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const _newDevice = '7a7b7c7d-1111-4222-8333-944455556666';

Uint8List _bytes(int seed, [int length = 32]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (seed + i * 7) % 256));

final class _Api extends Fake implements RecoveryApi {
  @override
  Future<List<RecoveryAskWire>> asks() async => [
    RecoveryAskWire(
      requestId: 'req-1',
      subjectUserId: _user,
      candidateDevice: _newDevice,
      candidatePubX: _bytes(40),
      shareSetVersion: 1,
      createdAtMs: 1000,
      expiresAtMs: 260200000,
    ),
  ];
}

/// The root's scopes, as `bootstrap()` nests them, over [recoveryRoutes].
Future<List<FakeCeremonyScanner>> _pumpRoute(
  WidgetTester tester,
  CryptoSuite suite,
  String location,
) async {
  final scanners = <FakeCeremonyScanner>[];
  final camera = RecoveryCamera(
    newScanner: () {
      final s = FakeCeremonyScanner();
      scanners.add(s);
      return s;
    },
  );
  final router = GoRouter(
    initialLocation: location,
    routes: recoveryRoutes(onRestored: (_) {}),
  );
  addTearDown(router.dispose);
  rkViewport(tester, rkTallViewport);
  final db = await openTestDb();
  await tester.pumpWidget(
    RkScope(
      db: db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: FakeKeyStore(),
      now: testNow,
      child: GuardianRecoveryScope(
        recovery: FakeGuardianRecovery.waiting(),
        child: RecoverySheetScope(
          sheet: HttpRecoverySheet(
            api: _Api(),
            // A stand-in AEAD: production has none yet (the lane's open
            // item), and without one the seam refuses before the camera opens.
            opener: (_, _) async => true,
            reader: camera.read,
            codeOfQr: (qr) => recoverySheetCodeOfQr(suite, qr),
          ),
          child: GuardianApprovalsScope(
            approvals: HttpGuardianApprovals(
              api: _Api(),
              requesterNameOf: (_) => 'Asha',
              deviceNameOf: (_) => '',
              fingerprintOf: (_) => 'AB12 CD34',
              scanner: candidateQrScanner(suite: suite, read: camera.read),
              resealer: (_) async => Uint8List(0),
            ),
            child: RecoveryCameraScope(
              camera: camera,
              child: MaterialApp.router(
                routerConfig: router,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: rkLocalizationsDelegates,
                theme: rkTheme(Brightness.light),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return scanners;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// `lib/bootstrap.dart` with `//` comments removed, so a comment can neither
/// satisfy nor break a pin.
String _bootstrapCode() {
  for (final path in ['lib/bootstrap.dart', 'app/lib/bootstrap.dart']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    return [
      for (final line in file.readAsStringSync().split('\n'))
        line.contains('//') ? line.substring(0, line.indexOf('//')) : line,
    ].join('\n');
  }
  fail('lib/bootstrap.dart not found from ${Directory.current.path}');
}

/// The one call `name(` … `)` in [code], brackets balanced; fails unless
/// there is exactly one, so the call checked is the call installed.
String _onlyCallOf(String code, String name) {
  final at = RegExp('(?<![A-Za-z0-9_])${RegExp.escape(name)}\\(');
  final hits = at.allMatches(code).toList();
  expect(hits, hasLength(1), reason: 'exactly one $name( in bootstrap');
  final start = hits.single.start;
  var depth = 0;
  for (var i = start + name.length; i < code.length; i++) {
    if (code[i] == '(') depth++;
    if (code[i] == ')' && --depth == 0) return code.substring(start, i + 1);
  }
  fail('unbalanced $name(');
}

/// [code] with every run of whitespace removed, so formatting cannot matter.
String _tight(String code) => code.replaceAll(RegExp(r'\s+'), '');

void main() {
  late CryptoSuite suite;
  setUpAll(() async => suite = await testSuite());

  group(
    'F1-07-313 the routes lend the camera (ADR 2026-09-19 ruling 1 🔒)',
    () {
      for (final (name, location) in [
        ('S11.2', RecoveryPaths.askMembers),
        ('S11.3', RecoveryPaths.sheet),
        ('S11.7', RecoveryPaths.approveOf('req-1')),
      ]) {
        testWidgets('F1-07-313 $name is mounted inside a RecoveryCameraHost', (
          tester,
        ) async {
          await _pumpRoute(tester, suite, location);
          expect(find.byType(RecoveryCameraHost), findsOneWidget);
        });
      }

      testWidgets('F1-07-313 S11.7 through the real route and the root scope: '
          'Scan their new phone opens the scan over the screen', (
        tester,
      ) async {
        final scanners = await _pumpRoute(
          tester,
          suite,
          RecoveryPaths.approveOf('req-1'),
        );
        await _tapText(tester, 'Scan their new phone');
        expect(find.text('Scan the square code'), findsOneWidget);
        expect(scanners, hasLength(1));
      });

      testWidgets('F1-07-313 S11.3 through the real route and the root scope: '
          'the sheet QR path opens the scan over the screen', (tester) async {
        final scanners = await _pumpRoute(tester, suite, RecoveryPaths.sheet);
        await _tapText(tester, 'Scan the square code');
        expect(scanners, hasLength(1));
        expect(
          find.byKey(const ValueKey('ceremony.preview.fake')),
          findsOneWidget,
        );
      });
    },
  );

  group('F1-07-313 · F1-07-314 bootstrap hands each producer its camera and '
      'the root its dialer', () {
    test('F1-07-313 one RecoveryCamera over the real adapter, and the root '
        'scope carries that one', () {
      final root = _bootstrapCode();
      expect(
        _tight(_onlyCallOf(root, 'RecoveryCamera')),
        'RecoveryCamera(newScanner:MobileScannerCeremonyScanner.new,)',
      );
      expect(
        RegExp(r'final\s+recoveryCamera\s*=\s*RecoveryCamera\(').hasMatch(root),
        isTrue,
      );
      final scope = _tight(_onlyCallOf(root, 'RecoveryCameraScope'));
      expect(scope, startsWith('RecoveryCameraScope(camera:recoveryCamera,'));
      expect(scope, contains('child:app'), reason: 'the app is under it');
    });

    test('F1-07-313 S11.7 reads the candidate code through the camera', () {
      final call = _tight(
        _onlyCallOf(_bootstrapCode(), 'HttpGuardianApprovals'),
      );
      expect(
        call,
        contains(
          'scanner:candidateQrScanner(suite:suite,read:recoveryCamera.read)',
        ),
      );
    });

    test('F1-07-313 S11.3 reads the sheet QR through the camera and turns it '
        'into the typed code', () {
      final call = _tight(_onlyCallOf(_bootstrapCode(), 'HttpRecoverySheet'));
      expect(call, contains('reader:recoveryCamera.read'));
      expect(call, contains('codeOfQr:(qr)=>recoverySheetCodeOfQr(suite,qr)'));
    });

    test('F1-07-313 S11.2 has no scanner until a member can show this user’s '
        'key — flip this pin when S11.7 *Show {name}’s key* lands (ADR '
        '2026-09-13c ruling 1 🔒; review SCAN1 #2)', () {
      final root = _bootstrapCode();
      final call = _tight(_onlyCallOf(root, 'HttpGuardianRecovery'));
      expect(call, contains('scanner:null'));
      expect(
        RegExp(r'\bownKeyQrScanner\(').hasMatch(root),
        isFalse,
        reason:
            'nothing draws the code it compares against, so every real scan '
            'would hard-fail and close the attempt',
      );
    });

    test('F1-07-314 the root installs the launchUrl dialer above the app', () {
      final root = _bootstrapCode();
      expect(
        RegExp(r'const\s+dialer\s*=\s*UrlLauncherDialer\(\s*\)').hasMatch(root),
        isTrue,
      );
      final scope = _tight(_onlyCallOf(root, 'DialerScope'));
      expect(scope, startsWith('DialerScope(dialer:dialer,'));
      expect(scope, contains('child:app'), reason: 'the app is under it');
    });

    test('F1-07-313 the recovery routes are mounted once, from this file', () {
      expect(
        RegExp(r'\brecoveryRoutes\(').allMatches(_bootstrapCode()),
        hasLength(1),
      );
    });
  });
}
