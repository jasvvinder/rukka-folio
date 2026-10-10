// ADR 2026-10-10 ruling 1 🔒 (C-1010-1, C-1010-2; PLAN desk 185 (b)): a
// device that signs in to an existing account (ADR 2026-10-04b §3) holds no
// usable tenant id. Its tenant is *not known*: neither a placeholder nor a
// fresh mint. Every reader answers *not known yet* — the sync engine reads
// meta and holds, nothing is filed, published or opened under a tenant — and
// the tenant is learned from the account once the device is certified and
// its memberships are readable: exactly one active membership, and that
// membership's tenant is the install's, persisted and picked up with no
// relaunch. Several stay unknown (ADR *Open*). A first device is unchanged.
//
// Over a real `LocalLedger` (in-memory SQLite, libsodium) and, for the seam,
// the real `SyncEngine` + `CryptoGuard` over the ledger's own binding against
// the sync engine's fake server. Synthetic ids only.
@Tags(['C'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart' show BookType;
import 'package:data/data.dart'
    show LedgerDatabase, SignedRecordMirror, SignedRecordRow;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/bootstrap.dart' show guardianRosterOf;
import 'package:rukka_folio/features/members/members_api.dart';
import 'package:rukka_folio/features/members/members_repository.dart'
    show BookGrant, BookRole, InviteRequest, MembersTenantNotKnown;
import 'package:rukka_folio/features/members/server_members_repository.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/records/device_added_record.dart';
import 'package:rukka_folio/shared/seams/guardians.dart' show GuardiansFailure;
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import '../test_app.dart';
import 'accepted_key_cache_test.dart' show guardOver, wireKeyFor;
import 'tenant_of.dart';

/// The account's first device: tenant minted at its first run, a book, and
/// a recovery sheet a further device can adopt the UMK from (rung 3).
Future<
  ({
    LocalLedger ledger,
    LedgerIdentity id,
    RecoverySheetMaterial sheet,
    UmkPublic published,
  })
>
_account() async {
  final a = await openTestLedger();
  final id = await a.bootstrapSolo(firstBookName: 'Me');
  final sheet = a.makeRecoverySheet();
  addTearDown(sheet.dispose);
  return (ledger: a, id: id, sheet: sheet, published: a.keyMaterial.umk.public);
}

typedef _Account = ({
  LocalLedger ledger,
  LedgerIdentity id,
  RecoverySheetMaterial sheet,
  UmkPublic published,
});

/// A fresh phone that signed in to [account] (ADR 2026-10-04b §3).
Future<({LocalLedger ledger, FakeKeyStore keys, LedgerDatabase db})> _further(
  _Account account,
) async {
  final keys = FakeKeyStore();
  final db = await openTestDb();
  final b = await openTestLedger(keys: keys, db: db);
  await b.openIdentity();
  await b.adoptExistingAccount(account.id.userId);
  return (ledger: b, keys: keys, db: db);
}

/// S0.2's mint (seeds only) and the account's UMK by rung 3.
Future<void> _registerWithUmk(LocalLedger b, _Account account) async {
  await b.mintForRegistration();
  final adopted = await b.adoptRecoveredUmk(
    sealedBlob: account.sheet.sealedBlob,
    rk: account.sheet.rk,
    sheetUserId: account.id.userId,
    expected: account.published,
  );
  expect(adopted, isA<RecoveredUmkAdopted>());
}

/// Certified under the account's UMK (06 §3 step 3).
Future<DeviceCert> _certify(LocalLedger b) async {
  final offer = b.issueOwnCert();
  await b.installOwnCert(offer.cert);
  expect(b.ownDeviceCert, isNotNull);
  return offer.cert;
}

Future<Map<String, Object?>> _storedJson(KeyStore keys) async => (jsonDecode(
  utf8.decode((await keys.read(LocalLedgerKeys.identity))!),
) as Map).cast<String, Object?>();

String _otherTenant(LocalLedger l) => l.newId();

typedef _Member = ({String userId, UmkKeyPair umk, VerifiedUmkPublic verified});

/// Another member of the account, and the key a real ceremony on [l]'s
/// device verified — the only way to a [VerifiedUmkPublic] (04 §8.2 🔒).
_Member _member(LocalLedger l) {
  final userId = l.newId();
  final umk = UmkKeyPair.generate(l.suite);
  addTearDown(umk.dispose);
  final r = Ceremony.verifyQr(
    l.suite,
    scanned: QrPayload(
      userId: userId,
      umk: umk.public,
      nonce: l.suite.randomBytes(ceremonyNonceBytes),
    ),
    relayed: umk.public,
    relayedUserId: userId,
  );
  return (userId: userId, umk: umk, verified: (r as CeremonyVerified).verified);
}

String _b64(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// A `verification_event` for [subject] that [l]'s own device signed under
/// [tenantId], put straight into `signed_records_local` — a row the
/// directory can place (its author is this device), already stored when the
/// tenant is learned. Returns the row id.
Future<String> _storedVerification(
  LocalLedger l, {
  required String tenantId,
  required _Member subject,
  required int hlc,
}) async {
  final umk = subject.umk.public;
  final signed = SignedRecord.sign(
    l.suite,
    tenantId: tenantId,
    kind: SignedRecordKind.verificationEvent,
    payloadJson: Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          VerificationPayload.subjectUserId: subject.userId,
          VerificationPayload.verifierUserId: l.identity.userId,
          VerificationPayload.method: 'qr_in_person',
          VerificationPayload.result: VerificationPayload.resultVerified,
          VerificationPayload.umkEd25519: _b64(umk.ed25519),
          VerificationPayload.umkX25519: _b64(umk.x25519),
          VerificationPayload.fingerprint: Fingerprint.of(l.suite, umk).hex,
        }),
      ),
    ),
    hlc: hlc,
    author: l.keyMaterial.device,
  );
  final id = l.newId();
  final appended = await SignedRecordMirror(l.db).append(
    SignedRecordRow(
      id: id,
      tenantId: signed.tenantId,
      kind: signed.kind,
      payload: signed.payloadJson,
      authorDevice: signed.authorDeviceId,
      sig: signed.authorSig,
      hlc: signed.hlc,
    ),
  );
  expect(appended, isTrue);
  return id;
}

/// Signs nothing real; records the tenant each record was signed for.
final class _Author implements MembersRecordAuthor {
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

/// The members routes, counting what reached them.
final class _Api implements MembersApi {
  int pulls = 0;
  final issued = <Map<String, Object?>>[];

  @override
  Future<eng.MetaResponse> pullMeta({String? after}) async {
    pulls++;
    return const eng.MetaResponse(storeEpoch: 'epoch-1', next: null);
  }

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

const _invite = InviteRequest(
  phoneE164: '+919999900002',
  grants: [BookGrant(bookId: 'b-1', role: BookRole.member)],
);

void main() {
  group('C-1010-1 a further device\'s tenant is not known (ADR 2026-10-10 '
      '§1 🔒)', () {
    test('C-1010-1 adopting an existing account leaves the tenant not known — '
        'no placeholder id, no fresh mint — stored as such, reopened as such, '
        'and announced', () async {
      final a = await _account();
      final keys = FakeKeyStore();
      final db = await openTestDb();
      final b = await openTestLedger(keys: keys, db: db);
      final provisional = await b.openIdentity();
      var told = 0;
      b.binding.tenant.addListener(() => told++);

      await b.adoptExistingAccount(a.id.userId);

      expect(told, 1);
      expect(b.identity.tenant, const TenantNotKnownYet());
      expect(b.binding.tenant.value, const TenantNotKnownYet());
      expect(provisional.tenant, isA<KnownTenant>(), reason: 'discarded');
      final raw = await _storedJson(keys);
      expect(raw.containsKey('tenant_id'), isFalse, reason: 'nothing minted');
      expect(raw['user_id'], a.id.userId);
      expect(
        (await readStoredIdentity(keys))!.tenant,
        const TenantNotKnownYet(),
      );

      final again = await openTestLedger(keys: keys, db: db);
      await again.openIdentity();
      expect(again.identity.tenant, const TenantNotKnownYet());
      expect(again.identity.userId, a.id.userId);
      expect(again.identity.deviceId, provisional.deviceId);
    });

    test('C-1010-1 registered, the binding answers registered-awaiting-tenant '
        '— never a RegisteredIdentity with an id — so the real engine over it '
        'holds tenantNotKnown, and the book-key store answers no tenant '
        '(KeyUnavailable, never an envelope opened under a guess)', () async {
      final a = await _account();
      final f = await _further(a);
      final b = f.ledger;
      expect(b.binding.currentIdentity(), const eng.NotRegisteredYet());

      await b.mintForRegistration();

      expect(
        b.binding.currentIdentity(),
        eng.RegisteredAwaitingTenant(
          deviceId: b.identity.deviceId,
          userId: a.id.userId,
        ),
      );
      final keys = b.binding.currentKeys();
      expect(keys, isA<eng.DeviceKeyMaterial>());
      expect((keys as eng.DeviceKeyMaterial).bookKeys.tenantIdOf('b'), isNull);

      final trust = eng.RecordTrustStore(umks: eng.BoundUmkSource(b.binding));
      final engine = eng.SyncEngine.late(
        db: b.db,
        mirror: b.mirror,
        transport: eng.FakeSyncServer(
          clock: eng.ManualClock(1 << 40),
          rateLimits: eng.RateLimits.none,
        ).transportFor(b.identity.deviceId),
        clock: eng.ManualClock(1 << 40),
        guard: eng.CryptoGuard.late(
          suite: b.suite,
          trust: trust,
          material: b.binding,
        ),
        trust: trust,
        identity: b.binding,
        keySink: b,
        tenantSink: b,
      );
      expect(engine.hold, eng.SyncHold.tenantNotKnown);
    });

    test('C-1010-1 with the account\'s UMK and a certificate, nothing that '
        'carries a tenant is authored: no book (nothing written), no '
        'verification record; a book key from sync is kept and filed under '
        'no tenant', () async {
      final a = await _account();
      final f = await _further(a);
      final b = f.ledger;
      await _registerWithUmk(b, a);
      await _certify(b);

      await expectLater(
        b.createBook(name: 'Mine', type: BookType.personal),
        throwsA(isA<LedgerTenantNotKnown>()),
      );
      expect(await b.mirror.bookIds(), isEmpty);
      expect(await b.db.select(b.db.keyCache).get(), isEmpty);
      expect(await b.db.select(b.db.outbox).get(), isEmpty);

      await expectLater(
        b.verifiedMembers.storeVerified(
          userId: b.newId(),
          verified: a.ledger.keyMaterial.verifiedUmkOf(a.id.userId)!,
          method: VerificationMethod.qrInPerson,
        ),
        throwsA(isA<LedgerTenantNotKnown>()),
      );
      expect(await b.db.select(b.db.signedRecordsLocal).get(), isEmpty);

      final joined = b.newId();
      final bk = BookKey.generate(b.suite, bookId: joined, keyVersion: 1);
      final accepted = guardOver(b).acceptWrappedKey(wireKeyFor(b, bk));
      await b.keyAccepted((accepted as eng.KeyAccepted).key);
      expect(await b.db.select(b.db.keyCache).get(), hasLength(1));
      final held = (b.binding.currentKeys() as eng.DeviceKeyMaterial).bookKeys;
      expect(held.has(joined, 1), isTrue);
      expect(held.tenantIdOf(joined), isNull, reason: 'filed under no tenant');
    });
  });

  group('C-1010-2 the tenant is learned from the account (ADR 2026-10-10 '
      '§1 🔒)', () {
    test('C-1010-2 certified, exactly one active membership: its tenant is '
        'the install\'s — written to the identity record, announced, read by '
        'the binding and the key store at once, and still there after a '
        'relaunch; a later read never changes it', () async {
      final a = await _account();
      final tenant = a.id.tenantId;
      final f = await _further(a);
      final b = f.ledger;
      await _registerWithUmk(b, a);
      await _certify(b);
      final joined = b.newId();
      final bk = BookKey.generate(b.suite, bookId: joined, keyVersion: 1);
      final accepted = guardOver(b).acceptWrappedKey(wireKeyFor(b, bk));
      await b.keyAccepted((accepted as eng.KeyAccepted).key);
      var told = 0;
      b.bindingChanges.addListener(() => told++);

      await b.ownMembershipsRead(
        OwnMemberships(userId: a.id.userId, activeTenantIds: {tenant}),
      );

      expect(told, 1);
      expect(b.identity.tenant, KnownTenant(tenant));
      expect(b.binding.tenant.value, KnownTenant(tenant));
      expect(
        b.binding.currentIdentity(),
        eng.RegisteredIdentity(
          deviceId: b.identity.deviceId,
          userId: a.id.userId,
          tenantId: tenant,
        ),
      );
      final held = (b.binding.currentKeys() as eng.DeviceKeyMaterial).bookKeys;
      expect(held.tenantIdOf(joined), tenant);
      expect((await _storedJson(f.keys))['tenant_id'], tenant);

      final other = _otherTenant(b);
      await b.ownMembershipsRead(
        OwnMemberships(userId: a.id.userId, activeTenantIds: {other}),
      );
      expect(b.identity.tenant, KnownTenant(tenant), reason: 'never changes');
      expect(told, 1);

      final again = await openTestLedger(keys: f.keys, db: f.db);
      await again.openIdentity();
      expect(again.identity.tenant, KnownTenant(tenant));
      expect(again.binding.currentIdentity(), isA<eng.RegisteredIdentity>());

      // Authoring opens once the tenant is known.
      await b.createBook(name: 'Mine', type: BookType.personal);
      expect(await b.mirror.bookIds(), hasLength(1));
    });

    test(
      'C-1010-2 fails closed: several active memberships (⚠️ SPEC, ADR '
      '*Open*), none, a read made as another user, or a device not yet '
      'certified — the tenant stays not known and nothing is written',
      () async {
        final a = await _account();
        final tenant = a.id.tenantId;
        final f = await _further(a);
        final b = f.ledger;
        await _registerWithUmk(b, a);
        final before = await _storedJson(f.keys);

        // Not certified yet: even the one right answer teaches it nothing.
        await b.ownMembershipsRead(
          OwnMemberships(userId: a.id.userId, activeTenantIds: {tenant}),
        );
        expect(b.identity.tenant, const TenantNotKnownYet());

        await _certify(b);
        for (final read in [
          OwnMemberships(
            userId: a.id.userId,
            activeTenantIds: {tenant, _otherTenant(b)},
          ),
          OwnMemberships(userId: a.id.userId, activeTenantIds: const {}),
          OwnMemberships(userId: b.newId(), activeTenantIds: {tenant}),
          OwnMemberships(userId: a.id.userId, activeTenantIds: {'not-a-uuid'}),
        ]) {
          await b.ownMembershipsRead(read);
          expect(b.identity.tenant, const TenantNotKnownYet(), reason: '$read');
        }
        expect(await _storedJson(f.keys), before);
        expect(
          b.binding.currentIdentity(),
          isA<eng.RegisteredAwaitingTenant>(),
        );
      },
    );

    test('C-1010-2 a first device is unchanged: its tenant was minted at its '
        'first run and no membership read moves it', () async {
      final a = await _account();
      final l = a.ledger;
      expect(l.identity.tenant, KnownTenant(a.id.tenantId));
      await l.ownMembershipsRead(
        OwnMemberships(userId: a.id.userId, activeTenantIds: {l.newId()}),
      );
      expect(l.identity.tenant, KnownTenant(a.id.tenantId));
      expect(
        l.binding.currentIdentity(),
        eng.RegisteredIdentity(
          deviceId: a.id.deviceId,
          userId: a.id.userId,
          tenantId: a.id.tenantId,
        ),
      );
    });

    test('C-1010-2 the verification directory learns with the ledger: before '
        'the learn it believes nobody and refuses a ceremony\'s key; once the '
        'tenant is learned the same directory — no rebuild, no relaunch — '
        'folds the rows already stored under that tenant (none under another), '
        'files a new ceremony under it, and answers for both through '
        'verifiedMembers, keyMaterial and the binding\'s key material; still '
        'believed after a relaunch', () async {
      final a = await _account();
      final tenant = a.id.tenantId;
      final f = await _further(a);
      final b = f.ledger;
      await _registerWithUmk(b, a);
      await _certify(b);
      final directory = b.verifiedMembers;
      final early = _member(b), elsewhere = _member(b), met = _member(b);
      final earlyRow = await _storedVerification(
        b,
        tenantId: tenant,
        subject: early,
        hlc: 9000,
      );
      final elsewhereRow = await _storedVerification(
        b,
        tenantId: _otherTenant(b),
        subject: elsewhere,
        hlc: 9001,
      );

      // Not known: the stored rows are not folded, a ceremony is refused.
      await directory.load();
      expect(directory.tenant, const TenantNotKnownYet());
      expect(directory.believed, isEmpty);
      expect(b.keyMaterial.verifiedUmkOf(early.userId), isNull);
      await expectLater(
        directory.storeVerified(
          userId: met.userId,
          verified: met.verified,
          method: VerificationMethod.qrInPerson,
        ),
        throwsA(isA<LedgerTenantNotKnown>()),
      );

      await b.ownMembershipsRead(
        OwnMemberships(userId: a.id.userId, activeTenantIds: {tenant}),
      );

      expect(identical(b.verifiedMembers, directory), isTrue);
      expect(directory.tenant, KnownTenant(tenant));
      // The learn folded what was already stored under the tenant…
      expect(directory.verifiedUmkOf(early.userId)!.public, early.umk.public);
      expect(
        b.keyMaterial.verifiedUmkOf(early.userId)!.public,
        early.umk.public,
      );
      final mirror = SignedRecordMirror(b.db);
      expect((await mirror.byId(earlyRow))!.verified, isTrue);
      // …and nothing of another tenant.
      expect(directory.verifiedUmkOf(elsewhere.userId), isNull);
      expect((await mirror.byId(elsewhereRow))!.verified, isFalse);

      // A ceremony now lands, signed under the learned tenant.
      final stored = await directory.storeVerified(
        userId: met.userId,
        verified: met.verified,
        method: VerificationMethod.codeRemote,
      );
      expect((await mirror.byId(stored.recordId))!.tenantId, tenant);
      expect(b.keyMaterial.verifiedUmkOf(met.userId)!.public, met.umk.public);
      final engineView =
          (b.binding.currentKeys() as eng.DeviceKeyMaterial).verifiedUmks!;
      expect(engineView.verifiedUmkOf(met.userId)!.public, met.umk.public);
      expect(engineView.verifiedUmkOf(early.userId)!.public, early.umk.public);

      final again = await openTestLedger(keys: f.keys, db: f.db);
      await again.openIdentity();
      expect(again.verifiedMembers.tenant, KnownTenant(tenant));
      expect(
        again.verifiedMembers.verifiedUmkOf(met.userId)!.public,
        met.umk.public,
      );
      expect(
        again.verifiedMembers.memberOf(met.userId)!.method,
        VerificationMethod.codeRemote,
      );
      expect(again.verifiedMembers.verifiedUmkOf(elsewhere.userId), isNull);
    });

    test('C-1010-2 the seam, end to end: the real engine over the ledger\'s '
        'binding reads meta while the tenant is not known and learns nothing '
        'before certification; once certified it learns the account\'s one '
        'tenant, and with no relaunch the next round runs under it — a book '
        'authored then is pushed stamped with that tenant', () async {
      final a = await _account();
      final tenant = a.id.tenantId;
      final f = await _further(a);
      final b = f.ledger;
      await _registerWithUmk(b, a);

      // The server's clock is the ledger's: an HLC ahead of it is refused.
      final clock = eng.ManualClock(testNow().millisecondsSinceEpoch);
      final server = eng.FakeSyncServer(
        clock: clock,
        rateLimits: eng.RateLimits.none,
      );
      final membership = '$tenant:${a.id.userId}';
      server.memberships[membership] = eng.WireMembership(
        id: membership,
        tenantId: tenant,
        userId: a.id.userId,
        status: 'active',
      );
      final trust = eng.RecordTrustStore(umks: eng.BoundUmkSource(b.binding));
      final engine = eng.SyncEngine.late(
        db: b.db,
        mirror: b.mirror,
        transport: server.transportFor(b.identity.deviceId),
        clock: clock,
        guard: eng.CryptoGuard.late(
          suite: b.suite,
          trust: trust,
          material: b.binding,
        ),
        trust: trust,
        identity: b.binding,
        recompute: b.recompute,
        keySink: b,
        tenantSink: b,
      );

      // Uncertified: the read happens, the ledger learns nothing from it.
      final r0 = await engine.sync();
      expect(r0.held, eng.SyncHold.tenantNotKnown);
      expect(b.identity.tenant, const TenantNotKnownYet());

      final cert = await _certify(b);
      trust.certs[cert.deviceId] = cert;
      final r1 = await engine.sync();
      expect(r1.held, eng.SyncHold.bindingChanged);
      expect(b.identity.tenant, KnownTenant(tenant));
      expect(engine.hold, isNull);

      await b.createBook(name: 'Mine', type: BookType.personal);
      final r2 = await engine.sync();
      expect(r2.held, isNull);
      expect(r2.acked, greaterThan(0));
      expect(server.stored, isNotEmpty);
      expect(server.stored.map((e) => e.tenantId).toSet(), {tenant});
    });
  });

  group('C-1010-1 every reader of the tenant says not known — never an empty '
      'tenant (ADR 2026-10-10 §1 🔒)', () {
    test(
      'C-1010-1 over a further device\'s ledger, the members repository, '
      'S11.1\'s roster and the device_added recorder read, sign, list and '
      'post nothing while the tenant is not known, and say so; the same '
      'instances work in the tenant once it is learned, with no rebuild',
      () async {
        final a = await _account();
        final f = await _further(a);
        final b = f.ledger;
        await _registerWithUmk(b, a);
        final cert = await _certify(b);
        final api = _Api();
        final author = _Author();
        final repo = ServerMembersRepository(
          api: api,
          tenantOf: () => b.binding.tenant.value,
          userIdOf: () => b.binding.userId.value,
          believes: believeNothing,
          unknownVerifierName: 'someone',
          someoneToMeetName: 'someone',
          author: author,
        );
        addTearDown(repo.dispose);
        final events = <String>[];
        final posted = <List<Map<String, Object?>>>[];
        final recorder = DeviceAddedRecorder.late(
          author: author,
          tenantOf: () => b.binding.tenant.value,
          post: (records) async {
            posted.add(records);
            return const ['ok'];
          },
          log: events.add,
        );

        await expectLater(
          repo.refresh(),
          throwsA(isA<MembersTenantNotKnown>()),
        );
        expect(api.pulls, 0, reason: 'nothing read, so nothing filtered');
        expect(repo.current, isNull, reason: 'no list of nobody');
        await expectLater(
          repo.invite(_invite),
          throwsA(isA<MembersTenantNotKnown>()),
        );
        expect(author.tenants, isEmpty, reason: 'nothing signed');
        expect(api.issued, isEmpty);
        expect(
          () => guardianRosterOf(
            repo.current,
            tenant: b.binding.tenant.value,
            nameOf: (_) => 'Member',
          ),
          throwsA(
            isA<GuardiansFailure>().having(
              (e) => e.reason,
              'reason',
              'no_tenant',
            ),
          ),
        );
        await recorder.deviceAdded(cert, umkKeyVersion: 1);
        expect(posted, isEmpty, reason: 'nothing published under a tenant');
        expect(author.tenants, isEmpty);
        expect(events, [DeviceAddedRecorder.notFiledTenantUnknownEvent]);

        await b.ownMembershipsRead(
          OwnMemberships(userId: a.id.userId, activeTenantIds: {a.id.tenantId}),
        );

        await repo.invite(_invite);
        expect(author.tenants, [a.id.tenantId]);
        await repo.refresh();
        expect(api.pulls, greaterThan(0));
        expect(repo.current, isNotNull);
        expect(
          guardianRosterOf(
            repo.current,
            tenant: b.binding.tenant.value,
            nameOf: (_) => 'Member',
          ).tenantId,
          a.id.tenantId,
        );
        await recorder.deviceAdded(cert, umkKeyVersion: 1);
        expect(posted.single.single['tenant_id'], a.id.tenantId);
      },
    );
  });
}
