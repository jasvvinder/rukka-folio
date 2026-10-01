// The l10n half of the subscription feature: enum → strings and icon, kept
// out of the seam so `entitlement_source.dart` and `tier_catalogue.dart` stay
// free of the generated l10n class and pumpable with any strings (the rule
// `rk_restriction_copy.dart` already follows).
//
// 🔒 **Two graces, two copies** (ADR 2026-09-05g §4, 13 §6). The two states
// that could be confused are written apart here and neither reaches for the
// other's words: [EntitlementState.readOnly] is the server-declared lapse,
// [EntitlementState.offlineGrace] says only *Connect once to keep entering*
// and never that a plan ended.
//
// Colour is never alone (07 §1 rule 3): every state carries an icon and a
// word, and the tint only reinforces them.
import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/rk_restriction.dart';
import 'entitlement_source.dart';
import 'tier_catalogue.dart';

/// Plan names in the ambient locale, keyed by **catalogue id** (ADR
/// 2026-09-25 §6). Never the catalogue's `name` column, which is the owner's
/// English console label (CLAUDE.md rule 8). An id this build has no words
/// for reads as *Another plan* — shown, never a crash.
extension RkPlanCopy on RkPlan {
  /// This plan's name.
  String name(AppLocalizations l) => switch (id) {
    'free' => l.subscriptionPlanFree,
    'personal' => l.subscriptionPlanPersonal,
    'shop' => l.subscriptionPlanShop,
    'business' => l.subscriptionPlanBusiness,
    'business_plus' => l.subscriptionPlanBusinessPlus,
    'family_lite' => l.subscriptionPlanFamilyLite,
    'family' => l.subscriptionPlanFamily,
    'family_plus' => l.subscriptionPlanFamilyPlus,
    'trust' => l.subscriptionPlanTrust,
    'trust_plus' => l.subscriptionPlanTrustPlus,
    _ => l.subscriptionPlanOther,
  };
}

/// A plan's "what is included" lines, in plain words (DESIGN-PACK §11 S12.1
/// 🔒: *"not a spec table"*): members, books, phones, space, then the two
/// extras ADR 2026-09-25 §5 lets a plan differ by — each said **both ways**,
/// so a plan without PDF says what still works rather than going quiet.
///
/// S12.1 passes a catalogue row's limits and features (describing a plan);
/// S12.3 passes the token's (what this tenant holds). Not one number is
/// written here.
List<String> rkIncludedLines(
  AppLocalizations l,
  EntitlementLimits limits,
  List<String> features,
) {
  // A null count is unlimited (`-1` on the wire, ADR 2026-09-24b §7 (b) 🔒)
  // — said as such, never as a small number.
  final members = limits.members;
  final devices = limits.devices;
  final bytes = limits.tenantBytes;
  final storage = bytes == null ? null : rkStorageOf(bytes);
  bool has(RkFeature f) => features.contains(f.wire);
  return [
    members == null
        ? l.plansLimitMembersUnlimited
        : l.plansLimitMembers(members),
    limits.businessBooks == null
        ? l.plansLimitBooksUnlimited
        : l.plansLimitBooks(limits.businessBooks!),
    devices == null
        ? l.plansLimitDevicesUnlimited
        : l.plansLimitDevices(devices),
    switch (storage) {
      null => l.plansLimitStorageUnlimited,
      (gigabytes: true, :final amount) => l.plansLimitStorageGb(amount),
      (gigabytes: false, :final amount) => l.plansLimitStorageMb(amount),
    },
    has(RkFeature.pdfOutput)
        ? l.plansFeaturePdfIncluded
        : l.plansFeaturePdfNone,
    has(RkFeature.statementImport)
        ? l.plansFeatureImportIncluded
        : l.plansFeatureImportNone,
  ];
}

/// State words, icon and tint (13 §6).
extension EntitlementStateCopy on EntitlementState {
  /// The state in one word or two.
  String label(AppLocalizations l) => switch (this) {
    EntitlementState.trial => l.subscriptionStateTrial,
    EntitlementState.active => l.subscriptionStateActive,
    EntitlementState.dunningGrace => l.subscriptionStateDunning,
    EntitlementState.readOnly => l.subscriptionStateReadOnly,
    EntitlementState.offlineGrace => l.subscriptionStateOfflineGrace,
  };

  /// The sentence under the state, or null where the persistent banner
  /// already carries it — read-only and offline grace both raise
  /// [RkRestrictionBanner], and a screen that said it twice would be saying
  /// it in two voices.
  String? body(AppLocalizations l) => switch (this) {
    EntitlementState.trial => l.subscriptionStateTrialBody,
    EntitlementState.active => l.subscriptionStateActiveBody,
    EntitlementState.dunningGrace => l.subscriptionStateDunningBody,
    EntitlementState.readOnly => null,
    EntitlementState.offlineGrace => null,
  };

  /// The icon that carries the state in grayscale (07 §1 rule 3, 07 §18).
  IconData get icon => switch (this) {
    EntitlementState.trial => Icons.hourglass_bottom,
    EntitlementState.active => Icons.check_circle_outline,
    EntitlementState.dunningGrace => Icons.error_outline,
    EntitlementState.readOnly => Icons.lock_outline,
    EntitlementState.offlineGrace => Icons.cloud_off_outlined,
  };

  /// Tint for the icon. Read-only is `info`, not `danger`: a lapsed plan is a
  /// state, not a security event (the reading `rk_restriction.dart` already
  /// took). Offline grace is `info` for the same reason — nothing is wrong.
  Color tint(RkStatusColors s) => switch (this) {
    EntitlementState.trial => s.info,
    EntitlementState.active => s.success,
    EntitlementState.dunningGrace => s.warning,
    EntitlementState.readOnly => s.info,
    EntitlementState.offlineGrace => s.info,
  };

  /// The S12.5 banner this state raises, or null where none is due.
  ///
  /// 🔒 Only [EntitlementState.readOnly] maps to
  /// [RkRestrictionKind.readOnly] — the lapse copy is unreachable from any
  /// other state, which is the same rule [Entitlement.state] enforces one
  /// layer down.
  RkRestrictionKind? get restriction => switch (this) {
    EntitlementState.readOnly => RkRestrictionKind.readOnly,
    EntitlementState.offlineGrace => RkRestrictionKind.offlineGrace,
    _ => null,
  };
}
