// F1-02-92…99: the **rights half** of post-then-review — what the authoring
// client writes into the entry payload so every reader can re-check it
// (02 §1.3 🔒, 02 §3 🔒, 03 §3.3 rule 5 🔒).
//
// `auto_post_limit_paise` lives in `book_roles`, which is plaintext server
// metadata the projector may never read. So the flag is **authored**, not
// derived: this client evaluates the limit in force at save time, writes
// `review_required` **and** `review_limit_paise` into the payload, and every
// reader re-checks one against the other (`ViolationKind.reviewFlagMissing`).
// A hostile client that writes `review_required=false` over the limit it
// itself carries is caught by that check, which is why the limit is pinned in
// the *decoded payload* here and not only in the projection.
//
// Everything is read back out of the rebuilt projection and out of the sealed
// envelope — never out of the object this facade happened to return. The
// limits come from `FakeReviewPolicy`; `shared/ledger` may not import
// `features/`, so the real `MembersRepository` reaches it only through
// `ReviewPolicy` (see `features/members/members_review_policy_test.dart`).
//
// In-memory SQLite, FakeKeyStore, injected clock. Amounts are synthetic
// (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/review_policy.dart';

import '../test_app.dart';

/// The entry payload as it was **sealed**, decoded through the ledger's own
/// opener — the bytes a second device will read, not the draft this process
/// built. The newest envelope for [objectId] wins, so an amended entry is
/// asked for by its own id.
Future<Map<String, Object?>> sealedPayload(
  LocalLedger l,
  String objectId,
) async {
  final rows =
      await (l.db.select(l.db.envelopesLocal)
            ..where((t) => t.objectId.equals(objectId))
            ..orderBy([(t) => OrderingTerm.desc(t.hlc)]))
          .get();
  final row = rows.first;
  return l.recompute.opener.open(
    row.envelopeBlob,
    BlobHeader(
      envelopeId: row.envelopeId,
      bookId: row.bookId,
      objectId: row.objectId,
      objectType: row.objectType,
      keyVersion: row.keyVersion,
      authorDevice: row.authorDevice,
      hlc: row.hlc,
    ),
  );
}

/// The projected review state of [entryId] (02 §3, folded by the projector).
Future<String> reviewStateOf(LocalLedger l, String entryId) async =>
    (await l.entry(entryId))!.reviewState;

/// The signed paise standing on [accountId] in [bookId] right now.
Future<int> balanceOf(SeededLedger s, String accountId) async {
  final row = await (s.ledger.db.select(
    s.ledger.db.balances,
  )..where((t) => t.accountId.equals(accountId))).getSingleOrNull();
  return row?.balancePaise ?? 0;
}

void main() {
  late SeededLedger s;
  late FakeReviewPolicy policy;
  late String me;
  late LocalDate today;

  setUp(() async {
    s = await seedSoloLedger();
    today = s.ledger.today();
    me = s.ledger.identity.userId;
    policy = FakeReviewPolicy();
    s.ledger.reviewPolicy = policy;
  });

  group('the authored flag (02 §1.3 🔒, 03 §3.3 rule 5 🔒)', () {
    test('F1-02-92 an entry over the limit posts COUNTED and flagged — '
        'review_required=true and review_limit_paise = the limit used, in the '
        'projection AND in the decoded payload (02 §3: post-then-review, the '
        'flag is never a gate)', () async {
      policy.setLimit(bookId: s.bookId, userId: me, paise: 500_000);
      final cashBefore = await balanceOf(s, s.cashId);

      final entry = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 500_001,
        date: today,
        note: 'over by one paisa',
      );

      // Posted and counted from the moment it was saved — 02 §3 🔒.
      expect(entry.status, EntryStatus.posted);
      expect(entry.reviewRequired, isTrue);
      expect(await balanceOf(s, s.cashId), cashBefore - 500_001);
      // The projector's own verdict, folded from the envelope.
      expect(await reviewStateOf(s.ledger, entry.id), 'open');

      // The payload a second device will read carries both halves, so the
      // reader's re-check (`reviewFlagMissing`) has something to check.
      final payload = await sealedPayload(s.ledger, entry.id);
      expect(payload['review_required'], isTrue);
      expect(payload['review_limit_paise'], 500_000);
      expect(payload['review_limit_paise'], isA<int>());
      expect(
        Entry.fromJson(payload).reviewLimitPaise,
        const Paise(500_000),
        reason: 'the limit round-trips through the codec, not just the map',
      );
    });

    test('F1-02-93 an entry AT the limit is not flagged — the engine\'s own '
        'reader check is `totalDebits > limit` — and the limit is recorded on '
        'the payload either way, so the reader can re-check it', () async {
      policy.setLimit(bookId: s.bookId, userId: me, paise: 500_000);

      final atLimit = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 500_000,
        date: today,
      );
      final under = await s.ledger.moneyIn(
        bookId: s.bookId,
        into: s.cashId,
        from: s.salesId,
        paise: 1_000,
        date: today,
      );

      for (final e in [atLimit, under]) {
        expect(e.reviewRequired, isFalse);
        expect(await reviewStateOf(s.ledger, e.id), 'none');
        final payload = await sealedPayload(s.ledger, e.id);
        expect(payload['review_required'], isFalse);
        expect(payload['review_limit_paise'], 500_000);
      }
    });

    test(
      'F1-02-94 NO limit configured means NO review required and no '
      'review_limit_paise on the payload — 02 §3 🔒 "`auto_post_limit_paise` '
      '(06 §1.1) is a review threshold, not a gate", and 06 §1.1 types the '
      'column nullable without saying a missing one reviews everything',
      () async {
        // No `setLimit` at all: the grant is absent, or carries no limit.
        final big = await s.ledger.moneyOut(
          bookId: s.bookId,
          from: s.cashId,
          forWhat: s.fuelId,
          paise: 99_00_00_000,
          date: today,
        );

        expect(big.reviewRequired, isFalse);
        expect(big.reviewLimitPaise, isNull);
        expect(await reviewStateOf(s.ledger, big.id), 'none');
        final payload = await sealedPayload(s.ledger, big.id);
        expect(payload['review_required'], isFalse);
        expect(
          payload['review_limit_paise'],
          isNull,
          reason: 'absent, not zero — zero would flag every entry on re-check',
        );
        expect(policy.reads.single, (bookId: s.bookId, userId: me));
      },
    );

    test('F1-02-95 the limit is read ONCE per post, at save time — the limit '
        'in force at this entry\'s HLC (03 §3.3 rule 5 🔒) — so raising or '
        'lowering the grant afterwards never re-flags an entry already in the '
        'book', () async {
      policy.setLimit(bookId: s.bookId, userId: me, paise: 500_000);
      final flagged = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 600_000,
        date: today,
      );
      expect(policy.reads, hasLength(1), reason: 'one read per post');
      expect(await reviewStateOf(s.ledger, flagged.id), 'open');

      // The admin raises the limit above that entry. The entry keeps the limit
      // it was measured against, and the flag stays open until a *decision*
      // clears it (02 §3 🔒) — a setting change is not a decision.
      policy.setLimit(bookId: s.bookId, userId: me, paise: 10_00_000);
      await s.ledger.rebuild(s.bookId);
      expect(await reviewStateOf(s.ledger, flagged.id), 'open');
      expect(
        (await sealedPayload(s.ledger, flagged.id))['review_limit_paise'],
        500_000,
      );

      // And a *new* entry under the raised limit is not flagged, which is the
      // same rule read forwards.
      final after = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 600_000,
        date: today,
      );
      expect(after.reviewRequired, isFalse);
      expect(
        (await sealedPayload(s.ledger, after.id))['review_limit_paise'],
        10_00_000,
      );
      expect(policy.reads, hasLength(2));
    });

    test('F1-02-96 the inter-book pair flags each half against ITS OWN '
        'book\'s limit (02 §6 🔒): one user action, two books, two limits, '
        'two independently authored flags', () async {
      final other = await s.ledger.createBook(
        name: 'Sharma Family',
        type: BookType.family,
      );
      final otherCash = (await s.ledger.chartOf(other))
          .byClass(AccountClass.money)
          .first
          .id;
      final otherExpense = await s.ledger.addAccount(
        other,
        name: 'Repairs',
        accountClass: AccountClass.categoryExpense,
      );
      // Tight here, generous there — so a single amount is over one limit and
      // under the other, and only the book's own limit can decide each half.
      policy.setLimit(bookId: s.bookId, userId: me, paise: 100_000);
      policy.setLimit(bookId: other, userId: me, paise: 500_000);

      final move = await s.ledger.transferBetweenBooks(
        fromBookId: s.bookId,
        fromAccountId: s.bankId,
        toBookId: other,
        toAccountId: otherCash,
        paise: 200_000,
        date: today,
      );

      expect(move.from.reviewRequired, isTrue);
      expect(move.to.reviewRequired, isFalse);
      expect(await reviewStateOf(s.ledger, move.from.id), 'open');
      expect(await reviewStateOf(s.ledger, move.to.id), 'none');
      // Each half carries the limit **its** reader will re-check it against.
      expect(
        (await sealedPayload(s.ledger, move.from.id))['review_limit_paise'],
        100_000,
      );
      expect(
        (await sealedPayload(s.ledger, move.to.id))['review_limit_paise'],
        500_000,
      );
      // One read per half, each for its own book (03 §3.3 rule 5 🔒).
      expect(policy.reads.map((r) => r.bookId), [s.bookId, other]);
      expect(policy.reads.every((r) => r.userId == me), isTrue);

      // The same for the one-sided case, with the limits the other way round:
      // the payer's half is small enough, the payee's book is the tight one.
      policy.reads.clear();
      policy.setLimit(bookId: s.bookId, userId: me, paise: 500_000);
      policy.setLimit(bookId: other, userId: me, paise: 100_000);
      final pocket = await s.ledger.pocketExpense(
        payerBookId: s.bookId,
        payerMoneyId: s.cashId,
        payeeBookId: other,
        payeeExpenseId: otherExpense.id,
        paise: 200_000,
        date: today,
      );
      expect(pocket.from.reviewRequired, isFalse);
      expect(pocket.to.reviewRequired, isTrue);
      expect(await reviewStateOf(s.ledger, pocket.to.id), 'open');
      expect(policy.reads.map((r) => r.bookId), [s.bookId, other]);
    });
  });

  group('the cases that are never flagged', () {
    test('F1-02-97 a `pending` advance request is not measured against the '
        'limit (02 §1.3 🔒: `pending` is ONLY an advance request awaiting '
        'approval, the one case where approval itself moves the money), and '
        'the 02 §5 reversal is never flagged however large it is', () async {
      policy.setLimit(bookId: s.bookId, userId: me, paise: 1);
      final advanceAccount = await s.ledger.addAccount(
        s.bookId,
        name: 'Advance – Ramesh',
        accountClass: AccountClass.advance,
      );

      final request = await s.ledger.requestAdvance(
        bookId: s.bookId,
        advance: advanceAccount.id,
        from: s.cashId,
        paise: 500_000,
        purpose: 'Mandi trip',
        date: today,
        approver: 'ramesh',
      );
      expect(request.status, EntryStatus.pending);
      expect(request.reviewRequired, isFalse);
      expect(
        (await sealedPayload(s.ledger, request.id))['review_required'],
        isFalse,
      );
      expect(
        request.reviewApprover,
        'ramesh',
        reason: 'the advance approver is the caller\'s, not this seam\'s',
      );

      // A reversal restores a figure and is authored by the corrector
      // (`Entry.reversal` in core_ledger fixes `review_required = false`).
      final original = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 900_000,
        date: today,
      );
      final mirror = await s.ledger.reverse(original.id, date: today);
      expect(mirror.reviewRequired, isFalse);
      expect(await reviewStateOf(s.ledger, mirror.id), 'none');
      expect(
        (await sealedPayload(s.ledger, mirror.id))['review_required'],
        isFalse,
      );
    });

    test('F1-02-98 review_approver is left NULL: ADR 2026-09-05e §9 🔒 puts '
        'the peer reviewer in the `book_config` envelope and no field carries '
        'it yet, and 02 §7.2 item 1 🔒 forbids naming the author — a wrong '
        'approver is worse than none', () async {
      policy.setLimit(bookId: s.bookId, userId: me, paise: 100);
      final config = await s.ledger.configOf(s.bookId);
      expect(
        config!.extra.keys.where((k) => k.contains('review')),
        isEmpty,
        reason: 'no peer-reviewer field is carried by book_config today',
      );

      final flagged = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 200_000,
        date: today,
      );

      expect(flagged.reviewRequired, isTrue);
      expect(flagged.reviewApprover, isNull);
      expect(
        (await sealedPayload(
          s.ledger,
          flagged.id,
        )).containsKey('review_approver'),
        isFalse,
      );
      // The author is never written into the slot that says who must act.
      final row = await (s.ledger.db.select(
        s.ledger.db.entriesP,
      )..where((t) => t.id.equals(flagged.id))).getSingle();
      expect(row.reviewApprover, isNull);
      expect(row.reviewState, 'open');
    });
  });

  group('the amendment hole (02 §5 + 02 §3 🔒)', () {
    test('F1-02-99 an amendment is re-measured against the limit in force at '
        'its own HLC, so raising a small approved entry to an over-limit one '
        'by amending it does NOT escape review', () async {
      policy.setLimit(bookId: s.bookId, userId: me, paise: 500_000);
      final chart = await s.ledger.chartOf(s.bookId);
      final small = await s.ledger.moneyOut(
        bookId: s.bookId,
        from: s.cashId,
        forWhat: s.fuelId,
        paise: 10_000,
        date: today,
      );
      expect(small.reviewRequired, isFalse);

      final grown = await s.ledger.amend(
        small.id,
        lines: Verbs.moneyOut(
          from: chart.account(s.cashId),
          forWhat: chart.account(s.fuelId),
          amount: const Paise(900_000),
        ),
      );

      expect(grown.reviewRequired, isTrue);
      expect(await reviewStateOf(s.ledger, grown.id), 'open');
      expect(
        (await sealedPayload(s.ledger, grown.id))['review_limit_paise'],
        500_000,
      );

      // And the other direction: an amendment back under the limit is not
      // flagged — the amount really is under it now.
      final shrunk = await s.ledger.amend(
        grown.id,
        lines: Verbs.moneyOut(
          from: chart.account(s.cashId),
          forWhat: chart.account(s.fuelId),
          amount: const Paise(20_000),
        ),
      );
      expect(shrunk.reviewRequired, isFalse);
      expect(await reviewStateOf(s.ledger, shrunk.id), 'none');
    });
  });
}
