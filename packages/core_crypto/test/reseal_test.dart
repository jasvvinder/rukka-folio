// Suite B — the guardian's re-seal (04 §7.3 step 3; ADR 2026-09-13c §3 🔒;
// escalation lane M11-RV6, 19 Sep 2026).
//
// Ids B-04-85, B-04-93. Ruling 1 (B-04-82…84) made the fresh device check the
// UMK it recovers *into* against a human channel. Ruling 3 is the mirror: a
// server that swaps the candidate public key in the recovery request would
// have k guardians re-seal the **real** shares to a server key. 04 §7.3
// step 2's "Call them before approving" becomes a check — the guardian's
// device scans the fresh device's `DeviceQrPayload`, compares it against the
// relayed request, and the re-seal accepts **only the verified type**. The
// server half (E-06-45, E-06-49, E-06-54) binds the declared sealing key to
// the request; this half makes the wrong key impossible to seal to.
// Test code may use dart:io — the purity rule binds lib/.
@Tags(['B'])
library;

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

/// A third synthetic device id — the attacker's phone.
const String _deviceC = '33333333-3333-4333-8333-333333333333';

/// 04 §7.3 **setup** as the honest devices run it: `UMK_priv` split 2-of-3,
/// each share sealed to a guardian the user verified by the mutual ceremony,
/// and every guardian device keeping the *user's* key as a
/// [VerifiedUmkPublic] (04 §6.4 "guardian setup is mutual").
final class _Household {
  _Household._(this.s, this.user, this.guardians, this.stored, this.userOnG);

  /// The `share_set_version` of this split.
  static const int version = 4;

  static Future<_Household> honest({int seed = 85}) async {
    final s = await testSuite(seed: seed);
    final user = UmkKeyPair.generate(s);
    final guardians = [for (var i = 0; i < 3; i++) UmkKeyPair.generate(s)];
    addTearDown(user.dispose);
    for (final g in guardians) {
      addTearDown(g.dispose);
    }
    final stored = _splitAndSeal(s, user, guardians, version);
    return _Household._(
      s,
      user,
      guardians,
      stored,
      verifiedUmk(s, user, userId: userA),
    );
  }

  /// Splits [user]'s secret under [ver] and seals share i to guardian i.
  static List<SealedBlob> _splitAndSeal(
    CryptoSuite s,
    UmkKeyPair user,
    List<UmkKeyPair> guardians,
    int ver,
  ) {
    final priv = user.exportSecretBytes();
    final shares = GuardianShareSet.create(
      s,
      umkSecret: priv,
      n: 3,
      shareSetVersion: ver,
    );
    s.zeroize(priv);
    final out = <SealedBlob>[];
    for (var i = 0; i < 3; i++) {
      final wire = shares[i].encode();
      out.add(
        sealToVerified(
          s,
          verifiedUmk(s, guardians[i], userId: _guardianIds[i]),
          wire,
        ),
      );
      s.zeroize(wire);
      shares[i].dispose();
    }
    return out;
  }

  final CryptoSuite s;
  final UmkKeyPair user;
  final List<UmkKeyPair> guardians;

  /// `share_i` sealed to guardian i, as the server stores it.
  final List<SealedBlob> stored;

  /// The user's UMK as each guardian's device holds it after mutual setup.
  final VerifiedUmkPublic userOnG;

  /// What the guardian's screen renders for ruling 1 — the *user's* key.
  String showUsersKey() => QrPayload(
    userId: userA,
    umk: userOnG.public,
    nonce: s.randomBytes(ceremonyNonceBytes),
  ).encode();
}

/// A fresh phone at 04 §7.3 step 1: device keys, a candidate pair, and the
/// request the server relays to the guardians.
final class _FreshPhone {
  _FreshPhone(CryptoSuite s, {String deviceId = deviceB})
    : device = DeviceKeyPair.generate(s, deviceId: deviceId),
      candidate = RecoveryCandidateKeyPair.generate(s) {
    addTearDown(device.dispose);
    addTearDown(candidate.dispose);
  }

  final DeviceKeyPair device;
  final RecoveryCandidateKeyPair candidate;

  /// The request as the server stores and relays it (0010:
  /// `candidate_device`, `candidate_pub_x`).
  String get relayedDeviceId => device.deviceId;
  Uint8List get relayedPubX => candidate.x25519;

  /// *Show my code* on the fresh phone (ADR 2026-09-13c §3).
  String show(CryptoSuite s) => DeviceQrPayload(
    device: candidate.asCandidateOf(device.public),
    nonce: s.randomBytes(ceremonyNonceBytes),
  ).encode();
}

/// The guardian's device: scan, then compare against the relayed request.
RecoveryCandidateResult _guardianScans(
  CryptoSuite s, {
  required String shown,
  required String relayedDeviceId,
  required Uint8List relayedPubX,
}) => Ceremony.verifyRecoveryCandidateQr(
  s,
  scanned: DeviceQrPayload.decode(shown),
  relayedDeviceId: relayedDeviceId,
  relayedCandidateX25519: relayedPubX,
);

void main() {
  group('the guardian re-seals only to a verified candidate (ADR 2026-09-13c §3)', () {
    test('B-04-85 the share re-seal\'s recipient parameter is a Verified* type: resealShareToCandidate takes only VerifiedRecoveryCandidate, which has no constructor outside ceremony.dart; every crypto_box_seal call site in lib/ seals to a parameter declared as a Verified* type, so no seal of share bytes to UmkPublic, DevicePublic or a raw X25519 key exists; and the honest run — fresh phone shows its candidate key as a DeviceQrPayload, the guardian\'s device verifies it against the relayed request, re-seals, the fresh device opens k shares and reconstructs the UMK against the ruling-1 ceremony — goes through (04 §7.3 steps 1–4)', () async {
      // ---- Static: the type is the rule. ------------------------------------
      final lib = Directory('lib/src')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final wrapping = File('lib/src/wrapping.dart').readAsStringSync();
      final sig = RegExp(
        r'ResealedShare resealShareToCandidate\([\s\S]*?\}\) \{',
      ).firstMatch(wrapping);
      expect(sig, isNotNull, reason: 'resealShareToCandidate must exist');
      expect(
        sig!.group(0),
        contains('required VerifiedRecoveryCandidate candidate'),
      );
      for (final bad in ['UmkPublic', 'DevicePublic', 'Uint8List']) {
        expect(
          RegExp('\\b$bad candidate\\b').hasMatch(wrapping),
          isFalse,
          reason: 'no recipient of type $bad anywhere in wrapping.dart',
        );
      }

      // The verified type is minted in ceremony.dart and nowhere else, by a
      // private constructor: no `VerifiedRecoveryCandidate(` call exists.
      var privateCtorUses = 0;
      for (final f in lib) {
        final src = f.readAsStringSync();
        expect(
          RegExp(r'(?<![\w.])VerifiedRecoveryCandidate\(').hasMatch(src),
          isFalse,
          reason: '${f.path}: no public constructor call',
        );
        final n = RegExp(r'VerifiedRecoveryCandidate\._\(').allMatches(src);
        if (n.isNotEmpty) {
          expect(f.path, endsWith('ceremony.dart'));
          privateCtorUses += n.length;
        }
      }
      expect(
        privateCtorUses,
        2,
        reason: 'declaration + the one use in verifyRecoveryCandidateQr',
      );

      // Every sealed box made in lib/ goes to a parameter whose declared type
      // is Verified*: sealToVerified (VerifiedUmkPublic), wrapUmkToDevice
      // (VerifiedDevicePublic), resealShareToCandidate
      // (VerifiedRecoveryCandidate). The scan finds each call, reads the
      // root variable of its `publicKey:` argument and requires a Verified*
      // declaration of that variable in the enclosing signature.
      final sealCall = RegExp(
        r'\.seal\(\s*message:\s*[^,]+,\s*publicKey:\s*([A-Za-z_]\w*)((?:\.\w+)*)\s*,?\s*\)',
      );
      var sealSites = 0;
      for (final f in lib) {
        final src = f.readAsStringSync();
        for (final m in sealCall.allMatches(src)) {
          sealSites++;
          final root = m.group(1)!;
          final before = src.substring(
            m.start > 2500 ? m.start - 2500 : 0,
            m.start,
          );
          final decl = RegExp(
            'Verified(UmkPublic|DevicePublic|RecoveryCandidate)\\s+$root\\b',
          );
          expect(
            decl.hasMatch(before),
            isTrue,
            reason:
                '${f.path}: box.seal publicKey `$root${m.group(2)}` is not a '
                'Verified* parameter',
          );
        }
      }
      expect(sealSites, 3, reason: 'three sealing functions, no more');

      // ---- Dynamic: the honest run, steps 1–4. ------------------------------
      final w = await _Household.honest();
      final s = w.s;
      final fresh = _FreshPhone(s);

      // Step 2, made a check: the guardian scans the phone on the call and
      // compares against the relayed request.
      final r0 = _guardianScans(
        s,
        shown: fresh.show(s),
        relayedDeviceId: fresh.relayedDeviceId,
        relayedPubX: fresh.relayedPubX,
      );
      expect(r0, isA<RecoveryCandidateVerified>());
      final verified = (r0 as RecoveryCandidateVerified).verified;
      expect(verified.deviceId, deviceB);
      expect(verified.x25519, fresh.candidate.x25519);
      expect(verified.method, VerificationMethod.qrInPerson);

      // Step 3: guardians 1 and 3 approve — open own share, re-seal to the
      // verified candidate. The stored blob is untouched and still theirs.
      final snapshot0 = Uint8List.fromList(w.stored[0].bytes);
      final re0 = resealShareToCandidate(
        s,
        guardian: w.guardians[0],
        stored: w.stored[0],
        candidate: verified,
      );
      final re2 = resealShareToCandidate(
        s,
        guardian: w.guardians[2],
        stored: w.stored[2],
        candidate: verified,
      );
      expect(w.stored[0].bytes, snapshot0, reason: 'stored share unchanged');
      final still = openSealed(s, w.guardians[0], w.stored[0]);
      expect(still.length, greaterThan(GuardianShare.headerLength));
      s.zeroize(still);
      // What the wire carries (E-06-45): the key it sealed to is exactly the
      // request's candidate key, the row is addressed to the candidate device,
      // and the generation comes from the share's own header.
      expect(re0.sealedTo, fresh.relayedPubX);
      expect(re0.deviceId, deviceB);
      expect(re0.shareSetVersion, _Household.version);
      expect(re0.suiteVersion, suiteVersion);
      expect(re0.bytes, isNot(re2.bytes));
      expect(
        re0.bytes.length,
        inInclusiveRange(1, 4096),
        reason: '0010 accepts 1..4096 opaque bytes',
      );

      // Step 4 on the fresh device: open both, run the ruling-1 ceremony for
      // `expected`, reconstruct.
      final sh0 = openResealedShare(s, re0, fresh.candidate);
      final sh2 = openResealedShare(s, re2, fresh.candidate);
      expect(sh0.index, 1);
      expect(sh2.index, 3);
      expect(sh0.shareSetVersion, _Household.version);
      final r1 = Ceremony.verifyQr(
        s,
        scanned: QrPayload.decode(w.showUsersKey()),
        relayed: w.user.public,
        relayedUserId: userA,
      );
      final expected = (r1 as CeremonyVerified).verified;
      final pair = GuardianShareSet.reconstructVerified(s, [
        sh0,
        sh2,
      ], expected: expected);
      expect(pair.public, w.user.public);
      final a = w.user.exportSecretBytes();
      final b = pair.exportSecretBytes();
      expect(b, a);
      s.zeroize(a);
      s.zeroize(b);
      pair.dispose();
      sh0.dispose();
      sh2.dispose();

      // Transit stays sealed (04 §7.3 step 3): another candidate pair cannot
      // open it — by recipient, and by box when the label is doctored.
      final other = RecoveryCandidateKeyPair.generate(s);
      addTearDown(other.dispose);
      expect(
        () => openResealedShare(s, re0, other),
        throwsA(
          isA<UnsealFailed>().having((e) => e.reason, 'reason', 'recipient'),
        ),
      );
      final relabelled = ResealedShare(
        deviceId: re0.deviceId,
        sealedTo: other.x25519,
        shareSetVersion: re0.shareSetVersion,
        bytes: re0.bytes,
      );
      expect(
        () => openResealedShare(s, relabelled, other),
        throwsA(isA<UnsealFailed>().having((e) => e.reason, 'reason', 'box')),
      );
    });

    test('B-04-93 the substitution run the other way fails at the guardian\'s scan: a relay that swaps candidate_pub_x for its own key → RecoveryCandidateMismatch against the true phone, so no VerifiedRecoveryCandidate exists and nothing can be re-sealed to the server key; an attacker\'s phone under the true request, the true key under another device id, or a wrong id all mismatch; the server\'s own pair opens no honest re-seal; a share re-sealed for attempt A names A\'s key and cannot be opened by B (E-06-49/E-06-54\'s mirror); malformed inputs are refused, never guessed; the residual — the guardian scanning the attacker\'s own phone — is the documented human-channel bound (04 §6.4)', () async {
      final w = await _Household.honest(seed: 93);
      final s = w.s;
      final fresh = _FreshPhone(s); // the user's real new phone
      final server = RecoveryCandidateKeyPair.generate(s); // S — the relay's
      addTearDown(server.dispose);
      final shown = fresh.show(s);

      // (i) Relay substitutes the key; the guardian scans the true phone.
      final ri = _guardianScans(
        s,
        shown: shown,
        relayedDeviceId: fresh.relayedDeviceId,
        relayedPubX: server.x25519,
      );
      expect(ri, isA<RecoveryCandidateMismatch>());
      // There is no verified value, and the type system leaves nothing else
      // to call: the only re-seal takes VerifiedRecoveryCandidate (B-04-85).

      // (ii) Relay honest; the phone on the call is the attacker's (its own
      // candidate key under the request's device id, or its own device id).
      final attacker = _FreshPhone(s, deviceId: _deviceC);
      final spoofedId = DeviceQrPayload(
        device: DevicePublic(
          deviceId: fresh.relayedDeviceId, // claims to be the real phone
          ed25519: attacker.device.public.ed25519,
          x25519: attacker.candidate.x25519,
        ),
        nonce: s.randomBytes(ceremonyNonceBytes),
      ).encode();
      expect(
        _guardianScans(
          s,
          shown: spoofedId,
          relayedDeviceId: fresh.relayedDeviceId,
          relayedPubX: fresh.relayedPubX,
        ),
        isA<RecoveryCandidateMismatch>(),
        reason: 'true id, attacker key',
      );
      expect(
        _guardianScans(
          s,
          shown: attacker.show(s),
          relayedDeviceId: fresh.relayedDeviceId,
          relayedPubX: fresh.relayedPubX,
        ),
        isA<RecoveryCandidateMismatch>(),
        reason: 'attacker id and key',
      );
      // The true key shown under another device id fails too (04 §6.3: ids
      // must agree), as does one flipped key byte.
      final trueKeyOtherId = DeviceQrPayload(
        device: DevicePublic(
          deviceId: _deviceC,
          ed25519: fresh.device.public.ed25519,
          x25519: fresh.candidate.x25519,
        ),
        nonce: s.randomBytes(ceremonyNonceBytes),
      ).encode();
      expect(
        _guardianScans(
          s,
          shown: trueKeyOtherId,
          relayedDeviceId: fresh.relayedDeviceId,
          relayedPubX: fresh.relayedPubX,
        ),
        isA<RecoveryCandidateMismatch>(),
      );
      final flipped = Uint8List.fromList(fresh.relayedPubX)..[5] ^= 0x10;
      expect(
        _guardianScans(
          s,
          shown: shown,
          relayedDeviceId: fresh.relayedDeviceId,
          relayedPubX: flipped,
        ),
        isA<RecoveryCandidateMismatch>(),
      );

      // (iii) The honest re-seal, and the server's pair against it.
      final ok = _guardianScans(
        s,
        shown: shown,
        relayedDeviceId: fresh.relayedDeviceId,
        relayedPubX: fresh.relayedPubX,
      );
      final verified = (ok as RecoveryCandidateVerified).verified;
      final reA = resealShareToCandidate(
        s,
        guardian: w.guardians[1],
        stored: w.stored[1],
        candidate: verified,
      );
      expect(
        () => openResealedShare(s, reA, server),
        throwsA(
          isA<UnsealFailed>().having((e) => e.reason, 'reason', 'recipient'),
        ),
      );
      expect(
        () => openResealedShare(
          s,
          ResealedShare(
            deviceId: reA.deviceId,
            sealedTo: server.x25519,
            shareSetVersion: reA.shareSetVersion,
            bytes: reA.bytes,
          ),
          server,
        ),
        throwsA(isA<UnsealFailed>().having((e) => e.reason, 'reason', 'box')),
      );

      // (iv) Two live attempts from two fresh phones (E-06-49): a share
      // re-sealed for A names A's key — which is what rf.recovery_decide
      // compares — and B's pair cannot open it.
      final phoneB = _FreshPhone(s, deviceId: _deviceC);
      expect(reA.sealedTo, fresh.relayedPubX);
      expect(reA.sealedTo, isNot(phoneB.relayedPubX));
      expect(
        () => openResealedShare(s, reA, phoneB.candidate),
        throwsA(
          isA<UnsealFailed>().having((e) => e.reason, 'reason', 'recipient'),
        ),
      );
      // The fresh phone itself opens it.
      final got = openResealedShare(s, reA, fresh.candidate);
      expect(got.index, 2);
      got.dispose();

      // (v) Refused, never guessed.
      expect(
        () => Ceremony.verifyRecoveryCandidateQr(
          s,
          scanned: DeviceQrPayload.decode(shown),
          relayedDeviceId: fresh.relayedDeviceId,
          relayedCandidateX25519: Uint8List(31),
        ),
        throwsArgumentError,
        reason: 'relayed key must be 32 bytes',
      );
      expect(
        () => ResealedShare(
          deviceId: deviceB,
          sealedTo: Uint8List(31),
          shareSetVersion: 4,
          bytes: reA.bytes,
        ),
        throwsArgumentError,
      );
      // A stored blob addressed to another guardian does not open for this one.
      expect(
        () => resealShareToCandidate(
          s,
          guardian: w.guardians[0],
          stored: w.stored[1],
          candidate: verified,
        ),
        throwsA(
          isA<UnsealFailed>().having((e) => e.reason, 'reason', 'recipient'),
        ),
      );
      // A blob that opens but is not a guardian share is refused as `share`.
      final junk = Uint8List.fromList(List<int>.filled(10, 0xAB));
      final notAShare = sealToVerified(
        s,
        verifiedUmk(s, w.guardians[0], userId: _guardianIds[0]),
        junk,
      );
      expect(
        () => resealShareToCandidate(
          s,
          guardian: w.guardians[0],
          stored: notAShare,
          candidate: verified,
        ),
        throwsA(isA<UnsealFailed>().having((e) => e.reason, 'reason', 'share')),
      );
      // Unknown suite on the way back.
      expect(
        () => openResealedShare(
          s,
          ResealedShare(
            deviceId: reA.deviceId,
            sealedTo: reA.sealedTo,
            shareSetVersion: reA.shareSetVersion,
            bytes: reA.bytes,
            suiteVersion: 0x02,
          ),
          fresh.candidate,
        ),
        throwsA(isA<UnsealFailed>().having((e) => e.reason, 'reason', 'suite')),
      );
      // The candidate secret is gone after dispose.
      final spent = RecoveryCandidateKeyPair.generate(s);
      spent.dispose();
      expect(spent.isDisposed, isTrue);
      expect(() => spent.x25519Secret, throwsStateError);

      // (vi) The generation is the share's, not the caller's: a share from an
      // older split re-seals with its own version, and the server's
      // share_set_version check is what refuses it (0010).
      final older = _Household._splitAndSeal(s, w.user, w.guardians, 3);
      final reOld = resealShareToCandidate(
        s,
        guardian: w.guardians[0],
        stored: older[0],
        candidate: verified,
      );
      expect(reOld.shareSetVersion, 3);

      // (vii) The residual, on the record (ADR 2026-09-13c §4): if the phone
      // the guardian actually scans is the attacker's AND the relay names it,
      // scanned = relayed and the ceremony cannot tell — the guardian has
      // approved a stranger's phone on a call. That is the human-channel
      // assumption every 04 §6 ceremony makes (04 §6.4: a channel where the
      // verifier recognises the *person*); the 24 h alarm on every existing
      // device (ADR 2026-09-05d §1) is the second line.
      final rc = _guardianScans(
        s,
        shown: attacker.show(s),
        relayedDeviceId: attacker.relayedDeviceId,
        relayedPubX: attacker.relayedPubX,
      );
      expect(rc, isA<RecoveryCandidateVerified>());
    });
  });
}
