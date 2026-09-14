@Tags(['C'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/auth/activation_scenarios.dart';
import 'package:rukka_folio/features/auth/auth_routes.dart';
import 'package:rukka_folio/features/devices/devices_routes.dart';
import 'package:rukka_folio/features/onboarding/onboarding_paths.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/shared/router.dart';

/// Every path the composed router answers, including the four tab branches.
Set<String> registeredPaths() {
  final router = buildRouter(
    featureRoutes: [...onboardingRoutes, ...authRoutes, ...devicesRoutes],
  );
  final out = <String>{};
  void walk(Iterable<RouteBase> routes, String prefix) {
    for (final r in routes) {
      var here = prefix;
      if (r is GoRoute) {
        here = r.path.startsWith('/')
            ? r.path
            : '${prefix == '/' ? '' : prefix}/${r.path}';
        out.add(here);
      } else if (r is ShellRouteBase) {
        for (final b in (r as StatefulShellRoute).branches) {
          walk(b.routes, prefix);
        }
        continue;
      }
      walk(r.routes, here);
    }
  }

  walk(router.configuration.routes, '/');
  return out;
}

/// The path 13 §3.2's S-id is mounted at today, or null when no screen for it
/// exists yet (the lane's open items).
String? pathOf(ActivationDestination d) => switch (d) {
  ActivationDestination.onboardingPurpose => OnboardingPaths.purpose,
  ActivationDestination.home => RkPaths.home,
  ActivationDestination.silentRestore => null,
  ActivationDestination.recoveryFork => null,
  ActivationDestination.emptyVault => null,
};

void main() {
  group('C-06-17 — 06 §5 activation flows by scenario', () {
    // One case per row of the 06 §5 table, in the table's order.
    const cases =
        <
          ({String row, ActivationSignals signals, ActivationScenario scenario})
        >[
          (
            row: 'Fresh signup',
            signals: ActivationSignals(platform: ActivationPlatform.ios),
            scenario: ActivationScenario.freshSignup,
          ),
          (
            row: 'New phone, same Apple/Google account',
            signals: ActivationSignals(
              platform: ActivationPlatform.ios,
              knownAccount: true,
              platformKeysRestored: true,
            ),
            scenario: ActivationScenario.platformKeySync,
          ),
          (
            row: 'Reinstall, same iPhone',
            signals: ActivationSignals(
              platform: ActivationPlatform.ios,
              knownAccount: true,
              reinstall: true,
              localKeysFound: true,
            ),
            scenario: ActivationScenario.reinstallSameIphone,
          ),
          (
            row: 'Reinstall, same Android',
            signals: ActivationSignals(
              platform: ActivationPlatform.android,
              knownAccount: true,
              reinstall: true,
            ),
            scenario: ActivationScenario.reinstallSameAndroid,
          ),
          (
            row: 'New phone, has old device',
            signals: ActivationSignals(
              platform: ActivationPlatform.android,
              knownAccount: true,
              hasOtherCertifiedDevice: true,
            ),
            scenario: ActivationScenario.newPhoneHasOldDevice,
          ),
          (
            row: 'New phone, no old device',
            signals: ActivationSignals(
              platform: ActivationPlatform.ios,
              knownAccount: true,
            ),
            scenario: ActivationScenario.newPhoneNoOldDevice,
          ),
          (
            row: 'Every rung fails',
            signals: ActivationSignals(
              platform: ActivationPlatform.ios,
              knownAccount: true,
              everyRungFailed: true,
            ),
            scenario: ActivationScenario.everyRungFailed,
          ),
        ];

    test('C-06-17 every row of the 06 §5 table resolves to its own scenario, and the seven rows between them cover the enum', () {
      for (final c in cases) {
        expect(
          resolveActivationScenario(c.signals),
          c.scenario,
          reason: '06 §5 row "${c.row}"',
        );
      }
      expect(
        cases.map((c) => c.scenario).toSet(),
        ActivationScenario.values.toSet(),
        reason: '06 §5 lists seven scenarios; every one needs a case',
      );
    });

    test('C-06-17 every scenario names a designated screen, and no two rows of 06 §5 are left without one', () {
      for (final s in ActivationScenario.values) {
        expect(s.destination.screenId, isNotEmpty, reason: '$s');
      }
      // The table's distinct landings: onboarding, silent restore, home, the
      // recovery fork, the empty vault.
      expect(
        ActivationScenario.values.map((s) => s.destination).toSet(),
        ActivationDestination.values.toSet(),
      );
    });

    test('C-06-17 each designated screen that exists is mounted at its path in the composed router', () {
      final paths = registeredPaths();
      for (final d in ActivationDestination.values.where((d) => d.built)) {
        final p = pathOf(d);
        expect(p, isNotNull, reason: '${d.screenId} is marked built');
        expect(
          paths,
          contains(p),
          reason: '${d.screenId} must be reachable at $p',
        );
      }
    });

    test('C-06-17 a reinstall on Android is treated as a new phone even when the local store still answers, and an iPhone reinstall with the Keychain wiped is not', () {
      // 06 §5: "Keystore was wiped → treat as new phone". The rule is the
      // platform's, not the observation's — a stale local answer must not
      // short-circuit it.
      expect(
        resolveActivationScenario(
          const ActivationSignals(
            platform: ActivationPlatform.android,
            knownAccount: true,
            reinstall: true,
            localKeysFound: true,
          ),
        ),
        ActivationScenario.reinstallSameAndroid,
      );
      expect(
        resolveActivationScenario(
          const ActivationSignals(
            platform: ActivationPlatform.ios,
            knownAccount: true,
            reinstall: true,
          ),
        ),
        ActivationScenario.newPhoneNoOldDevice,
      );
    });

    test('C-06-17 platform key sync wins over the ladder, and an exhausted ladder wins over everything (06 §5 first and last rows)', () {
      expect(
        resolveActivationScenario(
          const ActivationSignals(
            platform: ActivationPlatform.android,
            knownAccount: true,
            platformKeysRestored: true,
            hasOtherCertifiedDevice: true,
          ),
        ),
        ActivationScenario.platformKeySync,
      );
      expect(
        resolveActivationScenario(
          const ActivationSignals(
            platform: ActivationPlatform.ios,
            knownAccount: true,
            localKeysFound: true,
            everyRungFailed: true,
          ),
        ),
        ActivationScenario.everyRungFailed,
      );
    });

    test('C-06-17 guardian recovery is immediate only when no certified device is active (ADR 2026-09-05d §1)', () {
      expect(
        ActivationScenario.newPhoneHasOldDevice.guardianRecoveryIsWindowed,
        isTrue,
      );
      for (final s in ActivationScenario.values.where(
        (s) => s != ActivationScenario.newPhoneHasOldDevice,
      )) {
        expect(s.guardianRecoveryIsWindowed, isFalse, reason: '$s');
      }
    });

    test(
      'C-06-17 the recovery-ladder screens 06 §5 designates are built and routed',
      () {
        // S11.2 (ask guardians), S11.3 (paper sheet), S11.5 (silent restore),
        // S11.6 (the fork) and S11.8 (nothing worked yet) are listed in
        // 13 §3.2 with "activation" as their entry point, and none of them
        // exists in app/lib/features today — four of the seven 06 §5 rows have
        // no screen to land on. Reported as an open item by lane M7-C4; this
        // test lands with those screens.
        final paths = registeredPaths();
        for (final d in ActivationDestination.values.where((d) => !d.built)) {
          expect(pathOf(d), isNotNull, reason: d.screenId);
          expect(paths, contains(pathOf(d)), reason: d.screenId);
        }
      },
      skip: 'S11.2/S11.3/S11.5/S11.6/S11.8 are not built — 13 §3.2 gap reported by M7-C4',
    );
  });
}
