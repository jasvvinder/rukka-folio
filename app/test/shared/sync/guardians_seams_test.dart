// S11.1's live producer: who may hold a share, which generation it belongs
// to, and what happens when the server says no (04 §7.3 🔒).
//
// The adversarial cases are the point. A guardian set that looks right and is
// subtly wrong — a share sealed to a key nobody verified, two shares to one
// person, a generation published over another device's — is a green screen
// over a recovery that will not work, or a quorum smaller than the one the
// user was promised.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/guardians.dart';
import 'package:rukka_folio/shared/sync/guardian_sealing.dart';
import 'package:rukka_folio/shared/sync/guardians_seams.dart';
import 'package:sync_engine/sync_engine.dart' show MapUmkSource;

import 'guardian_test_keys.dart';

/// A scripted [GuardiansApi]: the history it answers with, and every draft it
/// was handed.
final class _Api implements GuardiansApi {
  _Api({this.history = const [], this.refuse});

  List<GuardianSetWire> history;

  /// When set, [publish] throws it.
  RecoveryApiFailure? refuse;

  final List<({int version, int k, List<SealedGuardianShare> shares})> drafts =
      [];
  int reads = 0;

  @override
  Future<List<GuardianSetWire>> sets() async {
    reads++;
    return history;
  }

  @override
  Future<int> publish({
    required int shareSetVersion,
    required int k,
    required List<SealedGuardianShare> shares,
  }) async {
    drafts.add((version: shareSetVersion, k: k, shares: shares));
    final r = refuse;
    if (r != null) throw r;
    history = [
      ...history,
      GuardianSetWire(
        subjectUserId: userMe,
        shareSetVersion: shareSetVersion,
        k: k,
        n: shares.length,
        members: [
          for (final s in shares)
            GuardianSetMemberWire(
              guardianUserId: s.guardian.userId,
              umkPubEd: s.guardian.umkPubEd,
            ),
        ],
      ),
    ];
    return shareSetVersion;
  }
}

GuardianSetWire _set(int version, List<String> ids, {String? subject}) =>
    GuardianSetWire(
      subjectUserId: subject ?? userMe,
      shareSetVersion: version,
      k: guardianThreshold(ids.length),
      n: ids.length,
      members: [
        for (final id in ids)
          GuardianSetMemberWire(guardianUserId: id, umkPubEd: Uint8List(0)),
      ],
    );

GuardianCandidateRow _row(
  String id, {
  GuardianCeremony ceremony = GuardianCeremony.done,
  bool isYou = false,
}) => GuardianCandidateRow(
  userId: id,
  name: 'Member ${id.substring(id.length - 1)}',
  ceremony: ceremony,
  isYou: isYou,
);

/// A sealer that records its requests and seals for real.
final class _Sealer {
  _Sealer(this.suite);

  final CryptoSuite suite;
  final List<GuardianSplitRequest> requests = [];

  /// Replaces the returned cover, to model a sealer that slipped.
  List<SealedGuardianShare> Function(List<SealedGuardianShare> honest)? bend;

  Future<List<SealedGuardianShare>> call(GuardianSplitRequest request) async {
    requests.add(request);
    final honest = [
      for (final g in request.guardians)
        SealedGuardianShare(
          guardian: g,
          blob: sealToVerified(suite, g.umk, Uint8List.fromList([1, 2, 3])),
        ),
    ];
    return bend?.call(honest) ?? honest;
  }
}

void main() {
  late CryptoSuite suite;
  late List<TestGuardian> guardians;
  late Map<String, VerifiedUmkPublic> verified;

  setUpAll(() async {
    suite = await liveSuite();
    guardians = [
      for (final id in userGuardians) TestGuardian.generate(suite, id),
    ];
    verified = {for (final g in guardians) g.userId: g.verified};
  });
  tearDownAll(() {
    for (final g in guardians) {
      g.umk.dispose();
    }
  });

  ServerGuardians build(
    _Api api, {
    List<GuardianCandidateRow>? rows,
    bool readOnly = false,
    Map<String, VerifiedUmkPublic>? keys,
    GuardianShareSealer? sealer,
  }) {
    final repo = ServerGuardians(
      api: api,
      roster: () async => GuardianRoster(
        candidates:
            rows ??
            [
              for (final id in userGuardians) _row(id),
              _row(userMe, isYou: true),
            ],
        readOnly: readOnly,
      ),
      verified: MapUmkSource(keys ?? verified),
      sealer: sealer,
    );
    addTearDown(repo.dispose);
    return repo;
  }

  test(
    'C-06-47 the set in force is the highest share_set_version, the signed-in '
    'user is never a candidate, and a chosen id the roster does not hold is '
    'still reported — a live 3-of-5 never reads as *not set up*',
    () async {
      final api = _Api(
        history: [
          _set(1, [userGuardians[0], userGuardians[1]]),
          // Out of order on the wire; the generation decides, not the order.
          _set(3, [userGuardians[0], userGuardians[1], 'stranger']),
          _set(2, [userGuardians[2], userGuardians[3]]),
        ],
      );
      final repo = build(api, readOnly: true);

      await repo.refresh();

      expect(repo.current!.chosenIds, [
        userGuardians[0],
        userGuardians[1],
        'stranger',
      ]);
      expect(repo.current!.isConfigured, isTrue);
      expect(repo.current!.readOnly, isTrue);
      expect(
        repo.current!.candidates.map((c) => c.memberId),
        isNot(contains(userMe)),
      );
    },
  );

  test('C-06-48 a share is sealed only to a key a ceremony verified: a member '
      'the trust source cannot answer for is refused, the UMK is never split, '
      'and nothing is uploaded (rule 5, 04 §8.2 🔒)', () async {
    final api = _Api();
    final sealer = _Sealer(suite);
    // The roster says the ceremony is done for all five — and the trust
    // source holds a key for nobody. The roster's word is not a key.
    final repo = build(
      api,
      keys: const {},
      sealer: sealer.call,
      rows: [for (final id in userGuardians) _row(id)],
    );
    await repo.refresh();

    await expectLater(
      repo.save([userGuardians[0], userGuardians[1], userGuardians[2]]),
      throwsA(
        isA<GuardiansFailure>().having((e) => e.reason, 'reason', 'unverified'),
      ),
    );
    expect(sealer.requests, isEmpty, reason: 'UMK_priv is never split');
    expect(api.drafts, isEmpty);
  });

  test(
    'C-06-49 the key the server relayed is not a key to seal to: a published '
    'set carrying umk_pub_ed for a member does not make them sealable',
    () async {
      final relayed = GuardianSetWire(
        subjectUserId: userMe,
        shareSetVersion: 1,
        k: 2,
        n: 2,
        members: [
          for (final g in guardians.take(2))
            GuardianSetMemberWire(
              guardianUserId: g.userId,
              // The server's copy of the very key a ceremony would verify.
              umkPubEd: g.verified.public.ed25519,
            ),
        ],
      );
      final api = _Api(history: [relayed]);
      final sealer = _Sealer(suite);
      final repo = build(api, keys: const {}, sealer: sealer.call);
      await repo.refresh();

      await expectLater(
        repo.save([userGuardians[0], userGuardians[1]]),
        throwsA(isA<GuardiansFailure>()),
      );
      expect(sealer.requests, isEmpty);
      expect(api.drafts, isEmpty);
    },
  );

  test(
    'C-06-50 a published set is k = ⌈(n+1)/2⌉ at the NEXT generation, one '
    'share per guardian sealed to their verified key, and the history is '
    'read back rather than assumed (04 §7.3 🔒, 0010 guardian_set_guard)',
    () async {
      final api = _Api(
        history: [
          _set(7, [userGuardians[3], userGuardians[4]]),
        ],
      );
      final sealer = _Sealer(suite);
      final repo = build(api, sealer: sealer.call);
      await repo.refresh();

      await repo.save([userGuardians[0], userGuardians[1], userGuardians[2]]);

      expect(api.drafts.single.version, 8, reason: 'max(history) + 1');
      expect(api.drafts.single.k, 2, reason: '⌈(3+1)/2⌉');
      expect(sealer.requests.single.n, 3);
      expect(sealer.requests.single.k, 2);
      expect(sealer.requests.single.shareSetVersion, 8);
      for (final s in api.drafts.single.shares) {
        expect(s.blob.recipient, verified[s.guardian.userId]!.fingerprint);
        expect(
          s.guardian.umkPubEd,
          verified[s.guardian.userId]!.public.ed25519,
        );
      }
      expect(repo.current!.chosenIds, [
        userGuardians[0],
        userGuardians[1],
        userGuardians[2],
      ]);
      expect(api.reads, 2, reason: 'refresh, then the read-back after publish');

      // 04 §7.3: every change re-splits. The second save is a fresh split at
      // the next generation — never the first one's shares again.
      await repo.save([userGuardians[0], userGuardians[1]]);
      expect(api.drafts.last.version, 9);
      expect(api.drafts.last.k, 2, reason: '⌈(2+1)/2⌉ — 2-of-2');
      expect(sealer.requests, hasLength(2));
      expect(
        api.drafts.last.shares.first.blob.bytes,
        isNot(api.drafts.first.shares.first.blob.bytes),
      );
    },
  );

  test('C-06-51 the shapes 04 §7.3 🔒 forbids never reach the wire: n outside '
      '2..5, the same person twice, the subject themself, a stranger, and a '
      'viewer who may not change the set', () async {
    final sealer = _Sealer(suite);
    final api = _Api();
    final repo = build(api, sealer: sealer.call);
    await repo.refresh();

    Future<String> refusalOf(List<String> ids) async {
      try {
        await repo.save(ids);
        fail('expected a refusal for $ids');
      } on GuardiansFailure catch (e) {
        return e.reason;
      }
    }

    expect(await refusalOf([userGuardians[0]]), 'size');
    expect(await refusalOf([...userGuardians, userMe]), 'size');
    expect(await refusalOf([userGuardians[0], userGuardians[0]]), 'duplicate');
    expect(await refusalOf([userGuardians[0], userMe]), 'self');
    expect(await refusalOf([userGuardians[0], 'nobody-at-all']), 'unknown');
    expect(api.drafts, isEmpty);
    expect(sealer.requests, isEmpty);

    // A member whose ceremony has not finished, however verified the key.
    final pending = build(
      _Api(),
      rows: [
        _row(userGuardians[0]),
        _row(userGuardians[1], ceremony: GuardianCeremony.started),
      ],
      sealer: sealer.call,
    );
    await pending.refresh();
    await expectLater(
      pending.save([userGuardians[0], userGuardians[1]]),
      throwsA(
        isA<GuardiansFailure>().having((e) => e.reason, 'reason', 'unverified'),
      ),
    );

    final viewer = build(_Api(), readOnly: true, sealer: sealer.call);
    await viewer.refresh();
    await expectLater(
      viewer.save([userGuardians[0], userGuardians[1]]),
      throwsA(
        isA<GuardiansFailure>().having((e) => e.reason, 'reason', 'read_only'),
      ),
    );
    expect(sealer.requests, isEmpty);
  });

  test('C-06-52 a refused draft is never retried a generation up: the version '
      'moved because another device published, and publishing over it would '
      'retire a set the user may have just made (0010 '
      'share_set_version_out_of_order)', () async {
    final api = _Api(
      history: [
        _set(1, [userGuardians[0], userGuardians[1]]),
      ],
      refuse: const RecoveryApiFailure(RecoveryRefusal.badRequest),
    );
    final sealer = _Sealer(suite);
    final repo = build(api, sealer: sealer.call);
    await repo.refresh();
    // Another device got there first.
    api.history = [
      ...api.history,
      _set(2, [userGuardians[2], userGuardians[3]]),
    ];

    await expectLater(
      repo.save([userGuardians[0], userGuardians[4]]),
      throwsA(
        isA<GuardiansFailure>().having((e) => e.reason, 'reason', 'rejected'),
      ),
    );

    expect(api.drafts, hasLength(1), reason: 'one attempt, never a retry');
    expect(api.drafts.single.version, 2);
    // The screen is left looking at what is actually in force.
    expect(repo.current!.chosenIds, [userGuardians[2], userGuardians[3]]);
  });

  test(
    "C-06-53 a sealer's cover is checked before anything is uploaded: a short "
    'set, two shares to one person, or a share addressed elsewhere is refused',
    () async {
      Future<void> expectSealRefusal(
        List<SealedGuardianShare> Function(List<SealedGuardianShare>) bend,
      ) async {
        final api = _Api();
        final sealer = _Sealer(suite)..bend = bend;
        final repo = build(api, sealer: sealer.call);
        await repo.refresh();
        await expectLater(
          repo.save([userGuardians[0], userGuardians[1], userGuardians[2]]),
          throwsA(
            isA<GuardiansFailure>().having((e) => e.reason, 'reason', 'seal'),
          ),
        );
        expect(api.drafts, isEmpty);
      }

      await expectSealRefusal((honest) => honest.take(2).toList());
      await expectSealRefusal(
        (honest) => [honest.first, honest.first, honest.last],
      );
      await expectSealRefusal(
        (honest) => [
          honest.first,
          honest[1],
          SealedGuardianShare(
            guardian: VerifiedGuardian(
              userId: guardians[4].userId,
              umk: guardians[4].verified,
            ),
            blob: sealToVerified(
              suite,
              guardians[4].verified,
              Uint8List.fromList([1]),
            ),
          ),
        ],
      );
    },
  );

  test(
    'C-06-54 a history this device cannot read as one subject, or that holds '
    'two rows at one generation, is a shape error — never a guess about whose '
    'set is in force',
    () async {
      final twoSubjects = build(
        _Api(
          history: [
            _set(1, [userGuardians[0], userGuardians[1]]),
            _set(2, [userGuardians[2], userGuardians[3]], subject: 'someone'),
          ],
        ),
      );
      await expectLater(
        twoSubjects.refresh(),
        throwsA(
          isA<GuardiansFailure>().having((e) => e.reason, 'reason', 'shape'),
        ),
      );

      final twice = build(
        _Api(
          history: [
            _set(1, [userGuardians[0], userGuardians[1]]),
            _set(1, [userGuardians[2], userGuardians[3]]),
          ],
        ),
      );
      await expectLater(
        twice.refresh(),
        throwsA(
          isA<GuardiansFailure>().having((e) => e.reason, 'reason', 'shape'),
        ),
      );
    },
  );

  test('C-06-55 with no sealer the repository still reads the set in force and '
      'refuses to publish — a producer that refuses is the truth, a fake that '
      'succeeds is not', () async {
    final api = _Api(
      history: [
        _set(2, [userGuardians[0], userGuardians[1]]),
      ],
    );
    final repo = build(api);
    await repo.refresh();

    expect(repo.current!.chosenIds, [userGuardians[0], userGuardians[1]]);
    await expectLater(
      repo.save([userGuardians[0], userGuardians[2]]),
      throwsA(
        isA<GuardiansFailure>().having((e) => e.reason, 'reason', 'no_sealer'),
      ),
    );
    expect(api.drafts, isEmpty);
  });

  test('C-06-56 the live split: n shares of one generation, each opening only '
      'for its own guardian, any k of them re-deriving the very UMK the set '
      'protects — and no other k (04 §7.3 steps 3–4)', () async {
    final me = UmkKeyPair.generate(suite);
    addTearDown(me.dispose);
    final mine = TestGuardian(suite, userMe, me).verified;
    final sealer = CryptoGuardianSealer(suite: suite, umk: () => me);

    final chosen = guardians.take(3).toList();
    final shares = await sealer.call(
      GuardianSplitRequest(
        shareSetVersion: 4,
        k: guardianThreshold(3),
        guardians: [
          for (final g in chosen)
            VerifiedGuardian(userId: g.userId, umk: g.verified),
        ],
      ),
    );

    expect(shares, hasLength(3));
    // Each blob opens for its own guardian and for nobody else.
    final opened = <GuardianShare>[];
    for (var i = 0; i < shares.length; i++) {
      final plain = openSealed(suite, chosen[i].umk, shares[i].blob);
      final share = GuardianShare.decode(plain);
      expect(share.shareSetVersion, 4);
      expect(share.k, 2);
      expect(share.n, 3);
      opened.add(share);
      expect(
        () => openSealed(suite, chosen[(i + 1) % 3].umk, shares[i].blob),
        throwsA(isA<UnsealFailed>()),
      );
    }
    addTearDown(() {
      for (final s in opened) {
        s.dispose();
      }
    });

    // k = 2 of them reconstruct the UMK, checked against the key the
    // recovering device already knows (ADR 2026-09-06 §2).
    final rebuilt = GuardianShareSet.reconstructVerified(suite, [
      opened[0],
      opened[2],
    ], expected: mine);
    addTearDown(rebuilt.dispose);
    expect(rebuilt.public.ed25519, me.public.ed25519);
    expect(rebuilt.public.x25519, me.public.x25519);

    // A share from another generation never joins this one.
    final later = await sealer.call(
      GuardianSplitRequest(
        shareSetVersion: 5,
        k: 2,
        guardians: [
          for (final g in chosen)
            VerifiedGuardian(userId: g.userId, umk: g.verified),
        ],
      ),
    );
    final foreign = GuardianShare.decode(
      openSealed(suite, chosen[1].umk, later[1].blob),
    );
    addTearDown(foreign.dispose);
    expect(
      () => GuardianShareSet.reconstruct([opened[0], foreign]),
      throwsArgumentError,
    );
  });
}
