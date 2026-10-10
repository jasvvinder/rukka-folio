@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/phone_shape.dart'
    show debugDemoPhonesOverride;
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/screens/s9_1_invite_screen.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

/// Synthetic numbers only (check_purity): the ten digits typed behind
/// S9.1's fixed +91, and the dev demo range (desk 116).
const _mobile = '9999900011'; // +91 99999 00011
const _e164 = '+91$_mobile';
const _demo = '5000001001'; // the dev demo range, never a real mobile

final _books = [
  const TenantBook(id: 'b-home', name: 'Ghar'),
  const TenantBook(id: 'b-shop', name: 'Shop'),
];

MembersSnapshot _snapshot(TenantType type) => MembersSnapshot(
  tenantType: type,
  books: _books,
  yourRoles: const {'b-home': BookRole.admin, 'b-shop': BookRole.admin},
);

Widget _scoped(MembersRepository repo, Widget child) =>
    MembersRepositoryScope(repository: repo, child: child);

void main() {
  group('S9.1 Invite member (13 §3.2, 07 §12, 06 §1.0/§1.1/§7)', () {
    testWidgets('F1-07-26 the three steps in order — phone, per-book role + limit grid, '
        'designation — with the 06 §1.0 🔒 line word for word and the 7-day, '
        'this-number-only expiry stated', (tester) async {
      final repo = FakeMembersRepository(
        initial: _snapshot(TenantType.organization),
      );
      await pumpRk(
        tester,
        _scoped(repo, const InviteScreen()),
        viewport: rkTallViewport,
      );
      expect(find.text('Invite someone'), findsOneWidget);
      expect(find.text('Their phone number'), findsOneWidget);
      expect(find.text('What they can do'), findsOneWidget);
      expect(find.text('Role in Ghar'), findsOneWidget);
      expect(find.text('Role in Shop'), findsOneWidget);
      expect(find.text('What they’re called'), findsOneWidget);
      expect(find.text('This one is optional.'), findsOneWidget);
      expect(
        find.text('A name, not a permission — what they can do is set above.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The invite works for 7 days, and only on a phone with that number.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'F1-07-26 the designation suggestions are the 01 §2 table for the tenant '
      'type — organisation, business, and a family, which 01 §2 gives no table '
      'and so is offered only the free field',
      (tester) async {
        final org = FakeMembersRepository(
          initial: _snapshot(TenantType.organization),
        );
        await pumpRk(
          tester,
          _scoped(org, const InviteScreen()),
          viewport: rkTallViewport,
        );
        expect(find.widgetWithText(ChoiceChip, 'President'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Treasurer'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Auditor'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Accountant'), findsNothing);

        final business = FakeMembersRepository(
          initial: _snapshot(TenantType.businessGroup),
        );
        await pumpRk(
          tester,
          _scoped(business, InviteScreen(key: UniqueKey())),
          viewport: rkTallViewport,
        );
        expect(find.widgetWithText(ChoiceChip, 'Accountant'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Partner'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'President'), findsNothing);

        final family = FakeMembersRepository(
          initial: _snapshot(TenantType.family),
        );
        await pumpRk(
          tester,
          _scoped(family, InviteScreen(key: UniqueKey())),
          viewport: rkTallViewport,
        );
        expect(find.text('Type the name your family uses.'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'President'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-26 a picked role states its capability in plain words and only a '
      'role that can post is offered a limit (06 §1.0 verbs table, 13 §2.4)',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _snapshot(TenantType.organization),
        );
        await pumpRk(
          tester,
          _scoped(repo, const InviteScreen()),
          viewport: rkTallViewport,
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Operator').first);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Posts entries up to their limit; sees day totals, not profit.',
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TextField, 'Limit in rupees (optional)'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(ChoiceChip, 'Viewer').first);
        await tester.pumpAndSettle();
        expect(find.text('Can look and export, cannot post.'), findsOneWidget);
        expect(
          find.widgetWithText(TextField, 'Limit in rupees (optional)'),
          findsNothing,
        );
      },
    );

    testWidgets('F1-07-26 Send reaches the repository with the +91 E.164 number, one grant '
        'per book and the limit as integer paise; the designation travels as a '
        'label only', (tester) async {
      final repo = FakeMembersRepository(
        initial: _snapshot(TenantType.organization),
      );
      var sent = 0;
      await pumpRk(
        tester,
        _scoped(repo, InviteScreen(onSent: () => sent++)),
        viewport: rkTallViewport,
      );
      await tester.enterText(find.byType(TextField).first, _mobile);
      // Ghar → Head with a ₹2,000 limit; Shop stays "No access".
      await tester.tap(find.widgetWithText(ChoiceChip, 'Head').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Limit in rupees (optional)'),
        '2000',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Treasurer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();

      final req = repo.invites.single;
      expect(req.phoneE164, _e164);
      expect(req.grants.length, 1);
      expect(req.grants.single.bookId, 'b-home');
      expect(req.grants.single.role, BookRole.head);
      expect(req.grants.single.autoPostLimitPaise, 200000);
      expect(req.designationLabel, 'Treasurer');
      // ADR 2026-09-25 §2: the inviter still has to send it, so S9.1 stays
      // on the share panel and returns to S9 on *Done* — not on creation.
      expect(sent, 0);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(sent, 1);
    });

    testWidgets('F1-07-26 a typed designation is kept as typed (01 §2 🔒: any name may be '
        'typed free) and nothing is sent without a ten-digit mobile number or '
        'without one role', (tester) async {
      final repo = FakeMembersRepository(initial: _snapshot(TenantType.family));
      await pumpRk(
        tester,
        _scoped(repo, const InviteScreen()),
        viewport: rkTallViewport,
      );
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter their 10-digit mobile number, like 98765 43210.'),
        findsOneWidget,
      );
      expect(
        find.text('Give them a role in at least one book.'),
        findsOneWidget,
      );
      expect(repo.invites, isEmpty);

      await tester.enterText(find.byType(TextField).first, _mobile);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Member').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Bhua ji');
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();
      expect(repo.invites.single.designationLabel, 'Bhua ji');
    });

    testWidgets(
      'F1-07-26 a failed send keeps the form filled and says so (13 §8 — an '
      'interruption never discards work)',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _snapshot(TenantType.organization),
        )..failNext = const MembersFailure('server said no');
        await pumpRk(
          tester,
          _scoped(repo, const InviteScreen()),
          viewport: rkTallViewport,
        );
        await tester.enterText(find.byType(TextField).first, _mobile);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Member').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send invite'));
        await tester.pumpAndSettle();
        expect(
          find.text('Couldn’t send that invite. Try again.'),
          findsOneWidget,
        );
        expect(find.text(_mobile), findsOneWidget);
        expect(find.text('Send invite'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-26 a refusal is named, not generic: the number, the permission '
      'and the connection each get the words that say what to do next '
      '(07 §1 rule 6 — no dead ends)',
      (tester) async {
        for (final (reason, message) in <(MembersRefusal, String)>[
          (
            MembersRefusal.badPhone,
            'Enter their 10-digit mobile number, like 98765 43210.',
          ),
          (
            MembersRefusal.notAdmin,
            'Only an admin can invite people, change roles or set limits.',
          ),
          (
            MembersRefusal.offline,
            'You’re offline. An invite needs one connection — try again when you’re back.',
          ),
          (MembersRefusal.server, 'Couldn’t send that invite. Try again.'),
        ]) {
          final repo = FakeMembersRepository(
            initial: _snapshot(TenantType.organization),
          )..failNext = MembersFailure('refused', reason);
          await pumpRk(
            tester,
            // A fresh key per case: the same widget type would otherwise
            // reuse the previous State, and with it the previous message.
            _scoped(repo, InviteScreen(key: ValueKey(reason))),
            viewport: rkTallViewport,
          );
          await tester.enterText(find.byType(TextField).first, _mobile);
          await tester.tap(find.widgetWithText(ChoiceChip, 'Member').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Send invite'));
          await tester.pumpAndSettle();
          expect(find.text(message), findsOneWidget, reason: reason.name);
        }
      },
    );

    testWidgets(
      'F1-07-26 offline: Send is disabled and the reason is stated — the '
      'invite is created on the server (ADR 2026-09-25 §2), so this one '
      'action needs a connection',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _snapshot(TenantType.organization),
        );
        await pumpRk(
          tester,
          _scoped(repo, const InviteScreen()),
          sync: FakeSyncClient(initial: const Offline()),
          viewport: rkTallViewport,
        );
        expect(
          find.text(
            'You’re offline. An invite needs one connection — try again when '
            'you’re back.',
          ),
          findsOneWidget,
        );
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Send invite'),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets(
      'F1-196-5 S9.1 over a held engine (Offline underneath): no offline '
      'line and Send is not disabled by the hold; once registered, a real '
      'Offline states its reason and disables Send (ADR 2026-10-10 §2 🔒)',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _snapshot(TenantType.organization),
        );
        final sync = FakeSyncClient(initial: const Offline(), held: true);
        addTearDown(sync.dispose);
        await pumpRk(
          tester,
          _scoped(repo, const InviteScreen()),
          sync: sync,
          viewport: rkTallViewport,
        );
        const line =
            'You’re offline. An invite needs one connection — try again when '
            'you’re back.';
        FilledButton send() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Send invite'),
        );
        expect(find.text(line), findsNothing);
        expect(send().onPressed, isNotNull);

        sync.held = false;
        await tester.pumpAndSettle();
        expect(find.text(line), findsOneWidget);
        expect(send().onPressed, isNull);
      },
    );

    for (final locale in rkLocales) {
      for (final scale in rkTextScales) {
        testWidgets('F1-07-26 S9.1 holds at ${scale}x text on 360×800 in '
            '${locale.languageCode} — every string resolves, nothing is cut', (
          tester,
        ) async {
          final repo = FakeMembersRepository(
            initial: _snapshot(TenantType.organization),
          );
          await pumpRk(
            tester,
            _scoped(repo, const InviteScreen()),
            locale: locale,
            textScale: scale,
            viewport: rkPhone360,
          );
          expect(tester.takeException(), isNull);
          expectTextFits(tester, reason: '$locale @ $scale');
          // Every step, not only the first screenful.
          for (var i = 0; i < 8; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -400));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expectTextFits(tester, reason: '$locale @ $scale scrolled $i');
          }
        });
      }
    }
  });

  // Desk 116 (owner-ruled 4 Oct 2026): S9.1 takes a number the way S0.2 and
  // S16.2 do — ten national digits behind a fixed +91 — through the one shared
  // predicate (`isNationalPhoneShape`, features/auth/phone_shape.dart), so a
  // release build can never invite a `+91 5…` demo number.
  group('S9.1 the invite number has the national shape S0.2 and S16.2 use '
      '(desk 116)', () {
    const invalid = 'Enter their 10-digit mobile number, like 98765 43210.';

    Future<FakeMembersRepository> typeAndSend(
      WidgetTester tester,
      String typed, {
      bool releaseMode = false,
    }) async {
      final repo = FakeMembersRepository(
        initial: _snapshot(TenantType.organization),
      );
      await pumpRk(
        tester,
        // A fresh key per case, or the previous case's State is reused.
        _scoped(repo, InviteScreen(key: UniqueKey(), releaseMode: releaseMode)),
        viewport: rkTallViewport,
      );
      await tester.enterText(find.byType(TextField).first, typed);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Member').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('F1-07-548 a mobile typed behind the fixed +91 — bare, or '
        'spaced or dashed as people write and paste it — is accepted and '
        'reaches the repository as +91 and the ten digits', (tester) async {
      debugDemoPhonesOverride = false;
      addTearDown(() => debugDemoPhonesOverride = null);
      // Reserved +91 99999 block only (ADR 2026-09-05i §7). The lead-digit
      // range (6–9) is the shared predicate's to prove (phone_shape_test);
      // here the digits-only formatter is the only thing that strips the
      // spaces and dashes, so these cases fail without it.
      for (final typed in [
        _mobile,
        '99999 00011',
        '99999-00011',
        ' 9999900011 ',
      ]) {
        final repo = await typeAndSend(tester, typed);
        expect(find.text(invalid), findsNothing, reason: typed);
        expect(repo.invites.single.phoneE164, _e164, reason: typed);
      }
    });

    testWidgets('F1-07-548 the +91 is drawn beside the field at rest — empty '
        'and unfocused, with the hint showing — not only once typing starts', (
      tester,
    ) async {
      await pumpRk(
        tester,
        _scoped(
          FakeMembersRepository(initial: _snapshot(TenantType.organization)),
          const InviteScreen(),
        ),
        viewport: rkTallViewport,
      );
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, isEmpty);
      expect(field.focusNode?.hasFocus ?? false, isFalse);
      expect(find.text('98765 43210'), findsOneWidget);
      final prefix = find.text('+91 ');
      expect(prefix, findsOneWidget);
      // Flutter fades an unlabelled prefix to 0 until focus or input; the
      // drawn opacity is what the person sees.
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(of: prefix, matching: find.byType(AnimatedOpacity)).first,
      );
      expect(opacity.opacity, 1.0);
    });

    testWidgets('F1-07-549 a number that is only E.164 — a foreign mobile, a '
        'landline-shaped or short number, or ten digits starting 0–4 — is '
        'refused with the invalid-number line and nothing is sent', (
      tester,
    ) async {
      debugDemoPhonesOverride = false;
      addTearDown(() => debugDemoPhonesOverride = null);
      for (final typed in [
        '+14155550123', // US mobile, valid E.164 — the old check took it
        '+447700900123', // UK mobile, valid E.164
        '1234567890',
        '4123456789',
        '98765',
      ]) {
        final repo = await typeAndSend(tester, typed);
        expect(find.text(invalid), findsOneWidget, reason: typed);
        expect(repo.invites, isEmpty, reason: typed);
      }
    });

    testWidgets('F1-07-550 a +91 5… demo number is refused when demo phones '
        'are off, and in a release build even with them on', (tester) async {
      debugDemoPhonesOverride = false;
      addTearDown(() => debugDemoPhonesOverride = null);
      var repo = await typeAndSend(tester, _demo);
      expect(find.text(invalid), findsOneWidget);
      expect(repo.invites, isEmpty);

      debugDemoPhonesOverride = true;
      repo = await typeAndSend(tester, _demo, releaseMode: true);
      expect(find.text(invalid), findsOneWidget);
      expect(repo.invites, isEmpty);
    });

    testWidgets('F1-07-551 a +91 5… demo number is accepted in a debug build '
        'with RF_DEMO_PHONES on', (tester) async {
      debugDemoPhonesOverride = true;
      addTearDown(() => debugDemoPhonesOverride = null);
      final repo = await typeAndSend(tester, _demo);
      expect(find.text(invalid), findsNothing);
      expect(repo.invites.single.phoneE164, '+91$_demo');
    });

    testWidgets('F1-07-552 a number pasted with its country code is refused, '
        'never cut down to ten digits — +91 99999 00011 must not become the '
        'stranger 91999 99000', (tester) async {
      debugDemoPhonesOverride = false;
      addTearDown(() => debugDemoPhonesOverride = null);
      for (final typed in ['+91 99999 00011', _e164, '0$_mobile']) {
        final repo = await typeAndSend(tester, typed);
        expect(find.text(invalid), findsOneWidget, reason: typed);
        expect(repo.invites, isEmpty, reason: typed);
      }
    });
  });
}
