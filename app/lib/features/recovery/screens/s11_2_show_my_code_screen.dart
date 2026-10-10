// S11.2 *Show my code* — the fresh phone's candidate key as a square code, for
// a trusted member's phone to scan on S11.7 before they approve (ADR
// 2026-09-13c ruling 3 🔒, ADR 2026-09-24b §1 🔒, 04 §7.3 🔒 rung 2).
//
// ⚠️ SPEC: **no canvas draws this step** (ADR 2026-09-13c Open 2 — the S11.2
// / S11.7 ceremony states are a 07/13 design gap, joining ADR 2026-09-06's
// *2 of 3 approved*). It follows the nearest drawn screen, S9.2 *Show my code*
// (07 §12 🔒): a huge square from the first frame, sized against the viewport
// height so the next step stays on the first screen, and the channel rule said
// out loud rather than left as an absent share button (04 §6.4 🔒). Two things
// are deliberately *not* carried over from S9.2:
//   * **no eight digit boxes and no countdown** — ruling 2 🔒 admits no code
//     path at recovery, so there is nothing to read aloud, and the candidate
//     key lives until the attempt closes (ADR 2026-09-24b §1), not for a
//     nonce's ten minutes;
//   * **no regenerate** — the key is the attempt's; a new key is a new
//     attempt, which only S11.2's own refresh may open.
//
// What is drawn is only ever the key this phone **holds** ([RecoveryMyCode],
// `my_code.dart`). When it holds none for this attempt the screen says so in
// words, draws no square, and offers the way back — never the server's copy.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../../ceremony/widgets/qr_view.dart';
import '../my_code.dart';

/// S11.2's *Show my code*.
class RecoveryShowMyCodeScreen extends StatefulWidget {
  /// Creates the screen. [myCode] defaults to [RecoveryMyCodeScope]'s; with
  /// neither, the screen says this phone cannot show its code yet.
  const RecoveryShowMyCodeScreen({
    super.key,
    this.myCode,
    this.onBack,
    this.encode = QrModules.of,
  });

  /// The producer of the code.
  final RecoveryMyCode? myCode;

  /// Back to S11.2. Null pops the route this screen was pushed on.
  final VoidCallback? onBack;

  /// How the payload becomes a module matrix; swapped in tests.
  final QrModules Function(String payload) encode;

  @override
  State<RecoveryShowMyCodeScreen> createState() =>
      _RecoveryShowMyCodeScreenState();
}

class _RecoveryShowMyCodeScreenState extends State<RecoveryShowMyCodeScreen> {
  RecoveryMyCodeRead? _read;
  QrModules? _modules;
  bool _failed = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final seam = widget.myCode ?? RecoveryMyCodeScope.maybeOf(context);
    setState(() {
      _failed = false;
      _read = null;
      _modules = null;
    });
    if (seam == null) {
      setState(() => _read = const RecoveryMyCodeUnavailable());
      return;
    }
    try {
      final read = await seam.read();
      if (!mounted) return;
      setState(() {
        _read = read;
        _modules = switch (read) {
          RecoveryMyCodeShown(:final qrText) => widget.encode(qrText),
          _ => null,
        };
      });
    } on Object {
      // Held in a field, not a FutureBuilder: a key store that fails must
      // land on the retryable error, never an unhandled framework error.
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _back() {
    final back = widget.onBack;
    if (back != null) {
      back();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final read = _read;
    return Scaffold(
      appBar: AppBar(title: RkFitText(l10n.recoveryShowTitle)),
      body: SafeArea(
        child: _failed
            ? _ErrorWithBack(onRetry: _load, onBack: _back)
            : switch (read) {
                null => RkSkeleton(label: l10n.recoveryShowLoading, rows: 3),
                RecoveryMyCodeShown() => _Shown(modules: _modules!),
                RecoveryMyCodeNotHeld() => _NoCode(
                  icon: Icons.phonelink_erase_outlined,
                  text: l10n.recoveryShowNotHeld,
                  onBack: _back,
                ),
                RecoveryMyCodeUnavailable() => _NoCode(
                  icon: Icons.lock_outline,
                  text: l10n.recoveryShowUnavailable,
                  onBack: _back,
                ),
              },
      ),
    );
  }
}

class _Shown extends StatelessWidget {
  const _Shown({required this.modules});

  final QrModules modules;

  /// S9.2's rule: the full column width, capped against the viewport height
  /// so the channel rule below stays on the first screen.
  static double _qrSide(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = media.width - RkSpace.gutter * 2;
    final cap = media.height * 0.42;
    return width < cap ? width : cap;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final sync = RkScope.of(context).sync;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s4,
        RkSpace.gutter,
        RkSpace.s8,
      ),
      children: [
        RkFitText(l10n.recoveryShowBody, style: text.bodyLarge),
        const SizedBox(height: RkSpace.s4),
        Center(
          child: SizedBox.square(
            dimension: _qrSide(context),
            child: RkQrView(
              modules: modules,
              semanticsLabel: l10n.recoveryShowQrSemantics,
            ),
          ),
        ),
        const SizedBox(height: RkSpace.s6),
        // Why there is no share button, said out loud (04 §6.4 🔒).
        DecoratedBox(
          decoration: BoxDecoration(
            color: status.sunk,
            borderRadius: BorderRadius.circular(RkRadius.md),
            border: Border(
              left: BorderSide(
                color: status.warning,
                width: RkRadius.ruleLeftWidth,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.cardPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  size: RkIcon.grid,
                  color: status.warning,
                ),
                const SizedBox(width: RkSpace.s3),
                Expanded(
                  child: RkFitText(
                    l10n.recoveryShowChannelRule,
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        // The code is drawn from what this phone holds, so being offline
        // stops nothing — a quiet chip, never a banner (07 §1 rule 7).
        StreamBuilder<SyncStatus?>(
          // Null while the engine is held before S0.2: no chip, and nothing
          // disabled (ADR 2026-10-10 §2 🔒).
          stream: sync.chipStatus,
          initialData: sync.chipCurrent,
          builder: (context, ss) => ss.data is! Offline
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: RkSpace.s4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: RkIcon.grid - RkSpace.s2,
                        color: status.muted,
                      ),
                      const SizedBox(width: RkSpace.s2),
                      Expanded(
                        child: RkFitText(
                          l10n.recoveryShowOffline,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// No code to draw: the reason in words beside an icon (07 §1 rule 3), and
/// the way back under it (07 §1 rule 6 🔒 — no dead ends).
class _NoCode extends StatelessWidget {
  const _NoCode({required this.icon, required this.text, required this.onBack});

  final IconData icon;
  final String text;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s8,
        RkSpace.gutter,
        RkSpace.s8,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: RkIcon.grid, color: status.locked),
            const SizedBox(width: RkSpace.s3),
            Expanded(
              child: RkFitText(
                text,
                style: theme.bodyLarge?.copyWith(color: status.locked),
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s6),
        FilledButton(
          onPressed: onBack,
          child: RkFitText(l10n.recoveryShowBack, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

class _ErrorWithBack extends StatelessWidget {
  const _ErrorWithBack({required this.onRetry, required this.onBack});

  final Future<void> Function() onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RkErrorState(
            text: l10n.recoveryShowError,
            retryLabel: l10n.recoveryShowRetry,
            onRetry: () => unawaited(onRetry()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: TextButton(
            onPressed: onBack,
            child: RkFitText(
              l10n.recoveryShowBack,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
