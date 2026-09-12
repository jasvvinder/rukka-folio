// S19.3 *No connection* — 13 §3.2 row S19.3 (`global`, *non-blocking; the app
// works offline*), 07 §24.
//
// It is built on the one banner atom of 13 §4.2 (`RkBannerSurface`) — same
// surface, same rule, same live region as the restriction family — and on
// nothing else. What it must never do:
//
//   * block: it is never a modal, never a route, never a barrier. Entry,
//     reading and **export** all continue while it is on screen; offline is
//     the app's normal state (05 §1, 07 §24).
//   * borrow the lapse vocabulary: 13 §5 🔒 keeps **two graces, two copies**
//     (ADR 2026-09-05g §4). `offlineGrace` is the *entitlement* grace and
//     says "Connect once to keep entering"; S19.3 is merely the radio being
//     off and says so in its own words. Structurally they cannot be confused
//     here: this notice has no access to `RkRestrictionCopy` at all.
//
// ⚠️ SPEC: neither 07 §24 nor 13 §3.2/§4.2 settles whether S19.3 is a fourth
// `RkRestrictionKind` or an atom of its own. 13 §4.2 enumerates the
// persistent banner as "suspended, read-only, book full" — S19.3 is not in
// that list, and every member of `RkRestrictionKind` is an entitlement or
// security position that a screen must *obey*. The conservative reading is
// taken: S19.3 shares the banner **atom** but not the restriction **family**,
// so no call site can pass it to `showRkBlockedEntrySheet` or read a
// `blocksEntry` from it. If the owner rules it a kind, this file collapses
// into `rk_restriction.dart` with the copy mapping unchanged.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'rk_banner.dart';

/// The S19.3 words, injected so this file stays free of the generated l10n
/// class (the rule `RkTabBar` and `RkRestrictionBanner` already follow).
/// Build one with `rkConnectionNoticeCopy(context)`.
@immutable
class RkConnectionNoticeCopy {
  /// Creates the copy set.
  const RkConnectionNoticeCopy({
    required this.title,
    required this.body,
    required this.retryLabel,
  });

  /// The fact: there is no connection.
  final String title;

  /// What that means — which is: nothing stops (13 §3.2 row S19.3).
  final String body;

  /// Label for the optional *try now* action. Never the only way on: the
  /// connection returning is itself the way on.
  final String retryLabel;
}

/// The S19.3 notice. Non-blocking, persistent while offline, dismissed by the
/// connection coming back and by nothing else.
class RkConnectionNotice extends StatelessWidget {
  /// Creates the notice. [onRetry] is optional — the screen may offer a
  /// manual check; with no callback the notice is pure information.
  const RkConnectionNotice({super.key, required this.copy, this.onRetry});

  /// The words.
  final RkConnectionNoticeCopy copy;

  /// Optional manual check.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final onRetry = this.onRetry;
    return RkBannerSurface(
      // `info`, never `warning` or `danger`: being offline is a normal state
      // of an offline-first app, not a problem the user caused.
      tone: RkBannerTone.info,
      // Colour never alone (07 §1 rule 3) — and a different icon from the
      // entitlement offline grace, which they are not.
      icon: Icons.wifi_off_outlined,
      title: copy.title,
      body: copy.body,
      actions: [
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: Text(copy.retryLabel)),
      ],
    );
  }
}

/// The mount seam.
///
/// Nothing in the app produces a connectivity signal yet — that lands with
/// sync (05) — so the notice is never wired into the shell here. A host
/// passes any `ValueListenable<bool>` (a fake in tests, the sync client's
/// reachability later) and the slot shows the notice while it reads true and
/// occupies **no space at all** when it reads false.
class RkConnectionNoticeSlot extends StatelessWidget {
  /// Creates the slot.
  const RkConnectionNoticeSlot({
    super.key,
    required this.offline,
    required this.copy,
    this.onRetry,
  });

  /// True while this device cannot reach the server.
  final ValueListenable<bool> offline;

  /// The words.
  final RkConnectionNoticeCopy copy;

  /// Optional manual check.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: offline,
    builder: (context, isOffline, _) => isOffline
        ? RkConnectionNotice(copy: copy, onRetry: onRetry)
        : const SizedBox.shrink(),
  );
}
