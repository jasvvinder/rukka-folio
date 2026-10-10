// F1-200-11…14 — S6 and S6.3 on the seams **production installs** (desk 200
// (c)). Until this slice `StructuralRequestsScope.of` fell back to an empty
// fake in the shipped app: no structural card was ever drawn and nothing ever
// opened S6.3, while every widget test of it ran on a hand-built fake.
//
// TEST HONESTY: every screen here is pumped under `LedgerInboxSeams.scopes` —
// the factory `bootstrap.dart` calls (pinned by F1-200-12) — over a real,
// in-memory ledger, with the pending request raised through the real write
// path (`LocalLedger.proposeDistribution`, 02 §7.1 🔒 / §7.2.1 🔒). If the
// structural seam yielded nothing, or the factory did not install it, the card
// these tests look for would not exist.
//
// The signer is the production one too (review F200I-3): `certifiedSignerOf`
// over the trust store the composition root builds, and another owner's
// approval reaches the screen only from a phone whose certificate that store
// holds and whose envelope the chain verified (structural_fixture.dart).
//
// Synthetic names and sums only (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:io';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/certified_signer.dart';
import 'package:rukka_folio/features/inbox/ledger_inbox_seams.dart';
import 'package:rukka_folio/features/inbox/screens/s6_3_structural_review_screen.dart';
import 'package:rukka_folio/features/inbox/screens/s6_inbox_screen.dart';
import 'package:rukka_folio/features/inbox/structural_requests.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import '../../shared/test_app.dart';
import 'structural_fixture.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// Lets the ledger writes behind a tap land, then settles the frame.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

typedef _Production = ({
  SharedBook book,
  LedgerInboxSeams seams,
  StructuralRequest request,
  eng.RecordTrustStore trust,
});

/// A shared book with a pending distribution, and the production seams over
/// it — the production signer over the production trust store — loaded
/// before the first frame (the drift reads need real async). [arrive] runs
/// first: what other owners' phones send, over that trust store.
Future<_Production> _production(
  WidgetTester tester, {
  Future<void> Function(
    SharedBook book,
    StructuralRequest request,
    eng.RecordTrustStore trust,
  )?
  arrive,
}) async {
  late SharedBook book;
  late LedgerInboxSeams seams;
  late StructuralRequest request;
  late eng.RecordTrustStore trust;
  await tester.runAsync(() async {
    book = await sharedBook();
    request = await book.proposeDistribution();
    trust = productionTrust(book);
    await arrive?.call(book, request, trust);
    seams = LedgerInboxSeams(
      book.ledger,
      memberName: book.nameOf,
      signerOf: certifiedSignerOf(trust, book.ledger.suite),
    );
    await seams.reviews.refresh();
    await seams.lateArrivals.refresh();
    await seams.structural.refresh();
  });
  addTearDown(() => tester.runAsync(seams.dispose));
  return (book: book, seams: seams, request: request, trust: trust);
}

/// [by]'s approval of [request], signed on their own certified phone and
/// chain-verified into the mirror (structural_fixture.dart). With
/// [keepCert] false the certificate is dropped afterwards — the trust store
/// of a launch before the meta read.
Future<void> _approvedOnTheirPhone(
  SharedBook book,
  StructuralRequest request,
  eng.RecordTrustStore trust,
  String by, {
  required int seq,
  bool keepCert = true,
}) async {
  final phone = await remotePhone(book, by);
  phone.fileCertIn(trust);
  final ok = await receiveFrom(
    book,
    phone,
    approvalOf(book, request, by, minutes: seq),
    trust: trust,
    authorSeq: 1,
    seq: seq,
  );
  expect(ok, isTrue, reason: 'the chain holds for $by\'s phone');
  if (!keepCert) trust.certs.remove(phone.deviceId);
}

Future<int> _approvalRows(WidgetTester tester, SharedBook b) async {
  late int n;
  await tester.runAsync(() async {
    final db = b.ledger.db;
    n = (await (db.select(
      db.envelopesLocal,
    )..where((t) => t.objectType.equals('structural_approval'))).get()).length;
  });
  return n;
}

void main() {
  testWidgets('F1-200-11 S6 under the production seams draws the structural '
      'card for a distribution raised through the real ledger — 0 of 3, '
      'Approve and Veto — and Approve signs one approval that the card then '
      'counts', (tester) async {
    final p = await _production(tester);
    String? opened;
    await pumpRk(
      tester,
      p.seams.scopes(
        child: InboxScreen(
          onOpenLedger: () {},
          onReviewGroup: (_) {},
          onOpenStructural: (id) => opened = id,
          onOpenLateArrivals: () {},
        ),
      ),
      viewport: rkTallViewport,
    );

    expect(find.text(_en.inboxSectionStructural), findsOneWidget);
    expect(find.text(_en.inboxStructuralKindProfit), findsOneWidget);
    expect(find.text(_en.inboxStructuralQuorumProgress(0, 3)), findsOneWidget);
    expect(find.text(_en.inboxStructuralYouRaised), findsOneWidget);
    final approve = find.widgetWithText(
      FilledButton,
      _en.inboxStructuralApprove,
    );
    expect(approve, findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, _en.inboxStructuralVeto),
      findsOneWidget,
    );

    await tester.tap(find.text(_en.inboxStructuralOpen));
    expect(opened, p.request.id, reason: 'the card opens S6.3 by request id');

    final before = await _approvalRows(tester, p.book);
    await tester.tap(approve);
    await tester.pumpAndSettle();
    // The confirm dialog's own Approve.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(_en.inboxStructuralApprove),
      ),
    );
    await _settle(tester);

    expect(await _approvalRows(tester, p.book), before + 1);
    expect(find.text(_en.inboxStructuralQuorumProgress(1, 3)), findsOneWidget);
    expect(find.text(_en.inboxStructuralYouApproved), findsOneWidget);
    expect(approve, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('F1-200-12 S6.3, opened by request id under the production '
      'seams, states what will change in the partners\' own A/c names and '
      'the shares in rupees', (tester) async {
    final p = await _production(tester);
    await pumpRk(
      tester,
      p.seams.scopes(
        child: StructuralReviewScreen(requestId: p.request.id, onDone: () {}),
      ),
      viewport: rkTallViewport,
    );
    expect(find.text(_en.inboxStructuralDetailTitle), findsOneWidget);
    expect(find.text(_en.inboxStructuralKindProfit), findsOneWidget);
    expect(find.text(_en.inboxStructuralTermsTitle), findsOneWidget);
    for (final who in ['Amrit', 'Sukhdev', 'Harjit']) {
      expect(find.text(p.book.partner(who).name), findsOneWidget);
    }
    expect(find.text('₹1,00,000'), findsNWidgets(3));
    expect(find.text(_en.inboxStructuralDetailGoneTitle), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('F1-200-13 the composition root installs the Inbox through '
      'LedgerInboxSeams, naming signers through certifiedSignerOf over the '
      'engine\'s trust store and the certificates this install retained — '
      'the same view the ledger\'s own signer reads — never a certificate\'s '
      'user id alone, and builds none of the three scopes by hand (root '
      'pin)', () {
    final root = File('lib/bootstrap.dart').readAsStringSync();
    expect(root, contains('LedgerInboxSeams('));
    expect(
      root,
      contains('signerOf: certifiedSignerOf(signers, suite)'),
      reason:
          'the chain re-run at read (F200I-1), the function E-200-24…27 '
          'and F1-200-15…17 exercise, over the view wireLedgerTrust returns '
          '(TRUSTWIRE-1)',
    );
    expect(
      root,
      contains('final signers = wireLedgerTrust(ledger, trust, suite);'),
      reason: 'the ledger\'s signer and the Inbox\'s read one view',
    );
    expect(
      root,
      contains(
        'final trust = eng.RecordTrustStore(umks: '
        'eng.BoundUmkSource(identity));',
      ),
      reason: 'the store productionTrust() in structural_fixture.dart mirrors',
    );
    expect(
      root,
      isNot(contains('certOf(deviceId)?.userId')),
      reason: 'the unsigned label the server controls (F200I-1)',
    );
    expect(root, contains('refreshOn: sync.status'));
    expect(root, contains('inbox.scopes('));
    for (final byHand in [
      'StructuralRequestsScope(',
      'LateArrivalsScope(',
      'ReviewQueueScope(',
      'FakeStructuralRequests',
    ]) {
      expect(root, isNot(contains(byHand)), reason: byHand);
    }
  });

  testWidgets('F1-200-14 a request whose change this phone cannot state says '
      'so and offers Veto with reason but never Approve, in EN, PA and HI '
      '(07 §26 🔒; 13 §4.3)', (tester) async {
    final now = testNow().millisecondsSinceEpoch;
    final request = StructuralRequest(
      id: 'r1',
      bookId: 'b1',
      hlc: Hlc.compose(physicalMs: now - 60 * 60 * 1000, counter: 0),
      action: StructuralAction.bookArchiveOrDelete,
      byUser: 'u1',
      ownerSetVersion: 1,
      payload: const {'mode': 'delete'},
    );
    final item = StructuralItem(
      request: request,
      outcome: evaluateStructural(
        request: request,
        records: const [],
        owners: const [
          OwnerSetVersion(
            version: 1,
            ownerIds: {'u1', 'u2'},
            quorum: StructuralQuorum.allOwners,
          ),
        ],
        asOfMs: now,
        signerOf: null, // no records: nothing to bind
      ),
      bookName: 'Sharma Brothers',
      initiatorName: 'Amrit Kaur',
      ownerNames: const {'u1': 'Amrit Kaur', 'u2': 'Sukhdev Singh'},
      viewerId: 'u2',
      viewerIsOwner: true,
      termsKnown: false,
    );
    for (final locale in rkLocales) {
      final l10n = lookupAppLocalizations(locale);
      final seam = FakeStructuralRequests(
        initial: StructuralInbox(items: [item]),
      );
      addTearDown(seam.dispose);
      await pumpRk(
        tester,
        StructuralRequestsScope(
          requests: seam,
          child: StructuralReviewScreen(requestId: 'r1', onDone: () {}),
        ),
        locale: locale,
        viewport: rkTallViewport,
      );
      expect(find.text(l10n.inboxStructuralTermsUnknown), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, l10n.inboxStructuralVeto),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, l10n.inboxStructuralApprove),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('F1-200-15 S6 under the production seams counts another '
      'owner\'s approval signed on their own certified phone — 1 of 3 — and '
      'still offers this owner Approve and Veto (02 §7.2.1 🔒)', (
    tester,
  ) async {
    final p = await _production(
      tester,
      arrive: (book, request, trust) =>
          _approvedOnTheirPhone(book, request, trust, sukhdev, seq: 1),
    );
    await pumpRk(
      tester,
      p.seams.scopes(
        child: InboxScreen(
          onOpenLedger: () {},
          onReviewGroup: (_) {},
          onOpenStructural: (_) {},
          onOpenLateArrivals: () {},
        ),
      ),
      viewport: rkTallViewport,
    );
    expect(find.text(_en.inboxStructuralQuorumProgress(1, 3)), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, _en.inboxStructuralApprove),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, _en.inboxStructuralVeto),
      findsOneWidget,
    );
    expect(find.text(_en.inboxStructuralUnconfirmed(1)), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('F1-200-16 on a launch before the meta read, another owner\'s '
      'approval is not counted and not hidden: S6 says how many records wait, '
      'the card says why, and neither Approve nor Veto is offered — in EN, '
      'PA and HI (02 §7.2.1 🔒; 13 §4.3)', (tester) async {
    final p = await _production(
      tester,
      arrive: (book, request, trust) => _approvedOnTheirPhone(
        book,
        request,
        trust,
        sukhdev,
        seq: 1,
        keepCert: false,
      ),
    );
    for (final locale in rkLocales) {
      final l10n = lookupAppLocalizations(locale);
      await pumpRk(
        tester,
        p.seams.scopes(
          child: InboxScreen(
            onOpenLedger: () {},
            onReviewGroup: (_) {},
            onOpenStructural: (_) {},
            onOpenLateArrivals: () {},
          ),
        ),
        locale: locale,
        viewport: rkTallViewport,
      );
      expect(find.text(l10n.inboxStructuralUnconfirmed(1)), findsOneWidget);
      expect(
        find.text(l10n.inboxStructuralSignersUnconfirmed('Sharma Brothers')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.inboxStructuralQuorumProgress(0, 3)),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, l10n.inboxStructuralApprove),
        findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, l10n.inboxStructuralVeto),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('F1-200-17 when every owner has approved — two of them on their '
      'own phones — S6.3 says the owners agreed and does not claim the change '
      'is in force, since nothing applies it yet, in EN, PA and HI '
      '(02 §7.2.1 🔒)', (tester) async {
    final p = await _production(
      tester,
      arrive: (book, request, trust) async {
        await _approvedOnTheirPhone(book, request, trust, sukhdev, seq: 1);
        await _approvedOnTheirPhone(book, request, trust, harjit, seq: 2);
        await book.ledger.authorStructural(
          (hlc, id) => StructuralApproval(
            id: id,
            bookId: book.bookId,
            hlc: hlc,
            requestId: request.id,
            byUser: book.me,
            ownerSetVersion: request.ownerSetVersion,
          ),
        );
      },
    );
    final item = p.seams.structural.current!.visible.single;
    expect(item.status, StructuralStatus.approved);
    expect(item.approvals, 3);
    expect(
      _en.inboxStructuralDoneBody(3, 3),
      isNot(contains('in force')),
      reason: 'no applier exists yet (lane report M13-F200I open)',
    );
    for (final locale in rkLocales) {
      final l10n = lookupAppLocalizations(locale);
      await pumpRk(
        tester,
        p.seams.scopes(
          child: StructuralReviewScreen(requestId: p.request.id, onDone: () {}),
        ),
        locale: locale,
        viewport: rkTallViewport,
      );
      expect(find.text(l10n.inboxStructuralDoneTitle), findsOneWidget);
      expect(find.text(l10n.inboxStructuralDoneBody(3, 3)), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, l10n.inboxStructuralApprove),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
