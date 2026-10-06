// ADR 2026-10-05b rulings 1–3 against the real method channels — SUPERSEDED
// for the device-key classes by ADR 2026-10-06 (6 Oct 2026, PLAN desk 152
// option b): the device keys are never biometric-bound and never move; the
// biometric set guards a separate gate key.
//
// The three tests below drove the API that ADR 2026-10-06 removed — the
// PIN-only → biometric class move behind the PIN (`upgradeAfterPin`), the
// biometric device-key namespace, and the native reset of that namespace after
// an invalidation (`dropInvalidatedAfterPin` → `resetBiometricDeviceItems`,
// which ruling 4 forbids: the native reset now touches the gate only). Their
// bodies are in git history (commit 0806100 and before); they stay here as
// skipped entries so the ids keep their record, and re-land as:
//   • C-1005b-1 → C-1006-2 (no qualifying biometric: no gate, S15 PIN-only,
//     nothing prompted) and C-1006-1 (where the device keys live);
//   • C-1005b-2 → C-1006-2 (behind the PIN a gate is minted; no key moves);
//   • C-1005b-3 → C-1006-4 (an enrolment change invalidates the gate only;
//     the MPIN mints a new one; the device keys are untouched).
// All in test/features/devices/gate_key_test.dart.
@Tags(['C'])
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'C-1005b-1 with no strong biometric enrolled the device keys are created '
    'in the PIN-only class (promptless Keystore, own namespace, no user auth), '
    'the binding is recorded first, nothing touches the biometric class — and '
    'the next PIN leaves them there',
    () {},
    skip:
        'superseded by ADR 2026-10-06 §1; re-lands as C-1006-1 and C-1006-2 '
        '(gate_key_test.dart)',
  );

  test(
    'C-1005b-2 after a biometric is enrolled, only a successful MPIN upgrades: '
    'the keys are re-created biometric-bound and read back before the PIN-only '
    'items are deleted; a cancelled prompt or a bad read-back keeps the '
    'PIN-only items; a wrong PIN or a biometric success alone changes nothing',
    () {},
    skip:
        'superseded by ADR 2026-10-06 §2; re-lands as C-1006-2 '
        '(gate_key_test.dart)',
  );

  test(
    "C-1005b-3 an invalidated biometric item reads as KeyStoreInvalidated, the "
    "plugin cannot even delete it, nothing is removed before the PIN, and after "
    "it the app's own reset clears it and the next device keys land in the "
    'class the phone qualifies for now — biometric if one is enrolled, PIN-only '
    'if none is',
    () {},
    skip:
        'superseded by ADR 2026-10-06 §4; re-lands as C-1006-4 '
        '(gate_key_test.dart)',
  );
}
