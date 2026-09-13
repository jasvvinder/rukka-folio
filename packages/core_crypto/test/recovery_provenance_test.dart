// Suite B — provenance of `expected` at recovery rung 2 (04 §7.3 steps 2–4;
// ADR 2026-09-13c §1, §3; escalation lane M7-K3, 13 Sep 2026).
//
// Ids B-04-82 … B-04-84. The question these pin is not "does Shamir work" but
// "whose copy of the UMK public key does a fresh device check the result
// against". A fresh phone holds nothing of the user's; the server holds the
// registered key (06 §3 item 3); `crypto_box_seal` names no sender (04 §2).
// So the check is only as strong as the provenance of `expected`, and the
// ruling makes it a `VerifiedUmkPublic` that a human channel produced.
// Test code may use dart:io — the purity rule binds lib/.
@Tags(['B'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Synthetic guardian user ids (never real).
const List<String> _guardianIds = [
  '55555555-5555-4555-8555-555555555551',
  '55555555-5555-4555-8555-555555555552',
  '55555555-5555-4555-8555-555555555553',
];

/// A fixed, synthetic certificate timestamp (injected — no clock in lib/).
const int _issuedAt = 1757700000000;

/// 04 §7.3 **setup** as the honest devices run it: the user's `UMK_priv`
/// split 2-of-3, each share sealed to a guardian the user verified by the
/// mutual ceremony, and every guardian device keeping the *user's* key as a
/// [VerifiedUmkPublic] from the same ceremony (04 §6.4 "guardian setup is
/// mutual"). The splitting device keeps nothing.
final class _Household {
  _Household._(
    this.s,
    this.user,
    this.guardians,
    this.stored,
    this.userOnGuardian,
  );

  /// The `share_set_version` of this split.
  static const int version = 4;

  static Future<_Household> honest({int seed = 82}) async {
    final s = await testSuite(seed: seed);
    final user = UmkKeyPair.generate(s);
    final guardians = [for (var i = 0; i < 3; i++) UmkKeyPair.generate(s)];
    addTearDown(user.dispose);
    for (final g in guardians) {
      addTearDown(g.dispose);
    }
    final priv = user.exportSecretBytes();
    final shares = GuardianShareSet.create(
      s,
      umkSecret: priv,
      n: 3,
      shareSetVersion: version,
    );
    s.zeroize(priv);
    final stored = <SealedBlob>[];
    for (var i = 0; i < 3; i++) {
      // The user's device verified guardian i (their side of the mutual
      // ceremony) and seals only to that type (04 §8.2).
      final wire = shares[i].encode();
      stored.add(
        sealToVerified(
          s,
          verifiedUmk(s, guardians[i], userId: _guardianIds[i]),
          wire,
        ),
      );
      s.zeroize(wire);
      shares[i].dispose();
    }
    // Guardian i's device verified the *user* in the other direction; this
    // is the copy it will show at recovery.
    final userOnGuardian = verifiedUmk(s, user, userId: userA);
    return _Household._(s, user, guardians, stored, userOnGuardian);
  }

  final CryptoSuite s;
  final UmkKeyPair user;
  final List<UmkKeyPair> guardians;

  /// `share_i` sealed to guardian i, as the server stores it.
  final List<SealedBlob> stored;

  /// The user's UMK as each guardian's device holds it after mutual setup.
  final VerifiedUmkPublic userOnGuardian;

  /// Step 3, honest guardian [i]: open the stored share, re-seal it to the
  /// candidate the guardian's device verified by ceremony (ruling 3 — the
  /// candidate is modelled as a [UmkKeyPair] so the re-seal can go through
  /// `sealToVerified`; M11 may use the device X25519 half and
  /// `VerifiedDevicePublic` instead — the direction under test here is the
  /// other one).
  SealedBlob reseal(int i, VerifiedUmkPublic candidate) {
    final plain = openSealed(s, guardians[i], stored[i]);
    try {
      return sealToVerified(s, candidate, plain);
    } finally {
      s.zeroize(plain);
    }
  }

  /// What the guardian's screen renders for ruling 1: the *user's* key, from
  /// the guardian's ceremony-verified copy, as the 04 §6.1 payload.
  String showUsersKey() => QrPayload(
    userId: userA,
    umk: userOnGuardian.public,
    nonce: s.randomBytes(ceremonyNonceBytes),
  ).encode();

  /// What a malicious server can make on its own: shares of *its own* key,
  /// sealed to the candidate public key it learned in step 1. The box names
  /// no sender, so these are indistinguishable from a guardian's re-seal.
  static List<SealedBlob> forgedBoxes(
    CryptoSuite s,
    UmkKeyPair serverKey,
    UmkPublic candidate, {
    int k = 2,
  }) {
    final priv = serverKey.exportSecretBytes();
    final shares = GuardianShareSet.create(
      s,
      umkSecret: priv,
      n: 3,
      shareSetVersion: version,
    );
    s.zeroize(priv);
    final out = <SealedBlob>[];
    for (var i = 0; i < k; i++) {
      final wire = shares[i].encode();
      out.add(
        SealedBlob(
          recipient: Fingerprint.of(s, candidate),
          bytes: s.sodium.crypto.box.seal(
            message: wire,
            publicKey: candidate.x25519,
          ),
        ),
      );
      s.zeroize(wire);
    }
    for (final sh in shares) {
      sh.dispose();
    }
    return out;
  }
}

/// The fresh device's side of the recovery ceremony (ruling 1): decode what
/// the camera saw and run 04 §6.3's QR check against what the server relayed
/// as this user's registered key.
CeremonyResult _recoveryCeremony(
  CryptoSuite s, {
  required String shown,
  required UmkPublic relayed,
}) => Ceremony.verifyQr(
  s,
  scanned: QrPayload.decode(shown),
  relayed: relayed,
  relayedUserId: userA,
);

/// The fresh device opens the boxes addressed to its candidate key.
List<GuardianShare> _open(
  CryptoSuite s,
  UmkKeyPair candidate,
  List<SealedBlob> boxes,
) => [for (final b in boxes) GuardianShare.decode(openSealed(s, candidate, b))];

void main() {
  group('provenance of `expected` (ADR 2026-09-13c §1)', () {
    test('B-04-82 reconstructVerified takes only a VerifiedUmkPublic — the signature names the type and no UmkPublic overload exists — and the honest recovery ceremony supplies it: a guardian\'s device shows the user\'s ceremony-verified UMK as a QrPayload, the fresh device verifies it byte-for-byte against the server-relayed registered key, and k re-sealed shares reconstruct the UMK (04 §7.3 steps 2–4)', () async {
      // Static: the type is the rule. `\bUmkPublic` does not match inside
      // `VerifiedUmkPublic` (no word boundary between `d` and `U`).
      final src = File('lib/src/shamir.dart').readAsStringSync();
      final sig = RegExp(
        r'static UmkKeyPair reconstructVerified\([\s\S]*?\}\) \{',
      ).firstMatch(src);
      expect(sig, isNotNull, reason: 'reconstructVerified must exist');
      expect(sig!.group(0), contains('required VerifiedUmkPublic expected'));
      expect(
        RegExp(r'\bUmkPublic expected').hasMatch(src),
        isFalse,
        reason: 'a server-relayed UmkPublic must not be accepted anywhere',
      );
      expect(
        src.contains('VerifiedUmkPublic.internal('),
        isFalse,
        reason: 'shamir.dart mints no verified key (B-04-80 covers the repo)',
      );

      final w = await _Household.honest();
      final s = w.s;
      // Step 1: the candidate key on the fresh phone.
      final candidate = UmkKeyPair.generate(s);
      addTearDown(candidate.dispose);
      // Ruling 3 (mirror): the guardian's device verified the candidate
      // before re-sealing anything to it.
      final candidateOnGuardian = verifiedUmk(s, candidate, userId: userA);
      // Step 3: two of three guardians approve.
      final boxes = [
        w.reseal(0, candidateOnGuardian),
        w.reseal(2, candidateOnGuardian),
      ];
      // Ruling 1: the guardian's screen shows the *user's* key; the fresh
      // device checks it against an honest relay.
      final r = _recoveryCeremony(
        s,
        shown: w.showUsersKey(),
        relayed: w.user.public,
      );
      expect(r, isA<CeremonyVerified>());
      final expected = (r as CeremonyVerified).verified;
      expect(expected.fingerprint, Fingerprint.of(s, w.user.public));
      expect(expected.method, VerificationMethod.qrInPerson);
      // Step 4.
      final opened = _open(s, candidate, boxes);
      final pair = GuardianShareSet.reconstructVerified(
        s,
        opened,
        expected: expected,
      );
      expect(pair.public, w.user.public);
      final priv = w.user.exportSecretBytes();
      final got = pair.exportSecretBytes();
      expect(got, priv);
      s.zeroize(priv);
      s.zeroize(got);
      pair.dispose();
      // Transit is still the sealed box (04 §7.3 step 3): a third guardian
      // cannot open a box addressed to the candidate.
      expect(
        () => openSealed(s, w.guardians[1], boxes[0]),
        throwsA(isA<UnsealFailed>()),
      );
    });

    test('B-04-83 a server that substitutes the registered UMK and the sealed boxes gets no reconstruction: against an honest guardian\'s screen the recovery ceremony fails CeremonyMismatch, so no VerifiedUmkPublic exists to reconstruct against; relaying the true key to pass the ceremony but forging the boxes fails GuardianShareMismatch with the caller\'s shares intact; a forged share mixed with a real one fails; the residual — the scanned device itself showing the server\'s key — is the documented collusion bound (04 §1.1 rows 1 and 3, §3.4)', () async {
      final w = await _Household.honest(seed: 83);
      final s = w.s;
      final server = UmkKeyPair.generate(s); // UMK′ — the server knows it all
      final candidate = UmkKeyPair.generate(s);
      addTearDown(server.dispose);
      addTearDown(candidate.dispose);
      final candidateOnGuardian = verifiedUmk(s, candidate, userId: userA);
      final shown = w.showUsersKey();

      // (i) Full substitution: registered key = UMK′, boxes forged. Before the
      // ruling this was the passing path — the forged shares reconstruct UMK′
      // and UMK′ re-derives exactly the key the server relayed. Only
      // provenance stops it.
      final forged = _open(
        s,
        candidate,
        _Household.forgedBoxes(s, server, candidate.public),
      );
      final raw = GuardianShareSet.reconstruct(forged);
      final rawPair = UmkKeyPair.fromSecretBytes(s, raw);
      s.zeroize(raw);
      expect(
        rawPair.public,
        server.public,
        reason: 'the attack payload is self-consistent',
      );
      rawPair.dispose();
      // The ceremony sees real (scanned) ≠ UMK′ (relayed): hard fail. There
      // is no `expected`, and the type system leaves nothing else to call.
      expect(
        _recoveryCeremony(s, shown: shown, relayed: server.public),
        isA<CeremonyMismatch>(),
      );

      // (ii) Relay the true key so the ceremony passes; forge the boxes.
      final r = _recoveryCeremony(s, shown: shown, relayed: w.user.public);
      final expected = (r as CeremonyVerified).verified;
      final snapshot = [for (final g in forged) Uint8List.fromList(g.bytes)];
      expect(
        () =>
            GuardianShareSet.reconstructVerified(s, forged, expected: expected),
        throwsA(isA<GuardianShareMismatch>()),
      );
      for (var i = 0; i < forged.length; i++) {
        expect(forged[i].isDisposed, isFalse);
        expect(forged[i].bytes, snapshot[i], reason: 'share ${i + 1} altered');
      }

      // (iii) One real re-sealed share plus one forged: garbage → mismatch.
      final real0 = _open(s, candidate, [
        w.reseal(0, candidateOnGuardian),
      ]).single;
      expect(
        () => GuardianShareSet.reconstructVerified(s, [
          real0,
          forged[1],
        ], expected: expected),
        throwsA(isA<GuardianShareMismatch>()),
      );
      // Two real ones still recover — the attempt did not harm the honest path.
      final real2 = _open(s, candidate, [
        w.reseal(2, candidateOnGuardian),
      ]).single;
      final ok = GuardianShareSet.reconstructVerified(s, [
        real0,
        real2,
      ], expected: expected);
      expect(ok.public, w.user.public);
      ok.dispose();

      // (iv) Substitute the key but not the boxes: fails as in (i).
      expect(
        _recoveryCeremony(s, shown: shown, relayed: server.public),
        isA<CeremonyMismatch>(),
      );
      // (v) A relay that disagrees on the user id fails too (04 §6.3).
      expect(
        Ceremony.verifyQr(
          s,
          scanned: QrPayload.decode(shown),
          relayed: w.user.public,
          relayedUserId: userB,
        ),
        isA<CeremonyMismatch>(),
      );

      // The residual, on the record (ADR 2026-09-13c §4): if the *scanned*
      // screen itself carries UMK′ — a colluding guardian, or malware on their
      // phone (04 §1.2) — scanned = relayed and the ceremony cannot tell.
      // Server + the one device the user chose to scan from is the bound: the
      // same single-verifier assumption every 04 §6 ceremony makes. A design
      // that requires two independent scans (checklist 4) supersedes this
      // block.
      final colluding = QrPayload(
        userId: userA,
        umk: server.public,
        nonce: s.randomBytes(ceremonyNonceBytes),
      ).encode();
      final rc = _recoveryCeremony(s, shown: colluding, relayed: server.public);
      expect(rc, isA<CeremonyVerified>());
      final bound = GuardianShareSet.reconstructVerified(
        s,
        forged,
        expected: (rc as CeremonyVerified).verified,
      );
      expect(bound.public, server.public);
      bound.dispose();
    });
  });

  group('option (b) is circular (ADR 2026-09-13c §3)', () {
    test('B-04-84 a guardian-signed re-sealed share cannot anchor a fresh device: with an empty TrustStore the chain verifier quarantines it (certMissing, then authorUnverified once the relayed cert is stored); a store seeded from the server\'s relay lets a server-fabricated guardian — ghost UMK, self-issued cert, signed share — verify end to end; only a human-verified guardian root tells the two apart, and that is the ceremony of ruling 1 applied once per guardian (04 §3.4)', () async {
      final s = await testSuite(seed: 84);
      // The real guardian: UMK_g, a device, its self-issued cert (04 §3.4).
      final realG = UmkKeyPair.generate(s);
      final realDev = DeviceKeyPair.generate(s, deviceId: deviceA);
      addTearDown(realG.dispose);
      addTearDown(realDev.dispose);
      final realCert = DeviceCert.issue(
        s,
        issuer: realG,
        userId: userB,
        device: realDev.public,
        issuedAtMs: _issuedAt,
      );
      // Option (b)'s artefact: the re-sealed share carried in a signed record
      // (a hypothetical kind — kinds are open strings, 05b §1).
      final payload = Uint8List.fromList(
        utf8.encode(
          '{"subject_user_id":"$userA","share_set_version":4,"box":"…"}',
        ),
      );
      final realRecord = SignedRecord.sign(
        s,
        tenantId: tenantA,
        kind: 'recovery_share',
        payloadJson: payload,
        hlc: 1,
        author: realDev,
      ).withSeq(10);
      expect(realRecord.verifySignature(s, realDev.public), isTrue);

      // A fresh device holds nothing verified. The relay can hand it the
      // cert; it cannot hand it a *human's* confirmation of UMK_g — the user's
      // old verification of the guardian is a signed record rooted in the
      // user's own UMK, the key being recovered.
      final fresh = MapTrustStore();
      expect(
        ChainVerifier(s, fresh).verifySignedRecord(realRecord),
        isA<ChainQuarantine>().having(
          (q) => q.reason,
          'reason',
          QuarantineReason.certMissing,
        ),
      );
      fresh.certs[deviceA] = realCert;
      expect(
        ChainVerifier(s, fresh).verifySignedRecord(realRecord),
        isA<ChainQuarantine>().having(
          (q) => q.reason,
          'reason',
          QuarantineReason.authorUnverified,
        ),
      );

      // The server fabricates a guardian wholesale.
      final ghostG = UmkKeyPair.generate(s);
      final ghostDev = DeviceKeyPair.generate(s, deviceId: deviceB);
      addTearDown(ghostG.dispose);
      addTearDown(ghostDev.dispose);
      final ghostCert = DeviceCert.issue(
        s,
        issuer: ghostG,
        userId: userB,
        device: ghostDev.public,
        issuedAtMs: _issuedAt,
      );
      final ghostRecord = SignedRecord.sign(
        s,
        tenantId: tenantA,
        kind: 'recovery_share',
        payloadJson: payload,
        hlc: 2,
        author: ghostDev,
      ).withSeq(11);

      // Relay-rooted: the device takes "the guardian's UMK" from the server's
      // copy (modelled by minting the verified type over the ghost key).
      // Everything the server made now verifies — the signature added no fact
      // the relay had not already asserted.
      final relayRooted = MapTrustStore(
        umks: {userB: verifiedUmk(s, ghostG, userId: userB)},
        certs: {deviceB: ghostCert},
      );
      expect(
        ChainVerifier(s, relayRooted).verifySignedRecord(ghostRecord),
        isA<ChainVerified>(),
      );

      // Human-rooted: the guardian's own key verified by ceremony from the
      // guardian's screen. The real record verifies; the ghost's cert fails
      // under the real key. This works — but it is one ceremony per
      // contributing guardian to authenticate the *sources*, where ruling 1
      // authenticates the *target* in one, and the key then authenticates
      // the shares (ADR 2026-09-06 §2).
      final humanRooted = MapTrustStore(
        umks: {userB: verifiedUmk(s, realG, userId: userB)},
        certs: {deviceA: realCert, deviceB: ghostCert},
      );
      expect(
        ChainVerifier(s, humanRooted).verifySignedRecord(realRecord),
        isA<ChainVerified>(),
      );
      expect(
        ChainVerifier(s, humanRooted).verifySignedRecord(ghostRecord),
        isA<ChainQuarantine>().having(
          (q) => q.reason,
          'reason',
          QuarantineReason.certInvalid,
        ),
      );
    });
  });
}
