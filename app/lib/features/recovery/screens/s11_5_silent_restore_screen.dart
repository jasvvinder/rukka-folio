// S11.5 — Recovery, silent restore (13 §3.2 row S11.5, design R2.0, 04 §7.0).
//
// The common case, and for most people the only recovery screen they will ever
// see: a new phone signed into the same Apple or Google account gets the
// wrapped master key back from the platform key store, and the books simply
// open. The pack is emphatic about what this screen is *not* — no choices, no
// explanation of cryptography, and nothing to read but a tick, a line and a
// count.
//
// While the count runs it is the **determinate loader rule** and never a
// spinner: a 2 px `loader-track` with a `loader-segment`, a value that is
// always supplied, and copy that counts books rather than quoting a
// percentage (11 §4.5 🔒, DESIGN-PACK's loader-rule paragraph).
//
// When rung 0 finds nothing — a different Apple/Google account, or key sync
// switched off (04 §7.0 limits) — the screen says so in one plain sentence and
// hands the person the ladder. 07 §1 rule 6 🔒: no dead ends, and an anxious
// person at a shop counter is the last one to leave staring at a wall.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/seams/recovery_ladder.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../widgets/recovery_parts.dart';

/// The screen rung 0 lands on.
class SilentRestoreScreen extends StatefulWidget {
  /// Creates the screen.
  const SilentRestoreScreen({
    super.key,
    this.ladder,
    this.onDone,
    this.onNeedsFork,
  });

  /// The ladder to watch; defaults to [RecoveryLadderScope]'s.
  final RecoveryLadder? ladder;

  /// Taken when the person leaves for Home with their books open.
  final VoidCallback? onDone;

  /// Taken when rung 0 found nothing and the ladder must be offered (S11.6).
  final VoidCallback? onNeedsFork;

  @override
  State<SilentRestoreScreen> createState() => _SilentRestoreScreenState();
}

class _SilentRestoreScreenState extends State<SilentRestoreScreen> {
  StreamSubscription<RecoveryProgress>? _sub;
  RecoveryProgress? _last;
  bool _stopped = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _watch();
    }
  }

  @override
  void didUpdateWidget(SilentRestoreScreen old) {
    super.didUpdateWidget(old);
    if (widget.ladder != old.ladder) _watch();
  }

  void _watch() {
    _sub?.cancel();
    final ladder = widget.ladder ?? RecoveryLadderScope.maybeOf(context);
    setState(() {
      _last = null;
      _stopped = false;
    });
    if (ladder == null) {
      // Nothing to watch is the same outcome as nothing found: offer the
      // ladder rather than sit on an empty screen.
      setState(() => _stopped = true);
      return;
    }
    _sub = ladder
        .progressOf(RecoveryRung.platformKeySync)
        .listen(
          (p) => setState(() => _last = p),
          // A stream that ends without a finished reading is a rung that did
          // not get there — the failure case, not a silent stall.
          onDone: () => setState(() => _stopped = true),
          onError: (Object _) => setState(() => _stopped = true),
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final last = _last;
    final done = last != null && last.finished;
    final failed = _stopped && !done;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (done) ...[
                    // The tick, the line, the count — in that order, and
                    // nothing else (design R2.0). The icon and the words
                    // carry the state; the success tint only reinforces it
                    // (07 §1 rule 3).
                    Icon(
                      Icons.check_circle_outline,
                      size: RkSpace.s10,
                      color: status.success,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    RkFitText(
                      l10n.recoverySilentTitle,
                      style: text.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    RkFitText(
                      l10n.recoverySilentRestored(last.done),
                      style: text.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: RkSpace.s8),
                    FilledButton(
                      onPressed: widget.onDone,
                      child: RkFitText(
                        l10n.recoverySilentContinue,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ] else if (failed) ...[
                    Icon(Icons.info_outline, color: status.muted),
                    const SizedBox(height: RkSpace.s4),
                    RkFitText(
                      l10n.recoverySilentFailed,
                      style: text.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: RkSpace.s8),
                    FilledButton(
                      onPressed: widget.onNeedsFork,
                      child: RkFitText(
                        l10n.recoverySilentFailedAction,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ] else ...[
                    RkFitText(
                      l10n.recoverySilentRestoring,
                      style: text.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: RkSpace.s6),
                    RecoveryLoaderRule(
                      value: last?.fraction ?? 0,
                      // The count appears with the first reading; until then
                      // the heading's verb carries the wait, which is what
                      // 11 §4.5 asks of an indeterminate moment.
                      countText: last == null
                          ? null
                          : l10n.recoverySilentProgress(
                              '${last.done}',
                              '${last.total}',
                            ),
                      semanticsLabel: l10n.recoverySilentLoader,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
