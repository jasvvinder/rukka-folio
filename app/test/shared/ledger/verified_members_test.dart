// Suite C — the missing persistence behind 04 §8.2 🔒.
//
// The defect this pins: the mutual ceremony proved a member's UMK public key
// and dropped it, so `LedgerKeyMaterial.verifiedUmkOf` answered only for this
// install's own user and every guardian candidate was refused as unverified —
// correct posture, impossible Setup (04 §7.3).
//
// The two properties the type system carries, asserted here as behaviour:
// what comes back out is a `VerifiedUmkPublic` (there is no other shape in
// the API — a test cannot even express "bytes plus a boolean"), and a key is
// believed only while a **signed** record backs it.
//
// Synthetic ids only (rule 4).
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../test_app.dart';

const String _memberA = '55555555-5555-4555-8555-555555555551';
const String _memberB = '55555555-5555-4555-8555-555555555552';

/// A member with a real UMK and the key a real ceremony verified — the only
/// way to obtain [VerifiedUmkPublic] (04 §8.2 🔒).
final class _Member {
  _Member(CryptoSuite suite, this.userId)
    : umk = UmkKeyPair.generate(suite),
      _suite = suite;

  final CryptoSuite _suite;
  final String userId;
  final UmkKeyPair umk;

  VerifiedUmkPublic get verified => (Ceremony.verifyQr(
    _suite,
    scanned: QrPayload(
      userId: userId,
      umk: umk.public,
      nonce: _suite.randomBytes(ceremonyNonceBytes),
    ),
    relayed: umk.public,
    relayedUserId: userId,
  ) as CeremonyVerified).verified;
}

void main() {
  group('VerifiedMemberDirectory (04 §6.4, §8.2 🔒 · ADR 2026-09-05d §7)', () {
    test('C-06-57 a ceremony that succeeds is remembered: before it '
        'verifiedUmkOf(member) is null, after it the material answers with the '
        'VerifiedUmkPublic the ceremony minted — the key a guardian share and a '
        'book key seal to', () async {
      final l = await openTestLedger();
      await l.bootstrapSolo(firstBookName: 'Me');
      final member = _Member(l.suite, _memberA);

      expect(l.keyMaterial.verifiedUmkOf(_memberA), isNull);

      final stored = await l.verifiedMembers.storeVerified(
        userId: _memberA,
        verified: member.verified,
        method: VerificationMethod.codeRemote,
      );

      final back = l.keyMaterial.verifiedUmkOf(_memberA);
      expect(back, isA<VerifiedUmkPublic>());
      expect(back!.public, member.umk.public);
      expect(back.fingerprint, Fingerprint.of(l.suite, member.umk.public));
      // The authoritative method is the record's (04 §6.4) — see the
      // ⚠️ SPEC note in verified_members.dart on why the minted type's own
      // `method` is not it.
      expect(stored.method, VerificationMethod.codeRemote);
      expect(
        l.verifiedMembers.memberOf(_memberA)!.method,
        VerificationMethod.codeRemote,
      );
      // Still nobody else.
      expect(l.keyMaterial.verifiedUmkOf(_memberB), isNull);
    });

    test('C-06-58 the key survives the app: a fresh LocalLedger over the same '
        'database and key store answers for the member the earlier ceremony '
        'verified — this is the persistence 04 §7.3 Setup waits on', () async {
      final db = await openTestDb();
      final keys = FakeKeyStore();
      final first = await openTestLedger(db: db, keys: keys);
      await first.bootstrapSolo(firstBookName: 'Me');
      final member = _Member(first.suite, _memberA);
      await first.verifiedMembers.storeVerified(
        userId: _memberA,
        verified: member.verified,
        method: VerificationMethod.qrInPerson,
      );
      first.dispose();

      final second = await openTestLedger(db: db, keys: keys);
      await second.bootstrapSolo();
      final back = second.keyMaterial.verifiedUmkOf(_memberA);
      expect(back, isNotNull);
      expect(back!.public, member.umk.public);
      expect(
        second.verifiedMembers.memberOf(_memberA)!.method,
        VerificationMethod.qrInPerson,
      );
    });

    test(
      'C-06-59 the signature is what is believed, not the row: tampering the '
      'stored payload — even to a key that parses — drops the member on the '
      'next load (C-05d-7 one layer down)',
      () async {
        final db = await openTestDb();
        final keys = FakeKeyStore();
        final l = await openTestLedger(db: db, keys: keys);
        await l.bootstrapSolo(firstBookName: 'Me');
        final good = _Member(l.suite, _memberA);
        final hostile = _Member(l.suite, _memberA);
        final rec = await l.verifiedMembers.storeVerified(
          userId: _memberA,
          verified: good.verified,
          method: VerificationMethod.qrInPerson,
        );

        // Swap the key halves for a different, perfectly well-formed pair and
        // keep the fingerprint consistent with them: the only thing left to
        // catch it is the Ed25519 signature over the payload.
        final tampered = _payload(
          subject: _memberA,
          verifier: l.identity.userId,
          umk: hostile.umk.public,
          fingerprint: Fingerprint.of(l.suite, hostile.umk.public).hex,
        );
        await (db.update(db.signedRecordsLocal)
              ..where((t) => t.id.equals(rec.recordId)))
            .write(SignedRecordsLocalCompanion(payload: Value(tampered)));

        await l.verifiedMembers.load();
        expect(l.keyMaterial.verifiedUmkOf(_memberA), isNull);
      },
    );

    test(
      'C-06-60 a record this install cannot place is stored and not believed: '
      'a server-relayed verification_event signed by an unknown device never '
      'becomes a seal target (04 §8.2 🔒)',
      () async {
        final db = await openTestDb();
        final l = await openTestLedger(db: db, keys: FakeKeyStore());
        await l.bootstrapSolo(firstBookName: 'Me');
        final ghost = _Member(l.suite, _memberB);
        final stranger = DeviceKeyPair.generate(l.suite, deviceId: l.newId());
        addTearDown(stranger.dispose);

        final signed = SignedRecord.sign(
          l.suite,
          tenantId: l.identity.tenantId,
          kind: SignedRecordKind.verificationEvent,
          payloadJson: _payload(
            subject: _memberB,
            verifier: l.identity.userId,
            umk: ghost.umk.public,
            fingerprint: Fingerprint.of(l.suite, ghost.umk.public).hex,
          ),
          hlc: 9000,
          author: stranger,
        );
        final id = l.newId();
        await SignedRecordMirror(db).append(
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

        await l.verifiedMembers.load();
        expect(l.keyMaterial.verifiedUmkOf(_memberB), isNull);
        // Stored — a record is history — but never marked believed.
        final row = await SignedRecordMirror(db).byId(id);
        expect(row, isNotNull);
        expect(row!.verified, isFalse);
      },
    );

    test(
      'C-06-61 the fingerprint in the record must be the fingerprint of the '
      'keys in it — a signed record whose two halves disagree proves nothing',
      () async {
        final db = await openTestDb();
        final l = await openTestLedger(db: db, keys: FakeKeyStore());
        await l.bootstrapSolo(firstBookName: 'Me');
        final a = _Member(l.suite, _memberA);
        final b = _Member(l.suite, _memberB);

        final signed = SignedRecord.sign(
          l.suite,
          tenantId: l.identity.tenantId,
          kind: SignedRecordKind.verificationEvent,
          payloadJson: _payload(
            subject: _memberA,
            verifier: l.identity.userId,
            umk: a.umk.public,
            // The fingerprint a human actually confirmed — of somebody else.
            fingerprint: Fingerprint.of(l.suite, b.umk.public).hex,
          ),
          hlc: 9100,
          author: l.keyMaterial.device,
        );
        await SignedRecordMirror(db).append(
          SignedRecordRow(
            id: l.newId(),
            tenantId: signed.tenantId,
            kind: signed.kind,
            payload: signed.payloadJson,
            authorDevice: signed.authorDeviceId,
            sig: signed.authorSig,
            hlc: signed.hlc,
          ),
        );

        await l.verifiedMembers.load();
        expect(l.keyMaterial.verifiedUmkOf(_memberA), isNull);
      },
    );

    test(
      'C-06-62 a re-verification replaces the key, and a reload reaches the '
      'same answer as the live insert: last record wins by (hlc, id)',
      () async {
        final db = await openTestDb();
        final l = await openTestLedger(db: db, keys: FakeKeyStore());
        await l.bootstrapSolo(firstBookName: 'Me');
        final before = _Member(l.suite, _memberA);
        final after = _Member(l.suite, _memberA);

        await l.verifiedMembers.storeVerified(
          userId: _memberA,
          verified: before.verified,
          method: VerificationMethod.qrInPerson,
        );
        await l.verifiedMembers.storeVerified(
          userId: _memberA,
          verified: after.verified,
          method: VerificationMethod.codeRemote,
        );
        expect(l.keyMaterial.verifiedUmkOf(_memberA)!.public, after.umk.public);

        await l.verifiedMembers.load();
        expect(l.keyMaterial.verifiedUmkOf(_memberA)!.public, after.umk.public);
        expect(
          l.verifiedMembers.memberOf(_memberA)!.method,
          VerificationMethod.codeRemote,
        );
      },
    );

    test(
      "C-06-63 this install's own UMK is the one it holds, never one a record "
      'told it about — a record naming self does not displace it',
      () async {
        final db = await openTestDb();
        final l = await openTestLedger(db: db, keys: FakeKeyStore());
        final id = await l.bootstrapSolo(firstBookName: 'Me');
        final own = l.keyMaterial.verifiedUmkOf(id.userId)!;
        final impostor = _Member(l.suite, id.userId);

        await l.verifiedMembers.storeVerified(
          userId: id.userId,
          verified: impostor.verified,
          method: VerificationMethod.qrInPerson,
        );

        expect(l.keyMaterial.verifiedUmkOf(id.userId)!.public, own.public);
        expect(
          l.keyMaterial.verifiedUmkOf(id.userId)!.public,
          isNot(impostor.umk.public),
        );
      },
    );

    test(
      'C-06-64 a verification_event of another tenant is never folded in — '
      'the tenant is inside the signed header, so it cannot be relabelled',
      () async {
        final db = await openTestDb();
        final l = await openTestLedger(db: db, keys: FakeKeyStore());
        await l.bootstrapSolo(firstBookName: 'Me');
        final other = _Member(l.suite, _memberB);
        final otherTenant = l.newId();

        final signed = SignedRecord.sign(
          l.suite,
          tenantId: otherTenant,
          kind: SignedRecordKind.verificationEvent,
          payloadJson: _payload(
            subject: _memberB,
            verifier: l.identity.userId,
            umk: other.umk.public,
            fingerprint: Fingerprint.of(l.suite, other.umk.public).hex,
          ),
          hlc: 9200,
          author: l.keyMaterial.device,
        );
        await SignedRecordMirror(db).append(
          SignedRecordRow(
            id: l.newId(),
            tenantId: signed.tenantId,
            kind: signed.kind,
            payload: signed.payloadJson,
            authorDevice: signed.authorDeviceId,
            sig: signed.authorSig,
            hlc: signed.hlc,
          ),
        );

        await l.verifiedMembers.load();
        expect(l.keyMaterial.verifiedUmkOf(_memberB), isNull);
      },
    );

    test(
      'C-06-65 verifiedMembers is LedgerNotOpen before bootstrap and again '
      'after dispose — no key outlives the material that proves it',
      () async {
        final l = await openTestLedger();
        expect(() => l.verifiedMembers, throwsA(isA<LedgerNotOpen>()));
        await l.bootstrapSolo(firstBookName: 'Me');
        expect(l.verifiedMembers, isA<VerifiedMemberDirectory>());
        l.dispose();
        expect(() => l.verifiedMembers, throwsA(isA<LedgerNotOpen>()));
      },
    );
  });
}

/// The exact payload shape `VerifiedMemberDirectory` writes — built here by
/// hand so a test can sign one that differs from it in exactly one field.
Uint8List _payload({
  required String subject,
  required String verifier,
  required UmkPublic umk,
  required String fingerprint,
  String method = 'qr_in_person',
  String result = 'verified',
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      VerificationPayload.subjectUserId: subject,
      VerificationPayload.verifierUserId: verifier,
      VerificationPayload.method: method,
      VerificationPayload.result: result,
      VerificationPayload.umkEd25519: _b64(umk.ed25519),
      VerificationPayload.umkX25519: _b64(umk.x25519),
      VerificationPayload.fingerprint: fingerprint,
    }),
  ),
);

String _b64(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');
