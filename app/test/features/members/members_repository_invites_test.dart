// F1 — the joiner's two invite methods live on the [MembersRepository]
// interface (M13-SEAM1; PLAN M7 seam row swept from M7-W2), so a fake stands
// in for `ServerMembersRepository` without a downcast.
//
// F1-07-546  `myInvites` — a caller that holds only a `MembersRepository`
//            (S0.9, through the production `DelegatedInvitationGateway`
//            binding) sees the fake's rows, nonce and status included
//            (ADR 2026-09-25b §2)
// F1-07-547  `acceptInvite` — the same caller's accept, bound through
//            `InviteNonceRelay.acceptInvite` as bootstrap binds it, reaches
//            the fake, returns the fake's membership status and leaves the
//            relay holding that invite's nonce (ADR 2026-09-25b §3); an id the
//            fake never offered is the one `inviteNotForYou` (ADR 2026-09-05d
//            §9 🔒)
//
// Test-honesty: each assertion is on a value only the fake could have
// supplied — an empty `offered` renders S0.9's no-invitation state and an
// empty row list, and an accept that returned nothing records no id.
// Nothing here is a real number or name (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show ceremonyNonceBytes;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/invite_nonce_relay.dart';
import 'package:rukka_folio/features/members/members_api.dart'
    show AcceptedInvite;
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/onboarding/invitation_gateway.dart'
    show DelegatedInvitationGateway, InvitationGateway, InvitationGatewayScope;
import 'package:rukka_folio/features/onboarding/screens/s0_9_invitation_screen.dart';
import 'package:rukka_folio/shared/prefs.dart' show MemoryPrefs;
import 'package:rukka_folio/shared/seams/auth_client.dart';

import '../../shared/test_app.dart';

final _nonce = Uint8List.fromList(
  List<int>.generate(ceremonyNonceBytes, (i) => i + 1),
);

InviteOffer _offer({String id = 'inv-1', int books = 2}) => InviteOffer(
  inviteId: id,
  tenantId: 'tenant-1',
  roles: [
    for (var i = 0; i < books; i++) {'book_id': 'book-$i', 'role': 'member'},
  ],
  expiresAt: testNow().add(const Duration(days: 7)),
  createdBy: 'user-admin',
  status: 'sent',
  nonce: _nonce,
);

/// The production binding (bootstrap's S0.9 gateway), over the interface
/// type: `offers` is the repository's `myInvites`, and `accept` goes
/// **through** [InviteNonceRelay.acceptInvite] — never straight to
/// `MembersRepository.acceptInvite`, which answers the status alone and would
/// drop the relayed nonce S9.2 pairs by `invite_id` (ADR 2026-09-25b §3).
///
/// Bootstrap's relay answers with `HttpMembersApi.acceptInviteRelayed`; over
/// the fake, its stand-in is the repository's accept (the status) plus the
/// offer's own nonce — the shape that route answers (25b §2). Nothing here
/// can reach a `ServerMembersRepository` member.
({InvitationGateway gateway, InviteNonceRelay relay}) _bindingOver(
  MembersRepository repo,
) {
  final relay = InviteNonceRelay(
    offers: repo.myInvites,
    accept: (inviteId) async {
      final status = await repo.acceptInvite(inviteId);
      final offer = (await repo.myInvites()).where(
        (o) => o.inviteId == inviteId,
      );
      return AcceptedInvite(
        inviteId: inviteId,
        status: status,
        nonce: offer.firstOrNull?.nonce,
      );
    },
    store: MemoryPrefs(),
  );
  return (
    gateway: DelegatedInvitationGateway(
      offers: repo.myInvites,
      accept: relay.acceptInvite,
    ),
    relay: relay,
  );
}

InvitationGateway _gatewayOver(MembersRepository repo) =>
    _bindingOver(repo).gateway;

Future<void> _pumpS09(WidgetTester tester, InvitationGateway gateway) => pumpRk(
  tester,
  InvitationGatewayScope(
    gateway: gateway,
    child: InvitationScreen(
      inviteId: 'inv-1',
      onOpenMyBook: () {},
      onConfirmNumber: () {},
      onSetUpPhone: () {},
    ),
  ),
  auth: FakeAuthClient(
    initial: const Active(
      AuthSession(userId: 'u-1', deviceId: 'd-1'),
      deviceCertified: true,
    ),
  ),
  viewport: const Size(390, 1400),
);

void main() {
  group('MembersRepository — joiner methods on the interface', () {
    test('F1-07-546 myInvites: a caller holding only a MembersRepository sees '
        "the fake's rows, nonce and status included", () async {
      final fake = FakeMembersRepository()
        ..offered = [_offer(), _offer(id: 'inv-2', books: 1)];
      final MembersRepository repo = fake;

      final rows = await _gatewayOver(repo).myInvites();

      expect(rows.map((o) => o.inviteId), ['inv-1', 'inv-2']);
      expect(rows.first.nonce, _nonce);
      expect(rows.first.status, 'sent');
      expect(fake.myInvitesCalls, 1);
    });

    testWidgets('F1-07-546 myInvites: S0.9 over the interface renders the '
        "fake's offer", (tester) async {
      final MembersRepository repo = FakeMembersRepository()
        ..offered = [_offer()];
      await _pumpS09(tester, _gatewayOver(repo));

      expect(find.text('You have been invited'), findsOneWidget);
      expect(find.text('2 shared books'), findsOneWidget);
    });

    test('F1-07-546 myInvites: the fake honours failNext like every other '
        'method', () async {
      final fake = FakeMembersRepository()
        ..offered = [_offer()]
        ..failNext = const MembersFailure('offline', MembersRefusal.offline);
      final MembersRepository repo = fake;

      await expectLater(
        repo.myInvites(),
        throwsA(
          isA<MembersFailure>().having(
            (f) => f.reason,
            'reason',
            MembersRefusal.offline,
          ),
        ),
      );
      expect((await repo.myInvites()).single.inviteId, 'inv-1');
    });

    test(
      "F1-07-547 acceptInvite: a caller holding only a MembersRepository "
      "gets the fake's membership status and the fake records the id",
      () async {
        final fake = FakeMembersRepository()
          ..offered = [_offer()]
          ..acceptStatus = 'status-from-the-fake';
        final MembersRepository repo = fake;

        final binding = _bindingOver(repo);
        final status = await binding.gateway.acceptInvite('inv-1');

        expect(status, 'status-from-the-fake');
        expect(fake.acceptedInvites, ['inv-1']);
        // Accepted through the relay, so the invite this device accepted is
        // the one S9.2 pairs its relayed nonce to (ADR 2026-09-25b §3). Bound
        // straight to `repo.acceptInvite`, the relay would know no invite and
        // answer no nonce.
        expect(binding.relay.ownInviteId, 'inv-1');
        expect(await binding.relay.nonce(), _nonce);
      },
    );

    testWidgets('F1-07-547 acceptInvite: S0.9 over the interface accepts '
        'through the fake', (tester) async {
      final fake = FakeMembersRepository()..offered = [_offer()];
      final MembersRepository repo = fake;
      await _pumpS09(tester, _gatewayOver(repo));

      await tester.tap(find.text('Accept invitation'));
      await tester.pumpAndSettle();

      expect(fake.acceptedInvites, ['inv-1']);
      expect(find.text('You are in'), findsOneWidget);
    });

    test('F1-07-547 acceptInvite: an id the fake never offered is the one '
        'inviteNotForYou (ADR 2026-09-05d §9 🔒)', () async {
      final fake = FakeMembersRepository()..offered = [_offer()];
      final MembersRepository repo = fake;

      await expectLater(
        repo.acceptInvite('invite-does-not-exist'),
        throwsA(
          isA<MembersFailure>().having(
            (f) => f.reason,
            'reason',
            MembersRefusal.inviteNotForYou,
          ),
        ),
      );
      expect(fake.acceptedInvites, isEmpty);
    });
  });
}
