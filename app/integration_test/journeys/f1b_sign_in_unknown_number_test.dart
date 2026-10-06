// Journey f1b_sign_in — 13 §5 flow F1b with a fresh, unknown number:
// S0.06 *I already use Rukka* → S0.2 (sign-in state) → code → S0.2e *No books
// on this number* → *Set up new books* → S0.3 … F1 (Myself) → S1.
// Runs the real app (main → bootstrap) on a device against the dev server;
// see support/harness.dart and scripts/run_journeys.sh.
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  final binding = Journey.ensureBinding();

  testWidgets(
    'JOURNEY-f1b_sign_in F1b sign-in with an unknown number sets up new books',
    (tester) async {
      final j = await Journey.launch('f1b_sign_in', tester, binding);
      await openingSteps(j, door: Door.signIn);
      await noBooksSteps(j);
      await sharedSetupSteps(j, OnboardingPurpose.myself);
      await branchSteps(j, OnboardingPurpose.myself);
      await homeStep(j, OnboardingPurpose.myself);
      await j.finish();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
