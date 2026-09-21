@Tags(['F1'])
library;

// S16.1 Edit profile — **name and photo only** (13 §3.2 row S16.1, 07 §21 🔒).
//
// Tests first. There is no photo pipeline in the app, so the photo half of
// this screen is a statement rather than a control; these tests hold it to
// that, because a picker that does nothing is the dead end 07 §1 rule 6
// forbids.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/account/account_repository.dart';
import 'package:rukka_folio/features/account/screens/s16_1_edit_profile_screen.dart';

import '../../shared/test_app.dart';

const _profile = AccountProfile(
  name: 'Amrit Kaur',
  phone: '+91 98765 43210',
  languageCode: 'en',
);

Widget _screen(AccountRepository repo, {VoidCallback? onDone}) =>
    AccountRepositoryScope(
      repository: repo,
      child: EditProfileScreen(key: UniqueKey(), onDone: onDone),
    );

Finder get _name => find.byKey(const Key('account.edit.name'));
Finder get _save => find.byKey(const Key('account.edit.save'));

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_save).onPressed != null;

/// A repository whose save never comes back — the loading state.
final class _Slow extends FakeAccountRepository {
  _Slow({super.initial});

  @override
  Future<void> setName(String name, {String lang = 'en'}) =>
      Completer<void>().future;
}

void main() {
  group('S16.1 Edit profile (13 §3.2 row S16.1)', () {
    testWidgets(
      'F1-07-321 a new name reaches the seam trimmed and with its script tag '
      '(01 §1 rule 9 🔒); Save is disabled-with-reason while nothing has '
      'changed and while the field is blank',
      (tester) async {
        final repo = FakeAccountRepository(
          initial: const AccountSnapshot(profile: _profile),
        );
        addTearDown(repo.dispose);
        var done = 0;
        await pumpRk(
          tester,
          _screen(repo, onDone: () => done++),
          viewport: rkPhone360,
        );

        expect(find.text('Edit profile'), findsOneWidget);
        expect(_saveEnabled(tester), isFalse);
        expect(find.text('Nothing has changed yet.'), findsOneWidget);

        await tester.enterText(_name, '   ');
        await tester.pumpAndSettle();
        expect(_saveEnabled(tester), isFalse);
        expect(find.text('Type a name first.'), findsOneWidget);

        await tester.enterText(_name, '  Amrit Kaur Sidhu  ');
        await tester.pumpAndSettle();
        expect(_saveEnabled(tester), isTrue);
        await tester.tap(_save);
        await tester.pumpAndSettle();

        expect(repo.renames, hasLength(1));
        expect(repo.renames.single.name, 'Amrit Kaur Sidhu');
        expect(repo.renames.single.lang, 'en');
        expect(done, 1);
      },
    );

    testWidgets(
      'F1-07-322 the photo half is honest: initials stand in, the reason is '
      'on screen, and there is no picker to tap — nothing claims a photo was '
      'saved',
      (tester) async {
        final repo = FakeAccountRepository(
          initial: const AccountSnapshot(profile: _profile),
        );
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkPhone360);

        expect(accountPhotoSupported, isFalse);
        expect(find.text('AK'), findsOneWidget);
        expect(
          find.text(
            'Photos are not in this version. Your initials stand in for one, '
            'in your own script.',
          ),
          findsOneWidget,
        );
        // The initials follow the typed name, in whatever script it is in.
        await tester.enterText(_name, 'ਸੁਨੀਤਾ ਕੌਰ');
        await tester.pumpAndSettle();
        expect(find.text('ਸੁਕੌ'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-323 the two remaining states of 13 §4.3: saving, and a failure '
      'that keeps the typed name and leaves Save as the retry',
      (tester) async {
        final slow = _Slow(initial: const AccountSnapshot(profile: _profile));
        addTearDown(slow.dispose);
        await pumpRk(tester, _screen(slow), viewport: rkPhone360);
        await tester.enterText(_name, 'Amrit K');
        await tester.pumpAndSettle();
        await tester.tap(_save);
        await tester.pump();
        expect(find.text('Saving…'), findsOneWidget);
        expect(_saveEnabled(tester), isFalse);

        final repo = FakeAccountRepository(
          initial: const AccountSnapshot(profile: _profile),
        );
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkPhone360);
        // Set after the first load, so the failure under test is the *save*.
        repo.failNext = const AccountFailure('no network');
        await tester.enterText(_name, 'Amrit K');
        await tester.pumpAndSettle();
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(find.text('Couldn’t save your name.'), findsOneWidget);
        expect(find.text('Amrit K'), findsOneWidget);
        expect(_saveEnabled(tester), isTrue);
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(repo.renames.single.name, 'Amrit K');
      },
    );

    testWidgets(
      'F1-07-324 EN, ਪੰਜਾਬੀ and हिन्दी all fit at 130 % and 200 % on 360×800 '
      'and 375×667, including the photo statement and the read-only reason',
      (tester) async {
        for (final locale in rkLocales) {
          for (final size in rkPhones) {
            for (final scale in rkTextScales) {
              final repo = FakeAccountRepository(
                initial: const AccountSnapshot(
                  profile: _profile,
                  readOnly: true,
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
                    'S16.1 ${locale.languageCode} @$scale '
                    '${size.width.toInt()}',
              );
            }
          }
        }
      },
    );
  });
}
