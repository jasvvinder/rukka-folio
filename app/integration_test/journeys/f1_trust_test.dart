// Journey f1_trust — 13 §5 flow F1 via the *Our trust* purpose card:
// S0.0 → S0.1 → S0.05 → S0.06 *I'm new* → S0.2 → S0.3 → S0.4 → S0.8 → S0.5
// (+S0.5b) → branch S0.6a–i (invites skipped) → S0.6 → S1 with the setup checklist,
// whose *Finish <book>* row resumes the invite step (ADR 2026-10-07).
// Runs the real app (main → bootstrap) on a device against the dev server;
// see support/harness.dart and scripts/run_journeys.sh.
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';

import 'support/flows.dart';
import 'support/harness.dart';

void main() {
  final binding = Journey.ensureBinding();

  testWidgets(
    'JOURNEY-f1_trust F1 sign-up via Our trust reaches Home with the checklist',
    (tester) async {
      final j = await Journey.launch('f1_trust', tester, binding);
      await openingSteps(j, door: Door.newBooks);
      await sharedSetupSteps(j, OnboardingPurpose.trust);
      await branchSteps(j, OnboardingPurpose.trust);
      await homeStep(j, OnboardingPurpose.trust);
      // ADR 2026-10-07 ruling 3: the invite step was skipped above.
      await invitesSkippedRow(j, OnboardingPurpose.trust);
      await j.finish();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
