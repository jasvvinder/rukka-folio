// Suite D — wire types (05 §3–§5) round-trip byte-for-byte and preserve the
// tables this build does not read (rule 6).
@Tags(['D'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

Uint8List _bytes(int n, [int seed = 7]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xff));

Map<String, Object?> _viaJson(Map<String, Object?> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, Object?>;

void main() {
  final env = WireEnvelope(
    envelopeId: 'e1',
    seq: 42,
    tenantId: 't1',
    bookId: 'b1',
    objectId: 'o1',
    objectType: 'entry',
    keyVersion: 2,
    suiteVersion: 1,
    payloadSchema: 1,
    authorDevice: 'd1',
    hlc: 123456789,
    blobHash: _bytes(32),
    blob: _bytes(140, 3),
  );

  test('D-05-7 push/pull/meta wire types round-trip through JSON with the '
      'field names 05 spells; unknown meta tables are preserved', () {
    final e2 = WireEnvelope.fromJson(_viaJson(env.toJson()));
    expect(e2.toJson(), env.toJson());
    expect(
      env.toJson().keys,
      containsAll([
        'envelope_id',
        'seq',
        'tenant_id',
        'book_id',
        'object_id',
        'object_type',
        'key_version',
        'suite_version',
        'payload_schema',
        'author_device',
        'hlc',
        'blob_hash',
        'size',
        'blob',
      ]),
    );
    expect(env.toJson()['size'], 140);

    final push = PushRequest(envelopes: [env, env.withSeq(43)]);
    expect(
      PushRequest.fromJson(_viaJson(push.toJson())).toJson(),
      push.toJson(),
    );

    final pushRes = PushResponse(
      storeEpoch: 'ep',
      results: const [
        PushResult(envelopeId: 'e1', result: PushOutcome.acked, seq: 42),
        PushResult(
          envelopeId: 'e2',
          result: PushOutcome.rejectedRateLimited,
          retryAfterMs: 60000,
        ),
        PushResult(
          envelopeId: 'e3',
          result: PushOutcome.rejectedShape,
          check: 'blob_hash',
        ),
      ],
    );
    expect(
      PushResponse.fromJson(_viaJson(pushRes.toJson())).toJson(),
      pushRes.toJson(),
    );

    const pull = PullRequest(bookId: 'b1', afterSeq: 10, fy: '2024-25');
    expect(
      PullRequest.fromJson(_viaJson(pull.toJson())).toJson(),
      pull.toJson(),
    );
    expect(pull.toJson()['after_seq'], 10);
    final pullRes = PullResponse(
      storeEpoch: 'ep',
      envelopes: [env],
      nextSeq: 42,
    );
    expect(
      PullResponse.fromJson(_viaJson(pullRes.toJson())).toJson(),
      pullRes.toJson(),
    );

    final rec = WireSignedRecord(
      id: 'r1',
      suiteVersion: 1,
      tenantId: 't1',
      kind: 'device_revocation',
      payloadJson: Uint8List.fromList(
        utf8.encode('{"revoked_device_id":"d9"}'),
      ),
      authorDeviceId: 'd1',
      authorSig: _bytes(64),
      hlc: 5,
      seq: 9,
    );
    final key = WireWrappedKey(
      id: 'k1',
      kind: WireWrappedKey.kindBkForUser,
      userId: 'u1',
      bookId: 'b1',
      keyVersion: 2,
      blob: _bytes(80),
      recipientFingerprint: _bytes(32, 9),
    );
    final meta = MetaResponse(
      storeEpoch: 'ep',
      next: '1700000000,abc',
      signedRecords: [rec],
      wrappedKeys: [key],
      devices: [
        WireDevice(
          id: 'd1',
          userId: 'u1',
          pubEd: _bytes(32, 1),
          pubX: _bytes(32, 2),
          status: 'active',
        ),
      ],
      deviceCerts: [
        WireDeviceCert(
          deviceId: 'd1',
          suiteVersion: 1,
          issuedAtMs: 1,
          signature: _bytes(64, 4),
          issuedByDevice: 'd0',
        ),
      ],
      memberships: const [
        WireMembership(
          id: 'm1',
          tenantId: 't1',
          userId: 'u1',
          status: 'active',
        ),
      ],
      bookRoles: const [
        WireBookRole(
          id: 'br1',
          bookId: 'b1',
          userId: 'u1',
          role: 'member',
          limits: {'per_entry_paise': 500000},
        ),
      ],
      guardianSets: const [
        WireGuardianSet(
          subjectUserId: 'u1',
          shareSetVersion: 3,
          k: 2,
          guardianUserIds: ['g1', 'g2', 'g3'],
        ),
      ],
      extra: const {
        'subscriptions': [
          {'id': 's1', 'plan': 'family'},
        ],
        'tombstones': <Object?>[],
      },
    );
    final back = MetaResponse.fromJson(_viaJson(meta.toJson()));
    expect(back.toJson(), meta.toJson());
    expect(back.extra['subscriptions'], meta.extra['subscriptions']);
    expect(back.guardianSets.single.n, 3);
    expect(back.wrappedKeys.single.keyVersion, 2);
    expect(back.signedRecords.single.seq, 9);
    expect(back.isEmpty, isFalse);
    expect(const MetaResponse(storeEpoch: 'x', next: null).isEmpty, isTrue);
  });
}
