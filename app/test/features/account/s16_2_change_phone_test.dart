@Tags(['F1'])
library;

// S16.2 Change phone number — **OTP old + new, or trusted-member approval when
// the old number is lost** (06 §9.4 🔒, 07 §21 🔒, 13 §3.2 row S16.2,
// ADR 2026-09-05d §1 🔒).
//
// Tests first. Two things are held hardest here, because they are the two a
// build could quietly get wrong and still look right:
//
//  * **06 §9.4 🔒 is an `and`.** The new number's code is required on *both*
//    routes; k approvals alone never finish the change (F1-07-368).
//  * **The lost-number route is never hidden.** A user with no trusted members
//    is told why and told where to fix it, in a row that stays on screen
//    (F1-07-364) — the dead end 07 §1 rule 6 forbids is exactly the one a
//    disappearing row would create.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/account/phone_change.dart';
import 'package:rukka_folio/features/account/screens/s16_2_change_phone_screen.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

PhoneChangeAttempt _start({
  int trustedMembers = 3,
  bool otherDevice = true,
  String phone = '+91 98765 43210',
}) => PhoneChangeAttempt(
  currentNumber: phone,
  trustedMemberCount: trustedMembers,
  hasOtherActiveDevice: otherDevice,
);

Widget _screen(
  PhoneChange seam, {
  VoidCallback? onDone,
  VoidCallback? onSetUp,
  void Function(TrustedApprover)? onCall,
}) => PhoneChangeScope(
  phoneChange: seam,
  child: ChangePhoneScreen(
    key: UniqueKey(),
    onDone: onDone,
    onSetUpTrustedMembers: onSetUp,
    onCall: onCall,
  ),
);

Finder get _otp => find.byKey(const Key('account.change.otp'));
Finder get _lost => find.byKey(const Key('account.change.lost'));
Finder get _code => find.byKey(const Key('account.change.code'));
Finder get _verify => find.byKey(const Key('account.change.verify'));
Finder get _newNumber => find.byKey(const Key('account.change.newnumber'));
Finder get _send => find.byKey(const Key('account.change.send'));
Finder get _cancel => find.byKey(const Key('account.change.cancel'));
Finder get _rule => find.byKey(const Key('account.change.rule'));

/// Walks the OTP route as far as the new-number step, which several tests
/// need before they can assert anything about the second half.
Future<void> _proveOldNumber(WidgetTester tester) async {
  await tester.tap(_otp);
  await tester.pumpAndSettle();
  await tester.enterText(_code, '123456');
  await tester.tap(_verify);
  await tester.pumpAndSettle();
}

void main() {
  group('S16.2 Change phone number (06 §9.4 🔒, 13 §3.2 row S16.2)', () {
    testWidgets(
      'F1-07-360 the first step offers both routes of 06 §9.4 🔒 side by side, '
      'says what does not change (keys, books, the people you share with), '
      'and promises the old number its plain notice before anything starts',
      (tester) async {
        final seam = FakePhoneChange(initial: _start());
        addTearDown(seam.dispose);
        await pumpRk(tester, _screen(seam), viewport: rkPhone360);

        expect(find.text('Change phone number'), findsOneWidget);
        expect(find.text('+91 98765 43210'), findsOneWidget);
        expect(_otp, findsOneWidget);
        expect(_lost, findsOneWidget);
        expect(
          find.textContaining(
            'Your books, keys and family stay exactly as they are',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('your old number gets a plain message'),
          findsOneWidget,
        );
        // Nothing has been asked of the server merely by opening the screen.
        expect(seam.oldSends, 0);
        expect(seam.asks, 0);
      },
    );

    testWidgets(
      'F1-07-361 the OTP route: a code goes to the old number, a wrong code '
      'says how many tries are left (06 §2) and the right one moves on — the '
      'screen never claims the change is done',
      (tester) async {
        final seam = FakePhoneChange(initial: _start())
          ..expectedCode = '123456';
        addTearDown(seam.dispose);
        await pumpRk(tester, _screen(seam), viewport: rkPhone360);

        await tester.tap(_otp);
        await tester.pumpAndSettle();
        expect(seam.oldSends, 1);
        expect(
          find.textContaining('Code sent to +91 98765 43210'),
          findsOneWidget,
        );

        await tester.enterText(_code, '000000');
        await tester.tap(_verify);
        await tester.pumpAndSettle();
        expect(find.text('That code is wrong. 2 tries left.'), findsOneWidget);
        expect(find.text('Your number is changed'), findsNothing);

        await tester.enterText(_code, '123456');
        await tester.tap(_verify);
        await tester.pumpAndSettle();
        expect(seam.oldCodes, ['000000', '123456']);
        // Proved, but NOT done — 06 §9.4 🔒 still wants the new number.
        expect(find.text('Your new number'), findsOneWidget);
        expect(find.text('Your number is changed'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-362 the new number is checked before the server is troubled: a '
      'short number and the number already on the record are both refused '
      'with a reason, and the number that reaches the seam is E.164',
      (tester) async {
        final seam = FakePhoneChange(initial: _start());
        addTearDown(seam.dispose);
        await pumpRk(tester, _screen(seam), viewport: rkPhone360);
        await _proveOldNumber(tester);

        await tester.enterText(_newNumber, '98765');
        await tester.tap(_send);
        await tester.pumpAndSettle();
        expect(find.text('Enter a 10-digit mobile number.'), findsOneWidget);
        expect(seam.newNumbers, isEmpty);

        await tester.enterText(_newNumber, '9876543210');
        await tester.tap(_send);
        await tester.pumpAndSettle();
        expect(find.text('That is already your number.'), findsOneWidget);
        expect(seam.newNumbers, isEmpty);

        await tester.enterText(_newNumber, '9123456780');
        await tester.tap(_send);
        await tester.pumpAndSettle();
        expect(seam.newNumbers, ['+919123456780']);
      },
    );

    testWidgets(
      'F1-07-363 the OTP route finishes: the new number proves itself, the '
      'record shows it, and the closing copy repeats 06 §9.4 🔒 — keys, books '
      'and members were never touched',
      (tester) async {
        final seam = FakePhoneChange(initial: _start());
        addTearDown(seam.dispose);
        var done = 0;
        await pumpRk(
          tester,
          _screen(seam, onDone: () => done++),
          viewport: rkPhone360,
        );
        await _proveOldNumber(tester);
        await tester.enterText(_newNumber, '9123456780');
        await tester.tap(_send);
        await tester.pumpAndSettle();

        await tester.enterText(_code, '654321');
        await tester.tap(_verify);
        await tester.pumpAndSettle();

        expect(seam.newCodes, ['654321']);
        expect(find.text('Your number is changed'), findsOneWidget);
        expect(find.text('+919123456780'), findsOneWidget);
        expect(find.textContaining('Sign in with this number'), findsOneWidget);
        expect(
          find.textContaining('the people you share with did not change'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('account.change.done')));
        await tester.pumpAndSettle();
        expect(done, 1);
      },
    );

    testWidgets('F1-07-364 with no trusted members the lost-number route is '
        'disabled-with-reason and stays on screen with the way to fix it '
        '(13 §4.3, 07 §1 rule 6 🔒) — never hidden, never a dead tap', (
      tester,
    ) async {
      final seam = FakePhoneChange(initial: _start(trustedMembers: 0));
      addTearDown(seam.dispose);
      var setUp = 0;
      await pumpRk(
        tester,
        _screen(seam, onSetUp: () => setUp++),
        viewport: rkPhone360,
      );

      expect(_lost, findsOneWidget);
      expect(
        find.text('You have not set up any trusted members yet.'),
        findsOneWidget,
      );
      await tester.tap(_lost);
      await tester.pumpAndSettle();
      expect(seam.asks, 0, reason: 'a disabled route may not reach the seam');

      await tester.ensureVisible(find.text('Set up trusted members'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set up trusted members'));
      await tester.pumpAndSettle();
      expect(setUp, 1);
    });

    testWidgets(
      'F1-07-365 the lost-number route draws the ask in the ladder’s own '
      'words: named rows with where each person stands, the tally counted '
      'from those rows, and the determinate rule — never a spinner, never a '
      'percentage (11 §4.5 🔒)',
      (tester) async {
        final seam = FakePhoneChange.asking(
          expiresAt: testNow().add(const Duration(hours: 60)),
        );
        addTearDown(seam.dispose);
        await pumpRk(
          tester,
          _screen(seam, onCall: (_) {}),
          viewport: rkPhone360,
        );

        expect(find.text('Waiting for your trusted members'), findsOneWidget);
        expect(find.text('Sunita'), findsOneWidget);
        expect(find.text('Approved'), findsOneWidget);
        expect(find.text('Harjit'), findsOneWidget);
        expect(find.text('Waiting…'), findsOneWidget);
        expect(find.text('Balwinder'), findsOneWidget);
        expect(find.text('Not asked'), findsOneWidget);

        // The tally is 1 of 2 and it was counted, not read off a counter.
        expect(find.text('1 of 2 approvals'), findsOneWidget);
        final bar = tester.widget<LinearProgressIndicator>(
          find.descendant(
            of: _rule,
            matching: find.byType(LinearProgressIndicator),
          ),
        );
        expect(bar.value, closeTo(0.5, 0.001));

        // Balwinder has no number in the book, so no row pretends to dial.
        // Two of the three have a number in the book; Balwinder does not, so
        // exactly two rows offer to dial and the third pretends nothing.
        expect(find.text('Call'), findsNWidgets(2));
      },
    );

    testWidgets(
      'F1-07-366 the 24 h window of ADR 2026-09-05d §1 🔒 is stated as '
      'protection, with whole hours left, and the one-tap Cancel is on this '
      'device too — cancelling changes nothing',
      (tester) async {
        final seam = FakePhoneChange.asking(
          waitUntil: testNow().add(const Duration(hours: 19, minutes: 30)),
        );
        addTearDown(seam.dispose);
        final a = seam.current!;
        final r = a.request!;
        seam.emit(
          a.copyWith(
            request: TrustedApprovalRequest(
              requestId: r.requestId,
              k: r.k,
              n: r.n,
              approvers: r.approvers,
              state: RecoveryAttemptState.waiting24h,
              waitUntil: r.waitUntil,
            ),
          ),
        );
        await pumpRk(tester, _screen(seam), viewport: rkPhone360);

        expect(find.text('Waiting 24 hours, for safety'), findsOneWidget);
        expect(find.text('About 19 hours left'), findsOneWidget);
        await tester.scrollUntilVisible(_cancel, 200);
        await tester.pumpAndSettle();
        expect(_cancel, findsOneWidget);

        await tester.tap(_cancel);
        await tester.pumpAndSettle();
        expect(seam.cancels, 1);
        expect(seam.current!.currentNumber, '+91 98765 43210');
        expect(find.text('Your number is changed'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-367 a closed ask claims neither a refusal nor a lapse — 03 §2.2 '
      'has no denied value, so the two are the same thing — and it still '
      'offers the way to start again',
      (tester) async {
        final seam = FakePhoneChange.asking();
        addTearDown(seam.dispose);
        final a = seam.current!;
        final r = a.request!;
        seam.emit(
          a.copyWith(
            request: TrustedApprovalRequest(
              requestId: r.requestId,
              k: r.k,
              n: r.n,
              approvers: r.approvers,
              state: RecoveryAttemptState.expired,
            ),
          ),
        );
        await pumpRk(tester, _screen(seam), viewport: rkPhone360);

        expect(
          find.textContaining('This request is closed and nothing changed'),
          findsOneWidget,
        );
        expect(find.textContaining('refused'), findsNothing);
        expect(find.textContaining('Said no'), findsNothing);
        await tester.tap(find.byKey(const Key('account.change.back')));
        await tester.pumpAndSettle();
        expect(_otp, findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-368 06 §9.4 🔒 is an `and`: trusted-member approval replaces the '
      'OLD number’s code and nothing else — the new number still proves '
      'itself before the record changes',
      (tester) async {
        final seam = FakePhoneChange.asking();
        addTearDown(seam.dispose);
        await pumpRk(tester, _screen(seam), viewport: rkPhone360);

        // The server carries the approved ask through its wait and reports the
        // old number proved. That is the most a k-of-n ask may ever do.
        seam.emit(
          seam.current!.copyWith(stage: PhoneChangeStage.oldNumberProved),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your new number'), findsOneWidget);
        expect(find.text('Your number is changed'), findsNothing);

        await tester.enterText(_newNumber, '9123456780');
        await tester.tap(_send);
        await tester.pumpAndSettle();
        expect(_code, findsOneWidget);
        expect(find.text('Your number is changed'), findsNothing);

        await tester.enterText(_code, '111111');
        await tester.tap(_verify);
        await tester.pumpAndSettle();
        expect(seam.newCodes, ['111111']);
        expect(find.text('Your number is changed'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-369 offline is quiet and non-blocking (07 §1 rule 7 🔒): the '
      'screen still reads, the chip says when this becomes possible, and the '
      'routes that need the server are disabled rather than throwing',
      (tester) async {
        final seam = FakePhoneChange(initial: _start());
        addTearDown(seam.dispose);
        final sync = FakeSyncClient(initial: const Offline());
        await pumpRk(tester, _screen(seam), sync: sync, viewport: rkPhone360);

        expect(
          find.textContaining('You can start this the moment you are back'),
          findsOneWidget,
        );
        expect(find.text('+91 98765 43210'), findsOneWidget);
        await tester.tap(_otp);
        await tester.pumpAndSettle();
        expect(seam.oldSends, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'F1-07-370 the loading and error states of 13 §4.3: a ruled skeleton '
      'announced in words, then a named cause with a retry beside it — never '
      'a raw code (07 §1 rule 12)',
      (tester) async {
        final seam = FakePhoneChange(initial: null)..failRefresh = true;
        addTearDown(seam.dispose);
        await pumpRk(tester, _screen(seam), viewport: rkPhone360);
        await tester.pump();

        expect(find.text('Couldn’t check this change.'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);

        seam.failRefresh = false;
        seam.emit(_start());
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(_otp, findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-371 EN, ਪੰਜਾਬੀ and हिन्दी fit every step at 130 % and 200 % on '
      '360×800 and 375×667',
      (tester) async {
        final stages = <PhoneChangeAttempt>[
          _start(),
          _start().copyWith(stage: PhoneChangeStage.codeSentToOld),
          FakePhoneChange.asking(
            waitUntil: testNow().add(const Duration(hours: 20)),
            expiresAt: testNow().add(const Duration(hours: 60)),
          ).current!,
          _start().copyWith(stage: PhoneChangeStage.oldNumberProved),
          _start().copyWith(
            stage: PhoneChangeStage.done,
            currentNumber: '+919123456780',
          ),
        ];
        for (final attempt in stages) {
          for (final locale in rkLocales) {
            for (final size in rkPhones) {
              for (final scale in rkTextScales) {
                final seam = FakePhoneChange(initial: attempt);
                addTearDown(seam.dispose);
                await pumpRk(
                  tester,
                  _screen(seam, onSetUp: () {}, onCall: (_) {}),
                  locale: locale,
                  textScale: scale,
                  viewport: size,
                );
                expect(tester.takeException(), isNull);
                expectTextFits(
                  tester,
                  reason:
                      'S16.2 ${attempt.stage.name} ${locale.languageCode} '
                      '@$scale ${size.width.toInt()}',
                );
              }
            }
          }
        }
      },
    );
  });
}
