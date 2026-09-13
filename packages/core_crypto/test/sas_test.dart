// Suite B — the code path of the verification ceremony against a substituting
// relay (04 §6.1, §6.3; ADR 2026-09-13d, escalation lane M7-K4, 13 Sep 2026).
//
// Ids B-04-86 … B-04-90. Two things are pinned here. First, the finding K3
// left open (ADR 2026-09-13c Open 1), made executable: the shipped 8-digit
// derivation is a function of two values the server holds or chooses, so a
// relay that substitutes the invitee's key can make the honest digits verify
// its own key — and when it relays independent nonces to the two sides the
// search is a birthday one, ~2·10⁴ hashes, not 10⁸ (B-04-87). Second, the
// recommended repair — a commitment-based short authentication string, landed
// alongside the old path — under the same relay with the same powers
// (B-04-88, B-04-89), with 04 §6.3's attempt and lifetime rules carried over
// unchanged (B-04-90). The QR path is shown unaffected in B-04-87.
//
// Everything is deterministic: seeded suite, counter nonces, no clock.
@Tags(['B'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A fixed, synthetic server timestamp for the commitment (injected).
const int _issued = 1_800_000_000_000;

Uint8List _tag(String s) => Uint8List.fromList(utf8.encode(s));

/// `decimal(first4bytes(h)) mod 10⁸`, zero-padded — recomputed by hand so the
/// tests pin the formula, not the function.
String _eightDigits(Uint8List h) =>
    (ByteData.sublistView(h, 0, 4).getUint32(0) % 100000000).toString().padLeft(
      8,
      '0',
    );

void main() {
  test('B-04-86 SAS code path, honest run: the shower commits, the verifier draws r_V only against the commitment + relayed key, the shower opens once, and the typed 8 digits verify the relayed key as code_remote; commitment and code formulas pinned', () async {
    // ADR 2026-09-13d §1: c = BLAKE2b-256("rf-sas-commit-v1" ‖ FP ‖ user_id ‖
    // r_S); code = decimal(first4(BLAKE2b-256("rf-sas-code-v1" ‖ FP ‖ user_id
    // ‖ r_S ‖ r_V))) mod 10⁸ — the same eight-digit shape as 04 §6.1.
    final s = await testSuite(seed: 86);
    final invitee = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    final fp = Fingerprint.of(s, invitee.public);

    // Invitee's phone: Show my code.
    final shower = SasShower.open(s, userId: userA, umk: invitee.public);
    expect(shower.commitment.length, sasCommitmentBytes);
    expect(shower.isSpent, isFalse);

    // Verifier's phone: holds the relayed key + relayed commitment, then r_V.
    final verifier = SasVerifier.begin(
      s,
      relayed: invitee.public,
      relayedUserId: userA,
      commitment: shower.commitment,
      issuedAtMs: _issued,
    );
    expect(verifier.verifierRandom.length, sasContributionBytes);
    expect(verifier.isOpened, isFalse);

    // r_V reaches the invitee's phone; it opens and shows the digits.
    final response = shower.respond(s, verifier.verifierRandom);
    expect(shower.isSpent, isTrue);
    expect(response.opening.length, sasContributionBytes);
    expect(response.code, matches(RegExp(r'^\d{8}$')));

    // The formulas, by hand.
    expect(
      shower.commitment,
      s.blake2b256(
        Bytes.concat([
          _tag('rf-sas-commit-v1'),
          fp.bytes,
          Uuid16.toBytes(userA),
          response.opening,
        ]),
      ),
      reason: 'commitment binds FP and user_id to r_S',
    );
    expect(
      response.code,
      _eightDigits(
        s.blake2b256(
          Bytes.concat([
            _tag('rf-sas-code-v1'),
            fp.bytes,
            Uuid16.toBytes(userA),
            response.opening,
            verifier.verifierRandom,
          ]),
        ),
      ),
    );
    expect(
      sasCode(
        s,
        fp: fp,
        userId: userA,
        showerRandom: response.opening,
        verifierRandom: verifier.verifierRandom,
      ),
      response.code,
    );
    expect(
      sasCommitment(s, fp: fp, userId: userA, showerRandom: response.opening),
      shower.commitment,
    );

    // The opening travels back; the verifier checks it and takes the digits.
    final opened = verifier.open(s, response.opening);
    expect(opened, isA<SasOpened>());
    expect(verifier.isOpened, isTrue);
    final c0 = (opened as SasOpened).challenge;
    expect(c0.attemptsLeft, codeMaxAttempts);
    expect(c0.relayed, invitee.public);

    // Read aloud in pairs of four: whitespace tolerated (as B-04-7).
    final code = response.code;
    final spaced = '${code.substring(0, 4)} ${code.substring(4)}';
    final r1 = c0.attempt(s, typed: spaced, nowMs: _issued + 1000);
    expect(r1.result, isA<CeremonyVerified>());
    final v = (r1.result as CeremonyVerified).verified;
    expect(v.public, invitee.public);
    expect(v.fingerprint, fp);
    expect(v.method, VerificationMethod.codeRemote);
    expect(r1.next.dead, isTrue, reason: 'one verification per session');
    expect(c0.dead, isFalse, reason: 'immutable — the old state is unchanged');

    // Deterministic under the seed (09 §1): same keys, same r_S, same c.
    final s2 = await testSuite(seed: 86);
    final invitee2 = UmkKeyPair.generate(s2);
    addTearDown(invitee2.dispose);
    expect(invitee2.public, invitee.public);
    final shower2 = SasShower.open(s2, userId: userA, umk: invitee2.public);
    expect(shower2.commitment, shower.commitment);

    // Hiding in practice: a second session of the same key is a different
    // commitment — r_S is fresh every time.
    final again = SasShower.open(s, userId: userA, umk: invitee.public);
    expect(again.commitment, isNot(shower.commitment));

    // Lengths and ids are checked, never guessed.
    expect(() => again.respond(s, Uint8List(15)), throwsArgumentError);
    expect(again.isSpent, isFalse, reason: 'a refused r_V spends nothing');
    expect(
      () => SasVerifier.begin(
        s,
        relayed: invitee.public,
        relayedUserId: userA,
        commitment: Uint8List(31),
        issuedAtMs: _issued,
      ),
      throwsArgumentError,
    );
    expect(
      () => SasVerifier.begin(
        s,
        relayed: invitee.public,
        relayedUserId: 'not-a-uuid',
        commitment: shower.commitment,
        issuedAtMs: _issued,
      ),
      throwsFormatException,
    );
    expect(
      () => SasShower.open(s, userId: 'not-a-uuid', umk: invitee.public),
      throwsFormatException,
    );
    expect(
      () => sasCode(
        s,
        fp: fp,
        userId: userA,
        showerRandom: response.opening,
        verifierRandom: Uint8List(17),
      ),
      throwsArgumentError,
    );
  });

  test('B-04-87 old code path (04 §6.3): a relay that substitutes the invitee\'s key and chooses both nonces makes the honest 8 digits verify its own key — a birthday search of ~2·10⁴ hashes, accepted on the first attempt, rate limits never engaged; the QR path under the same relay hard-fails', () async {
    // The finding of ADR 2026-09-13c Open 1, verified (CLAUDE.md rule 11).
    // 04 §6.3: the verifier "computes the expected code from the *server-
    // relayed* keys + nonce". 04 §6.1: the nonce is "server-generated". 06 §3
    // item 3: the server holds the invitee's registered UMK public key. So the
    // server knows FP_S and chooses n_S (what the invitee's phone derives its
    // digits from) and n_V (what the verifier's phone derives its expected
    // digits from), and relays UMK′ as the invitee's key. It needs
    //   code(FP_S, n_S) == code(FP′, n_V)
    // — an equality between two families it fully controls, over 10⁸ values:
    // a birthday collision, found after ~√10⁸ candidates per side. With one
    // nonce held honest the search is one-sided, ~10⁸ hashes — seconds in C,
    // ~24 min in this Dart loop (measured 14 µs per BLAKE2b through sodium) —
    // still offline, still one attempt. Rate limits bound *guessing*; the
    // relay does not guess.
    final s = await testSuite(seed: 87);
    final invitee = UmkKeyPair.generate(s);
    final ghost = UmkKeyPair.generate(s); // the server's own key, UMK′
    addTearDown(invitee.dispose);
    addTearDown(ghost.dispose);
    final fpS = Fingerprint.of(
      s,
      invitee.public,
    ); // registered — the server has it
    final fpGhost = Fingerprint.of(s, ghost.public);

    // Birthday search: nonces are plain counters, family byte 0 for the
    // invitee's side and 1 for the verifier's side.
    final byCode = <String, Uint8List>{}; // code → n_S
    Uint8List? nS;
    Uint8List? nV;
    var hashes = 0;
    final probe = Uint8List(16);
    for (var i = 1; nS == null; i++) {
      if (i > 200000) fail('no collision in 4·10⁵ hashes — expected ~2·10⁴');
      probe.buffer.asByteData().setUint32(0, i);
      probe[15] = 0;
      byCode[verificationCode(s, fpS, probe)] = Uint8List.fromList(probe);
      probe[15] = 1;
      final cV = verificationCode(s, fpGhost, probe);
      hashes += 2;
      final hit = byCode[cV];
      if (hit != null) {
        nS = hit;
        nV = Uint8List.fromList(probe);
      }
    }
    expect(
      hashes,
      lessThan(400000),
      reason: 'a birthday search, not a 10⁸ one (this run: $hashes hashes)',
    );

    // The invitee's phone was issued n_S (04 §6.1) and derives its digits from
    // its own true key — exactly what S9.2 does (ceremony_repository.dart
    // _derive). The human reads them aloud.
    final shown = verificationCode(s, fpS, nS);

    // The verifier's phone was relayed (UMK′, n_V) — what S9.3 hands
    // CodeChallenge. The honest digits verify the ghost, first try.
    final c = CodeChallenge(
      relayed: ghost.public,
      nonce: nV!,
      issuedAtMs: _issued,
    );
    final r = c.attempt(s, typed: shown, nowMs: _issued + 1000);
    expect(r.result, isA<CeremonyVerified>());
    expect(
      (r.result as CeremonyVerified).verified.public,
      ghost.public,
      reason: 'the ghost member is now a VerifiedUmkPublic — book keys would be wrapped to it (04 §5.1)',
    );
    expect(
      c.attemptsUsed,
      0,
      reason:
          'no wrong attempt was ever spent: 3-per-nonce never saw the attack',
    );

    // One-sided variant (the invitee's nonce honest, the verifier's ground):
    // shown at four digits so the push lane stays fast — expected 10⁴ tries
    // here, 10⁸ for all eight, the same search either way.
    final honestNonce = s.randomBytes(16);
    final honestCode = verificationCode(s, fpS, honestNonce);
    var tries = 0;
    final grind = Uint8List(16);
    String candidate;
    do {
      tries++;
      if (tries > 200000) fail('no 4-digit prefix collision in 2·10⁵ tries');
      grind.buffer.asByteData().setUint32(0, tries);
      candidate = verificationCode(s, fpGhost, grind);
    } while (candidate.substring(0, 4) != honestCode.substring(0, 4));
    expect(candidate.substring(0, 4), honestCode.substring(0, 4));

    // The QR path under the same relay: the 64 key bytes come off the
    // invitee's screen, not from the server, and the nonce plays no part in
    // the comparison — hard fail, no override (04 §6.3).
    expect(
      Ceremony.verifyQr(
        s,
        scanned: QrPayload(userId: userA, umk: invitee.public, nonce: nS),
        relayed: ghost.public,
        relayedUserId: userA,
      ),
      isA<CeremonyMismatch>(),
    );
    expect(
      Ceremony.verifyQr(
        s,
        scanned: QrPayload(userId: userA, umk: invitee.public, nonce: nV),
        relayed: ghost.public,
        relayedUserId: userA,
      ),
      isA<CeremonyMismatch>(),
      reason: 'whichever nonce the relay put in play',
    );
  });

  test('B-04-88 SAS: the same relay — substituted key, its own commitment, its choice of r_V′ and of the opening — cannot make the honest digits verify: the commitment is fixed before r_V exists, the shower opens once, and neither side\'s code can be searched', () async {
    // ADR 2026-09-13d §1–§2. The relay's powers are complete: it decides what
    // commitment the verifier sees, what r_V′ the shower sees and what opening
    // the verifier sees, and it knows FP_S. What it cannot do is reorder the
    // honest devices.
    final s = await testSuite(seed: 88);
    final invitee = UmkKeyPair.generate(s);
    final ghost = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    addTearDown(ghost.dispose);
    final fpS = Fingerprint.of(s, invitee.public);
    final fpGhost = Fingerprint.of(s, ghost.public);

    // (1) Substituted key, honest commitment forwarded: the honest opening
    // cannot open it under FP′ — hard fail before any digit is typed.
    {
      final shower = SasShower.open(s, userId: userA, umk: invitee.public);
      final v = SasVerifier.begin(
        s,
        relayed: ghost.public,
        relayedUserId: userA,
        commitment: shower.commitment,
        issuedAtMs: _issued,
      );
      final resp = shower.respond(s, v.verifierRandom);
      expect(v.open(s, resp.opening), isA<SasOpeningMismatch>());
    }

    // (2) The relay fabricates its own commitment for UMK′. It must do so
    // *before* the verifier draws r_V — SasVerifier.begin takes the commitment
    // — so (FP′, r′) is fixed blind to r_V, and the verifier's expected code
    // sasCode(FP′, r′, r_V) is a value the relay cannot steer. The shower's
    // digits sasCode(FP_S, r_S, r_V′) depend on r_S, which the relay learns
    // only after it has already chosen r_V′. Over 64 independent sessions
    // (expected coincidences 64·10⁻⁸) the honest digits never verify.
    var verifiedGhost = 0;
    for (var session = 0; session < 64; session++) {
      final rPrime = s.randomBytes(sasContributionBytes);
      final cPrime = sasCommitment(
        s,
        fp: fpGhost,
        userId: userA,
        showerRandom: rPrime,
      );
      final v = SasVerifier.begin(
        s,
        relayed: ghost.public,
        relayedUserId: userA,
        commitment: cPrime,
        issuedAtMs: _issued,
      );
      // The relay may forward r_V or anything else to the invitee's phone.
      final shower = SasShower.open(s, userId: userA, umk: invitee.public);
      final rVPrime = session.isEven
          ? v.verifierRandom
          : s.randomBytes(sasContributionBytes);
      final resp = shower.respond(s, rVPrime);
      // It opens its own commitment — that passes; the expected code is set.
      final opened = v.open(s, rPrime);
      expect(opened, isA<SasOpened>());
      final challenge = (opened as SasOpened).challenge;
      // The honest human types what the invitee's phone shows.
      final r = challenge.attempt(s, typed: resp.code, nowMs: _issued + 1000);
      if (r.result is CeremonyVerified) verifiedGhost++;
      expect(r.result, isA<CodeWrong>());
      expect((r.result as CodeWrong).attemptsLeft, codeMaxAttempts - 1);
    }
    expect(verifiedGhost, 0);

    // (3) After r_V exists the commitment is spent as a degree of freedom: a
    // different r′ — the relay now knows both codes and would like to pick an
    // r′ that reconciles them — fails the opening check. 2·10³ candidates,
    // every one a mismatch; the birthday family of B-04-87 has collapsed to a
    // single member per r_V.
    {
      final rPrime0 = s.randomBytes(sasContributionBytes);
      final cPrime0 = sasCommitment(
        s,
        fp: fpGhost,
        userId: userA,
        showerRandom: rPrime0,
      );
      final alt = Uint8List(sasContributionBytes);
      for (var i = 1; i <= 2000; i++) {
        final v = SasVerifier.begin(
          s,
          relayed: ghost.public,
          relayedUserId: userA,
          commitment: cPrime0,
          issuedAtMs: _issued,
        );
        alt.buffer.asByteData().setUint32(0, i);
        expect(v.open(s, alt), isA<SasOpeningMismatch>());
      }
    }

    // (4) On the shower's side the relay chooses r_V′ before it knows r_S,
    // and once it knows r_S the session is spent: there is no second code to
    // search r_V″ against.
    {
      final shower = SasShower.open(s, userId: userA, umk: invitee.public);
      final rVPrime = s.randomBytes(sasContributionBytes);
      final resp = shower.respond(s, rVPrime); // relay now holds r_S and code_S
      expect(
        sasCode(
          s,
          fp: fpS,
          userId: userA,
          showerRandom: resp.opening,
          verifierRandom: rVPrime,
        ),
        resp.code,
        reason: 'the relay can recompute code_S — too late to matter',
      );
      expect(
        () => shower.respond(s, s.randomBytes(sasContributionBytes)),
        throwsStateError,
      );
      expect(
        () => shower.respond(s, rVPrime),
        throwsStateError,
        reason: 'not even the same r_V′ again',
      );
    }

    // (5) And the verifier's side is single-use too: once opened, no second
    // opening — a relay cannot try the honest opening and then its own.
    {
      final shower = SasShower.open(s, userId: userA, umk: invitee.public);
      final v = SasVerifier.begin(
        s,
        relayed: invitee.public,
        relayedUserId: userA,
        commitment: shower.commitment,
        issuedAtMs: _issued,
      );
      final resp = shower.respond(s, v.verifierRandom);
      expect(v.open(s, resp.opening), isA<SasOpened>());
      expect(() => v.open(s, resp.opening), throwsStateError);
    }
  });

  test('B-04-89 SAS commitment binds the key and the person: an honest commitment opens only under the true key and the true user id; a flipped bit in the opening or the commitment fails; a replayed honest session can at most verify the true key', () async {
    // ADR 2026-09-13d §1: c = H(tag ‖ FP ‖ user_id ‖ r_S). Without FP and
    // user_id inside, a relay could forward an honest commitment and open it
    // with the honest r_S under a substituted key or a different person.
    final s = await testSuite(seed: 89);
    final invitee = UmkKeyPair.generate(s);
    final ghost = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);
    addTearDown(ghost.dispose);

    final shower = SasShower.open(s, userId: userA, umk: invitee.public);
    final rVPrime = s.randomBytes(sasContributionBytes);
    final resp = shower.respond(s, rVPrime);

    SasVerifier begin({UmkPublic? relayed, String id = userA, Uint8List? c}) =>
        SasVerifier.begin(
          s,
          relayed: relayed ?? invitee.public,
          relayedUserId: id,
          commitment: c ?? shower.commitment,
          issuedAtMs: _issued,
        );

    // True key, true id: opens.
    expect(begin().open(s, resp.opening), isA<SasOpened>());
    // Substituted key: no.
    expect(
      begin(relayed: ghost.public).open(s, resp.opening),
      isA<SasOpeningMismatch>(),
    );
    // True key, the server says it belongs to someone else: no.
    expect(begin(id: userB).open(s, resp.opening), isA<SasOpeningMismatch>());
    // One flipped bit in the opening: no.
    final flippedOpening = Uint8List.fromList(resp.opening)..[3] ^= 0x10;
    expect(begin().open(s, flippedOpening), isA<SasOpeningMismatch>());
    // One flipped bit in the relayed commitment: no.
    final flippedC = Uint8List.fromList(shower.commitment)..[31] ^= 0x01;
    expect(begin(c: flippedC).open(s, resp.opening), isA<SasOpeningMismatch>());
    // Half the key swapped (x25519 of the ghost, ed25519 of the invitee): no.
    expect(
      begin(
        relayed: UmkPublic(
          x25519: ghost.public.x25519,
          ed25519: invitee.public.ed25519,
        ),
      ).open(s, resp.opening),
      isA<SasOpeningMismatch>(),
    );

    // Replay of an honest, already-opened session under the true key: the
    // opening check passes — harmless, it is the invitee's real key — but the
    // verifier's r_V is fresh, so the digits it expects were never shown on
    // any screen; the old code does not verify, and the shower is spent.
    final replay = begin();
    final opened = replay.open(s, resp.opening);
    expect(opened, isA<SasOpened>());
    final r = (opened as SasOpened).challenge.attempt(
      s,
      typed: resp.code,
      nowMs: _issued + 1000,
    );
    expect(r.result, isA<CodeWrong>());
    expect(shower.isSpent, isTrue);
  });

  test('B-04-90 SAS challenge keeps 04 §6.3\'s rules: 3 wrong attempts kill the session (the right code no longer verifies), the lifetime is 10 minutes from the commitment\'s server timestamp (expired at 10:00.001, not at 10:00.000), expiry spends no attempt, garbage is a wrong attempt, success retires the session', () async {
    // Mirrors B-04-7, B-04-9 and B-04-10 over SasChallenge — the switch to
    // the SAS changes what is derived, not how many tries or for how long.
    final s = await testSuite(seed: 90);
    final invitee = UmkKeyPair.generate(s);
    addTearDown(invitee.dispose);

    ({SasChallenge challenge, String code}) session() {
      final shower = SasShower.open(s, userId: userA, umk: invitee.public);
      final v = SasVerifier.begin(
        s,
        relayed: invitee.public,
        relayedUserId: userA,
        commitment: shower.commitment,
        issuedAtMs: _issued,
      );
      final resp = shower.respond(s, v.verifierRandom);
      final opened = v.open(s, resp.opening) as SasOpened;
      return (challenge: opened.challenge, code: resp.code);
    }

    String wrongFor(String code) =>
        code[0] == '9' ? '0${code.substring(1)}' : '9${code.substring(1)}';

    // Three wrong → exhausted; the right code is now useless on this session.
    {
      final (:challenge, :code) = session();
      final wrong = wrongFor(code);
      var c = challenge;
      final r1 = c.attempt(s, typed: wrong, nowMs: _issued);
      expect((r1.result as CodeWrong).attemptsLeft, 2);
      c = r1.next;
      final r2 = c.attempt(s, typed: wrong, nowMs: _issued);
      expect((r2.result as CodeWrong).attemptsLeft, 1);
      c = r2.next;
      final r3 = c.attempt(s, typed: wrong, nowMs: _issued);
      expect(r3.result, isA<CodeExhausted>());
      c = r3.next;
      expect(c.dead, isTrue);
      expect(c.attemptsLeft, 0);
      final r4 = c.attempt(s, typed: code, nowMs: _issued);
      expect(r4.result, isA<CodeExhausted>());
      expect(identical(r4.next, c), isTrue);
      expect(challenge.attemptsLeft, 3, reason: 'immutable');
    }

    // Garbage is a wrong attempt, never a match; then the right code works.
    {
      final (:challenge, :code) = session();
      final r1 = challenge.attempt(s, typed: 'abcdefgh', nowMs: _issued);
      expect(r1.result, isA<CodeWrong>());
      final r2 = r1.next.attempt(s, typed: code, nowMs: _issued + 5000);
      expect(r2.result, isA<CeremonyVerified>());
      // Success retires the session.
      final r3 = r2.next.attempt(s, typed: code, nowMs: _issued + 6000);
      expect(r3.result, isA<CodeExhausted>());
    }

    // Lifetime: ten minutes from the commitment's server timestamp, boundary
    // per the 09 §2 clock-jump convention (fires at N + 1, not at N − 1).
    {
      final (:challenge, :code) = session();
      const tenMin = codeNonceLifetimeMs;
      expect(tenMin, 10 * 60 * 1000);
      expect(
        challenge.isExpiredAt(_issued + 9 * 60 * 1000 + 59 * 1000),
        isFalse,
      );
      expect(challenge.isExpiredAt(_issued + tenMin), isFalse);
      expect(challenge.isExpiredAt(_issued + tenMin + 1), isTrue);
      final late = challenge.attempt(
        s,
        typed: code,
        nowMs: _issued + tenMin + 1,
      );
      expect(late.result, isA<CodeExpired>());
      expect(late.next.attemptsLeft, 3, reason: 'expiry spends no attempt');
      final inTime = challenge.attempt(
        s,
        typed: code,
        nowMs: _issued + 9 * 60 * 1000 + 59 * 1000,
      );
      expect(inTime.result, isA<CeremonyVerified>());
    }
  });
}
