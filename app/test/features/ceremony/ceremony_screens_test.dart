@Tags(['F1'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ceremony/camera_scanner.dart';
import 'package:rukka_folio/features/ceremony/ceremony_repository.dart';
import 'package:rukka_folio/features/ceremony/screens/s9_2_show_my_code_screen.dart';
import 'package:rukka_folio/features/ceremony/screens/s9_3_verify_member_screen.dart';
import 'package:rukka_folio/features/ceremony/screens/s9_4_mismatch_screen.dart';
import 'package:rukka_folio/features/ceremony/widgets/code_boxes.dart';
import 'package:rukka_folio/features/ceremony/widgets/qr_view.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

// ---------------------------------------------------------------------------
// Fixtures — synthetic keys only (CLAUDE.md rule 4). These are public halves;
// nothing here is a secret and nothing here is money.
// ---------------------------------------------------------------------------

const _memberId = '3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
const _otherId = '11112222-3333-4444-5555-666677778888';

Uint8List _bytes(int seed, [int length = 32]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (seed + i * 7) % 256));

UmkPublic _umk(int seed) =>
    UmkPublic(x25519: _bytes(seed), ed25519: _bytes(seed + 1));

Uint8List get _nonceBytes => _bytes(9, ceremonyNonceBytes);

InviteNonce _nonce([DateTime? at]) =>
    InviteNonce(bytes: _nonceBytes, issuedAt: at ?? testNow());

/// The invitee's contribution `r_S` and the verifier's `r_V`
/// (ADR 2026-09-13d §1). Fixed here only so a test can recompute the digits
/// both devices derive; on a phone each is drawn from the suite's RNG.
Uint8List get _showerRandom => _bytes(21, sasContributionBytes);

Uint8List get _verifierRandom => _bytes(33, sasContributionBytes);

MyCode _myCode({String? digits = '04871523', DateTime? expiresAt}) => MyCode(
  qrPayload: QrPayload(
    userId: _memberId,
    umk: _umk(1),
    nonce: _nonceBytes,
  ).encode(),
  digits: digits,
  expiresAt: expiresAt ?? testNow().add(const Duration(minutes: 9)),
);

/// A relay whose commitment really does open to [showerRandom] under [umk] —
/// the honest case. Hand it an opening that does not, and the verifier's
/// device must hard-fail before a digit can be typed (ADR 2026-09-13d §2).
FakeVerifierSessionRelay _verifierRelay(
  CryptoSuite suite, {
  UmkPublic? umk,
  Uint8List? showerRandom,
  Uint8List? opening,
  String userId = _memberId,
  DateTime? issuedAt,
}) {
  final rS = showerRandom ?? _showerRandom;
  return FakeVerifierSessionRelay(
    commitmentBytes: sasCommitment(
      suite,
      fp: Fingerprint.of(suite, umk ?? _umk(1)),
      userId: userId,
      showerRandom: rS,
    ),
    openingBytes: opening ?? rS,
    issuedAt: issuedAt ?? testNow(),
  );
}

/// The eight digits the *verifier's* device expects for this session — the
/// number ADR 2026-09-13d §5 🔒 says must never appear on the verifier's
/// screen. Recomputed here from what the relay saw, never read off a widget.
String _expectedCode(
  CryptoSuite suite,
  FakeVerifierSessionRelay relay, {
  UmkPublic? umk,
  Uint8List? showerRandom,
  String userId = _memberId,
}) => sasCode(
  suite,
  fp: Fingerprint.of(suite, umk ?? _umk(1)),
  userId: userId,
  showerRandom: showerRandom ?? _showerRandom,
  verifierRandom: relay.contributions.single,
);

/// Scrolls [label] into view and taps it — at 200 % and in remote mode the
/// buttons of S9.3 sit below the fold, which is allowed (04 §6.2 asks for them
/// on the screen, not above the fold).
Future<void> tapText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Asserts [code] is nowhere a person or a screen reader could reach it:
/// no rendered text, no semantics label, no field value, no code box
/// (ADR 2026-09-13d §5 🔒 — a verifier's device that shows the number it wants
/// to hear turns the ceremony into a prompt).
void expectCodeNotOnScreen(
  WidgetTester tester,
  String code, {
  required String reason,
}) {
  expect(find.textContaining(code), findsNothing, reason: reason);
  for (final boxes in tester.widgetList<RkCodeBoxes>(
    find.byType(RkCodeBoxes),
  )) {
    expect(boxes.digits, isNot(contains(code)), reason: reason);
    expect(boxes.semanticsLabel ?? '', isNot(contains(code)), reason: reason);
  }
  for (final node in tester.widgetList<Semantics>(find.byType(Semantics))) {
    expect(node.properties.label ?? '', isNot(contains(code)), reason: reason);
    expect(node.properties.value ?? '', isNot(contains(code)), reason: reason);
  }
  for (final field in tester.widgetList<EditableText>(
    find.byType(EditableText),
  )) {
    expect(field.controller.text, isNot(contains(code)), reason: reason);
  }
}

/// The eight boxes, as widgets — one `_Box` per character position.
Finder get _codeBoxes => find.byType(RkCodeBoxes);

/// Every affordance whose presence on these screens would be a spec breach:
/// a share or copy on the code (04 §6.4 🔒), a retry or override on S9.4
/// (04 §6.3 🔒).
void expectNoShareAffordance(WidgetTester tester) {
  for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
    expect(
      icon.icon,
      isNot(
        anyOf(
          Icons.share,
          Icons.share_outlined,
          Icons.ios_share,
          Icons.copy,
          Icons.copy_all,
          Icons.content_copy,
          Icons.content_copy_outlined,
        ),
      ),
      reason: '04 §6.4 🔒: the code may never be shared or copied',
    );
  }
  expect(find.textContaining('Share'), findsNothing);
  expect(find.textContaining('Copy'), findsNothing);
}

void main() {
  // -------------------------------------------------------------------------
  group('S9.2 Show my code (13 §3.2, 07 §12 🔒, 04 §6.1, §6.2)', () {
    testWidgets(
      'F1-07-26 S9.2 ready: a huge QR, the eight character boxes beneath it, '
      'a visible expiry countdown — and no share or copy anywhere (04 §6.4 🔒)',
      (tester) async {
        final repo = FakeShowMyCodeRepository(code: _myCode());
        await pumpRk(
          tester,
          ShowMyCodeScreen(
            repository: repo,
            now: testNow,
            encode: (_) => const FakeQrModules(),
          ),
          viewport: rkPhone360,
        );

        expect(find.text('Show my code'), findsOneWidget);
        expect(find.byType(RkQrView), findsOneWidget);

        // Eight separate boxes, one character each — not one text run.
        expect(_codeBoxes, findsOneWidget);
        for (final digit in '04871523'.split('')) {
          expect(find.text(digit), findsWidgets);
        }
        expect(find.text('04871523'), findsNothing);

        // The countdown is visible, not implied.
        expect(find.textContaining('Expires in'), findsOneWidget);
        expect(find.textContaining('9 min'), findsOneWidget);

        // The channel rule is stated, and the affordance it forbids is absent.
        expect(
          find.textContaining('Never send this code in a message'),
          findsOneWidget,
        );
        expectNoShareAffordance(tester);
      },
    );

    testWidgets(
      'F1-07-26 S9.2 the QR and the digits are derived by core_crypto — the '
      'square from the invite nonce, the digits from both devices’ randomness '
      '(04 §6.1 🔒 as amended, ADR 2026-09-13d §1)',
      (tester) async {
        final suite = await testSuite();
        final umk = _umk(1);
        final nonce = _nonce();
        final relay = FakeShowerSessionRelay(
          issuedAt: testNow(),
          verifier: _verifierRandom,
        );
        final repository = CryptoShowMyCodeRepository(
          suite: suite,
          userId: _memberId,
          umk: umk,
          nonces: ({bool fresh = false}) async => nonce,
          relay: relay,
          verifierName: 'Sunita',
        );

        String? encoded;
        await pumpRk(
          tester,
          ShowMyCodeScreen(
            repository: repository,
            now: testNow,
            encode: (payload) {
              encoded = payload;
              return const FakeQrModules();
            },
          ),
          viewport: rkPhone360,
        );

        // The commitment went out; the opening followed it, never the other
        // way round — that ordering is the whole repair (ADR 2026-09-13d §1).
        expect(relay.commitments, hasLength(1));
        expect(relay.openings, hasLength(1));
        final rS = relay.openings.single;
        expect(
          relay.commitments.single,
          sasCommitment(
            suite,
            fp: Fingerprint.of(suite, umk),
            userId: _memberId,
            showerRandom: rS,
          ),
          reason: 'the relayed commitment binds this device’s key, id and r_S',
        );

        // The digits are the SAS over both contributions — never the retired
        // BLAKE2b(FP ‖ nonce ‖ "verify-v1"), which the server could compute.
        expect(
          tester.widget<RkCodeBoxes>(_codeBoxes).digits,
          sasCode(
            suite,
            fp: Fingerprint.of(suite, umk),
            userId: _memberId,
            showerRandom: rS,
            verifierRandom: _verifierRandom,
          ),
        );

        // The invite nonce lives on in the QR payload, and nowhere else.
        final decoded = QrPayload.decode(encoded!);
        expect(decoded.userId, _memberId);
        expect(decoded.nonce, nonce.bytes);
        expect(decoded.umk.ed25519, umk.ed25519);
      },
    );

    testWidgets(
      'F1-07-26 S9.2 loading shows the skeleton, an error shows the retry, and '
      'offline is a quiet chip that never blocks (13 §4.3, 07 §1 rule 7)',
      (tester) async {
        final failing = FakeShowMyCodeRepository(
          code: _myCode(),
          failure: const CeremonyFailure(),
        );
        await pumpRk(
          tester,
          ShowMyCodeScreen(
            repository: failing,
            now: testNow,
            encode: (_) => const FakeQrModules(),
          ),
          viewport: rkPhone360,
        );
        expect(find.text('Couldn’t get your code.'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        failing.failure = null;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.byType(RkQrView), findsOneWidget);

        // Offline: the code still shows, with a chip beside it.
        await pumpRk(
          tester,
          ShowMyCodeScreen(
            repository: FakeShowMyCodeRepository(code: _myCode()),
            now: testNow,
            offline: true,
            encode: (_) => const FakeQrModules(),
          ),
          viewport: rkPhone360,
        );
        expect(find.byType(RkQrView), findsOneWidget);
        expect(
          find.textContaining('this code still works face to face'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-07-26 S9.2 past the nonce’s ten minutes the code greys out and the '
      'one next step is Get a new code — a fresh nonce, never a re-used one '
      '(04 §6.3)',
      (tester) async {
        final repo = FakeShowMyCodeRepository(
          code: _myCode(
            expiresAt: testNow().subtract(const Duration(hours: 1)),
          ),
          next: _myCode(digits: '99887766'),
        );
        await pumpRk(
          tester,
          ShowMyCodeScreen(
            repository: repo,
            now: testNow,
            encode: (_) => const FakeQrModules(),
          ),
          viewport: rkPhone360,
        );
        expect(find.text('This code has expired.'), findsOneWidget);
        expect(tester.widget<RkCodeBoxes>(_codeBoxes).muted, isTrue);

        await tester.ensureVisible(find.text('Get a new code'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Get a new code'));
        await tester.pumpAndSettle();
        expect(repo.regenerations, 1);
      },
    );

    testWidgets(
      'F1-13d-1 S9.2 the square is up at once but the eight boxes stand empty '
      'and say who they are waiting for — the digits do not exist until the '
      'verifier’s contribution arrives (ADR 2026-09-13d §5 🔒)',
      (tester) async {
        final repository = FakeShowMyCodeRepository(
          code: _myCode(),
          waitForVerifier: true,
        );
        await pumpRk(
          tester,
          ShowMyCodeScreen(
            repository: repository,
            now: testNow,
            encode: (_) => const FakeQrModules(),
          ),
          viewport: rkPhone360,
        );

        // The QR never waits for anybody: it is the fast path and it is drawn
        // from the first frame (ADR 2026-09-13d §5).
        expect(find.byType(RkQrView), findsOneWidget);

        // The boxes are there, at full size, and empty.
        expect(tester.widget<RkCodeBoxes>(_codeBoxes).digits, isEmpty);
        expect(find.text('04871523'), findsNothing);
        expect(
          find.text('Waiting for Sunita to enter the code'),
          findsOneWidget,
        );
        expect(
          find.textContaining('The digits appear the moment they begin'),
          findsOneWidget,
        );
        // A screen reader hears why the boxes are empty, not eight blanks.
        expect(
          tester.widget<RkCodeBoxes>(_codeBoxes).semanticsLabel,
          contains('not ready yet'),
        );
        // The countdown is already running: the ten minutes belong to the
        // commitment, which is on the server (04 §6.3, ADR 2026-09-13d §3).
        expect(find.textContaining('Expires in'), findsOneWidget);
        expectNoShareAffordance(tester);

        // r_V lands; this device opens its commitment and the code exists.
        repository.arrive();
        await tester.pumpAndSettle();

        expect(tester.widget<RkCodeBoxes>(_codeBoxes).digits, '04871523');
        expect(find.text('Your 8-digit code'), findsOneWidget);
        expect(find.text('Waiting for Sunita to enter the code'), findsNothing);
        expect(find.byType(RkQrView), findsOneWidget);
        expectNoShareAffordance(tester);
      },
    );

    testWidgets(
      'F1-13d-1 S9.2 Regenerate opens a fresh session, and a stale r_V from '
      'the session it replaced is never shown (ADR 2026-09-13d §2)',
      (tester) async {
        final repository = FakeShowMyCodeRepository(
          code: _myCode(
            expiresAt: testNow().subtract(const Duration(hours: 1)),
          ),
          next: _myCode(digits: '99887766'),
          waitForVerifier: true,
        );
        await pumpRk(
          tester,
          ShowMyCodeScreen(
            repository: repository,
            now: testNow,
            encode: (_) => const FakeQrModules(),
          ),
          viewport: rkPhone360,
        );
        expect(find.text('This code has expired.'), findsOneWidget);

        await tester.ensureVisible(find.text('Get a new code'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Get a new code'));
        await tester.pumpAndSettle();

        // The new session is waiting on its own verifier, not on the old one.
        expect(repository.regenerations, 1);
        expect(tester.widget<RkCodeBoxes>(_codeBoxes).digits, isEmpty);
        expect(
          find.text('Waiting for Sunita to enter the code'),
          findsOneWidget,
        );

        repository.arrive();
        await tester.pumpAndSettle();
        expect(tester.widget<RkCodeBoxes>(_codeBoxes).digits, '99887766');
      },
    );
  });

  // -------------------------------------------------------------------------
  group('S9.3 Verify member (13 §3.2, 07 §12 🔒, 04 §6.2–§6.4)', () {
    testWidgets(
      'F1-07-26 S9.3 opens on the camera and Enter code instead is on the '
      'screen from the first frame — the camera-free path is equal, not a '
      'fallback (04 §6.2 🔒, design-system §3.1 rule 7 🔒)',
      (tester) async {
        final scanner = FakeCeremonyScanner();
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: FakeVerifyMemberRepository(),
            scanner: scanner,
          ),
          viewport: rkPhone360,
        );
        expect(find.text('Verify member'), findsOneWidget);
        expect(
          find.text('Point the camera at the square on their phone.'),
          findsOneWidget,
        );
        expect(find.text('Enter code instead'), findsOneWidget);
        expect(scanner.starts, 1);

        await tester.tap(find.text('Enter code instead'));
        await tester.pumpAndSettle();
        expect(find.byType(RkCodeField), findsOneWidget);
        expect(find.text('Their 8-digit code'), findsWidgets);
      },
    );

    testWidgets(
      'F1-07-26 S9.3 a missing or refused camera lands on the code path with '
      'the reason stated — never a wall (07 §1 rule 6)',
      (tester) async {
        for (final (status, line) in [
          (
            CameraStatus.unavailable,
            'The camera isn’t available on this phone',
          ),
          (CameraStatus.denied, 'This app hasn’t been given the camera'),
        ]) {
          await pumpRk(
            tester,
            VerifyMemberScreen(
              // Keyed: a second pump of the same widget type reuses the
              // element, and initState — where the camera is asked — would
              // never run again.
              key: ValueKey(status),
              repository: FakeVerifyMemberRepository(),
              scanner: FakeCeremonyScanner(status: status),
            ),
            viewport: rkPhone360,
          );
          expect(find.textContaining(line), findsOneWidget);
          expect(find.byType(RkCodeField), findsOneWidget);
          expect(find.text('Check code'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'F1-07-26 S9.3 a matching QR verifies through core_crypto and the '
      'ceremony writes the permanent verification entry (04 §6.3, §6.4)',
      (tester) async {
        final suite = await testSuite();
        final umk = _umk(1);
        final log = RecordingCeremonyEventLog();
        final sink = RecordingVerifiedMemberSink();
        final repository = CryptoVerifyMemberRepository(
          keys: sink,
          suite: suite,
          relayedUmk: umk,
          relayedUserId: _memberId,
          relay: _verifierRelay(suite, umk: umk),
          memberName: 'Sunita',
          now: testNow,
          log: log,
        );
        final scanner = FakeCeremonyScanner();
        var verified = 0;
        var mismatched = 0;
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: repository,
            scanner: scanner,
            onVerified: () => verified++,
            onMismatch: () => mismatched++,
          ),
          viewport: rkPhone360,
        );

        scanner.emit(
          QrPayload(userId: _memberId, umk: umk, nonce: _nonceBytes).encode(),
        );
        await tester.pumpAndSettle();

        expect(find.text('Verified'), findsOneWidget);
        expect(
          find.text('Sunita is confirmed. Their shared books open now.'),
          findsOneWidget,
        );
        expect(mismatched, 0);
        expect(repository.mismatchesLogged, 0);
        expect(log.verifications, [('Sunita', VerificationMethod.qrInPerson)]);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(verified, 1);
      },
    );

    testWidgets(
      'F1-07-26 S9.3 a QR whose keys differ is a hard fail: the screen hands '
      'off to S9.4, the security event is already written, and nothing on the '
      'way offers a retry (04 §6.3 🔒)',
      (tester) async {
        final suite = await testSuite();
        final log = RecordingCeremonyEventLog();
        final sink = RecordingVerifiedMemberSink();
        final repository = CryptoVerifyMemberRepository(
          keys: sink,
          suite: suite,
          relayedUmk: _umk(1),
          relayedUserId: _memberId,
          relay: _verifierRelay(suite),
          memberName: 'Sunita',
          now: testNow,
          log: log,
        );
        final scanner = FakeCeremonyScanner();
        var mismatched = 0;
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: repository,
            scanner: scanner,
            onMismatch: () => mismatched++,
          ),
          viewport: rkPhone360,
        );

        // Someone else's keys under the right nonce — the attack 04 §6 stops.
        scanner.emit(
          QrPayload(
            userId: _otherId,
            umk: _umk(50),
            nonce: _nonceBytes,
          ).encode(),
        );
        await tester.pumpAndSettle();

        expect(mismatched, 1);
        expect(repository.mismatchesLogged, 1);
        expect(log.mismatches, ['Sunita']);
        expect(find.text('Verified'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-26 S9.3 a stranger’s QR is not a mismatch: nothing is compared, '
      'nothing is logged, the camera keeps looking (04 §6.3)',
      (tester) async {
        final repository = FakeVerifyMemberRepository(
          onScanned: (_) async => throw const NotACeremonyCode(),
        );
        final scanner = FakeCeremonyScanner();
        var mismatched = 0;
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: repository,
            scanner: scanner,
            onMismatch: () => mismatched++,
          ),
          viewport: rkPhone360,
        );

        scanner.emit('upi://pay?pa=someshop@bank');
        await tester.pumpAndSettle();

        expect(mismatched, 0);
        expect(repository.mismatchesLogged, 0);
        expect(
          find.textContaining('isn’t a verification square'),
          findsOneWidget,
        );
        expect(find.text('Enter code instead'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-26 S9.3 the code path spends the nonce’s three attempts and then '
      'says so, with the one next step on the invitee’s phone (04 §6.3)',
      (tester) async {
        var call = 0;
        final repository = FakeVerifyMemberRepository(
          onTyped: (_) async {
            call++;
            return switch (call) {
              1 => const CodeWrong(attemptsLeft: 2),
              2 => const CodeWrong(attemptsLeft: 1),
              _ => const CodeExhausted(),
            };
          },
        );
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: repository,
            scanner: FakeCeremonyScanner(status: CameraStatus.unavailable),
          ),
          viewport: rkPhone360,
        );

        Future<void> type(String digits) async {
          await tester.enterText(find.byType(TextField), digits);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Check code'));
          await tester.pumpAndSettle();
        }

        await type('11111111');
        expect(find.textContaining('2 tries left.'), findsOneWidget);
        await type('22222222');
        expect(find.textContaining('1 try left.'), findsOneWidget);
        await type('33333333');
        expect(find.textContaining('That code is used up.'), findsOneWidget);
        expect(repository.typed, ['11111111', '22222222', '33333333']);
      },
    );

    testWidgets(
      'F1-07-26 S9.3 Check code stays disabled until all eight digits are in, '
      'and an expired nonce says to get a new one (04 §6.3)',
      (tester) async {
        final repository = FakeVerifyMemberRepository(
          onTyped: (_) async => const CodeExpired(),
        );
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: repository,
            scanner: FakeCeremonyScanner(status: CameraStatus.unavailable),
          ),
          viewport: rkPhone360,
        );

        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await tester.enterText(find.byType(TextField), '1234');
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );

        await tester.enterText(find.byType(TextField), '12345678');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Check code'));
        await tester.pumpAndSettle();
        expect(find.textContaining('That code has expired.'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-26 S9.3 remote mode says "Call them and ask them to read the code '
      'aloud" and carries no share button, by design (04 §6.4 🔒, 07 §12 🔒)',
      (tester) async {
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: FakeVerifyMemberRepository(mode: CeremonyMode.remote),
            scanner: FakeCeremonyScanner(),
          ),
          viewport: rkPhone360,
        );
        expect(
          find.text('Call them and ask them to read the code aloud.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('A voice or video call only.'),
          findsOneWidget,
        );
        expectNoShareAffordance(tester);
      },
    );

    testWidgets(
      'F1-07-26 S9.3 a member who may not verify is told who can, not shown a '
      'blank screen (13 §2.3.1, 07 §1 rule 6)',
      (tester) async {
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: FakeVerifyMemberRepository(canVerify: false),
            scanner: FakeCeremonyScanner(),
          ),
          viewport: rkPhone360,
        );
        expect(
          find.textContaining('Only an active, verified member can verify'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-13d-2 S9.3 Enter code instead arms the SAS session — and the digits '
      'this device expects are nowhere in its widget tree, before typing, '
      'after a wrong try, and in the notice it shows (ADR 2026-09-13d §5 🔒)',
      (tester) async {
        final suite = await testSuite();
        final umk = _umk(1);
        final relay = _verifierRelay(suite, umk: umk);
        final log = RecordingCeremonyEventLog();
        final sink = RecordingVerifiedMemberSink();
        final repository = CryptoVerifyMemberRepository(
          keys: sink,
          suite: suite,
          relayedUmk: umk,
          relayedUserId: _memberId,
          relay: relay,
          memberName: 'Sunita',
          now: testNow,
          log: log,
          mode: CeremonyMode.remote,
        );
        var mismatched = 0;
        var verified = 0;
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: repository,
            scanner: FakeCeremonyScanner(),
            onMismatch: () => mismatched++,
            onVerified: () => verified++,
          ),
          viewport: rkPhone360,
        );

        await tapText(tester, 'Enter code instead');

        // Armed: this device drew exactly one contribution, and only after it
        // held the relayed key and the relayed commitment.
        expect(relay.contributions, hasLength(1));
        expect(find.byType(RkCodeField), findsOneWidget);
        expect(mismatched, 0);
        expect(
          find.textContaining('This phone never shows their code'),
          findsOneWidget,
        );

        final expected = _expectedCode(suite, relay, umk: umk);
        expectCodeNotOnScreen(
          tester,
          expected,
          reason:
              'ADR 2026-09-13d §5 🔒: the verifier’s device never shows '
              'the code it expects — typing it is the check',
        );

        // A wrong try must not coax the number out of the screen either.
        final wrong = expected == '00000000' ? '11111111' : '00000000';
        await tester.enterText(find.byType(TextField), wrong);
        await tester.pumpAndSettle();
        await tapText(tester, 'Check code');
        expect(find.textContaining('2 tries left.'), findsOneWidget);
        expectCodeNotOnScreen(
          tester,
          expected,
          reason: 'a wrong attempt must not reveal the expected code',
        );

        // Going back to the camera and returning re-uses the session: one
        // session, one contribution (ADR 2026-09-13d §2).
        await tapText(tester, 'Use the camera instead');
        await tapText(tester, 'Enter code instead');
        expect(relay.contributions, hasLength(1));

        // The real code, read aloud by the person, verifies.
        await tester.enterText(find.byType(TextField), expected);
        await tester.pumpAndSettle();
        await tapText(tester, 'Check code');
        expect(find.text('Verified'), findsOneWidget);
        expect(log.verifications, [('Sunita', VerificationMethod.codeRemote)]);
        expect(repository.mismatchesLogged, 0);
        expect(mismatched, 0);
        expectNoShareAffordance(tester);

        await tapText(tester, 'Done');
        expect(verified, 1);
      },
    );

    testWidgets(
      'F1-13d-2 S9.3 an opening that does not open the relayed commitment is a '
      'relay that lied: hard fail to S9.4 with the event written, before a '
      'single digit can be typed (ADR 2026-09-13d §2, 04 §6.3 🔒)',
      (tester) async {
        final suite = await testSuite();
        final log = RecordingCeremonyEventLog();
        final sink = RecordingVerifiedMemberSink();
        final repository = CryptoVerifyMemberRepository(
          keys: sink,
          suite: suite,
          relayedUmk: _umk(1),
          relayedUserId: _memberId,
          // The commitment was made over one r_S; the relay hands back another.
          relay: _verifierRelay(
            suite,
            opening: _bytes(77, sasContributionBytes),
          ),
          memberName: 'Sunita',
          now: testNow,
          log: log,
        );
        var mismatched = 0;
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: repository,
            scanner: FakeCeremonyScanner(status: CameraStatus.unavailable),
            onMismatch: () => mismatched++,
          ),
          viewport: rkPhone360,
        );

        expect(
          mismatched,
          1,
          reason:
              'handed off to S9.4, exactly as a QR '
              'mismatch is',
        );
        expect(repository.mismatchesLogged, 1);
        expect(log.mismatches, ['Sunita']);
        // Nothing was offered to type: there is no session to type against.
        expect(find.byType(RkCodeField), findsNothing);
        expect(find.text('Check code'), findsNothing);
        expect(find.text('Verified'), findsNothing);
      },
    );

    testWidgets(
      'F1-13d-2 S9.3 while the session is being armed the screen says so and '
      'offers the camera back — never an empty box to type into (13 §4.3)',
      (tester) async {
        final gate = Completer<CodePathArming>();
        final repository = FakeVerifyMemberRepository(onArm: () => gate.future);
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: repository,
            scanner: FakeCeremonyScanner(),
          ),
          viewport: rkPhone360,
        );

        await tester.ensureVisible(find.text('Enter code instead'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Enter code instead'));
        await tester.pump();

        expect(find.text('Getting ready for their code.'), findsOneWidget);
        expect(find.byType(RkCodeField), findsNothing);
        expect(find.text('Use the camera instead'), findsOneWidget);

        gate.complete(CodePathArming.armed);
        await tester.pumpAndSettle();
        expect(find.byType(RkCodeField), findsOneWidget);
        expect(repository.arms, 1);
      },
    );

    testWidgets(
      'F1-13d-2 S9.3 a relay this device cannot reach is a retry, not a '
      'mismatch: nothing is logged and Try again arms a clean session '
      '(04 §6.3)',
      (tester) async {
        var calls = 0;
        final repository = FakeVerifyMemberRepository(
          onArm: () async {
            calls++;
            if (calls == 1) throw const CeremonyFailure(offline: true);
            return CodePathArming.armed;
          },
        );
        var mismatched = 0;
        await pumpRk(
          tester,
          VerifyMemberScreen(
            repository: repository,
            scanner: FakeCeremonyScanner(status: CameraStatus.unavailable),
            onMismatch: () => mismatched++,
          ),
          viewport: rkPhone360,
        );

        expect(
          find.textContaining('checking needs a connection'),
          findsOneWidget,
        );
        expect(mismatched, 0);
        expect(repository.mismatchesLogged, 0);

        await tapText(tester, 'Try again');
        expect(find.byType(RkCodeField), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('S9.4 Verification mismatch (13 §3.2, 07 §12 🔒, 04 §6.3 🔒)', () {
    testWidgets(
      'F1-07-26 S9.4 is a full red screen with Contact support, the logged '
      'line, an icon and words beside the colour — and no override, no retry, '
      'no "verify anyway" (04 §6.3 🔒)',
      (tester) async {
        var support = 0;
        await pumpRk(
          tester,
          VerificationMismatchScreen(onContactSupport: () => support++),
          viewport: rkPhone360,
        );

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        final context = tester.element(find.byType(VerificationMismatchScreen));
        expect(scaffold.backgroundColor, RkStatusColors.of(context).danger);

        expect(find.text('Do not proceed.'), findsOneWidget);
        expect(find.textContaining('does not match the keys'), findsOneWidget);
        expect(
          find.textContaining('written to your security log'),
          findsOneWidget,
        );
        expect(find.text('Contact support'), findsOneWidget);

        // Canvas 4's three added lines (S9.4 "Mismatch · no way past").
        expect(find.textContaining('went to the wrong number'), findsOneWidget);
        expect(
          find.text('Nothing has been shared. No access was given.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Do not try again on this phone'),
          findsOneWidget,
        );

        // Colour never alone (07 §1 rule 3): the warning icon is present.
        expect(find.byIcon(Icons.gpp_bad_outlined), findsOneWidget);

        // The absences are the screen.
        expect(find.text('Try again'), findsNothing);
        expect(find.textContaining('anyway'), findsNothing);
        expect(find.textContaining('Verify'), findsNothing);
        expect(find.textContaining('sure'), findsNothing);
        expectNoShareAffordance(tester);

        await tester.ensureVisible(find.text('Contact support'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Contact support'));
        expect(support, 1);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('Layout — 360×800 and 375×667, EN/PA/HI, 130 % and 200 %', () {
    for (final locale in rkLocales) {
      for (final scale in rkTextScales) {
        for (final viewport in rkPhones) {
          final where =
              '${locale.languageCode} @ $scale on '
              '${viewport.width.toInt()}×${viewport.height.toInt()}';

          testWidgets(
            'F1-07-26 S9.2 the QR, the eight code boxes and the countdown fit '
            '— $where',
            (tester) async {
              await pumpRk(
                tester,
                ShowMyCodeScreen(
                  repository: FakeShowMyCodeRepository(code: _myCode()),
                  now: testNow,
                  encode: (_) => const FakeQrModules(),
                ),
                locale: locale,
                textScale: scale,
                viewport: viewport,
              );
              expect(tester.takeException(), isNull);
              expect(_codeBoxes, findsOneWidget);
              expectTextFits(tester, reason: 'S9.2 $where');
            },
          );

          testWidgets(
            'F1-13d-1 S9.2 the waiting state fits too — the empty boxes, the '
            'line naming who we are waiting for and the countdown — $where',
            (tester) async {
              await pumpRk(
                tester,
                ShowMyCodeScreen(
                  repository: FakeShowMyCodeRepository(
                    code: _myCode(),
                    waitForVerifier: true,
                  ),
                  now: testNow,
                  encode: (_) => const FakeQrModules(),
                ),
                locale: locale,
                textScale: scale,
                viewport: viewport,
              );
              expect(tester.takeException(), isNull);
              expect(tester.widget<RkCodeBoxes>(_codeBoxes).digits, isEmpty);
              expectTextFits(tester, reason: 'S9.2 waiting $where');
            },
          );

          testWidgets(
            'F1-07-26 S9.3 the camera path and the code path both fit — $where',
            (tester) async {
              await pumpRk(
                tester,
                VerifyMemberScreen(
                  repository: FakeVerifyMemberRepository(
                    mode: CeremonyMode.remote,
                  ),
                  scanner: FakeCeremonyScanner(),
                ),
                locale: locale,
                textScale: scale,
                viewport: viewport,
              );
              expect(tester.takeException(), isNull);
              expectTextFits(tester, reason: 'S9.3 camera $where');

              // At 200 % everything scrolls; *Enter code instead* is on the
              // screen, which is what 04 §6.2 🔒 asks — not above the fold.
              await tester.ensureVisible(find.byType(OutlinedButton));
              await tester.pumpAndSettle();
              await tester.tap(find.byType(OutlinedButton));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(find.byType(RkCodeField), findsOneWidget);
              expectTextFits(tester, reason: 'S9.3 code $where');
            },
          );

          testWidgets('F1-07-26 S9.4 the red screen fits — $where', (
            tester,
          ) async {
            await pumpRk(
              tester,
              const VerificationMismatchScreen(),
              locale: locale,
              textScale: scale,
              viewport: viewport,
            );
            expect(tester.takeException(), isNull);
            expectTextFits(tester, reason: 'S9.4 $where');
          });
        }
      }
    }
  });
}
