// ADR 2026-10-09 ruling 1 🔒 (C-1009-1, app half): the composition root
// builds everything once, before the device keys exist, and every part that
// used to capture a key or an id in a constructor reads it through the
// ledger's late binding instead — the sync engine, its guard and trust
// store, `ServerMembersRepository`, S11.1's roster, `GuardianStandingHost`
// and `DeviceRecordAuthor` (with the `device_added` recorder it signs for).
// Before the keys exist a reader gets an explicit *not registered yet*
// answer; the S0.2 mint and a C-04b-3 re-mint take effect with no relaunch
// for every late-bound part — the ceremony builder too since desk 184 (b),
// so the re-mint arm of review finding KEY168B-2 is gone. The root still
// rebuilds, at the next safe foreground, on `onUmkAdopted` (rung 3).
//
// Behaviour over a real `LocalLedger` (in-memory SQLite, libsodium); the
// root's own wiring through its source, comments stripped — the reading
// F1-24b-3 and the C-04b-2 pins already use. Synthetic ids.
@Tags(['C'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/bootstrap.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart'
    show SessionItems;
import 'package:rukka_folio/features/devices/guardian_standing.dart';
import 'package:rukka_folio/features/members/members_api.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/server_members_repository.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/records/device_added_record.dart';
import 'package:rukka_folio/shared/records/device_record_author.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/sync/guardians_seams.dart';
import 'package:sync_engine/sync_engine.dart' as eng;
import 'package:sync_engine/sync_engine.dart' show MetaResponse;

import '../../shared/test_app.dart';
import '../../shared/ledger/tenant_of.dart';

/// `lib/bootstrap.dart` with `//` comments stripped, so a pin cannot pass on
/// prose that merely names the call.
String _root() {
  for (final path in ['lib/bootstrap.dart', 'app/lib/bootstrap.dart']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final code = [
      for (final line in file.readAsLinesSync())
        line.trimLeft().startsWith('//') ? '' : line,
    ].join('\n');
    expect(code, contains('Future<void> bootstrap() async {'));
    return code;
  }
  fail('bootstrap.dart not found');
}

Future<LocalLedger> _ledger(FakeKeyStore keys) async {
  final l = LocalLedger(
    db: await openTestDb(),
    keys: keys,
    suite: await testSuite(),
    now: testNow,
    requireConfirmedIdentity: true,
  );
  addTearDown(l.dispose);
  await l.openIdentity();
  return l;
}

/// Records the tenant every signature is made for.
final class _TenantAuthor implements MembersRecordAuthor {
  final tenants = <String>[];

  @override
  Uint8List nonce16() => Uint8List(16);

  @override
  Future<Map<String, Object?>> sign({
    required String tenantId,
    required String kind,
    required Map<String, Object?> payload,
  }) async {
    tenants.add(tenantId);
    return {'id': 'r-${tenants.length}', 'tenant_id': tenantId, 'kind': kind};
  }
}

final class _Api implements MembersApi {
  final issued = <Map<String, Object?>>[];

  @override
  Future<MetaResponse> pullMeta({String? after}) async =>
      const MetaResponse(storeEpoch: 'epoch-1', next: null);

  @override
  Future<IssuedInvite> issueInvite({
    required Map<String, Object?> record,
    required String phoneE164,
  }) async {
    issued.add(record);
    return IssuedInvite(inviteId: 'i-1', recordId: record['id']! as String);
  }

  @override
  Future<List<InviteOffer>> myInvites() async => const [];

  @override
  Future<String> acceptInvite(String inviteId) async => 'joined';

  @override
  Future<List<String>> postRecords(List<Map<String, Object?>> records) async =>
      const ['ok'];
}

void main() {
  late FakeKeyStore keys;

  setUp(() => keys = FakeKeyStore());

  group('C-1009-1 the root binds ids and keys late (ADR 2026-10-09 §1)', () {
    test('C-1009-1 the root opens ids only, builds the engine, guard and '
        'trust store over the ledger binding, and captures no key material '
        'and no id in any constructor', () {
      final root = _root();
      expect(root, contains('await ledger.openIdentity();'));
      expect(root, isNot(contains('ledger.bootstrapSolo(')));
      expect(
        RegExp(r'final\s+identity\s*=\s*ledger\.binding\s*;').hasMatch(root),
        isTrue,
      );
      expect(
        RegExp(
          r'final\s+trust\s*=\s*eng\.RecordTrustStore\(\s*'
          r'umks:\s*eng\.BoundUmkSource\(\s*identity\s*\)',
        ).hasMatch(root),
        isTrue,
      );
      expect(
        RegExp(
          r'eng\.SyncEngine\.late\([^;]*guard:\s*eng\.CryptoGuard\.late\(\s*'
          r'suite:\s*suite\s*,\s*trust:\s*trust\s*,\s*material:\s*identity\s*,'
          r'\s*\)\s*,\s*trust:\s*trust\s*,\s*identity:\s*identity\s*,',
        ).hasMatch(root),
        isTrue,
      );
      expect(RegExp(r'eng\.SyncEngine\(').hasMatch(root), isFalse);
      expect(RegExp(r'eng\.CryptoGuard\(').hasMatch(root), isFalse);
      // The key material is only ever read inside a call, never held.
      expect(RegExp(r'=\s*ledger\.keyMaterial\b').hasMatch(root), isFalse);
      expect(
        RegExp(r'\bmaterial\.(device|umk|bookKeys)\b').hasMatch(root),
        isFalse,
      );
      // The ids: read through providers, never as a fixed string.
      expect(
        RegExp(
          r'ServerMembersRepository\([^;]*'
          r'tenantOf:\s*\(\)\s*=>\s*identity\.tenant\.value\s*,\s*'
          r'userIdOf:\s*\(\)\s*=>\s*identity\.userId\.value\s*,',
        ).hasMatch(root),
        isTrue,
      );
      expect(
        RegExp(
          r'GuardianStandingHost\(\s*trust:\s*trust\s*,\s*'
          r'subjectUserIdOf:\s*identity\.userId\s*,',
        ).hasMatch(root),
        isTrue,
      );
      expect(
        RegExp(
          r'roster:\s*\(\)\s*async\s*=>\s*guardianRosterOf\(\s*'
          r'members\.current\s*,\s*tenant:\s*identity\.tenant\.value',
        ).hasMatch(root),
        isTrue,
        reason: 'S11.1 reads the tenant at each save',
      );
      expect(
        RegExp(r'verified:\s*eng\.BoundUmkSource\(\s*identity\s*\)')
            .hasMatch(root),
        isTrue,
      );
      // The record author exists from launch and reads at each signature.
      expect(root, isNot(contains('DeviceRecordAuthor.ifAvailable')));
      expect(
        RegExp(r'final\s+recordAuthor\s*=\s*DeviceRecordAuthor\(')
            .hasMatch(root),
        isTrue,
      );
      expect(
        RegExp(
          r'auth\.announcer\s*=\s*DeviceAddedRecorder\.late\(\s*'
          r'author:\s*recordAuthor\s*,\s*'
          r'tenantOf:\s*\(\)\s*=>\s*identity\.tenant\.value',
        ).hasMatch(root),
        isTrue,
      );
    });

    test('C-1010-2 the root hands the engine\'s membership reads to the ledger '
        'it reads its identity from, so a further device learns its tenant '
        'with no relaunch (ADR 2026-10-10 §1)', () {
      final root = _root();
      expect(
        RegExp(
          r'eng\.SyncEngine\.late\([^;]*identity:\s*identity\s*,[^;]*'
          r'tenantSink:\s*ledger\s*,',
        ).hasMatch(root),
        isTrue,
      );
      expect(
        RegExp(r'final\s+identity\s*=\s*ledger\.binding\s*;').hasMatch(root),
        isTrue,
      );
    });

    test('C-1009-1 C-04b-3 S0.2 mints through the ledger the root bound; the '
        'root rebuilds on a recovered UMK and not on a re-mint, because the '
        'ceremony builder reads the ids at each opening (desk 184 (b))', () {
      final root = _root();
      final signup = root.indexOf(
        RegExp(r'auth\.signupIdentity\s*=\s*ledger;'),
      );
      final mint = root.indexOf(RegExp(r'auth\.keyMint\s*=\s*ledger;'));
      expect(signup, greaterThan(0));
      expect(mint, greaterThan(signup));
      expect(mint, lessThan(root.indexOf('ServerMembersRepository(')));
      expect(
        RegExp(r'ledger\.onUmkAdopted\s*=\s*relaunch\.arm;').hasMatch(root),
        isTrue,
      );
      expect(
        RegExp(r'onIdentityReminted\s*=').hasMatch(root),
        isFalse,
        reason: 'nothing in the root takes the ids at launch any more',
      );
      expect(
        RegExp(
          r'buildLiveCeremonySessions\([^;]*'
          r'tenantOf:\s*\(\)\s*=>\s*identity\.tenant\.value\s*,\s*'
          r'selfUserIdOf:\s*\(\)\s*=>\s*identity\.userId\.value',
        ).hasMatch(root),
        isTrue,
        reason: 'S9.2/S9.3 read the ids late (ADR 2026-10-09 §1, desk 184 (b))',
      );
      expect(
        RegExp(r'buildLiveCeremonySessions\([^;]*\btenantId:').hasMatch(root),
        isFalse,
        reason: 'no fixed tenant id is handed to the ceremony',
      );
    });

    test('C-1009-1 the members repository reads the install\'s ids at use: a '
        're-mint before S0.2 is the tenant the next invite is signed for, '
        'with no rebuild', () async {
      final l = await _ledger(keys);
      final author = _TenantAuthor();
      final api = _Api();
      final repo = ServerMembersRepository(
        api: api,
        tenantOf: () => l.binding.tenant.value,
        userIdOf: () => l.binding.userId.value,
        believes: believeNothing,
        unknownVerifierName: 'someone',
        someoneToMeetName: 'someone',
        author: author,
      );
      expect(repo.tenant, KnownTenant(l.identity.tenantId));
      final before = l.identity.tenantId;

      await l.remintProvisionalIdentity();

      expect(repo.tenant, KnownTenant(l.identity.tenantId));
      expect(repo.tenant, isNot(KnownTenant(before)));
      expect(repo.userId, l.identity.userId);
      await repo.invite(
        const InviteRequest(
          phoneE164: '+919999900002',
          grants: [BookGrant(bookId: 'b-1', role: BookRole.member)],
        ),
      );
      expect(author.tenants, [l.identity.tenantId]);
    });

    test('C-1009-1 the record author built at launch refuses before the '
        'device is registered — no key is read, nothing is signed — and '
        'signs under the minted key once S0.2 has run, with no rebuild; the '
        'device_added recorder files in the tenant as it is then', () async {
      final l = await _ledger(keys);
      final suite = l.suite;
      final author = DeviceRecordAuthor(
        suite: suite,
        keys: keys,
        deviceIdOf: () async {
          if (!l.identityConfirmed) return null;
          final raw = await keys.read(SessionItems.deviceId);
          return raw == null ? null : utf8.decode(raw);
        },
        clock: RecordHlcClock(testNow),
      );
      final posted = <List<Map<String, Object?>>>[];
      final recorder = DeviceAddedRecorder.late(
        author: author,
        tenantOf: () => l.binding.tenant.value,
        post: (records) async {
          posted.add(records);
          return const ['ok'];
        },
      );

      keys.writes.clear();
      await expectLater(
        author.sign(tenantId: l.identity.tenantId, kind: 'k', payload: {}),
        throwsA(
          isA<MembersFailure>().having(
            (e) => e.reason,
            'reason',
            MembersRefusal.unauthorized,
          ),
        ),
      );

      // C-04b-3 before S0.2, then S0.2: confirm, mint, register.
      await l.remintProvisionalIdentity();
      await l.confirmIdentity(l.identity.userId);
      await l.mintForRegistration();
      await keys.write(
        SessionItems.deviceId,
        Uint8List.fromList(utf8.encode(l.identity.deviceId)),
      );

      final wire = await author.sign(
        tenantId: (recorder.tenant as KnownTenant).id,
        kind: 'device_added',
        payload: {'device_id': l.identity.deviceId},
      );
      expect(wire['author_device_id'], l.identity.deviceId);
      expect(wire['tenant_id'], l.identity.tenantId);
      Uint8List b64(String v) =>
          Uint8List.fromList(base64Url.decode(base64Url.normalize(v)));
      final record = SignedRecord(
        suiteVersion: wire['suite_version']! as int,
        tenantId: l.identity.tenantId,
        kind: 'device_added',
        payloadJson: b64(wire['payload_json']! as String),
        authorDeviceId: l.identity.deviceId,
        authorSig: b64(wire['author_sig']! as String),
        hlc: wire['hlc']! as int,
      );
      expect(
        suite.sodium.crypto.sign.verifyDetached(
          signature: record.authorSig,
          message: record.signedDigest(suite),
          publicKey: l.keyMaterial.device.public.ed25519,
        ),
        isTrue,
        reason: 'signed by the key S0.2 minted, read at the signature',
      );
    });

    testWidgets('C-1009-1 S11\'s guardians row follows the install\'s user id: '
        'a re-mint gives S11 a new reading with no relaunch', (tester) async {
      late LocalLedger l;
      late ServerGuardians guardians;
      await tester.runAsync(() async {
        l = await _ledger(keys);
        guardians = ServerGuardians(
          api: HttpGuardiansApi(
            transport: FakeRkHttpTransport(
              (method, url, headers, body) =>
                  RkHttpResponse(200, jsonEncode({'guardian_sets': []})),
            ),
            functionsRoot: Uri.parse('https://api.example.test/functions/v1/'),
            accessToken: () async => 'tok',
          ),
          roster: () async => const GuardianRoster(),
          verified: eng.BoundUmkSource(l.binding),
        );
      });
      addTearDown(guardians.dispose);
      final trust = eng.RecordTrustStore(umks: eng.BoundUmkSource(l.binding));

      GuardianStanding? seen;
      await tester.pumpWidget(
        GuardianStandingHost(
          trust: trust,
          subjectUserIdOf: l.binding.userId,
          guardians: guardians,
          child: Builder(
            builder: (context) {
              seen = GuardianStandingScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      final first = seen;
      expect(first, isNotNull);

      await tester.runAsync(l.remintProvisionalIdentity);
      await tester.pump();
      await tester.pump();

      expect(seen, isNotNull);
      expect(identical(seen, first), isFalse, reason: 'a new reading');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
