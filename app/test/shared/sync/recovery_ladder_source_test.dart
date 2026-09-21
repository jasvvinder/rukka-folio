// The live recovery ladder (04 §7.0 🔒, §7.1, §7.2, §7.4 🔒; 13 §5 F11).
//
// One property carries the weight here, and it is adversarial rather than
// cosmetic: **no rung may read as available unless a real source said so.**
// The person reading S11.6 is already locked out, so a green test over a
// ladder that cheerfully offers a rung it never asked about is exactly the
// failure this suite exists to catch — the screen would look right and the
// person would spend their one attempt on a door that is not there.
//
// The mirror of it is tested just as hard: a source that could not be reached
// may not be turned into a refusal either. "You have no recovery sheet" said
// to somebody holding one is how a person stops trying.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/devices_repository.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/sync/guardians_api.dart';
import 'package:rukka_folio/shared/sync/recovery_ladder_source.dart';
import 'package:rukka_folio/shared/sync/recovery_seams.dart';

// ---------------------------------------------------------------------------
// doubles
// ---------------------------------------------------------------------------

/// A key store that can also fail, which [FakeKeyStore] cannot.
final class _Keys implements KeyStore {
  _Keys({Set<String>? present, this.throwsOn}) : _present = present ?? {};

  final Set<String> _present;

  /// An id whose presence cannot be established — the platform refusing.
  final String? throwsOn;

  @override
  Future<bool> contains(String id) async {
    if (id == throwsOn) throw StateError('keystore unavailable');
    return _present.contains(id);
  }

  @override
  Future<Uint8List?> read(String id) async =>
      fail('the ladder must never read a key to answer a question');

  @override
  Future<void> write(String id, Uint8List bytes) async => fail('no writes');

  @override
  Future<void> delete(String id) async => fail('no deletes');
}

final class _Guardians implements GuardiansApi {
  _Guardians({this.history = const [], this.throws});

  final List<GuardianSetWire> history;
  final Object? throws;
  int reads = 0;

  @override
  Future<List<GuardianSetWire>> sets() async {
    reads++;
    final t = throws;
    if (t != null) throw t;
    return history;
  }

  @override
  Future<int> publish({
    required int shareSetVersion,
    required int k,
    required List<SealedGuardianShare> shares,
  }) async => fail('the ladder never writes');
}

final class _Recovery implements RecoveryApi {
  _Recovery({this.blob, this.throws});

  /// The sheet the route answers with; null is the route's `no_sheet`.
  final RecoverySheetWire? blob;
  final Object? throws;
  int sheetReads = 0;

  @override
  Future<RecoverySheetWire?> sheet() async {
    sheetReads++;
    final t = throws;
    if (t != null) throw t;
    return blob;
  }

  @override
  Future<String?> approve({
    required String requestId,
    required Uint8List blob,
    required Uint8List sealedToPubX,
  }) async => fail('not the ladder');

  @override
  Future<List<RecoveryAskWire>> asks() async => fail('not the ladder');

  @override
  Future<void> cancel(String requestId) async => fail('not the ladder');

  @override
  Future<void> deny(String requestId) async => fail('not the ladder');

  @override
  Future<List<RecoveryRequestWire>> myRequests() async =>
      fail('not the ladder');

  @override
  Future<RecoveryRequestWire> open(Uint8List candidatePubX) async =>
      fail('not the ladder');

  @override
  Future<RecoveryProgressWire> progress(String requestId) async =>
      fail('not the ladder');

  @override
  Future<int> publishSheet(Uint8List blob) async =>
      fail('the ladder never writes');
}

/// A devices repository whose refresh can fail while a snapshot is cached.
final class _Devices implements DevicesRepository {
  _Devices({this.snapshot, this.refreshThrows = false});

  DevicesSnapshot? snapshot;
  bool refreshThrows;
  int refreshes = 0;

  @override
  DevicesSnapshot? get current => snapshot;

  @override
  Future<void> refresh() async {
    refreshes++;
    if (refreshThrows) throw const DevicesFailure('offline');
  }

  @override
  Stream<DevicesSnapshot> watch() => const Stream.empty();

  @override
  Future<void> cancelWindow(String windowId) async => fail('not the ladder');

  @override
  Future<void> retrySuspended() async => fail('not the ladder');

  @override
  Future<void> revoke(String deviceId, {bool stolen = false}) async =>
      fail('not the ladder');

  @override
  Future<void> setBackup(BackupSetting setting, bool enabled) async =>
      fail('not the ladder');
}

LinkedDevice _device({
  String id = 'd2',
  DeviceStatus status = DeviceStatus.certified,
  bool isThis = false,
}) => LinkedDevice(
  id: id,
  name: id,
  model: 'iPhone',
  addedOn: DateTime.utc(2026),
  lastActive: DateTime.utc(2026),
  status: status,
  isThisDevice: isThis,
);

GuardianSetWire _set({required int version, int n = 3, int k = 2}) =>
    GuardianSetWire(
      subjectUserId: 'u-me',
      shareSetVersion: version,
      k: k,
      n: n,
      members: [
        for (var i = 0; i < n; i++)
          GuardianSetMemberWire(guardianUserId: 'g$i', umkPubEd: Uint8List(32)),
      ],
    );

RecoveryRungOffer _offerFor(List<RecoveryRungOffer> all, RecoveryRung rung) =>
    all.firstWhere((o) => o.rung == rung);

RecoverySheetWire _wire() => RecoverySheetWire(
  userId: 'u-me',
  sheetVersion: 2,
  blob: Uint8List.fromList(const [1, 2, 3]),
  createdAtMs: 5,
);

/// The composition root's own **code** — read, not imagined, with the
/// comments stripped.
///
/// Stripping matters: `bootstrap.dart` names `FakeRecoveryLadder` in the prose
/// that explains why the live one is installed, and a check over the raw text
/// would fail on the sentence rather than on a fake. Line comments only; the
/// file has no block comments, and cutting at `//` can at worst truncate a
/// URL inside a string, which nothing here looks at.
///
/// `flutter test` runs from `app/`, but both candidates are tried so the test
/// is honest from the workspace root too, and a missing file fails rather
/// than passing vacuously.
String _bootstrapCode() {
  for (final path in ['lib/bootstrap.dart', 'app/lib/bootstrap.dart']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    expect(text, isNotEmpty, reason: 'the root was really read');
    return [
      for (final line in text.split('\n'))
        line.contains('//') ? line.substring(0, line.indexOf('//')) : line,
    ].join('\n');
  }
  fail('lib/bootstrap.dart not found from ${Directory.current.path}');
}

void main() {
  group('the third state', () {
    test(
      'F1-06-57 a rung with no probe is unknown, never available — '
      '"no producer in this build" is not evidence the rung is missing',
      () async {
        const ladder = LiveRecoveryLadder(probes: {});
        final offers = await ladder.rungs();

        for (final rung in RecoveryRung.forkOrder) {
          final offer = _offerFor(offers, rung);
          expect(
            offer.availability,
            RecoveryRungAvailability.unknown,
            reason: '${rung.name} was never asked',
          );
          expect(offer.isAvailable, isFalse);
          expect(offer.isBlocked, isFalse);
          expect(offer.blocked, isNull, reason: 'no reason is true here');
        }
      },
    );

    test('F1-06-58 an unknown offer is not available: isAvailable is false and '
        'the availability enum says so', () {
      const unknown = RecoveryRungOffer.unknown(RecoveryRung.recoverySheet);
      const available = RecoveryRungOffer.available(RecoveryRung.recoverySheet);
      const blocked = RecoveryRungOffer.blocked(
        RecoveryRung.recoverySheet,
        RecoveryRungBlocked.noRecoverySheet,
      );

      expect(unknown.isAvailable, isFalse);
      expect(unknown.isBlocked, isFalse);
      expect(unknown.availability, RecoveryRungAvailability.unknown);
      expect(available.availability, RecoveryRungAvailability.available);
      expect(blocked.availability, RecoveryRungAvailability.unavailable);
      // Three distinct values, so nothing can collapse two of them.
      expect(unknown, isNot(available));
      expect(unknown, isNot(blocked));
      expect(
        unknown,
        const RecoveryRungOffer.unknown(RecoveryRung.recoverySheet),
      );
    });

    test(
      'F1-06-59 one failing source cannot decide another rung: the probe that '
      'threw is unknown and the ones that answered are untouched',
      () async {
        final ladder = LiveRecoveryLadder(
          probes: {
            RecoveryRung.anotherDevice: () async =>
                throw StateError('transport died'),
            RecoveryRung.trustedMembers: trustedMembersProbe(
              _Guardians(history: [_set(version: 1)]),
            ),
            RecoveryRung.recoverySheet: recoverySheetProbe(_Recovery()),
          },
        );

        final offers = await ladder.rungs();
        expect(
          _offerFor(offers, RecoveryRung.anotherDevice).availability,
          RecoveryRungAvailability.unknown,
        );
        expect(
          _offerFor(offers, RecoveryRung.trustedMembers).isAvailable,
          isTrue,
        );
        expect(
          _offerFor(offers, RecoveryRung.recoverySheet).blocked,
          RecoveryRungBlocked.noRecoverySheet,
        );
      },
    );

    test(
      'F1-06-60 rungs() never throws, so a whole-screen error can never hide '
      'the rungs that did answer',
      () async {
        final ladder = LiveRecoveryLadder(
          probes: {
            for (final rung in RecoveryRung.forkOrder)
              rung: () async => throw StateError('everything is down'),
          },
        );

        final offers = await ladder.rungs();
        expect(offers.length, greaterThanOrEqualTo(4));
        expect(
          offers.every(
            (o) => o.availability == RecoveryRungAvailability.unknown,
          ),
          isTrue,
        );
      },
    );

    test('F1-06-61 every fork rung is present in the answer, plus rung 0 — an '
        'absent rung would be a hidden row', () async {
      final ladder = LiveRecoveryLadder(
        probes: {RecoveryRung.recoverySheet: recoverySheetProbe(_Recovery())},
      );
      final offers = await ladder.rungs();
      for (final rung in RecoveryRung.values) {
        expect(
          offers.where((o) => o.rung == rung).length,
          1,
          reason: '${rung.name} appears exactly once',
        );
      }
    });

    test(
      'F1-06-62 a probe that answers about the wrong rung is a wiring mistake, '
      'and a wiring mistake learned nothing',
      () async {
        final ladder = LiveRecoveryLadder(
          probes: {
            RecoveryRung.recoverySheet: () async =>
                const RecoveryRungOffer.available(RecoveryRung.anotherDevice),
          },
        );
        final offers = await ladder.rungs();
        expect(
          _offerFor(offers, RecoveryRung.recoverySheet).availability,
          RecoveryRungAvailability.unknown,
        );
        expect(
          _offerFor(offers, RecoveryRung.anotherDevice).availability,
          RecoveryRungAvailability.unknown,
        );
      },
    );
  });

  group('rung 3 — the recovery sheet (04 §7.4 🔒)', () {
    RecoverySheetWire wire() => RecoverySheetWire(
      userId: 'u-me',
      sheetVersion: 2,
      blob: Uint8List.fromList(const [1, 2, 3]),
      createdAtMs: 5,
    );

    test('F1-06-63 a blob on the route means the rung is real', () async {
      final api = _Recovery(blob: wire());
      final offer = await recoverySheetProbe(api)();
      expect(offer.isAvailable, isTrue);
      expect(api.sheetReads, 1);
    });

    test('F1-06-64 `no_sheet` is a real source saying no: the server holds one '
        'blob per user and says this user published none', () async {
      final offer = await recoverySheetProbe(_Recovery())();
      expect(offer.blocked, RecoveryRungBlocked.noRecoverySheet);
      expect(offer.isUnknown, isFalse);
    });

    test(
      'F1-06-93 a 200 whose `sealed_rk_blob` this build cannot read is '
      'UNKNOWN, not a sheet: `decodeB64Url` answers zero bytes for an absent, '
      'empty or malformed field and swallows the FormatException '
      '(recovery_api.dart:495), so a non-null wire is not by itself evidence',
      () async {
        // Driven through the real decoder, not a hand-built wire — the defect
        // was that `fromJson` yields a non-null wire either way.
        final bodies = <String, Map<String, Object?>>{
          'the field is absent': const {
            'user_id': 'u-me',
            'sheet_version': 2,
            'created_at': 5,
          },
          'the field is the empty string': const {
            'user_id': 'u-me',
            'sheet_version': 2,
            'sealed_rk_blob': '',
            'created_at': 5,
          },
          'the field is not base64url': const {
            'user_id': 'u-me',
            'sheet_version': 2,
            'sealed_rk_blob': 'not %% base64url at all',
            'created_at': 5,
          },
        };

        for (final entry in bodies.entries) {
          final wire = RecoverySheetWire.fromJson(entry.value);
          expect(
            wire.blob,
            isEmpty,
            reason: '${entry.key}: the decoder really does yield zero bytes',
          );
          final api = _Recovery(blob: wire);
          final offer = await recoverySheetProbe(api)();
          expect(
            offer.availability,
            RecoveryRungAvailability.unknown,
            reason:
                '${entry.key} — offering a sheet nothing could read '
                'spends the one attempt they steeled themselves for',
          );
          expect(
            offer.blocked,
            isNull,
            reason: '${entry.key} is not the server saying `no_sheet` either',
          );
          expect(api.sheetReads, 1, reason: 'the route was really asked');
        }

        // A field of the wrong TYPE does not decode at all: `fromJson` throws
        // on the cast (recovery_api.dart:414) rather than inventing bytes,
        // and that is left as it is — `HttpRecoverySheet.submit` reads the
        // same wire, and a blob silently emptied there could reach R2.4 as
        // "that code did not work". The end state on S11.6 is the same one,
        // because the ladder's single conversion turns ANY throw out of the
        // sheet read — not only a `RecoveryApiFailure` — into unknown.
        expect(
          () => RecoverySheetWire.fromJson(const {
            'user_id': 'u-me',
            'sheet_version': 2,
            'sealed_rk_blob': 42,
            'created_at': 5,
          }),
          throwsA(isA<TypeError>()),
        );
        final ladder = LiveRecoveryLadder(
          probes: {
            RecoveryRung.recoverySheet: recoverySheetProbe(
              _Recovery(throws: StateError('a body this build cannot read')),
            ),
          },
        );
        expect(
          _offerFor(
            await ladder.rungs(),
            RecoveryRung.recoverySheet,
          ).availability,
          RecoveryRungAvailability.unknown,
        );

        // And a real sealed blob — never zero bytes for an XChaCha20 sheet
        // (04 §7.4 🔒) — is still the rung, so nothing true was denied.
        expect(
          (await recoverySheetProbe(
            _Recovery(
              blob: RecoverySheetWire.fromJson(const {
                'user_id': 'u-me',
                'sheet_version': 2,
                'sealed_rk_blob': 'AQID',
                'created_at': 5,
              }),
            ),
          )()).isAvailable,
          isTrue,
        );
      },
    );

    test(
      'F1-06-65 a refusal is unknown, NOT "no sheet" — offline or unauthorized '
      'learned nothing, and denying a sheet somebody holds ends the attempt',
      () async {
        for (final refusal in [
          RecoveryRefusal.offline,
          RecoveryRefusal.unauthorized,
          RecoveryRefusal.flood,
          RecoveryRefusal.server,
          RecoveryRefusal.upgradeRequired,
        ]) {
          final probe = recoverySheetProbe(
            _Recovery(throws: RecoveryApiFailure(refusal)),
          );
          final ladder = LiveRecoveryLadder(
            probes: {RecoveryRung.recoverySheet: probe},
          );
          final offer = _offerFor(
            await ladder.rungs(),
            RecoveryRung.recoverySheet,
          );
          expect(
            offer.availability,
            RecoveryRungAvailability.unknown,
            reason: '${refusal.name} must not read as "no sheet"',
          );
        }
      },
    );
  });

  group('rung 0 — platform key sync (04 §7.0 🔒, §7.1)', () {
    test('F1-06-66 the wrapped UMK present is the rung, and the probe never '
        'reads an item to find out', () async {
      final keys = _Keys(present: {KeyIds.wrappedUmk});
      final offer = await platformKeySyncProbe(keys)();
      expect(offer.isAvailable, isTrue);
    });

    test(
      'F1-06-67 04 §7.1: device keys intact on the same phone is the remnant, '
      'and it counts',
      () async {
        final keys = _Keys(present: {KeyIds.deviceSigningKey});
        expect((await platformKeySyncProbe(keys)()).isAvailable, isTrue);
      },
    );

    test('F1-06-68 an empty store is a source saying no', () async {
      final offer = await platformKeySyncProbe(_Keys())();
      expect(offer.isBlocked, isTrue);
      expect(offer.isUnknown, isFalse);
    });

    test(
      'F1-06-69 a store that could not answer is unknown, not "nothing here"',
      () async {
        final ladder = LiveRecoveryLadder(
          probes: {
            RecoveryRung.platformKeySync: platformKeySyncProbe(
              _Keys(throwsOn: KeyIds.wrappedUmk),
            ),
          },
        );
        expect(
          _offerFor(
            await ladder.rungs(),
            RecoveryRung.platformKeySync,
          ).availability,
          RecoveryRungAvailability.unknown,
        );
      },
    );

    test('F1-06-87 the SECOND question failing is unknown too — a store that '
        'said no to the wrapped UMK and then threw on the device key has not '
        'established §7.1\'s remnant is absent', () async {
      // F1-06-69 fails on the first `contains`; this one gets past it, so
      // a probe that swallowed the remnant branch's error and fell through
      // to `blocked` would pass there and fail here.
      final keys = _Keys(throwsOn: KeyIds.deviceSigningKey);
      final ladder = LiveRecoveryLadder(
        probes: {RecoveryRung.platformKeySync: platformKeySyncProbe(keys)},
      );
      final offer = _offerFor(
        await ladder.rungs(),
        RecoveryRung.platformKeySync,
      );
      expect(offer.availability, RecoveryRungAvailability.unknown);
      expect(offer.blocked, isNull);
    });
  });

  group('rung 2 — trusted members (04 §7.3)', () {
    test('F1-06-70 an empty history is UNKNOWN, never "nobody to ask" — the '
        'meta pull\'s `guardian_sets` is RLS-gated on rf.is_certified() '
        '(0005:357) and the phone at S11.6 is uncertified by construction, so '
        '[] is a read it was filtered out of, not an answer', () async {
      final offer = await trustedMembersProbe(_Guardians())();
      expect(offer.availability, RecoveryRungAvailability.unknown);
      expect(offer.blocked, isNull, reason: 'no reason is true here');
      expect(offer.isAvailable, isFalse, reason: 'and it is not a yes');
    });

    test('F1-06-71 the set in force is the HIGHEST share_set_version, whatever '
        'order the history arrives in — an earlier generation describes people '
        'who no longer hold a share', () async {
      // v3 is the set in force and this build cannot read it (n below the
      // 0010 floor); v1 and v2 look fine and must not rescue it. Three
      // outcomes are distinguishable here, which is what makes the test
      // sharp: reading v1 would say `available`, and only reading v3 says
      // `unknown`.
      final api = _Guardians(
        history: [
          _set(version: 1),
          _set(version: 3, n: 1, k: 1),
          _set(version: 2),
        ],
      );
      final offer = await trustedMembersProbe(api)();
      expect(offer.availability, RecoveryRungAvailability.unknown);
      expect(offer.isAvailable, isFalse, reason: 'v1 must not rescue v3');
    });

    test(
      'F1-06-84 a set row this build cannot read is UNKNOWN, never "you set '
      'nobody up": an absent `k` decodes to 0 (guardians_api.dart:157) and a '
      'person with five trusted members would have been told they had none',
      () async {
        // The body carried a subject, a version, an n and the members — the
        // one thing it establishes is that a set EXISTS. Only `k` is
        // unreadable, and no reading of that makes "setup never happened"
        // true.
        final row = GuardianSetWire.fromJson(const {
          'subject_user_id': 'u-me',
          'share_set_version': 4,
          'n': 3,
          'guardian_user_ids': ['g0', 'g1', 'g2'],
        });
        expect(row.k, 0, reason: 'the decoder really does default k to 0');
        expect(row.n, 3);
        expect(row.members, hasLength(3), reason: 'a set plainly exists');

        final offer = await trustedMembersProbe(
          _Guardians(history: [row]),
          subjectUserId: 'u-me',
        )();
        expect(offer.availability, RecoveryRungAvailability.unknown);
        expect(offer.blocked, isNull, reason: 'no reason is true here');
      },
    );

    test('F1-06-85 a published set this build CAN read is the only case that '
        'reads as available: n at both ends of 0010\'s 2..5 with the k the '
        'trigger stored, and nothing else on this probe is a yes', () async {
      // The empty case used to assert `blocked` here. It does not any more
      // — see F1-06-70 and F1-06-92 — and the assertion is corrected
      // rather than deleted, because "what may read as available" is the
      // half of this test that was always load-bearing.
      final empty = await trustedMembersProbe(_Guardians())();
      expect(empty.isAvailable, isFalse);
      expect(empty.blocked, isNull);

      // n at both ends of 0010's 2..5, with the k the trigger stores.
      for (final (n, k) in const [(2, 2), (3, 2), (4, 3), (5, 3)]) {
        final offer = await trustedMembersProbe(
          _Guardians(
            history: [_set(version: 1, n: n, k: k)],
          ),
        )();
        expect(
          offer.isAvailable,
          isTrue,
          reason: 'a published $k-of-$n set is the rung',
        );
      }
    });

    test('F1-06-86 an unreachable `guardian_sets` is unknown, and the probe is '
        'really the thing that was asked — a ladder that never called it would '
        'read zero', () async {
      final api = _Guardians(throws: StateError('meta pull failed'));
      final ladder = LiveRecoveryLadder(
        probes: {RecoveryRung.trustedMembers: trustedMembersProbe(api)},
      );
      expect(
        _offerFor(
          await ladder.rungs(),
          RecoveryRung.trustedMembers,
        ).availability,
        RecoveryRungAvailability.unknown,
      );
      expect(api.reads, 1, reason: 'the source was actually consulted');
    });

    test('F1-06-72 a published 2-of-3 set is the rung', () async {
      final api = _Guardians(history: [_set(version: 1), _set(version: 2)]);
      expect((await trustedMembersProbe(api)()).isAvailable, isTrue);
    });

    test('F1-06-73 a set this user is only a GUARDIAN of never reads as "you '
        'have trusted members" when the subject is known — and what is left '
        'after the filter is unknown, not a denial', () async {
      final api = _Guardians(
        history: [
          const GuardianSetWire(
            subjectUserId: 'u-somebody-else',
            shareSetVersion: 9,
            k: 2,
            n: 3,
          ),
        ],
      );
      final offer = await trustedMembersProbe(api, subjectUserId: 'u-me')();
      expect(offer.isAvailable, isFalse, reason: 'the rung is NOT offered');
      expect(offer.availability, RecoveryRungAvailability.unknown);
      expect(
        offer.blocked,
        isNull,
        reason:
            'somebody else\'s set is not '
            'evidence about this user\'s own, either way',
      );
    });

    test('F1-06-92 `noTrustedMembers` is UNREACHABLE from the live probe, and '
        'that is the point: an uncertified phone cannot tell an empty '
        'set-history from one RLS filtered it out of, so it never says "you '
        'set nobody up" to somebody who has five', () async {
      // The three shapes a `200 {guardian_sets: …}` can take on the one
      // screen this probe is drawn on. `guardian_sets_select`
      // (0005_rls_and_grants.sql:357) is gated on `rf.is_certified()`, the
      // phone at S11.6 holds nothing but its own keys (0010:134, ADR
      // 2026-09-05d §2 🔒), and RLS filters rather than errors — so all
      // three reach this probe as a body with nothing in it for this user.
      final bodies = <String, _Guardians>{
        'the route answered with no rows at all': _Guardians(),
        'rows, none of them this user\'s': _Guardians(
          history: [
            const GuardianSetWire(
              subjectUserId: 'u-somebody-else',
              shareSetVersion: 3,
              k: 2,
              n: 3,
            ),
          ],
        ),
        'a row whose subject this build could not match': _Guardians(
          history: [
            // `subject_user_id` absent decodes to '' (guardians_api:154),
            // so the filter drops it — and a row that named nobody is not
            // this user saying they set nobody up.
            GuardianSetWire.fromJson(const {
              'share_set_version': 2,
              'k': 2,
              'n': 3,
            }),
          ],
        ),
      };

      for (final entry in bodies.entries) {
        final offer = await trustedMembersProbe(
          entry.value,
          subjectUserId: 'u-me',
        )();
        expect(
          offer.blocked,
          isNull,
          reason: '${entry.key} is not the server refusing rung 2',
        );
        expect(
          offer.availability,
          RecoveryRungAvailability.unknown,
          reason: entry.key,
        );
        expect(entry.value.reads, 1, reason: 'the source was consulted');
      }

      // Stated as the property, not as three examples: no input this probe
      // can be handed produces the false denial. The ONE thing it still
      // says yes to is a readable set of this user's own.
      final yes = await trustedMembersProbe(
        _Guardians(history: [_set(version: 7)]),
        subjectUserId: 'u-me',
      )();
      expect(yes.isAvailable, isTrue);
    });
  });

  group('rung 1 — another of your own devices (04 §7.2)', () {
    test(
      'F1-06-74 only a certified device that is not this one counts: a '
      'suspended, revoked or uncertified phone will refuse to link',
      () async {
        for (final status in [
          DeviceStatus.suspended,
          DeviceStatus.revoked,
          DeviceStatus.uncertified,
        ]) {
          final devices = _Devices(
            snapshot: DevicesSnapshot(
              devices: [
                _device(id: 'me', isThis: true),
                _device(id: 'other', status: status),
              ],
            ),
          );
          final offer = await anotherDeviceProbe(devices)();
          expect(
            offer.blocked,
            RecoveryRungBlocked.noOtherDevice,
            reason: 'a ${status.name} device is not a phone to link from',
          );
        }
      },
    );

    test('F1-06-75 one other certified phone is the rung', () async {
      final devices = _Devices(
        snapshot: DevicesSnapshot(
          devices: [
            _device(id: 'me', isThis: true),
            _device(id: 'other'),
          ],
        ),
      );
      expect((await anotherDeviceProbe(devices)()).isAvailable, isTrue);
      expect(devices.refreshes, 1, reason: 'a stale list is not an answer');
    });

    test(
      'F1-06-76 this device alone is not another device, however certified',
      () async {
        final devices = _Devices(
          snapshot: DevicesSnapshot(devices: [_device(id: 'me', isThis: true)]),
        );
        expect(
          (await anotherDeviceProbe(devices)()).blocked,
          RecoveryRungBlocked.noOtherDevice,
        );
      },
    );

    test('F1-06-88 a refresh that succeeded and left NOTHING behind told us '
        'nothing: unknown, never "you have no other phone"', () async {
      // The mirror of F1-06-77. A repository with no snapshot has not
      // denied the rung — a person holding a second certified phone would
      // be told they had none, which is the false denial the third state
      // exists to prevent.
      final devices = _Devices();
      final offer = await anotherDeviceProbe(devices)();
      expect(offer.availability, RecoveryRungAvailability.unknown);
      expect(offer.blocked, isNull, reason: 'no reason is true here');
      expect(devices.refreshes, 1, reason: 'it did ask');
    });

    test(
      'F1-06-77 a refresh that failed is unknown even with a cached snapshot: '
      'the cached list cannot establish that the device is certified NOW',
      () async {
        final devices = _Devices(
          snapshot: DevicesSnapshot(
            devices: [
              _device(id: 'me', isThis: true),
              _device(id: 'other'),
            ],
          ),
          refreshThrows: true,
        );
        final ladder = LiveRecoveryLadder(
          probes: {RecoveryRung.anotherDevice: anotherDeviceProbe(devices)},
        );
        expect(
          _offerFor(
            await ladder.rungs(),
            RecoveryRung.anotherDevice,
          ).availability,
          RecoveryRungAvailability.unknown,
        );
      },
    );
  });

  group('progress', () {
    test(
      'F1-06-78 a rung with no progress source reports nothing rather than a '
      'reading it does not have — S11.5 reads that as "did not get there"',
      () async {
        const ladder = LiveRecoveryLadder(probes: {});
        expect(
          await ladder.progressOf(RecoveryRung.platformKeySync).toList(),
          isEmpty,
        );
      },
    );
  });

  group('the production ladder — what the composition root installs', () {
    test(
      'F1-06-89 the ladder `bootstrap()` builds answers rungs 0, 2 and 3 from '
      'their real sources and reports rung 1 UNKNOWN — it has no producer in '
      'this build and will not offer a phone the person may not have',
      () async {
        final ladder = buildRecoveryLadder(
          keys: _Keys(present: {KeyIds.wrappedUmk}),
          guardians: _Guardians(history: [_set(version: 1)]),
          recovery: _Recovery(blob: _wire()),
        );
        // Not the fake — that swap is the whole point of the slice, and the
        // fake offers every fork rung as available whether it is or not.
        expect(ladder, isA<LiveRecoveryLadder>());
        expect(ladder, isNot(isA<FakeRecoveryLadder>()));

        final offers = await ladder.rungs();
        expect(
          _offerFor(offers, RecoveryRung.platformKeySync).isAvailable,
          isTrue,
          reason: 'the key store was asked',
        );
        expect(
          _offerFor(offers, RecoveryRung.trustedMembers).isAvailable,
          isTrue,
          reason: 'guardian_sets was asked',
        );
        expect(
          _offerFor(offers, RecoveryRung.recoverySheet).isAvailable,
          isTrue,
          reason: 'recovery/sheet was asked',
        );
        // The one this build cannot answer. It is neither offered nor denied,
        // and a probe added later changes this line and nothing else.
        final rung1 = _offerFor(offers, RecoveryRung.anotherDevice);
        expect(rung1.availability, RecoveryRungAvailability.unknown);
        expect(rung1.isAvailable, isFalse);
        expect(rung1.blocked, isNull, reason: '04 §7.2 was never asked');
      },
    );

    test(
      'F1-06-90 every source refusing still yields four offers and no throw: '
      'a locked-out person never meets a whole-screen error in place of the '
      'rungs that did answer',
      () async {
        final ladder = buildRecoveryLadder(
          keys: _Keys(throwsOn: KeyIds.wrappedUmk),
          guardians: _Guardians(throws: StateError('offline')),
          recovery: _Recovery(
            throws: const RecoveryApiFailure(RecoveryRefusal.offline),
          ),
        );
        final offers = await ladder.rungs();
        expect(offers, hasLength(RecoveryRung.values.length));
        for (final o in offers) {
          expect(
            o.availability,
            RecoveryRungAvailability.unknown,
            reason: '${o.rung.name} must not default either way',
          );
        }
      },
    );

    testWidgets(
      'F1-06-91 the composition root installs it: `RecoveryLadderScope` hands '
      'the live ladder down and a screen never reads `FakeRecoveryLadder` in '
      'production',
      (tester) async {
        final ladder = buildRecoveryLadder(
          keys: _Keys(),
          guardians: _Guardians(),
          recovery: _Recovery(),
        );
        RecoveryLadder? seen;
        await tester.pumpWidget(
          RecoveryLadderScope(
            ladder: ladder,
            child: Builder(
              builder: (context) {
                seen = RecoveryLadderScope.maybeOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(seen, same(ladder));
        expect(seen, isNot(isA<FakeRecoveryLadder>()));

        // And the root really does the installing. S11.6 fell back to the
        // seam's fake for as long as the scope was absent (07 §1 rule 6 — a
        // missing scope is never a red screen), so "the widget reads the
        // scope" is only half the fact; the other half is a line in
        // `bootstrap.dart`, and it is the half that was missing.
        final root = _bootstrapCode();
        // The binding, not the co-occurrence. A root that called
        // `buildRecoveryLadder` into a local it then ignored and handed the
        // scope some other ladder used to keep this test green — two
        // `contains` that never met each other. So the identifier is read off
        // the build and compared with the one the scope is actually given.
        final built = RegExp(r'final\s+(\w+)\s*=\s*buildRecoveryLadder\(')
            .allMatches(root)
            .toList();
        expect(
          built,
          hasLength(1),
          reason: 'the root builds the live ladder, once',
        );
        final installed = RegExp(r'RecoveryLadderScope\(\s*ladder:\s*(\w+)\s*,')
            .allMatches(root)
            .toList();
        expect(
          installed,
          hasLength(1),
          reason:
              'and installs a ladder it names — an inline '
              '`ladder: SomeLadder()` would not match, which is the point',
        );
        expect(
          installed.single.group(1),
          built.single.group(1),
          reason:
              'the ladder handed to the scope is THE one '
              '`buildRecoveryLadder` returned',
        );
        expect(
          root,
          isNot(contains('FakeRecoveryLadder')),
          reason:
              'the root must never CONSTRUCT the fake — comments about '
              'why it does not are fine, a construction is not',
        );
        // The stripper really is doing something, so this test cannot pass
        // because it read an empty string or lost the code with the prose.
        expect(
          root,
          contains('Future<void> bootstrap() async {'),
          reason: 'the code survived the strip',
        );
      },
    );

    test('F1-06-94 `progress` is installed if it is given and empty if it is '
        'not: production passes none, so `progressOf` closes at once and S11.5 '
        'reads that as "this rung did not get there" rather than counting '
        'books nothing restored', () async {
      // What production does today, stated so a producer landing later has
      // to change this line deliberately.
      final bare = buildRecoveryLadder(
        keys: _Keys(present: {KeyIds.wrappedUmk}),
        guardians: _Guardians(),
        recovery: _Recovery(),
      );
      expect(
        await bare.progressOf(RecoveryRung.platformKeySync).toList(),
        isEmpty,
        reason: 'no restore driver exists in this build',
      );

      // And the seam is really a seam: what is passed is what S11.5 gets,
      // unit and counts intact (11 §4.5 🔒 — a count, never a percentage).
      const readings = [
        RecoveryProgress(done: 1, total: 5, unit: RecoveryUnit.books),
        RecoveryProgress(
          done: 5,
          total: 5,
          unit: RecoveryUnit.books,
          finished: true,
        ),
      ];
      final asked = <RecoveryRung>[];
      final wired = buildRecoveryLadder(
        keys: _Keys(),
        guardians: _Guardians(),
        recovery: _Recovery(),
        progress: (rung) {
          asked.add(rung);
          return Stream.fromIterable(readings);
        },
      );
      expect(
        await wired.progressOf(RecoveryRung.platformKeySync).toList(),
        readings,
      );
      expect(asked, [RecoveryRung.platformKeySync]);
    });
  });

  group('rung 3 — the checksum is real (04 §7.4 🔒)', () {
    RecoverySheetCode code(String s) => RecoverySheetCode.parse(s)!;

    test(
      'F1-06-79 a code the precheck refuses is rejected WITHOUT spending the '
      'rate-limited recovery/sheet route',
      () async {
        final api = _Recovery(
          blob: RecoverySheetWire(
            userId: 'u',
            sheetVersion: 1,
            blob: Uint8List(4),
            createdAtMs: 1,
          ),
        );
        var opened = 0;
        final sheet = HttpRecoverySheet(
          api: api,
          precheck: (_) => false,
          opener: (_, _) async {
            opened++;
            return true;
          },
        );

        await expectLater(
          sheet.submit(code('ABCD-EFGH')),
          throwsA(isA<RecoverySheetRejected>()),
        );
        expect(api.sheetReads, 0, reason: 'no fetch was spent');
        expect(opened, 0);
      },
    );

    test('F1-06-80 a code the precheck accepts still goes to the AEAD, which '
        'remains the second and final verdict', () async {
      final api = _Recovery(
        blob: RecoverySheetWire(
          userId: 'u',
          sheetVersion: 1,
          blob: Uint8List(4),
          createdAtMs: 1,
        ),
      );
      final sheet = HttpRecoverySheet(
        api: api,
        precheck: (_) => true,
        opener: (_, _) async => false, // a sheet reprinted since
      );

      await expectLater(
        sheet.submit(code('ABCD-EFGH')),
        throwsA(isA<RecoverySheetRejected>()),
      );
      expect(api.sheetReads, 1);
    });

    test('F1-06-81 a precheck that could not run is not a verdict: the code is '
        'still worth trying', () async {
      final api = _Recovery(
        blob: RecoverySheetWire(
          userId: 'u',
          sheetVersion: 1,
          blob: Uint8List(4),
          createdAtMs: 1,
        ),
      );
      final sheet = HttpRecoverySheet(
        api: api,
        precheck: (_) => throw StateError('suite not ready'),
        opener: (_, _) async => true,
      );

      expect(sheet.isWorthTrying(code('ABCD')), isTrue);
      await sheet.submit(code('ABCD-EFGH'));
      expect(api.sheetReads, 1);
    });

    test('F1-06-82 with no precheck installed nothing is refused early — the '
        'behaviour before this slice is unchanged', () async {
      final api = _Recovery(
        blob: RecoverySheetWire(
          userId: 'u',
          sheetVersion: 1,
          blob: Uint8List(4),
          createdAtMs: 1,
        ),
      );
      final sheet = HttpRecoverySheet(api: api, opener: (_, _) async => true);
      expect(sheet.isWorthTrying(code('ABCD')), isTrue);
      await sheet.submit(code('ABCD-EFGH'));
      expect(api.sheetReads, 1);
    });

    test(
      'F1-06-83 the precheck runs before the fetch even when the route would '
      'have refused: a mistype is never reported as a server problem',
      () async {
        final api = _Recovery(
          throws: const RecoveryApiFailure(RecoveryRefusal.offline),
        );
        final sheet = HttpRecoverySheet(
          api: api,
          precheck: (_) => false,
          opener: (_, _) async => true,
        );
        await expectLater(
          sheet.submit(code('ABCD-EFGH')),
          throwsA(isA<RecoverySheetRejected>()),
        );
        expect(api.sheetReads, 0);
      },
    );
  });
}
