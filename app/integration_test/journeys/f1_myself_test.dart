// Journey f1_myself — 13 §5 flow F1 via the *Myself* purpose card:
// S0.0 → S0.1 → S0.05 → S0.06 *I'm new* → S0.2 → S0.3 → S0.4 → S0.8 → S0.5
// (+S0.5b) → branch S0.6a–i → S0.6 → S1 with the setup checklist.
// Runs the real app (main → bootstrap) on a device against the dev server;
// see support/harness.dart and scripts/run_journeys.sh.
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  final binding = Journey.ensureBinding();

  testWidgets('JOURNEY-f1_myself F1 sign-up via Myself reaches Home with the checklist', (
    tester,
  ) async {
    final j = await Journey.launch('f1_myself', tester, binding);
    await openingSteps(j, door: Door.newBooks);
    await sharedSetupSteps(j, OnboardingPurpose.myself);
    await branchSteps(j, OnboardingPurpose.myself);
    await homeStep(j, OnboardingPurpose.myself);
    await j.finish();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
