// The recovery candidate is its own X25519 pair, one per attempt
// (ADR 2026-09-24b §1 🔒, desk 12; 04 §7.3 steps 1–4) — F1-24b-1.
//
// What is adversarial here, rather than cosmetic:
//
//   * the candidate is **not this device's `pub_x`** and never lands in a
//     device-key item — an abandoned attempt must not share a key with the
//     device's identity;
//   * the attempt this phone watches is the one its **held key** belongs to,
//     matched on the key bytes — not the newest in the listing, which may be
//     another of the user's phones, and not a key the server echoes back
//     different from the one sent (ADR 2026-09-13c §3's substitution, seen
//     from the requester's side);
//   * every close zeroises, and a close of somebody else's attempt deletes
//     nothing; `approved` keeps the pair only until reconstruct, which deletes
//     it whichever way it goes;
//   * every buffer read from the key store is zeroised after use.
//
// Real libsodium throughout (the ceremony is the only producer of the
// verified type, 04 §8.2), a real `HttpRecoveryApi` over a fake transport,
// and a memory key store that remembers what it handed out.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/sync/recovery_candidate.dart';
import 'package:rukka_folio/shared/sync/recovery_seams.dart';

import 'guardian_test_keys.dart';

final _root = Uri.parse('https://api.example.test/functions/v1/');

/// The fresh phone's device id — synthetic, canonical (the key types refuse
/// anything else).
const _deviceNew = '33333333-3333-4333-8333-333333333332';

String _b64(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

Uint8List _unb64(String s) =>
    Uint8List.fromList(base64Url.decode(base64.normalize(s)));

/// A key store that remembers every candidate buffer it handed out, so a test
/// can look at them after the holder is done with them. Only the holder reads
/// [KeyIds.recoveryCandidate]; nothing in these tests reads it directly.
final class _RecordingKeyStore extends FakeKeyStore {
  final List<Uint8List> handedOut = [];
  final List<String> deletes = [];

  /// Every buffer the holder asked to have written under the candidate id —
  /// the caller's own buffer, not the store's copy.
  final List<Uint8List> offered = [];

  /// When true, the platform store will not take the candidate secret.
  bool refuseWrite = false;

  /// When true, the platform store cannot be read for the candidate id.
  bool refuseRead = false;

  @override
  Future<Uint8List?> read(String id) async {
    if (refuseRead && id == KeyIds.recoveryCandidate) {
      throw StateError('keychain locked');
    }
    final v = await super.read(id);
    if (v != null && id == KeyIds.recoveryCandidate) handedOut.add(v);
    return v;
  }

  @override
  Future<void> write(String id, Uint8List bytes) {
    if (id == KeyIds.recoveryCandidate) {
      offered.add(bytes);
      if (refuseWrite) throw StateError('keychain full');
    }
    return super.write(id, bytes);
  }

  @override
  Future<void> delete(String id) {
    deletes.add(id);
    return super.delete(id);
  }
}

/// A holder that zeroises LATE — after the seam has already told the screen
/// the attempt closed. It is the negative control that shows the
/// before-the-screen-hears-it probe can fail at all.
final class _LateDiscard implements RecoveryCandidateKeys {
  _LateDiscard(this._inner);

  final RecoveryCandidateKeys _inner;
  final List<Future<void>> pending = [];

  @override
  Future<Uint8List> mint() => _inner.mint();

  @override
  Future<Uint8List?> held() => _inner.held();

  @override
  Future<void> discard(Uint8List publicHalf) async {
    pending.add(
      Future<void>.delayed(Duration.zero, () => _inner.discard(publicHalf)),
    );
  }
}

/// The 0010 routes as far as the requester sees them: a listing, a progress
/// read, and an open that files what was posted.
final class _Server {
  final List<Map<String, Object?>> requests = [];
  final List<Map<String, Object?>> opens = [];
  String state = 'pending';

  /// The derived state of one attempt, by request id; [state] otherwise.
  final Map<String, String> states = {};

  /// Progress reads answered, by request id.
  final List<String> progressReads = [];

  /// When set, the open answers with this key instead of the one posted.
  Uint8List? echoInstead;

  /// When set, the open is refused with this status and error word.
  (int, String)? refuseOpen;

  /// When true, the open never answers — but, like a lost response, the
  /// insert still lands.
  bool loseOpenResponse = false;

  int _n = 0;

  Map<String, Object?> add(Uint8List pub, {String device = 'dev-new'}) {
    _n++;
    final r = <String, Object?>{
      'request_id': 'req-$_n',
      'user_id': 'u-subject',
      'candidate_device': device,
      'candidate_pub_x': _b64(pub),
      'share_set_version': 1,
      'opened_state': 'pending',
      'created_at': 1000 + _n,
      'expires_at': 260200000,
    };
    requests.add(r);
    return r;
  }

  late final FakeRkHttpTransport transport = FakeRkHttpTransport((
    method,
    url,
    headers,
    body,
  ) {
    if (method == 'POST') {
      final j = (jsonDecode(body!) as Map).cast<String, Object?>();
      opens.add(j);
      final refuse = refuseOpen;
      if (refuse != null) {
        return RkHttpResponse(refuse.$1, jsonEncode({'error': refuse.$2}));
      }
      final r = add(echoInstead ?? _unb64(j['candidate_pub_x']! as String));
      if (loseOpenResponse) throw const RkHttpFailure();
      return RkHttpResponse(200, jsonEncode(r));
    }
    final id = url.queryParameters['request_id'];
    if (id != null) {
      progressReads.add(id);
      return RkHttpResponse(
        200,
        jsonEncode({
          'request_id': id,
          'share_set_version': 1,
          'k': 2,
          'n': 3,
          'approvals': 0,
          'denials': 0,
          'opened_state': 'pending',
          'state': states[id] ?? state,
          'kth_approval_at': null,
          'wait_until': null,
          'expires_at': 260200000,
          'cancelled_at': null,
          'decisions': const <Object?>[],
        }),
      );
    }
    return RkHttpResponse(200, jsonEncode({'requests': requests}));
  });

  HttpRecoveryApi get api => HttpRecoveryApi(
    transport: transport,
    functionsRoot: _root,
    accessToken: () async => 'tok',
    clientVersion: '0.1.0',
  );
}

HttpGuardianRecovery _seam(
  _Server server,
  RecoveryCandidateKeys keys, {
  Stream<void>? ticks,
  RecoveryScanner? scanner,
}) {
  final seam = HttpGuardianRecovery(
    api: server.api,
    roster: (_) async => const [],
    candidateKeys: keys,
    scanner: scanner,
    ticker: (_) => ticks ?? const Stream.empty(),
  );
  addTearDown(seam.dispose);
  return seam;
}

void main() {
  late CryptoSuite suite;
  setUpAll(() async => suite = await liveSuite());

  test('F1-24b-1 opening an attempt mints its OWN pair: only its secret is '
      'written, under its own id, and only its public half is sent — never '
      'this device\'s pub_x; re-reads mint nothing more', () async {
    final keys = _RecordingKeyStore();
    final device = DeviceKeyPair.generate(suite, deviceId: _deviceNew);
    addTearDown(device.dispose);
    // This device's own keys, as `LocalLedger.bootstrapSolo` leaves them.
    final agree = device.x25519Secret.extractBytes();
    await keys.write(KeyIds.deviceAgreementKey, agree);
    final writesBefore = keys.writes.length;

    final server = _Server();
    final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
    final seam = _seam(server, holder);
    await seam.refresh();

    expect(server.opens, hasLength(1));
    final sent = _unb64(server.opens.single['candidate_pub_x']! as String);
    expect(sent, hasLength(32));
    expect(
      sent,
      isNot(device.public.x25519),
      reason: 'the candidate is its own pair, never the device pub_x',
    );
    expect(await holder.held(), sent);
    expect(seam.candidate!.candidatePubX, sent);
    expect(seam.current, isNotNull);
    expect(keys.writes.sublist(writesBefore), [
      KeyIds.recoveryCandidate,
    ], reason: 'one item written, and it is not a device-key item');
    expect(await keys.read(KeyIds.deviceAgreementKey), agree);

    // Re-reading the attempt it opened opens nothing new and keeps the key.
    await seam.refresh();
    await seam.refresh();
    expect(server.opens, hasLength(1));
    expect(await holder.held(), sent);

    // Every buffer the holder read from the store was zeroised after use.
    expect(keys.handedOut, isNotEmpty);
    for (final b in keys.handedOut) {
      expect(b, everyElement(0));
    }
  });

  test('F1-24b-1 the held pair survives a relaunch and pins ITS attempt by '
      'key, not the newest in the listing (another phone\'s)', () async {
    final keys = _RecordingKeyStore();
    final server = _Server();
    final first = _seam(
      server,
      KeyStoreRecoveryCandidate(keys: keys, suite: suite),
    );
    await first.refresh();
    final mine = _unb64(server.requests.single['candidate_pub_x']! as String);
    final mineId = server.requests.single['request_id'];

    // Another of the user's phones opens an attempt of its own, later.
    final other = RecoveryCandidateKeyPair.generate(suite);
    addTearDown(other.dispose);
    server.add(other.x25519, device: 'dev-other');

    // A relaunch: a new seam and a new holder over the same key store.
    final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
    final again = _seam(server, holder);
    await again.refresh();
    expect(server.opens, hasLength(1), reason: 'nothing minted, nothing sent');
    expect(again.current!.requestId, mineId);
    expect(again.candidate!.candidatePubX, mine);
    expect(await holder.held(), mine);
  });

  test('F1-24b-1 a poll never mints: only the screen\'s own refresh may open '
      'an attempt, so a timer is never what asks the guardians', () async {
    final keys = _RecordingKeyStore();
    final server = _Server();
    final ticks = StreamController<void>.broadcast();
    addTearDown(ticks.close);
    final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
    final seam = _seam(server, holder, ticks: ticks.stream);
    final sub = seam.watch().listen((_) {}); // starts polling
    addTearDown(sub.cancel);

    ticks
      ..add(null)
      ..add(null);
    await pumpEventQueue();
    expect(server.opens, isEmpty, reason: 'no attempt, and a poll opens none');
    expect(await holder.held(), isNull, reason: 'and mints none');

    await seam.refresh();
    expect(server.opens, hasLength(1));
    ticks.add(null);
    await pumpEventQueue();
    expect(server.opens, hasLength(1));
  });

  for (final closed in const ['cancelled', 'expired']) {
    test('F1-24b-1 a `$closed` attempt zeroises the held secret before the '
        'screen hears it closed', () async {
      final keys = _RecordingKeyStore();
      final server = _Server();
      final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
      final seam = _seam(server, holder);
      await seam.refresh();
      expect(await keys.contains(KeyIds.recoveryCandidate), isTrue);

      // The mint deleted the id before writing it (one attempt's key is never
      // another's), so `deletes` already names it. Cleared, so the only
      // delete the probe can see is the close's own.
      expect(keys.deletes, [KeyIds.recoveryCandidate]);
      keys.deletes.clear();

      // What the screen knows at the moment it is told: `deletes` is written
      // synchronously when the holder calls delete, so after the clear above
      // it names the id at that moment if and only if the zeroise came first.
      // The control below shows a late zeroise reads `false` here.
      final deletedWhenTold = <bool>[];
      final sub = seam.watch().listen(
        (a) => deletedWhenTold.add(
          a.isClosed && keys.deletes.contains(KeyIds.recoveryCandidate),
        ),
      );
      addTearDown(sub.cancel);

      server.state = closed;
      await seam.refresh();
      await pumpEventQueue();
      expect(deletedWhenTold, [isTrue]);
      expect(seam.current!.isClosed, isTrue);
      expect(await keys.contains(KeyIds.recoveryCandidate), isFalse);
      expect(keys.deletes, [KeyIds.recoveryCandidate]);
      expect(await holder.held(), isNull);
    });

    test(
      'F1-24b-1 control: the `$closed` probe above is not vacuous — a '
      'holder that zeroises only after the screen is told reads false',
      () async {
        final keys = _RecordingKeyStore();
        final server = _Server();
        final late = _LateDiscard(
          KeyStoreRecoveryCandidate(keys: keys, suite: suite),
        );
        final seam = _seam(server, late);
        await seam.refresh();
        keys.deletes.clear();

        final deletedWhenTold = <bool>[];
        final sub = seam.watch().listen(
          (a) => deletedWhenTold.add(
            a.isClosed && keys.deletes.contains(KeyIds.recoveryCandidate),
          ),
        );
        addTearDown(sub.cancel);

        server.state = closed;
        await seam.refresh();
        await pumpEventQueue();
        await Future.wait(late.pending);
        expect(deletedWhenTold, [
          isFalse,
        ], reason: 'told first, zeroised after');
        expect(await keys.contains(KeyIds.recoveryCandidate), isFalse);
      },
    );
  }

  test('F1-24b-1 `approved` keeps the pair for step 4, and a close of an '
      'attempt that is not this phone\'s deletes nothing', () async {
    final keys = _RecordingKeyStore();
    final server = _Server();
    final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
    final seam = _seam(server, holder);
    await seam.refresh();
    final held = await holder.held();

    server.state = 'approved';
    await seam.refresh();
    expect(seam.current!.state, RecoveryAttemptState.approved);
    expect(await holder.held(), held, reason: 'still needed to open shares');

    // The holder removes only the pair it was asked about.
    final stranger = RecoveryCandidateKeyPair.generate(suite);
    addTearDown(stranger.dispose);
    await holder.discard(stranger.x25519);
    expect(await holder.held(), held);
  });

  test(
    'F1-24b-1 a server that echoes a different candidate key is refused: '
    'nothing is pinned, the minted secret is gone, and the substituted '
    'attempt, re-read, is shown but never offered as this phone\'s key',
    () async {
      final keys = _RecordingKeyStore();
      final server = _Server();
      final relay = RecoveryCandidateKeyPair.generate(suite);
      addTearDown(relay.dispose);
      server.echoInstead = relay.x25519;
      final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
      final scanned = <RecoveryCandidate>[];
      final seam = _seam(
        server,
        holder,
        // A scanner that would pass anything it is handed.
        scanner: (c) async {
          scanned.add(c);
          return RecoveryScanOutcome.verified;
        },
      );

      await expectLater(
        seam.refresh(),
        throwsA(
          isA<RecoveryFailure>().having(
            (f) => f.reason,
            'reason',
            RecoveryRefusal.candidateKeyMismatch.name,
          ),
        ),
      );
      expect(seam.current, isNull);
      expect(seam.candidate, isNull);
      expect(await holder.held(), isNull);

      // The relay's attempt is in the listing now. Re-read, it is drawn — the
      // screen says what the server says — but its key is not this phone's,
      // so no candidate exists for it and the ceremony cannot run over it.
      server.echoInstead = null;
      await seam.refresh();
      expect(
        server.opens,
        hasLength(1),
        reason: 'a listed attempt is not re-opened',
      );
      expect(seam.current, isNotNull);
      expect(seam.candidate, isNull);
      expect(await seam.verifyOwnKeyByScan(), RecoveryScanOutcome.unavailable);
      expect(scanned, isEmpty);
    },
  );

  test(
    'F1-24b-1 a refused open removes the minted secret; a lost response '
    'keeps it, and the next read finds the attempt that carries it',
    () async {
      final keys = _RecordingKeyStore();
      final server = _Server()..refuseOpen = (409, 'no_guardian_set');
      final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
      final seam = _seam(server, holder);
      await expectLater(seam.refresh(), throwsA(isA<RecoveryFailure>()));
      expect(server.opens, hasLength(1));
      expect(await holder.held(), isNull, reason: 'no attempt was opened');

      server
        ..refuseOpen = null
        ..loseOpenResponse = true;
      await expectLater(seam.refresh(), throwsA(isA<RecoveryFailure>()));
      final kept = await holder.held();
      expect(kept, isNotNull, reason: 'the insert may have landed');
      expect(server.requests, hasLength(1));

      server.loseOpenResponse = false;
      await seam.refresh();
      expect(server.opens, hasLength(2), reason: 'found, not re-opened');
      expect(seam.current!.requestId, server.requests.single['request_id']);
      expect(seam.candidate!.candidatePubX, kept);
    },
  );

  test('F1-24b-1 step 4: reconstruct opens the re-sealed shares with the held '
      'pair, returns the UMK verified against the ceremony key, and deletes the '
      'held secret — on success and on failure', () async {
    final user = UmkKeyPair.generate(suite);
    addTearDown(user.dispose);
    final expected = TestGuardian(suite, userMe, user).verified;

    final keys = _RecordingKeyStore();
    final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);

    List<ResealedShare> resealedTo(Uint8List pub) {
      final priv = user.exportSecretBytes();
      final shares = GuardianShareSet.create(
        suite,
        umkSecret: priv,
        n: 3,
        shareSetVersion: 1,
      );
      suite.zeroize(priv);
      final out = [
        for (final s in shares.take(2))
          ResealedShare(
            deviceId: 'dev-new',
            sealedTo: pub,
            shareSetVersion: 1,
            bytes: suite.sodium.crypto.box.seal(
              message: s.encode(),
              publicKey: pub,
            ),
          ),
      ];
      for (final s in shares) {
        s.dispose();
      }
      return out;
    }

    // Success.
    final pub = await holder.mint();
    final umk = await holder.reconstruct(
      shares: resealedTo(pub),
      expected: expected,
    );
    addTearDown(umk.dispose);
    expect(umk.public, user.public);
    expect(await keys.contains(KeyIds.recoveryCandidate), isFalse);

    // Failure: shares sealed to some other key open nothing — and the held
    // secret is gone all the same.
    await holder.mint();
    final elsewhere = RecoveryCandidateKeyPair.generate(suite);
    addTearDown(elsewhere.dispose);
    await expectLater(
      holder.reconstruct(
        shares: resealedTo(elsewhere.x25519),
        expected: expected,
      ),
      throwsA(isA<UnsealFailed>()),
    );
    expect(await keys.contains(KeyIds.recoveryCandidate), isFalse);

    // Nothing held: refused plainly, nothing opened.
    await expectLater(
      holder.reconstruct(shares: const [], expected: expected),
      throwsA(isA<RecoveryFailure>()),
    );

    // Every secret the holder read was zeroised after use.
    expect(keys.handedOut, isNotEmpty);
    for (final b in keys.handedOut) {
      expect(b, everyElement(0));
    }
  });
  for (final closed in const ['cancelled', 'expired']) {
    test('F1-24b-1 after this phone\'s own attempt is `$closed`, the refresh '
        'that sees the close only shows it; the NEXT screen refresh — '
        're-entering S11.2, the "start a new one" its closed card promises — '
        'opens a fresh attempt on a fresh pair, and polling resumes for it '
        'without a poll ever opening one', () async {
      final keys = _RecordingKeyStore();
      final server = _Server();
      final ticks = StreamController<void>.broadcast();
      addTearDown(ticks.close);
      final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
      final seam = _seam(server, holder, ticks: ticks.stream);
      final told = <GuardianRecoveryAttempt>[];
      final sub = seam.watch().listen(told.add); // starts polling
      addTearDown(sub.cancel);

      await seam.refresh();
      final firstId = server.requests.single['request_id']! as String;
      final firstKey = (await holder.held())!;

      server.states[firstId] = closed;
      await seam.refresh();
      expect(seam.current!.requestId, firstId);
      expect(seam.current!.isClosed, isTrue, reason: 'the close is shown');
      expect(server.opens, hasLength(1), reason: 'seeing a close asks nobody');
      expect(await holder.held(), isNull);

      // The close stopped polling: ticks now read nothing and open nothing.
      final readsAtClose = server.progressReads.length;
      ticks
        ..add(null)
        ..add(null);
      await pumpEventQueue();
      expect(server.opens, hasLength(1));
      expect(server.progressReads, hasLength(readsAtClose));

      await seam.refresh();
      expect(server.opens, hasLength(2), reason: 'one fresh attempt');
      final secondId = server.requests.last['request_id']! as String;
      expect(secondId, isNot(firstId));
      final secondKey = await holder.held();
      expect(secondKey, isNotNull);
      expect(
        secondKey,
        isNot(firstKey),
        reason: 'one attempt\'s key is never another\'s',
      );
      expect(
        _unb64(server.opens.last['candidate_pub_x']! as String),
        secondKey,
      );
      expect(seam.current!.requestId, secondId);
      expect(seam.current!.isClosed, isFalse);
      expect(seam.candidate!.requestId, secondId);
      expect(seam.candidate!.candidatePubX, secondKey);

      // It is this phone's attempt now: a re-read pins it and opens nothing.
      await seam.refresh();
      expect(server.opens, hasLength(2));
      expect(seam.current!.requestId, secondId);

      // And the screen, still listening, hears it move by poll alone.
      server.states[secondId] = 'waiting_24h';
      ticks.add(null);
      await pumpEventQueue();
      expect(told.last.requestId, secondId);
      expect(told.last.state, RecoveryAttemptState.waiting24h);
      expect(server.opens, hasLength(2), reason: 'a poll never opens');
    });
  }

  test('F1-24b-1 a phone holding no key, whose newest listed attempt is over '
      '(another phone\'s, cancelled), opens its own on the screen\'s refresh '
      'and never on a poll; one that is approved or still live is shown and '
      'nobody is re-asked', () async {
    final other = RecoveryCandidateKeyPair.generate(suite);
    addTearDown(other.dispose);

    final keys = _RecordingKeyStore();
    final server = _Server();
    final old = server.add(other.x25519, device: 'dev-other');
    server.states[old['request_id']! as String] = 'cancelled';
    final ticks = StreamController<void>.broadcast();
    addTearDown(ticks.close);
    final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
    final seam = _seam(server, holder, ticks: ticks.stream);
    final sub = seam.watch().listen((_) {}); // starts polling
    addTearDown(sub.cancel);

    ticks.add(null);
    await pumpEventQueue();
    expect(server.opens, isEmpty, reason: 'a poll never opens');
    expect(seam.current?.state, RecoveryAttemptState.cancelled);
    expect(await holder.held(), isNull);
    expect(keys.deletes, isEmpty, reason: 'nobody else\'s close deletes here');

    await seam.refresh();
    expect(server.opens, hasLength(1));
    final mine = await holder.held();
    expect(mine, isNotNull);
    expect(mine, isNot(other.x25519));
    expect(seam.current!.requestId, server.requests.last['request_id']);
    expect(seam.current!.isClosed, isFalse);
    expect(seam.candidate!.candidatePubX, mine);

    // ⚠️ SPEC (reported): only cancelled and expired — the two closes whose
    // copy promises a new request — re-ask. An `approved` attempt this phone
    // cannot finish, and a live one of another phone, are shown as before.
    for (final word in const ['approved', 'pending', 'waiting_24h']) {
      final s = _Server();
      final r = s.add(other.x25519, device: 'dev-other');
      s.states[r['request_id']! as String] = word;
      final h = KeyStoreRecoveryCandidate(
        keys: _RecordingKeyStore(),
        suite: suite,
      );
      final v = _seam(s, h);
      await v.refresh();
      expect(s.opens, isEmpty, reason: '`$word` is not over: nobody re-asked');
      expect(v.current!.requestId, r['request_id']);
      expect(v.candidate, isNull, reason: 'shown, not owned');
      expect(await h.held(), isNull);
    }
  });

  test('F1-24b-1 overlapping screen refreshes (and a poll between them) open '
      'ONE attempt: reads are serialised, so each later read finds the first '
      'one\'s attempt by its held key instead of minting over it', () async {
    final keys = _RecordingKeyStore();
    final server = _Server();
    final ticks = StreamController<void>.broadcast();
    addTearDown(ticks.close);
    final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
    final seam = _seam(server, holder, ticks: ticks.stream);
    final sub = seam.watch().listen((_) {}); // starts polling
    addTearDown(sub.cancel);

    final a = seam.refresh();
    ticks.add(null);
    final b = seam.refresh();
    final c = seam.refresh();
    await Future.wait([a, b, c]);
    await pumpEventQueue();

    expect(server.opens, hasLength(1));
    expect(keys.offered, hasLength(1), reason: 'one mint');
    final held = await holder.held();
    expect(
      _unb64(server.requests.single['candidate_pub_x']! as String),
      held,
      reason: 'the one attempt carries the one key held',
    );
    expect(seam.current!.requestId, server.requests.single['request_id']);
    expect(seam.candidate!.candidatePubX, held);
  });

  test(
    'F1-24b-1 a key store that will not take the secret, or cannot be '
    'read, is refused as `key_store` and NOTHING is sent — an attempt whose '
    'key this phone does not hold is one whose shares nobody can open',
    () async {
      final keys = _RecordingKeyStore()..refuseWrite = true;
      final server = _Server();
      final holder = KeyStoreRecoveryCandidate(keys: keys, suite: suite);
      final seam = _seam(server, holder);
      Matcher keyStore() => throwsA(
        isA<RecoveryFailure>().having((f) => f.reason, 'reason', 'key_store'),
      );

      await expectLater(seam.refresh(), keyStore());
      expect(server.opens, isEmpty);
      expect(seam.current, isNull);
      expect(seam.candidate, isNull);
      expect(keys.offered, hasLength(1));
      expect(
        keys.offered.single,
        everyElement(0),
        reason: 'the secret the store refused was zeroised all the same',
      );
      expect(await keys.contains(KeyIds.recoveryCandidate), isFalse);

      keys
        ..refuseWrite = false
        ..refuseRead = true;
      await expectLater(seam.refresh(), keyStore());
      expect(server.opens, isEmpty);
      expect(keys.offered, hasLength(1), reason: 'no mint without a read');

      keys.refuseRead = false;
      await seam.refresh();
      expect(server.opens, hasLength(1));
    },
  );

  test('F1-24b-1 bootstrap installs the holder: the ONE HttpGuardianRecovery '
      'the root builds takes KeyStoreRecoveryCandidate over the platform key '
      'store and the live suite — not null — and S11.2 is given that one', () {
    final root = _bootstrapCode();
    expect(
      RegExp(r'\bHttpGuardianRecovery\(').allMatches(root),
      hasLength(1),
      reason: 'one producer, so the one checked is the one installed',
    );
    expect(
      RegExp(r'final\s+guardianRecovery\s*=\s*HttpGuardianRecovery\(')
          .hasMatch(root),
      isTrue,
    );
    final call = _callOf(root, 'HttpGuardianRecovery');
    expect(
      RegExp(r'\bcandidateKeys\s*:').allMatches(call),
      hasLength(1),
      reason: 'passed once, and never overridden',
    );
    expect(
      RegExp(
        r'\bcandidateKeys\s*:\s*KeyStoreRecoveryCandidate\(\s*keys\s*:\s*keys'
        r'\s*,\s*suite\s*:\s*suite\s*,?\s*\)',
      ).hasMatch(call),
      isTrue,
      reason: 'the holder itself — without it rung 2 can never open',
    );
    expect(
      RegExp(r'final\s+keys\s*=').allMatches(root),
      hasLength(1),
      reason: 'no second `keys` to shadow the platform store',
    );
    expect(
      RegExp(r'final\s+keys\s*=\s*KeychainKeyStore\(\s*\)').hasMatch(root),
      isTrue,
    );
    expect(
      RegExp(r'final\s+suite\s*=').allMatches(root),
      hasLength(1),
      reason: 'no second `suite` to shadow the live one',
    );
    expect(
      RegExp(
        r'final\s+suite\s*=\s*CryptoSuite\(\s*await\s+SodiumInit\.init\(\)\s*\)',
      ).hasMatch(root),
      isTrue,
    );
    expect(
      RegExp(r'GuardianRecoveryScope\(\s*recovery\s*:\s*guardianRecovery\b')
          .hasMatch(root),
      isTrue,
      reason: 'the producer S11.2 reads',
    );
  });
}

/// The composition root's own **code**, comments stripped — the F1-24b-2 and
/// F1-06-89 reading: prose that names the holder cannot stand in for it.
/// `flutter test` runs from `app/`; both paths are tried, and a missing file
/// fails rather than passing vacuously.
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

/// The text of the first `<name>(…)` call in [code], parentheses balanced.
String _callOf(String code, String name) {
  final start = code.indexOf('$name(');
  expect(start, isNonNegative, reason: '$name is constructed in the root');
  var depth = 0;
  for (var i = start + name.length; i < code.length; i++) {
    if (code[i] == '(') depth++;
    if (code[i] == ')' && --depth == 0) return code.substring(start, i + 1);
  }
  fail('unbalanced $name(');
}
