// The `book_config` envelope (03 §2.3) — the two fields onboarding collects
// and the ledger must keep: the partners' share weights (02 §7.1 🔒, ADR
// 2026-09-09 §2) and the organization subtype (07 §3.1.1 🔒).
//
// The ledger is append-only, so every case below is really one question: what
// happens to a config written by a *different* build of the app — older (the
// key is absent) or newer (the key is there but the value means something this
// build does not know). Both must survive, neither may throw, and 03 §3.3.4 🔒
// says the bytes we could not interpret come back out unchanged.
import 'dart:convert';

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:test/test.dart';

BookConfig _roundTrip(BookConfig c) => BookConfig.fromJson(
  jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>,
);

void main() {
  group('book_config partner share weights (02 §7.1, ADR 2026-09-09 §2)', () {
    test('E-03-30 the weights persist keyed by partner account id, and a '
        'config written before the field existed reads back with none', () {
      final config = BookConfig(
        id: 'b1',
        tenantId: 't1',
        type: BookType.business,
        name: 'Sharma Kirana',
        ownership: BookOwnership.shared,
        partnerShares: const {'acct-amrit': 2, 'acct-sukhdev': 1},
      );

      final wire = config.toJson();
      expect(
        wire['partner_shares'],
        {'acct-amrit': 2, 'acct-sukhdev': 1},
        reason:
            'keyed by account id, never by the owner name — the account is '
            'seeded `{Name} — Partner Current A/c` and may be renamed',
      );
      final back = _roundTrip(config);
      expect(back.partnerShares, {'acct-amrit': 2, 'acct-sukhdev': 1});
      expect(back.ownership, BookOwnership.shared);

      // Weights are whole numbers, so the 2:1 split of ₹100.00 is the engine's
      // floor division and not a percentage: 33/33/34 is a real difference.
      final total = back.partnerShares.values.fold(0, (a, b) => a + b);
      expect(total, 3);

      // An older book: no key at all. Not an error, and never "equal shares".
      final older = BookConfig.fromJson({
        'id': 'b0',
        'tenant_id': 't1',
        'type': 'business',
        'name': 'Older book',
        'ownership': 'shared',
      });
      expect(older.partnerShares, isEmpty);
      expect(older.toJson().containsKey('partner_shares'), isFalse);

      // A justMe book carries none either, and does not invent any.
      final solo = BookConfig(
        id: 'b2',
        tenantId: 't1',
        type: BookType.business,
        name: 'My shop',
      );
      expect(solo.partnerShares, isEmpty);
      expect(solo.toJson().containsKey('partner_shares'), isFalse);
    });

    test('E-03-30 a weights value this build cannot interpret is preserved '
        'verbatim, not guessed at (03 §3.3.4 🔒)', () {
      // A newer build might carry per-partner objects, or a float, or a zero.
      // None of these are a ratio this build can divide by, so it must keep
      // its hands off them rather than silently drop the partnership.
      for (final raw in <Object?>[
        {
          'acct-amrit': {'weight': 2, 'from': '2026-04-01'},
        },
        {'acct-amrit': 2.5, 'acct-sukhdev': 1},
        {'acct-amrit': 0, 'acct-sukhdev': 1},
        {'acct-amrit': -1},
        'equal',
      ]) {
        final decoded = BookConfig.fromJson({
          'id': 'b1',
          'tenant_id': 't1',
          'type': 'business',
          'name': 'Sharma Kirana',
          'ownership': 'shared',
          'partner_shares': raw,
        });
        expect(
          decoded.partnerShares,
          isEmpty,
          reason:
              'uninterpretable is not "no partners": it is unknown, and '
              'reading it as a ratio would post a wrong distribution',
        );
        expect(decoded.extra['partner_shares'], raw);
        expect(
          decoded.toJson()['partner_shares'],
          raw,
          reason:
              'amending the config writes the newer build\'s field back '
              'unchanged (03 §3.3.4 🔒)',
        );
      }
    });
  });

  group('book_config organization subtype (07 §3.1.1)', () {
    test('E-03-31 the trust subtype persists on its own wire name, defaults to '
        'null on an older book, and an unrecognised one round-trips', () {
      for (final subtype in OrganizationSubtype.values) {
        final config = BookConfig(
          id: 'b3',
          tenantId: 't1',
          type: BookType.organization,
          name: 'Guru Nanak Gurudwara',
          organizationSubtype: subtype,
        );
        expect(
          config.toJson()['organization_subtype'],
          organizationSubtypeWire[subtype],
        );
        expect(_roundTrip(config).organizationSubtype, subtype);
      }
      // The wire names are fixed: renaming the Dart identifier must not move
      // a book from one subtype to another on the next read.
      expect(
        organizationSubtypeWire[OrganizationSubtype.registeredTrust],
        'registered_trust',
      );

      // A book written before the field existed, and every non-organization
      // book, simply has none.
      final older = BookConfig.fromJson({
        'id': 'b0',
        'tenant_id': 't1',
        'type': 'organization',
        'name': 'Older trust',
      });
      expect(older.organizationSubtype, isNull);
      expect(older.toJson().containsKey('organization_subtype'), isFalse);

      // 07 §3.1.1 calls its four an illustrative list, so a newer build may
      // write a fifth. That must not throw the way `values.byName` would, and
      // must survive an amend by this build.
      final newer = BookConfig.fromJson({
        'id': 'b4',
        'tenant_id': 't1',
        'type': 'organization',
        'name': 'Sabha',
        'organization_subtype': 'sabha',
      });
      expect(newer.organizationSubtype, isNull);
      expect(newer.extra['organization_subtype'], 'sabha');
      expect(newer.toJson()['organization_subtype'], 'sabha');
    });

    test('E-03-31 neither new field disturbs the unknown fields already being '
        'round-tripped (03 §3.3.4 🔒)', () {
      final decoded = BookConfig.fromJson({
        'id': 'b5',
        'tenant_id': 't1',
        'type': 'organization',
        'name': 'Guru Nanak Gurudwara',
        'organization_subtype': 'gurudwara',
        'partner_shares': {'acct-a': 1},
        'future_field': {
          'x': 1,
          'y': ['a', 'b'],
        },
      });
      expect(decoded.organizationSubtype, OrganizationSubtype.gurudwara);
      expect(decoded.partnerShares, {'acct-a': 1});
      expect(
        decoded.extra.keys,
        ['future_field'],
        reason: 'a field we now understand leaves extra, and nothing else does',
      );
      final wire = decoded.toJson();
      expect(wire['future_field'], {
        'x': 1,
        'y': ['a', 'b'],
      });
      expect(wire['organization_subtype'], 'gurudwara');
      expect(wire['partner_shares'], {'acct-a': 1});
    });
  });
}
