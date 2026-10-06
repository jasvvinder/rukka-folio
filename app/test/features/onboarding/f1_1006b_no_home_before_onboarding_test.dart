// ADR 2026-10-06b 🔒 — the app never lands on Home until sign-up (13 §5 F1)
// or sign-in (F1b) has handed over to it.
//
// Every test here pumps the production composition — `RukkaFolioApp` with the
// real `onboardingRoutes` + `authRoutes` + `recoveryRoutes`, the gate built by
// the same `OnboardingGate.over` `bootstrap` calls (over a real `PinVault`),
// and an `AppSettings` over a memory store — and starts from the router's own
// default location (Home). Remove the redirect and F1-1006b-1/-2 land on Home;
// remove the `PopScope`s and F1-1006b-3's Back closes the app; drop the gate
// from `bootstrap.dart` and the root pin in F1-1006b-1 fails.
@Tags(['F1'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/auth_routes.dart';
import 'package:rukka_folio/features/devices/pin_vault.dart';
import 'package:rukka_folio/features/home/home_paths.dart';
import 'package:rukka_folio/features/lock/widgets/pin_pad.dart' show PinKeypad;
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_1_language_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6g_trust_name_screen.dart'
    show TrustType;
import 'package:rukka_folio/features/recovery/recovery_routes.dart'
    show NothingWorkedYetScreen, RecoveryForkScreen, recoveryRoutes;
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

import '../auth/sign_in_harness.dart' show enterNumberAndSend, tapKeys;

const _session = Active(
  AuthSession(userId: 'u-1', deviceId: 'd-1'),
  deviceCertified: true,
);

/// An auth client whose code check and device activation wait for the test,
/// so S0.2's verifying and activating states can be held on screen.
final class _StallingAuth extends FakeAuthClient {
  _StallingAuth({this.stallCheck = false, this.stallActivate = false});

  final bool stallCheck;
  final bool stallActivate;
  final release = Completer<void>();

  @override
  Future<OtpOutcome> checkOtp(String code) async {
    if (stallCheck) await release.future;
    return super.checkOtp(code);
  }

  @override
  Future<AuthSession> activateDevice(ActivationTicket ticket) async {
    if (stallActivate) await release.future;
    return super.activateDevice(ticket);
  }
}

/// An entitlement reading that waits for the test once [stall] is set — the
/// S12.5 check a committing step makes before `createBook`, so the step can
/// be held mid-creation.
final class _StallingEntitlement implements EntitlementSource {
  bool stall = false;
  final release = Completer<void>();

  @override
  Future<Entitlement> read() async {
    if (stall) await release.future;
    return Entitlement.untokened();
  }
}

/// Taps [digits] on S0.2's keypad without settling — a step held mid-request
/// keeps its progress animation running.
Future<void> tapKeysNoSettle(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(
      find.descendant(of: find.byType(PinKeypad), matching: find.text(d)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 100));
}

const _number = '9999900012';
const _withBooks = '9999900011';

/// A fresh install's settings, or one whose store already says onboarded.
Future<AppSettings> settingsOver(MemoryPrefs prefs) async {
  final s = AppSettings(prefs: prefs);
  await s.load();
  return s;
}

/// The gate of the last [pumpGated].
late OnboardingGate lastGate;

/// Pumps the app as `bootstrap` composes it, from the router's default
/// location, and returns the router. [pin] sets a real MPIN in the vault the
/// gate reads (S0.8's result), exactly as `bootstrap` wires it.
Future<GoRouter> pumpGated(
  WidgetTester tester, {
  required LocalLedger ledger,
  required AppSettings settings,
  bool account = true,
  bool pin = false,
  FakeAuthClient? auth,
  EntitlementSource? entitlement,
}) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client =
      auth ?? FakeAuthClient(initial: account ? _session : const SignedOut());
  final vault = PinVault(
    keys: FakeKeyStore(),
    suite: await testSuite(),
    now: testNow,
  );
  if (pin) await tester.runAsync(() => vault.setPin('135790'));
  final gate = lastGate = OnboardingGate.over(
    auth: client,
    vault: vault,
    flow: onboardingFlow,
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    RukkaFolioApp(
      db: ledger.db,
      sync: FakeSyncClient(),
      auth: client,
      keys: ledger.keys as FakeKeyStore,
      now: testNow,
      locale: const Locale('en'),
      ledger: ledger,
      settings: settings,
      entitlement: entitlement,
      featureRoutes: [
        ...onboardingRoutes,
        ...authRoutes,
        ...recoveryRoutes(onRestored: gate.handOverIfReady),
      ],
      onboardingGate: gate,
    ),
  );
  await tester.pumpAndSettle();
  return GoRouter.of(tester.element(find.byType(Navigator).first));
}

String where(GoRouter r) => r.state.uri.path;

Future<void> go(WidgetTester tester, GoRouter r, String path) async {
  r.go(path);
  await tester.pumpAndSettle();
}

/// Android system Back, as the engine delivers it.
Future<bool> systemBack(WidgetTester tester) async {
  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return handled;
}

void main() {
  late LocalLedger ledger;

  setUp(() async {
    onboardingFlow.reset();
    ledger = await openTestLedger();
    await ledger.bootstrapSolo();
  });
  tearDown(onboardingFlow.reset);

  group('F1-1006b-1 Home is unreachable until the chain hands over', () {
    testWidgets(
      'F1-1006b-1 not onboarded: Home, every tab, the entry action and a deep '
      'link all land in the chain',
      (tester) async {
        final settings = await settingsOver(MemoryPrefs());
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: settings,
        );
        // The router's default location is Home; the gate took it.
        expect(where(router), OnboardingPaths.purpose);
        expect(find.text('Rukka Folio'), findsNothing);

        for (final path in [
          RkPaths.home,
          RkPaths.ledger,
          RkPaths.inbox,
          RkPaths.menu,
          RkPaths.entry,
          HomePaths.position.replaceFirst(':line', 'cash'),
          RkPaths.advances,
          RkPaths.members,
          '/close/b1/2026-09',
        ]) {
          await go(tester, router, path);
          expect(where(router), OnboardingPaths.purpose, reason: path);
        }
        expect(settings.onboarded, isFalse);
      },
    );

    testWidgets('F1-1006b-1 onboarded: Home and the tabs open as before', (
      tester,
    ) async {
      final settings = await settingsOver(
        MemoryPrefs()..values[RkPrefKeys.onboarded] = '1',
      );
      final router = await pumpGated(
        tester,
        ledger: ledger,
        settings: settings,
      );
      expect(where(router), RkPaths.home);
      await go(tester, router, RkPaths.ledger);
      expect(where(router), RkPaths.ledger);
    });

    testWidgets(
      'F1-1006b-1 the chain\'s last step records the hand-over once, it '
      'survives a restart, and only then does Home open',
      (tester) async {
        final prefs = MemoryPrefs();
        final settings = await settingsOver(prefs);
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: settings,
          pin: true,
        );
        // Account + PIN, nothing else saved → S0.5 (ruling 2).
        expect(where(router), OnboardingPaths.booksSafe);
        await go(tester, router, OnboardingPaths.recoverySheet);

        // S0.5b's skip with no purpose recorded is `afterSetPin` → Home: the
        // production callback, not a hand-written navigation.
        tester
            .widget<RecoverySheetScreen>(find.byType(RecoverySheetScreen))
            .onSkip!();
        await tester.pumpAndSettle();
        expect(where(router), RkPaths.home);
        expect(settings.onboarded, isTrue);
        expect(prefs.values[RkPrefKeys.onboarded], '1');

        // A restart over the same store opens Home with no launch argument.
        final restarted = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(prefs),
          pin: true,
        );
        expect(where(restarted), RkPaths.home);
      },
    );
  });

  group('F1-1006b-2 a cold start resumes the chain', () {
    testWidgets(
      'F1-1006b-2 no account on the device → S0.0 splash, which hands on to '
      'S0.1 — never Home',
      (tester) async {
        final gate = OnboardingGate(
          hasAccount: () => false,
          pinSet: () async => true,
          flow: onboardingFlow..setYourName('Harpreet'),
        );
        // No account outranks anything else on the device.
        expect(await gate.resumeTarget(), OnboardingPaths.splash);

        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
          account: false,
        );
        // S0.0 is a mark animation; in a test it hands straight on.
        expect(where(router), OnboardingPaths.language);
        expect(find.byType(LanguagePickerScreen), findsOneWidget);
      },
    );

    testWidgets(
      'F1-1006b-2 an account but nothing after it → S0.3; a purpose in hand → '
      'S0.4; a name → S0.8; a PIN → S0.5',
      (tester) async {
        Future<String> landing({bool pin = false}) async => where(
          await pumpGated(
            tester,
            ledger: ledger,
            settings: await settingsOver(MemoryPrefs()),
            pin: pin,
          ),
        );

        expect(await landing(), OnboardingPaths.purpose);
        onboardingFlow.setPurpose(OnboardingPurpose.family);
        expect(await landing(), OnboardingPaths.namePhoto);
        onboardingFlow.setYourName('Harpreet');
        expect(await landing(), OnboardingPaths.setPin);
        expect(await landing(pin: true), OnboardingPaths.booksSafe);
      },
    );

    testWidgets('F1-1006b-2 after the hand-over a cold start opens Home', (
      tester,
    ) async {
      final router = await pumpGated(
        tester,
        ledger: ledger,
        settings: await settingsOver(
          MemoryPrefs()..values[RkPrefKeys.onboarded] = '1',
        ),
        pin: true,
      );
      expect(where(router), RkPaths.home);
    });

    test('F1-1006b-2 the chain, S0.2, the ladder and the lock stand; '
        'Home and the tabs do not', () {
      for (final p in [
        OnboardingPaths.splash,
        OnboardingPaths.signIn,
        OnboardingPaths.invitation,
        OnboardingPaths.trustAccounts,
        RkPaths.authPhone,
        RkPaths.recovery,
        RkPaths.recoveryFork,
        '/lock',
        RkPaths.updateRequired,
      ]) {
        expect(OnboardingGate.allowsBeforeOnboarding(p), isTrue, reason: p);
      }
      for (final p in [
        RkPaths.home,
        RkPaths.ledger,
        RkPaths.inbox,
        RkPaths.menu,
        RkPaths.entry,
        '/homework',
        '/onboardingx',
      ]) {
        expect(OnboardingGate.allowsBeforeOnboarding(p), isFalse, reason: p);
      }
    });
  });

  group('F1-1006b-3 system Back follows the chain', () {
    const justMe = BusinessDraft(
      name: 'Sharma Traders',
      ownership: BusinessOwnershipChoice.justMe,
      fyStartMonth: 4,
    );
    const shared = BusinessDraft(
      name: 'Sharma Traders',
      ownership: BusinessOwnershipChoice.shared,
      fyStartMonth: 4,
    );
    const family = FamilyDraft(name: 'Sandhu');
    const trust = TrustDraft(name: 'Singh Sabha', type: TrustType.gurudwara);

    // (step, flow setup, where Back lands — the step itself where it holds).
    // Every step of 13 §5 F1 after S0.06 is here, including the committing
    // ones (S0.6b/f/i) with their book created — and with the creation
    // failed, the one case they may still go back — and S0.6c.
    final steps = <(String, void Function(), String)>[
      (OnboardingPaths.welcome, () {}, OnboardingPaths.language),
      (OnboardingPaths.start, () {}, OnboardingPaths.welcome),
      (OnboardingPaths.signIn, () {}, OnboardingPaths.start),
      (OnboardingPaths.namePhoto, () {}, OnboardingPaths.purpose),
      (OnboardingPaths.setPin, () {}, OnboardingPaths.namePhoto),
      (OnboardingPaths.recoverySheet, () {}, OnboardingPaths.booksSafe),
      (OnboardingPaths.business, () {}, OnboardingPaths.recoverySheet),
      (
        OnboardingPaths.businessOwners,
        () => onboardingFlow.setBusiness(shared),
        OnboardingPaths.business,
      ),
      // S0.6b with no S0.6a answer: the creation fails, no book exists, and
      // Back goes to the answer step.
      (OnboardingPaths.businessOpening, () {}, OnboardingPaths.business),
      // S0.6b once its book exists: the answers are fixed into it — hold.
      (
        OnboardingPaths.businessOpening,
        () => onboardingFlow.setBusiness(justMe),
        OnboardingPaths.businessOpening,
      ),
      (
        OnboardingPaths.businessOpening,
        () => onboardingFlow.setBusiness(shared),
        OnboardingPaths.businessOpening,
      ),
      // S0.6c: S0.6b has posted (or skipped) — hold, never re-post.
      (
        OnboardingPaths.businessAnother,
        () => onboardingFlow
          ..setPurpose(OnboardingPurpose.businesses)
          ..setBusiness(justMe)
          ..businessBookId = 'b-1',
        OnboardingPaths.businessAnother,
      ),
      (OnboardingPaths.family, () {}, OnboardingPaths.recoverySheet),
      (
        OnboardingPaths.familyMembers,
        () => onboardingFlow.setFamily(family),
        OnboardingPaths.family,
      ),
      (OnboardingPaths.familyAccounts, () {}, OnboardingPaths.familyMembers),
      (
        OnboardingPaths.familyAccounts,
        () => onboardingFlow.setFamily(family),
        OnboardingPaths.familyAccounts,
      ),
      (OnboardingPaths.trust, () {}, OnboardingPaths.recoverySheet),
      (
        OnboardingPaths.trustMembers,
        () => onboardingFlow.setTrust(trust),
        OnboardingPaths.trust,
      ),
      (OnboardingPaths.trustAccounts, () {}, OnboardingPaths.trustMembers),
      (
        OnboardingPaths.trustAccounts,
        () => onboardingFlow.setTrust(trust),
        OnboardingPaths.trustAccounts,
      ),
    ];

    for (final (i, (step, setup, previous)) in steps.indexed) {
      final verb = previous == step ? 'holds' : '→ $previous';
      testWidgets('F1-1006b-3 Back on $step $verb, never out (#$i)', (
        tester,
      ) async {
        setup();
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
        );
        await go(tester, router, step);
        expect(where(router), step);

        expect(await systemBack(tester), isTrue, reason: 'the app stays open');
        expect(where(router), previous);
        expect(where(router), isNot(RkPaths.home));
      });
    }

    testWidgets(
      'F1-1006b-3 a committing step holds while its book is being created, '
      'then — the book made — never reopens the answers it was made from',
      (tester) async {
        onboardingFlow.setBusiness(justMe);
        final entitlement = _StallingEntitlement();
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
          entitlement: entitlement,
        );
        entitlement.stall = true;
        await go(tester, router, OnboardingPaths.businessOpening);
        expect(find.text('Setting up your books…'), findsOneWidget);
        // No book yet, so the chain's previous step *would* be S0.6a — the
        // host holds because the creation is in flight.
        expect(onboardingFlow.businessBookId, isNull);
        expect(
          previousOnboardingStep(
            OnboardingPaths.businessOpening,
            onboardingFlow,
          ),
          OnboardingPaths.business,
        );
        expect(await systemBack(tester), isTrue);
        expect(where(router), OnboardingPaths.businessOpening);

        entitlement.release.complete();
        await tester.pumpAndSettle();

        // The book exists now; Back still holds and S0.6a is not reopened.
        expect(onboardingFlow.businessBookId, isNotNull);
        expect(find.byType(BusinessOpeningBalancesScreen), findsOneWidget);
        expect(await systemBack(tester), isTrue);
        expect(where(router), OnboardingPaths.businessOpening);
      },
    );

    testWidgets(
      'F1-1006b-3 S0.6b mounted again after Save moves on to S0.6c and '
      'offers no second set of opening balances to the same book',
      (tester) async {
        onboardingFlow
          ..setPurpose(OnboardingPurpose.businesses)
          ..setBusiness(justMe);
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
        );
        await go(tester, router, OnboardingPaths.businessOpening);
        final screen = tester.widget<BusinessOpeningBalancesScreen>(
          find.byType(BusinessOpeningBalancesScreen),
        );
        final bookId = onboardingFlow.businessBookId;
        screen.onSave!({screen.rows.first.accountId: 150000});
        await tester.pumpAndSettle();
        expect(where(router), OnboardingPaths.businessAnother);
        expect(onboardingFlow.businessOpeningPosted, isTrue);

        // A deep link (or any re-mount) back into S0.6b: same book, no form.
        await go(tester, router, OnboardingPaths.businessOpening);
        expect(where(router), OnboardingPaths.businessAnother);
        expect(find.byType(BusinessOpeningBalancesScreen), findsNothing);
        expect(onboardingFlow.businessBookId, bookId);
      },
    );

    testWidgets(
      'F1-1006b-3 a second pass round the My business loop: Back on S0.6a '
      'returns to S0.6c',
      (tester) async {
        onboardingFlow
          ..setPurpose(OnboardingPurpose.businesses)
          ..setBusiness(
            const BusinessDraft(
              name: 'Sharma Traders',
              ownership: BusinessOwnershipChoice.justMe,
              fyStartMonth: 4,
            ),
          )
          ..addAnotherBusiness();
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
        );
        await go(tester, router, OnboardingPaths.business);
        expect(await systemBack(tester), isTrue);
        expect(where(router), OnboardingPaths.businessAnother);
      },
    );

    testWidgets(
      'F1-1006b-3 S0.8 mirrors its own back: the confirm step starts over in '
      'place, then the choose step returns to S0.4',
      (tester) async {
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
        );
        await go(tester, router, OnboardingPaths.setPin);
        for (final d in '123456'.split('')) {
          await tester.tap(find.text(d).last);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.text('Type it again'), findsOneWidget);

        expect(await systemBack(tester), isTrue);
        expect(where(router), OnboardingPaths.setPin);
        expect(find.text('Type it again'), findsNothing);

        expect(await systemBack(tester), isTrue);
        expect(where(router), OnboardingPaths.namePhoto);
      },
    );

    testWidgets(
      'F1-1006b-3 a step with no meaningful previous step holds its place: '
      'S0.3 after the device is active, S0.5 after the PIN is saved',
      (tester) async {
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
        );
        expect(where(router), OnboardingPaths.purpose);
        expect(await systemBack(tester), isTrue);
        expect(where(router), OnboardingPaths.purpose);

        await go(tester, router, OnboardingPaths.booksSafe);
        expect(await systemBack(tester), isTrue);
        expect(where(router), OnboardingPaths.booksSafe);
      },
    );

    testWidgets(
      'F1-1006b-3 only the chain\'s first screen lets Back leave the app',
      (tester) async {
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
        );
        await go(tester, router, OnboardingPaths.language);
        expect(
          await systemBack(tester),
          isFalse,
          reason: 'the system takes Back: the app may close here',
        );
      },
    );

    testWidgets(
      'F1-1006b-3 S0.2 mirrors its own back on every sub-step: the code step '
      'returns to the number step in place, the number step to S0.06',
      (tester) async {
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
          auth: FakeAuthClient(),
        );
        await go(tester, router, OnboardingPaths.signIn);
        await enterNumberAndSend(tester, _number);
        expect(find.text('Enter the code'), findsOneWidget);

        expect(await systemBack(tester), isTrue);
        expect(where(router), OnboardingPaths.signIn);
        expect(find.text('Your phone number'), findsOneWidget);

        expect(await systemBack(tester), isTrue);
        expect(where(router), OnboardingPaths.start);
      },
    );

    testWidgets(
      'F1-1006b-3 S0.2 holds while a code is being verified and while the '
      'device is being activated',
      (tester) async {
        for (final (stallCheck, holding) in [
          (true, 'Checking…'),
          (false, 'Setting up this phone…'),
        ]) {
          final auth = _StallingAuth(
            stallCheck: stallCheck,
            stallActivate: !stallCheck,
          );
          final router = await pumpGated(
            tester,
            ledger: ledger,
            settings: await settingsOver(MemoryPrefs()),
            auth: auth,
          );
          await go(tester, router, OnboardingPaths.signIn);
          await enterNumberAndSend(tester, _number);
          await tapKeysNoSettle(tester, '482913');
          expect(find.text(holding), findsWidgets, reason: holding);

          expect(
            await tester.binding.handlePopRoute(),
            isTrue,
            reason: holding,
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(where(router), OnboardingPaths.signIn, reason: holding);
          expect(find.text(holding), findsWidgets, reason: holding);

          // Released, the step carries on where it was — nothing was undone.
          auth.release.complete();
          await tester.pumpAndSettle();
          expect(auth.current, isA<Active>(), reason: holding);
        }
      },
    );

    testWidgets(
      'F1-1006b-3 F1b: Back on the S11.6 fork returns to S0.2b with its '
      'answers in place — the app stays open',
      (tester) async {
        final auth = FakeAuthClient()..numbersWithBooks.add('+91$_withBooks');
        final router = await pumpGated(
          tester,
          ledger: ledger,
          settings: await settingsOver(MemoryPrefs()),
          auth: auth,
        );
        await go(tester, router, OnboardingPaths.signInReturning);
        await enterNumberAndSend(tester, _withBooks);
        await tapKeys(tester, '482913');
        expect(find.text('Is your old phone with you?'), findsOneWidget);

        await tester.tap(find.text('No, it’s lost or reset'));
        await tester.pumpAndSettle();
        expect(where(router), RkPaths.recoveryFork);
        expect(find.byType(RecoveryForkScreen), findsOneWidget);

        expect(await systemBack(tester), isTrue, reason: 'the app stays open');
        expect(where(router), OnboardingPaths.signIn);
        expect(find.text('Is your old phone with you?'), findsOneWidget);
        expect(auth.requestedPhones, ['+91$_withBooks']);
      },
    );
  });

  group('F1-1006b-1 F1b through the ladder hands over only a phone that is '
      'set up', () {
    Future<(GoRouter, AppSettings)> continueFromNothingYet(
      WidgetTester tester, {
      required bool account,
      required bool pin,
    }) async {
      final settings = await settingsOver(MemoryPrefs());
      final router = await pumpGated(
        tester,
        ledger: ledger,
        settings: settings,
        account: account,
        pin: pin,
      );
      await go(tester, router, RkPaths.recoveryNothingYet);
      expect(where(router), RkPaths.recoveryNothingYet);
      tester
          .widget<NothingWorkedYetScreen>(find.byType(NothingWorkedYetScreen))
          .onContinue!();
      await tester.pumpAndSettle();
      return (router, settings);
    }

    testWidgets(
      'F1-1006b-1 S11.8 Continue with no device activated resumes the chain '
      'at S0.0 and records nothing — a relaunch is still gated',
      (tester) async {
        final (router, settings) = await continueFromNothingYet(
          tester,
          account: false,
          pin: false,
        );
        expect(where(router), OnboardingPaths.language);
        expect(settings.onboarded, isFalse);
        await go(tester, router, RkPaths.home);
        expect(where(router), isNot(RkPaths.home));
      },
    );

    testWidgets(
      'F1-1006b-1 S11.8 Continue with a session but no PIN resumes the chain '
      'and records nothing',
      (tester) async {
        final (router, settings) = await continueFromNothingYet(
          tester,
          account: true,
          pin: false,
        );
        expect(where(router), OnboardingPaths.purpose);
        expect(settings.onboarded, isFalse);
      },
    );

    testWidgets(
      'F1-1006b-1 S11.8 Continue with a session and a PIN (the real vault) '
      'is the hand-over: Home, recorded once',
      (tester) async {
        final (router, settings) = await continueFromNothingYet(
          tester,
          account: true,
          pin: true,
        );
        expect(where(router), RkPaths.home);
        expect(settings.onboarded, isTrue);
      },
    );

    test('F1-1006b-1 the composition root builds the one gate with '
        'OnboardingGate.over over its live session and PIN vault, and hands '
        'it to both the router and the ladder (root pin)', () {
      final root = [
        'lib/bootstrap.dart',
        'app/lib/bootstrap.dart',
      ].map(File.new).firstWhere((f) => f.existsSync()).readAsStringSync();
      expect(
        RegExp(
          r'final onboardingGate = OnboardingGate\.over\(\s*auth: auth,\s*'
          r'vault: vault,\s*flow: onboardingFlow,\s*\);',
        ).allMatches(root),
        hasLength(1),
      );
      expect('onboardingGate: onboardingGate,'.allMatches(root), hasLength(1));
      expect(
        'onRestored: onboardingGate.handOverIfReady,'.allMatches(root),
        hasLength(1),
      );
      // The PIN vault the gate reads is the app's own.
      expect(root, contains('pinVault: vault,'));
      // No second, hand-built gate anywhere in the root.
      expect(RegExp(r'OnboardingGate\(').allMatches(root), isEmpty);
    });
  });
}
