// F1 widget tests for S0.9 Invitation accept — the joiner's side of the
// invite (13 §3.2 row S0.9, design O7a/O7b; 07 §12 🔒; 06 §7 🔒;
// ADR 2026-09-05d §2 and §9 🔒; 13 §5 flow F11).
//
// F1-07-89  the happy path: offer → Accept → own book now, shared books greyed
// F1-07-90  ADR 2026-09-05d §9 🔒 — ONE message for "not your number" and
//           "no such link", proven by comparing the whole rendered screen
// F1-07-91  the two refusals that are allowed their own names, each with a way out
// F1-07-92  the S0.9 variant: an uncertified device names nothing and asks nothing
// F1-07-93  every other state renders, and EN/PA/HI survive 200% on 360×800
// F1-07-94  no session yet → the OTP step of 13 §3.2's `accept → OTP → …`
@Tags(['F1'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/invitation_gateway.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_9_invitation_screen.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';

import '../../shared/test_app.dart';

const _locales = [Locale('en'), Locale('pa'), Locale('hi')];

/// Pumping a second screen of the same type into the same slot *updates* the
/// existing element, so `initState` — and with it the load — would not run
/// again. A fresh key per pump makes each situation a genuinely fresh S0.9.
int _pumpSeq = 0;

/// An offer over [books] shared books, expiring a week after the test clock
/// (06 §7's 7-day window). Nothing here is a real number or a real name
/// (CLAUDE.md rule 4).
InviteOffer _offer({String id = 'inv-1', int books = 2}) => InviteOffer(
  inviteId: id,
  tenantId: 'tenant-1',
  roles: [
    for (var i = 0; i < books; i++) {'book_id': 'book-$i', 'role': 'member'},
  ],
  expiresAt: testNow().add(const Duration(days: 7)),
  createdBy: 'user-admin',
);

/// A signed-in, certified device — the ordinary joiner (06 §3 step 4: a fresh
/// signup self-certifies immediately).
FakeAuthClient _certified() => FakeAuthClient(
  initial: const Active(
    AuthSession(userId: 'u-1', deviceId: 'd-1'),
    deviceCertified: true,
  ),
);

/// Signed in, but the device holds no certificate under the user's UMK — the
/// device of 13 §5 flow F11 that is shown nothing of the family.
FakeAuthClient _uncertified() => FakeAuthClient(
  initial: const Active(
    AuthSession(userId: 'u-1', deviceId: 'd-1'),
    deviceCertified: false,
  ),
);

Future<void> _pumpInvite(
  WidgetTester tester, {
  required InvitationGateway gateway,
  FakeAuthClient? auth,
  String? inviteId,
  Locale? locale,
  double textScale = 1,
  Size viewport = const Size(390, 1400),
}) async {
  await pumpRk(
    tester,
    InvitationGatewayScope(
      gateway: gateway,
      child: InvitationScreen(
        key: ValueKey('s0.9-${_pumpSeq++}'),
        inviteId: inviteId,
        onOpenMyBook: () {},
        onConfirmNumber: () {},
        onSetUpPhone: () {},
      ),
    ),
    auth: auth ?? _certified(),
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
}

/// Every non-empty string the screen is currently rendering. Used to prove a
/// *whole screen* is identical between two situations, not merely that one
/// expected sentence appears in both.
Set<String> _visibleText(WidgetTester tester) => {
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    if ((t.data ?? '').isNotEmpty) t.data!,
};

/// A gateway whose answer never arrives — the only honest way to hold S0.9 in
/// its loading state, since the harness settles every pump.
final class _SilentGateway implements InvitationGateway {
  @override
  Future<List<InviteOffer>> myInvites() =>
      Completer<List<InviteOffer>>().future;

  @override
  Future<String> acceptInvite(String inviteId) => Completer<String>().future;

  @override
  Future<List<PendingBook>> pendingBooks() async => const [];
}

void main() {
  group('S0.9 happy path (13 §3.2, 07 §12 🔒)', () {
    testWidgets('F1-07-89 accept → the personal book works immediately and the '
        'shared books are greyed with the 07 §12 line', (tester) async {
      final gateway = FakeInvitationGateway(
        offers: [_offer()],
        joined: const [
          PendingBook(name: 'Family pool', activateWithName: 'Sunita'),
        ],
      );
      await _pumpInvite(tester, gateway: gateway, inviteId: 'inv-1');

      // The offer names no tenant and no book — the server tells a phone that
      // has not joined neither (ADR 2026-09-05c §4, ADR 2026-09-05d §2 🔒).
      expect(find.text('You have been invited'), findsOneWidget);
      expect(find.text('2 shared books'), findsOneWidget);
      expect(find.textContaining('tenant-1'), findsNothing);
      expect(find.textContaining('Family pool'), findsNothing);

      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();

      // The id the deep link carried is what was accepted.
      expect(gateway.accepted, ['inv-1']);

      // 07 §12 🔒 / 06 §7 🔒 — own book now, shared book greyed, named person.
      expect(find.text('You are in'), findsOneWidget);
      expect(
        find.text('Your own book works right now. It waits for nobody.'),
        findsOneWidget,
      );
      expect(find.text('Family pool'), findsOneWidget);
      expect(find.text('Meet Sunita to activate'), findsOneWidget);
      // A dead end would be a success screen with no door (07 §1 rule 6).
      expect(find.text('Open my book'), findsOneWidget);
    });

    testWidgets('F1-07-89 with no meta pull yet the shared books are a count, '
        'never an invented name (07 §12 🔒)', (tester) async {
      final gateway = FakeInvitationGateway(offers: [_offer(books: 1)]);
      await _pumpInvite(tester, gateway: gateway);
      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();

      expect(find.text('1 shared book is waiting for you'), findsOneWidget);
      expect(
        find.text('Meet someone already in this book to activate'),
        findsOneWidget,
      );
    });
  });

  group('S0.9 refusals — ADR 2026-09-05d §9 🔒', () {
    testWidgets('F1-07-90 "not your number", "no such link" and "nothing '
        'addressed to this phone" render ONE identical screen', (tester) async {
      // 1. The server refused the accept by name.
      final refused = FakeInvitationGateway(offers: [_offer()])
        ..failNextList = const MembersFailure(
          'http 403',
          MembersRefusal.inviteNotForYou,
        );
      await _pumpInvite(tester, gateway: refused, inviteId: 'inv-1');
      final fromRefusal = _visibleText(tester);

      // 2. Nothing is addressed to this number at all.
      await _pumpInvite(tester, gateway: FakeInvitationGateway());
      final fromEmpty = _visibleText(tester);

      // 3. The link named an invite this phone was offered none of.
      await _pumpInvite(
        tester,
        gateway: FakeInvitationGateway(offers: [_offer()]),
        inviteId: 'inv-harvested',
      );
      final fromUnknownId = _visibleText(tester);

      // Byte-identical screens, exactly as the route answers with
      // byte-identical bodies (C-05d-9). Two messages here would make the
      // screen the oracle the route refuses to be.
      expect(fromEmpty, fromRefusal);
      expect(fromUnknownId, fromRefusal);
      expect(
        fromRefusal,
        contains('This invitation cannot be used on this phone'),
      );

      // And the screen says nothing about whether a link existed, whose it
      // was, or which number it went to.
      final joined = fromRefusal.join(' ').toLowerCase();
      for (final leak in [
        'expired',
        'already',
        'no such',
        'not found',
        'wrong number',
        'inv-1',
        'inv-harvested',
        'tenant-1',
      ]) {
        expect(joined, isNot(contains(leak)), reason: 'leaked "$leak"');
      }
    });

    testWidgets('F1-07-90 a refusal on accept lands on the same one message', (
      tester,
    ) async {
      final gateway = FakeInvitationGateway(offers: [_offer()])
        ..failNextAccept = const MembersFailure(
          'http 403',
          MembersRefusal.inviteNotForYou,
        );
      await _pumpInvite(tester, gateway: gateway);
      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();

      expect(
        find.text('This invitation cannot be used on this phone'),
        findsOneWidget,
      );
      // Still a door: the joiner's own book (07 §1 rule 6).
      expect(find.text('Use my own book'), findsOneWidget);
    });

    testWidgets('F1-07-91 expired and not-live each name their own cause and '
        'offer a way out (06 §7 🔒)', (tester) async {
      final expired = FakeInvitationGateway(offers: [_offer()])
        ..failNextList = const MembersFailure(
          'http 410',
          MembersRefusal.inviteExpired,
        );
      await _pumpInvite(tester, gateway: expired);
      expect(find.text('This invitation has run out'), findsOneWidget);
      expect(
        find.text(
          'Invitations last seven days. Ask whoever invited you to '
          'send it again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Use my own book'), findsOneWidget);

      final notLive = FakeInvitationGateway(offers: [_offer()])
        ..failNextList = const MembersFailure(
          'http 409',
          MembersRefusal.inviteNotLive,
        );
      await _pumpInvite(tester, gateway: notLive);
      expect(find.text('This link is no longer the live one'), findsOneWidget);
      expect(find.text('Use my own book'), findsOneWidget);

      // Neither is confused with the one message of §9.
      expect(
        find.text('This invitation cannot be used on this phone'),
        findsNothing,
      );
    });
  });

  group(
    'S0.9 variant — uncertified device (13 §5 F11, ADR 2026-09-05d §2 🔒)',
    () {
      testWidgets('F1-07-92 names no tenant, no book and no member, and never '
          'asks the server', (tester) async {
        final gateway = FakeInvitationGateway(
          offers: [_offer()],
          joined: const [
            PendingBook(name: 'Family pool', activateWithName: 'Sunita'),
          ],
        );
        await _pumpInvite(
          tester,
          gateway: gateway,
          auth: _uncertified(),
          inviteId: 'inv-1',
        );

        expect(find.text('This phone is not set up yet'), findsOneWidget);
        expect(find.text('Set up this phone'), findsOneWidget);

        // It asked nothing: an uncertified device is shown nothing of the
        // family, so there is nothing to ask for (C-06-19).
        expect(gateway.listCalls, 0);
        expect(gateway.accepted, isEmpty);

        // Nothing of the family appears, and — the easy mistake — it does not
        // even claim an invitation is waiting, because this device cannot know.
        final shown = _visibleText(tester).join(' ');
        for (final leak in [
          'Family pool',
          'Sunita',
          'tenant-1',
          'inv-1',
          'invited',
          'shared book',
        ]) {
          expect(shown, isNot(contains(leak)), reason: 'leaked "$leak"');
        }
      });
    },
  );

  group('S0.9 remaining states (13 §4.3, 07 §1)', () {
    testWidgets('F1-07-93 loading shows the ruled skeleton, never a blank', (
      tester,
    ) async {
      // An answer that never arrives: the screen stays in `checking`, which is
      // exactly the state a slow network puts it in.
      await _pumpInvite(tester, gateway: _SilentGateway());
      expect(find.text('Checking your invitation…'), findsOneWidget);
      // A skeleton, not a spinner (11 §4.5, 13 §4.2).
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('F1-07-93 offline and error both retry and both keep a door', (
      tester,
    ) async {
      final offline = FakeInvitationGateway(
        offers: [_offer()],
      )..failNextList = const MembersFailure('offline', MembersRefusal.offline);
      await _pumpInvite(tester, gateway: offline);
      expect(find.text('No connection'), findsOneWidget);
      expect(find.text('Use my own book'), findsOneWidget);

      // Retry succeeds — the one-shot failure has cleared.
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('You have been invited'), findsOneWidget);

      final broken = FakeInvitationGateway(offers: [_offer()])
        ..failNextList = const MembersFailure('http 500');
      await _pumpInvite(tester, gateway: broken);
      expect(find.text('We could not check your invitation'), findsOneWidget);
      // Named cause and a retry, never a raw code (07 §1 rule 12).
      expect(find.textContaining('500'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('F1-07-94 no session yet → the OTP step of 13 §3.2, and the '
        'server is not asked', (tester) async {
      final gateway = FakeInvitationGateway(offers: [_offer()]);
      await _pumpInvite(
        tester,
        gateway: gateway,
        auth: FakeAuthClient(),
        inviteId: 'inv-1',
      );
      expect(find.text('Confirm your number first'), findsOneWidget);
      expect(find.text('Confirm my number'), findsOneWidget);
      expect(gateway.listCalls, 0);
    });

    testWidgets('F1-07-93 EN, PA and HI all resolve at 200% on 360x800 with '
        'no overflow', (tester) async {
      for (final locale in _locales) {
        for (final gateway in [
          FakeInvitationGateway(offers: [_offer()]),
          FakeInvitationGateway(),
          FakeInvitationGateway(offers: [_offer()])
            ..failNextList = const MembersFailure(
              'http 410',
              MembersRefusal.inviteExpired,
            ),
        ]) {
          await _pumpInvite(
            tester,
            gateway: gateway,
            locale: locale,
            textScale: 2,
            viewport: const Size(360, 800),
          );
          expect(tester.takeException(), isNull, reason: 'overflow in $locale');
          // Nothing fell back to a missing-key blank.
          expect(_visibleText(tester), isNotEmpty, reason: 'empty in $locale');
        }
      }
    });

    testWidgets('F1-07-93 the accepted state also survives PA and HI at 200%', (
      tester,
    ) async {
      for (final locale in _locales) {
        await _pumpInvite(
          tester,
          gateway: FakeInvitationGateway(
            offers: [_offer()],
            joined: const [
              PendingBook(name: 'Saanjha khaata', activateWithName: 'Sunita'),
            ],
          ),
          locale: locale,
          textScale: 2,
          viewport: const Size(360, 800),
        );
        await tester.ensureVisible(find.byType(FilledButton).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton).first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Saanjha khaata'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'overflow in $locale');
        expect(find.text('Saanjha khaata'), findsOneWidget);
      }
    });
  });
}
