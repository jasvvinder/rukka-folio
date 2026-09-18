// F1-07-36 — S6.3, the structural approval card and its review surface
// (07 §26 🔒; 02 §7.2.1 🔒; ADR 2026-09-05f §D; 13 §3.2, §4.3).
//
// What these tests hold in place:
//  · the card states **exactly what will change**, in words with figures, the
//    terms in force beside the proposed ones (07 §26 🔒);
//  · quorum progress is the **engine's** number — `outcome.approvedBy.length`
//    of `outcome.threshold` — never `owners.length` and never a local
//    ⌊n/2⌋+1. The majority cases below would read differently if the screen
//    counted for itself (ADR 2026-09-14 ruling 1 🔒);
//  · **Approve** and **Veto with reason**; a veto needs a reason, cancels the
//    request and is logged (02 §7.2.1 🔒, §7.2 item 3);
//  · nothing is applied early — the card says so in words (02 §7.2.1 🔒);
//  · an initiation is **not** an approval: the initiator still signs one, and
//    the card tells them (the engine asserts this at A-02-94);
//  · every 13 §4.3 state, including the owner who has voted, the member who is
//    not an owner, the lapsed request and the vetoed one;
//  · a single-owner book draws no card at all — "the concept is invisible
//    there" (02 §7.2.1 🔒);
//  · EN/PA/HI at 1.3 and 2.0 on 360×800 without a cut word.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/review_queue.dart';
import 'package:rukka_folio/features/inbox/screens/s6_3_structural_review_screen.dart';
import 'package:rukka_folio/features/inbox/screens/s6_inbox_screen.dart';
import 'package:rukka_folio/features/inbox/structural_requests.dart';

import '../../shared/test_app.dart';

// ---------------------------------------------------------------- fixtures

/// The moment every fixture is judged at — the harness clock.
final _nowMs = testNow().millisecondsSinceEpoch;

/// A request authored [daysAgo] before [testNow].
StructuralRequest _request({
  StructuralAction action = StructuralAction.ownershipRatio,
  String byUser = 'u1',
  int ownerSetVersion = 1,
  int daysAgo = 2,
  String id = 'r1',
}) => StructuralRequest(
  id: id,
  bookId: 'b1',
  hlc: Hlc.compose(
    physicalMs: _nowMs - daysAgo * 24 * 60 * 60 * 1000,
    counter: 0,
  ),
  action: action,
  byUser: byUser,
  ownerSetVersion: ownerSetVersion,
);

StructuralApproval _approval(
  StructuralRequest r,
  String by, {
  int hoursAfter = 1,
}) => StructuralApproval(
  id: 'a-$by',
  bookId: r.bookId,
  hlc: Hlc.compose(
    physicalMs: r.hlc.physicalMs + hoursAfter * 60 * 60 * 1000,
    counter: 0,
  ),
  requestId: r.id,
  byUser: by,
  ownerSetVersion: r.ownerSetVersion,
);

/// Builds the item the screen draws, with the engine's own verdict on it.
/// Nothing in the test computes a threshold either.
StructuralItem _item({
  StructuralRequest? request,
  Set<String> owners = const {'u1', 'u2', 'u3'},
  StructuralQuorum quorum = StructuralQuorum.allOwners,
  List<String> approvedBy = const [],
  List<StructuralEvent> extraRecords = const [],
  String viewerId = 'u2',
  bool viewerIsOwner = true,
  bool viewerCanInitiate = false,
  int? asOfMs,
  List<StructuralTerm> terms = const [],
  String? subject,
  Map<String, String>? names,
}) {
  final r = request ?? _request();
  final versions = [
    OwnerSetVersion(version: 1, ownerIds: owners, quorum: quorum),
  ];
  final records = <StructuralEvent>[
    for (final by in approvedBy) _approval(r, by),
    ...extraRecords,
  ];
  final outcome = evaluateStructural(
    request: r,
    records: records,
    owners: versions,
    asOfMs: asOfMs ?? _nowMs,
  );
  return StructuralItem(
    request: r,
    outcome: outcome,
    bookName: 'Sharma Brothers',
    initiatorName: names?[r.byUser] ?? 'Amrit',
    ownerNames: names ?? {for (final id in owners) id: _defaultNames[id] ?? id},
    viewerId: viewerId,
    viewerIsOwner: viewerIsOwner,
    viewerCanInitiate: viewerCanInitiate,
    terms: terms,
    subject: subject,
  );
}

const _defaultNames = {
  'u1': 'Amrit',
  'u2': 'Sukhdev',
  'u3': 'Harjit',
  'u4': 'Gurpreet',
  'u5': 'Manjit',
};

/// 07 §26's own worked example: *"Ownership ratio: Amrit 40 · Sukhdev 30 ·
/// Harjit 30 — currently equal thirds"*. Weights, never percentages
/// (ADR 2026-09-09 §2).
const _ratioTerms = [
  StructuralTerm(
    subject: 'Amrit',
    current: StructuralText('1'),
    proposed: StructuralText('40'),
  ),
  StructuralTerm(
    subject: 'Sukhdev',
    current: StructuralText('1'),
    proposed: StructuralText('30'),
  ),
  StructuralTerm(
    subject: 'Harjit',
    current: StructuralText('1'),
    proposed: StructuralText('30'),
  ),
];

Widget _inbox(
  FakeStructuralRequests seam, {
  void Function(String requestId)? onOpen,
}) {
  final queue = FakeReviewQueue(initial: const InboxSnapshot());
  addTearDown(queue.dispose);
  return ReviewQueueScope(
    queue: queue,
    child: StructuralRequestsScope(
      requests: seam,
      child: InboxScreen(onOpenLedger: () {}, onOpenStructural: onOpen),
    ),
  );
}

Widget _surface(
  FakeStructuralRequests seam, {
  String requestId = 'r1',
  VoidCallback? onDone,
}) => StructuralRequestsScope(
  requests: seam,
  child: StructuralReviewScreen(requestId: requestId, onDone: onDone),
);

FakeStructuralRequests _seam(List<StructuralItem> items) {
  final seam = FakeStructuralRequests(initial: StructuralInbox(items: items));
  addTearDown(seam.dispose);
  return seam;
}

/// Every string actually painted, however it was built.
List<String> _painted(WidgetTester tester) {
  final out = <String>[];
  void visit(RenderObject o) {
    if (o is RenderParagraph) out.add(o.text.toPlainText());
    o.visitChildren(visit);
  }

  final root = tester.binding.rootElement?.renderObject;
  if (root != null) visit(root);
  return out;
}

// ------------------------------------------------------------------- tests

void main() {
  group('F1-07-36 what will change', () {
    testWidgets(
      'F1-07-36 S6.3 states the change with the terms in force beside the '
      'proposed ones (07 §26 🔒)',
      (tester) async {
        final seam = _seam([_item(terms: _ratioTerms)]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(find.text('Change the ownership shares'), findsOneWidget);
        expect(
          find.text('Amrit raised this in Sharma Brothers.'),
          findsOneWidget,
        );
        expect(find.text('What will change'), findsOneWidget);
        // Every partner is named, with both figures.
        for (final name in ['Amrit', 'Sukhdev', 'Harjit']) {
          expect(find.text(name), findsWidgets, reason: '$name is a term line');
        }
        expect(find.text('Now'), findsNWidgets(3));
        expect(find.text('Proposed'), findsNWidgets(3));
        expect(find.text('40'), findsOneWidget);
        expect(find.text('30'), findsNWidgets(2));
        expect(find.text('1'), findsNWidgets(3));
      },
    );

    testWidgets(
      'F1-07-36 an unrecorded ratio is said to be unrecorded, never read as '
      'equal shares (02 §7.1 🔒)',
      (tester) async {
        final seam = _seam([
          _item(
            terms: const [
              StructuralTerm(subject: 'Amrit', proposed: StructuralText('40')),
              StructuralTerm(
                subject: 'Sukhdev',
                proposed: StructuralText('30'),
              ),
            ],
          ),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(find.text('Not recorded'), findsNWidgets(2));
        expect(
          find.textContaining('not the same as equal shares'),
          findsOneWidget,
          reason: '02 §7.1 🔒: an absent map means never recorded, never equal',
        );
        final painted = _painted(tester).join(' | ').toLowerCase();
        expect(
          painted.contains('equal thirds'),
          isFalse,
          reason: 'nothing may divide an unrecorded ratio evenly',
        );
      },
    );

    testWidgets(
      'F1-07-36 a money term is drawn from integer paise, a day from a '
      'LocalDate (CLAUDE.md rule 1; 07 §1 rule 5)',
      (tester) async {
        final seam = _seam([
          _item(
            request: _request(action: StructuralAction.profitDistribution),
            terms: [
              const StructuralTerm(
                subject: 'Amrit',
                current: StructuralMoney(0),
                proposed: StructuralMoney(23_40_000),
              ),
              StructuralTerm(
                subject: 'Year starts',
                current: StructuralDay(LocalDate(2026, 4, 1)),
                proposed: StructuralDay(LocalDate(2026, 1, 1)),
              ),
            ],
          ),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(find.text('Share out the profit'), findsOneWidget);
        expect(find.text('₹23,400'), findsOneWidget);
        expect(find.text('₹0'), findsOneWidget);
        expect(find.text('01 Apr 2026'), findsOneWidget);
        expect(find.text('01 Jan 2026'), findsOneWidget);
      },
    );

    testWidgets('F1-07-36 each structural kind of 02 §7.2.1 names itself', (
      tester,
    ) async {
      final cases = <StructuralAction, String>{
        StructuralAction.ownershipRatio: 'Change the ownership shares',
        StructuralAction.profitDistribution: 'Share out the profit',
        StructuralAction.interestOnCapital: 'Change interest on capital',
        StructuralAction.ownerAddOrRemove: 'Change who owns this book',
        StructuralAction.fyStartChange: 'Change when the book’s year starts',
        StructuralAction.bookArchiveOrDelete: 'Archive Sharma Brothers',
        StructuralAction.quorumSetting: 'Change how many owners must agree',
      };
      for (final entry in cases.entries) {
        final seam = _seam([_item(request: _request(action: entry.key))]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);
        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
      }
    });

    testWidgets(
      'F1-07-36 a member removal and a year re-open name their subject',
      (tester) async {
        final removal = _seam([
          _item(
            request: _request(action: StructuralAction.memberRemoval),
            subject: 'Nirmal',
          ),
        ]);
        await pumpRk(tester, _inbox(removal), viewport: rkTallViewport);
        expect(find.text('Remove Nirmal from this book'), findsOneWidget);

        final reopen = _seam([
          _item(
            request: _request(action: StructuralAction.yearReopen),
            subject: '2025–26',
          ),
        ]);
        await pumpRk(tester, _inbox(reopen), viewport: rkTallViewport);
        expect(find.text('Re-open the closed year 2025–26'), findsOneWidget);
      },
    );
  });

  group('F1-07-36 quorum progress is the engine\'s number', () {
    testWidgets('F1-07-36 the card reads "2 of 3" (07 §26 🔒)', (tester) async {
      final seam = _seam([
        _item(approvedBy: const ['u1', 'u3'], terms: _ratioTerms),
      ]);
      await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

      expect(find.text('2 of 3 owners have approved'), findsOneWidget);
    });

    testWidgets(
      'F1-07-36 a majority book shows the engine\'s threshold, not the owner '
      'count (ADR 2026-09-14 ruling 1 🔒)',
      (tester) async {
        // Five owners, majority ⌊5/2⌋+1 = 3. A screen that counted owners
        // would say "2 of 5"; one that kept 02 §7.2.1's old ⌈n/2⌉+1 would say
        // "2 of 4". The engine says 3, so the card must say 3.
        final seam = _seam([
          _item(
            owners: const {'u1', 'u2', 'u3', 'u4', 'u5'},
            quorum: StructuralQuorum.majority,
            approvedBy: const ['u1', 'u3'],
          ),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(find.text('2 of 3 owners have approved'), findsOneWidget);
        expect(find.textContaining('of 5'), findsNothing);
        expect(find.textContaining('of 4'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-36 an unknown owner-set version disables the pair with its '
      'reason (13 §4.3)',
      (tester) async {
        final seam = _seam([
          _item(request: _request(ownerSetVersion: 7), viewerId: 'u2'),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(
          find.textContaining('cannot count the approvals'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
        expect(
          find.widgetWithText(OutlinedButton, 'Veto with reason'),
          findsNothing,
        );
        expect(find.textContaining('owners have approved'), findsNothing);
      },
    );

    testWidgets('F1-07-36 the card says nothing has been applied yet '
        '(02 §7.2.1 🔒)', (tester) async {
      final seam = _seam([
        _item(approvedBy: const ['u1']),
      ]);
      await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

      expect(
        find.textContaining('No money and no permission moves'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Lapses on 19 Sep 2026 if the owners have not agreed by then.',
        ),
        findsOneWidget,
        reason: 'the 14-day window of 02 §7.2.1, from the engine\'s deadline',
      );
    });
  });

  group('F1-07-36 who sees what', () {
    testWidgets('F1-07-36 an owner who has not voted gets both actions', (
      tester,
    ) async {
      final seam = _seam([
        _item(viewerId: 'u2', approvedBy: const ['u1']),
      ]);
      await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

      expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Veto with reason'),
        findsOneWidget,
      );
    });

    testWidgets(
      'F1-07-36 the initiator is told that raising is not approving, and '
      'still gets the actions (02 §7.2.1, A-02-94)',
      (tester) async {
        final seam = _seam([_item(viewerId: 'u1')]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(
          find.textContaining('Raising it is not approving it'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
        expect(find.text('0 of 3 owners have approved'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-36 an owner who has voted sees their vote and what is still '
      'waited on, and no second Approve',
      (tester) async {
        final seam = _seam([
          _item(viewerId: 'u2', approvedBy: const ['u1', 'u2']),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(find.text('You approved this.'), findsOneWidget);
        expect(find.text('Waiting on 1 more owner.'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
        expect(
          find.widgetWithText(OutlinedButton, 'Veto with reason'),
          findsNothing,
        );
      },
    );

    testWidgets('F1-07-36 a member who is not an owner is told who decides '
        '(13 §2.3.1)', (tester) async {
      final seam = _seam([
        _item(viewerId: 'm9', viewerIsOwner: false, approvedBy: const ['u1']),
      ]);
      await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

      expect(
        find.textContaining('The owners of Sharma Brothers decide this one.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'Veto with reason'),
        findsNothing,
      );
    });

    testWidgets(
      'F1-07-36 a single-owner book draws no card at all (02 §7.2.1 🔒)',
      (tester) async {
        final seam = _seam([
          _item(owners: const {'u1'}, viewerId: 'u1'),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(find.text('Needs the owners’ decision'), findsNothing);
        expect(find.text('Change the ownership shares'), findsNothing);
        expect(
          find.text('Nothing needs you right now.'),
          findsOneWidget,
          reason: 'with nothing visible the tray is simply empty',
        );
      },
    );
  });

  group('F1-07-36 deciding', () {
    testWidgets(
      'F1-07-36 Approve confirms, then reaches the seam for that request',
      (tester) async {
        final seam = _seam([_item(viewerId: 'u2')]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
        await tester.pumpAndSettle();
        expect(find.text('Approve this change?'), findsOneWidget);
        expect(
          find.textContaining('signed on this phone'),
          findsOneWidget,
          reason: '02 §7.2.1: each approval is authored on the owner’s device',
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
        await tester.pumpAndSettle();

        expect(seam.approved, ['r1']);
        expect(find.text('Your approval is recorded.'), findsOneWidget);
      },
    );

    testWidgets('F1-07-36 cancelling the confirmation signs nothing', (
      tester,
    ) async {
      final seam = _seam([_item(viewerId: 'u2')]);
      await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(seam.approved, isEmpty);
    });

    testWidgets(
      'F1-07-36 a veto names its consequence, demands a reason, and carries '
      'it to the seam (07 §26 🔒, 02 §7.2.1 🔒)',
      (tester) async {
        final seam = _seam([_item(viewerId: 'u2')]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Veto with reason'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Why are you vetoing this?'), findsOneWidget);
        expect(
          find.textContaining('closes this request for everyone'),
          findsOneWidget,
        );
        expect(
          find.textContaining('go on the book’s record'),
          findsOneWidget,
          reason: '02 §7.2 item 3: the veto joins the admin-actions feed',
        );

        // A blank reason can never leave the sheet.
        await tester.tap(
          find.widgetWithText(FilledButton, 'Veto this request'),
        );
        await tester.pumpAndSettle();
        expect(seam.vetoes, isEmpty);
        expect(find.textContaining('Write a reason first'), findsOneWidget);

        await tester.enterText(
          find.byType(TextField),
          '  The shares were agreed at the start.  ',
        );
        await tester.tap(
          find.widgetWithText(FilledButton, 'Veto this request'),
        );
        await tester.pumpAndSettle();

        expect(seam.vetoes, [
          (requestId: 'r1', reason: 'The shares were agreed at the start.'),
        ]);
        expect(find.text('Vetoed. The request is closed.'), findsOneWidget);
      },
    );

    testWidgets('F1-07-36 a failed write says so and changes nothing', (
      tester,
    ) async {
      final seam = _seam([_item(viewerId: 'u2')])
        ..failNext = const StructuralRequestFailure();
      await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
      await tester.pumpAndSettle();

      expect(seam.approved, isEmpty);
      expect(find.textContaining('Nothing has changed.'), findsOneWidget);
    });
  });

  group('F1-07-36 decided requests', () {
    testWidgets(
      'F1-07-36 a veto shows who, why, and that it is on the record',
      (tester) async {
        final r = _request();
        final veto = StructuralVeto(
          id: 'v1',
          bookId: r.bookId,
          hlc: Hlc.compose(
            physicalMs: r.hlc.physicalMs + 3600 * 1000,
            counter: 0,
          ),
          requestId: r.id,
          byUser: 'u3',
          ownerSetVersion: 1,
          reason: 'We settled this at the start.',
        );
        final seam = _seam([
          _item(request: r, extraRecords: [veto], viewerId: 'u2'),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(find.text('Cancelled by Harjit'), findsOneWidget);
        expect(
          find.text('Reason: We settled this at the start.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('stay on the book’s record'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
      },
    );

    testWidgets(
      'F1-07-36 a lapsed request says so and offers the one next action '
      '(02 §7.2.1: lapsed, logged, re-initiable)',
      (tester) async {
        final seam = _seam([
          _item(
            request: _request(daysAgo: 20),
            viewerId: 'u2',
            viewerCanInitiate: true,
          ),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(find.text('Lapsed — 14 days with no decision'), findsOneWidget);
        expect(find.textContaining('closed on its own'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);

        await tester.tap(find.widgetWithText(FilledButton, 'Raise it again'));
        await tester.pumpAndSettle();
        expect(seam.reinitiated, ['r1']);
      },
    );

    testWidgets(
      'F1-07-36 a lapsed request an owner may not re-raise is still not a '
      'dead end (07 §1 rule 6)',
      (tester) async {
        final seam = _seam([
          _item(request: _request(daysAgo: 20), viewerId: 'u2'),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(
          find.text('An admin of Sharma Brothers can raise it again.'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Raise it again'),
          findsNothing,
        );
      },
    );

    testWidgets('F1-07-36 quorum reached is stated as in force', (
      tester,
    ) async {
      final seam = _seam([
        _item(viewerId: 'u2', approvedBy: const ['u1', 'u2', 'u3']),
      ]);
      await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

      expect(find.text('The owners agreed'), findsOneWidget);
      expect(
        find.text('3 of 3 owners approved, so this is now in force.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
    });
  });

  group('F1-07-36 the review surface', () {
    testWidgets(
      'F1-07-36 S6.3 names who has approved, marks the reader, and states '
      'the rule in force',
      (tester) async {
        final seam = _seam([
          _item(viewerId: 'u2', approvedBy: const ['u1', 'u2']),
        ]);
        await pumpRk(tester, _surface(seam), viewport: rkTallViewport);

        expect(find.text('Structural change'), findsOneWidget);
        expect(find.text('Who has approved'), findsOneWidget);
        expect(find.text('Amrit'), findsWidgets);
        expect(find.text('Sukhdev (you)'), findsOneWidget);
        expect(find.text('3 of the 3 owners must approve.'), findsOneWidget);
        expect(find.text('Raised on 05 Sep 2026 by Amrit'), findsOneWidget);
      },
    );

    testWidgets('F1-07-36 nobody has approved yet is said, not left blank', (
      tester,
    ) async {
      final seam = _seam([_item(viewerId: 'u2')]);
      await pumpRk(tester, _surface(seam), viewport: rkTallViewport);

      expect(find.text('Nobody has approved yet.'), findsOneWidget);
    });

    testWidgets(
      'F1-07-36 a request that is gone gets an explanation and a way back',
      (tester) async {
        final seam = _seam([_item()]);
        var back = 0;
        await pumpRk(
          tester,
          _surface(seam, requestId: 'gone', onDone: () => back++),
          viewport: rkTallViewport,
        );

        expect(find.text('That request is not here any more.'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Back to Inbox'));
        await tester.pumpAndSettle();
        expect(back, 1);
      },
    );

    testWidgets('F1-07-36 the surface decides through the same seam', (
      tester,
    ) async {
      final seam = _seam([_item(viewerId: 'u2')]);
      await pumpRk(tester, _surface(seam), viewport: rkTallViewport);

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
      await tester.pumpAndSettle();

      expect(seam.approved, ['r1']);
    });
  });

  group('F1-07-36 states, vocabulary and layout', () {
    testWidgets('F1-07-36 the skeleton stands in before the first load', (
      tester,
    ) async {
      final seam = FakeStructuralRequests();
      addTearDown(seam.dispose);
      await pumpRk(tester, _surface(seam), viewport: rkPhone360);

      expect(find.bySemanticsLabel('Loading your inbox'), findsOneWidget);
    });

    testWidgets('F1-07-36 a failed load offers the retry (13 §4.3)', (
      tester,
    ) async {
      final seam = FakeStructuralRequests()
        ..failNext = const StructuralRequestFailure();
      addTearDown(seam.dispose);
      await pumpRk(tester, _surface(seam), viewport: rkPhone360);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets(
      'F1-07-36 S6.3 is a consumer surface: no bare Dr or Cr (02 §10 🔒)',
      (tester) async {
        final seam = _seam([
          _item(approvedBy: const ['u1'], terms: _ratioTerms),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        final bare = RegExp(r'(^|[\s(])(Dr|Cr)\.?([\s),.]|$)');
        for (final s in _painted(tester)) {
          expect(
            bare.hasMatch(s),
            isFalse,
            reason: 'Dr/Cr belongs to professional surfaces only: "$s"',
          );
        }
      },
    );

    testWidgets(
      'F1-07-36 every status is an icon and a word, never a colour alone '
      '(07 §1 rule 3)',
      (tester) async {
        final cases = <String, StructuralItem>{
          'pending': _item(approvedBy: const ['u1']),
          'lapsed': _item(request: _request(daysAgo: 20)),
          'approved': _item(approvedBy: const ['u1', 'u2', 'u3']),
        };
        for (final entry in cases.entries) {
          final seam = _seam([entry.value]);
          await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);
          expect(
            find.byType(Icon),
            findsWidgets,
            reason: '${entry.key} carries an icon beside its words',
          );
          expect(
            _painted(tester).where((s) => s.trim().isNotEmpty),
            isNotEmpty,
            reason: '${entry.key} says what it is in words',
          );
        }
      },
    );

    testWidgets('F1-07-36 the card fits EN/PA/HI at 1.3 and 2.0 on 360×800', (
      tester,
    ) async {
      for (final locale in rkLocales) {
        for (final scale in rkTextScales) {
          final seam = _seam([
            _item(viewerId: 'u2', approvedBy: const ['u1'], terms: _ratioTerms),
          ]);
          await pumpRk(
            tester,
            _inbox(seam),
            locale: locale,
            textScale: scale,
            viewport: rkPhone360,
          );
          expect(tester.takeException(), isNull);
          expectTextFits(tester, reason: '${locale.languageCode} at $scale×');
        }
      }
    });

    testWidgets(
      'F1-07-36 the review surface fits EN/PA/HI at 1.3 and 2.0 on 360×800',
      (tester) async {
        for (final locale in rkLocales) {
          for (final scale in rkTextScales) {
            final seam = _seam([
              _item(
                viewerId: 'u2',
                approvedBy: const ['u1', 'u2'],
                terms: _ratioTerms,
              ),
            ]);
            await pumpRk(
              tester,
              _surface(seam),
              locale: locale,
              textScale: scale,
              viewport: rkPhone360,
            );
            expect(tester.takeException(), isNull);
            expectTextFits(tester, reason: '${locale.languageCode} at $scale×');
          }
        }
      },
    );

    testWidgets(
      'F1-07-36 the veto sheet fits EN/PA/HI at 1.3 and 2.0 on 360×800',
      (tester) async {
        for (final locale in rkLocales) {
          for (final scale in rkTextScales) {
            // A fresh root between cases: pumping another MaterialApp keeps
            // the same Navigator state, so the sheet opened last time would
            // still be mounted and this case would measure it instead.
            await tester.pumpWidget(const SizedBox());
            final seam = _seam([_item(viewerId: 'u2')]);
            await pumpRk(
              tester,
              _inbox(seam),
              locale: locale,
              textScale: scale,
              viewport: rkPhone360,
            );
            // The button sits below the fold at 200 %: scroll to it, or the
            // tap misses, the sheet never opens and this case passes on the
            // card it was not meant to measure.
            await tester.ensureVisible(find.byType(OutlinedButton));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(OutlinedButton));
            await tester.pumpAndSettle();
            expect(
              find.byType(TextField),
              findsOneWidget,
              reason: 'the veto sheet is what this case measures',
            );
            expect(tester.takeException(), isNull);
            expectTextFits(
              tester,
              reason: 'veto sheet ${locale.languageCode} at $scale×',
            );
          }
        }
      },
    );

    testWidgets(
      'F1-07-36 S6 draws the structural section above the review cards',
      (tester) async {
        final seam = _seam([
          _item(approvedBy: const ['u1']),
        ]);
        await pumpRk(tester, _inbox(seam), viewport: rkTallViewport);

        expect(find.text('Needs the owners’ decision'), findsOneWidget);
        // Reviews are empty in this fixture, so the tray's empty state must
        // not claim there is nothing to do.
        expect(find.text('Nothing needs you right now.'), findsNothing);
      },
    );
  });
}
