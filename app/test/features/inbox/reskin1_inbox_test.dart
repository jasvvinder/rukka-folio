// RESKIN1 round 2, slice R2A — audit captures for the Inbox (ADR 2026-10-05
// §2; ADR 2026-10-10b §1 phase 1: an audit, not a build). Pair with
// `python3 scripts/design_match.py pair <S-id>`.
//
// S6   — canvas 9 *Inbox · three waiting*.
// S6.1 — canvas 9 *Grouped review card · Approve all or one by one*. The app
//        has no S6.1 screen: the grouped card is [ReviewCard], drawn inline in
//        S6, so S6.1 is captured as S6 holding that card.
// S6.2 — canvas 9 *Review stepper · 3 of 7*.
// S6.3 — canvas 9 *Structural approval · 2 of 3 approved*.
//
// TEST HONESTY: S6 and S6.2 run on the seams production installs
// (bootstrap.dart: `LateArrivalsScope(tray: LedgerLateArrivals(ledger))` and
// `ReviewQueueScope(queue: LedgerReviewQueue(ledger, authorNameOf: …))`) over a
// real ledger holding flagged entries by another member, with the constructor
// arguments `inboxRoot` / `inboxRoutes` pass (inbox_routes.dart). The author
// name stands in for the members repository's answer when this phone holds
// the contact. Synthetic names and sums only (CLAUDE.md rule 4).
@Tags(['F1'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/late_arrivals.dart';
import 'package:rukka_folio/features/inbox/ledger_late_arrivals.dart';
import 'package:rukka_folio/features/inbox/ledger_review_queue.dart';
import 'package:rukka_folio/features/inbox/review_queue.dart';
import 'package:rukka_folio/features/inbox/screens/s6_2_review_stepper_screen.dart';
import 'package:rukka_folio/features/inbox/screens/s6_3_structural_review_screen.dart';
import 'package:rukka_folio/features/inbox/screens/s6_inbox_screen.dart';
import 'package:rukka_folio/features/inbox/structural_requests.dart';
import 'package:rukka_folio/features/inbox/widgets/review_card.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart';

const _ramesh = 'user-ramesh';

/// Writes the screen as it stands now — the same root-layer picture
/// [rkDesignCapture] takes, for a state a tap reached.
Future<void> _snap(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: rkDesignPixelRatio,
    );
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    File('$rkDesignCaptureDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png.buffer.asUint8List());
    image.dispose();
  });
}

void _drop(String name) {
  final f = File('$rkDesignCaptureDir/$name.png');
  if (f.existsSync()) f.deleteSync();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Lets the ledger writes behind a tap land, then settles the frame.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// A posted, flagged entry by Ramesh (02 §1.3 🔒: the authoring client sets
/// `review_required`), as `ledger_review_queue_test.dart` posts them.
Future<void> _flag(
  LocalLedger ledger,
  String bookId,
  List<Line> lines, {
  required EntryKind kind,
  String? note,
}) => ledger.post(
  Entry(
    id: '',
    bookId: bookId,
    kind: kind,
    status: EntryStatus.posted,
    reviewRequired: true,
    accountingDate: ledger.today(),
    lines: lines,
    note: note,
    reviewApprover: ledger.identity.userId,
    createdByUser: _ramesh,
    createdByDevice: 'device-of-$_ramesh',
    hlc: const Hlc(0),
  ),
);

/// The live seams over a seeded book holding seven of Ramesh's entries from
/// today — one card (07 §9: one card per author + book + day).
final class _Inbox {
  _Inbox(this.ledger, this.queue, this.tray);
  final LocalLedger ledger;
  final LedgerReviewQueue queue;
  final LedgerLateArrivals tray;

  Widget wrap(Widget child) => LateArrivalsScope(
    tray: tray,
    child: ReviewQueueScope(queue: queue, child: child),
  );
}

Future<_Inbox> _inbox(WidgetTester tester) async {
  late _Inbox out;
  await tester.runAsync(() async {
    final s = await seedSoloLedger();
    final l = s.ledger;
    final chart = await l.chartOf(s.bookId);
    Account a(String id) => chart.account(id);
    final out7 = <(String, int)>[
      ('Isuzu, full tank', 240_000),
      ('Freight to Ludhiana', 180_000),
      ('Labour and material', 380_000),
      ('Packing boxes', 45_000),
      ('Tea for the stall', 12_000),
    ];
    for (final (note, paise) in out7) {
      await _flag(
        l,
        s.bookId,
        Verbs.moneyOut(
          from: a(s.cashId),
          forWhat: a(s.fuelId),
          amount: Paise(paise),
        ),
        kind: EntryKind.moneyOut,
        note: note,
      );
    }
    for (final (note, paise) in [
      ('Counter cash sales', 1_860_000),
      ('Cotton lot 40 kg', 1_200_000),
    ]) {
      await _flag(
        l,
        s.bookId,
        Verbs.moneyIn(
          into: a(s.cashId),
          from: a(s.salesId),
          amount: Paise(paise),
        ),
        kind: EntryKind.moneyIn,
        note: note,
      );
    }
    final queue = LedgerReviewQueue(
      l,
      authorNameOf: (id) => id == _ramesh ? 'Ramesh Sharma' : '',
    );
    final tray = LedgerLateArrivals(l);
    for (var i = 0; i < 600; i++) {
      await queue.refresh();
      if (queue.current?.reviews.length == 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await tray.refresh();
    out = _Inbox(l, queue, tray);
  });
  addTearDown(
    () => tester.runAsync(() async {
      await out.queue.dispose();
      await out.tray.dispose();
    }),
  );
  return out;
}

InboxScreen _inboxScreen() => InboxScreen(
  onOpenLedger: () {},
  onReviewGroup: (_) {},
  onOpenStructural: (_) {},
  onOpenLateArrivals: () {},
);

// ---------------------------------------------------------------- S6.3

final _nowMs = testNow().millisecondsSinceEpoch;

/// 07 §26's worked example, as `s6_3_structural_test.dart` builds it: Amrit
/// proposes 40 · 30 · 30 over equal thirds; Amrit and Sukhdev have approved;
/// the viewer is Harjit, an owner who has not voted yet.
StructuralItem _ratioChange() {
  final r = StructuralRequest(
    id: 'r1',
    bookId: 'b1',
    hlc: Hlc.compose(physicalMs: _nowMs - 2 * 60 * 60 * 1000, counter: 0),
    action: StructuralAction.ownershipRatio,
    byUser: 'u1',
    ownerSetVersion: 1,
  );
  StructuralApproval approval(String by, int n) => StructuralApproval(
    id: 'a-$by',
    bookId: r.bookId,
    hlc: Hlc.compose(physicalMs: r.hlc.physicalMs + n * 60 * 1000, counter: 0),
    requestId: r.id,
    byUser: by,
    ownerSetVersion: 1,
  );
  const owners = {'u1', 'u2', 'u3'};
  final outcome = evaluateStructural(
    request: r,
    records: [approval('u1', 1), approval('u2', 2)],
    owners: const [
      OwnerSetVersion(
        version: 1,
        ownerIds: owners,
        quorum: StructuralQuorum.allOwners,
      ),
    ],
    asOfMs: _nowMs,
  );
  return StructuralItem(
    request: r,
    outcome: outcome,
    bookName: 'Sharma Brothers',
    initiatorName: 'Amrit Kaur',
    ownerNames: const {'u1': 'Amrit', 'u2': 'Sukhdev', 'u3': 'Harjit'},
    viewerId: 'u3',
    viewerIsOwner: true,
    viewerCanInitiate: false,
    terms: const [
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
    ],
  );
}

void main() {
  testWidgets('F1-1010r2A-6 design capture S6 (inbox, one grouped card of '
      'seven) and S6.1 (the grouped review card, entry list open)', (
    tester,
  ) async {
    for (final target in RkDesignTarget.values) {
      final inbox = await _inbox(tester);
      await rkDesignCapture(
        tester,
        sid: 'S6',
        state: 'waiting',
        target: target,
        tab: RkTab.inbox,
        ledger: inbox.ledger,
        child: inbox.wrap(_inboxScreen()),
      );
      expect(find.byType(ReviewCard), findsOneWidget);
      expect(find.text('Ramesh Sharma'), findsWidgets);
      // S6.1: c9 *Grouped review card* draws the entry list open — the state
      // production reaches by tapping 'Show the entries' on the card
      // (review_card.dart toggles _expanded). Captured after that tap, so the
      // pair compares the frame's rows with the app's _EntryRow, not a second
      // copy of S6.
      expect(find.text('Show the entries'), findsOneWidget);
      await tester.tap(find.text('Show the entries'));
      await _settle(tester);
      expect(find.text('Hide the entries'), findsOneWidget);
      await _snap(tester, 'S6.1__grouped-card${target.suffix}');
      await _unmount(tester);
    }
  });

  testWidgets('F1-1010r2A-7 design capture S6.2 (stepper, 3 of 7 after two '
      'approvals)', (tester) async {
    for (final target in RkDesignTarget.values) {
      final inbox = await _inbox(tester);
      final group = inbox.queue.current!.reviews.single;
      expect(group.count, 7);
      await rkDesignCapture(
        tester,
        sid: 'S6.2',
        state: 'pre',
        target: target,
        ledger: inbox.ledger,
        child: inbox.wrap(ReviewStepperScreen(groupId: group.id)),
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
        await _settle(tester);
      }
      expect(find.text('3 of 7'), findsOneWidget);
      await _snap(tester, 'S6.2__3-of-7${target.suffix}');
      _drop('S6.2__pre${target.suffix}');
      await _unmount(tester);
    }
  });

  // ⚠️ SPEC: this state is UNREACHABLE in production. No StructuralRequestsScope
  // is installed anywhere in app/lib (bootstrap.dart wires LateArrivalsScope
  // and ReviewQueueScope only), so StructuralRequestsScope.of falls back to an
  // empty FakeStructuralRequests: S6 never draws a structural card and nothing
  // opens S6.3. The card is captured on that fake only so the frame can be
  // compared with the widget that would draw it; design/match/S6.3.json
  // records the gap.
  testWidgets('F1-1010r2A-8 design capture S6.3 (structural approval, 2 of 3 '
      '— unreachable in production, see ⚠️ SPEC)', (tester) async {
    for (final target in RkDesignTarget.values) {
      final seam = FakeStructuralRequests(
        initial: StructuralInbox(items: [_ratioChange()]),
      );
      addTearDown(seam.dispose);
      await rkDesignCapture(
        tester,
        sid: 'S6.3',
        state: 'unreachable-2-of-3',
        target: target,
        child: StructuralRequestsScope(
          requests: seam,
          child: StructuralReviewScreen(requestId: 'r1', onDone: () {}),
        ),
      );
      expect(find.byType(StructuralReviewScreen), findsOneWidget);
      await _unmount(tester);
    }
  });
}
