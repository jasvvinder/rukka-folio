// The two producers S17.4 needs and the app does not yet have.
//
// Both are declared here as interfaces with **no live implementation**, the
// way `RecoveryScanner` is declared in `features/recovery` and left null
// while ADR 2026-09-19 (mobile_scanner + url_launcher) is unratified. A seam
// with an absent producer is honest: the screen draws the
// disabled-with-reason state of 13 §4.3, states the reason in words, and
// still offers a way on (07 §1 rule 6 🔒 — no dead ends). It is not a stub
// that pretends to work.
//
//   * [DiagnosticsDevice] — app version, phone software version and the
//     app's own problem codes. Reading those needs a platform plugin
//     (`package_info_plus`) in `app/pubspec.yaml`, which no lane owns this
//     round, so the production route passes null and the report simply omits
//     the fields it cannot read.
//   * [DiagnosticsSender] — the channel the report goes out on. S17.3's
//     WhatsApp door is a `url_launcher` target, blocked by the same
//     unratified ADR, so production passes null and S17.4's primary action
//     is disabled with `diag.send.reason.channel` while *Copy the report*
//     carries the person forward.
library;

import 'diagnostics_report.dart';

/// Reads what the app can learn about the device it runs on.
///
/// 🔒 CLAUDE.md rule 4 binds an implementation of this: [DeviceFacts.problemCodes]
/// must come from the app's **own fixed table of codes** — never a formatted
/// message, never a string a person typed, never anything built from ledger
/// data. [buildDiagnosticsReport] shape-checks what it is handed and caps the
/// list, but that is a backstop behind this contract, not a substitute for it.
abstract class DiagnosticsDevice {
  /// The facts, or as many of them as this phone will give up. Throwing is a
  /// state S17.4 draws (`diag.collect.error`), not a crash.
  Future<DeviceFacts> read();
}

/// Sends a built payload to support.
abstract class DiagnosticsSender {
  /// Sends [payload] — the exact text the person just read. Throwing is the
  /// error state of 13 §4.3 (`diag.error.*`); nothing is retried silently.
  Future<void> send(String payload);
}

/// A device seam that answers with fixed facts. Used by tests and by any
/// future route that can supply the facts without a plugin.
final class FixedDiagnosticsDevice implements DiagnosticsDevice {
  /// Creates the seam over [facts].
  const FixedDiagnosticsDevice(this.facts);

  /// What [read] answers.
  final DeviceFacts facts;

  @override
  Future<DeviceFacts> read() async => facts;
}
