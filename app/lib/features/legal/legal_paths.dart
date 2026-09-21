/// Path constants for the Legal & trust feature (features/README "Routes").
/// S18 is a root-navigator hub reached from the **last** Menu row under
/// *This app* (07 §2, ADR 2026-09-03 ruling 3) — not a tab root.
///
/// Aliases of `RkPaths` — the single declaration lives in
/// `shared/router.dart` (the `RecoveryPaths` convention).
library;

import '../../shared/router.dart';

abstract final class LegalPaths {
  /// S18 Legal & trust hub.
  static const root = RkPaths.legal;

  /// S18.1 Terms of service (document page).
  static const terms = RkPaths.legalTerms;

  /// S18.2 Privacy policy (document page).
  static const privacy = RkPaths.legalPrivacy;

  /// S18.3 What we can and cannot see — 12 §2's impossibility table as a
  /// page (07 §23 🔒). The one S18 page with content of its own.
  static const whatWeSee = RkPaths.legalWhatWeSee;

  /// S18.4 Open-source licences (document page, filled from the bundle's
  /// own licence registry).
  static const licences = RkPaths.legalLicences;
}
