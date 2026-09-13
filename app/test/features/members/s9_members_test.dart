@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/screens/s9_members_screen.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

final _books = [
  const TenantBook(id: 'b-home', name: 'Ghar'),
  const TenantBook(id: 'b-shop', name: 'Shop'),
];

/// The signed-in admin.
final _you = Member(
  id: 'u-amrit',
  displayName: 'Amrit Kaur',
  designationLabel: 'Chairman',
  state: MembershipState.active,
  isYou: true,
  grants: const [
    BookGrant(bookId: 'b-home', role: BookRole.admin),
    BookGrant(bookId: 'b-shop', role: BookRole.admin),
  ],
  verification: Verification(
    verifiedByName: 'Sunita',
    method: VerificationMethod.qrInPerson,
    on: DateTime(2026, 8, 2),
  ),
);

/// Active, verified over a call, with a limit in one book.
final _sunita = Member(
  id: 'u-sunita',
  displayName: 'Sunita',
  designationLabel: 'ਖ਼ਜ਼ਾਨਚੀ',
  state: MembershipState.active,
  grants: const [
    BookGrant(
      bookId: 'b-shop',
      role: BookRole.head,
      autoPostLimitPaise: 500000,
    ),
  ],
  verification: Verification(
    verifiedByName: 'Amrit Kaur',
    method: VerificationMethod.codeRemote,
    on: DateTime(2026, 8, 20),
  ),
);

/// Joined, ceremony still owed.
const _harjit = Member(
  id: 'u-harjit',
  displayName: 'Harjit',
  state: MembershipState.joinedPendingVerification,
  grants: [BookGrant(bookId: 'b-home', role: BookRole.member)],
);

/// Invited by someone else — this device holds no contact for them
/// (ADR 2026-09-05c §4, ADR 2026-09-05f §G).
final _anonymousInvite = Member(
  id: 'inv-1',
  state: MembershipState.invited,
  invitedByName: 'Amrit',
  expiresOn: DateTime(2026, 9, 12, 10),
  grants: const [BookGrant(bookId: 'b-shop', role: BookRole.operator)],
);

/// Expired invite — carries the one-tap re-invite (07 §12).
const _expired = Member(
  id: 'inv-2',
  displayName: 'Ramesh',
  state: MembershipState.expired,
  invitedByName: 'Amrit Kaur',
  grants: [BookGrant(bookId: 'b-shop', role: BookRole.viewer)],
);

MembersSnapshot _adminSnapshot({
  List<Member>? members,
  List<PendingBook> pending = const [],
  TenantType type = TenantType.organization,
}) => MembersSnapshot(
  tenantType: type,
  books: _books,
  members: members ?? [_you, _sunita, _harjit, _anonymousInvite, _expired],
  pendingBooks: pending,
  yourRoles: const {'b-home': BookRole.admin, 'b-shop': BookRole.admin},
);

Widget _scoped(MembersRepository repo, Widget child) =>
    MembersRepositoryScope(repository: repo, child: child);

void main() {
  group('S9 Members (13 §3.2, 07 §12, 06 §1.0/§7, 04 §6.4)', () {
    testWidgets(
      'F1-07-26 populated: per-book role badges with the auto-post limit, the '
      'permanent verification log (method + date, 04 §6.4), the 06 §7 state of '
      'every row, and + Invite for an admin',
      (tester) async {
        final repo = FakeMembersRepository(initial: _adminSnapshot());
        var invites = 0;
        await pumpRk(
          tester,
          _scoped(repo, MembersScreen(onInvite: () => invites++)),
          viewport: rkTallViewport,
        );

        expect(find.text('Members'), findsOneWidget);
        expect(find.text('Amrit Kaur'), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
        // Role per book, never global (06 §1.1).
        expect(find.text('Shop · Head'), findsOneWidget);
        expect(find.text('Ghar · Admin'), findsOneWidget);
        // Integer paise rendered as whole rupees.
        expect(find.text('Up to ₹5,000'), findsOneWidget);
        expect(find.text('No limit'), findsWidgets);
        // 04 §6.4: who verified whom, by which method, on which day.
        expect(
          find.text('Verified in person by Sunita on 02 Aug 2026'),
          findsOneWidget,
        );
        expect(
          find.text('Verified over a call by Amrit Kaur on 20 Aug 2026'),
          findsOneWidget,
        );
        expect(find.text('Not verified yet'), findsWidgets);
        // 06 §7 state machine.
        expect(find.text('Active'), findsNWidgets(2));
        expect(find.text('Joined — verification needed'), findsOneWidget);
        expect(find.text('Invited · expires in 5 days'), findsOneWidget);
        expect(find.text('Invite expired'), findsOneWidget);
        // A designation never travels without the capability (06 §1.0 🔒).
        expect(
          find.text(
            'Chairman · Invites people, sets limits, checks entries and closes '
            'the books.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'ਖ਼ਜ਼ਾਨਚੀ · Runs the book day to day — posts, checks entries and '
            'closes.',
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Invite'));
        expect(invites, 1);
      },
    );

    testWidgets(
      'F1-07-26 a second admin cannot see whom was invited — the row reads '
      '"Invited by Amrit · awaiting join" and no number is drawn (ADR '
      '2026-09-05c §4, ADR 2026-09-05f §G 🔒)',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _adminSnapshot(members: [_you, _anonymousInvite]),
        );
        await pumpRk(
          tester,
          _scoped(repo, const MembersScreen()),
          viewport: rkTallViewport,
        );
        expect(find.text('Invited by Amrit · awaiting join'), findsOneWidget);
        expect(find.textContaining('+91'), findsNothing);
        expect(find.textContaining('98765'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-26 non-admin variant (13 §2.3.1): no Invite button, the reason is '
      'stated, and no limit is tappable',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: MembersSnapshot(
            tenantType: TenantType.organization,
            books: _books,
            members: [_sunita, _harjit],
            yourRoles: const {'b-shop': BookRole.member},
          ),
        );
        await pumpRk(
          tester,
          _scoped(repo, const MembersScreen()),
          viewport: rkTallViewport,
        );
        expect(find.text('Invite'), findsNothing);
        expect(
          find.text(
            'Only an admin can invite people, change roles or set limits.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Up to ₹5,000'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('Save limit'), findsNothing);
        expect(repo.limits, isEmpty);
      },
    );

    testWidgets(
      'F1-07-26 an admin taps a limit and the change reaches the repository as '
      'integer paise; Remove the limit sends null',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _adminSnapshot(members: [_you, _sunita]),
        );
        await pumpRk(
          tester,
          _scoped(repo, const MembersScreen()),
          viewport: rkTallViewport,
        );
        await tester.tap(find.text('Up to ₹5,000'));
        await tester.pumpAndSettle();
        expect(find.text('Auto-post limit'), findsWidgets);
        expect(
          find.text(
            'Entries above this still post — they are flagged for someone else '
            'to check.',
          ),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField), '7500.50');
        await tester.tap(find.text('Save limit'));
        await tester.pumpAndSettle();
        expect(repo.limits.single.paise, 750050);
        expect(repo.limits.single.bookId, 'b-shop');
        expect(repo.limits.single.memberId, 'u-sunita');

        await tester.tap(find.text('Up to ₹7,500'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove the limit'));
        await tester.pumpAndSettle();
        expect(repo.limits.last.paise, isNull);
      },
    );

    testWidgets(
      'F1-07-26 a typed limit that is not a rupee amount is refused with a '
      'named cause and nothing is written',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _adminSnapshot(members: [_you, _sunita]),
        );
        await pumpRk(
          tester,
          _scoped(repo, const MembersScreen()),
          viewport: rkTallViewport,
        );
        await tester.tap(find.text('Up to ₹5,000'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '5,0o0');
        await tester.tap(find.text('Save limit'));
        await tester.pumpAndSettle();
        expect(find.text('Enter a rupee amount, like 5000.'), findsOneWidget);
        expect(repo.limits, isEmpty);
      },
    );

    testWidgets(
      'F1-07-26 an expired invite carries the one-tap re-invite (07 §12), and '
      'a failure says so with the retry still there',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _adminSnapshot(members: [_you, _expired]),
        );
        await pumpRk(
          tester,
          _scoped(repo, const MembersScreen()),
          viewport: rkTallViewport,
        );
        await tester.tap(find.text('Invite again'));
        await tester.pumpAndSettle();
        expect(repo.reinvited, ['inv-2']);

        repo.failNext = const MembersFailure('offline');
        await tester.tap(find.text('Invite again'));
        await tester.pumpAndSettle();
        expect(
          find.text('Couldn’t send that invite. Try again.'),
          findsOneWidget,
        );
        expect(find.text('Invite again'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-26 a blocked row states the path instead of offering a re-invite '
      '(06 §7: admin unblocks only after investigation)',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _adminSnapshot(
            members: [
              _you,
              const Member(
                id: 'u-blocked',
                displayName: 'Baljit',
                state: MembershipState.blocked,
                grants: [BookGrant(bookId: 'b-shop', role: BookRole.member)],
              ),
            ],
          ),
        );
        await pumpRk(
          tester,
          _scoped(repo, const MembersScreen()),
          viewport: rkTallViewport,
        );
        expect(find.text('Blocked after a failed check'), findsOneWidget);
        expect(
          find.text(
            'An admin has to look into this before a new invite can go out.',
          ),
          findsOneWidget,
        );
        expect(find.text('Invite again'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-26 the invitee sees their shared books greyed — "Meet Sunita to '
      'activate" (07 §12, 06 §7 joined_pending_verification)',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: MembersSnapshot(
            books: _books,
            members: [_harjit],
            pendingBooks: const [
              PendingBook(name: 'Shop', activateWithName: 'Sunita'),
            ],
            yourRoles: const {'b-home': BookRole.member},
          ),
        );
        await pumpRk(
          tester,
          _scoped(repo, const MembersScreen()),
          viewport: rkTallViewport,
        );
        expect(find.text('Shared books'), findsOneWidget);
        expect(find.text('Meet Sunita to activate'), findsOneWidget);
        expect(
          find.textContaining('Your own book works right now'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-07-26 loading shows the ruled skeleton and an all-but-you tenant '
      'shows the empty state with its one next action (13 §4.3)',
      (tester) async {
        final repo = FakeMembersRepository();
        await pumpRk(tester, _scoped(repo, const MembersScreen()));
        expect(find.bySemanticsLabel('Loading members…'), findsOneWidget);

        repo.current = _adminSnapshot(members: [_you]);
        await tester.pumpAndSettle();
        expect(find.text('It’s just you here so far.'), findsOneWidget);
        expect(find.text('Invite someone'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-26 a failed load is an error with a retry that reaches the '
      'repository — never a dead end (07 §1 rule 6)',
      (tester) async {
        final repo = FakeMembersRepository()
          ..failNext = const MembersFailure('no network');
        await pumpRk(tester, _scoped(repo, const MembersScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Couldn’t load the members.'), findsOneWidget);

        repo.onRefresh = _adminSnapshot(members: [_you, _sunita]);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Sunita'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-26 offline is a quiet chip over the last-seen list, never a '
      'blocked screen (07 §1 rule 7, 13 §8)',
      (tester) async {
        final repo = FakeMembersRepository(
          initial: _adminSnapshot(members: [_you, _sunita]),
        );
        await pumpRk(
          tester,
          _scoped(repo, const MembersScreen()),
          sync: FakeSyncClient(initial: const Offline()),
        );
        expect(
          find.text('Offline — showing what this phone last saw.'),
          findsOneWidget,
        );
        expect(find.text('Sunita'), findsOneWidget);
      },
    );

    for (final locale in rkLocales) {
      for (final scale in rkTextScales) {
        testWidgets('F1-07-26 S9 holds at ${scale}x text on 360×800 in '
            '${locale.languageCode} — every string resolves, nothing is cut', (
          tester,
        ) async {
          final repo = FakeMembersRepository(
            initial: _adminSnapshot(
              pending: const [
                PendingBook(name: 'Shop', activateWithName: 'Sunita'),
              ],
            ),
          );
          await pumpRk(
            tester,
            _scoped(repo, const MembersScreen()),
            locale: locale,
            textScale: scale,
            viewport: rkPhone360,
          );
          expect(tester.takeException(), isNull);
          expectTextFits(tester, reason: '$locale @ $scale');
        });
      }
    }
  });
}
