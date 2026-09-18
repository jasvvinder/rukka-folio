// F1-06-19 · F1-06-20: the members adapter for the auto-post-limit seam
// (02 §3 🔒, 03 §3.3 rule 5 🔒, 06 §1.1) and its mount.
//
// F1-06-19 pins that the adapter and `FakeReviewPolicy` answer the **same**
// `ReviewPolicy` contract — same question, same answers, including every way
// of not knowing — so a test that uses the fake is testing the thing the app
// ships. F1-06-20 mounts the real adapter over the real `LocalLedger` and
// reads the authored flag back out of the projection, the way IN1's mount
// test reads its cards back out of `ReviewQueueScope`.
//
// Amounts are synthetic (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/members_review_policy.dart';
import 'package:rukka_folio/shared/seams/review_policy.dart';

import '../../shared/test_app.dart';

MembersSnapshot snapshotWith({
  required String userId,
  required String bookId,
  int? paise,
  bool grant = true,
}) => MembersSnapshot(
  books: [TenantBook(id: bookId, name: 'Shop')],
  members: [
    Member(
      id: userId,
      state: MembershipState.active,
      isYou: true,
      grants: [
        if (grant)
          BookGrant(
            bookId: bookId,
            role: BookRole.member,
            autoPostLimitPaise: paise,
          ),
      ],
    ),
    // A second member of the same book: 02 §7.2 item 1 🔒 raises no flag at
    // all in a book with one member, so a limit only bites where there is
    // somebody to do the checking.
    Member(
      id: 'ramesh',
      state: MembershipState.active,
      grants: [BookGrant(bookId: bookId, role: BookRole.head)],
    ),
  ],
  yourRoles: {bookId: BookRole.member},
);

void main() {
  group('the adapter answers the seam\'s contract (F1-06-19)', () {
    test('F1-06-19 the limit comes from this member\'s own book_roles grant, '
        'in integer paise, and the fake and the adapter agree on every answer '
        'including the three ways of not knowing', () async {
      final repo = FakeMembersRepository();
      final adapter = MembersReviewPolicy(repo, warmOnMiss: false);
      final fake = FakeReviewPolicy();

      // 1. No snapshot at all — the metadata has never loaded.
      expect(repo.current, isNull);
      expect(
        await adapter.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        isNull,
      );
      expect(
        await fake.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        isNull,
      );

      // 2. A snapshot with a grant that carries a limit.
      repo.current = snapshotWith(
        userId: 'amrit',
        bookId: 'shop',
        paise: 500_000,
      );
      fake.setLimit(bookId: 'shop', userId: 'amrit', paise: 500_000);
      expect(
        await adapter.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        500_000,
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        await fake.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        isA<int>(),
      );

      // 3. A member with a grant but no limit on it — unlimited, not zero.
      repo.current = snapshotWith(userId: 'amrit', bookId: 'shop');
      expect(
        await adapter.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        isNull,
      );

      // 4. A member with no grant in that book, and a member who is not in
      //    the snapshot at all. Both are *no limit known here*, never a flag
      //    invented from absent metadata (⚠️ SPEC on ReviewPolicy).
      repo.current = snapshotWith(
        userId: 'amrit',
        bookId: 'shop',
        paise: 500_000,
        grant: false,
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        isNull,
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'shop', userId: 'sunita'),
        isNull,
      );

      // The limit is per book as well as per member.
      repo.current = const MembersSnapshot(
        members: [
          Member(
            id: 'amrit',
            state: MembershipState.active,
            grants: [
              BookGrant(
                bookId: 'shop',
                role: BookRole.member,
                autoPostLimitPaise: 100,
              ),
              BookGrant(
                bookId: 'home',
                role: BookRole.admin,
                autoPostLimitPaise: 900,
              ),
            ],
          ),
          Member(
            id: 'ramesh',
            state: MembershipState.active,
            grants: [
              BookGrant(bookId: 'shop', role: BookRole.head),
              BookGrant(bookId: 'home', role: BookRole.head),
            ],
          ),
        ],
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        100,
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'home', userId: 'amrit'),
        900,
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'other', userId: 'amrit'),
        isNull,
      );
    });

    test('F1-06-19 a book with exactly ONE member raises no flag at all, '
        'whatever limit its own grant carries — 02 §7.2 item 1 🔒 "If a book '
        'has exactly one member, no flag is raised (there is nothing to check '
        'and nobody to check it)", and 02 §3 🔒 "A member in their own '
        'personal book is never flagged"', () async {
      final repo = FakeMembersRepository();
      final adapter = MembersReviewPolicy(repo, warmOnMiss: false);

      repo.current = const MembersSnapshot(
        members: [
          Member(
            id: 'amrit',
            state: MembershipState.active,
            isYou: true,
            grants: [
              BookGrant(
                bookId: 'personal',
                role: BookRole.admin,
                autoPostLimitPaise: 100,
              ),
            ],
          ),
        ],
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'personal', userId: 'amrit'),
        isNull,
        reason:
            'a flag here could be cleared by nobody and would block the '
            'month close forever (02 §8 step 3 🔒)',
      );

      // An *invited* second person is not yet a member who can check
      // anything: they hold the grant they will get (06 §7) and no key.
      repo.current = MembersSnapshot(
        members: [
          repo.current!.members.single,
          const Member(
            id: 'invite-1',
            state: MembershipState.invited,
            grants: [BookGrant(bookId: 'personal', role: BookRole.head)],
          ),
        ],
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'personal', userId: 'amrit'),
        isNull,
      );

      // Once they have joined and been verified, the limit applies.
      repo.current = MembersSnapshot(
        members: [
          repo.current!.members.first,
          const Member(
            id: 'sunita',
            state: MembershipState.active,
            grants: [BookGrant(bookId: 'personal', role: BookRole.head)],
          ),
        ],
      );
      expect(
        await adapter.autoPostLimitPaise(bookId: 'personal', userId: 'amrit'),
        100,
      );
    });

    test('F1-06-19 a lookup never blocks a save and never throws: an offline '
        'repository answers *no limit* and starts ONE background refresh, '
        'however many entries are posted (02 §3 🔒 — the entry posts the '
        'moment it is saved)', () async {
      final repo = FakeMembersRepository()
        ..failNext = const MembersFailure('offline', MembersRefusal.offline);
      final adapter = MembersReviewPolicy(repo);

      for (var i = 0; i < 5; i++) {
        expect(
          await adapter.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
          isNull,
        );
      }
      expect(adapter.warmStarted, isTrue);
      // The refusal was swallowed; nothing was thrown into the save path.
      await Future<void>.delayed(Duration.zero);
      expect(repo.failNext, isNull, reason: 'exactly one refresh was tried');
    });
  });

  group('the mount (F1-06-20)', () {
    late SeededLedger s;

    setUp(() async {
      s = await seedSoloLedger();
    });

    test('F1-06-20 mounted over the real ledger, an over-limit entry is '
        'flagged from the member\'s real grant and an under-limit one is not '
        '— the same read S9 shows, on the write path', () async {
      final me = s.ledger.identity.userId;
      final repo = FakeMembersRepository(
        initial: snapshotWith(userId: me, bookId: s.bookId, paise: 500_000),
      );
      s.ledger.reviewPolicy = MembersReviewPolicy(repo, warmOnMiss: false);

      final over = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 600_000,
        date: s.ledger.today(),
      );
      final under = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 400_000,
        date: s.ledger.today(),
      );

      expect((await s.ledger.entry(over.id))!.reviewState, 'open');
      expect((await s.ledger.entry(under.id))!.reviewState, 'none');
      expect(over.reviewLimitPaise, const Paise(500_000));
      expect(under.reviewLimitPaise, const Paise(500_000));

      // The admin lowers the limit through the same repository S9 writes to;
      // the next entry is measured against the new one, and the two already
      // posted keep theirs (03 §3.3 rule 5 🔒 — the limit in force at the
      // entry's HLC).
      repo.current = snapshotWith(userId: me, bookId: s.bookId, paise: 100_000);
      final after = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 200_000,
        date: s.ledger.today(),
      );
      expect((await s.ledger.entry(after.id))!.reviewState, 'open');
      expect(after.reviewLimitPaise, const Paise(100_000));
      expect((await s.ledger.entry(under.id))!.reviewState, 'none');
    });

    test(
      'F1-06-20 the composition root\'s order works: the ledger is built '
      'before the members repository exists, handed a LateReviewPolicy, and '
      'the policy set into it a few lines later decides every later post',
      () async {
        final holder = LateReviewPolicy();
        s.ledger.reviewPolicy = holder;

        // Before the repository exists: no limit is known, so nothing is
        // flagged — exactly the app's behaviour before this seam.
        final early = await s.ledger.moneyOut(
          bookId: s.bookId,
          from: s.cashId,
          forWhat: s.fuelId,
          paise: 900_000,
          date: s.ledger.today(),
        );
        expect(early.reviewRequired, isFalse);
        expect(early.reviewLimitPaise, isNull);

        holder.policy = MembersReviewPolicy(
          FakeMembersRepository(
            initial: snapshotWith(
              userId: s.ledger.identity.userId,
              bookId: s.bookId,
              paise: 500_000,
            ),
          ),
          warmOnMiss: false,
        );
        final later = await s.ledger.moneyOut(
          bookId: s.bookId,
          from: s.cashId,
          forWhat: s.fuelId,
          paise: 900_000,
          date: s.ledger.today(),
        );
        expect(later.reviewRequired, isTrue);
        expect((await s.ledger.entry(later.id))!.reviewState, 'open');
        // The entry posted through the empty window is left exactly as it was
        // authored — nothing is retro-flagged (02 §1.4 rule 4, append-only).
        expect((await s.ledger.entry(early.id))!.reviewState, 'none');
      },
    );
  });
}
