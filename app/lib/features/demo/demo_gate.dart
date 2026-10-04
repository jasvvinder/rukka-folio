// The demo builder's gate (owner-directed, 4 Oct 2026) — DEBUG ONLY.
//
// The builder exists so the owner can show people who asked for this app how
// it works, on a simulator, with each person's books already made from
// invented entries. It is open only when ALL of these hold:
//   1. the build is not a release build ([kReleaseMode] — a `const`, so a
//      release build drops every branch below and the rosters with them);
//   2. the demo-phone switch is on — the same define S0.2 reads
//      (`features/auth/phone_shape.dart`: `RF_DEMO_PHONES`), or this file's
//      own test seam [debugDemoBuilderOverride];
//   3. the phone that just signed in is on the roster.
// A release build that somehow carried the defines still answers *closed*,
// and scripts/check_release_flags.sh fails the release lane on any
// `RF_DEMO_` define as the second lock.
//
// The signed-in phone is held in memory only, for this launch only, and is
// never logged (CLAUDE.md rule 4): `AuthState.Active` carries no number, so
// [watchDemoSignIn] remembers the number the code went to (`OtpSent`) and
// promotes it when that sign-in completes.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/seams/auth_client.dart';
import '../auth/phone_shape.dart' show rfDemoPhones;
import 'demo_roster.dart';
import 'demo_roster_fallback.dart';

/// `--dart-define=RF_DEMO_ROSTER=<base64 of .demo/demo_roster.json>` —
/// passed by scripts/run_dev.sh when that git-ignored file exists.
const String rfDemoRoster = String.fromEnvironment('RF_DEMO_ROSTER');

/// Test seam only: when non-null, stands in for [rfDemoPhones] wherever
/// [demoBuilderOn] is called without an explicit `demoPhones`, so a widget
/// test can drive the S0.3 route down the demo-on path. It never opens a
/// release build. Tests that set it reset it to null in a tear-down.
@visibleForTesting
bool? debugDemoBuilderOverride;

/// Whether this build may offer the demo builder at all (conditions 1 and 2).
/// [demoPhones] and [releaseMode] are parameters only so a test can reach
/// every combination in one process — a `const` define cannot be flipped.
bool demoBuilderOn({bool? demoPhones, bool releaseMode = kReleaseMode}) {
  // `kReleaseMode` is tested by name, not only through the parameter: it is a
  // compile-time constant, so in a release build everything after this line
  // is dead code the compiler drops — whatever a caller passes.
  if (kReleaseMode || releaseMode) return false;
  return demoPhones ?? debugDemoBuilderOverride ?? rfDemoPhones;
}

/// The roster in force: the define's, else the fictional one. A release
/// build answers [DemoRoster.empty] without reading either.
DemoRoster activeDemoRoster({bool releaseMode = kReleaseMode}) {
  // As above: the constant guard is what lets a release build drop both the
  // define and the fictional roster.
  if (kReleaseMode || releaseMode) return DemoRoster.empty;
  return _decoded ??= decodeDemoRosterDefine(
    rfDemoRoster,
    fallback: fictionalDemoRoster,
  ).$1;
}

DemoRoster? _decoded;

/// The roster person who may build their books here, or null — all three
/// conditions at once. [roster] defaults to [activeDemoRoster].
(DemoPerson, DemoCase)? demoPersonFor({
  required String? signedInPhone,
  DemoRoster? roster,
  bool? demoPhones,
  bool releaseMode = kReleaseMode,
}) {
  if (!demoBuilderOn(demoPhones: demoPhones, releaseMode: releaseMode)) {
    return null;
  }
  return (roster ?? activeDemoRoster(releaseMode: releaseMode)).personForPhone(
    signedInPhone,
  );
}

/// The number that signed in during this launch, when the demo is on. Null
/// otherwise — and null after a restored session, which never names its
/// number (the demo then simply does not offer itself).
final ValueNotifier<String?> demoSignedInPhone = ValueNotifier<String?>(null);

/// Follows [auth] so [demoSignedInPhone] names the phone that just signed in.
/// Returns null — and listens to nothing — when the demo is off, so a normal
/// build never holds a number here.
StreamSubscription<AuthState>? watchDemoSignIn(
  AuthClient auth, {
  bool? demoPhones,
  bool releaseMode = kReleaseMode,
}) {
  if (!demoBuilderOn(demoPhones: demoPhones, releaseMode: releaseMode)) {
    return null;
  }
  String? pending;
  return auth.state.listen((s) {
    switch (s) {
      case OtpSent(:final phone):
        pending = phone;
      case Active():
        if (pending != null) demoSignedInPhone.value = pending;
      case SignedOut():
        pending = null;
        demoSignedInPhone.value = null;
    }
  });
}
