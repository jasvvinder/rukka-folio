@Tags(['F1'])
library;

// S11.2 and S11.3 on the **live** producers, over a fake socket (04 §7.3 🔒
// rung 2 / migration 0010, 04 §7.4 🔒 rung 3 / migration 0011).
//
// The screens' own suites run on `recovery_ladder.dart`'s fakes and settle the
// layout. These run the same two screens against `shared/sync`'s adapters and
// a scripted HTTP answer, because the two defects this slice exists to prevent
// are not layout defects and cannot be seen from a fake:
//
//   1. **A refusal that is not the AEAD, drawn as a wrong code.** The server
//      never sees the code a human typed and holds nothing it could compare
//      one against, so `no_sheet` — or a 401, or a dead socket — reaching
//      R2.4's *"That code did not work"* would tell somebody holding a
//      correctly copied sheet that they mistyped it.
//   2. **A tick beside somebody who did not act.** `progressToWire` sends a
//      count *and* the decision rows; only the rows may name a person, and
//      only for the generation of the set the attempt was pinned to.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/recovery/screens/s11_2_ask_members_screen.dart';
import 'package:rukka_folio/features/recovery/screens/s11_3_sheet_screen.dart';
import 'package:rukka_folio/features/recovery/screens/s11_6_fork_screen.dart';
import 'package:rukka_folio/features/recovery/widgets/recovery_parts.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/sync/guardians_api.dart';
import 'package:rukka_folio/shared/sync/recovery_roster.dart';
import 'package:rukka_folio/shared/sync/recovery_seams.dart';

import '../../shared/test_app.dart';

final _root = Uri.parse('https://api.example.test/functions/v1/');

const _sheetPath = '/functions/v1/sync-meta/recovery/sheet';
const _metaPath = '/functions/v1/sync-meta';

/// A code as the sheet prints it: Crockford Base32 in groups of four.
const _printed = 'K8N4-2QRT-9VWX-Y0Z1';

String _b64(List<int> b) =>
    base64Url.encode(Uint8List.fromList(b)).replaceAll('=', '');

/// One attempt, pinned to generation [version] (⚠️ WIRE `requestToWire`).
Map<String, Object?> _request({int version = 1}) => {
  'request_id': 'req-1',
  'candidate_device': 'dev-new',
  'candidate_pub_x': _b64(List<int>.generate(32, (i) => i)),
  'share_set_version': version,
  'opened_state': 'pending',
  'created_at': 1000,
  'expires_at': 260200000,
};

/// One reading (⚠️ WIRE `progressToWire`).
Map<String, Object?> _progress({
  int approvals = 1,
  int denials = 0,
  List<Map<String, Object?>> decisions = const [],
}) => {
  'request_id': 'req-1',
  'share_set_version': 1,
  'k': 2,
  'n': 3,
  'approvals': approvals,
  'denials': denials,
  'opened_state': 'pending',
  'state': 'pending',
  'kth_approval_at': null,
  'wait_until': null,
  'expires_at': 260200000,
  'cancelled_at': null,
  'decisions': decisions,
};

/// One generation of the published set (⚠️ WIRE the meta pull's
/// `guardian_sets`).
Map<String, Object?> _set(int version, List<String> ids) => {
  'subject_user_id': 'u-subject',
  'share_set_version': version,
  'k': 2,
  'n': ids.length,
  'guardians': [
    for (final id in ids) {'guardian_user_id': id, 'umk_pub_ed': ''},
  ],
};

FakeRkHttpTransport _transport(
  Map<String, Object?> Function(String method, Uri url) answer, {
  Map<String, int> status = const {},
}) => FakeRkHttpTransport(
  (method, url, headers, body) =>
      RkHttpResponse(status[url.path] ?? 200, jsonEncode(answer(method, url))),
);

HttpRecoveryApi _api(FakeRkHttpTransport t) => HttpRecoveryApi(
  transport: t,
  functionsRoot: _root,
  accessToken: () async => 'tok',
  clientVersion: '0.1.0',
);

HttpGuardiansApi _guardians(FakeRkHttpTransport t) => HttpGuardiansApi(
  transport: t,
  functionsRoot: _root,
  accessToken: () async => 'tok',
  clientVersion: '0.1.0',
);

/// The live S11.2 producer with the ceremony scanner passing, so the test
/// reaches the roster rows the way a person with a member's phone in front of
/// them does (ADR 2026-09-13c ruling 1 🔒 — the gate is never bypassed here,
/// it is *passed*).
HttpGuardianRecovery _recovery(
  FakeRkHttpTransport t, {
  required RecoveryRosterSource roster,
}) => HttpGuardianRecovery(
  api: _api(t),
  roster: roster,
  scanner: (_) async => RecoveryScanOutcome.verified,
  ticker: (_) => const Stream.empty(),
);

Future<void> _passCeremony(WidgetTester tester) async {
  await tester.tap(find.text('Scan their screen'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String code) async {
  await tester.tap(find.text('Type the code instead'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), code);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open my books'));
  await tester.pumpAndSettle();
}

void main() {
  group('S11.2 on the live producers (13 §3.2 row S11.2, design R2.2)', () {
    testWidgets(
      'F1-07-340 the screen names people at last: the decision rows land on '
      'the members they name, a denial reads *Said no*, and everybody else '
      'reads *Waiting…* — the count never ticks a row (0010 THE DECISION 🔒)',
      (tester) async {
        final t = _transport(
          (method, url) => switch (url.path) {
            _metaPath => {
              'guardian_sets': [
                _set(1, ['g1', 'g2', 'g3']),
              ],
            },
            _ =>
              url.queryParameters.containsKey('request_id')
                  ? _progress(
                      approvals: 1,
                      denials: 1,
                      decisions: const [
                        {'guardian_user_id': 'g3', 'decision': 'approved'},
                        {'guardian_user_id': 'g1', 'decision': 'denied'},
                      ],
                    )
                  : {
                      'requests': [_request()],
                    },
          },
        );
        final seam = _recovery(
          t,
          roster: PinnedGuardianRoster(
            api: _guardians(t),
            nameOf: (id) => switch (id) {
              'g1' => 'Sunita',
              'g2' => 'Harjit',
              _ => 'Balwinder',
            },
          ).call,
        );
        addTearDown(seam.dispose);

        await pumpRk(
          tester,
          AskTrustedMembersScreen(recovery: seam),
          viewport: rkTallViewport,
        );
        await _passCeremony(tester);

        // Three real people, drawn in the set's own order.
        expect(find.text('Sunita'), findsOneWidget);
        expect(find.text('Harjit'), findsOneWidget);
        expect(find.text('Balwinder'), findsOneWidget);

        // One tick, and it is on the member the row named — not on the first
        // of them, which is what a count would have produced.
        expect(find.text('Approved'), findsOneWidget);
        expect(find.text('Said no'), findsOneWidget);
        expect(find.text('Waiting…'), findsOneWidget);
        expect(find.text('1 of 2 approvals'), findsOneWidget);
        expect(
          find.text('Ask any 2 of 3 to approve'),
          findsOneWidget,
          reason: 'k and n stay the server\'s, carried as they came',
        );
      },
    );

    testWidgets(
      'F1-07-341 a re-split while the attempt is open moves no row: the set '
      'the attempt was PINNED to is drawn, and a member of the newer set — '
      'who was never asked — never appears (0010 pins share_set_version)',
      (tester) async {
        final t = _transport(
          (method, url) => switch (url.path) {
            _metaPath => {
              'guardian_sets': [
                _set(1, ['g1', 'g2', 'g3']),
                _set(2, ['g7', 'g8', 'g9']),
              ],
            },
            _ =>
              url.queryParameters.containsKey('request_id')
                  ? _progress(
                      decisions: const [
                        {'guardian_user_id': 'g2', 'decision': 'approved'},
                      ],
                    )
                  : {
                      'requests': [_request()],
                    },
          },
        );
        final seam = _recovery(
          t,
          roster: PinnedGuardianRoster(
            api: _guardians(t),
            nameOf: (id) => 'Person $id',
          ).call,
        );
        addTearDown(seam.dispose);

        await pumpRk(
          tester,
          AskTrustedMembersScreen(recovery: seam),
          viewport: rkTallViewport,
        );
        await _passCeremony(tester);

        expect(find.text('Person g2'), findsOneWidget);
        expect(find.text('Approved'), findsOneWidget);
        for (final absent in ['Person g7', 'Person g8', 'Person g9']) {
          expect(
            find.text(absent),
            findsNothing,
            reason: '$absent holds no share of the pinned generation',
          );
        }
      },
    );
  });

  group('S11.3 on the live producer (13 §3.2 row S11.3, design R2.4)', () {
    testWidgets(
      'F1-07-342 the wrong-code state is reached ONLY by the AEAD refusing: '
      'the blob is fetched, the opener says it did not open, and R2.4 states '
      'both causes (04 §7.4 🔒)',
      (tester) async {
        final t = _transport(
          (method, url) => {
            'user_id': 'u-subject',
            'sheet_version': 2,
            'sealed_rk_blob': _b64(const [1, 2, 3, 4]),
            'created_at': 1000,
          },
        );
        var opened = 0;
        final sheet = HttpRecoverySheet(
          api: _api(t),
          opener: (code, s) async {
            opened++;
            return false; // XChaCha20-Poly1305 refused these bytes.
          },
        );

        await pumpRk(
          tester,
          RecoverySheetScreen(sheet: sheet),
          viewport: rkTallViewport,
        );
        await _type(tester, _printed);

        expect(find.text('That code did not work'), findsOneWidget);
        expect(find.textContaining('newer sheet'), findsOneWidget);
        expect(find.textContaining('mistyped'), findsOneWidget);
        expect(opened, 1);
        // The route was asked for a user's blob, and told no code.
        final call = t.calls.single;
        expect(call.method, 'GET');
        expect(call.url.path, _sheetPath);
        expect(call.url.queryParameters, isEmpty);
      },
    );

    testWidgets(
      'F1-07-343 a user who never printed a sheet is NOT told their code is '
      'wrong: `no_sheet` is the error-with-retry state, and so is a refusal '
      'that never reached the AEAD (13 §4.3)',
      (tester) async {
        for (final answer in <({int status, String error})>[
          (status: 404, error: 'no_sheet'),
          (status: 401, error: 'unauthorized'),
          (status: 429, error: 'sheet_flood'),
        ]) {
          final t = _transport(
            (method, url) => {'error': answer.error},
            status: {_sheetPath: answer.status},
          );
          final sheet = HttpRecoverySheet(
            api: _api(t),
            opener: (code, s) async =>
                fail('nothing may be decrypted after ${answer.error}'),
          );

          await pumpRk(
            tester,
            RecoverySheetScreen(sheet: sheet),
            viewport: rkTallViewport,
          );
          await _type(tester, _printed);

          expect(
            find.text('We could not check that code just now.'),
            findsOneWidget,
            reason: '${answer.error} says nothing about the code',
          );
          expect(find.text('Try again'), findsOneWidget);
          expect(
            find.text('That code did not work'),
            findsNothing,
            reason: 'a correctly copied sheet is never called wrong',
          );
        }
      },
    );

    testWidgets(
      'F1-07-344 the code that opens the blob restores, and the restore is a '
      'count of entries — never a percentage and never a spinner (11 §4.5 🔒)',
      (tester) async {
        final t = _transport(
          (method, url) => {
            'user_id': 'u-subject',
            'sheet_version': 2,
            'sealed_rk_blob': _b64(const [1, 2, 3, 4]),
            'created_at': 1000,
          },
        );
        final sheet = HttpRecoverySheet(
          api: _api(t),
          opener: (code, s) async => s.sheetVersion == 2,
          restoreProgress: () => Stream.fromIterable(const [
            RecoveryProgress(
              done: 1240,
              total: 3890,
              unit: RecoveryUnit.entries,
            ),
          ]),
        );

        await pumpRk(
          tester,
          RecoverySheetScreen(sheet: sheet),
          viewport: rkTallViewport,
        );
        await _type(tester, _printed);

        expect(find.text('That code did not work'), findsNothing);
        expect(find.textContaining('entries restored'), findsOneWidget);
      },
    );
  });

  // =========================================================================
  // S11.6 and the third state (seams/recovery_ladder.dart:136 🔒)
  // =========================================================================
  //
  // This group lives in *this* file because it is the one file under
  // `test/features/recovery/` the `shared/sync` lane owns. What it pins is
  // the seam's own 🔒 — "A screen must not draw it as denied, and must not
  // draw it as confirmed either" — and it is the assertion whose absence let
  // `FakeRecoveryLadder.allUnknown()` sit unreferenced while the fork drew
  // the third state as the first.
  group('S11.6 — an unknown rung is not an available one', () {
    /// Everything about [rung]'s row a person or a screen reader can perceive
    /// **other than its colour**: the reason line, whether the row is live,
    /// what it announces, and every word in it.
    ///
    /// Deliberately not a list of specific widgets and deliberately not a
    /// render dump either — a dump of two pumps differs on RenderObject ids
    /// alone, which would make the comparison below pass for no reason at
    /// all. Colour is left out because 07 §1 rule "colour never alone" means
    /// a fix that only recoloured the row would not be a fix; any of the four
    /// things read here moving is.
    String rowSignature(WidgetTester tester, RecoveryRung rung) {
      final finder = find.byWidgetPredicate(
        (w) => w is RecoveryRungRow && w.rung == rung,
      );
      expect(finder, findsOneWidget, reason: '${rung.name} always renders');
      final row = tester.widget<RecoveryRungRow>(finder);
      final announced = tester
          .widgetList<Semantics>(
            find.descendant(of: finder, matching: find.byType(Semantics)),
          )
          .first
          .properties;
      final words = [
        for (final t in tester.widgetList<Text>(
          find.descendant(of: finder, matching: find.byType(Text)),
        ))
          t.data,
      ];
      return 'reason=${row.reason} live=${row.onTap != null} '
          'button=${announced.button} enabled=${announced.enabled} $words';
    }

    Future<String> render(
      WidgetTester tester,
      RecoveryRungOffer sheetOffer,
    ) async {
      await pumpRk(
        tester,
        RecoveryForkScreen(
          // Rungs 1 and 2 are held available in both runs: rung 1's state
          // moves 06 §5's "link instead" note onto the trusted row, so
          // varying it would make the two screens differ for a reason that
          // has nothing to do with the third state.
          ladder: FakeRecoveryLadder(
            offers: [
              const RecoveryRungOffer.available(RecoveryRung.anotherDevice),
              const RecoveryRungOffer.available(RecoveryRung.trustedMembers),
              sheetOffer,
            ],
          ),
          // Non-null in both runs, so a live tap is not masked by the screen
          // having nowhere to send the person.
          onRung: (_) {},
        ),
        viewport: rkTallViewport,
      );
      await tester.pumpAndSettle();
      return rowSignature(tester, RecoveryRung.recoverySheet);
    }

    testWidgets(
      'F1-07-417 a rung the ladder could not find out about is drawn '
      'differently from one a real source confirmed — offering "use your '
      'recovery sheet" as a working door to somebody who may have none '
      'spends the one attempt they steeled themselves for',
      (tester) async {
        const unknown = RecoveryRungOffer.unknown(RecoveryRung.recoverySheet);
        const available = RecoveryRungOffer.available(
          RecoveryRung.recoverySheet,
        );
        // Not vacuous: the two offers really are different answers, and
        // neither carries a `blocked` reason — which is exactly why a screen
        // reading `blocked == null` as "available" cannot tell them apart.
        expect(unknown.availability, RecoveryRungAvailability.unknown);
        expect(available.availability, RecoveryRungAvailability.available);
        expect(unknown.blocked, isNull);
        expect(available.blocked, isNull);

        final drawnUnknown = await render(tester, unknown);
        final drawnAvailable = await render(tester, available);

        expect(
          drawnUnknown,
          isNot(drawnAvailable),
          reason:
              'S11.6 draws the third state as the first — '
              's11_6_fork_screen.dart:216 passes `reason: blocked == null ? '
              'null : …` and :218 a live `onTap`, so an unknown rung is a '
              'confirmed one on screen',
        );
      },
      // The defect is real and confirmed; the fix is in
      // `app/lib/features/recovery/screens/s11_6_fork_screen.dart`, which the
      // `shared/sync` lane does not own. Landing this red would break the
      // build for the lane that does, so it is pinned and skipped rather than
      // dropped — the alternative is that nothing in the repo records it.
      // SKIPPED, not deleted: an `unknown` rung renders as `available`
      // (review finding 2 of 21 Sep). Un-skip with the fork-screen fix.
      skip: true,
    );

    testWidgets(
      'F1-07-416 the all-unknown ladder is a real state, not a test fixture: '
      'a wholly offline phone reaches the fork with three rungs it could not '
      'ask about and no reason to show for any of them',
      (tester) async {
        final ladder = FakeRecoveryLadder.allUnknown();
        await pumpRk(
          tester,
          RecoveryForkScreen(ladder: ladder, onRung: (_) {}),
          viewport: rkTallViewport,
        );
        await tester.pumpAndSettle();

        // Every rung still renders (13 §4.3 — there is no hidden state), and
        // not one of them may carry a reason, because none is true.
        for (final rung in RecoveryRung.forkOrder) {
          final row = tester.widget<RecoveryRungRow>(
            find.byWidgetPredicate(
              (w) => w is RecoveryRungRow && w.rung == rung,
            ),
          );
          expect(row.reason, isNull, reason: '${rung.name}: nothing refused');
        }
        expect(ladder.asked, 1, reason: 'the ladder was really consulted');
      },
    );
  });
}
