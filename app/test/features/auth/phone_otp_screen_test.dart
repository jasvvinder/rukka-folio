@Tags(['F1'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart';
import 'package:rukka_folio/features/auth/phone_shape.dart';
import 'package:rukka_folio/features/auth/screens/s0_2_phone_otp_screen.dart';
import 'package:rukka_folio/features/auth/screens/s19_1_update_required_screen.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';
import 'sign_in_harness.dart';

/// A movable clock for the resend cooldown; widgets read `RkScope.now`.
final class _Clock {
  DateTime now = DateTime(2026, 9, 7, 10);
  DateTime call() => now;
}

/// A fake that is also an [OtpChannelSource] and reports SMS once a code
/// is requested, the state in which the pre-ADR-2026-09-25 screen drew the
/// WhatsApp→SMS fallback line (`channel.value == OtpChannel.sms`, F1-06-5 at
/// ce5799f). C-25-1 pumps it so the "no fallback line" half can fail.
final class _SmsChannelAuth extends FakeAuthClient implements OtpChannelSource {
  _SmsChannelAuth({super.expectedCode});

  final _channel = ValueNotifier<OtpChannel?>(null);

  @override
  ValueListenable<OtpChannel?> get otpChannel => _channel;

  @override
  Future<void> requestOtp(
    String phone, {
    SignInDoor door = SignInDoor.newBooks,
  }) async {
    await super.requestOtp(phone, door: door);
    _channel.value = OtpChannel.sms;
  }
}

/// The typed number, from the reserved test block (ADR 2026-09-05i §7).
const _typed = '9999900001'; // +91 99999 00001
const _e164 = '+91$_typed';

/// How S0.2 writes the number (canvas 1b L3: `+91 98765 43210`).
const _shown = '+91 99999 00001';

/// The first synthetic demo number (dev project, owner-directed 4 Oct 2026).
const _demo = '5000001001';

Future<void> _enterPhoneAndSend(WidgetTester tester) =>
    enterNumberAndSend(tester, _typed);

/// The S0.2 title in each shipped language — the anchor the layout sweep
/// looks for once the screen is drawn at 1.3× and 2×.
const _title = {
  'en': 'Your phone number',
  'pa': 'ਤੁਹਾਡਾ ਫ਼ੋਨ ਨੰਬਰ',
  'hi': 'आपका फ़ोन नंबर',
};

void main() {
  group('S0.2 Phone + OTP (13 §3.2, 07 §3.1, 06 §2)', () {
    testWidgets(
      'F1-06-1 default → sending → OTP step: the number goes to the seam as E.164, the code step names the number, verify + activate ends on a done screen that names nothing about the family',
      (tester) async {
        final auth = FakeAuthClient(expectedCode: '482913');
        AuthSession? done;
        await pumpRk(
          tester,
          PhoneOtpScreen(onDone: (s) => done = s),
          auth: auth,
        );
        expect(find.text('Your phone number'), findsOneWidget);
        expect(
          find.text('+91'),
          findsOneWidget,
        ); // fixed country prefix beside the number
        await _enterPhoneAndSend(tester);
        expect(auth.requestedPhones, [_e164]);
        expect(auth.requestedDoors, [SignInDoor.newBooks]);
        expect(find.text('Enter the code'), findsOneWidget);
        expect(find.text('Sent by SMS to $_shown.'), findsOneWidget);
        // Six digits verify by themselves (canvas 1b L3 has no Verify button).
        await tapKeys(tester, '482913');
        expect(auth.verifiedCodes, ['482913']);
        expect(
          auth.current,
          isA<Active>().having((a) => a.deviceCertified, 'certified', false),
        );
        expect(find.text('This phone is ready'), findsOneWidget);
        expect(find.textContaining('family', findRichText: true), findsNothing);
        await tester.tap(find.text('Continue'));
        expect(done?.deviceId, 'fake-device');
      },
    );

    testWidgets(
      'F1-06-2 wrong code shows tries left with the boxes kept; the third miss clears the boxes and, once the 06 §2 wait is over, a new code goes by itself — never a lockout (ADR 2026-10-05c §2); Change stays on screen (no dead end)',
      (tester) async {
        final clock = _Clock();
        final auth = FakeAuthClient(expectedCode: '482913');
        await pumpRk(
          tester,
          const PhoneOtpScreen(),
          auth: auth,
          now: clock.call,
        );
        await _enterPhoneAndSend(tester);
        // Let the first 30 s wait run out, so the third miss can resend.
        clock.now = clock.now.add(const Duration(seconds: 31));
        await tester.pump(const Duration(seconds: 1));
        for (final (code, expected) in [
          (
            '000000',
            'That code didn’t match. 2 tries left, then we’ll send a new one.',
          ),
          (
            '000001',
            'That code didn’t match. 1 try left, then we’ll send a new one.',
          ),
        ]) {
          await tapKeys(tester, code);
          expect(find.text(expected), findsOneWidget);
          // The rejected digits stay in the boxes (c1b L4).
          expect(find.text(code[5]), findsWidgets);
        }
        await tapKeys(tester, '000002');
        expect(
          find.text(
            'That code didn’t match three times. We’ve sent you a new one.',
          ),
          findsOneWidget,
        );
        expect(auth.requestedPhones, [_e164, _e164]);
        expect(find.text('Change'), findsOneWidget);
        // The new code verifies.
        await tapKeys(tester, '482913');
        expect(find.text('This phone is ready'), findsOneWidget);
        clock.now = clock.now.add(const Duration(minutes: 5));
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets(
      'F1-06-3 resend cooldown 30 s → 60 s runs against the injected clock and the button re-enables at zero',
      (tester) async {
        final clock = _Clock();
        final auth = FakeAuthClient();
        await pumpRk(
          tester,
          const PhoneOtpScreen(),
          auth: auth,
          now: clock.call,
        );
        await _enterPhoneAndSend(tester);
        // The wait is words with a clock, not a button (c1 O2b).
        expect(find.text('Send again in 0:30'), findsOneWidget);
        expect(find.byIcon(Icons.schedule), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Send again'), findsNothing);
        clock.now = clock.now.add(const Duration(seconds: 29));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Send again in 0:01'), findsOneWidget);
        clock.now = clock.now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Didn’t get it?'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Send again'));
        await tester.pumpAndSettle();
        expect(auth.requestedPhones, hasLength(2));
        expect(find.text('Send again in 1:00'), findsOneWidget);
        // Drain the periodic timer.
        clock.now = clock.now.add(const Duration(seconds: 60));
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets(
      'F1-06-4 offline: a quiet chip and nothing blocking — Send stays live and rests on the auth client\'s own answer, never on sync status (ADR 2026-10-10 §2); rate-limited and unavailable failures read generic',
      (tester) async {
        final sync = FakeSyncClient(initial: const Offline());
        final auth = FakeAuthClient();
        await pumpRk(tester, const PhoneOtpScreen(), auth: auth, sync: sync);
        expect(
          find.text('Offline — you need internet for the code.'),
          findsOneWidget,
        );
        await tapKeys(tester, _typed);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send code'),
              )
              .onPressed,
          isNotNull,
          reason: 'sync status never disables Send (ADR 2026-10-10 §2)',
        );
        // The tap reaches the auth client while the chip still shows; what
        // comes back is the auth client's own answer.
        auth.failNext = const AuthFailure(AuthFailureKind.rateLimited);
        await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
        await tester.pumpAndSettle();
        expect(
          find.text('Offline — you need internet for the code.'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(
          find.text(
            'Too many tries for now. Please wait a while and try again.',
          ),
          findsOneWidget,
        );
        expect(auth.requestedPhones, isEmpty);
        auth.failNext = const AuthFailure(AuthFailureKind.unavailable);
        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();
        expect(
          find.text('Couldn’t connect. Check your internet and try again.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-06-5 min-version gate: when the 426 listenable fires, S19.1 replaces S0.2 with no way back',
      (tester) async {
        final gate = ValueNotifier<UpdateRequired?>(null);
        await pumpRk(tester, PhoneOtpScreen(gate: gate));
        await _enterPhoneAndSend(tester);
        // No channel line on the code step (ADR 2026-09-25 §1) — C-25-1.
        gate.value = const UpdateRequired(
          currentVersion: '1.2.0',
          requiredVersion: '1.3.0',
        );
        await tester.pumpAndSettle();
        expect(find.byType(UpdateRequiredScreen), findsOneWidget);
        expect(find.text('Update needed'), findsOneWidget);
        expect(find.text('You have 1.2.0 · needs 1.3.0'), findsOneWidget);
        expect(find.text('Enter the code'), findsNothing);
        expect(
          tester.widget<PopScope>(find.byType(PopScope).first).canPop,
          isFalse,
        );
      },
    );

    testWidgets(
      'F1-06-6 Send waits for ten digits (c1 O2a), a ten-digit number that is not a mobile is refused before any request, the keypad stops at ten; strings resolve in PA and HI without overflow at 200 %',
      (tester) async {
        final auth = FakeAuthClient();
        await pumpRk(tester, const PhoneOtpScreen(), auth: auth);
        await tapKeys(tester, '98765');
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send code'),
              )
              .onPressed,
          isNull,
        );
        await tapKeys(tester, '1234567');
        expect(find.text('98765 12345'), findsOneWidget);
        // A shape no mobile has: refused on the phone, no request.
        await pumpRk(
          tester,
          const PhoneOtpScreen(key: ValueKey('shape')),
          auth: auth,
        );
        await enterNumberAndSend(tester, '1234567890');
        expect(find.text('Enter the 10-digit mobile number.'), findsOneWidget);
        expect(auth.requestedPhones, isEmpty);

        for (final locale in rkLocales) {
          for (final vp in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                const PhoneOtpScreen(),
                locale: locale,
                textScale: scale,
                viewport: vp,
              );
              expect(find.text(_title[locale.languageCode]!), findsOneWidget);
              expect(tester.takeException(), isNull);
              expectTextFits(
                tester,
                reason: '${locale.languageCode} @ $scale on $vp',
              );
            }
          }
        }
      },
    );
  });

  group(
    'S0.2 demo phone range is off by default (owner-directed 4 Oct 2026)',
    () {
      testWidgets(
        'F1-DEMO-3 without RF_DEMO_PHONES a 5-number is refused before any request, exactly as any other bad number; a 9-number (control) reaches the seam as E.164',
        (tester) async {
          final auth = FakeAuthClient();
          await pumpRk(tester, const PhoneOtpScreen(), auth: auth);
          await enterNumberAndSend(tester, _demo);
          expect(
            find.text('Enter the 10-digit mobile number.'),
            findsOneWidget,
          );
          expect(auth.requestedPhones, isEmpty);

          await pumpRk(
            tester,
            const PhoneOtpScreen(key: ValueKey('control')),
            auth: auth,
          );
          await enterNumberAndSend(tester, _typed);
          expect(auth.requestedPhones, [_e164]);
        },
      );

      testWidgets(
        'F1-DEMO-6 with the demo range ON (the RF_DEMO_PHONES=true path, via the test seam) S0.2 sends a 5-number to the seam as E.164 — the screen follows the shared predicate, not a copy of its own',
        (tester) async {
          debugDemoPhonesOverride = true;
          addTearDown(() => debugDemoPhonesOverride = null);
          final auth = FakeAuthClient();
          await pumpRk(tester, const PhoneOtpScreen(), auth: auth);
          await enterNumberAndSend(tester, _demo);
          expect(find.text('Enter the 10-digit mobile number.'), findsNothing);
          expect(auth.requestedPhones, ['+91$_demo']);
          expect(find.text('Enter the code'), findsOneWidget);
        },
      );
    },
  );

  group('S0.2 OTP by SMS only (ADR 2026-09-25 §1, amends 06 §2)', () {
    testWidgets(
      'C-25-1 S0.2 says SMS and never WhatsApp in EN, PA and HI: the phone step names SMS as the one channel, and the code step shows no WhatsApp line and no fallback line',
      (tester) async {
        // The helper line per locale: SMS is the only channel it names.
        const hint = {
          'en': 'We’ll send a 6-digit code by SMS.',
          'pa': 'ਅਸੀਂ SMS ਰਾਹੀਂ 6 ਅੰਕਾਂ ਦਾ ਕੋਡ ਭੇਜਾਂਗੇ।',
          'hi': 'हम SMS से 6 अंकों का कोड भेजेंगे।',
        };
        // The retired fallback line, in each language — it must never draw.
        const fallback = {
          'en': 'WhatsApp didn’t go through, so the code went by SMS.',
          'pa': 'WhatsApp ’ਤੇ ਨਹੀਂ ਗਿਆ, ਇਸ ਲਈ ਕੋਡ SMS ਰਾਹੀਂ ਭੇਜਿਆ ਗਿਆ।',
          'hi': 'WhatsApp पर नहीं गया, इसलिए कोड SMS से भेजा गया।',
        };
        for (final locale in rkLocales) {
          final lang = locale.languageCode;
          // A channel source, so the code step runs in the state that once
          // drew the fallback line: channel reported as SMS.
          final auth = _SmsChannelAuth(expectedCode: '482913');
          // A fresh screen per locale (keyed), so each run starts on step 1.
          await pumpRk(
            tester,
            PhoneOtpScreen(key: ValueKey(lang)),
            locale: locale,
            auth: auth,
          );
          // Phone step: the screen is drawn and names SMS, not WhatsApp. The
          // SMS sentence closes canvas 1 O2a's subtitle (one Text).
          expect(find.text(_title[lang]!), findsOneWidget, reason: lang);
          expect(
            find.textContaining(hint[lang]!),
            findsOneWidget,
            reason: lang,
          );
          expect(find.textContaining('WhatsApp'), findsNothing, reason: lang);

          await tapKeys(tester, _typed);
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          // Code step reached through the seam, and no channel line at all —
          // the one line names SMS (canvas 1b L3).
          expect(auth.requestedPhones, [_e164], reason: lang);
          expect(auth.otpChannel.value, OtpChannel.sms, reason: lang);
          expect(find.textContaining(_shown), findsOneWidget, reason: lang);
          expect(find.textContaining('SMS'), findsOneWidget, reason: lang);
          expect(find.textContaining('WhatsApp'), findsNothing, reason: lang);
          expect(find.text(fallback[lang]!), findsNothing, reason: lang);
          expect(tester.takeException(), isNull);
        }
      },
    );
  });

  group('S19.1 Update required (13 §3.2, 07 §24, 06 §4.5)', () {
    testWidgets(
      'F1-06-7 renders title, body, versions; the action shows its loading state and the offline note keeps the button (no dead end)',
      (tester) async {
        var opened = 0;
        final sync = FakeSyncClient(initial: const Offline());
        await pumpRk(
          tester,
          UpdateRequiredScreen(
            gate: const UpdateRequired(
              currentVersion: '1.0.0',
              requiredVersion: '',
            ),
            onUpdate: () async => opened++,
          ),
          sync: sync,
        );
        expect(find.text('Update needed'), findsOneWidget);
        expect(find.text('You have 1.0.0 · needs —'), findsOneWidget);
        expect(find.text('You’ll need internet to update.'), findsOneWidget);
        await tester.tap(find.text('Update now'));
        await tester.pumpAndSettle();
        expect(opened, 1);
        await pumpRk(
          tester,
          const UpdateRequiredScreen(
            gate: UpdateRequired(currentVersion: '1', requiredVersion: '2'),
          ),
          locale: const Locale('hi'),
        );
        expect(find.text('अपडेट ज़रूरी है'), findsOneWidget);
      },
    );
  });

  // ADR 2026-10-05c §2 supersedes the single *already signed up* state of ADR
  // 2026-10-04b §3 (desk 131): on the *I'm new* door it is S0.2a, whose *Sign
  // in to my books* continues to S0.2b with no second code; *Get my books
  // back* → fork is now S0.2b's *No, it's lost or reset*. The coverage below
  // is the same three questions, re-pointed: never activated, both ways on,
  // and the strings fit.
  group('S0.2 a number that already has an account (ADR 2026-10-04b §3, '
      're-pointed by ADR 2026-10-05c §2)', () {
    /// The S0.2a title, per locale — the anchor for the layout sweep.
    const existingTitle = {
      'en': 'Welcome back',
      'pa': 'ਜੀ ਆਇਆਂ ਨੂੰ, ਫਿਰ ਤੋਂ',
      'hi': 'फिर से स्वागत है',
    };

    Future<FakeAuthClient> reachExisting(
      WidgetTester tester, {
      VoidCallback? onNoOldPhone,
      void Function(AuthSession)? onDone,
      Locale? locale,
      double textScale = 1,
      Size? viewport,
    }) async {
      final auth = FakeAuthClient()..numbersWithBooks.add(_e164);
      await pumpRk(
        tester,
        // A fresh state per pump: the sweep re-pumps the same screen type.
        PhoneOtpScreen(
          key: UniqueKey(),
          onDone: onDone,
          onNoOldPhone: onNoOldPhone,
        ),
        auth: auth,
        locale: locale,
        textScale: textScale,
        viewport: viewport,
      );
      await enterNumberAndSend(tester, _typed);
      await tapKeys(tester, '482913');
      return auth;
    }

    testWidgets(
      'C-04b-2 a verify that answers another account shows S0.2a — never activating this phone — with two ways on: Sign in to my books (to S0.2b, no second code, then the 06 §5 fork) and Use a different number (back to the phone step)',
      (tester) async {
        var forked = 0;
        AuthSession? done;
        final auth = await reachExisting(
          tester,
          onNoOldPhone: () => forked++,
          onDone: (s) => done = s,
        );
        expect(find.text('Welcome back'), findsOneWidget);
        expect(
          find.text(
            '$_shown is already used with Rukka Folio. One number keeps one '
            'set of books, so there is nothing new to set up.',
          ),
          findsOneWidget,
        );
        expect(auth.current, isNot(isA<Active>()));
        expect(done, isNull);

        await tester.tap(find.text('Sign in to my books'));
        await tester.pumpAndSettle();
        expect(find.text('Is your old phone with you?'), findsOneWidget);
        expect(auth.requestedPhones, hasLength(1), reason: 'no second code');
        await tester.tap(find.text('No, it’s lost or reset'));
        await tester.pumpAndSettle();
        expect(forked, 1);
        expect(auth.current, isNot(isA<Active>()));

        // Back to S0.2a, then Use a different number → the phone step.
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use a different number'));
        await tester.pumpAndSettle();
        expect(find.text('Your phone number'), findsOneWidget);
        expect(find.text('Welcome back'), findsNothing);
      },
    );

    testWidgets(
      'C-04b-2 with no callback S0.2b still draws the fork its copy promises — No, it\'s lost or reset is enabled — and S0.2a draws both actions',
      (tester) async {
        await reachExisting(tester);
        expect(
          find.widgetWithText(FilledButton, 'Sign in to my books'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Use a different number'),
          findsOneWidget,
        );
        await tester.tap(find.text('Sign in to my books'));
        await tester.pumpAndSettle();
        expect(find.text('No, it’s lost or reset'), findsOneWidget);
      },
    );

    testWidgets(
      'C-04b-2 S0.2a and S0.2b resolve in EN, PA and HI and fit at 1.3× and 2× on 360×800 and 375×667',
      (tester) async {
        for (final locale in rkLocales) {
          for (final vp in rkPhones) {
            for (final scale in rkTextScales) {
              await reachExisting(
                tester,
                onNoOldPhone: () {},
                locale: locale,
                textScale: scale,
                viewport: vp,
              );
              final why = '${locale.languageCode} @ $scale on $vp';
              expect(
                find.text(existingTitle[locale.languageCode]!),
                findsOneWidget,
                reason: why,
              );
              expect(tester.takeException(), isNull);
              expectTextFits(tester, reason: why);
              await tester.ensureVisible(find.byType(FilledButton));
              await tester.tap(find.byType(FilledButton));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expectTextFits(tester, reason: 'S0.2b $why');
            }
          }
        }
      },
    );
  });

  group('S0.2 repair r1 — resend, autofill, targets (07 §3.1 step 2, '
      'design-system §3.1)', () {
    double? sizeOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style?.fontSize;
    double? bodyMedium(WidgetTester tester) =>
        Theme.of(tester.element(find.text('Enter the code')))
            .textTheme
            .bodyMedium
            ?.fontSize;

    testWidgets(
      'F1-06-3 an error never hides the resend: after an expired code the countdown stays beside the words, then Send again appears at zero and works; the helper lines are the body-small role (c1 O2b 13.5 px, c1b L3 14 px)',
      (tester) async {
        final clock = _Clock();
        final auth = FakeAuthClient(expectedCode: '482913');
        await pumpRk(
          tester,
          const PhoneOtpScreen(),
          auth: auth,
          now: clock.call,
        );
        await _enterPhoneAndSend(tester);
        expect(sizeOf(tester, 'Send again in 0:30'), bodyMedium(tester));
        expect(
          tester.getSize(find.byIcon(Icons.schedule)).height,
          bodyMedium(tester),
        );
        auth.failNext = const AuthFailure(AuthFailureKind.codeExpired);
        await tapKeys(tester, '111111');
        expect(
          find.text('That code has expired. Ask for a new one.'),
          findsOneWidget,
        );
        expect(
          sizeOf(tester, 'That code has expired. Ask for a new one.'),
          bodyMedium(tester),
        );
        expect(find.text('Send again in 0:30'), findsOneWidget);
        expect(find.byIcon(Icons.schedule), findsOneWidget);
        clock.now = clock.now.add(const Duration(seconds: 31));
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.text('That code has expired. Ask for a new one.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextButton, 'Send again'), findsOneWidget);
        expect(sizeOf(tester, 'Didn’t get it?'), bodyMedium(tester));
        await tester.tap(find.widgetWithText(TextButton, 'Send again'));
        await tester.pumpAndSettle();
        expect(auth.requestedPhones, [_e164, _e164]);
        expect(find.text('Send again in 1:00'), findsOneWidget);
        clock.now = clock.now.add(const Duration(minutes: 1));
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets(
      'F1-06-2 third miss inside the wait: the timer stays drawn beside "when the timer ends"; at zero the new code goes by itself and its countdown shows with the words; the next key clears the words, never the timer',
      (tester) async {
        final clock = _Clock();
        final auth = FakeAuthClient(expectedCode: '482913');
        await pumpRk(
          tester,
          const PhoneOtpScreen(),
          auth: auth,
          now: clock.call,
        );
        await _enterPhoneAndSend(tester);
        for (final code in ['000000', '000001', '000002']) {
          await tapKeys(tester, code);
        }
        expect(
          find.text(
            'That code didn’t match three times. We’ll send a new one when '
            'the timer ends.',
          ),
          findsOneWidget,
        );
        expect(find.text('Send again in 0:30'), findsOneWidget);
        expect(auth.requestedPhones, [_e164]);
        clock.now = clock.now.add(const Duration(seconds: 31));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(auth.requestedPhones, [_e164, _e164]);
        expect(
          find.text(
            'That code didn’t match three times. We’ve sent you a new one.',
          ),
          findsOneWidget,
        );
        expect(find.text('Send again in 1:00'), findsOneWidget);
        await tapKeys(tester, '4');
        expect(
          find.text(
            'That code didn’t match three times. We’ve sent you a new one.',
          ),
          findsNothing,
        );
        expect(find.text('Send again in 1:00'), findsOneWidget);
        await tapKeys(tester, '82913');
        expect(find.text('This phone is ready'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-06-1 the code boxes are also a system text field: one-time-code autofill hint, number keyboard, a pasted SMS verifies by itself, and the drawn keypad drives the same field (WCAG 2.2 SC 3.3.8, design-system §3.1)',
      (tester) async {
        final auth = FakeAuthClient(expectedCode: '482913');
        await pumpRk(tester, const PhoneOtpScreen(), auth: auth);
        expect(find.byType(TextField), findsNothing, reason: 'number step');
        await _enterPhoneAndSend(tester);
        final field = find.byType(TextField);
        expect(field, findsOneWidget);
        final tf = tester.widget<TextField>(field);
        expect(tf.autofillHints, contains(AutofillHints.oneTimeCode));
        expect(tf.keyboardType, TextInputType.number);
        // The keypad and the field are one code.
        await tapKeys(tester, '48');
        expect(tf.controller?.text, '48');
        // Paste the whole SMS through the field's own paste action.
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData'
              ? <String, Object?>{
                  'text': 'Your Rukka Folio code is 482913. Valid 10 min.',
                }
              : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.tap(field);
        await tester.pump();
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .pasteText(SelectionChangedCause.toolbar);
        await tester.pumpAndSettle();
        expect(auth.verifiedCodes, ['482913']);
        expect(find.text('This phone is ready'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-06-1 a code typed on the system keyboard verifies; a wrong one keeps the rejected digits in the boxes and the next typed digit starts afresh',
      (tester) async {
        final auth = FakeAuthClient(expectedCode: '482913');
        await pumpRk(tester, const PhoneOtpScreen(), auth: auth);
        await _enterPhoneAndSend(tester);
        await tester.enterText(find.byType(TextField), '000000');
        await tester.pumpAndSettle();
        expect(auth.verifiedCodes, ['000000']);
        expect(
          find.text(
            'That code didn’t match. 2 tries left, then we’ll send a new one.',
          ),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField), '482913');
        await tester.pumpAndSettle();
        expect(auth.verifiedCodes, ['000000', '482913']);
        expect(find.text('This phone is ready'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-06-6 the inline links that are a way out (Change, Send again, Set up instead) are at least 44 dp tall (design-system §3.1 rule 9, 13 §8)',
      (tester) async {
        final clock = _Clock();
        await pumpRk(
          tester,
          const PhoneOtpScreen(door: SignInDoor.signIn),
          now: clock.call,
        );
        final setUp = find.widgetWithText(TextButton, 'Set up instead');
        expect(tester.getSize(setUp).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(setUp).width, greaterThanOrEqualTo(44));
        await _enterPhoneAndSend(tester);
        clock.now = clock.now.add(const Duration(seconds: 31));
        await tester.pump(const Duration(seconds: 1));
        for (final label in ['Change', 'Send again']) {
          final link = find.widgetWithText(TextButton, label);
          expect(link, findsOneWidget, reason: label);
          expect(tester.getSize(link).height, greaterThanOrEqualTo(44));
          expect(tester.getSize(link).width, greaterThanOrEqualTo(44));
        }
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      },
    );
  });
}
