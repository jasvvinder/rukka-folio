// The two trust holes of TRUST200 at the data layer (lane F200I, review
// F200I-1; escalated 10 Oct 2026; repair round after review TRUST200 #1–#4).
//
//   * **Hole 1 — signer ≠ claimed approver.** The fold counted a
//     `structural_approval` by its payload's `by_user` alone, so one member's
//     phone could approve, veto or initiate "as" every owner and the ratio and
//     interest a distribution applies followed from that. The reader now takes
//     the certified device → user map (`signerOf`, injected — no I/O here,
//     asked by the envelope's signing identity `(author_device, author_seq)`
//     and never by the record's id or `by_user`) and hands it to
//     `evaluateStructural`, which binds every record (02 §7.2.1 🔒: *each
//     approval is authored on that owner's own device*). A record whose signer
//     it cannot name is nobody's: not counted, listed in `recordRefusals`, and
//     the reading says its signers are not all confirmed. `signerOf` has no
//     default — a caller writes the function, or `null` as its own assertion
//     that it bound each envelope itself (the Inbox).
//   * **Hole 2 — approvals bind to `request_id` only.** Requests were keyed by
//     payload id, last wins, so a second envelope reusing a request's id with
//     other terms could make a `business_setting` verify against terms the
//     owners never approved. A request id carried by more than one envelope is
//     now refused whole (`ambiguousRequest`), as the Inbox already does.
//
// A refused *record* is listed apart from `quarantined` (review TRUST200 #3):
// `quarantined` holds what bears on the terms in force — deed versions and
// `business_setting` records — because the one production consumer refuses
// every distribution while it is non-empty, and a stray forged, unattributable
// or duplicated record must not disable S14.1 for the book for good.
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

Account _partner(String id, String memberId, {int order = 0}) => Account(
  id: id,
  bookId: _book,
  name: '$id — Partner Current A/c',
  accountClass: AccountClass.partner,
  memberId: memberId,
  createdOrder: order,
);

List<Account> _chart() => [
  _partner('farm:amrit', 'amrit'),
  _partner('farm:sukhdev', 'sukhdev', order: 1),
  _partner('farm:harjit', 'harjit', order: 2),
];

const _thirds = {'farm:amrit': 1, 'farm:sukhdev': 1, 'farm:harjit': 1};
const _newRatio = {'farm:amrit': 2, 'farm:sukhdev': 1, 'farm:harjit': 1};
const _otherRatio = {'farm:amrit': 1, 'farm:sukhdev': 1, 'farm:harjit': 8};

BookConfig _deed() => const BookConfig(
  id: _book,
  tenantId: 't1',
  type: BookType.business,
  name: 'Kaur Farm',
  ownership: BookOwnership.shared,
  partnerShares: _thirds,
);

/// The certificates this reader holds. `d-mem` is a member's phone; `d-ghost`
/// has no certificate the reader can verify.
const _certs = {
  'd-amrit': 'amrit',
  'd-sukhdev': 'sukhdev',
  'd-harjit': 'harjit',
  'd-mem': 'gurpreet',
};
String? _signerOf(String? device, int? seq) => _certs[device];

StructuralRequest _request({
  required String id,
  required int day,
  required StructuralAction action,
  required Map<String, Object?> payload,
  String byUser = 'amrit',
  String? device = 'd-amrit',
  int seq = 1,
}) => StructuralRequest(
  id: id,
  bookId: _book,
  hlc: _at(day),
  action: action,
  byUser: byUser,
  ownerSetVersion: 1,
  payload: payload,
  authorDevice: device,
  authorSeq: seq,
);

StructuralApproval _approval(
  String id,
  String requestId,
  String byUser,
  int day, {
  required String? device,
  int seq = 1,
}) => StructuralApproval(
  id: id,
  bookId: _book,
  hlc: _at(day),
  requestId: requestId,
  byUser: byUser,
  ownerSetVersion: 1,
  authorDevice: device,
  authorSeq: seq,
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

StructuralReading _read({
  required List<StructuralEvent> events,
  required List<BusinessSetting> records,
  StructuralSignerOf? signerOf = _signerOf,
}) => readStructuralState(
  bookId: _book,
  configVersions: [
    BookConfigVersion(envelopeId: 'env-cfg-1', hlc: _at(1), config: _deed()),
  ],
  accounts: _chart(),
  structuralEvents: events,
  businessSettings: records,
  asOfMs: _day(30),
  signerOf: signerOf,
);

Iterable<String> _reasons(Iterable<StructuralQuarantine> list) =>
    list.map((q) => '${q.objectId}:${q.reason.name}');

void main() {
  group('E-03-87 the fold counts a record only when its signing device is '
      'certified to the user it names (02 §7.2.1 🔒; hole 1)', () {
    /// A ratio change approved by all three — except that harjit's approval
    /// was signed on sukhdev's phone.
    List<StructuralEvent> forged() => [
      _request(
        id: 'req-ratio',
        day: 10,
        action: StructuralAction.ownershipRatio,
        payload: const {'partner_shares': _newRatio},
      ),
      _approval('ap-1', 'req-ratio', 'amrit', 11, device: 'd-amrit'),
      _approval('ap-2', 'req-ratio', 'sukhdev', 12, device: 'd-sukhdev'),
      _approval('ap-3', 'req-ratio', 'harjit', 13, device: 'd-sukhdev'),
    ];
    final record = _record(
      id: 'bs-1',
      day: 14,
      requestId: 'req-ratio',
      settings: const {'partner_shares': _newRatio},
    );

    test('E-03-87 a forged approval does not authorise the business_setting: '
        'the record is quarantined requestNotApplied, the forgery is listed '
        'signerNotBound in recordRefusals, and the deed\'s ratio stays in '
        'force', () {
      // Pre-fix: applied, and partnerShares == _newRatio.
      final reading = _read(events: forged(), records: [record]);
      expect(reading.settings.applied, isEmpty);
      expect(_reasons(reading.quarantined), ['bs-1:requestNotApplied']);
      expect(reading.partnerShares, _thirds);
      expect(reading.signersConfirmed, isTrue);
      final forgery = reading.recordRefusals.where((q) => q.objectId == 'ap-3');
      expect(forgery.single.reason, StructuralQuarantineReason.signerNotBound);
      // No plaintext terms in a refusal (CLAUDE.md rule 4).
      expect(forgery.single.detail, isNot(contains('farm:')));
    });

    test('E-03-87 the same story with every approval on its owner\'s own '
        'phone applies — the binding refuses forgeries, not quorum', () {
      final honest = [
        ...forged().take(3),
        _approval('ap-3', 'req-ratio', 'harjit', 13, device: 'd-harjit'),
      ];
      final reading = _read(events: honest, records: [record]);
      expect(reading.quarantined, isEmpty);
      expect(reading.recordRefusals, isEmpty);
      expect(reading.settings.applied.single.id, 'bs-1');
      expect(reading.partnerShares, _newRatio);
      expect(reading.signersConfirmed, isTrue);
    });

    test('E-03-87 ownerSetVersions binds too: a quorum_setting to majority '
        'approved on the owners\' own phones is promoted; the same request '
        'with two approvals from a member\'s phone promotes no version — the '
        'rule stays all owners, and a member\'s phone cannot soften the '
        'quorum', () {
      OwnerSetReading fold(List<StructuralEvent> events) => ownerSetVersions(
        deed: _deed(),
        accounts: _chart(),
        structuralEvents: events,
        asOfMs: _day(30),
        signerOf: _signerOf,
      );
      final request = _request(
        id: 'req-q',
        day: 10,
        action: StructuralAction.quorumSetting,
        payload: const {structuralQuorumKey: 'majority'},
      );

      // The honest control first (review TRUST200 #4): under signerOf an
      // honestly signed quorum_setting IS promoted — so the refusal below is
      // the binding's doing, not a fold that promotes nothing.
      final promoted = fold([
        request,
        _approval('q-1', 'req-q', 'amrit', 11, device: 'd-amrit'),
        _approval('q-2', 'req-q', 'sukhdev', 12, device: 'd-sukhdev'),
        _approval('q-3', 'req-q', 'harjit', 13, device: 'd-harjit'),
      ]);
      expect(promoted.refused, isEmpty);
      expect(promoted.versions, hasLength(2));
      expect(promoted.inForce?.version, 2);
      expect(promoted.inForce?.quorum, StructuralQuorum.majority);
      expect(promoted.inForce?.required, 2);

      // Pre-fix: two versions, the second `majority`.
      final forged = fold([
        request,
        _approval('q-1', 'req-q', 'amrit', 11, device: 'd-amrit'),
        _approval('q-2', 'req-q', 'sukhdev', 12, device: 'd-mem'),
        _approval('q-3', 'req-q', 'harjit', 13, device: 'd-mem'),
      ]);
      expect(forged.versions, hasLength(1));
      expect(forged.inForce?.quorum, StructuralQuorum.allOwners);
      expect(forged.inForce?.required, 3);
    });

    test('E-03-87 a record whose signer this reader cannot name — no '
        'certificate — is nobody\'s: not counted, listed signerUnknown in '
        'recordRefusals, and the reading says its signers are not confirmed; '
        'nothing is applied', () {
      final events = [
        ...forged().take(3),
        _approval('ap-3', 'req-ratio', 'harjit', 13, device: 'd-ghost'),
      ];
      final reading = _read(events: events, records: [record]);
      expect(reading.signersConfirmed, isFalse);
      expect(reading.settings.applied, isEmpty);
      expect(reading.partnerShares, _thirds);
      expect(_reasons(reading.quarantined), ['bs-1:requestNotApplied']);
      final ghost = reading.recordRefusals.where((q) => q.objectId == 'ap-3');
      expect(ghost.single.reason, StructuralQuarantineReason.signerUnknown);
    });

    test('E-03-87 the initiation is bound as well: a request "by" an owner '
        'signed on a member\'s phone is refused and authorises nothing, '
        'however many real approvals follow', () {
      final events = [
        _request(
          id: 'req-ratio',
          day: 10,
          action: StructuralAction.ownershipRatio,
          payload: const {'partner_shares': _newRatio},
          device: 'd-mem',
        ),
        _approval('ap-1', 'req-ratio', 'amrit', 11, device: 'd-amrit'),
        _approval('ap-2', 'req-ratio', 'sukhdev', 12, device: 'd-sukhdev'),
        _approval('ap-3', 'req-ratio', 'harjit', 13, device: 'd-harjit'),
      ];
      final reading = _read(events: events, records: [record]);
      expect(reading.settings.applied, isEmpty);
      expect(reading.partnerShares, _thirds);
      expect(_reasons(reading.quarantined), ['bs-1:requestNotApplied']);
      expect(
        reading.recordRefusals
            .where((q) => q.objectId == 'req-ratio')
            .single
            .reason,
        StructuralQuarantineReason.signerNotBound,
      );
    });

    test('E-03-87 the signer is asked by signing identity, never by record '
        'id: a member\'s approval whose id and by_user copy an owner\'s, '
        'sorted before the owner\'s own, is refused on its own device while '
        'the owner\'s counts', () {
      // Review TRUST200 #1: a signer keyed by record id let the member's copy
      // take the owner's signer. The reader hands the engine (device, seq).
      final events = [
        ...forged().take(1),
        _approval('ap-1', 'req-ratio', 'amrit', 11, device: 'd-mem', seq: 4),
        _approval('ap-1', 'req-ratio', 'amrit', 12, device: 'd-amrit'),
        _approval('ap-2', 'req-ratio', 'sukhdev', 13, device: 'd-sukhdev'),
        _approval('ap-3', 'req-ratio', 'harjit', 14, device: 'd-harjit'),
      ];
      final reading = _read(events: events, records: [record]);
      expect(reading.settings.applied.single.id, 'bs-1');
      expect(reading.partnerShares, _newRatio);
      expect(reading.quarantined, isEmpty);
      expect(_reasons(reading.recordRefusals), ['ap-1:signerNotBound']);
      expect(reading.recordRefusals.single.detail, contains('device d-mem #4'));
    });

    test('E-03-87 a refused record does not quarantine the book: forged, '
        'unattributable or duplicated records with no business_setting '
        'naming their request leave quarantined empty, so a stray envelope '
        'from any member cannot disable distributions for good', () {
      // Review TRUST200 #3. The honest ratio change applies throughout.
      final honest = [
        ...forged().take(3),
        _approval('ap-3', 'req-ratio', 'harjit', 13, device: 'd-harjit'),
      ];
      final removal = _request(
        id: 'req-rm',
        day: 15,
        action: StructuralAction.memberRemoval,
        payload: const {'member_id': 'harjit'},
      );

      // (a) A forged approval of the removal, from a member's phone.
      final withForgery = _read(
        events: [
          ...honest,
          removal,
          _approval('rm-1', 'req-rm', 'amrit', 16, device: 'd-mem'),
        ],
        records: [record],
      );
      expect(withForgery.quarantined, isEmpty);
      expect(_reasons(withForgery.recordRefusals), ['rm-1:signerNotBound']);
      expect(withForgery.partnerShares, _newRatio);
      expect(withForgery.signersConfirmed, isTrue);

      // (b) A member envelope reusing the removal's request id, in the
      // member's own name — the probe of review #3. Pre-repair: quarantined
      // = [ambiguousRequest, ambiguousRequest] and S14.1 refused for good.
      final withDuplicate = _read(
        events: [
          ...honest,
          removal,
          _request(
            id: 'req-rm',
            day: 15,
            action: StructuralAction.memberRemoval,
            payload: const {'member_id': 'harjit'},
            byUser: 'gurpreet',
            device: 'd-mem',
            seq: 2,
          ),
        ],
        records: [record],
      );
      expect(withDuplicate.quarantined, isEmpty);
      expect(_reasons(withDuplicate.recordRefusals), [
        'req-rm:ambiguousRequest',
        'req-rm:ambiguousRequest',
      ]);
      expect(withDuplicate.partnerShares, _newRatio);
      expect(withDuplicate.signersConfirmed, isTrue);

      // (c) A record from a device nobody can name: listed, signers not
      // confirmed — the reading says so — but the terms in force stand.
      final withGhost = _read(
        events: [
          ...honest,
          removal,
          _approval('rm-1', 'req-rm', 'amrit', 16, device: 'd-ghost'),
        ],
        records: [record],
      );
      expect(withGhost.quarantined, isEmpty);
      expect(_reasons(withGhost.recordRefusals), ['rm-1:signerUnknown']);
      expect(withGhost.signersConfirmed, isFalse);
      expect(withGhost.partnerShares, _newRatio);

      // A business_setting that DOES name the duplicated id is still refused
      // on its own — that is what quarantined is for.
      final leaning = _read(
        events: [
          ...honest,
          removal,
          _request(
            id: 'req-rm',
            day: 15,
            action: StructuralAction.memberRemoval,
            payload: const {'member_id': 'harjit'},
            byUser: 'gurpreet',
            device: 'd-mem',
            seq: 2,
          ),
        ],
        records: [
          record,
          _record(
            id: 'bs-2',
            day: 17,
            requestId: 'req-rm',
            settings: const {'partner_shares': _otherRatio},
          ),
        ],
      );
      expect(_reasons(leaning.quarantined), ['bs-2:ambiguousRequest']);
      expect(leaning.partnerShares, _newRatio);
    });
  });

  group('E-03-88 a request id carried by more than one envelope is refused '
      'whole — approvals bind to request_id only (hole 2)', () {
    /// Two envelopes carry `req-ratio`: the one the owners approved, and a
    /// later one in the same id with other terms. The approvals name the id.
    List<StructuralEvent> twoCarriers({
      Map<String, int> second = _otherRatio,
    }) => [
      _request(
        id: 'req-ratio',
        day: 10,
        action: StructuralAction.ownershipRatio,
        payload: const {'partner_shares': _newRatio},
      ),
      _request(
        id: 'req-ratio',
        day: 10,
        action: StructuralAction.ownershipRatio,
        payload: {'partner_shares': second},
        device: 'd-harjit',
        byUser: 'harjit',
        seq: 7,
      ),
      _approval('ap-1', 'req-ratio', 'amrit', 11, device: 'd-amrit'),
      _approval('ap-2', 'req-ratio', 'sukhdev', 12, device: 'd-sukhdev'),
      _approval('ap-3', 'req-ratio', 'harjit', 13, device: 'd-harjit'),
    ];

    test('E-03-88 differing terms: a business_setting naming the id is '
        'quarantined ambiguousRequest even when its settings equal one '
        'carrier\'s payload, both carriers are listed in recordRefusals, and '
        'the deed stands', () {
      // Pre-fix: last wins — the second carrier's terms verified and applied.
      final smuggled = _record(
        id: 'bs-1',
        day: 14,
        requestId: 'req-ratio',
        settings: const {'partner_shares': _otherRatio},
      );
      final reading = _read(events: twoCarriers(), records: [smuggled]);
      expect(reading.settings.applied, isEmpty);
      expect(_reasons(reading.quarantined), ['bs-1:ambiguousRequest']);
      expect(reading.partnerShares, _thirds);
      expect(_reasons(reading.recordRefusals), [
        'req-ratio:ambiguousRequest',
        'req-ratio:ambiguousRequest',
      ]);

      // Nor does naming the first carrier's terms help: the id is ambiguous.
      final honest = _record(
        id: 'bs-2',
        day: 14,
        requestId: 'req-ratio',
        settings: const {'partner_shares': _newRatio},
      );
      final again = _read(events: twoCarriers(), records: [honest]);
      expect(again.settings.applied, isEmpty);
      expect(_reasons(again.quarantined), ['bs-2:ambiguousRequest']);
    });

    test('E-03-88 identical terms are refused all the same: 03 defines no '
        'amend of a structural_approval, and the Inbox refuses the pair, so '
        'the fold must not apply what the Inbox will not show', () {
      // Pre-fix: applied (the two carriers agreed, the second overwrote).
      final record = _record(
        id: 'bs-1',
        day: 14,
        requestId: 'req-ratio',
        settings: const {'partner_shares': _newRatio},
      );
      final reading = _read(
        events: twoCarriers(second: _newRatio),
        records: [record],
      );
      expect(reading.settings.applied, isEmpty);
      expect(_reasons(reading.quarantined), ['bs-1:ambiguousRequest']);
      expect(reading.partnerShares, _thirds);
    });

    test('E-03-88 ownerSetVersions refuses a duplicated quorum_setting id and '
        'promotes no version', () {
      // Pre-fix: last wins — `majority` promoted on the first carrier's
      // approvals.
      final reading = ownerSetVersions(
        deed: _deed(),
        accounts: _chart(),
        structuralEvents: [
          _request(
            id: 'req-q',
            day: 10,
            action: StructuralAction.quorumSetting,
            payload: const {structuralQuorumKey: 'majority'},
          ),
          _request(
            id: 'req-q',
            day: 10,
            action: StructuralAction.quorumSetting,
            payload: const {structuralQuorumKey: 'majority'},
            device: 'd-sukhdev',
            byUser: 'sukhdev',
            seq: 9,
          ),
          _approval('q-1', 'req-q', 'amrit', 11, device: 'd-amrit'),
          _approval('q-2', 'req-q', 'sukhdev', 12, device: 'd-sukhdev'),
          _approval('q-3', 'req-q', 'harjit', 13, device: 'd-harjit'),
        ],
        asOfMs: _day(30),
        signerOf: _signerOf,
      );
      expect(reading.versions, hasLength(1));
      expect(reading.inForce?.quorum, StructuralQuorum.allOwners);
      expect(
        reading.refused.single.reason,
        OwnerSetRefusalReason.ambiguousRequest,
      );
      expect(reading.refused.single.objectId, 'req-q');
    });

    test('E-03-88 one carrier per id is the ordinary case and still reads', () {
      final events = twoCarriers().skip(1).toList()
        ..insert(
          0,
          _request(
            id: 'req-ratio',
            day: 10,
            action: StructuralAction.ownershipRatio,
            payload: const {'partner_shares': _newRatio},
          ),
        )
        ..removeAt(1);
      final record = _record(
        id: 'bs-1',
        day: 14,
        requestId: 'req-ratio',
        settings: const {'partner_shares': _newRatio},
      );
      final reading = _read(events: events, records: [record]);
      expect(reading.quarantined, isEmpty);
      expect(reading.recordRefusals, isEmpty);
      expect(reading.settings.applied.single.id, 'bs-1');
      expect(reading.partnerShares, _newRatio);
    });
  });
}
