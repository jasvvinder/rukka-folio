// The sign-in journey (ADR 2026-10-05c, canvas 1b; 13 §5 F1 / F1b) on the real
// onboarding routes under the real `RukkaFolioApp`: S0.05 → S0.06 → S0.2 on
// either door → the post-code surprises S0.2a / S0.2b / S0.2e → S0.3 or the
// S11.6 fork. A stub stands at S0.3 and at the fork so the test reads where a
// step went without depending on those features' scopes.
//
// Numbers: the reserved test block `+91 99999 xxxxx` (ADR 2026-09-05i §7).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/auth/screens/s0_2_phone_otp_screen.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';
import 'sign_in_harness.dart';

const _forkMarker = 'S11.6 fork (stub)';
const _purposeMarker = 'S0.3 purpose (stub)';

const _known = '9999900011'; // has books under another account
const _unknown = '9999900012'; // no account

/// The onboarding routes with S0.3 and the fork stubbed, from [start].
Future<GoRouter> _pump(
  WidgetTester tester, {
  required FakeAuthClient auth,
  required LocalLedger ledger,
  String start = OnboardingPaths.start,
}) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = buildRouter(
    featureRoutes: [
      for (final r in onboardingRoutes)
        if (r is! GoRoute || r.path != OnboardingPaths.purpose) r,
      GoRoute(
        path: OnboardingPaths.purpose,
        builder: (context, state) => const Scaffold(body: Text(_purposeMarker)),
      ),
      GoRoute(
        path: RkPaths.recoveryFork,
        builder: (context, state) => const Scaffold(body: Text(_forkMarker)),
      ),
    ],
    initialLocation: start,
  );
  addTearDown(router.dispose);
  // A fresh tree per call: a reused app element would keep the last router.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    RukkaFolioApp(
      db: ledger.db,
      sync: FakeSyncClient(),
      auth: auth,
      keys: ledger.keys as FakeKeyStore,
      now: testNow,
      locale: const Locale('en'),
      router: router,
      ledger: ledger,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// adoptSignup fails the way a local write would (not an AuthFailure).
final class _AdoptThrows extends FakeAuthClient {
  @override
  Future<ActivationTicket> adoptSignup(SignupTicket ticket) async =>
      throw StateError('key store unavailable');
}

FakeAuthClient _auth() => FakeAuthClient()..numbersWithBooks.add('+91$_known');

void main() {
  group('ADR 2026-10-05c §1 — S0.06, one front door', () {
    testWidgets(
      'F1-1005c-1 the welcome slides end on S0.06; I\'m new opens S0.2 on the I\'m-new door (signup purpose, Your phone number) and I already use Rukka opens it in its sign-in state (Sign in, Set up instead, SMS); the invite line points to the link and is not a button',
      (tester) async {
        final ledger = await openTestLedger();
        final auth = _auth();
        final router = await _pump(
          tester,
          auth: auth,
          ledger: ledger,
          start: OnboardingPaths.welcome,
        );
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, OnboardingPaths.start);
        expect(find.text('I’m new · set up my books'), findsOneWidget);
        expect(find.text('I already use Rukka · sign in'), findsOneWidget);
        expect(
          find.text('Invited by someone? Open the link they sent you.'),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.text('Invited by someone? Open the link they sent you.'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
          findsNothing,
        );

        await tester.tap(find.text('I’m new · set up my books'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, OnboardingPaths.signIn);
        expect(find.text('Your phone number'), findsOneWidget);
        expect(find.text('Set up instead'), findsNothing);
        await enterNumberAndSend(tester, _unknown);
        expect(auth.requestedDoors, [SignInDoor.newBooks]);

        // Back to S0.06 from the number step, then the other door.
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, OnboardingPaths.start);
        await tester.tap(find.text('I already use Rukka · sign in'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, OnboardingPaths.signIn);
        expect(
          router.state.uri.queryParameters[OnboardingPaths.signInDoorParam],
          OnboardingPaths.signInDoorReturning,
        );
        expect(find.text('Sign in'), findsOneWidget);
        expect(
          find.text(
            'Enter the number you use with Rukka Folio. We’ll send a code by '
            'SMS.',
          ),
          findsOneWidget,
        );
        expect(find.text('Set up instead'), findsOneWidget);
        await enterNumberAndSend(tester, _unknown);
        expect(auth.requestedDoors.last, SignInDoor.signIn);

        // *Set up instead* covers a wrong tap without the slides.
        await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Set up instead'));
        await tester.pumpAndSettle();
        expect(find.text('Your phone number'), findsOneWidget);
        await enterNumberAndSend(tester, _unknown);
        expect(auth.requestedDoors.last, SignInDoor.newBooks);
      },
    );
  });

  group('ADR 2026-10-05c §2 — the number answers only after the code', () {
    testWidgets(
      'F1-1005c-2 before the code every number gets the same screen: a number with books and one without draw identical text on either door',
      (tester) async {
        Future<List<String?>> afterSend(String number, String start) async {
          final ledger = await openTestLedger();
          await _pump(tester, auth: _auth(), ledger: ledger, start: start);
          await enterNumberAndSend(tester, number);
          return [
            for (final t in tester.widgetList<Text>(find.byType(Text)))
              t.data?.replaceAll(RegExp('0001[12]'), '0001x'),
          ];
        }

        for (final start in [
          OnboardingPaths.signIn,
          OnboardingPaths.signInReturning,
        ]) {
          final known = await afterSend(_known, start);
          final unknown = await afterSend(_unknown, start);
          expect(known, unknown, reason: start);
          expect(known, contains('Enter the code'));
        }
      },
    );

    testWidgets(
      'F1-1005c-2 I\'m new + a number with books → S0.2a → Sign in to my books → S0.2b with no second requestOtp; Use a different number keeps the door',
      (tester) async {
        final ledger = await openTestLedger();
        final auth = _auth();
        await _pump(
          tester,
          auth: auth,
          ledger: ledger,
          start: OnboardingPaths.signIn,
        );
        await enterNumberAndSend(tester, _known);
        await tapKeys(tester, '482913');
        expect(find.text('Welcome back'), findsOneWidget);
        expect(find.text('Sign in to my books'), findsOneWidget);
        expect(auth.current, isNot(isA<Active>()));
        await tester.tap(find.text('Sign in to my books'));
        await tester.pumpAndSettle();
        expect(find.text('Is your old phone with you?'), findsOneWidget);
        expect(auth.requestedPhones, ['+91$_known']);
        expect(auth.verifiedCodes, ['482913']);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use a different number'));
        await tester.pumpAndSettle();
        expect(find.text('Your phone number'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-1005c-2 sign in + a number with books → S0.2b straight from the code (13 §5 F1b), no S0.2a, nothing activated',
      (tester) async {
        final ledger = await openTestLedger();
        final auth = _auth();
        await _pump(
          tester,
          auth: auth,
          ledger: ledger,
          start: OnboardingPaths.signInReturning,
        );
        await enterNumberAndSend(tester, _known);
        await tapKeys(tester, '482913');
        expect(find.text('Is your old phone with you?'), findsOneWidget);
        expect(find.text('Sign in to my books'), findsNothing);
        expect(auth.current, isNot(isA<Active>()));
      },
    );

    testWidgets(
      'F1-1005c-2 sign in + no account → S0.2e → Set up new books adopts the signup ticket → activate → S0.3, with no second requestOtp; Try another number goes back on the sign-in door',
      (tester) async {
        final ledger = await openTestLedger();
        final auth = _auth();
        final router = await _pump(
          tester,
          auth: auth,
          ledger: ledger,
          start: OnboardingPaths.signInReturning,
        );
        await enterNumberAndSend(tester, _unknown);
        await tapKeys(tester, '482913');
        expect(find.text('No books on this number'), findsOneWidget);
        expect(
          find.text(
            '+91 99999 00012 hasn’t been used with Rukka Folio before.',
          ),
          findsOneWidget,
        );
        expect(auth.current, isNot(isA<Active>()));
        expect(auth.adoptedTickets, isEmpty, reason: 'only when chosen');

        await tester.tap(find.text('Try another number'));
        await tester.pumpAndSettle();
        expect(find.text('Sign in'), findsOneWidget);
        await enterNumberAndSend(tester, _unknown);
        await tapKeys(tester, '482913');
        await tester.tap(find.text('Set up new books'));
        await tester.pumpAndSettle();
        expect(auth.adoptedTickets, hasLength(1));
        expect(auth.requestedPhones, hasLength(2), reason: 'one per number');
        expect(auth.verifiedCodes, hasLength(2));
        expect(auth.current, isA<Active>());
        expect(find.text('This phone is ready'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, OnboardingPaths.purpose);
        expect(find.text(_purposeMarker), findsOneWidget);
      },
    );

    testWidgets(
      'F1-1005c-2 a signup ticket the server no longer honours (signup_ticket_invalid) restarts from the number with a plain message; nothing is activated',
      (tester) async {
        final ledger = await openTestLedger();
        final auth = _auth();
        await _pump(
          tester,
          auth: auth,
          ledger: ledger,
          start: OnboardingPaths.signInReturning,
        );
        await enterNumberAndSend(tester, _unknown);
        await tapKeys(tester, '482913');
        auth.failNext = const AuthFailure(AuthFailureKind.signupTicketInvalid);
        await tester.tap(find.text('Set up new books'));
        await tester.pumpAndSettle();
        expect(find.text('Sign in'), findsOneWidget);
        expect(
          find.text(
            'That took too long. Enter your number again and we’ll send a new '
            'code.',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(auth.current, isNot(isA<Active>()));
      },
    );

    testWidgets(
      'F1-1005c-2 an adopt that fails for any other reason (a key-store write, no device identity) lands back on S0.2e with a plain error and every way out enabled — no dead end (07 §1 rule 6)',
      (tester) async {
        final ledger = await openTestLedger();
        final auth = _AdoptThrows()..numbersWithBooks.add('+91$_known');
        await _pump(
          tester,
          auth: auth,
          ledger: ledger,
          start: OnboardingPaths.signInReturning,
        );
        await enterNumberAndSend(tester, _unknown);
        await tapKeys(tester, '482913');
        await tester.tap(find.text('Set up new books'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('No books on this number'), findsOneWidget);
        expect(
          find.text('Something didn’t work. Please try again.'),
          findsOneWidget,
        );
        for (final label in ['Set up new books', 'Try another number']) {
          final button = find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          expect(
            tester.widget<ButtonStyleButton>(button.first).onPressed,
            isNotNull,
            reason: label,
          );
        }
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(auth.current, isNot(isA<Active>()));
      },
    );

    testWidgets(
      'F1-1005c-2 I\'m new + no account: the code itself is the signup — straight to activation and S0.3, no S0.2e',
      (tester) async {
        final ledger = await openTestLedger();
        final auth = _auth();
        final router = await _pump(
          tester,
          auth: auth,
          ledger: ledger,
          start: OnboardingPaths.signIn,
        );
        await enterNumberAndSend(tester, _unknown);
        await tapKeys(tester, '482913');
        expect(find.text('No books on this number'), findsNothing);
        expect(find.text('This phone is ready'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, OnboardingPaths.purpose);
      },
    );
  });

  group('ADR 2026-10-05c §3 — S0.2b, is your old phone with you?', () {
    testWidgets(
      'F1-1005c-3 No, it\'s lost or reset opens the S11.6 fork; Yes, it\'s with me is disabled with a visible reason that names the way that works — never a dead end',
      (tester) async {
        final ledger = await openTestLedger();
        final auth = _auth();
        final router = await _pump(
          tester,
          auth: auth,
          ledger: ledger,
          start: OnboardingPaths.signInReturning,
        );
        await enterNumberAndSend(tester, _known);
        await tapKeys(tester, '482913');
        expect(find.text('Is your old phone with you?'), findsOneWidget);

        // Yes: disabled, with its reason on screen and in semantics.
        final yes = find.text('Yes, it’s with me');
        expect(yes, findsOneWidget);
        expect(
          find.text(
            'Approving from your old phone isn’t in this version of the app '
            'yet. Choose “No” below for now — your trusted members or your '
            'recovery sheet can open your books.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<InkWell>(
                find.ancestor(of: yes, matching: find.byType(InkWell)),
              )
              .onTap,
          isNull,
        );
        final handle = tester.ensureSemantics();
        expect(
          tester.getSemantics(
            find.ancestor(of: yes, matching: find.byType(Semantics)).first,
          ),
          matchesSemantics(
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            label: 'Yes, it’s with me. Approve this phone from the old one',
          ),
        );
        handle.dispose();
        await tester.tap(yes, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('Is your old phone with you?'), findsOneWidget);

        // No: the fork.
        await tester.tap(find.text('No, it’s lost or reset'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, RkPaths.recoveryFork);
        expect(find.text(_forkMarker), findsOneWidget);
        expect(auth.current, isNot(isA<Active>()));
      },
    );

    testWidgets(
      'F1-1005c-3 S0.2b, S0.2e and S0.06 resolve in EN, PA and HI and fit at 1.3× and 2× on 360×800 and 375×667',
      (tester) async {
        for (final locale in rkLocales) {
          for (final vp in rkPhones) {
            for (final scale in rkTextScales) {
              final why = '${locale.languageCode} @ $scale on $vp';
              for (final step in [
                PhoneOtpStep.foundYou,
                PhoneOtpStep.noBooks,
                PhoneOtpStep.hasBooks,
                PhoneOtpStep.otp,
              ]) {
                await pumpRk(
                  tester,
                  PhoneOtpScreen(
                    key: UniqueKey(),
                    door: SignInDoor.signIn,
                    debugStep: step,
                    debugPhone: _known,
                  ),
                  locale: locale,
                  textScale: scale,
                  viewport: vp,
                );
                expect(tester.takeException(), isNull, reason: why);
                expectTextFits(tester, reason: '${step.name} $why');
              }
              await pumpRk(
                tester,
                StartScreen(key: UniqueKey()),
                locale: locale,
                textScale: scale,
                viewport: vp,
              );
              expect(tester.takeException(), isNull, reason: why);
              expectTextFits(tester, reason: 'S0.06 $why');
            }
          }
        }
      },
    );
  });
}
