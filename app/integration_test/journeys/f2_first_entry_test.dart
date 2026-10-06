// Journey f2_first_entry — 13 §5 flow F2 from a freshly set-up Home:
// F1 (the card from --dart-define=RF_JOURNEY_PURPOSE, default `family`) → S1
// → *Money in* → S2 keypad → money account → other side (S2.1, inline
// create) → Save → "Saved ✓" → back to S1, which shows the entry.
// The default card is `family` rather than `myself` so that F2 reaches S2
// even while the Myself path's Home is known to fail to load (no personal
// book is created); pass RF_JOURNEY_PURPOSE=myself to run it on that path.
// Runs the real app (main → bootstrap) on a device against the dev server;
// see support/harness.dart and scripts/run_journeys.sh.
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';

import 'support/flows.dart';
import 'support/harness.dart';

const _purposeName = String.fromEnvironment(
  'RF_JOURNEY_PURPOSE',
  defaultValue: 'family',
);

void main() {
  final binding = Journey.ensureBinding();

  testWidgets('JOURNEY-f2_first_entry F2 money in from Home shows on Home', (
    tester,
  ) async {
    final purpose = OnboardingPurpose.values.byName(_purposeName);
    final j = await Journey.launch('f2_first_entry', tester, binding);
    await openingSteps(j, door: Door.newBooks);
    await sharedSetupSteps(j, purpose);
    await branchSteps(j, purpose);
    await homeStep(j, purpose);
    await firstEntrySteps(j);
    await j.finish();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
