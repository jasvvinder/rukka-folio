// S11.2 *Show my code* — the fresh phone's candidate key as a square, for a
// trusted member's phone to scan before approving (ADR 2026-09-13c ruling 3
// 🔒, ADR 2026-09-24b §1 🔒, 04 §7.3 🔒 rung 2) — F1-13c-4..F1-13c-7.
//
// What is adversarial here, rather than cosmetic: the one value this screen
// must never draw is the server-relayed `candidate_pub_x`, because it is
// exactly what the guardian's phone compares against. Every "shown" case
// decodes the drawn payload and checks its X25519 half against the key the
// phone HOLDS; every "not held" case has a relayed key available that a wrong
// implementation could draw, and asserts no square was encoded at all.
//
// Real libsodium and a real `KeyStoreRecoveryCandidate` throughout; the live
// `HttpGuardianRecovery` over a fake transport where the pairing matters.
@Tags(['F1'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/ceremony/widgets/code_boxes.dart';
import 'package:rukka_folio/features/ceremony/widgets/qr_view.dart';
import 'package:rukka_folio/features/recovery/my_code.dart';
import 'package:rukka_folio/features/recovery/screens/s11_2_ask_members_screen.dart';
import 'package:rukka_folio/features/recovery/screens/s11_2_show_my_code_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/sync/recovery_candidate.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';
import 'package:rukka_folio/shared/sync/recovery_seams.dart';

import '../../shared/sync/guardian_test_keys.dart';
import '../../shared/test_app.dart';

/// This fresh phone's device id — synthetic, canonical.
const _me = '33333333-3333-4333-8333-333333333332';

/// The `candidate_device` the pinned attempt relays in the fixtures —
/// deliberately NOT [_me], so drawing the relayed id instead of this phone's
/// own is caught (review QR1 finding 1).
const _relayedDevice = '44444444-4444-4444-8444-444444444443';

/// Every affordance whose presence on Show my code would breach the channel
/// rule (04 §6.4 🔒: no share or copy on the code) — the same icon set as the
/// settled S9.2 check (ceremony_screens_test.dart `expectNoShareAffordance`),
/// plus any visible text or tooltip that offers to share or copy.
void _expectNoShareAffordance(WidgetTester tester) {
  for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
    expect(
      icon.icon,
      isNot(
        anyOf(
          Icons.share,
          Icons.share_outlined,
          Icons.ios_share,
          Icons.copy,
          Icons.copy_all,
          Icons.content_copy,
          Icons.content_copy_outlined,
        ),
      ),
      reason: '04 §6.4 🔒: the code may never be shared or copied',
    );
  }
  final offer = RegExp('share|copy', caseSensitive: false);
  expect(find.textContaining(offer), findsNothing);
  expect(
    find.byWidgetPredicate(
      (w) => w is Tooltip && offer.hasMatch(w.message ?? ''),
    ),
    findsNothing,
  );
}

String _b64(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

Uint8List _bytes(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed + i * 7) % 256));

/// Records every payload the screen asks to have encoded.
final class _Encoder {
  final payloads = <String>[];
  QrModules call(String payload) {
    payloads.add(payload);
    return const FakeQrModules();
  }
}

/// A [RecoveryCandidateKeys] whose `held` fails — a key store that refuses.
final class _BrokenKeys implements RecoveryCandidateKeys {
  @override
  Future<Uint8List> mint() => throw StateError('no');
  @override
  Future<Uint8List?> held() => throw StateError('key store locked');
  @override
  Future<void> discard(Uint8List publicHalf) async {}
}

/// A [RecoveryMyCode] that never answers, for the loading state.
final class _Never implements RecoveryMyCode {
  @override
  Future<RecoveryMyCodeRead> read() => Completer<RecoveryMyCodeRead>().future;
}

GuardianRecoveryAttempt _attempt({
  RecoveryAttemptState state = RecoveryAttemptState.pending,
}) => GuardianRecoveryAttempt(
  requestId: 'req-1',
  k: 2,
  n: 3,
  state: state,
  approvers: const [
    TrustedApprover(
      memberId: 'm1',
      name: 'Sunita',
      state: TrustedApproverState.waiting,
    ),
  ],
);

/// A minimal 0010 server: the user's listing, open, and progress.
final class _Server {
  final requests = <Map<String, Object?>>[];
  int _n = 0;

  void add(Uint8List pub, {String device = _me}) {
    _n++;
    requests.add({
      'request_id': 'req-$_n',
      'user_id': 'u-subject',
      'candidate_device': device,
      'candidate_pub_x': _b64(pub),
      'share_set_version': 1,
      'opened_state': 'pending',
      'created_at': 1000 + _n,
      'expires_at': 260200000,
    });
  }

  late final transport = FakeRkHttpTransport((method, url, headers, body) {
    if (method == 'POST') {
      final j = (jsonDecode(body!) as Map).cast<String, Object?>();
      final pub = j['candidate_pub_x']! as String;
      add(Uint8List.fromList(base64Url.decode(base64.normalize(pub))));
      return RkHttpResponse(200, jsonEncode(requests.last));
    }
    final id = url.queryParameters['request_id'];
    if (id != null) {
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
          'state': 'pending',
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

  HttpGuardianRecovery seam(RecoveryCandidateKeys keys) {
    final s = HttpGuardianRecovery(
      api: HttpRecoveryApi(
        transport: transport,
        functionsRoot: Uri.parse('https://api.example.test/functions/v1/'),
        accessToken: () async => 'tok',
        clientVersion: '0.1.0',
      ),
      roster: (_) async => const [],
      candidateKeys: keys,
      ticker: (_) => const Stream.empty(),
    );
    addTearDown(s.dispose);
    return s;
  }
}

/// The drawn payload, decoded as the guardian's phone decodes it.
DeviceQrPayload _decode(_Encoder e) =>
    DeviceQrPayload.decode(e.payloads.single);

void main() {
  late CryptoSuite suite;
  late DeviceKeyPair device;
  setUpAll(() async {
    suite = await liveSuite();
    device = DeviceKeyPair.generate(suite, deviceId: _me);
  });
  tearDownAll(() => device.dispose());

  /// A holder with a freshly minted pair; returns it and its public half.
  Future<(KeyStoreRecoveryCandidate, Uint8List)> heldPair() async {
    final holder = KeyStoreRecoveryCandidate(
      keys: FakeKeyStore(),
      suite: suite,
    );
    final pub = await holder.mint();
    return (holder, pub);
  }

  HeldCandidateMyCode myCode(
    RecoveryCandidateKeys keys,
    RecoveryCandidate? Function() pinned,
  ) => HeldCandidateMyCode(
    keys: keys,
    pinned: pinned,
    thisDevice: () async => device.public,
    suite: suite,
  );

  RecoveryCandidate candidate(Uint8List pub) => RecoveryCandidate(
    requestId: 'req-1',
    deviceId: _relayedDevice,
    candidatePubX: pub,
  );

  group('S11.2 Show my code (ADR 2026-09-13c ruling 3 🔒, 24b §1 🔒)', () {
    testWidgets(
      'F1-13c-4 the square carries the key this phone HOLDS — decoded as the '
      'guardian decodes it, its X25519 half is the held pair and its device '
      'id this phone\'s own; the scan against the relayed request verifies; '
      'QR only: no digit boxes, no text field, no share or copy control',
      (tester) async {
        final (holder, held) = await tester.runAsync(
          heldPair,
        ) as (KeyStoreRecoveryCandidate, Uint8List);
        final encoder = _Encoder();
        await pumpRk(
          tester,
          RecoveryShowMyCodeScreen(
            myCode: myCode(holder, () => candidate(held)),
            encode: encoder.call,
          ),
          viewport: rkPhone360,
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(find.byType(RkQrView), findsOneWidget);
        final drawn = _decode(encoder);
        expect(drawn.device.x25519, held);
        // This phone's own id from `thisDevice` — never the relayed
        // `candidate_device`, which the fixture sets to another id.
        expect(drawn.device.deviceId, _me);
        expect(drawn.device.deviceId, isNot(_relayedDevice));
        expect(drawn.device.ed25519, device.public.ed25519);
        // The guardian's own check (S11.7) passes against the honest relay.
        expect(
          Ceremony.verifyRecoveryCandidateQr(
            suite,
            scanned: drawn,
            relayedDeviceId: _me,
            relayedCandidateX25519: held,
          ),
          isA<RecoveryCandidateVerified>(),
        );
        expect(find.byType(RkCodeBoxes), findsNothing);
        expect(find.byType(TextField), findsNothing);
        _expectNoShareAffordance(tester);
        expect(
          find.text(
            'Show it only to the person you are talking to. Never send it as '
            'a message or a photo.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-13c-5 the relayed candidate_pub_x is NEVER drawn: when the attempt '
      'in hand carries a key other than the held one, or this phone holds '
      'none, or no attempt is pinned, no square is encoded at all — the '
      'screen says so in words and Back returns to S11.2',
      (tester) async {
        final (holder, held) = await tester.runAsync(
          heldPair,
        ) as (KeyStoreRecoveryCandidate, Uint8List);
        final relayed = _bytes(3);
        expect(relayed, isNot(held));
        final empty = KeyStoreRecoveryCandidate(
          keys: FakeKeyStore(),
          suite: suite,
        );
        final cases = <String, RecoveryMyCode>{
          'relayed differs from held': myCode(holder, () => candidate(relayed)),
          'nothing held, relayed present': myCode(
            empty,
            () => candidate(relayed),
          ),
          'held, but no attempt pinned': myCode(holder, () => null),
        };
        for (final MapEntry(key: why, value: code) in cases.entries) {
          final encoder = _Encoder();
          await pumpRk(
            tester,
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RecoveryShowMyCodeScreen(
                          myCode: code,
                          encode: encoder.call,
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            viewport: rkPhone360,
          );
          await tester.tap(find.text('open'));
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();

          expect(encoder.payloads, isEmpty, reason: why);
          expect(find.byType(RkQrView), findsNothing, reason: why);
          expect(
            find.text(
              'This phone has no code for this request. Only the phone that '
              'asked for it can show one.',
            ),
            findsOneWidget,
            reason: why,
          );
          await tester.tap(find.text('Back'));
          await tester.pumpAndSettle();
          expect(
            find.text('open'),
            findsOneWidget,
            reason: '$why: no dead end',
          );
        }
      },
    );

    test(
      'F1-13c-6 over the live producer: this phone\'s own attempt draws its '
      'held key; another phone\'s attempt (a relayed key this phone does not '
      'hold) leaves HttpGuardianRecovery.candidate null and draws nothing',
      () async {
        // Another of the user's phones asked first.
        final other = RecoveryCandidateKeyPair.generate(suite);
        addTearDown(other.dispose);
        final server = _Server()
          ..add(other.x25519, device: '33333333-3333-4333-8333-333333333339');

        // Shown, not owned: a live attempt of another phone is not re-asked.
        final none = KeyStoreRecoveryCandidate(
          keys: FakeKeyStore(),
          suite: suite,
        );
        final watching = server.seam(none);
        await watching.refresh();
        expect(watching.current, isNotNull);
        expect(watching.candidate, isNull);
        expect(
          await myCode(none, () => watching.candidate).read(),
          isA<RecoveryMyCodeNotHeld>(),
        );

        // This phone opens its own attempt: the listing is emptied first so
        // the refresh asks (nothing listed → 04 §7.3 step 1).
        server.requests.clear();
        final holder = KeyStoreRecoveryCandidate(
          keys: FakeKeyStore(),
          suite: suite,
        );
        final mine = server.seam(holder);
        await mine.refresh();
        final held = (await holder.held())!;
        final read = await myCode(holder, () => mine.candidate).read();
        expect(read, isA<RecoveryMyCodeShown>());
        final drawn = DeviceQrPayload.decode(
          (read as RecoveryMyCodeShown).qrText,
        );
        expect(drawn.device.x25519, held);
        expect(drawn.device.x25519, isNot(other.x25519));
      },
    );

    testWidgets(
      'F1-13c-7 S11.2 offers Show my code on the ceremony step and while the '
      'request is live — not once it is closed or approved — and pushes the '
      'screen over itself; with no producer installed it says this phone '
      'cannot show its code yet, with Back',
      (tester) async {
        await pumpRk(
          tester,
          AskTrustedMembersScreen(
            recovery: FakeGuardianRecovery(initial: _attempt()),
          ),
          viewport: rkPhone360,
        );
        await tester.pumpAndSettle();
        expect(find.text('Show my code'), findsOneWidget);
        await tester.tap(find.text('Show my code'));
        await tester.pumpAndSettle();
        expect(find.byType(RecoveryShowMyCodeScreen), findsOneWidget);
        expect(
          find.text('This phone cannot show its code yet.'),
          findsOneWidget,
        );
        expect(find.byType(RkQrView), findsNothing);
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Scan their screen'), findsOneWidget);

        // Past the ceremony, while members can still approve.
        await tester.tap(find.text('Scan their screen'));
        await tester.pumpAndSettle();
        expect(find.text('Show my code'), findsOneWidget);

        for (final state in [
          RecoveryAttemptState.approved,
          RecoveryAttemptState.expired,
          RecoveryAttemptState.cancelled,
        ]) {
          await pumpRk(
            tester,
            AskTrustedMembersScreen(
              key: ValueKey(state),
              recovery: FakeGuardianRecovery(initial: _attempt(state: state)),
            ),
            viewport: rkPhone360,
          );
          await tester.pumpAndSettle();
          // Not on the ceremony step either: on a closed attempt the held key
          // is already discarded (review QR1 finding 3).
          expect(
            find.text('Show my code'),
            findsNothing,
            reason: '$state, ceremony step',
          );
          await tester.tap(find.text('Scan their screen'));
          await tester.pumpAndSettle();
          expect(
            find.text('Show my code'),
            findsNothing,
            reason: '$state, waiting list',
          );
        }
      },
    );

    testWidgets(
      'F1-13c-7 states: the ruled skeleton while reading, the retryable '
      'error (with Back) when the key store refuses',
      (tester) async {
        await pumpRk(
          tester,
          RecoveryShowMyCodeScreen(myCode: _Never()),
          viewport: rkPhone360,
        );
        await tester.pump();
        expect(find.byType(RkSkeleton), findsOneWidget);

        await pumpRk(
          tester,
          RecoveryShowMyCodeScreen(
            key: const ValueKey('broken'),
            myCode: myCode(_BrokenKeys(), () => candidate(_bytes(3))),
          ),
          viewport: rkPhone360,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('We could not get this phone’s code.'),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);
        expect(find.byType(RkQrView), findsNothing);
      },
    );

    testWidgets(
      'F1-13c-7 offline: the quiet chip over a square that still draws, '
      'because the code is this phone\'s own (07 §1 rule 7)',
      (tester) async {
        final (holder, held) = await tester.runAsync(
          heldPair,
        ) as (KeyStoreRecoveryCandidate, Uint8List);
        await pumpRk(
          tester,
          RecoveryShowMyCodeScreen(
            key: const ValueKey('offline'),
            myCode: myCode(holder, () => candidate(held)),
            encode: _Encoder().call,
          ),
          sync: FakeSyncClient(initial: const Offline()),
          viewport: rkTallViewport,
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(find.byType(RkQrView), findsOneWidget);
        expect(
          find.text(
            'Offline — your code still works, so they can scan it now.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-13c-7 every state resolves in EN, PA and HI and fits at 200 % on '
      '360×800 and 375×667',
      (tester) async {
        final (holder, held) = await tester.runAsync(
          heldPair,
        ) as (KeyStoreRecoveryCandidate, Uint8List);
        final codes = <RecoveryMyCode?>[
          myCode(holder, () => candidate(held)),
          myCode(holder, () => candidate(_bytes(3))),
          null,
          myCode(_BrokenKeys(), () => null),
        ];
        for (final size in rkPhones) {
          for (final locale in rkLocales) {
            for (final (i, code) in codes.indexed) {
              await pumpRk(
                tester,
                RecoveryShowMyCodeScreen(
                  key: ValueKey('$size$locale$i'),
                  myCode: code,
                  encode: _Encoder().call,
                ),
                locale: locale,
                textScale: 2,
                viewport: size,
              );
              await tester.runAsync(() => Future<void>.delayed(Duration.zero));
              await tester.pumpAndSettle();
              final l10n = AppLocalizations.of(
                tester.element(find.byType(RecoveryShowMyCodeScreen)),
              );
              expect(find.text(l10n.recoveryShowTitle), findsOneWidget);
              expect(
                tester.takeException(),
                isNull,
                reason: '$size $locale $i',
              );
            }
          }
        }
      },
    );
  });
}
