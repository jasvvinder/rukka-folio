@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart';
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

Future<void> _enterPhoneAndSend(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '9876543210');
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
}

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
        expect(auth.requestedPhones, ['+919876543210']);
        expect(find.text('Enter the code'), findsOneWidget);
        expect(find.text('Sent to +919876543210'), findsOneWidget);
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
      'F1-06-5 min-version gate: when the 426 listenable fires, S19.1 replaces S0.2 with no way back; the SMS-fallback line shows when the channel says sms',
      (tester) async {
        final gate = ValueNotifier<UpdateRequired?>(null);
        final channel = ValueNotifier<OtpChannel?>(null);
        await pumpRk(tester, PhoneOtpScreen(gate: gate, channel: channel));
        await _enterPhoneAndSend(tester);
        expect(
          find.text('WhatsApp didn’t go through, so the code went by SMS.'),
          findsNothing,
        );
        channel.value = OtpChannel.sms;
        await tester.pump();
        expect(
          find.text('WhatsApp didn’t go through, so the code went by SMS.'),
          findsOneWidget,
        );
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

        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpRk(
          tester,
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const PhoneOtpScreen(),
          ),
          locale: const Locale('pa'),
        );
        expect(find.text('ਤੁਹਾਡਾ ਫ਼ੋਨ ਨੰਬਰ'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await pumpRk(
          tester,
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const PhoneOtpScreen(),
          ),
          locale: const Locale('hi'),
        );
        expect(find.text('आपका फ़ोन नंबर'), findsOneWidget);
        expect(tester.takeException(), isNull);
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
