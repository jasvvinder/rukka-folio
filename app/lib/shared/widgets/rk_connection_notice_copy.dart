// The l10n half of the S19.3 notice: locale → strings. Kept out of
// `rk_connection_notice.dart` so the widget stays free of the generated l10n
// class and can be pumped with any strings.
import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import 'rk_connection_notice.dart';

/// The S19.3 words in the ambient locale.
///
/// 13 §5 🔒 — **two graces, two copies**: these keys are `connection.*` and
/// are minted for S19.3 alone. The entitlement `offlineGrace` copy
/// (`subscription.banner.offline_grace.*`) is never reachable from here, so a
/// phone that is merely off-network can never be told anything about its
/// plan.
RkConnectionNoticeCopy rkConnectionNoticeCopy(BuildContext context) {
  final l = AppLocalizations.of(context);
  return RkConnectionNoticeCopy(
    title: l.connectionNoticeTitle,
    body: l.connectionNoticeBody,
    retryLabel: l.connectionNoticeRetry,
  );
}
