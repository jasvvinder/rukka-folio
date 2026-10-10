// RESKIN1 audit captures for sign-in (ADR 2026-10-05 §2; ADR 2026-10-10b §1
// phase 1): the states the canvas draws that s0_2_sign_in_design_test.dart does
// not already capture.
//
// * S0.2 with the engine held before registration (HELD181, ADR 2026-10-10
//   §2 🔒): no sync chip, even when the status underneath is offline — the
//   frames (c1b L2, c1 O2a) draw none.
// * S19.1 (c3 *Update required · iPhone* / *· Android*) and its offline state.
// * S15.3's *Send the code* (c1b U3 *Forgot PIN · enter the code*): today the
//   forgot door opens S0.2 at its number step (main.dart `_onForgotPin`,
//   ⚠️ SPEC there), so that is what the pair shows against U3.
//
// S0.2c and S0.2d (c1b L6, L7) are not built (PLAN desk 160, SIGNIN2): nothing
// to capture; S0.2b's disabled *Yes* is the door (S0.2b__default).
//
// Pair with `python3 scripts/design_match.py pair S0.2` (S19.1, S15.3).
@Tags(['F1'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart';
import 'package:rukka_folio/features/auth/screens/s0_2_phone_otp_screen.dart';
import 'package:rukka_folio/features/auth/screens/s19_1_update_required_screen.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/design_capture.dart';
import '../lock/lock_harness.dart' show unmount;

/// The canvas's number (c1b): the frames draw 98765 43210.
const _number = '9876543210';

/// [child] under the app's scope with [sync] in place of the test default, so
/// a capture can show a held or offline engine.
Widget _withSync(SyncClient sync, Widget child) => Builder(
  builder: (context) {
    final s = RkScope.of(context);
    return RkScope(
      db: s.db,
      sync: sync,
      auth: s.auth,
      keys: s.keys,
      now: s.now,
      child: child,
    );
  },
);

void main() {
  Future<void> capture(
    WidgetTester tester,
    String sid,
    String state,
    Widget Function() child, {
    void Function()? check,
  }) async {
    for (final target in RkDesignTarget.values) {
      await rkDesignCapture(
        tester,
        sid: sid,
        state: state,
        target: target,
        child: child(),
      );
      check?.call();
      await unmount(tester);
    }
  }

  testWidgets('F1-R1C-2 design capture S0.2 held before registration — no '
      'sync chip although the status is offline (canvas 1b L2, HELD181)', (
    tester,
  ) async {
    await capture(
      tester,
      'S0.2',
      'held-offline',
      () => _withSync(
        FakeSyncClient(initial: const Offline(), held: true),
        PhoneOtpScreen(
          door: SignInDoor.signIn,
          onBack: () {},
          debugPhone: _number,
        ),
      ),
      // Held: no chip, although the status underneath is offline. The same
      // screen not held does draw it (phone_otp_screen_test.dart).
      check: () {
        expect(find.text('Your phone number'), findsNothing);
        expect(find.text('Sign in'), findsOneWidget);
        expect(
          find.text('Offline — you need internet for the code.'),
          findsNothing,
        );
      },
    );
  });

  testWidgets('F1-R1C-3 design capture S19.1 update required, and offline '
      '(canvas 3 S19.1 *Update required · iPhone* / *· Android*)', (
    tester,
  ) async {
    const gate = UpdateRequired(
      currentVersion: '1.0.0',
      requiredVersion: '1.2.0',
    );
    await capture(
      tester,
      'S19.1',
      'default',
      () => const UpdateRequiredScreen(gate: gate),
    );
    await capture(
      tester,
      'S19.1',
      'offline',
      () => _withSync(
        FakeSyncClient(initial: const Offline()),
        const UpdateRequiredScreen(gate: gate),
      ),
      check: () =>
          expect(find.text('You’ll need internet to update.'), findsOneWidget),
    );
  });

  testWidgets('F1-R1C-4 design capture S15.3 forgot PIN → *Send the code* '
      'lands on S0.2 (canvas 1b U3 *Forgot PIN · enter the code*)', (
    tester,
  ) async {
    // The route the forgot door pushes (auth_routes.dart: a bare
    // PhoneOtpScreen at its number step).
    await capture(
      tester,
      'S15.3',
      'forgot-send-code-lands',
      () => PhoneOtpScreen(onDone: (_) {}),
    );
  });
}
