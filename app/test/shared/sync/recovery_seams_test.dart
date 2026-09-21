// The live producers behind the recovery-ladder seams, against the 0010 wire.
//
// Two properties carry the weight here and both are adversarial rather than
// cosmetic: **the 24 h ladder belongs to the server** (ADR 2026-09-05d §1 🔒,
// E-06-56 — a phone that can shorten it is a defect even when every screen
// looks right), and **an approval is attributed only to the guardian a row
// names** (0010 THE DECISION 🔒 — a counter cannot say who, and guessing who
// is worse than saying nothing).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/sync/guardians_api.dart';
import 'package:rukka_folio/shared/sync/recovery_roster.dart';
import 'package:rukka_folio/shared/sync/recovery_seams.dart';

final _root = Uri.parse('https://api.example.test/functions/v1/');

/// A candidate key that is 32 bytes and nothing anybody's.
Uint8List _key(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed + i) & 0xff));

String _b64(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

/// One attempt as `requestToWire` writes it.
Map<String, Object?> _request({
  String id = 'req-1',
  Uint8List? pub,
  int createdAt = 1000,
  int expiresAt = 260200000,
  String openedState = 'waiting_24h',
}) => {
  'request_id': id,
  'user_id': 'u-subject',
  'candidate_device': 'dev-new',
  'candidate_pub_x': _b64(pub ?? _key(1)),
  'share_set_version': 1,
  'opened_state': openedState,
  'created_at': createdAt,
  'expires_at': expiresAt,
};

/// One reading as `progressToWire` writes it.
Map<String, Object?> _progress({
  String state = 'waiting_24h',
  int approvals = 1,
  int denials = 0,
  int? waitUntil,
  List<Map<String, Object?>>? decisions,
}) => {
  'request_id': 'req-1',
  'share_set_version': 1,
  'k': 2,
  'n': 3,
  'approvals': approvals,
  'denials': denials,
  'opened_state': 'waiting_24h',
  'state': state,
  'kth_approval_at': null,
  'wait_until': waitUntil,
  'expires_at': 260200000,
  'cancelled_at': null,
  'decisions': decisions ?? const <Map<String, Object?>>[],
};

/// One ask as the `/recovery/asks` block writes it.
Map<String, Object?> _ask({String id = 'req-1', Uint8List? pub}) => {
  'request_id': id,
  'subject_user_id': 'u-subject',
  'candidate_device': 'dev-new',
  'candidate_pub_x': _b64(pub ?? _key(1)),
  'share_set_version': 1,
  'created_at': 1000,
  'expires_at': 260200000,
  'my_decision': null,
};

const _roster = [
  TrustedApprover(memberId: 'g1', name: 'Sunita', phone: '98765 43210'),
  TrustedApprover(memberId: 'g2', name: 'Harjit'),
  TrustedApprover(memberId: 'g3', name: 'Balwinder'),
];

/// A transport that answers by path and records what was asked.
({FakeRkHttpTransport transport, List<String> posts}) _wire(
  Map<String, Object?> Function(String method, Uri url) answer, {
  Map<String, int>? status,
}) {
  final posts = <String>[];
  final t = FakeRkHttpTransport((method, url, headers, body) {
    if (method == 'POST') posts.add('${url.path}|${body ?? ''}');
    final code = status?[url.path] ?? 200;
    return RkHttpResponse(code, jsonEncode(answer(method, url)));
  });
  return (transport: t, posts: posts);
}

HttpRecoveryApi _api(FakeRkHttpTransport t) => HttpRecoveryApi(
  transport: t,
  functionsRoot: _root,
  accessToken: () async => 'tok',
  clientVersion: '0.1.0',
);

void main() {
  group('S11.2 — the requester watches an attempt', () {
    test('F1-06-30 the 24 h wait is the SERVER\'s: a phone whose clock is past '
        '`wait_until` still reads waiting24h, because the state is the word the '
        'database derived (ADR 2026-09-05d §1 🔒, E-06-56)', () async {
      // `wait_until` is in 1970 — long past on any real clock. The server
      // nevertheless still says `waiting_24h`, and that is the only word
      // that decides anything.
      final w = _wire(
        (method, url) => url.queryParameters.containsKey('request_id')
            ? _progress(state: 'waiting_24h', waitUntil: 1)
            : {
                'requests': [_request()],
              },
      );
      final seam = HttpGuardianRecovery(
        api: _api(w.transport),
        roster: (_) async => _roster,
        ticker: (_) => const Stream.empty(),
      );
      addTearDown(seam.dispose);

      await seam.refresh();
      expect(seam.current!.state, RecoveryAttemptState.waiting24h);
      // Carried for display, never for a decision.
      expect(seam.current!.waitUntil, DateTime.fromMillisecondsSinceEpoch(1));
      // And nothing on this phone can move it: there is no input to the
      // mapping but the server's word.
      expect(recoveryStateOf('waiting_24h'), RecoveryAttemptState.waiting24h);
      expect(recoveryStateOf('approved'), RecoveryAttemptState.approved);
    });

    test(
      'F1-06-31 a state this build does not recognise reads as pending — the '
      'one direction a mapping may never fail in is toward approved',
      () {
        expect(recoveryStateOf(''), RecoveryAttemptState.pending);
        expect(recoveryStateOf('APPROVED'), RecoveryAttemptState.pending);
        expect(recoveryStateOf('ready'), RecoveryAttemptState.pending);
        expect(recoveryStateOf('denied'), RecoveryAttemptState.pending);
        // 03 §2.2 has no `denied`, so three denials arrive as `expired` and
        // are indistinguishable from 72 h — the seam says so and so does this.
        expect(recoveryStateOf('expired'), RecoveryAttemptState.expired);
      },
    );

    test(
      'F1-06-32 a count is not an attribution: the server says 2 approvals '
      'and names nobody, so no member is ticked (0010 THE DECISION 🔒)',
      () async {
        final w = _wire(
          (method, url) => url.queryParameters.containsKey('request_id')
              ? _progress(state: 'waiting_24h', approvals: 2)
              : {
                  'requests': [_request()],
                },
        );
        final seam = HttpGuardianRecovery(
          api: _api(w.transport),
          roster: (_) async => _roster,
          ticker: (_) => const Stream.empty(),
        );
        addTearDown(seam.dispose);

        await seam.refresh();
        final a = seam.current!;
        expect(a.approvers.length, 3);
        expect(
          a.approvers.map((x) => x.state),
          everyElement(TrustedApproverState.waiting),
          reason: 'no row may claim a person acted when nothing named them',
        );
        expect(a.approvals, 0, reason: 'under-reports, never misattributes');
        // The quorum itself is still the server's, carried as it came.
        expect(a.k, 2);
        expect(a.n, 3);
      },
    );

    test('F1-06-33 when the route names the rows, each decision lands on the '
        'member it names and on no other', () async {
      final w = _wire(
        (method, url) => url.queryParameters.containsKey('request_id')
            ? _progress(
                state: 'waiting_24h',
                approvals: 1,
                denials: 1,
                decisions: [
                  {'guardian_user_id': 'g3', 'decision': 'approved'},
                  {'guardian_user_id': 'g1', 'decision': 'denied'},
                ],
              )
            : {
                'requests': [_request()],
              },
      );
      final seam = HttpGuardianRecovery(
        api: _api(w.transport),
        roster: (_) async => _roster,
        ticker: (_) => const Stream.empty(),
      );
      addTearDown(seam.dispose);

      await seam.refresh();
      final by = {for (final x in seam.current!.approvers) x.memberId: x.state};
      expect(by['g3'], TrustedApproverState.approved);
      expect(by['g1'], TrustedApproverState.declined);
      expect(by['g2'], TrustedApproverState.waiting);
      expect(seam.current!.approvals, 1);
      expect(seam.current!.declines, 1);
      // The roster's order is the screen's order, untouched by the rows.
      expect(seam.current!.approvers.map((x) => x.memberId), [
        'g1',
        'g2',
        'g3',
      ]);
    });

    test(
      'F1-06-34 a closed attempt stops being polled — a decided attempt is '
      'not a slow flood of the route ADR 2026-09-05b §7 rate-limits',
      () async {
        var state = 'waiting_24h';
        var reads = 0;
        final w = _wire((method, url) {
          if (url.queryParameters.containsKey('request_id')) {
            reads++;
            return _progress(state: state);
          }
          return {
            'requests': [_request()],
          };
        });
        final tick = StreamController<void>.broadcast();
        addTearDown(tick.close);
        final seam = HttpGuardianRecovery(
          api: _api(w.transport),
          roster: (_) async => _roster,
          ticker: (_) => tick.stream,
        );
        addTearDown(seam.dispose);

        final seen = <RecoveryAttemptState>[];
        final sub = seam.watch().listen((a) => seen.add(a.state));
        addTearDown(sub.cancel);

        await seam.refresh();
        expect(reads, 1);
        tick.add(null);
        await pumpEventQueue();
        expect(reads, 2, reason: 'still open, still polled');

        state = 'cancelled';
        tick.add(null);
        await pumpEventQueue();
        expect(reads, 3);
        final after = reads;
        tick.add(null);
        tick.add(null);
        await pumpEventQueue();
        expect(reads, after, reason: 'cancelled is final; polling stopped');
        expect(seen.last, RecoveryAttemptState.cancelled);
      },
    );

    test('F1-06-35 with no attempt open and no candidate-key producer the seam '
        'refuses plainly rather than inventing one', () async {
      final w = _wire((method, url) => const {'requests': <Object?>[]});
      final seam = HttpGuardianRecovery(
        api: _api(w.transport),
        roster: (_) async => _roster,
        ticker: (_) => const Stream.empty(),
      );
      addTearDown(seam.dispose);

      await expectLater(seam.refresh(), throwsA(isA<RecoveryFailure>()));
      expect(seam.current, isNull);
      expect(w.posts, isEmpty, reason: 'no key was minted and none was sent');
    });
  });

  group('S11.7 — the guardian decides', () {
    HttpGuardianApprovals build(
      FakeRkHttpTransport t, {
      RecoveryScanner? scanner,
      RecoveryResealer? resealer,
    }) => HttpGuardianApprovals(
      api: _api(t),
      requesterNameOf: (u) => 'Gurpreet',
      deviceNameOf: (d) => 'a new phone',
      fingerprintOf: (b) => '8F3C 21A9',
      scanner: scanner,
      resealer: resealer,
    );

    test('F1-06-36 approve REFUSES before a matching scan, and sends nothing — '
        'ADR 2026-09-13c ruling 3 🔒 is a check in the contract, not advice on '
        'a screen', () async {
      final w = _wire(
        (method, url) => {
          'asks': [_ask()],
        },
      );
      final seam = build(w.transport, resealer: (_) async => _key(9));

      await expectLater(
        seam.approve('req-1'),
        throwsA(isA<RecoveryCandidateUnverified>()),
      );
      expect(w.posts, isEmpty, reason: 'no share was sealed and none sent');

      // The same call after a verified scan goes through.
      final ok = build(
        w.transport,
        scanner: (_) async => RecoveryScanOutcome.verified,
        resealer: (_) async => _key(9),
      );
      expect(
        await ok.verifyCandidateByScan('req-1'),
        RecoveryScanOutcome.verified,
      );
      await ok.approve('req-1');
      expect(w.posts.single, contains('/recovery/approve'));
      expect(
        w.posts.single,
        contains('"sealed_to_pub_x":"${_b64(_key(1))}"'),
        reason: 'sealed to THIS attempt\'s candidate key (0010)',
      );
    });

    test(
      'F1-06-37 a scan is bound to the attempt AND to the key it matched: it '
      'never carries to another request, and a later mismatch revokes it',
      () async {
        var pub = _key(1);
        final w = _wire(
          (method, url) => {
            'asks': [_ask(pub: pub), _ask(id: 'req-2', pub: _key(200))],
          },
        );
        var outcome = RecoveryScanOutcome.verified;
        final seam = build(
          w.transport,
          scanner: (_) async => outcome,
          resealer: (_) async => _key(9),
        );

        await seam.verifyCandidateByScan('req-1');
        // Another attempt was never scanned, so it cannot borrow this pass.
        await expectLater(
          seam.approve('req-2'),
          throwsA(isA<RecoveryCandidateUnverified>()),
        );

        // The attempt's candidate key changing out from under the scan is
        // refused too — the pass was for those bytes, not for that id.
        pub = _key(77);
        await expectLater(
          seam.approve('req-1'),
          throwsA(isA<RecoveryCandidateUnverified>()),
        );

        // And a mismatch clears an earlier pass (ruling 1 🔒 — hard fail).
        pub = _key(1);
        await seam.verifyCandidateByScan('req-1');
        outcome = RecoveryScanOutcome.mismatch;
        expect(
          await seam.verifyCandidateByScan('req-1'),
          RecoveryScanOutcome.mismatch,
        );
        await expectLater(
          seam.approve('req-1'),
          throwsA(isA<RecoveryCandidateUnverified>()),
        );
        expect(w.posts, isEmpty);
      },
    );

    test('F1-06-38 declining needs no scan — refusing is always safe (04 §7.3 '
        'step 7) — and load carries no financial field', () async {
      final w = _wire(
        (method, url) => {
          'asks': [_ask()],
        },
      );
      final seam = build(w.transport);

      final ask = await seam.load('req-1');
      expect(ask.requesterName, 'Gurpreet');
      expect(ask.newDeviceFingerprint, '8F3C 21A9');

      await seam.decline('req-1');
      expect(
        w.posts.single,
        startsWith('/functions/v1/sync-meta/recovery/deny'),
      );
      expect(w.posts.single, contains('"request_id":"req-1"'));
    });

    test(
      'F1-06-39 an attempt that does not exist and one this guardian may not '
      'see are ONE answer — the route is no oracle for whose recovery is in '
      'flight (0010, ADR 2026-09-05d §2)',
      () async {
        final w = _wire((method, url) => const {'asks': <Object?>[]});
        final seam = build(w.transport);

        RecoveryFailure? a;
        RecoveryFailure? b;
        try {
          await seam.load('req-nobodys');
        } on RecoveryFailure catch (e) {
          a = e;
        }
        try {
          await seam.load('req-missing');
        } on RecoveryFailure catch (e) {
          b = e;
        }
        expect(a, isNotNull);
        expect(b!.reason, a!.reason, reason: 'byte-identical refusals');
      },
    );
  });

  group('rung 3 — the recovery sheet (04 §7.4 🔒, migration 0011)', () {
    // The sheet as `GET /recovery/sheet` writes it.
    Map<String, Object?> sheetBody({int version = 2, List<int>? blob}) => {
      'user_id': 'u-subject',
      'sheet_version': version,
      'sealed_rk_blob': _b64(Uint8List.fromList(blob ?? const [1, 2, 3, 4])),
      'created_at': 1000,
    };

    const sheetPath = '/functions/v1/sync-meta/recovery/sheet';

    test(
      'F1-06-40 a wrong code is the CLIENT\'s AEAD verdict and nothing else: '
      'the server is asked for the user\'s own blob, is told no code, and the '
      'rejection comes from the opener (04 §7.4 🔒; supersedes the pre-0011 '
      'form of this id, ADR 2026-09-05i §4)',
      () async {
        final w = _wire((method, url) => sheetBody());
        RecoverySheetCode? sawCode;
        RecoverySheetWire? sawSheet;
        final sheet = HttpRecoverySheet(
          api: _api(w.transport),
          opener: (code, s) async {
            sawCode = code;
            sawSheet = s;
            return false; // XChaCha20-Poly1305 refused these bytes.
          },
        );

        final code = RecoverySheetCode.parse('ABCD-EFGH')!;
        await expectLater(
          sheet.submit(code),
          throwsA(isA<RecoverySheetRejected>()),
        );

        // The opener saw the code, and the SERVER did not: the fetch carries
        // no query and no body, so `no_sheet` can never be a verdict on a
        // code the route was never shown.
        expect(sawCode, code);
        expect(sawSheet!.blob, Uint8List.fromList(const [1, 2, 3, 4]));
        expect(sawSheet!.sheetVersion, 2);
        final call = w.transport.calls.single;
        expect(call.method, 'GET');
        expect(call.url.path, sheetPath);
        expect(call.url.queryParameters, isEmpty);
        expect(w.posts, isEmpty);
      },
    );

    test('F1-06-47 `no_sheet` is NOT a rejected code: a user who never printed '
        'one gets RecoveryFailure, so a correctly copied sheet is never called '
        'wrong (04 §7.4 🔒)', () async {
      var opened = 0;
      final w = _wire(
        (method, url) => {'error': 'no_sheet'},
        status: {sheetPath: 404},
      );
      final sheet = HttpRecoverySheet(
        api: _api(w.transport),
        opener: (code, s) async {
          opened++;
          return true;
        },
      );

      await expectLater(
        sheet.submit(RecoverySheetCode.parse('ABCD-EFGH')!),
        throwsA(
          allOf(
            isA<RecoveryFailure>(),
            isNot(isA<RecoverySheetRejected>()),
            isA<RecoveryFailure>().having(
              (e) => e.reason,
              'reason',
              'no_sheet',
            ),
          ),
        ),
      );
      expect(opened, 0, reason: 'nothing was decrypted, so nothing failed');
    });

    test(
      'F1-06-48 a refusal that is not the AEAD is never a rejection: offline, '
      'unauthorized and rate-limited all read as RecoveryFailure',
      () async {
        for (final answer in <({int status, String error})>[
          (status: 401, error: 'unauthorized'),
          (status: 429, error: 'sheet_flood'),
          (status: 500, error: 'boom'),
        ]) {
          final w = _wire(
            (method, url) => {'error': answer.error},
            status: {sheetPath: answer.status},
          );
          final sheet = HttpRecoverySheet(
            api: _api(w.transport),
            opener: (code, s) async => true,
          );
          await expectLater(
            sheet.submit(RecoverySheetCode.parse('ABCD-EFGH')!),
            throwsA(
              allOf(
                isA<RecoveryFailure>(),
                isNot(isA<RecoverySheetRejected>()),
              ),
            ),
            reason: '${answer.error} says nothing about the code',
          );
        }

        // A transport that never answered is the same: the one refusal that
        // does not claim the server spoke.
        final dead = FakeRkHttpTransport((method, url, headers, body) {
          throw const RkHttpFailure();
        });
        final offline = HttpRecoverySheet(
          api: _api(dead),
          opener: (code, s) async => true,
        );
        await expectLater(
          offline.submit(RecoverySheetCode.parse('ABCD-EFGH')!),
          throwsA(
            allOf(isA<RecoveryFailure>(), isNot(isA<RecoverySheetRejected>())),
          ),
        );
      },
    );

    test(
      'F1-06-49 with no opener this build reaches no verdict, so it asks for '
      'nothing and claims nothing — and an opener that THROWS is this device '
      'failing, not the code being wrong',
      () async {
        final w = _wire((method, url) => sheetBody());
        final blind = HttpRecoverySheet(api: _api(w.transport));
        await expectLater(
          blind.submit(RecoverySheetCode.parse('ABCD-EFGH')!),
          throwsA(
            allOf(isA<RecoveryFailure>(), isNot(isA<RecoverySheetRejected>())),
          ),
        );
        expect(
          w.transport.calls,
          isEmpty,
          reason:
              'no verdict is reachable, so the rate-limited route is not '
              'spent learning that',
        );
        expect(await blind.restore().toList(), isEmpty);
        expect(await blind.scanSheet(), RecoveryScanOutcome.unavailable);

        final w2 = _wire((method, url) => sheetBody());
        final broken = HttpRecoverySheet(
          api: _api(w2.transport),
          opener: (code, s) async => throw StateError('no key store'),
        );
        await expectLater(
          broken.submit(RecoverySheetCode.parse('ABCD-EFGH')!),
          throwsA(
            allOf(isA<RecoveryFailure>(), isNot(isA<RecoverySheetRejected>())),
          ),
        );
      },
    );

    test('F1-06-50 the code that opens the blob restores: submit returns, and '
        'the restore count is the one the producer was given (11 §4.5 🔒 — a '
        'count, never a percentage)', () async {
      final w = _wire((method, url) => sheetBody(version: 7));
      final sheet = HttpRecoverySheet(
        api: _api(w.transport),
        opener: (code, s) async => s.sheetVersion == 7,
        restoreProgress: () => Stream.fromIterable(const [
          RecoveryProgress(done: 1, total: 2, unit: RecoveryUnit.entries),
          RecoveryProgress(
            done: 2,
            total: 2,
            unit: RecoveryUnit.entries,
            finished: true,
          ),
        ]),
      );

      await sheet.submit(RecoverySheetCode.parse('ABCD-EFGH')!);
      final readings = await sheet.restore().toList();
      expect(readings.last.finished, isTrue);
      expect(readings.last.done, 2);
    });

    test('F1-06-51 publishing a sheet sends the sealed blob and NOTHING else — '
        'RK is on paper and never on the wire (04 §7.4 🔒)', () async {
      final w = _wire((method, url) => {'sheet_version': 3});
      final api = _api(w.transport);
      final version = await api.publishSheet(
        Uint8List.fromList(const [9, 8, 7]),
      );
      expect(version, 3);
      expect(w.posts.single, startsWith('$sheetPath|'));
      final body =
          jsonDecode(w.posts.single.split('|').last) as Map<String, Object?>;
      expect(body.keys, ['blob'], reason: 'no code, no RK, no checksum');
      expect(
        base64Url.decode(base64.normalize(body['blob']! as String)),
        const [9, 8, 7],
      );
    });

    test('F1-06-52 `no_sheet` is the only refusal that becomes null — a 401 '
        'must never read as "this user has no sheet"', () async {
      final missing = _wire(
        (method, url) => {'error': 'no_sheet'},
        status: {sheetPath: 404},
      );
      expect(await _api(missing.transport).sheet(), isNull);

      final denied = _wire(
        (method, url) => {'error': 'unauthorized'},
        status: {sheetPath: 401},
      );
      await expectLater(
        _api(denied.transport).sheet(),
        throwsA(isA<RecoveryApiFailure>()),
      );
    });
  });

  group('the roster is the set the attempt PINNED', () {
    /// One generation as the `guardian_sets` history carries it.
    Map<String, Object?> set(int version, List<String> ids) => {
      'subject_user_id': 'u-subject',
      'share_set_version': version,
      'k': 2,
      'n': ids.length,
      'guardians': [
        for (final id in ids) {'guardian_user_id': id, 'umk_pub_ed': ''},
      ],
    };

    HttpGuardiansApi guardians(FakeRkHttpTransport t) => HttpGuardiansApi(
      transport: t,
      functionsRoot: _root,
      accessToken: () async => 'tok',
      clientVersion: '0.1.0',
    );

    test(
      'F1-06-53 a re-split mid-attempt does not move the rows: the roster is '
      'the pinned generation\'s people, and the decision lands on the member '
      'it names (0010 pins share_set_version at open)',
      () async {
        final w = _wire(
          (method, url) => switch (url.path) {
            '/functions/v1/sync-meta' => {
              'guardian_sets': [
                set(1, ['g1', 'g2', 'g3']),
                // The user re-split after opening this attempt.
                set(2, ['g7', 'g8', 'g9']),
              ],
            },
            _ =>
              url.queryParameters.containsKey('request_id')
                  ? _progress(
                      decisions: [
                        {'guardian_user_id': 'g2', 'decision': 'approved'},
                      ],
                    )
                  : {
                      'requests': [_request()],
                    },
          },
        );
        final seam = HttpGuardianRecovery(
          api: _api(w.transport),
          roster: PinnedGuardianRoster(
            api: guardians(w.transport),
            nameOf: (id) => 'Name $id',
          ).call,
          ticker: (_) => const Stream.empty(),
        );
        addTearDown(seam.dispose);

        await seam.refresh();
        final rows = seam.current!.approvers;
        expect(rows.map((r) => r.memberId), ['g1', 'g2', 'g3']);
        expect(
          rows.map((r) => r.memberId),
          isNot(contains('g7')),
          reason: 'a member of the NEW set was never asked on this attempt',
        );
        expect(rows[1].state, TrustedApproverState.approved);
        expect(rows[0].state, TrustedApproverState.waiting);
        expect(rows[2].state, TrustedApproverState.waiting);
        expect(seam.current!.approvals, 1);
      },
    );

    test(
      'F1-06-54 a decision naming somebody outside the pinned set ticks '
      'nobody: an unrecognised row is dropped, never slid onto a neighbour',
      () async {
        final w = _wire(
          (method, url) => switch (url.path) {
            '/functions/v1/sync-meta' => {
              'guardian_sets': [
                set(1, ['g1', 'g2', 'g3']),
              ],
            },
            _ =>
              url.queryParameters.containsKey('request_id')
                  ? _progress(
                      approvals: 1,
                      denials: 1,
                      decisions: [
                        {'guardian_user_id': 'ghost', 'decision': 'approved'},
                        {'guardian_user_id': 'g3', 'decision': 'denied'},
                      ],
                    )
                  : {
                      'requests': [_request()],
                    },
          },
        );
        final seam = HttpGuardianRecovery(
          api: _api(w.transport),
          roster: PinnedGuardianRoster(
            api: guardians(w.transport),
            nameOf: (id) => 'Name $id',
            phoneOf: (id) => id == 'g1' ? '98765 43210' : null,
          ).call,
          ticker: (_) => const Stream.empty(),
        );
        addTearDown(seam.dispose);

        await seam.refresh();
        final rows = seam.current!.approvers;
        expect(rows.length, 3);
        expect(
          rows.where((r) => r.state == TrustedApproverState.approved),
          isEmpty,
          reason: 'the approval belongs to nobody on this screen',
        );
        // A denial is a row; silence is the absence of one, and the two are
        // drawn differently (04 §7.3 step 7 🔒).
        expect(rows[2].state, TrustedApproverState.declined);
        expect(rows[0].state, TrustedApproverState.waiting);
        expect(seam.current!.declines, 1);
        // A number is never the server's — only where this device holds one.
        expect(rows[0].phone, '98765 43210');
        expect(rows[1].phone, isNull);
      },
    );

    test('F1-06-55 a generation this device does not hold names NOBODY rather '
        'than substituting another one, and a roster that cannot be read is the '
        'same answer', () async {
      final other = _wire(
        (method, url) => switch (url.path) {
          '/functions/v1/sync-meta' => {
            'guardian_sets': [
              set(4, ['g1', 'g2', 'g3']),
            ],
          },
          _ => const {},
        },
      );
      expect(
        await PinnedGuardianRoster(
          api: guardians(other.transport),
          nameOf: (id) => id,
        ).call(1),
        isEmpty,
      );

      final dead = FakeRkHttpTransport((method, url, headers, body) {
        throw const RkHttpFailure();
      });
      expect(
        await PinnedGuardianRoster(
          api: guardians(dead),
          nameOf: (id) => id,
        ).call(1),
        isEmpty,
      );
    });
  });

  group('the wire', () {
    test(
      'F1-06-41 every call carries a fresh bearer and the min-version header, '
      'and each refusal keeps the name the route gave it',
      () async {
        var tokens = 0;
        final t = FakeRkHttpTransport((method, url, headers, body) {
          expect(headers['authorization'], 'Bearer tok-$tokens');
          expect(headers[HttpRecoveryApi.clientVersionHeader], '0.1.0');
          return RkHttpResponse(200, jsonEncode({'requests': <Object?>[]}));
        });
        final api = HttpRecoveryApi(
          transport: t,
          functionsRoot: _root,
          accessToken: () async => 'tok-${++tokens}',
          clientVersion: '0.1.0',
        );
        tokens = 0;
        await api.myRequests();
        expect(t.calls.single.url.path, '/functions/v1/sync-meta/recovery');

        // ⚠️ WIRE `recoveryError` in sync-meta/index.ts — one name each way.
        expect(
          recoveryRefusalOf('unknown_request', 403),
          RecoveryRefusal.unknownRequest,
        );
        expect(
          recoveryRefusalOf('unknown_candidate_device', 403),
          RecoveryRefusal.unknownRequest,
          reason: 'the two refuse identically',
        );
        expect(
          recoveryRefusalOf('recovery_closed', 409),
          RecoveryRefusal.recoveryClosed,
        );
        expect(
          recoveryRefusalOf('already_decided', 409),
          RecoveryRefusal.alreadyDecided,
        );
        expect(
          recoveryRefusalOf('candidate_key_mismatch', 409),
          RecoveryRefusal.candidateKeyMismatch,
        );
        expect(
          recoveryRefusalOf('no_guardian_set', 409),
          RecoveryRefusal.noGuardianSet,
        );
        expect(recoveryRefusalOf('recovery_flood', 429), RecoveryRefusal.flood);
        expect(
          recoveryRefusalOf('recovery_shape', 400),
          RecoveryRefusal.badRequest,
        );
        expect(
          recoveryRefusalOf('something_new', 500),
          RecoveryRefusal.server,
          reason: 'an unknown name is never guessed into something friendlier',
        );
      },
    );

    test('F1-06-56 rung 3\'s own refusals keep the names 0011 gave them, and '
        '`no_sheet` is its own reason — never folded into `not_found`', () {
      expect(recoveryRefusalOf('no_sheet', 404), RecoveryRefusal.noSheet);
      expect(
        recoveryRefusalOf('not_found', 404),
        RecoveryRefusal.notFound,
        reason: 'a missing attempt is not a missing sheet',
      );
      expect(recoveryRefusalOf('sheet_flood', 429), RecoveryRefusal.flood);
      expect(
        recoveryRefusalOf('sheet_version_out_of_order', 409),
        RecoveryRefusal.sheetConflict,
      );
      expect(
        recoveryRefusalOf('append_only', 409),
        RecoveryRefusal.sheetConflict,
        reason: '0011 is write-once: a conflict is never an overwrite',
      );
    });

    test('F1-06-42 a transport that never answered is `offline` — the one '
        'refusal that does not claim the server spoke', () async {
      final t = FakeRkHttpTransport((method, url, headers, body) {
        throw const RkHttpFailure();
      });
      final api = HttpRecoveryApi(
        transport: t,
        functionsRoot: _root,
        accessToken: () async => 'tok',
      );
      await expectLater(
        api.myRequests(),
        throwsA(
          isA<RecoveryApiFailure>().having(
            (e) => e.refusal,
            'refusal',
            RecoveryRefusal.offline,
          ),
        ),
      );
    });
  });
}
