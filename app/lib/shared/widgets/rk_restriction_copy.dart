// The l10n half of the S12.5 pair: kind → strings. Kept out of
// `rk_restriction.dart` so the widgets stay free of the generated l10n class
// (the rule `RkTabBar` already follows) and can be pumped with any strings.
import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import 'rk_restriction.dart';

/// Builds the [RkRestrictionCopy] for [kind] from the current locale.
///
/// 13 §5 🔒 — **two graces, two copies**: `readOnly` is the tenant-wide,
/// server-declared lapse and `offlineGrace` is device-local. This mapping is
/// the only place the two can be confused, so they are written apart here and
/// the offline variant never reaches for a read-only string.
extension RkRestrictionCopyL10n on RkRestrictionKind {
  /// Strings for this kind in the ambient locale.
  RkRestrictionCopy copy(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (this) {
      RkRestrictionKind.readOnly => RkRestrictionCopy(
        bannerTitle: l.subscriptionBannerReadOnlyTitle,
        bannerBody: l.subscriptionBannerReadOnlyBody,
        // DESIGN-PACK §11 (S12.5) 🔒 names this button *Renew*; 13 §3.2 row
        // S12.5 names where it goes — S12.1 Plans.
        bannerActionLabel: l.subscriptionActionRenew,
        sheetTitle: l.subscriptionSheetReadOnlyTitle,
        sheetBlocked: l.subscriptionSheetReadOnlyBlocked,
        sheetStillWorks: l.subscriptionSheetReadOnlyStillWorks,
        sheetActionLabel: l.subscriptionActionRenew,
        sheetDismissLabel: l.subscriptionSheetDismiss,
        exportLabel: l.subscriptionActionExport,
      ),
      // Offline grace never blocks entry, so it never raises the sheet
      // (`blocksEntry` is false). Its sheet slots repeat its own banner words
      // rather than minting a surface the spec does not describe — and, above
      // all, rather than borrowing the read-only lapse copy.
      RkRestrictionKind.offlineGrace => RkRestrictionCopy(
        bannerTitle: l.subscriptionBannerOfflineGraceTitle,
        bannerBody: l.subscriptionBannerOfflineGraceBody,
        bannerActionLabel: l.subscriptionActionRetry,
        sheetTitle: l.subscriptionBannerOfflineGraceTitle,
        sheetBlocked: l.subscriptionBannerOfflineGraceBody,
        sheetStillWorks: l.subscriptionSheetBookFullStillWorks,
        sheetActionLabel: l.subscriptionActionRetry,
        sheetDismissLabel: l.subscriptionSheetDismiss,
        exportLabel: l.subscriptionActionExport,
      ),
      RkRestrictionKind.bookFull => RkRestrictionCopy(
        bannerTitle: l.subscriptionBannerBookFullTitle,
        bannerBody: l.subscriptionBannerBookFullBody,
        bannerActionLabel: l.subscriptionActionPlans,
        sheetTitle: l.subscriptionSheetBookFullTitle,
        sheetBlocked: l.subscriptionSheetBookFullBlocked,
        sheetStillWorks: l.subscriptionSheetBookFullStillWorks,
        sheetActionLabel: l.subscriptionActionPlans,
        sheetDismissLabel: l.subscriptionSheetDismiss,
        exportLabel: l.subscriptionActionExport,
      ),
    };
  }
}
