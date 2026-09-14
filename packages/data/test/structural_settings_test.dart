// Structural settings in two layers (ADR 2026-09-14b §2–§5): the deed in the
// `book_config` envelope — `partner_shares`, `structural_quorum` — and every
// change as a dated `business_setting` record naming its approved request; the
// terms in force are the fold of the two. The ledger is append-only, so as with
// the other config fields (E-03-30, E-03-31) the questions are what an older
// or newer build's bytes do here: absent, present, or present and not
// understood — and 03 §3.3.4 🔒 says the last comes back out unchanged.
// Synthetic data only (the Kaur farm of 02 §7.1); no real entry.
@Tags(['E'])
library;

import 'dart:convert';

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:test/test.dart';

const _thirds = {'farm:amrit': 1, 'farm:sukhdev': 1, 'farm:harjit': 1};

BookConfig _deed({
  StructuralQuorum? quorum,
  Map<String, int> shares = _thirds,
  Map<String, Object?> extra = const {},
}) => BookConfig(
  id: 'farm',
  tenantId: 't1',
  type: BookType.business,
  name: 'Kaur Farm',
  ownership: BookOwnership.shared,
  partnerShares: shares,
  structuralQuorum: quorum,
  extra: extra,
);

/// Through JSON text, the way a blob travels.
Map<String, Object?> _wire(Map<String, Object?> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, Object?>;

int _day(int n) => n * 86400000;

BusinessSetting _record({
  required String id,
  required int day,
  required Map<String, Object?> settings,
  String bookId = 'farm',
  String? requestId = 'req-1',
}) => BusinessSetting(
  id: id,
  bookId: bookId,
  hlc: Hlc.compose(physicalMs: _day(day), counter: 0),
  byUser: 'harjit',
  requestId: requestId,
  settings: settings,
);

void main() {
  group('E-03-32 book_config.structural_quorum — the deed (ADR 2026-09-14b §3)', () {
    test('E-03-32 absent means the default, all owners: nothing recorded, no '
        'key written, and the engine agrees', () {
      final deed = _deed();
      expect(deed.structuralQuorum, isNull);
      expect(deed.toJson().containsKey(structuralQuorumKey), isFalse);
      expect(structuralQuorumOf(deed.toJson()), StructuralQuorum.allOwners);
      expect(isStructuralQuorumKnown(deed.toJson()), isTrue);

      // A book written before the field existed reads the same way.
      final older = BookConfig.fromJson({
        'id': 'farm',
        'tenant_id': 't1',
        'type': 'business',
        'name': 'Kaur Farm',
        'ownership': 'shared',
      });
      expect(older.structuralQuorum, isNull);
      expect(older.toJson().containsKey(structuralQuorumKey), isFalse);
    });

    test('E-03-32 a recorded choice round-trips on the engine\'s wire key and '
        'value, and the engine reads the same value off the wire', () {
      // The wire key and values are the engine's (02 §7.2.1), fixed: renaming
      // the Dart identifiers must never move a book's quorum rule.
      expect(structuralQuorumKey, 'structural_quorum');
      expect(StructuralQuorum.allOwners.wire, 'all_owners');
      expect(StructuralQuorum.majority.wire, 'majority');

      for (final q in StructuralQuorum.values) {
        final deed = _deed(quorum: q);
        final wire = _wire(deed.toJson());
        expect(wire[structuralQuorumKey], q.wire);
        final back = BookConfig.fromJson(wire);
        expect(back.structuralQuorum, q);
        expect(structuralQuorumOf(wire), q, reason: 'engine and codec agree');
        expect(back.extra.containsKey(structuralQuorumKey), isFalse);
      }
    });

    test('E-03-32 a value this build cannot interpret is read as all owners — '
        'the strictest rule — kept in extra, written back verbatim once, and '
        'never guessed at (03 §3.3.4 🔒)', () {
      for (final raw in <Object?>[
        'two_thirds',
        3,
        {'k': 2, 'of': 3},
        true,
      ]) {
        final deed = BookConfig.fromJson({
          'id': 'farm',
          'tenant_id': 't1',
          'type': 'business',
          'name': 'Kaur Farm',
          'ownership': 'shared',
          structuralQuorumKey: raw,
        });
        expect(deed.structuralQuorum, isNull, reason: 'not understood: $raw');
        expect(deed.extra[structuralQuorumKey], raw);

        final wire = deed.toJson();
        expect(wire[structuralQuorumKey], raw, reason: 'written back');
        expect(
          wire.keys.where((k) => k == structuralQuorumKey).length,
          1,
          reason: 'the codec must not also write a default under the key',
        );
        // The engine's conservative read: unknown → all owners, flagged.
        expect(structuralQuorumOf(wire), StructuralQuorum.allOwners);
        expect(isStructuralQuorumKnown(wire), isFalse);
      }
    });

    test('E-03-32 the new field disturbs no other field, known or unknown '
        '(03 §3.3.4 🔒)', () {
      final deed = BookConfig.fromJson({
        'id': 'farm',
        'tenant_id': 't1',
        'type': 'business',
        'name': 'Kaur Farm',
        'ownership': 'shared',
        'partner_shares': {'farm:amrit': 2, 'farm:sukhdev': 1},
        structuralQuorumKey: 'majority',
        'future_field': {'x': 1},
      });
      expect(deed.partnerShares, {'farm:amrit': 2, 'farm:sukhdev': 1});
      expect(deed.structuralQuorum, StructuralQuorum.majority);
      expect(deed.extra.keys, ['future_field']);
      final wire = deed.toJson();
      expect(wire['partner_shares'], {'farm:amrit': 2, 'farm:sukhdev': 1});
      expect(wire[structuralQuorumKey], 'majority');
      expect(wire['future_field'], {'x': 1});
    });
  });

  group('E-03-33 the business_setting record (ADR 2026-09-14b §5)', () {
    test('E-03-33 every field round-trips through JSON; request_id is optional '
        'at the codec and never judged here', () {
      final record = _record(
        id: 'bs-1',
        day: 20,
        settings: const {
          'partner_shares': {
            'farm:amrit': 40,
            'farm:sukhdev': 30,
            'farm:harjit': 30,
          },
        },
      );
      final wire = _wire(record.toJson());
      expect(wire, {
        'id': 'bs-1',
        'book_id': 'farm',
        'hlc': Hlc.compose(physicalMs: _day(20), counter: 0).raw,
        'by_user': 'harjit',
        'request_id': 'req-1',
        'settings': {
          'partner_shares': {
            'farm:amrit': 40,
            'farm:sukhdev': 30,
            'farm:harjit': 30,
          },
        },
      });
      final back = BusinessSetting.fromJson(wire);
      expect(back.id, 'bs-1');
      expect(back.bookId, 'farm');
      expect(back.hlc, record.hlc);
      expect(back.byUser, 'harjit');
      expect(back.requestId, 'req-1');
      expect(back.settings, record.settings);
      expect(back.extra, isEmpty);
      // The settings map is the engine's: the same codec reads it.
      expect(partnerSharesInForce(back.settings), {
        'farm:amrit': 40,
        'farm:sukhdev': 30,
        'farm:harjit': 30,
      });

      // No request named: decoded, not refused — the verifier refuses it
      // (E-03-36 @M7). The key is then not written at all.
      final orphan = BusinessSetting.fromJson(
        _wire(
          _record(
            id: 'bs-0',
            day: 1,
            requestId: null,
            settings: const {structuralQuorumKey: 'majority'},
          ).toJson(),
        ),
      );
      expect(orphan.requestId, isNull);
      expect(orphan.toJson().containsKey('request_id'), isFalse);
      expect(structuralQuorumOf(orphan.settings), StructuralQuorum.majority);
    });

    test('E-03-33 unknown top-level fields round-trip in extra; unknown keys '
        'and values inside settings round-trip verbatim inside settings '
        '(03 §3.3.4 🔒)', () {
      final wire = <String, Object?>{
        'id': 'bs-2',
        'book_id': 'farm',
        'hlc': 42,
        'by_user': 'amrit',
        'request_id': 'req-2',
        'settings': {
          structuralQuorumKey: 'two_thirds',
          'interest_on_capital': {'rate_bp': 800, 'from': '2026-04-01'},
        },
        'effective_from': '2026-04-01',
      };
      final record = BusinessSetting.fromJson(_wire(wire));
      expect(record.extra, {'effective_from': '2026-04-01'});
      expect(record.settings, wire['settings']);
      // Consumers read the unknown conservatively — and keep their hands off.
      expect(structuralQuorumOf(record.settings), StructuralQuorum.allOwners);
      expect(isStructuralQuorumKnown(record.settings), isFalse);
      expect(_wire(record.toJson()), wire, reason: 'byte-for-byte on amend');
    });

    test('E-03-33 a record that sets nothing is malformed and throws — the '
        'caller quarantines it with the reason', () {
      for (final bad in <Map<String, Object?>>[
        {'id': 'x', 'book_id': 'farm', 'hlc': 1, 'by_user': 'a'},
        {
          'id': 'x',
          'book_id': 'farm',
          'hlc': 1,
          'by_user': 'a',
          'settings': 'majority',
        },
        {
          'id': 'x',
          'book_id': 'farm',
          'hlc': 1,
          'by_user': 'a',
          'settings': [1],
        },
      ]) {
        expect(() => BusinessSetting.fromJson(bad), throwsFormatException);
      }
    });

    test('E-03-33 it is not a projector event: decodeEvent ignores it and '
        'Recompute does not consume it, so the golden hash cannot move', () {
      final record = _record(
        id: 'bs-3',
        day: 5,
        settings: const {structuralQuorumKey: 'majority'},
      );
      expect(decodeEvent('business_setting', record.toJson()), isNull);
      expect(projectedObjectTypes.contains('business_setting'), isFalse);
    });
  });

  group('E-03-34 the terms in force are the fold (ADR 2026-09-14b §2)', () {
    test('E-03-34 with no records the deed governs: creation shares, default '
        'quorum — and a recorded creation quorum shows through', () {
      final inForce = structuralSettingsInForce(
        deed: _deed(),
        applied: const [],
      );
      expect(partnerSharesInForce(inForce), _thirds);
      expect(quorumInForce(inForce), StructuralQuorum.allOwners);
      expect(inForce.containsKey(structuralQuorumKey), isFalse);

      final chosen = structuralSettingsInForce(
        deed: _deed(quorum: StructuralQuorum.majority),
        applied: const [],
      );
      expect(quorumInForce(chosen), StructuralQuorum.majority);

      // Only the structural keys are folded — the deed's routine fields are
      // not settings (name, type, FY start stay where the projector reads them).
      expect(inForce.keys.toSet(), {'partner_shares'});
      expect(chosen.keys.toSet(), {'partner_shares', structuralQuorumKey});
    });

    test('E-03-34 records override the deed in (hlc, id) order whatever order '
        'they arrive, and the fold as of an earlier point is the earlier terms', () {
      final ratioA = _record(
        id: 'bs-a',
        day: 20,
        settings: const {
          'partner_shares': {
            'farm:amrit': 40,
            'farm:sukhdev': 30,
            'farm:harjit': 30,
          },
        },
      );
      final quorumB = _record(
        id: 'bs-b',
        day: 30,
        settings: const {structuralQuorumKey: 'majority'},
      );
      // Same hlc as B: the id breaks the tie, so C is ordered after B.
      final ratioC = _record(
        id: 'bs-c',
        day: 30,
        settings: const {
          'partner_shares': {
            'farm:amrit': 50,
            'farm:sukhdev': 25,
            'farm:harjit': 25,
          },
        },
      );
      final expected = {
        'partner_shares': {
          'farm:amrit': 50,
          'farm:sukhdev': 25,
          'farm:harjit': 25,
        },
        structuralQuorumKey: 'majority',
      };
      for (final arrival in [
        [ratioA, quorumB, ratioC],
        [ratioC, quorumB, ratioA],
        [quorumB, ratioC, ratioA],
      ]) {
        final inForce = structuralSettingsInForce(
          deed: _deed(),
          applied: arrival,
        );
        expect(inForce, expected, reason: 'arrival order never matters');
        expect(partnerSharesInForce(inForce), {
          'farm:amrit': 50,
          'farm:sukhdev': 25,
          'farm:harjit': 25,
        });
        expect(quorumInForce(inForce), StructuralQuorum.majority);
      }

      // As of day 25 — the caller hands in the records up to that point — the
      // 40/30/30 ratio and the deed's default quorum were in force. A past
      // period's terms are recoverable (02 §7.1's reason for a dated envelope).
      final asOf25 = structuralSettingsInForce(
        deed: _deed(),
        applied: [ratioA],
      );
      expect(partnerSharesInForce(asOf25), {
        'farm:amrit': 40,
        'farm:sukhdev': 30,
        'farm:harjit': 30,
      });
      expect(quorumInForce(asOf25), StructuralQuorum.allOwners);
    });

    test(
      'E-03-34 a record in the fold equals applyStructural on the approved '
      'request it records — the record is the engine\'s derivation, dated',
      () {
        const owners = OwnerSetVersion(
          version: 1,
          ownerIds: {'amrit', 'sukhdev', 'harjit'},
          quorum: StructuralQuorum.allOwners,
        );
        final request = StructuralRequest(
          id: 'req-quorum',
          bookId: 'farm',
          hlc: Hlc.compose(physicalMs: _day(10), counter: 0),
          action: StructuralAction.quorumSetting,
          byUser: 'amrit',
          ownerSetVersion: 1,
          payload: const {structuralQuorumKey: 'majority'},
        );
        StructuralApproval approve(String by, int day) => StructuralApproval(
          id: 'ok-$by',
          bookId: 'farm',
          hlc: Hlc.compose(physicalMs: _day(day), counter: 0),
          requestId: 'req-quorum',
          byUser: by,
          ownerSetVersion: 1,
        );
        final outcome = evaluateStructural(
          request: request,
          records: [
            approve('amrit', 11),
            approve('sukhdev', 12),
            approve('harjit', 13),
          ],
          owners: const [owners],
          asOfMs: _day(13),
        );
        expect(outcome.isApplied, isTrue);

        final base = structuralSettingsInForce(
          deed: _deed(),
          applied: const [],
        );
        final viaEngine = applyStructural(base, outcome);
        // The record the k-th approver's device writes at quorum: dated at or
        // after `decidedAt`, naming the request, carrying its payload.
        final record = BusinessSetting(
          id: 'bs-quorum',
          bookId: 'farm',
          hlc: outcome.decidedAt!,
          byUser: 'harjit',
          requestId: request.id,
          settings: request.payload,
        );
        final viaRecord = structuralSettingsInForce(
          deed: _deed(),
          applied: [record],
        );
        expect(viaRecord, viaEngine);
        expect(quorumInForce(viaRecord), StructuralQuorum.majority);
        expect(
          record.settings,
          request.payload,
          reason: 'the verifier\'s check',
        );
      },
    );

    test('E-03-34 an uninterpretable value in force — in the deed or in a '
        'record — is carried verbatim and read conservatively', () {
      // Deed written by a newer build: the quorum rule is unknown to us.
      final newerDeed = BookConfig.fromJson({
        'id': 'farm',
        'tenant_id': 't1',
        'type': 'business',
        'name': 'Kaur Farm',
        'ownership': 'shared',
        'partner_shares': _thirds,
        structuralQuorumKey: 'two_thirds',
      });
      final fromDeed = structuralSettingsInForce(
        deed: newerDeed,
        applied: const [],
      );
      expect(fromDeed[structuralQuorumKey], 'two_thirds', reason: 'verbatim');
      expect(quorumInForce(fromDeed), StructuralQuorum.allOwners);
      expect(isStructuralQuorumKnown(fromDeed), isFalse);
      expect(partnerSharesInForce(fromDeed), _thirds);

      // A record written by a newer build sets a ratio shape we cannot divide
      // by: it is in force, and *not recorded* is what we must say — never
      // the deed's old thirds, which would post a wrong distribution.
      final newerRatio = _record(
        id: 'bs-n',
        day: 40,
        settings: const {
          'partner_shares': {
            'farm:amrit': {'weight': 2, 'from': '2027-04-01'},
          },
        },
      );
      final fromRecord = structuralSettingsInForce(
        deed: _deed(),
        applied: [newerRatio],
      );
      expect(
        fromRecord['partner_shares'],
        newerRatio.settings['partner_shares'],
      );
      expect(partnerSharesInForce(fromRecord), isEmpty);
    });

    test('E-03-34 a record of another book is refused, and neither input is '
        'mutated by the fold', () {
      final deed = _deed();
      final foreign = _record(
        id: 'bs-x',
        day: 3,
        bookId: 'shop',
        settings: const {structuralQuorumKey: 'majority'},
      );
      expect(
        () => structuralSettingsInForce(deed: deed, applied: [foreign]),
        throwsArgumentError,
      );

      final record = _record(
        id: 'bs-1',
        day: 20,
        settings: const {structuralQuorumKey: 'majority'},
      );
      final before = _wire(record.toJson());
      final deedBefore = _wire(deed.toJson());
      final inForce = structuralSettingsInForce(deed: deed, applied: [record]);
      expect(() => inForce['x'] = 1, throwsUnsupportedError);
      expect(_wire(record.toJson()), before);
      expect(_wire(deed.toJson()), deedBefore);
      expect(deed.structuralQuorum, isNull, reason: 'the deed never changes');
    });
  });
}
