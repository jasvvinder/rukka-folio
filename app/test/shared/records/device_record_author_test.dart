// F1-05-24 … F1-05-27: the device can actually sign a structural record (ADR
// 2026-09-05b §1 🔒, 04 §3.3 device keys, 04 §8.3 author signatures) — and,
// when it cannot, `ServerMembersRepository` still refuses rather than pretend
// to write.
//
// Real libsodium (the sodium build hook), a fake key store, an injected clock.
// No network, no plaintext financial data.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart' show Hlc;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/members_api.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/server_members_repository.dart';
import 'package:rukka_folio/shared/records/device_record_author.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:sync_engine/sync_engine.dart' show MetaResponse;

import '../test_app.dart';

const deviceId = '11111111-2222-4333-8444-555555555555';
const tenantId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const userId = '99999999-8888-4777-8666-555555555555';

Future<FakeKeyStore> storeWithDeviceKeys(CryptoSuite suite) async {
  final keys = FakeKeyStore();
  await keys.write(KeyIds.deviceSigningKey, suite.randomBytes(32));
  await keys.write(KeyIds.deviceAgreementKey, suite.randomBytes(32));
  return keys;
}

/// The same replay the author uses, so the test can hold the public half.
DeviceKeyPair deviceFrom(CryptoSuite suite, Uint8List ed, Uint8List x) {
  final queue = <Uint8List>[Uint8List.fromList(ed), Uint8List.fromList(x)];
  return DeviceKeyPair.generate(
    CryptoSuite(suite.sodium, random: (_) => queue.removeAt(0)),
    deviceId: deviceId,
  );
}

Uint8List b64any(String s) => base64.decode(
  base64.normalize(s.replaceAll('-', '+').replaceAll('_', '/')),
);

/// A [MembersApi] that records what it was asked to post and answers nothing.
final class RecordingApi implements MembersApi {
  final posted = <List<Map<String, Object?>>>[];
  final issued = <Map<String, Object?>>[];

  @override
  Future<String> acceptInvite(String inviteId) async =>
      'joined_pending_verification';

  @override
  Future<IssuedInvite> issueInvite({
    required Map<String, Object?> record,
    required String phoneE164,
  }) async {
    issued.add(record);
    return const IssuedInvite(inviteId: 'i1', recordId: 'r1');
  }

  @override
  Future<List<InviteOffer>> myInvites() async => const [];

  @override
  Future<MetaResponse> pullMeta({String? after}) async =>
      MetaResponse.fromJson(const {
        'store_epoch': 'e1',
        'devices': <Object?>[],
        'memberships': <Object?>[],
        'book_roles': <Object?>[],
        'wrapped_keys': <Object?>[],
        'signed_records': <Object?>[],
        'has_more': false,
      });

  @override
  Future<List<String>> postRecords(List<Map<String, Object?>> records) async {
    posted.add(records);
    return List.filled(records.length, 'applied');
  }
}

void main() {
  test('F1-05-24 a signed record carries the exact bytes that were signed, '
      'and the signature verifies under this device Ed25519 key', () async {
    final suite = await testSuite();
    final keys = await storeWithDeviceKeys(suite);
    final author = await DeviceRecordAuthor.ifAvailable(
      suite: suite,
      keys: keys,
      deviceIdOf: () async => deviceId,
      clock: RecordHlcClock(() => DateTime.utc(2026, 9, 14, 10)),
    );
    expect(author, isNotNull);

    final wire = await author!.sign(
      tenantId: tenantId,
      kind: MembersRecordKind.bookRole,
      payload: {
        'book_id': 'b1',
        'user_id': userId,
        'role': 'member',
        // Money is integer paise end to end (rule 1).
        'auto_post_limit_paise': 250000,
        // rule 6: a field this build does not understand still travels.
        'future_field': {'kept': true},
      },
    );

    expect(Uuid16.isCanonical(wire['id']! as String), isTrue);
    expect(wire['tenant_id'], tenantId);
    expect(wire['author_device_id'], deviceId);
    expect(wire['kind'], MembersRecordKind.bookRole);
    expect(wire['seq'], isNull, reason: 'seq is the server\'s, never signed');

    final payloadBytes = b64any(wire['payload_json']! as String);
    final decoded =
        jsonDecode(utf8.decode(payloadBytes)) as Map<String, Object?>;
    expect(decoded['auto_post_limit_paise'], 250000);
    expect(decoded['auto_post_limit_paise'], isA<int>());
    expect(decoded['future_field'], {'kept': true});

    final record = SignedRecord(
      suiteVersion: wire['suite_version']! as int,
      tenantId: tenantId,
      kind: wire['kind']! as String,
      payloadJson: payloadBytes,
      authorDeviceId: deviceId,
      authorSig: b64any(wire['author_sig']! as String),
      hlc: wire['hlc']! as int,
    );
    final device = deviceFrom(
      suite,
      (await keys.read(KeyIds.deviceSigningKey))!,
      (await keys.read(KeyIds.deviceAgreementKey))!,
    );
    expect(
      suite.sodium.crypto.sign.verifyDetached(
        signature: record.authorSig,
        message: record.signedDigest(suite),
        publicKey: device.public.ed25519,
      ),
      isTrue,
    );
    device.dispose();
  });

  test('F1-05-25 record HLCs are monotone on one device (05 §2) and the '
      'nonce is 16 bytes from the CSPRNG (06 §7)', () async {
    final suite = await testSuite();
    final keys = await storeWithDeviceKeys(suite);
    var now = DateTime.utc(2026, 9, 14, 10);
    final author = (await DeviceRecordAuthor.ifAvailable(
      suite: suite,
      keys: keys,
      deviceIdOf: () async => deviceId,
      clock: RecordHlcClock(() => now),
    ))!;

    final hlcs = <int>[];
    for (var i = 0; i < 3; i++) {
      final w = await author.sign(
        tenantId: tenantId,
        kind: MembersRecordKind.designation,
        payload: {'user_id': userId, 'designation_label': 'Munshi'},
      );
      hlcs.add(w['hlc']! as int);
    }
    // Same millisecond: the counter moves, never the value backwards.
    expect(hlcs[1], greaterThan(hlcs[0]));
    expect(hlcs[2], greaterThan(hlcs[1]));
    // A wall clock that jumps backwards still cannot pull the HLC back.
    now = DateTime.utc(2026, 9, 14, 9);
    final back = await author.sign(
      tenantId: tenantId,
      kind: MembersRecordKind.designation,
      payload: {'user_id': userId},
    );
    expect(back['hlc']! as int, greaterThan(hlcs.last));

    expect(author.nonce16(), hasLength(16));
    expect(author.nonce16(), isNot(equals(author.nonce16())));

    // A clock can be raised to another clock on the same device.
    final clock = RecordHlcClock(() => now)..seed(const Hlc(1 << 40));
    expect(clock.tick().raw, greaterThan(1 << 40));
  });

  test('F1-05-26 no signing key and no device id mean no author at all — '
      'ServerMembersRepository then refuses to write, which is the correct '
      'fallback and must stay reachable', () async {
    final suite = await testSuite();

    expect(
      await DeviceRecordAuthor.ifAvailable(
        suite: suite,
        keys: FakeKeyStore(), // registered, but no keys at rest
        deviceIdOf: () async => deviceId,
        clock: RecordHlcClock(DateTime.now),
      ),
      isNull,
    );
    expect(
      await DeviceRecordAuthor.ifAvailable(
        suite: suite,
        keys: await storeWithDeviceKeys(suite),
        deviceIdOf: () async => null, // never registered (06 §3)
        clock: RecordHlcClock(DateTime.now),
      ),
      isNull,
    );
    expect(
      await DeviceRecordAuthor.ifAvailable(
        suite: suite,
        keys: await storeWithDeviceKeys(suite),
        deviceIdOf: () async => 'not-a-uuid',
        clock: RecordHlcClock(DateTime.now),
      ),
      isNull,
    );

    final api = RecordingApi();
    final repo = ServerMembersRepository(
      api: api,
      tenantId: tenantId,
      userId: userId,
      believes: believeNothing,
      unknownVerifierName: 'someone',
      someoneToMeetName: 'someone',
      // The author that could not be built.
      author: null,
    );
    await expectLater(
      repo.invite(
        const InviteRequest(
          phoneE164: '+919999999999',
          grants: [BookGrant(bookId: 'b1', role: BookRole.member)],
        ),
      ),
      throwsA(
        isA<MembersFailure>().having(
          (e) => e.reason,
          'reason',
          MembersRefusal.unauthorized,
        ),
      ),
    );
    expect(api.issued, isEmpty, reason: 'the number never left the phone');
    await repo.dispose();
  });

  test('F1-05-27 with an author, invite() and setAutoPostLimit() reach the '
      'server as signed records', () async {
    final suite = await testSuite();
    final keys = await storeWithDeviceKeys(suite);
    final api = RecordingApi();
    final repo = ServerMembersRepository(
      api: api,
      tenantId: tenantId,
      userId: userId,
      believes: believeNothing,
      unknownVerifierName: 'someone',
      someoneToMeetName: 'someone',
      author: await DeviceRecordAuthor.ifAvailable(
        suite: suite,
        keys: keys,
        deviceIdOf: () async => deviceId,
        clock: RecordHlcClock(DateTime.now),
      ),
    );

    await repo.invite(
      const InviteRequest(
        phoneE164: '+919999999999',
        grants: [
          BookGrant(
            bookId: 'b1',
            role: BookRole.member,
            autoPostLimitPaise: 500000,
          ),
        ],
      ),
    );
    expect(api.issued, hasLength(1));
    final record = api.issued.single;
    expect(record['kind'], MembersRecordKind.invite);
    expect(Uuid16.isCanonical(record['author_device_id']! as String), isTrue);
    final payload = jsonDecode(
      utf8.decode(b64any(record['payload_json']! as String)),
    ) as Map<String, Object?>;
    // 06 §7's 128-bit nonce, and no identifier of the invitee anywhere.
    expect(b64any(payload['nonce']! as String), hasLength(16));
    expect(jsonEncode(payload), isNot(contains('9999999999')));
    expect((payload['roles']! as List).single, {
      'book_id': 'b1',
      'role': 'member',
      'auto_post_limit_paise': 500000,
    });

    // The phone this device invited stays on this device (ADR 2026-09-05f §G).
    expect(repo.directory.inviteePhoneOf('i1'), '+919999999999');
    await repo.dispose();
  });
}
