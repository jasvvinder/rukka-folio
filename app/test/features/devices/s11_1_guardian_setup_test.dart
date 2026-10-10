@Tags(['F1'])
library;

// S11.1 Guardian setup — the mutual-ceremony screen behind the S11 *Trusted
// members* row (13 §3.2, 07 §15, 04 §7.3 🔒, ADR 2026-09-06 checklist 4 🔒,
// DESIGN-PACK canvas 2b R3.2).
//
// Tests first. The screen runs against `FakeGuardians` only — the real
// repository over the server routes is a later lane, and this suite must never
// depend on a route shape nobody has agreed yet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/ceremony/ceremony_paths.dart';
import 'package:rukka_folio/features/devices/devices_routes.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/guardians.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../../shared/test_app.dart';

TrustedMemberCandidate _c(
  String id,
  String name, {
  GuardianCeremony ceremony = GuardianCeremony.done,
}) => TrustedMemberCandidate(memberId: id, name: name, ceremony: ceremony);

/// Three verified members — the default 2-of-3 shape of 04 §7.3.
List<TrustedMemberCandidate> _three() => [
  _c('m1', 'Sunita'),
  _c('m2', 'Harpreet'),
  _c('m3', 'Gurmeet'),
];

Widget _screen(
  GuardiansRepository repo, {
  void Function(TrustedMemberCandidate)? onMeet,
  GuardianMeetBlock? Function(TrustedMemberCandidate)? meetBlockOf,
  VoidCallback? onAddMember,
  VoidCallback? onDone,
}) => GuardiansScope(
  repository: repo,
  // A fresh key per pump: several of these tests pump a second screen into the
  // same tester, and without it Flutter reuses the first screen's State.
  child: GuardianSetupScreen(
    key: UniqueKey(),
    onMeet: onMeet ?? (_) {},
    meetBlockOf: meetBlockOf ?? (_) => null,
    onAddMember: onAddMember,
    onDone: onDone,
  ),
);

Finder get _save => find.byKey(const Key('guardians.save'));
Finder _member(String id) => find.byKey(Key('guardians.member.$id'));

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_save).onPressed != null;

/// The page scrolls — at 200 % it scrolls a lot — so reach a row before
/// tapping it rather than tapping where it would be on a tall screen.
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

/// Back to the top of the list, where the rule line lives.
Future<void> _top(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String id) async {
  await _reveal(tester, _member(id));
  await tester.tap(_member(id));
  await tester.pumpAndSettle();
}

/// A seam whose first read never comes back — the loading state, which a
/// fake that answers immediately can never show.
final class _Pending implements GuardiansRepository {
  @override
  GuardianSetup? get current => null;

  @override
  Stream<GuardianSetup> watch() => const Stream.empty();

  @override
  Future<void> refresh() => Completer<void>().future;

  @override
  Future<void> save(List<String> memberIds) => Completer<void>().future;
}

void main() {
  group('S11.1 Guardian setup (13 §3.2, 04 §7.3 🔒)', () {
    testWidgets(
      'F1-06-21 populated: every member of the book with where the mutual '
      'ceremony stands, the threshold as a sentence once three are chosen, '
      '“Meet them” on the one not yet met — and Save disabled with its reason '
      'until that meeting is done (04 §8.2 🔒)',
      (tester) async {
        final repo = FakeGuardians(
          initial: GuardianSetup(
            candidates: [
              _c('m1', 'Sunita'),
              _c('m2', 'Harpreet'),
              _c('m3', 'Gurmeet', ceremony: GuardianCeremony.notStarted),
            ],
          ),
        );
        addTearDown(repo.dispose);
        var met = 0;
        await tester.runAsync(() async {});
        await pumpRk(
          tester,
          _screen(repo, onMeet: (_) => met++),
          viewport: rkPhone360,
        );

        expect(find.text('Trusted members'), findsOneWidget);
        expect(find.text('Sunita'), findsOneWidget);
        expect(find.text('Harpreet'), findsOneWidget);
        expect(find.text('Gurmeet'), findsOneWidget);
        // Ceremony state is a word plus an icon — colour never alone (07 §1.3).
        expect(find.text('Met and verified'), findsNWidgets(2));
        expect(find.text('Not met yet'), findsOneWidget);
        // Nothing is chosen yet: the rule line asks for people.
        expect(
          find.text('Choose at least 2 people. Three is the usual choice.'),
          findsOneWidget,
        );
        expect(_saveEnabled(tester), isFalse);

        await _choose(tester, 'm1');
        await _choose(tester, 'm2');
        await _choose(tester, 'm3');
        await _top(tester);
        expect(
          find.text('Any 2 of the 3 you choose can help you get back in.'),
          findsOneWidget,
        );
        // One of the three has not been met: still blocked, and it says why.
        expect(_saveEnabled(tester), isFalse);
        expect(
          find.text('Meet everyone you have chosen before saving.'),
          findsOneWidget,
        );

        await _reveal(tester, find.byKey(const Key('guardians.meet.m3')));
        await tester.tap(find.byKey(const Key('guardians.meet.m3')));
        await tester.pumpAndSettle();
        expect(
          met,
          1,
          reason: 'S11.1 hands the ceremony to S9.3, never runs it',
        );
      },
    );

    testWidgets(
      'F1-06-22 the threshold is a sentence for every n it allows — 2-of-2, '
      '2-of-3, 3-of-4, 3-of-5 — and never a formula on screen (04 §7.3 🔒)',
      (tester) async {
        const expected = {2: 2, 3: 2, 4: 3, 5: 3};
        for (final n in expected.keys) {
          final repo = FakeGuardians(
            initial: GuardianSetup(
              candidates: [for (var i = 1; i <= 5; i++) _c('m$i', 'Member $i')],
            ),
          );
          addTearDown(repo.dispose);
          await pumpRk(tester, _screen(repo), viewport: rkPhone360);
          for (var i = 1; i <= n; i++) {
            await _choose(tester, 'm$i');
          }
          await _top(tester);
          expect(
            find.text(
              'Any ${expected[n]} of the $n you choose can help you get back in.',
            ),
            findsOneWidget,
            reason: 'n = $n states k = ${expected[n]} in words',
          );
          // No formula reaches the screen.
          for (final t in tester.widgetList<Text>(find.byType(Text))) {
            final s = t.data ?? '';
            expect(s.contains('⌈'), isFalse, reason: s);
            expect(s.contains('k ='), isFalse, reason: s);
            expect(s.contains('k-of-n'), isFalse, reason: s);
          }
        }
      },
    );

    testWidgets(
      'F1-06a-1 🔒 2-of-2 is permitted only behind a typed confirmation '
      '(ADR 2026-09-06 checklist 4): with two chosen the button stays '
      'disabled, tapping every other control on the screen never enables it, '
      'no dialog or dismissible warning exists, and only the typed phrase '
      'turns it on — clearing the phrase turns it off again',
      (tester) async {
        final repo = FakeGuardians(
          initial: GuardianSetup(
            candidates: [_c('m1', 'Sunita'), _c('m2', 'Harpreet')],
          ),
        );
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkPhone360);

        await _choose(tester, 'm1');
        await _choose(tester, 'm2');
        expect(find.text('Only two people'), findsOneWidget);
        expect(
          find.text(
            'With two, both of them must help you. If one of them cannot be '
            'reached, nobody can let you back in. Three is safer.',
          ),
          findsOneWidget,
        );
        expect(_saveEnabled(tester), isFalse);

        // There is no dismissible path: no dialog, no sheet, and every other
        // button on the screen leaves Save disabled.
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(Dismissible), findsNothing);
        expect(find.byIcon(Icons.close), findsNothing);
        final buttons = find.byWidgetPredicate(
          (w) => w is ButtonStyleButton || w is IconButton,
        );
        for (var i = 0; i < tester.widgetList(buttons).length; i++) {
          final f = buttons.at(i);
          if (tester.widget(f).key == const Key('guardians.save')) continue;
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          await tester.tap(f, warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(
            _saveEnabled(tester),
            isFalse,
            reason: 'no control other than the typed phrase may enable 2-of-2',
          );
          expect(find.byType(AlertDialog), findsNothing);
        }
        expect(repo.saved, isEmpty);

        // Wrong words do not do it either.
        await tester.enterText(
          find.byKey(const Key('guardians.two.field')),
          'yes',
        );
        await tester.pumpAndSettle();
        expect(_saveEnabled(tester), isFalse);

        await tester.enterText(
          find.byKey(const Key('guardians.two.field')),
          'I need both',
        );
        await tester.pumpAndSettle();
        expect(_saveEnabled(tester), isTrue);

        await tester.enterText(
          find.byKey(const Key('guardians.two.field')),
          '',
        );
        await tester.pumpAndSettle();
        expect(_saveEnabled(tester), isFalse);
      },
    );

    testWidgets(
      'F1-06-24 the screen renders no key material: no share, no QR, no '
      'Base32 group anywhere in the tree, and it says so in plain words '
      '(04 §7.4 / 07 §5.6, the S0.5b precedent)',
      (tester) async {
        final repo = FakeGuardians(
          initial: GuardianSetup(
            candidates: _three(),
            chosenIds: const ['m1', 'm2', 'm3'],
          ),
        );
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkPhone360);

        expect(
          find.text(
            'Nothing secret is shown here. Your key never appears on this '
            'screen, and they never see your entries.',
          ),
          findsOneWidget,
        );
        for (final icon in const [
          Icons.qr_code,
          Icons.qr_code_2,
          Icons.qr_code_scanner,
        ]) {
          expect(find.byIcon(icon), findsNothing);
        }
        // Crockford Base32 groups (04 §7.4) and hex blobs: none of them.
        final base32 = RegExp(r'[0-9A-HJ-NP-TV-Z]{4}[- ][0-9A-HJ-NP-TV-Z]{4}');
        final hex = RegExp(r'\b[0-9a-f]{16,}\b');
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          final s = t.data ?? '';
          expect(base32.hasMatch(s), isFalse, reason: 'base32-shaped: "$s"');
          expect(hex.hasMatch(s), isFalse, reason: 'key-shaped: "$s"');
        }
      },
    );

    testWidgets(
      'F1-06-25 the states of 13 §4.3: loading skeleton, empty with its one '
      'next action, error with retry, the non-blocking offline line, and the '
      'read-only variant where nothing can be changed',
      (tester) async {
        // Loading — the first read has not come back yet.
        await pumpRk(tester, _screen(_Pending()), viewport: rkPhone360);
        expect(find.byType(RkSkeleton), findsOneWidget);
        expect(
          find.bySemanticsLabel('Loading members'),
          findsOneWidget,
          reason: 'the wait is stated in words, not only in grey rules',
        );

        // Empty — the book has nobody else yet.
        final empty = FakeGuardians(initial: const GuardianSetup());
        addTearDown(empty.dispose);
        var added = 0;
        await pumpRk(
          tester,
          _screen(empty, onAddMember: () => added++),
          viewport: rkPhone360,
        );
        expect(find.text('No one to choose yet'), findsOneWidget);
        await tester.tap(find.text('Add a member'));
        await tester.pumpAndSettle();
        expect(added, 1);

        // Error with retry.
        final bad = FakeGuardians(failRefresh: true);
        addTearDown(bad.dispose);
        await pumpRk(tester, _screen(bad), viewport: rkPhone360);
        await tester.pumpAndSettle();
        expect(find.text('Could not load your members.'), findsOneWidget);
        bad.failRefresh = false;
        bad.emit(GuardianSetup(candidates: _three()));
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Sunita'), findsOneWidget);

        // Offline — a line, never a block.
        final offline = FakeGuardians(
          initial: GuardianSetup(candidates: _three()),
        );
        addTearDown(offline.dispose);
        final sync = FakeSyncClient(initial: const Offline());
        await pumpRk(
          tester,
          _screen(offline),
          sync: sync,
          viewport: rkPhone360,
        );
        expect(
          find.text(
            'You are offline. Your choice is saved on this phone and goes out '
            'when you are back.',
          ),
          findsOneWidget,
        );
        await _choose(tester, 'm1');
        await _choose(tester, 'm2');
        expect(_saveEnabled(tester), isFalse, reason: '2-of-2 still typed');

        // Read-only.
        final ro = FakeGuardians(
          initial: GuardianSetup(
            candidates: _three(),
            chosenIds: const ['m1', 'm2', 'm3'],
            readOnly: true,
          ),
        );
        addTearDown(ro.dispose);
        await pumpRk(tester, _screen(ro), viewport: rkPhone360);
        expect(
          find.text(
            'Read-only right now. You can see your trusted members but not '
            'change them.',
          ),
          findsOneWidget,
        );
        await _top(tester);
        expect(find.text('In force now: any 2 of 3.'), findsOneWidget);
        expect(_saveEnabled(tester), isFalse);
        await _choose(tester, 'm1');
        expect(ro.saved, isEmpty);
      },
    );

    testWidgets(
      'F1-06-26 Save hands the seam exactly the chosen ids and nothing else; '
      'the screen reports it saved and leaves',
      (tester) async {
        final repo = FakeGuardians(
          initial: GuardianSetup(candidates: _three()),
        );
        addTearDown(repo.dispose);
        var done = 0;
        await pumpRk(
          tester,
          _screen(repo, onDone: () => done++),
          viewport: rkPhone360,
        );
        await _choose(tester, 'm1');
        await _choose(tester, 'm3');
        await _choose(tester, 'm2');
        expect(_saveEnabled(tester), isTrue);
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(repo.saved, [
          ['m1', 'm3', 'm2'],
        ]);
        expect(find.text('Trusted members saved.'), findsOneWidget);
        expect(done, 1);
      },
    );

    testWidgets(
      'F1-06-27 a save that fails says so in plain words and leaves the '
      'choice on screen to try again — no raw code (07 §1 rule 12)',
      (tester) async {
        final repo = FakeGuardians(
          initial: GuardianSetup(candidates: _three()),
          failSave: true,
        );
        addTearDown(repo.dispose);
        await pumpRk(tester, _screen(repo), viewport: rkPhone360);
        await _choose(tester, 'm1');
        await _choose(tester, 'm2');
        await _choose(tester, 'm3');
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(find.text('That did not save. Try again.'), findsOneWidget);
        expect(find.textContaining('GuardiansFailure'), findsNothing);
        expect(_saveEnabled(tester), isTrue);
      },
    );

    testWidgets(
      'F1-06-28 the bounds of 04 §7.3: a sixth person cannot be chosen and '
      'the screen says why; “Meet them” is disabled with its reason for a '
      'member who has not finished joining (06 §7 🔒 `invited`; 13 §4.3 '
      'disabled-with-reason)',
      (tester) async {
        final repo = FakeGuardians(
          initial: GuardianSetup(
            candidates: [
              for (var i = 1; i <= 5; i++) _c('m$i', 'Member $i'),
              _c('m6', 'Member 6'),
              _c('m7', 'Balbir', ceremony: GuardianCeremony.notStarted),
            ],
          ),
        );
        addTearDown(repo.dispose);
        // The production mapping, over a roster where m7 is still `invited`.
        final members = FakeMembersRepository(
          initial: MembersSnapshot(
            members: [
              for (var i = 1; i <= 6; i++)
                Member(id: 'm$i', state: MembershipState.active),
              const Member(id: 'm7', state: MembershipState.invited),
            ],
          ),
        );
        await pumpRk(
          tester,
          _screen(repo, meetBlockOf: guardianMeetBlockFrom(members)),
          viewport: rkPhone360,
        );
        for (var i = 1; i <= 5; i++) {
          await _choose(tester, 'm$i');
        }
        await _top(tester);
        expect(find.text('Five is the most you can choose.'), findsOneWidget);
        await _choose(tester, 'm6');
        expect(repo.saved, isEmpty);
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(repo.saved.single.length, 5);

        await _reveal(tester, find.byKey(const Key('guardians.meet.m7')));
        expect(
          find.text(
            'You can do this once Balbir has finished joining the book.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('guardians.meet.m7')),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'F1-196-10 S11.1 over a held engine (Offline underneath) shows no '
      'offline note; once registered the real note shows '
      '(ADR 2026-10-10 §2 🔒)',
      (tester) async {
        final repo = FakeGuardians(
          initial: GuardianSetup(candidates: _three()),
        );
        addTearDown(repo.dispose);
        final sync = FakeSyncClient(initial: const Offline(), held: true);
        addTearDown(sync.dispose);
        await pumpRk(tester, _screen(repo), sync: sync, viewport: rkPhone360);
        const note =
            'You are offline. Your choice is saved on this phone and goes out '
            'when you are back.';
        expect(find.text(note), findsNothing);
        expect(find.text('Sunita'), findsOneWidget);

        sync.held = false;
        await tester.pumpAndSettle();
        expect(find.text(note), findsOneWidget);
      },
    );

    testWidgets('F1-07-545 “Meet them” reaches S9.3 for the member’s **user id** through '
        'the real devices route — a candidate with no invite id is still met '
        '(04 §6 one component, four uses; 04 §7.3 🔒 mutual ceremony per '
        'guardian; 07 §1 no dead ends), and an `invited`, `expired` or '
        '`blocked` member is never pushed into S9.3 but disabled with the '
        'reason true for them (06 §7 🔒; 13 §4.3)', (tester) async {
      rkViewport(tester, rkPhone360);
      final repo = FakeGuardians(
        initial: GuardianSetup(
          candidates: [
            _c('m1', 'Sunita'),
            _c('u-balbir', 'Balbir', ceremony: GuardianCeremony.notStarted),
            // Keyed by the invite id, as the server roster keys them.
            _c('inv-jaspal', 'Jaspal', ceremony: GuardianCeremony.notStarted),
            _c('inv-kiran', 'Kiran', ceremony: GuardianCeremony.notStarted),
            _c('u-manjit', 'Manjit', ceremony: GuardianCeremony.notStarted),
          ],
        ),
      );
      addTearDown(repo.dispose);
      final members = FakeMembersRepository(
        initial: const MembersSnapshot(
          members: [
            Member(id: 'm1', state: MembershipState.active),
            Member(
              id: 'u-balbir',
              state: MembershipState.joinedPendingVerification,
            ),
            Member(id: 'inv-jaspal', state: MembershipState.invited),
            Member(id: 'inv-kiran', state: MembershipState.expired),
            Member(id: 'u-manjit', state: MembershipState.blocked),
          ],
        ),
      );
      final router = GoRouter(
        initialLocation: '${DevicesPaths.devices}/guardians',
        routes: [
          ...devicesRoutes,
          GoRoute(
            path: RkPaths.ceremonyVerifyMember,
            builder: (context, state) => Text(
              'verify:${state.pathParameters[CeremonyPaths.subjectParameter]}',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        RkScope(
          db: await openTestDb(),
          sync: FakeSyncClient(),
          auth: FakeAuthClient(),
          keys: FakeKeyStore(),
          now: testNow,
          child: DevicesRepositoryScope(
            repository: FakeDevicesRepository(),
            child: MembersRepositoryScope(
              repository: members,
              child: GuardiansScope(
                repository: repo,
                child: MaterialApp.router(
                  routerConfig: router,
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: rkLocalizationsDelegates,
                  theme: rkTheme(Brightness.light),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Not joined, or blocked: disabled, with the reason that is true.
      for (final (id, why) in [
        (
          'inv-jaspal',
          'You can do this once Jaspal has finished joining the book.',
        ),
        (
          'inv-kiran',
          'You can do this once Kiran has finished joining the book.',
        ),
        (
          'u-manjit',
          'An admin has to look into this before a new invite can go out.',
        ),
      ]) {
        final b = find.byKey(Key('guardians.meet.$id'));
        await _reveal(tester, b);
        expect(tester.widget<OutlinedButton>(b).onPressed, isNull, reason: id);
        expect(
          tester.widget<Text>(find.byKey(Key('guardians.meet.why.$id'))).data,
          why,
        );
      }

      // Balbir sits above the rows just checked; reveal only scrolls down.
      await _top(tester);
      final meet = find.byKey(const Key('guardians.meet.u-balbir'));
      await _reveal(tester, meet);
      expect(
        tester.widget<OutlinedButton>(meet).onPressed,
        isNotNull,
        reason: 'no invite id is not a reason: the ceremony is per member',
      );
      expect(
        find.text('You can do this once Balbir has finished joining the book.'),
        findsNothing,
      );
      await tester.tap(meet);
      await tester.pumpAndSettle();
      // A push leaves the base uri alone; the pushed match is the last one.
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        CeremonyPaths.verifyMemberFor('u-balbir'),
      );
      expect(find.text('verify:u-balbir'), findsOneWidget);
    });

    testWidgets(
      'F1-03c-1 an `invited`, `expired` or `blocked` member cannot be CHOSEN '
      'on S11.1 (ADR 2026-10-03c §4; 04 §7.3 verified keys only): the choice '
      'is disabled with the same reason *Meet them* shows, announced as '
      'disabled with the reason readable (13 §4.3), a tap does not choose '
      'them, and a verified member stays choosable; one already in the set '
      'in force blocks Save with its reason until taken off (no dead end)',
      (tester) async {
        final members = FakeMembersRepository(
          initial: const MembersSnapshot(
            members: [
              Member(id: 'm1', state: MembershipState.active),
              Member(id: 'm2', state: MembershipState.active),
              Member(id: 'm3', state: MembershipState.active),
              Member(id: 'inv-jaspal', state: MembershipState.invited),
              Member(id: 'inv-kiran', state: MembershipState.expired),
              Member(id: 'u-manjit', state: MembershipState.blocked),
            ],
          ),
        );
        List<TrustedMemberCandidate> candidates() => [
          _c('m1', 'Sunita'),
          _c('m2', 'Harpreet'),
          _c('m3', 'Gurmeet'),
          _c('inv-jaspal', 'Jaspal', ceremony: GuardianCeremony.notStarted),
          _c('inv-kiran', 'Kiran', ceremony: GuardianCeremony.notStarted),
          _c('u-manjit', 'Manjit', ceremony: GuardianCeremony.notStarted),
        ];
        const reasons = [
          (
            'inv-jaspal',
            'You can do this once Jaspal has finished joining the book.',
          ),
          (
            'inv-kiran',
            'You can do this once Kiran has finished joining the book.',
          ),
          (
            'u-manjit',
            'An admin has to look into this before a new invite can go out.',
          ),
        ];
        Checkbox box(String id) => tester.widget<Checkbox>(
          find.descendant(of: _member(id), matching: find.byType(Checkbox)),
        );
        final semantics = tester.ensureSemantics();

        final repo = FakeGuardians(
          initial: GuardianSetup(candidates: candidates()),
        );
        addTearDown(repo.dispose);
        await pumpRk(
          tester,
          _screen(repo, meetBlockOf: guardianMeetBlockFrom(members)),
          viewport: rkPhone360,
        );

        // Verified members: choosable, announced enabled.
        for (final id in const ['m1', 'm2', 'm3']) {
          await _reveal(tester, _member(id));
          expect(box(id).onChanged, isNotNull, reason: id);
          expect(
            tester.getSemantics(_member(id)),
            containsSemantics(hasEnabledState: true, isEnabled: true),
            reason: id,
          );
          await _choose(tester, id);
          expect(box(id).value, isTrue, reason: id);
        }

        // Not joined, expired, blocked: disabled, with the reason that is
        // true for them, and a tap on the row or the box chooses nobody.
        for (final (id, why) in reasons) {
          await _reveal(tester, _member(id));
          expect(box(id).onChanged, isNull, reason: id);
          expect(
            tester.widget<Text>(find.byKey(Key('guardians.meet.why.$id'))).data,
            why,
            reason: 'the same reason *Meet them* shows',
          );
          expect(
            tester.getSemantics(_member(id)),
            containsSemantics(
              hasEnabledState: true,
              isEnabled: false,
              hasCheckedState: true,
              isChecked: false,
            ),
            reason: '$id: disabled is announced',
          );
          expect(
            tester.getSemantics(_member(id)).label,
            contains(why),
            reason: '$id: the reason is read with the row, not only seen',
          );
          await tester.tap(_member(id), warnIfMissed: false);
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(of: _member(id), matching: find.byType(Checkbox)),
            warnIfMissed: false,
          );
          await tester.pumpAndSettle();
          expect(box(id).value, isFalse, reason: '$id was chosen by a tap');
        }

        // Only the three verified people reach the seam.
        expect(_saveEnabled(tester), isTrue);
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(repo.saved, [
          ['m1', 'm2', 'm3'],
        ]);

        // A set in force that holds someone now blocked is never silently
        // savable: Save says why, and taking them off is the way on.
        final held = FakeGuardians(
          initial: GuardianSetup(
            candidates: candidates(),
            chosenIds: const ['m1', 'm2', 'm3', 'u-manjit'],
          ),
        );
        addTearDown(held.dispose);
        await pumpRk(
          tester,
          _screen(held, meetBlockOf: guardianMeetBlockFrom(members)),
          viewport: rkPhone360,
        );
        expect(_saveEnabled(tester), isFalse);
        expect(
          find.text(
            'Someone you chose cannot be a trusted member right now. Take '
            'them off the list to save.',
          ),
          findsOneWidget,
        );
        await _reveal(tester, _member('u-manjit'));
        expect(box('u-manjit').value, isTrue);
        expect(
          box('u-manjit').onChanged,
          isNotNull,
          reason: 'a chosen row always un-chooses — no dead end',
        );
        await _choose(tester, 'u-manjit');
        expect(box('u-manjit').value, isFalse);
        expect(box('u-manjit').onChanged, isNull, reason: 'and stays off');
        expect(_saveEnabled(tester), isTrue);
        semantics.dispose();
      },
    );

    testWidgets(
      'F1-03c-3 a set in force that holds someone this phone has no row for '
      'shows them as a row that can be taken off, so Save’s *Take them off '
      'the list* can be carried out (07 §1 rule 6, no dead ends; ADR '
      '2026-10-03c §4) — and they cannot be chosen back',
      (tester) async {
        final members = FakeMembersRepository(
          initial: const MembersSnapshot(
            members: [
              Member(id: 'm1', state: MembershipState.active),
              Member(id: 'm2', state: MembershipState.active),
              Member(id: 'm3', state: MembershipState.active),
            ],
          ),
        );
        final unlisted = find.byKey(const Key('guardians.unlisted.u-gone'));
        Checkbox box() => tester.widget<Checkbox>(
          find.descendant(of: unlisted, matching: find.byType(Checkbox)),
        );
        final semantics = tester.ensureSemantics();
        // `u-gone` is in the server's set verbatim (guardians_seams.dart) but
        // the roster this device holds lists no one by that id.
        final held = FakeGuardians(
          initial: GuardianSetup(
            candidates: [
              _c('m1', 'Sunita'),
              _c('m2', 'Harpreet'),
              _c('m3', 'Gurmeet'),
            ],
            chosenIds: const ['m1', 'm2', 'm3', 'u-gone'],
          ),
        );
        addTearDown(held.dispose);
        await pumpRk(
          tester,
          _screen(held, meetBlockOf: guardianMeetBlockFrom(members)),
          viewport: rkPhone360,
        );

        expect(_saveEnabled(tester), isFalse);
        expect(
          find.text(
            'Someone you chose cannot be a trusted member right now. Take '
            'them off the list to save.',
          ),
          findsOneWidget,
        );
        await _reveal(tester, unlisted);
        expect(
          find.descendant(
            of: unlisted,
            matching: find.text('Someone not on this phone’s member list'),
          ),
          findsOneWidget,
          reason: 'a row the user can find, with words, not a bare id',
        );
        expect(box().value, isTrue);
        expect(box().onChanged, isNotNull, reason: 'it can be taken off');
        expect(
          tester.getSemantics(unlisted),
          containsSemantics(
            hasEnabledState: true,
            isEnabled: true,
            hasCheckedState: true,
            isChecked: true,
          ),
        );

        await tester.tap(unlisted);
        await tester.pumpAndSettle();
        expect(box().value, isFalse, reason: 'taken off');
        expect(box().onChanged, isNull, reason: 'and cannot be chosen back');
        expect(
          tester.getSemantics(unlisted),
          containsSemantics(hasEnabledState: true, isEnabled: false),
        );
        await tester.tap(unlisted, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(box().value, isFalse);

        expect(_saveEnabled(tester), isTrue);
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(held.saved, [
          ['m1', 'm2', 'm3'],
        ]);
        semantics.dispose();
      },
    );

    testWidgets(
      'F1-06-29 EN, ਪੰਜਾਬੀ and हिन्दी all fit at 200 % on 360×800 and '
      '375×667 — the list, the rule line and the 2-of-2 panel',
      (tester) async {
        for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
          for (final size in const [rkPhone360, rkPhone375]) {
            final repo = FakeGuardians(
              initial: GuardianSetup(
                candidates: [
                  _c('m1', 'Sunita'),
                  _c('m2', 'Harpreet'),
                  _c('m3', 'Gurmeet', ceremony: GuardianCeremony.notStarted),
                ],
              ),
            );
            addTearDown(repo.dispose);
            await pumpRk(
              tester,
              _screen(repo),
              locale: locale,
              textScale: 2,
              viewport: size,
            );
            await _choose(tester, 'm1');
            await _choose(tester, 'm2');
            expect(tester.takeException(), isNull);
            expectTextFits(
              tester,
              reason: 'S11.1 ${locale.languageCode} @2.0 ${size.width.toInt()}',
            );
          }
        }
      },
    );
  });
}
