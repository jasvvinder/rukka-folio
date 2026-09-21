@Tags(['F1'])
library;

// S16 My account (07 §21 🔒, 13 §3.2 row S16: name, photo, phone, language).
//
// Tests first. The screen runs against `FakeAccountRepository` only — the real
// identity record lands with the auth/server lanes, and this suite must never
// depend on a route shape nobody has agreed yet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/account/account_repository.dart';
import 'package:rukka_folio/features/account/deletion_window.dart';
import 'package:rukka_folio/features/account/screens/s16_my_account_screen.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../../shared/test_app.dart';

const _profile = AccountProfile(
  name: 'Amrit Kaur',
  phone: '+91 98765 43210',
  languageCode: 'en',
);

AccountSnapshot _snap({
  DeletionWindow? window,
  DeletionRequest? request,
  bool readOnly = false,
  AccountProfile profile = _profile,
}) => AccountSnapshot(
  profile: profile,
  window: window,
  request: request,
  readOnly: readOnly,
);

Widget _screen(
  AccountRepository repo, {
  VoidCallback? onEditProfile,
  VoidCallback? onChangePhone,
  VoidCallback? onOpenLanguage,
  VoidCallback? onOpenDelete,
}) => AccountRepositoryScope(
  repository: repo,
  child: MyAccountScreen(
    key: UniqueKey(),
    onEditProfile: onEditProfile,
    onChangePhone: onChangePhone,
    onOpenLanguage: onOpenLanguage,
    onOpenDelete: onOpenDelete,
  ),
);

/// A seam whose first read never comes back — the loading state, which a fake
/// that answers immediately can never show.
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

void main() {
  group('S16 My account (07 §21 🔒, 13 §3.2)', () {
    testWidgets(
      'F1-07-316 populated: the four things 13 §3.2 names — name, photo, '
      'phone, language — and the photo is honestly initials, because the app '
      'has no photo pipeline at all',
      (tester) async {
        final repo = FakeAccountRepository(initial: _snap());
        addTearDown(repo.dispose);
        var edited = 0;
        var language = 0;
        var deleted = 0;
        await pumpRk(
          tester,
          _screen(
            repo,
            onEditProfile: () => edited++,
            onOpenLanguage: () => language++,
            onOpenDelete: () => deleted++,
          ),
          viewport: rkPhone360,
        );

        expect(find.text('My account'), findsOneWidget);
        expect(find.text('Amrit Kaur'), findsWidgets);
        expect(find.text('+91 98765 43210'), findsOneWidget);
        expect(find.text('English'), findsOneWidget);
        // The avatar is the initials of the name, not a silhouette and not a
        // picture: `accountPhotoSupported` is false everywhere.
        expect(accountPhotoSupported, isFalse);
        expect(find.text('AK'), findsOneWidget);
        expect(find.text('Your initials'), findsOneWidget);
        expect(
          find.text(
            'Photos are not in this version. Your initials stand in for one.',
          ),
          findsOneWidget,
        );

        await _reveal(tester, find.byKey(const Key('account.row.name')));
        await tester.tap(find.byKey(const Key('account.row.name')));
        await tester.pumpAndSettle();
        expect(edited, 1);

        await _reveal(tester, find.byKey(const Key('account.row.language')));
        await tester.tap(find.byKey(const Key('account.row.language')));
        await tester.pumpAndSettle();
        expect(language, 1);

        await _reveal(tester, find.byKey(const Key('account.row.delete')));
        await tester.tap(find.byKey(const Key('account.row.delete')));
        await tester.pumpAndSettle();
        expect(deleted, 1);
      },
    );

    testWidgets(
      'F1-07-317 the states of 13 §4.3 that are not the content: the ruled '
      'skeleton while nothing has loaded, error-with-retry that actually '
      'retries, and the offline line that never blocks',
      (tester) async {
        await pumpRk(tester, _screen(_Pending()), viewport: rkPhone360);
        expect(find.byType(RkSkeleton), findsOneWidget);
        expect(
          find.bySemanticsLabel('Loading your account.'),
          findsOneWidget,
          reason: 'the wait is stated in words, not only in grey rules',
        );

        final failing = FakeAccountRepository()
          ..failNext = const AccountFailure('offline');
        addTearDown(failing.dispose);
        await pumpRk(tester, _screen(failing), viewport: rkPhone360);
        expect(find.text('Couldn’t load your account.'), findsOneWidget);
        failing.onRefresh = _snap();
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Amrit Kaur'), findsWidgets);

        final repo = FakeAccountRepository(initial: _snap());
        addTearDown(repo.dispose);
        final sync = FakeSyncClient(initial: const Offline());
        await pumpRk(tester, _screen(repo), sync: sync, viewport: rkPhone360);
        expect(
          find.text('Offline — showing what this phone last saw.'),
          findsOneWidget,
        );
        // Non-blocking: the rows are still there and still tappable.
        expect(find.byKey(const Key('account.row.name')), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-318 no dead ends (07 §1 rule 6): the change-phone row is a row '
      'with a reason, never a missing door and never a tap that does nothing '
      '— and read-only says what still works',
      (tester) async {
        final repo = FakeAccountRepository(initial: _snap());
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkPhone360);
        await _reveal(tester, find.byKey(const Key('account.row.phone')));
        expect(
          find.text('Changing your number is not in this version yet.'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('account.row.phone')),
            matching: find.byType(InkWell),
          ),
          findsNothing,
          reason: 'disabled-with-reason, not a fake link (13 §4.3)',
        );

        var changed = 0;
        await pumpRk(
          tester,
          _screen(repo, onChangePhone: () => changed++),
          viewport: rkPhone360,
        );
        await _reveal(tester, find.byKey(const Key('account.row.phone')));
        await tester.tap(find.byKey(const Key('account.row.phone')));
        await tester.pumpAndSettle();
        expect(changed, 1, reason: 'S16.2 lands and the row becomes a door');

        final ro = FakeAccountRepository(initial: _snap(readOnly: true));
        addTearDown(ro.dispose);
        await pumpRk(tester, _screen(ro), viewport: rkPhone360);
        expect(
          find.text('You can’t change your details right now'),
          findsOneWidget,
        );
        expect(
          find.text('Deleting your account still works, and so does export.'),
          findsOneWidget,
        );
        // Deletion is a right, not a feature: the row stays a door.
        await _reveal(tester, find.byKey(const Key('account.row.delete')));
        expect(find.byKey(const Key('account.row.delete')), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-319 a running 15-day window shows on S16 as a state with its '
      'date and days left; a support request shows as a card to accept and '
      'never as a started clock (ADR 2026-09-05h §2)',
      (tester) async {
        final running = FakeAccountRepository(
          initial: _snap(
            window: DeletionWindow(
              id: 'd1',
              origin: DeletionOrigin.user,
              startedAt: testNow(),
            ),
          ),
        );
        addTearDown(running.dispose);
        await pumpRk(tester, _screen(running), viewport: rkPhone360);
        expect(find.text('Your account is set to be deleted'), findsOneWidget);
        expect(
          find.text(
            'On 22 Sep 2026. Until then nothing has been erased, and you can '
            'stop it.',
          ),
          findsOneWidget,
        );
        expect(find.text('15 days left'), findsOneWidget);

        final asked = FakeAccountRepository(
          initial: _snap(
            request: DeletionRequest(id: 'r1', requestedAt: testNow()),
          ),
        );
        addTearDown(asked.dispose);
        var opened = 0;
        await pumpRk(
          tester,
          _screen(asked, onOpenDelete: () => opened++),
          viewport: rkPhone360,
        );
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
        // No clock anywhere: a request is not a countdown.
        expect(find.textContaining('days left'), findsNothing);
        expect(find.textContaining('Until then'), findsNothing);
        await tester.tap(find.text('Read what this means'));
        await tester.pumpAndSettle();
        expect(opened, 1);
      },
    );

    testWidgets(
      'F1-07-320 EN, ਪੰਜਾਬੀ and हिन्दी all fit at 130 % and 200 % on 360×800 '
      'and 375×667, with the deletion state on screen',
      (tester) async {
        for (final locale in rkLocales) {
          for (final size in rkPhones) {
            for (final scale in rkTextScales) {
              final repo = FakeAccountRepository(
                initial: _snap(
                  window: DeletionWindow(
                    id: 'd1',
                    origin: DeletionOrigin.user,
                    startedAt: testNow(),
                  ),
                ),
              );
              addTearDown(repo.dispose);
              await pumpRk(
                tester,
                _screen(repo),
                locale: locale,
                textScale: scale,
                viewport: size,
              );
              expect(tester.takeException(), isNull);
              expectTextFits(
                tester,
                reason:
                    'S16 ${locale.languageCode} @$scale ${size.width.toInt()}',
              );
            }
          }
        }
      },
    );
  });
}
