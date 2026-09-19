// S11.6 — Recovery, the fork (13 §3.2 row S11.6, design R2.1, 04 §7, 06 §5).
//
// The quiet screen after OTP on a new phone. Rung 0 has already been tried and
// found nothing (S11.5), so this is the first moment the person is asked to
// choose anything — and the pack's whole instruction about tone is that they
// are anxious and possibly at a shop counter. Three ways in, in the pack's 🔒
// order, each with one plain line; then the muted truth about the private
// book. Nothing else.
//
// **No app bar.** There is nothing behind this screen but the OTP they just
// passed, and a back arrow to it would be a route out of their own books.
//
// **Every rung always renders** (13 §4.3 disabled-with-reason). S11.2 and
// S11.3 are not built at M11, so those two rows arrive blocked — and a
// blocked row still states its reason and still names a way that works, which
// is what 07 §1 rule 6 asks of a blocked action. A row that disappeared would
// quietly teach the reader that the way is gone; it is not.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/seams/recovery_ladder.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../widgets/recovery_parts.dart';

/// The fork. [ladder] is the seam; when it is null the screen takes the one
/// installed above it, and shows its error state when there is none — never a
/// red screen (07 §1 rule 6).
class RecoveryForkScreen extends StatefulWidget {
  /// Creates the screen.
  const RecoveryForkScreen({
    super.key,
    this.ladder,
    this.onRung,
    this.onNothingWorked,
  });

  /// The ladder to ask; defaults to [RecoveryLadderScope]'s.
  final RecoveryLadder? ladder;

  /// Taken with the rung the person chose. The screens that walk rungs 2 and
  /// 3 are other slices; this screen only says which way was picked.
  final void Function(RecoveryRung rung)? onRung;

  /// Taken when no rung is open and the person asks what happens now → S11.8.
  final VoidCallback? onNothingWorked;

  @override
  State<RecoveryForkScreen> createState() => _RecoveryForkScreenState();
}

class _RecoveryForkScreenState extends State<RecoveryForkScreen> {
  List<RecoveryRungOffer>? _offers;
  bool _failed = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(RecoveryForkScreen old) {
    super.didUpdateWidget(old);
    // A new ladder is a new answer. Without this the screen would keep the
    // first reading for the life of the element — which is wrong on the real
    // route the moment the shell installs a ladder over a screen that was
    // built before one existed, and is exactly the stale state a test catches
    // when it pumps two ladders in a row.
    if (widget.ladder != old.ladder) _load();
  }

  /// Asks the ladder and moves the screen's state.
  ///
  /// The result is held as plain fields rather than a `Future` handed to a
  /// `FutureBuilder`: a ladder that fails **synchronously** completes its
  /// future before any builder has subscribed, and the framework reports that
  /// as an unhandled error — a red test over a screen that is behaving
  /// correctly. Catching here keeps the failure inside the screen, where
  /// 13 §4.3's error-with-retry lives.
  Future<void> _load() async {
    final ladder = widget.ladder ?? RecoveryLadderScope.maybeOf(context);
    setState(() {
      _offers = null;
      _failed = false;
    });
    if (ladder == null) {
      // No ladder in the tree: the honest answer is the error state with a
      // retry, not a crash and not a blank (07 §1 rule 6).
      setState(() => _failed = true);
      return;
    }
    try {
      final offers = await ladder.rungs();
      if (!mounted) return;
      setState(() => _offers = offers);
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offers = _offers;
    return Scaffold(
      body: SafeArea(
        child: switch ((_failed, offers)) {
          (true, _) => RkErrorState(
            text: l10n.recoveryForkError,
            retryLabel: l10n.recoveryForkRetry,
            onRetry: _load,
          ),
          (false, null) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(RkSpace.gutter),
                child: RkFitText(
                  l10n.recoveryForkLoading,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Expanded(
                child: RkSkeleton(label: l10n.recoveryForkLoading, rows: 3),
              ),
            ],
          ),
          (false, final list?) => _Fork(
            offers: list,
            onRung: widget.onRung,
            onNothingWorked: widget.onNothingWorked,
          ),
        },
      ),
    );
  }
}

class _Fork extends StatelessWidget {
  const _Fork({
    required this.offers,
    required this.onRung,
    required this.onNothingWorked,
  });

  final List<RecoveryRungOffer> offers;
  final void Function(RecoveryRung rung)? onRung;
  final VoidCallback? onNothingWorked;

  /// The offer for [rung]; a rung the ladder forgot is treated as blocked by
  /// *this build*, never as absent.
  RecoveryRungOffer _offerFor(RecoveryRung rung) => offers.firstWhere(
    (o) => o.rung == rung,
    orElse: () =>
        RecoveryRungOffer.blocked(rung, RecoveryRungBlocked.notOnThisPhoneYet),
  );

  String _reason(AppLocalizations l10n, RecoveryRungBlocked blocked) =>
      switch (blocked) {
        RecoveryRungBlocked.noOtherDevice =>
          l10n.recoveryForkBlockedNoOtherPhone,
        RecoveryRungBlocked.noTrustedMembers =>
          l10n.recoveryForkBlockedNoTrustedMembers,
        RecoveryRungBlocked.noRecoverySheet => l10n.recoveryForkBlockedNoSheet,
        RecoveryRungBlocked.notOnThisPhoneYet => l10n.recoveryForkBlockedNotYet,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final sync = RkScope.of(context).sync;

    // 06 §5 🔒: a user who still has an active phone should *link* rather than
    // ask anybody, "and the screen says so". The line is attached to the
    // trusted-member row and shown only while that is true — said when it is
    // not, it would be a lie about a phone they do not have.
    final canLink = _offerFor(RecoveryRung.anotherDevice).isAvailable;
    final allBlocked = RecoveryRung.forkOrder.every(
      (r) => !_offerFor(r).isAvailable,
    );

    Widget row(RecoveryRung rung) {
      final offer = _offerFor(rung);
      final blocked = offer.blocked;
      return RecoveryRungRow(
        rung: rung,
        title: switch (rung) {
          RecoveryRung.anotherDevice => l10n.recoveryForkOtherPhoneTitle,
          RecoveryRung.trustedMembers => l10n.recoveryForkTrustedTitle,
          RecoveryRung.recoverySheet => l10n.recoveryForkSheetTitle,
          RecoveryRung.platformKeySync => l10n.recoveryForkOtherPhoneTitle,
        },
        body: switch (rung) {
          RecoveryRung.anotherDevice => l10n.recoveryForkOtherPhoneBody,
          RecoveryRung.trustedMembers => l10n.recoveryForkTrustedBody,
          RecoveryRung.recoverySheet => l10n.recoveryForkSheetBody,
          RecoveryRung.platformKeySync => l10n.recoveryForkOtherPhoneBody,
        },
        subLine: rung == RecoveryRung.recoverySheet
            ? l10n.recoveryForkSheetSub
            : null,
        note: rung == RecoveryRung.trustedMembers && canLink
            ? l10n.recoveryForkTrustedLinkInstead
            : null,
        reason: blocked == null ? null : _reason(l10n, blocked),
        onTap: onRung == null ? null : () => onRung!(rung),
      );
    }

    return StreamBuilder<SyncStatus>(
      stream: sync.status,
      initialData: sync.current,
      builder: (context, ss) {
        final offline = ss.data is Offline;
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                RkSpace.s8,
                RkSpace.gutter,
                RkSpace.s6,
              ),
              child: RkFitText(
                l10n.recoveryForkTitle,
                style: text.headlineSmall,
              ),
            ),
            if (offline)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RkSpace.gutter,
                  0,
                  RkSpace.gutter,
                  RkSpace.s4,
                ),
                // A quiet chip, never a blocking banner (07 §1 rule 7): every
                // row below stays live while it shows.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: RkIcon.grid - RkSpace.s2,
                      color: status.muted,
                    ),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(
                      child: RkFitText(
                        l10n.recoveryForkOffline,
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
                    ),
                  ],
                ),
              ),
            for (final rung in RecoveryRung.forkOrder) row(rung),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                RkSpace.s6,
                RkSpace.gutter,
                RkSpace.s4,
              ),
              child: RkFitText(
                l10n.recoveryForkFooter,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
            ),
            // ⚠️ SPEC: DESIGN-PACK R2.1 draws no control here. It is added
            // only for the state the pack does not draw — every rung blocked
            // — because that screen would otherwise be a dead end, which
            // 07 §1 rule 6 🔒 forbids, and 13 §5 F11 already routes
            // `none → S11.8`. It is deliberately absent whenever any way in
            // is still open, so it can never read as an invitation to give
            // up. Reported to the owner as an open item.
            if (allBlocked && onNothingWorked != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RkSpace.gutter,
                  0,
                  RkSpace.gutter,
                  RkSpace.s8,
                ),
                child: TextButton(
                  onPressed: onNothingWorked,
                  child: RkFitText(
                    l10n.recoveryForkNoneAction,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
