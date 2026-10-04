// F1-25-1 — S9.1 *Send invite* creates the invite, then the inviter sends it
// from their own phone through the share sheet (ADR 2026-09-25 §2, amending
// 06 §7 and ADR 2026-09-05c §4). E-25-2 (*the server sends nothing*) is the
// server lane's.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/screens/s9_1_invite_screen.dart';
import 'package:rukka_folio/shared/seams/share_sheet.dart';

import '../../shared/test_app.dart';

/// Synthetic number only (check_purity): the ten digits typed behind
/// S9.1's fixed +91 (desk 116).
const _mobile = '9999900011'; // +91 99999 00011

final _books = [
  const TenantBook(id: 'b-home', name: 'Ghar'),
  const TenantBook(id: 'b-shop', name: 'Shop'),
];

MembersSnapshot _snapshot() => MembersSnapshot(
  tenantType: TenantType.organization,
  books: _books,
  yourRoles: const {'b-home': BookRole.admin, 'b-shop': BookRole.admin},
);

Uri _link(String id) => Uri.parse('https://links.test/join/$id');

/// A share sheet that also records how many invites existed when it was
/// raised — so "created, **then** shared" is asserted, not assumed.
final class _OrderedSheet implements ShareSheet {
  _OrderedSheet(this.repo);

  final FakeMembersRepository repo;
  ShareOutcome outcome = const ShareSheetRaised();
  final shared = <String>[];
  final invitesAtShare = <int>[];

  @override
  Future<ShareOutcome> shareText(String text) async {
    invitesAtShare.add(repo.invites.length);
    shared.add(text);
    return outcome;
  }
}

Widget _hosted(
  FakeMembersRepository repo,
  ShareSheet? sheet, {
  VoidCallback? onSent,
}) {
  final screen = InviteScreen(onSent: onSent ?? () {});
  return MembersRepositoryScope(
    repository: repo,
    child: sheet == null
        ? screen
        : ShareSheetScope(sheet: sheet, child: screen),
  );
}

/// Fills the form the short way: a number, one role, a ₹2,000 limit and a
/// designation — so the message can be checked for every one of them.
Future<void> _fillAndSend(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, _mobile);
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
}

List<String> _clipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  group('F1-25-1 S9.1 the inviter sends the invite from their own phone '
      '(ADR 2026-09-25 §2)', () {
    testWidgets('F1-25-1 Send invite creates the invite through the repository '
        'and only then raises the share sheet, with the link and a '
        'prefilled message that carries no amount, no book and no number', (
      tester,
    ) async {
      final repo = FakeMembersRepository(initial: _snapshot(), linkOf: _link);
      final sheet = _OrderedSheet(repo);
      await pumpRk(tester, _hosted(repo, sheet), viewport: rkTallViewport);

      await _fillAndSend(tester);

      expect(repo.invites, hasLength(1));
      expect(sheet.shared, hasLength(1));
      expect(
        sheet.invitesAtShare.single,
        1,
        reason: 'the invite existed before the sheet was raised',
      );
      final message = sheet.shared.single;
      expect(message, contains('https://links.test/join/invite-1'));
      expect(message, contains('Rukka Folio'));
      // CLAUDE.md rule 4 — nothing of the book and nothing of the invitee.
      for (final leak in [
        '99999',
        '00011',
        '2000',
        '2,000',
        '₹',
        'Ghar',
        'Shop',
        'Treasurer',
        'Head',
      ]) {
        expect(message.contains(leak), isFalse, reason: 'leaked "$leak"');
      }
      // The sheet is its own confirmation: nothing is claimed after it
      // (07 §1 rule 12, the ReportShared precedent).
      expect(find.text('Invite sent.'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Now send it from your phone'), findsOneWidget);
      expect(find.textContaining('Copied.'), findsNothing);
      expect(
        find.textContaining('couldn’t open the share sheet'),
        findsNothing,
      );
      // The same message stays on screen, selectable.
      expect(find.widgetWithText(SelectableText, message), findsOneWidget);
    });

    testWidgets('F1-25-1 Resend reopens the share sheet with the same message '
        'and creates no second invite', (tester) async {
      final repo = FakeMembersRepository(initial: _snapshot(), linkOf: _link);
      final sheet = FakeShareSheet();
      await pumpRk(tester, _hosted(repo, sheet), viewport: rkTallViewport);
      await _fillAndSend(tester);

      await tester.tap(find.text('Resend'));
      await tester.pumpAndSettle();

      expect(sheet.shared, hasLength(2));
      expect(sheet.shared[1], sheet.shared[0]);
      expect(repo.invites, hasLength(1));
    });

    testWidgets('F1-25-1 a failed creation opens no share sheet — the form '
        'stays filled with its error and retry', (tester) async {
      final repo = FakeMembersRepository(initial: _snapshot(), linkOf: _link)
        ..failNext = const MembersFailure('server said no');
      final sheet = FakeShareSheet();
      await pumpRk(tester, _hosted(repo, sheet), viewport: rkTallViewport);

      await _fillAndSend(tester);

      expect(sheet.shared, isEmpty);
      expect(repo.invites, isEmpty);
      expect(
        find.text('Couldn’t send that invite. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Send invite'), findsOneWidget);
      expect(find.text('Now send it from your phone'), findsNothing);
    });

    testWidgets('F1-25-1 when no share sheet can be raised the screen says so '
        'and shows the message with Copy — never a dead end (07 §1 rule 6)', (
      tester,
    ) async {
      final copied = _clipboard(tester);
      final repo = FakeMembersRepository(initial: _snapshot(), linkOf: _link);
      final sheet = FakeShareSheet(outcome: const ShareUnavailable());
      await pumpRk(tester, _hosted(repo, sheet), viewport: rkTallViewport);
      await _fillAndSend(tester);

      expect(
        find.text(
          'This phone couldn’t open the share sheet. Copy the message and '
          'send it yourself.',
        ),
        findsOneWidget,
      );
      final message = sheet.shared.single;
      expect(find.widgetWithText(SelectableText, message), findsOneWidget);

      await tester.tap(find.text('Copy the message'));
      await tester.pumpAndSettle();
      expect(copied, [message]);
      expect(
        find.text('Copied. Paste it into WhatsApp or SMS and send it to them.'),
        findsOneWidget,
      );
    });

    testWidgets('F1-25-1 with no share sheet installed at all, the invite is '
        'still created and the message is offered with Copy', (tester) async {
      final repo = FakeMembersRepository(initial: _snapshot(), linkOf: _link);
      await pumpRk(tester, _hosted(repo, null), viewport: rkTallViewport);
      await _fillAndSend(tester);

      expect(repo.invites, hasLength(1));
      expect(find.textContaining('couldn’t open the share sheet'), findsOne);
      expect(find.text('Copy the message'), findsOneWidget);
    });

    testWidgets('F1-25-1 the clipboard binding (the live one until a text '
        'share sheet is admitted) states the copy as a fact', (tester) async {
      final repo = FakeMembersRepository(initial: _snapshot(), linkOf: _link);
      final written = <String>[];
      final sheet = ClipboardShareSheet(write: (t) async => written.add(t));
      await pumpRk(tester, _hosted(repo, sheet), viewport: rkTallViewport);
      await _fillAndSend(tester);

      expect(written, hasLength(1));
      expect(written.single, contains('https://links.test/join/invite-1'));
      expect(
        find.text('Copied. Paste it into WhatsApp or SMS and send it to them.'),
        findsOneWidget,
      );
    });

    test('F1-25-1 ClipboardShareSheet never throws: a failed write is '
        'ShareUnavailable', () async {
      final ok = await ClipboardShareSheet(write: (_) async {}).shareText('x');
      expect(ok, isA<ShareCopied>());
      final failed = await ClipboardShareSheet(
        write: (_) async => throw PlatformException(code: 'no clipboard'),
      ).shareText('x');
      expect(failed, isA<ShareUnavailable>());
    });

    testWidgets('F1-25-1 with no link format bound (⚠️ SPEC, M11-INV2) no '
        'share sheet is raised and nothing names a link or a way to join: the '
        'panel says the invite is made and there is nothing to send yet', (
      tester,
    ) async {
      final repo = FakeMembersRepository(initial: _snapshot());
      final sheet = FakeShareSheet();
      var sent = 0;
      await pumpRk(
        tester,
        _hosted(repo, sheet, onSent: () => sent++),
        viewport: rkTallViewport,
      );
      // The form promises no link: its help line and the expiry line name the
      // invite, never a link that production cannot make.
      expect(find.textContaining('link'), findsNothing);
      await _fillAndSend(tester);

      expect(repo.invites, hasLength(1), reason: 'the invite still exists');
      expect(sheet.shared, isEmpty, reason: 'nothing to share without a link');
      expect(find.text('The invite is made'), findsOneWidget);
      expect(
        find.text(
          'This version of the app can’t make its link yet, so there is '
          'nothing to send them for now. It shows on Members as invited.',
        ),
        findsOneWidget,
      );
      expect(find.text('Now send it from your phone'), findsNothing);
      expect(find.text('Resend'), findsNothing);
      expect(find.text('Copy the message'), findsNothing);
      expect(find.textContaining('sign in'), findsNothing);
      expect(find.textContaining('7 days'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(sent, 1);
    });

    testWidgets('F1-25-1 Done returns to S9', (tester) async {
      final repo = FakeMembersRepository(initial: _snapshot(), linkOf: _link);
      var sent = 0;
      await pumpRk(
        tester,
        _hosted(repo, FakeShareSheet(), onSent: () => sent++),
        viewport: rkTallViewport,
      );
      await _fillAndSend(tester);
      expect(sent, 0);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(sent, 1);
    });

    for (final locale in rkLocales) {
      testWidgets('F1-25-1 the no-link panel (⚠️ SPEC, M11-INV2) holds at 2x '
          'text on 360×800 in ${locale.languageCode}', (tester) async {
        final repo = FakeMembersRepository(initial: _snapshot());
        final sheet = FakeShareSheet();
        await pumpRk(
          tester,
          _hosted(repo, sheet),
          locale: locale,
          textScale: 2,
          viewport: const Size(360, 6000),
        );
        await tester.enterText(find.byType(TextField).first, _mobile);
        await tester.tap(find.byType(ChoiceChip).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton).last);
        await tester.pumpAndSettle();
        rkViewport(tester, rkPhone360);
        await tester.pumpAndSettle();
        expect(repo.invites, hasLength(1));
        expect(sheet.shared, isEmpty);
        expect(find.byType(FilledButton), findsOneWidget, reason: 'Done');
        expect(tester.takeException(), isNull);
        expectTextFits(tester, reason: '$locale @ 2x no link');
      });
    }

    for (final locale in rkLocales) {
      testWidgets('F1-25-1 the share panel holds at 2x text on 360×800 in '
          '${locale.languageCode} — every string resolves, nothing is cut', (
        tester,
      ) async {
        final repo = FakeMembersRepository(initial: _snapshot(), linkOf: _link);
        // Unavailable draws every line the panel has.
        final sheet = FakeShareSheet(outcome: const ShareUnavailable());
        // Filled on a 360-wide, very tall screen so every field is built;
        // the panel is then laid out on the real 360×800 phone.
        await pumpRk(
          tester,
          _hosted(repo, sheet),
          locale: locale,
          textScale: 2,
          viewport: const Size(360, 6000),
        );
        await tester.enterText(find.byType(TextField).first, _mobile);
        await tester.tap(find.byType(ChoiceChip).at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton).last);
        await tester.pumpAndSettle();
        rkViewport(tester, rkPhone360);
        await tester.pumpAndSettle();
        expect(sheet.shared, hasLength(1));
        expect(tester.takeException(), isNull);
        expectTextFits(tester, reason: '$locale @ 2x');
        for (var i = 0; i < 6; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expectTextFits(tester, reason: '$locale @ 2x scrolled $i');
        }
      });
    }
  });
}
