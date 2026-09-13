// S9.3 Verify member (13 §3.2, 07 §12 🔒, 04 §6.2, §6.3, §6.4) — the
// verifier's side, and the one screen in the ceremony that carries a real
// state machine (13 §4.3).
//
// 🔒 Camera open by default, with **Enter code instead** always on the screen —
// design-system §3.1 rule 7: the QR always has the 8-digit code as an *equal*
// alternative, so a blind user or a broken camera never blocks joining. When
// the camera is unavailable or refused the code path simply takes over; it is
// never a wall (07 §1 rule 6).
//
// 🔒 Remote mode (admin toggle per invite, 04 §6.4) instructs *"Call them and
// ask them to read the code aloud"* — and carries **no share button**. The
// code must reach the verifier over a channel where they recognise the person.
//
// A mismatch leaves this screen for S9.4 and never comes back: 04 §6.3 gives
// the QR path no override. A *wrong typed code* is not a mismatch — it is one
// of three attempts on the nonce (04 §6.3) — and neither is a stranger's QR.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../camera_scanner.dart';
import '../ceremony_repository.dart';
import '../widgets/code_boxes.dart';

/// The states of S9.3 (13 §4.3).
enum VerifyMemberState {
  /// Camera open, waiting for a square (the default, 04 §6.2).
  scanning,

  /// The camera is not available or not permitted; the code path took over.
  cameraBlocked,

  /// The eight boxes, ready for typed digits.
  enteringCode,

  /// A comparison is running.
  checking,

  /// Verified — green tick, restrained (07 §12).
  verified,

  /// Something failed before any comparison; retry.
  error,

  /// This member may not run the ceremony (13 §2.3.1).
  notPermitted,
}

/// S9.3.
class VerifyMemberScreen extends StatefulWidget {
  /// [onMismatch] hands off to S9.4 — a hard fail with no override
  /// (04 §6.3 🔒), so this screen never renders the mismatch itself.
  const VerifyMemberScreen({
    super.key,
    required this.repository,
    required this.scanner,
    this.onMismatch,
    this.onVerified,
    this.offline = false,
  });

  /// The seam over `core_crypto` and the server-relayed keys.
  final VerifyMemberRepository repository;

  /// The camera, behind its own seam.
  final CeremonyScanner scanner;

  /// Called once, when the comparison fails (04 §6.3).
  final VoidCallback? onMismatch;

  /// Called when the ceremony completes.
  final VoidCallback? onVerified;

  /// No connection: the relayed keys cannot be fetched, so this one check
  /// genuinely waits — with the path back stated (07 §1 rule 6).
  final bool offline;

  @override
  State<VerifyMemberScreen> createState() => _VerifyMemberScreenState();
}

class _VerifyMemberScreenState extends State<VerifyMemberScreen> {
  final _typed = TextEditingController();
  StreamSubscription<String>? _scans;
  VerifyMemberState _state = VerifyMemberState.scanning;
  CameraStatus _camera = CameraStatus.ready;

  /// The line under the boxes: wrong code, expired nonce, dead nonce, a
  /// stranger's QR, or a failed call. Never a raw error (07 §1 rule 12).
  String? Function(AppLocalizations)? _notice;

  @override
  void initState() {
    super.initState();
    if (!widget.repository.canVerify) {
      _state = VerifyMemberState.notPermitted;
      return;
    }
    _typed.addListener(_onTyped);
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    unawaited(_scans?.cancel());
    unawaited(widget.scanner.dispose());
    _typed
      ..removeListener(_onTyped)
      ..dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    final status = await widget.scanner.start();
    if (!mounted) return;
    setState(() {
      _camera = status;
      // No camera is not a dead end: the equal alternative simply becomes the
      // path (design-system §3.1 rule 7 🔒).
      _state = status == CameraStatus.ready
          ? VerifyMemberState.scanning
          : VerifyMemberState.cameraBlocked;
    });
    if (status != CameraStatus.ready) return;
    _scans = widget.scanner.codes.listen(_onScanned);
  }

  void _onTyped() {
    if (_notice == null) return;
    setState(() => _notice = null);
  }

  Future<void> _onScanned(String text) async {
    if (_state == VerifyMemberState.checking ||
        _state == VerifyMemberState.verified) {
      return;
    }
    await _run(() => widget.repository.verifyScanned(text));
  }

  Future<void> _checkTyped() async {
    if (_typed.text.length != ceremonyCodeLength) return;
    await _run(() => widget.repository.verifyTyped(_typed.text));
  }

  Future<void> _run(Future<CeremonyResult> Function() call) async {
    final previous = _state;
    setState(() {
      _state = VerifyMemberState.checking;
      _notice = null;
    });
    final CeremonyResult result;
    try {
      result = await call();
    } on NotACeremonyCode {
      if (!mounted) return;
      // Not a mismatch: nothing was compared, so nothing is logged and the
      // camera keeps looking (04 §6.3 applies to a real ceremony payload).
      setState(() {
        _state = previous;
        _notice = (l10n) => l10n.ceremonyVerifyScanNotACode;
      });
      return;
    } on CeremonyFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _state = VerifyMemberState.error;
        _notice = (l10n) =>
            e.offline ? l10n.ceremonyVerifyOffline : l10n.ceremonyVerifyError;
      });
      return;
    }
    if (!mounted) return;
    switch (result) {
      case CeremonyVerified():
        unawaited(_scans?.cancel());
        setState(() => _state = VerifyMemberState.verified);
      case CeremonyMismatch():
        // Hard fail. Off this screen, no override, already logged.
        widget.onMismatch?.call();
      case CodeWrong(:final attemptsLeft):
        // Clear BEFORE the notice, never after: the field's own listener wipes
        // the notice on every edit, so clearing afterwards erased the very
        // line that says how many tries are left.
        _typed.clear();
        setState(() {
          _state = VerifyMemberState.enteringCode;
          _notice = (l10n) => l10n.ceremonyVerifyWrong(attemptsLeft);
        });
      case CodeExpired():
        setState(() {
          _state = VerifyMemberState.enteringCode;
          _notice = (l10n) => l10n.ceremonyVerifyExpired;
        });
      case CodeExhausted():
        setState(() {
          _state = VerifyMemberState.enteringCode;
          _notice = (l10n) => l10n.ceremonyVerifyExhausted;
        });
    }
  }

  void _showCodePath() => setState(() {
    _state = VerifyMemberState.enteringCode;
    _notice = null;
  });

  void _showCamera() => setState(() {
    _state = _camera == CameraStatus.ready
        ? VerifyMemberState.scanning
        : VerifyMemberState.cameraBlocked;
    _notice = null;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ceremonyVerifyTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter)
              .copyWith(top: RkSpace.s4, bottom: RkSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.repository.mode == CeremonyMode.remote)
                const _RemoteInstruction(),
              if (widget.offline) const _OfflineNotice(),
              ..._bodyFor(l10n),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bodyFor(AppLocalizations l10n) => switch (_state) {
    VerifyMemberState.notPermitted => [
      _Notice(
        icon: Icons.lock_outline,
        text: l10n.ceremonyVerifyReadOnly,
        tone: _Tone.locked,
      ),
    ],
    VerifyMemberState.verified => [
      _Verified(name: widget.repository.memberName, onDone: widget.onVerified),
    ],
    VerifyMemberState.checking => [
      const SizedBox(height: RkSpace.s8),
      Semantics(
        liveRegion: true,
        child: Text(
          l10n.ceremonyVerifyChecking,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    ],
    VerifyMemberState.error => [
      _Notice(
        icon: Icons.error_outline,
        text: _notice?.call(l10n) ?? l10n.ceremonyVerifyError,
        tone: _Tone.warning,
      ),
      const SizedBox(height: RkSpace.s4),
      FilledButton(
        onPressed: _showCodePath,
        child: Text(l10n.ceremonyShowRetry),
      ),
    ],
    VerifyMemberState.scanning => [
      _Viewfinder(child: widget.scanner.buildPreview(context)),
      const SizedBox(height: RkSpace.s4),
      Text(
        l10n.ceremonyVerifyCameraHint,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      if (_notice != null) ...[
        const SizedBox(height: RkSpace.s3),
        _Notice(
          icon: Icons.qr_code_2_outlined,
          text: _notice!(l10n)!,
          tone: _Tone.warning,
        ),
      ],
      const SizedBox(height: RkSpace.s6),
      // Always on the screen — never behind a menu, never only after the
      // camera fails (design-system §3.1 rule 7 🔒).
      OutlinedButton(
        onPressed: _showCodePath,
        child: Text(l10n.ceremonyVerifyCameraEnterCode),
      ),
    ],
    VerifyMemberState.cameraBlocked => [
      _Notice(
        icon: Icons.no_photography_outlined,
        text: _camera == CameraStatus.denied
            ? l10n.ceremonyVerifyCameraDenied
            : l10n.ceremonyVerifyCameraUnavailable,
        tone: _Tone.info,
      ),
      const SizedBox(height: RkSpace.s4),
      ..._codeEntry(l10n, offerCamera: false),
    ],
    VerifyMemberState.enteringCode => _codeEntry(
      l10n,
      offerCamera: _camera == CameraStatus.ready,
    ),
  };

  List<Widget> _codeEntry(AppLocalizations l10n, {required bool offerCamera}) {
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return [
      Text(l10n.ceremonyVerifyCodeLabel, style: theme.textTheme.titleLarge),
      const SizedBox(height: RkSpace.s2),
      Text(
        l10n.ceremonyVerifyCodeHint,
        style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
      ),
      const SizedBox(height: RkSpace.s4),
      RkCodeField(
        controller: _typed,
        label: l10n.ceremonyVerifyCodeLabel,
        autofocus: true,
        onSubmitted: (_) => unawaited(_checkTyped()),
      ),
      if (_notice != null) ...[
        const SizedBox(height: RkSpace.s3),
        _Notice(
          icon: Icons.error_outline,
          text: _notice!(l10n)!,
          tone: _Tone.warning,
        ),
      ],
      const SizedBox(height: RkSpace.s4),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _typed,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.length == ceremonyCodeLength
              ? () => unawaited(_checkTyped())
              : null,
          child: Text(l10n.ceremonyVerifyCheck),
        ),
      ),
      if (offerCamera) ...[
        const SizedBox(height: RkSpace.s3),
        TextButton(
          onPressed: _showCamera,
          child: Text(l10n.ceremonyVerifyCodeUseCamera),
        ),
      ],
    ];
  }
}

/// 04 §6.4 🔒, verbatim — with the reason beside it, and no share button.
class _RemoteInstruction extends StatelessWidget {
  const _RemoteInstruction();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: status.sunk,
          borderRadius: BorderRadius.circular(RkRadius.md),
          border: Border(
            left: BorderSide(color: status.info, width: RkRadius.ruleLeftWidth),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.call_outlined, size: RkIcon.grid, color: status.info),
              const SizedBox(width: RkSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.ceremonyVerifyRemoteInstruction,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    Text(
                      l10n.ceremonyVerifyRemoteWhy,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: status.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: RkSpace.s4),
    child: _Notice(
      icon: Icons.cloud_off_outlined,
      text: AppLocalizations.of(context).ceremonyVerifyOffline,
      tone: _Tone.info,
    ),
  );
}

/// The camera frame — the screen owns it, so every scanner implementation
/// sits in the same square.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    // Capped: a square viewfinder the full width of the phone pushes
    // *Enter code instead* — which 04 §6.2 🔒 requires on the screen — past the
    // fold, and at 200 % text scale far past it. Two-fifths of the height is
    // still a big target to aim a phone with.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.4;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: status.sunk,
            borderRadius: BorderRadius.circular(RkRadius.md),
            border: Border.all(color: status.hairline, width: RkIcon.stroke),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(RkRadius.md),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Success: a tick, the word, the name. Restrained — no confetti (07 §12).
class _Verified extends StatelessWidget {
  const _Verified({required this.name, required this.onDone});

  final String name;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RkSpace.s8),
        Icon(Icons.verified_outlined, size: RkSpace.s12, color: status.success),
        const SizedBox(height: RkSpace.s4),
        Semantics(
          liveRegion: true,
          child: Text(
            // The word carries the meaning; the green never carries it alone
            // (07 §1 rule 3).
            l10n.ceremonyVerifySuccessTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(color: status.success),
          ),
        ),
        const SizedBox(height: RkSpace.s3),
        Text(
          l10n.ceremonyVerifySuccessBody(name),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: RkSpace.s8),
        FilledButton(
          onPressed: onDone,
          child: Text(l10n.ceremonyVerifySuccessDone),
        ),
      ],
    );
  }
}

enum _Tone { info, warning, locked }

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.tone});

  final IconData icon;
  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final colour = switch (tone) {
      _Tone.info => status.info,
      _Tone.warning => status.warning,
      _Tone.locked => status.locked,
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: RkIcon.grid, color: colour),
          const SizedBox(width: RkSpace.s2),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
