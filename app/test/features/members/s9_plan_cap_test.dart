@Tags(['F1'])
library;

// F1-05g-4 … F1-05g-7 — S9.1 *Send invite* and S9 *Invite again* when the
// plan says no (ADR 2026-09-05g §2 / §6 🔒; server `seat_cap`,
// `seat_rotation_cap`, `book_cap`, migration 0019). Each refusal is its own
// plain line that names the way on — S12.1 Plans — and never the generic
// "try again": asking again cannot make room (01 §3, 07 §1 rule 6).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/members/members_routes.dart';
import 'package:rukka_folio/features/subscription/subscription_paths.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';

import '../../shared/test_app.dart';

final _books = [
  const TenantBook(id: 'b-home', name: 'Ghar'),
  const TenantBook(id: 'b-shop', name: 'Shop'),
];

const _you = Member(
  id: 'u-amrit',
  displayName: 'Amrit Kaur',
  state: MembershipState.active,
  isYou: true,
  grants: [
    BookGrant(bookId: 'b-home', role: BookRole.admin),
    BookGrant(bookId: 'b-shop', role: BookRole.admin),
  ],
);

/// Expired invite — carries the one-tap re-invite (07 §12).
const _expired = Member(
  id: 'inv-2',
  displayName: 'Ramesh',
  state: MembershipState.expired,
  invitedByName: 'Amrit Kaur',
  grants: [BookGrant(bookId: 'b-shop', role: BookRole.viewer)],
);

MembersSnapshot _snapshot() => MembersSnapshot(
  tenantType: TenantType.family,
  books: _books,
  members: const [_you, _expired],
  yourRoles: const {'b-home': BookRole.admin, 'b-shop': BookRole.admin},
);

Widget _scoped(MembersRepository repo, Widget child) =>
    MembersRepositoryScope(repository: repo, child: child);

/// Synthetic number (check_purity: +91 99999 xxxxx).
const _phone = '+919999900011';

const _en = {
  MembersRefusal.seatCap:
      'Your plan has no room for another member. To invite someone, choose a '
      'plan with more members in Plans.',
  MembersRefusal.seatRotationCap:
      'You’ve added as many different people as your plan allows in a year. '
      'To invite someone new, choose a plan with more members in Plans.',
  MembersRefusal.bookCap:
      'Your plan has no room for another business book. To add one, choose a '
      'plan with more business books in Plans.',
};

const _generic = 'Couldn’t send that invite. Try again.';

Future<void> _fillAndSend(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, _phone);
  await tester.tap(find.widgetWithText(ChoiceChip, 'Member').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send invite'));
  await tester.pumpAndSettle();
}

/// 01 §1 rule 4's forbidden jargon, and the wire names themselves.
final _forbidden = RegExp(
  r'\b(journal|voucher|contra|accrual|folio|narration)s?\b|_cap\b|seat',
  caseSensitive: false,
);

void main() {
  group('S9.1 / S9 when the plan is full (ADR 2026-09-05g §6)', () {
    testWidgets(
      'F1-05g-4 S9.1: each cap refusal is its own plain line with See plans, '
      'which opens Plans — not the generic retry line — and the form stays '
      'filled so a later Send is a new invite',
      (tester) async {
        for (final MapEntry(key: reason, value: line) in _en.entries) {
          final repo = FakeMembersRepository(initial: _snapshot())
            ..failNext = MembersFailure('refused', reason);
          var plans = 0;
          await pumpRk(
            tester,
            _scoped(
              repo,
              InviteScreen(key: ValueKey(reason), onOpenPlans: () => plans++),
            ),
            viewport: rkTallViewport,
          );
          await _fillAndSend(tester);
          expect(find.text(line), findsOneWidget, reason: reason.name);
          expect(find.text(_generic), findsNothing, reason: reason.name);
          // The other two caps' lines are not shown: one fact, one line.
          for (final other in _en.values.where((l) => l != line)) {
            expect(find.text(other), findsNothing);
          }
          expect(find.text(_phone), findsOneWidget, reason: 'form kept');
          await tester.tap(find.text('See plans'));
          await tester.pumpAndSettle();
          expect(plans, 1, reason: reason.name);

          // Upgraded: Send again goes through, as a fresh request.
          await tester.tap(find.text('Send invite'));
          await tester.pumpAndSettle();
          expect(repo.invites, hasLength(1), reason: reason.name);
          expect(find.text(line), findsNothing);
        }
      },
    );

    testWidgets(
      'F1-05g-5 S9 Invite again: a cap says what is full and offers Plans; any '
      'other failure keeps the generic retry line',
      (tester) async {
        final repo = FakeMembersRepository(initial: _snapshot())
          ..failNext = const MembersFailure(
            'refused',
            MembersRefusal.seatRotationCap,
          );
        var plans = 0;
        await pumpRk(
          tester,
          _scoped(repo, MembersScreen(onOpenPlans: () => plans++)),
          viewport: rkTallViewport,
        );
        await tester.tap(find.text('Invite again'));
        await tester.pumpAndSettle();
        expect(find.text(_en[MembersRefusal.seatRotationCap]!), findsOneWidget);
        expect(find.text(_generic), findsNothing);
        expect(repo.reinvited, isEmpty, reason: 'nothing was created');
        await tester.tap(find.text('See plans'));
        await tester.pumpAndSettle();
        expect(plans, 1);

        repo.failNext = const MembersFailure('offline');
        await tester.tap(find.text('Invite again'));
        await tester.pumpAndSettle();
        expect(find.text(_generic), findsOneWidget);
        expect(
          find.text(_en[MembersRefusal.seatRotationCap]!),
          findsNothing,
          reason: 'a new failure replaces the old line',
        );
      },
    );

    testWidgets(
      'F1-05g-6 the routes wire See plans to S12.1: from S9.1 on the real '
      'members routes, a seat cap lands on SubscriptionPaths.plans',
      (tester) async {
        final repo = FakeMembersRepository(initial: _snapshot())
          ..failNext = const MembersFailure('refused', MembersRefusal.seatCap);
        final router = GoRouter(
          initialLocation: MembersPaths.invite,
          routes: [
            ...membersRoutes,
            GoRoute(
              path: SubscriptionPaths.plans,
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('plans-landed'))),
            ),
          ],
        );
        rkViewport(tester, rkTallViewport);
        await tester.pumpWidget(
          RkScope(
            db: await openTestDb(),
            sync: FakeSyncClient(),
            auth: FakeAuthClient(),
            keys: FakeKeyStore(),
            now: testNow,
            child: _scoped(
              repo,
              MaterialApp.router(
                routerConfig: router,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: rkLocalizationsDelegates,
                theme: rkTheme(Brightness.light),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _fillAndSend(tester);
        await tester.tap(find.text('See plans'));
        await tester.pumpAndSettle();
        expect(find.text('plans-landed'), findsOneWidget);
      },
    );

    for (final locale in rkLocales) {
      testWidgets(
        'F1-05g-7 every cap line resolves in ${locale.languageCode}, holds at '
        '2x on 360×800, and carries no jargon and no wire name',
        (tester) async {
          for (final reason in _en.keys) {
            final repo = FakeMembersRepository(initial: _snapshot())
              ..failNext = MembersFailure('refused', reason);
            await pumpRk(
              tester,
              _scoped(repo, InviteScreen(key: ValueKey(reason))),
              locale: locale,
              textScale: 2,
              viewport: rkPhone360,
            );
            final l10n = AppLocalizations.of(
              tester.element(find.byType(InviteScreen)),
            );
            final line = switch (reason) {
              MembersRefusal.seatCap => l10n.inviteCapSeats,
              MembersRefusal.seatRotationCap => l10n.inviteCapRotation,
              _ => l10n.inviteCapBooks,
            };
            expect(_forbidden.hasMatch(line), isFalse, reason: line);
            expect(_forbidden.hasMatch(l10n.inviteCapPlans), isFalse);
            await tester.enterText(find.byType(TextField).first, _phone);
            final member = find.widgetWithText(
              ChoiceChip,
              roleLabel(l10n, BookRole.member),
            );
            // The grid is below the fold at 2x: build it, then bring it in.
            await tester.scrollUntilVisible(
              member,
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.ensureVisible(member.first);
            await tester.pumpAndSettle();
            await tester.tap(member.first);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.byType(FilledButton),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.ensureVisible(find.byType(FilledButton));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(FilledButton));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text(line));
            await tester.pumpAndSettle();
            expect(find.text(line), findsOneWidget, reason: '$locale $reason');
            expect(find.text(l10n.inviteCapPlans), findsOneWidget);
            expect(tester.takeException(), isNull);
            expectTextFits(tester, reason: '$locale $reason');
          }
        },
      );
    }
  });
}
