@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/screens/s9_1_invite_screen.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

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
    testWidgets(
      'F1-07-26 the three steps in order — phone, per-book role + limit grid, '
      'designation — with the 06 §1.0 🔒 line word for word and the 7-day, '
      'this-number-only expiry stated',
      (tester) async {
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
          find.text(
            'A name, not a permission — what they can do is set above.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'The link works for 7 days, and only on a phone with that number.',
          ),
          findsOneWidget,
        );
      },
    );

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

    testWidgets(
      'F1-07-26 Send reaches the repository with the E.164 number, one grant '
      'per book and the limit as integer paise; the designation travels as a '
      'label only',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _snapshot(TenantType.organization),
        );
        var sent = 0;
        await pumpRk(
          tester,
          _scoped(repo, InviteScreen(onSent: () => sent++)),
          viewport: rkTallViewport,
        );
        await tester.enterText(find.byType(TextField).first, '+91 98765 43210');
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
        expect(req.phoneE164, '+919876543210');
        expect(req.grants.length, 1);
        expect(req.grants.single.bookId, 'b-home');
        expect(req.grants.single.role, BookRole.head);
        expect(req.grants.single.autoPostLimitPaise, 200000);
        expect(req.designationLabel, 'Treasurer');
        expect(sent, 1);
      },
    );

    testWidgets('F1-07-26 a typed designation is kept as typed (01 §2 🔒: any name may be '
        'typed free) and nothing is sent without a country code or without one '
        'role', (tester) async {
      final repo = FakeMembersRepository(initial: _snapshot(TenantType.family));
      await pumpRk(
        tester,
        _scoped(repo, const InviteScreen()),
        viewport: rkTallViewport,
      );
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();
      expect(
        find.text('Add the country code too, like +91 98765 43210.'),
        findsOneWidget,
      );
      expect(
        find.text('Give them a role in at least one book.'),
        findsOneWidget,
      );
      expect(repo.invites, isEmpty);

      await tester.enterText(find.byType(TextField).first, '+919876543210');
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
        await tester.enterText(find.byType(TextField).first, '+919876543210');
        await tester.tap(find.widgetWithText(ChoiceChip, 'Member').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send invite'));
        await tester.pumpAndSettle();
        expect(
          find.text('Couldn’t send that invite. Try again.'),
          findsOneWidget,
        );
        expect(find.text('+919876543210'), findsOneWidget);
        expect(find.text('Send invite'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-26 offline: Send is disabled and the reason is stated — the link '
      'is sent by the server (06 §7), so this one action needs a connection',
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
}
