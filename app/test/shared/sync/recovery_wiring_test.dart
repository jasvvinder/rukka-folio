// The shell's side of the recovery ladder: one declaration per path, and the
// three scopes actually handing a producer down.
//
// Both are wiring facts rather than behaviour, and both are the kind that
// fails silently: a re-typed path diverges from the router on the day one of
// them changes, and a scope the composition root forgot leaves every screen
// on the seam's fake — which, for the sheet, is a fake that *accepts* codes.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/recovery/recovery_paths.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/sync/recovery_seams.dart';

void main() {
  test('F1-06-43 every activation path is one declaration in RkPaths with an '
      'alias here — features/README: never re-type a path', () {
    expect(RecoveryPaths.silent, same(RkPaths.recovery));
    expect(RecoveryPaths.fork, same(RkPaths.recoveryFork));
    expect(RecoveryPaths.nothingYet, same(RkPaths.recoveryNothingYet));
    expect(RecoveryPaths.askMembers, same(RkPaths.recoveryAskMembers));
    expect(RecoveryPaths.sheet, same(RkPaths.recoverySheet));
    expect(RecoveryPaths.approve, same(RkPaths.recoveryApprove));

    // Six distinct roots — a collision would silently shadow a screen.
    expect(
      {
        RecoveryPaths.silent,
        RecoveryPaths.fork,
        RecoveryPaths.nothingYet,
        RecoveryPaths.askMembers,
        RecoveryPaths.sheet,
        RecoveryPaths.approve,
      }.length,
      6,
    );
    // The parameterised one still fills in, and stays under /recovery.
    expect(RecoveryPaths.approveOf('req-1'), '/recovery/approve/req-1');
    expect(RecoveryPaths.approve, startsWith(RkPaths.recovery));
  });

  testWidgets(
    'F1-06-44 the three scopes hand the live producers down, and a screen '
    'reads them without knowing which it got',
    (tester) async {
      final api = HttpRecoveryApi(
        transport: FakeRkHttpTransport(
          (method, url, headers, body) => const RkHttpResponse(200, '{}'),
        ),
        functionsRoot: Uri.parse('https://api.example.test/functions/v1/'),
        accessToken: () async => 'tok',
      );
      final recovery = HttpGuardianRecovery(
        api: api,
        roster: () async => const [],
        ticker: (_) => const Stream.empty(),
      );
      addTearDown(recovery.dispose);
      final approvals = HttpGuardianApprovals(
        api: api,
        requesterNameOf: (_) => 'someone in this book',
        deviceNameOf: (_) => '',
        fingerprintOf: (_) => '',
      );

      late GuardianRecovery? seenRecovery;
      late RecoverySheetEntry? seenSheet;
      late GuardianApprovals? seenApprovals;
      await tester.pumpWidget(
        GuardianRecoveryScope(
          recovery: recovery,
          child: RecoverySheetScope(
            sheet: const HttpRecoverySheet(),
            child: GuardianApprovalsScope(
              approvals: approvals,
              child: Builder(
                builder: (context) {
                  seenRecovery = GuardianRecoveryScope.maybeOf(context);
                  seenSheet = RecoverySheetScope.maybeOf(context);
                  seenApprovals = GuardianApprovalsScope.maybeOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      expect(seenRecovery, same(recovery));
      expect(seenApprovals, same(approvals));
      expect(seenSheet, isA<HttpRecoverySheet>());
      // And never the fakes the screens are *tested* against — that swap is
      // the whole point of installing a scope.
      expect(seenRecovery, isNot(isA<FakeGuardianRecovery>()));
      expect(seenSheet, isNot(isA<FakeRecoverySheet>()));
      expect(seenApprovals, isNot(isA<FakeGuardianApprovals>()));
    },
  );
}
