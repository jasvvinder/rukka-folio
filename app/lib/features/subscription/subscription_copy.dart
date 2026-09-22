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

/// Tier names (08 §2) in the ambient locale.
extension RkPlanCopy on RkPlan {
  /// This plan's name.
  String name(AppLocalizations l) => switch (this) {
    RkPlan.free => l.subscriptionPlanFree,
    RkPlan.personal => l.subscriptionPlanPersonal,
    RkPlan.family => l.subscriptionPlanFamily,
    RkPlan.familyPlus => l.subscriptionPlanFamilyPlus,
  };
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
