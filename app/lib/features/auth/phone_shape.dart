// The national ten-digit shape of a phone number this app will send an OTP
// to — one predicate for S0.2 (first run) and S16.2 (change number), so the
// two screens can never disagree about what a number looks like.
//
// The rule 06 §1 🔒 locks is only "one phone number (E.164) = one human"; the
// `[6-9]` lead digit is this app's own shape check (Indian mobiles begin 6–9),
// and the server accepts any E.164 (server/supabase/functions/_shared/phone.ts).
//
// **Demo range (owner-directed, 4 Oct 2026).** The synthetic demo accounts on
// the dev project use numbers that begin with 5 (`50000 01001` →
// `+91 5000001001`), which no real Indian mobile can, so a demo account can
// never be a real person. The app accepts them only when BOTH the build was
// given `--dart-define=RF_DEMO_PHONES=true` AND it is not a release build.
// Without the define the shape is exactly the `[6-9]` one, and a release build
// refuses 5-numbers even if the define slipped in — which
// scripts/check_release_flags.sh also fails the release lane on.
import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;

/// `--dart-define=RF_DEMO_PHONES=true` — dev builds only; off by default.
const bool rfDemoPhones = bool.fromEnvironment('RF_DEMO_PHONES');

final _realMobile = RegExp(r'^[6-9][0-9]{9}$');
final _demoMobile = RegExp(r'^5[0-9]{9}$');

/// Test seam only: when non-null, stands in for [rfDemoPhones] wherever
/// [isNationalPhoneShape] is called without an explicit `demoPhones` — so a
/// widget test can drive S0.2 and S16.2 down the demo-on path through the
/// screen itself, not just the predicate. It never widens a release build:
/// release mode refuses the demo range whatever this says. Tests that set it
/// reset it to null in a tear-down.
@visibleForTesting
bool? debugDemoPhonesOverride;

/// Whether [tenDigits] (already trimmed, no `+91`) is a number this build
/// will send a code to: `[6-9]` then nine digits always, and `5` then nine
/// digits only when demo phones are on and [releaseMode] is off.
///
/// [demoPhones] defaults to [debugDemoPhonesOverride], then to the build's
/// [rfDemoPhones]; [releaseMode] defaults to [kReleaseMode]. Both are
/// parameters only so a test can reach all four combinations in one run (a
/// `const` define cannot be flipped inside a test process).
bool isNationalPhoneShape(
  String tenDigits, {
  bool? demoPhones,
  bool releaseMode = kReleaseMode,
}) {
  if (_realMobile.hasMatch(tenDigits)) return true;
  final demo = demoPhones ?? debugDemoPhonesOverride ?? rfDemoPhones;
  return demo && !releaseMode && _demoMobile.hasMatch(tenDigits);
}
