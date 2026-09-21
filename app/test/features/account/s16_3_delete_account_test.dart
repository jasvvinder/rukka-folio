@Tags(['F1'])
library;

// S16.3 Delete account — 15-day cooling, what is erased vs retained
// (07 §21 🔒, 06 §9.3 🔒, ADR 2026-09-05h §2; 13 §3.2 row S16.3).
//
// Tests first, and they are mostly about honesty. The cooling period is a
// **state** the screen lives in, not a dialog it throws; and the screen must
// never claim an erasure the architecture does not perform — the entries the
// user wrote in a shared book stay, and so does the material that lets other
// phones verify them (06 §9.3 🔒).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/account/account_repository.dart';
import 'package:rukka_folio/features/account/deletion_window.dart';
import 'package:rukka_folio/features/account/screens/s16_3_delete_account_screen.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../../shared/test_app.dart';

const _profile = AccountProfile(
  name: 'Amrit Kaur',
  phone: '+91 98765 43210',
  languageCode: 'en',
);

AccountSnapshot _snap({DeletionWindow? window, DeletionRequest? request}) =>
    AccountSnapshot(profile: _profile, window: window, request: request);

DeletionWindow _running({DeletionOrigin origin = DeletionOrigin.user}) =>
    DeletionWindow(id: 'd1', origin: origin, startedAt: testNow());

Widget _screen(AccountRepository repo) => AccountRepositoryScope(
  repository: repo,
  child: DeleteAccountScreen(key: UniqueKey()),
);

Finder get _ack => find.byKey(const Key('account.delete.ack'));
Finder get _start => find.byKey(const Key('account.delete.start'));
Finder get _cancel => find.byKey(const Key('account.delete.cancel'));
Finder get _accept => find.byKey(const Key('account.delete.accept'));
Finder get _decline => find.byKey(const Key('account.delete.decline'));

bool _enabled(WidgetTester tester, Finder f) =>
    tester.widget<ButtonStyleButton>(f).onPressed != null;

Future<void> _reveal(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      120,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 80,
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

/// A repository whose first read never comes back — the loading state.
final class _Pending implements AccountRepository {
  @override
  AccountSnapshot? get current => null;

  @override
  Stream<AccountSnapshot> watch() => const Stream.empty();

  @override
  Future<void> refresh() => Completer<void>().future;

  @override
  Future<void> setName(String name, {String lang = 'en'}) =>
      Completer<void>().future;

  @override
  Future<void> startDeletion() => Completer<void>().future;

  @override
  Future<void> acceptDeletionRequest(String id) => Completer<void>().future;

  @override
  Future<void> declineDeletionRequest(String id) => Completer<void>().future;

  @override
  Future<void> cancelDeletion() => Completer<void>().future;
}

void main() {
  group('S16.3 Delete account (06 §9.3 🔒, ADR 2026-09-05h §2)', () {
    testWidgets(
      'F1-07-325 both lists are on the one screen: what is erased, and what '
      'stays with the reason it stays — the screen never claims an erasure '
      'the architecture does not perform (06 §9.3 🔒)',
      (tester) async {
        final repo = FakeAccountRepository(initial: _snap());
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkTallViewport);

        expect(find.text('What is erased'), findsOneWidget);
        expect(
          find.text('Your name, photo, number and language.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Every key of yours we hold, so nothing of yours can be opened '
            'again.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Your personal book, entry by entry.'),
          findsOneWidget,
        );
        expect(
          find.text('Every phone signed in as you is signed out.'),
          findsOneWidget,
        );

        expect(find.text('What stays, and why'), findsOneWidget);
        expect(
          find.text(
            'Entries you wrote in a shared book stay. They are that book’s '
            'records, not yours alone — your name on them becomes a fixed '
            'label.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('your public key and your phones’ certificates'),
          findsOneWidget,
        );
        // Export is the way out that always works (06 §9.2 🔒) — no dead end.
        expect(find.text('Take your books with you first'), findsOneWidget);
        // 01 §1 rule 4: no jargon reaches a consumer surface.
        for (final word in const [
          'journal',
          'voucher',
          'contra',
          'accrual',
          'narration',
          'debit',
          'credit',
        ]) {
          expect(
            find.textContaining(RegExp(word, caseSensitive: false)),
            findsNothing,
            reason: '"$word" must not appear on S16.3',
          );
        }
      },
    );

    testWidgets(
      'F1-07-326 starting the 15 days takes two deliberate acts: until the '
      'line is ticked the action is disabled-with-reason, and the tap starts '
      'a clock, never an erasure',
      (tester) async {
        final repo = FakeAccountRepository(initial: _snap(), now: testNow);
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkTallViewport);

        expect(find.text('Start the 15 days'), findsOneWidget);
        expect(_enabled(tester, _start), isFalse);
        expect(find.text('Tick the line above first.'), findsOneWidget);

        await _reveal(tester, _ack);
        await tester.tap(_ack);
        await tester.pumpAndSettle();
        expect(_enabled(tester, _start), isTrue);
        expect(find.text('Tick the line above first.'), findsNothing);

        await _reveal(tester, _start);
        await tester.tap(_start);
        await tester.pumpAndSettle();
        expect(repo.deletionsStarted, 1);
        // The screen moves into the running state; nothing is gone yet.
        expect(find.text('The 15 days are running'), findsOneWidget);
        expect(
          find.text(
            'Your account will be deleted on 22 Sep 2026. Nothing has been '
            'erased yet.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-07-327 the cooling period is a state, not a dialog: the date, the '
      'days left, who was told, Cancel still working at 14 d 23 h 59 — and at '
      'exactly 15 days the window is over and offers no Cancel (06 §9.3 🔒)',
      (tester) async {
        final repo = FakeAccountRepository(initial: _snap(window: _running()));
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkTallViewport);

        expect(find.text('The 15 days are running'), findsOneWidget);
        expect(find.text('15 days left'), findsOneWidget);
        expect(
          find.text(
            'Every phone of yours and every trusted member has been told.',
          ),
          findsOneWidget,
        );
        expect(_enabled(tester, _cancel), isTrue);

        // The last minute of the window: cancel-anytime still means anytime.
        final late = FakeAccountRepository(initial: _snap(window: _running()));
        addTearDown(late.dispose);
        final lastMinute = testNow().add(
          const Duration(days: 14, hours: 23, minutes: 59),
        );
        await pumpRk(
          tester,
          _screen(late),
          now: () => lastMinute,
          viewport: rkTallViewport,
        );
        expect(find.text('1 day left'), findsOneWidget);
        expect(_enabled(tester, _cancel), isTrue);
        await _reveal(tester, _cancel);
        await tester.tap(_cancel);
        await tester.pumpAndSettle();
        expect(late.deletionsCancelled, 1);
        expect(find.text('Stopped. Your account stays.'), findsOneWidget);

        // Exactly at 15 days it is complete: the cancel is gone, and the
        // screen says so rather than leaving a button that cannot work.
        final over = FakeAccountRepository(initial: _snap(window: _running()));
        addTearDown(over.dispose);
        await pumpRk(
          tester,
          _screen(over),
          now: () => testNow().add(DeletionWindow.cooling),
          viewport: rkTallViewport,
        );
        expect(find.text('The 15 days are over'), findsOneWidget);
        expect(
          find.text(
            'Your account is being erased. This can no longer be stopped.',
          ),
          findsOneWidget,
        );
        expect(_cancel, findsNothing);
      },
    );

    testWidgets(
      'F1-07-328 a support request lands as a card to accept and never as a '
      'started clock: nothing runs until this phone accepts, and declining '
      'stops nothing because nothing was running (ADR 2026-09-05h §2)',
      (tester) async {
        final repo = FakeAccountRepository(
          initial: _snap(
            request: DeletionRequest(id: 'r1', requestedAt: testNow()),
          ),
          now: testNow,
        );
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkTallViewport);

        expect(
          find.text('Support has been asked to delete your account'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Nothing has started. Only you, on your own phone, can start the '
            '15 days.',
          ),
          findsOneWidget,
        );
        expect(find.text('Asked on 07 Sep 2026'), findsOneWidget);
        // No countdown exists yet — a request is not a window.
        expect(find.textContaining('days left'), findsNothing);
        expect(find.text('The 15 days are running'), findsNothing);
        expect(repo.current!.window, isNull);

        await _reveal(tester, _decline);
        await tester.tap(_decline);
        await tester.pumpAndSettle();
        expect(repo.declined, ['r1']);
        expect(repo.deletionsStarted, 0);
        expect(repo.current!.window, isNull);
        expect(
          find.text('Nothing was running. The request is gone.'),
          findsOneWidget,
        );

        // Accepting is what starts the clock — and it is the user's device
        // that does it.
        final second = FakeAccountRepository(
          initial: _snap(
            request: DeletionRequest(id: 'r2', requestedAt: testNow()),
          ),
          now: testNow,
        );
        addTearDown(second.dispose);
        await pumpRk(tester, _screen(second), viewport: rkTallViewport);
        await _reveal(tester, _ack);
        await tester.tap(_ack);
        await tester.pumpAndSettle();
        await _reveal(tester, _accept);
        await tester.tap(_accept);
        await tester.pumpAndSettle();
        expect(second.accepted, ['r2']);
        expect(second.current!.window!.origin, DeletionOrigin.support);
        expect(find.text('The 15 days are running'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-329 the rest of 13 §4.3 — skeleton, error-with-retry — and EN, '
      'ਪੰਜਾਬੀ, हिन्दी at 130 % and 200 % on 360×800 and 375×667',
      (tester) async {
        await pumpRk(tester, _screen(_Pending()), viewport: rkPhone360);
        expect(find.byType(RkSkeleton), findsOneWidget);

        final repo = FakeAccountRepository(initial: _snap(), now: testNow);
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkTallViewport);
        repo.failNext = const AccountFailure('no network');
        await _reveal(tester, _ack);
        await tester.tap(_ack);
        await tester.pumpAndSettle();
        await _reveal(tester, _start);
        await tester.tap(_start);
        await tester.pumpAndSettle();
        expect(find.text('Couldn’t start the deletion.'), findsOneWidget);
        // The way forward survives the failure.
        expect(_enabled(tester, _start), isTrue);
        await tester.tap(_start);
        await tester.pumpAndSettle();
        expect(repo.deletionsStarted, 1);

        for (final locale in rkLocales) {
          for (final size in rkPhones) {
            for (final scale in rkTextScales) {
              final r = FakeAccountRepository(
                initial: _snap(window: _running()),
              );
              addTearDown(r.dispose);
              await pumpRk(
                tester,
                _screen(r),
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              expect(tester.takeException(), isNull);
              expectTextFits(
                tester,
                reason:
                    'S16.3 ${locale.languageCode} @$scale '
                    '${size.width.toInt()}',
              );
            }
          }
        }
      },
    );
  });
}
