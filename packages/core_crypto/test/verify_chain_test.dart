@Tags(['B'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String objectX = '55555555-5555-4555-8555-555555555551';
const String envId = '66666666-6666-4666-8666-666666666661';
const int hlc0 = 1757100000000 << 16;
const int issuedAt = 1757100000000;

/// A tenant with one verified member (Alice, device A) and one sealed envelope.
final class World {
  World(this.s, this.alice, this.devA, this.key, this.trust, this.env);

  final CryptoSuite s;
  final UmkKeyPair alice;
  final DeviceKeyPair devA;
  final BookKey key;
  final MapTrustStore trust;
  final Envelope env;

  ChainVerifier get verifier => ChainVerifier(s, trust);
}

Future<World> world({int seed = 40}) async {
  final s = await testSuite(seed: seed);
  final alice = UmkKeyPair.generate(s);
  final devA = DeviceKeyPair.generate(s, deviceId: deviceA);
  final key = BookKey.generate(s, bookId: bookA, keyVersion: 1);
  addTearDown(alice.dispose);
  addTearDown(devA.dispose);
  addTearDown(key.dispose);
  final cert = DeviceCert.issue(
    s,
    issuer: alice,
    userId: userA,
    device: devA.public,
    issuedAtMs: issuedAt,
  );
  final trust = MapTrustStore(
    umks: {userA: verifiedUmk(s, alice)},
    certs: {deviceA: cert},
  );
  final env = EnvelopeBuilder.seal(
    s,
    tenantId: tenantA,
    bookId: bookA,
    objectId: objectX,
    objectType: 'entry',
    envelopeId: envId,
    hlc: hlc0,
    authorSeq: 1,
    object: const {'amount_paise': 12500},
    bookKey: key,
    author: devA,
  );
  return World(s, alice, devA, key, trust, env);
}

Envelope withBlob(Envelope e, Uint8List blob, {int? suiteVersion}) =>
    Envelope.fromParts(
      suiteVersion: suiteVersion ?? e.suiteVersion,
      tenantId: e.tenantId,
      bookId: e.bookId,
      objectId: e.objectId,
      objectType: e.objectType,
      keyVersion: e.keyVersion,
      payloadSchema: e.payloadSchema,
      authorDeviceId: e.authorDeviceId,
      hlc: e.hlc,
      envelopeId: e.envelopeId,
      blob: blob,
    );

Matcher quarantine(QuarantineReason r) => isA<ChainQuarantine>()
    .having((q) => q.reason, 'reason', r)
    .having((q) => q.securityEvent, 'securityEvent', isTrue);

void main() {
  test('B-04-37 happy path (04 §3.4): sig ✓ under device key → cert ✓ under author UMK → UMK verified by ceremony → ChainVerified; blob hash checked when given', () async {
    final w = await world();
    final v = w.verifier.verifyEnvelope(
      w.env,
      seq: 10,
      expectedBlobHash: w.env.blobHash(w.s),
    );
    expect(v, isA<ChainVerified>());
    expect(v.securityEvent, isFalse);
    expect(w.verifier.verifyEnvelope(w.env), isA<ChainVerified>());
    // Only after verification is the content opened (04 §8.3).
    expect(w.env.open(w.s, w.key).object, {'amount_paise': 12500});
  });

  test('B-04-38 blob_hash mismatch is corruption, not tampering (ADR 05c §2): ChainCorrupt, no security event, checked before anything else', () async {
    final w = await world(seed: 41);
    final flipped = Uint8List.fromList(w.env.blob)..[100] ^= 0x01;
    final v = w.verifier.verifyEnvelope(
      withBlob(w.env, flipped),
      seq: 10,
      expectedBlobHash: w.env.blobHash(w.s),
    );
    expect(v, isA<ChainCorrupt>());
    expect(v.securityEvent, isFalse);
    // Same corrupted blob with NO stored hash to compare against: the
    // signature is what fails, and that IS a security event.
    expect(
      w.verifier.verifyEnvelope(withBlob(w.env, flipped), seq: 10),
      quarantine(QuarantineReason.sigInvalid),
    );
    // A hash mismatch wins even when the trust store is empty.
    final empty = ChainVerifier(w.s, MapTrustStore());
    expect(
      empty.verifyEnvelope(
        withBlob(w.env, flipped),
        expectedBlobHash: w.env.blobHash(w.s),
      ),
      isA<ChainCorrupt>(),
    );
  });

  test('B-04-39 the author\'s UMK must be ceremony-verified for this tenant (04 §3.4): an intact chain rooted in an unverified UMK is quarantined authorUnverified with a security event', () async {
    final w = await world(seed: 42);
    w.trust.umks.clear();
    expect(
      w.verifier.verifyEnvelope(w.env, seq: 1),
      quarantine(QuarantineReason.authorUnverified),
    );
    // Verified in a *different* tenant's store does not count: the store is
    // per tenant, so a fresh store without Alice behaves the same.
    final otherTenant = ChainVerifier(w.s, MapTrustStore(certs: w.trust.certs));
    expect(
      otherTenant.verifyEnvelope(w.env, seq: 1),
      quarantine(QuarantineReason.authorUnverified),
    );
  });

  test('B-04-40 certificate link: missing cert → certMissing; cert signed by another UMK or naming another device → certInvalid', () async {
    final w = await world(seed: 43);
    final mallory = UmkKeyPair.generate(w.s);
    addTearDown(mallory.dispose);

    // Missing.
    final saved = w.trust.certs.remove(deviceA)!;
    expect(
      w.verifier.verifyEnvelope(w.env, seq: 1),
      quarantine(QuarantineReason.certMissing),
    );

    // Server substitutes a cert for device A issued by Mallory's UMK but
    // labelled as Alice's ("ghost member", 04 §1.1).
    w.trust.certs[deviceA] = DeviceCert.issue(
      w.s,
      issuer: mallory,
      userId: userA,
      device: w.devA.public,
      issuedAtMs: issuedAt,
    );
    expect(
      w.verifier.verifyEnvelope(w.env, seq: 1),
      quarantine(QuarantineReason.certInvalid),
    );

    // A genuine cert filed under the wrong device id.
    w.trust.certs[deviceA] = DeviceCert.issue(
      w.s,
      issuer: w.alice,
      userId: userA,
      device: DevicePublic(
        deviceId: deviceB,
        ed25519: w.devA.public.ed25519,
        x25519: w.devA.public.x25519,
      ),
      issuedAtMs: issuedAt,
    );
    expect(
      w.verifier.verifyEnvelope(w.env, seq: 1),
      quarantine(QuarantineReason.certInvalid),
    );

    w.trust.certs[deviceA] = saved;
    expect(w.verifier.verifyEnvelope(w.env, seq: 1), isA<ChainVerified>());
  });

  test('B-04-41 author signature: an envelope signed by a device other than the certified one, or with a flipped signature byte, is quarantined sigInvalid (04 §8.3)', () async {
    final w = await world(seed: 44);
    // Forged: device B (uncertified) signs, then claims to be device A.
    final devB = DeviceKeyPair.generate(
      w.s,
      deviceId: deviceA,
    ); // same id, other keys
    addTearDown(devB.dispose);
    final forged = EnvelopeBuilder.seal(
      w.s,
      tenantId: tenantA,
      bookId: bookA,
      objectId: objectX,
      objectType: 'entry',
      envelopeId: envId,
      hlc: hlc0,
      authorSeq: 1,
      object: const {'amount_paise': 1},
      bookKey: w.key,
      author: devB,
    );
    expect(
      w.verifier.verifyEnvelope(forged, seq: 1),
      quarantine(QuarantineReason.sigInvalid),
    );

    final blob = Uint8List.fromList(w.env.blob)
      ..[24 + 5] ^= 0x01; // inside author_sig
    expect(
      w.verifier.verifyEnvelope(withBlob(w.env, blob), seq: 1),
      quarantine(QuarantineReason.sigInvalid),
    );
  });

  test('B-05b-6 revocation cut-off is the server seq (ADR 05b §5): seq 41 below a revocation at 42 stays valid; 42 and 43 are quarantined revoked; an unknown seq is refused conservatively', () async {
    final w = await world(seed: 45);
    w.trust.revocations[deviceA] = 42;
    expect(w.verifier.verifyEnvelope(w.env, seq: 41), isA<ChainVerified>());
    expect(
      w.verifier.verifyEnvelope(w.env, seq: 42),
      quarantine(QuarantineReason.revoked),
    );
    expect(
      w.verifier.verifyEnvelope(w.env, seq: 43),
      quarantine(QuarantineReason.revoked),
    );
    expect(
      w.verifier.verifyEnvelope(w.env),
      quarantine(QuarantineReason.revoked),
    );
    // HLC plays no part: a backdated HLC does not rescue a post-revocation envelope.
    final backdated = Envelope(
      suiteVersion: w.env.suiteVersion,
      tenantId: w.env.tenantId,
      bookId: w.env.bookId,
      objectId: w.env.objectId,
      objectType: w.env.objectType,
      keyVersion: w.env.keyVersion,
      payloadSchema: w.env.payloadSchema,
      nonce: w.env.nonce,
      ciphertext: w.env.ciphertext,
      authorDeviceId: w.env.authorDeviceId,
      authorSig: w.env.authorSig,
      hlc: 1,
      envelopeId: w.env.envelopeId,
    );
    expect(
      w.verifier.verifyEnvelope(backdated, seq: 42),
      quarantine(QuarantineReason.revoked),
    );
    w.trust.revocations.clear();
    expect(w.verifier.verifyEnvelope(w.env), isA<ChainVerified>());
  });

  test('B-05b-7 a signed record walks the same chain (ADR 05b §1): verified when authored on a certified device of a verified member; certMissing / sigInvalid / revoked otherwise', () async {
    final w = await world(seed: 46);
    final payload = Uint8List.fromList(
      utf8.encode('{"user_id":"$userB","status":"active"}'),
    );
    final rec = SignedRecord.sign(
      w.s,
      tenantId: tenantA,
      kind: SignedRecordKind.membershipStatus,
      payloadJson: payload,
      hlc: hlc0,
      author: w.devA,
    ).withSeq(100);
    expect(w.verifier.verifySignedRecord(rec), isA<ChainVerified>());

    // Tampered payload → sigInvalid.
    final tampered = SignedRecord(
      suiteVersion: rec.suiteVersion,
      tenantId: rec.tenantId,
      kind: rec.kind,
      payloadJson: Uint8List.fromList(
        utf8.encode('{"user_id":"$userB","status":"blocked"}'),
      ),
      authorDeviceId: rec.authorDeviceId,
      authorSig: rec.authorSig,
      hlc: rec.hlc,
      seq: rec.seq,
    );
    expect(
      w.verifier.verifySignedRecord(tampered),
      quarantine(QuarantineReason.sigInvalid),
    );

    // Authored by an uncertified device → certMissing (the "bare row" of 05b §2 has no record at all).
    final rogue = DeviceKeyPair.generate(w.s, deviceId: deviceB);
    addTearDown(rogue.dispose);
    final rogueRec = SignedRecord.sign(
      w.s,
      tenantId: tenantA,
      kind: SignedRecordKind.deviceRevocation,
      payloadJson: payload,
      hlc: hlc0,
      author: rogue,
    );
    expect(
      w.verifier.verifySignedRecord(rogueRec),
      quarantine(QuarantineReason.certMissing),
    );

    // The author device was itself revoked at seq 90: its record at 100 is refused.
    w.trust.revocations[deviceA] = 90;
    expect(
      w.verifier.verifySignedRecord(rec),
      quarantine(QuarantineReason.revoked),
    );
    expect(
      w.verifier.verifySignedRecord(rec.withSeq(89)),
      isA<ChainVerified>(),
    );
  });

  test('B-04-42 an unknown suite_version is quarantined suiteUnsupported (04 §8.5 — only 0x01 exists today)', () async {
    final w = await world(seed: 47);
    expect(
      w.verifier.verifyEnvelope(
        withBlob(w.env, w.env.blob, suiteVersion: 0x02),
        seq: 1,
      ),
      quarantine(QuarantineReason.suiteUnsupported),
    );
  });
}
