// S11.3 — Recovery, the paper sheet (13 §3.2 row S11.3, design R2.4,
// 04 §7.4 🔒).
//
// Rung 3: the one-page document the user was told to keep with the Aadhaar and
// the LIC papers. The screen has two ways in — scan the square, or type the
// code — and the pack is explicit that the **failure** state is part of the
// design: *"That code didn't work"* with the two likely causes stated plainly,
// **never a blank error**.
//
// **No camera package is added.** The scan sits behind the seam like every
// other device capability in this repo, and its fake answers
// [RecoveryScanOutcome.unavailable] — which is this build's truth. Choosing a
// scanner package is an owner ruling (the ADR 2026-09-12e precedent), so the
// screen states the limitation and puts the whole weight on the typed path,
// which is built for real: 04 §7.4's Crockford Base32 in groups of four, with
// the one failure this phone can name by itself caught before the server is
// asked ([RecoverySheetCode.parse]).
//
// ⚠️ SPEC: 04 §7.4 🔒 says the typed fallback carries a "2-char checksum" but
// nowhere says which checksum. Nothing here verifies one — inventing an
// algorithm would put a wrong red line under a correct code. A code whose
// characters are all legal goes to the seam, and the failure state states both
// of the pack's causes because the server cannot tell them apart either.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/money_format.dart' show groupIndian;
import '../../../shared/seams/recovery_ladder.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../widgets/recovery_parts.dart';

/// Where the screen stands.
enum _Step {
  /// Both ways in are offered.
  choose,

  /// The grouped character field is open.
  typing,

  /// The seam refused the code — R2.4's failure state.
  refused,

  /// The key is back; the entries are coming.
  restoring,
}

/// The recovery-sheet screen.
class RecoverySheetScreen extends StatefulWidget {
  /// Creates the screen. [sheet] defaults to [RecoverySheetScope]'s.
  const RecoverySheetScreen({
    super.key,
    this.sheet,
    this.onBack,
    this.onRestored,
  });

  /// The seam to ask.
  final RecoverySheetEntry? sheet;

  /// Back to the fork (S11.6). 07 §1 rule 6 🔒: no dead ends.
  final VoidCallback? onBack;

  /// Where a finished restore lands — Home, in the shell.
  final VoidCallback? onRestored;

  @override
  State<RecoverySheetScreen> createState() => _RecoverySheetScreenState();
}

class _RecoverySheetScreenState extends State<RecoverySheetScreen> {
  final _controller = TextEditingController();
  _Step _step = _Step.choose;
  bool _busy = false;
  bool _failed = false;
  RecoveryScanOutcome? _scan;
  RecoveryProgress? _progress;
  StreamSubscription<RecoveryProgress>? _sub;

  RecoverySheetEntry? get _seam =>
      widget.sheet ?? RecoverySheetScope.maybeOf(context);

  /// The typed code, or null when it is not a sheet code at all.
  RecoverySheetCode? get _code => _controller.text.trim().isEmpty
      ? null
      : RecoverySheetCode.parse(_controller.text);

  @override
  void didUpdateWidget(RecoverySheetScreen old) {
    super.didUpdateWidget(old);
    // A new seam is a new attempt. Without this the screen would keep the
    // first one's step for the life of the element — stale the moment the
    // shell installs a live sheet over a screen built before one existed,
    // and the same staleness S11.6 guards against.
    if (widget.sheet != old.sheet) {
      _sub?.cancel();
      _sub = null;
      _controller.clear();
      setState(() {
        _step = _Step.choose;
        _busy = false;
        _failed = false;
        _scan = null;
        _progress = null;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scanSheet() async {
    final seam = _seam;
    if (seam == null || _busy) return;
    setState(() => _busy = true);
    try {
      final outcome = await seam.scanSheet();
      if (!mounted) return;
      setState(() => _scan = outcome);
      if (outcome == RecoveryScanOutcome.verified) _restore();
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final seam = _seam;
    final code = _code;
    if (seam == null || code == null || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await seam.submit(code);
      if (!mounted) return;
      _restore();
    } on RecoverySheetRejected {
      // R2.4's failure state — never a blank error, and the typed code is
      // kept so the person can compare it with the page group by group
      // (13 §8, interruption never discards work).
      if (mounted) setState(() => _step = _Step.refused);
    } on Object {
      // The attempt could not be made at all, which is a different thing from
      // a code that did not work (13 §4.3 error-with-retry).
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _restore() {
    final seam = _seam;
    if (seam == null) return;
    setState(() => _step = _Step.restoring);
    _sub?.cancel();
    _sub = seam.restore().listen((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_failed) {
      return Scaffold(
        body: SafeArea(
          child: RkErrorState(
            text: l10n.recoverySheetError,
            retryLabel: l10n.recoverySheetRetry,
            onRetry: () => setState(() => _failed = false),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: switch (_step) {
          _Step.restoring => _Restoring(
            progress: _progress,
            onRestored: widget.onRestored,
          ),
          _Step.refused => _Refused(
            onRetry: () => setState(() => _step = _Step.typing),
            onBack: widget.onBack,
          ),
          _Step.choose || _Step.typing => _Entry(
            step: _step,
            controller: _controller,
            code: _code,
            busy: _busy,
            scan: _scan,
            onScan: _scanSheet,
            onType: () => setState(() => _step = _Step.typing),
            onChanged: () => setState(() {}),
            onSubmit: _submit,
            onBack: widget.onBack,
          ),
        },
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.step,
    required this.controller,
    required this.code,
    required this.busy,
    required this.scan,
    required this.onScan,
    required this.onType,
    required this.onChanged,
    required this.onSubmit,
    required this.onBack,
  });

  final _Step step;
  final TextEditingController controller;
  final RecoverySheetCode? code;
  final bool busy;
  final RecoveryScanOutcome? scan;
  final VoidCallback onScan;
  final VoidCallback onType;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final sync = RkScope.of(context).sync;
    final typing = step == _Step.typing;
    final unavailable = scan == RecoveryScanOutcome.unavailable;
    final mismatch = scan == RecoveryScanOutcome.mismatch;
    final typed = controller.text.trim().isNotEmpty;
    final malformed = typed && code == null;

    return StreamBuilder<SyncStatus>(
      stream: sync.status,
      initialData: sync.current,
      builder: (context, ss) => ListView(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s8,
          RkSpace.gutter,
          RkSpace.s8,
        ),
        children: [
          RkFitText(l10n.recoverySheetTitle, style: text.headlineSmall),
          const SizedBox(height: RkSpace.s4),
          // The pack's "small illustration reminding them what the sheet
          // looks like". There is no artwork in the bundle, so it is drawn
          // from the icon grid over the sunk surface — a true placeholder, and
          // the sentence beneath does the describing either way.
          Container(
            height: RkSpace.s12 + RkSpace.s8,
            decoration: BoxDecoration(
              color: status.sunk,
              borderRadius: BorderRadius.circular(RkRadius.md),
              border: Border.all(color: status.hairline),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.description_outlined,
              size: RkIcon.grid + RkSpace.s6,
              color: status.muted,
            ),
          ),
          const SizedBox(height: RkSpace.s3),
          RkFitText(
            l10n.recoverySheetWhat,
            style: text.bodyMedium?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s6),
          if (unavailable)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: RkIcon.grid - RkSpace.s2,
                  color: status.locked,
                ),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: RkFitText(
                    l10n.recoverySheetScanUnavailable,
                    style: text.bodyMedium?.copyWith(color: status.locked),
                  ),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: busy ? null : onScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: RkFitText(
                l10n.recoverySheetScanAction,
                textAlign: TextAlign.center,
              ),
            ),
          if (mismatch) ...[
            const SizedBox(height: RkSpace.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: status.danger),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: RkFitText(
                    l10n.recoverySheetScanMismatch,
                    style: text.bodyMedium?.copyWith(color: status.danger),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: RkSpace.s4),
          if (!typing)
            TextButton(
              onPressed: onType,
              child: RkFitText(
                l10n.recoverySheetTypeAction,
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.recoverySheetTypeLabel,
                helperText: l10n.recoverySheetTypeHint,
                helperMaxLines: 3,
                errorText: malformed ? l10n.recoverySheetTypeInvalid : null,
                errorMaxLines: 4,
              ),
              style: text.bodyLarge?.copyWith(fontFeatures: RkType.tabular),
            ),
            if (code != null) ...[
              const SizedBox(height: RkSpace.s2),
              // Read back in the sheet's own groups of four, so the person can
              // check it against the page without counting characters.
              RkFitText(
                code!.grouped,
                style: text.bodyMedium?.copyWith(
                  color: status.muted,
                  fontFeatures: RkType.tabular,
                ),
              ),
            ],
            const SizedBox(height: RkSpace.s4),
            Semantics(
              button: true,
              enabled: code != null && !busy,
              // The reason travels with the control, so a screen reader hears
              // *why* and not merely "dimmed" (13 §4.3).
              hint: malformed ? l10n.recoverySheetTypeInvalid : null,
              child: FilledButton(
                onPressed: code == null || busy ? null : onSubmit,
                child: RkFitText(
                  l10n.recoverySheetSubmit,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          if (ss.data is Offline) ...[
            const SizedBox(height: RkSpace.s3),
            Row(
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
                    l10n.recoverySheetOffline,
                    style: text.bodySmall?.copyWith(color: status.muted),
                  ),
                ),
              ],
            ),
          ],
          if (onBack != null) ...[
            const SizedBox(height: RkSpace.s4),
            TextButton(
              onPressed: onBack,
              child: RkFitText(
                l10n.recoveryAskBack,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// R2.4's failure state: the heading, then **both** likely causes in plain
/// words, then back to the field with what was typed still in it.
class _Refused extends StatelessWidget {
  const _Refused({required this.onRetry, required this.onBack});

  final VoidCallback onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
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
            Icon(Icons.error_outline, color: status.danger),
            const SizedBox(width: RkSpace.s2),
            Expanded(
              child: RkFitText(
                l10n.recoverySheetFailedTitle,
                style: text.titleLarge?.copyWith(color: status.danger),
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s4),
        RkFitText(l10n.recoverySheetFailedCauseNew, style: text.bodyMedium),
        const SizedBox(height: RkSpace.s3),
        RkFitText(l10n.recoverySheetFailedCauseTypo, style: text.bodyMedium),
        const SizedBox(height: RkSpace.s6),
        FilledButton(
          onPressed: onRetry,
          child: RkFitText(
            l10n.recoverySheetFailedAction,
            textAlign: TextAlign.center,
          ),
        ),
        if (onBack != null) ...[
          const SizedBox(height: RkSpace.s4),
          TextButton(
            onPressed: onBack,
            child: RkFitText(l10n.recoveryAskBack, textAlign: TextAlign.center),
          ),
        ],
      ],
    );
  }
}

class _Restoring extends StatelessWidget {
  const _Restoring({required this.progress, required this.onRestored});

  final RecoveryProgress? progress;
  final VoidCallback? onRestored;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final done = progress?.finished ?? false;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RkFitText(
              done ? l10n.recoverySheetDoneTitle : l10n.recoverySheetTitle,
              style: text.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RkSpace.s6),
            RecoveryLoaderRule(
              value: progress?.fraction ?? 0,
              // Until the first reading there is no honest count to draw; the
              // heading's verb carries the moment (11 §4.5).
              countText: progress == null
                  ? null
                  : l10n.recoverySheetRestoring(
                      groupIndian('${progress!.done}'),
                      groupIndian('${progress!.total}'),
                    ),
              semanticsLabel: l10n.recoverySheetRestoreLoader,
            ),
            if (done && onRestored != null) ...[
              const SizedBox(height: RkSpace.s6),
              FilledButton(
                onPressed: onRestored,
                child: RkFitText(
                  l10n.recoverySheetDoneAction,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
