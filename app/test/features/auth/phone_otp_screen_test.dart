@Tags(['F1'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart';
import 'package:rukka_folio/features/auth/phone_shape.dart';
import 'package:rukka_folio/features/auth/screens/s0_2_phone_otp_screen.dart';
import 'package:rukka_folio/features/auth/screens/s19_1_update_required_screen.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

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
  Future<void> requestOtp(String phone) async {
    await super.requestOtp(phone);
    _channel.value = OtpChannel.sms;
  }
}

/// The typed number, from the reserved test block (ADR 2026-09-05i §7).
const _typed = '9999900001'; // +91 99999 00001
const _e164 = '+91$_typed';

/// The first synthetic demo number (dev project, owner-directed 4 Oct 2026).
const _demo = '5000001001';

Future<void> _enterPhoneAndSend(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), _typed);
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
}

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
          find.text('+91 '),
          findsOneWidget,
        ); // fixed country prefix beside the field
        await _enterPhoneAndSend(tester);
        expect(auth.requestedPhones, [_e164]);
        expect(find.text('Enter the code'), findsOneWidget);
        expect(find.text('Sent to $_e164'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '482913');
        await tester.tap(find.text('Verify'));
        await tester.pumpAndSettle();
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
      'F1-06-2 wrong code shows attempts left, the third miss says the code expired and asks for a new one; the phone stays on screen (no dead end)',
      (tester) async {
        final auth = FakeAuthClient(expectedCode: '482913');
        await pumpRk(tester, const PhoneOtpScreen(), auth: auth);
        await _enterPhoneAndSend(tester);
        for (final (code, expected) in [
          ('000000', 'That code didn’t match. 2 tries left.'),
          ('000001', 'That code didn’t match. 1 try left.'),
          ('000002', 'That code has expired. Ask for a new one.'),
        ]) {
          await tester.enterText(find.byType(TextField), code);
          await tester.tap(find.text('Verify'));
          await tester.pumpAndSettle();
          expect(find.text(expected), findsOneWidget);
        }
        expect(find.text('Change number'), findsOneWidget);
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
        expect(find.text('Send again in 30 s'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Send again in 30 s'),
              )
              .onPressed,
          isNull,
        );
        clock.now = clock.now.add(const Duration(seconds: 29));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Send again in 1 s'), findsOneWidget);
        clock.now = clock.now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Send again'), findsOneWidget);
        await tester.tap(find.text('Send again'));
        await tester.pumpAndSettle();
        expect(auth.requestedPhones, hasLength(2));
        expect(find.text('Send again in 60 s'), findsOneWidget);
        // Drain the periodic timer.
        clock.now = clock.now.add(const Duration(seconds: 60));
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets(
      'F1-06-4 offline: quiet chip, Send disabled with the reason, nothing blocking; rate-limited and unavailable failures read generic',
      (tester) async {
        final sync = FakeSyncClient(initial: const Offline());
        final auth = FakeAuthClient();
        await pumpRk(tester, const PhoneOtpScreen(), auth: auth, sync: sync);
        expect(
          find.text('Offline — you need internet for the code.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send code'),
              )
              .onPressed,
          isNull,
        );
        sync.current = const Synced();
        await tester.pumpAndSettle();
        auth.failNext = const AuthFailure(AuthFailureKind.rateLimited);
        await _enterPhoneAndSend(tester);
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
      'F1-06-6 client-side validation refuses a short number before any request; strings resolve in PA and HI without overflow at 200 %',
      (tester) async {
        final auth = FakeAuthClient();
        await pumpRk(tester, const PhoneOtpScreen(), auth: auth);
        await tester.enterText(find.byType(TextField), '98765');
        await tester.tap(find.text('Send code'));
        await tester.pumpAndSettle();
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
          await tester.enterText(find.byType(TextField), _demo);
          await tester.tap(find.text('Send code'));
          await tester.pumpAndSettle();
          expect(
            find.text('Enter the 10-digit mobile number.'),
            findsOneWidget,
          );
          expect(auth.requestedPhones, isEmpty);

          await tester.enterText(find.byType(TextField), _typed);
          await tester.tap(find.text('Send code'));
          await tester.pumpAndSettle();
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
          await tester.enterText(find.byType(TextField), _demo);
          await tester.tap(find.text('Send code'));
          await tester.pumpAndSettle();
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
          // Phone step: the screen is drawn and names SMS, not WhatsApp.
          expect(find.text(_title[lang]!), findsOneWidget, reason: lang);
          expect(find.text(hint[lang]!), findsOneWidget, reason: lang);
          expect(find.textContaining('WhatsApp'), findsNothing, reason: lang);

          await tester.enterText(find.byType(TextField), _typed);
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          // Code step reached through the seam, and no channel line at all.
          expect(auth.requestedPhones, [_e164], reason: lang);
          expect(auth.otpChannel.value, OtpChannel.sms, reason: lang);
          expect(find.textContaining(_e164), findsOneWidget, reason: lang);
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
}
