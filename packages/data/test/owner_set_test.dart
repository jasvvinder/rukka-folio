// The owner-set fold (ADR 2026-09-14b §3 and § Open bullet 4): who signs, how
// many must sign, and at which order point each version comes into force.
//
// The trap this suite exists for: every mistake here makes quorum *easier*.
// Drop an owner the fold cannot identify and `all owners` becomes a smaller
// number; apply a `quorum_setting` before quorum and a bare majority approves
// its own promotion to majority; count an approval by the very person being
// added and two owners become three. Each of those is a green ledger and a
// wrong one, so each has a test that also asserts the wrong answer is *not*
// produced.
//
// Synthetic data only (the Kaur farm of 02 §7.1); no real entry.
@Tags(['E'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:test/test.dart';

const _book = 'farm';

int _day(int n) => n * 86400000;

Hlc _at(int day, [int counter = 0]) =>
    Hlc.compose(physicalMs: _day(day), counter: counter);

/// A Partner Current A/c: the deed's key, and (through [Account.memberId]) the
/// only handle the chart gives from that key to a member who can sign.
Account _partner(
  String id,
  String? memberId, {
  int order = 0,
  String bookId = _book,
  AccountClass accountClass = AccountClass.partner,
}) => Account(
  id: id,
  bookId: bookId,
  name: '$id — Partner Current A/c',
  accountClass: accountClass,
  subtype: accountClass == AccountClass.money ? MoneySubtype.cash : null,
  memberId: memberId,
  createdOrder: order,
);

/// The farm's chart: three partner accounts, one member each.
List<Account> _chart() => [
  _partner('farm:amrit', 'amrit'),
  _partner('farm:sukhdev', 'sukhdev', order: 1),
  _partner('farm:harjit', 'harjit', order: 2),
];

BookConfig _deed({
  Map<String, int> shares = const {'farm:amrit': 1, 'farm:sukhdev': 1},
  StructuralQuorum? quorum,
  Map<String, Object?> extra = const {},
}) => BookConfig(
  id: _book,
  tenantId: 't1',
  type: BookType.business,
  name: 'Kaur Farm',
  ownership: BookOwnership.shared,
  partnerShares: shares,
  structuralQuorum: quorum,
  extra: extra,
);

StructuralRequest _request({
  required String id,
  required int day,
  required StructuralAction action,
  required Map<String, Object?> payload,
  int ownerSetVersion = 1,
  String byUser = 'amrit',
  String bookId = _book,
}) => StructuralRequest(
  id: id,
  bookId: bookId,
  hlc: _at(day),
  action: action,
  byUser: byUser,
  ownerSetVersion: ownerSetVersion,
  payload: payload,
);

StructuralApproval _approval(
  String id,
  String requestId,
  String byUser,
  int day, {
  int ownerSetVersion = 1,
  String bookId = _book,
}) => StructuralApproval(
  id: id,
  bookId: bookId,
  hlc: _at(day),
  requestId: requestId,
  byUser: byUser,
  ownerSetVersion: ownerSetVersion,
);

StructuralVeto _veto(String id, String requestId, String byUser, int day) =>
    StructuralVeto(
      id: id,
      bookId: _book,
      hlc: _at(day),
      requestId: requestId,
      byUser: byUser,
      ownerSetVersion: 1,
      reason: 'not agreed',
    );

BusinessSetting _record({
  required String id,
  required int day,
  required String requestId,
  required Map<String, Object?> settings,
}) => BusinessSetting(
  id: id,
  bookId: _book,
  hlc: _at(day),
  byUser: 'amrit',
  requestId: requestId,
  settings: settings,
);

/// The fold under test, with the farm's chart unless another is given.
OwnerSetReading _fold({
  BookConfig? deed,
  List<Account>? accounts,
  List<StructuralEvent> events = const [],
  int asOfDay = 200,
}) => ownerSetVersions(
  deed: deed ?? _deed(),
  accounts: accounts ?? _chart(),
  structuralEvents: events,
  asOfMs: _day(asOfDay),
);

const _twoOwners = {'farm:amrit': 1, 'farm:sukhdev': 1};
const _threeOwners = {'farm:amrit': 1, 'farm:sukhdev': 1, 'farm:harjit': 1};

void main() {
  group('E-03-37 version 1 is the founding owner set — the deed read through '
      'the chart (ADR 2026-09-14b §3, § Open bullet 4; 02 §7.1 🔒)', () {
    test('E-03-37 the memberId of every partner account the deed names, with '
        'the deed\'s quorum; absent means all owners', () {
      final reading = _fold(deed: _deed(shares: _threeOwners));
      expect(reading.refused, isEmpty);
      expect(reading.versions, hasLength(1));

      final v1 = reading.versions.single;
      expect(v1.version, 1);
      expect(v1.ownerIds, {'amrit', 'sukhdev', 'harjit'});
      expect(v1.quorum, StructuralQuorum.allOwners, reason: 'absent = default');
      expect(v1.required, 3, reason: 'all owners of three');
      expect(reading.inForce, same(v1));
    });

    test('E-03-37 the deed\'s recorded quorum is the version\'s rule, and a '
        'value this build cannot interpret reads as all owners — the '
        'strictest rule (03 §3.3.4 🔒)', () {
      expect(
        _fold(
          deed: _deed(shares: _threeOwners, quorum: StructuralQuorum.majority),
        ).versions.single.required,
        2,
        reason: '⌊3/2⌋ + 1',
      );

      // A newer build's value rides in `extra`; reading it as *majority*
      // would lower the bar on a rule this build cannot even name.
      final newer = _fold(
        deed: _deed(
          shares: _threeOwners,
          extra: const {structuralQuorumKey: 'two_thirds'},
        ),
      );
      expect(newer.versions.single.quorum, StructuralQuorum.allOwners);
      expect(newer.versions.single.required, 3);
    });

    test('E-03-37 the fold is a pure function of what it is handed: account '
        'order, duplicate instances and another book\'s chart change '
        'nothing', () {
      final ours = _chart();
      final shuffled = [
        _partner('other:amrit', 'amrit', bookId: 'other-book'),
        ours[2],
        ours[0],
        ours[1],
        // The same account seen twice, as two mirror rows would give it.
        _partner('farm:harjit', 'harjit', order: 2),
      ];
      final a = _fold(
        deed: _deed(shares: _threeOwners),
        accounts: ours,
      );
      final b = _fold(
        deed: _deed(shares: _threeOwners),
        accounts: shuffled,
      );
      expect(b.versions.single.ownerIds, a.versions.single.ownerIds);
      expect(b.refused, isEmpty);
    });
  });

  group('E-03-38 when the deed cannot name a signer the founding set is not '
      'derivable — and the fold says so rather than shrinking it', () {
    test('E-03-38 a partner account with no memberId: no versions, a typed '
        'refusal, and nothing can reach quorum', () {
      final chart = [
        _partner('farm:amrit', 'amrit'),
        _partner('farm:sukhdev', 'sukhdev', order: 1),
        // Seeded before the owner accepted their invite (02 §7.1: at creation
        // the owners are only *invited*), so the account names no member yet.
        _partner('farm:harjit', null, order: 2),
      ];
      final reading = _fold(
        deed: _deed(shares: _threeOwners),
        accounts: chart,
      );

      expect(reading.versions, isEmpty, reason: 'not derivable');
      expect(reading.inForce, isNull);
      final refusal = reading.refused.single;
      expect(refusal.reason, OwnerSetRefusalReason.ownerNotIdentified);
      expect(refusal.objectId, _book, reason: 'recorded against the deed');
      expect(refusal.detail, contains('farm:harjit'));

      // The whole point: with no versions, a request naming version 1 finds no
      // owner set and stays pending — nothing applies.
      final request = _request(
        id: 'req-ratio',
        day: 10,
        action: StructuralAction.ownershipRatio,
        payload: const {
          'partner_shares': {'farm:amrit': 2, 'farm:sukhdev': 1},
        },
      );
      final records = [
        _approval('ap-1', 'req-ratio', 'amrit', 11),
        _approval('ap-2', 'req-ratio', 'sukhdev', 12),
      ];
      final outcome = evaluateStructural(
        request: request,
        records: records,
        owners: reading.versions,
        asOfMs: _day(20),
      );
      expect(outcome.status, StructuralStatus.pending);
      expect(outcome.isApplied, isFalse);
      expect(outcome.threshold, isNull);

      // And the answer a shrinking fold would have produced: two owners, both
      // of whom signed — the same two approvals would have changed the ratio.
      final shrunk = evaluateStructural(
        request: request,
        records: records,
        owners: const [
          OwnerSetVersion(
            version: 1,
            ownerIds: {'amrit', 'sukhdev'},
            quorum: StructuralQuorum.allOwners,
          ),
        ],
        asOfMs: _day(20),
      );
      expect(shrunk.isApplied, isTrue, reason: 'the wrong answer, stated');
    });

    test('E-03-38 a deed key that is not a partner account of this book — '
        'absent, another class, another book — is refused by id', () {
      final chart = [
        _partner('farm:amrit', 'amrit'),
        _partner(
          'farm:sukhdev',
          'sukhdev',
          order: 1,
          accountClass: AccountClass.party,
        ),
        _partner('farm:harjit', 'harjit', order: 2, bookId: 'other-book'),
      ];
      final reading = _fold(
        deed: _deed(shares: _threeOwners),
        accounts: chart,
      );
      expect(reading.versions, isEmpty);
      expect(reading.refused.map((r) => r.reason).toSet(), {
        OwnerSetRefusalReason.notPartnerAccount,
      });
      // Every named id is accounted for; none is silently dropped.
      expect(reading.refused, hasLength(2));
      expect(
        reading.refused.map((r) => r.detail).join(' '),
        allOf(contains('farm:sukhdev'), contains('farm:harjit')),
      );
    });

    test('E-03-38 a deed with no ratio recorded names no owners at all — '
        'absent or empty is *not recorded*, never *equal* (02 §7.1 🔒)', () {
      final reading = _fold(deed: _deed(shares: const {}));
      expect(reading.versions, isEmpty);
      expect(
        reading.refused.single.reason,
        OwnerSetRefusalReason.sharesNotRecorded,
      );
    });
  });

  group('E-03-39 a later version is one approved owner_add_or_remove — and '
      'nothing is applied early (02 §7.2.1 🔒)', () {
    List<StructuralEvent> add({
      required String id,
      required int day,
      List<String> approvers = const ['amrit', 'sukhdev'],
    }) => [
      _request(
        id: id,
        day: day,
        action: StructuralAction.ownerAddOrRemove,
        payload: const {'partner_shares': _threeOwners},
      ),
      for (var i = 0; i < approvers.length; i++)
        _approval('$id-ap$i', id, approvers[i], day + 1 + i),
    ];

    test('E-03-39 approved by every owner: version 2 carries the new owner and '
        'the quorum rule in force', () {
      final reading = _fold(events: add(id: 'req-add', day: 10));
      expect(reading.refused, isEmpty);
      expect(reading.versions.map((v) => v.version), [1, 2]);
      expect(reading.versions[0].ownerIds, {'amrit', 'sukhdev'});

      final v2 = reading.versions[1];
      expect(v2.ownerIds, {'amrit', 'sukhdev', 'harjit'});
      expect(v2.quorum, StructuralQuorum.allOwners, reason: 'carried over');
      expect(v2.required, 3);
    });

    test('E-03-39 short of quorum, vetoed, or lapsed: the set never moves', () {
      // One approval of two required.
      expect(
        _fold(
          events: add(id: 'req-add', day: 10, approvers: ['amrit']),
        ).versions,
        hasLength(1),
      );

      // Vetoed before the second approval.
      expect(
        _fold(
          events: [
            ...add(id: 'req-add', day: 10, approvers: ['amrit']),
            _veto('veto-1', 'req-add', 'sukhdev', 12),
          ],
        ).versions,
        hasLength(1),
      );

      // Lapsed: 14 days without quorum (02 §7.2.1), judged against the
      // injected time and never a clock read.
      final late = _fold(
        events: add(id: 'req-add', day: 10, approvers: ['amrit']),
        asOfDay: 40,
      );
      expect(late.versions, hasLength(1));
      // The approval that arrives after the window is ignored by the engine,
      // so it cannot revive the version either.
      final afterDeadline = _fold(
        events: [
          ...add(id: 'req-add', day: 10, approvers: ['amrit']),
          _approval('ap-late', 'req-add', 'sukhdev', 30),
        ],
        asOfDay: 40,
      );
      expect(afterDeadline.versions, hasLength(1));
    });

    test('E-03-39 only the two actions that change the set or the rule bump a '
        'version — an approved ratio change or profit distribution does '
        'not (ADR 2026-09-14b §3)', () {
      final events = <StructuralEvent>[];
      var day = 10;
      for (final action in [
        StructuralAction.ownershipRatio,
        StructuralAction.profitDistribution,
        StructuralAction.interestOnCapital,
        StructuralAction.memberRemoval,
        StructuralAction.yearReopen,
        StructuralAction.bookArchiveOrDelete,
      ]) {
        final id = 'req-${action.wire}';
        events
          ..add(
            _request(
              id: id,
              day: day,
              action: action,
              // Payloads that *would* move the set, if this action could.
              payload: const {'partner_shares': _threeOwners},
            ),
          )
          ..add(_approval('$id-a', id, 'amrit', day + 1))
          ..add(_approval('$id-b', id, 'sukhdev', day + 2));
        day += 20;
      }
      final reading = _fold(events: events, asOfDay: 200);
      expect(reading.versions, hasLength(1));
      expect(reading.refused, isEmpty);
    });
  });

  group('E-03-40 a later version is one approved quorum_setting — the rule '
      'changes, the owners do not (02 §7.2.1 🔒)', () {
    test('E-03-40 approved by all owners: version 2 keeps the set and takes '
        'the new rule', () {
      final reading = _fold(
        deed: _deed(shares: _threeOwners),
        events: [
          _request(
            id: 'req-q',
            day: 10,
            action: StructuralAction.quorumSetting,
            payload: const {structuralQuorumKey: 'majority'},
          ),
          _approval('q1', 'req-q', 'amrit', 11),
          _approval('q2', 'req-q', 'sukhdev', 12),
          _approval('q3', 'req-q', 'harjit', 13),
        ],
      );
      expect(reading.versions.map((v) => v.version), [1, 2]);
      final v2 = reading.versions[1];
      expect(v2.ownerIds, {'amrit', 'sukhdev', 'harjit'});
      expect(v2.quorum, StructuralQuorum.majority);
      expect(v2.required, 2);
    });

    test('E-03-40 a payload that records no rule bumps nothing; a value this '
        'build cannot interpret lands as all owners, never as the looser '
        'rule it replaces', () {
      List<StructuralEvent> quorumChange(Map<String, Object?> payload) => [
        _request(
          id: 'req-q',
          day: 10,
          action: StructuralAction.quorumSetting,
          payload: payload,
        ),
        _approval('q1', 'req-q', 'amrit', 11),
        _approval('q2', 'req-q', 'sukhdev', 12),
      ];

      final empty = _fold(events: quorumChange(const {}));
      expect(empty.versions, hasLength(1));
      expect(
        empty.refused.single.reason,
        OwnerSetRefusalReason.quorumNotRecorded,
      );
      expect(empty.refused.single.objectId, 'req-q');

      final unknown = _fold(
        deed: _deed(quorum: StructuralQuorum.majority),
        events: quorumChange(const {structuralQuorumKey: 'two_thirds'}),
      );
      expect(unknown.versions, hasLength(2));
      expect(unknown.versions[0].quorum, StructuralQuorum.majority);
      expect(unknown.versions[1].quorum, StructuralQuorum.allOwners);
      expect(unknown.versions[1].required, 2, reason: 'all of two');
    });
  });

  group('E-03-41 an owner_add_or_remove the fold cannot trust bumps nothing, '
      'and is refused by reason — never silently skipped', () {
    OwnerSetReading refuseOn(Map<String, Object?> payload) => _fold(
      accounts: [
        ..._chart(),
        // A second partner account opened in Amrit's name.
        _partner('farm:amrit-2', 'amrit', order: 3),
        _partner(
          'farm:tools',
          null,
          order: 4,
          accountClass: AccountClass.money,
        ),
      ],
      events: [
        _request(
          id: 'req-own',
          day: 10,
          action: StructuralAction.ownerAddOrRemove,
          payload: payload,
        ),
        _approval('o1', 'req-own', 'amrit', 11),
        _approval('o2', 'req-own', 'sukhdev', 12),
      ],
    );

    test('E-03-41 an account that is not a partner account of this book', () {
      final reading = refuseOn(const {
        'partner_shares': {'farm:amrit': 1, 'farm:tools': 1},
      });
      expect(reading.versions, hasLength(1));
      final refusal = reading.refused.single;
      expect(refusal.reason, OwnerSetRefusalReason.notPartnerAccount);
      expect(refusal.objectId, 'req-own');
      expect(refusal.detail, contains('farm:tools'));
    });

    test('E-03-41 an account whose owner the chart cannot name', () {
      final reading = _fold(
        accounts: [..._chart(), _partner('farm:new', null, order: 3)],
        events: [
          _request(
            id: 'req-own',
            day: 10,
            action: StructuralAction.ownerAddOrRemove,
            payload: const {
              'partner_shares': {
                'farm:amrit': 1,
                'farm:sukhdev': 1,
                'farm:new': 1,
              },
            },
          ),
          _approval('o1', 'req-own', 'amrit', 11),
          _approval('o2', 'req-own', 'sukhdev', 12),
        ],
      );
      expect(reading.versions, hasLength(1));
      expect(
        reading.refused.single.reason,
        OwnerSetRefusalReason.ownerNotIdentified,
      );
    });

    test('E-03-41 a second account for an owner already in the set — one '
        'Partner Current A/c per owner (02 §7.1 🔒)', () {
      final reading = refuseOn(const {
        'partner_shares': {
          'farm:amrit': 1,
          'farm:sukhdev': 1,
          'farm:amrit-2': 1,
        },
      });
      expect(reading.versions, hasLength(1));
      final refusal = reading.refused.single;
      expect(refusal.reason, OwnerSetRefusalReason.ownerAlreadyPresent);
      expect(refusal.detail, contains('amrit'));
    });

    test('E-03-41 a removal that would leave zero owners, and a ratio this '
        'build cannot read', () {
      final none = refuseOn(const {'partner_shares': <String, Object?>{}});
      expect(none.versions, hasLength(1));
      expect(none.refused.single.reason, OwnerSetRefusalReason.noOwnersLeft);

      for (final raw in <Object?>[
        null,
        'everyone',
        <String, Object?>{'farm:amrit': 0.5},
        <String, Object?>{'farm:amrit': -1},
      ]) {
        final reading = refuseOn({'partner_shares': raw});
        expect(reading.versions, hasLength(1), reason: 'raw: $raw');
        expect(
          reading.refused.single.reason,
          OwnerSetRefusalReason.sharesNotRecorded,
          reason: 'raw: $raw',
        );
      }
    });
  });

  group('E-03-42 a version comes into force at the order point quorum was '
      'reached, and a request counts under the set in force at its own '
      '(ADR 2026-09-06 §3, K1\'s precedent)', () {
    /// Add Harjit: initiated day 5, quorum reached day 7.
    List<StructuralEvent> addHarjit() => [
      _request(
        id: 'req-add',
        day: 5,
        action: StructuralAction.ownerAddOrRemove,
        payload: const {'partner_shares': _threeOwners},
      ),
      _approval('add-1', 'req-add', 'amrit', 6),
      _approval('add-2', 'req-add', 'sukhdev', 7),
    ];

    test('E-03-42 a request initiated between the initiation and the quorum '
        'of an owner change still counts under the old set — nothing is '
        'applied early', () {
      final versions = _fold(events: addHarjit()).versions;
      expect(versions, hasLength(2));

      // Initiated day 6: after the add was proposed, before it was approved.
      final early = _request(
        id: 'req-early',
        day: 6,
        action: StructuralAction.ownershipRatio,
        payload: const {
          'partner_shares': {'farm:amrit': 2, 'farm:sukhdev': 1},
        },
      );
      final approvals = [
        _approval('e1', 'req-early', 'amrit', 8),
        _approval('e2', 'req-early', 'sukhdev', 9),
      ];
      final outcome = evaluateStructural(
        request: early,
        records: approvals,
        owners: versions,
        asOfMs: _day(20),
      );
      expect(outcome.threshold, 2, reason: 'the two owners of version 1');
      expect(outcome.isApplied, isTrue);

      // Had it named the version the add created, that version did not exist
      // at its order point and the engine applies nothing.
      final premature = evaluateStructural(
        request: early.copyWith(id: 'req-early-2', ownerSetVersion: 3),
        records: approvals,
        owners: versions,
        asOfMs: _day(20),
      );
      expect(premature.status, StructuralStatus.pending);
    });

    test('E-03-42 a re-versioned owner set neither resets the count nor '
        'raises the bar: the threshold is the earliest version among the '
        'request and the approvals that counted', () {
      final versions = _fold(events: addHarjit()).versions;
      final stale = _request(
        id: 'req-stale',
        day: 10,
        action: StructuralAction.ownershipRatio,
        payload: const {
          'partner_shares': {'farm:amrit': 2, 'farm:sukhdev': 1},
        },
      );
      final outcome = evaluateStructural(
        request: stale,
        records: [
          _approval('s1', 'req-stale', 'amrit', 11),
          _approval('s2', 'req-stale', 'sukhdev', 12),
        ],
        owners: versions,
        asOfMs: _day(20),
      );
      expect(outcome.threshold, 2, reason: 'version 1, the earliest named');
      expect(outcome.isApplied, isTrue);

      // A request authored under the new set needs all three.
      final fresh = evaluateStructural(
        request: stale.copyWith(id: 'req-fresh', ownerSetVersion: 2),
        records: [
          _approval('f1', 'req-fresh', 'amrit', 11, ownerSetVersion: 2),
          _approval('f2', 'req-fresh', 'sukhdev', 12, ownerSetVersion: 2),
        ],
        owners: versions,
        asOfMs: _day(20),
      );
      expect(fresh.threshold, 3);
      expect(fresh.status, StructuralStatus.pending);
    });

    test('E-03-42 versions are numbered by the order point quorum was '
        'reached, not by the order the requests were initiated — and the '
        'later version carries the earlier one\'s change', () {
      // Initiated first, approved last: the add sits pending for 29 days
      // while a quorum change is proposed and approved inside its window.
      final reading = _fold(
        events: [
          _request(
            id: 'req-add',
            day: 1,
            action: StructuralAction.ownerAddOrRemove,
            payload: const {'partner_shares': _threeOwners},
          ),
          _approval('add-1', 'req-add', 'amrit', 2),
          _request(
            id: 'req-q',
            day: 3,
            action: StructuralAction.quorumSetting,
            payload: const {structuralQuorumKey: 'majority'},
          ),
          _approval('q1', 'req-q', 'amrit', 3),
          _approval('q2', 'req-q', 'sukhdev', 4),
          // The add's second approval, inside its 14-day window.
          _approval('add-2', 'req-add', 'sukhdev', 10),
        ],
        asOfDay: 60,
      );

      expect(reading.versions.map((v) => v.version), [1, 2, 3]);
      expect(reading.versions[1].quorum, StructuralQuorum.majority);
      expect(reading.versions[1].ownerIds, {'amrit', 'sukhdev'});
      // Version 3 is the add, folded onto the rule in force when it landed —
      // deriving it from the set it was *evaluated* against would have
      // silently reverted the quorum rule to the deed's.
      expect(reading.versions[2].ownerIds, {'amrit', 'sukhdev', 'harjit'});
      expect(reading.versions[2].quorum, StructuralQuorum.majority);
      expect(reading.versions[2].required, 2);
    });

    test('E-03-42 input order changes nothing — the same envelopes in any '
        'order fold to the same versions', () {
      final events = [
        ...addHarjit(),
        _request(
          id: 'req-q',
          day: 20,
          action: StructuralAction.quorumSetting,
          payload: const {structuralQuorumKey: 'majority'},
          ownerSetVersion: 2,
        ),
        _approval('q1', 'req-q', 'amrit', 21, ownerSetVersion: 2),
        _approval('q2', 'req-q', 'sukhdev', 22, ownerSetVersion: 2),
        _approval('q3', 'req-q', 'harjit', 23, ownerSetVersion: 2),
      ];
      String shape(OwnerSetReading r) => r.versions
          .map(
            (v) =>
                '${v.version}:${(v.ownerIds.toList()..sort()).join(",")}'
                ':${v.quorum.wire}',
          )
          .join(' | ');

      final forwards = _fold(events: events, asOfDay: 60);
      final backwards = _fold(events: events.reversed.toList(), asOfDay: 60);
      expect(shape(backwards), shape(forwards));
      expect(
        shape(forwards),
        '1:amrit,sukhdev:all_owners | '
        '2:amrit,harjit,sukhdev:all_owners | '
        '3:amrit,harjit,sukhdev:majority',
      );
    });
  });

  group('E-03-43 the owner being added does not vote themselves in', () {
    test('E-03-43 an approval by the member the request would add is not an '
        'owner\'s approval: ignored as notOwner, the request stays short of '
        'quorum, and no version is bumped', () {
      final events = [
        _request(
          id: 'req-add',
          day: 10,
          action: StructuralAction.ownerAddOrRemove,
          payload: const {'partner_shares': _threeOwners},
        ),
        // Harjit signs first — he is the one being added.
        _approval('ap-h', 'req-add', 'harjit', 11),
        _approval('ap-a', 'req-add', 'amrit', 12),
      ];
      final reading = _fold(events: events);
      expect(reading.versions, hasLength(1), reason: 'still two owners');
      expect(reading.refused, isEmpty, reason: 'pending, not refused');

      final outcome = evaluateStructural(
        request: events.first as StructuralRequest,
        records: events,
        owners: reading.versions,
        asOfMs: _day(20),
      );
      expect(outcome.status, StructuralStatus.pending);
      expect(outcome.approvedBy, ['amrit']);
      expect(outcome.threshold, 2);
      expect(
        outcome.ignored
            .where((i) => i.reason == StructuralIgnoreReason.notOwner)
            .map((i) => i.recordId),
        ['ap-h'],
      );

      // Sukhdev's approval is the one that carries it.
      final withSukhdev = _fold(
        events: [...events, _approval('ap-s', 'req-add', 'sukhdev', 13)],
      );
      expect(withSukhdev.versions, hasLength(2));
      expect(withSukhdev.versions[1].ownerIds, contains('harjit'));
    });
  });

  group('E-03-44 a quorum rule cannot lower itself', () {
    test('E-03-44 quorum_setting to majority signed by a bare majority under '
        'all owners is short of quorum: pending, not applied, and the next '
        'request still needs every owner', () {
      final events = [
        _request(
          id: 'req-q',
          day: 10,
          action: StructuralAction.quorumSetting,
          payload: const {structuralQuorumKey: 'majority'},
        ),
        _approval('q1', 'req-q', 'amrit', 11),
        _approval('q2', 'req-q', 'sukhdev', 12),
      ];
      final reading = _fold(
        deed: _deed(shares: _threeOwners),
        events: events,
      );

      expect(reading.versions, hasLength(1));
      expect(reading.inForce!.quorum, StructuralQuorum.allOwners);
      expect(reading.inForce!.required, 3);
      expect(reading.refused, isEmpty, reason: 'pending, not refused');

      final outcome = evaluateStructural(
        request: events.first as StructuralRequest,
        records: events,
        owners: reading.versions,
        asOfMs: _day(20),
      );
      expect(outcome.status, StructuralStatus.pending);
      expect(
        outcome.threshold,
        3,
        reason:
            'the rule it would change, not the '
            'rule it proposes',
      );

      // A record claiming the change is unauthorised: nothing is applied early.
      final verified = verifyBusinessSettings(
        bookId: _book,
        records: [
          _record(
            id: 'bs-q',
            day: 13,
            requestId: 'req-q',
            settings: const {structuralQuorumKey: 'majority'},
          ),
        ],
        structuralEvents: events,
        owners: reading.versions,
        asOfMs: _day(20),
      );
      expect(verified.applied, isEmpty);
      expect(
        verified.quarantined.single.reason,
        StructuralQuarantineReason.requestNotApplied,
      );

      // And a later ratio change still needs all three.
      final later = evaluateStructural(
        request: _request(
          id: 'req-ratio',
          day: 14,
          action: StructuralAction.ownershipRatio,
          payload: const {'partner_shares': _threeOwners},
        ),
        records: [
          _approval('r1', 'req-ratio', 'amrit', 15),
          _approval('r2', 'req-ratio', 'sukhdev', 16),
        ],
        owners: reading.versions,
        asOfMs: _day(20),
      );
      expect(later.threshold, 3);
      expect(later.isApplied, isFalse);
    });
  });

  group('E-03-45 the whole story through one entry point: deed → owner set '
      'versions → verified records → the terms in force', () {
    const ratio2 = {'farm:amrit': 2, 'farm:sukhdev': 1};
    const ratio3 = {'farm:amrit': 3, 'farm:sukhdev': 2, 'farm:harjit': 1};

    List<StructuralEvent> story() => [
      // 1. Two owners agree a 2:1 ratio — all owners, so both must sign.
      _request(
        id: 'req-ratio-1',
        day: 10,
        action: StructuralAction.ownershipRatio,
        payload: const {'partner_shares': ratio2},
      ),
      _approval('a1', 'req-ratio-1', 'amrit', 11),
      _approval('a2', 'req-ratio-1', 'sukhdev', 12),
      // 2. Harjit is added — again both current owners.
      _request(
        id: 'req-add',
        day: 20,
        action: StructuralAction.ownerAddOrRemove,
        payload: const {'partner_shares': _threeOwners},
      ),
      _approval('b1', 'req-add', 'amrit', 21),
      _approval('b2', 'req-add', 'sukhdev', 22),
      // 3. The rule is changed to majority — under version 2, all three.
      _request(
        id: 'req-q',
        day: 30,
        action: StructuralAction.quorumSetting,
        payload: const {structuralQuorumKey: 'majority'},
        ownerSetVersion: 2,
      ),
      _approval('c1', 'req-q', 'amrit', 31, ownerSetVersion: 2),
      _approval('c2', 'req-q', 'sukhdev', 32, ownerSetVersion: 2),
      _approval('c3', 'req-q', 'harjit', 33, ownerSetVersion: 2),
      // 4. A ratio change signed by two of three — a quorum under majority.
      _request(
        id: 'req-ratio-2',
        day: 40,
        action: StructuralAction.ownershipRatio,
        payload: const {'partner_shares': ratio3},
        ownerSetVersion: 3,
      ),
      _approval('d1', 'req-ratio-2', 'amrit', 41, ownerSetVersion: 3),
      _approval('d2', 'req-ratio-2', 'harjit', 42, ownerSetVersion: 3),
    ];

    List<BusinessSetting> records() => [
      _record(
        id: 'bs-1',
        day: 13,
        requestId: 'req-ratio-1',
        settings: const {'partner_shares': ratio2},
      ),
      _record(
        id: 'bs-2',
        day: 23,
        requestId: 'req-add',
        settings: const {'partner_shares': _threeOwners},
      ),
      _record(
        id: 'bs-3',
        day: 34,
        requestId: 'req-q',
        settings: const {structuralQuorumKey: 'majority'},
      ),
      _record(
        id: 'bs-4',
        day: 43,
        requestId: 'req-ratio-2',
        settings: const {'partner_shares': ratio3},
      ),
    ];

    StructuralReading read() => readStructuralState(
      bookId: _book,
      configVersions: [
        BookConfigVersion(
          envelopeId: 'env-cfg-1',
          hlc: _at(1),
          config: _deed(),
        ),
      ],
      accounts: _chart(),
      structuralEvents: story(),
      businessSettings: records(),
      asOfMs: _day(50),
    );

    test('E-03-45 founding two, a ratio by both, a third owner, then majority '
        '— and every record lands', () {
      final reading = read();
      expect(reading.quarantined, isEmpty);
      expect(reading.ownerRefusals, isEmpty);
      expect(reading.settings.applied.map((r) => r.id), [
        'bs-1',
        'bs-2',
        'bs-3',
        'bs-4',
      ]);

      expect(reading.owners.versions.map((v) => v.version), [1, 2, 3]);
      expect(reading.owners.versions[0].ownerIds, {'amrit', 'sukhdev'});
      expect(reading.owners.versions[1].ownerIds, {
        'amrit',
        'sukhdev',
        'harjit',
      });
      expect(reading.owners.versions[1].quorum, StructuralQuorum.allOwners);
      expect(reading.owners.versions[2].quorum, StructuralQuorum.majority);
      expect(reading.owners.inForce!.required, 2);

      // The terms the distribution wizard reads (ADR 2026-09-14b §6).
      expect(reading.partnerShares, ratio3);
      expect(reading.quorum, StructuralQuorum.majority);
      expect(reading.deed!.partnerShares, _twoOwners, reason: 'frozen');
    });

    test('E-03-45 the last ratio change counted only because the rule had '
        'been changed: under the deed\'s all owners the same two signatures '
        'are short of quorum and the record is quarantined', () {
      final reading = read();
      final asMajority = reading.owners.versions;
      // The same three versions, but version 3 never took the new rule.
      final asAllOwners = [
        asMajority[0],
        asMajority[1],
        OwnerSetVersion(
          version: 3,
          ownerIds: asMajority[2].ownerIds,
          quorum: StructuralQuorum.allOwners,
        ),
      ];
      final request = story().whereType<StructuralRequest>().firstWhere(
        (r) => r.id == 'req-ratio-2',
      );

      expect(
        evaluateStructural(
          request: request,
          records: story(),
          owners: asMajority,
          asOfMs: _day(50),
        ).isApplied,
        isTrue,
      );
      final under = evaluateStructural(
        request: request,
        records: story(),
        owners: asAllOwners,
        asOfMs: _day(50),
      );
      expect(under.status, StructuralStatus.pending);
      expect(under.threshold, 3);
      expect(under.approvedBy, ['amrit', 'harjit']);

      final verified = verifyBusinessSettings(
        bookId: _book,
        records: records(),
        structuralEvents: story(),
        owners: asAllOwners,
        asOfMs: _day(50),
      );
      expect(verified.applied.map((r) => r.id), ['bs-1', 'bs-2', 'bs-3']);
      expect(verified.quarantined.single.objectId, 'bs-4');
      expect(
        verified.quarantined.single.reason,
        StructuralQuarantineReason.requestNotApplied,
      );
      expect(
        partnerSharesInForce(
          structuralSettingsInForce(deed: _deed(), applied: verified.applied),
        ),
        _threeOwners,
        reason: 'the ratio before the unauthorised change',
      );
    });

    test('E-03-45 with no config versions there is no deed, no owner set and '
        'no terms — and nothing throws', () {
      final empty = readStructuralState(
        bookId: _book,
        configVersions: const [],
        accounts: _chart(),
        structuralEvents: story(),
        businessSettings: records(),
        asOfMs: _day(50),
      );
      expect(empty.deed, isNull);
      expect(empty.owners.versions, isEmpty);
      expect(empty.settings.applied, isEmpty);
      expect(empty.inForce, isEmpty);
      expect(empty.partnerShares, isEmpty);
      expect(empty.quorum, StructuralQuorum.allOwners);
    });

    test('E-03-45 a config version of another book is a caller error, not a '
        'quiet reading', () {
      expect(
        () => readStructuralState(
          bookId: 'other-book',
          configVersions: [
            BookConfigVersion(
              envelopeId: 'env-cfg-1',
              hlc: _at(1),
              config: _deed(),
            ),
          ],
          accounts: _chart(),
          structuralEvents: const [],
          businessSettings: const [],
          asOfMs: _day(50),
        ),
        throwsArgumentError,
      );
    });
  });
}
