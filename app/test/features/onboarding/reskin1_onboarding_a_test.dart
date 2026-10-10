// Re-skin phase 1 audit captures (ADR 2026-10-05 §2; ADR 2026-10-10b §1;
// PLAN desk 142) for the onboarding core without a design test of its own:
// S0.0 Splash · S0.05 Welcome · S0.1 Language · S0.3 Purpose · S0.4 Name &
// photo · S0.5 Keeping your books safe · S0.9 Invitation.
//
// Phase 1 changes no production code: these captures only put each screen
// beside its canvas frame. Pair with
// `python3 scripts/design_match.py pair <S-id>`; the records are
// design/match/<S-id>.json.
//
// Every state is captured twice (iOS 390×844, matched against the frame;
// Android 360×800, reviewed for reflow).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/invitation_gateway.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_05_welcome_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_0_splash_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_1_language_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_4_name_photo_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_5_books_safe_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_9_invitation_screen.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/design_capture.dart';
import '../../shared/test_app.dart' show openTestDb, pumpRk, testNow;
import '../lock/lock_harness.dart' show unmount;

/// Captures one state per target, fresh each time.
Future<void> _each(
  WidgetTester tester,
  String sid,
  String state,
  Widget Function(RkDesignTarget target) child,
) async {
  for (final target in RkDesignTarget.values) {
    await rkDesignCapture(
      tester,
      sid: sid,
      state: state,
      target: target,
      child: child(target),
    );
    await unmount(tester);
  }
}

/// Captures a run of states that one State walks through ([between] moves it
/// on). The same GlobalKey across pumps re-parents the State, so the second
/// capture is the tap's result rather than a fresh screen.
Future<void> _walk(
  WidgetTester tester,
  String sid,
  List<String> states,
  Widget Function(Key key) child,
  Future<void> Function() between,
) async {
  for (final target in RkDesignTarget.values) {
    final key = GlobalKey();
    for (var i = 0; i < states.length; i++) {
      if (i > 0) await between();
      if (states[i].startsWith('_')) {
        await pumpRk(tester, child(key), viewport: target.size);
        continue;
      }
      await rkDesignCapture(
        tester,
        sid: sid,
        state: states[i],
        target: target,
        child: child(key),
      );
    }
    await unmount(tester);
  }
}

/// A signed-in, certified device for S0.9 (06 §3 step 4). The capture helper
/// pumps a signed-out fake, so S0.9 gets its own scope here.
Future<Widget> _certified(Widget child) async {
  final db = await openTestDb();
  return RkScope(
    db: db,
    sync: FakeSyncClient(),
    auth: FakeAuthClient(
      initial: const Active(
        AuthSession(userId: 'u-1', deviceId: 'd-1'),
        deviceCertified: true,
      ),
    ),
    keys: FakeKeyStore(),
    now: testNow,
    child: child,
  );
}

/// Synthetic offer and book names (CLAUDE.md rule 4) — the frame's own
/// placeholders, so the pair compares like with like.
InviteOffer _offer() => InviteOffer(
  inviteId: 'inv-1',
  tenantId: 'tenant-1',
  roles: [
    for (var i = 0; i < 3; i++) {'book_id': 'book-$i', 'role': 'member'},
  ],
  expiresAt: testNow().add(const Duration(days: 7)),
  createdBy: 'user-admin',
);

void main() {
  testWidgets('F1-1010r-1 design capture S0.0 Splash (canvas 1/11 O0)', (
    tester,
  ) async {
    // reducedMotion holds the (invisible until slow) loader still, so the
    // tree settles; the locked branch draws the same frame either way.
    await _each(
      tester,
      'S0.0',
      'default',
      (_) => const SplashScreen(reducedMotion: true),
    );
  });

  testWidgets('F1-1010r-2 design capture S0.05 Welcome 1·2·3 (canvas 1/11 '
      'O0b)', (tester) async {
    await _walk(
      tester,
      'S0.05',
      const ['slide1', 'slide2', 'slide3'],
      (key) => WelcomeScreen(key: key, onDone: () {}),
      () async {
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('F1-1010r-3 design capture S0.1 Language (canvas 1/11 O1)', (
    tester,
  ) async {
    await _each(
      tester,
      'S0.1',
      'default',
      (_) => LanguagePickerScreen(onSelected: (_) {}),
    );
  });

  testWidgets('F1-1010r-4 design capture S0.3 Purpose (canvas 1 O3; '
      'c11–c14 O3 chooses …)', (tester) async {
    await _each(
      tester,
      'S0.3',
      'default',
      (_) => PurposeScreen(onSelected: (_) {}),
    );
  });

  testWidgets('F1-1010r-5 design capture S0.4 Name & photo (canvas 1 O4)', (
    tester,
  ) async {
    await _each(
      tester,
      'S0.4',
      'default',
      (_) =>
          NamePhotoScreen(onPickPhoto: () async => null, onSubmit: (_, _) {}),
    );
    // O4 draws the field filled (the frame's own synthetic name), so the
    // pair also needs the filled state to compare like with like.
    await _each(
      tester,
      'S0.4',
      'filled',
      (_) => NamePhotoScreen(
        initialName: 'Amrit Kaur',
        onPickPhoto: () async => null,
        onSubmit: (_, _) {},
      ),
    );
  });

  testWidgets('F1-1010r-6 design capture S0.5 Books safe — key sync on and '
      'the no-key-sync variant (canvas 1/11 O5)', (tester) async {
    // The default capture is built exactly as production builds it
    // (onboarding_routes.dart, booksSafe route): no `keySyncAvailable` and no
    // `backupDestination`, so it shows 04 §7.0's default (on) and the generic
    // "Saved to your own cloud drive" line — what a user actually sees.
    await _each(
      tester,
      'S0.5',
      'default',
      (_) => BooksSafeScreen(onContinue: () {}, onSheet: () {}, onSkip: () {}),
    );
    // ⚠️ SPEC: production cannot reach this state in this build — no host
    // wires the `keySyncAvailable` seam (onboarding_routes.dart ⚠️ SPEC), so a
    // null check always reads as "on". It is captured only because canvas 1
    // draws the no-iCloud / no-Google-Password-Manager variant and the screen
    // carries it behind the seam; design/match/S0.5.json says so. Otherwise it
    // is built as production builds it (no destination).
    await _each(
      tester,
      'S0.5',
      'no_key_sync',
      (_) => BooksSafeScreen(
        keySyncAvailable: () async => false,
        onContinue: () {},
        onSheet: () {},
        onSkip: () {},
      ),
    );
  });

  testWidgets('F1-1010r-7 design capture S0.9 Invitation — offer and '
      'accepted (canvas 1 O7a, O7b)', (tester) async {
    for (final target in RkDesignTarget.values) {
      final gateway = FakeInvitationGateway(
        offers: [_offer()],
        joined: const [
          PendingBook(name: 'Joint fund', activateWithName: 'Amrit'),
          PendingBook(name: 'Ramesh household', activateWithName: 'Amrit'),
          PendingBook(name: 'Kirana Store', activateWithName: 'Amrit'),
        ],
      );
      final key = GlobalKey();
      Future<Widget> screen() => _certified(
        InvitationGatewayScope(
          gateway: gateway,
          child: InvitationScreen(
            key: key,
            onOpenMyBook: () {},
            onConfirmNumber: () {},
            onSetUpPhone: () {},
            onOpenDevices: () {},
          ),
        ),
      );
      await rkDesignCapture(
        tester,
        sid: 'S0.9',
        state: 'offer',
        target: target,
        child: await screen(),
      );
      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();
      await rkDesignCapture(
        tester,
        sid: 'S0.9',
        state: 'joined',
        target: target,
        child: await screen(),
      );
      await unmount(tester);
    }
  });
}
