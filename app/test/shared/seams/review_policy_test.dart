// F1-06-17 · F1-06-18: the auto-post-limit seam (02 §3 🔒, 03 §3.3 rule 5 🔒,
// 06 §1.1).
//
// The seam carries one number and one meaning: *the limit in force for this
// member in this book*, integer paise, or null for **no limit applies**. The
// meaning is the load-bearing half — a wrong null flags nothing (or, read the
// other way, flags everything and deadlocks a single-member book's close), so
// it is pinned here with the section it comes from quoted in the test name.
@Tags(['F1'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/review_policy.dart';

void main() {
  test(
    'F1-06-17 the shipped policy answers *no limit* for every book and '
    'member, so the app behaves exactly as it did before this seam — and a '
    'missing limit means NO review (02 §3 🔒 "a review threshold, not a '
    'gate"; 06 §1.1 types the column nullable and says nothing more)',
    () async {
      expect(
        await noReviewPolicy.autoPostLimitPaise(bookId: 'b1', userId: 'u1'),
        isNull,
      );
      expect(
        await noReviewPolicy.autoPostLimitPaise(bookId: 'b2', userId: 'u2'),
        isNull,
      );
      // The constant is const — one instance, so installing it twice is not a
      // change any listener has to react to.
      expect(identical(noReviewPolicy, const _Same().value), isTrue);
    },
  );

  test('F1-06-17 the fake answers per (book, member), records every read, and '
      'integer paise only (CLAUDE.md rule 1)', () async {
    final policy = FakeReviewPolicy(
      limits: {
        (bookId: 'shop', userId: 'amrit'): 500_000,
        (bookId: 'shop', userId: 'sukhdev'): null,
      },
    );

    expect(
      await policy.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
      500_000,
    );
    expect(
      await policy.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
      isA<int>(),
    );
    // A key present with a null value and a key that is absent are the same
    // answer: no limit applies.
    expect(
      await policy.autoPostLimitPaise(bookId: 'shop', userId: 'sukhdev'),
      isNull,
    );
    expect(
      await policy.autoPostLimitPaise(bookId: 'home', userId: 'amrit'),
      isNull,
    );
    // The limit is per book AND per member — never one or the other.
    policy.setLimit(bookId: 'home', userId: 'amrit', paise: 100);
    expect(
      await policy.autoPostLimitPaise(bookId: 'home', userId: 'amrit'),
      100,
    );
    expect(
      await policy.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
      500_000,
    );

    expect(policy.reads, hasLength(6));
    expect(policy.reads.first, (bookId: 'shop', userId: 'amrit'));
    expect(policy.reads.last, (bookId: 'shop', userId: 'amrit'));
  });

  test(
    'F1-06-18 the composition root\'s late binding answers *no limit* until '
    'a policy is installed, and never *reviewed* on missing information',
    () async {
      final late_ = LateReviewPolicy();
      expect(
        await late_.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        isNull,
      );

      late_.policy = FakeReviewPolicy(
        limits: {(bookId: 'shop', userId: 'amrit'): 250_000},
      );
      expect(
        await late_.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        250_000,
      );
      expect(
        await late_.autoPostLimitPaise(bookId: 'shop', userId: 'ramesh'),
        isNull,
      );

      // Installed at construction is the same thing, for a caller that has the
      // policy in hand already.
      final eager = LateReviewPolicy(
        FakeReviewPolicy(limits: {(bookId: 'shop', userId: 'amrit'): 1}),
      );
      expect(
        await eager.autoPostLimitPaise(bookId: 'shop', userId: 'amrit'),
        1,
      );
    },
  );
}

final class _Same {
  const _Same();
  ReviewPolicy get value => noReviewPolicy;
}
