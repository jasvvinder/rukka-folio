// Suite A / H2b — multiple admins and the quorum rule (02 §7.2.1 🔒).
// Engine only: signed-record counting, the `structural_quorum` setting and its
// round-trip, veto, expiry, single-owner books, and the 🔒 enumeration of
// structural actions. Synthetic data only. The screen (S6.3) and the server
// relay are other lanes.
@Tags(['A'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Physical milliseconds for a synthetic day number — the injected time base.
int day(int n) => n * 86400000;

Hlc at(int dayNo, [int counter = 0]) =>
    Hlc.compose(physicalMs: day(dayNo), counter: counter);

void main() {
  const book = 'farm';
  const three = OwnerSetVersion(
    version: 1,
    ownerIds: {'amrit', 'sukhdev', 'harjit'},
    quorum: StructuralQuorum.allOwners,
  );

  StructuralRequest ratioRequest({
    Hlc? hlc,
    int version = 1,
    String by = 'amrit',
  }) => StructuralRequest(
    id: 'req-ratio',
    bookId: book,
    hlc: hlc ?? at(10),
    action: StructuralAction.ownershipRatio,
    byUser: by,
    ownerSetVersion: version,
    payload: const {
      'partner_shares': {
        'farm:amrit': 40,
        'farm:sukhdev': 30,
        'farm:harjit': 30,
      },
    },
  );

  StructuralApproval approve(
    String by,
    Hlc hlc, {
    String? id,
    int version = 1,
    String requestId = 'req-ratio',
  }) => StructuralApproval(
    id: id ?? 'ok-$by-${hlc.raw}',
    bookId: book,
    hlc: hlc,
    requestId: requestId,
    byUser: by,
    ownerSetVersion: version,
  );

  StructuralVeto veto(String by, Hlc hlc, {String reason = 'not agreed'}) =>
      StructuralVeto(
        id: 'veto-$by',
        bookId: book,
        hlc: hlc,
        requestId: 'req-ratio',
        byUser: by,
        ownerSetVersion: 1,
        reason: reason,
      );

  group('A-02-94 the quorum rule (02 §7.2.1 🔒)', () {
    test('A-02-94 quorum sizes: all owners = n; majority = ⌈n/2⌉+1 capped at n; one owner = 1', () {
      for (var n = 1; n <= 7; n++) {
        expect(StructuralQuorum.allOwners.requiredOf(n), n, reason: 'all/$n');
      }
      // ⌈n/2⌉ + 1 as written in 02 §7.2.1, never more than the owners there are.
      expect(StructuralQuorum.majority.requiredOf(1), 1);
      expect(StructuralQuorum.majority.requiredOf(2), 2);
      expect(StructuralQuorum.majority.requiredOf(3), 3);
      expect(StructuralQuorum.majority.requiredOf(4), 3);
      expect(StructuralQuorum.majority.requiredOf(5), 4);
      expect(StructuralQuorum.majority.requiredOf(6), 4);
      expect(StructuralQuorum.majority.requiredOf(7), 5);
      expect(
        () => StructuralQuorum.majority.requiredOf(0),
        throwsArgumentError,
      );
    });

    test('A-02-94 initiation alone changes nothing: pending, zero approvals, threshold 3', () {
      final out = evaluateStructural(
        request: ratioRequest(),
        records: const [],
        owners: const [three],
        asOfMs: day(11),
      );
      expect(out.status, StructuralStatus.pending);
      expect(out.isApplied, isFalse);
      expect(out.approvedBy, isEmpty);
      expect(out.threshold, 3);
      expect(out.decidedAt, isNull);
      expect(out.deadlineMs, day(10) + structuralExpiryMs);
    });

    test('A-02-94 two of three on an all-owners quorum is still pending; the third applies it', () {
      final two = [approve('amrit', at(11)), approve('sukhdev', at(12))];
      final pending = evaluateStructural(
        request: ratioRequest(),
        records: two,
        owners: const [three],
        asOfMs: day(13),
      );
      expect(pending.status, StructuralStatus.pending);
      expect(pending.approvedBy, ['amrit', 'sukhdev']);
      expect(pending.isApplied, isFalse);

      final done = evaluateStructural(
        request: ratioRequest(),
        records: [...two, approve('harjit', at(13))],
        owners: const [three],
        asOfMs: day(13),
      );
      expect(done.status, StructuralStatus.approved);
      expect(done.isApplied, isTrue);
      expect(done.approvedBy, ['amrit', 'sukhdev', 'harjit']);
      // Effective at the order point of the third (k-th) approval — like the
      // k-th smallest `seq` of ADR 2026-09-06 §3.
      expect(done.decidedAt, at(13));
      expect(done.decidedById, 'ok-harjit-${at(13).raw}');
    });

    test('A-02-94 the initiator is not counted as an approver — a signed approval envelope is', () {
      final out = evaluateStructural(
        request: ratioRequest(by: 'amrit'),
        records: [approve('sukhdev', at(11)), approve('harjit', at(12))],
        owners: const [three],
        asOfMs: day(12),
      );
      expect(out.status, StructuralStatus.pending);
      expect(out.approvedBy, ['sukhdev', 'harjit']);
    });

    test('A-02-94 deterministic on every device: arrival order never changes the outcome', () {
      final records = [
        approve('harjit', at(13)),
        approve('amrit', at(11)),
        veto('sukhdev', at(12, 5)),
        approve('sukhdev', at(12)),
      ];
      final a = evaluateStructural(
        request: ratioRequest(),
        records: records,
        owners: const [three],
        asOfMs: day(20),
      );
      final b = evaluateStructural(
        request: ratioRequest(),
        records: records.reversed,
        owners: const [three],
        asOfMs: day(20),
      );
      expect(a.status, b.status);
      expect(a.approvedBy, b.approvedBy);
      expect(a.decidedAt, b.decidedAt);
      expect(a.decidedById, b.decidedById);
      expect(
        a.ignored.map((i) => (i.recordId, i.reason)),
        b.ignored.map((i) => (i.recordId, i.reason)),
      );
      // Sukhdev approved and then vetoed: the veto, later in (hlc, id) order,
      // closes the request before Harjit's approval could complete it.
      expect(a.status, StructuralStatus.vetoed);
    });

    test('A-02-94 never cached as final: a late-arriving veto ordered before the k-th approval flips approved → vetoed', () {
      final approvals = [
        approve('amrit', at(11)),
        approve('sukhdev', at(12)),
        approve('harjit', at(13)),
      ];
      final before = evaluateStructural(
        request: ratioRequest(),
        records: approvals,
        owners: const [three],
        asOfMs: day(14),
      );
      expect(before.status, StructuralStatus.approved);
      final after = evaluateStructural(
        request: ratioRequest(),
        records: [
          ...approvals,
          veto('harjit', at(12, 1), reason: 'wait for the season'),
        ],
        owners: const [three],
        asOfMs: day(14),
      );
      expect(after.status, StructuralStatus.vetoed);
      expect(after.veto?.reason, 'wait for the season');
      expect(after.isApplied, isFalse);
      // Harjit's own later approval no longer counts: the request was closed.
      expect(
        after.ignored,
        contains(
          predicate<StructuralIgnored>(
            (i) =>
                i.recordId == 'ok-harjit-${at(13).raw}' &&
                i.reason == StructuralIgnoreReason.afterDecision,
          ),
        ),
      );
    });

    test('A-02-94 one approval per owner: a duplicate is ignored and logged; a non-owner never counts', () {
      final out = evaluateStructural(
        request: ratioRequest(),
        records: [
          approve('amrit', at(11)),
          approve('amrit', at(12), id: 'ok-amrit-again'),
          approve('cousin', at(12, 1), id: 'ok-cousin'),
          approve('sukhdev', at(13)),
        ],
        owners: const [three],
        asOfMs: day(13),
      );
      expect(out.status, StructuralStatus.pending);
      expect(out.approvedBy, ['amrit', 'sukhdev']);
      expect(out.ignored.map((i) => (i.recordId, i.reason)), [
        ('ok-amrit-again', StructuralIgnoreReason.duplicateAuthor),
        ('ok-cousin', StructuralIgnoreReason.notOwner),
      ]);
    });

    test('A-02-94 a veto closes the request immediately with its reason; nothing applies afterwards', () {
      final out = evaluateStructural(
        request: ratioRequest(),
        records: [
          approve('amrit', at(11)),
          veto('harjit', at(12), reason: 'ratio was agreed for three seasons'),
          approve('sukhdev', at(13)),
          approve('harjit', at(14)),
        ],
        owners: const [three],
        asOfMs: day(14),
      );
      expect(out.status, StructuralStatus.vetoed);
      expect(out.veto?.byUser, 'harjit');
      expect(out.veto?.reason, 'ratio was agreed for three seasons');
      expect(out.decidedAt, at(12));
      expect(out.approvedBy, ['amrit']);
      expect(out.isApplied, isFalse);
      expect(
        out.ignored.map((i) => i.reason),
        everyElement(StructuralIgnoreReason.afterDecision),
      );
    });

    test('A-02-94 a veto needs a recorded reason and an owner', () {
      expect(() => veto('harjit', at(12), reason: ''), throwsArgumentError);
      expect(() => veto('harjit', at(12), reason: '   '), throwsArgumentError);
      final out = evaluateStructural(
        request: ratioRequest(),
        records: [
          StructuralVeto(
            id: 'veto-cousin',
            bookId: book,
            hlc: at(12),
            requestId: 'req-ratio',
            byUser: 'cousin',
            ownerSetVersion: 1,
            reason: 'I object',
          ),
        ],
        owners: const [three],
        asOfMs: day(12),
      );
      expect(out.status, StructuralStatus.pending);
      expect(out.ignored.single.reason, StructuralIgnoreReason.notOwner);
    });

    test('A-02-94 expiry: 14 days without quorum → lapsed against the injected time, approvals after the window do not count', () {
      // ⚠️ SPEC: 02 §7.2.1 marks the 14-day window "confirm"; taken as written.
      expect(structuralExpiryDays, 14);
      final records = [approve('amrit', at(11)), approve('sukhdev', at(12))];
      final inWindow = evaluateStructural(
        request: ratioRequest(),
        records: records,
        owners: const [three],
        asOfMs: day(24),
      );
      expect(inWindow.status, StructuralStatus.pending);
      final lapsed = evaluateStructural(
        request: ratioRequest(),
        records: records,
        owners: const [three],
        asOfMs: day(24) + 1,
      );
      expect(lapsed.status, StructuralStatus.lapsed);
      expect(lapsed.lapseRecorded, isFalse);
      expect(lapsed.isApplied, isFalse);
      // A third approval authored after the deadline is ignored, so the same
      // record set lapses on every device whatever its clock says.
      final late = evaluateStructural(
        request: ratioRequest(),
        records: [...records, approve('harjit', at(25))],
        owners: const [three],
        asOfMs: day(30),
      );
      expect(late.status, StructuralStatus.lapsed);
      expect(late.ignored.single.reason, StructuralIgnoreReason.afterDeadline);
      // An approval on the last millisecond of the window still counts.
      final edge = evaluateStructural(
        request: ratioRequest(),
        records: [
          ...records,
          approve('harjit', Hlc.compose(physicalMs: day(24), counter: 9)),
        ],
        owners: const [three],
        asOfMs: day(30),
      );
      expect(edge.status, StructuralStatus.approved);
    });

    test('A-02-94 a recorded lapse is logged and re-initiable; one authored before the deadline is ignored', () {
      final early = StructuralLapse(
        id: 'lapse-early',
        bookId: book,
        hlc: at(20),
        requestId: 'req-ratio',
        byUser: 'amrit',
      );
      final out = evaluateStructural(
        request: ratioRequest(),
        records: [approve('amrit', at(11)), early],
        owners: const [three],
        asOfMs: day(21),
      );
      expect(out.status, StructuralStatus.pending);
      expect(
        out.ignored.single.reason,
        StructuralIgnoreReason.lapseBeforeDeadline,
      );

      final logged = StructuralLapse(
        id: 'lapse',
        bookId: book,
        hlc: at(25),
        requestId: 'req-ratio',
        byUser: 'amrit',
      );
      final lapsed = evaluateStructural(
        request: ratioRequest(),
        records: [approve('amrit', at(11)), logged],
        owners: const [three],
        asOfMs: day(25),
      );
      expect(lapsed.status, StructuralStatus.lapsed);
      expect(lapsed.lapseRecorded, isTrue);
      expect(lapsed.decidedById, 'lapse');
      // Re-initiable: a fresh request with a new id is evaluated on its own.
      final again = evaluateStructural(
        request: ratioRequest(hlc: at(26)).copyWith(id: 'req-ratio-2'),
        records: [approve('amrit', at(11)), logged],
        owners: const [three],
        asOfMs: day(26),
      );
      expect(again.status, StructuralStatus.pending);
      expect(again.approvedBy, isEmpty, reason: 'records name the old request');
    });

    test('A-02-94 counted against the version the record names; a re-versioned owner set does not reset the count', () {
      // v1: three owners, all-owners. v2 (an owner added by an approved
      // structural action): four owners, majority (⌈4/2⌉+1 = 3).
      const four = OwnerSetVersion(
        version: 2,
        ownerIds: {'amrit', 'sukhdev', 'harjit', 'gurmeet'},
        quorum: StructuralQuorum.majority,
      );
      final out = evaluateStructural(
        request: ratioRequest(version: 1),
        records: [
          approve('amrit', at(11), version: 1),
          approve(
            'gurmeet',
            at(12),
            version: 1,
            id: 'ok-gurmeet-v1',
          ), // not an owner at v1
          approve('gurmeet', at(13), version: 2, id: 'ok-gurmeet-v2'),
          approve('sukhdev', at(14), version: 2),
          approve(
            'harjit',
            at(12, 1),
            version: 9,
            id: 'ok-harjit-v9',
          ), // unknown version
        ],
        owners: const [three, four],
        asOfMs: day(16),
      );
      // Threshold is that of the earliest version among counted records (v1:
      // all three owners), so amrit + gurmeet + sukhdev = 3 approvals reach it
      // — approvals carry across versions and the bar is never raised mid-way.
      expect(out.threshold, 3);
      expect(out.approvedBy, ['amrit', 'gurmeet', 'sukhdev']);
      expect(out.status, StructuralStatus.approved);
      expect(out.decidedAt, at(14));
      expect(out.ignored.map((i) => (i.recordId, i.reason)), [
        ('ok-gurmeet-v1', StructuralIgnoreReason.notOwner),
        ('ok-harjit-v9', StructuralIgnoreReason.unknownVersion),
      ]);
    });

    test('A-02-94 a request naming an unknown owner-set version can never reach quorum', () {
      final out = evaluateStructural(
        request: ratioRequest(version: 7),
        records: [
          approve('amrit', at(11)),
          approve('sukhdev', at(12)),
          approve('harjit', at(13)),
        ],
        owners: const [three],
        asOfMs: day(13),
      );
      expect(out.status, StructuralStatus.pending);
      expect(out.threshold, isNull);
      expect(out.isApplied, isFalse);
    });

    test('A-02-94 single-owner books have a quorum of one and the concept is invisible', () {
      const justMe = OwnerSetVersion(
        version: 1,
        ownerIds: {'sunita'},
        quorum: StructuralQuorum.allOwners,
      );
      final request = StructuralRequest(
        id: 'req-fy',
        bookId: 'shop',
        hlc: at(10),
        action: StructuralAction.quorumSetting,
        byUser: 'sunita',
        ownerSetVersion: 1,
        payload: const {structuralQuorumKey: 'majority'},
      );
      final out = evaluateStructural(
        request: request,
        records: const [],
        owners: const [justMe],
        asOfMs: day(10),
      );
      // Applied at initiation: the owner's own signed initiation is the one
      // approval a quorum of one needs. Nothing is ever pending.
      expect(out.status, StructuralStatus.approved);
      expect(out.threshold, 1);
      expect(out.decidedAt, at(10));
      expect(out.decidedById, 'req-fy');
      expect(out.isApplied, isTrue);
      // And it never lapses, however late it is looked at.
      expect(
        evaluateStructural(
          request: request,
          records: const [],
          owners: const [justMe],
          asOfMs: day(400),
        ).status,
        StructuralStatus.approved,
      );
    });

    test('A-02-94 nothing is applied early: config unchanged and balances untouched until quorum, then the payload lands', () {
      // A book_config payload as a newer client might write it — with a field
      // this build does not know, which must survive verbatim (03 §3.3 rule 4 🔒).
      final config = <String, Object?>{
        'id': book,
        'type': 'business',
        'name': 'Kaur Farm',
        'ownership': 'shared',
        'partner_shares': {
          'farm:amrit': 1,
          'farm:sukhdev': 1,
          'farm:harjit': 1,
        },
        structuralQuorumKey: 'all_owners',
        'future_field': {
          'nested': [1, 2, 3],
          'flag': true,
        },
      };
      final snapshot = Map<String, Object?>.of(config);
      final two = [approve('amrit', at(11)), approve('sukhdev', at(12))];
      final pending = evaluateStructural(
        request: ratioRequest(),
        records: two,
        owners: const [three],
        asOfMs: day(12),
      );
      final unchanged = applyStructural(config, pending);
      expect(
        identical(unchanged, config),
        isTrue,
        reason: 'a pending action changes nothing',
      );
      expect(config, snapshot);

      final done = evaluateStructural(
        request: ratioRequest(),
        records: [...two, approve('harjit', at(13))],
        owners: const [three],
        asOfMs: day(13),
      );
      final applied = applyStructural(config, done);
      expect(applied['partner_shares'], {
        'farm:amrit': 40,
        'farm:sukhdev': 30,
        'farm:harjit': 30,
      });
      expect(applied[structuralQuorumKey], 'all_owners');
      expect(applied['future_field'], {
        'nested': [1, 2, 3],
        'flag': true,
      });
      expect(
        identical(applied['future_field'], config['future_field']),
        isTrue,
        reason: 'preserved verbatim, not copied',
      );
      expect(applied.keys.toSet(), snapshot.keys.toSet());
      expect(config, snapshot, reason: 'the input is never mutated');

      // Balances: the structural envelopes travel in the same book stream and
      // the projector neither sums nor quarantines them — before or after quorum.
      final farm = TestBook(book, bookType: BookType.business);
      final bank = farm.money('Bank');
      final seed = farm.income('Wheat sale');
      final sale = farm.entry(
        [dr(bank, rs(50000)), cr(seed, rs(50000))],
        kind: EntryKind.moneyIn,
        hlc: at(9),
      );
      final plain = project([sale], farm.chart);
      final withPending = project([sale, ratioRequest(), ...two], farm.chart);
      final withApproved = project([
        sale,
        ratioRequest(),
        ...two,
        approve('harjit', at(13)),
      ], farm.chart);
      for (final s in [withPending, withApproved]) {
        expect(s.balances.canonical(), plain.balances.canonical());
        expect(s.quarantined, isEmpty);
        expect(s.held, isEmpty);
        expect(s.entries.keys, plain.entries.keys);
      }
    });

    test('A-02-94 structural_quorum round-trips in book_config: absent → all owners; unknown value → all owners, preserved; every other field verbatim', () {
      expect(structuralQuorumOf(const {}), StructuralQuorum.allOwners);
      expect(
        structuralQuorumOf(const {structuralQuorumKey: 'majority'}),
        StructuralQuorum.majority,
      );
      expect(
        structuralQuorumOf(const {structuralQuorumKey: 'all_owners'}),
        StructuralQuorum.allOwners,
      );
      // A value a newer app wrote: this build reads it conservatively as all
      // owners and does not touch it.
      final newer = <String, Object?>{
        structuralQuorumKey: 'two_thirds',
        'x': 1,
      };
      expect(structuralQuorumOf(newer), StructuralQuorum.allOwners);
      expect(isStructuralQuorumKnown(newer), isFalse);
      expect(
        isStructuralQuorumKnown(const {structuralQuorumKey: 'majority'}),
        isTrue,
      );
      expect(
        isStructuralQuorumKnown(const {}),
        isTrue,
        reason: 'absent = the default, understood',
      );

      final config = <String, Object?>{
        'id': book,
        'name': 'Kaur Farm',
        'partner_shares': {'farm:amrit': 1},
        'future_field': ['keep', 'me'],
      };
      final changed = withStructuralQuorum(config, StructuralQuorum.majority);
      expect(changed[structuralQuorumKey], 'majority');
      expect(structuralQuorumOf(changed), StructuralQuorum.majority);
      expect(changed.keys.toList(), [...config.keys, structuralQuorumKey]);
      for (final k in config.keys) {
        expect(
          identical(changed[k], config[k]),
          isTrue,
          reason: '$k preserved verbatim',
        );
      }
      expect(
        config.containsKey(structuralQuorumKey),
        isFalse,
        reason: 'input never mutated',
      );
      expect(StructuralQuorum.fromWire('majority'), StructuralQuorum.majority);
      expect(StructuralQuorum.fromWire('nonsense'), isNull);
      expect(StructuralQuorum.fromWire(3), isNull);
    });

    test('A-02-94 changing the quorum setting is itself structural and applies only at quorum', () {
      final request = StructuralRequest(
        id: 'req-quorum',
        bookId: book,
        hlc: at(10),
        action: StructuralAction.quorumSetting,
        byUser: 'amrit',
        ownerSetVersion: 1,
        payload: const {structuralQuorumKey: 'majority'},
      );
      final config = <String, Object?>{
        structuralQuorumKey: 'all_owners',
        'name': 'Kaur Farm',
      };
      final pending = evaluateStructural(
        request: request,
        records: [
          approve('amrit', at(11), requestId: 'req-quorum'),
          approve('sukhdev', at(12), requestId: 'req-quorum'),
        ],
        owners: const [three],
        asOfMs: day(12),
      );
      expect(
        structuralQuorumOf(applyStructural(config, pending)),
        StructuralQuorum.allOwners,
      );
      final done = evaluateStructural(
        request: request,
        records: [
          approve('amrit', at(11), requestId: 'req-quorum'),
          approve('sukhdev', at(12), requestId: 'req-quorum'),
          approve('harjit', at(13), requestId: 'req-quorum'),
        ],
        owners: const [three],
        asOfMs: day(13),
      );
      expect(
        structuralQuorumOf(applyStructural(config, done)),
        StructuralQuorum.majority,
      );
    });

    test('A-02-94 changing the FY start is refused outright once any year has closed (ADR 2026-09-05e §9)', () {
      final request = StructuralRequest(
        id: 'req-fy',
        bookId: book,
        hlc: at(10),
        action: StructuralAction.fyStartChange,
        byUser: 'amrit',
        ownerSetVersion: 1,
        payload: const {'fy_start_month': 1},
      );
      expect(checkStructuralRequest(request, closedYears: const []), isNull);
      expect(
        checkStructuralRequest(request, closedYears: [FinancialYear(2025)]),
        StructuralRefusal.fyStartAfterYearClose,
      );
      // Any other action is unaffected by closed years.
      expect(
        checkStructuralRequest(
          ratioRequest(),
          closedYears: [FinancialYear(2025)],
        ),
        isNull,
      );
    });
  });

  group('A-02-95 the structural-action enumeration (02 §7.2.1 table 🔒)', () {
    test('A-02-95 exactly the table\'s set plus the quorum setting itself; adding or dropping one is a 🔒 change', () {
      expect(StructuralAction.values.map((a) => a.wire).toSet(), {
        'ownership_ratio',
        'profit_distribution',
        'interest_on_capital',
        'owner_add_or_remove',
        'member_removal',
        'year_reopen',
        'fy_start_change',
        'book_archive_or_delete',
        'quorum_setting',
      });
      expect(StructuralAction.values, hasLength(9));
      for (final a in StructuralAction.values) {
        expect(StructuralAction.fromWire(a.wire), a);
        expect(a.requiresQuorum, isTrue);
      }
      expect(StructuralAction.fromWire('invite_member'), isNull);
      expect(StructuralAction.fromWire('period_lock'), isNull);
    });

    test('A-02-95 config-shaped actions land in the book settings; the others are applied by their own posting or ceremony', () {
      expect(StructuralAction.values.where((a) => a.changesConfig).toSet(), {
        StructuralAction.ownershipRatio,
        StructuralAction.interestOnCapital,
        StructuralAction.ownerAddOrRemove,
        StructuralAction.fyStartChange,
        StructuralAction.quorumSetting,
      });
      // Distributing profit posts an entry (02 §7.1); re-opening a year is a
      // period_unlock (02 §8.1); removing a member and archiving are membership
      // and tenancy acts — none of them edits book_config.
      for (final a in [
        StructuralAction.profitDistribution,
        StructuralAction.yearReopen,
        StructuralAction.memberRemoval,
        StructuralAction.bookArchiveOrDelete,
      ]) {
        expect(a.changesConfig, isFalse);
      }
    });

    test('A-02-95 a period lock stays routine; unlocking a month of a closed year is structural (year re-open), an open year\'s is not', () {
      final fy25 = FinancialYear(2025);
      final fy26 = FinancialYear(2026);
      final lock = PeriodLock(
        id: 'lock',
        bookId: book,
        period: YearMonth(2026, 5),
        byUser: 'amrit',
        hlc: at(10),
      );
      final unlockOpenYear = PeriodUnlock(
        id: 'ul-open',
        bookId: book,
        period: YearMonth(2026, 5),
        byUser: 'amrit',
        reason: 'late arrivals',
        hlc: at(11),
      );
      final unlockClosedYear = PeriodUnlock(
        id: 'ul-closed',
        bookId: book,
        period: YearMonth(2025, 11),
        byUser: 'amrit',
        reason: 'prior-year fix',
        hlc: at(12),
      );
      final closed = [fy25];
      expect(structuralActionOf(lock, closedYears: closed), isNull);
      expect(structuralActionOf(unlockOpenYear, closedYears: closed), isNull);
      expect(
        structuralActionOf(unlockClosedYear, closedYears: closed),
        StructuralAction.yearReopen,
      );
      expect(
        structuralActionOf(unlockClosedYear, closedYears: const []),
        isNull,
      );
      // A non-default FY start is honoured when placing the month.
      final jan = FinancialYear(2025, startMonth: 1);
      expect(
        structuralActionOf(unlockClosedYear, closedYears: [jan]),
        StructuralAction.yearReopen,
      );
      expect(structuralActionOf(unlockOpenYear, closedYears: [jan]), isNull);
      expect(fy26.contains(unlockOpenYear.period.firstDay), isTrue);
    });
  });
}
